--!strict
-- DIDACTICIEL (place Tutorial uniquement). Pour l'instant : place le joueur au bon endroit ET DANS LE BON SENS. Le spawn par defaut
-- (SpawnLocationOriginal) est SOUS la map -- il sert au flow de la place principale (selection de plot). Ici on repose
-- le perso sur RootSpawnPlayer a CHAQUE spawn (mort comprise). Le deplacement se fait derriere le rideau de chargement,
-- donc invisible. La 1re haie guidee viendra s'ajouter ici plus tard.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local TutorialConfigs = require(ReplicatedStorage.Modules.Configs.TutorialConfigs)

local TutorialService = {}

local SPAWN_PATH = { "Worlds", "Maps", "RootSpawnPlayer" } -- le point de spawn voulu, dans la map du tuto
local SPAWN_HEIGHT = 4 -- studs au-dessus du point, pour ne pas clipper dans la part

local function findSpawn(): BasePart?
	local current: Instance = Workspace
	for _, name in SPAWN_PATH do
		local child = current:FindFirstChild(name)
		if not child then
			return nil
		end
		current = child
	end
	return if current:IsA("BasePart") then current else nil
end

local function placeCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not (root and root:IsA("BasePart")) then
		return
	end
	local spawn = findSpawn()
	if not spawn then
		warn(`[Tutorial] Point de spawn introuvable : Workspace.{table.concat(SPAWN_PATH, ".")}`)
		return
	end
	-- On garde le CAP de la part (sa rotation autour de la verticale) et on JETTE son inclinaison : le joueur regarde
	-- donc dans le sens ou la part est tournee -- vers la maison du grand-pere -- sans risquer d'etre couche si elle
	-- est posee de travers. Reprendre la CFrame entiere ferait exactement ce degat.
	local _, yaw = spawn.CFrame:ToEulerAnglesYXZ()
	character:PivotTo(
		CFrame.new(spawn.Position + Vector3.new(0, SPAWN_HEIGHT, 0)) * CFrame.fromEulerAnglesYXZ(0, yaw, 0)
	)
end

-- Cherche un objet par son NOM dans tout le Workspace. Comme le fait le client pour la porte : on ne suppose
-- aucun rangement, parce qu'obliger a ranger un objet au bon endroit pour qu'il fonctionne est un piege qui a
-- deja coute plusieurs diagnostics dans ce projet.
local function findByName(name: string): Instance?
	for _, d in Workspace:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

-- Vrai tant que le grand-pere marche : la scene peut se terminer plusieurs fois (rejouee, ou un second joueur),
-- et deux marches en parallele se disputeraient le meme modele.
local walking = false

-- Hauteur du sol sous un point, ou nil si on ne trouve rien.
local function groundAt(position: Vector3, ignore: { Instance }): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position, Vector3.new(0, -TutorialConfigs.OLDMAN_WALK_GROUND_RAY, 0), params)
	return if hit then hit.Position.Y else nil
end

-- ===== EST-CE QUE L'ANIMATION BOUGE VRAIMENT LE RIG ? =====
--
-- Une piste peut se charger, se jouer, afficher une longueur correcte, et n'ecrire STRICTEMENT RIEN. C'est ce
-- qui arrive quand ses poses portent des noms qui ne correspondent a aucune partie du rig : Roblox joue avec un
-- poids de 1 et ne trouve personne a qui parler. Aucune erreur, aucun warning, un personnage fige.
--
-- On ne peut donc pas se fier a "la piste joue" : il faut regarder le RESULTAT. Les animations ecrivent dans
-- `Transform`, jamais dans `C0` -- et les deux familles de rig en ont un : `Motor6D` pour un modele assemble,
-- `Bone` pour un skinned mesh. Ne balayer qu'une des deux fait crier au faux probleme sur l'autre.
local function jointPose(model: Model): { CFrame }
	local pose: { CFrame } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("Bone") then
			table.insert(pose, d.Transform)
		end
	end
	return pose
end

-- Deux poses different-elles ? On compare la position ET l'orientation : une articulation peut tourner sur place
-- sans que son origine bouge d'un poil, et on conclurait a tort qu'elle est morte.
local function poseMoved(before: { CFrame }, after: { CFrame }): boolean
	if #before == 0 or #before ~= #after then
		return false
	end
	for index, one in before do
		local other = after[index]
		if (one.Position - other.Position).Magnitude > 1e-3 then
			return true
		end
		if one.RightVector:Dot(other.RightVector) < 0.9999 or one.UpVector:Dot(other.UpVector) < 0.9999 then
			return true
		end
	end
	return false
