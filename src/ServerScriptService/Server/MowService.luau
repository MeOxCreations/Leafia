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
}

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
end

local function stopHold(state: CarryState)
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

-- Le point le plus BAS de la tondeuse, en monde. Les 8 coins de chaque part, pas seulement son centre : une part
-- inclinee descend plus bas que (position - demi-hauteur), et le carter d'une tondeuse est rarement d'aplomb.
-- On IGNORE la CutZone : c'est une zone LOGIQUE posee sous le carter, pas une piece de la machine. La compter
-- ferait poser la tondeuse un peu trop haut, et c'est exactement le defaut qu'on corrige.
local function lowestPoint(model: Model): number?
	local low: number? = nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= MowConfigs.CUT_ZONE_NAME then
			local h = d.Size * 0.5
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local y = (d.CFrame * CFrame.new(h.X * sx, h.Y * sy, h.Z * sz)).Position.Y
						low = if low then math.min(low, y) else y
					end
				end
			end
		end
	end
	return low
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
	local low = lowestPoint(model)
	-- De combien la RootPart surplombe le bas de la machine : c'est ce qu'il faut remonter pour la poser au sol.
	local aboveBottom = if low then root.Position.Y - low else 0
	local down = feet - aboveBottom - MowConfigs.CARRY_CLEARANCE

	local forward = MowConfigs.CARRY_GAP
	local handle = model:FindFirstChild(MowConfigs.HANDLE_NAME, true)
	if handle and handle:IsA("BasePart") then
		local d = handle.Position - root.Position
		forward += math.sqrt(d.X * d.X + d.Z * d.Z)
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
	la tondeuse d'un poil, et l'offset serait calcule sur une pose qui n'existe plus.
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local c0 = carryC0(model, root, hrp :: BasePart, humanoid)

	local state: CarryState = { owner = player, parts = {}, weld = nil, hold = nil }
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
