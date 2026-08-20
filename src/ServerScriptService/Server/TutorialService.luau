--!strict
-- DIDACTICIEL (place Tutorial uniquement). Pour l'instant : place le joueur au bon endroit ET DANS LE BON SENS. Le spawn par defaut
-- (SpawnLocationOriginal) est SOUS la map -- il sert au flow de la place principale (selection de plot). Ici on repose
-- le perso sur RootSpawnPlayer a CHAQUE spawn (mort comprise). Le deplacement se fait derriere le rideau de chargement,
-- donc invisible. La 1re haie guidee viendra s'ajouter ici plus tard.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

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

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(placeCharacter)
	if player.Character then
		placeCharacter(player.Character)
	end
end

function TutorialService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return TutorialService
