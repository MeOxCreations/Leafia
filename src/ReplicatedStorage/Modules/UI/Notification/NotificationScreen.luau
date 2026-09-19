--!strict
-- L'INTERFACE DES NOTIFICATIONS (`NotificationUI`), CONSTRUITE EN CODE.
--
-- POURQUOI. Elle etait faite dans Studio, et Rojo ne synchronise pas StarterGui : elle n'existait que dans les places
-- ou on l'avait recopiee a la main, et chaque retouche etait a refaire partout. Ici elle part sur GitHub et arrive
-- dans TOUTES les places d'un coup. Meme exception assumee que le bandeau des taches.
--
-- LES VALEURS VIENNENT DE LA MAQUETTE de Studio, exportee par `scripts/studio/ExporterInterface.lua` le 19/09/2026 :
-- tout est repris tel quel. Toast et SideNotificationHandler n'ont pas change : ils cherchent toujours
-- `PlayerGui.NotificationUI` et ses enfants par leur nom.
--
-- ELLE GAGNE sur une copie de Studio : une `NotificationUI` qui arriverait encore de StarterGui (place pas encore
-- nettoyee) est detruite, sinon deux interfaces du meme nom se disputeraient les notifications.

local Players = game:GetService("Players")

local NotificationScreen = {}

local NAME = "NotificationUI"
local LUCKIEST = Font.new("rbxasset://fonts/families/LuckiestGuy.json")
local FREDOKA = Font.new("rbxasset://fonts/families/FredokaOne.json")
local SOURCE_SANS = Font.new("rbxasset://fonts/families/SourceSansPro.json")
local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(0, 0, 0)

local screen: ScreenGui? = nil

--- Cree une instance, lui pose ses proprietes, la parente. Rend `Instance` : aucun appelant n'a besoin du type
--- exact, et un type precis ferait refuser les enfants suivants dans un meme tableau (luau-lsp).
local function make(class: string, props: { [string]: any }, parent: Instance?): Instance
	local inst = Instance.new(class)
	-- LE LISERE PAR DEFAUT SAUTE ICI : Roblox pose `BorderSizePixel = 1` sur tout GuiObject, la maquette n'en a aucun.
	if inst:IsA("GuiObject") then
		(inst :: GuiObject).BorderSizePixel = 0
	end
	for key, value in pairs(props) do
		(inst :: any)[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function colors(points: { { number | Color3 } }): ColorSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, ColorSequenceKeypoint.new(p[1] :: number, p[2] :: Color3))
	end
	return ColorSequence.new(keys)
end

local function alphas(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

--- Un texte de la maquette : fond transparent, texte a l'echelle, retour a la ligne, texte riche.
local function label(name: string, props: { [string]: any }, parent: Instance): Instance
	local base: { [string]: any } = {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		RichText = true,
		TextSize = 14,
		TextScaled = true,
		TextWrapped = true,
		TextColor3 = WHITE,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	return make("TextLabel", base, parent)
end

local function stroke(parent: Instance, color: Color3, thickness: number): Instance
	return make("UIStroke", {
		Color = color,
		Thickness = thickness,
		StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize,
	}, parent)
end

-- ===== LE TOAST (bas au milieu) =====
local function buildToastTemplate(parent: Instance)
	local card = make("Frame", {
		Name = "TemplateNotification",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5841, 0.8987),
		Size = UDim2.fromScale(3.126, 0.2027),
		Visible = false,
		BackgroundColor3 = WHITE,
	}, parent)

	local message = label("MessageText", {
		Position = UDim2.fromScale(0.505, 0.58),
		Size = UDim2.fromScale(0.965, 0.65),
		ZIndex = 5,
		Text = 'WARNING MESSAGE "NIL"',
		FontFace = LUCKIEST,
	}, card)
	make("UIStroke", { Thickness = 0.08, StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize }, message)
	make("UIGradient", {
		Rotation = 90,
		Color = colors({
			{ 0, WHITE },
			{ 0.515, WHITE },
			{ 0.5282, Color3.fromRGB(226, 226, 226) },
			{ 1, Color3.fromRGB(147, 147, 147) },
		}),
	}, message)

	make("UIGradient", {
		Transparency = alphas({ { 0, 1 }, { 0.348, 0 }, { 0.5104, 0 }, { 0.6508, 0 }, { 1, 1 } }),
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0.8, 0) }, card)
	local outline = stroke(card, WHITE, 0.09)
	make("UIGradient", { Transparency = alphas({ { 0, 1 }, { 0.5201, 0 }, { 1, 1 } }) }, outline)
end

