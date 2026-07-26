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

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local LADDER_PREFIX = "Escabaut"
local MAX_DIST = 30 -- distance MAX joueur <-> echelle a la prise (anti-triche)
-- Anim de l'echelle : une seule piste, deux temps balises par deux marqueurs. Meme chemin que le client.
local ANIM_FOLDER = { "Animations", "Player", "Tools", "Ladder", "ModelAnimate" }
local MODEL_ANIM = "ActionLadderAnimation"
local CLOSE_EVENT = "FermerEvenement" -- echelle REPLIEE : on fige la
local OPEN_EVENT = "LadderOpenEndEvent" -- echelle DEPLIEE (fin) : on stoppe
local CLOSED_ATTR = "LeafiaLadderClosed" -- true = repliee (le client le lit)

local LadderMoveService = {}

type PartState = { anchored: boolean, canCollide: boolean }
type CarryState = {
	owner: Player,
	parts: { [BasePart]: PartState },
	humanoid: Humanoid?,
	platformStand: boolean,
	weld: Weld?,
	foldTrack: AnimationTrack?,
}
local carried: { [Model]: CarryState } = {}

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

	local state: CarryState =
		{ owner = player, parts = {}, humanoid = nil, platformStand = false, weld = nil, foldTrack = nil }
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
	end
end

function LadderMoveService.init()
	local remote = RemoteSetup.getRemote("SetLadderCarry", "Ladder")
	if remote and remote:IsA("RemoteEvent") then
		remote.OnServerEvent:Connect(onCarry)
	else
		warn("[LadderMoveService] Remote Ladder/SetLadderCarry introuvable : le portage co-op ne marchera pas")
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
	end)
end

return LadderMoveService