end

-- REMET LE GRAND-PERE SUR SON IDLE, une fois arrive -- et c'est LE TUTO qui decide, pas l'ambiance.
--
-- DEUX SERVICES DECLARENT SON IDLE, et ils ont fini par diverger. `AmbientAnimService` en lance un au demarrage
-- (un ID ecrit dans sa config, sous la cle du NOM du modele) ; ici on en a un second, une Instance Animation
-- rangee dans ReplicatedStorage. L'ancienne version s'effacait devant celui qui jouait deja -- donc l'ambiance
-- gagnait TOUJOURS, et l'idle du tuto ne jouait JAMAIS.
--
-- A l'ecran ca ne ressemble pas du tout a un conflit de services : ca ressemble a une animation mal faite. La
-- canne revient au centre parce qu'elle n'est pas clee dans CELLE qui joue, et on part regler l'animation.
--
-- Pendant la scene, le grand-pere appartient au tuto : on coupe les autres idles avant de poser le notre. A
-- priorite EGALE Roblox ne choisit pas, il MELANGE : en laisser une donnerait la moyenne des deux, ce qui se lit
-- encore comme "l'animation ne joue pas completement". Une seule piste, un seul ecrivain.
--
-- MAIS ON CHARGE AVANT DE COUPER, et l'ordre inverse a coute une regression complete : couper d'abord puis
-- echouer a charger laissait le grand-pere SANS AUCUNE animation, fige debout. `LoadAnimation` ne DEMARRE rien,
-- il prepare la piste -- il n'y avait donc jamais de risque de melange a charger en premier, seulement un risque
-- de tout perdre a couper en premier. Regle : ne jamais detruire l'etat courant avant d'avoir en main de quoi le
-- remplacer.
--
-- ET ON VERIFIE LE RESULTAT. Une piste peut se charger, se jouer, et n'ecrire STRICTEMENT RIEN : asset jamais
-- telecharge (sa longueur reste a zero), ou noms de poses qui ne correspondent a aucune part du rig. Dans les
-- deux cas rien ne remonte, et on va chercher le bug du cote de l'animation. On repose donc l'idle d'ambiance
-- plutot que de laisser une statue.
--
-- On NOMME ce qu'on coupe et ce qu'on pose, avec les IDs : quand les deux se revelent identiques, c'est que
-- l'Instance de ReplicatedStorage pointe encore sur l'ancienne animation -- et ca, aucune sonde qui compte des
-- pistes ne peut le dire.
local function restoreIdle(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if not animator then
		return
	end

	local node: Instance? = ReplicatedStorage:FindFirstChild("Animations")
	for _, name in TutorialConfigs.OLDMAN_IDLE_PATH do
		node = node and node:FindFirstChild(name)
	end
	if not (node and node:IsA("Animation")) then
		warn(
			`[Tutorial] Idle introuvable : ReplicatedStorage.Animations.`
				.. `{table.concat(TutorialConfigs.OLDMAN_IDLE_PATH, ".")}. Le grand-pere gardera l'idle d'ambiance.`
		)
		return
	end
	local idle = node :: Animation

	-- 0) EST-CE QUE C'EST DEJA LA BONNE ? Les deux services peuvent tres bien designer la MEME animation : ici
	-- l'Instance de ReplicatedStorage et l'ID d'AmbientAnimConfigs pointaient sur le meme asset. Couper la piste
	-- pour recharger le meme fichier ne peut rien ameliorer, et ca ne peut que casser -- c'est exactement ce qui a
	-- fige le grand-pere. On ne remplace jamais quelque chose par lui-meme.
	for _, playing in (animator :: Animator):GetPlayingAnimationTracks() do
		local source = playing.Animation
		if
			playing.Priority == Enum.AnimationPriority.Idle
			and source
			and source.AnimationId == idle.AnimationId
		then
			print(`[Tutorial] Idle du grand-pere : {idle.AnimationId} joue deja, rien a faire.`)
			return
		end
	end

	-- 1) CHARGER. Rien ne joue encore, donc rien a melanger. Si ca rate, on sort SANS avoir touche a l'existant :
	-- le grand-pere garde l'idle d'ambiance, ce qui est moche mais vivant.
	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(idle)
	end)
	if not (ok and typeof(result) == "Instance") then
		warn(
			`[Tutorial] Idle du grand-pere non chargeable ({idle.AnimationId}). `
				.. "Il garde l'idle d'ambiance. Verifie que cette Animation existe et t'appartient."
		)
		return
	end
	local track = result :: AnimationTrack

	-- 2) COUPER, en gardant les pistes sous la main : c'est ce qui permet de les REMETTRE si la notre ne donne rien.
	local stopped: { AnimationTrack } = {}
	local stoppedIds: { string } = {}
	for _, playing in (animator :: Animator):GetPlayingAnimationTracks() do
		if playing.Priority == Enum.AnimationPriority.Idle and playing ~= track then
			local source = playing.Animation
			table.insert(stoppedIds, if source then source.AnimationId else playing.Name)
			table.insert(stopped, playing)
			playing:Stop()
		end
	end

	-- 3) POSER LA NOTRE.
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Idle
	track:Play()

	-- 4) MESURER LE RESULTAT, pas l'intention. On regarde si les articulations BOUGENT vraiment, en relevant leur
	-- pose deux fois a un court intervalle. Deux causes tombent d'un coup : l'asset jamais telecharge (longueur a
	-- zero) ET l'animation qui joue dans le vide (noms de poses etrangers au rig). Dans les deux cas on repose
	-- l'idle d'ambiance : un grand-pere qui respire mal vaut mieux qu'une statue.
	task.delay(TutorialConfigs.OLDMAN_IDLE_CHECK, function()
		if not model.Parent then
			return
		end
		-- Deux releves A L'INSTANT DU CONTROLE, pas un avant / un apres : sur une boucle, la pose de depart peut
		-- revenir a l'identique et faire croire a tort que rien ne bouge.
		local before = jointPose(model)
		task.wait(TutorialConfigs.OLDMAN_IDLE_SAMPLE)
		if not model.Parent then
			return
		end
		local joints = #before
		-- UNE PISTE PLUS FORTE PAR-DESSUS REND CE CONTROLE AVEUGLE. L'explication (priorite Action) bouge les memes
		-- articulations : "ca bouge" ne prouve donc plus que c'est l'IDLE qui ecrit. On ne conclut alors que sur ce
		-- qu'on peut encore prouver -- le chargement -- au lieu de rendre un OK qu'on n'a pas mesure.
		local covered = false
		for _, playing in (animator :: Animator):GetPlayingAnimationTracks() do
			if playing ~= track and playing.Priority.Value > Enum.AnimationPriority.Idle.Value then
				covered = true
				break
			end
		end
		if track.Length > 0 and (covered or poseMoved(before, jointPose(model))) then
			return -- ca joue, et soit ca bouge, soit une autre piste nous empeche de le dire
		end

		if track.Length <= 0 then
			warn(
				`[Tutorial] L'idle {idle.AnimationId} n'a jamais charge apres `
					.. `{TutorialConfigs.OLDMAN_IDLE_CHECK} s : on remet l'idle d'ambiance. `
					.. "Cet ID est faux, ou l'animation n'appartient pas au proprietaire du jeu."
			)
		else
			-- LE DIAGNOSTIC PRECIS, celui qui a coute des heures sur le grand-pere la premiere fois.
			warn(
				`[Tutorial] L'idle {idle.AnimationId} JOUE (longueur {string.format("%.2f", track.Length)} s) mais `
					.. `n'ecrit RIEN sur les {joints} articulations de "{model.Name}". Ses poses portent des noms que `
					.. "ce rig n'a pas. Compare-les avec scripts/studio/ComparerAnimEtRig.lua. On remet l'ambiance."
			)
		end
		track:Stop()
		for _, previous in stopped do
			previous:Play()
		end
	end)

	print(
		`[Tutorial] Idle du grand-pere : {idle.AnimationId} `
			.. `(remplace {#stoppedIds} : {if #stoppedIds > 0 then table.concat(stoppedIds, ", ") else "aucune"})`
	)
