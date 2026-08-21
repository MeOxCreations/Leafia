--!strict
-- Autorite SERVEUR sur la tondeuse PORTEE. Meme mecanique que l'echelle, en plus simple : a la prise on desancre
-- la tondeuse et on SOUDE sa RootPart au HRP du porteur. La soudure replique la position a tout le monde, sans
-- flot de remotes et sans que la tondeuse puisse tomber ou se decrocher.
--
-- CE SERVICE NE COUPE RIEN. L'herbe est CLIENTE (chaque joueur fabrique la sienne), donc la coupe l'est aussi :
-- c'est MowController qui appelle GrassZoneController.mowAt. Ici on ne decide que d'UNE chose : qui porte quoi.
--
-- L'offset de portage est CALCULE ici sur la geometrie du modele, jamais envoye par le client : il n'y a donc
-- rien a valider et rien a falsifier. Il n'est pas non plus regle a l'oeil dans la config -- voir carryC0.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local MowConfigs = require(ReplicatedStorage.Modules.Configs.MowConfigs)

local MowService = {}

type PartState = { anchored: boolean, canCollide: boolean }
type CarryState = {
	owner: Player,
	parts: { [BasePart]: PartState },
	weld: Weld?,
	hold: AnimationTrack?, -- pose "mains sur le guidon", figee au marqueur. Coupee a la repose.
	holdGuard: RBXScriptConnection?, -- filet : rattrape la pose si le marqueur est rate (image perdue)
	humanoid: Humanoid?, -- porteur, garde pour rendre le saut a la repose
	jumpWasEnabled: boolean, -- etat du saut AVANT la prise : on restaure, on ne force pas a true
	jumpHeight: number, -- valeurs REELLES d'avant, pas les defauts Roblox : un autre systeme a pu les changer
	jumpPower: number,
}

-- On cle la pose JUSTE avant la derniere image, jamais dessus : a la derniere image pile, la piste bouclee
-- repart au debut avant qu'on ait pu la figer.
local HOLD_EPSILON = 0.001
local ANIMATOR_TIMEOUT = 5 -- l'Animator d'un PERSONNAGE arrive apres l'Humanoid (contrairement a un modele de map)

local carried: { [Model]: CarryState } = {}

local function rootOf(model: Model): BasePart?
	local root = model.PrimaryPart or model:FindFirstChild(MowConfigs.ROOT_NAME)
	return if root and root:IsA("BasePart") then root else nil
end

-- Une tondeuse VALIDE : un Model au bon nom, avec une racine. On ne fait confiance a aucun nom envoye par le
-- client -- c'est l'instance elle-meme qu'on verifie.
local function isMower(inst: Instance?): Model?
	if not (inst and inst:IsA("Model") and inst.Name == MowConfigs.MODEL_NAME) then
		return nil
	end
	local model = inst :: Model
	if not model:IsDescendantOf(Workspace) or not rootOf(model) then
		return nil
	end
	return model
end

-- Une SEULE Instance Animation pour tout le serveur : c'est un porteur d'ID, pas un etat. La creer par prise
-- multiplierait les instances sans rien apporter.
local holdAnim: Animation? = nil
local function getHoldAnimation(): Animation
	if not holdAnim then
		local a = Instance.new("Animation")
		a.Name = "LeafiaMowerHold"
		a.AnimationId = MowConfigs.HOLD_ANIM_ID
		holdAnim = a
	end
	return holdAnim :: Animation
end

