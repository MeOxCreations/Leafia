--!strict
-- LA BARRE DES OUTILS DU CAMION : une CARTE BLANCHE par outil, en bas de l'ecran, qui monte depuis le bord.
--
-- LES CARTES ARRIVENT UNE PAR UNE. Un panneau entier qui glisse d'un bloc annonce "voici une interface" ; des
-- cartes qui montent l'une apres l'autre annoncent "voici TES outils, les voila", et l'oeil les compte pendant
-- qu'elles arrivent. Le decalage est court -- assez pour se lire, pas assez pour qu'on attende la derniere.
--
-- BLANCHES SUR UN JEU VERT ET COLORE : elles se detachent sans avoir besoin d'un cadre sombre par-dessus la scene.
-- Le fond opaque qui entourait tout l'ensemble a disparu, et avec lui le rectangle qui mangeait le bas de l'ecran.
--
-- L'APERCU EST UN DESSIN QUAND IL EN EXISTE UN, et le VRAI MODELE 3D sinon (dans un `ViewportFrame`).
--
-- LE DESSIN GAGNE parce qu'il est fait POUR etre lu petit : un modele 3D depend de son angle, de son eclairage et
-- de sa silhouette, et deux outils sombres se ressemblent dans une case de cent pixels.
--
-- MAIS L'APERCU 3D RESTE, et c'est ce qui rend la barre increvable : un outil range dans la benne apparait ici
-- MEME sans dessin. Exiger une icone le ferait disparaitre de l'interface en attendant qu'on la dessine -- donc
-- une benne pleine et une barre vide, sans que rien ne le dise.
--
-- UNE CARTE PAR OUTIL, DEDANS OU DEHORS. Celui qui est sorti garde sa carte, effacee, avec un bouton BLEU qui le
-- RANGE : le geste inverse se fait au meme endroit que le geste aller, et le joueur voit d'un coup d'oeil ce
-- qu'il a deja pris. Une barre qui ne montrerait que ce qui reste ne dirait pas ou est le reste.
--
-- ELLE NE DECIDE RIEN. On lui donne une liste et une fonction a appeler ; ce qui est ouvert, ce qui est dehors et
-- ce qui vole est l'affaire du controller et du serveur.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TruckConfigs = require(ReplicatedStorage.Modules.Configs.TruckConfigs)

local TruckToolsHandler = {}

local player = Players.LocalPlayer

-- ===== LA RANGEE =====
-- EN BAS, CENTREE. C'est la place des interfaces qu'on utilise sans quitter le jeu des yeux : le regard y descend
-- et remonte. Au milieu de l'ecran, elle cacherait le camion dont elle parle.
local ROW_POS = UDim2.fromScale(0.5, 0.97)
local CARD_SIZE = UDim2.fromOffset(120, 152)
local CARD_GAP = 12

-- ===== L'ARRIVEE =====
-- CHAQUE CARTE MONTE DEPUIS SOUS L'ECRAN, a sa place dans le rang. Elle part tres bas -- plus bas que sa propre
-- hauteur -- pour etre VRAIMENT hors champ au depart : partie du bord, on la verrait deja a moitie.
local CARD_IN = UDim2.fromScale(0.5, 0.5)
local CARD_OUT = UDim2.fromScale(0.5, 3.2)
-- `Back` : elle depasse un peu sa place avant de se poser. C'est ce qui donne le poids -- une carte qui s'arrete
-- pile a sa place a l'air posee par un tableur.
local RISE = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FALL = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- LE DECALAGE ENTRE DEUX CARTES. Court : a 0.12 on attend la derniere, a 0 elles arrivent d'un bloc et l'effet
-- disparait.
local STAGGER = 0.055

