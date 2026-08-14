--!strict
-- Autorite SERVEUR sur l'echelle en portage. PORTAGE par WELD : a la prise, on desancre l'echelle et on soude sa
-- RootPart au HumanoidRootPart du porteur -> elle suit le perso et sa POSITION se replique nativement a tous, sans
-- flot de remotes et sans jamais tomber. A la repose, on retire le weld et on re-ancre sur place.
--
-- REPLI / DEPLI (ActionLadderAnimation) : joue ICI, cote serveur. Une anim jouee par le client sur l'echelle ne se
-- replique PAS aux autres (l'echelle n'est pas SON perso) ; jouee par le serveur, elle part a tous. Le client ne fait
-- que DECLENCHER (phase "close" au bon instant du geste de prise, "place" a la repose). C'est possible proprement
-- parce que le weld gere deja la position : le repli serveur ne se bat plus avec une prediction client.
--
-- On memorise l'etat d'origine (Anchored, CanCollide par part ; PlatformStand du Humanoid) pour le restaurer a la repose.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local LADDER_PREFIX = "Escabaut"
local MAX_DIST = 30 -- distance MAX joueur <-> echelle a la prise (anti-triche)
-- Anim de l'echelle : une seule piste, deux temps balises par deux marqueurs. Meme chemin que le client.
local ANIM_FOLDER = { "Animations", "Player", "Tools", "Ladder", "ModelAnimate" }
local MODEL_ANIM = "ActionLadderAnimation"
local CLOSE_EVENT = "FermerEvenement" -- echelle REPLIEE : on fige la
local OPEN_EVENT = "LadderOpenEndEvent" -- echelle DEPLIEE (fin) : on stoppe
local CLOSED_ATTR = "LeafiaLadderClosed" -- true = repliee (le client le lit)
-- ROTATION de l'echelle portee (touche R). On tween le C0 du weld -> l'echelle tourne pour TOUS (le weld est
-- serveur). Toggle entre l'orientation de base et une rotation de 180 degres autour de la VERTICALE (Y du repere
-- de l'echelle). Si l'echelle tourne autour du mauvais axe, changer l'axe ici (ex : math.pi sur Z).
local ROTATE_FLIP = CFrame.Angles(0, math.pi, 0)
local ROTATE_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- MONTEE : l'aimant vers le point de montage, joue COTE SERVEUR (tween du CFrame du HRP ancre) pour se repliquer
-- a tous. Cote client, ancrer + poser sa propre part ne se repliquait pas -> les autres voyaient le grimpeur de travers.
local CLIMB_MOUNT_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local LadderMoveService = {}

