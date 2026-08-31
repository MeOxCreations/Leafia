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
		if track.Length > 0 and poseMoved(before, jointPose(model)) then
			return -- ca joue ET ca bouge : rien a dire
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

-- LE GRAND-PERE SORT DE CHEZ LUI. Il glisse jusqu'a la part posee dans Studio, puis se repose sur son idle.
--
-- ON LE DEPLACE PAR LE CODE, pas par `Humanoid:MoveTo`. Son rig doit rester ANCRE, et Roblox REFUSE de deplacer
-- une part ancree : `MoveTo` partait, ne bougeait rien, et rendait "chemin barre" au bout de son delai. Ce n'est
-- pas un contournement -- pour un personnage de scene qui suit un trajet decide a l'avance, un glissement est
-- plus SUR qu'un pathfinding : il ne peut ni s'accrocher a un meuble ni tomber d'un bord.
-- IL ARRIVE, ET IL SE TIENT LE DOS. Un geste ponctuel, joue une fois, qui rend la main a l'idle quand il
-- s'acheve -- c'est LUI qui dit quand il a fini, pas un delai pose a cote qui se decalerait si on retouche
-- l'animation.
--
-- Chaque sortie retombe sur `restoreIdle` : sans animation d'arrivee, sans Animator, ou si le chargement echoue,
-- le grand-pere doit se retrouver dans sa pose de repos. Le laisser fige sur sa derniere image de marche serait
-- pire que pas d'arrivee du tout.
-- REMPLIE PLUS BAS. `playArrival` a besoin de la marche, definie apres lui -- et la marche a besoin de
-- `playArrival` a son arrivee. Une variable de fonction casse le cercle sans deplacer un bloc entier.
local walkTo: ((string, ((Model) -> ())?) -> ())? = nil

local function playArrival(model: Model)
	local animId = TutorialConfigs.OLDMAN_ARRIVE_ANIM
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if animId == "" or not animator then
		restoreIdle(model)
		return
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if not ok or typeof(result) ~= "Instance" then
		warn(`[Tutorial] Animation d'arrivee introuvable ({animId}) : il passe directement a son idle.`)
		restoreIdle(model)
		return
	end

	local t = result :: AnimationTrack
	-- AU-DESSUS DE L'IDLE, sinon la pose de repos la melangerait : a priorite egale Roblox ne choisit pas, il
	-- MOYENNE les deux.
	t.Priority = Enum.AnimationPriority.Action
	-- FORCE A FALSE cote code : le reglage de l'editeur n'est qu'une suggestion, et une piste bouclee par erreur
	-- reste a plein poids POUR TOUJOURS -- l'idle ne reviendrait jamais.
	t.Looped = false
	t.Stopped:Connect(function()
		-- IL SOUFFLE, PUIS IL REPART. L'idle est pose tout de suite : sans lui, il resterait fige sur la derniere
		-- image de sa descente pendant toute la pause.
		restoreIdle(model)
		task.delay(TutorialConfigs.OLDMAN_ARRIVE_PAUSE, function()
			local walk = walkTo
			if walk then
				walk(TutorialConfigs.OLDMAN_STAIRS_TARGET, restoreIdle)
			end
		end)
	end)
	t:Play()
end

--- Fait marcher le grand-pere jusqu'a la part `targetName`, puis appelle `onDone`.
---
--- La cible est un PARAMETRE et non une constante : le meme trajet sert deux fois -- sortir de chez lui, puis
--- descendre du perron -- et deux copies de cette fonction finiraient par diverger.
local function walkOldMan(targetName: string, onDone: ((Model) -> ())?)
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
			t:AdjustSpeed(TutorialConfigs.OLDMAN_WALK_SPEED / TutorialConfigs.OLDMAN_WALK_REFERENCE)
			track = t
		end
	else
		warn(`[Tutorial] Pas d'Animator sous "{model.Name}" : il marchera sans animation.`)
	end

	-- LA DUREE VIENT DE LA DISTANCE, jamais d'un chiffre pose a la main : deplacer la part dans Studio suffit
	-- alors a rallonger le trajet, et ses pieds restent d'accord avec son deplacement quoi qu'on change.
	local seconds = flat.Magnitude / math.max(TutorialConfigs.OLDMAN_WALK_SPEED, 0.1)

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


walkTo = walkOldMan

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(placeCharacter)
	if player.Character then
		placeCharacter(player.Character)
	end
end

function TutorialService.init()
	local done = RemoteSetup.getRemote("TutorialSceneDone", "Tutorial") :: RemoteEvent
	done.OnServerEvent:Connect(function()
		-- Aucun argument a valider : le client ne fait que dire "la scene est finie". Le pire qu'il puisse faire
		-- est de la declencher trop tot, ce qui fait sortir le grand-pere -- pas de quoi tricher.
		walkOldMan(TutorialConfigs.OLDMAN_WALK_TARGET, playArrival)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return TutorialService
