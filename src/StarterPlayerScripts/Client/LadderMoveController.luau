--!strict
-- PROTOTYPE : DEPLACER l'echelle. Dans box_detecte_For_Move (enfant du model d'echelle) :
--   PRISE (E)   : le joueur joue MoveForwardLadderAnimation ; au marqueur TakeLadderEvent, on demande au SERVEUR de
--                 souder l'echelle a notre HRP et de jouer son REPLI. Puis pose de portage.
--   PORTAGE     : rail le long de la haie (on deplace + oriente le JOUEUR) ; l'echelle, SOUDEE, le suit toute seule.
--   ROTATION (R): on joue RotateLadderAnimation (geste de main) et on demande au serveur de tourner l'echelle 180 deg
--                 (tween du C0 du weld -> vu par tous). Toggle : R rebascule a l'orientation de depart.
--   REPOSE (E)  : on demande au serveur de retirer le weld, re-ancrer, et jouer le DEPLI. Puis on lache tout.
-- Ce module (client) fait le rail JOUEUR, les animations JOUEUR (prise, portage, repose) et DECLENCHE le serveur. Le
-- serveur (LadderMoveService) fait tout ce qui doit se repliquer sur l'echelle : le WELD (position) et son anim
-- (repli / depli). Une anim jouee ici sur l'echelle ne se verrait que chez le porteur, d'ou le passage au serveur.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local CarryUtils = require(ReplicatedStorage.Modules.Utils.CarryUtils)
local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)
local MoveInput = require(script.Parent.Utils.MoveInput)

-- Sons de l'echelle, ranges dans SoundService. On les CLONE au declenchement (SoundUtils), donc leur volume /
-- pitch se reglent dans Studio.
local LADDER_SOUND_PATH = { "Sounds", "Engins", "Ladder" }

local player = Players.LocalPlayer

