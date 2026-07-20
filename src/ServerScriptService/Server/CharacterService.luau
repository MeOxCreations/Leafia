--!strict
-- Reglages appliques au personnage a chaque apparition.
-- Separe de ToolService : la vitesse de marche n'a rien a voir avec ce que le joueur tient dans les mains.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfigs = require(ReplicatedStorage.Modules.Configs.CharacterConfigs)

local CharacterService = {}

local HUMANOID_TIMEOUT = 10

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid", HUMANOID_TIMEOUT)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	-- Applique cote SERVEUR : le client peut ecrire dans son propre Humanoid, donc une valeur posee la-bas ne
	-- serait qu'une suggestion. Ici elle fait autorite.
	humanoid.WalkSpeed = CharacterConfigs.WALK_SPEED
	humanoid.JumpHeight = CharacterConfigs.JUMP_HEIGHT
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

function CharacterService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return CharacterService
