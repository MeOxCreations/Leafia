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
-- et deux marches en parallele se disputeraient le meme Humanoid.
local walking = false

-- LE GRAND-PERE SORT DE CHEZ LUI. Il marche jusqu'a la part posee dans Studio, puis se repose sur son idle.
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

	-- LES TROIS CONDITIONS POUR QU'UN PERSONNAGE MARCHE, verifiees une par une et nommees separement : elles se
	-- ressemblent a l'ecran -- il ne bouge pas -- et se corrigent a trois endroits differents.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(`[Tutorial] "{model.Name}" n'a pas de Humanoid : il ne peut pas marcher.`)
		return
	end
	-- Roblox cherche ce nom EXACT pour deplacer un personnage. Une RootPart nommee autrement laisse le Humanoid
	-- sans prise : l'animation joue, `MoveTo` ne fait rien, et rien dans la console ne l'explique.
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		warn(`[Tutorial] "{model.Name}" n'a pas de part nommee "HumanoidRootPart" : renomme sa RootPart ainsi.`)
		return
	end
	if (root :: BasePart).Anchored then
		warn(`[Tutorial] La HumanoidRootPart de "{model.Name}" est ANCREE : il ne peut pas se deplacer.`)
		return
	end

	walking = true
	humanoid.WalkSpeed = TutorialConfigs.OLDMAN_WALK_SPEED

	-- L'ANIMATION EST FACULTATIVE : sans elle il glisse, mais il arrive quand meme. On ne bloque pas la scene
	-- pour un asset manquant.
	local track: AnimationTrack? = nil
	local animator = humanoid:FindFirstChildOfClass("Animator")
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
			-- Jouee au RAPPORT des deux vitesses : changer sa vitesse de marche ne fait pas patiner ses pieds, et
			-- il n'y a aucune seconde valeur a garder d'accord avec la premiere.
			t:Play()
			t:AdjustSpeed(TutorialConfigs.OLDMAN_WALK_SPEED / TutorialConfigs.OLDMAN_WALK_REFERENCE)
			track = t
		end
	else
		warn(`[Tutorial] Pas d'Animator sous le Humanoid de "{model.Name}" : il marchera sans animation.`)
	end

	task.spawn(function()
		humanoid:MoveTo(target.Position)
		-- `MoveToFinished` rend `false` quand il n'arrive pas -- chemin barre, ou timeout de Roblox. Dans les deux
		-- cas on s'arrete la : mieux vaut un grand-pere pose en chemin qu'un grand-pere qui pietine contre un mur.
		local reached = humanoid.MoveToFinished:Wait()
		if not reached then
			warn(`[Tutorial] "{model.Name}" n'a pas atteint "{TutorialConfigs.OLDMAN_WALK_TARGET}" : chemin barre ?`)
		end
		-- ON ARRETE LA MARCHE, on ne rejoue pas l'idle : il tourne DEJA en dessous (AmbientAnimService, priorite
		-- `Idle`). Le relancer ici en ferait deux, et deux pistes de meme priorite donnent leur MOYENNE.
		if track then
			(track :: AnimationTrack):Stop()
		end
		walking = false
	end)

	-- FILET. `MoveToFinished` peut ne jamais tirer si le Humanoid meurt ou si le modele est detruit en chemin :
	-- sans ce garde-fou, `walking` resterait vrai et la marche ne pourrait plus jamais repartir.
	task.delay(TutorialConfigs.OLDMAN_WALK_TIMEOUT, function()
		if walking then
			walking = false
			if track then
				(track :: AnimationTrack):Stop()
			end
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