end

-- IL EXPLIQUE AVEC LES BRAS. Elle demarre DES SES PREMIERS PAS et se superpose a la marche : il raconte deja son
-- affaire en traversant sa cour, au lieu d'attendre d'etre plante devant sa porte pour commencer a vivre.
--
-- LA SUPERPOSITION TIENT A LA PRIORITE. La marche est en `Movement`, l'explication en `Action` : Action gagne sur
-- les membres qu'elle CLE, et laisse les autres a la marche. Une explication qui clerait aussi les jambes
-- ecraserait donc le pas -- c'est la meme regle que les poses de maintien d'outil, qui ne clent que bras et
-- torse. Et l'idle, en `Idle`, continue de tourner sous les deux.
--
-- LE SERVEUR TIENT CETTE PISTE, comme la marche : le grand-pere est un modele du monde et non le personnage d'un
-- joueur. Jouee cote client, elle ne se verrait que chez celui qui l'a lancee.
--
-- SA DUREE EST LA SOMME DES `hold` DE LA REPLIQUE, jamais un chiffre pose a la main : la config est partagee, donc
-- reenregistrer la voix (et rebouger les `hold`) rallonge la piste toute seule. Et elle part au meme instant que
-- la voix -- SPEECH2_DELAY, le souffle qu'il prend en arrivant -- pour ne pas gesticuler dans le silence.
local talkTrack: AnimationTrack? = nil
-- LE MODELE QU'ON ANIME, retenu des qu'on l'a trouve. Les repliques arrivent par remote a n'importe quel moment :
-- sans lui, il faudrait re-balayer le Workspace a chaque phrase.
local talkModel: Model? = nil
-- QUI JOUE LA SCENE, et le remote qui lui dira que le marqueur est tombe.
--
-- ON RETIENT LE JOUEUR. Le marqueur arrive d'une piste d'animation, et une piste ne sait pas pour qui elle joue :
-- envoyer a tout le monde ferait apparaitre la consigne chez quelqu'un qui n'a pas encore vu la scene.
local sceneOwner: Player? = nil
local focusRemote: RemoteEvent? = nil