-- POSE DE MAINTIEN : le joueur attrape le guidon, et TIENT la pose tant qu'il pousse.
--
-- Jouee cote SERVEUR -> elle se replique a tous, comme les animations de l'echelle.
--
-- Priorite Action : en dessous (Movement) la marche l'ecraserait. L'animation ne cle QUE le torse, la tete et les
-- bras -- si elle clait aussi les jambes, Action les figerait et le joueur glisserait sans marcher.
--
-- Looped = TRUE et non false : une piste non bouclee se RELACHE en arrivant au bout et la pose saute. On la fige
-- donc au marqueur (vitesse 0) AVANT la fin, et elle ne boucle jamais puisqu'elle n'avance plus.
local function playHold(character: Model, state: CarryState)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	-- A CharacterAdded l'Animator arrive quelques frames apres l'Humanoid : un FindFirstChildOfClass nu rend nil.
	local animator = humanoid:FindFirstChildOfClass("Animator")
		or humanoid:WaitForChild("Animator", ANIMATOR_TIMEOUT)
	if not (animator and animator:IsA("Animator")) then
		warn("[MowService] Pas d'Animator sur le porteur : pose de maintien non jouee.")
		return
	end

	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(getHoldAnimation())
	end)
	if not ok or typeof(result) ~= "Instance" then
		warn(`[MowService] Pose de maintien non chargeable ({MowConfigs.HOLD_ANIM_ID}).`)
		return
	end

	local track = result :: AnimationTrack
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:GetMarkerReachedSignal(MowConfigs.HOLD_READY_EVENT):Connect(function()
		track:AdjustSpeed(0) -- mains sur le guidon : on TIENT
	end)
	track:Play(MowConfigs.HOLD_FADE)
	track.TimePosition = 0
	state.hold = track

	-- FILET. Le marqueur suffit tant que les images tombent bien, mais une seule image perdue et la tete de
	-- lecture le DEPASSE sans que le signal serve a rien : la piste boucle alors, et la pose repart du debut.
	-- Symptome vecu : ca marche la plupart du temps, et parfois non. On surveille donc aussi la position, et
	-- on la cle juste avant la fin. Celui des deux qui arrive en premier gagne, l'autre n'a plus rien a faire.
	state.holdGuard = RunService.Heartbeat:Connect(function()
		if track.Speed == 0 then
			-- Le marqueur a fait le travail : plus rien a surveiller.
			if state.holdGuard then
				state.holdGuard:Disconnect()
				state.holdGuard = nil
			end
			return
		end
		local length = track.Length
		if length > 0 and track.TimePosition >= length - HOLD_EPSILON then
			track.TimePosition = length - HOLD_EPSILON
			track:AdjustSpeed(0)
		end
	end)
end

local function stopHold(state: CarryState)
	if state.holdGuard then
		state.holdGuard:Disconnect()
		state.holdGuard = nil
	end
	local track = state.hold
	if not track then
		return
	end
	state.hold = nil
	-- pcall : on passe aussi par ici quand le joueur MEURT en poussant. Son Animator est alors deja detruit, et
	-- couper une piste morte leve. Ce n'est pas un cas anormal, donc on ne warn pas -- on nettoie, point.
	pcall(function()
		-- On rend la vitesse AVANT d'arreter : une piste figee a 0 ne fondrait pas, elle disparaitrait d'un coup.
		track:AdjustSpeed(1)
		track:Stop(MowConfigs.HOLD_FADE)
	end)
end

-- SAUT COUPE pendant le portage. On pousse une tondeuse, on ne saute pas avec.
-- On MEMORISE l'etat d'avant et on le restaure, plutot que de forcer `true` a la repose : un autre systeme peut
-- avoir de bonnes raisons d'avoir deja coupe le saut (une cinematique, un dialogue), et le lui rendre de force
-- casserait le sien.
-- DEUX gestes explicites plutot qu'un booleen : bloquer et rendre ne sont PAS symetriques. Rendre doit toujours
-- remettre les VALEURS d'origine, meme si le saut etait deja interdit avant la prise -- sinon un joueur qui prend
-- la tondeuse pendant un dialogue garderait JumpHeight a zero pour toujours.
local function blockJump(state: CarryState)
	local humanoid = state.humanoid
	if not (humanoid and humanoid.Parent) then
		return
	end
	-- LES PROPRIETES FONT LE TRAVAIL : elles se REPLIQUENT. `SetStateEnabled`, lui, n'agit que sur la machine
	-- qui l'appelle -- or c'est le CLIENT qui simule le personnage, pas le serveur. Le couper cote serveur seul
	-- laissait donc sauter, vu a l'ecran.
	-- On met les DEUX a zero : laquelle compte depend de UseJumpPower, et ce reglage peut changer sans nous.
	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0
	-- En plus, pas a la place : coupe aussi un saut deja demande du cote serveur.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

local function restoreJump(state: CarryState)
	local humanoid = state.humanoid
	if not (humanoid and humanoid.Parent) then
		return
	end
	humanoid.JumpHeight = state.jumpHeight
	humanoid.JumpPower = state.jumpPower
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, state.jumpWasEnabled)
end