-- Meme prefixe que LadderController : les modeles d'echelle s'appellent Escabaut_xxx.
local LADDER_PREFIX = "Escabaut"
-- Prompt "[F] PRENDRE" affiche quand le joueur est assez PRES d'une echelle. Verifie a intervalle (pas chaque frame :
-- la detection balaie les echelles). Detection RADIALE (DETECT_RADIUS), pas une box : aucun angle mort. Cf ladderAt.
local PROMPT_KEY = "F" -- PRENDRE l'echelle sur F (E est reserve a MONTER, cote LadderController)
local PROMPT_LABEL = "TAKE"
local PROMPT_TITLE = "LADDER" -- titre au-dessus du prompt (comme "MAILBOX" sur la boite), meme objet que la montee
local PROMPT_OFFSET = Vector3.new(0, 5, 0) -- hauteur d'AFFICHAGE du prompt au-dessus de la racine (pas la distance de detection)
local DETECT_RADIUS = 8 -- distance HORIZONTALE (studs) sous laquelle le prompt PRENDRE apparait. LE knob "detecter plus loin"
local PROMPT_INTERVAL = 0.2
-- Les deux anims sont dans un sous-dossier ModelAnimate (echelle + joueur).
local ANIM_FOLDER = { "Animations", "Player", "Tools", "Ladder", "ModelAnimate" }
local PLAYER_ANIM = "MoveForwardLadderAnimation" -- geste de PRISE (une fois) : le joueur attrape l'echelle
local PLAYER_CARRY_ANIM = "IsReadyForMoveLadderAnimation" -- pose de PORTAGE, en boucle : jouee A LA FIN de la prise
local PLAYER_ROTATE_ANIM = "RotateLadderAnimation" -- geste de MAIN a la rotation (R), joue une fois par-dessus le portage
-- L'anim de l'echelle (repli / depli, ActionLadderAnimation) est jouee cote SERVEUR (LadderMoveService), pour se
-- repliquer a tous. Ici on garde juste le marqueur du geste de prise qui declenche le repli, et l'attribut d'etat (lu).
local TAKE_EVENT = "TakeLadderEvent" -- marqueur dans PLAYER_ANIM : instant ou on demande au serveur le repli
local ROTATE_EVENT = "RotateAnimEvent" -- marqueur dans PLAYER_ROTATE_ANIM : instant ou on demande au serveur de tourner
local CLOSED_ATTR = "LeafiaLadderClosed" -- attribut pose par le SERVEUR : true = repliee (lu a la prise / repose)
local TAKE_KEY = Enum.KeyCode.F -- prendre / reposer l'echelle (E est reserve a MONTER, cote LadderController)
local ROTATE_KEY = Enum.KeyCode.R -- tourne l'echelle 180 degres pendant qu'on la porte
local ROTATE_DEBOUNCE = 0.45 -- anti-spam de R : environ la duree du tween serveur, pour ne pas relancer en plein tour
-- Pendant le portage, le joueur est sur un RAIL comme en taille : il glisse LE LONG de la haie a distance
-- constante, face a elle. Il ne peut pas partir dans la map.
local FACE_SPEED = 10 -- lissage du pivot vers la haie
-- Distance joueur <-> face de la haie pendant le portage. PLUS GRANDE qu'en taille (1.9) : pour porter/poser l'echelle
-- on se tient EN RETRAIT, un peu en dehors de la zone, pas colle a la haie. Monte / baisse cette valeur pour ajuster.
-- 3.5 : l'echelle se posait trop loin de la surface. C'est ce reglage-ci qu'il faut bouger et pas CARRY_CLEARANCE :
-- il rapproche le joueur ET l'echelle en gardant leur ecart, alors que l'autre pousserait l'echelle plus loin devant
-- un joueur reste en arriere -- elle finirait par entrer dans la haie.
local WORK_DIST = 3.5 -- distance perso <-> face de la haie en portage focus. Monter = perso plus RECULE de la haie.
local MAGNET_K = 1.2 -- force de rappel a la distance de travail (proportionnelle a l'ecart)
-- DEUX MODES de portage : FOCUS (rail le long de la haie) et LIBRE (detache, on se balade et on pose ou on veut).
-- On DETACHE en poussant fort vers l'arriere (S) ; on RE-FOCUS en revenant pres d'une haie. Deux distances (entree /
-- sortie) pour ne pas re-accrocher juste apres s'etre detache : il faut d'abord s'eloigner.
-- ECART (studs) entre le JOUEUR et le BORD ARRIERE de l'echelle pendant le portage. On mesure la taille reelle de
-- l'echelle et on la pousse DEVANT de sorte que son bord le plus proche soit a cette distance du joueur : le perso
-- n'est donc JAMAIS dans l'echelle, quelle que soit sa taille (fini le reglage au pif). Monter = echelle plus loin devant.
local CARRY_CLEARANCE = 1
-- ORIENTATION de l'echelle quand on la porte, en degres autour de la verticale, RELATIVE a "face a la haie" (0 =
-- l'echelle alignee comme le joueur qui regarde la haie). On ne capture plus la pose Studio d'origine (souvent de
-- travers) : c'est CETTE valeur qui fixe le sens, donc la repose est toujours pareille et bien orientee vers la
-- haie. A REGLER a l'oeil : prends l'echelle, si elle fait face de travers essaie 90, 180 ou 270 jusqu'a ce que
-- son cote de grimpe soit bien vers la haie.
local CARRY_YAW_DEGREES = 90
local DETACH_INPUT = 0.5 -- pousse arriere (part Z de l'input) au-dela de laquelle on se detache de la haie
-- Portee du FOCUS : au-dela, la haie est ignoree (pas d'aimant vers une haie lointaine). DOIT rester > WORK_DIST (5),
-- sinon l'aimant tiendrait le joueur juste HORS de la portee et le focus se couperait aussitot. Baisser = il faut
-- s'approcher PLUS pres de la haie pour que l'aimant accroche.
local FOCUS_RANGE = 6.5 -- on focus/re-focus une haie a moins de ca de sa boite (studs)
-- Apres un DETACHEMENT VOLONTAIRE (pousse arriere), on bloque le re-focus ce court instant, le temps de s'ecarter.
-- Base sur le TEMPS, pas la distance : sinon contourner la haie en restant pres ne rearmait jamais le re-focus, et on
-- ne pouvait se re-aimanter que du cote de la prise. La, on revient sur N'IMPORTE QUEL cote et ca re-focus.
local REFOCUS_GRACE = 0.4
-- AUTO-EQUIP : en approchant une haie (a cette distance de sa boite), on equipe le taille-haie tout seul. On NE
-- desequipe jamais ici, et JAMAIS pendant qu'on porte une echelle (sinon on se retrouve avec l'outil ET l'echelle).
local AUTO_EQUIP_RANGE = 6 -- distance a la haie (studs) qui declenche l'equipement auto
local AUTO_EQUIP_INTERVAL = 0.2 -- on ne teste pas la proximite chaque frame (inutile), toutes les X secondes
-- Anti-spam de E : apres une prise OU une repose, on ignore E ce court instant. E bascule prise <-> repose ; sans ca,
-- un double-tap posait l'echelle AVANT que le repli (au marqueur TakeLadderEvent, ~0.23s apres) ait joue, et l'anim
-- etait zappee ou figee en plein milieu. Ce delai laisse le repli aller jusqu'a CLOSE_EVENT avant d'autoriser la suite.
local PICKUP_DEBOUNCE = 0.6
-- SONS de l'echelle. A REMPLIR : mets l'ID de tes sons ("rbxassetid://..."). Vide = aucun son (pas d'erreur). Le son
-- est SPATIAL (joue a l'endroit de l'echelle). Pour l'instant client-local (le porteur l'entend) : quand on fera le
-- co-op de l'echelle, il passera cote serveur pour que les autres l'entendent aussi.
local PICKUP_SOUND = "LadderTakeSound" -- son joue quand on PREND l'echelle (dans LADDER_SOUND_PATH)
local PICKUP_SOUND_DELAY = 0.15 -- retard du son de prise : le geste attrape l'echelle un poil apres l'appui (0.1 a 0.2)
local PLACE_SOUND = "LadderDeposeSound" -- son joue quand on REPOSE l'echelle

-- Etat : non-nil = on est en train de porter (ou de prendre) une echelle.
local carriedLadder: Instance? = nil
local playerTrack: AnimationTrack? = nil -- geste de prise (une fois)
local carryTrack: AnimationTrack? = nil -- pose de portage (jouee une fois puis figee a la derniere image)
local placeTrack: AnimationTrack? = nil -- geste de repose = geste de prise joue A L'ENVERS (one-shot)
local rotateTrack: AnimationTrack? = nil -- geste de main a la rotation (R), joue une fois par-dessus le portage
local takeConn: RBXScriptConnection? = nil
local endConn: RBXScriptConnection? = nil
-- Rail de portage : bind RenderStep actif ? + AutoRotate d'origine a rendre a la fin.
-- L'input BRUT du joueur se lit via MoveInput (module partage) : humanoid.MoveDirection ne reflete plus son
-- intention des qu'on contraint le deplacement avec Move.
local carryBound = false
local savedAutoRotate: boolean? = nil
local RAIL_NAME = "LadderCarryRail"
-- Mode de portage : "focus" (rail le long de la haie) ou "libre" (detache, balade + pose libre). refocusBlockUntil :
-- instant (os.clock) avant lequel le re-focus est bloque, pose apres un detachement volontaire (le temps de s'ecarter).
local carryMode = "focus"
local refocusBlockUntil = 0
-- ToggleTool bascule l'outil (equipe <-> range). On ne le declenche QUE quand le taille-haie est en main, pour le
-- RANGER a la prise (sinon on l'equiperait par erreur). Prendre l'echelle ne demande PAS d'avoir l'outil.
local toggleToolRemote: RemoteEvent? = nil
-- Remote de PRISE / REPOSE. A la prise, le serveur SOUDE l'echelle a notre HRP (offset c0) : elle suit le perso et se
-- replique a tous, sans que le client la positionne. A la repose, le serveur retire le weld et re-ancre. Voir LadderMoveService.
local carryRemote: RemoteEvent? = nil
-- Vrai entre la prise et la repose : on tient l'echelle (soudee). Sert a la relacher (retirer le weld) meme sur une mort
-- (stopCarry appele hors repose normale), pour ne pas laisser une echelle desancree possedee par un perso disparu.
local ownsLadder = false
local lastEquipCheck = 0 -- throttle du test de proximite haie pour l'auto-equip
local lastActionAt = 0 -- instant de la derniere prise/repose, pour l'anti-spam de E (PICKUP_DEBOUNCE)
local lastRotateAt = 0 -- instant de la derniere rotation, pour l'anti-spam de R (ROTATE_DEBOUNCE)

-- Boutons tactiles de portage (mobile), lies au portage : bind au debut, unbind a la fin. Assignes plus bas, une fois
-- placeLadder / rotateCarry definis (interdit d'appeler une fonction au-dessus de sa definition -> forward declare).
local bindCarryButtons: () -> () = function() end
local unbindCarryButtons: () -> () = function() end
local lastPromptAt = 0 -- throttle du test de zone pour le prompt
local currentPromptLadder: Instance? = nil -- echelle dont le prompt est affiche (pour ne (re)montrer qu'au CHANGEMENT)
-- Cache des modeles d'echelle : detecter la zone chaque tick sans balayer tous les descendants du workspace
-- (des milliers de carreaux de haie). Reconstruit quand une echelle apparait / disparait.
local laddersCache: { Instance }? = nil

local LadderMoveController = {}

local function getRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Joue un son ponctuel de l'echelle (clone depuis SoundService, spatial sur l'echelle). Nom vide = rien.
local function playLadderSound(soundName: string, ladder: Instance?)
	if soundName == "" then
		return
	end
	local host: BasePart? = if ladder and ladder:IsA("Model")
		then (ladder.PrimaryPart or ladder:FindFirstChildWhichIsA("BasePart", true))
		else getRoot() -- a defaut d'echelle, sur le perso (le son reste audible)
	local path = table.clone(LADDER_SOUND_PATH)
	table.insert(path, soundName)
	SoundUtils.play(path, host)
end

-- Taille-haie en main ? La lame (HitBoxRoot) n'existe dans le perso QUE quand l'outil est equipe (meme signal que
-- LadderController / HedgeController). Sert UNIQUEMENT a decider s'il faut le RANGER a la prise, pas a l'exiger.
local function isTrimmerEquipped(): boolean
	local character = player.Character
	return character ~= nil and character:FindFirstChild("HitBoxRoot", true) ~= nil
end

local function getHumanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- Haie taguee la plus proche d'une position (les haies portent HedgeConfigs.TAG). Meme source que LadderController.
local function nearestHedge(position: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, inst in ipairs(CollectionService:GetTagged(HedgeConfigs.TAG)) do
		if inst:IsA("BasePart") then
			local d = (inst.Position - position).Magnitude
			if d < bestDist then
				best = inst
				bestDist = d
			end
		end
	end
	return best
end


-- Normale SORTANTE de la face de haie la plus proche (on ignore Y : la haie est un mur vertical). Discrete : elle
-- designe une face (X+ / X- / Z+ / Z-), suffisant pour poser une echelle.
local function faceNormal(hedge: BasePart, position: Vector3): Vector3
	local localP = hedge.CFrame:PointToObjectSpace(position)
	local half = hedge.Size * 0.5
	local outX = math.abs(localP.X) - half.X
	local outZ = math.abs(localP.Z) - half.Z
	local localN = if outX >= outZ
		then Vector3.new(if localP.X >= 0 then 1 else -1, 0, 0)
		else Vector3.new(0, 0, if localP.Z >= 0 then 1 else -1)
	return hedge.CFrame:VectorToWorldSpace(localN)
end

-- Distance HORIZONTALE du joueur a la BOITE d'une haie (0 s'il est dedans). Y ignore : une haie est un mur.
local function distToHedgeBox(hedge: BasePart, position: Vector3): number
	local localP = hedge.CFrame:PointToObjectSpace(position)
	local half = hedge.Size * 0.5
	local dx = math.max(math.abs(localP.X) - half.X, 0)
	local dz = math.max(math.abs(localP.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- Normale VRAIE (continue) + distance EXACTE a la boite : on prend le point le plus proche du bord (XZ) et la
-- direction de ce point vers le joueur. Le long d'une face c'est la perpendiculaire ; pres d'un COIN, le point le
-- plus proche EST le coin, donc la normale tourne en ARC. Le lieu a distance constante d'une boite est un rectangle
-- a coins arrondis : le coin arrondi est deja dans la geometrie, pas besoin de le fabriquer par lissage. Si le joueur
-- est DANS la boite (pas de direction radiale definie), on retombe sur la face discrete la plus proche.
local function boxNormalAndDist(hedge: BasePart, position: Vector3): (Vector3, number)
	local localP = hedge.CFrame:PointToObjectSpace(position)
	local half = hedge.Size * 0.5
	local cx = math.clamp(localP.X, -half.X, half.X)
	local cz = math.clamp(localP.Z, -half.Z, half.Z)
	local dx = localP.X - cx
	local dz = localP.Z - cz
	local distSq = dx * dx + dz * dz
	if distSq < 1e-6 then
		return faceNormal(hedge, position), 0
	end
	local dist = math.sqrt(distSq)
	return hedge.CFrame:VectorToWorldSpace(Vector3.new(dx / dist, 0, dz / dist)), dist
end

-- Part de ZONE (detection / couleur) a EXCLURE de la mesure de taille de l'echelle : ces boites depassent le rig et
-- fausseraient le calcul. On teste le nom de la part et de ses parents (jusqu'a l'echelle).
local function isDetectionPart(part: Instance, ladder: Instance): boolean
	local node: Instance? = part
	while node and node ~= ladder do
		local n = node.Name
		if n:sub(1, 11) == "box_detecte" or n:sub(1, 10) == "area_color" then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Encombrement ARRIERE de l'echelle (vers le joueur) quand elle est portee a un YAW donne, en distance depuis sa
-- RootPart. On mesure les 8 coins de chaque part STRUCTURELLE en repere ECHELLE (relatif a sa RootPart, donc
-- INDEPENDANT de son orientation actuelle), puis on applique le yaw de portage : ca donne de combien reculer
-- l'echelle pour que son dos soit a CARRY_CLEARANCE du joueur, a CE yaw. Robuste au rig (aucune supposition sur
-- quel axe est le devant).
local function ladderBackOffsetForYaw(ladder: Instance, ladderRoot: BasePart, yaw: number): number
	local rot = CFrame.Angles(0, yaw, 0)
	local maxZ = -math.huge
	for _, part in ipairs(ladder:GetDescendants()) do
		if part:IsA("BasePart") and not isDetectionPart(part, ladder) then
			local half = part.Size * 0.5
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local world = part.CFrame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
						local localCorner = ladderRoot.CFrame:PointToObjectSpace(world)
						maxZ = math.max(maxZ, (rot * localCorner).Z)
					end
				end
			end
		end
	end
	return if maxZ > -math.huge then maxZ else 0
end


-- PORTAGE (priorite Camera, apres le module de controle -> notre Move ecrase ses touches). Deux modes :
--   FOCUS : rail le long de la haie (distance constante, face a elle), l'echelle reste carree avec la haie.
--   LIBRE : detache. Le joueur marche NORMALEMENT (on ne force pas Move, AutoRotate rendu), l'echelle le suit ; il
--           pose ou il veut. FOCUS -> LIBRE en poussant fort vers l'arriere ; LIBRE -> FOCUS en revenant pres d'une
--           haie (apres s'etre eloigne, pour ne pas re-accrocher aussitot).
local function carryStep(dt: number)
	if not carriedLadder then
		return
	end
	local root = getRoot()
	local humanoid = getHumanoid()
	if not (root and humanoid and carriedLadder:IsA("Model")) then
		return
	end

	-- Pose de portage : on l'EPINGLE sur sa derniere image, chaque frame. Pas de lecture 0->fin (sinon on verrait
	-- l'anim se rejouer en entier a chaque prise) : juste la pose de tenue, maintenue. Vitesse 0 cote piste, donc
	-- c'est cet ancrage qui la tient. Length = 0 tant que l'asset charge : on attend qu'il soit pret avant d'epingler.
	if carryTrack and carryTrack.Length > 0 then
		carryTrack.TimePosition = carryTrack.Length - 0.001
	end

	local hedge = nearestHedge(root.Position)
	local dist = if hedge then distToHedgeBox(hedge, root.Position) else math.huge

	-- FOCUS -> LIBRE : pousse arriere franche (S), ou aucune haie A PORTEE (nearestHedge renvoie toujours une haie,
	-- meme a 100 studs : sans ce test de distance, l'aimant tirait le joueur vers une haie lointaine).
	if carryMode == "focus" then
		local mv = MoveInput.get()
		local pushBack = mv.Z > DETACH_INPUT
		if hedge == nil or dist > FOCUS_RANGE or pushBack then
			carryMode = "libre"
			humanoid.AutoRotate = true -- on rend au joueur le controle de son orientation
			if pushBack then
				-- Detachement VOLONTAIRE : on bloque le re-focus un court instant, le temps de s'ecarter (sinon on se
				-- re-aimanterait aussitot). Base sur le temps, pas la distance : contourner la haie re-focus quand meme.
				refocusBlockUntil = os.clock() + REFOCUS_GRACE
			end
		end
	end

	if carryMode == "focus" and hedge and dist <= FOCUS_RANGE then
		-- ===== RAIL (focus haie) =====
		-- Normale VRAIE = direction du point le plus proche de la boite vers le joueur. Aucun lissage a fabriquer : le
		-- lieu a distance constante d'une boite est deja un rectangle a coins ARRONDIS. Le long d'une face la normale
		-- est perpendiculaire ; pres d'un coin elle tourne en arc, donc le joueur contourne la haie en cercle, propre.
		local normal, boxDist = boxNormalAndDist(hedge, root.Position)

		local right = (-normal):Cross(Vector3.yAxis)
		right = if right.Magnitude > 1e-3 then right.Unit else Vector3.zero

		local mv = MoveInput.get()
		local lateral = math.clamp(mv.X + math.min(mv.Z, 0), -1, 1)
		local constrained = right * lateral

		-- Aimant : rappel proportionnel a l'ecart pour tenir WORK_DIST du bord. boxDist est la distance EXACTE a la
		-- boite (coin inclus), donc l'aimant tient la meme distance partout = le rail arrondi, coins compris.
		local gap = boxDist - WORK_DIST
		constrained += -normal * math.clamp(gap * MAGNET_K, -1, 1)

		humanoid:Move(constrained, false)

		-- Orientation face a la haie (la normale en sort, on regarde a l'oppose). L'echelle est SOUDEE au HRP : elle
		-- suit le perso toute seule (et se replique a tous), on ne la positionne plus ici. Comme le perso est tenu face
		-- a la haie, l'echelle soudee devant lui reste alignee sur la haie.
		local desired = CFrame.lookAt(root.Position, root.Position - normal)
		root.CFrame = root.CFrame:Lerp(desired, math.min(1, FACE_SPEED * dt))
	else
		-- ===== LIBRE (detache) =====
		-- Re-focus des qu'on revient pres d'une haie (N'IMPORTE QUEL cote) ET que le delai post-detachement est passe.
		if hedge and dist < FOCUS_RANGE and os.clock() >= refocusBlockUntil then
			carryMode = "focus"
			humanoid.AutoRotate = false -- on reprend la main sur l'orientation (face haie)
		end
		-- On ne force PAS Move : le joueur marche avec SES touches. L'echelle, soudee au HRP, le suit (devant lui).
	end
end

-- On DECLENCHE les actions serveur sur l'echelle par phase :
--   "grab"    : soude l'echelle a notre HRP (offset c0) -> elle suit + se replique.
--   "close"   : le serveur joue le REPLI (au marqueur de prise). Joue serveur pour se repliquer a tous.
--   "rotate"  : le serveur tween le C0 du weld -> l'echelle tourne 180 degres pour tous (toggle).
--   "place"   : retire le weld, re-ancre, et joue le DEPLI.
--   "release" : retire le weld + re-ancre sans depli (mort / respawn).
local function fireCarry(ladder: Instance, phase: string, c0: CFrame?)
	if carryRemote then
		carryRemote:FireServer(ladder, phase, c0)
	end
end

-- PRISE : on soude (grab). ownsLadder retient qu'on tient l'echelle, pour la relacher meme sur une mort.
local function grabCarry(ladder: Instance, c0: CFrame)
	ownsLadder = true
	-- "On porte" n'est PLUS pose ici : c'est LadderMoveService qui le fait, dans le meme geste que la soudure.
	-- Le client le posait lui-meme, donc un client modifie pouvait ne pas le poser et porter l'echelle PLUS le
	-- reste. Bonus : l'attribut et la soudure arrivent maintenant ENSEMBLE, au lieu que notre pose optimiste
	-- prenne de l'avance sur les zones de grimpe qui, elles, n'ont commence a suivre qu'au weld.
	fireCarry(ladder, "grab", c0)
end

-- Fin de portage : on relache (phase donnee : "place" avec depli, ou "release" sec). Idempotent via ownsLadder.
local function endCarry(ladder: Instance, phase: string)
	if not ownsLadder then
		return
	end
	ownsLadder = false
	-- La grimpe redevient possible quand le SERVEUR rend les mains, pas quand on le decide ici.
	fireCarry(ladder, phase)
end

-- Debut du portage : on coupe l'AutoRotate (on gere l'orientation) et on branche le rail en priorite Camera.
local function startCarry()
	if carryBound then
		return
	end
	local humanoid = getHumanoid()
	if humanoid then
		savedAutoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false
	end
	-- On prend l'echelle pres de son emplacement (donc pres d'une haie) : on demarre en FOCUS, sans blocage de re-focus.
	carryMode = "focus"
	refocusBlockUntil = 0
	carryBound = true
	RunService:BindToRenderStep(RAIL_NAME, Enum.RenderPriority.Camera.Value, carryStep)
	bindCarryButtons() -- pose les boutons tactiles DROP / TURN (mobile) le temps du portage
end

-- Beams de l'echelle (le rectangle de zone area_color_action) : caches pendant le portage, remontres a la repose.
-- On balaie les descendants (les Beams sont ranges sous box_detecte_For_Move) et on toggle leur .Enabled.
local function setLadderBeams(ladder: Instance, enabled: boolean)
	for _, d in ipairs(ladder:GetDescendants()) do
		if d:IsA("Beam") then
			d.Enabled = enabled
		end
	end
end

-- Fin du portage : on debranche le rail, on rend l'AutoRotate, on stoppe les pistes et on lache l'echelle.
-- (La REPOSE de l'echelle au sol viendra apres ; ici on nettoie deja proprement pour la mort / le respawn.)
local function stopCarry()
	if carryBound then
		RunService:UnbindFromRenderStep(RAIL_NAME)
		carryBound = false
	end
	unbindCarryButtons() -- retire les boutons tactiles DROP / TURN (mobile)
	local humanoid = getHumanoid()
	if humanoid and savedAutoRotate ~= nil then
		humanoid.AutoRotate = savedAutoRotate
	end
	savedAutoRotate = nil
	if endConn then
		endConn:Disconnect()
		endConn = nil
	end
	if takeConn then
		takeConn:Disconnect()
		takeConn = nil
	end
	if playerTrack then
		playerTrack:Stop(0.1)
		playerTrack = nil
	end
	if carryTrack then
		carryTrack:Stop(0.1)
		carryTrack = nil
	end
	if rotateTrack then
		rotateTrack:Stop(0)
		rotateTrack = nil
	end
	if carriedLadder then
		setLadderBeams(carriedLadder, true) -- l'echelle est reposee (ou on est mort) : la zone redevient visible
		-- Si on tient encore l'echelle (mort / respawn en plein portage), on la relache sec (retire le weld + re-ancre) :
		-- sinon on laisserait une echelle soudee a un perso disparu. En repose normale, placeLadder a deja relache.
		if ownsLadder then
			endCarry(carriedLadder, "release")
		end
	end
	carriedLadder = nil
end

-- Animator du JOUEUR. WaitForChild court : a CharacterAdded l'Animator arrive quelques frames apres l'Humanoid.
local function getPlayerAnimator(): Animator?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	return humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 2) :: Animator?
end

local function resolveAnimation(name: string): Animation?
	local node: Instance = ReplicatedStorage
	for _, part in ipairs(ANIM_FOLDER) do
		local child = node:FindFirstChild(part)
		if not child then
			return nil
		end
		node = child
	end
	local anim = node:FindFirstChild(name)
	return if anim and anim:IsA("Animation") then anim else nil
end

local function loadTrack(animator: Animator, name: string): AnimationTrack?
	local anim = resolveAnimation(name)
	if not anim then
		warn(`[LadderMove] Animation {name} introuvable dans {table.concat(ANIM_FOLDER, "/")}`)
		return nil
	end
	return animator:LoadAnimation(anim)
end

-- Geste de REPOSE = le geste de prise (PLAYER_ANIM) joue A L'ENVERS. Une piste jouee a l'envers ne s'auto-stoppe pas
-- fiablement a 0 (cf LadderController qui teste TimePosition a la main), et poser TimePosition PILE a la fin peut
-- l'auto-stopper : on part donc de Length - 0.001, vitesse negative, et on la stoppe apres sa duree. Le controle
-- d'identite (placeTrack == rev) evite qu'un arret retarde tue un geste plus recent.
local function playPlaceGesture()
	local animator = getPlayerAnimator()
	if not animator then
		return
	end
	local rev = loadTrack(animator, PLAYER_ANIM)
	if not rev then
		return
	end
	placeTrack = rev
	rev.Priority = Enum.AnimationPriority.Action2
	rev.Looped = false
	rev:Play(0.1)
	local len = if rev.Length > 0 then rev.Length else 0.4
	rev.TimePosition = len - 0.001
	rev:AdjustSpeed(-1)
	task.delay(len, function()
		if placeTrack == rev then
			rev:Stop(0.1)
			placeTrack = nil
		end
	end)
end

-- REPOSE (2e appui sur E). On DECLENCHE le serveur : "place" s'il faut deplier (echelle repliee), sinon "release".
-- Le serveur retire le weld, re-ancre sur place, et joue le DEPLI (qui se replique a tous). Le client, lui, coupe
-- juste son rail et joue le geste de repose : il n'a plus a gerer le timing du depli (le serveur le fait).
local function placeLadder()
	local ladder = carriedLadder
	if not ladder then
		return
	end
	playLadderSound(PLACE_SOUND, ladder) -- son de repose
	-- Toujours "place" a la repose normale : c'est le SERVEUR qui sait s'il y a un depli a jouer (il a la piste) ou
	-- non. Pas de lecture d'attribut cote client, qui pourrait etre en retard sur le repli et rater le depli.
	endCarry(ladder, "place") -- relache cote serveur : retire le weld, re-ancre, et deplie si l'echelle etait repliee
	stopCarry() -- debranche le rail + stoppe la pose ; ownsLadder est deja false, donc pas de double release
	playPlaceGesture()
end

-- Modeles d'echelle du Workspace, EN CACHE. ladderAt tourne maintenant EN CONTINU (pour le prompt), on ne peut
-- plus balayer tous les descendants (des milliers de carreaux) a chaque appel. Le cache se reconstruit quand une
-- echelle apparait / disparait (voir init, filtre par nom : les carreaux ne le touchent pas). GetDescendants (une
-- fois) : l'echelle reste trouvee meme rangee dans un dossier.
local function getLadders(): { Instance }
	local cached = laddersCache
	if cached then
		return cached
	end
	local list: { Instance } = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name:sub(1, #LADDER_PREFIX) == LADDER_PREFIX then
			table.insert(list, d)
		end
	end
	laddersCache = list
	return list
end

-- RootPart de l'echelle (PrimaryPart, sinon enfant "RootPart"). Reference FIXE, contrairement a GetPivot qui suit la
-- bounding box (que les zones welded decalent). Meme source que le portage.
local function ladderRootPart(ladder: Instance): BasePart?
	if ladder:IsA("Model") then
		local r = ladder.PrimaryPart or ladder:FindFirstChild("RootPart")
		return if r and r:IsA("BasePart") then r else nil
	end
	return nil
end

-- Echelle PRENABLE la plus proche de la position, ou nil. Detection RADIALE : distance HORIZONTALE (X/Z) a la RootPart
-- de l'echelle, sous DETECT_RADIUS. Un seul rayon -> AUCUN angle mort, independant de l'orientation du rig. Les anciennes
-- box laterales (offset 3) laissaient des trous : colle a un bout de l'echelle, on tombait HORS zone -> pas de prompt.
-- On rend la PLUS PROCHE dans le rayon.
local function ladderAt(position: Vector3): Instance?
	local best: Instance? = nil
	local bestDist = DETECT_RADIUS
	for _, ladder in ipairs(getLadders()) do
		if ladder.Parent then
			local root = ladderRootPart(ladder)
			if root then
				local flat = (root.Position - position) * Vector3.new(1, 0, 1) -- Y ignore : une echelle se prend au sol
				local dist = flat.Magnitude
				if dist <= bestDist then
					best = ladder
					bestDist = dist
				end
			end
		end
	end
	return best
end

local function pickUp(ladder: Instance)
	if carriedLadder then
		return
	end
	-- LES MAINS SONT DEJA PRISES (seau, tondeuse). Le serveur refuse deja la soudure, mais SANS ce test le geste
	-- partait quand meme : animation de prise, son, et rien au bout. Le joueur voyait son perso attraper une
	-- echelle qu'il n'attrapait pas. Un refus serveur silencieux n'est pas un refus : il faut aussi que le client
	-- n'ait rien joue.
	if not CarryUtils.isFree(player) then
		return
	end
	local animator = getPlayerAnimator()
	if not animator then
		return
	end
	-- Si le geste de repose (prise a l'envers) tourne encore, on le coupe : on repart d'une prise propre.
	if placeTrack then
		placeTrack:Stop(0)
		placeTrack = nil
	end
	carriedLadder = ladder
	-- Son de prise RETARDE : le geste (MoveForwardLadderAnimation) attrape l'echelle un peu apres l'appui, le son colle
	-- mieux decale. Garde : si on ne porte plus CETTE echelle a l'echeance (respawn, repose eclair), on ne joue rien.
	task.delay(PICKUP_SOUND_DELAY, function()
		if carriedLadder == ladder then
			playLadderSound(PICKUP_SOUND, ladder)
		end
	end)
	setLadderBeams(ladder, false) -- on cache la zone (Beams) tant qu'on porte l'echelle

	-- L'echelle est-elle DEJA repliee ? (pose par FermerEvenement lors d'un repli precedent). Si oui, on ne rejoue
	-- pas le repli a la prise : elle est deja fermee, on part directement en portage.
	local alreadyClosed = ladder:GetAttribute(CLOSED_ATTR) == true

	-- Si le taille-haie est en main, on le RANGE : porter l'echelle et tenir l'outil en meme temps embrouille. On
	-- toggle SEULEMENT dans ce sens (equipe -> range) : sans outil, on ne fait rien et on prend l'echelle quand meme.
	if isTrimmerEquipped() and toggleToolRemote then
		toggleToolRemote:FireServer()
	end

	-- On retient la position de l'echelle relative a un REPERE CARRE avec la haie (a la position du joueur, face a la
	-- haie, a plat), et NON a la rotation exacte du joueur : celle-ci louvoie (lerp), et l'echelle finirait de travers.
	-- En s'accrochant au repere carre, l'echelle reste TOUJOURS alignee sur la haie, quel que soit l'angle exact.
	local root0 = getRoot()
	local ladderRoot = if ladder:IsA("Model")
		then (ladder :: Model).PrimaryPart or (ladder:FindFirstChild("RootPart") :: BasePart?)
		else nil
	if root0 and ladder:IsA("Model") and ladderRoot then
		local hedge0 = nearestHedge(root0.Position)
		local square0 = if hedge0
			then CFrame.lookAt(root0.Position, root0.Position - faceNormal(hedge0, root0.Position))
			else root0.CFrame
		-- Offset base sur la ROOTPART, PAS sur ladder:GetPivot() : GetPivot suit la BOUNDING BOX du model, que les
		-- zones de detection generees (box_detecte_For_Move, soudees a la racine, decalees sur les cotes + au sol)
		-- DECALENT et DESORIENTENT -> l'echelle partait de travers. La RootPart, elle, ne bouge pas.
		-- ORIENTATION DE PORTAGE FIXE et reglable (CARRY_YAW_DEGREES), relative au repere carre (face a la haie). On ne
		-- capture PLUS le yaw d'origine de l'echelle : il venait de sa pose Studio, souvent de travers -> portee ET
		-- reposee de travers pour toujours. Ici le sens est CONNU, donc la repose est toujours pareille et bien orientee
		-- vers la haie. X centre, Y garde la hauteur, Z recule pour que le dos soit a CARRY_CLEARANCE du joueur.
		local heightY = square0:ToObjectSpace(ladderRoot.CFrame).Position.Y
		-- SENS DETERMINISTE : toujours CARRY_YAW_DEGREES, jamais son oppose. On avait un flip 0/180 "le plus proche de la
		-- pose plantee", mais l'echelle REPLIEE est ~symetrique : le flip choisissait parfois l'oppose sans que ca se voie
		-- a la prise, et au DEPLI (repose) l'echelle se retrouvait a 180 de travers. Un sens unique = repose toujours bonne.
		local yaw = math.rad(CARRY_YAW_DEGREES)
		-- Bord arriere mesure A CE yaw : l'echelle recule pile ce qu'il faut, quelle que soit l'orientation choisie.
		local backOffset = ladderBackOffsetForYaw(ladder, ladderRoot, yaw)
		local offset = CFrame.new(0, heightY, -(CARRY_CLEARANCE + backOffset)) * CFrame.Angles(0, yaw, 0)

		-- SOUDURE : le serveur fige RootPart = HRP.CFrame * offset. Le HRP fait face a la haie EN PORTAGE (square0, le
		-- rail l'y tient), donc l'echelle se cale droite devant et bien orientee des que le joueur l'est.
		grabCarry(ladder, offset) -- soude l'echelle au HRP : elle suit + se replique a tous
	end

	-- Stance FOCUS : rail le long de la haie, face a elle, tant qu'on porte l'echelle.
	startCarry()

	-- 1. Le JOUEUR joue le geste de prise. Action2 : au-dessus du maintien d'outil (Action) et de la marche.
	local track = loadTrack(animator, PLAYER_ANIM)
	if not track then
		carriedLadder = nil
		return
	end
	playerTrack = track
	track.Priority = Enum.AnimationPriority.Action2
	track.Looped = false
	track:Play()

	-- 2. SYNCHRO : au marqueur TakeLadderEvent (la main attrape l'echelle), on DEMANDE au serveur de jouer le REPLI,
	-- SAUF si l'echelle est deja repliee. C'est le SERVEUR qui joue l'anim (elle se replique alors a tous les joueurs,
	-- contrairement a une anim jouee ici sur l'echelle). Le depli, lui, sera declenche a la repose (voir placeLadder).
	if takeConn then
		takeConn:Disconnect()
	end
	if not alreadyClosed then
		takeConn = track:GetMarkerReachedSignal(TAKE_EVENT):Connect(function()
			fireCarry(ladder, "close")
		end)
	end

	-- 3. A LA FIN du geste de prise, on enchaine sur la pose de PORTAGE, EN BOUCLE (tenue tant qu'on porte l'echelle).
	-- Meme logique que l'echelle : IdleDown (pret) -> UpDown (grimpe) ; ici MoveForward (prise) -> IsReadyForMove
	-- (porte). La derniere image de la prise doit matcher la 1re du portage pour un enchainement propre, sans pop.
	if endConn then
		endConn:Disconnect()
	end
	endConn = track.Stopped:Connect(function()
		if endConn then
			endConn:Disconnect()
			endConn = nil
		end
		if not carriedLadder then
			return -- repose entre-temps : plus rien a enchainer
		end
		local carry = loadTrack(animator, PLAYER_CARRY_ANIM)
		if carry then
			carryTrack = carry
			carry.Priority = Enum.AnimationPriority.Action2
			-- Pose de portage : elle doit TENIR sa derniere image, pas se rejouer. Looped = true garde la pose appliquee
			-- (sans Looped elle se relacherait), vitesse 0 pour qu'elle n'avance jamais seule, et carryStep l'epingle sur
			-- sa derniere image chaque frame. Le fondu 0.15 s la relie proprement a la fin du geste de prise.
			carry.Looped = true
			carry:Play(0.15)
			carry:AdjustSpeed(0)
		end
	end)
end

-- ROTATION (touche R) pendant le portage. Le SERVEUR tourne l'echelle (tween du weld -> vu par tous) ; ICI on
-- joue le geste de main par-dessus la pose de portage, et on demande la rotation au marqueur RotateAnimEvent
-- (l'echelle tourne PILE quand la main la fait tourner). Le geste, joue sur SON propre perso, se replique aussi
-- aux autres.
local function rotateCarry()
	local ladder = carriedLadder
	if not ladder then
		return
	end

	local animator = getPlayerAnimator()
	if not animator then
		-- Pas d'animator (respawn en cours) : on tourne quand meme, le geste n'est qu'un plus.
		fireCarry(ladder, "rotate")
		return
	end
	-- Rechargee a chaque fois (action rare) ; on coupe la precedente pour que deux R rapproches ne se chevauchent pas.
	if rotateTrack then
		rotateTrack:Stop(0)
		rotateTrack = nil
	end
	local track = loadTrack(animator, PLAYER_ROTATE_ANIM)
	if not track then
		fireCarry(ladder, "rotate")
		return
	end
	rotateTrack = track
	-- Action3 : AU-DESSUS de la pose de portage (Action2). Le geste prend le pas pendant qu'il joue, puis rend la
	-- main a la pose de portage figee. Une seule fois.
	track.Priority = Enum.AnimationPriority.Action3
	track.Looped = false

	-- On tourne l'echelle AU MARQUEUR (sync avec la main), une seule fois. Secours a l'arret de la piste : a la
	-- 1re lecture de la session, l'asset peut ne pas etre charge et le marqueur ne pas tirer -> sans ce secours,
	-- l'echelle ne tournerait pas du tout ce coup-la.
	local fired = false
	local markerConn: RBXScriptConnection? = nil
	local stopConn: RBXScriptConnection? = nil
	local function doRotate()
		if fired then
			return
		end
		fired = true
		fireCarry(ladder, "rotate")
		if markerConn then
			markerConn:Disconnect()
		end
		if stopConn then
			stopConn:Disconnect()
		end
	end
	markerConn = track:GetMarkerReachedSignal(ROTATE_EVENT):Connect(doRotate)
	stopConn = track.Stopped:Connect(doRotate)
	track:Play(0.1)
end

-- Prompt "[E] PRENDRE" : affiche quand on ENTRE dans une zone (et qu'on ne porte pas), cache sinon. On ne
-- (re)montre qu'au CHANGEMENT d'echelle. Throttle car detecter la zone balaie les echelles. Sur mobile, le tap
-- du prompt prend l'echelle (meme chose que E), avec le meme anti-spam.
local function updatePrompt()
	if os.clock() - lastPromptAt < PROMPT_INTERVAL then
		return
	end
	lastPromptAt = os.clock()

	local root = getRoot()
	-- On ne propose pas ce qu'on ne pourra pas prendre : mains deja prises (seau, tondeuse) = pas de prompt. Sans
	-- ca le badge "F PRENDRE" restait affiche par-dessus un seau qu'on porte, et l'appui ne donnait rien.
	local free = CarryUtils.isFree(player)
	local ladder: Instance? = if root and not carriedLadder and free then ladderAt(root.Position) else nil
	if ladder == currentPromptLadder then
		return
	end
	currentPromptLadder = ladder

	if ladder and ladder:IsA("Model") then
		local model = ladder
		local target = model.PrimaryPart or model:FindFirstChild("RootPart")
		if target and target:IsA("BasePart") then
			InteractionPrompt.show(target, PROMPT_KEY, PROMPT_LABEL, PROMPT_OFFSET, function()
				if os.clock() - lastActionAt < PICKUP_DEBOUNCE then
					return
				end
				lastActionAt = os.clock()
				pickUp(model)
			end, PROMPT_TITLE)
			return
		end
	end
	InteractionPrompt.hide()
end

-- Declencheurs CENTRAUX des 3 actions, chacun anti-spammé. Clavier (UserInputService) ET tactile (ContextActionService,
-- mobile) tapent ces memes fonctions : appeler deux fois dans la meme frame est sans risque, le debounce absorbe le 2e.
local function tryPickup()
	if carriedLadder or os.clock() - lastActionAt < PICKUP_DEBOUNCE then
		return
	end
	local root = getRoot()
	if not root then
		return
	end
	local ladder = ladderAt(root.Position)
	if ladder then
		lastActionAt = os.clock()
		pickUp(ladder)
	end
end

local function tryPlace()
	if not carriedLadder or os.clock() - lastActionAt < PICKUP_DEBOUNCE then
		return
	end
	lastActionAt = os.clock()
	placeLadder()
end

local function tryRotate()
	if not (carriedLadder and ownsLadder) or os.clock() - lastRotateAt < ROTATE_DEBOUNCE then
		return
	end
	lastRotateAt = os.clock()
	rotateCarry()
end

-- Boutons tactiles DROP / TURN du portage (MOBILE uniquement). ScreenGui custom (PAS ContextActionService, dont les
-- boutons ronds plats sont moches et auto-alignes cote a cote) : on maitrise la POSITION (en DIAGONALE, a gauche du
-- bouton de saut, sans le chevaucher) et le STYLE. Crees UNE fois, caches par defaut ; bindCarryButtons les montre le
-- temps du portage, unbindCarryButtons les cache. Le clavier (F / R) reste gere par UserInputService (voir init), donc
-- rien a l'ecran sur PC. La PRISE se fait au tap du prompt d'interaction (updatePrompt), pas ici.
local IS_TOUCH = UserInputService.TouchEnabled
local carryButtonsGui: ScreenGui? = nil
local CARRY_BTN_SIZE = 54 -- diametre d'un bouton (px GUI). Plus petit = moins encombrant
-- Positions : AnchorPoint bas-droite (1,1), offsets en px GUI depuis le coin bas-droite (ou vit le bouton de saut Roblox).
-- ATTENTION : px GUI (points), PAS px physiques -- sur ce type d'ecran l'unite GUI fait ~2.4x le pixel d'une CAPTURE, donc
-- de gros offsets propulsent les boutons au CENTRE. DIAGONALE "/" : TURN en BAS a gauche, DROP en HAUT a droite (vers le
-- pouce / le saut). Valeurs calibrees sur capture, A affiner a l'oeil.
local DROP_BTN_POS = UDim2.new(1, -93, 1, -148)
local TURN_BTN_POS = UDim2.new(1, -153, 1, -68)
local DROP_BTN_COLOR = Color3.fromRGB(255, 146, 237) -- rose (fond du bouton DROP)
local TURN_BTN_COLOR = Color3.fromRGB(164, 73, 221) -- violet (fond du bouton TURN)
local CARRY_BTN_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy) -- Heavy = Black (900)

local function makeCarryButton(name: string, label: string, pos: UDim2, bg: Color3, onPress: () -> ()): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = pos
	btn.Size = UDim2.fromOffset(CARRY_BTN_SIZE, CARRY_BTN_SIZE)
	btn.BackgroundColor3 = bg
	btn.BackgroundTransparency = 0
	btn.Text = label
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.FontFace = CARRY_BTN_FONT
	btn.TextScaled = true
	btn.BorderSizePixel = 0
	local corner = Instance.new("UICorner") :: UICorner
	corner.CornerRadius = UDim.new(1, 0) -- cercle plein
	corner.Parent = btn
	local pad = Instance.new("UIPadding") -- marge interne pour que le texte ne colle pas au bord du rond
	pad.PaddingTop = UDim.new(0.3, 0)
	pad.PaddingBottom = UDim.new(0.3, 0)
	pad.PaddingLeft = UDim.new(0.16, 0)
	pad.PaddingRight = UDim.new(0.16, 0)
	pad.Parent = btn
	btn.Activated:Connect(onPress)
	return btn
end

local function ensureCarryButtonsGui()
	if carryButtonsGui or not IS_TOUCH then
		return
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "LeafiaLadderCarry"
	sg.ResetOnSpawn = false -- survit aux respawns : on ne veut pas la recreer a chaque mort
	sg.DisplayOrder = 5
	sg.Enabled = false
	sg:SetAttribute("LeafiaNoSlime", true) -- pas de slime auto (ButtonSlimeController) sur ces boutons
	makeCarryButton("Turn", "TURN", TURN_BTN_POS, TURN_BTN_COLOR, tryRotate).Parent = sg
	makeCarryButton("Drop", "DROP", DROP_BTN_POS, DROP_BTN_COLOR, tryPlace).Parent = sg
	sg.Parent = player:WaitForChild("PlayerGui")
	carryButtonsGui = sg
end

bindCarryButtons = function()
	if not IS_TOUCH then
		return -- PC : le clavier (F / R) gere tout, aucun bouton a l'ecran
	end
	ensureCarryButtonsGui()
	if carryButtonsGui then
		carryButtonsGui.Enabled = true
	end
end

unbindCarryButtons = function()
	if carryButtonsGui then
		carryButtonsGui.Enabled = false
	end
end

function LadderMoveController.init()
	local toggle = RemoteSetup.getRemote("ToggleTool", "Tool")
	if toggle and toggle:IsA("RemoteEvent") then
		toggleToolRemote = toggle
	else
		warn("[LadderMove] Remote Tool/ToggleTool introuvable : le taille-haie ne se rangera pas a la prise")
	end

	local carry = RemoteSetup.getRemote("SetLadderCarry", "Ladder")
	if carry and carry:IsA("RemoteEvent") then
		carryRemote = carry
	else
		warn(
			"[LadderMove] Remote Ladder/SetLadderCarry introuvable : le portage ne sera pas visible des autres joueurs"
		)
	end

	-- Clavier (PC). Sur mobile, les boutons tactiles DROP / TURN (ScreenGui custom) tapent les memes tryXxx pendant le
	-- portage ; la PRISE, elle, se fait au tap du prompt d'interaction (updatePrompt). F = prendre / reposer, R = tourner.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == ROTATE_KEY then
			tryRotate()
		elseif input.KeyCode == TAKE_KEY then
			if carriedLadder then
				tryPlace()
			else
				tryPickup()
			end
		end
	end)

	-- Respawn / mort en plein portage : l'ancien perso est mort, on repart d'un etat propre (boucle de facing coupee,
	-- pistes lachees). Sans ca, le rail tournerait sur un root disparu et carriedLadder resterait bloque.
	player.CharacterAdded:Connect(function()
		stopCarry()
		-- Nouveau perso : on repart sans prompt (l'ancien pointait sur l'ancienne position).
		currentPromptLadder = nil
		InteractionPrompt.hide()
	end)

	-- Cache des echelles : invalide des qu'une echelle apparait / disparait (filtre par nom : les carreaux de
	-- haie qui s'ajoutent ne le touchent pas).
	local function invalidateIfLadder(inst: Instance)
		if inst:IsA("Model") and inst.Name:sub(1, #LADDER_PREFIX) == LADDER_PREFIX then
			laddersCache = nil
		end
	end
	workspace.DescendantAdded:Connect(invalidateIfLadder)
	workspace.DescendantRemoving:Connect(invalidateIfLadder)

	-- AUTO-EQUIP DU TAILLE-HAIE en approchant une haie. Confort : plus besoin de l'equiper a la main avant de tailler.
	-- Garde-fous : jamais si on PORTE une echelle (on veut les mains libres pour l'echelle), jamais si l'outil est deja
	-- en main. On n'auto-DESEQUIPE pas (seul le portage range l'outil). ToggleTool sans outil en main = il equipe.
	RunService.Heartbeat:Connect(function()
		updatePrompt() -- son propre throttle (PROMPT_INTERVAL), independant de l'auto-equip ci-dessous
		if os.clock() - lastEquipCheck < AUTO_EQUIP_INTERVAL then
			return
		end
		lastEquipCheck = os.clock()
		if carriedLadder or isTrimmerEquipped() or not toggleToolRemote then
			return
		end
		-- LES MAINS SONT PRISES (tondeuse, echelle, seau) : tous se portent a deux mains, pas d'outil pendant ce
		-- temps. Le serveur refuse deja l'equipement, mais sans ce test l'auto-equip tirerait le remote toutes les
		-- 0.2 s pour rien -- l'outil ne s'equipant jamais, la condition "pas encore equipe" resterait vraie pour
		-- toujours. Avant, ce test ne connaissait que la tondeuse.
		if not CarryUtils.isFree(player) then
			return
		end
		-- Sur l'echelle : l'outil est RANGE le temps de la grimpe (cote serveur). On NE le re-sort pas ici, sinon
		-- l'auto-equip se battrait avec ce rangement et l'outil reviendrait en pleine montee.
		local character = player.Character
		if character and character:GetAttribute("LeafiaOnLadder") then
			return
		end
		local root = getRoot()
		if not root then
			return
		end
		local hedge = nearestHedge(root.Position)
		if not hedge then
			return
		end
		-- Distance HORIZONTALE du joueur a la boite de la haie (0 s'il est dedans). Y ignore : une haie est un mur.
		local localP = hedge.CFrame:PointToObjectSpace(root.Position)
		local half = hedge.Size * 0.5
		local dx = math.max(math.abs(localP.X) - half.X, 0)
		local dz = math.max(math.abs(localP.Z) - half.Z, 0)
		if math.sqrt(dx * dx + dz * dz) <= AUTO_EQUIP_RANGE then
			toggleToolRemote:FireServer() -- aucun outil en main -> ToggleTool equipe le taille-haie
			-- ANTI-OSCILLATION : l'outil (HitBoxRoot) n'apparait qu'apres un aller-retour serveur. Sans ce delai, le
			-- test suivant croirait qu'il n'est pas equipe et re-tirerait ToggleTool, qui cette fois le DESEQUIPERAIT.
			lastEquipCheck = os.clock() + 0.8
		end
	end)

	print("[LadderMove] Pret. E dans box_detecte_For_Move pour prendre l'echelle.")
end

return LadderMoveController