local function playTalk(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if not animator then
		return -- restoreIdle a deja prevenu : sans Animator il n'y a aucune animation du tout
	end

	-- DEJA EN TRAIN DE JOUER : on ne fait RIEN. Elle est rappelee a chaque replique, et la relancer couperait le
	-- geste en cours pour le redemarrer -- un a-coup a chaque phrase, alors qu'on veut justement qu'il continue.
	local current = talkTrack
	if current and current.IsPlaying then
		return
	end
	-- Une piste chargee mais arretee (replique precedente finie) : on la ferme avant d'en poser une neuve. Deux
	-- pistes a priorite EGALE ne se choisissent pas, Roblox les MELANGE.
	if current then
		current:Stop(TutorialConfigs.OLDMAN_TALK_FADE)
		talkTrack = nil
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = TutorialConfigs.OLDMAN_TALK_ANIM
	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if not (ok and typeof(result) == "Instance") then
		warn(
			`[Tutorial] Explication non chargeable ({TutorialConfigs.OLDMAN_TALK_ANIM}). `
				.. "Il parlera sans bouger les bras."
		)
		return
	end
	local track = result :: AnimationTrack
	track.Looped = TutorialConfigs.OLDMAN_TALK_LOOP
	track.Priority = TutorialConfigs.OLDMAN_TALK_PRIORITY
	talkTrack = track

	-- ON ECOUTE SON MARQUEUR. Branche AVANT `Play` : une connexion posee apres pourrait rater un marqueur place
	-- tout au debut de la piste.
	--
	-- LA PISTE BOUCLE tant qu'il parle, donc il retombe a chaque tour : on compte les tours, sinon trois lignes
	-- identiques dans la console ressemblent a un bug plutot qu'a une boucle qui fait son travail.
	local hits = 0
	track:GetMarkerReachedSignal(TutorialConfigs.END_FOCUS_EVENT):Connect(function()
		hits += 1
		print(
			`[Tutorial] {TutorialConfigs.END_FOCUS_EVENT} (tour {hits}) a `
				.. `{string.format("%.2f", track.TimePosition)} s sur {string.format("%.2f", track.Length)} s`
		)
		-- ET C'EST ICI QUE LA CONSIGNE ARRIVE CHEZ LE JOUEUR. Le marqueur est le seul endroit qui sache ou en est
		-- ce geste : une duree calculee de notre cote se decalerait a la premiere retouche de l'animation, et
		-- c'est exactement ce qu'on vient de supprimer ailleurs.
		--
		-- Il retombe a chaque replique, puisque la piste rejoue en entier a chaque fois : c'est le CLIENT qui se
		-- garde des doublons, et il le fait deja pour son bandeau de tache.
		local remote, owner = focusRemote, sceneOwner
		if remote and owner and owner.Parent then
			remote:FireClient(owner)
		end
	end)

	-- ELLE SE LIBERE QUAND ELLE FINIT. Sans ca, `talkTrack` garderait une piste morte, et le prochain appel la
	-- croirait encore en place : il la couperait pour rien avant d'en charger une neuve.
	track.Stopped:Connect(function()
		if talkTrack == track then
			talkTrack = nil
		end
	end)

	track:Play(TutorialConfigs.OLDMAN_TALK_FADE)
	print(`[Tutorial] Explication du grand-pere : {TutorialConfigs.OLDMAN_TALK_ANIM}`)

	-- ===== POURQUOI LE MARQUEUR NE TIRE PAS : ON MESURE, ON NE DEVINE PAS =====
	-- Deux causes possibles, et elles se corrigent a deux endroits opposes :
	--   1) le marqueur n'est PAS dans l'asset publie -- ajoute dans l'editeur mais l'animation n'a pas ete
	--      republiee, ce qui est le cas le plus courant et le plus invisible ;
	--   2) il y est, mais APRES l'endroit ou la lecture s'arrete -- pose a 14.7 s dans une piste qu'on ne joue
	--      que 12 s, il ne peut pas tomber.
	--
	-- Un "ca ne marche pas" ne separe pas les deux. Ces deux mesures, oui.
	task.spawn(function()
		local deadline = os.clock() + 8
		while track.Length <= 0 and os.clock() < deadline do
			task.wait(0.2)
		end
		print(`[Tutorial] piste d'explication : {string.format("%.2f", track.Length)} s de long`)

		-- LES MARQUEURS REELLEMENT PRESENTS dans l'asset. `GetKeyframeSequenceAsync` est un appel RESEAU
		-- capricieux -- le journal du projet le dit -- donc pcall et rien de casse s'il rate : c'est un
		-- diagnostic, pas une dependance.
		local ok, seq = pcall(function()
			return game:GetService("KeyframeSequenceProvider")
				:GetKeyframeSequenceAsync(TutorialConfigs.OLDMAN_TALK_ANIM)
		end)
		if not (ok and typeof(seq) == "Instance") then
			print("[Tutorial] marqueurs de l'explication : lecture impossible (appel reseau rate)")
			return
		end
		local found: { string } = {}
		for _, kf in (seq :: Instance):GetChildren() do
			if kf:IsA("Keyframe") then
				for _, m in kf:GetChildren() do
					if m:IsA("KeyframeMarker") then
						table.insert(found, `{m.Name}@{string.format("%.2f", (kf :: Keyframe).Time)}s`)
					end
				end
			end
		end
		if #found == 0 then
			print("[Tutorial] marqueurs de l'explication : AUCUN dans l'asset publie.")
		else
			print(`[Tutorial] marqueurs de l'explication : {table.concat(found, ", ")}`)
		end
	end)
