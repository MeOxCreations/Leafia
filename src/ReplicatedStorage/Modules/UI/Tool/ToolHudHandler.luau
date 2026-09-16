--!strict
-- LE MENU DES OUTILS, en bas a gauche. Un bouton blanc ; on clique, un panneau blanc se deplie au-dessus.
--
-- REPLIE PAR DEFAUT, ET C'EST LE POINT. Le joueur n'a pas trois outils a choisir en permanence : il en a un en
-- main, et il en change de temps en temps. Une barre ouverte en continu occuperait un coin de l'ecran pour une
-- decision qu'on prend deux fois par chantier.
--
-- LE BOUTON MONTRE CE QU'ON TIENT. L'ancien affichait toujours le meme dessin : pour savoir quel outil on avait
-- en main, il fallait ouvrir le menu. La, un coup d'oeil suffit -- et le menu ne s'ouvre plus que pour CHANGER.
--
-- UNE LIGNE PAR OUTIL, AVEC SON NOM. Des cases carrees a dessin seul se devinent ; un outil sans dessin (le
-- rateau) y devenait un mot tasse dans un carre. Une ligne a la place pour le dessin, le nom ET l'etat.
--
-- BLANC, comme les cartes du camion : les deux interfaces parlent des memes outils, elles doivent se reconnaitre.
--
-- EN BAS A GAUCHE. Et PAS EN MEME TEMPS que la barre du camion : les deux parlent des memes outils, et les voir
-- ensemble devant la benne rendait le choix confus. Quand la barre s'ouvre, le bouton se range sous l'ecran et
-- revient a sa fermeture (voir PanelFocus).
--
-- ELLE NE DECIDE RIEN. On lui donne la liste des outils possedes et celui qui est en main ; equiper, ranger, et
-- savoir ce qu'on possede est l'affaire du controller et du serveur.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local PanelFocus = require(ReplicatedStorage.Modules.UI.Core.PanelFocus)

local ToolHudHandler = {}

local player = Players.LocalPlayer

-- ===== LA PLACE =====
local ROOT_POS = UDim2.fromScale(0.035, 0.93)
local BUTTON = 76
-- L'ecart entre le bouton et le panneau : colle, on ne voit pas que l'un sort de l'autre ; loin, ils se lisent
-- comme deux interfaces.
local MENU_GAP = 10
local PANEL_W = 252
local PAD = 8
local HEADER_H = 22
-- 52 PIXELS DE HAUT PAR LIGNE : au doigt, une cible sous 44 se rate. Le menu doit se jouer au pouce.
local ROW_H = 52
local ROW_GAP = 6
-- La marge autour de la carte, dans le groupe : sans elle, l'ombre serait coupee au bord.
local SHADOW_MARGIN = 8
local SHADOW_DROP = 4

-- ===== LES COULEURS =====
local CARD = Color3.fromRGB(255, 255, 255)
local CARD_STROKE = Color3.fromRGB(206, 214, 224)
local TEXT = Color3.fromRGB(32, 38, 46)
local SOFT_TEXT = Color3.fromRGB(128, 136, 146)
-- Le creux sous le dessin : un blanc casse, juste assez pour detourer l'outil. Meme valeur que les cartes du camion.
local WELL = Color3.fromRGB(241, 244, 248)
local HOVER = Color3.fromRGB(245, 247, 250)
-- LE VERT DU JEU pour l'outil EN MAIN : la meme couleur que les taches et le bouton TAKE, parce que c'est la meme
-- idee -- ce qui est actif.
local HELD = Color3.fromRGB(98, 206, 59)
-- Et sa version pale en fond de ligne : le vert plein partout mangerait le dessin de l'outil.
local HELD_BG = Color3.fromRGB(236, 248, 229)
local BADGE = Color3.fromRGB(32, 38, 46)
local SHADOW_TRANSPARENCY = 0.86

-- ===== LE MOUVEMENT =====
local OPEN_EASE = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_EASE = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOVER_EASE = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- LE PANNEAU GRANDIT DEPUIS LE BOUTON : il part un peu plus petit, ancre en bas a gauche, donc il sort de lui.
local CLOSED_SCALE = 0.9
-- LES LIGNES ARRIVENT L'UNE APRES L'AUTRE, en glissant de quelques pixels : un decalage se lit comme un
-- deploiement, un bloc qui apparait se lit comme une fenetre.
local STAGGER = 0.035
local ROW_SLIDE = 14
-- LE "+" DEVIENT UNE CROIX en tournant d'un huitieme de tour : le meme signe dit "ouvrir" puis "fermer".
local BADGE_TURN = 45
-- LE RANGEMENT : le bouton descend sous le bas de l'ecran quand un autre panneau prend la place, et remonte avec un
-- leger rebond. Sous l'ecran, et pas en fondu : il sort par le bord le plus proche, donc on devine ou il est parti.
local TUCK_OUT = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TUCK_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- La marge sous l'ecran : le "+" en coin depasse du bouton, il ne doit pas rester visible au bord.
local TUCK_MARGIN = 24
local PANEL = "ToolHud"
-- Le dessin du bouton quand on ne tient rien. En attendant une caisse a outils, c'est l'icone de la cisaille.
local BUTTON_ICON = "rbxassetid://96003986607540"

