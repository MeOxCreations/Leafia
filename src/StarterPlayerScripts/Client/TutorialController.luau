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
local CameraEffects = require(script.Parent.Utils.CameraEffects)
local CharacterFade = require(script.Parent.Utils.CharacterFade)
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
-- Surveille la fin de l'animation d'ouverture, pour la figer avant qu'elle ne reboucle.
local doorWatch: RBXScriptConnection? = nil
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

-- LE JOUEUR S'EFFACE PENDANT LA SCENE. On regarde le grand-pere, pas son propre dos.
--
-- `LocalTransparencyModifier` et pas `Transparency` : ca ne se replique pas, donc en co-op les autres continuent
-- de voir un personnage normal. Et ca s'AJOUTE a la transparence du jeu au lieu de l'ecraser -- il n'y a aucune
-- valeur d'origine a memoriser pour pouvoir la rendre.
local function fadePlayer(amount: number)
	local character = player.Character
	if character then
		CharacterFade.apply(character, amount, amount)
	end
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
	CameraEffects.SetFovOffset(0)
	fadePlayer(0)
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

-- EST-CE QUE L'ANIMATION A REELLEMENT BOUGE QUELQUE CHOSE ? Une animation retrouve ses cibles par leur NOM : si
-- aucune ne correspond au rig, elle joue a plein poids et n'ecrit RIEN, sans la moindre erreur. La piste tourne,
-- le son part, l'ecran ne bouge pas -- et on cherche le bug dans le declenchement, qui est parfait.
--
-- On mesure donc le RESULTAT. Les animations ecrivent dans `Transform`, jamais dans `C0` : un Transform reste a
-- l'identite = personne n'a ecrit dedans. Piege deja paye deux fois -- sur les PNJ, puis sur le seau porte.
local function checkAnimMoved(model: Model, animName: string)
	task.delay(TutorialConfigs.ANIM_CHECK_DELAY, function()
		if not model.Parent then
			return
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Motor6D") and d.Transform ~= CFrame.identity then
				return -- au moins un joint a bouge : l'animation s'applique bien
			end
		end
		warn(
			`[Tutorial] "{animName}" tourne mais n'a RIEN bouge sur "{model.Name}" : aucune de ses pistes ne porte `
				.. "le nom d'une part de ce rig. Elle anime probablement un AUTRE model -- verifie la cible dans "
				.. "TutorialConfigs (le nom de l'animation ne dit pas sur quoi elle joue)."
		)
	end)
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
-- Marge avant la fin sous laquelle on considere l'animation terminee. Une image a 30 FPS fait 0.033 s : en
-- dessous de ca, la fenetre serait sautee a chaque partie un peu chargee.
local END_WINDOW = 0.05

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
	-- L'IMAGE SE RESSERRE PILE QUAND LA PORTE PART. L'oeil suit le mouvement sans qu'on lui dise ou regarder.
	--
	-- On passe par CameraEffects et pas par `camera.FieldOfView` : il est declare SEUL ECRIVAIN de cette
	-- propriete et sa boucle tourne meme pendant la scene. Ecrire dessus en parallele donnerait un champ de
	-- vision qui vibre entre deux valeurs, et on chercherait la cause dans le zoom.
	CameraEffects.SetFovOffset(-TutorialConfigs.SCENE_ZOOM)
	-- Le grincement part AVEC le mouvement, pas au marqueur de mi-course : c'est l'ouverture elle-meme qu'il
	-- accompagne, et un bruit qui arrive une fois la porte deja entrebaillee sonne en retard.
	SoundUtils.play(TutorialConfigs.OPEN_SOUND, anchor)

	-- TROIS ANIMATIONS SE PARTAGENT L'ANIMATOR DE LA PORTE : le tremblement des coups, le geste de poignee, et
	-- l'ouverture. A priorite EGALE, Roblox ne choisit pas, il MELANGE : deux poses actives donnent leur
	-- moyenne, et la porte s'ouvrirait a moitie de travers. On efface donc les deux precedentes avant.
	stopTrack(shakeTrack)
	stopTrack(tryTrack)
	shakeTrack, tryTrack = nil, nil
	doorTrack = track
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true

	-- Instant ou la porte est EPINGLEE ouverte, ou nil tant qu'elle bouge encore. Declare ici et pas plus bas :
	-- la reprise apres la pause doit pouvoir le consulter, et elle est ecrite avant.
	local frozenAt: number? = nil
	local lastTime = 0

	local midDone = false
	track:GetMarkerReachedSignal(TutorialConfigs.DOOR_MID_EVENT):Connect(function()
		if midDone then
			return
		end
		midDone = true
		track:AdjustSpeed(0)
		task.delay(TutorialConfigs.DOOR_PAUSE, function()
			-- On ne relance QUE si la porte n'est pas deja tenue ouverte. Sans ce test, une pause encore en
			-- attente pourrait faire repartir une piste qu'on vient d'epingler, et la porte se refermerait --
			-- avec un retard qui rendrait la cause introuvable.
			if doorTrack == track and track.IsPlaying and frozenAt == nil then
				-- Elle repart AU RALENTI : la fin de l'ouverture est le moment ou l'on decouvre le grand-pere, et
				-- a vitesse pleine elle etait finie avant qu'on ait le temps de regarder.
				track:AdjustSpeed(TutorialConfigs.DOOR_FULL_OPEN_SPEED)
			end
		end)
	end)
	-- LA PORTE RESTE OUVERTE, ET ELLE EST TENUE -- pas juste gelee une fois.
	--
	-- Geler puis lacher la surveillance ne suffit pas : apres ca, plus rien ne defend la pose. Une piste qui se
	-- relache, un Stop venu d'ailleurs, un rebouclage rate d'une image, et la porte se referme sans qu'on sache
	-- lequel des trois. On RE-AFFIRME donc l'etat a chaque image tant que la scene dure. Deux ecritures par
	-- frame sur un seul objet : ca ne se mesure pas.
	--
	-- Et jamais `Stop` pour figer : un Stop fait rendre a la piste sa pose de repos, donc la porte CLAQUE en
	-- position fermee. C'est `AdjustSpeed(0)` plus un temps epingle.
	-- ON EPINGLE A LA DERNIERE IMAGE, pas la ou un marqueur tombe. La porte est grande ouverte AU BOUT de
	-- l'animation : s'arreter avant fige une pose intermediaire et le reste du mouvement ne joue jamais.
	--
	-- JAMAIS PILE A `Length` : la piste est bouclee, donc le tout dernier instant repart a zero. On epingle juste
	-- avant.
	local function pinAtEnd()
		if frozenAt then
			return
		end
		local length = track.Length
		if length <= 0 then
			return -- duree pas encore connue : on repassera a l'image suivante
		end
		local last = math.max(length - 0.001, 0)
		frozenAt = last
		track:AdjustSpeed(0)
		track.TimePosition = last
		-- LE GRAND-PERE APPARAIT : l'image se resserre une seconde fois, sur LUI. Cadence imposee --
		-- l'allure par defaut de CameraEffects mettrait deux secondes, et l'accent serait fini apres le
		-- moment qu'il souligne.
		CameraEffects.SetFovOffset(
			-(TutorialConfigs.SCENE_ZOOM + TutorialConfigs.REVEAL_ZOOM),
			TutorialConfigs.REVEAL_ZOOM_SPEED
		)
	end

	doorWatch = RunService.Heartbeat:Connect(function()
		-- Une autre ouverture a pris la main (nouvelle scene) : ce gardien n'a plus rien a defendre.
		if doorTrack ~= track then
			if doorWatch then
				doorWatch:Disconnect()
				doorWatch = nil
			end
			return
		end

		local pinned = frozenAt
		if pinned then
			-- ON TIENT LA POSE. Si quelque chose a arrete la piste, on la relance : une piste arretee ne dessine
			-- plus rien, et la porte revient a sa pose de repos, c'est-a-dire fermee.
			if not track.IsPlaying then
				track:Play(0)
			end
			if track.Speed ~= 0 then
				track:AdjustSpeed(0)
			end
			if math.abs(track.TimePosition - pinned) > 0.001 then
				track.TimePosition = pinned
			end
			return
		end

		-- LA FIN SE DETECTE DE DEUX FACONS, et il faut les deux.
		--
		-- La fenetre "assez proche de la fin" attrape le cas normal, mais un FPS bas peut la SAUTER : entre deux
		-- images la piste passe par-dessus et reboucle. Le retour en arriere, lui, est un fait qu'on ne peut pas
		-- rater. Les deux menent au meme endroit -- epingle a la derniere image -- donc rater la premiere ne
		-- coute qu'une image de plus.
		local now = track.TimePosition
		local length = track.Length
		if now < lastTime - 0.001 or (length > 0 and now >= length - END_WINDOW) then
			pinAtEnd()
			return
		end
		lastTime = now
	end)
	track:Play()
	checkAnimMoved(model, TutorialConfigs.DOOR_ANIM)
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
	checkAnimMoved(model :: Model, TutorialConfigs.GRANDPA_ANIM)