end

-- IL SE MET A EXPLIQUER, et l'animation va jusqu'au bout. Appelee par la marche et par chaque replique.
--
-- PLUS AUCUN MINUTEUR. La piste n'est plus bouclee : elle se relache a sa derniere image, donc elle porte
-- elle-meme sa duree -- c'est ce qui permet a son marqueur de 14.92 s d'etre atteint. Toute la machinerie qui
-- calculait "jusqu'a quand il parle" pour la couper a disparu avec, et deux choses qui ne peuvent plus se
-- contredire valent mieux qu'un calcul juste.
local function talkFor(model: Model)
	talkModel = model
	playTalk(model)
end

-- LE GRAND-PERE SORT DE CHEZ LUI. Il glisse jusqu'a la part posee dans Studio, puis se repose sur son idle.
--
-- ON LE DEPLACE PAR LE CODE, pas par `Humanoid:MoveTo`. Son rig doit rester ANCRE, et Roblox REFUSE de deplacer
-- une part ancree : `MoveTo` partait, ne bougeait rien, et rendait "chemin barre" au bout de son delai. Ce n'est
-- pas un contournement -- pour un personnage de scene qui suit un trajet decide a l'avance, un glissement est
-- plus SUR qu'un pathfinding : il ne peut ni s'accrocher a un meuble ni tomber d'un bord.
--- Fait marcher le grand-pere jusqu'a la part `targetName`, puis appelle `onDone`.
---
--- La cible est un PARAMETRE et non une constante : le meme trajet sert deux fois -- sortir de chez lui, puis
--- descendre du perron -- et deux copies de cette fonction finiraient par diverger.
---
--- `onStart` tire quand il se met REELLEMENT en marche, c'est-a-dire une fois tous les controles passes. Un
--- appelant qui lancerait son geste avant saurait seulement qu'il l'a DEMANDE : le modele peut etre introuvable,
--- la cible absente, une marche deja en cours -- et le geste partirait dans le vide.
local function walkOldMan(targetName: string, onDone: ((Model) -> ())?, onStart: ((Model) -> ())?)
	if walking then
		return
	end

	local model = findByName(TutorialConfigs.GRANDPA_NAME)
	if not (model and model:IsA("Model")) then
		warn(`[Tutorial] "{TutorialConfigs.GRANDPA_NAME}" introuvable : il ne sortira pas de chez lui.`)
		return
	end
	local target = findByName(targetName)
	if not (target and target:IsA("BasePart")) then
		warn(
			`[Tutorial] Aucune part "{targetName}" dans le Workspace : le grand-pere n'a `
				.. "nulle part ou aller. Rojo ne synchronise pas le Workspace, elle doit exister dans CETTE place."
		)
		return
	end
	-- On se cale sur une PART REELLE et pas sur `GetPivot` : sans PrimaryPart, le pivot d'un Model suit sa BOITE
	-- ENGLOBANTE, qu'un simple accessoire ajoute dans Studio suffit a decaler.
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		warn(`[Tutorial] "{model.Name}" n'a pas de part nommee "HumanoidRootPart" : renomme sa RootPart ainsi.`)
		return
	end
	local rootPart = root :: BasePart
	local targetPart = target :: BasePart

	local from = rootPart.CFrame
	local flat = Vector3.new(targetPart.Position.X - from.Position.X, 0, targetPart.Position.Z - from.Position.Z)
	if flat.Magnitude < 0.1 then
		return -- deja arrive : on ne fabrique pas un trajet pour rien
	end

	-- SA HAUTEUR AU-DESSUS DU SOL, mesuree et rendue a l'arrivee. Il est ancre, donc rien ne le repose : un sol
	-- qui monte ou descend entre les deux le ferait s'enfoncer ou leviter.
	local ignore = { model }
	local startGround = groundAt(from.Position, ignore)
	local endGround = groundAt(Vector3.new(targetPart.Position.X, from.Position.Y, targetPart.Position.Z), ignore)
	local endY = if startGround and endGround then from.Position.Y + (endGround - startGround) else from.Position.Y
	local to = CFrame.lookAt(
		Vector3.new(targetPart.Position.X, endY, targetPart.Position.Z),
		Vector3.new(targetPart.Position.X, endY, targetPart.Position.Z) + flat.Unit
	)

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil

	walking = true

	-- L'ANIMATION EST FACULTATIVE : sans elle il glisse sans bouger les jambes, mais il arrive. On ne bloque pas
	-- une scene pour un asset manquant.
	local track: AnimationTrack? = nil
	if animator then
		local anim = Instance.new("Animation")
		anim.AnimationId = TutorialConfigs.OLDMAN_WALK_ANIM
		local ok, result = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		if ok and typeof(result) == "Instance" then
			local t = result :: AnimationTrack
			t.Looped = true
			t.Priority = TutorialConfigs.OLDMAN_WALK_PRIORITY
			t:Play()
			-- Jouee au RAPPORT des deux vitesses : changer sa vitesse de marche ne fait pas patiner ses pieds, et
			-- il n'y a aucune seconde valeur a garder d'accord avec la premiere.
			--
			-- Le BOOST se multiplie par-dessus : il accelere les jambes SANS toucher au trajet, qui est calcule
			-- ailleurs sur la distance. Les deux restent donc reglables separement -- un seul chiffre pour les
			-- deux aurait force a compenser l'un en tournant l'autre.
			t:AdjustSpeed(
				TutorialConfigs.OLDMAN_WALK_SPEED
					/ TutorialConfigs.OLDMAN_WALK_REFERENCE
					* TutorialConfigs.OLDMAN_WALK_ANIM_BOOST
			)
			track = t
		end
	else
		warn(`[Tutorial] Pas d'Animator sous "{model.Name}" : il marchera sans animation.`)
	end

	-- LA DUREE VIENT DE LA DISTANCE, jamais d'un chiffre pose a la main : deplacer la part dans Studio suffit
	-- alors a rallonger le trajet, et ses pieds restent d'accord avec son deplacement quoi qu'on change.
	local seconds = flat.Magnitude / math.max(TutorialConfigs.OLDMAN_WALK_SPEED, 0.1)

	if onStart then
		onStart(model :: Model)
	end

	task.spawn(function()
		local t0 = os.clock()
		while true do
			local e = math.clamp((os.clock() - t0) / seconds, 0, 1)
			if not model.Parent then
				break -- detruit en chemin (changement de place, rechargement) : plus rien a deplacer
			end
			-- ON APPLIQUE UN ECART MONDE, pas un pivot : `PivotTo` passe par `GetPivot`, decale des qu'on ajoute
			-- un enfant au modele. En composant l'ecart de la RACINE, on ne depend d'aucun pivot.
			--
			-- LINEAIRE, sans adoucissement : une marche a vitesse constante est ce qu'on attend d'un personnage
			-- qui traverse une piece. Une courbe le ferait accelerer puis ralentir, et ses pieds patineraient aux
			-- deux bouts -- l'animation, elle, tourne a vitesse fixe.
			local now = from:Lerp(to, e)
			model:PivotTo(now * rootPart.CFrame:Inverse() * model:GetPivot())
			if e >= 1 then
				break
			end
			task.wait()
		end
		-- ON ARRETE LA MARCHE, PUIS on joue son arrivee. L'ordre compte : la marche est en priorite Movement, donc
		-- plus forte que l'idle -- la laisser tourner masquerait completement la pose qu'on vient de mettre.
		if track then
			(track :: AnimationTrack):Stop()
		end
		-- WALKING RETOMBE AVANT LA SUITE : elle peut relancer une marche, et le garde la bloquerait.
		walking = false
		if onDone then
			onDone(model)
		end
	end)
