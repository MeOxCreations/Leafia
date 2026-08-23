--!strict
-- PRISE / PORTAGE / REPOSE du SEAU, cote client. PORTAGE LIBRE : on se balade ou on veut, on repose ou on veut.
-- Aucun rail, aucun aimant vers une haie -- contrairement a LadderMoveController, dont tout le systeme de focus
-- est volontairement absent ici.
--
--   PRISE   : on joue TakeAnimation ; au marqueur TakeBucketEvent (la main se referme), on demande au SERVEUR de
--             souder le seau ; au marqueur EndTakeEventBin (fin du geste), le geste s'efface et DECOUVRE la
--             pose de portage.
--
-- LES DEUX ANIMATIONS SE SUPERPOSENT, elles ne se relaient pas. La pose de portage (Action2) demarre EN MEME
-- TEMPS que le geste (Action3) et joue en dessous, masquee. La fin du geste ne fait que la reveler.
--
-- C'est ce qui supprime le soubresaut qu'on voyait entre les deux : tant qu'on les enchainait, il existait un
-- instant sans pose -- le temps de charger l'asset, ou une image de signal differe -- et le corps y repassait
-- par la position neutre. Il n'y a plus d'instant a combler. Et les priorites doivent DIFFERER : a priorite
-- egale Roblox ne choisit pas, il moyenne les deux poses.
--   REPOSE  : on rejoue TakeAnimation A L'ENVERS depuis sa derniere image ; en repassant TakeBucketEvent dans
--             l'autre sens (la main s'ouvre), on demande au serveur de retirer le joint et de poser le seau AU
--             SOL devant nous.
--
-- POURQUOI ON SOUDE AU MARQUEUR ET PAS A L'APPUI. L'echelle, elle, soude des l'appui : elle est enorme et le
-- geste est rapide, le saut ne se voit pas. Un seau pose par terre, lui, se teleporterait dans la main avant que
-- la main l'atteigne.
--
-- CE SONT LES MARQUEURS QUI MENENT, et c'est voulu : deplacer l'un d'eux dans l'editeur change le geste sans
-- toucher au code. Chacun a son filet, parce qu'un marqueur muet (asset pas encore charge a la 1re lecture de la
-- session) voudrait dire soit un seau qui ne se prend PAS, soit un joueur fige sans pose de portage.

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
local lastDebugAt = 0
local promptTarget: Model? = nil
local promptAnchor: BasePart? = nil
local actionBound = false
local takeTrack: AnimationTrack? = nil
local carryTrack: AnimationTrack? = nil
local markerConn: RBXScriptConnection? = nil
local endConn: RBXScriptConnection? = nil
-- Boucle du geste de prise : elle fait pivoter le joueur vers le seau et tient les filets des deux marqueurs.
local holdConn: RBXScriptConnection? = nil
-- La part qu'on a ancree pour figer le joueur pendant le geste. On retient LAQUELLE, pas un simple booleen :
-- celui qui modifie est celui qui restaure, et le personnage peut avoir change entre-temps.
local anchoredRoot: BasePart? = nil
-- Une marche d'approche est en cours. Sans ce drapeau, re-appuyer pendant le trajet en lancerait une seconde.
local approaching = false
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

local function getHumanoid(): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
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
	if endConn then
		endConn:Disconnect()
		endConn = nil
	end
	if holdConn then
		holdConn:Disconnect()
		holdConn = nil
	end
end

-- Rend au joueur sa liberte de mouvement. Idempotent : appele a la fin du geste ET a tout abandon (repose,
-- changement de personnage, autre portage). Un ancrage oublie laisserait le joueur plante pour toujours.
local function releaseStance()
	local root = anchoredRoot
	anchoredRoot = nil
	if root and root.Parent then
		root.Anchored = false
	end
end

local function stopTracks()
	clearTakeConns()
	releaseStance()
	if takeTrack then
		takeTrack:Stop(0.1)
		takeTrack = nil
	end
	if carryTrack then
		carryTrack:Stop(0.15)
		carryTrack = nil
	end
end

