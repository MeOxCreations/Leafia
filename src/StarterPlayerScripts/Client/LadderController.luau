--!strict
-- PROTOTYPE escabeau, SOCLE. Le joueur entre dans une zone de detection du rig (box_detecte_A / box_detecte_B),
-- on l'AIMANTE au pied de l'echelle face a elle, root ANCRE + WalkSpeed 0 (pas de marche dans le vide), et deux
-- animations s'echangent selon l'etat :
--   - Au sol, pret a monter (pieds au sol, main sur l'echelle) : IdleDownAnimation, EN BOUCLE.
--   - En train de monter / descendre : UpDownAnimation, pilotee par le DEPLACEMENT (avant = monte, arriere = descend).
-- On monte via un prompt E (bouton a taper sur mobile) en entrant dans la zone. Avant fait grimper (joystick ou W),
-- arriere fait descendre ; tout en bas, arriere detache de l'echelle (IdleDown a l'envers).
--
-- Camera : vue ISO orbitale, activee des l'accroche. Elle ease depuis la vue joueur vers la vue iso, suit le corps
-- qui monte, et le joueur peut tourner librement (clic droit) + zoomer (molette).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ToolConfigs = require(ReplicatedStorage.Modules.Configs.ToolConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)

local LadderController = {}

local player = Players.LocalPlayer

-- Pose par LadderMoveController sur le perso pendant qu'on PORTE une echelle. Tant qu'il est vrai, on ne grimpe
-- pas : l'echelle portee est soudee a nous, ses zones de grimpe nous suivent, on grimperait sa propre echelle.
-- Meme nom cote LadderMoveController (les deux doivent rester d'accord).
local CARRYING_ATTR = "LeafiaCarryingLadder"

-- Rigs poses a la main dans le Workspace, leurs deux zones, et le dossier des anims (renomme Escabaut -> Ladder).
-- PREFIXE et non nom exact : on gere PLUSIEURS echelles. Tout enfant du Workspace dont le nom commence par ce
-- prefixe est une echelle (ex : Escabaut_1a_rig, Escabaut_2a_rig, une copie...).
local LADDER_PREFIX = "Escabaut"
local ZONE_NAMES = { "box_detecte_A", "box_detecte_B" }
local ANIM_FOLDER = { "Animations", "Player", "Tools", "Ladder" }
local IDLE_ANIM = "IdleDownAnimation" -- pose prete, au sol
local CLIMB_ANIM = "UpDownAnimation" -- grimpe (corps / jambes), pilotee W/S
local GRIP_ANIM = "UpDownHandGripAnimation" -- main qui agrippe l'echelle, jouee EN SYNC avec la grimpe
-- SON DE PAS a la montee. On ne s'appuie PLUS sur des marqueurs d'anim (fragiles : nom exact + ne tirent pas
-- fiablement sur une anim pilotee a la main) : on declenche un pas tous les X de PROGRESSION de la grimpe, et on
-- tire un des deux sons AU HASARD. Sons ranges dans SoundService, clones au declenchement (volume regle en Studio).
local LADDER_SOUND_PATH = { "Sounds", "Engins", "Ladder" }
local CLIMB_STEP_SOUNDS = { "LadderClimbStepOne", "LadderClimbStepTwo" } -- un tire au hasard par pas
-- Nombre de pas sur toute la grimpe (~ nombre de marches). Plus haut = plus de pas, plus rapproches. A REGLER a l'oreille.
local CLIMB_STEP_COUNT = 6
-- Maintien EN HAUT : jambes bien posees sur les marches. Joue au sommet PAR-DESSUS la grimpe gelee, en Action4 pour
-- gagner sur les jambes de la grimpe. Meme dossier que la grimpe (Ladder).
local TOP_LEGS_ANIM = "IdleUpLadder"
-- CONDITION pour que ca marche : IdleUpLadder ne doit cler QUE les jambes (LeftUpperLeg/LowerLeg/Foot + cote droit),
-- PAS le LowerTorso ni les hanches. Le LowerTorso est ce que la grimpe gelee monte pour tenir le corps en haut : si
-- IdleUpLadder le cle aussi (a hauteur sol), en Action4 elle ecrase la montee et le corps RETOMBE au pied. A false,
-- on la coupe (le corps reste tenu par la grimpe seule, jambes en pose de grimpe).
local TOP_LEGS_ENABLED = true
-- Coupe gauche-droite du DESSUS (bras), jouee AU SOMMET par-dessus IdleUpLadder. TRIM_FOLDER = SECOURS (taille-haie) :
-- ensureTrimTrack prend d'abord le dossier de l'OUTIL equipe (ex la cisaille a sa propre RightLeftAnimation) et ne
-- retombe ici que si l'outil n'a pas cette pose.
local TRIM_FOLDER = { "Animations", "Player", "Tools", "HedgeTrimmer" }
local TRIM_ANIM = "RightLeftAnimation"
-- VISEE DU DESSUS, UNE SEULE REGLE : la souris PAR RAPPORT AU JOUEUR a l'ecran pilote la lame. Souris pile DEVANT le
-- joueur -> milieu de l'anim ; a gauche -> debut, a droite -> fin. Repere = le corps (pas le centre de l'ecran), donc
-- peu importe ou le joueur est cadre. TOP_SENSITIVITY : plus haut = moins de mouvement de souris pour parcourir 0 a 1.
local TOP_SENSITIVITY = 10

