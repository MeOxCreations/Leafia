--!strict
-- Etiquette de prix flottante REUTILISABLE (BillboardGui) : icone de coin + texte colore, dans une pastille blanche
-- arrondie avec ombre douce (meme principe que la carte des TIPS du chargement). Suit une position monde. Sert au COUT de
-- construction ("-X" rouge, BuildWallController) ET au REMBOURSEMENT de suppression ("+X" vert, BuildDeleteController).
-- Reduite sur ecran TACTILE (mobile / tablette) via un UIScale, pour ne pas etre oversize.

local UserInputService = game:GetService("UserInputService")

local PriceTag = {}

local COIN_ICON = "rbxassetid://85340926781465"
local TOUCH_SCALE = 0.7 -- reduction de la pastille sur tactile

export type Tag = {
	show: (worldPos: Vector3, text: string, color: Color3) -> (),
	hide: () -> (),
	destroy: () -> (),
}

function PriceTag.new(): Tag
	local anchor = Instance.new("Part")
	anchor.Name = "LeafiaPriceTagAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Name = "LeafiaPriceTag"
	bb.Adornee = anchor
	bb.Size = UDim2.fromOffset(220, 70) -- zone large ; la pastille s'auto-dimensionne dedans
	bb.AlwaysOnTop = true -- lisible meme a travers le mur
	bb.Enabled = false
	bb.Parent = anchor

	-- Conteneur qui s'auto-dimensionne a la pastille -> l'ombre (en scale) suit sa taille. UIScale pour l'ecran tactile.
	local wrapper = Instance.new("Frame")
	wrapper.Name = "Wrapper"
	wrapper.AnchorPoint = Vector2.new(0.5, 0.5)
	wrapper.Position = UDim2.fromScale(0.5, 0.5)
	wrapper.AutomaticSize = Enum.AutomaticSize.XY
	wrapper.Size = UDim2.fromOffset(0, 0)
	wrapper.BackgroundTransparency = 1
	wrapper.Parent = bb

	local uiScale = Instance.new("UIScale") :: UIScale
	uiScale.Scale = if UserInputService.TouchEnabled then TOUCH_SCALE else 1
	uiScale.Parent = wrapper

	-- OMBRE douce derriere la pastille : sombre, semi-transparente, un poil plus grande et decalee vers le BAS, coins
	-- arrondis, ZIndex sous la pastille. En scale -> suit la pastille sans compter dans son auto-size.
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.fromScale(0.5, 0.62)
	shadow.Size = UDim2.fromScale(1.02, 1.16)
	shadow.BackgroundColor3 = Color3.fromRGB(80, 97, 65)
	shadow.BackgroundTransparency = 0.72
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	shadow.Parent = wrapper

	local shadowCorner = Instance.new("UICorner") :: UICorner
	shadowCorner.CornerRadius = UDim.new(0, 12)
	shadowCorner.Parent = shadow

	-- Pastille BLANCHE arrondie, auto-dimensionnee au contenu.
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AutomaticSize = Enum.AutomaticSize.XY
	pill.Size = UDim2.fromOffset(0, 0)
	pill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	pill.ZIndex = 2
	pill.Parent = wrapper

	local corner = Instance.new("UICorner") :: UICorner
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = pill

	local pad = Instance.new("UIPadding") :: UIPadding
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = pill

	-- Contenu en LIGNE : icone de coin puis prix, centres.
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 5)
	list.Parent = pill

	local coin = Instance.new("ImageLabel")
	coin.Name = "Coin"
	coin.LayoutOrder = 1
	coin.Size = UDim2.fromOffset(22, 22)
	coin.BackgroundTransparency = 1
	coin.Image = COIN_ICON
	coin.ScaleType = Enum.ScaleType.Fit
	coin.ZIndex = 3
	coin.Parent = pill

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Price"
	lbl.LayoutOrder = 2
	lbl.AutomaticSize = Enum.AutomaticSize.XY
	lbl.Size = UDim2.fromOffset(0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 22
	lbl.TextColor3 = Color3.fromRGB(230, 60, 60)
	lbl.Text = ""
	lbl.ZIndex = 3
	lbl.Parent = pill

	local tag: Tag = {
		show = function(worldPos: Vector3, text: string, color: Color3)
			anchor.Position = worldPos
			lbl.Text = text
			lbl.TextColor3 = color
			bb.Enabled = true
		end,
		hide = function()
			bb.Enabled = false
		end,
		destroy = function()
			anchor:Destroy() -- emporte le BillboardGui (enfant)
		end,
	}
	return tag
end

return PriceTag