-- Pose de PORTAGE. Elle demarre DES LE DEBUT du geste de prise, pas a sa fin, et elle joue EN DESSOUS de lui :
-- le geste est en Action3, elle en Action2, donc il la masque entierement tant qu'il dure.
--
-- C'EST CE QUI SUPPRIME LE SOUBRESAUT ENTRE LES DEUX ANIMATIONS. Avant, elle etait chargee et lancee a
-- l'instant precis de la bascule -- un instant ou le geste s'effaçait deja. Il suffisait d'une milliseconde de
-- retard (chargement de l'asset, signal differe d'une image) pour que le corps repasse par la position neutre.
-- Rien ne pouvait combler ce trou, puisqu'il n'y avait aucune pose EN DESSOUS.
--
-- Deux priorites DIFFERENTES, et c'est essentiel : a priorite EGALE Roblox ne choisit pas, il MELANGE les deux
-- poses. On verrait alors une moyenne des bras pendant tout le fondu.
--
-- Elle ne cle QUE les bras et le torse, donc la marche continue de tourner par-dessous.
local function playCarryPose()
	local animator = getAnimator()
	if not animator or not carriedBin then
		return
	end
	if carryTrack then
		carryTrack:Stop(BinConfigs.CARRY_FADE)
		carryTrack = nil
	end
	local carry = loadTrack(animator, BinConfigs.CARRY_ANIM)
	if not carry then
		return
	end
	carryTrack = carry
	carry.Priority = Enum.AnimationPriority.Action2
	carry.Looped = true
	carry:Play(BinConfigs.CARRY_FADE)
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
	-- PIVOT FACE AU SEAU, SANS UN STUD DE DEPLACEMENT. On ne fabrique pas une marche : le joueur se tourne, la
	-- main se referme face a l'objet, et c'est tout. On ne garde que la ROTATION (la position reste vive), sinon
	-- le lerp figerait aussi ses coordonnees et il resterait colle en l'air s'il saute au meme moment.
	local hrp = getRoot()
	local binPart = binRoot(model)
	local fromRot: CFrame? = nil
	local toRot: CFrame? = nil
	if hrp and binPart then
		local flat = binPart.Position - hrp.Position
		flat = Vector3.new(flat.X, 0, flat.Z)
		if flat.Magnitude >= BinConfigs.FACE_MIN_DIST then
			local start = hrp.CFrame
			local target = CFrame.lookAt(start.Position, start.Position + flat.Unit)
			fromRot = start - start.Position
			toRot = target - target.Position
		end
		-- FIGE PENDANT LE GESTE, mais JAMAIS EN L'AIR : figer quelqu'un en plein saut se verrait bien plus que
		-- le probleme qu'on corrige.
		local humanoid = getHumanoid()
		if
			BinConfigs.ANCHOR_DURING_TAKE
			and humanoid
			and humanoid.FloorMaterial ~= Enum.Material.Air
			and not hrp.Anchored
		then
			releaseStance()
			hrp.Anchored = true
			anchoredRoot = hrp
		end
	end

	-- LA POSE DE PORTAGE PART MAINTENANT, pas a la fin du geste. Elle joue dessous, masquee, et sera simplement
	-- REVELEE quand le geste s'efface. Plus aucun instant sans pose, donc plus de soubresaut.
	playCarryPose()

	takeTrack = track
	-- ACTION3, AU-DESSUS de la pose de portage (Action2). Deux pistes de MEME priorite se melangeraient.
	track.Priority = Enum.AnimationPriority.Action3
	-- LOOPED = FALSE, et ce n'est plus un probleme. Une piste non bouclee se relache a sa derniere image : avant
	-- ca faisait retomber les bras, faute de pose en dessous. Maintenant ce relachement REVELE le portage --
	-- c'est devenu le mecanisme, plus le bug. Et une piste non bouclee ne peut pas reboucler d'une image au
	-- mauvais moment, ce qui supprime l'autre moitie du soubresaut.
	track.Looped = false

	local fired = false
	clearTakeConns()
	-- Le drapeau garantit UN seul envoi : marqueur et filet demanderaient sinon la prise deux fois.
	-- On ne coupe QUE le marqueur de prise ici, surtout pas clearTakeConns : ca tuerait la surveillance de fin.
	local function doGrab()
		if fired or carriedBin ~= model then
			return
		end
		fired = true
		if markerConn then
			markerConn:Disconnect()
			markerConn = nil
		end
		request(model, "grab")
	end

	-- FIN DU GESTE : on l'efface en fondu, ce qui DECOUVRE la pose de portage deja en place dessous.
	--
	-- Si ce marqueur se tait, la piste finit d'elle-meme et se relache : elle decouvre exactement la meme pose,
	-- juste un poil plus tard. Il n'y a donc plus de filet a prevoir ici -- l'echec est devenu inoffensif.
	local function finish()
		clearTakeConns()
		releaseStance()
		-- Le geste est fini : le seau DOIT etre en main, quoi qu'il se soit passe avant.
		doGrab()
		track:Stop(BinConfigs.CARRY_FADE)
		if takeTrack == track then
			takeTrack = nil
		end
	end

	markerConn = track:GetMarkerReachedSignal(BinConfigs.TAKE_EVENT):Connect(doGrab)
	endConn = track:GetMarkerReachedSignal(BinConfigs.END_EVENT):Connect(finish)
	track:Play(BinConfigs.TAKE_FADE)

	local elapsed = 0
	holdConn = RunService.Heartbeat:Connect(function(dt)
		-- Le joueur a repose le seau, ou une autre prise a pris la main : on lache tout.
		if takeTrack ~= track or carriedBin ~= model then
			clearTakeConns()
			releaseStance()
			return
		end
		elapsed += dt

		-- LE PIVOT. Fraction du temps ecoule, pas un lerp exponentiel : celui-ci n'atteindrait jamais sa cible et
		-- laisserait le joueur legerement de travers pour toujours.
		if fromRot and toRot and hrp and hrp.Parent then
			local a = if BinConfigs.FACE_TURN_TIME > 0
				then math.min(elapsed / BinConfigs.FACE_TURN_TIME, 1)
				else 1
			hrp.CFrame = CFrame.new(hrp.Position) * (fromRot :: CFrame):Lerp(toRot :: CFrame, a)
			if a >= 1 then
				fromRot = nil
			end
		end
		-- FILET DE PRISE, si TAKE_EVENT se tait. Sans effet tant que le marqueur parle.
		if elapsed >= BinConfigs.TAKE_GRAB_FALLBACK then
			doGrab()
		end
	end)