local CLIMB_SPEED = 1.1 -- vitesse de lecture de l'anim de grimpe (monter = grimpe plus rapide)
-- La camera SUIT la hauteur de grimpe : le HRP reste ancre en bas (c'est l'anim qui monte le corps), donc sans ca la
-- vue resterait basse et le perso grimperait hors du cadre. On monte le POINT VISE de la camera (Humanoid.CameraOffset,
-- la cam joueur garde son angle + zoom) selon la progression : 0 au sol, CLIMB_CAM_RISE en haut. A REGLER pour cadrer.
local CLIMB_CAM_RISE = 6
local EXIT_SPEED = 3 -- vitesse de lecture d'IdleDown A L'ENVERS pour sortir (plus haut = sortie plus rapide)
local MOUNT_BACK = 1.25 -- recul du point de montage depuis le centre de la zone, vers l'exterieur de l'echelle (studs)
-- Prompt "[E] MONTER" affiche quand on entre dans une zone de grimpe (box_detecte_A / _B). On ne monte PLUS
-- automatiquement en entrant : il faut appuyer E (ou taper le bouton sur mobile). F est la prise (LadderMoveController).
local MOUNT_PROMPT_KEY = "E"
local MOUNT_PROMPT_LABEL = "MONTER"
local MOUNT_PROMPT_TITLE = "LADDER" -- titre au-dessus du prompt, comme "MAILBOX" sur la boite aux lettres
local MOUNT_PROMPT_OFFSET = Vector3.new(0, 5, 0) -- hauteur d'AFFICHAGE du prompt au-dessus de la zone (pas la distance de detection)

local idleTrack: AnimationTrack? = nil
local climbTrack: AnimationTrack? = nil
local gripTrack: AnimationTrack? = nil
local trimTrack: AnimationTrack? = nil
-- Dossier d'anim pour lequel trimTrack est charge (nil = secours taille-haie). Sert a RECHARGER la pose si l'outil
-- a change depuis la derniere montee (chaque outil a sa propre RightLeftAnimation).
local trimFolderLoaded: string? = nil
-- Maintien EN HAUT (jambes sur les marches). Joue au sommet a la place de la grimpe, sous les bras qui taillent.
local topLegsTrack: AnimationTrack? = nil
-- Sert AUSSI d'etat "accroche" : non-nil = on est sur l'echelle.
local mountCFrame: CFrame? = nil
-- Empeche de se raccrocher tant qu'on n'a pas quitte la zone une fois (apres une sortie).
local canMount = true
-- WalkSpeed d'origine, retenue pour la rendre a la sortie.
local savedWalkSpeed: number? = nil
-- Progression de la grimpe au dernier pas joue : sert a declencher un pas des qu'on a avance d'un intervalle.
local lastStepPos = 0
-- Phase sur l'echelle :
--   "ready"    IdleDown EN BOUCLE (pret a monter). W = grimper, S = ressortir.
--   "climbing" UpDown pilotee par W/S ; au bas de la descente, on repasse par "exiting".
--   "top"      grimpe gelee au max, taille du dessus (IdleUpLadder + RightLeft).
--   "exiting"  IdleDown a l'envers (max -> 0) ; arrive a 0, on lache l'echelle.
local phase = "off"

