--!strict
-- DIDACTICIEL, cote client : ce qui GUIDE le joueur. Pendant de TutorialService, qui le pose deja face a la
-- maison du grand-pere.
--
-- Deux choses, dans cet ordre :
--   1. Un HALO QUI RESPIRE sur la porte. Il dit "viens ici" sans ecrire une consigne -- donc sans rien a
--      traduire, et sans interface posee par-dessus le monde.
--   2. Un PROMPT quand on arrive devant. C'est lui qui lance la mission.
--
-- Une fois la mission lancee, les deux s'eteignent POUR DE BON : le guidage a fait son travail, et un halo qui
-- continue de battre pendant la scene tirerait l'oeil hors du plan.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)
local Letterbox = require(ReplicatedStorage.Modules.UI.Core.Letterbox)
local Dialogue = require(ReplicatedStorage.Modules.UI.Core.Dialogue)
local SoundDuck = require(ReplicatedStorage.Modules.UI.Core.SoundDuck)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local TutorialConfigs = require(ReplicatedStorage.Modules.Configs.TutorialConfigs)
local SceneCamera = require(script.Parent.Utils.SceneCamera)

local player = Players.LocalPlayer

local TutorialController = {}

local door: Model? = nil
local highlight: Highlight? = nil
local anchor: BasePart? = nil
-- Point vise par le prompt : le CENTRE de la porte, pas sa PrimaryPart. Celle-ci est le "Handle", la CHARNIERE
-- posee sur le COTE, donc le badge sortait a cote de la porte. Le centre de la boite englobante ne depend
-- d'aucun choix de PrimaryPart, et il reste juste meme si on en change dans Studio.
local anchorPos = Vector3.zero
local lastScanAt = 0
local lastPromptAt = 0
local lastDebugAt = 0
local startedAt = 0
-- UN DRAPEAU PAR AVERTISSEMENT, pas un seul pour les deux. Partage, le premier manquant masque le second : la
-- porte absente ferait taire le message du Highlight absent, et on chercherait au mauvais endroit.
local warnedNoDoor = false
local warnedNoHighlight = false
local elapsed = 0
local doorHint = true
local missionStarted = false
local sceneEnded = false
local grandpaTrack: AnimationTrack? = nil
local doorTrack: AnimationTrack? = nil
local knockTrack: AnimationTrack? = nil
local shakeTrack: AnimationTrack? = nil
local tryTrack: AnimationTrack? = nil
local trySound: Sound? = nil
local promptShown = false
local actionBound = false
local conn: RBXScriptConnection? = nil

local function getRoot(): BasePart?
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

-- La porte, ou nil. RECHERCHE PAR NOM dans tout le Workspace, jamais par un chemin fixe : elle a deja demenage
-- une fois et elle redemenagera, et un chemin en dur transforme chaque rangement dans l'editeur en panne
-- silencieuse. Le balayage ne tourne QUE tant qu'elle n'est pas trouvee.
local function findDoor(): (Model?, BasePart?)
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == TutorialConfigs.DOOR_NAME then
			-- Reference FIXE, jamais GetPivot : le pivot d'un Model suit sa bounding box, donc ajouter la
			-- moindre part enfant le decale et le prompt part de travers sans que rien ne le signale.
			local part = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart", true)
			-- ON N'ACCEPTE QUE CE QUI EST UTILISABLE. Une porte sans aucune part ne sert a rien : soit ses parts
			-- ne sont pas encore repliquees (streaming), soit c'est un autre Model qui porte le meme nom. Dans
			-- les deux cas on continue de chercher au lieu de se figer sur elle.
			if part then
				return d, part
			end
		end
	end
	return nil, nil
end

-- Le prompt est un SINGLETON partage (echelle, tondeuse, seau, boite aux lettres). On ne cache donc QUE le
-- notre : appeler hide() sans regarder ferait disparaitre celui d'une autre feature en plein milieu.
local function hideOurs()
	if promptShown and InteractionPrompt.currentTarget() == anchorPos then
		InteractionPrompt.hide()
	end
	promptShown = false