type PartState = { anchored: boolean, canCollide: boolean }
type CarryState = {
	owner: Player,
	parts: { [BasePart]: PartState },
	humanoid: Humanoid?,
	platformStand: boolean,
	weld: Weld?,
	foldTrack: AnimationTrack?,
	-- ROTATION : C0 de base (non tourne), etat retourne courant, et le tween en cours (pour l'annuler a la repose
	-- ou a un nouveau R). On repart toujours de baseC0 : pas d'accumulation qui deriverait au fil des rotations.
	baseC0: CFrame,
	rotated: boolean,
	rotateTween: Tween?,
}
local carried: { [Model]: CarryState } = {}
-- MONTEE : HRP ancre par le serveur le temps de la grimpe (+ le tween d'aimant en cours). Sert a poser la pose du
-- grimpeur (face a l'echelle) de facon repliquee, et a tout defaire proprement a la descente / mort.
local climbing: { [Player]: { hrp: BasePart, tween: Tween? } } = {}

local function isLadder(inst: unknown): boolean
	if typeof(inst) ~= "Instance" then
		return false
	end
	local instance = inst :: Instance
	return instance:IsA("Model")
		and instance:IsDescendantOf(workspace)
		and instance.Name:sub(1, #LADDER_PREFIX) == LADDER_PREFIX
end

local function ladderRootPart(model: Model): BasePart?
	return model.PrimaryPart or (model:FindFirstChild("RootPart") :: BasePart?)
end

local function resolveModelAnim(): Animation?
	local node: Instance = ReplicatedStorage
	for _, part in ipairs(ANIM_FOLDER) do
		local child = node:FindFirstChild(part)
		if not child then
			return nil
		end
		node = child
	end
	local anim = node:FindFirstChild(MODEL_ANIM)
	return if anim and anim:IsA("Animation") then anim else nil
end

-- Animator de l'echelle (elle a son propre Humanoid). Cree s'il manque.
local function getLadderAnimator(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

-- Retire le weld, coupe la vitesse, restaure l'etat d'origine (root re-ancre, enfants restaures) et fige la position.
local function unweld(state: CarryState, model: Model)
	local pivot = model:GetPivot()
	-- Une rotation en cours tweenait le C0 du weld : on la coupe AVANT de detruire le weld, sinon le tween
	-- ecrirait sur une instance detruite.
	if state.rotateTween then
		state.rotateTween:Cancel()
		state.rotateTween = nil
	end
	if state.weld then
		state.weld:Destroy()
		state.weld = nil
	end
	for part in pairs(state.parts) do
		if part.Parent then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	for part, saved in pairs(state.parts) do
		if part.Parent then
			part.Anchored = saved.anchored
			part.CanCollide = saved.canCollide
		end
	end
	if state.humanoid then
		state.humanoid.PlatformStand = state.platformStand
	end
	model:PivotTo(pivot)
end

-- PRISE : desancre + soude la RootPart au HRP du porteur (offset c0), et fige le Humanoid de l'echelle.
local function grab(player: Player, model: Model, c0: CFrame?)
	if carried[model] then
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end
	if (model:GetPivot().Position - hrp.Position).Magnitude > MAX_DIST then
		return
	end
	local root = ladderRootPart(model)
	if not root then
		warn(`[LadderMoveService] Pas de RootPart / PrimaryPart sur {model.Name} : soudure impossible`)
		return
	end

	local state: CarryState = {
		owner = player,
		parts = {},
		humanoid = nil,
		platformStand = false,
		weld = nil,
		foldTrack = nil,
		baseC0 = CFrame.identity,
		rotated = false,
		rotateTween = nil,
	}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			state.parts[d] = { anchored = d.Anchored, canCollide = d.CanCollide }
			d.Anchored = false
			d.CanCollide = false
		elseif d:IsA("Humanoid") then
			state.humanoid = d
			state.platformStand = d.PlatformStand
			d.PlatformStand = true
			pcall(function()
				d:ChangeState(Enum.HumanoidStateType.Physics)
			end)
		end
	end

	local weld = Instance.new("Weld")
	weld.Part0 = hrp
	weld.Part1 = root
	if typeof(c0) == "CFrame" then
		weld.C0 = c0
	end
	weld.Parent = root
	state.weld = weld
	-- Orientation de reference pour la rotation : on la memorise APRES avoir pose le C0 de portage.
	state.baseC0 = weld.C0
	carried[model] = state

	-- On CHARGE la piste de repli des la prise (sans la jouer) : au "close" (~0.23s plus tard) elle sera prete,
	-- marqueurs inclus. Sinon, a la 1re prise de la session, l'asset n'est pas encore charge cote serveur et les
	-- marqueurs (FermerEvenement) ne tirent pas -> l'anim jouerait EN ENTIER au lieu de se figer repliee.
	local animator = getLadderAnimator(model)
	local anim = resolveModelAnim()
	if animator and anim then
		state.foldTrack = animator:LoadAnimation(anim)
	end
end

-- REPLI ("close", au marqueur de prise) : on joue la piste (chargee/chauffee au grab) 0 -> CLOSE_EVENT et on la fige.
-- Jouee cote serveur -> se replique a tous.
local function foldClose(player: Player, model: Model)
	local state = carried[model]
	if not state or state.owner ~= player then
		return
	end
	local mt = state.foldTrack
	if not mt then
		-- Repli : l'Animator n'etait pas pret au grab. On charge maintenant (repli).
		local animator = getLadderAnimator(model)
		local anim = resolveModelAnim()
		if not (animator and anim) then
			warn(`[LadderMoveService] Repli impossible (animator ou anim absent) : {model.Name}`)
			return
		end
		mt = animator:LoadAnimation(anim)
		state.foldTrack = mt
	end
	if mt.IsPlaying then
		return -- deja en train de se replier
	end
	mt.Looped = false
	mt:GetMarkerReachedSignal(CLOSE_EVENT):Connect(function()
		mt:AdjustSpeed(0) -- fige replie
		model:SetAttribute(CLOSED_ATTR, true)
	end)
	mt:GetMarkerReachedSignal(OPEN_EVENT):Connect(function()
		mt:Stop(0.1) -- deplie : on lache l'anim
		model:SetAttribute(CLOSED_ATTR, false)
	end)
	mt:Play()
	mt.TimePosition = 0
end

-- REPOSE ("place") : on retire le weld et on re-ancre SUR PLACE, puis on DEPLIE (l'anim tourne sur l'echelle ancree :
-- racine ancree + enfants sur Motor6D = ca s'anime, et ca se replique). L'OPEN_EVENT (pose en close) stoppe l'anim.
local function place(player: Player, model: Model)
	local state = carried[model]
	if not state or state.owner ~= player then
		return
	end
	local mt = state.foldTrack
	unweld(state, model)
	carried[model] = nil
	if mt then
		mt:AdjustSpeed(1) -- repart de CLOSE_EVENT vers OPEN_EVENT : depli
	else
		model:SetAttribute(CLOSED_ATTR, false)
	end
end

-- RELACHE IMMEDIAT ("release") : mort / respawn / depart. On retire le weld et on re-ancre, sans depli.
local function releaseImmediate(player: Player, model: Model)
	local state = carried[model]
	if not state or state.owner ~= player then
		return
	end
	if state.foldTrack then
		state.foldTrack:Stop(0)
	end
	unweld(state, model)
	carried[model] = nil
end

-- ROTATION ("rotate", touche R) : chaque appui BASCULE entre l'orientation de base et la retournee de 180 degres.
-- On tween le C0 du weld (serveur) -> l'echelle tourne pour TOUS. On repart de baseC0 a chaque fois (pas
-- d'accumulation), et on annule un tween en cours pour repartir de la position courante sans a-coup.
local function rotateLadder(player: Player, model: Model)
	local state = carried[model]
	if not state or state.owner ~= player or not state.weld then
		return
	end
	state.rotated = not state.rotated
	local target = if state.rotated then state.baseC0 * ROTATE_FLIP else state.baseC0
	if state.rotateTween then
		state.rotateTween:Cancel()
	end
	local tween = TweenService:Create(state.weld, ROTATE_TWEEN, { C0 = target })
	state.rotateTween = tween
	tween:Play()
end

-- MONTEE : le grimpeur signale son echelle + son point de montage (face a l'echelle). On ANCRE son HRP et on le
-- pose la, par un tween, COTE SERVEUR -> tous le voient droit devant l'echelle. Le client ancre aussi en local
-- (freeze immediat), mais c'est ce CFrame SERVEUR qui se replique aux autres.
local function climbMount(player: Player, model: Model, cframe: CFrame)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end
	-- Anti-triche : le point de montage ET le joueur doivent etre pres de l'echelle.
	local pivot = model:GetPivot().Position
	if (cframe.Position - pivot).Magnitude > MAX_DIST or (hrp.Position - pivot).Magnitude > MAX_DIST then
		return
	end
	local existing = climbing[player]
	if existing and existing.tween then
		existing.tween:Cancel()
	end
	hrp.Anchored = true -- serveur AUTORITAIRE : il possede la part ancree, donc son CFrame se replique.
	local tween = TweenService:Create(hrp, CLIMB_MOUNT_TWEEN, { CFrame = cframe })
	climbing[player] = { hrp = hrp, tween = tween }
	tween:Play()
end

-- DESCENTE / mort : on desancre le HRP et on annule le tween. Le joueur reprend la main sur sa physique.
local function climbRelease(player: Player)
	local state = climbing[player]
	if not state then
		return
	end
	climbing[player] = nil
	if state.tween then
		state.tween:Cancel()
	end
	if state.hrp.Parent then
		state.hrp.Anchored = false
	end
end

local function onCarry(player: Player, ladder: unknown, phase: unknown, c0: unknown)
	if not isLadder(ladder) or typeof(phase) ~= "string" then
		return
	end
	local model = ladder :: Model
	if phase == "grab" then
		grab(player, model, if typeof(c0) == "CFrame" then c0 :: CFrame else nil)
	elseif phase == "close" then
		foldClose(player, model)
	elseif phase == "place" then
		place(player, model)
	elseif phase == "release" then
		releaseImmediate(player, model)
	elseif phase == "rotate" then
		rotateLadder(player, model)
	end
end

function LadderMoveService.init()
	local remote = RemoteSetup.getRemote("SetLadderCarry", "Ladder")
	if remote and remote:IsA("RemoteEvent") then
		remote.OnServerEvent:Connect(onCarry)
	else
		warn("[LadderMoveService] Remote Ladder/SetLadderCarry introuvable : le portage co-op ne marchera pas")
	end

	-- MONTEE : le serveur ancre + pose le grimpeur face a l'echelle (repliqué). A la montee : (echelle, CFrame).
	-- A la descente : rien -> on desancre.
	local climbRemote = RemoteSetup.getRemote("SetLadderClimb", "Ladder")
	if climbRemote and climbRemote:IsA("RemoteEvent") then
		climbRemote.OnServerEvent:Connect(function(player: Player, ladder: unknown, cframe: unknown)
			if isLadder(ladder) and typeof(cframe) == "CFrame" then
				climbMount(player, ladder :: Model, cframe :: CFrame)
			else
				climbRelease(player)
			end
		end)
	else
		warn("[LadderMoveService] Remote Ladder/SetLadderClimb introuvable : la montee ne se verra pas droite chez les autres")
	end

	-- PRECHARGE l'anim de l'echelle au demarrage : sans ca, la 1re prise de la session trouve l'asset pas encore
	-- charge cote serveur et ses marqueurs (FermerEvenement) ne tirent pas -> le repli jouerait en entier. On le fait
	-- dans un thread a part (PreloadAsync yield) : aucune raison de retarder le demarrage du serveur.
	task.spawn(function()
		local anim = resolveModelAnim()
		if anim then
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync({ anim })
			end)
		end
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		for model, state in pairs(carried) do
			if state.owner == player then
				releaseImmediate(player, model)
			end
		end
		climbRelease(player)
	end)
end

return LadderMoveService