end

-- REPOSE : TAKE_ANIM JOUEE A L'ENVERS. On part de sa derniere image -- celle que la pose de portage tient deja,
-- donc le raccord ne se voit pas -- et on remonte le temps. Le seau quitte les mains quand la MAIN S'OUVRE, pas
-- a l'appui : en marche arriere c'est le meme marqueur qu'a la prise, repasse dans l'autre sens.
local function placeBin()
	local model = carriedBin
	if not model then
		return
	end
	carriedBin = nil
	clearTakeConns()
	releaseStance()
	-- L'ELAN DU JOUEUR EST COUPE DES L'APPUI, pas a la fin : sans ca il repose son seau en pleine course et le
	-- geste glisse a cote de lui. C'est le serveur qui pilote la vitesse -- il en est le seul ecrivain -- et il
	-- la rend tout seul, meme si ce geste est interrompu.
	request(model, "placeStart")

	local released = false
	local function doRelease()
		if released then
			return
		end
		released = true
		request(model, "place")
	end
	-- FILET DUR, sur son PROPRE minuteur. Tout le reste peut etre coupe par une nouvelle prise ou un respawn :
	-- lui non. Sans lui, un marqueur muet laisserait le seau soude au joueur pour toujours.
	task.delay(BinConfigs.PLACE_TIMEOUT, doRelease)

	local animator = getAnimator()
	local track = if animator then loadTrack(animator, BinConfigs.TAKE_ANIM) else nil
	if not track then
		-- Sans animation on repose quand meme : garder un seau colle serait pire que perdre le geste.
		stopTracks()
		doRelease()
		return
	end

	-- L'ancien geste laisse la place : deux pistes de MEME priorite se MELANGENT, elles ne se remplacent pas.
	if takeTrack then
		takeTrack:Stop(BinConfigs.TAKE_FADE)
	end
	takeTrack = track
	-- ACTION3, comme a la prise : au-dessus de la pose de portage, qu'il masque le temps de s'en debarrasser.
	track.Priority = Enum.AnimationPriority.Action3
	-- LOOPED = FALSE : arrivee a zero la piste se relache, et il n'y a plus rien dessous -- la marche reprend.
	track.Looped = false
	track:Play(BinConfigs.TAKE_FADE)
	track.TimePosition = math.max(track.Length - 0.001, 0)
	track:AdjustSpeed(-BinConfigs.PLACE_SPEED)

	-- La pose de portage s'efface pendant que le geste inverse monte : fondu croise, comme a la prise.
	if carryTrack then
		carryTrack:Stop(BinConfigs.CARRY_FADE)
		carryTrack = nil
	end

	markerConn = track:GetMarkerReachedSignal(BinConfigs.TAKE_EVENT):Connect(doRelease)

	local elapsed = 0
	holdConn = RunService.Heartbeat:Connect(function(dt)
		-- Une nouvelle prise a pris la main : ce geste ne nous appartient plus. Le filet dur reste en place.
		if takeTrack ~= track then
			clearTakeConns()
			return
		end
		elapsed += dt
		if elapsed < BinConfigs.PLACE_SETTLE then
			return
		end
		-- Retour termine (ou trop long) : on lache et on rend la main a la marche.
		if track.TimePosition <= 0.001 or elapsed >= BinConfigs.PLACE_TIMEOUT then
			doRelease()
			clearTakeConns()
			track:Stop(BinConfigs.TAKE_FADE)
			if takeTrack == track then
				takeTrack = nil
			end
		end
	end)
end

