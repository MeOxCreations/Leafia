--!strict
-- Ressenti du deplacement, cote client : champ de vision selon la vitesse, oscillation au sprint, plongee a
-- l'atterrissage. Et l'input du sprint (Shift), qui declenche l'acceleration cote serveur.
--
-- On ne touche JAMAIS a FieldOfView ni a CameraOffset directement : tout passe par CameraEffects, seul
-- ecrivain de la camera. Ce controller ne fait que decider les cibles et rapporter l'input.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraEffects = require(script.Parent.Utils.CameraEffects)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local CameraController = {}

local player = Players.LocalPlayer

local REST_FOV = 70
local MOVE_FOV = 76
-- Sprint : un cran de plus, discret. Un ecart trop grand donne le mal de mer, pas de la vitesse.
local SPRINT_FOV = 80
-- En dessous de ca on considere le joueur immobile : evite le papillonnement quand il s'arrete presque.
local MOVING_THRESHOLD = 2

-- Bob du sprint. TRES leger : c'est une respiration de la camera, pas un tremblement.
local SPRINT_BOB_AMPLITUDE = 0.12 -- studs
local SPRINT_BOB_FREQUENCY = 11 -- oscillations par seconde, ~cadence des foulees

-- Plongee a l'atterrissage : vitesse initiale donnee au ressort (studs/s), pas une profondeur. La profondeur
-- reelle en decoule (environ strength / sqrt(raideur)). Discrete : la camera encaisse, elle ne tombe pas.
local LAND_DIP_STRENGTH = 6.5

local SPRINT_KEYS = { [Enum.KeyCode.LeftShift] = true, [Enum.KeyCode.RightShift] = true }

local function isSprinting(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

-- La plongee a l'atterrissage est un effet du LOCAL player : on l'ecoute sur son propre Humanoid. StateChanged
-- plutot qu'un test de vitesse verticale : Roblox connait deja le moment exact du contact au sol.
local function watchCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	humanoid.StateChanged:Connect(function(_, newState: Enum.HumanoidStateType)
		if newState == Enum.HumanoidStateType.Landed then
			CameraEffects.LandDip(LAND_DIP_STRENGTH)
		end
	end)
end

function CameraController.init()
	CameraEffects.init()

	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	-- Sprint : on ne previent le serveur qu'au CHANGEMENT d'etat de la touche, pas chaque frame. Le serveur
	-- decide de la vitesse ; ici on rapporte, c'est tout.
	local sprintRemote = RemoteSetup.getRemote("SetSprint", "Character")
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if SPRINT_KEYS[input.KeyCode] and sprintRemote and sprintRemote:IsA("RemoteEvent") then
			sprintRemote:FireServer(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		-- Pas de filtre gameProcessed sur le relachement : arreter de sprinter ne doit jamais rester coince,
		-- meme si la touche a ete relachee au-dessus d'une interface.
		if SPRINT_KEYS[input.KeyCode] and sprintRemote and sprintRemote:IsA("RemoteEvent") then
			sprintRemote:FireServer(false)
		end
	end)

	-- FOV et bob : reevalues chaque frame selon l'etat reel du joueur.
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = humanoid and humanoid.RootPart
		if not (humanoid and root) then
			CameraEffects.SetFovBase(REST_FOV)
			CameraEffects.SetBob(0, SPRINT_BOB_FREQUENCY)
			return
		end

		-- Vitesse HORIZONTALE seulement : un saut ou une chute ne doit pas elargir la vue.
		local velocity = root.AssemblyLinearVelocity
		local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > MOVING_THRESHOLD
		local sprinting = moving and isSprinting()

		if sprinting then
			CameraEffects.SetFovBase(SPRINT_FOV)
			CameraEffects.SetBob(SPRINT_BOB_AMPLITUDE, SPRINT_BOB_FREQUENCY)
		elseif moving then
			CameraEffects.SetFovBase(MOVE_FOV)
			CameraEffects.SetBob(0, SPRINT_BOB_FREQUENCY)
		else
			CameraEffects.SetFovBase(REST_FOV)
			CameraEffects.SetBob(0, SPRINT_BOB_FREQUENCY)
		end
	end)
end

return CameraController