-- ===== LES COULEURS =====
local CARD = Color3.fromRGB(255, 255, 255)
-- LE TEXTE EST SOMBRE, pas gris : sur blanc, un gris clair se lit mal sur un ecran de telephone en plein soleil.
local CARD_TEXT = Color3.fromRGB(32, 38, 46)
-- Le fond de la vignette : un blanc casse, juste assez different pour detourer l'objet sans faire une deuxieme
-- carte dans la carte.
local WELL = Color3.fromRGB(241, 244, 248)
local TITLE_COLOR = Color3.fromRGB(255, 255, 255)
-- LE TITRE PORTE UN CONTOUR SOMBRE. Ecrit en blanc sans contour, il disparait sur une facade claire -- et le
-- didacticiel se joue justement devant une maison beige.
local TITLE_STROKE = Color3.fromRGB(20, 26, 34)
-- LE VERT DU JEU, celui des taches : c'est la meme famille d'action -- avancer, prendre, faire.
local TAKE = Color3.fromRGB(98, 206, 59)
local TAKE_HOVER = Color3.fromRGB(126, 226, 88)
-- ET LE BLEU POUR RANGER. Une autre couleur parce que c'est le geste INVERSE : deux boutons verts cote a cote,
-- l'un qui sort et l'autre qui rentre, se cliquent l'un pour l'autre. La couleur dit le sens avant qu'on lise.
local BACK = Color3.fromRGB(64, 150, 226)
local BACK_HOVER = Color3.fromRGB(96, 178, 245)
-- ET LA CARTE D'UN OUTIL DEJA SORTI S'EFFACE UN PEU : il n'est plus la, et l'interface doit le dire sans un mot.
local OUT_IMAGE_TRANSPARENCY = 0.5
local OUT_CARD_TRANSPARENCY = 0.25

-- LE SURVOL SOULEVE LA CARTE de quelques pixels. Sans lui, rien ne dit qu'elle est vivante avant d'avoir clique.
local HOVER_LIFT = 6
local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- La camera de l'apercu. `FOV` serre = peu de perspective, donc l'objet ne se deforme pas dans le coin du cadre.
local VIEW_FOV = 28
-- De combien on recule, en MULTIPLE de la taille de l'objet : un rateau et un seau n'ont pas la meme taille, et
-- une distance fixe montrerait l'un en entier et l'autre en gros plan.
local VIEW_BACK = 1.9
-- L'angle de vue : de trois quarts et un peu de dessus, comme une vitrine. De face, un objet plat disparait.
local VIEW_YAW = 35
local VIEW_PITCH = 18

-- ===== LES MOTS =====
-- EN ANGLAIS, comme tout texte vu par le joueur.
local TAKE_TEXT = "TAKE"
local BACK_TEXT = "PUT BACK"
local TITLE_TEXT = "IN THE TRUCK"

local gui: ScreenGui? = nil
local root: Frame? = nil
local row: Frame? = nil
local titleLabel: TextLabel? = nil
local shown = false
-- LES CARTES DANS L'ORDRE DU RANG. Gardees pour les faire monter l'une apres l'autre : le layout donne leur
-- place, pas leur tour de passage.
local cards: { Frame } = {}
local hideToken = 0