-- MESURE DE LA MACHINE, en une passe : son point le plus BAS, et de combien elle depasse EN ARRIERE de sa racine.
--
-- On ne compte que les parts VISIBLES : la CutZone et les autres zones logiques ne sont pas des pieces de la
-- machine, et une seule d'entre elles posee bas ou loin fausserait tout (deja paye : la tondeuse flottait).
-- Les 8 COINS de chaque part, pas son centre : une part inclinee depasse plus loin que sa position.
--
-- L'AXE D'AVANCEE est MESURE, pas devine : c'est la direction RootPart -> CutZone, et la CutZone est par
-- definition posee a l'avant, sous le carter. Sans elle on ne peut pas savoir de quel cote regarde la machine,
-- et on retombe sur un recul de config.
local function measure(model: Model, root: BasePart): (number?, number)
	local rootPos = root.Position
	local forwardDir: Vector3? = nil
	local zone = model:FindFirstChild(MowConfigs.CUT_ZONE_NAME, true)
	if zone and zone:IsA("BasePart") then
		local d = zone.Position - rootPos
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude > 1e-3 then
			forwardDir = d.Unit
		end
	end

	local low: number? = nil
	local back = 0 -- de combien la machine depasse DERRIERE la racine, le long de l'axe d'avancee
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= MowConfigs.CUT_ZONE_NAME and d.Transparency < 1 then
			local h = d.Size * 0.5
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local corner = (d.CFrame * CFrame.new(h.X * sx, h.Y * sy, h.Z * sz)).Position
						low = if low then math.min(low, corner.Y) else corner.Y
						if forwardDir then
							-- Projection NEGATIVE = le coin est derriere la racine. On garde le plus loin.
							back = math.max(back, -(corner - rootPos):Dot(forwardDir))
						end
					end
				end
			end
		end
	end
	return low, back
end

-- Offset de portage, CALCULE sur la geometrie reelle plutot que regle a l'oeil.
--
-- HAUTEUR : on ne descend pas d'une distance fixe sous le HRP, on vise le SOL sur lequel le joueur se tient. Le
-- HRP est toujours a HipHeight + demi-hauteur au-dessus de ses pieds : cette distance est CONNUE. Et comme le HRP
-- monte avec les pentes, la tondeuse les suit gratuitement, sans un seul raycast.
--
-- DISTANCE : c'est le GUIDON qui doit tomber a CARRY_GAP devant le joueur, pas la RootPart. La racine se place
-- donc d'autant plus loin que le guidon est en arriere d'elle. Mesure HORIZONTALE : la hauteur du guidon ne
-- doit rien changer a la distance.
--
-- Consequence : changer la taille du modele ne demande plus aucun reglage.
local function carryC0(model: Model, root: BasePart, hrp: BasePart, humanoid: Humanoid?): CFrame
	local hip = if humanoid then humanoid.HipHeight else 2
	local feet = hip + hrp.Size.Y * 0.5
	local low, back = measure(model, root)
	-- De combien la RootPart surplombe le bas de la machine : c'est ce qu'il faut remonter pour la poser au sol.
	local aboveBottom = if low then root.Position.Y - low else 0
	local down = feet - aboveBottom - MowConfigs.CARRY_CLEARANCE

	-- Le joueur se tient derriere le point le plus ARRIERE de la machine, pas derriere sa racine : la racine est
	-- a l'avant-bas du carter, s'y caler plantait le personnage AU MILIEU de la tondeuse.
	-- Faute de CutZone, on ne connait pas l'axe d'avancee : on retombe sur un recul de config.
	local forward = MowConfigs.CARRY_GAP + (if back > 0 then back else MowConfigs.CARRY_FALLBACK_BACK)

	if MowConfigs.CARRY_DEBUG then
		local r = root.CFrame
		print(
			`[MowService] PORTAGE | pieds sous HRP {string.format("%.2f", feet)}`
			.. ` | racine au-dessus du bas {string.format("%.2f", aboveBottom)}`
			.. ` | descente {string.format("%.2f", down)} | avance {string.format("%.2f", forward)}`
			.. ` | racine Y {string.format("%.2f", r.Position.Y)} bas {string.format("%.2f", low or -999)}`
			.. ` | recul mesure {string.format("%.2f", back)} | orientation racine {r:ToOrientation()}`
		)
	end
	return CFrame.new(0, -down, -forward) * CFrame.Angles(0, math.rad(MowConfigs.CARRY_YAW), 0)
