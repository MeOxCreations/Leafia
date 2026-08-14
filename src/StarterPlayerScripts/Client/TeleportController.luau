--!strict
-- Ecran de TRANSITION pendant un teleport (vers un chantier / le tuto). Roblox l'affiche a la place de son ecran par
-- defaut pendant le voyage. IMPORTANT : les scripts DANS ce GUI ne tournent PAS pendant le teleport -> il est STATIQUE
-- (aucune anim possible). On le garde donc sobre : fond GRIS + la feuille + 4 boules FIGEES.
--
-- Meme rideau gris que l'ecran d'ARRIVEE (ReplicatedFirst/LoadingScreen quand on vient d'un teleport) : le joueur ne
-- voit jamais le ciel Roblox vide, ca donne une transition propre "on change de lieu". A l'arrivee, les boules, elles,
-- rebondissent (la, du code tourne).

local TeleportService = game:GetService("TeleportService")

local BG_COLOR = Color3.fromRGB(31, 31, 31) -- gris fonce (meme que LoadingOverlay / l'ecran d'arrivee)
local LEAF_IMAGE = "rbxassetid://117703108607506" -- la feuille (logo)
local LEAF_COLOR = Color3.fromRGB(81, 81, 81)
local BALL_SIZE = 14
local BALL_GAP = 12
local BALL_COUNT = 4

local TeleportController = {}

function TeleportController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TeleportLoadingGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false

	-- Fond gris fonce plein ecran.
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = BG_COLOR
	bg.BorderSizePixel = 0
	bg.Parent = gui

	-- La feuille (logo) au centre, teintee. STATIQUE (pas d'oscillation : aucun script ne tourne pendant le teleport).
	local leaf = Instance.new("ImageLabel")
	leaf.BackgroundTransparency = 1
	leaf.AnchorPoint = Vector2.new(0.5, 0.5)
	leaf.Position = UDim2.fromScale(0.5, 0.46)
	leaf.Size = UDim2.fromScale(0.2, 0.2)
	leaf.Image = LEAF_IMAGE
	leaf.ImageColor3 = LEAF_COLOR
	leaf.ScaleType = Enum.ScaleType.Fit
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = leaf
	leaf.Parent = bg

	-- 4 boules blanches alignees, FIGEES (pas de rebond possible ici). Juste un repere "chargement".
	local width = BALL_COUNT * BALL_SIZE + (BALL_COUNT - 1) * BALL_GAP
	local loader = Instance.new("Frame")
	loader.BackgroundTransparency = 1
	loader.AnchorPoint = Vector2.new(0.5, 0.5)
	loader.Position = UDim2.fromScale(0.5, 0.62)
	loader.Size = UDim2.fromOffset(width, BALL_SIZE)
	loader.Parent = bg
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, BALL_GAP)
	layout.Parent = loader
	for i = 1, BALL_COUNT do
		local ball = Instance.new("Frame")
		ball.Size = UDim2.fromOffset(BALL_SIZE, BALL_SIZE)
		ball.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		ball.BorderSizePixel = 0
		ball.LayoutOrder = i
		local c = Instance.new("UICorner") :: UICorner
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = ball
		ball.Parent = loader
	end

	-- Enregistre ce GUI : Roblox le clone et l'affiche pendant TOUT teleport.
	TeleportService:SetTeleportGui(gui)
	print("[Teleport] Ecran de transition (gris) pret (SetTeleportGui).")
end

return TeleportController