local function getGui(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("ScreenGui")
	created.Name = "LeafiaTruckTools"
	created.ResetOnSpawn = false
	created.IgnoreGuiInset = true
	created.ScreenInsets = Enum.ScreenInsets.None
	-- Au-dessus du jeu mais SOUS les notifications : une alerte doit pouvoir passer par-dessus une vitrine.
	created.DisplayOrder = 55
	created.Parent = player:WaitForChild("PlayerGui")
	gui = created
	return created
end

-- Le cast est OBLIGATOIRE : luau-lsp ne resout pas `Instance.new("UICorner")` vers `UICorner`, et poser
-- `.CornerRadius` sur ce qu'il croit etre une `Instance` sort en erreur rouge.
local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.Parent = parent
end

--- L'APERCU 3D D'UN MODELE, cadre tout seul sur sa taille.
---
--- LE CLONE EST ANCRE ET SANS SCRIPT : un ViewportFrame ne simule rien, mais un modele qui arrive avec ses joints
--- et ses parts libres s'y affiche dans la pose ou la physique l'avait laisse.
local function preview(model: Model, parent: Instance, inside: boolean)
	-- LE DESSIN D'ABORD, s'il existe : fait pour etre lu petit, il gagne contre un rendu 3D dans une case de cent
	-- pixels. `Fit` et pas `Stretch` -- une icone etiree n'est plus l'objet qu'elle represente.
	local icon = TruckConfigs.TOOL_ICONS[model.Name]
	if icon then
		local image = Instance.new("ImageLabel")
		image.Name = "Preview"
		image.BackgroundTransparency = 1
		image.Image = icon
		-- SORTI, IL S'EFFACE. La carte reste -- c'est par elle qu'on le range -- mais elle ne doit pas se lire
		-- comme un outil disponible : l'oeil compte ce qui reste dans la benne avant de lire les boutons.
		image.ImageTransparency = if inside then 0 else OUT_IMAGE_TRANSPARENCY
		image.ScaleType = Enum.ScaleType.Fit
		image.Size = UDim2.fromScale(0.86, 0.86)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Parent = parent
		return
	end

	local view = Instance.new("ViewportFrame")
	view.Name = "Preview"
	view.BackgroundTransparency = 1
	view.Size = UDim2.fromScale(1, 1)
	view.Position = UDim2.fromScale(0.5, 0.5)
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.ImageTransparency = if inside then 0 else OUT_IMAGE_TRANSPARENCY
	view.Ambient = Color3.fromRGB(190, 190, 190)
	view.LightColor = Color3.fromRGB(255, 255, 255)
	view.Parent = parent

	local clone = model:Clone()
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			(d :: BasePart).Anchored = true
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	clone.Parent = view

	local camera = Instance.new("Camera")
	camera.FieldOfView = VIEW_FOV
	camera.Parent = view
	view.CurrentCamera = camera

	-- LA DISTANCE VIENT DE LA TAILLE DE L'OBJET, pas d'un chiffre pose a la main : un rateau et un seau n'ont pas
	-- la meme taille, et une distance fixe montrerait l'un en entier et l'autre en gros plan.
	local pivot, size = clone:GetBoundingBox()
	local reach = math.max(size.X, size.Y, size.Z) * VIEW_BACK
	local dir = CFrame.Angles(0, math.rad(VIEW_YAW), 0) * CFrame.Angles(math.rad(-VIEW_PITCH), 0, 0)
	camera.CFrame = CFrame.lookAt(pivot.Position + dir.LookVector * -reach, pivot.Position)
end

--- Fabrique une carte pour `model`. `inside` dit s'il est encore dans la benne ; `onClick` est appele avec son
--- nom quand on clique -- dans les deux sens, parce que c'est la PLACE de l'objet qui decide de ce que ca fait.
---
--- DEUX CADRES ET PAS UN : le PORTEUR prend sa place dans le rang (c'est lui que le layout range), et la CARTE
--- bouge librement a l'interieur. Animer directement ce que le layout positionne, c'est se battre contre lui a
--- chaque image.
local function makeCard(model: Model, inside: boolean, onClick: (string) -> (), parent: Instance): Frame
	local holder = Instance.new("Frame")
	holder.Name = model.Name
	holder.Size = CARD_SIZE
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ClipsDescendants = false
	holder.Parent = parent

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = if shown then CARD_IN else CARD_OUT
	card.BackgroundColor3 = CARD
	card.BackgroundTransparency = if inside then 0 else OUT_CARD_TRANSPARENCY
	card.BorderSizePixel = 0
	card.Parent = holder
	corner(card, 16)
	stroke(card, Color3.fromRGB(206, 214, 224), 1.5, 0.35)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 9)
	pad.PaddingBottom = UDim.new(0, 9)
	pad.PaddingLeft = UDim.new(0, 9)
	pad.PaddingRight = UDim.new(0, 9)
	pad.Parent = card

	-- LA VIGNETTE : un creux clair sous l'objet. Il detoure l'apercu sans ajouter un cadre, donc l'outil se lit
	-- meme quand il est clair ou tres fin.
	local well = Instance.new("Frame")
	well.Name = "Well"
	well.Size = UDim2.new(1, 0, 0, 76)
	well.BackgroundColor3 = WELL
	well.BorderSizePixel = 0
	well.Parent = card
	corner(well, 12)

	preview(model, well, inside)

	local name = Instance.new("TextLabel")
	name.Name = "ToolName"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 17)
	name.Position = UDim2.fromOffset(0, 81)
	name.Font = Enum.Font.GothamBold
	name.TextColor3 = CARD_TEXT
	name.TextTransparency = if inside then 0 else 0.35
	name.TextScaled = true
	-- LE NOM DU MODELE, tel quel. Une table de jolis noms serait une SECONDE source a tenir d'accord avec la
	-- benne : le jour ou l'un des deux bouge, l'interface annonce un outil qui n'existe plus.
	name.Text = model.Name
	name.Parent = card

	-- LE BOUTON DIT CE QUI VA SE PASSER, en mot ET en couleur. Vert il sort l'outil, bleu il le range : deux
	-- boutons verts cote a cote, l'un qui sort et l'autre qui rentre, se cliquent l'un pour l'autre.
	local idle = if inside then TAKE else BACK
	local over = if inside then TAKE_HOVER else BACK_HOVER

	local take = Instance.new("TextButton")
	take.Name = "Take"
	take.Size = UDim2.new(1, 0, 0, 30)
	take.Position = UDim2.new(0, 0, 1, -30)
	take.BackgroundColor3 = idle
	take.BorderSizePixel = 0
	take.AutoButtonColor = false
	take.Font = Enum.Font.GothamBold
	take.TextColor3 = Color3.fromRGB(255, 255, 255)
	take.TextScaled = true
	take.Text = if inside then TAKE_TEXT else BACK_TEXT
	take.Parent = card
	corner(take, 10)

	local textPad = Instance.new("UIPadding")
	textPad.PaddingTop = UDim.new(0, 6)
	textPad.PaddingBottom = UDim.new(0, 6)
	textPad.Parent = take

	-- LE SURVOL EST UN RETOUR, pas une decoration : sans lui, rien ne dit que la carte est cliquable avant d'avoir
	-- clique. Sur tactile il ne sert a rien et ne coute rien -- le tap declenche directement.
	--
	-- LA CARTE SE SOULEVE, pas seulement le bouton : c'est la carte entiere qui designe l'outil, et un survol qui
	-- ne touche qu'un rectangle de trente pixels se remarque a peine.
	local function lift(up: boolean)
		-- ON NE SOULEVE RIEN PENDANT QUE LA CARTE MONTE : les deux ecriraient la meme position, et le survol
		-- gagnerait -- la carte se planterait a mi-chemin sous la souris.
		if not shown then
			return
		end
		TweenService:Create(card, HOVER_TWEEN, {
			Position = if up then UDim2.new(0.5, 0, 0.5, -HOVER_LIFT) else CARD_IN,
		}):Play()
		take.BackgroundColor3 = if up then over else idle
	end
	take.MouseEnter:Connect(function()
		lift(true)
	end)
	take.MouseLeave:Connect(function()
		lift(false)
	end)
	take.Activated:Connect(function()
		onClick(model.Name)
	end)

	return card
