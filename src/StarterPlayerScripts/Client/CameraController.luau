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
-- En mode build, c'est BuildController qui pilote le FOV (via CameraEffects). On lui rend la main pour ne pas ecraser
-- son effet chaque frame avec REST_FOV (le perso etant fige, on le croirait a l'arret). Meme dossier -> require direct.
local BuildController = require(script.Parent.BuildController)

local CameraController = {}

local player = Players.LocalPlayer

-- Resserrement du champ de vision quand le joueur ACCELERE l'outil AU PIED D'UNE HAIE. Negatif : la vue se
-- referme, ce qui se lit comme de la concentration sur le travail.
local THROTTLE_FOV = -5
-- A l'inverse, accelerer EN LIBRE (hors chantier, hors echelle, hors box de deplacement) RECULE la vue : positif,
-- la vue s'ouvre, on ressent la puissance du moteur. On le fait UNIQUEMENT en libre : sur l'echelle et au chantier
-- la camera est deja scriptee, un effet de plus serait de trop (d'ou le test camera Custom plus bas).
local FREE_REV_FOV = 6
-- Petit DELAI avant que le recul demarre : il ne s'applique qu'apres avoir accelere EN CONTINU ce temps-la. Evite
-- qu'un tapotement de gachette fasse pomper la vue ; le recul recompense une acceleration tenue.
local FREE_REV_DELAY = 0.2

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
-- Temps passe a accelerer EN LIBRE d'affilee. Remis a zero des qu'on n'y est plus. Sert au delai du recul de FOV.
local freeRevTime = 0

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
			-- Une teleportation scriptee (ex : entree sur le plot au Start) pose ce drapeau sur le perso : la chute
			-- FORCEE ne doit pas declencher la plongee. Invisible tant que la camera est scriptee, la plongee
			-- "apparaitrait" d'un coup au passage en camera de jeu -> un bump. PlotSelectController pose ce drapeau.
			if character:GetAttribute("LeafiaSuppressLandDip") then
				return
			end
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
		-- En mode build, BuildController possede le FOV : on ne touche a rien (sinon on ecraserait son effet de vitesse).
		if BuildController.isActive() then
			return
		end
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

		-- Accelerer decale le champ de vision, et le SENS depend du contexte. Simple decalage : il s'additionne au
		-- sprint / a la marche au lieu de les remplacer.
		--   - AU PIED D'UNE HAIE : la vue se RESSERRE (concentration sur le travail).
		--   - EN LIBRE (camera Custom : ni echelle ni chantier, et pas de portage puisque le portage range l'outil) :
		--     la vue RECULE (s'ouvre) pour ressentir la puissance a l'acceleration.
		--   - SUR L'ECHELLE / autre camera scriptee : rien (elle a deja son propre traitement, on n'en rajoute pas).
		local throttling = character:GetAttribute(HedgeConfigs.THROTTLE_ATTRIBUTE) == true
		local atHedge = character:GetAttribute(HedgeConfigs.AT_HEDGE_ATTRIBUTE) == true
		local camera = workspace.CurrentCamera
		local freeCam = camera ~= nil and camera.CameraType == Enum.CameraType.Custom

		-- On compte le temps d'acceleration EN LIBRE d'affilee ; le recul n'apparait qu'apres FREE_REV_DELAY.
		local freeRev = throttling and not atHedge and freeCam
		freeRevTime = if freeRev then freeRevTime + dt else 0

		local throttleFov = 0
		if throttling and atHedge then
			throttleFov = THROTTLE_FOV
		elseif freeRev and freeRevTime >= FREE_REV_DELAY then
			throttleFov = FREE_REV_FOV
		end

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