-- Prompt de montee : est-il affiche, et sur quelle zone / echelle il pointe (pour monter au bon endroit a l'appui).
local mountPromptShown = false
local pendingZone: BasePart? = nil
local pendingLadder: Instance? = nil

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
-- MONTEE : on demande au serveur d'ANCRER + poser le HRP face a l'echelle. Ancrer + poser en local ne se
-- repliquait pas -> les autres voyaient le grimpeur de travers. Le serveur pose le CFrame, ca se voit chez tous.
local climbRemote: RemoteEvent? = nil

-- La lame : la meme part que le systeme de taille au sol (HitBoxRoot). Reflete HedgeController ; si ca se
-- stabilise, la sortir dans un util partage (voir CLAUDE.md sur la duplication). Sert a la visee du dessus.
local function findBlade(character: Model): BasePart?
	local found = character:FindFirstChild("HitBoxRoot", true)
	return if found and found:IsA("BasePart") then found else nil
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

-- Inverse le sens du balayage. La souris et la lame peuvent partir a l'oppose selon le sens de RightLeftAnimation et
-- l'orientation de la haie. A basculer si le sens est faux (curseur a gauche -> lame a droite = mets false, ou true).
local CUT_TOP_INVERT = false
-- Lissage du balayage : la lame GLISSE vers la visee au lieu de la coller sec. Haut = plus reactif (colle a la
-- souris), bas = plus doux / trainant. La position lissee courante est cutRatioSmooth.
local CUT_SWEEP_SMOOTH = 10
local cutRatioSmooth = 0.5

local lastCutRatio = 0.5

-- VISEE DU DESSUS. La lame suit la souris PAR RAPPORT AU JOUEUR a l'ecran (pas le centre de l'ecran) : souris pile
-- DEVANT le joueur -> MILIEU de l'anim ; a gauche -> debut, a droite -> fin. Le repere est le CORPS, donc peu importe ou
-- le joueur est cadre. TOP_SENSITIVITY : plus haut = moins de mouvement de souris pour parcourir 0 a 1. CUT_TOP_INVERT
-- si le sens gauche/droite est faux.
local function topAim(): number
	local camera = workspace.CurrentCamera
	local root = getRoot()
	if not (camera and root) then
		return lastCutRatio
	end
	local viewW = camera.ViewportSize.X
	if viewW <= 0 then
		return lastCutRatio
	end
	-- Milieu du joueur A L'ECRAN : on prend la TETE si dispo (le corps est monte sur l'echelle), sinon la RootPart.
	-- WorldToViewportPoint et GetMouseLocation sont dans le meme repere (viewport), donc leurs X se comparent direct.
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local refPos = if head and head:IsA("BasePart") then head.Position else root.Position
	local playerX = camera:WorldToViewportPoint(refPos).X
	local mouseX = UserInputService:GetMouseLocation().X
	-- Offset de la souris PAR RAPPORT au joueur, normalise par la largeur d'ecran. 0 = pile devant -> ratio 0.5.
	local ratio = 0.5 + ((mouseX - playerX) / viewW) * TOP_SENSITIVITY
	if CUT_TOP_INVERT then
		ratio = 1 - ratio
	end
	lastCutRatio = math.clamp(ratio, 0, 1)
	return lastCutRatio
