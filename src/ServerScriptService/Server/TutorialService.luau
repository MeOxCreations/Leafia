--!strict
-- DIDACTICIEL (place Tutorial uniquement). Pour l'instant : place le joueur au bon endroit ET DANS LE BON SENS. Le spawn par defaut
-- (SpawnLocationOriginal) est SOUS la map -- il sert au flow de la place principale (selection de plot). Ici on repose
-- le perso sur RootSpawnPlayer a CHAQUE spawn (mort comprise). Le deplacement se fait derriere le rideau de chargement,
-- donc invisible. La 1re haie guidee viendra s'ajouter ici plus tard.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarryUtils = require(ReplicatedStorage.Modules.Utils.CarryUtils)
local MowConfigs = require(ReplicatedStorage.Modules.Configs.MowConfigs)
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
-- DECLAREE ICI, DEFINIE PLUS BAS. Le marqueur de son animation la declenche, et cette ecoute se branche dans
-- `playTalk` -- tout en haut du fichier -- alors que le suivi a besoin de `groundAt` et de la config de marche,
-- donc il ne peut pas etre ecrit avant. On ne cite jamais une fonction avant sa definition.
local startFollow: ((Player, Model) -> ())? = nil

--- Rend VRAI si elle vient de lancer une piste neuve, faux si une lecture etait deja en cours.
---
--- L'appelant s'en sert pour savoir s'il a le droit de decider de la FIN : celui qui n'a pas demarre la piste ne
--- doit pas la couper -- une phrase d'impatience arrivee pendant la grande explication l'amputerait de son
--- marqueur.
local function playTalk(model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if not animator then
		return false -- restoreIdle a deja prevenu : sans Animator il n'y a aucune animation du tout
	end

	-- DEJA EN TRAIN DE JOUER : on ne fait RIEN. Elle est rappelee a chaque replique, et la relancer couperait le
	-- geste en cours pour le redemarrer -- un a-coup a chaque phrase, alors qu'on veut justement qu'il continue.
	local current = talkTrack
	if current and current.IsPlaying then
		return false
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
		return false
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
			-- ET IL EMBOITE LE PAS. La consigne vient d'etre donnee : a partir de maintenant il accompagne le
			-- joueur jusqu'a ce que la machine soit dans ses mains.
			--
			-- `startFollow` sort tout seul si une boucle tourne deja, donc ce marqueur qui retombe a chaque
			-- replique n'en lance pas une seconde.
			local follow = startFollow
			if follow then
				follow(owner, model)
			end
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
	return true
end

-- IL SE MET A EXPLIQUER. `seconds` borne le geste ; sans elle, l'animation va jusqu'a sa derniere image.
--
-- DEUX USAGES, DEUX REGLES, et c'est tout l'objet de cet argument :
--   -- LA GRANDE EXPLICATION (sa marche, sa replique d'arrivee) joue EN ENTIER. Elle porte le marqueur qui
--      declenche la consigne du joueur, a 14.92 s : la couper avant, c'est ne jamais l'atteindre.
--   -- UNE PETITE REPLIQUE (impatience, "prends la tondeuse") dure ce que dure SON SON. Deux secondes de
--      phrase ne doivent pas lancer dix-sept secondes de gestes, sinon il continue de s'agiter longtemps apres
--      s'etre tu -- et ca se lit comme une animation oubliee.
--
-- SEUL CELUI QUI A DEMARRE LA PISTE DECIDE DE SA FIN. Une phrase d'impatience qui tomberait pendant la grande
-- explication l'amputerait de son marqueur, ce qui casserait la consigne -- alors qu'elle ne demandait qu'a
-- accompagner deux secondes de voix.
local function talkFor(model: Model, seconds: number?)
	talkModel = model
	local started = playTalk(model)
	if not (started and seconds and seconds > 0) then
		return
	end
	local track = talkTrack
	if not track then
		return
	end
	task.delay(seconds, function()
		-- On revalide : une autre lecture a pu prendre la place pendant la replique.
		if talkTrack ~= track then
			return
		end
		track:Stop(TutorialConfigs.OLDMAN_TALK_FADE)
		talkTrack = nil
	end)
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


-- ===== IL VA VERS LA TONDEUSE, LE JOUEUR AVEC =====
-- Une boucle par image, cote SERVEUR : le grand-pere est un objet du monde, il doit bouger pour tout le monde.
--
-- CE QU'IL VISE EST LA MACHINE, PAS LE JOUEUR. Une cible qui bouge a chaque image donne un PNJ collant, qui
-- repart et s'arrete des que l'autre change de pied -- un vieux monsieur ne fait pas ca. Ce qui l'interesse,
-- c'est la ou le travail va se faire ; le joueur s'y rend en meme temps que lui. Une cible FIXE donne un
-- deplacement lisse, sans qu'on ait rien a lisser.
--
-- IL RESTE QUAND MEME DERRIERE LE JOUEUR : deux gardes suffisent, l'un sur la distance a la machine, l'autre sur
-- la distance au joueur -- il s'arrete au premier des deux atteint.
--
-- ON LE DEPLACE PAR LE CODE, comme pour sa sortie, et pour la meme raison : son rig est ANCRE, et Roblox REFUSE
-- de deplacer une part ancree -- `Humanoid:MoveTo` partirait, ne bougerait rien, et rendrait "chemin barre" au
-- bout de son delai.
local followConn: RBXScriptConnection? = nil
local followTrack: AnimationTrack? = nil
local followGroundOffset = 0
local followStopped = false -- il est arrive : sert d'hysteresis, il faut REdepasser la distance pour repartir
-- LA MACHINE QU'IL VISE, GARDEE. On ne la re-cherche qu'a intervalle, et on ne CHANGE que si celle qu'on avait
-- ne fait plus l'affaire : re-choisir a chaque image faisait alterner la cible entre deux machines proches, donc
-- zigzaguer sur place.
local followMower: BasePart? = nil
local followScanAt = 0
-- LA VITESSE A LAQUELLE SA PISTE DE PAS EST REGLEE. Gardee pour ne la re-ajuster que quand elle change : il
-- marche a deux allures (vers la machine, puis en flanant), et des pieds restes a la cadence du suivi
-- patineraient pendant la promenade.
local followAnimSpeed = 0
-- OU IL SE PROMENE, et quand il repart. La cible est gardee d'une image sur l'autre : retiree a chaque image, il
-- en tirerait une nouvelle soixante fois par seconde et n'irait jamais nulle part.
local strollTarget: Vector3? = nil
local strollNextAt = 0
-- LE MOTEUR A-T-IL DEMARRE UNE FOIS ? Tant que non, il n'a qu'une idee en tete : la machine. Apres, son travail
-- est fini et il flane.
--
-- UN VERROU QUI NE SE ROUVRE PAS, comme son impatience qui s'eteint pour de bon au meme instant. Le joueur peut
-- reposer la tondeuse ensuite : le grand-pere n'a plus rien a lui demander, il ne doit pas retourner la chercher.
local engineStarted = false
local engineScanAt = 0
local walkZone: BasePart? = nil
local warnedZone = false

local function stopFollow()
	if followConn then
		followConn:Disconnect()
		followConn = nil
	end
	local track = followTrack
	followTrack = nil
	followMower = nil
	followAnimSpeed = 0
	strollTarget = nil
	engineStarted = false
	if track then
		-- L'idle tourne DESSOUS (priorite Idle contre Movement) : arreter le pas suffit a le remettre au repos,
		-- il n'y a rien a reposer.
		track:Stop(TutorialConfigs.FOLLOW_ANIM_FADE)
	end
end

-- Joue ou coupe son animation de pas, a l'allure DEMANDEE (en studs/s ; zero = arrete). Idempotent : appelee a
-- chaque image, elle ne relance rien et ne re-regle rien tant que rien ne change.
--
-- ELLE PREND UNE VITESSE ET PAS UN BOOLEEN, parce qu'il marche a deux allures : vers la machine, puis en flanant.
-- Une piste reglee une fois pour toutes garderait la cadence de la premiere et ses pieds patineraient dans la
-- seconde.
local function setFollowWalking(model: Model, speed: number)
	local moving = speed > 0
	local track = followTrack
	if not moving then
		if track and track.IsPlaying then
			track:Stop(TutorialConfigs.FOLLOW_ANIM_FADE)
		end
		return
	end
	if not track then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
		if not animator then
			return -- sans Animator il glissera sans bouger les jambes, mais il avancera
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = TutorialConfigs.OLDMAN_WALK_ANIM
		local ok, result = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		if not (ok and typeof(result) == "Instance") then
			return
		end
		track = result :: AnimationTrack
		track.Looped = true
		track.Priority = TutorialConfigs.OLDMAN_WALK_PRIORITY
		followTrack = track
	end
	-- Jouee au RAPPORT des deux vitesses, comme sa sortie : changer son allure ne fait pas patiner ses pieds, et
	-- il n'y a aucune seconde valeur a garder d'accord avec la premiere.
	if speed ~= followAnimSpeed then
		followAnimSpeed = speed
		track:AdjustSpeed(speed / TutorialConfigs.OLDMAN_WALK_REFERENCE * TutorialConfigs.FOLLOW_ANIM_BOOST)
	end
	if not track.IsPlaying then
		track:Play(TutorialConfigs.FOLLOW_ANIM_FADE)
	end
end

-- LA TONDEUSE LIBRE LA PLUS PROCHE DU JOUEUR. Meme critere que le repere affiche chez lui : les deux doivent
-- designer la MEME machine, sinon le grand-pere part vers une autre que celle qu'on montre au joueur.
--
-- Distance HORIZONTALE : une machine un etage plus bas n'est pas "loin", elle est ailleurs.
local function nearestFreeMower(from: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and d.Name == MowConfigs.MODEL_NAME and d:GetAttribute(MowConfigs.CARRIED_ATTRIBUTE) == nil then
			local root = d.PrimaryPart or d:FindFirstChild(MowConfigs.ROOT_NAME)
			if root and root:IsA("BasePart") then
				local flat = (root :: BasePart).Position - from
				local dist = math.sqrt(flat.X * flat.X + flat.Z * flat.Z)
				if dist < bestDist then
					bestDist, best = dist, root :: BasePart
				end
			end
		end
	end
	return best
end

-- La machine qu'il vise, gardee d'une image sur l'autre.
--
-- ON NE LA REMET EN QUESTION QUE SI ELLE NE FAIT PLUS L'AFFAIRE -- detruite, ou prise par quelqu'un -- et jamais
-- plus souvent que `FOLLOW_RESCAN`. Deux raisons, et la premiere est un bug qu'on vient de payer : re-choisir a
-- chaque image faisait alterner la cible entre deux machines a peu pres a egale distance, donc zigzaguer sur
-- place. La seconde est le cout : un balayage de tout le Workspace par image, pour une reponse qui ne change pas
-- soixante fois par seconde.
local function currentMower(from: Vector3): BasePart?
	local kept = followMower
	local usable = kept ~= nil
		and (kept :: BasePart).Parent ~= nil
		and (function(): boolean
			local model = (kept :: BasePart):FindFirstAncestorOfClass("Model")
			return model ~= nil and model:GetAttribute(MowConfigs.CARRIED_ATTRIBUTE) == nil
		end)()
	if usable and os.clock() < followScanAt then
		return kept
	end
	if not usable then
		followMower = nil
	end
	if os.clock() >= followScanAt then
		followScanAt = os.clock() + TutorialConfigs.FOLLOW_RESCAN
		-- ON NE CHANGE QUE SI ON N'EN A PLUS : une machine gardee reste la cible tant qu'elle est libre, meme si
		-- une autre devient plus proche. Sinon on retrouve l'alternance qu'on vient de supprimer.
		if not followMower then
			followMower = nearestFreeMower(from)
		end
	end
	return followMower
end

-- A-T-IL DEMARRE LA MACHINE QU'IL TIENT ?
--
-- BALAYAGE ET PAS UN REMOTE : l'etat est deja replique -- un attribut pose par MowService sur le modele -- donc
-- le demander au client serait une deuxieme source pour une question qui a deja sa reponse, et c'est ainsi que
-- deux verites finissent par se contredire.
--
-- ET IL NE TOURNE QUE QUELQUES SECONDES : entre la prise de la machine et le demarrage, a la cadence de
-- `FOLLOW_RESCAN`. Une fois vrai, la reponse est gardee pour de bon.
local function startedMower(player: Player): boolean
	for _, d in Workspace:GetDescendants() do
		if
			d:IsA("Model")
			and d.Name == MowConfigs.MODEL_NAME
			and d:GetAttribute(MowConfigs.CARRIED_ATTRIBUTE) == player.UserId
			and d:GetAttribute(MowConfigs.RUNNING_ATTRIBUTE) == true
		then
			return true
		end
	end
	return false
end

-- LA ZONE OU IL A LE DROIT DE SE PROMENER, gardee des qu'on l'a. RE-CHERCHEE tant qu'on ne l'a pas : avec le
-- streaming, une part posee dans Studio arrive apres le boot, et une reference resolue une seule fois resterait
-- vide pour toute la session.
local function strollZone(): BasePart?
	local kept = walkZone
	if kept and kept.Parent then
		return kept
	end
	walkZone = nil
	local found = findByName(TutorialConfigs.WALK_ZONE_NAME)
	if found and found:IsA("BasePart") then
		walkZone = found :: BasePart
	end
	return walkZone
end

-- UN POINT OU ALLER FLANER, ou nil si rien ne convient ce tour-ci.
--
-- TIRAGE ET REJET, pas un calcul. L'ensemble des points a la fois DANS la zone, a bonne distance du joueur, a
-- bonne distance de lui et POSES SUR DU SOL n'a aucune forme simple -- et il change des qu'on redimensionne la
-- zone dans Studio. Tirer puis refuser tient en quinze lignes et reste juste sans rien savoir de la geometrie.
local function pickStrollPoint(from: Vector3, playerPos: Vector3, ignore: { Instance }): Vector3?
	local zone = strollZone()
	if not zone then
		-- UNE SEULE FOIS. Un service qui balaye le monde doit dire ce qu'il n'a pas trouve : sans ce mot, le
		-- grand-pere reste simplement immobile et rien n'explique pourquoi.
		if not warnedZone then
			warnedZone = true
			warn(`[Tutorial] Aucune part "{TutorialConfigs.WALK_ZONE_NAME}" : le grand-pere ne se promenera pas.`)
		end
		return nil
	end
	local half = zone.Size * 0.5
	for _ = 1, TutorialConfigs.STROLL_TRIES do
		-- TIRE EN REPERE DE LA ZONE puis ramene au monde : elle peut etre tournee dans Studio sans que ce calcul
		-- ait a le savoir.
		local inZone = Vector3.new((math.random() * 2 - 1) * half.X, 0, (math.random() * 2 - 1) * half.Z)
		local point = zone.CFrame * inZone
		local toPlayer = (Vector3.new(point.X - playerPos.X, 0, point.Z - playerPos.Z)).Magnitude
		local toHere = (Vector3.new(point.X - from.X, 0, point.Z - from.Z)).Magnitude
		if
			toPlayer <= TutorialConfigs.STROLL_NEAR_PLAYER
			and toPlayer >= TutorialConfigs.FOLLOW_MIN_PLAYER
			and toHere >= TutorialConfigs.STROLL_MIN_DIST
		then
			-- LE SOL DECIDE EN DERNIER, et le rayon part du HAUT de la zone : elle est un volume, pas une surface.
			-- Un point tire au-dessus d'un trou ou d'un massif le ferait marcher dans le vide.
			local top = Vector3.new(point.X, zone.Position.Y + half.Y, point.Z)
			local ground = groundAt(top, ignore)
			if ground then
				return Vector3.new(point.X, ground + followGroundOffset, point.Z)
			end
		end
	end
	return nil
end

-- SA VIE APRES LA SCENE, en UNE boucle et une seule ecriture de pose. Deux raisons de marcher s'y relaient : la
-- machine tant qu'elle est par terre, une promenade ensuite. Deux boucles se battraient pour le meme modele.
startFollow = function(player: Player, model: Model)
	if followConn then
		return -- deja en route : une seconde boucle se battrait avec la premiere pour la meme pose
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		warn(`[Tutorial] "{model.Name}" n'a pas de HumanoidRootPart : il n'ira pas vers la tondeuse.`)
		return
	end
	local rootPart = root :: BasePart

	-- SA HAUTEUR AU-DESSUS DU SOL, mesuree UNE FOIS. Il est ancre, donc la physique ne le pose pas : sans cette
	-- mesure il faudrait deviner de combien lever son rig. Mesuree a chaque image, un sol qui manque (trou, bord
	-- de dalle) la ferait sauter.
	local ground = groundAt(rootPart.Position, { model })
	followGroundOffset = if ground then rootPart.Position.Y - ground else 0
	followStopped = false

	-- SON TEMPS DE REACTION. Il ne s'ebranle pas a la milliseconde ou la consigne tombe : ce retard est ce qui
	-- separe un vieux monsieur d'un chien de garde.
	local startAt = os.clock() + TutorialConfigs.FOLLOW_DELAY

	followConn = RunService.Heartbeat:Connect(function(dt: number)
		if not model.Parent or not player.Parent then
			stopFollow()
			return
		end
		local character = player.Character
		local hrpChild = character and character:FindFirstChild("HumanoidRootPart")
		if not (hrpChild and hrpChild:IsA("BasePart")) or os.clock() < startAt then
			setFollowWalking(model, 0)
			return -- mort, respawn, ou temps de reaction : on reste branche, on ne bouge pas
		end
		local hrp = hrpChild :: BasePart
		local here = rootPart.Position
		local now = os.clock()
		local ignore: { Instance } = { model }
		if character then
			table.insert(ignore, character)
		end
		local playerDist = (Vector3.new(hrp.Position.X - here.X, 0, hrp.Position.Z - here.Z)).Magnitude

		-- OU IL VA, A QUELLE ALLURE, ET A QUELLE DISTANCE IL S'ARRETE. Trois valeurs, un seul trajet en dessous :
		-- ecrire la marche deux fois, une par raison, finirait par les faire diverger.
		--
		-- LA MACHINE PASSE DEVANT. Tant qu'elle est par terre, c'est la seule chose qui compte pour lui -- la
		-- promenade est ce qu'il fait quand il n'a plus rien a demander.
		--
		-- On lit l'ETAT de ses mains (CarryUtils) et pas un evenement de prise : le joueur peut la prendre, la
		-- lacher, mourir, en reprendre une autre -- un evenement tire une fois nous laisserait sur une reponse
		-- perimee.
		local goal: Vector3? = nil
		local speed = 0
		local keepDist = 0
		local chasing = false
		local holding = CarryUtils.holds(player, "Mower")
		-- LE MOTEUR EST LA LIMITE ENTRE SES DEUX VIES. Avant, il pousse le joueur vers la machine ; apres, il
		-- flane. Il ne suffit pas que la tondeuse soit dans ses mains : tant qu'elle n'a pas demarre, le joueur
		-- est encore en train de tirer la corde, et voir le grand-pere s'eloigner a ce moment-la retire tout son
		-- poids a ce qu'il vient de demander.
		if not engineStarted and holding and now >= engineScanAt then
			engineScanAt = now + TutorialConfigs.FOLLOW_RESCAN
			engineStarted = startedMower(player)
			if engineStarted then
				-- IL REGARDE D'ABORD. Sans cette attente il tournerait les talons a la seconde ou le moteur prend,
				-- pendant qu'il dit "parfait" -- un compliment lance en s'en allant n'en est plus un.
				strollNextAt = now + TutorialConfigs.STROLL_WAIT_MIN
			end
		end
		if not engineStarted and not holding then
			-- LA MACHINE EST CHERCHEE DEPUIS LE JOUEUR, pas depuis lui : c'est celle vers laquelle le JOUEUR se
			-- dirige qui compte, et c'est aussi celle que son repere a l'ecran lui montre.
			local mower = currentMower(hrp.Position)
			if mower then
				goal, speed, chasing = mower.Position, TutorialConfigs.FOLLOW_SPEED, true
				-- `followStopped` fait l'hysteresis : sans elle, arrete pile a la distance d'arret, il repartirait
				-- au moindre centimetre.
				keepDist = TutorialConfigs.FOLLOW_MOWER_DIST
					+ (if followStopped then TutorialConfigs.FOLLOW_HYST else 0)
			end
		end
		-- ET S'IL TIENT LA MACHINE SANS L'AVOIR DEMARREE, rien des deux : il reste ou il est et le regarde
		-- s'acharner sur la corde. `goal` a nil donne un pas nul, donc le meme calcul en dessous.
		if not chasing and engineStarted then
			local target = strollTarget
			-- IL LAISSE TOMBER UNE CIBLE QUI S'ELOIGNE : le joueur marche pendant qu'il marche, et finir un
			-- trajet vers un coin que le joueur a quitte n'accompagne plus personne.
			if
				target
				and (Vector3.new(target.X - hrp.Position.X, 0, target.Z - hrp.Position.Z)).Magnitude
					> TutorialConfigs.STROLL_LEASH
			then
				target = nil
			end
			if not target and now >= strollNextAt then
				target = pickStrollPoint(here, hrp.Position, ignore)
				if not target then
					strollNextAt = now + TutorialConfigs.STROLL_RETRY
				end
			end
			strollTarget = target
			if target then
				goal, speed, keepDist = target, TutorialConfigs.STROLL_SPEED, TutorialConfigs.STROLL_ARRIVE
			end
		end

		local toGoal = if goal then Vector3.new(goal.X - here.X, 0, goal.Z - here.Z) else Vector3.zero
		local goalDist = toGoal.Magnitude

		-- IL EST ARRIVE, OU IL EST TROP PRES DU JOUEUR : il s'arrete.
		local arrived = goal == nil or goalDist <= keepDist or goalDist < 1e-3
		local crowded = playerDist <= TutorialConfigs.FOLLOW_MIN_PLAYER
		if chasing then
			-- L'HYSTERESIS NE SERT QU'A LA MACHINE. Lui faire porter la promenade la ferait repartir avec une
			-- distance d'arret qui n'est pas la sienne.
			followStopped = arrived or crowded
		elseif strollTarget and (arrived or crowded) then
			-- ARRIVE, OU LE JOUEUR LUI EST DANS LES PIEDS : il abandonne ce point et se repose un moment. Sans
			-- l'abandon, un joueur plante sur lui le figerait sur une cible qu'il ne peut plus atteindre.
			--
			-- L'attente est tiree au hasard : une cadence reguliere se lit comme une horloge, donc comme un
			-- systeme, pas comme quelqu'un qui flane.
			strollTarget = nil
			strollNextAt = now
				+ TutorialConfigs.STROLL_WAIT_MIN
				+ math.random() * (TutorialConfigs.STROLL_WAIT_MAX - TutorialConfigs.STROLL_WAIT_MIN)
		end

		-- OU IL AVANCE, ET DE COMBIEN. Arrete, le pas vaut zero : la suite du calcul est alors la meme, ce qui
		-- evite d'ecrire la pose a deux endroits differents -- et donc de les voir diverger.
		local step = 0
		if not (arrived or crowded) then
			-- `dt` fait que la vitesse est la meme quel que soit le nombre d'images, et on ne depasse jamais la
			-- distance d'arret.
			step = math.min(speed * dt, goalDist - keepDist)
		end
		local nextPos = if step > 0 then here + toGoal.Unit * step else here
		if step > 0 then
			local nextGround = groundAt(nextPos, ignore)
			if nextGround then
				nextPos = Vector3.new(nextPos.X, nextGround + followGroundOffset, nextPos.Z)
			end
		end

		-- SON CAP SUIT SA MARCHE, ET RIEN D'AUTRE : il tourne vers la machine pendant qu'il y va, et garde son
		-- orientation des qu'il est arrete.
		--
		-- IL SE TOURNAIT VERS LE JOUEUR A L'ARRET, et ca se voyait au pire moment : a la sortie de la scene, le
		-- joueur est sur son pas de porte, donc plus pres que `FOLLOW_MIN_PLAYER` -- il etait "arrive" des la
		-- premiere image et pivotait vers lui d'un coup, juste apres avoir fini de parler. Un vieux monsieur a
		-- canne ne fait pas volte-face parce qu'on s'approche.
		--
		-- ET LA MARCHE EST LE BON DECLENCHEUR, pas la distance : quelqu'un tourne la tete vers OU IL VA. Ca
		-- supprime aussi la deuxieme cible, donc l'alternance entre deux caps a la limite de la distance d'arret
		-- -- le tremblement que `FOLLOW_TURN` servait a moyenner n'a plus de source.
		local facing = CFrame.new(nextPos) * (rootPart.CFrame - rootPart.CFrame.Position)
		if step > 0 and goalDist >= 1e-3 then
			local wanted = CFrame.lookAt(nextPos, nextPos + toGoal.Unit)
			-- Un lerp de CFrame interpole la rotation par le plus court chemin : pas besoin de manipuler des
			-- angles, ni de gerer le passage par 180 degres.
			facing = facing:Lerp(wanted, math.clamp(TutorialConfigs.FOLLOW_TURN * dt, 0, 1))
		end

		-- UNE SEULE ECRITURE DE POSE PAR IMAGE. On applique un ECART MONDE et pas un pivot : `PivotTo` passe par
		-- `GetPivot`, qui suit la boite englobante -- une part ajoutee au modele dans Studio le decalerait.
		model:PivotTo(facing * rootPart.CFrame:Inverse() * model:GetPivot())
		setFollowWalking(model, if step > 0 then speed else 0)
	end)
	print(`[Tutorial] Le grand-pere accompagne {player.Name} : la tondeuse, puis la promenade.`)
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
	talkRemote.OnServerEvent:Connect(function(_player, seconds)
		-- LE CLIENT MENT TOUJOURS : on borne, et une valeur qui n'est pas un nombre est simplement ignoree -- le
		-- geste joue alors en entier, ce qui est moche mais jamais casse.
		local bounded: number? = nil
		if type(seconds) == "number" and seconds == seconds then
			bounded = math.clamp(seconds, 0, TutorialConfigs.OLDMAN_TALK_MAX)
		end
		local model = talkModel or findByName(TutorialConfigs.GRANDPA_NAME)
		if model and model:IsA("Model") then
			talkFor(model, bounded)
		end
	end)

	-- IL ARRETE DE SUIVRE QUELQU'UN QUI N'EST PLUS LA. Celui qui cree est celui qui nettoie : la boucle vit sur
	-- RunService, elle survivrait au depart du joueur et continuerait de deplacer le grand-pere vers un
	-- personnage detruit.
	Players.PlayerRemoving:Connect(function(player)
		if sceneOwner == player then
			sceneOwner = nil
			stopFollow()
		end
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return TutorialService
