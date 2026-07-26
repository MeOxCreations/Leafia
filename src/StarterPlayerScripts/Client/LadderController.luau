--!strict
-- PROTOTYPE escabeau, SOCLE. Le joueur entre dans une zone de detection du rig (box_detecte_A / box_detecte_B),
-- on l'AIMANTE au pied de l'echelle face a elle, root ANCRE + WalkSpeed 0 (pas de marche dans le vide), et deux
-- animations s'echangent selon l'etat :
--   - Au sol, pret a monter (pieds au sol, main sur l'echelle) : IdleDownAnimation, EN BOUCLE.
--   - En train de monter / descendre : UpDownAnimation, pilotee par W/S (Z/S sur AZERTY).
-- W monte (l'anim avance), S descend (l'anim recule). Tout en bas, S detache de l'echelle (IdleDown a l'envers).
--
-- Camera : vue ISO orbitale, activee des l'accroche. Elle ease depuis la vue joueur vers la vue iso, suit le corps
-- qui monte, et le joueur peut tourner librement (clic droit) + zoomer (molette).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local Toast = require(ReplicatedStorage.Modules.UI.Core.Toast)

local LadderController = {}

local player = Players.LocalPlayer

-- Rigs poses a la main dans le Workspace, leurs deux zones, et le dossier des anims (renomme Escabaut -> Ladder).
-- PREFIXE et non nom exact : on gere PLUSIEURS echelles. Tout enfant du Workspace dont le nom commence par ce
-- prefixe est une echelle (ex : Escabaut_1a_rig, Escabaut_2a_rig, une copie...).
local LADDER_PREFIX = "Escabaut"
local ZONE_NAMES = { "box_detecte_A", "box_detecte_B" }
local ANIM_FOLDER = { "Animations", "Player", "Tools", "Ladder" }
local IDLE_ANIM = "IdleDownAnimation" -- pose prete, au sol
local CLIMB_ANIM = "UpDownAnimation" -- grimpe (corps / jambes), pilotee W/S
local GRIP_ANIM = "UpDownHandGripAnimation" -- main qui agrippe l'echelle, jouee EN SYNC avec la grimpe
-- Maintien EN HAUT : jambes bien posees sur les marches. Joue au sommet PAR-DESSUS la grimpe gelee, en Action4 pour
-- gagner sur les jambes de la grimpe. Meme dossier que la grimpe (Ladder).
local TOP_LEGS_ANIM = "IdleUpLadder"
-- CONDITION pour que ca marche : IdleUpLadder ne doit cler QUE les jambes (LeftUpperLeg/LowerLeg/Foot + cote droit),
-- PAS le LowerTorso ni les hanches. Le LowerTorso est ce que la grimpe gelee monte pour tenir le corps en haut : si
-- IdleUpLadder le cle aussi (a hauteur sol), en Action4 elle ecrase la montee et le corps RETOMBE au pied. A false,
-- on la coupe (le corps reste tenu par la grimpe seule, jambes en pose de grimpe).
local TOP_LEGS_ENABLED = true
-- Coupe gauche-droite du DESSUS (bras), jouee AU SOMMET par-dessus IdleUpLadder. Dossier du taille-haie.
local TRIM_FOLDER = { "Animations", "Player", "Tools", "HedgeTrimmer" }
local TRIM_ANIM = "RightLeftAnimation"

local MAGNET_RATE = 10 -- vitesse d'aspiration vers le point de montage
local CLIMB_SPEED = 0.7 -- vitesse de lecture de l'anim de grimpe
local EXIT_SPEED = 3 -- vitesse de lecture d'IdleDown A L'ENVERS pour sortir (plus haut = sortie plus rapide)
local MOUNT_BACK = 1.25 -- recul du point de montage depuis le centre de la zone, vers l'exterieur de l'echelle (studs)