end


local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(placeCharacter)
	if player.Character then
		placeCharacter(player.Character)
	end
end

function TutorialService.init()
	local done = RemoteSetup.getRemote("TutorialSceneDone", "Tutorial") :: RemoteEvent
	focusRemote = RemoteSetup.getRemote("TutorialFocusDone", "Tutorial") :: RemoteEvent

	done.OnServerEvent:Connect(function(player)
		sceneOwner = player
		-- Aucun argument a valider : le client ne fait que dire "la scene est finie". Le pire qu'il puisse faire
		-- est de la declencher trop tot, ce qui fait sortir le grand-pere -- pas de quoi tricher.
		walkOldMan(TutorialConfigs.OLDMAN_WALK_TARGET, function(model)
			restoreIdle(model)
			-- IL CONTINUE D'EXPLIQUER. Rien a calculer : la piste va jusqu'a sa derniere image, et si elle tourne
			-- deja depuis son premier pas, cet appel ne la relance pas.
			talkFor(model)
		end, function(model)
			-- IL PARLE EN MARCHANT. Lancee ici, au premier pas, elle se superpose a la marche au lieu d'attendre
			-- qu'il soit arrete.
			talkFor(model)
		end)
	end)

	-- IL GESTICULE QUAND IL PARLE. Le client ne fait que declencher : aucun argument, donc rien a valider -- ce
	-- qui vaut toujours mieux que borner une valeur venue de lui.
	local talkRemote = RemoteSetup.getRemote("OldManTalk", "Tutorial") :: RemoteEvent
	talkRemote.OnServerEvent:Connect(function()
		local model = talkModel or findByName(TutorialConfigs.GRANDPA_NAME)
		if model and model:IsA("Model") then
			talkFor(model)
		end
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return TutorialService
