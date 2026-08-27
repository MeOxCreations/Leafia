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

-- REMET LE GRAND-PERE SUR SON IDLE, une fois arrive.
--
-- ON DEMANDE A L'ANIMATOR ce qui joue REELLEMENT, au lieu de supposer. `AmbientAnimService` lance deja un idle au
-- demarrage, et en theorie il ressort tout seul des qu'on arrete la marche -- mais une piste a pu etre coupee
-- ailleurs (la scene, un respawn, un rechargement), et rien ne le dirait : le grand-pere resterait simplement
-- fige, ce qui ressemble a une animation qui ne joue pas.
--
-- Le fait bat l'hypothese : `GetPlayingAnimationTracks` dit ce qui tourne, une liste tenue a la main dit ce qu'on
-- croit avoir.
local function ensureIdle(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if not animator then
		return
	end
	for _, playing in (animator :: Animator):GetPlayingAnimationTracks() do
		if playing.Priority == Enum.AnimationPriority.Idle then
			return -- un idle tourne deja : en lancer un second les ferait MELANGER, pas se remplacer
		end
	end

	local node: Instance? = ReplicatedStorage:FindFirstChild("Animations")
	for _, name in TutorialConfigs.OLDMAN_IDLE_PATH do
		node = node and node:FindFirstChild(name)
	end
	if not (node and node:IsA("Animation")) then
		warn(
			`[Tutorial] Idle introuvable : ReplicatedStorage.Animations.`
				.. `{table.concat(TutorialConfigs.OLDMAN_IDLE_PATH, ".")}. Le grand-pere restera fige.`
		)
		return
	end
	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(node :: Animation)
	end)
	if ok and typeof(result) == "Instance" then
		local t = result :: AnimationTrack
		t.Looped = true
		t.Priority = Enum.AnimationPriority.Idle
		t:Play()
	end
end

-- LE GRAND-PERE SORT DE CHEZ LUI. Il glisse jusqu'a la part posee dans Studio, puis se repose sur son idle.
--
-- ON LE DEPLACE PAR LE CODE, pas par `Humanoid:MoveTo`. Son rig doit rester ANCRE, et Roblox REFUSE de deplacer
-- une part ancree : `MoveTo` partait, ne bougeait rien, et rendait "chemin barre" au bout de son delai. Ce n'est
-- pas un contournement -- pour un personnage de scene qui suit un trajet decide a l'avance, un glissement est
-- plus SUR qu'un pathfinding : il ne peut ni s'accrocher a un meuble ni tomber d'un bord.
local function walkOldMan()
	if walking then
		return
	end

	local model = findByName(TutorialConfigs.GRANDPA_NAME)
	if not (model and model:IsA("Model")) then
		warn(`[Tutorial] "{TutorialConfigs.GRANDPA_NAME}" introuvable : il ne sortira pas de chez lui.`)
		return
	end
	local target = findByName(TutorialConfigs.OLDMAN_WALK_TARGET)
	if not (target and target:IsA("BasePart")) then
		warn(
			`[Tutorial] Aucune part "{TutorialConfigs.OLDMAN_WALK_TARGET}" dans le Workspace : le grand-pere n'a `
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
		-- ON ARRETE LA MARCHE, PUIS on s'assure qu'un idle tourne. L'ordre compte : arreter en premier laisse la
		-- place, et `ensureIdle` ne fait rien si l'idle d'ambiance est deja la -- ce qui est le cas normal.
		if track then
			(track :: AnimationTrack):Stop()
		end
		ensureIdle(model)
		walking = false
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
	done.OnServerEvent:Connect(function()
		-- Aucun argument a valider : le client ne fait que dire "la scene est finie". Le pire qu'il puisse faire
		-- est de la declencher trop tot, ce qui fait sortir le grand-pere -- pas de quoi tricher.
		walkOldMan()
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return TutorialService