-- ===== LES MOTS =====
-- EN ANGLAIS, comme tout texte vu par le joueur.
local HEADER_TEXT = "MY TOOLS"
local BUTTON_TEXT = "TOOLS"
local HELD_TEXT = "IN HAND"
local EQUIP_TEXT = "EQUIP"

export type Entry = {
	-- Le nom du MODELE (ce que le joueur lit), et la cle d'equipement (ce que le serveur attend).
	label: string,
	tool: string,
	icon: string?,
	held: boolean,
}

local gui: ScreenGui? = nil
local root: Frame? = nil
local buttonIcon: ImageLabel? = nil
local buttonCaption: TextLabel? = nil
local buttonStroke: UIStroke? = nil
local badge: Frame? = nil
local menu: CanvasGroup? = nil
local menuScale: UIScale? = nil
local card: Frame? = nil
local shadow: Frame? = nil
local rows: { TextButton } = {}
local open = false
-- Sert quand on rouvre pendant une fermeture : la fermeture en retard ne doit pas cacher le panneau rouvert.
local openToken = 0
local outsideClick: RBXScriptConnection? = nil

local function getGui(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("ScreenGui")
	created.Name = "LeafiaToolHud"
	created.ResetOnSpawn = false
	created.IgnoreGuiInset = true
	created.ScreenInsets = Enum.ScreenInsets.None
	-- Sous la barre du camion : ils ne s'affichent plus ensemble, mais se croisent le temps du rangement, et c'est
	-- le camion qu'on vient d'ouvrir qui compte.
	created.DisplayOrder = 52
	created.Parent = player:WaitForChild("PlayerGui")
	gui = created
	return created
end

-- Le cast est OBLIGATOIRE : luau-lsp ne resout pas `Instance.new("UICorner")` vers `UICorner`.
local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = radius
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function label(parent: Instance, text: string, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	-- UNE TAILLE FIXE, pas `TextScaled` : des noms de longueurs differentes finiraient a des tailles differentes,
	-- et une liste dont chaque ligne a sa police se lit comme un bug.
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.Parent = parent
	return l
end

local function menuHeight(count: number): number
	return PAD * 2 + HEADER_H + count * ROW_H + math.max(count - 1, 0) * ROW_GAP
end

local function rowY(index: number): number
	return PAD + HEADER_H + (index - 1) * (ROW_H + ROW_GAP)
end

--- Ouvre ou ferme le panneau. `animateRows` fait glisser les lignes une a une : seulement a l'ouverture, pas quand
--- la liste est refaite pendant qu'il est deja ouvert -- sinon chaque changement d'outil rejouerait l'entree.
local function applyOpen(animateRows: boolean)
	PanelFocus.setOpen(PANEL, open)
	openToken += 1
	local token = openToken
	local group, scale, mark = menu, menuScale, badge
	if mark then
		TweenService:Create(mark, OPEN_EASE, { Rotation = if open then BADGE_TURN else 0 }):Play()
	end
	if not (group and scale) then
		return
	end
	if open then
		group.Visible = true
		TweenService:Create(group, OPEN_EASE, { GroupTransparency = 0 }):Play()
		TweenService:Create(scale, OPEN_EASE, { Scale = 1 }):Play()
		for index, row in rows do
			local final = UDim2.fromOffset(PAD, rowY(index))
			if animateRows then
				row.Position = final + UDim2.fromOffset(-ROW_SLIDE, 0)
				task.delay((index - 1) * STAGGER, function()
					if token == openToken and row.Parent then
						TweenService:Create(row, OPEN_EASE, { Position = final }):Play()
					end
				end)
			else
				row.Position = final
			end
		end
	else
		TweenService:Create(group, CLOSE_EASE, { GroupTransparency = 1 }):Play()
		TweenService:Create(scale, CLOSE_EASE, { Scale = CLOSED_SCALE }):Play()
		-- ON NE CACHE QU'A LA FIN du fondu, et seulement si personne n'a rouvert entre-temps.
		task.delay(CLOSE_EASE.Time, function()
			if token == openToken and not open then
				group.Visible = false
			end
		end)
	end
end

local function build(onToggle: () -> ()): Frame
	local existing = root
	if existing and existing.Parent then
		return existing
	end
	local holder = getGui()

	local frame = Instance.new("Frame")
	frame.Name = "ToolHud"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = ROOT_POS
	frame.Size = UDim2.fromOffset(BUTTON, BUTTON)
	frame.BackgroundTransparency = 1
	frame.Parent = holder

	-- L'OMBRE : un rectangle sombre tres transparent, decale vers le bas. Sans elle, du blanc sur une facade claire
	-- n'a plus de bord.
	local buttonShadow = Instance.new("Frame")
	buttonShadow.Name = "Shadow"
	buttonShadow.Size = UDim2.fromScale(1, 1)
	buttonShadow.Position = UDim2.fromOffset(0, SHADOW_DROP)
	buttonShadow.BackgroundColor3 = Color3.new(0, 0, 0)
	buttonShadow.BackgroundTransparency = SHADOW_TRANSPARENCY
	buttonShadow.BorderSizePixel = 0
	buttonShadow.Parent = frame
	corner(buttonShadow, UDim.new(0, 20))

	local toggle = Instance.new("TextButton")
	toggle.Name = "Toggle"
	toggle.Size = UDim2.fromScale(1, 1)
	toggle.BackgroundColor3 = CARD
	toggle.BorderSizePixel = 0
	toggle.AutoButtonColor = false
	toggle.Text = ""
	toggle.ZIndex = 2
	toggle.Parent = frame
	corner(toggle, UDim.new(0, 20))
	local toggleStroke = stroke(toggle, CARD_STROKE, 1.5, 0.2)
	toggle.Activated:Connect(onToggle)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 8)
	icon.Size = UDim2.fromOffset(44, 44)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = BUTTON_ICON
	icon.ZIndex = 3
	icon.Parent = toggle

	local caption = label(toggle, BUTTON_TEXT, 11, TEXT)
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0.5, 1)
	caption.Position = UDim2.new(0.5, 0, 1, -6)
	caption.Size = UDim2.new(1, -8, 0, 13)
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	caption.ZIndex = 3

	-- LE "+" EN COIN : il dit que le bouton OUVRE quelque chose. Sans lui, un bouton qui montre un outil se lit
	-- comme "l'outil", et on ne devine pas qu'il y a un menu derriere.
	local mark = Instance.new("Frame")
	mark.Name = "Badge"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.new(1, -4, 0, 4)
	mark.Size = UDim2.fromOffset(24, 24)
	mark.BackgroundColor3 = BADGE
	mark.BorderSizePixel = 0
	mark.ZIndex = 4
	mark.Parent = frame
	corner(mark, UDim.new(1, 0))
	stroke(mark, CARD, 2, 0)
	local plus = label(mark, "+", 18, CARD)
	plus.Size = UDim2.fromScale(1, 1)
	-- GothamBold pose son "+" un poil trop bas : un pixel de remontee le recentre dans le rond.
	plus.Position = UDim2.fromOffset(0, -1)
	plus.ZIndex = 5

	-- LE PANNEAU. Un `CanvasGroup` pour faire fondre TOUT d'un seul reglage : fondre chaque texte, chaque dessin
	-- et chaque contour un par un, c'est vingt tweens a tenir d'accord.
	local group = Instance.new("CanvasGroup")
	group.Name = "Menu"
	group.AnchorPoint = Vector2.new(0, 1)
	-- Le bas de la CARTE (pas du groupe, qui a sa marge d'ombre en plus) tombe a `MENU_GAP` au-dessus du bouton.
	group.Position = UDim2.fromOffset(-SHADOW_MARGIN, SHADOW_MARGIN + SHADOW_DROP - MENU_GAP)
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.GroupTransparency = 1
	group.Visible = false
	group.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Scale = CLOSED_SCALE
	scale.Parent = group

	local panelShadow = Instance.new("Frame")
	panelShadow.Name = "Shadow"
	panelShadow.Position = UDim2.fromOffset(SHADOW_MARGIN, SHADOW_MARGIN + SHADOW_DROP)
	panelShadow.BackgroundColor3 = Color3.new(0, 0, 0)
	panelShadow.BackgroundTransparency = SHADOW_TRANSPARENCY
	panelShadow.BorderSizePixel = 0
	panelShadow.Parent = group
	corner(panelShadow, UDim.new(0, 18))

	local panel = Instance.new("Frame")
	panel.Name = "Card"
	panel.Position = UDim2.fromOffset(SHADOW_MARGIN, SHADOW_MARGIN)
	panel.BackgroundColor3 = CARD
	panel.BorderSizePixel = 0
	panel.Parent = group
	corner(panel, UDim.new(0, 18))
	stroke(panel, CARD_STROKE, 1.5, 0.2)

	local header = label(panel, HEADER_TEXT, 12, SOFT_TEXT)
	header.Name = "Header"
	header.Position = UDim2.fromOffset(PAD + 6, PAD)
	header.Size = UDim2.new(1, -(PAD + 6) * 2, 0, HEADER_H - 4)
	header.TextXAlignment = Enum.TextXAlignment.Left

	-- UN CLIC DANS LE MONDE FERME LE MENU. Un menu qui reste ouvert tant qu'on ne revise pas son bouton oblige a y
	-- revenir ; la, on choisit et on retourne au jeu. Les clics SUR une interface sont marques `gameProcessed` :
	-- ils ne ferment rien, donc cliquer une ligne ne coupe pas le menu avant d'avoir compte.
	outsideClick = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not open then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			ToolHudHandler.setOpen(false)
		end
	end)

	root, buttonIcon, buttonCaption, buttonStroke = frame, icon, caption, toggleStroke
	badge, menu, menuScale, card, shadow = mark, group, scale, panel, panelShadow

	-- SEUL ECRIVAIN DE `frame.Position` apres sa creation : le rangement. Rien d'autre ne deplace le bouton.
	local hidden = UDim2.new(ROOT_POS.X.Scale, ROOT_POS.X.Offset, 1, BUTTON + TUCK_MARGIN)
	PanelFocus.register(PANEL, {
		tuck = function(tucked: boolean, instant: boolean)
			if tucked and open then
				ToolHudHandler.setOpen(false)
			end
			local goal = if tucked then hidden else ROOT_POS
			if instant then
				frame.Position = goal
			else
				TweenService:Create(frame, if tucked then TUCK_OUT else TUCK_IN, { Position = goal }):Play()
			end
		end,
		close = function()
			ToolHudHandler.setOpen(false)
		end,
	})
	return frame