end

-- Position temporelle de la lame pour un ratio [0,1] : LINEAIRE sur toute la duree de l'anim (0 -> debut, 1 -> fin).
-- Simple et robuste : le curseur pilote directement le temps de lecture, sans evenements ni appel async.
local function topTrimTime(track: AnimationTrack, ratio: number): number
	local length = track.Length
	return math.clamp(ratio * length, 0, length - 0.001)
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

-- Un pas de grimpe : tire un des deux sons AU HASARD, joue sur le perso (spatial). Appele par la boucle de
-- grimpe des qu'on a avance d'un intervalle (voir update).
local function playClimbStep()
	local name = CLIMB_STEP_SOUNDS[math.random(#CLIMB_STEP_SOUNDS)]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local path = table.clone(LADDER_SOUND_PATH)
	table.insert(path, name)
	SoundUtils.play(path, if root and root:IsA("BasePart") then root else nil)
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
	-- La pose de coupe du dessus (trimTrack) est chargee a part, dans ensureTrimTrack : elle depend de l'OUTIL equipe.
	return idleTrack ~= nil and climbTrack ~= nil
end

-- Dossier d'anims de l'outil TENU (ex "Shear", "HedgeTrimmer"), lu via l'attribut LeafiaTool pose sur le modele de
-- l'outil (enfant du perso), ou nil si aucun outil. Meme source que HedgeController.heldToolConfig cote sol.
local function equippedToolFolder(): string?
	local character = player.Character
	if not character then
		return nil
	end
	for _, child in ipairs(character:GetChildren()) do
		local toolName = child:GetAttribute("LeafiaTool")
		if typeof(toolName) == "string" then
			local config = ToolConfigs[toolName]
			if config then
				return config.animationFolder
			end
		end
	end
	return nil
end

-- (Re)charge la pose de coupe du dessus (RightLeft) pour l'OUTIL equipe : son dossier si l'anim y existe, sinon le
-- taille-haie (TRIM_FOLDER). Appele a la PRISE de l'echelle, ou l'outil est encore equipe (il est range juste apres,
-- a SetOnLadder). Ne recharge que si l'outil a change (trimFolderLoaded) : pas de rechargement inutile a chaque montee.
local function ensureTrimTrack()
	local folder = equippedToolFolder()
	if trimTrack and folder == trimFolderLoaded then
		return
	end
	if trimTrack then
		trimTrack:Stop(0)
		trimTrack = nil
	end
	trimFolderLoaded = folder
	local animator = getAnimator()
	if not animator then
		return
	end
	local folderPath = TRIM_FOLDER
	if folder then
		local toolFolder = { "Animations", "Player", "Tools", folder }
		-- Existence de la pose dans le dossier de l'outil : sinon on retombe sur le taille-haie (evite un warn).
		local node: Instance? = ReplicatedStorage
		for _, name in ipairs(toolFolder) do
			node = node and node:FindFirstChild(name)
		end
		if node and node:FindFirstChild(TRIM_ANIM) then
			folderPath = toolFolder
		end
	end
	trimTrack = loadTrack(animator, folderPath, TRIM_ANIM)
	-- La coupe des bras ne DEFILE PAS toute seule : c'est une POSE parcourue a la main par la visee (comme au sol).
	-- Bouclee, elle rejouait en boucle avec un reset moche. Non bouclee + vitesse 0 : on place sa position nous-memes.
	if trimTrack then
		trimTrack.Looped = false
	end
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
	-- On quittait peut-etre depuis le sommet : couper la taille depuis l'echelle (idempotent si deja coupee).
	setLadderWork(false)
	-- On quitte l'echelle : le serveur reengage l'aimant du sol ET rejoue le maintien de l'outil (que le garde-fou
	-- d'anim a pu couper). Sans ca, l'outil reste dans la main sans pose de maintien apres la sortie.
	if onLadderRemote then
		onLadderRemote:FireServer(false)
	end
	-- Plus sur l'echelle : l'auto-equip du taille-haie peut de nouveau se declencher.
	local char = player.Character
	if char then
		char:SetAttribute("LeafiaOnLadder", nil)
	end
	-- On dit au serveur de DESANCRER le HRP (fin de montee cote serveur). Sans argument -> release.
	if climbRemote then
		climbRemote:FireServer()
	end
	local root = getRoot()
	if root then
		root.Anchored = false
	end
	-- On rend sa vitesse de marche au joueur.
	local humanoid = getHumanoid()
	if humanoid then
		if savedWalkSpeed then
			humanoid.WalkSpeed = savedWalkSpeed
		end
		-- Fin du suivi vertical de la grimpe : on remet le point vise de la camera au niveau du joueur. On ne quitte
		-- jamais la camera normale (voir mount) ; c'est le SEUL reglage camera a la sortie.
		humanoid.CameraOffset = Vector3.zero
	end
	savedWalkSpeed = nil
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
	-- Pose de coupe du dessus pour l'OUTIL equipe : il l'est encore ici (il sera range plus bas, a SetOnLadder). Chaque
	-- outil a sa propre RightLeftAnimation (ex la cisaille), sinon secours taille-haie.
	ensureTrimTrack()
	canMount = false
	phase = "ready"
	-- On dit au serveur qu'on est SUR l'echelle : il desengage l'aimant du sol tant qu'on y est (sinon, dans une
	-- zone qui chevauche celle de la haie, les deux systemes se disputent le joueur).
	if onLadderRemote then
		onLadderRemote:FireServer(true)
	end
	-- Marque le perso "sur l'echelle", lu par LadderMoveController pour BLOQUER l'auto-equip du taille-haie pendant
	-- la grimpe. Le serveur range l'outil sur l'echelle ; sans ce blocage, l'auto-equip (haie a cote) le re-sortirait.
	local char = player.Character
	if char then
		char:SetAttribute("LeafiaOnLadder", true)
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

	-- On demande au SERVEUR d'ancrer + poser le HRP a ce point (face a l'echelle) : c'est ce CFrame serveur qui se
	-- replique aux autres (l'aimant local, lui, ne se voyait que chez le grimpeur). Le root est deja ancre en local.
	if climbRemote then
		climbRemote:FireServer(ladder, mountCFrame)
	end

	-- PAS de camera iso ici : sur l'echelle on garde la camera NORMALE du joueur, comme il l'a reglee (choix de design).
end

-- Input de deplacement pour MONTER / DESCENDRE l'echelle (avant = monte, arriere = descend). Marche au JOYSTICK sur
-- mobile ET a W/S sur PC. Meme approche que HedgeController : ControlModule charge en fond (retry) + secours clavier si
-- le module custom rend du vide. Avant on lisait W/S EN DUR -> le joystick mobile ne montait pas.
local climbControlModule: any = nil
task.spawn(function()
	while not climbControlModule do
		local ok, result = pcall(function()
			local scripts = player:WaitForChild("PlayerScripts", 10)
			local pm = scripts and require(scripts:WaitForChild("PlayerModule", 10)) :: any
			return pm and pm:GetControls()
		end)
		if ok and result then
			climbControlModule = result
		else
			task.wait(0.3)
		end
	end
end)

-- Move vector du ControlModule (mobile thumbstick ET PC WASD), en repere CAMERA-monde. Vide si le module n'est pas resolu.
local function climbMoveVector(): Vector3
	if climbControlModule then
		local ok, v = pcall(function()
			return climbControlModule:GetMoveVector()
		end)
		if ok and typeof(v) == "Vector3" then
			return v
		end
	end
	return Vector3.zero
end

-- Monte sur l'echelle. Appele par la touche E (PC, via init) ET par le tap du prompt sur mobile (onActivate). Garde et
-- idempotent : ne fait rien si deja accroche, si on porte une echelle, ou si aucune zone de grimpe n'est en attente.
local function tryMount()
	local zone = pendingZone
	local ladder = pendingLadder
	if mountCFrame or not (zone and ladder and canMount) then
		return
	end
	local character = player.Character
	if character and character:GetAttribute(CARRYING_ATTR) == true then
		return -- on porte une echelle : ses zones nous suivent, pas de grimpe
	end
	local root = getRoot()
	if not root then
		return
	end
	InteractionPrompt.hide()
	mountPromptShown = false
	mount(zone, ladder, root)
end

local function update(dt: number)
	local root = getRoot()
	if not root then
		dismount()
		return
	end

	-- On PORTE une echelle (LadderMoveController) : elle est soudee a nous, donc ses zones de grimpe nous suivent
	-- et on serait en permanence "dans la zone" -> on grimperait sa propre echelle. Tant qu'on porte, pas de grimpe.
	-- dismount est idempotent : rien si on n'etait pas accroche ; sinon il sort proprement (cas ou on prend l'echelle
	-- alors qu'on etait deja accroche).
	local character = player.Character
	if character and character:GetAttribute(CARRYING_ATTR) == true then
		dismount()
		return
	end

	if not mountCFrame then
		local zone, ladder = zoneContaining(root.Position)
		if zone and ladder and canMount then
			-- Dans une zone de grimpe, pas encore raccroche : on PROPOSE la montee (prompt E, bouton a taper sur
			-- mobile). On ne monte QUE sur appui (tryMount), plus automatiquement. AUCUNE condition d'outil : il est
			-- range pendant la grimpe (syncLadderTool) et rendu en haut pour tailler.
			pendingZone, pendingLadder = zone, ladder
			if not mountPromptShown then
				mountPromptShown = true
				InteractionPrompt.show(zone, MOUNT_PROMPT_KEY, MOUNT_PROMPT_LABEL, MOUNT_PROMPT_OFFSET, tryMount, MOUNT_PROMPT_TITLE)
			end
		else
			-- Hors zone de grimpe (ou raccrochage encore bloque) : on cache le prompt et on oublie la cible.
			pendingZone, pendingLadder = nil, nil
			if mountPromptShown then
				mountPromptShown = false
				InteractionPrompt.hide()
			end
			if not zone then
				-- On a quitte la zone : on pourra se raccrocher au prochain passage.
				canMount = true
			end
		end
		return
	end

	-- AIMANT : c'est le SERVEUR qui pose le HRP au point de montage (tween du CFrame de la part ancree), pour que
	-- la pose face a l'echelle se voie chez TOUS. Le client ne touche plus a root.CFrame : le poser en local ne se
	-- repliquait pas -> les autres voyaient le grimpeur de travers (cf climbMount serveur).
	local idle = idleTrack
	local climb = climbTrack
	local grip = gripTrack
	local trim = trimTrack
	local topLegs = topLegsTrack
	if not (idle and climb) then
		return
	end

	-- SUIVI VERTICAL DE LA GRIMPE. Le corps monte par l'anim alors que le HRP reste ancre en bas : sans ca il grimperait
	-- hors du cadre. On decale le POINT VISE de la camera (CameraOffset) selon la progression de la grimpe -> la vue monte
	-- avec le joueur. La cam garde son angle et son zoom (on ne touche QUE le point vise). 0 au sol, max en haut, et la
	-- descente est suivie aussi. Hors grimpe (ready / exiting) : 0 ; a la sortie, dismount le remet a 0.
	local humanoid = getHumanoid()
	if humanoid then
		local rise = 0
		if (phase == "climbing" or phase == "top") and climb.Length > 0 then
			rise = math.clamp(climb.TimePosition / climb.Length, 0, 1) * CLIMB_CAM_RISE
		end
		humanoid.CameraOffset = Vector3.new(0, rise, 0)
	end

	-- GARDE-FOU ANIM. On ne coupe QUE les anims Roblox par DEFAUT (idle / marche / course), sous la priorite Action :
	-- ce sont elles qui jouent sur les parties non-clees et donnent le "walk dans le vide". On GARDE tout ce qui est
	-- Action et au-dessus : nos pistes d'echelle (Action3/4) ET le MAINTIEN de l'outil (Action). Ce maintien est de
	-- toute facon ECRASE par nos pistes d'echelle (plus prioritaires), donc invisible ici ; mais comme on ne le coupe
	-- plus, il REVIENT tout seul a la sortie de l'echelle (coupe, l'outil ne le rejouait jamais -> bras sans pose).
	--
	-- DANS TOUTES LES PHASES (y compris "ready" au pied de l'echelle) : des qu'on est sur l'echelle, aucune anim
	-- par defaut ne doit jouer, sinon les membres non-cles (ex : le bras gauche) "marchent dans le vide". Les
	-- membres qu'aucune de nos pistes ne cle restent alors a leur pose de repos : a cler dans l'anim si on les veut poses.
	local animator = getAnimator()
	if animator then
		for _, playing in ipairs(animator:GetPlayingAnimationTracks()) do
			if playing.Priority.Value < Enum.AnimationPriority.Action.Value then
				playing:Stop(0)
			end
		end
	end

	-- Monte/descend au DEPLACEMENT : POUSSER VERS L'AVANT (haut du stick / W) = monter, arriere = descendre. Le move vector
	-- du ControlModule (mobile thumbstick ET PC WASD) est en repere CAMERA-monde : on le PROJETTE sur le regard de la camera
	-- pour recuperer la poussee "vers le haut de l'ecran", INDEPENDAMMENT de l'orientation de l'echelle. Avant on testait le
	-- Z MONDE en dur (mv.Z) -> ne marchait que si l'echelle/camera faisait face a -Z, et le mobile ne montait pas sinon.
	local mv = climbMoveVector()
	local forward = 0
	if mv.Magnitude > 0.05 then
		local cam = workspace.CurrentCamera
		local f = if cam then cam.CFrame.LookVector else Vector3.new(0, 0, -1)
		f = Vector3.new(f.X, 0, f.Z) -- regard horizontal
		if f.Magnitude > 1e-3 then
			forward = mv:Dot(f.Unit)
		end
	end
	if forward == 0 then -- secours si le ControlModule n'est pas (encore) resolu : lecture clavier directe (independante de la cam)
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			forward = 1
		elseif UserInputService:IsKeyDown(Enum.KeyCode.S) then
			forward = -1
		end
	end
	local up = forward > 0.2
	local down = forward < -0.2

	-- MONTEE EN FLUX CONTINU : tant qu'on POUSSE EN AVANT, on grimpe. PAS d'armement (relacher puis rappuyer) : entrer dans
	-- la zone touche avant tenue enchaine directement sur la grimpe, ca coule sans point d'arret. Le raccrochage juste
	-- apres une sortie est deja empeche par canMount (il faut quitter la zone une fois), donc pas de rebond au pied.
	local climbUp = up

	if phase == "ready" then
		-- IdleDown joue 0 -> fin UNE fois (l'anim d'ACCROCHE a l'echelle, ~1 s), puis on la FIGE sur sa derniere image
		-- (la pose "pret a monter"). Looped=true garde la pose APPLIQUEE au bout (non bouclee, la piste se relacherait a
		-- la fin et le corps sauterait), mais on ne la laisse PAS reboucler : on avance sa TimePosition A LA MAIN jusqu'a
		-- la fin puis on cle la (aucun wrap). W = enchainer sur la grimpe une fois l'accroche JOUEE, S = ressortir.
		if not idle.IsPlaying then
			idle:Play()
			idle.TimePosition = 0
		end
		idle.Looped = true
		idle:AdjustSpeed(0)
		local idleDone = true
		if idle.Length > 0 then
			idle.TimePosition = math.min(idle.TimePosition + dt, idle.Length - 0.001)
			-- Accroche JOUEE EN ENTIER avant de grimper : on attend qu'elle atteigne sa fin. Sinon W tenu des la 1re
			-- frame la couperait a ~0 s et on ne la verrait pas. Le flux reste continu : W maintenu enchaine tout seul
			-- des que l'accroche est finie, sans avoir a relacher.
			idleDone = idle.TimePosition >= idle.Length - 0.02
		end
		if climbUp and idleDone then
			-- On monte : UpDown demarre pile ou IdleDown s'arrete. La main qui agrippe demarre en meme temps, a 0.
			phase = "climbing"
			idle:Stop(0)
			climb:Play()
			climb.TimePosition = 0
			climb:AdjustSpeed(0)
			lastStepPos = 0 -- on repart du bas : pas de faux pas des la 1re frame
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
		-- SON DE PAS : des qu'on a avance d'un INTERVALLE de grimpe (montee OU descente), un pas au hasard. Base
		-- sur la progression et non sur des marqueurs -> se declenche a coup sur tant que la grimpe avance.
		if dir ~= 0 and climb.Length > 0 then
			local interval = climb.Length / CLIMB_STEP_COUNT
			if interval > 0 and math.abs(climb.TimePosition - lastStepPos) >= interval then
				lastStepPos = climb.TimePosition
				playClimbStep()
			end
		end
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
					trim.TimePosition = topTrimTime(trim, cutRatioSmooth)
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
			-- Balayage compresse a la largeur de la haie + centre (topTrimTime), borne sous la fin (une piste non
			-- bouclee posee PILE a sa fin peut s'auto-stopper).
			trim.TimePosition = topTrimTime(trim, cutRatioSmooth)
		end
		-- TAILLE DU DESSUS : on envoie le segment REEL de la lame chaque frame. Moteur en marche + gachette pressee,
		-- le serveur coupe le dessus la ou passe la lame. Sans outil en main, rien n'est envoye.
		sendBladeAim()
		if down and not climbUp then
			-- On redescend : on quitte le sommet. On coupe le maintien haut (jambes) + la coupe (bras) et on relance
			-- la main qui agrippe. La grimpe est DEJA jouee (gelee au max), la phase "climbing" la fait redescendre.
			phase = "climbing"
			setLadderWork(false)
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

	local climb = RemoteSetup.getRemote("SetLadderClimb", "Ladder")
	if climb and climb:IsA("RemoteEvent") then
		climbRemote = climb
	else
		warn("[Ladder] Remote Ladder/SetLadderClimb introuvable : la montee ne se verra pas droite chez les autres")
	end

	player.CharacterAdded:Connect(function()
		-- Nouveau perso : anciens Animator/pistes morts, etat propre.
		idleTrack = nil
		climbTrack = nil
		gripTrack = nil
		trimTrack = nil
		trimFolderLoaded = nil
		topLegsTrack = nil
		mountCFrame = nil
		phase = "off"
		canMount = true
		savedWalkSpeed = nil
		mountPromptShown = false
		pendingZone = nil
		pendingLadder = nil
		InteractionPrompt.hide()
		-- Si on meurt en haut d'une echelle, les etats "taille echelle" et "sur l'echelle" resteraient poses cote
		-- serveur et bloqueraient la taille au sol du nouveau perso. On les coupe (idempotent si deja coupes).
		setLadderWork(false)
		if onLadderRemote then
			onLadderRemote:FireServer(false)
		end
		-- Rien a reinitialiser cote camera : sur l'echelle on ne touche jamais a la camera du joueur (voir mount).
	end)

	-- Touche E = monter (PC). Sur mobile, c'est le tap du prompt (onActivate = tryMount) qui monte. tryMount est garde :
	-- sans zone de grimpe en attente, l'appui ne fait rien (donc pas de conflit avec le E de la boite aux lettres, ailleurs).
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.E then
			tryMount()
		end
	end)

	RunService.Heartbeat:Connect(update)

	print("[Ladder] Pret. Entre dans une zone -> prompt E (MONTER). Avant = monte, arriere = descend / lache.")
end

return LadderController
