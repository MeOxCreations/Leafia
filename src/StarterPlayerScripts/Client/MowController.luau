--!strict
-- LA TONDEUSE, cote client. Trois choses, et rien d'autre :
--   1. le prompt "[E] TAKE" quand on s'approche (detection RADIALE, aucun angle mort)
--   2. l'appel de la COUPE, chaque image, sous la part CutZone
--   3. la rotation des ROUES, calculee sur la distance reellement parcourue
--
-- Le PORTAGE lui-meme appartient au serveur (MowService) : c'est lui qui soude la tondeuse au porteur, donc tout
-- le monde la voit au meme endroit. Ici on ne fait que demander, afficher et couper.
--
-- POURQUOI LA COUPE EST CLIENTE : l'herbe de zone est fabriquee par CHAQUE client (GrassZoneController), elle
-- n'existe pas cote serveur. Faire transiter la coupe par le reseau reviendrait a payer cher pour rien. Le jour ou
-- tondre rapportera un cheque, c'est le serveur qui comptera -- pas ces appels-la.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local MowConfigs = require(ReplicatedStorage.Modules.Configs.MowConfigs)
local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)
local GrassZoneController = require(script.Parent.GrassZoneController)

local MowController = {}

local ACTION_NAME = "LeafiaMowerCarry"
-- Touche reelle du bind. Volontairement en dur plutot que `Enum.KeyCode[PROMPT_KEY]` : une indexation par
-- chaine n'est pas verifiable par le type-checker, et une faute dans la config donnerait une erreur a
-- l'execution au lieu d'un rouge a l'ecriture. PROMPT_KEY ne sert qu'a AFFICHER la touche.
local ACTION_KEY = Enum.KeyCode.E
-- REVELATION : touche MAINTENUE qui allume ce qui reste a tondre. G, libre dans tout le projet.
local HIGHLIGHT_KEY = Enum.KeyCode.G
local CARRIED_ATTRIBUTE = "LeafiaCarriedBy" -- pose par MowService : UserId du porteur
local RESCAN_INTERVAL = 2 -- secondes entre deux balayages du Workspace (streaming : une tondeuse peut arriver tard)
local PROMPT_INTERVAL = 0.15 -- on ne teste pas la proximite a chaque image, ca ne se voit pas et ca coute

local player = Players.LocalPlayer

