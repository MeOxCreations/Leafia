--!strict
-- PRISE / PORTAGE / REPOSE du SEAU, cote client. PORTAGE LIBRE : on se balade ou on veut, on repose ou on veut.
-- Aucun rail, aucun aimant vers une haie -- contrairement a LadderMoveController, dont tout le systeme de focus
-- est volontairement absent ici.
--
--   PRISE   : on joue TakeAnimation ; au marqueur TakeBucketEvent (la main se referme), on demande au SERVEUR de
--             souder le seau. Puis on enchaine sur la pose de portage.
--   REPOSE  : on demande au serveur, qui retire le joint et pose le seau AU SOL devant nous.
--
-- POURQUOI ON SOUDE AU MARQUEUR ET PAS A L'APPUI. L'echelle, elle, soude des l'appui : elle est enorme et le
-- geste est rapide, le saut ne se voit pas. Un seau pose par terre, lui, se teleporterait dans la main avant que
-- la main l'atteigne. FILET : si le marqueur ne tire pas (asset pas encore charge a la 1re lecture de la
-- session), l'arret de la piste declenche quand meme la soudure -- sinon le seau ne se prendrait pas DU TOUT.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local BinConfigs = require(ReplicatedStorage.Modules.Configs.BinConfigs)
local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)

-- Attributs poses par les AUTRES systemes de portage. On ne porte qu'une chose a la fois : tant que l'un d'eux
-- est actif, on ne propose pas le seau (et on ne branche pas la touche, qui est partagee avec la tondeuse).
local BLOCKING_ATTRIBUTES = { "LeafiaCarryingLadder" }

local player = Players.LocalPlayer

local BinCarryController = {}

local carriedBin: Model? = nil
local binsCache: { Model }? = nil
local lastScanAt = 0
local lastPromptAt = 0
local lastActionAt = 0
local promptTarget: Model? = nil
local promptAnchor: BasePart? = nil
local actionBound = false
local takeTrack: AnimationTrack? = nil
local carryTrack: AnimationTrack? = nil
local markerConn: RBXScriptConnection? = nil
local stopConn: RBXScriptConnection? = nil
local stepConn: RBXScriptConnection? = nil
local remote: RemoteEvent? = nil

local function getRoot(): BasePart?
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

-- L'Animator arrive quelques frames APRES l'Humanoid : un FindFirstChildOfClass a CharacterAdded rend nil.
-- WaitForChild avec timeout, jamais sans.
local function getAnimator(): Animator?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:WaitForChild("Animator", 3)
	return if animator and animator:IsA("Animator") then animator else nil
end

local function resolveAnimation(name: string): Animation?
	local node: Instance? = ReplicatedStorage
	for _, part in ipairs(BinConfigs.ANIM_FOLDER) do
		node = node and node:FindFirstChild(part)
	end
	local anim = node and node:FindFirstChild(name)
	return if anim and anim:IsA("Animation") then anim else nil
end

local function loadTrack(animator: Animator, name: string): AnimationTrack?
	local anim = resolveAnimation(name)
	if not anim then
		warn(`[BinCarry] Animation {name} introuvable dans {table.concat(BinConfigs.ANIM_FOLDER, "/")}`)
		return nil
	end
	return animator:LoadAnimation(anim)
end

local function binRoot(model: Model): BasePart?
	local root = model.PrimaryPart or model:FindFirstChild(BinConfigs.ROOT_NAME)
	return if root and root:IsA("BasePart") then root else nil
end