end

-- IL S'ACHARNE SUR LA POIGNEE. Entre les coups et l'ouverture : le grand-pere se bat avec sa vieille porte.
-- Quand l'animation s'acheve, l'ouverture prend la suite -- c'est elle qui dit quand elle a fini, pas un delai
-- pose a cote qui se decalerait a la premiere retouche.
local function playTryOpen()
	-- LA CIBLE EST DANS LA CONFIG, pas deduite du nom de l'animation : "oldman_TryOpenDoor" peut tres bien
	-- animer la poignee de la porte plutot que le vieux.
	local model = findModel(TutorialConfigs.TRY_OPEN_MODEL)
	local animator = if model then animatorOf(model) else nil
	local track = if animator then loadSceneTrack(animator, TutorialConfigs.TRY_OPEN_ANIM) else nil
	if not track then
		-- ON DIT POURQUOI ON SAUTE. Sans ces deux messages l'etape disparait EN SILENCE : la scene s'enchaine
		-- normalement, rien ne casse, et on croit que le code ne joue pas l'animation alors qu'il ne trouve pas
		-- de quoi la jouer. `loadSceneTrack` parle deja quand c'est l'Animation qui manque ; ici on couvre les
		-- deux autres causes.
		if not model then
			warn(`[Tutorial] Model "{TutorialConfigs.TRY_OPEN_MODEL}" introuvable : pas de geste de poignee.`)
		elseif not animator then
			warn(`[Tutorial] Pas d'Animator sous "{TutorialConfigs.TRY_OPEN_MODEL}" : pas de geste de poignee.`)
		end
		playGrandpa() -- l'etape saute, la scene continue
		return
	end
	tryTrack = track
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	trySound = SoundUtils.play(TutorialConfigs.TRY_OPEN_SOUND, anchor)
	checkAnimMoved(model :: Model, TutorialConfigs.TRY_OPEN_ANIM)

	local chained = false
	track.Stopped:Connect(function()
		if chained then
			return
		end
		chained = true
		-- LE SON CONTINUE. Il dure plus longtemps que le geste, et le couper net s'entend comme un bug -- alors
		-- qu'il deborde sur l'ouverture sans deranger personne. SoundUtils detruit le clone tout seul a la fin.
		trySound = nil
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
	SceneCamera.kick(TutorialConfigs.KNOCK_KICK)

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
	fadePlayer(TutorialConfigs.SCENE_PLAYER_FADE)
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
			CameraEffects.SetFovOffset(0)
			fadePlayer(0)
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
	CameraEffects.SetFovOffset(0)
	fadePlayer(0)
	-- UNE PAR UNE, jamais `ipairs` sur une liste de valeurs nilables : ipairs S'ARRETE AU PREMIER NIL. Une seule
	-- piste absente et la boucle ne tourne pas du tout -- les autres resteraient en place. Piege deja paye sur
	-- l'animation de recul de la tondeuse, qui ne s'arretait jamais.
	stopTrack(grandpaTrack)
	stopTrack(doorTrack)
	stopTrack(knockTrack)
	stopTrack(shakeTrack)
	stopTrack(tryTrack)
	if doorWatch then
		doorWatch:Disconnect()
		doorWatch = nil
	end
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
