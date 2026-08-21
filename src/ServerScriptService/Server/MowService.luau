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
local ContentProvider = game:GetService("ContentProvider")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local MowConfigs = require(ReplicatedStorage.Modules.Configs.MowConfigs)
local CharacterService = require(script.Parent.CharacterService)

local MowService = {}

type PartState = { anchored: boolean, canCollide: boolean }
type CarryState = {
	owner: Player,
	parts: { [BasePart]: PartState },
	weld: Weld?,
	hold: AnimationTrack?, -- pose "mains sur le guidon", figee au marqueur. Coupee a la repose.
	holdGuard: RBXScriptConnection?, -- filet : rattrape la pose si le marqueur est rate (image perdue)
	motor: AnimationTrack?, -- boucle du moteur, sur l'Animator de la TONDEUSE
	lever: AnimationTrack?, -- levier d'accelerateur : on pilote sa TimePosition, on ne la laisse pas jouer
	tick: RBXScriptConnection?, -- boucle de la machine : montee en vitesse + position du levier
	speed: number, -- vitesse COURANTE du porteur, montee/descente lissee
	humanoid: Humanoid?, -- porteur, garde pour rendre le saut a la repose
	jumpWasEnabled: boolean, -- etat du saut AVANT la prise : on restaure, on ne force pas a true
	jumpHeight: number, -- valeurs REELLES d'avant, pas les defauts Roblox : un autre systeme a pu les changer
	jumpPower: number,
}

-- On cle la pose JUSTE avant la derniere image, jamais dessus : a la derniere image pile, la piste bouclee
-- repart au debut avant qu'on ait pu la figer.
local HOLD_EPSILON = 0.001
-- Duree MINIMALE pour qu'une piste soit prise au serieux. Une piste encore en cours de chargement annonce une
-- Length minuscule (voire nulle) : la comparaison `TimePosition >= Length - epsilon` devenait alors VRAIE des
-- l'image ZERO, le filet figeait la pose au tout debut, et le personnage restait droit comme un R15 sans
-- animation. Symptome trompeur : intermittent, parce que c'est une course entre le chargement et la 1re image.
local HOLD_MIN_LENGTH = 0.05
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

-- Animations de la MACHINE, mises en cache : ce sont des porteurs d'ID, pas des etats.
local machineAnims: { [string]: Animation } = {}
local function machineAnimation(id: string): Animation?
	if id == "" then
		return nil
	end
	local a = machineAnims[id]
	if not a then
		a = Instance.new("Animation")
		a.AnimationId = id
		machineAnims[id] = a
	end
	return a
end

-- L'Animator de la TONDEUSE. Un mesh rigge importe par le 3D Importer arrive avec un AnimationController VIDE :
-- Roblox n'y met pas d'Animator. On le CREE au lieu de renoncer -- meme piege que sur les arbres d'ambiance.
local function machineAnimator(model: Model): Animator?
	local holder: Instance? = model:FindFirstChildOfClass("AnimationController")
		or model:FindFirstChildOfClass("Humanoid")
	if not holder then
		local controller = Instance.new("AnimationController")
		controller.Parent = model
		holder = controller
	end
	local found = (holder :: Instance):FindFirstChildOfClass("Animator")
	if found then
		return found
	end
	local animator = Instance.new("Animator")
	animator.Parent = holder
	return animator
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
		-- `TimePosition > 0` en plus de la vitesse : une piste qui vient d'etre lancee peut annoncer une vitesse
		-- nulle avant que Play ne prenne effet. Lacher le filet a cet instant le rendrait inutile pile quand il
		-- sert -- au tout debut.
		if track.Speed == 0 and track.TimePosition > 0 then
			-- Le marqueur a fait le travail : plus rien a surveiller.
			if state.holdGuard then
				state.holdGuard:Disconnect()
				state.holdGuard = nil
			end
			return
		end
		-- Trois conditions, et les deux premieres sont des garde-fous, pas du zele :
		--   IsPlaying      -> une piste pas encore demarree n'a rien a figer ;
		--   Length credible -> une piste en cours de chargement ment sur sa duree (voir HOLD_MIN_LENGTH).
		local length = track.Length
		if track.IsPlaying and length > HOLD_MIN_LENGTH and track.TimePosition >= length - HOLD_EPSILON then
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

-- LA MACHINE TOURNE : moteur en boucle, levier pilote a la main, et le porteur monte en vitesse.
--
-- LE LEVIER N'EST PAS "JOUE". Sa position raconte le REGIME, pas le temps qui passe : on le pose donc a vitesse
-- zero et on ecrit sa TimePosition selon la vitesse du moment. Meme mecanique que la visee haut/bas du taille-haie
-- -- une animation dont on ne lit qu'une IMAGE, jamais le defilement.
local function startMachine(model: Model, state: CarryState)
	local animator = machineAnimator(model)
	if not animator then
		return
	end

	local motorAsset = machineAnimation(MowConfigs.MOTOR_ANIM_ID)
	if motorAsset then
		local ok, track = pcall(function()
			return animator:LoadAnimation(motorAsset)
		end)
		if ok and typeof(track) == "Instance" then
			local t = track :: AnimationTrack
			t.Looped = true
			t.Priority = Enum.AnimationPriority.Idle
			t:Play()
			state.motor = t
		end
	end

	local leverAsset = machineAnimation(MowConfigs.LEVER_ANIM_ID)
	if leverAsset then
		local ok, track = pcall(function()
			return animator:LoadAnimation(leverAsset)
		end)
		if ok and typeof(track) == "Instance" then
			local t = track :: AnimationTrack
			-- Looped pour que la piste ne se RELACHE jamais (sinon la pose du levier saute), vitesse zero pour
			-- qu'elle n'avance pas d'elle-meme : c'est nous qui la deplacons.
			t.Looped = true
			t.Priority = Enum.AnimationPriority.Action
			t:Play()
			t:AdjustSpeed(0)
			t.TimePosition = 0
			state.lever = t
		end
	end