end

-- REPOSE : on retire la soudure et on rend a chaque part son etat d'origine. Celui qui a modifie est celui qui
-- restaure, et il restaure TOUT : un nettoyage reparti finit toujours par oublier un champ.
local function release(model: Model)
	local state = carried[model]
	if not state then
		return
	end
	if state.weld then
		state.weld:Destroy()
		state.weld = nil
	end
	for part, saved in pairs(state.parts) do
		if part.Parent then
			part.Anchored = saved.anchored
			part.CanCollide = saved.canCollide
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	stopHold(state)
	restoreJump(state)
	carried[model] = nil
	model:SetAttribute("LeafiaCarriedBy", nil)
end

local function grab(player: Player, model: Model)
	if carried[model] then
		return -- deja portee, par ce joueur ou un autre
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end
	local root = rootOf(model)
	if not root then
		return
	end
	-- Proximite : le client DEMANDE, le serveur verifie. Sur la RootPart, pas sur GetPivot (que la CutZone decale).
	if (root.Position - hrp.Position).Magnitude > MowConfigs.MAX_GRAB_DIST then
		return
	end

	-- MESURE AVANT DE TOUCHER A QUOI QUE CE SOIT : des qu'on desancre, la physique peut deja avoir fait bouger
	-- la tondeuse d'un poil, et l'offset serait calcule sur une pose qui n'existe plus.
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local c0 = carryC0(model, root, hrp :: BasePart, humanoid)

	local state: CarryState = {
		owner = player,
		parts = {},
		weld = nil,
		hold = nil,
		holdGuard = nil,
		humanoid = humanoid,
		jumpWasEnabled = if humanoid then humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) else true,
		jumpHeight = if humanoid then humanoid.JumpHeight else 7.2,
		jumpPower = if humanoid then humanoid.JumpPower else 50,
	}
	blockJump(state)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			state.parts[d] = { anchored = d.Anchored, canCollide = d.CanCollide }
			d.Anchored = false
			-- Portee, elle ne doit plus bousculer le porteur ni accrocher le decor.
			d.CanCollide = false
		end
	end

	local weld = Instance.new("Weld")
	weld.Part0 = hrp
	weld.Part1 = root
	weld.C0 = c0
	weld.Parent = root
	state.weld = weld
	carried[model] = state
	-- Lu par le client pour savoir si c'est LUI qui pousse (donc s'il doit couper et tourner les roues).
	model:SetAttribute("LeafiaCarriedBy", player.UserId)

	playHold(character :: Model, state)
end

-- Toutes les tondeuses portees par ce joueur. Il n'en porte qu'une, mais boucler evite qu'un etat orphelin
-- survive a une deconnexion et bloque la tondeuse pour tout le monde.
local function releaseAllOf(player: Player)
	for model, state in pairs(carried) do
		if state.owner == player then
			release(model)
		end
	end
end

function MowService.init()
	local remote = RemoteSetup.getRemote("SetMowerCarry", "Mow") :: RemoteEvent

	remote.OnServerEvent:Connect(function(player: Player, inst: unknown, phase: unknown)
		if type(phase) ~= "string" then
			return
		end
		local model = isMower(inst :: Instance?)
		if not model then
			return
		end
		if phase == "grab" then
			grab(player, model)
		elseif phase == "place" then
			-- Seul le porteur repose sa tondeuse. Sinon n'importe qui la ferait tomber des mains d'un autre.
			local state = carried[model]
			if state and state.owner == player then
				release(model)
			end
		end
	end)

	-- Mort / respawn / depart : on lache. Une soudure sur un HRP detruit laisserait la tondeuse introuvable.
	Players.PlayerRemoving:Connect(releaseAllOf)
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterRemoving:Connect(function()
			releaseAllOf(player)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterRemoving:Connect(function()
			releaseAllOf(player)
		end)
	end
end

return MowService
