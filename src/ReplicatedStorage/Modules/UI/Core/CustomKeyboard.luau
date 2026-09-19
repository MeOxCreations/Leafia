--!strict
-- CLAVIER A L'ECRAN, a la place de celui du telephone. Le clavier natif recouvre la moitie de l'ecran, change d'un
-- appareil a l'autre et ne ressemble pas au jeu ; celui-ci est dessine dans le style de l'interface qui l'accueille.
--
-- UN SEUL CLAVIER POUR TOUT LE JEU : ne a l'origine dans la fenetre du nom d'entreprise (LoadCompanyController), sorti
-- ici quand la console admin en a eu besoin a son tour. Deux copies auraient fini par diverger.
--
-- Il ne tient AUCUN texte : chaque touche appelle `onChar`, `onBackspace` ou `onConfirm`. C'est l'appelant qui sait ce
-- qu'il remplit, sa longueur maximale et ce que veut dire "valider".

local CustomKeyboard = {}

export type Options = {
	-- Une chaine par rangee ; chaque caractere est une touche, affichee en majuscule et tapee telle quelle.
	rows: { string },
	-- Largeur d'une touche de caractere, en fraction de la largeur du clavier.
	keyWidth: number,
	-- Hauteur d'une rangee, en fraction de la hauteur du clavier.
	rowHeight: number,
	-- Touches ajoutees a la derniere rangee, entre effacer et espace (ex "_"). La barre d'espace se raccourcit d'autant.
	extraKeys: { string }?,
	font: Font,
	zIndex: number,
	keyColor: Color3,
	specialColor: Color3,
	textColor: Color3,
	-- Couleur tant qu'on appuie : on voit la touche prise, meme sous le pouce.
	pressColor: Color3,
	confirmColor: Color3,
	confirmTextColor: Color3,
	onChar: (string) -> (),
	onBackspace: () -> (),
	onConfirm: () -> (),
}

-- Largeurs de la derniere rangee (fractions du clavier). Sans touche en plus : 0.16 + 0.46 + 0.16, les valeurs
-- d'origine du clavier du nom d'entreprise.
local SPECIAL_WIDTH = 0.16
local SPACE_WIDTH = 0.46
local ROW_GAP = 0.008

--- Remplit `keyboard` -- un Frame qui porte deja sa UIListLayout VERTICALE -- avec une rangee par chaine de `rows`,
--- puis la rangee effacer / touches en plus / espace / valider.
function CustomKeyboard.fill(keyboard: Instance, o: Options)
	-- Une touche : widthScale = fraction de la LARGEUR du clavier (touches uniformes).
	local function makeKey(labelText: string, widthScale: number, bg: Color3, textColor: Color3, onClick: () -> ()): TextButton
		local btn = Instance.new("TextButton")
		btn.Name = "Key_" .. labelText
		btn.BackgroundColor3 = bg
		btn.Size = UDim2.fromScale(widthScale, 1)
		btn.Text = labelText
		btn.TextColor3 = textColor
		btn.FontFace = o.font
		btn.TextScaled = true
		btn.AutoButtonColor = false -- on gere la couleur d'appui a la main (InputBegan / InputEnded)
		btn.ZIndex = o.zIndex
		local round = Instance.new("UICorner") :: UICorner
		round.CornerRadius = UDim.new(0.16, 0)
		round.Parent = btn
		local pad = Instance.new("UIPadding") :: UIPadding
		pad.PaddingTop = UDim.new(0.2, 0)
		pad.PaddingBottom = UDim.new(0.2, 0)
		pad.PaddingLeft = UDim.new(0.08, 0)
		pad.PaddingRight = UDim.new(0.08, 0)
		pad.Parent = btn
		btn.Activated:Connect(onClick)
		-- Retour visuel d'appui : la touche change de couleur tant qu'on la maintient, puis revient a la sienne.
		btn.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				btn.BackgroundColor3 = o.pressColor
			end
		end)
		btn.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				btn.BackgroundColor3 = bg
			end
		end)
		btn.MouseLeave:Connect(function() -- glisse hors de la touche sans relacher : on remet la couleur d'origine
			btn.BackgroundColor3 = bg
		end)
		return btn
	end

	-- Une rangee : UIListLayout horizontal centre, donc les rangees plus courtes restent centrees.
	local function makeRow(order: number): Frame
		local row = Instance.new("Frame")
		row.Name = "Row" .. order
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromScale(1, o.rowHeight)
		row.LayoutOrder = order
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(ROW_GAP, 0)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = row
		return row
	end

	for r, rowStr in o.rows do
		local rowFrame = makeRow(r)
		for i = 1, #rowStr do
			local ch = rowStr:sub(i, i)
			local key = makeKey(ch:upper(), o.keyWidth, o.keyColor, o.textColor, function()
				o.onChar(ch)
			end)
			key.LayoutOrder = i
			key.Parent = rowFrame
		end
		rowFrame.Parent = keyboard
	end

	-- Derniere rangee : effacer, touches en plus, espace (large), valider.
	local extras = o.extraKeys or {}
	local specialRow = makeRow(#o.rows + 1)
	local order = 0
	local function add(key: TextButton)
		order += 1
		key.LayoutOrder = order
		key.Parent = specialRow
	end
	add(makeKey("<", SPECIAL_WIDTH, o.specialColor, o.textColor, o.onBackspace))
	for _, ch in extras do
		add(makeKey(ch, o.keyWidth, o.specialColor, o.textColor, function()
			o.onChar(ch)
		end))
	end
	local spaceWidth = math.max(SPACE_WIDTH - #extras * (o.keyWidth + ROW_GAP), 0.1)
	add(makeKey("SPACE", spaceWidth, o.specialColor, o.textColor, function()
		o.onChar(" ")
	end))
	add(makeKey("OK", SPECIAL_WIDTH, o.confirmColor, o.confirmTextColor, o.onConfirm))
	specialRow.Parent = keyboard
end

return CustomKeyboard
