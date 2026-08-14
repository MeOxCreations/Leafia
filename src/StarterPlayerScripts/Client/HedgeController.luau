--!strict
-- Ressenti du travail au pied d'une haie, cote client : orientation forcee face a la haie, camera de travail,
-- et le debug visuel du volume de detection.
--
-- POURQUOI COTE CLIENT. Le client possede son personnage et sa camera. Forcer l'orientation depuis le serveur
-- se battrait contre la simulation locale du joueur et donnerait du rubber-banding. Le serveur DECIDE (il pose
-- l'attribut LeafiaAtHedge), le client OBEIT.
--
-- Le decrochage est automatique : reculer eloigne le joueur, le volume de detection ne touche plus, le serveur
-- passe l'attribut a false et tout se relache ici.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)
local ToolConfigs = require(ReplicatedStorage.Modules.Configs.ToolConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local CameraEffects = require(script.Parent.Utils.CameraEffects)
local CharacterFade = require(script.Parent.Utils.CharacterFade)
local InputDevice = require(ReplicatedStorage.Modules.Utils.InputDevice)

-- Attribut pose par ToolService sur le modele de l'outil tenu (sa valeur = le nom de l'outil).
local TOOL_ATTRIBUTE = "LeafiaTool"

local HedgeController = {}

local player = Players.LocalPlayer
-- Une barre par angle de l'eventail. N'en dessiner qu'une masquerait les lancers de biais, et le debug
-- mentirait a nouveau sur ce qui est reellement teste.
local debugParts: { [number]: BasePart } = {}
-- Etiquette de chaque barre : la part de portee consommee avant de toucher.
local debugLabels: { [number]: TextLabel } = {}
local cursorPart: BasePart? = nil
-- Etat local, pour ne faire les transitions qu'UNE fois au lieu de reecrire les memes proprietes chaque frame.
local engaged = false

-- Pivot horizontal de la camera autour du joueur, en radians. Remis a zero au decrochage : on retrouve
-- toujours la vue de face en revenant sur une haie.
local yaw = 0
local yawVel = 0 -- vitesse du ressort de retour a la limite (rubber-band). Nulle tant qu'on ne deborde pas.
local orbiting = false

-- DOIGT DE VISEE (tactile). Le contact (non gameProcessed) qui vise et balaye la haie : poser + glisser = viser + couper.
-- nil = aucun doigt pose. Sur clavier-souris il reste nil et la visee prend la souris (cf aimScreenPoint).
local aimTouch: InputObject? = nil
-- DOIGT D'ORBITE (tactile). Un doigt pose HORS de la haie (ciel / sol) fait TOURNER la camera au lieu de tailler : le
-- pouce droit sert donc a couper (sur la haie) OU a orbiter (a cote), sans deuxieme doigt. nil = pas d'orbite en cours.
local orbitTouch: InputObject? = nil

-- ===== RETOUR DOUX DE LA CAMERA A LA SORTIE =====
-- Le desengagement (S / on quitte la haie) rendait la main a la cam de jeu D'UN COUP (cut sec). A la place, on GLISSE
-- de la vue iso vers l'etat EXACT ou la cam de jeu reprend, en SUIVANT le joueur, puis on rend la main. L'etat cible
-- est capture a l'ENGAGE via camera.Focus (avant Scriptable) : le focus (offset / HRP) + l'offset camera (angle + zoom).
local RELEASE_TIME = 0.55 -- duree du retour (s). Monter = plus lent / plus doux.
local releasing = false
local releaseElapsed = 0
local savedFocusOffset: Vector3? = nil -- (cam.Focus - HRP) capture a l'engage
local savedCamOffset: Vector3? = nil -- (cam.Position - cam.Focus) a l'engage = angle + distance de zoom
local releaseStartLookOffset = Vector3.zero -- point vise iso au depart de la sortie, relatif au HRP
local releaseStartCamOffset = Vector3.zero -- offset camera iso au depart de la sortie

-- Normale de travail REELLEMENT appliquee, en monde. Elle poursuit la geometrie sans jamais tourner plus vite
-- que CORNER_TURN_SPEED. Remise a nil au decrochage : on se recale d'emblee sur la haie suivante au lieu d'y
-- arriver en pivotant depuis la precedente.
local workNormal: Vector3? = nil

-- Avancement du fondu du personnage, de 0 (opaque) a 1 (fantome au dosage regle).
local workFade = 0

-- Facteur de zoom de la camera de travail. 1 = le placement du reglage.
--
-- Il N'EST PAS remis a zero au decrochage, contrairement au pivot : c'est un confort de vue que le joueur
-- choisit une fois, pas un coup d'oeil ponctuel. Le reinitialiser a chaque haie le lui reprendrait.
local cameraZoom = 1

-- La camera de travail se place DIRECTEMENT sur son cercle une fois arrivee (orbite 1:1, cf la boucle). camArrived
-- distingue l'ARRIVEE a l'engage (ou on glisse depuis la cam de jeu) du travail (placement direct). Remis a false a
-- chaque engage. currentDistance lisse le recul (rapproche a l'acceleration) EN PARAMETRE, pour ne pas deformer
-- l'orbite comme le ferait un lissage de la position.
local camArrived = false
local currentDistance = HedgeConfigs.CAMERA_DISTANCE

-- Module de controle par defaut de Roblox. On lui demande l'input BRUT du joueur.
--
-- POURQUOI PAS humanoid.MoveDirection : des qu'on contraint le deplacement avec humanoid:Move(), MoveDirection
-- devient NOTRE valeur contrainte. On lirait donc notre propre sortie, et l'intention de reculer du joueur
-- serait invisible : impossible de detecter qu'il veut sortir.
-- GetMoveVector rend l'input tel qu'il a ete saisi, avant toute contrainte, et sans dependre du clavier
-- (AZERTY ou QWERTY, c'est le module de Roblox qui s'en occupe).
local controlModule: any = nil

-- Filtre commun a TOUS les lancers qui cherchent une haie : detection, curseur, mesure de l'aimant, debug.
--
-- Centralise expres. Il y avait trois copies de ces quatre lignes ; le jour ou un nouveau dossier doit etre
-- ignore, en oublier une donne un bug qui ne se manifeste que dans un des trois cas, et on cherche loin.
--
-- Ce qu'on exclut :
--   le personnage      -- sans lui le lancer taperait dans l'outil qu'il tient, a zero stud
--   les espaces vitaux -- ils entourent chaque haie, ils seraient touches AVANT elle
--   les carreaux       -- ils sont poses SUR la haie, meme probleme
-- Un filtre exclut une instance ET ses descendants : d'ou les dossiers a part, jamais ranges dans la haie.
local function hedgeRayParams(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local ignore: { Instance } = { character }
	for _, folderName in ipairs({ HedgeConfigs.BUFFER_FOLDER, HedgeConfigs.CELL_FOLDER }) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			table.insert(ignore, folder)
		end
	end
	params.FilterDescendantsInstances = ignore
	return params
end

-- ===== ENVOI DE LA VISEE =====
-- Le serveur ne peut PAS lire la hauteur de la lame : la pose des bras est jouee ici et pilotee image par
-- image, or Roblox replique le demarrage d'une animation, pas son defilement. Cote serveur l'outil reste donc
-- fige a une hauteur, et la coupe ne tomberait juste que par hasard.
--
-- On lui envoie donc l'INTENTION, pas le resultat : il garde l'autorite sur la vitesse de coupe et sur la haie
-- concernee, le client ne lui dit que ou il vise.
local aimRemote: RemoteEvent? = nil
-- Un COUP de cisaille (clic). Le client ne fait que declencher ; le serveur decide s'il coupe et de combien.
local snipRemote: RemoteEvent? = nil
-- Les deux bouts de la lame REELLEMENT envoyes : ce que le serveur a en main, pour le debug.
local lastAimBase: Vector3? = nil
local lastAimTip: Vector3? = nil
local lastAimAt = 0

local function sendAim(base: Vector3?, tip: Vector3?)
	local remote = aimRemote
	if not remote then
		return
	end

	if base == nil or tip == nil then
		lastAimBase = nil
		lastAimTip = nil
		return
	end

	-- Rien de neuf : on se tait. Un envoi par frame ferait soixante paquets par seconde et par joueur pour une
	-- lame qui bouge a peine. On juge le mouvement sur le MILIEU du segment, qui resume son deplacement.
	local now = os.clock()
	local middle = (base + tip) * 0.5
	local previous = if lastAimBase and lastAimTip then (lastAimBase + lastAimTip) * 0.5 else nil
	local moved = previous == nil or (middle - previous).Magnitude >= HedgeConfigs.AIM_SEND_STEP
	if not (moved and now - lastAimAt >= HedgeConfigs.AIM_SEND_INTERVAL) then
		return
	end

	lastAimBase = base
	lastAimTip = tip
	lastAimAt = now
	remote:FireServer(base, tip)
end

-- Derniere haie visee. Gardee pour continuer a viser SA face meme quand le curseur en sort : sans elle, le
-- moindre debordement rendrait la visee nulle. Declaree ici parce que le debug de coupe en a besoin AVANT
-- le curseur : en Luau, on n'appelle jamais au-dessus de sa definition.
local lastHedge: BasePart? = nil

-- ===== REPERE DE COUPE (guide visuel) =====
-- Un CERCLE (le SurfaceGui du template VisualRootTarget) PLAQUE sur la surface visee : "tu couperas ici". Sa position
-- vient de la DERNIERE visee ENVOYEE au serveur (ce qu'il a reellement en main), donc il montre ou ca coupe vraiment.
-- A plat contre la face verticale, ET a plat sur le DESSUS quand on taille le dessus (cf drawCutZone).
local cutZonePart: BasePart? = nil
local cutHitbox: BasePart? = nil
-- Elements du template a TEINTER selon l'etat (recuperes au clonage). Le cercle vire au vert quand on taille.
local cutZoneFrames: { Frame } = {}
local cutZoneStrokes: { UIStroke } = {}
local cutZoneColor: Color3? = nil -- derniere couleur appliquee : on ne re-teinte qu'au changement
-- Echelle ANIMEE du cercle : un ressort amorti. Jaillit de 0 a l'apparition (slime), se presse un peu en coupe.
local cutZoneScale = 0
local cutZoneScaleVel = 0
local cutZoneClock = 0 -- os.clock du dernier pas du ressort (pour le dt, independant de l'appelant)

-- Couleur VOULUE du cercle, recalculee dans la boucle selon la matiere sous la lame (blanc = il reste a couper,
-- orange = nu). cutZoneColor (plus haut) est la derniere REELLEMENT appliquee : on ne re-teinte qu'au changement.
local cutZoneTargetColor: Color3 = HedgeConfigs.VISUAL_CUT_FOLIAGE_COLOR
-- os.clock du dernier coup qui a MORDU (tick de coupe). Sert a detecter le "nu" : tailler sans mordre -> orange.
local lastCutTickClock = 0

local cutZoneTemplateWarned = false
local function getCutZonePart(): BasePart?
	local existing = cutZonePart
	if existing and existing.Parent then
		return existing
	end
	-- Le template vit cote Studio (ReplicatedStorage.Assets.Effects), Rojo n'y touche pas. On le CLONE : tous les
	-- reglages du SurfaceGui / UIStroke (dont StrokeSizingMode = ScaledSize, qu'on ne peut pas poser en code) sont
	-- ainsi preserves. Une Part fine avec un cercle sur sa face du haut, qu'on plaque a plat sur la surface visee.
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local effects = assets and assets:FindFirstChild("Effects")
	local template = effects and effects:FindFirstChild(HedgeConfigs.VISUAL_CUT_TEMPLATE)
	if not (template and template:IsA("BasePart")) then
		if not cutZoneTemplateWarned then
			cutZoneTemplateWarned = true
			warn(`[HedgeController] Repere de coupe introuvable : ReplicatedStorage.Assets.Effects.{HedgeConfigs.VISUAL_CUT_TEMPLATE}`)
		end
		return nil
	end
	local part = template:Clone()
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1 -- le slab lui-meme est invisible : seul le SurfaceGui (le cercle) se voit
	part.Parent = workspace
	cutZonePart = part

	-- Elements a teinter (frames + contours du SurfaceGui), recuperes UNE fois.
	table.clear(cutZoneFrames)
	table.clear(cutZoneStrokes)
	cutZoneColor = nil
	-- L'echelle repart de 0 : le cercle JAILLIT (slime) a chaque apparition.
	cutZoneScale = 0
	cutZoneScaleVel = 0
	cutZoneClock = os.clock()
	for _, d in part:GetDescendants() do
		if d:IsA("Frame") then
			table.insert(cutZoneFrames, d)
		elseif d:IsA("UIStroke") then
			table.insert(cutZoneStrokes, d)
		end
	end
	return part
end

local function hideCutZone()
	if cutZonePart then
		cutZonePart:Destroy()
		cutZonePart = nil
		table.clear(cutZoneFrames)
		table.clear(cutZoneStrokes)
		cutZoneColor = nil
	end
end

-- La boite de lame, cote CLIENT. Ici elle est a la BONNE place : c'est nous qui jouons l'animation.
local function findBlade(character: Model): BasePart?
	local cached = cutHitbox
	if cached and cached.Parent and cached:IsDescendantOf(character) then
		return cached
	end
	local found = character:FindFirstChild("HitBoxRoot", true)
	cutHitbox = if found and found:IsA("BasePart") then found else nil
	return cutHitbox
end

-- Les deux bouts de la lame, en monde : base et pointe, le long de son axe le PLUS LONG.
--
-- C'est nous qui jouons l'animation, donc la CFrame de la boite est ici a la BONNE place. On envoie ce segment
-- au serveur, qui taille tout ce qui est a portee de cette LIGNE : c'est ce qui fait couper le BOUT de la lame,
-- que la sphere centree sur un point ratait.
local function bladeSegment(blade: BasePart): (Vector3, Vector3)
	local size = blade.Size
	local axis: Vector3, half: number
	if size.X >= size.Y and size.X >= size.Z then
		axis, half = Vector3.xAxis, size.X * 0.5
	elseif size.Y >= size.Z then
		axis, half = Vector3.yAxis, size.Y * 0.5
	else
		axis, half = Vector3.zAxis, size.Z * 0.5
	end
	local reach = blade.CFrame:VectorToWorldSpace(axis) * half
	return blade.Position - reach, blade.Position + reach
end

-- Rayon PERPENDICULAIRE de la coupe. Meme valeur que le serveur (CUT_RADIUS + marge) : le diametre du disque
-- part de la, pour qu'il couvre la vraie largeur taillee et pas une approximation.
local function cutRadius(): number
	return HedgeConfigs.CUT_RADIUS + HedgeConfigs.CUT_MARGIN
end

-- surfaceNormal : la normale de la SURFACE visee (sort d'elle). La face du HAUT du template (ou vit le cercle) est
-- alignee dessus -> plaque a plat contre une face verticale, et A PLAT sur le DESSUS quand la normale est verticale.
local function drawCutZone(base: Vector3?, tip: Vector3?, state: string, surfaceNormal: Vector3)
	if not HedgeConfigs.VISUAL_CUT_ENABLED then
		return
	end
	-- Pas de visee, ou hors d'une surface taillable : on cache. Le repere ne s'affiche que la ou l'on peut couper.
	if not base or not tip or state == "off" then
		hideCutZone()
		return
	end

	local part = getCutZonePart()
	if not part then
		return
	end
	local length = (tip - base).Magnitude

	-- SLIME + PRESSAGE : ressort amorti sur l'echelle. dt via os.clock (drawCutZone n'a pas le dt de la boucle), borne
	-- contre les a-coups. Cible : pressee tant qu'on TAILLE, sinon 1. A la creation l'echelle part de 0 -> jaillit.
	local now = os.clock()
	local dt = math.min(now - cutZoneClock, 1 / 30)
	cutZoneClock = now
	local target = if state == "cutting" then HedgeConfigs.VISUAL_CUT_PRESS_SCALE else 1
	local springForce = -HedgeConfigs.VISUAL_CUT_SLIME_STIFFNESS * (cutZoneScale - target)
		- HedgeConfigs.VISUAL_CUT_SLIME_DAMPING * cutZoneScaleVel
	cutZoneScaleVel += springForce * dt
	cutZoneScale += cutZoneScaleVel * dt

	-- A PLAT SUR LA SURFACE. La face du HAUT du slab (+Y, ou est le SurfaceGui) pointe le long de la NORMALE : face
	-- verticale -> +Y horizontal (slab vertical, cercle face au joueur) ; DESSUS -> +Y vertical (slab a plat, cercle
	-- vu de dessus). Le dessus devient donc plat tout seul. X et Z couvrent la coupe (longueur de lame + largeur
	-- taillee) ; Y garde l'epaisseur fine du template.
	local up = surfaceNormal.Unit
	-- Un perpendiculaire quelconque a la normale, pour completer le repere (le cercle est symetrique, l'axe importe peu).
	local ref = if math.abs(up.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local right = up:Cross(ref).Unit
	-- L'echelle du ressort multiplie le diametre (clamp a 0 : une taille de part ne peut pas etre negative).
	local diameter = (length + cutRadius() * 2) * HedgeConfigs.VISUAL_CUT_SIZE_SCALE * math.max(cutZoneScale, 0)
	-- Recule le repere hors des feuilles : pose SUR la surface au lieu de vibrer dedans (z-fighting).
	local center = (base + tip) * 0.5 + up * HedgeConfigs.VISUAL_CUT_SURFACE_OFFSET
	part.Size = Vector3.new(diameter, part.Size.Y, diameter)
	part.CFrame = CFrame.fromMatrix(center, right, up)

	-- COULEUR selon la matiere sous la lame (blanc = reste a couper, orange = nu), calculee dans la boucle. On teinte
	-- les frames + contours du cercle, seulement au CHANGEMENT.
	local color = cutZoneTargetColor
	if color ~= cutZoneColor then
		cutZoneColor = color
		for _, f in cutZoneFrames do
			f.BackgroundColor3 = color
		end
		for _, s in cutZoneStrokes do
			s.Color = color
		end
	end
end

-- ===== SON DE COUPE =====
-- Une COPIE par coup, et non la meme instance relancee : relancer coupe le son en cours a chaque fois, on
-- n'entendrait donc que son attaque, en boucle. Des copies se superposent comme de vraies coupes.
local cutSounds: { Sound } = {}
local lastCutSoundAt = 0
-- Dernier echantillon joue. Sert a ne pas le reprendre deux fois de suite : avec deux sons, un tirage
-- totalement libre en repete un une fois sur deux, et l'oreille l'entend tout de suite.
local lastCutIndex = 0

local function playCut(perClick: boolean)
	local count = #cutSounds
	if count == 0 then
		return
	end
	-- Le taille-haie coupe en CONTINU : on borne le rythme des sons (le tick serveur est deja espace, ceci est un
	-- garde-fou). La cisaille coupe au CLIC : chaque clic est un evenement discret, il doit sonner a CHAQUE fois. Sans
	-- ce contournement, deux clics rapproches (l'anti-spam en laisse passer ~12/s) n'en jouaient qu'un : le son sautait.
	if not perClick then
		local now = os.clock()
		if now - lastCutSoundAt < HedgeConfigs.CUT_SOUND_INTERVAL then
			return
		end
		lastCutSoundAt = now
	end

	local index = math.random(count)
	if count > 1 and index == lastCutIndex then
		-- Decale d'un cran plutot que de retirer au hasard : un nouveau tirage pourrait retomber sur le meme,
		-- et boucler. Ici on sort a coup sur, en une operation.
		index = index % count + 1
	end
	lastCutIndex = index

	local source = cutSounds[index]
	local copy = source:Clone()
	-- Hauteur ET volume tires au hasard. Le meme echantillon repete a l'identique se reconnait comme une
	-- boucle en trois secondes ; ces deux variations suffisent a le rendre vivant.
	local pitch = HedgeConfigs.CUT_SOUND_PITCH
	local volume = HedgeConfigs.CUT_SOUND_VOLUME
	copy.PlaybackSpeed = source.PlaybackSpeed * (1 + (math.random() - 0.5) * 2 * pitch)
	copy.Volume = source.Volume * (1 + (math.random() - 0.5) * 2 * volume)
	copy.Parent = SoundService
	copy:Play()
	-- Se detruit tout seul a la fin : pas de liste a tenir, pas de fuite possible.
	copy.Ended:Connect(function()
		copy:Destroy()
	end)
end

-- ===== PARTICULES DE COUPE =====
-- Emises la ou le curseur touche la haie, donc exactement la ou la lame travaille.
--
-- COTE CLIENT : des particules sont du ressenti pur. Les faire naitre sur le serveur reviendrait a payer du
-- reseau pour quelque chose que chaque machine sait calculer seule.
local cutEffect: BasePart? = nil
local cutHolder: BasePart? = nil
local cutEmitters: { ParticleEmitter } = {}
local warnedMissingEffect = false

-- UN SEUL support, cree une fois, deplace a chaque coupe.
--
-- Le cloner a chaque fois coutait une creation et une destruction six fois par seconde. Inutile : une
-- particule deja emise vit dans le MONDE, pas dans son emetteur. Deplacer le support n'emporte donc pas les
-- bouffees precedentes, elles restent la ou elles sont nees.
local function ensureCutHolder(): BasePart?
	local existing = cutHolder
	if existing and existing.Parent then
		return existing
	end

	local template = cutEffect
	if not template then
		return nil
	end

	local holder = template:Clone()
	holder.Anchored = true
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	-- Dans la camera : purement local, jamais replique.
	holder.Parent = workspace.CurrentCamera

	table.clear(cutEmitters)
	for _, descendant in ipairs(holder:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			-- COUPE. Un emetteur laisse actif cracherait en continu ; on ne veut que la bouffee de Emit, calee
			-- sur le moment exact de la coupe.
			descendant.Enabled = false
			table.insert(cutEmitters, descendant)
		end
	end

	cutHolder = holder
	return holder
end

local function emitCut(position: Vector3)
	-- Nom vide : effet volontairement coupe. On sort AVANT le test d'existence, pour ne pas avertir de
	-- l'absence de quelque chose qu'on a decide de ne pas utiliser.
	if HedgeConfigs.CUT_EFFECT == "" then
		return
	end

	if not cutEffect then
		if not warnedMissingEffect then
			warnedMissingEffect = true
			-- Anormal ET actionnable : sans cet effet la coupe n'a aucun retour visuel, et on chercherait
			-- longtemps pourquoi le geste parait mou.
			warn(
				`[HedgeController] Effet de coupe introuvable : `
					.. `ReplicatedStorage.Assets.Effects.{HedgeConfigs.CUT_EFFECT}`
			)
		end
		return
	end

	local holder = ensureCutHolder()
	if not holder then
		return
	end
	holder.CFrame = CFrame.new(position)

	for _, emitter in ipairs(cutEmitters) do
		-- Le nombre se regle emetteur par emetteur dans Studio, avec un repli sur la config. Une bourrasque de
		-- feuilles et une poussiere fine n'ont aucune raison d'emettre la meme quantite.
		emitter:Emit((emitter:GetAttribute("EmitCount") :: number?) or HedgeConfigs.CUT_EFFECT_COUNT)
	end
end

-- ControlModule recupere UNE fois EN TACHE DE FOND. require(PlayerModule) peut YIELD longtemps (WaitForChild ~10-20s
-- quand PlayerModule tarde a etre pret -- vu dans une place secondaire / le tuto). Le laisser dans getMoveVector, appele
-- PAR FRAME dans l'etat de travail, GELAIT toute la boucle le temps du WaitForChild : la taille restait bloquee plusieurs
-- secondes ("delai avant de pouvoir tailler"). Ici zero yield par frame : getMoveVector rend zero tant que ce n'est pas pret.
task.spawn(function()
	while not controlModule do
		local ok, result = pcall(function()
			local scripts = player:WaitForChild("PlayerScripts", 10)
			local playerModule = scripts and require(scripts:WaitForChild("PlayerModule", 10)) :: any
			return playerModule and playerModule:GetControls()
		end)
		if ok and result then
			controlModule = result
		else
			task.wait(0.3) -- RETRY : au boot (surtout place secondaire) PlayerModule / GetControls peut ne pas etre pret
		end
	end
end)

-- JOYSTICK DE TRAVAIL (tactile). Dans l'etat de travail la camera passe en Scriptable ; le thumbstick tactile PAR
-- DEFAUT (PlayerModule) cesse alors de remonter un move vector (GetMoveVector rend 0) -> sur mobile le joueur ne peut
-- ni glisser le long de la haie ni en sortir. On pose donc NOTRE propre joystick, actif seulement pendant le travail,
-- qui alimente getMoveVector directement. Independant du PlayerModule ET de la camera. Son toucher est gameProcessed
-- (bouton Active) -> la visee (InputBegan filtre gameProcessed) l'ignore : un doigt bouge, l'autre vise / taille.
local IS_TOUCH = UserInputService.TouchEnabled -- CAPACITE stable (vraie en emulateur ET vrai mobile), pas l'input actif
local mobileMove = Vector3.zero -- X = pas de cote, Z = avant / arriere (Z > 0 = sortie). Alimente par le joystick tactile.
local moveThumbInput: InputObject? = nil -- le doigt qui tient le joystick (nil = relache)

local function getMoveVector(): Vector3
	local vec = Vector3.zero
	local cm = controlModule
	if cm then
		local ok, v = pcall(function()
			return cm:GetMoveVector()
		end)
		if ok and typeof(v) == "Vector3" then
			vec = v
		end
	end
	-- JOYSTICK TACTILE (etat de travail). Le module de controle rend 0 sur mobile ici (camera Scriptable), donc on lit
	-- NOTRE joystick pose plus bas. Il passe AVANT le clavier : sur tactile il n'y a de toute facon pas de clavier.
	if vec.Magnitude < 0.05 and IS_TOUCH and mobileMove.Magnitude > 0.05 then
		vec = mobileMove
	end
	-- SECOURS CLAVIER : si le module de controle custom (StarterPlayer.PlayerModule, pose en Studio) rend du VIDE -- ce
	-- qu'il fait dans une place secondaire comme le tuto -- on lit WASD directement. Le deplacement marche alors quoi
	-- qu'il arrive (au moins clavier / emulateur). X = pas de cote (D +, A -), Z = avant/arriere (W -, S +, convention Roblox).
	if vec.Magnitude < 0.05 then
		local x, z = 0, 0
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			z -= 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			z += 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			x -= 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			x += 1
		end
		if x ~= 0 or z ~= 0 then
			vec = Vector3.new(x, 0, z)
		end
	end
	return vec
end

-- ===== JOYSTICK DE TRAVAIL (tactile) : construction + affichage =====
-- Un joystick DYNAMIQUE (apparait la ou le doigt se pose, dans une zone en bas a gauche). On ne mesure que le DELTA
-- depuis le point de contact : robuste a l'inset de la barre Roblox (le decalage se simplifie). Glisser sur le cote =
-- pas de cote ; tirer vers le BAS = arriere = sortie (Z > EXIT_MIN_INPUT). Construit une seule fois, montre au travail.
local moveThumbGui: ScreenGui? = nil
local moveThumbBase: Frame? = nil
local moveThumbKnob: Frame? = nil
local moveThumbStart = Vector2.zero -- point de contact (repere pour le delta)
local moveThumbRadius = 90 -- rayon en px du deplacement max ; recalcule a chaque prise selon la hauteur d'ecran

local function resetMoveThumb()
	moveThumbInput = nil
	mobileMove = Vector3.zero
	if moveThumbBase then
		moveThumbBase.Visible = false
	end
	if moveThumbKnob then
		moveThumbKnob.Visible = false
	end
end

local function ensureMoveThumb()
	if moveThumbGui or not IS_TOUCH then
		return
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "HedgeMoveThumb"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- input.Position et AbsolutePosition dans le MEME repere (origine = coin absolu de l'ecran)
	gui.DisplayOrder = 50 -- au-dessus des controles tactiles par defaut
	gui.Enabled = false -- montre seulement pendant le travail
	gui.Parent = pg

	-- ZONE DE PRISE, bas-gauche. Bouton Active -> son toucher est gameProcessed, la visee l'ignore. Tenue LOIN du
	-- centre (ou est la haie) pour ne pas manger les touchers de visee : le pouce gauche bouge, l'autre doigt vise.
	local zone = Instance.new("TextButton")
	zone.Name = "Zone"
	zone.BackgroundTransparency = 1
	zone.Text = ""
	zone.AutoButtonColor = false
	zone.Size = UDim2.fromScale(0.42, 0.5)
	zone.Position = UDim2.fromScale(0, 1)
	zone.AnchorPoint = Vector2.new(0, 1)
	zone.Parent = gui

	local base = Instance.new("Frame")
	base.Name = "Base"
	base.Visible = false
	base.AnchorPoint = Vector2.new(0.5, 0.5)
	base.Size = UDim2.fromOffset(150, 150)
	base.BackgroundColor3 = Color3.fromRGB(20, 24, 28)
	base.BackgroundTransparency = 0.55
	base.BorderSizePixel = 0
	base.Parent = gui
	local baseCorner = Instance.new("UICorner") :: UICorner
	baseCorner.CornerRadius = UDim.new(1, 0)
	baseCorner.Parent = base

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Visible = false
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(70, 70)
	knob.BackgroundColor3 = Color3.fromRGB(240, 244, 240)
	knob.BackgroundTransparency = 0.15
	knob.BorderSizePixel = 0
	knob.Parent = gui
	local knobCorner = Instance.new("UICorner") :: UICorner
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	moveThumbGui = gui
	moveThumbBase = base
	moveThumbKnob = knob

	-- Prise : un doigt se pose dans la zone -> il devient le doigt du joystick. Un seul a la fois (moveThumbInput).
	zone.InputBegan:Connect(function(input: InputObject)
		if not engaged or moveThumbInput then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		moveThumbInput = input
		moveThumbStart = Vector2.new(input.Position.X, input.Position.Y)
		local cam = workspace.CurrentCamera
		moveThumbRadius = if cam then cam.ViewportSize.Y * 0.11 else 90
		base.Position = UDim2.fromOffset(moveThumbStart.X, moveThumbStart.Y)
		base.Size = UDim2.fromOffset(moveThumbRadius * 2, moveThumbRadius * 2)
		knob.Size = UDim2.fromOffset(moveThumbRadius, moveThumbRadius)
		knob.Position = base.Position
		base.Visible = true
		knob.Visible = true
	end)

	-- Glissement : on lit le DELTA depuis le contact. X = pas de cote, Y (vers le bas) = arriere -> Z positif = sortie.
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input ~= moveThumbInput then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		local delta = pos - moveThumbStart
		local mag = delta.Magnitude
		local clamped = if mag > moveThumbRadius then delta.Unit * moveThumbRadius else delta
		knob.Position = UDim2.fromOffset(moveThumbStart.X + clamped.X, moveThumbStart.Y + clamped.Y)
		mobileMove = Vector3.new(
			math.clamp(delta.X / moveThumbRadius, -1, 1),
			0,
			math.clamp(delta.Y / moveThumbRadius, -1, 1)
		)
	end)

	-- Relache : le doigt part -> plus de deplacement, on cache le visuel.
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == moveThumbInput then
			resetMoveThumb()
		end
	end)
end

-- Montre / cache le joystick avec l'etat de travail. A la sortie on reset (le doigt peut encore etre pose).
local function setMoveThumbActive(on: boolean)
	if not IS_TOUCH then
		return
	end
	if on then
		ensureMoveThumb()
	end
	if moveThumbGui then
		moveThumbGui.Enabled = on
	end
	if not on then
		resetMoveThumb()
	end
end

-- ===== PAS CHASSE =====
-- Devant une haie le joueur ne marche pas, il se deplace en pas chasses. UNE seule piste sert aux deux sens :
-- jouee a l'envers pour l'autre cote. Le miroir est donc exact par construction, et il n'y a qu'une animation
-- a produire et a maintenir au lieu de deux qu'il faudrait garder synchronisees a la main.
--
-- POURQUOI COTE CLIENT, alors que ToolService joue ses animations cote serveur : le sens du glissement est
-- calcule ICI, frame par frame, a partir de l'input brut. Le faire trancher par le serveur ajouterait un
-- aller-retour reseau a chaque changement de direction, et les jambes partiraient du mauvais cote pendant ce
-- temps. Une animation jouee sur son PROPRE personnage se replique de toute facon aux autres joueurs.
local slideTrack: AnimationTrack? = nil
-- Sens en cours : -1 gauche, 1 droite, 0 arret. Retenu pour ne toucher a la piste qu'aux CHANGEMENTS, et non
-- soixante fois par seconde.
local slideDirection = 0

-- Part de la vitesse appliquee en ce moment. Montee d'un coup a chaque pose de pied, puis elle retombe.
local stepStrength = 1
-- Date du dernier marqueur recu. Sert au repli en deplacement continu quand plus rien n'arrive.
local lastStepAt = 0

-- ===== HAUTEUR DE COUPE =====
-- Piste FIGEE et parcourue a la main : sa premiere image est la coupe basse, sa derniere la coupe haute. On ne
-- la joue pas, on s'en sert comme d'une regle graduee que la hauteur visee promene.
local updownTrack: AnimationTrack? = nil
-- Pose pour le DESSUS. Une piste par ORIENTATION de surface : tailler un mur vertical et une table
-- horizontale ne sont pas le meme geste, et le corps ne se place pas pareil.
local rightleftTrack: AnimationTrack? = nil
-- Piste actuellement en scene. Retenue pour ne faire la transition qu'UNE fois au changement de surface.
local poseTrack: AnimationTrack? = nil
-- Dossier d'anims dont les poses (up/down + dessus) sont ACTUELLEMENT chargees. Sert a ne recharger qu'au
-- CHANGEMENT d'outil : chaque outil a sa propre pose de coupe, la cisaille ne doit pas prendre celle du taille-haie.
local poseFolder: string? = nil
-- L'outil tenu coupe-t-il au CLIC (cisaille) plutot qu'en maintenu (taille-haie) ? Mis a jour chaque frame depuis
-- la config de l'outil. C'est lui qui autorise le clic gauche a envoyer un coup de cisaille (CutSnip).
local heldPerClick = false
-- La visee pointe-t-elle une surface de haie taillable en ce moment ? Retenu pour n'autoriser le coup de cisaille
-- que quand il a une cible : cliquer en visant le vide ne doit rien declencher.
local aimActive = false
-- TACTILE : temps accumule depuis le dernier coup de cisaille au glissement. Sur mobile la cisaille ne se joue pas au
-- tap (aimActive est faux a l'instant du contact) : on re-declenche le coup tant que le doigt glisse sur la haie.
local touchSnipClock = 0
-- Hauteur suivie en ce moment, entre 0 et 1. Distincte de la hauteur VISEE : elle la rejoint progressivement,
-- sinon les bras claqueraient d'une position a l'autre au moindre saut de curseur.
local updownRatio = 0
-- Vitesse du ressort. C'est elle qui cree le RETARD : elle part de zero, il faut donc un instant avant que les
-- bras bougent vraiment, puis ils rattrapent la souris. Un simple lissage n'a pas cette inertie, il demarre a
-- pleine vitesse et ne fait que ralentir.
local updownVelocity = 0

local function loadTrack(animator: Animator, path: { string }, priority: Enum.AnimationPriority): AnimationTrack?
	local source: Instance? = ReplicatedStorage
	for _, name in ipairs(path) do
		source = source and source:FindFirstChild(name)
	end
	local label = table.concat(path, ".")
	if not (source and source:IsA("Animation")) then
		warn(`[HedgeController] Animation introuvable : {label}`)
		return nil
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(source :: Animation)
	end)
	if not (ok and track) then
		warn(`[HedgeController] Animation impossible a charger : {label}`)
		return nil
	end
	track.Priority = priority
	return track
end

-- Config de l'outil TENU par ce personnage, ou nil si aucun. L'equipement pose LeafiaTool sur le modele de
-- l'outil (sa valeur = le nom de l'outil) et le parente au personnage : on le retrouve ici. Sert a la fois au
-- dossier de pose (animationFolder) et a savoir si l'outil coupe au clic (cutPerClick).
local function heldToolConfig(character: Model): ToolConfigs.ToolConfig?
	for _, child in ipairs(character:GetChildren()) do
		local toolName = child:GetAttribute(TOOL_ATTRIBUTE)
		if typeof(toolName) == "string" then
			local config = ToolConfigs[toolName]
			if config then
				return config
			end
		end
	end
	return nil
end

-- Suit un chemin d'instances depuis ReplicatedStorage, ou nil si une etape manque. Sert a verifier l'existence
-- d'une anim AVANT de la charger, ce qui evite un warn quand un outil n'a pas telle piste (secours ou geste absent).
local function findAnim(path: { string }): Instance?
	local node: Instance? = ReplicatedStorage
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

-- Chemin d'une pose : dans le dossier de l'outil si l'anim y existe, sinon le secours (le taille-haie). Un outil
-- peut n'avoir qu'une partie de ses poses (l'anim absente retombe alors sur le taille-haie), et sans outil
-- (folder nil) tout retombe sur le secours.
local function resolvePosePath(folder: string?, animName: string, fallback: { string }): { string }
	if folder then
		local toolPath = { "Animations", "Player", "Tools", folder, animName }
		if findAnim(toolPath) then
			return toolPath
		end
	end
	return fallback
end

-- (Re)charge les poses up/down et dessus pour un dossier d'outil donne (nil = aucun outil -> secours taille-haie).
-- Appele au spawn et a chaque changement d'outil. On coupe les anciennes pistes : elles appartenaient a l'outil
-- precedent et resteraient a plein poids sur leur priorite.
local function loadPoseTracks(animator: Animator, folder: string?)
	if updownTrack then
		updownTrack:Stop(0)
		updownTrack = nil
	end
	if rightleftTrack then
		rightleftTrack:Stop(0)
		rightleftTrack = nil
	end
	poseTrack = nil
	poseFolder = folder

	local updown = loadTrack(animator, resolvePosePath(folder, "UpDownAnimation", HedgeConfigs.UPDOWN_ANIMATION), HedgeConfigs.UPDOWN_PRIORITY)
	if updown then
		-- Surtout PAS bouclee : elle ne se deroule jamais toute seule, c'est la visee qui la deplace.
		updown.Looped = false
		updownTrack = updown
	end

	local rightleft = loadTrack(animator, resolvePosePath(folder, "RightLeftAnimation", HedgeConfigs.RIGHTLEFT_ANIMATION), HedgeConfigs.UPDOWN_PRIORITY)
	if rightleft then
		rightleft.Looped = false
		rightleftTrack = rightleft
	end
	-- Note : le GESTE de coupe (les lames qui claquent, CutLamesAnimation) n'est PAS ici. Il anime le MODEL de
	-- l'outil, pas les bras : il est charge sur l'animator du model et joue cote serveur (ToolService), pas sur le
	-- personnage. Ici on ne gere que les poses du PERSO (hauteur up/down + dessus).
end

local function setupCharacter(character: Model)
	-- Les anciennes pistes appartenaient a l'Animator du personnage precedent : elles ne pointent plus sur rien.
	slideTrack = nil
	updownTrack = nil
	slideDirection = 0

	-- SECOUSSE A LA COUPE. Le serveur incremente un compteur quand des feuilles tombent reellement ; on ne
	-- reagit donc jamais a un passage de lame dans le vide.
	--
	-- Connectee sur le PERSONNAGE : elle meurt avec lui, il n'y a rien a couper a la main. C'est aussi pour ca
	-- que l'attribut est pose la et pas sur le joueur.
	-- LA LAME QUI FORCE. Secousse SEPAREE de celle de la coupe, et plus forte : mordre dans du bois deja au ras
	-- n'est pas tailler, et le joueur doit sentir la difference AVANT que le rouge la lui montre.
	--
	-- Elle demarre AVEC le rouge, et monte jusqu'a ce que le carreau soit perdu. La main et l'oeil disent la
	-- meme chose au meme moment : le joueur relie donc tout de suite la gene a ce qu'il voit.
	character:GetAttributeChangedSignal(HedgeConfigs.DAMAGE_TICK_ATTRIBUTE):Connect(function()
		local level = character:GetAttribute(HedgeConfigs.DAMAGE_LEVEL_ATTRIBUTE)
		local raw = if typeof(level) == "number" then level else 0
		-- Remappee sur [seuil, 1] : la secousse part de son minimum PILE au seuil, au lieu de commencer deja
		-- a mi-course parce que la valeur brute y est deja haute.
		local start = HedgeConfigs.DAMAGE_SHAKE_START
		local ratio = math.clamp((raw - start) / math.max(1 - start, 1e-3), 0, 1)
		local intensity = HedgeConfigs.DAMAGE_SHAKE_MIN
			+ (HedgeConfigs.DAMAGE_SHAKE_MAX - HedgeConfigs.DAMAGE_SHAKE_MIN) * ratio
		CameraEffects.Shake(intensity, HedgeConfigs.DAMAGE_SHAKE_DURATION)
	end)

	character:GetAttributeChangedSignal(HedgeConfigs.CUT_TICK_ATTRIBUTE):Connect(function()
		CameraEffects.Shake(HedgeConfigs.CUT_SHAKE_INTENSITY, HedgeConfigs.CUT_SHAKE_DURATION)
		playCut(heldPerClick)
		-- Slime au coup : une impulsion sur le ressort du cercle -> il gonfle d'un coup puis rebondit a chaque coupe.
		cutZoneScaleVel += HedgeConfigs.VISUAL_CUT_CLICK_KICK
		-- Ce coup a MORDU (des feuilles tombent) : on est sur du feuillu -> le repere reste blanc (cf boucle).
		lastCutTickClock = os.clock()
		-- Les particules naissent A LA LAME, et non au curseur.
		--
		-- Le curseur est ce que le joueur VISE, la lame est ce qui COUPE. Les deux ne coincident pas : le
		-- ressort met un instant a rattraper la souris. Des feuilles qui jaillissent d'un point ou la lame
		-- n'est pas encore cassent le lien entre le geste et sa consequence.
		-- On prend la position COURANTE et non celle envoyee au serveur : a l'ecran, c'est la lame visible qui
		-- doit projeter les debris.
		local blade = findBlade(character)
		if blade then
			emitCut(blade.Position)
		end
	end)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	-- A CharacterAdded le personnage est parente mais PAS complet : l'Animator arrive quelques frames apres
	-- l'Humanoid. Un FindFirstChildOfClass seul renverrait nil ici.
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
	if not (animator and animator:IsA("Animator")) then
		return
	end

	local slide = loadTrack(animator, HedgeConfigs.SLIDE_ANIMATION, HedgeConfigs.SLIDE_PRIORITY)
	if slide then
		slide.Looped = true
		-- Le deplacement est declenche par l'IMAGE, pas par une minuterie : la poussee tombe exactement quand le
		-- pied touche le sol a l'ecran. Cause et effet sur la meme frame, c'est ce qui supprime le patinage.
		slide:GetMarkerReachedSignal(HedgeConfigs.STEP_MARKER):Connect(function()
			stepStrength = HedgeConfigs.STEP_PUSH
			lastStepAt = os.clock()
		end)
		slideTrack = slide
	end

	-- Pose de coupe : chargee depuis le dossier de l'outil deja tenu (nil = aucun outil -> secours taille-haie).
	-- Le changement d'outil en cours de partie est gere dans la boucle update, qui recharge au vol.
	local config = heldToolConfig(character)
	loadPoseTracks(animator, config and config.animationFolder)
end

-- active : le joueur vise-t-il une haie, moteur en marche.
-- ratio  : 0 a 1 sur la surface visee (bas vers haut sur un cote, bord proche vers bord oppose sur le dessus).
-- onTop  : le curseur est-il sur le DESSUS de la haie.
local function setPose(active: boolean, ratio: number, onTop: boolean, dt: number, followSpeed: number)
	local wanted = if onTop then rightleftTrack else updownTrack

	-- CHANGEMENT DE SURFACE. On coupe l'ancienne pose EN FONDU et on lance la nouvelle : les deux se croisent,
	-- donc le corps glisse d'un geste a l'autre au lieu de claquer.
	if poseTrack ~= wanted then
		if poseTrack and poseTrack.IsPlaying then
			poseTrack:Stop(HedgeConfigs.UPDOWN_FADE)
		end
		poseTrack = wanted
		-- L'elan repart de zero : garder celui de l'autre surface enverrait les bras dans le sens du geste
		-- precedent, qui n'a plus rien a voir.
		updownVelocity = 0
		updownRatio = ratio
	end

	local track = wanted
	if not track then
		return
	end

	if not active then
		if track.IsPlaying then
			track:Stop(HedgeConfigs.UPDOWN_FADE)
		end
		return
	end

	if not track.IsPlaying then
		-- Vitesse ZERO : la piste est lancee mais ne se deroule pas. Elle ne bougera que par TimePosition.
		track:Play(HedgeConfigs.UPDOWN_FADE, 1, 0)
		-- On part de la position visee et non de la derniere connue : sinon les bras balaieraient toute la haie
		-- au premier affichage, depuis la position qu'ils avaient au chantier precedent.
		updownRatio = ratio
		updownVelocity = 0
	end

	-- SUIVI DE LA VISEE, propre a l'OUTIL. followSpeed = 0 -> AUCUN smooth (outil LEGER, cisaille) : la pose COLLE a la
	-- visee, reactivite max. Sinon RESSORT AMORTI AU CRITIQUE (F = -k*x - c*v, Euler) a la frequence de l'outil : k = f^2
	-- et c = 2*f donnent l'amortissement critique EXACT, le plus rapide qui n'oscille pas (un depassement ferait osciller
	-- la hauteur de coupe). Le retard vient de la vitesse (part de zero) : c'est ce qui donne le POIDS du taille-haie.
	if followSpeed <= 0 then
		updownRatio = ratio
		updownVelocity = 0
	else
		-- dt borne : a bas framerate, Euler explose sur un ressort raide et les bras partiraient a l'infini.
		local timeStep = math.min(dt, 1 / 30)
		local force = -(followSpeed * followSpeed) * (updownRatio - ratio) - 2 * followSpeed * updownVelocity
		updownVelocity += force * timeStep
		updownRatio += updownVelocity * timeStep
	end

	-- COURSE ADAPTEE A LA HAIE. La visee est normalisee de 0 a 1 quelle que soit la hauteur : sans ce facteur,
	-- viser le sommet d'une haie basse donnait la pose la plus HAUTE de l'animation, bras au-dessus de la tete
	-- pour une haie qui arrive a la taille.
	-- Le DESSUS n'est pas concerne : sa piste couvre une portee de bras, pas une hauteur de haie.
	local span = 1
	if not onTop then
		local hedge = lastHedge
		if hedge and hedge.Parent then
			span = math.clamp(
				hedge.Size.Y / HedgeConfigs.UPDOWN_REFERENCE_HEIGHT,
				HedgeConfigs.UPDOWN_MIN_SPAN,
				1
			)
		end
	end

	track.TimePosition = track.Length * span * math.clamp(updownRatio, 0, 1)
end

-- direction : -1 glisse a GAUCHE, 1 glisse a DROITE, 0 arret.
local function setSlide(direction: number)
	if direction == slideDirection then
		return
	end
	slideDirection = direction

	local track = slideTrack
	if not track then
		return
	end

	if direction == 0 then
		track:Stop(HedgeConfigs.SLIDE_FADE)
		return
	end

	-- Le premier pas part a pleine poussee : demarrer a la vitesse de glissement donnerait un depart mou.
	-- La date est posee ICI et non a zero, sinon le repli de securite se declencherait le temps que le premier
	-- marqueur arrive, et chaque depart serait continu avant de passer au pas.
	stepStrength = HedgeConfigs.STEP_PUSH
	lastStepAt = os.clock()

	-- La piste est animee pour le pas chasse vers la GAUCHE. Vers la droite on la deroule a l'envers, d'ou la
	-- vitesse NEGATIVE.
	local speed = HedgeConfigs.SLIDE_SPEED * -direction

	if track.IsPlaying then
		-- On ne relance pas : la lecture repart d'ou elle en est, simplement dans l'autre sens. Les jambes
		-- changent de sens en continu au lieu de sauter a la premiere image.
		track:AdjustSpeed(speed)
		return
	end

	-- La vitesse est passee a Play et non reglee apres : sans troisieme argument, Play la remet a 1 et la
	-- premiere image partirait a l'endroit avant d'etre corrigee.
	track:Play(HedgeConfigs.SLIDE_FADE, 1, speed)
	if speed < 0 then
		-- Demarrer a l'envers depuis le debut : la lecture n'a nulle part ou reculer. On la place a la fin.
		-- TimePosition ne tient que sur une piste DEJA lancee, d'ou cette ligne apres Play et pas avant.
		track.TimePosition = track.Length
	end
end

-- Liste ce qui joue REELLEMENT sur le personnage. On interroge l'Animator au lieu de supposer : une piste
-- qu'on croit prioritaire et une piste qui l'est vraiment sont deux choses differentes, et seul le moteur sait.
local lastSlideLog = 0

local function logSlide(character: Model, stepping: boolean)
	if not HedgeConfigs.DEBUG_SLIDE then
		return
	end
	local now = os.clock()
	if now - lastSlideLog < 1 then
		return
	end
	lastSlideLog = now

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not (animator and animator:IsA("Animator")) then
		return
	end

	local lines = {}
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		table.insert(
			lines,
			`  {track.Name} | {track.Priority.Name} | poids {string.format("%.2f", track.WeightCurrent)} | vitesse {track.Speed}`
		)
	end
	-- Le mode compte AUTANT que les pistes : "continu" veut dire que les marqueurs n'arrivent plus, donc que
	-- le repli de securite a pris la main. C'est LA ligne a lire pour savoir si le pas chasse fonctionne.
	local mode = if stepping
		then `AU PAS (poussee {string.format("%.2f", stepStrength)})`
		else "CONTINU (aucun marqueur recu, repli)"
	print(`[HedgeController] {mode} | pistes ({#lines}) :\n` .. table.concat(lines, "\n"))
end

-- ===== DEBUG =====

local function getDebugPart(index: number): BasePart
	local existing = debugParts[index]
	if existing and existing.Parent then
		return existing
	end

	local part = Instance.new("Part")
	part.Name = `HedgeRayDebug_{index}`
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	-- CanTouch a false aussi : sans ca cette boite declencherait les Touched des autres systemes.
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	-- On voit A TRAVERS plutot que de retrecir la boite : sa taille EST celle qui est testee, la reduire
	-- ferait mentir le debug, et un debug qui ment coute plus cher que pas de debug du tout.
	part.Transparency = HedgeConfigs.DEBUG_TRANSPARENCY
	-- Dans Camera et non workspace : rien de ce qui vit la n'est replique ni sauvegarde, c'est l'endroit des
	-- objets purement visuels et locaux.
	part.Parent = workspace.CurrentCamera

	-- Part de portee CONSOMMEE avant de toucher. C'est le chiffre qui manque a l'oeil : de face, une barre
	-- courte et une barre longue se ressemblent, alors qu'elles ne disent pas du tout la meme chose.
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(64, 22)
	-- Decalees les unes au-dessus des autres : au centre elles se superposeraient et seraient illisibles.
	billboard.StudsOffset = Vector3.new(0, 0.8 * index, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	debugParts[index] = part
	debugLabels[index] = label
	return part
end

local function hideDebug()
	for index, part in pairs(debugParts) do
		-- Le label vit DANS la part : la detruire l'emporte. On vide juste la table, sinon elle garderait des
		-- references vers des objets morts.
		part:Destroy()
		debugParts[index] = nil
		debugLabels[index] = nil
	end
end

-- ===== CURSEUR SUR LA HAIE =====
-- Bille posee la ou le curseur touche la haie. C'est ce point qui deviendra l'endroit ou l'on taille : le
-- construire maintenant sert d'abord a VOIR ou on vise, et servira ensuite de cible reelle.

local function getCursorPart(): BasePart
	local existing = cursorPart
	if existing and existing.Parent then
		return existing
	end

	local part = Instance.new("Part")
	part.Name = "HedgeCursor"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * HedgeConfigs.CURSOR_SIZE
	-- INVISIBLE : l'ancienne bille neon de visee est remplacee par le repere de coupe (le cercle VisualRootTarget).
	-- On garde la part (updateCursor la positionne encore, elle peut redevenir une cible reelle) mais on ne l'affiche
	-- plus.
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	-- CanQuery a false fonctionne ici : la bille n'a pas de collision. Sans ca elle se trouverait elle-meme au
	-- lancer suivant et resterait collee devant la camera.
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = workspace.CurrentCamera

	cursorPart = part
	return part
end

local function hideCursor()
	if cursorPart then
		cursorPart:Destroy()
		cursorPart = nil
	end
end


-- Distance HORIZONTALE d'un point a la boite de la haie. Sert a refuser qu'un curseur pointe une haie lointaine
-- ne s'en empare comme haie de travail. Meme calcul de coin arrondi que surfaceNormal, sans la direction.
local function hedgeReach(hedge: BasePart, from: Vector3): number
	local localPoint = hedge.CFrame:PointToObjectSpace(from)
	local half = hedge.Size * 0.5
	local dx = localPoint.X - math.clamp(localPoint.X, -half.X, half.X)
	local dz = localPoint.Z - math.clamp(localPoint.Z, -half.Z, half.Z)
	return math.sqrt(dx * dx + dz * dz)
end

-- La HAIE DE TRAVAIL, donnee par le SERVEUR via un ObjectValue replique. C'est la source fiable de "sur quelle
-- haie je suis", independante du curseur : l'aimant et l'orientation s'y accrochent des l'entree dans la zone,
-- sans attendre que la souris se pose sur la haie. Le curseur (lastHedge) ne sert plus qu'a VISER la coupe.
local function serverHedge(character: Model): BasePart?
	local value = character:FindFirstChild(HedgeConfigs.WORK_HEDGE_VALUE)
	if value and value:IsA("ObjectValue") then
		local hedge = value.Value
		if hedge and hedge:IsA("BasePart") and hedge.Parent then
			return hedge
		end
	end
	return nil
end

-- Rend la HAUTEUR VISEE sur la face de la haie, entre 0 (le pied) et 1 (le sommet), ou nil si le joueur ne
-- vise plus la haie. C'est cette valeur qui pilote la pose de coupe, et plus tard l'endroit reellement taille.
--
-- ON VISE LE PLAN DE LA FACE, PAS LA SURFACE TOUCHEE. Lire l'endroit ou le rayon tombe rendait la visee nulle
-- des qu'il ratait la haie d'un pixel : viser le pied pour le balayer proprement faisait glisser le curseur
-- sur le sol, et la pose sautait pile au moment ou le joueur travaillait. Le plan, lui, est infini : sortir
-- des bords ne le rate jamais, on n'a plus qu'a decider jusqu'ou on accepte de deborder.
-- Point d'ecran vise, en coordonnees VIEWPORT. Le POINT vient TOUJOURS de GetMouseLocation : sur tactile il suit le
-- doigt PENDANT le contact et il est deja dans le bon repere (celui qu'attend ViewportPointToRay ; l'utiliser en dur
-- mettait la bille a cote). Le doigt (aimTouch) ne sert plus qu'a savoir si on vise : sans doigt pose, on rend nil
-- pour ne pas laisser une visee fantome figee au dernier point touche.
local function aimScreenPoint(): Vector2?
	if InputDevice.isTouch() and not aimTouch then
		return nil
	end
	local m = UserInputService:GetMouseLocation()
	return Vector2.new(m.X, m.Y)
end

-- Un point d'ecran tombe-t-il sur une haie de travail ATTEIGNABLE ? Sert a decider, a la pose du doigt, si ce contact
-- TAILLE (sur la haie) ou fait TOURNER la camera (a cote). Meme lancer que la visee, mais reduit a un oui / non.
local function touchOnHedge(character: Model, screen: Vector2): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * HedgeConfigs.CURSOR_RANGE, hedgeRayParams(character))
	if not (result and result.Instance:GetAttribute(HedgeConfigs.HEDGE_MARK_ATTRIBUTE) == true) then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return root ~= nil
		and root:IsA("BasePart")
		and hedgeReach(result.Instance, root.Position) <= HedgeConfigs.CURSOR_HEDGE_RANGE
end

-- Rend (hauteur visee, est-ce le DESSUS). nil = le joueur ne vise plus la haie.
-- `workHedge` est la haie D'OU VIENT `normal`. Les deux vont ENSEMBLE : voir le repli plus bas.
local function updateCursor(character: Model, normal: Vector3, workHedge: BasePart?): (number?, boolean)
	local camera = workspace.CurrentCamera
	if not camera then
		hideCursor()
		return nil, false
	end

	-- ViewportPointToRay et non ScreenPointToRay. VERIFIE A L'ECRAN : avec ScreenPointToRay la bille tombait
	-- environ 36 pixels sous le curseur, pile la hauteur de la barre Roblox. Le point vise (souris OU doigt) rend
	-- deja des coordonnees VIEWPORT, et ScreenPointToRay rajoutait l'inset une seconde fois.
	local point = aimScreenPoint()
	if not point then
		-- Tactile sans doigt pose : on ne vise pas (pas de curseur fantome fige au dernier point touche).
		hideCursor()
		return nil, false
	end
	local ray = camera:ViewportPointToRay(point.X, point.Y)

	local params = hedgeRayParams(character)

	local result = workspace:Raycast(ray.Origin, ray.Direction * HedgeConfigs.CURSOR_RANGE, params)
	-- On lit l'ATTRIBUT et non le tag : un attribut se replique de facon certaine jusqu'au client.
	-- Ce lancer ne sert plus qu'a SAVOIR QUELLE HAIE on vise. La hauteur, elle, vient du plan.
	if result and result.Instance:GetAttribute(HedgeConfigs.HEDGE_MARK_ATTRIBUTE) == true then
		local hit = result.Instance
		local root = character:FindFirstChild("HumanoidRootPart")

		-- LE CURSEUR NE NOMME LA HAIE DE TRAVAIL QUE SI LE JOUEUR EST ASSEZ PRES D'ELLE.
		--
		-- Sans ce garde, viser une haie a l'autre bout du jardin la faisait devenir la haie de travail : la
		-- normale, l'aimant et l'orientation basculaient dessus, le joueur se tournait vers elle et SORTAIT du
		-- chantier tout seul, sans jamais toucher a S. C'etait le bug "il suffit de mettre la souris a gauche".
		-- Trop loin, on garde la haie courante : le curseur ne peut plus voler le focus a distance.
		if
			root
			and root:IsA("BasePart")
			and hedgeReach(hit, root.Position) <= HedgeConfigs.CURSOR_HEDGE_RANGE
		then
			lastHedge = hit

			-- LE DESSUS. On regarde l'inclinaison de la surface touchee : une face verticale a une normale
			-- horizontale, le dessus l'a verticale. Le curseur dit donc tout seul quelle surface on travaille,
			-- sans qu'on ait a comparer des hauteurs ni a inventer un mode.
			if result.Normal.Y >= HedgeConfigs.TOP_AIM_DOT then
				-- LE DESSUS N'EST ATTEIGNABLE QUE SUR UNE HAIE BASSE. Au-dela, on ne passe pas le taille-haie
				-- par-dessus depuis le sol : la pose gauche-droite ne se joue pas, et on reste sur la pose
				-- VERTICALE au maximum, comme un joueur qui tend les bras vers le haut sans atteindre le sommet.
				-- Meme seuil que la coupe du dessus (voir HedgeCellService). L'escabeau viendra lever ca.
				if hit.Size.Y > HedgeConfigs.TOP_CUT_MAX_HEIGHT then
					getCursorPart().Position = result.Position
					return 1, false
				end

				-- Sur le dessus, ce qui varie est un COTE et non une hauteur : le curseur a gauche fait balayer
				-- a gauche, a droite a droite. On mesure donc l'ecart le long de la haie, entre le curseur et le
				-- joueur, et non une profondeur.
				local right = (-normal):Cross(Vector3.yAxis).Unit
				local offset = (result.Position - root.Position):Dot(right)
				local reach = HedgeConfigs.TOP_REACH
				getCursorPart().Position = result.Position
				-- 0.5 = pile devant le joueur. Un ecart borne, et non la longueur de la haie : la piste doit
				-- couvrir ce que le BRAS peut atteindre, pas ce que la haie mesure.
				return math.clamp(0.5 + offset / (reach * 2), 0, 1), true
			end
		end
	end

	-- REPLI : le curseur ne touche aucune haie atteignable, on projette sur un PLAN. Ce plan doit etre celui de la
	-- haie D'OU VIENT `normal`, c'est-a-dire la haie de TRAVAIL, jamais la derniere haie survolee.
	--
	-- Les deux different des qu'il y a plus d'une haie dans le jardin : `lastHedge` retient la derniere que le
	-- curseur a touchee, `workHedge` est celle que le serveur nous a accrochee. Prendre les dimensions de l'une
	-- avec la normale de l'autre construit un plan qui n'existe nulle part -- il passe a cote de la haie, souvent
	-- de plusieurs studs, et la bille de visee va se poser dans le vide. Le joueur voit alors un curseur qui ne
	-- suit plus sa souris, alors que la souris est lue correctement : c'est la CIBLE qui est fausse.
	-- Sans haie de travail (le serveur n'a pas encore accroche), `lastHedge` reste le meilleur repli disponible.
	local hedge = workHedge or lastHedge
	-- Parent verifie aussi : une haie detruite ou sortie du streaming laisserait une reference morte.
	if not (hedge and hedge.Parent) then
		hideCursor()
		return nil, false
	end

	-- PLAN DE LA FACE. Son point de passage est la surface de la haie du cote ou se tient le joueur.
	-- VectorToObjectSpace plutot que de piocher dans Size au hasard : ca marche aussi si la haie est tournee.
	local localNormal = hedge.CFrame:VectorToObjectSpace(normal)
	local half = hedge.Size * 0.5
	local depth = math.abs(localNormal.X * half.X) + math.abs(localNormal.Y * half.Y) + math.abs(localNormal.Z * half.Z)
	local planePoint = hedge.Position + normal * depth

	local direction = ray.Direction.Unit
	local denominator = direction:Dot(normal)
	-- Rayon quasi parallele au plan : l'intersection part a l'infini. Aucun resultat exploitable.
	if math.abs(denominator) < 1e-4 then
		hideCursor()
		return nil, false
	end
	local distance = (planePoint - ray.Origin):Dot(normal) / denominator
	-- Negatif : le plan est DERRIERE la camera, le joueur regarde ailleurs.
	if distance <= 0 then
		hideCursor()
		return nil, false
	end
	local hitPoint = ray.Origin + direction * distance

	local height = hedge.Size.Y
	if height <= 0 then
		hideCursor()
		return nil, false
	end

	-- On repasse dans le repere de la haie pour borner. Un plan est INFINI : sans ces bornes, viser vingt studs
	-- a cote de la haie donnait une visee parfaitement valide, et la pose de coupe se declenchait dans le vide.
	local localPoint = hedge.CFrame:PointToObjectSpace(hitPoint)

	-- Axe LATERAL : celui des deux axes horizontaux qui n'est pas celui de la face.
	local sideways, sidewaysHalf
	if math.abs(localNormal.X) > math.abs(localNormal.Z) then
		sideways, sidewaysHalf = localPoint.Z, half.Z
	else
		sideways, sidewaysHalf = localPoint.X, half.X
	end

	-- LE BAS DE L'ECRAN EST UNE ZONE SURE : viser sous le pied de la haie garde la pose basse, quelle que soit la
	-- position laterale. Deux raisons qui vont dans le meme sens :
	--   - c'est la zone qu'on balaie le plus, la moindre sortie ne doit pas faire sauter la pose ;
	--   - en bas d'ecran le rayon est RASANT, donc son intersection avec le plan part loin, vers le bas ET sur le
	--     cote a cause de l'angle 3/4. Le `sideways` y devient donc faux et declenchait une sortie laterale
	--     fantome des qu'on visait en bas a gauche ou a droite.
	-- On IGNORE donc le test lateral quand on vise sous le pied. Au-dessus du pied, il reprend son role : sortir
	-- franchement sur le cote a hauteur de travail rend bien la main. Le haut garde aussi sa marge.
	local margin = HedgeConfigs.AIM_MARGIN
	local belowFoot = localPoint.Y < -half.Y
	local aboveTop = localPoint.Y > half.Y + margin
	local sidewaysOut = math.abs(sideways) > sidewaysHalf + margin
	if aboveTop or (sidewaysOut and not belowFoot) then
		hideCursor()
		return nil, false
	end

	getCursorPart().Position = hitPoint

	-- ZONES MORTES. On remappe [deadzone, hauteur - deadzone] sur [0, 1] : tout ce qui est plus bas vaut le bas
	-- franc, tout ce qui est plus haut vaut le haut franc. Ce sont les positions les plus utilisees, elles
	-- doivent etre les plus faciles a tenir.
	local dead = math.min(HedgeConfigs.AIM_DEADZONE, height * 0.4)
	local usable = height - dead * 2
	if usable <= 0 then
		return 0.5, false
	end
	-- localPoint.Y va de -half.Y (le pied) a +half.Y (le sommet) : on le ramene d'abord a une hauteur au-dessus
	-- du pied.
	return math.clamp((localPoint.Y + half.Y - dead) / usable, 0, 1), false
end

-- La couleur se decide LANCER PAR LANCER, plus globalement : savoir "une haie est detectee" n'apprend rien,
-- savoir LEQUEL des trois la voit et a quelle distance, si.
local function drawDebug(character: Model, origin: Vector3, direction: Vector3, length: number)
	if not HedgeConfigs.DEBUG_RAY then
		return
	end

	-- MEME volume et MEME filtre que le serveur : ce qu'on voit est exactement ce qui est teste. Oublier les
	-- boites d'espace vital ici ferait s'arreter la barre de debug avant la haie, alors que le serveur, lui,
	-- la detecte : le debug mentirait.
	local params = hedgeRayParams(character)

	local size = Vector3.new(HedgeConfigs.DETECT_WIDTH, HedgeConfigs.DETECT_HEIGHT, HedgeConfigs.DETECT_THICKNESS)

	-- MEMES angles que le serveur. N'en dessiner qu'un masquerait les lancers de biais, et on ne comprendrait
	-- pas pourquoi une haie sur le cote est detectee.
	for index, angle in ipairs(HedgeConfigs.DETECT_ANGLES) do
		local rayDirection = CFrame.Angles(0, math.rad(angle), 0) * direction
		local start = CFrame.lookAt(origin, origin + rayDirection)
		local result = workspace:Blockcast(start, size, rayDirection * length, params)
		local drawLength = if result then result.Distance else length

		local part = getDebugPart(index)
		part.Size = Vector3.new(HedgeConfigs.DETECT_WIDTH, HedgeConfigs.DETECT_HEIGHT, math.max(drawLength, 0.05))
		-- Le recul de moitie fait PARTIR la boite de l'origine au lieu d'etre centree dessus.
		part.CFrame = start * CFrame.new(0, 0, -drawLength * 0.5)
		-- Couleur PAR LANCER et non plus globale : trois barres toutes vertes alors qu'une seule touchait ne
		-- disaient pas laquelle travaillait.
		part.Color = if result then HedgeConfigs.DEBUG_COLOR_HIT else HedgeConfigs.DEBUG_COLOR_MISS

		local label = debugLabels[index]
		if label then
			if result then
				label.Text = `{math.round(result.Distance / length * 100)}%`
				label.TextColor3 = HedgeConfigs.DEBUG_COLOR_HIT
			else
				label.Text = "vide"
				label.TextColor3 = HedgeConfigs.DEBUG_COLOR_MISS
			end
		end
	end
end

-- ===== TRANSITIONS =====

-- Un pas du RETOUR DOUX de la camera a la sortie (glissement iso -> cam de jeu, en SUIVANT le joueur). Voir les
-- variables en tete de fichier. Se debranche tout seul a la fin, ou si le perso disparait.
local function stepRelease(dt: number)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (camera and root and root:IsA("BasePart") and savedFocusOffset and savedCamOffset) then
		releasing = false
		RunService:UnbindFromRenderStep("LeafiaHedgeExit")
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
		return
	end
	releaseElapsed += dt
	local t = math.clamp(releaseElapsed / RELEASE_TIME, 0, 1)
	local a = 1 - (1 - t) * (1 - t) -- ease out : demarre franc, finit doux
	-- On SUIT le joueur (focus ancre sur son HRP a chaque frame) et on ease l'offset de la vue iso vers l'etat de la
	-- cam de jeu (capture a l'engage). A la fin, Custom reprend PILE la.
	local focus = root.Position + releaseStartLookOffset:Lerp(savedFocusOffset, a)
	local camPos = focus + releaseStartCamOffset:Lerp(savedCamOffset, a)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(camPos, focus)
	if t >= 1 then
		releasing = false
		RunService:UnbindFromRenderStep("LeafiaHedgeExit")
		camera.CameraType = Enum.CameraType.Custom
	end
end

-- Parties du CORPS a cacher en vue rapprochee (R15 ET R6). On NE liste PAS les bras/mains : ils restent visibles. L'OUTIL
-- (parts hors corps et hors accessoire) reste visible aussi -> vue 1re personne "mains + outil".
local FP_HIDE_BODY: { [string]: boolean } = {
	Head = true,
	UpperTorso = true,
	LowerTorso = true,
	Torso = true, -- R6
	HumanoidRootPart = true,
	["Left Leg"] = true, -- R6
	["Right Leg"] = true, -- R6
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
}

-- Cache le CORPS du perso EN LOCAL (LocalTransparencyModifier : n'affecte QUE la vue du joueur, les autres le voient
-- normalement), mais GARDE les BRAS / MAINS et l'OUTIL visibles -> vraie 1re personne. Les accessoires (chapeau, cheveux)
-- sont caches aussi (ils boucheraient la vue). hidden=false remet tout visible. Une part intrinsequement invisible
-- (hitbox Transparency=1) le reste : LocalTransparencyModifier n'ecrase pas la transparence propre.
local function setCharacterHiddenLocally(hidden: boolean)
	local character = player.Character
	if not character then
		return
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			local hide = hidden
				and (FP_HIDE_BODY[d.Name] == true or d:FindFirstAncestorOfClass("Accessory") ~= nil)
			d.LocalTransparencyModifier = if hide then 1 else 0
		end
	end
end

local function release(humanoid: Humanoid?)
	if not engaged then
		return
	end
	engaged = false
	setCharacterHiddenLocally(false) -- on sort : le perso redevient visible en local
	-- On repart toujours d'une vue de face en revenant sur une haie : garder le pivot d'un chantier precedent
	-- placerait le joueur de biais sans qu'il comprenne pourquoi.
	yaw = 0
	yawVel = 0
	orbiting = false
	-- Meme raison pour la normale de travail : gardee, elle ferait pivoter le joueur depuis l'orientation de la
	-- haie precedente en arrivant sur la suivante, alors qu'il faut se caler d'emblee.
	workNormal = nil
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	hideCursor()
	-- La haie memorisee n'a de sens que pendant le chantier : la garder ferait viser la precedente en arrivant
	-- sur la suivante, le temps que le premier lancer touche.
	lastHedge = nil
	hideCutZone()
	-- Le pas chasse n'a de sens qu'au pied d'une haie. Sans cet arret il continuerait pendant que le joueur
	-- traverse le jardin, et il masquerait la marche : elle est en Movement, lui en Action.
	setSlide(0)
	-- Meme raison pour la pose de coupe : elle est en Action2, elle bloquerait les bras sur toute la carte.
	setPose(false, 0, false, 0, 0)
	-- Plus de cible : un clic ne doit plus declencher de coup de cisaille en quittant la haie.
	aimActive = false
	-- Le joystick tactile n'a de sens qu'au pied d'une haie : on le cache et on coupe le deplacement.
	setMoveThumbActive(false)

	if humanoid then
		-- On rend au joueur le pivot automatique de son personnage.
		humanoid.AutoRotate = true
		-- On rend le saut, bloque pendant la taille.
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end

	local camera = workspace.CurrentCamera
	local root = humanoid and humanoid.RootPart
	if camera and root and savedFocusOffset and savedCamOffset then
		-- RETOUR DOUX au lieu d'un cut sec : on part de la vue iso COURANTE et on glisse (RELEASE_TIME) vers l'etat
		-- exact ou la cam de jeu reprend, en suivant le joueur. stepRelease rend la main a Custom a la fin.
		releaseStartLookOffset = Vector3.new(0, HedgeConfigs.CAMERA_LOOK_HEIGHT, 0)
		releaseStartCamOffset = camera.CFrame.Position - (root.Position + releaseStartLookOffset)
		releaseElapsed = 0
		releasing = true
		RunService:BindToRenderStep("LeafiaHedgeExit", Enum.RenderPriority.Camera.Value, stepRelease)
	elseif camera then
		-- Secours (pas d'etat capture, ex : perte du perso) : bascule directe.
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function engage(humanoid: Humanoid)
	if engaged then
		return
	end
	engaged = true

	-- Vue rapprochee : on cache le perso en LOCAL pour qu'il ne bouche pas la haie (les autres joueurs le voient toujours).
	if HedgeConfigs.CAMERA_FIRST_PERSON then
		setCharacterHiddenLocally(true)
	end

	-- La camera GLISSE depuis la cam de jeu a l'engage (camArrived = false), puis se placera direct une fois
	-- arrivee. On repart d'une distance de base propre pour que ce glisse ne parte pas du recul de la haie precedente.
	camArrived = false
	currentDistance = HedgeConfigs.CAMERA_DISTANCE

	-- Sans ca, Roblox tourne le personnage dans la direction ou il MARCHE : le joueur qui longe la haie se
	-- retrouverait de profil, et impossible de tailler.
	humanoid.AutoRotate = false

	-- PAS DE SAUT PENDANT LA TAILLE. Bloquer l'etat Jumping refuse le saut manuel ET l'AUTO-jump (sur mobile
	-- AutoJumpEnabled est vrai par defaut : le perso saute tout seul des qu'il bute sur le bas de la haie). On ne
	-- touche pas AutoJumpEnabled, on refuse juste la transition d'etat -> rendu tel quel a la sortie.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	-- Re-accroche pendant un retour de sortie : on coupe le glissement, la boucle de travail reprend la main.
	if releasing then
		releasing = false
		RunService:UnbindFromRenderStep("LeafiaHedgeExit")
	end

	local camera = workspace.CurrentCamera
	if camera then
		-- Etat de la cam de jeu capture AVANT de passer en Scriptable (via camera.Focus), pour que le retour de sortie
		-- finisse PILE dessus : focus (offset / HRP) et offset camera (angle + zoom). Ne bouge pas pendant le travail.
		local root = humanoid.RootPart
		if root then
			savedFocusOffset = camera.Focus.Position - root.Position
			savedCamOffset = camera.CFrame.Position - camera.Focus.Position
		end
		camera.CameraType = Enum.CameraType.Scriptable
	end

	-- Camera Scriptable = le thumbstick tactile par defaut ne remonte plus rien : on montre NOTRE joystick.
	setMoveThumbActive(true)
end

-- Direction SORTANTE depuis le point de la haie le plus proche du joueur, dans le plan horizontal.
--
-- C'est ce qui arrondit les angles, et ca ne coute aucune interpolation : la surface a distance constante
-- d'une boite est un rectangle a coins ARRONDIS de rayon egal a cette distance. En mesurant depuis le point le
-- plus proche, cette forme sort toute seule. Le long d'un cote, le resultat est exactement la normale de la
-- face ; passe le bout, il pivote progressivement autour du coin. Il ne peut donc plus y avoir de bascule.
--
-- EN DEUX DIMENSIONS, jamais en trois. Sur une haie basse, le joueur est plus haut que le sommet : le point le
-- plus proche en 3D serait sur le DESSUS, et la normale pointerait vers le ciel. Le rail partirait a la
-- verticale, ce qui n'a aucun sens pour quelqu'un qui marche.
local function surfaceNormal(hedge: BasePart, from: Vector3): Vector3?
	local localPoint = hedge.CFrame:PointToObjectSpace(from)
	local half = hedge.Size * 0.5
	local out = Vector3.new(
		localPoint.X - math.clamp(localPoint.X, -half.X, half.X),
		0,
		localPoint.Z - math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	-- Le joueur est A L'INTERIEUR de l'emprise : aucune direction sortante n'a de sens. Ca n'arrive pas au
	-- travail, la boite invisible l'en empeche, mais un decor mal pose ne doit pas produire un rail nul.
	if out.Magnitude < 1e-3 then
		return nil
	end
	return hedge.CFrame:VectorToWorldSpace(out.Unit)
end

-- ===== BOUCLE =====

-- Rubber-band de l'orbite : dans les clous, sensibilite pleine. Au-dela de la limite, pousser ENCORE plus loin
-- resiste de plus en plus (marge elastique) jusqu'a un mur dur a limite + marge. Tirer vers le centre reste libre.
-- Le retour a la limite se fait au RELACHEMENT, par le ressort slime dans update (yaw n'est plus pilote par l'input).
local function applyOrbitDrag(deltaX: number, sensitivity: number)
	local limit = math.rad(HedgeConfigs.CAMERA_YAW_LIMIT)
	local margin = math.rad(HedgeConfigs.CAMERA_YAW_MARGIN)
	local step = -math.rad(deltaX * sensitivity)

	-- De combien on est DEJA au-dela d'une limite (0 si dans les clous).
	local over = 0
	if yaw > limit then
		over = yaw - limit
	elseif yaw < -limit then
		over = -limit - yaw
	end

	-- Si le pas enfonce ENCORE dans la marge, on l'amortit d'autant qu'on est deja loin (0 au bord du mur). Vers
	-- le centre, aucun amortissement : on revient toujours librement.
	local pushingOut = (yaw >= limit and step > 0) or (yaw <= -limit and step < 0)
	if pushingOut then
		step *= 1 - math.clamp(over / margin, 0, 1)
	end

	yaw = math.clamp(yaw + step, -limit - margin, limit + margin)
end

local function update(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not (character and humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		release(nil)
		-- Le personnage suivant doit naitre opaque. Sans cette remise a zero, un joueur qui meurt au pied d'une
		-- haie reapparaitrait en fantome ailleurs sur la carte, et mettrait une seconde a redevenir visible.
		workFade = 0
		hideDebug()
		hideCursor()
		return
	end

	-- Chaque outil a sa propre pose de coupe (dossier d'anim different). On la recharge quand l'outil change en
	-- cours de partie : sans ca, prendre la cisaille apres le taille-haie garderait la pose du taille-haie. On en
	-- profite pour savoir si l'outil coupe au CLIC (cisaille) : c'est ce qui autorise le coup de cisaille plus bas.
	local toolConfig = heldToolConfig(character)
	local toolFolder = toolConfig and toolConfig.animationFolder
	heldPerClick = toolConfig ~= nil and toolConfig.cutPerClick ~= nil
	if toolFolder ~= poseFolder then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			loadPoseTracks(animator, toolFolder)
		end
	end

	local atHedge = character:GetAttribute(HedgeConfigs.AT_HEDGE_ATTRIBUTE) == true
	local serverNormal = character:GetAttribute(HedgeConfigs.HEDGE_NORMAL_ATTRIBUTE)

	-- FONDU DU PERSONNAGE. Pilote ICI et non dans engage / release : ces deux-la ne passent qu'une fois, alors
	-- qu'un fondu doit continuer a se resorber APRES le decrochage. Mis dans release, le joueur redeviendrait
	-- opaque d'un coup au moment ou il quitte la haie, ce qui claque plus que de ne rien faire.
	local wanted = if atHedge and HedgeConfigs.WORK_FADE then 1 else 0
	workFade += (wanted - workFade) * math.min(1, HedgeConfigs.WORK_FADE_SPEED * dt)
	-- Un lerp exponentiel n'atteint JAMAIS sa cible : il laisse un residu minuscule. A 0 ca compte, parce qu'une
	-- transparence de 0.005 suffit a faire passer la part dans le rendu TRANSPARENT de Roblox, ou le tri se fait
	-- par objet et non par profondeur : les membres se chevauchent quand on pivote la camera. On cle donc a la
	-- cible (0 ou 1) des qu'on est assez pres, pour garantir un personnage REELLEMENT opaque en sortie de haie.
	if math.abs(wanted - workFade) < 0.01 then
		workFade = wanted
	end
	CharacterFade.apply(
		character,
		HedgeConfigs.WORK_FADE_BODY * workFade,
		HedgeConfigs.WORK_FADE_HANDS * workFade
	)

	drawDebug(
		character,
		root.Position,
		root.CFrame.LookVector,
		if atHedge then HedgeConfigs.RAY_LENGTH_ENGAGED else HedgeConfigs.RAY_LENGTH
	)

	local camera = workspace.CurrentCamera
	if not (atHedge and typeof(serverNormal) == "Vector3" and camera) then
		-- TAILLE DEPUIS L'ECHELLE. On n'est pas accroche au sol, mais si le serveur signale qu'on taille le dessus
		-- depuis l'echelle, on DESSINE quand meme le guide de coupe (le cylindre), depuis la lame, pour que le joueur
		-- voie ou ca coupe. On ne touche NI la camera (l'echelle la controle) NI l'aimant : juste le visuel.
		if character:GetAttribute(HedgeConfigs.LADDER_TRIM_ATTRIBUTE) == true then
			local blade = findBlade(character)
			if blade then
				local base, tip = bladeSegment(blade)
				local throttling = character:GetAttribute(HedgeConfigs.THROTTLE_ATTRIBUTE) == true
				-- Depuis l'echelle on taille le DESSUS : la surface est horizontale, sa normale pointe vers le haut.
				drawCutZone(base, tip, if throttling then "cutting" else "guide", Vector3.yAxis)
			else
				hideCutZone()
			end
			-- Le POINT ROSE de visee, lui, est pose par LadderController (il projette le curseur sur le dessus).
			return
		end
		-- release() ne cache PAS le cylindre quand on n'etait pas "engaged" (il sort tot). On le cache donc ici pour
		-- que le guide de l'echelle disparaisse bien a la sortie. Sans guide, cutZonePart est nil : appel inoffensif.
		hideCutZone()
		release(humanoid)
		return
	end

	engage(humanoid)

	-- ===== NORMALE DE TRAVAIL =====
	-- Recalculee ici, et non lue telle quelle depuis le serveur.
	--
	-- Celle du serveur designe une FACE : elle est discrete, donc elle bascule d'un quart de tour d'un seul coup
	-- dans un angle. Or tout en depend, le rail, l'aimant, l'orientation, la camera, et tout sautait avec elle.
	-- La geometrie, elle, est continue par construction : voir surfaceNormal.
	-- HAIE DE TRAVAIL = celle que le SERVEUR designe (accrochee des l'entree dans la zone), curseur en repli.
	-- Avant on ne prenait que lastHedge (le curseur) : sans souris sur la haie, la normale geometrique n'etait
	-- pas calculee et l'aimant ne s'accrochait pas. Le serveur, lui, sait deja sur quelle haie on est.
	local workHedge = serverHedge(character) or lastHedge
	local aimed = (
		if workHedge and workHedge.Parent then surfaceNormal(workHedge, root.Position) else nil
	) or serverNormal

	local previous = workNormal
	if previous then
		-- PLAFOND DE ROTATION, le seul reglage du contournement.
		--
		-- La geometrie ne saute jamais, mais sa VITESSE de rotation, si : elle passe de zero a vitesse/rayon en
		-- entrant dans l'angle, soit pres de 400 degres par seconde en replacement. Le plafonner fait prendre du
		-- retard a la normale, donc le rail tourne moins vite que le joueur et l'aimant le laisse s'ecarter :
		-- l'arc S'ELARGIT au lieu de ralentir. Le joueur garde sa vitesse, il n'est jamais freine dans l'angle.
		-- Rayon obtenu = vitesse / plafond : large et coulant en se replacant, serre et precis en taillant.
		local signed = math.atan2(previous:Cross(aimed).Y, math.clamp(previous:Dot(aimed), -1, 1))
		local maxStep = math.rad(HedgeConfigs.CORNER_TURN_SPEED) * dt
		workNormal = (CFrame.Angles(0, math.clamp(signed, -maxStep, maxStep), 0) * previous).Unit
	else
		-- Premiere frame du chantier : on se cale d'emblee, au lieu d'y arriver en pivotant depuis une normale
		-- heritee de la haie precedente.
		workNormal = aimed
	end
	local normal = workNormal :: Vector3

	-- ===== RAIL DE TRAVAIL =====
	-- Le joueur glisse LE LONG de la haie, a distance constante. On ne remappe pas ses touches : on retire de
	-- son deplacement la composante qui n'a nulle part ou aller. Q/D glissent, Z ne fait rien une fois en
	-- place, S sort (le serveur decroche des qu'il pousse vers l'arriere).
	--
	-- La distance CONSTANTE n'est pas du confort : sans elle le cadrage derive, et le meme geste de souris ne
	-- coupe plus au meme endroit. La taille deviendrait inapprenable.
	-- Les axes de travail sont ceux de la FACE, jamais ceux de la camera. Le joueur regarde la haie : sa droite
	-- longe la haie, son avant y va. Passer par la camera faisait partir D en diagonale des qu'elle etait
	-- decalee sur le cote.
	local right = (-normal):Cross(Vector3.yAxis).Unit
	-- SENS aligne sur la CAMERA. L'axe reste celui de la HAIE (glissement propre le long de la face, pas de diagonale),
	-- mais son SIGNE suit la droite de la camera : sinon, quand on pivote la vue de l'autre cote de la haie, pousser a
	-- droite envoyait le joueur a GAUCHE de l'ecran (inversion). Camera derriere (cas normal) -> +1, rien ne change.
	local cameraSign = if right:Dot(camera.CFrame.RightVector) < 0 then -1 else 1

	-- L'input brut : X = pas de cote, Z = avant / arriere (negatif vers l'avant, convention Roblox).
	local moveVector = getMoveVector()

	-- SORTIE. Seule la part ARRIERE de l'axe Z compte : le joueur pousse franchement en arriere, il quitte le
	-- chantier. On le laisse partir SANS contrainte, et c'est cette direction non contrainte que le serveur lit
	-- dans MoveDirection pour decrocher tout de suite.
	if moveVector.Z > HedgeConfigs.EXIT_MIN_INPUT then
		-- Il s'en va : c'est de la marche normale, pas un pas chasse.
		setSlide(0)
		humanoid:Move(normal * moveVector.Z + right * (moveVector.X * cameraSign), false)
		return
	end

	-- GLISSEMENT. SEUL le pas de cote deplace le joueur.
	--
	-- L'axe avant / arriere ne glisse plus. Avant, l'avant etait recycle en glissement vers la GAUCHE, au motif
	-- que la touche ne servait a rien devant une haie. Ca TROMPE le joueur : il pousse en avant et son
	-- personnage part sur le cote sans qu'il l'ait demande, donc il ne peut plus relier ce qu'il appuie a ce
	-- qu'il voit. Ne rien faire est plus lisible, et c'est la verite du chantier : devant la haie, on ne va pas
	-- plus loin.
	-- L'arriere, lui, est deja parti plus haut en sortie de chantier : il ne reste rien a en faire ici.
	local lateral = math.clamp(moveVector.X * cameraSign, -1, 1)

	-- Les jambes suivent le sens du glissement. On lit `lateral` et non l'input brut : c'est le deplacement
	-- REEL apres contrainte, donc avant + droite qui s'annulent laissent bien le joueur immobile ET jambes au
	-- repos, au lieu de le figer sur place en continuant a pietiner.
	setSlide(if math.abs(lateral) < HedgeConfigs.SLIDE_MIN_INPUT then 0 else math.sign(lateral))

	-- Moteur accelere. Sert ICI (plancher du pas) et plus bas (recul de la camera, etat du repere) : calcule une
	-- fois, reutilise.
	local throttling = character:GetAttribute(HedgeConfigs.THROTTLE_ATTRIBUTE) == true

	-- DEPLACEMENT AU PAS. Le corps avance quand le PIED POUSSE, puis il glisse sur son elan jusqu'au pas
	-- suivant. La poussee vient du marqueur de l'animation, cette ligne ne fait que la laisser retomber.
	--
	-- PLANCHER PROPRE A L'ALLURE. Ce plancher MULTIPLIE la vitesse : partage entre les deux allures, il ne
	-- permettait pas d'accelerer le replacement sans accelerer la coupe du meme coup. La coupe garde donc le sien,
	-- reste a la valeur historique, et retrouve exactement le rythme qu'elle avait.
	local glide = if throttling then HedgeConfigs.STEP_GLIDE_CUT else HedgeConfigs.STEP_GLIDE
	stepStrength = math.max(glide, stepStrength - HedgeConfigs.STEP_DECAY * dt)

	-- Repli : sans marqueur depuis trop longtemps, on repasse en continu plutot que de bloquer le joueur.
	local stepping = os.clock() - lastStepAt < HedgeConfigs.STEP_TIMEOUT
	local constrained = right * lateral * (if stepping then stepStrength else 1)

	logSlide(character, stepping)

	-- AIMANT. La distance est mesuree ICI et non lue depuis le serveur : une valeur repliquee arrive avec du
	-- retard, l'aimant corrigerait donc une position perimee et se mettrait a osciller.
	--
	-- CALCUL GEOMETRIQUE et non lancer de rayon. Le rayon partait du torse, a l'horizontale : sur une haie de
	-- trois studs il passait AU-DESSUS, ne touchait rien, et l'aimant ne s'activait jamais. Le joueur restait
	-- donc loin des haies basses sans qu'on comprenne pourquoi.
	-- Une haie est une boite : sa distance se calcule, elle n'a pas besoin d'etre sondee.
	-- La haie de travail (serveur), pas le curseur : l'aimant s'accroche des l'entree dans la zone.
	local magnetHedge = workHedge
	if magnetHedge and magnetHedge.Parent then
		local localRoot = magnetHedge.CFrame:PointToObjectSpace(root.Position)
		local localNormal = magnetHedge.CFrame:VectorToObjectSpace(normal)
		local half = magnetHedge.Size * 0.5
		-- Distance du joueur au PLAN de la face travaillee, le long de sa normale.
		local along = localRoot.X * localNormal.X + localRoot.Z * localNormal.Z
		local depth = math.abs(localNormal.X * half.X) + math.abs(localNormal.Z * half.Z)
		local gap = along - depth - HedgeConfigs.WORK_DISTANCE

		-- Rappel PROPORTIONNEL a l'ecart dans les deux cas : il faiblit en approchant de la cible, donc il ne
		-- la depasse jamais et n'oscille pas autour.
		if gap > HedgeConfigs.WORK_DISTANCE_TOLERANCE then
			-- TROP LOIN. La normale sort de la haie : s'en rapprocher, c'est aller dans son sens INVERSE.
			local strength = math.clamp(gap / HedgeConfigs.MAGNET_RANGE, 0, 1) * HedgeConfigs.MAGNET_STRENGTH
			constrained += -normal * strength
		elseif gap < -HedgeConfigs.WORK_DISTANCE_TOLERANCE then
			-- TROP PRES. Cette poussee arriere avait ete supprimee parce que le serveur la confondait avec
			-- l'intention de sortir : il decrochait, ca raccrochait, l'aimant repoussait, ca redecrochait.
			-- Elle revient parce que le serveur sait maintenant s'en garder : tant que la distance de travail
			-- n'est pas retablie, il NE JUGE PLUS l'intention de sortir (voir HedgeService.updatePlayer).
			local strength = math.clamp(-gap / HedgeConfigs.MAGNET_RANGE, 0, 1) * HedgeConfigs.MAGNET_PUSH_STRENGTH
			constrained += normal * strength
		end
	end

	-- Move ecrase la direction calculee par le module de controle. On ne l'appelle QUE pendant l'accroche :
	-- hors haie, le joueur doit retrouver son deplacement normal.
	humanoid:Move(constrained, false)

	-- ORIENTATION. La normale sort de la haie ; le joueur doit donc regarder dans le sens INVERSE.
	local position = root.Position
	local lookTarget = position - normal
	local desired = CFrame.lookAt(position, lookTarget)
	-- Lerp exponentiel avec dt dans le facteur : meme vitesse de pivot a 30 et a 60 FPS.
	root.CFrame = root.CFrame:Lerp(desired, math.min(1, HedgeConfigs.FACE_TURN_SPEED * dt))

	-- CAMERA. Placee du cote du joueur, en retrait le long de la normale, avec un decalage lateral qui donne
	-- l'angle 3/4. On la calcule a partir de la NORMALE et non du regard du joueur : elle reste donc stable
	-- pendant que le personnage pivote.
	--
	-- Le pivot du joueur tourne la NORMALE utilisee par la camera, pas le personnage : celui-ci reste face a la
	-- haie pendant qu'on regarde son travail sous un autre angle.
	-- RUBBER-BAND, retour : quand on ne pilote plus l'orbite (doigt / clic relaches) et que yaw a deborde de sa
	-- limite, un ressort SOUS-AMORTI le ramene a la limite avec un petit rebond (slime). Dans les clous, rest = yaw :
	-- la camera garde son angle, le ressort dort. Pendant l'orbite, l'input tient yaw, on garde la vitesse a zero.
	local orbitActive = orbiting or orbitTouch ~= nil
	if orbitActive then
		yawVel = 0
	else
		local yawLimit = math.rad(HedgeConfigs.CAMERA_YAW_LIMIT)
		local rest = math.clamp(yaw, -yawLimit, yawLimit)
		if yaw ~= rest or yawVel ~= 0 then
			local accel = -HedgeConfigs.CAMERA_YAW_SNAP_STIFFNESS * (yaw - rest)
				- HedgeConfigs.CAMERA_YAW_SNAP_DAMPING * yawVel
			yawVel += accel * dt
			yaw += yawVel * dt
			-- Un ressort expo n'atteint jamais sa cible : des qu'on est assez pres, on cale pile et on coupe.
			if math.abs(yaw - rest) < 1e-4 and math.abs(yawVel) < 1e-3 then
				yaw = rest
				yawVel = 0
			end
		end
	end

	-- PREMIERE PERSONNE (CAMERA_FIRST_PERSON) : oeil A LA TETE, regard vers la haie. Sinon vue iso 3/4 (orbite).
	local target = camera.CFrame
	if HedgeConfigs.CAMERA_FIRST_PERSON then
		-- Vue rapprochee DE COTE : oeil pres de la tete mais DECALE lateralement (FP_SIDE) + un peu en arriere et en
		-- hauteur, et il regarde le POINT DE TRAVAIL devant le joueur -> on voit la surface de biais (pas plat dans la
		-- haie). La visee part de CETTE camera (ViewportPointToRay) -> elle suit toute seule, rien a changer.
		local head = character:FindFirstChild("Head")
		local headPos = if head and head:IsA("BasePart")
			then head.Position
			else position + Vector3.new(0, HedgeConfigs.CAMERA_LOOK_HEIGHT, 0)
		-- Direction horizontale LE LONG de la haie (perpendiculaire a la normale) : sert au decalage lateral de l'oeil.
		local side = normal:Cross(Vector3.yAxis)
		side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
		local eye = headPos
			+ side * HedgeConfigs.FP_SIDE
			+ normal * HedgeConfigs.FP_BACK
			+ Vector3.new(0, HedgeConfigs.FP_HEIGHT, 0)
		local lookAt = headPos - normal * HedgeConfigs.FP_LOOK_FORWARD + Vector3.new(0, HedgeConfigs.FP_LOOK_HEIGHT, 0)
		target = CFrame.lookAt(eye, lookAt)
	else
		local viewNormal = CFrame.Angles(0, yaw, 0) * normal
		-- Le cote se prend perpendiculairement a cette direction, dans le plan horizontal.
		local side = viewNormal:Cross(Vector3.yAxis).Unit
		-- Accelerer rapproche la camera : l'attention se resserre sur le geste. Le lerp de la camera fait la
		-- transition tout seul, il n'y a rien de plus a ecrire.
		-- La distance de recul se LISSE en parametre (rapproche a l'acceleration, ressort en relachant) : ca ne deforme
		-- pas l'orbite, contrairement a un lissage de la POSITION de la camera. Une fois la camera placee direct (plus
		-- bas), c'est le seul mouvement doux qui reste.
		local targetDistance = if throttling then HedgeConfigs.CAMERA_DISTANCE_THROTTLE else HedgeConfigs.CAMERA_DISTANCE
		currentDistance += (targetDistance - currentDistance) * math.min(1, HedgeConfigs.CAMERA_DISTANCE_LERP * dt)
		-- Le zoom multiplie TOUT le placement, pas le seul recul : l'angle 3/4 reste donc le meme de pres comme de
		-- loin. En ne mettant a l'echelle que le recul, la vue plongerait en zoomant et s'aplatirait en reculant.
		-- Sur mobile : depart plus DE FACE (moins de decalage lateral). Le joueur ajuste ensuite par l'orbite tactile.
		local sideAmount = if InputDevice.isTouch() then HedgeConfigs.CAMERA_SIDE_TOUCH else HedgeConfigs.CAMERA_SIDE
		local camPosition = position
			+ (
				viewNormal * currentDistance
				+ side * sideAmount
				+ Vector3.new(0, HedgeConfigs.CAMERA_HEIGHT, 0)
			) * cameraZoom
		local camLook = position + Vector3.new(0, HedgeConfigs.CAMERA_LOOK_HEIGHT, 0)
		target = CFrame.lookAt(camPosition, camLook)
	end
	-- ORBITE 1:1, sans corde coupee. On ne LISSE PAS la position de la camera pendant le travail : lisser une
	-- position qui tourne sur un arc la fait plonger vers l'interieur du cercle puis ressortir (la "courbe"), et
	-- c'est PIRE quand on tourne vite car le retard grandit. On place donc la camera DIRECTEMENT sur son cercle au
	-- yaw courant : elle colle au doigt et garde son rayon. Seule EXCEPTION, l'arrivee a l'engage : on glisse une
	-- fois depuis la camera de jeu jusqu'a la vue de travail (doux), jusqu'a etre assez pres.
	if camArrived then
		camera.CFrame = target
	else
		camera.CFrame = camera.CFrame:Lerp(target, math.min(1, HedgeConfigs.CAMERA_LERP_SPEED * dt))
		if (camera.CFrame.Position - target.Position).Magnitude < HedgeConfigs.CAMERA_SETTLE_DIST then
			camArrived = true
		end
	end

	-- Humanoid.CameraOffset n'est applique que par la camera par defaut de Roblox : en Scriptable il est
	-- ignore. Sans cette ligne, secousses, bob et plongee disparaitraient des qu'on travaille une haie, donc
	-- exactement la ou le retour de coupe devra se voir.
	-- Applique APRES le lerp et en repere local, pour que le decalage ne soit pas lisse : un impact doit
	-- claquer, pas se fondre.
	camera.CFrame = camera.CFrame * CFrame.new(CameraEffects.GetOffset())

	-- Apres la camera : la bille se calcule depuis la camera de CETTE frame, sinon elle viserait a partir de
	-- l'image precedente et flotterait en arriere pendant les pivots.
	-- workHedge en 3e argument : la bille doit se projeter sur la haie qui a donne `normal`, pas sur la derniere
	-- survolee par le curseur (les deux different des qu'il y a plusieurs haies).
	local aim, onTop = updateCursor(character, normal, workHedge)

	-- HAUTEUR DE COUPE. La pose ne sort que moteur EN MARCHE : lever le taille-haie vers le haut de la haie
	-- alors qu'il est eteint n'a aucun sens, le joueur ne taille rien.
	local engine = character:GetAttribute(HedgeConfigs.ENGINE_ATTRIBUTE) == true
	-- Reactivite de la pose PROPRE A L'OUTIL : la cisaille (legere) colle a la visee (0), le taille-haie (lourd) traine.
	local poseFollow = if toolConfig and toolConfig.poseFollowSpeed ~= nil
		then toolConfig.poseFollowSpeed
		else HedgeConfigs.UPDOWN_FOLLOW_SPEED
	setPose(engine and aim ~= nil, aim or 0, onTop, dt, poseFollow)
	-- Meme etat que la pose : le coup de cisaille (clic) n'est autorise que moteur pret ET visee sur une surface
	-- taillable. Sinon un clic jouerait le geste dans le vide et enverrait un CutSnip que le serveur rejetterait.
	aimActive = engine and aim ~= nil

	-- CISAILLE AU DOIGT (tactile). Le tap seul ne coupe jamais : a l'instant du contact, aimActive est encore faux
	-- (le doigt vient de se poser). Tant que le doigt est pose sur une surface taillable, on RE-declenche le coup a
	-- intervalle (le serveur borne deja a CUT_CLICK_MIN_INTERVAL) -> on coupe en glissant, comme le taille-haie.
	if InputDevice.isTouch() and aimTouch and heldPerClick and snipRemote and engaged and aimActive then
		touchSnipClock += dt
		if touchSnipClock >= HedgeConfigs.CUT_TOUCH_SNIP_INTERVAL then
			touchSnipClock = 0
			snipRemote:FireServer()
		end
	else
		touchSnipClock = HedgeConfigs.CUT_TOUCH_SNIP_INTERVAL -- pret a tirer des le 1er contact valide
	end

	-- On envoie le SEGMENT REEL DE LA LAME, pas la hauteur visee.
	--
	-- Les deux ne coincident pas : rien ne garantit qu'a 80 pour cent de visee le bras place la lame a 80 pour
	-- cent de la hauteur de la haie. Envoyer la visee faisait couper la ou pointe le CURSEUR, souvent bien
	-- au-dessus de la lame. Ici, ce qu'on voit est ce qui coupe, sur TOUTE la lame, quelle que soit l'animation.
	local blade = findBlade(character)
	if engine and blade then
		local base, tip = bladeSegment(blade)
		sendAim(base, tip)
	else
		sendAim(nil, nil)
	end

	-- ETAT DU REPERE :
	--   hors haie -> la souris a quitte la haie (aim nil), la coupe ne mordra rien : orange.
	--   coupe     -> gachette pressee, il taille : discret, on ne masque pas le travail.
	--   guide     -> il vise mais ne taille pas encore : bien visible, "tu couperas ici".
	-- `throttling` est deja calcule plus haut dans update (avant le deplacement au pas) : on le reutilise.
	local cutState = if aim == nil then "off" elseif throttling then "cutting" else "guide"

	-- COULEUR DU REPERE : blanc s'il reste a couper, orange si c'est nu. Approximation cote client : hors coupe on tient
	-- lastCutTickClock a jour (etat "humide" par defaut) ; pendant la coupe, SEULS les coups qui mordent l'avancent.
	-- Tailler sans qu'un coup morde pendant VISUAL_CUT_DRY_TIME = on gratte du nu -> orange.
	if not throttling then
		lastCutTickClock = os.clock()
	end
	local dry = throttling and (os.clock() - lastCutTickClock) > HedgeConfigs.VISUAL_CUT_DRY_TIME
	cutZoneTargetColor = if dry then HedgeConfigs.VISUAL_CUT_BARE_COLOR else HedgeConfigs.VISUAL_CUT_FOLIAGE_COLOR

	-- Dessine le repere AVEC LE DERNIER SEGMENT ENVOYE (ce que le serveur a en main), plaque selon la normale de la
	-- surface travaillee. Le DESSUS a une normale VERTICALE, la face une horizontale : on passe la bonne pour que le
	-- repere se pose A PLAT sur ce qu'on taille (a plat sur le dessus, plaque contre la face).
	local surfaceNormal = if onTop then Vector3.yAxis else normal
	drawCutZone(lastAimBase, lastAimTip, cutState, surfaceNormal)
end

function HedgeController.init()
	-- BindToRenderStep a la priorite Camera, et NON un simple RenderStepped.
	--
	-- Le module de controle de Roblox tourne a la priorite Input (100) et appelle humanoid:Move avec l'input
	-- brut. Notre contrainte doit passer APRES, sinon il ecraserait la notre et le joueur pourrait avancer et
	-- reculer librement. Camera (200) garantit cet ordre ; un RenderStepped simple ne le garantit pas.
	local remote = RemoteSetup.getRemote("SetAim", "Hedge")
	if remote and remote:IsA("RemoteEvent") then
		aimRemote = remote
	else
		warn("[HedgeController] Remote Hedge/SetAim introuvable : la coupe ne suivra pas la visee")
	end

	local snip = RemoteSetup.getRemote("CutSnip", "Hedge")
	if snip and snip:IsA("RemoteEvent") then
		snipRemote = snip
	else
		warn("[HedgeController] Remote Hedge/CutSnip introuvable : la cisaille ne coupera pas")
	end

	-- Resolus UNE fois : les chercher a chaque coupe ferait un parcours d'arborescence sept fois par seconde.
	if #HedgeConfigs.CUT_SOUND > 0 then
		local node: Instance? = SoundService
		for _, name in ipairs(HedgeConfigs.CUT_SOUND) do
			node = node and node:FindFirstChild(name)
		end

		if node and node:IsA("Sound") then
			-- Chemin qui designe un son precis : il n'y en aura qu'un, et c'est un cas valide.
			table.insert(cutSounds, node)
		elseif node then
			-- Chemin qui designe un DOSSIER : on prend tout ce qu'il contient. Deposer un echantillon de plus
			-- dans Studio suffit donc a enrichir la coupe.
			for _, child in ipairs(node:GetChildren()) do
				if child:IsA("Sound") then
					table.insert(cutSounds, child)
				end
			end
		end

		if #cutSounds == 0 then
			warn(`[HedgeController] Aucun son de coupe sous SoundService.{table.concat(HedgeConfigs.CUT_SOUND, ".")}`)
		end
	end

	local effects = ReplicatedStorage:FindFirstChild("Assets")
	effects = effects and effects:FindFirstChild("Effects")
	local found = effects and effects:FindFirstChild(HedgeConfigs.CUT_EFFECT)
	if found and found:IsA("BasePart") then
		cutEffect = found
	end

	RunService:BindToRenderStep("LeafiaHedge", Enum.RenderPriority.Camera.Value, update)

	-- Les pistes se chargent au spawn, JAMAIS dans la boucle : setupCharacter attend l'Animator, et un
	-- WaitForChild dans un BindToRenderStep bloquerait le rendu de la frame.
	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		task.spawn(setupCharacter, player.Character)
	end

	-- PIVOT au clic DROIT maintenu. Le gauche reste a l'outil et le curseur reste libre pour viser la haie ;
	-- le bouton droit est le seul disponible.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		-- DOIGT (tactile). Sur la haie -> il TAILLE (aimTouch ; la gachette part deja au Touch via ToolController). A
		-- COTE de la haie (ciel / sol), pendant le travail -> il fait TOURNER la camera (orbitTouch), pas tailler.
		-- Un seul doigt fait donc les deux selon OU on le pose. Non gameProcessed : le joystick / les boutons sont hors.
		if input.UserInputType == Enum.UserInputType.Touch then
			local character = player.Character
			local m = UserInputService:GetMouseLocation()
			if engaged and character and not touchOnHedge(character, Vector2.new(m.X, m.Y)) then
				orbitTouch = input
			else
				aimTouch = input
			end
		end
		-- COUP DE CISAILLE (outil clic-par-clic). Marche au SOL (engaged + visee valide) ET depuis l'ECHELLE
		-- (ladder-trim : la visee du dessus est envoyee par LadderController, pas par HedgeController qui ne
		-- s'engage pas la-haut). heldPerClick est faux pour le taille-haie (coupe continue par la gachette) : ce
		-- bloc ne le touche pas. Le serveur revalide tout (outil, contact, portee, anti-spam) ; le client declenche.
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local character = player.Character
			local ladderTrim = character ~= nil
				and character:GetAttribute(HedgeConfigs.LADDER_TRIM_ATTRIBUTE) == true
			if heldPerClick and snipRemote and ((engaged and aimActive) or ladderTrim) then
				snipRemote:FireServer()
			end
			return
		end
		-- PIVOT camera au clic DROIT : n'a de sens qu'au travail AU SOL.
		if not engaged then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbiting = true
			-- Le curseur reste sur place pendant le glissement : sans ca il partirait hors de l'ecran au bout
			-- de deux pivots, et la bille de visee avec lui.
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		-- Pas de filtre gameProcessed au relachement : le pivot ne doit jamais rester coince.
		-- Le doigt de visee se leve : on cesse de viser (la gachette se coupe de son cote via ToolController).
		if input == aimTouch then
			aimTouch = nil
		end
		-- Le doigt d'orbite se leve : on arrete de tourner la camera.
		if input == orbitTouch then
			orbitTouch = nil
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbiting = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not engaged then
			return
		end

		-- ORBITE TACTILE : le doigt pose HORS de la haie glisse -> on tourne la camera (meme yaw que le clic droit
		-- souris, sensibilite propre au doigt). Le personnage ne tourne pas : seule la camera pivote autour de lui.
		if input == orbitTouch then
			applyOrbitDrag(input.Delta.X, HedgeConfigs.CAMERA_YAW_TOUCH_SENSITIVITY)
			return
		end

		-- ZOOM A LA MOLETTE. Elle ne sert a rien d'autre pendant le travail : la camera est en Scriptable, donc
		-- celle de Roblox ne lit plus rien. Son zoom a elle est fige et le joueur le retrouve intact en sortant.
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			-- Position.Z vaut +1 vers l'avant. On veut alors se RAPPROCHER, donc REDUIRE le facteur : le signe
			-- s'inverse ici, une fois, plutot que dans la tete du joueur.
			--
			-- En PROPORTION et non en pas fixe : un cran doit changer la vue d'autant de pres que de loin. Avec un
			-- pas fixe, les crans sont brutaux au plus pres et imperceptibles au plus loin.
			local factor = 1 - input.Position.Z * HedgeConfigs.CAMERA_ZOOM_STEP
			cameraZoom =
				math.clamp(cameraZoom * factor, HedgeConfigs.CAMERA_ZOOM_MIN, HedgeConfigs.CAMERA_ZOOM_MAX)
			return
		end

		if not orbiting or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		-- Seul le deplacement HORIZONTAL compte : la hauteur de vue reste celle du reglage, on ne veut pas que
		-- le joueur puisse se retrouver a regarder ses pieds ou le ciel en plein travail.
		applyOrbitDrag(input.Delta.X, HedgeConfigs.CAMERA_YAW_SENSITIVITY)
	end)

	player.CharacterRemoving:Connect(function()
		-- Le personnage disparait : on relache tout, sinon la camera resterait bloquee en Scriptable sur un
		-- personnage mort et le joueur ne verrait plus rien apres son respawn.
		release(nil)
		hideDebug()
		hideCursor()
		-- Les pistes appartiennent a l'Animator qui part avec le personnage : les garder ferait travailler sur
		-- des pistes mortes au prochain spawn, sans jamais d'erreur pour le signaler.
		slideTrack = nil
		updownTrack = nil
		rightleftTrack = nil
		poseTrack = nil
		-- Force le rechargement des poses au prochain spawn : setupCharacter les recharge, mais si le nouvel outil
		-- est le meme, la boucle update sauterait le rechargement en croyant le dossier deja en place.
		poseFolder = nil
		slideDirection = 0
	end)
end

return HedgeController