local carryRemote: RemoteEvent? = nil
local mowers: { Model } = {}
local lastScanAt = 0
local lastPromptAt = 0
local lastActionAt = 0
local promptTarget: Model? = nil -- tondeuse dont le prompt est affiche (pour ne le remontrer qu'au CHANGEMENT)
local actionBound = false
local lastCutPos: Vector3? = nil -- position de coupe a l'image precedente : donne la distance parcourue
local wheelAngle = 0
local connection: RBXScriptConnection? = nil

local function rootOf(model: Model): BasePart?
	local root = model.PrimaryPart or model:FindFirstChild(MowConfigs.ROOT_NAME)
	return if root and root:IsA("BasePart") then root else nil
end

-- Part sur laquelle on ACCROCHE le badge. Distincte de la racine : la racine sert a MESURER (detection), elle est
-- choisie pour etre fixe, pas pour etre jolie. Le guidon, lui, est a hauteur des mains -- c'est la qu'on lit
-- "prendre". Deux besoins differents, deux parts.
local function promptAnchorOf(model: Model): BasePart?
	local named = model:FindFirstChild(MowConfigs.PROMPT_PART_NAME, true)
	if named and named:IsA("BasePart") then
		return named
	end
	return rootOf(model)
end

-- Balayage du Workspace. RE-SCAN periodique et non une seule fois au boot : avec le streaming, une tondeuse
-- posee loin n'existe pas encore chez le client au demarrage, et un scan unique ne la verrait jamais.
local function refreshMowers(now: number)
	if now - lastScanAt < RESCAN_INTERVAL then
		return
	end
	lastScanAt = now
	table.clear(mowers)
	for _, d in ipairs(Workspace:GetDescendants()) do
		-- Filtre bon marche d'abord : IsA("Model") ecarte des milliers de parts avant toute comparaison de nom.
		if d:IsA("Model") and d.Name == MowConfigs.MODEL_NAME and rootOf(d) then
			mowers[#mowers + 1] = d
		end
	end
end

-- La tondeuse que JE porte, s'il y en a une.
local function myMower(): Model?
	for _, model in ipairs(mowers) do
		if model:GetAttribute(CARRIED_ATTRIBUTE) == player.UserId then
			return model
		end
	end
	return nil
end

-- Tondeuse LIBRE la plus proche, sous DETECT_RADIUS. Distance HORIZONTALE a une part FIXE (la racine), jamais a
-- GetPivot : le pivot d'un Model suit sa bounding box, donc la CutZone soudee le decalerait. Un rayon plutot
-- qu'une box : colle a un bout de la tondeuse, une box laisse un angle mort et le prompt ne sort pas.
local function freeMowerNear(from: Vector3): (Model?, BasePart?)
	local best, bestRoot = nil, nil
	local bestDist = MowConfigs.DETECT_RADIUS
	for _, model in ipairs(mowers) do
		if model:GetAttribute(CARRIED_ATTRIBUTE) == nil then
			local root = rootOf(model)
			if root then
				local d = root.Position - from
				local dist = math.sqrt(d.X * d.X + d.Z * d.Z)
				if dist < bestDist then
					bestDist, best, bestRoot = dist, model, root
				end
			end
		end
	end
	return best, bestRoot
end

-- OU on coupe, et sur quel rayon. La part CutZone (posee par scripts/studio/) fait autorite : sa position dit le
-- point, sa largeur donne le rayon. Absente, on retombe devant la racine -- le jeu tourne quand meme, il coupe
-- juste moins juste, et le message le DIT une fois plutot que d'echouer en silence.
local warnedNoCutZone = false
local function cutPointOf(model: Model): (Vector3?, number)
	local zone = model:FindFirstChild(MowConfigs.CUT_ZONE_NAME, true)
	if zone and zone:IsA("BasePart") then
		return zone.Position, zone.Size.X * 0.5
	end
	local root = rootOf(model)
	if not root then
		return nil, 0
	end
	if not warnedNoCutZone then
		warnedNoCutZone = true
		warn(
			`[MowController] Pas de part "{MowConfigs.CUT_ZONE_NAME}" sous {model.Name} : coupe approximative. `
				.. "Lancer scripts/studio/CreerZoneDeCoupeTondeuse.lua dans la barre de commandes."
		)
	end
	return (root.CFrame * CFrame.new(0, 0, -MowConfigs.FALLBACK_FORWARD)).Position, MowConfigs.FALLBACK_RADIUS
end

-- ROUES. L'angle vient de la DISTANCE parcourue, pas du temps : la roue colle donc au sol quelle que soit
-- l'allure du joueur, et elle s'arrete pile quand il s'arrete. Une animation, elle, patinerait.
local function spinWheels(model: Model, distance: number)
	local root = rootOf(model)
	if not root or distance <= 0 then
		return
	end
	for _, name in ipairs(MowConfigs.WHEEL_MOTORS) do
		local motor = root:FindFirstChild(name)
		if motor and motor:IsA("Motor6D") then
			local wheel = motor.Part1
			-- Rayon MESURE sur la roue plutot que devine : changer la taille du modele ne demande alors aucun reglage.
			local radius = MowConfigs.WHEEL_RADIUS_FALLBACK
			if wheel then
				local s = wheel.Size
				radius = math.max(s.X, s.Y, s.Z) * 0.5
			end
			if radius > 1e-3 then
				local delta = MowConfigs.WHEEL_DIRECTION * distance / radius
				wheelAngle = (wheelAngle + delta) % (math.pi * 2)
				local axis = MowConfigs.WHEEL_AXIS
				local spin = if axis == "Y"
					then CFrame.Angles(0, wheelAngle, 0)
					elseif axis == "Z" then CFrame.Angles(0, 0, wheelAngle)
					else CFrame.Angles(wheelAngle, 0, 0)
				-- On ecrit C0, PAS Transform : Transform appartient a l'Animator. Corollaire, ces joints ne doivent
				-- etre cles dans AUCUNE animation, sinon deux ecrivains se disputent le meme joint.
				local base = motor:GetAttribute("LeafiaBaseC0")
				if typeof(base) ~= "CFrame" then
					base = motor.C0
					motor:SetAttribute("LeafiaBaseC0", base)
				end
				motor.C0 = (base :: CFrame) * spin
			end
		end
	end
end

local function request(model: Model, phase: string)
	if not carryRemote then
		return
	end
	if os.clock() - lastActionAt < MowConfigs.ACTION_DEBOUNCE then
		return -- la touche ET le bouton tactile peuvent tirer ensemble : un seul geste passe
	end
	lastActionAt = os.clock()
	carryRemote:FireServer(model, phase)
end

-- OU le joueur doit se tenir pour prendre la tondeuse : derriere le point le plus ARRIERE de la machine, face a
-- elle. L'axe d'avancee est MESURE (RootPart -> CutZone, posee a l'avant), jamais devine.
-- Rend le point au sol et la direction a regarder, ou nil si on ne sait pas de quel cote regarde la machine.
local function grabSpot(model: Model): (Vector3?, Vector3?)
	local root = rootOf(model)
	local zone = model:FindFirstChild(MowConfigs.CUT_ZONE_NAME, true)
	if not (root and zone and zone:IsA("BasePart")) then
		return nil, nil
	end
	local d = zone.Position - root.Position
	d = Vector3.new(d.X, 0, d.Z)
	if d.Magnitude < 1e-3 then
		return nil, nil
	end
	local forward = d.Unit
	-- Meme geometrie que cote serveur : recul de la machine + l'ecart de confort. On repart du plus loin en
	-- arriere, pas de la racine, sinon on se plante au milieu de la tondeuse.
	local back = 0
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= MowConfigs.CUT_ZONE_NAME and part.Transparency < 1 then
			back = math.max(back, -(part.Position - root.Position):Dot(forward))
		end
	end
	return root.Position - forward * (back + MowConfigs.CARRY_GAP), forward
end

-- APPROCHE : le joueur MARCHE jusqu'au guidon, puis prend. C'est lui qui va a la machine, pas l'inverse.
--
-- Si on est DEJA sur place, on ne fabrique AUCUN deplacement : construire une marche forcee pour un joueur deja
-- arrive a deja coute un systeme entier sur l'echelle. On mesure d'abord, on marche seulement si besoin.
local approaching = false
local function approachThenGrab(model: Model, onArrived: () -> ())
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local spot, facing = grabSpot(model)
	if not (MowConfigs.APPROACH_ENABLED and humanoid and hrp and hrp:IsA("BasePart") and spot and facing) then
		onArrived()
		return
	end

	local flat = Vector3.new(hrp.Position.X - spot.X, 0, hrp.Position.Z - spot.Z)
	if flat.Magnitude <= MowConfigs.APPROACH_SKIP_DIST then
		onArrived() -- deja arrive : rien a animer
		return
	end

	approaching = true
	task.spawn(function()
		local done = false
		local conn = (humanoid :: Humanoid).MoveToFinished:Connect(function()
			done = true
		end)
		;(humanoid :: Humanoid):MoveTo(spot :: Vector3)

		-- Timeout : mieux vaut une prise un peu de travers qu'un joueur bloque par un caillou.
		local until_ = os.clock() + MowConfigs.APPROACH_TIMEOUT
		while not done and os.clock() < until_ do
			task.wait()
		end
		conn:Disconnect()

		-- PIVOT vers la machine. Sans lui, un joueur venu par l'avant arrive DOS a elle, et la soudure la
		-- reposerait de l'autre cote. On tourne le personnage, on ne le deplace pas.
		local root2 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root2 and root2:IsA("BasePart") then
			local from = root2.CFrame
			local to = CFrame.lookAt(from.Position, from.Position + (facing :: Vector3))
			local t0 = os.clock()
			while os.clock() - t0 < MowConfigs.APPROACH_TURN_TIME do
				local a = (os.clock() - t0) / MowConfigs.APPROACH_TURN_TIME
				root2.CFrame = from:Lerp(to, a)
				task.wait()
			end
			root2.CFrame = to
		end
		-- Relache SEULEMENT ici : le pivot fait partie du geste, un second appui pendant qu'il tourne
		-- relancerait une marche par-dessus celle qui vient de finir.
		approaching = false
		onArrived()
	end)
end

-- UN SEUL declencheur pour prendre ET reposer : la meme touche, le meme bouton, le meme anti-spam.
local function toggleCarry()
	local mine = myMower()
	if mine then
		request(mine, "place")
		return
	end
	if approaching then
		return -- deja en train de rejoindre une tondeuse : on ne relance pas la marche par-dessus
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local target = freeMowerNear(hrp.Position)
		if target then
			approachThenGrab(target, function()
				request(target, "grab")
			end)
		end
	end
end

-- La touche n'est branchee QUE quand l'action a un sens (pres d'une tondeuse, ou en train d'en pousser une).
-- createTouchButton fait apparaitre un bouton a l'ecran sur tactile, et bind la touche sur PC, d'un seul geste :
-- sans lui, deposer la tondeuse serait injouable sans clavier.
local function setActionBound(active: boolean)
	if active == actionBound then
		return
	end
	actionBound = active
	if active then
		ContextActionService:BindAction(ACTION_NAME, function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				toggleCarry()
			end
			return Enum.ContextActionResult.Pass
		end, true, ACTION_KEY)
		-- MAINTENUE, pas une bascule : on jette un oeil, on ne joue pas dedans. Un mode qu'on peut laisser allume
		-- deviendrait le mode NORMAL, et la pelouse ne serait plus jamais regardee pour elle-meme.
		-- End ET Cancel : perdre le focus (alt-tab, une UI qui s'ouvre) doit eteindre, sinon ca reste allume a vie.
		ContextActionService:BindAction(MowConfigs.HIGHLIGHT_ACTION, function(_, state: Enum.UserInputState)
			GrassZoneController.setHighlight(state == Enum.UserInputState.Begin)
			return Enum.ContextActionResult.Pass
		end, true, HIGHLIGHT_KEY)
	else
		ContextActionService:UnbindAction(ACTION_NAME)
		ContextActionService:UnbindAction(MowConfigs.HIGHLIGHT_ACTION)
		-- On s'eloigne la touche enfoncee : sans ca la pelouse resterait allumee pour de bon.
		GrassZoneController.setHighlight(false)
	end
end

-- Le prompt est un SINGLETON partage (dialogue de Papi, echelle, boite aux lettres...). On ne cache donc QUE
-- le notre : appeler hide() sans regarder ferait disparaitre celui d'un autre en plein milieu.
local function hideOurs()
	local anchor = if promptTarget then promptAnchorOf(promptTarget) else nil
	if anchor and InteractionPrompt.currentTarget() == anchor then
		InteractionPrompt.hide()
	end
	promptTarget = nil
end

local function updatePrompt(hrp: BasePart, carrying: Model?)
	if carrying then
		-- On pousse : plus de badge sur la tondeuse (on est dessus), mais l'action reste branchee pour la reposer.
		hideOurs()
		setActionBound(true)
		return
	end

	local target, root = freeMowerNear(hrp.Position)
	if target and root then
		setActionBound(true)
		-- On re-montre au CHANGEMENT de tondeuse, mais AUSSI quand le prompt ne nous appartient plus : une autre
		-- feature a pu prendre le singleton (un dialogue s'ouvre pendant qu'on est a cote). Sans ce second test,
		-- notre prompt disparaitrait pour de bon alors que rien n'a change de notre point de vue.
		local anchor = promptAnchorOf(target) or root
		if target ~= promptTarget or InteractionPrompt.currentTarget() ~= anchor then
			promptTarget = target
			InteractionPrompt.show(
				anchor,
				MowConfigs.PROMPT_KEY,
				MowConfigs.PROMPT_LABEL,
				MowConfigs.PROMPT_OFFSET,
				toggleCarry,
				MowConfigs.PROMPT_TITLE
			)
		end
	elseif promptTarget then
		hideOurs()
		setActionBound(false)
	else
		setActionBound(false)
	end
end

local function update(dt: number)
	local now = os.clock()
	refreshMowers(now)

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end

	local mine = myMower()

	if now - lastPromptAt >= PROMPT_INTERVAL then
		lastPromptAt = now
		updatePrompt(hrp :: BasePart, mine)
	end

	if not mine then
		lastCutPos = nil
		return
	end

	local point, radius = cutPointOf(mine)
	if not point then
		return
	end

	-- DISTANCE PARCOURUE, a l'horizontale : monter une pente ne doit pas faire tourner les roues plus vite, et
	-- sauter ne doit pas les faire tourner du tout.
	local distance = 0
	if lastCutPos then
		local d = point - lastCutPos
		distance = math.sqrt(d.X * d.X + d.Z * d.Z)
	end
	lastCutPos = point

	spinWheels(mine, distance)
	-- La coupe tourne MEME A L'ARRET : rester sur place finit de tondre la touffe sous le carter, au lieu de laisser
	-- un rond a moitie coupe qu'on ne comprend pas.
	GrassZoneController.mowAt(point, radius, dt)
end

function MowController.init()
	-- getRemote cache un WaitForChild : en ligne droite dans un init, il gele TOUT le boot le temps du timeout.
	task.spawn(function()
		carryRemote = RemoteSetup.getRemote("SetMowerCarry", "Mow") :: RemoteEvent
	end)

	-- On branche la boucle MEME si aucune tondeuse n'est encore la : avec le streaming, "absente au demarrage" est
	-- un etat normal, et un `return` ici ne se rattraperait jamais. Elle sort en trois lignes tant qu'il n'y a rien.
	connection = RunService.Heartbeat:Connect(update)

	-- Nouveau perso : le prompt d'avant pointait sur une position morte, et on ne porte plus rien.
	player.CharacterAdded:Connect(function()
		hideOurs()
		lastCutPos = nil
		GrassZoneController.setHighlight(false)
		setActionBound(false)
	end)
end

function MowController.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	setActionBound(false)
	hideOurs()
	lastCutPos = nil
	GrassZoneController.setHighlight(false)
end

return MowController