-- Le Workspace est re-balaye periodiquement, pas une seule fois au boot : avec StreamingEnabled un seau
-- lointain arrive TARD, et un scan unique ne le verrait jamais.
local function getBins(now: number): { Model }
	local cached = binsCache
	if cached and now - lastScanAt < BinConfigs.RESCAN_INTERVAL then
		return cached
	end
	lastScanAt = now
	local list: { Model } = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name:sub(1, #BinConfigs.MODEL_PREFIX) == BinConfigs.MODEL_PREFIX then
			table.insert(list, d)
		end
	end
	binsCache = list
	return list
end

-- On ne porte qu'une chose a la fois. Un joueur qui tient deja l'echelle ne doit ni voir le prompt du seau, ni
-- pouvoir le prendre : la touche E est en plus partagee avec la tondeuse.
local function busyWithSomethingElse(): boolean
	local character = player.Character
	if not character then
		return true
	end
	for _, attribute in ipairs(BLOCKING_ATTRIBUTES) do
		if character:GetAttribute(attribute) then
			return true
		end
	end
	return false
end

-- Seau LIBRE le plus proche. Detection RADIALE (distance horizontale a une part FIXE) : un seul rayon, aucun
-- angle mort, independant de l'orientation. Une box laterale laisserait des trous aux extremites.
local function freeBinNear(position: Vector3, now: number): (Model?, BasePart?)
	local best: Model? = nil
	local bestRoot: BasePart? = nil
	local bestDist = BinConfigs.DETECT_RADIUS
	for _, model in ipairs(getBins(now)) do
		if model.Parent and not model:GetAttribute(BinConfigs.CARRIED_ATTRIBUTE) then
			local root = binRoot(model)
			if root then
				local flat = (root.Position - position) * Vector3.new(1, 0, 1) -- Y ignore : un seau se prend au sol
				local dist = flat.Magnitude
				if dist <= bestDist then
					best, bestRoot, bestDist = model, root, dist
				end
			end
		end
	end
	return best, bestRoot
end

local function request(model: Model, phase: string)
	if remote then
		remote:FireServer(model, phase)
	end
end

local function clearTakeConns()
	if markerConn then
		markerConn:Disconnect()
		markerConn = nil
	end
	if stopConn then
		stopConn:Disconnect()
		stopConn = nil
	end
end

local function stopTracks()
	clearTakeConns()
	if takeTrack then
		takeTrack:Stop(0.1)
		takeTrack = nil
	end
	if carryTrack then
		carryTrack:Stop(0.15)
		carryTrack = nil
	end
end

-- Pose de PORTAGE, enchainee A LA FIN du geste de prise. Elle ne cle que les bras et le torse, donc la marche
-- continue de tourner par-dessous. Action2 : au-dessus du maintien d'outil (Action) et de la marche (Movement).
local function playCarryPose()
	local animator = getAnimator()
	if not animator or not carriedBin then
		return
	end
	local carry = loadTrack(animator, BinConfigs.CARRY_ANIM)
	if not carry then
		return
	end
	carryTrack = carry
	carry.Priority = Enum.AnimationPriority.Action2
	carry.Looped = true
	carry:Play(0.15)
end

local function pickUp(model: Model)
	if carriedBin or busyWithSomethingElse() then
		return
	end
	local animator = getAnimator()
	if not animator then
		return
	end
	carriedBin = model

	local track = loadTrack(animator, BinConfigs.TAKE_ANIM)
	if not track then
		-- Sans animation on prend quand meme : le geste n'est qu'un plus, rester bloque serait pire.
		request(model, "grab")
		playCarryPose()
		return
	end
	takeTrack = track
	track.Priority = Enum.AnimationPriority.Action2
	-- FORCE a false : une piste bouclee par erreur reste a plein poids POUR TOUJOURS et pollue tout ce qui
	-- partage sa priorite. Le reglage de l'editeur n'est qu'une suggestion.
	track.Looped = false

	-- SOUDURE AU MARQUEUR, avec filet a l'arret de la piste. Le drapeau garantit UN seul envoi : sans lui, le
	-- marqueur puis l'arret demanderaient deux fois la prise.
	local fired = false
	clearTakeConns()
	local function doGrab()
		if fired or carriedBin ~= model then
			return
		end
		fired = true
		clearTakeConns()
		request(model, "grab")
	end
	markerConn = track:GetMarkerReachedSignal(BinConfigs.TAKE_EVENT):Connect(doGrab)
	stopConn = track.Stopped:Connect(function()
		doGrab() -- filet : le marqueur n'a pas tire (asset pas charge a la 1re lecture)
		playCarryPose()
	end)
	track:Play(0.1)
end

local function placeBin()
	local model = carriedBin
	if not model then
		return
	end
	carriedBin = nil
	stopTracks()
	request(model, "place")
end

local function toggleCarry()
	local now = os.clock()
	if now - lastActionAt < BinConfigs.PICKUP_DEBOUNCE then
		return
	end
	lastActionAt = now

	if carriedBin then
		placeBin()
		return
	end
	local root = getRoot()
	if not root then
		return
	end
	local target = freeBinNear(root.Position, now)
	if target then
		pickUp(target)
	end
end

-- La touche n'est branchee QUE quand l'action a un sens. createTouchButton fait apparaitre un bouton a l'ecran
-- sur tactile ET bind la touche sur PC, d'un seul geste : sans lui, le seau serait injouable sans clavier.
local function setActionBound(active: boolean)
	if active == actionBound then
		return
	end
	actionBound = active
	if active then
		ContextActionService:BindAction(BinConfigs.ACTION_NAME, function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				toggleCarry()
			end
			return Enum.ContextActionResult.Pass
		end, true, BinConfigs.ACTION_KEY)
	else
		ContextActionService:UnbindAction(BinConfigs.ACTION_NAME)
	end
end

-- Le prompt est un SINGLETON partage (echelle, tondeuse, boite aux lettres, dialogues). On ne cache donc QUE le
-- notre : appeler hide() sans regarder ferait disparaitre celui d'une autre feature en plein milieu.
local function hideOurs()
	local anchor = promptAnchor
	if anchor and InteractionPrompt.currentTarget() == anchor then
		InteractionPrompt.hide()
	end
	promptTarget = nil
	promptAnchor = nil
end

local function updatePrompt(now: number)
	if now - lastPromptAt < BinConfigs.PROMPT_INTERVAL then
		return
	end
	lastPromptAt = now

	-- On porte : plus de badge (on l'a en main), mais la touche reste branchee pour reposer.
	if carriedBin then
		hideOurs()
		setActionBound(true)
		return
	end
	local root = getRoot()
	if not root or busyWithSomethingElse() then
		hideOurs()
		setActionBound(false)
		return
	end

	local target, anchor = freeBinNear(root.Position, now)
	if target and anchor then
		setActionBound(true)
		-- On re-montre au CHANGEMENT de seau, mais AUSSI quand le prompt ne nous appartient plus : une autre
		-- feature a pu prendre le singleton entre-temps. Sans ce second test, le notre disparaitrait pour de bon.
		if target ~= promptTarget or InteractionPrompt.currentTarget() ~= anchor then
			promptTarget = target
			promptAnchor = anchor
			InteractionPrompt.show(
				anchor,
				BinConfigs.PROMPT_KEY,
				BinConfigs.PROMPT_LABEL,
				BinConfigs.PROMPT_OFFSET,
				toggleCarry,
				BinConfigs.PROMPT_TITLE
			)
		end
	else
		hideOurs()
		setActionBound(false)
	end
end

function BinCarryController.init()
	-- getRemote cache un WaitForChild : appele en ligne droite dans un init, il gele TOUT le boot le temps du
	-- timeout. En tache de fond, le reste demarre pendant qu'il attend.
	task.spawn(function()
		local r = RemoteSetup.getRemote("SetBinCarry", "Bin")
		if r and r:IsA("RemoteEvent") then
			remote = r
		else
			warn("[BinCarry] Remote Bin/SetBinCarry introuvable : le portage du seau ne marchera pas")
		end
	end)

	-- Le cache est invalide quand un seau apparait / disparait (streaming, repose). Filtre par nom : les milliers
	-- d'autres instances du Workspace ne le touchent pas.
	local function invalidate(inst: Instance)
		if inst:IsA("Model") and inst.Name:sub(1, #BinConfigs.MODEL_PREFIX) == BinConfigs.MODEL_PREFIX then
			binsCache = nil
		end
	end
	workspace.DescendantAdded:Connect(invalidate)
	workspace.DescendantRemoving:Connect(invalidate)

	stepConn = RunService.Heartbeat:Connect(function()
		updatePrompt(os.clock())
	end)

	-- MORT / RESPAWN : le serveur relache deja le seau de son cote. Ici on oublie l'etat local, sinon on
	-- croirait encore porter un seau qui n'est plus dans nos mains.
	player.CharacterRemoving:Connect(function()
		carriedBin = nil
		stopTracks()
		hideOurs()
		setActionBound(false)
	end)
end

-- Coupe tout : boucle, connexions, animations, prompt et bind. Celui qui cree est celui qui nettoie, et il
-- nettoie TOUT.
function BinCarryController.stop()
	if stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
	stopTracks()
	hideOurs()
	setActionBound(false)
	carriedBin = nil
end

return BinCarryController