end

--- Une ligne du menu : le dessin dans son creux, le nom, et a droite ce que le clic va faire.
local function makeRow(entry: Entry, index: number, parent: Frame, onPick: (string) -> ()): TextButton
	local idleBg = if entry.held then HELD_BG else CARD

	local row = Instance.new("TextButton")
	row.Name = entry.label
	row.Position = UDim2.fromOffset(PAD, rowY(index))
	row.Size = UDim2.new(1, -PAD * 2, 0, ROW_H)
	row.BackgroundColor3 = idleBg
	row.BorderSizePixel = 0
	row.AutoButtonColor = false
	row.Text = ""
	row.Parent = parent
	corner(row, UDim.new(0, 14))
	-- LE CONTOUR VERT DIT CE QUI EST EN MAIN, en plus du fond pale : sur un ecran de telephone en plein soleil, un
	-- fond pale seul ne se distingue plus du blanc.
	if entry.held then
		stroke(row, HELD, 2, 0)
	end

	local well = Instance.new("Frame")
	well.Name = "Well"
	well.AnchorPoint = Vector2.new(0, 0.5)
	well.Position = UDim2.new(0, 5, 0.5, 0)
	well.Size = UDim2.fromOffset(42, 42)
	well.BackgroundColor3 = if entry.held then CARD else WELL
	well.BorderSizePixel = 0
	well.Parent = row
	corner(well, UDim.new(0, 11))

	if entry.icon then
		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.BackgroundTransparency = 1
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(0.8, 0.8)
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = entry.icon :: string
		image.Parent = well
	else
		-- SANS DESSIN, SON INITIALE. Le nom est deja ecrit a cote : un creux vide ferait croire a une image qui
		-- n'a pas charge.
		local initial = label(well, entry.label:sub(1, 1):upper(), 20, SOFT_TEXT)
		initial.Size = UDim2.fromScale(1, 1)
	end

	local pillW = 64
	local name = label(row, entry.label, 15, TEXT)
	name.Name = "ToolName"
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.Position = UDim2.new(0, 56, 0.5, 0)
	name.Size = UDim2.new(1, -(56 + pillW + 12), 0, 18)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd

	-- A DROITE, CE QUE LE CLIC VA FAIRE. En main : une pastille verte ; ailleurs : le verbe, discret. Le joueur
	-- lit l'etat avant de cliquer, au lieu de cliquer pour voir.
	local pill = Instance.new("Frame")
	pill.Name = "State"
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.new(1, -8, 0.5, 0)
	pill.Size = UDim2.fromOffset(pillW, 22)
	pill.BackgroundColor3 = HELD
	pill.BackgroundTransparency = if entry.held then 0 else 1
	pill.BorderSizePixel = 0
	pill.Parent = row
	corner(pill, UDim.new(1, 0))
	local state = label(pill, if entry.held then HELD_TEXT else EQUIP_TEXT, 11, if entry.held then CARD else SOFT_TEXT)
	state.Size = UDim2.fromScale(1, 1)

	row.MouseEnter:Connect(function()
		TweenService:Create(row, HOVER_EASE, { BackgroundColor3 = if entry.held then HELD_BG else HOVER }):Play()
		if not entry.held then
			state.TextColor3 = TEXT
		end
	end)
	row.MouseLeave:Connect(function()
		TweenService:Create(row, HOVER_EASE, { BackgroundColor3 = idleBg }):Play()
		if not entry.held then
			state.TextColor3 = SOFT_TEXT
		end
	end)
	row.Activated:Connect(function()
		onPick(entry.tool)
		-- ON FERME APRES LE CHOIX : on ouvre ce menu pour prendre un outil, pas pour le regarder.
		ToolHudHandler.setOpen(false)
	end)
	return row