end

local function build(): Frame
	local existing = root
	if existing and existing.Parent then
		return existing
	end
	local holder = getGui()

	-- LE CADRE RACINE N'A PLUS DE FOND. Les cartes se detachent toutes seules : un panneau sombre derriere elles
	-- ajouterait un rectangle qui mange le bas de l'ecran pour ne rien dire de plus.
	local frame = Instance.new("Frame")
	frame.Name = "Cards"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = ROW_POS
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.Size = UDim2.fromOffset(0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ClipsDescendants = false
	frame.Parent = holder

	local stack = Instance.new("UIListLayout")
	stack.FillDirection = Enum.FillDirection.Vertical
	stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Padding = UDim.new(0, 6)
	stack.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.LayoutOrder = 1
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromOffset(200, 18)
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = TITLE_COLOR
	title.TextScaled = true
	title.Text = TITLE_TEXT
	title.Parent = frame
	stroke(title, TITLE_STROKE, 2, 0.35)

	local list = Instance.new("Frame")
	list.Name = "Row"
	list.LayoutOrder = 2
	list.BackgroundTransparency = 1
	list.AutomaticSize = Enum.AutomaticSize.X
	list.Size = UDim2.fromOffset(0, CARD_SIZE.Y.Offset)
	list.ClipsDescendants = false
	list.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.Name
	layout.Padding = UDim.new(0, CARD_GAP)
	layout.Parent = list

	root, row, titleLabel = frame, list, title
	return frame
end

export type Entry = { model: Model, inside: boolean }

--- REMPLIT LA BARRE, et rend le nombre de cartes posees.
---
--- ON REFAIT TOUT A CHAQUE FOIS plutot que de modifier la carte qui change. Le monde est la SOURCE : ce qui est
--- dans la benne y est, ce qui est dehors porte sa marque. Corriger une carte a la main serait un second etat a
--- tenir d'accord avec lui, et c'est exactement ainsi que deux verites finissent par se contredire.
function TruckToolsHandler.fill(entries: { Entry }, onClick: (string) -> ()): number
	build()
	local list = row
	if not list then
		return 0
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	table.clear(cards)
	for _, entry in entries do
		table.insert(cards, makeCard(entry.model, entry.inside, onClick, list))
	end
	return #entries
end

--- Montre ou cache la barre. Idempotent : appelee deux fois de suite, elle ne rejoue rien.
---
--- LES CARTES MONTENT L'UNE APRES L'AUTRE, et redescendent de meme. Le `hideToken` sert au cas ou l'on rouvre
--- pendant la descente : les montees en retard d'une fermeture annulee ne doivent pas se declencher apres coup.
function TruckToolsHandler.setShown(on: boolean)
	if on == shown then
		return
	end
	shown = on
	local frame = root
	if not frame then
		return
	end
	hideToken += 1
	local token = hideToken
	if on then
		frame.Visible = true
	end
	local title = titleLabel
	if title then
		TweenService:Create(title, if on then RISE else FALL, {
			TextTransparency = if on then 0 else 1,
		}):Play()
		local outline = title:FindFirstChildOfClass("UIStroke")
		if outline then
			TweenService:Create(outline, if on then RISE else FALL, {
				Transparency = if on then 0.35 else 1,
			}):Play()
		end
	end
	for i, card in cards do
		-- A LA FERMETURE, LA DERNIERE PARTIE EN PREMIERE : le rang se vide du meme cote qu'il s'est rempli, ce qui
		-- se lit comme un retrait et pas comme une panne.
		local step = if on then i - 1 else #cards - i
		task.delay(step * STAGGER, function()
			if token ~= hideToken or not card.Parent then
				return
			end
			TweenService:Create(card, if on then RISE else FALL, {
				Position = if on then CARD_IN else CARD_OUT,
			}):Play()
		end)
	end
	if not on then
		-- ON NE CACHE QU'APRES LA DERNIERE, et seulement si personne ne l'a rouverte entre-temps : masquer tout de
		-- suite couperait la descente en plein vol.
		task.delay(#cards * STAGGER + FALL.Time, function()
			if token == hideToken and not shown then
				frame.Visible = false
			end
		end)
	end
end

--- Detruit tout. Celui qui cree est celui qui nettoie, et il nettoie TOUT.
function TruckToolsHandler.destroy()
	hideToken += 1
	local holder = gui
	if holder then
		holder:Destroy()
	end
	table.clear(cards)
	gui, root, row, titleLabel, shown = nil, nil, nil, nil, false
end

return TruckToolsHandler
