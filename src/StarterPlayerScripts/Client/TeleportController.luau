--!strict
-- Ecran de TRANSITION pendant un teleport (vers un chantier). Roblox l'affiche a la place de son ecran par defaut
-- pendant le voyage. IMPORTANT : les scripts DANS ce GUI ne tournent PAS pendant le teleport -> il est STATIQUE
-- (aucune anim scriptee possible). On le garde donc simple et lisible : fond + titre + sous-titre. Style Sims : sobre.
--
-- Different de l'ecran de JOIN (ReplicatedFirst/LoadingScreen), qui lui est scripte et anime : celui-ci ne couvre
-- QUE le trajet d'un teleport, ou aucun code ne tourne.

local TeleportService = game:GetService("TeleportService")

-- Couleurs du fond (degrade doux). A adapter a ton theme.
local BG_TOP = Color3.fromRGB(120, 200, 255) -- ciel du jeu
local BG_BOTTOM = Color3.fromRGB(150, 225, 180) -- vert doux
local TITLE = "Leafia"
local SUBTITLE = "Chargement du chantier..."

local TeleportController = {}

local function styledStroke(parent: GuiObject, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = Color3.fromRGB(40, 60, 55)
	stroke.Parent = parent
	return stroke
end

function TeleportController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TeleportLoadingGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false

	-- Fond plein-ecran, degrade doux (le degrade STATIQUE est ok : c'est juste une image, pas une anim).
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(1, 1, 1)
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(BG_TOP, BG_BOTTOM)
	grad.Parent = bg

	-- Bloc central : titre + sous-titre, centres.
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.46)
	title.Size = UDim2.fromScale(0.6, 0.16)
	title.Font = Enum.Font.FredokaOne
	title.Text = TITLE
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	styledStroke(title, 3)
	title.Parent = bg

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
	subtitle.Position = UDim2.fromScale(0.5, 0.6)
	subtitle.Size = UDim2.fromScale(0.5, 0.06)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.Text = SUBTITLE
	subtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	subtitle.TextScaled = true
	styledStroke(subtitle, 2)
	subtitle.Parent = bg

	-- On enregistre ce GUI comme ecran de teleport : Roblox le clonera et l'affichera pendant TOUT teleport.
	TeleportService:SetTeleportGui(gui)

	print("[Teleport] Ecran de transition pret (SetTeleportGui).")
end

return TeleportController