-- APPROCHE : le joueur MARCHE jusqu'au seau, puis le prend. C'est lui qui va a l'objet, pas l'objet qui lui
-- saute dans les bras.
--
-- Si on est DEJA sur place, on ne fabrique AUCUN deplacement. Fabriquer une marche pour un joueur deja arrive a
-- coute un systeme entier sur l'echelle, pour rien : on mesure d'abord, on marche seulement si besoin.
--
-- On s'arrete DU COTE D'OU L'ON VIENT. Un seau se prend de n'importe quel bord : aucun contournement a faire,
-- contrairement au guidon d'une tondeuse, qui est derriere elle et qu'il faut aller chercher.
local function approachThenPickUp(model: Model)
	if approaching or carriedBin then
		return
	end
	local humanoid = getHumanoid()
	local hrp = getRoot()
	local binPart = binRoot(model)
	if not (BinConfigs.APPROACH_ENABLED and humanoid and hrp and binPart) then
		pickUp(model)
		return
	end

	local away = hrp.Position - binPart.Position
	away = Vector3.new(away.X, 0, away.Z)
	away = if away.Magnitude > 1e-3 then away.Unit else hrp.CFrame.LookVector
	-- Point d'arret a HAUTEUR DU JOUEUR : MoveTo vise un point au sol, viser la hauteur du seau ferait
	-- travailler l'Humanoid contre la pente pour rien.
	local spot = binPart.Position + away * BinConfigs.APPROACH_STOP_DIST
	spot = Vector3.new(spot.X, hrp.Position.Y, spot.Z)

	if ((spot - hrp.Position) * Vector3.new(1, 0, 1)).Magnitude <= BinConfigs.APPROACH_SKIP_DIST then
		pickUp(model)
		return
	end

	approaching = true
	task.spawn(function()
		local done = false
		local conn = humanoid.MoveToFinished:Connect(function()
			done = true
		end)
		humanoid:MoveTo(spot)
		-- PLAFOND DE TEMPS. Mieux vaut une prise un peu de travers qu'un joueur bloque parce qu'un caillou lui
		-- barre le chemin : MoveTo n'abandonne jamais tout seul.
		local deadline = os.clock() + BinConfigs.APPROACH_TIMEOUT
		while not done and os.clock() < deadline do
			task.wait()
		end
		conn:Disconnect()
		approaching = false
		-- Le trajet a pris du temps : quelqu'un a pu prendre le seau entre-temps, ou il a pu disparaitre.
		if model.Parent and not model:GetAttribute(BinConfigs.CARRIED_ATTRIBUTE) then
			pickUp(model)
		end
	end)
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
		approachThenPickUp(target)
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

-- Dit ce que la detection VOIT, pas ce qu'on croit qu'elle voit. "Aucun prompt" couvre plusieurs causes qui se
-- ressemblent a l'ecran (aucun seau trouve / trop loin / deja porte / on porte autre chose) : les separer ici
-- evite de chercher au mauvais endroit.
local function debugTrace(now: number)
	if not BinConfigs.DEBUG or now - lastDebugAt < BinConfigs.DEBUG_INTERVAL then
		return
	end
	lastDebugAt = now

	local root = getRoot()
	if not root then
		print("[BinCarry] pas de HumanoidRootPart (personnage pas encore la)")
		return
	end
	local all = getBins(now)
	if #all == 0 then
		print(`[BinCarry] AUCUN model commencant par "{BinConfigs.MODEL_PREFIX}" dans le Workspace`)
		return
	end

	local nearest, nearestDist, carriedBy = nil, math.huge, nil
	for _, model in ipairs(all) do
		local binPart = binRoot(model)
		if binPart then
			local dist = ((binPart.Position - root.Position) * Vector3.new(1, 0, 1)).Magnitude
			if dist < nearestDist then
				nearest, nearestDist = model, dist
				carriedBy = model:GetAttribute(BinConfigs.CARRIED_ATTRIBUTE)
			end
		else
			print(`[BinCarry] {model:GetFullName()} ignore : ni PrimaryPart ni {BinConfigs.ROOT_NAME}`)
		end
	end

	if not nearest then
		print(`[BinCarry] {#all} model(s) trouve(s), mais AUCUN n'a de reference de position`)
		return
	end
	print(
		`[BinCarry] {#all} seau(x) | plus proche "{nearest.Name}" a {string.format("%.1f", nearestDist)} studs `
			.. `(rayon {BinConfigs.DETECT_RADIUS}) | porte par {tostring(carriedBy)} | occupe ailleurs : {tostring(busyWithSomethingElse())} `
			.. `| porte : {tostring(carriedBin ~= nil)} | touche branchee : {tostring(actionBound)}`
	)
end

local function updatePrompt(now: number)
	debugTrace(now)
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
		approaching = false
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
	approaching = false
end

return BinCarryController
