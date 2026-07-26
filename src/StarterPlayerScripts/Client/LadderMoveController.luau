--!strict
-- PROTOTYPE : DEPLACER l'echelle. Dans box_detecte_For_Move (enfant du model d'echelle) :
--   PRISE (E)   : le joueur joue MoveForwardLadderAnimation ; au marqueur TakeLadderEvent, l'echelle (son propre
--                 Humanoid) joue ActionLadderAnimation et se REPLIE, figee a CLOSE_EVENT. Puis pose de portage.
--   PORTAGE     : rail le long de la haie (face a elle, distance constante), l'echelle repliee SUIT le joueur.
--   REPOSE (E)  : on REPREND la meme anim de CLOSE_EVENT jusqu'a OPEN_EVENT (l'echelle se DEPLIE), et on lache tout.
-- Repli / portage / depli sont joues EN LOCAL (prediction client), le porteur les voit parfaitement. Seule la POSITION
-- finale part au serveur a la repose (LadderMoveService), pour que l'echelle POSEE se replique aux autres joueurs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)

local player = Players.LocalPlayer

-- Meme prefixe que LadderController : les modeles d'echelle s'appellent Escabaut_xxx.
local LADDER_PREFIX = "Escabaut"
-- La zone de prise, posee comme enfant de CHAQUE model d'echelle.
local MOVE_ZONE_NAME = "box_detecte_For_Move"
-- Les deux anims sont dans un sous-dossier ModelAnimate (echelle + joueur).
local ANIM_FOLDER = { "Animations", "Player", "Tools", "Ladder", "ModelAnimate" }
local PLAYER_ANIM = "MoveForwardLadderAnimation" -- geste de PRISE (une fois) : le joueur attrape l'echelle
local PLAYER_CARRY_ANIM = "IsReadyForMoveLadderAnimation" -- pose de PORTAGE, en boucle : jouee A LA FIN de la prise
-- UNE seule anim d'echelle, deux temps balises par deux marqueurs : 0 -> CLOSE_EVENT = repli, CLOSE_EVENT ->
-- OPEN_EVENT = depli. On la fige a CLOSE_EVENT a la prise, on la REPREND jusqu'a OPEN_EVENT a la repose.
local MODEL_ANIM = "ActionLadderAnimation" -- jouee sur l'ECHELLE (repli puis depli, les deux temps dans une seule anim)
local TAKE_EVENT = "TakeLadderEvent" -- marqueur dans PLAYER_ANIM : instant ou on lance le repli de l'echelle
local CLOSE_EVENT = "FermerEvenement" -- marqueur MODEL_ANIM : echelle REPLIEE, on fige la pose la
local OPEN_EVENT = "LadderOpenEndEvent" -- marqueur MODEL_ANIM : echelle DEPLIEE (fin), on stoppe l'anim la
local CLOSED_ATTR = "LeafiaLadderClosed" -- attribut sur le model : true = repliee. Evite de la replier deux fois.
local TAKE_KEY = Enum.KeyCode.E
-- Pendant le portage, le joueur est sur un RAIL comme en taille : il glisse LE LONG de la haie a distance
-- constante, face a elle. Il ne peut pas partir dans la map.
local FACE_SPEED = 10 -- lissage du pivot vers la haie
-- Distance joueur <-> face de la haie pendant le portage. PLUS GRANDE qu'en taille (1.9) : pour porter/poser l'echelle
-- on se tient EN RETRAIT, un peu en dehors de la zone, pas colle a la haie. Monte / baisse cette valeur pour ajuster.
local WORK_DIST = 5 -- distance perso <-> face de la haie en portage focus. Monter = perso plus RECULE de la haie.
local MAGNET_K = 1.2 -- force de rappel a la distance de travail (proportionnelle a l'ecart)
-- DEUX MODES de portage : FOCUS (rail le long de la haie) et LIBRE (detache, on se balade et on pose ou on veut).
-- On DETACHE en poussant fort vers l'arriere (S) ; on RE-FOCUS en revenant pres d'une haie. Deux distances (entree /
-- sortie) pour ne pas re-accrocher juste apres s'etre detache : il faut d'abord s'eloigner.
-- ECART (studs) entre le JOUEUR et le BORD ARRIERE de l'echelle pendant le portage. On mesure la taille reelle de
-- l'echelle et on la pousse DEVANT de sorte que son bord le plus proche soit a cette distance du joueur : le perso
-- n'est donc JAMAIS dans l'echelle, quelle que soit sa taille (fini le reglage au pif). Monter = echelle plus loin devant.
local CARRY_CLEARANCE = 1
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
local PICKUP_SOUND = "" -- son joue quand on PREND l'echelle
local PLACE_SOUND = "" -- son joue quand on REPOSE l'echelle
local LADDER_SOUND_VOLUME = 0.6

-- Etat : non-nil = on est en train de porter (ou de prendre) une echelle.
local carriedLadder: Instance? = nil
local playerTrack: AnimationTrack? = nil -- geste de prise (une fois)
local carryTrack: AnimationTrack? = nil -- pose de portage (jouee une fois puis figee a la derniere image)
local placeTrack: AnimationTrack? = nil -- geste de repose = geste de prise joue A L'ENVERS (one-shot)
-- Piste de repli/depli PAR echelle : elle vit tout le cycle (prise -> figee repliee -> repose -> depliee -> stoppee).
-- Table (pas une var simple) pour ne jamais perdre la reference, meme apres une mort en plein portage.
local foldTracks: { [Instance]: AnimationTrack } = {}
local takeConn: RBXScriptConnection? = nil
local endConn: RBXScriptConnection? = nil
-- Rail de portage : bind RenderStep actif ? + AutoRotate d'origine a rendre a la fin. controlModule = le module de
-- controle du joueur, pour lire son input BRUT (humanoid.MoveDirection ne marche pas une fois qu'on contraint Move).
local carryBound = false
local savedAutoRotate: boolean? = nil
local controlModule: any = nil
local RAIL_NAME = "LadderCarryRail"
-- Mode de portage : "focus" (rail le long de la haie) ou "libre" (detache, balade + pose libre). refocusBlockUntil :
-- instant (os.clock) avant lequel le re-focus est bloque, pose apres un detachement volontaire (le temps de s'ecarter).
local carryMode = "focus"
local refocusBlockUntil = 0
-- Offset CANONIQUE de l'echelle dans les mains, capture UNE SEULE FOIS (a la 1re prise, echelle a sa pose d'origine
-- carree). Reutilise a chaque prise : l'echelle est donc TOUJOURS reprise droite, meme si une pose libre l'a laissee
-- de travers (sinon le travers se recapturait et s'accumulait). Constante de rig : jamais remis a zero.
local canonicalOffset: CFrame? = nil
-- ToggleTool bascule l'outil (equipe <-> range). On ne le declenche QUE quand le taille-haie est en main, pour le
-- RANGER a la prise (sinon on l'equiperait par erreur). Prendre l'echelle ne demande PAS d'avoir l'outil.
local toggleToolRemote: RemoteEvent? = nil
-- Remote de PRISE / REPOSE. A la prise, le serveur SOUDE l'echelle a notre HRP (offset c0) : elle suit le perso et se
-- replique a tous, sans que le client la positionne. A la repose, le serveur retire le weld et re-ancre. Voir LadderMoveService.
local carryRemote: RemoteEvent? = nil
-- Vrai entre la prise et la repose : on tient l'echelle (soudee). Sert a la relacher (retirer le weld) meme sur une mort
-- (stopCarry appele hors repose normale), pour ne pas laisser une echelle desancree possedee par un perso disparu.
local ownsLadder = false
-- Vrai pendant la sequence de repose (depli en cours) : empeche stopCarry de relacher trop tot (l'OPEN_EVENT le fera).
local placing = false
local lastEquipCheck = 0 -- throttle du test de proximite haie pour l'auto-equip
local lastActionAt = 0 -- instant de la derniere prise/repose, pour l'anti-spam de E (PICKUP_DEBOUNCE)

local LadderMoveController = {}

local function getRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Joue un son ponctuel a l'endroit de l'echelle (spatial). soundId vide = rien. On cree un Sound jetable sur une part
-- de l'echelle, on le joue, et Debris le detruit apres (garde-fou si Ended ne tire pas, ex : ID absent).
local function playLadderSound(soundId: string, ladder: Instance?)
	if soundId == "" then
		return
	end
	local host: BasePart? = if ladder and ladder:IsA("Model")
		then (ladder.PrimaryPart or ladder:FindFirstChildWhichIsA("BasePart", true))
		else nil
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = LADDER_SOUND_VOLUME
	sound.Parent = host or getRoot() -- a defaut d'echelle, sur le perso (le son reste audible)
	sound:Play()
	Debris:AddItem(sound, 5)
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

-- Input BRUT du joueur (camera-relatif) : X = pas de cote, Z = avant/arriere (negatif vers l'avant). On passe par le
-- module de controle car une fois qu'on contraint le deplacement avec humanoid:Move, humanoid.MoveDirection ne reflete
-- plus l'intention du joueur mais notre contrainte.
local function getMoveVector(): Vector3
	if not controlModule then
		local ok, result = pcall(function()
			local scripts = player:WaitForChild("PlayerScripts", 10)
			local playerModule = scripts and require(scripts:WaitForChild("PlayerModule", 10)) :: any
			return playerModule and playerModule:GetControls()
		end)
		if not (ok and result) then
			return Vector3.zero
		end
		controlModule = result
	end
	local ok, vector = pcall(function()
		return controlModule:GetMoveVector()
	end)
	return if ok and typeof(vector) == "Vector3" then vector else Vector3.zero
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

-- Z le plus vers le JOUEUR (bord ARRIERE de l'echelle) parmi ses parts STRUCTURELLES, exprime dans le repere carre.
-- Sert a reculer le joueur juste derriere l'echelle, quelle que soit sa taille. On parcourt les 8 coins de chaque part
-- (hors zones) : robuste a l'orientation du rig. Appele UNE fois a la 1re prise (capture de canonicalOffset).
local function ladderBackEdgeZ(ladder: Instance, square: CFrame): number
	local maxZ = -math.huge
	for _, part in ipairs(ladder:GetDescendants()) do
		if part:IsA("BasePart") and not isDetectionPart(part, ladder) then
			local half = part.Size * 0.5
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local corner = part.CFrame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
						maxZ = math.max(maxZ, square:PointToObjectSpace(corner).Z)
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
		local mv = getMoveVector()
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

		local mv = getMoveVector()
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

-- Demande au serveur la PROPRIETE de l'echelle : il la desancre et nous la donne, donc notre portage (PivotTo) et
-- notre repli se repliquent des lors a tous. On retient qu'on la possede, pour la relacher meme sur une mort.
-- PRISE : on demande au serveur de SOUDER l'echelle a notre HRP, avec l'offset c0 (place l'echelle devant nous).
-- Des lors elle suit le perso et se replique a tous, sans que le client ait a la positionner (le weld le fait).
local function grabCarry(ladder: Instance, c0: CFrame)
	ownsLadder = true
	if carryRemote then
		carryRemote:FireServer(ladder, true, c0)
	end
end

-- REPOSE : on demande au serveur de retirer le weld et de re-ancrer l'echelle ou elle est. Idempotent (garde ownsLadder).
local function releaseCarry(ladder: Instance)
	if not ownsLadder then
		return
	end
	ownsLadder = false
	if carryRemote then
		carryRemote:FireServer(ladder, false)
	end
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
	-- On ne touche PAS aux pistes de repli (foldTracks) ici : chaque echelle garde la sienne, qui tient sa pose
	-- (repliee ou depliee) jusqu'a la prochaine transition. La repose la reprend pour deplier.
	if carriedLadder then
		setLadderBeams(carriedLadder, true) -- l'echelle est reposee (ou on est mort) : la zone redevient visible
		-- Si on tient encore l'echelle et qu'on n'est PAS en repose normale (mort / respawn en plein portage), on la
		-- relache ici (retire le weld + re-ancre) : sinon on laisserait une echelle soudee a un perso disparu. En repose
		-- normale, placing=true : c'est l'OPEN_EVENT (fin du depli) qui relache, pour garder le weld pendant le depli.
		if ownsLadder and not placing then
			releaseCarry(carriedLadder)
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

-- Animator de l'ECHELLE (elle a son propre Humanoid). On le cree s'il manque : un rig anime en Studio a un
-- Humanoid mais pas forcement d'Animator a l'execution.
local function getModelAnimator(model: Instance): Animator?
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

-- REPOSE (2e appui sur E). On DEPLIE l'echelle. L'echelle est SOUDEE au perso pendant le depli (donc elle tient
-- toute seule et le depli se replique), et c'est l'OPEN_EVENT (fin du depli) qui relache : le serveur retire le weld
-- et re-ancre l'echelle sur place. Le weld la tient jusque-la : plus de pin, plus de chute possible.
local function placeLadder()
	local ladder = carriedLadder
	if not ladder then
		return
	end
	playLadderSound(PLACE_SOUND, ladder) -- son de repose
	local mt = foldTracks[ladder]
	if mt then
		placing = true -- empeche stopCarry de relacher : c'est l'OPEN_EVENT qui le fera, a la fin du depli
		stopCarry() -- debranche le rail + stoppe la pose ; ne relache pas (placing=true), le weld tient l'echelle
		playPlaceGesture()
		mt:AdjustSpeed(1) -- 0 depuis CLOSE_EVENT -> OPEN_EVENT : l'echelle se deplie, et l'OPEN_EVENT clot la repose
	else
		-- Pas de depli (echelle deja depliee, ou repose tres tot) : rien a attendre, on relache tout de suite.
		ladder:SetAttribute(CLOSED_ATTR, false)
		stopCarry() -- placing=false -> stopCarry relache lui-meme (retire le weld + re-ancre sur place)
		playPlaceGesture()
	end
end

-- Echelle dont le box_detecte_For_Move contient la position donnee, ou nil.
local function ladderAt(position: Vector3): Instance?
	-- GetDescendants (et pas GetChildren) : l'echelle reste detectee meme rangee dans un dossier d'organisation.
	-- Cout OK : ladderAt ne tourne qu'a l'appui sur E, pas chaque frame (contrairement a la grimpe, qui elle cache).
	for _, child in ipairs(workspace:GetDescendants()) do
		if child.Name:sub(1, #LADDER_PREFIX) == LADDER_PREFIX then
			local zone = child:FindFirstChild(MOVE_ZONE_NAME)
			if zone and zone:IsA("BasePart") then
				local rel = zone.CFrame:PointToObjectSpace(position)
				local half = zone.Size * 0.5
				-- On IGNORE Y (comme les zones de grimpe) : la zone n'a pas besoin d'englober le torse en hauteur, seul
				-- l'emplacement au sol (X/Z) compte. Tester Y faisait rater la detection quand la box etait basse.
				if math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z then
					return child
				end
			end
		end
	end
	return nil
end

local function pickUp(ladder: Instance)
	if carriedLadder then
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
	placing = false
	playLadderSound(PICKUP_SOUND, ladder) -- son de prise
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
		-- Offset CANONIQUE (pivot de l'echelle dans le repere carre), capture UNE seule fois (1re prise, echelle droite).
		-- On le REUTILISE ensuite : l'echelle est donc toujours reprise droite, meme si une pose libre l'a laissee de
		-- travers. On ANNULE le decalage lateral (X : echelle centree), on garde la hauteur (Y), la rotation captee, et
		-- on calcule la profondeur (Z) INTELLIGEMMENT : bord arriere de l'echelle a CARRY_CLEARANCE studs du joueur.
		if canonicalOffset == nil then
			local pivotInSquare = square0:ToObjectSpace(ladder:GetPivot())
			local p = pivotInSquare.Position
			local backOffset = ladderBackEdgeZ(ladder, square0) - p.Z -- distance pivot -> bord arriere (constante du rig)
			-- Le joueur est a Z=0, la haie vers -Z. On pose l'echelle a -Z pour que son bord arriere tombe a -CLEARANCE :
			-- le perso reste donc CARRY_CLEARANCE studs derriere l'echelle, jamais dedans, quelle que soit sa taille.
			canonicalOffset = CFrame.new(0, p.Y, -(CARRY_CLEARANCE + backOffset)) * pivotInSquare.Rotation
		end

		-- OFFSET DE SOUDURE (c0) : la CFrame de la RootPart a la position de portage voulue, exprimee dans le REPERE CARRE
		-- (face a la haie), PAS dans le HRP courant. C'est crucial : la soudure fige l'echelle relative au HRP, et le HRP
		-- fait face a la haie EN PORTAGE (le rail l'y tient). Si on prenait le HRP de la PRISE (pas encore tourne vers la
		-- haie), l'echelle finirait de travers une fois le joueur retourne. En calant sur le repere carre, l'echelle est
		-- alignee sur la haie des que le joueur l'est. Le serveur soude : RootPart = HRP.CFrame * c0.
		local desiredPivot = square0 * (canonicalOffset :: CFrame)
		local rootRelPivot = ladder:GetPivot():ToObjectSpace(ladderRoot.CFrame) -- constante du rig (racine vs pivot)
		local c0 = square0:ToObjectSpace(desiredPivot * rootRelPivot)
		grabCarry(ladder, c0) -- le serveur soude l'echelle a notre HRP : elle suit + se replique a tous
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

	-- 2. SYNCHRO : au marqueur TakeLadderEvent, l'echelle joue son REPLI, SAUF si elle est deja repliee (piste deja
	-- figee a CLOSE_EVENT). On charge la piste une fois par echelle et on branche ses DEUX marqueurs des maintenant :
	-- CLOSE_EVENT (fige replie a la prise) et OPEN_EVENT (stoppe deplie a la repose). Ils ne tirent qu'a la phase
	-- correspondante : le repli va 0 -> CLOSE_EVENT ; le depli ne repart que sur ordre de la repose (voir placeLadder).
	if takeConn then
		takeConn:Disconnect()
	end
	if not alreadyClosed then
		takeConn = track:GetMarkerReachedSignal(TAKE_EVENT):Connect(function()
			local modelAnimator = getModelAnimator(ladder)
			if not modelAnimator then
				warn("[LadderMove] Pas d'Animator sur l'echelle : repli impossible")
				return
			end
			local mt = loadTrack(modelAnimator, MODEL_ANIM)
			if not mt then
				return
			end
			foldTracks[ladder] = mt
			mt.Looped = false
			mt.TimePosition = 0
			mt:Play()
			mt:GetMarkerReachedSignal(CLOSE_EVENT):Connect(function()
				mt:AdjustSpeed(0) -- fige sur la pose repliee (ne se rouvre pas)
				ladder:SetAttribute(CLOSED_ATTR, true)
			end)
			mt:GetMarkerReachedSignal(OPEN_EVENT):Connect(function()
				mt:Stop(0.1) -- depliee : on lache l'anim, le rig revient a sa pose de repos (ouverte)
				foldTracks[ladder] = nil
				ladder:SetAttribute(CLOSED_ATTR, false)
				-- Fin du depli = fin de la repose : on demande au serveur de retirer le weld et de re-ancrer l'echelle
				-- sur place. C'est ICI qu'on relache, pas avant, pour que le depli se replique (echelle encore soudee).
				if placing then
					placing = false
					releaseCarry(ladder)
				end
			end)
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
		warn("[LadderMove] Remote Ladder/SetLadderCarry introuvable : le portage ne sera pas visible des autres joueurs")
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or input.KeyCode ~= TAKE_KEY then
			return
		end
		-- ANTI-SPAM : on ignore E s'il suit de trop pres la derniere prise/repose. Sinon un double-tap posait l'echelle
		-- avant que son repli ait joue, et l'anim etait zappee.
		if os.clock() - lastActionAt < PICKUP_DEBOUNCE then
			return
		end
		if carriedLadder then
			-- Deja en train de porter : ce 2e appui REPOSE l'echelle (deplie + arret du portage).
			lastActionAt = os.clock()
			placeLadder()
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
	end)

	-- Respawn / mort en plein portage : l'ancien perso est mort, on repart d'un etat propre (boucle de facing coupee,
	-- pistes lachees). Sans ca, le rail tournerait sur un root disparu et carriedLadder resterait bloque.
	player.CharacterAdded:Connect(function()
		stopCarry()
	end)

	-- AUTO-EQUIP DU TAILLE-HAIE en approchant une haie. Confort : plus besoin de l'equiper a la main avant de tailler.
	-- Garde-fous : jamais si on PORTE une echelle (on veut les mains libres pour l'echelle), jamais si l'outil est deja
	-- en main. On n'auto-DESEQUIPE pas (seul le portage range l'outil). ToggleTool sans outil en main = il equipe.
	RunService.Heartbeat:Connect(function()
		if os.clock() - lastEquipCheck < AUTO_EQUIP_INTERVAL then
			return
		end
		lastEquipCheck = os.clock()
		if carriedLadder or isTrimmerEquipped() or not toggleToolRemote then
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
