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
local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)

local CameraController = {}

local player = Players.LocalPlayer

-- Resserrement du champ de vision quand le joueur ACCELERE l'outil. Negatif : la vue se referme, ce qui se lit
-- comme de la concentration. S'applique meme hors chantier : c'est une reaction a l'OUTIL, pas au lieu.
local THROTTLE_FOV = -5

local REST_FOV = 70
local MOVE_FOV = 76
-- Sprint : un cran de plus, discret. Un ecart trop grand donne le mal de mer, pas de la vitesse.
local SPRINT_FOV = 80
-- Seuils d'ENTREE et de SORTIE du mouvement. Deux valeurs et non une : avec un seuil unique, un signal qui
-- oscille autour fait clignoter le champ de vision.
local MOVING_ENTER = 0.30
-- DOIT rester sous HedgeConfigs.STEP_GLIDE (0.25). Le signal lisse ne descend jamais sous la plus petite
-- valeur brute : au pied d'une haie, cette valeur EST STEP_GLIDE. Un seuil de sortie au-dessus ferait
-- retomber le champ de vision entre deux pas, et le tremblement reviendrait.
-- Marge mesuree en regime etabli : le signal oscille entre 0.25 et 0.54.
local MOVING_EXIT = 0.15
-- Lissage du signal de deplacement. Le pas chasse pousse par a-coups : l'intention pulse entre la poussee et
-- le glissement. Sans ce filtre, meme avec deux seuils, le champ de vision tremblerait au rythme des pas.
local MOVE_SIGNAL_SMOOTH = 8

-- Signal lisse et etat courant, gardes d'une frame a l'autre.
local moveSignal = 0
local moving = false

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
	RunService.RenderStepped:Connect(function(dt: number)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			CameraEffects.SetFovBase(REST_FOV)
			CameraEffects.SetBob(0, SPRINT_BOB_FREQUENCY)
			return
		end

		-- MoveDirection, l'INTENTION du joueur, et non sa vitesse mesuree.
		--
		-- La vitesse reelle pulse : le pas chasse pousse au moment ou le pied touche le sol puis laisse glisser.
		-- Elle traversait donc le seuil a CHAQUE PAS, et le champ de vision tremblait au rythme de la marche.
		-- L'intention, elle, ne retombe jamais a zero tant que le joueur pousse sur ses touches.
		--
		-- MoveDirection est deja horizontale : un saut ou une chute ne l'elargit pas, on n'a rien a filtrer.
		local raw = humanoid.MoveDirection.Magnitude
		-- Lissage puis DEUX seuils : le filtre efface les a-coups, l'ecart entre les seuils absorbe le reste.
		moveSignal += (raw - moveSignal) * math.min(1, MOVE_SIGNAL_SMOOTH * dt)
		if moving then
			moving = moveSignal > MOVING_EXIT
		else
			moving = moveSignal > MOVING_ENTER
		end
		local sprinting = moving and isSprinting()

		-- Accelerer RESSERRE la vue, mais uniquement AU PIED D'UNE HAIE. Accelerer dans le vide en traversant le
		-- jardin ne doit pas resserrer la vue : le resserrement dit "je me concentre sur ce travail", il n'a de
		-- sens que s'il y a un travail devant.
		-- Un simple decalage, pour que l'effet s'additionne au sprint et a la marche au lieu de les remplacer.
		local working = character:GetAttribute(HedgeConfigs.THROTTLE_ATTRIBUTE) == true
			and character:GetAttribute(HedgeConfigs.AT_HEDGE_ATTRIBUTE) == true
		local throttleFov = if working then THROTTLE_FOV else 0

		if sprinting then
			CameraEffects.SetFovBase(SPRINT_FOV + throttleFov)
			CameraEffects.SetBob(SPRINT_BOB_AMPLITUDE, SPRINT_BOB_FREQUENCY)
		elseif moving then
			CameraEffects.SetFovBase(MOVE_FOV + throttleFov)
			CameraEffects.SetBob(0, SPRINT_BOB_FREQUENCY)
		else
			CameraEffects.SetFovBase(REST_FOV + throttleFov)
			CameraEffects.SetBob(0, SPRINT_BOB_FREQUENCY)
		end
	end)
end

return CameraController