end

local function stopMachine(state: CarryState)
	if state.tick then
		state.tick:Disconnect()
		state.tick = nil
	end
	-- Une par une, et PAS via ipairs sur une table qui peut contenir un trou : ipairs s'arrete au premier nil,
	-- donc un moteur absent aurait laisse le levier tourner pour toujours.
	local function cut(track: AnimationTrack?)
		if track then
			pcall(function()
				track:AdjustSpeed(1)
				track:Stop(MowConfigs.HOLD_FADE)
			end)
		end
	end
	cut(state.motor)
	cut(state.lever)
	state.motor = nil
	state.lever = nil
	-- On RETIRE l'allure imposee : CharacterService reprend la main et ramene le joueur a sa marche, en
	-- douceur. Reposer une valeur nous-memes reviendrait a redevenir un deuxieme ecrivain.
	CharacterService.setSpeedOverride(state.owner, nil)
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
	stopMachine(state)
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
		motor = nil,
		lever = nil,
		tick = nil,
		speed = MowConfigs.SPEED_MIN,
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
	startMachine(model, state)

	-- BOUCLE DE LA MACHINE : montee en vitesse du porteur, et position du levier qui la raconte.
	-- Separee du filet de la pose : deux responsabilites, deux connexions, chacune coupee a son heure.
	state.tick = RunService.Heartbeat:Connect(function(dt: number)
		local hum = state.humanoid
		local char = hum and hum.Parent
		local rootPart = char and char:FindFirstChild("HumanoidRootPart")
		if not (hum and hum.Parent and rootPart and rootPart:IsA("BasePart")) then
			return
		end

		-- Vitesse REELLE, pas l'intention : pousser contre un mur ne doit pas faire monter le regime.
		local v = (rootPart :: BasePart).AssemblyLinearVelocity
		local moving = math.sqrt(v.X * v.X + v.Z * v.Z) > MowConfigs.SPEED_MOVE_EPSILON

		-- Montee LENTE, descente VIVE : on gagne sa vitesse, on ne la garde pas gratuitement.
		local target = if moving then MowConfigs.SPEED_MAX else MowConfigs.SPEED_MIN
		local rate = if moving then MowConfigs.SPEED_RAMP_UP else MowConfigs.SPEED_RAMP_DOWN
		if state.speed < target then
			state.speed = math.min(target, state.speed + rate * dt)
		else
			state.speed = math.max(target, state.speed - rate * dt)
		end
		-- On DECLARE l'allure, on n'ecrit pas dans WalkSpeed : CharacterService en est le seul proprietaire, et
		-- ecrire directement le ferait se battre avec le sprint et les autres features (sa regle, en tete de
		-- son fichier). Sa rampe est plus rapide que la notre, donc c'est bien NOTRE montee qu'on ressent.
		CharacterService.setSpeedOverride(state.owner, state.speed)

		-- LE LEVIER RACONTE LE REGIME. Ratio 0 au ralenti, 1 a plein regime, et on ecrit l'IMAGE correspondante.
		-- On s'arrete a Length - epsilon : sur la derniere image pile, une piste bouclee est deja repartie a zero.
		local lever = state.lever
		if lever and lever.Length > 0 then
			local span = MowConfigs.SPEED_MAX - MowConfigs.SPEED_MIN
			local ratio = if span > 1e-3 then (state.speed - MowConfigs.SPEED_MIN) / span else 0
			lever.TimePosition = math.clamp(ratio, 0, 1) * (lever.Length - HOLD_EPSILON)
		end
	end)
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
	-- PRECHARGEMENT. Le filet rattrape une piste pas encore chargee, mais mieux vaut qu'elle le soit deja :
	-- a la 1re prise d'une session, l'asset arrive parfois APRES le Play, et la pose part de travers.
	-- En task.spawn : c'est un appel RESEAU, il n'a rien a faire dans le chemin de boot.
	task.spawn(function()
		local assets: { Instance } = { getHoldAnimation() }
		for _, id in ipairs({ MowConfigs.MOTOR_ANIM_ID, MowConfigs.LEVER_ANIM_ID }) do
			local a = machineAnimation(id)
			if a then
				assets[#assets + 1] = a
			end
		end
		-- pcall : un asset absent ou une coupure reseau ne doit pas empecher la tondeuse de fonctionner.
		pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)
	end)

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