end

-- La touche n'est branchee QUE quand l'action a un sens. createTouchButton fait apparaitre un bouton a l'ecran
-- sur tactile ET bind la touche sur PC : sans lui, le didacticiel serait infranchissable sans clavier.
local function setActionBound(active: boolean)
	if active == actionBound then
		return
	end
	actionBound = active
	if active then
		ContextActionService:BindAction(TutorialConfigs.ACTION_NAME, function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				-- Lu au moment de l'appui, donc bien apres que le module soit charge : pas d'appel au-dessus
				-- d'une definition, c'est le champ qui est resolu a l'usage.
				TutorialController.startMission()
			end
			-- Pass et pas Sink : E est partagee avec le seau et la tondeuse. Avaler l'input ici les casserait.
			return Enum.ContextActionResult.Pass
		end, true, TutorialConfigs.ACTION_KEY)
	else
		ContextActionService:UnbindAction(TutorialConfigs.ACTION_NAME)
	end
end

--- Allume ou eteint le halo de la porte. A appeler avec `false` quand la scene se lance : un halo qui continue
--- de respirer pendant une cinematique tire l'oeil hors du plan.
function TutorialController.setDoorHint(on: boolean)
	doorHint = on
	local halo = highlight
	if halo and halo.Parent and not on then
		halo.FillTransparency = TutorialConfigs.FILL_MAX
	end
end

-- CADRAGE DE LA SCENE. Une part posee dans Studio a le dernier mot ; sinon on cadre depuis le JOUEUR, qui fait
-- deja face a la porte. Se placer "devant la porte" supposerait de savoir quel axe du Model est son devant --
-- rien ne le garantit, ca vient du rig.
local function sceneCFrame(): CFrame?
	local placed = Workspace:FindFirstChild(TutorialConfigs.SCENE_CAM_NAME, true)
	if placed and placed:IsA("BasePart") then
		return placed.CFrame
	end
	local root = getRoot()
	if not root then
		return nil
	end
	local cf = root.CFrame
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local side = flat:Cross(Vector3.new(0, 1, 0))
	local pos = root.Position
		- flat * TutorialConfigs.SCENE_CAM_BACK
		+ Vector3.new(0, TutorialConfigs.SCENE_CAM_UP, 0)
		+ side * TutorialConfigs.SCENE_CAM_SIDE
	return CFrame.lookAt(pos, anchorPos + Vector3.new(0, TutorialConfigs.SCENE_LOOK_UP, 0))
end

-- Rend la main au joueur : la camera glisse vers la vue de jeu pendant que les barres repartent dans les bords.
-- Idempotent : la fin normale (l'animation du grand-pere s'acheve) et le filet de secours peuvent tirer tous les
-- deux, et le second ne doit pas relancer une sortie deja en cours.
local function endScene()
	if sceneEnded then
		return
	end
	sceneEnded = true
	SceneCamera.exit(TutorialConfigs.SCENE_CAM_OUT)
	Letterbox.hide(TutorialConfigs.SCENE_BARS_TIME)
	SoundDuck.restore(TutorialConfigs.SCENE_DUCK_TIME)
end

-- Cherche un Model par son NOM, comme la porte : on ne suppose aucun rangement.
local function findModel(name: string): Model?
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == name then
			return d
		end
	end
	return nil
end