-- ===== LA NOTIFICATION LATERALE (bas droite) =====
local function buildSideTemplate(parent: Instance)
	local card = make("Frame", {
		Name = "TemplateNotificationSide",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5088, 0.9618),
		Size = UDim2.fromScale(0.9824, 0.07648),
		Visible = false,
		BackgroundColor3 = WHITE,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0.2, 0) }, card)
	make("UIGradient", {
		Name = "UIGradientNotificationColor",
		Rotation = 180,
		Transparency = alphas({ { 0, 0 }, { 0.79, 0.425 }, { 1, 0.875 } }),
	}, card)

	local title = label("NameNotificationType", {
		Position = UDim2.fromScale(0.3503, 0.55),
		Size = UDim2.fromScale(0.6674, 0.4821),
		ZIndex = 2,
		Text = "NOTIFICATION_NAME",
		FontFace = LUCKIEST,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	stroke(title, Color3.fromRGB(166, 166, 166), 0.06)

	local border = stroke(card, WHITE, 0.03)
	-- A CHEVAL SUR LE BORD, comme dans la maquette. Sous pcall : propriete recente, un nom d'enum inconnu ne doit pas
	-- faire tomber toute l'interface pour un contour.
	pcall(function()
		(border :: any).BorderStrokePosition = (Enum :: any).BorderStrokePosition.Center
	end)
	make("UIGradient", { Name = "UIGradientRotate", Transparency = alphas({ { 0, 0 }, { 1, 1 } }) }, border)

	local image = make("ImageLabel", {
		Name = "Image",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.94, 0.5),
		Size = UDim2.fromScale(0.4, 0.4),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		Image = "rbxassetid://87897946031671",
		ImageTransparency = 0.31,
	}, card)
	make("UIAspectRatioConstraint", { AspectRatio = 1.12 }, image)

	make("TextButton", {
		Name = "SelectButton",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		Text = "",
		FontFace = SOURCE_SANS,
		TextSize = 14,
		TextColor3 = BLACK,
	}, card)

	local description = label("DescriptionText", {
		Position = UDim2.fromScale(0.4697, 0.3747),
		Size = UDim2.fromScale(0.7574, 0.2485),
		ZIndex = 2,
		Visible = false,
		Text = "",
		FontFace = LUCKIEST,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	stroke(description, Color3.fromRGB(81, 81, 81), 0.08)

	local earn = label("AdditionalEarnText", {
		Position = UDim2.fromScale(0.5265, 0.912),
		Size = UDim2.fromScale(0.8709, 0.1084),
		ZIndex = 2,
		Visible = false,
		Text = "",
		FontFace = FREDOKA,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, card)
	local earnStroke = stroke(earn, WHITE, 0.08)
	make("UIGradient", {
		Rotation = -90,
		Color = ColorSequence.new(BLACK),
		Transparency = alphas({ { 0, 0 }, { 0.6886, 0.7125 }, { 0.8571, 0.9563 }, { 1, 1 } }),
	}, earnStroke)
	make("UIGradient", {
		Name = "UIGradientColor",
		Color = colors({ { 0, Color3.fromRGB(219, 255, 61) }, { 1, Color3.fromRGB(176, 255, 112) } }),
	}, earn)

	label("CooldownClearNotification", {
		Position = UDim2.fromScale(0.7894, 0.55),
		Size = UDim2.fromScale(0.1277, 0.5104),
		ZIndex = 2,
		Text = "00.0s",
		FontFace = LUCKIEST,
		TextColor3 = Color3.fromRGB(184, 184, 184),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
end

local function build(): ScreenGui
	local gui = make("ScreenGui", {
		Name = NAME,
		DisplayOrder = 1,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- FAUX : construite par le code, personne ne la recreerait apres une mort.
		ResetOnSpawn = false,
	}) :: ScreenGui

	-- La pile du bas, au milieu.
	local holder = make("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.765),
		Size = UDim2.fromScale(0.5, 0.213),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
	}, gui)
	make("UIAspectRatioConstraint", { AspectRatio = 1.88 }, holder)
	local list = make("Frame", {
		Name = "List",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
	}, holder)
	make("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0.02, 0),
	}, list)

	local templates = make("Folder", { Name = "Templates" }, gui)
	buildToastTemplate(templates)
	buildSideTemplate(templates)

	-- La pile laterale, a droite.
	local side = make("Frame", {
		Name = "HolderPopupSide",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.9992, 0.582),
		Size = UDim2.fromScale(0.1655, 0.3862),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
	}, gui)
	local sideList = make("Frame", {
		Name = "HolderList",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3831),
		Size = UDim2.fromScale(0.9745, 1.203),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
	}, side)
	make("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, sideList)
	make("UIAspectRatioConstraint", { AspectRatio = 0.7 }, side)
	return gui
end

--- POSE L'INTERFACE DANS LE PlayerGui, une fois. Idempotent : Toast et SideNotificationHandler l'appellent tous les
--- deux a leur demarrage, le premier la construit.
function NotificationScreen.ensure()
	local existing = screen
	if existing and existing.Parent then
		return
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:WaitForChild("PlayerGui", 10)
	if not playerGui then
		return
	end
	-- UNE COPIE DE STUDIO NE DOIT PAS COHABITER AVEC ELLE : meme nom, les modules prendraient l'une ou l'autre.
	-- Elle arrive au spawn (StarterGui) : on la retire maintenant ET a son arrivee.
	for _, child in playerGui:GetChildren() do
		if child.Name == NAME then
			child:Destroy()
		end
	end
	local gui = build()
	screen = gui
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == NAME and child ~= screen then
			child:Destroy()
		end
	end)
	gui.Parent = playerGui
end

return NotificationScreen