end

--- REMPLIT LE MENU. `onPick` recoit la cle d'equipement de la ligne cliquee.
---
--- ON REFAIT LES LIGNES A CHAQUE FOIS. La liste des outils possedes et celui qui est en main viennent du monde :
--- corriger une ligne a la main serait un second etat a tenir d'accord avec lui.
function ToolHudHandler.fill(entries: { Entry }, onToggle: () -> (), onPick: (string) -> ())
	build(onToggle)
	local panel, group, panelShadow = card, menu, shadow
	if not (panel and group and panelShadow) then
		return
	end

	-- LE BOUTON PREND LE VISAGE DE L'OUTIL EN MAIN.
	local held: Entry? = nil
	for _, entry in entries do
		if entry.held then
			held = entry
		end
	end
	local icon, caption, outline = buttonIcon, buttonCaption, buttonStroke
	if icon and caption and outline then
		icon.Image = if held and held.icon then held.icon :: string else BUTTON_ICON
		-- ON NE TIENT RIEN : le dessin s'efface un peu. Plein, il ferait croire qu'on tient la cisaille.
		icon.ImageTransparency = if held then 0 else 0.45
		caption.Text = if held then (held :: Entry).label else BUTTON_TEXT
		outline.Color = if held then HELD else CARD_STROKE
		outline.Thickness = if held then 2.5 else 1.5
		outline.Transparency = if held then 0 else 0.2
	end

	for _, row in rows do
		row:Destroy()
	end
	table.clear(rows)

	local height = menuHeight(#entries)
	group.Size = UDim2.fromOffset(PANEL_W + SHADOW_MARGIN * 2, height + SHADOW_MARGIN * 2 + SHADOW_DROP)
	panel.Size = UDim2.fromOffset(PANEL_W, height)
	panelShadow.Size = UDim2.fromOffset(PANEL_W, height)

	for index, entry in entries do
		table.insert(rows, makeRow(entry, index, panel, onPick))
	end
end

--- Ouvre ou ferme le menu. Rend l'etat obtenu.
function ToolHudHandler.setOpen(on: boolean): boolean
	if on == open then
		return open
	end
	-- RANGE, IL NE S'OUVRE PAS : son panneau se deplierait depuis un bouton hors de l'ecran.
	if on and PanelFocus.isTucked(PANEL) then
		return open
	end
	open = on
	applyOpen(on)
	return open
end

function ToolHudHandler.isOpen(): boolean
	return open
end

--- Montre ou cache le HUD entier : il n'a rien a dire tant qu'on ne possede aucun outil.
function ToolHudHandler.setVisible(on: boolean)
	local frame = root
	if frame then
		frame.Visible = on
	end
	if not on and open then
		open = false
		applyOpen(false)
	end
end

--- Detruit tout. Celui qui cree est celui qui nettoie, et il nettoie TOUT.
function ToolHudHandler.destroy()
	openToken += 1
	PanelFocus.unregister(PANEL)
	local connection = outsideClick
	if connection then
		connection:Disconnect()
	end
	local holder = gui
	if holder then
		holder:Destroy()
	end
	gui, root, buttonIcon, buttonCaption, buttonStroke = nil, nil, nil, nil, nil
	badge, menu, menuScale, card, shadow, outsideClick = nil, nil, nil, nil, nil, nil
	open = false
	table.clear(rows)
end

return ToolHudHandler