local function animatorOf(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
end

local function stopTrack(track: AnimationTrack?)
	if track then
		track:Stop(0)
	end
end

local function playerAnimator(): Animator?
	local character = player.Character
	return if character then animatorOf(character) else nil
end

local function loadSceneTrack(animator: Animator, animName: string): AnimationTrack?
	local node: Instance? = ReplicatedStorage
	for _, part in ipairs(TutorialConfigs.SCENE_ANIM_FOLDER) do
		node = node and node:FindFirstChild(part)
	end
	local anim = node and node:FindFirstChild(animName)
	if not (anim and anim:IsA("Animation")) then
		warn(
			`[Tutorial] Animation "{animName}" introuvable dans `
				.. `ReplicatedStorage.{table.concat(TutorialConfigs.SCENE_ANIM_FOLDER, ".")}`
		)
		return nil
	end
	return animator:LoadAnimation(anim)
end

-- LA PORTE. Elle s'ouvre a MOITIE, se FIGE le temps que le grand-pere parle, puis finit de s'ouvrir et TIENT.
--
-- Le gel se fait a la VITESSE (AdjustSpeed 0), jamais par un Stop : arreter une piste lui fait rendre sa pose de
-- repos, donc la porte se refermerait d'un coup. Et elle reste bouclee pour la meme raison -- une piste non
-- bouclee se relache a sa derniere image.
local function openDoor()
	local model = door
	if not model then
		return
	end
	local animator = animatorOf(model)
	if not animator then
		warn(`[Tutorial] Pas d'Animator sous "{model.Name}" : la porte ne s'ouvrira pas.`)
		return
	end
	local track = loadSceneTrack(animator, TutorialConfigs.DOOR_ANIM)
	if not track then
		return
	end
	-- Le tremblement tourne sur le MEME Animator. Deux pistes de meme priorite se melangeraient : celle des
	-- coups a fini son travail, on la coupe avant que l'ouverture commence.
	if shakeTrack then
		shakeTrack:Stop(0)
		shakeTrack = nil
	end
	doorTrack = track
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true

	local midDone = false
	track:GetMarkerReachedSignal(TutorialConfigs.DOOR_MID_EVENT):Connect(function()
		if midDone then
			return
		end
		midDone = true
		track:AdjustSpeed(0)
		task.delay(TutorialConfigs.DOOR_PAUSE, function()
			if doorTrack == track and track.IsPlaying then
				track:AdjustSpeed(1)
			end
		end)
	end)
	track:GetMarkerReachedSignal(TutorialConfigs.DOOR_END_EVENT):Connect(function()
		-- Grand ouverte : on gele ici. La suite de la piste est vide, et la laisser courir la ferait reboucler.
		track:AdjustSpeed(0)
	end)
	track:Play()
end

-- LE GRAND-PERE MENE LA SCENE. Son animation declenche la porte, et sa fin termine la scene : c'est elle qui
-- sait combien de temps ca dure, pas une constante.
local function playGrandpa()
	local model = findModel(TutorialConfigs.GRANDPA_NAME)
	local animator = if model then animatorOf(model) else nil
	local track = if animator then loadSceneTrack(animator, TutorialConfigs.GRANDPA_ANIM) else nil
	if not track then
		if not model then
			warn(`[Tutorial] Model "{TutorialConfigs.GRANDPA_NAME}" introuvable : la scene se jouera a vide.`)
		elseif not animator then
			warn(`[Tutorial] Pas d'Animator sous "{TutorialConfigs.GRANDPA_NAME}" : la scene se jouera a vide.`)
		end
		-- FILET : sans lui le joueur resterait coince en camera scriptee, derriere des barres noires, sans aucun
		-- moyen d'en sortir. Une animation absente ne doit jamais devenir une partie bloquee.
		task.delay(TutorialConfigs.SCENE_HOLD, endScene)
		return
	end

	grandpaTrack = track
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	track:GetMarkerReachedSignal(TutorialConfigs.DOOR_START_EVENT):Connect(openDoor)
	-- C'EST LA FIN DE L'ANIMATION QUI TERMINE LA SCENE. Une duree en dur et une animation finissent toujours par
	-- se contredire, et c'est la duree qui a tort : elle ne suit pas quand on retouche l'animation.
	track.Stopped:Connect(endScene)
	track:Play()
end

-- IL S'ACHARNE SUR LA POIGNEE. Entre les coups et l'ouverture : le grand-pere se bat avec sa vieille porte.
-- Quand l'animation s'acheve, l'ouverture prend la suite -- c'est elle qui dit quand elle a fini, pas un delai
-- pose a cote qui se decalerait a la premiere retouche.
local function playTryOpen()
	local model = findModel(TutorialConfigs.GRANDPA_NAME)
	local animator = if model then animatorOf(model) else nil
	local track = if animator then loadSceneTrack(animator, TutorialConfigs.TRY_OPEN_ANIM) else nil
	if not track then
		-- ON DIT POURQUOI ON SAUTE. Sans ces deux messages l'etape disparait EN SILENCE : la scene s'enchaine
		-- normalement, rien ne casse, et on croit que le code ne joue pas l'animation alors qu'il ne trouve pas
		-- de quoi la jouer. `loadSceneTrack` parle deja quand c'est l'Animation qui manque ; ici on couvre les
		-- deux autres causes.
		if not model then
			warn(`[Tutorial] Model "{TutorialConfigs.GRANDPA_NAME}" introuvable : pas de geste de poignee.`)
		elseif not animator then
			warn(`[Tutorial] Pas d'Animator sous "{TutorialConfigs.GRANDPA_NAME}" : pas de geste de poignee.`)
		end
		playGrandpa() -- l'etape saute, la scene continue
		return
	end
	tryTrack = track
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	trySound = SoundUtils.play(TutorialConfigs.TRY_OPEN_SOUND, anchor)

	local chained = false
	track.Stopped:Connect(function()
		if chained then
			return
		end
		chained = true
		-- LE SON S'ARRETE AVEC LE GESTE. Il dure cinq secondes : le laisser courir ferait grincer une poignee
		-- que plus personne ne touche, pendant que la porte s'ouvre.
		local sfx = trySound
		trySound = nil
		if sfx and sfx.Parent then
			sfx:Stop()
			sfx:Destroy()
		end
		playGrandpa()
	end)
	track:Play()
end

-- UN COUP : la porte tremble et on entend le choc. Appele une fois par marqueur de l'animation du joueur, donc
-- c'est l'ANIMATION qui dit quand -- pas un minuteur qui finirait par se decaler d'elle.
local function knockOnce()
	local model = door
	if not model then
		return -- porte pas encore repliquee : la boucle de resolution la reprendra, rien a signaler ici
	end
	SoundUtils.play(TutorialConfigs.KNOCK_SOUND, anchor)

	local shake = shakeTrack
	if not shake then
		local animator = animatorOf(model)
		shake = if animator then loadSceneTrack(animator, TutorialConfigs.DOOR_SHAKE_ANIM) else nil
		if not shake then
			return
		end
		shake.Priority = Enum.AnimationPriority.Action
		shake.Looped = false
		shakeTrack = shake
	end
	-- ON REMBOBINE plutot que d'enchainer Stop puis Play. Trois coups rapproches : un Stop coupe en fondu, donc
	-- le deuxieme coup partirait par-dessus la fin du premier et le tremblement s'aplatirait.
	if shake.IsPlaying then
		shake.TimePosition = 0
	else
		shake:Play(0)
	end
end

-- LE JOUEUR TOQUE, et c'est ce qui OUVRE la scene. Chaque marqueur de son animation donne un coup ; quand elle
-- s'acheve, le grand-pere prend la suite.
local function playScene()
	local animator = playerAnimator()
	local track = if animator then loadSceneTrack(animator, TutorialConfigs.KNOCK_ANIM) else nil
	if not track then
		-- Pas d'animation de coups : on ne bloque pas la scene pour autant, le grand-pere vient quand meme.
		playTryOpen()
		return
	end
	knockTrack = track
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	for _, eventName in ipairs(TutorialConfigs.KNOCK_EVENTS) do
		track:GetMarkerReachedSignal(eventName):Connect(knockOnce)
	end
	-- La fin des coups enchaine sur le grand-pere. Un drapeau garantit UN seul enchainement : `Stopped` peut
	-- aussi tirer si la piste est coupee, et la scene partirait deux fois.
	local chained = false
	track.Stopped:Connect(function()
		if chained then
			return
		end
		chained = true
		playTryOpen()
	end)
	track:Play()
end

--- Le joueur a toque : la mission commence. Le guidage s'eteint DEFINITIVEMENT -- halo, prompt et touche --
--- puis la scene part. Idempotent : un double appui ne doit pas relancer une scene deja en cours.
---
--- ETAT ACTUEL : les barres et la camera sont branchees, les ANIMATIONS ne le sont pas encore. La scene tient
--- donc SCENE_HOLD secondes puis rend la main. Des que l'animation du grand-pere existe, c'est ELLE qui doit
--- decider de la fin -- une duree en dur et une animation finissent toujours par se contredire.
function TutorialController.startMission()
	if missionStarted then
		return
	end
	missionStarted = true
	TutorialController.setDoorHint(false)
	hideOurs()
	setActionBound(false)

	-- LES BARRES ET LA CAMERA PARTENT ENSEMBLE. Dans un film le cadre bouge pendant que le rideau descend, il
	-- n'attend pas que le noir soit en place.
	Letterbox.show(TutorialConfigs.SCENE_BARS_TIME)
	-- LE JEU BAISSE, il ne se tait pas. Un silence total s'entend comme une coupure et le monde a l'air de
	-- s'eteindre : on veut que l'oreille se tourne vers la scene, pas que le reste disparaisse.
	SoundDuck.duck(TutorialConfigs.SCENE_DUCK, TutorialConfigs.SCENE_DUCK_TIME)
	-- LA BOITE DE DIALOGUE S'EFFACE. Elle occupe le bas de l'ecran, pile ou les barres arrivent : une bulle qui
	-- reste ouverte pendant qu'on toque parle par-dessus le geste. Elle reviendra quand la SCENE la demandera.
	Dialogue.hide()
	local cf = sceneCFrame()
	if not cf then
		-- Pas de cadrage possible (pas de personnage) : on ne prend pas la camera pour rien.
		task.delay(TutorialConfigs.SCENE_HOLD, endScene)
		return
	end
	SceneCamera.enter(cf, TutorialConfigs.SCENE_CAM_IN, function()
		-- Le rappel tire QUAND LA CAMERA EST ARRIVEE : la scene commence de la, pas de l'appui. Sinon le temps de
		-- trajet mangerait le debut du plan, et il changerait avec SCENE_CAM_IN sans qu'on y pense.
		playScene()
	end)
end

local function step(dt: number)
	local now = os.clock()

	-- ON REVALIDE TANT QU'IL MANQUE QUELQUE CHOSE, pas seulement au premier passage. Avec StreamingEnabled le
	-- Model arrive souvent AVANT ses parts : resoudre l'ancre une seule fois la laissait a nil pour TOUTE la
	-- session, et le prompt ne sortait jamais -- sans la moindre erreur. Le Model etait pourtant bien trouve,
	-- donc on cherchait le probleme du cote de la distance ou du prompt, pas du cote de la replication.
	if not (door and door.Parent and anchor and anchor.Parent) then
		door, anchor = nil, nil
		if now - lastScanAt < TutorialConfigs.RESCAN_INTERVAL then
			return
		end
		lastScanAt = now
		door, anchor = findDoor()
		if not door then
			if not warnedNoDoor and now - startedAt > TutorialConfigs.NOT_FOUND_WARN_AFTER then
				warnedNoDoor = true
				warn(
					`[Tutorial] Aucun Model "{TutorialConfigs.DOOR_NAME}" utilisable dans le Workspace : ni halo, `
						.. "ni prompt. Rojo ne synchronise pas le Workspace, la porte doit exister dans CETTE place."
				)
			end
			return
		end
	end

	-- Le Highlight peut arriver APRES les parts : meme raison, on le re-cherche tant qu'on ne l'a pas.
	if not (highlight and highlight.Parent) then
		local halo = (door :: Model):FindFirstChild(TutorialConfigs.HIGHLIGHT_NAME)
		highlight = if halo and halo:IsA("Highlight") then halo else nil
		if not highlight and not warnedNoHighlight and now - startedAt > TutorialConfigs.NOT_FOUND_WARN_AFTER then
			warnedNoHighlight = true
			warn(
				`[Tutorial] Porte trouvee mais aucun Highlight "{TutorialConfigs.HIGHLIGHT_NAME}" dedans : elle ne `
					.. "clignotera pas. Ce Highlight se pose A LA MAIN dans Studio, dans chaque place."
			)
		end
	end

	-- ===== LE HALO =====
	local halo = highlight
	if halo and halo.Parent then
		if not doorHint then
			-- On ECRIT la valeur eteinte plutot que de sortir en silence : le halo a pu etre coupe en plein
			-- battement, et il resterait alors fige a moitie visible.
			if halo.FillTransparency ~= TutorialConfigs.FILL_MAX then
				halo.FillTransparency = TutorialConfigs.FILL_MAX
			end
		else
			elapsed += dt
			-- SINUS, pas un aller-retour lineaire. Une respiration n'a ni depart ni arrivee : le cosinus repart
			-- de lui-meme, donc aucune saccade au bouclage. Un lerp aller-retour casse a chaque extremite.
			local a = 0.5 - 0.5 * math.cos(elapsed * math.pi * 2 / TutorialConfigs.PULSE_PERIOD)
			halo.FillTransparency = TutorialConfigs.FILL_MAX
				+ (TutorialConfigs.FILL_MIN - TutorialConfigs.FILL_MAX) * a
		end
	end

	-- ===== LE PROMPT =====
	-- LE CENTRE DE LA PORTE, pas sa PrimaryPart. Celle-ci est le "Handle" : la CHARNIERE, posee sur le COTE. Le
	-- badge sortait donc a cote de la porte, et la distance se comptait depuis ce bord. La boite englobante ne
	-- depend d'aucun choix de PrimaryPart -- et elle reste juste si on en change dans Studio.
	--
	-- Recalculee a chaque test : deplacer la porte pendant une partie doit suivre. Une boite englobante sur une
	-- poignee de parts ne coute rien, et la valeur est IDENTIQUE tant que la porte ne bouge pas -- donc le
	-- prompt n'est pas re-affiche pour rien.
	anchorPos = (door :: Model):GetBoundingBox().Position

	local root = getRoot()

	-- Dit ce que la detection VOIT, pas ce qu'on croit qu'elle voit.
	if TutorialConfigs.DEBUG and now - lastDebugAt >= TutorialConfigs.DEBUG_INTERVAL then
		lastDebugAt = now
		if not root then
			print("[Tutorial] pas de HumanoidRootPart (personnage pas encore la)")
		else
			local d = ((anchorPos - root.Position) * Vector3.new(1, 0, 1)).Magnitude
			print(
				`[Tutorial] porte "{(door :: Model).Name}" | centre a {string.format("%.1f", d)} studs `
					.. `(rayon {TutorialConfigs.PROMPT_RADIUS}) | halo {tostring(highlight ~= nil)} `
					.. `| mission lancee {tostring(missionStarted)} | touche branchee {tostring(actionBound)}`
			)
		end
	end

	if missionStarted then
		return
	end
	if now - lastPromptAt < TutorialConfigs.PROMPT_INTERVAL then
		return
	end
	lastPromptAt = now

	if not root then
		hideOurs()
		setActionBound(false)
		return
	end

	-- DISTANCE RADIALE, a plat. Une box orientee laisserait des angles morts : colle a un bout de la porte on
	-- tomberait dehors, et l'agrandir ne bouche pas le trou puisqu'elle reste au mauvais endroit.
	local flat = (anchorPos - root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude > TutorialConfigs.PROMPT_RADIUS then
		hideOurs()
		setActionBound(false)
		return
	end

	setActionBound(true)
	-- On re-montre au CHANGEMENT de cible, mais AUSSI quand le prompt ne nous appartient plus : une autre
	-- feature a pu prendre le singleton entre-temps. Sans ce second test, le notre disparaitrait pour de bon.
	if not promptShown or InteractionPrompt.currentTarget() ~= anchorPos then
		promptShown = true
		InteractionPrompt.show(
			anchorPos,
			TutorialConfigs.PROMPT_KEY,
			TutorialConfigs.PROMPT_LABEL,
			TutorialConfigs.PROMPT_OFFSET,
			TutorialController.startMission,
			TutorialConfigs.PROMPT_TITLE
		)
	end
end

function TutorialController.init()
	if conn then
		return
	end
	startedAt = os.clock()
	-- MORT OU RESPAWN EN PLEINE SCENE. Sans ce filet le joueur ressuscite avec une camera scriptee et des barres
	-- noires, et AUCUN moyen d'en sortir : la scene attend une fin qui ne viendra jamais.
	player.CharacterRemoving:Connect(function()
		if SceneCamera.isActive() or Letterbox.isShown() then
			SceneCamera.abort()
			Letterbox.hide(0)
			SoundDuck.restore(0)
		end
	end)
	-- LA BOUCLE PART MEME SI LA PORTE N'EST PAS ENCORE LA. Avec StreamingEnabled elle arrive souvent apres le
	-- spawn : sortir ici laisserait le guidage mort pour toute la session, sans la moindre erreur pour le dire.
	-- Elle coute une comparaison de date tant qu'il n'y a rien a animer.
	conn = RunService.Heartbeat:Connect(step)
end

--- Coupe tout : boucle, halo, prompt et touche. Celui qui cree est celui qui nettoie, et il nettoie TOUT.
function TutorialController.stop()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	-- LA SCENE SURVIT AU CONTROLLER. La camera et les barres vivent dans la PlayerGui, et les pistes tournent sur
	-- des Animator du Workspace : les laisser en place figerait le joueur dans une scene qui n'existe plus, et la
	-- porte resterait ouverte sur rien. Celui qui cree est celui qui nettoie, et il nettoie TOUT.
	SceneCamera.abort()
	Letterbox.hide(0)
	-- Le son est BAISSE, pas coupe : l'oublier laisserait le jeu a un quart de volume pour toujours, et personne
	-- ne ferait le lien avec une scene finie depuis longtemps.
	SoundDuck.restore(0)
	-- UNE PAR UNE, jamais `ipairs` sur une liste de valeurs nilables : ipairs S'ARRETE AU PREMIER NIL. Une seule
	-- piste absente et la boucle ne tourne pas du tout -- les autres resteraient en place. Piege deja paye sur
	-- l'animation de recul de la tondeuse, qui ne s'arretait jamais.
	stopTrack(grandpaTrack)
	stopTrack(doorTrack)
	stopTrack(knockTrack)
	stopTrack(shakeTrack)
	stopTrack(tryTrack)
	grandpaTrack, doorTrack, knockTrack, shakeTrack, tryTrack = nil, nil, nil, nil, nil
	local sfx = trySound
	trySound = nil
	if sfx and sfx.Parent then
		sfx:Stop()
		sfx:Destroy()
	end
	local halo = highlight
	if halo and halo.Parent then
		halo.FillTransparency = TutorialConfigs.FILL_MAX
	end
	hideOurs()
	setActionBound(false)
	door, highlight, anchor = nil, nil, nil
end

return TutorialController