-- Camera : ORBITE autour du joueur qui grimpe, du COTE de la haie ou est posee l'echelle. On trouve la haie la plus
-- proche, on regarde de quel cote l'echelle se trouve (outward), et on place la camera a un azimut + une elevation
-- par defaut (l'angle iso 3/4). Le joueur peut ensuite tourner LIBREMENT (clic droit) : horizontal 360 + vertical
-- borne. Seul le POINT SUIVI est lisse ; l'orbit, lui, est DIRECT, donc reactif meme en tournant vite.
local CAM_ISO_DIST = 19 -- rayon : distance camera -> joueur (studs)
local CAM_ISO_YAW = 25 -- azimut par defaut = l'angle 3/4 (degres ; le signe choisit le cote du cadre)
local CAM_ISO_PITCH = 38 -- elevation par defaut (degres ; haut = vue plus plongeante / iso)
local CAM_ISO_LOOK = 3 -- point vise, au-dessus du joueur (studs). Monte-le pour viser davantage le haut de la haie
local CAM_FOLLOW = 14 -- lissage du SUIVI du joueur (le point suivi seulement ; l'orbit reste direct, sans lag)
local CAM_ENTER = 0.7 -- duree de l'entree en douceur : la vue glisse de la cam joueur vers la vue iso (s)
local CAM_TWEEN_OUT = 0.3 -- duree du retour derriere le joueur a la sortie (s). Court : le joueur RECULE en sortant,
-- une cible figee "derriere lui" vieillit vite ; un tween long laisse la vue trainer pres de l'echelle avant de le
-- rattraper. Court = handoff rapide vers la camera de jeu qui suit le joueur en direct.
-- Orbit joueur au clic droit maintenu (meme geste qu'en taillant), applique DIRECT (pas de lerp) donc jamais en
-- retard. Yaw = tour horizontal complet ; pitch = inclinaison verticale, bornee pour ne pas retourner la camera.
local CAM_YAW_SENS = 0.4 -- degres de pivot horizontal par pixel de souris
local CAM_PITCH_SENS = 0.4 -- degres de pivot vertical par pixel de souris
local CAM_PITCH_MIN = -45 -- inclinaison la plus basse (regarder le haut de la haie d'en dessous)
local CAM_PITCH_MAX = 82 -- inclinaison la plus haute (vue plongeante ; sous 90 pour ne pas retourner la camera)
-- Zoom molette : multiplie le rayon. En PROPORTION (et non un pas fixe) pour que chaque cran change la vue d'autant
-- de pres que de loin. Pas besoin de tenir le clic droit : la molette zoome des qu'on est sur l'echelle.
local CAM_ZOOM_STEP = 0.1 -- fraction par cran de molette
local CAM_ZOOM_MIN = 0.5 -- au plus pres (rayon * 0.5)
local CAM_ZOOM_MAX = 1.8 -- au plus loin (rayon * 1.8)

local idleTrack: AnimationTrack? = nil
local climbTrack: AnimationTrack? = nil
local gripTrack: AnimationTrack? = nil
local trimTrack: AnimationTrack? = nil
-- Maintien EN HAUT (jambes sur les marches). Joue au sommet a la place de la grimpe, sous les bras qui taillent.
local topLegsTrack: AnimationTrack? = nil
-- Sert AUSSI d'etat "accroche" : non-nil = on est sur l'echelle.
local mountCFrame: CFrame? = nil
-- Empeche de se raccrocher tant qu'on n'a pas quitte la zone une fois (apres une sortie).
local canMount = true
-- Evite de repeter le toast "equipe ton taille-haie" a chaque frame passee dans la zone sans outil.
local noTrimmerNotified = false
-- WalkSpeed d'origine, retenue pour la rendre a la sortie.
local savedWalkSpeed: number? = nil
-- La montee n'est ARMEE qu'apres avoir relache W une fois depuis l'accroche. Le joueur entre souvent dans la zone
-- en MARCHANT (touche avant = KeyCode.W), et sans ca on lancerait la grimpe direct au lieu de l'idle.
local climbArmed = false
-- Phase sur l'echelle :
--   "ready"    IdleDown EN BOUCLE (pret a monter). W = grimper, S = ressortir.
--   "climbing" UpDown pilotee par W/S ; au bas de la descente, on repasse par "exiting".
--   "top"      grimpe gelee au max, taille du dessus (IdleUpLadder + RightLeft).
--   "exiting"  IdleDown a l'envers (max -> 0) ; arrive a 0, on lache l'echelle.
local phase = "off"

-- folderPath = chemin sous ReplicatedStorage (les anims de l'echelle et celle du taille-haie sont dans des
-- dossiers differents).
local function resolveAnimation(folderPath: { string }, name: string): Animation?
	local node: Instance? = ReplicatedStorage
	for _, folder in ipairs(folderPath) do
		node = node and node:FindFirstChild(folder)
	end
	node = node and node:FindFirstChild(name)
	return if node and node:IsA("Animation") then node else nil
end

local function getRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getAnimator(): Animator?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end
	return humanoid:WaitForChild("Animator", 5) :: Animator?
end

-- Humanoid du joueur, pour couper sa vitesse de marche (WalkSpeed) sur l'echelle : a 0, le Humanoid ne se croit
-- plus en deplacement, donc l'anim de marche par defaut ne se joue plus. C'est ca qui tue le "walk dans le vide".
local function getHumanoid(): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid:IsA("Humanoid") then humanoid else nil
end

-- TAILLE DEPUIS L'ECHELLE. Remotes recuperes dans init. SetAim = segment reel de la lame envoye au serveur (comme
-- HedgeController) ; SetLadderWork = "je suis en haut, pret a tailler le dessus" (booleen), le serveur choisit la
-- haie. On garde l'etat pour ne pas re-signaler chaque frame.
local aimRemote: RemoteEvent? = nil
local ladderWorkRemote: RemoteEvent? = nil
local ladderWorkActive = false
-- "Sur l'echelle" (toute phase) : le serveur desengage l'aimant du sol tant que c'est vrai, et rejoue le maintien
-- de l'outil a la sortie. Different de SetLadderWork, qui ne concerne que la coupe au sommet.
local onLadderRemote: RemoteEvent? = nil

-- La lame : la meme part que le systeme de taille au sol (HitBoxRoot). Ces deux helpers refletent HedgeController ;
-- si ca se stabilise, les sortir dans un util partage (voir CLAUDE.md sur la duplication).
local function findBlade(character: Model): BasePart?
	local found = character:FindFirstChild("HitBoxRoot", true)
	return if found and found:IsA("BasePart") then found else nil
end

-- Taille-haie en main ? La lame (HitBoxRoot) n'existe dans le perso QUE quand l'outil est equipe. C'est donc le
-- signal d'equipement. On l'exige pour monter : sans outil, taille depuis l'echelle impossible et etats incoherents.
local function isTrimmerEquipped(): boolean
	local character = player.Character
	return character ~= nil and findBlade(character) ~= nil
end

-- Les deux bouts de la lame en monde, le long de son axe le PLUS LONG. Le serveur taille le long de cette ligne.
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

-- Signale au serveur qu'on taille (ou plus) depuis l'echelle. Idempotent : ne renvoie que sur changement d'etat.
local function setLadderWork(active: boolean)
	if active == ladderWorkActive then
		return
	end
	ladderWorkActive = active
	if ladderWorkRemote then
		ladderWorkRemote:FireServer(active)
	end
end

-- Envoie le segment de lame courant au serveur (rien si pas d'outil en main : pas de lame a envoyer).
local function sendBladeAim()
	local remote = aimRemote
	if not remote then
		return
	end
	local character = player.Character
	local blade = character and findBlade(character)
	if blade then
		local base, tip = bladeSegment(blade)
		remote:FireServer(base, tip)
	end
end

-- La haie de travail (retenue a l'accroche) : sert a projeter le curseur sur son DESSUS pour la visee de coupe.
local mountHedge: BasePart? = nil
-- Direction horizontale vers l'EXTERIEUR de la haie, du cote de l'echelle (le "cote" detecte). Declaree ICI (avant
-- topAim qui s'en sert pour trouver l'axe de largeur du dessus) ; elle sert aussi a la camera plus bas.
local camOutward: Vector3? = nil

-- Inverse le sens du balayage. La souris et la lame peuvent partir a l'oppose selon le sens de RightLeftAnimation et
-- l'orientation de la haie. A basculer si le sens est faux (curseur a gauche -> lame a droite = mets false, ou true).
local CUT_TOP_INVERT = false
-- Lissage du balayage : la lame GLISSE vers la visee au lieu de la coller sec. Haut = plus reactif (colle a la
-- souris), bas = plus doux / trainant. La position lissee courante est cutRatioSmooth.
local CUT_SWEEP_SMOOTH = 10
local cutRatioSmooth = 0.5

-- Point rose de visee sur le dessus (comme le curseur des cotes). Cree une fois, sous la camera. Neon = bien visible.
local topCursorPart: BasePart? = nil
local lastCutRatio = 0.5

local function getTopCursor(): BasePart
	local existing = topCursorPart
	if existing and existing.Parent then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "LadderCutCursor"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * HedgeConfigs.CURSOR_SIZE
	part.Color = HedgeConfigs.CURSOR_COLOR
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = workspace.CurrentCamera
	topCursorPart = part
	return part
end

local function hideTopCursor()
	if topCursorPart then
		topCursorPart:Destroy()
		topCursorPart = nil
	end
end

-- VISEE DU DESSUS. On projette le curseur sur le plan du haut de la haie, mais on RAMENE le point sur l'emprise du
-- dessus (clampe) : il ne part donc jamais dans le vide, il reste SUR la haie. Le ratio se lit sur la LARGEUR REELLE
-- du dessus (auto-echelle) : les extremes tombent PILE aux bords de la haie, plus besoin de pointer loin. Le point
-- rose montre ou on vise, la lame suit. Renvoie le dernier ratio si on ne peut pas viser (regard a plat).
local function topAim(): number
	local camera = workspace.CurrentCamera
	local hedge = mountHedge
	if not (camera and hedge and hedge.Parent) then
		hideTopCursor()
		return lastCutRatio
	end
	local half = hedge.Size * 0.5
	local topY = hedge.Position.Y + half.Y
	local ray = camera:ViewportPointToRay(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
	-- La vue iso plonge : le rayon DESCEND vers le plan. S'il monte ou est a plat, pas d'intersection utile.
	if ray.Direction.Y > -1e-3 then
		hideTopCursor()
		return lastCutRatio
	end
	local t = (topY - ray.Origin.Y) / ray.Direction.Y
	if t <= 0 then
		hideTopCursor()
		return lastCutRatio
	end
	-- Point du plan ramene dans le repere de la haie, CLAMPE a l'emprise du dessus : le point rose reste sur la haie.
	local localHit = hedge.CFrame:PointToObjectSpace(ray.Origin + ray.Direction * t)
	localHit = Vector3.new(math.clamp(localHit.X, -half.X, half.X), half.Y, math.clamp(localHit.Z, -half.Z, half.Z))
	local worldBall = hedge.CFrame:PointToWorldSpace(localHit)
	getTopCursor().Position = worldBall
	-- Ratio le long de la DROITE DE LA CAMERA (= la droite de l'ECRAN), pas celle du perso : c'est avec la souris,
	-- sur l'ecran, que le joueur vise. Tourner l'echelle retourne le perso mais PAS l'ecran, donc "souris a droite =
	-- lame a droite" reste vrai quelle que soit l'orientation. On mesure a plat (Y ignore), sur la largeur reelle du
	-- dessus projetee sur cet axe (auto-echelle).
	local camRight = camera.CFrame.RightVector
	camRight = Vector3.new(camRight.X, 0, camRight.Z)
	camRight = if camRight.Magnitude > 1e-3 then camRight.Unit else Vector3.xAxis
	local halfWidth = math.abs(camRight.X) * half.X + math.abs(camRight.Z) * half.Z
	local ratio = if halfWidth > 1e-3
		then ((worldBall - hedge.Position):Dot(camRight) + halfWidth) / (2 * halfWidth)
		else 0.5
	if CUT_TOP_INVERT then
		ratio = 1 - ratio
	end
	lastCutRatio = math.clamp(ratio, 0, 1)
	return lastCutRatio
end

-- Tween camera en cours (sortie). Garde pour l'annuler si l'etat change avant la fin.
local camTween: Tween? = nil
-- Etat de la camera iso. camTracking = true quand le suivi iso est actif (camOutward est declaree plus haut).
local camTracking = false
-- camSubject = point suivi LISSE (le corps qui monte), pour que l'orbit ne parte pas d'un point qui tremble.
local camSubject: Vector3? = nil
-- Entree en douceur : camEnterFrom = la CFrame de la cam joueur au moment de l'accroche ; on ease depuis elle vers
-- la vue iso pendant camEnterElapsed < CAM_ENTER, puis l'orbit reprend en direct. Sans ca l'entree snappe sec.
local camEnterFrom: CFrame? = nil
local camEnterElapsed = 0
-- Orbit joueur : ladderYaw / ladderPitch = pivots accumules a la souris ; orbiting = clic droit maintenu maintenant.
-- ladderZoom = multiplicateur de rayon (molette).
local ladderYaw = 0
local ladderPitch = 0
local ladderZoom = 1
local orbiting = false

-- Le point du corps a viser / suivre. LowerTorso d'abord : c'est LUI qui MONTE avec l'anim (le HumanoidRootPart,
-- lui, reste ancre en bas). Sans ca la camera ne "suivrait" pas la grimpe. Secours : Torso (R6), puis HRP.
local function getTrackPoint(): Vector3?
	local character = player.Character
	if not character then
		return nil
	end
	local part = character:FindFirstChild("LowerTorso")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part.Position else nil
end

-- La haie taguee la plus proche d'un point (l'echelle). C'est elle qui donne le cote et le haut a cadrer.
local function nearestHedge(position: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, instance in ipairs(CollectionService:GetTagged(HedgeConfigs.TAG)) do
		if instance:IsA("BasePart") then
			local d = (instance.Position - position).Magnitude
			if d < bestDist then
				bestDist = d
				best = instance
			end
		end
	end
	return best
end

-- Le COTE de la haie ou se trouve l'echelle, cale sur la face la plus proche (devant/derriere/gauche/droite) et
-- mis a plat. C'est la "normale" simplifiee qui sort de la haie vers l'echelle : la camera se posera dans cette
-- direction, donc automatiquement du bon cote quelle que soit l'orientation de la haie.
local function outwardSide(hedge: BasePart, from: Vector3): Vector3
	local localDir = hedge.CFrame:VectorToObjectSpace(from - hedge.Position)
	local axis = if math.abs(localDir.X) >= math.abs(localDir.Z)
		then Vector3.new(if localDir.X >= 0 then 1 else -1, 0, 0)
		else Vector3.new(0, 0, if localDir.Z >= 0 then 1 else -1)
	local world = hedge.CFrame:VectorToWorldSpace(axis)
	world = Vector3.new(world.X, 0, world.Z)
	return if world.Magnitude > 1e-3 then world.Unit else Vector3.new(0, 0, 1)
end

-- Envoie la camera vers cf par un tween, puis rend la main a la camera de jeu (Custom). Sert a la SORTIE : ramener
-- la vue derriere le joueur en douceur avant de rendre le controle, au lieu d'un saut sec vers la vue par defaut.
local function tweenCameraToCustom(cf: CFrame, duration: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if camTween then
		camTween:Cancel()
		camTween = nil
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(camera, info, { CFrame = cf })
	camTween = tween
	tween.Completed:Connect(function()
		if camTween ~= tween then
			return -- un autre tween a pris le relais entre-temps : on ne fait rien.
		end
		-- Rien ne reste accroche : la camera de jeu reprend (derriere le joueur, libre a la souris).
		local cam = workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Custom
		end
	end)
	tween:Play()
end

-- priority : par defaut Action4. Les pistes de BASE (grimpe, maintien en haut) se chargent plus BAS (Action3) pour
-- que les pistes qui cLENT les memes membres par-dessus (main qui agrippe, coupe des bras) l'emportent. A priorite
-- EGALE Roblox MELANGE, il ne choisit pas : voir le journal dans CLAUDE.md.
local function loadTrack(
	animator: Animator,
	folderPath: { string },
	name: string,
	priority: Enum.AnimationPriority?
): AnimationTrack?
	local animation = resolveAnimation(folderPath, name)
	if not animation then
		warn(`[Ladder] Animation introuvable : ReplicatedStorage.{table.concat(folderPath, ".")}.{name}`)
		return nil
	end
	local track = animator:LoadAnimation(animation)
	track.Priority = priority or Enum.AnimationPriority.Action4
	-- Bouclees VOLONTAIREMENT : Roblox ne les coupe pas a leur fin, on les fige / borne nous-memes.
	track.Looped = true
	return track
end

-- Charge les pistes une fois. Renvoie false si l'Animator ou une anim OBLIGATOIRE manque.
local function ensureTracks(): boolean
	if idleTrack and climbTrack then
		return true
	end
	local animator = getAnimator()
	if not animator then
		warn("[Ladder] Animator introuvable")
		return false
	end
	idleTrack = idleTrack or loadTrack(animator, ANIM_FOLDER, IDLE_ANIM)
	-- La grimpe est la piste de BASE (Action3) : gelee a son max, c'est elle qui TIENT le LowerTorso en haut. Tout
	-- le reste passe PAR-DESSUS en Action4 pour gagner sur la grimpe, chacun sur ses propres membres (jambes / mains
	-- / bras) : a condition de ne PAS cler le LowerTorso, sinon ils ecrasent la hauteur tenue par la grimpe.
	climbTrack = climbTrack or loadTrack(animator, ANIM_FOLDER, CLIMB_ANIM, Enum.AnimationPriority.Action3)
	topLegsTrack = topLegsTrack or loadTrack(animator, ANIM_FOLDER, TOP_LEGS_ANIM)
	gripTrack = gripTrack or loadTrack(animator, ANIM_FOLDER, GRIP_ANIM)
	trimTrack = trimTrack or loadTrack(animator, TRIM_FOLDER, TRIM_ANIM)
	-- La coupe des bras ne DEFILE PAS toute seule : c'est une POSE parcourue a la main par la visee (comme au sol).
	-- Bouclee, elle rejouait en boucle avec un reset moche. Non bouclee + vitesse 0 : on place sa position nous-memes.
	if trimTrack then
		trimTrack.Looped = false
	end
	return idleTrack ~= nil and climbTrack ~= nil
end

-- Toutes les echelles du Workspace : tout DESCENDANT dont le nom commence par LADDER_PREFIX (recursif : detecte
-- l'echelle meme rangee dans un dossier d'organisation). GetDescendants est trop cher a refaire chaque frame sur un
-- gros Workspace (des milliers de carreaux de haie), donc on CACHE. Le cache ne se reconstruit que quand une instance
-- au nom d'echelle apparait / disparait (filtre par nom : les carreaux ne declenchent rien). getLadders (appele
-- chaque frame par la grimpe) rend alors la liste cachee sans rescanner.
local ladderCache: { Instance }? = nil

local function invalidateIfLadder(inst: Instance)
	if inst.Name:sub(1, #LADDER_PREFIX) == LADDER_PREFIX then
		ladderCache = nil
	end
end
workspace.DescendantAdded:Connect(invalidateIfLadder)
workspace.DescendantRemoving:Connect(invalidateIfLadder)

local function getLadders(): { Instance }
	if ladderCache then
		return ladderCache
	end
	local result: { Instance } = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name:sub(1, #LADDER_PREFIX) == LADDER_PREFIX then
			table.insert(result, d)
		end
	end
	ladderCache = result
	return result
end

-- La zone (parmi les deux de CHAQUE echelle) au-dessus de laquelle se tient le point, ET l'echelle a laquelle elle
-- appartient. Test HORIZONTAL seulement (X/Z) : le root du perso est a ~3 studs de haut, donc au-dessus des boites
-- posees au sol ; verifier Y ferait tout rater.
local function zoneContaining(position: Vector3): (BasePart?, Instance?)
	for _, ladder in ipairs(getLadders()) do
		for _, name in ipairs(ZONE_NAMES) do
			local zone = ladder:FindFirstChild(name)
			if zone and zone:IsA("BasePart") then
				local rel = zone.CFrame:PointToObjectSpace(position)
				local half = zone.Size * 0.5
				if math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z then
					return zone, ladder
				end
			end
		end
	end
	return nil, nil
end

local function dismount()
	if not mountCFrame then
		return -- deja detache : idempotent.
	end
	mountCFrame = nil
	phase = "off"
	-- On quitte : plus de point rose de visee, plus de haie de travail retenue.
	hideTopCursor()
	mountHedge = nil
	-- On quittait peut-etre depuis le sommet : couper la taille depuis l'echelle (idempotent si deja coupee).
	setLadderWork(false)
	-- On quitte l'echelle : le serveur reengage l'aimant du sol ET rejoue le maintien de l'outil (que le garde-fou
	-- d'anim a pu couper). Sans ca, l'outil reste dans la main sans pose de maintien apres la sortie.
	if onLadderRemote then
		onLadderRemote:FireServer(false)
	end
	local root = getRoot()
	if root then
		root.Anchored = false
	end
	-- On rend sa vitesse de marche au joueur.
	local humanoid = getHumanoid()
	if humanoid and savedWalkSpeed then
		humanoid.WalkSpeed = savedWalkSpeed
	end
	savedWalkSpeed = nil
	-- CAMERA : on coupe d'abord la visee vivante (sinon la boucle d'aim ecraserait le tween de sortie), puis on ramene
	-- la vue DERRIERE le joueur par un tween avant de rendre la main a la camera de jeu (Custom). Sans ce tween, Custom
	-- reprend d'un coup = le saut qu'on veut eviter. Cible = derriere le joueur, visant sa tete.
	camTracking = false
	camOutward = nil
	camSubject = nil
	camEnterFrom = nil
	-- Si on lache l'echelle en plein clic droit : on libere le curseur, sinon il resterait fige hors echelle.
	orbiting = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	if root then
		local headPos = root.Position + Vector3.new(0, 1.5, 0)
		local behind = root.Position - root.CFrame.LookVector * 12 + Vector3.new(0, 3, 0)
		tweenCameraToCustom(CFrame.lookAt(behind, headPos), CAM_TWEEN_OUT)
	else
		local camera = workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
	if idleTrack then
		idleTrack:Stop(0.15)
	end
	if climbTrack then
		climbTrack:Stop(0.15)
	end
	if gripTrack then
		gripTrack:Stop(0.15)
	end
	if trimTrack then
		trimTrack:Stop(0.15)
	end
	if topLegsTrack then
		topLegsTrack:Stop(0.15)
	end

	-- RESYNC ANIMATION. Le garde-fou a coupe (Stop) les pistes du script Animate par defaut pendant la montee. Ce
	-- script DEDOUBLONNE : il croit toujours jouer sa derniere anim, donc en repartant il ne la rejoue pas (surtout
	-- si une touche reste tenue : aucun nouvel appui pour declencher une transition). D'ou un perso qui glisse SANS
	-- animation. On relance Animate UNE fois, ici a la sortie, pour qu'il reparte d'un etat propre. Le journal
	-- deconseille de couper Animate PENDANT l'interaction (re-init qui glitche) ; ici c'est un simple resync final.
	local character = player.Character
	local animate = character and character:FindFirstChild("Animate")
	if animate and animate:IsA("BaseScript") then
		animate.Disabled = true
		-- Defer : on garantit un vrai stop puis restart (true->false synchrone pourrait s'annuler). Une frame au
		-- repos, puis Animate rejoue idle / marche selon le mouvement reel.
		-- GARDE : on ne rallume Animate QUE si on n'est pas deja re-remonte sur l'echelle entre-temps. Sinon, en
		-- quittant puis revenant vite, la relance tombait en pleine remontee et rejouait la marche dans le vide.
		task.defer(function()
			if animate.Parent and not mountCFrame then
				animate.Disabled = false
			end
		end)
	end
end

local function mount(zone: BasePart, ladder: Instance, root: BasePart)
	if not ensureTracks() then
		return
	end
	canMount = false
	-- La montee n'est pas encore armee : il faut relacher W une fois (le joueur tenait souvent l'avant pour entrer).
	climbArmed = false
	phase = "ready"
	-- On dit au serveur qu'on est SUR l'echelle : il desengage l'aimant du sol tant qu'on y est (sinon, dans une
	-- zone qui chevauche celle de la haie, les deux systemes se disputent le joueur).
	if onLadderRemote then
		onLadderRemote:FireServer(true)
	end
	-- Ancre : plus de physique qui se bat avec l'aimant. WalkSpeed A 0 : le Humanoid ne se croit plus en deplacement,
	-- donc son anim de marche par defaut ne joue plus (LE fix du "walk dans le vide"). Root ancre + WalkSpeed 0
	-- suffisent a bloquer tout mouvement.
	root.Anchored = true
	local humanoid = getHumanoid()
	if humanoid then
		savedWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 0
	end

	-- IdleDown : Looped=true (la pose reste appliquee au bout), lancee a 0. La phase "ready" avance sa TimePosition a
	-- la main jusqu'a la fin puis la fige (voir update) : elle joue une fois, ne reboucle pas.
	if idleTrack then
		idleTrack.Looped = true
		idleTrack.TimePosition = 0
		idleTrack:Play()
		idleTrack:AdjustSpeed(0)
	end

	-- Point de montage : le centre de la zone, RECULE vers l'exterieur de l'echelle (MOUNT_BACK), a la hauteur du
	-- joueur, tourne face a l'echelle. Le recul evite de finir DANS l'echelle. On se sert de l'echelle PASSEE (celle
	-- a laquelle la zone appartient), pas d'une recherche par nom.
	local center = zone.CFrame.Position
	local towards = if ladder:IsA("Model") then ladder:GetPivot().Position else center
	-- Direction vers l'EXTERIEUR : de l'echelle vers la zone, a plat.
	local away = Vector3.new(center.X - towards.X, 0, center.Z - towards.Z)
	away = if away.Magnitude > 1e-3 then away.Unit else Vector3.zero
	local spot = Vector3.new(center.X, root.Position.Y, center.Z) + away * MOUNT_BACK
	mountCFrame = CFrame.lookAt(spot, Vector3.new(towards.X, root.Position.Y, towards.Z))

	-- CAMERA : vue iso du cote de la haie, activee DES l'accroche. On trouve la haie la plus proche de l'echelle et on
	-- retient de quel COTE l'echelle se trouve (camOutward). La boucle d'aim posera la camera de ce cote, en hauteur,
	-- et suivra le joueur. L'entree ease depuis la vue joueur ACTUELLE vers la vue iso (pas de snap).
	local hedge = nearestHedge(spot)
	mountHedge = hedge -- retenue pour la visee du dessus (projection du curseur sur son plan haut)
	if hedge then
		camOutward = outwardSide(hedge, spot)
	else
		-- Pas de haie taguee a proximite : on se rabat sur le cote de l'echelle (direction du recul deja calculee).
		camOutward = if away.Magnitude > 1e-3 then away else Vector3.new(0, 0, 1)
	end
	ladderYaw = 0
	ladderPitch = 0
	ladderZoom = 1
	camSubject = getTrackPoint()
	local camNow = workspace.CurrentCamera
	camEnterFrom = if camNow then camNow.CFrame else nil
	camEnterElapsed = 0
	camTracking = true
end

local function update(dt: number)
	local root = getRoot()
	if not root then
		dismount()
		return
	end

	if not mountCFrame then
		local zone, ladder = zoneContaining(root.Position)
		if zone and ladder and canMount then
			-- TAILLE-HAIE OBLIGATOIRE pour monter : sans lui, la taille depuis l'echelle est impossible et l'etat
			-- devient incoherent (bugs). On NE MONTE PAS tant qu'il n'est pas equipe ; on previent une fois.
			if isTrimmerEquipped() then
				noTrimmerNotified = false
				mount(zone, ladder, root)
			elseif not noTrimmerNotified then
				noTrimmerNotified = true
				Toast.show("Alert", "Equipe ton taille-haie pour monter sur l'echelle")
			end
		elseif not zone then
			-- On a quitte la zone : on pourra se raccrocher au prochain passage, et on re-avertira au besoin.
			noTrimmerNotified = false
			canMount = true
		end
		return
	end

	-- AIMANT : on tire le joueur vers le point de montage. On CLE NET des qu'on est assez pres. Un lerp
	-- exponentiel n'atteint jamais sa cible : il laisse un residu de mouvement PERMANENT, que le Humanoid lit
	-- comme une vitesse et traduit en marche par-dessus l'anim (le "walk dans le vide"). Cf journal CLAUDE.md.
	if (root.Position - mountCFrame.Position).Magnitude > 0.05 then
		root.CFrame = root.CFrame:Lerp(mountCFrame, math.min(1, MAGNET_RATE * dt))
	else
		root.CFrame = mountCFrame
	end

	local idle = idleTrack
	local climb = climbTrack
	local grip = gripTrack
	local trim = trimTrack
	local topLegs = topLegsTrack
	if not (idle and climb) then
		return
	end

	-- GARDE-FOU ANIM. On ne coupe QUE les anims Roblox par DEFAUT (idle / marche / course), sous la priorite Action :
	-- ce sont elles qui jouent sur les parties non-clees et donnent le "walk dans le vide". On GARDE tout ce qui est
	-- Action et au-dessus : nos pistes d'echelle (Action3/4) ET le MAINTIEN de l'outil (Action). Ce maintien est de
	-- toute facon ECRASE par nos pistes d'echelle (plus prioritaires), donc invisible ici ; mais comme on ne le coupe
	-- plus, il REVIENT tout seul a la sortie de l'echelle (coupe, l'outil ne le rejouait jamais -> bras sans pose).
	--
	-- SEULEMENT en grimpe/sommet. En phase "ready", si IdleDown ne cle pas les jambes, on LAISSE l'idle par defaut
	-- les animer (le couper les figerait en pose gelee). Ancre + WalkSpeed 0, il n'y a de toute facon pas de walk
	-- parasite a couper au sol.
	local animator = getAnimator()
	if animator and phase ~= "ready" then
		for _, playing in ipairs(animator:GetPlayingAnimationTracks()) do
			if playing.Priority.Value < Enum.AnimationPriority.Action.Value then
				playing:Stop(0)
			end
		end
	end

	local up = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local down = UserInputService:IsKeyDown(Enum.KeyCode.S)

	-- ARMEMENT DE LA MONTEE. Tant que W n'a pas ete relache une fois depuis l'accroche, on IGNORE W : entrer dans
	-- la zone en marchant (touche avant = W) montre l'idle au lieu de lancer la grimpe. Un vrai appui apres avoir
	-- relache = grimper.
	if not up then
		climbArmed = true
	end
	local climbUp = up and climbArmed

	if phase == "ready" then
		-- IdleDown joue 0 -> fin UNE fois, puis on la FIGE sur sa derniere image (la pose "pret a monter"). Looped=true
		-- garde la pose APPLIQUEE au bout (non bouclee, la piste se relacherait a la fin et le corps sauterait), mais on
		-- ne la laisse PAS reboucler : on avance sa TimePosition A LA MAIN jusqu'a la fin puis on cle la (aucun wrap).
		-- W = enchainer sur la grimpe, S = ressortir (l'inverse).
		if not idle.IsPlaying then
			idle:Play()
			idle.TimePosition = 0
		end
		idle.Looped = true
		idle:AdjustSpeed(0)
		if idle.Length > 0 then
			idle.TimePosition = math.min(idle.TimePosition + dt, idle.Length - 0.001)
		end
		if climbUp then
			-- On monte : UpDown demarre pile ou IdleDown s'arrete. La main qui agrippe demarre en meme temps, a 0.
			phase = "climbing"
			idle:Stop(0)
			climb:Play()
			climb.TimePosition = 0
			climb:AdjustSpeed(0)
			if grip then
				grip:Play()
				grip.TimePosition = 0
				grip:AdjustSpeed(0)
			end
		elseif down then
			-- On ressort : IdleDown a l'envers (max -> 0), RAPIDE (EXIT_SPEED). On coupe la boucle pour s'arreter net.
			phase = "exiting"
			idle.Looped = false
			idle:AdjustSpeed(-EXIT_SPEED)
		end
		return
	end

	if phase == "climbing" then
		-- GRIMPE : UpDown (corps) pilotee par W/S ; la main qui agrippe suit EN SYNC juste apres.
		local dir = if climbUp and not down then 1 elseif down and not climbUp then -1 else 0
		climb:AdjustSpeed(dir * CLIMB_SPEED)
		if climb.Length > 0 then
			if dir >= 0 and climb.TimePosition >= climb.Length - 0.02 then
				-- SOMMET ATTEINT. dir >= 0 (et pas > 0) : des qu'on touche le max on bascule, MEME si Z vient d'etre
				-- relache. Sinon, lacher la touche pile au sommet laissait coince en "climbing", grimpe figee et main
				-- qui agrippe TOUJOURS jouee (le bug).
				--
				-- On NE STOPPE PAS la grimpe : on la GELE a son dernier frame. Le HumanoidRootPart reste ancre EN BAS ;
				-- ce qui tient le corps EN HAUT, c'est UpDownAnimation qui monte le LowerTorso a son dernier frame. La
				-- stopper faisait retomber le corps au pied de l'echelle. Elle reste donc jouee (vitesse 0), en base
				-- Action3, et IdleUpLadder (jambes) + RightLeft (bras) passent PAR-DESSUS en Action4.
				phase = "top"
				climb.TimePosition = climb.Length - 0.001
				climb:AdjustSpeed(0)
				if grip then
					grip:Stop(0.1)
				end
				idle:Stop(0.1)
				if TOP_LEGS_ENABLED and topLegs and not topLegs.IsPlaying then
					topLegs:Play(0.1)
					topLegs.TimePosition = 0
				end
				if trim and not trim.IsPlaying then
					-- Jouee GELEE (vitesse 0) : c'est la souris qui parcourt la pose (voir phase "top"). On la place
					-- deja sur la visee courante pour ne pas partir d'un coup depuis le bord.
					trim:Play(0.1)
					trim:AdjustSpeed(0)
					-- On part de la visee COURANTE (pas de glissement depuis 0.5 en arrivant en haut).
					cutRatioSmooth = topAim()
					trim.TimePosition = math.min(cutRatioSmooth * trim.Length, trim.Length - 0.001)
				end
				-- On est en haut : on signale au serveur qu'on peut tailler le dessus (il choisit la haie la plus
				-- proche). La coupe reste conditionnee au moteur en marche + gachette, comme au sol.
				setLadderWork(true)
				return
			elseif dir < 0 and climb.TimePosition <= 0.02 then
				-- BAS ATTEINT en descendant : sortie. UpDown ET la main coupees NET, IdleDown repart de son max a
				-- l'envers, RAPIDE (EXIT_SPEED), sans boucler.
				climb:Stop(0)
				if grip then
					grip:Stop(0)
				end
				phase = "exiting"
				idle.Looped = false
				idle:Play()
				idle.TimePosition = if idle.Length > 0 then idle.Length - 0.001 else 0
				idle:AdjustSpeed(-EXIT_SPEED)
				return
			end
		end
		-- Main qui agrippe : collee a la MEME position temporelle que la grimpe, frame par frame.
		if grip then
			if not grip.IsPlaying then
				grip:Play()
			end
			grip:AdjustSpeed(0)
			grip.TimePosition = climb.TimePosition
		end
		return
	end

	if phase == "top" then
		-- AU SOMMET. La grimpe reste GELEE a son max (Action3) : c'est elle qui TIENT le corps en haut (le HRP est
		-- ancre en bas). Par-dessus (Action4) : IdleUpLadder pose les jambes sur les marches, RightLeft taille. Main
		-- qui agrippe et idle bas sont stoppees.
		climb.TimePosition = climb.Length - 0.001
		climb:AdjustSpeed(0)
		-- COUPE PILOTEE PAR LA VISEE. La pose des bras (RightLeft) est GELEE (vitesse 0) et on place sa position avec
		-- la souris : gauche de l'ecran -> un bord, droite -> l'autre. Le joueur balaie donc la lame lui-meme, comme
		-- au sol ; plus de boucle automatique. La lame suit la pose, donc la coupe suit la souris.
		if trim and trim.Length > 0 then
			if not trim.IsPlaying then
				trim:Play()
			end
			trim:AdjustSpeed(0)
			-- LISSAGE : la lame GLISSE vers la visee (topAim) au lieu de la coller sec, quand on va de gauche a droite.
			cutRatioSmooth += (topAim() - cutRatioSmooth) * math.min(1, CUT_SWEEP_SMOOTH * dt)
			-- Borne juste sous la fin : poser TimePosition PILE a la fin d'une piste non bouclee peut l'auto-stopper.
			trim.TimePosition = math.min(cutRatioSmooth * trim.Length, trim.Length - 0.001)
		end
		-- TAILLE DU DESSUS : on envoie le segment REEL de la lame chaque frame. Moteur en marche + gachette pressee,
		-- le serveur coupe le dessus la ou passe la lame. Sans outil en main, rien n'est envoye.
		sendBladeAim()
		if down and not climbUp then
			-- On redescend : on quitte le sommet. On coupe le maintien haut (jambes) + la coupe (bras) et on relance
			-- la main qui agrippe. La grimpe est DEJA jouee (gelee au max), la phase "climbing" la fait redescendre.
			phase = "climbing"
			setLadderWork(false)
			hideTopCursor() -- plus de visee du dessus tant qu'on n'est pas au sommet
			if topLegs then
				topLegs:Stop(0.1)
			end
			if trim then
				trim:Stop(0.1)
			end
			if grip then
				grip:Play(0.1)
				grip.TimePosition = climb.TimePosition
				grip:AdjustSpeed(0)
			end
		end
		return
	end

	-- phase == "exiting" : IdleDown a l'envers (max -> 0). Arrive a 0 (ou piste finie), on lache l'echelle.
	if not idle.IsPlaying or (idle.Length > 0 and idle.TimePosition <= 0.02) then
		dismount()
	end
end

function LadderController.init()
	-- Remotes de taille depuis l'echelle. SetAim est partage avec le systeme au sol (le serveur borne la portee) ;
	-- SetLadderWork active la coupe alors que l'aimant du sol est desengage.
	local aim = RemoteSetup.getRemote("SetAim", "Hedge")
	if aim and aim:IsA("RemoteEvent") then
		aimRemote = aim
	else
		warn("[Ladder] Remote Hedge/SetAim introuvable : la coupe depuis l'echelle ne suivra pas la lame")
	end
	local work = RemoteSetup.getRemote("SetLadderWork", "Hedge")
	if work and work:IsA("RemoteEvent") then
		ladderWorkRemote = work
	else
		warn("[Ladder] Remote Hedge/SetLadderWork introuvable : pas de taille depuis l'echelle")
	end
	local onLadder = RemoteSetup.getRemote("SetOnLadder", "Hedge")
	if onLadder and onLadder:IsA("RemoteEvent") then
		onLadderRemote = onLadder
	else
		warn("[Ladder] Remote Hedge/SetOnLadder introuvable : aimant sol et echelle vont se disputer")
	end

	player.CharacterAdded:Connect(function()
		-- Nouveau perso : anciens Animator/pistes morts, etat propre.
		idleTrack = nil
		climbTrack = nil
		gripTrack = nil
		trimTrack = nil
		topLegsTrack = nil
		mountCFrame = nil
		phase = "off"
		canMount = true
		savedWalkSpeed = nil
		-- Si on meurt en haut d'une echelle, les etats "taille echelle" et "sur l'echelle" resteraient poses cote
		-- serveur et bloqueraient la taille au sol du nouveau perso. On les coupe (idempotent si deja coupes).
		setLadderWork(false)
		if onLadderRemote then
			onLadderRemote:FireServer(false)
		end
		hideTopCursor()
		mountHedge = nil
		-- Si on meurt accroche, la camera etait scriptee : on la rend a Custom, et on coupe le suivi / un tween en
		-- cours. (Plus de controles a rallumer : on ne les coupe plus, voir mount.)
		camTracking = false
		camOutward = nil
		camSubject = nil
		camEnterFrom = nil
		orbiting = false
		ladderYaw = 0
		ladderPitch = 0
		ladderZoom = 1
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		if camTween then
			camTween:Cancel()
			camTween = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
	end)
	RunService.Heartbeat:Connect(update)

	-- ORBITE. On separe deux choses pour que l'orbit ne traine jamais :
	--   1. Le POINT SUIVI (camSubject) se lisse vers le corps qui monte -> pas de tremblement d'anim, mais ce lissage
	--      ne touche QUE le point vise, pas la rotation.
	--   2. La CAMERA se pose DIRECTEMENT (aucun lerp) a l'azimut/elevation courants autour de ce point -> quand le
	--      joueur pivote, ca repond a la frame, meme tres vite. C'etait la l'erreur d'avant : lerper toute la CFrame
	--      lissait aussi la rotation, d'ou le retard degueu.
	-- A la priorite Camera, comme HedgeController.
	RunService:BindToRenderStep("LadderCamAim", Enum.RenderPriority.Camera.Value, function(dt: number)
		local outward = camOutward
		if not (camTracking and outward) then
			return
		end
		local camera = workspace.CurrentCamera
		local target = getTrackPoint()
		if not (camera and target) then
			return
		end
		-- 1. Point suivi lisse (le seul lissage restant).
		camSubject = if camSubject then camSubject:Lerp(target, math.min(1, CAM_FOLLOW * dt)) else target
		local focus = (camSubject :: Vector3) + Vector3.new(0, CAM_ISO_LOOK, 0)

		-- 2. Direction camera -> AZIMUT (yaw defaut + pivot joueur) puis ELEVATION (pitch defaut + pivot joueur,
		-- borne pour ne pas retourner la camera). Sphere autour du focus, rayon constant : la camera glisse sur une
		-- calotte, jamais de flip.
		local azimuth = ladderYaw + math.rad(CAM_ISO_YAW)
		local pitch =
			math.clamp(math.rad(CAM_ISO_PITCH) + ladderPitch, math.rad(CAM_PITCH_MIN), math.rad(CAM_PITCH_MAX))
		local horiz = CFrame.Angles(0, azimuth, 0) * outward
		horiz = Vector3.new(horiz.X, 0, horiz.Z)
		horiz = if horiz.Magnitude > 1e-3 then horiz.Unit else Vector3.new(0, 0, 1)
		local dir = horiz * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
		local camPos = focus + dir * (CAM_ISO_DIST * ladderZoom)
		local desired = CFrame.lookAt(camPos, focus)

		camera.CameraType = Enum.CameraType.Scriptable
		-- ENTREE EN DOUCEUR. Pendant CAM_ENTER secondes apres l'accroche, on EASE depuis la vue joueur (camEnterFrom)
		-- vers la vue iso, au lieu de snapper. Ease-out (1-(1-t)^2) : demarre franc, finit doux. Passe ce temps, on
		-- pose la camera en DIRECT : l'orbit redevient instantane. Le ease vise la CFrame COURANTE, donc pivoter
		-- pendant l'entree marche deja.
		local from = camEnterFrom
		if from and camEnterElapsed < CAM_ENTER then
			camEnterElapsed += dt
			local t = math.clamp(camEnterElapsed / CAM_ENTER, 0, 1)
			local a = 1 - (1 - t) * (1 - t)
			camera.CFrame = from:Lerp(desired, a)
			if t >= 1 then
				camEnterFrom = nil
			end
		else
			camera.CFrame = desired
		end
	end)

	-- ORBIT au clic droit maintenu, seulement sur l'echelle. Meme geste qu'en taillant. Le curseur se fige pendant
	-- le glissement (sinon il sortirait de l'ecran) et revient libre au relachement.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not mountCFrame then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbiting = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		-- Pas de filtre gameProcessed au relachement : l'orbit ne doit jamais rester coince.
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbiting = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not mountCFrame then
			return
		end
		-- ZOOM MOLETTE. Marche des qu'on est sur l'echelle, sans tenir le clic droit. Position.Z vaut +1 vers l'AVANT
		-- (zoom in) : on veut alors REDUIRE le multiplicateur (se rapprocher), d'ou le signe inverse ici, une fois.
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local factor = 1 - input.Position.Z * CAM_ZOOM_STEP
			ladderZoom = math.clamp(ladderZoom * factor, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
			return
		end
		-- Le reste (pivot) demande le clic droit maintenu.
		if not orbiting then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			-- Horizontal : meme signe que HedgeController (pivot dans le meme sens qu'en taillant).
			ladderYaw -= math.rad(input.Delta.X * CAM_YAW_SENS)
			-- Vertical : souris vers le BAS (Delta.Y positif) = vue qui descend. On clampe l'ACCUMULATEUR (pas juste
			-- la valeur utilisee) : sinon, drague au-dela de la borne et le surplus doit etre rattrape avant que ca
			-- reponde a nouveau (zone morte). ladderPitch est un offset autour de l'elevation par defaut.
			local minOffset = math.rad(CAM_PITCH_MIN - CAM_ISO_PITCH)
			local maxOffset = math.rad(CAM_PITCH_MAX - CAM_ISO_PITCH)
			ladderPitch = math.clamp(ladderPitch + math.rad(input.Delta.Y * CAM_PITCH_SENS), minOffset, maxOffset)
		end
	end)

	print("[Ladder] Pret. Entre dans une zone : idle au sol, W monte, S descend / lache.")
end

return LadderController
