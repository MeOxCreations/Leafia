--!strict
-- Reglages appliques au personnage a chaque apparition.
-- Separe de ToolService : la vitesse de marche n'a rien a voir avec ce que le joueur tient dans les mains.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfigs = require(ReplicatedStorage.Modules.Configs.CharacterConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local CharacterService = {}

local HUMANOID_TIMEOUT = 10
local ANIMATOR_TIMEOUT = 5

-- Prepare l'animation d'atterrissage sur l'Animator du personnage et la joue a chaque reception au sol.
local function setupLanding(character: Model, humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = humanoid:WaitForChild("Animator", ANIMATOR_TIMEOUT) :: Animator?
	end
	if not animator then
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = CharacterConfigs.LANDING_ANIMATION_ID
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not (ok and track) then
		warn("[CharacterService] Animation d'atterrissage impossible a charger")
		return
	end
	track.Priority = CharacterConfigs.LANDING_PRIORITY

	-- StateChanged plutot qu'un test de vitesse verticale : Roblox connait deja le moment exact ou le
	-- personnage touche le sol, inutile de le redeviner a la main.
	humanoid.StateChanged:Connect(function(_, newState: Enum.HumanoidStateType)
		if newState == Enum.HumanoidStateType.Landed and character.Parent then
			-- Rejouee depuis le debut a chaque atterrissage. La piste n'est pas bouclee : elle s'arrete seule.
			track:Play(0.1)
		end
	end)
end

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid", HUMANOID_TIMEOUT)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	-- Applique cote SERVEUR : le client peut ecrire dans son propre Humanoid, donc une valeur posee la-bas ne
	-- serait qu'une suggestion. Ici elle fait autorite.
	humanoid.WalkSpeed = CharacterConfigs.WALK_SPEED
	humanoid.JumpHeight = CharacterConfigs.JUMP_HEIGHT

	setupLanding(character, humanoid)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

-- Sprint : le client demande, le serveur decide. On relit WALK_SPEED / SPRINT_SPEED depuis la config a chaque
-- fois plutot que de memoriser un etat : la valeur fait autorite, et un respawn qui remet WALK_SPEED n'a rien
-- a resynchroniser.
local function onSetSprint(player: Player, wants: unknown)
	if typeof(wants) ~= "boolean" then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	humanoid.WalkSpeed = if wants then CharacterConfigs.SPRINT_SPEED else CharacterConfigs.WALK_SPEED
end

function CharacterService.init()
	local sprintRemote = RemoteSetup.getRemote("SetSprint", "Character")
	if sprintRemote and sprintRemote:IsA("RemoteEvent") then
		sprintRemote.OnServerEvent:Connect(onSetSprint)
	else
		warn("[CharacterService] Remote Character/SetSprint introuvable")
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return CharacterService
