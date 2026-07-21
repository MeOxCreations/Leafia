--!strict
-- Debug visuel du rayon de detection de haie.
--
-- COTE CLIENT expres. La premiere version dessinait la barre depuis le serveur : elle arrivait avec la latence
-- et l'interpolation de replication, donc elle trainait derriere le personnage. Le client, lui, possede son
-- personnage : la barre colle a la frame pres.
--
-- REPARTITION : le client dessine la GEOMETRIE (origine, direction, longueur), le serveur donne le VERDICT via
-- l'attribut LeafiaAtHedge. On ne duplique donc aucune regle de jeu ; la couleur reflete toujours ce que le
-- serveur a reellement decide.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)

local HedgeController = {}

local player = Players.LocalPlayer
local debugPart: BasePart? = nil

local function getDebugPart(): BasePart
	local existing = debugPart
	if existing and existing.Parent then
		return existing
	end

	local part = Instance.new("Part")
	part.Name = "HedgeRayDebug"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	-- CanTouch a false aussi : sans ca cette barre declencherait les Touched des autres systemes.
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 0.35
	-- Dans Camera et non workspace : rien de ce qui vit la n'est repliqué ni sauvegarde, c'est l'endroit des
	-- objets purement visuels et locaux.
	part.Parent = workspace.CurrentCamera

	debugPart = part
	return part
end

local function hide()
	if debugPart then
		debugPart:Destroy()
		debugPart = nil
	end
end

local function update()
	if not HedgeConfigs.DEBUG_RAY then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		hide()
		return
	end

	-- Meme origine et meme longueur que le serveur : au CENTRE du HumanoidRootPart, droit devant.
	local origin = root.Position
	local direction = root.CFrame.LookVector
	local engaged = character:GetAttribute(HedgeConfigs.AT_HEDGE_ATTRIBUTE) == true
	local length = if engaged then HedgeConfigs.RAY_LENGTH_ENGAGED else HedgeConfigs.RAY_LENGTH

	-- MEME volume que le serveur : ce qu'on voit est exactement ce qui est teste. Ce lancer local ne sert qu'a
	-- savoir ou la boite s'arrete visuellement ; la decision, elle, vient de l'attribut pose par le serveur.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local size = Vector3.new(HedgeConfigs.DETECT_WIDTH, HedgeConfigs.DETECT_HEIGHT, HedgeConfigs.DETECT_THICKNESS)
	local start = CFrame.lookAt(origin, origin + direction)
	local result = workspace:Blockcast(start, size, direction * length, params)
	local drawLength = if result then result.Distance else length

	local part = getDebugPart()
	part.Size = Vector3.new(HedgeConfigs.DETECT_WIDTH, HedgeConfigs.DETECT_HEIGHT, math.max(drawLength, 0.05))
	-- Le recul de moitie fait PARTIR la boite de l'origine au lieu d'etre centree dessus.
	part.CFrame = start * CFrame.new(0, 0, -drawLength * 0.5)
	part.Color = if engaged then HedgeConfigs.DEBUG_COLOR_HIT else HedgeConfigs.DEBUG_COLOR_MISS
end

function HedgeController.init()
	if not HedgeConfigs.DEBUG_RAY then
		return
	end
	-- RenderStepped et non Heartbeat : on dessine juste avant le rendu, donc la barre est calculee sur la MEME
	-- position que celle qui sera affichee. Sur Heartbeat elle aurait une frame de retard.
	RunService.RenderStepped:Connect(update)
	player.CharacterRemoving:Connect(hide)
end

return HedgeController
