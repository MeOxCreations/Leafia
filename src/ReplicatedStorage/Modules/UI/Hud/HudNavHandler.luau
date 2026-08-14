--!strict
-- BARRE DE NAVIGATION du HUD (bas de l'ecran), style Leafia : cartes creme arrondies + accent vert + ombre douce (meme
-- langage visuel que la pastille PriceTag / la carte des TIPS). CADRE REUTILISABLE : la plupart des onglets pointent vers
-- des sections qui n'existent pas encore -> ils sont INERTES (ils se SELECTIONNENT visuellement et appellent le hook
-- HudNavHandler.onSelect(id), a brancher quand chaque section arrivera). La feuille centrale ouvrira l'ARBRE DE
-- COMPETENCES (placeholder pour l'instant). Le widget HORLOGE a droite est un placeholder (jour/nuit plus tard).
--
-- ICONES : fournies par le joueur. Colle l'ID de chaque logo dans TABS.icon / LEAF_ICON. Vide "" -> carre placeholder gris.
-- La currency (haut de l'ecran) est deja geree par CurrencyController -> pas touchee ici.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)

local player = Players.LocalPlayer
-- Sur TACTILE, les coins bas de l'ecran sont pris par le joystick (gauche) et le bouton de saut (droite). On passe donc
-- en ICONES SEULES (libelles caches) pour que la nav reste etroite et centree, loin des controles. TouchEnabled = capacite
-- stable (vraie en emulateur ET sur vrai mobile), le bon critere pour une decision de LAYOUT.
local TOUCH = UserInputService.TouchEnabled

local HL_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- transition douce du survol / selection
-- Sons UI PARTAGES (memes assets que ButtonSlime, dans SoundService.Sounds.UI). La nav opte-out du slime (LeafiaNoSlime)
-- donc elle avait perdu ces sons avec le mouvement -> on rebranche juste les SONS (clic + survol), pas le gonflement.
local HOVER_SOUND = { "Sounds", "UI", "HoverButtonSound" }
local CLICK_SOUND = { "Sounds", "UI", "PressButtonSound" }

-- FEUILLE centrale : au survol elle s'ETIRE vers le haut (comme une etiquette qu'on tire) ; on l'OUVRE par un GESTE
-- (clic MAINTENU + glissement vers le HAUT), pas un simple clic. Voir makeLeaf.
local LEAF_EXTEND_HOVER = 0.14 -- etirement au survol simple (fraction de la hauteur)
local LEAF_EXTEND_MAX = 0.55 -- etirement max en tirant vers le haut
local LEAF_DRAG_OPEN = 55 -- px de glissement vers le haut pour OUVRIR l'interface
local LEAF_EXTEND_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local HudNavHandler = {}

-- Hook appele au clic d'un onglet (id de TABS) ou "skilltree" pour la feuille. A remplacer quand les sections existeront.
HudNavHandler.onSelect = function(_id: string) end :: (string) -> ()

-- ===== STYLE (tokens) =====
-- selene: allow(unused_variable)
local GREEN = Color3.fromRGB(96, 165, 78) -- accent : token de palette garde pour les sections a venir
local GREEN_SOFT = Color3.fromRGB(204, 232, 201) -- fond de l'onglet SELECTIONNE (box arrondie qui s'affiche au clic)
local TEXT = Color3.fromRGB(96, 104, 86) -- libelle au repos
local TEXT_SEL = Color3.fromRGB(60, 120, 55) -- libelle selectionne
local SHADOW = Color3.fromRGB(80, 97, 65)
local PLACEHOLDER = Color3.fromRGB(205, 205, 200) -- carre gris quand l'icone n'est pas encore fournie

-- Nav PLUS GROSSE sur PC (grand ecran + labels), compacte sur tactile (icones seules, ecran serre). Regle a l'oeil.
local PC_SCALE = if TOUCH then 1 else 1.35
local PILL_H = 42 * PC_SCALE -- hauteur des cartes
local LEAF_D = 52 * PC_SCALE -- diametre du bouton feuille (depasse en haut = effet "eleve")
local ICON = 30 * PC_SCALE -- icone des onglets (~40 px sur PC, 30 sur mobile : garde la proportion pour ne pas deborder la pilule)
local TEXT_SIZE = 13 * PC_SCALE
local CORNER = 13 * PC_SCALE

-- ===== ICONES A REMPLIR PAR LE JOUEUR =====
local LEAF_ICON = "rbxassetid://117703108607506" -- feuille centrale (bouton arbre de competences)
local LEAF_TINT = Color3.fromRGB(97, 157, 28) -- teinte verte de la feuille
type TabDef = { id: string, label: string, icon: string, side: string }
local TABS: { TabDef } = {
	{ id = "build", label = "BUILD", icon = "rbxassetid://139674269210332", side = "left" },
	{ id = "clients", label = "CLIENTS", icon = "", side = "left" },
	{ id = "projets", label = "PROJETS", icon = "", side = "left" },
	{ id = "catalogue", label = "CATALOGUE", icon = "", side = "right" },
	{ id = "employes", label = "EMPLOYES", icon = "", side = "right" },
	{ id = "boutique", label = "BOUTIQUE", icon = "", side = "right" },
}

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

-- Coins HAUTS arrondis a fond, coins BAS carres (coupole) : la feuille pose a plat sur la barre et s'arrondit en haut.
-- Utilise les rayons PAR COIN de UICorner (BottomLeftRadius / BottomRightRadius). Cast `any` car ces champs ne sont pas
-- (encore) dans le dump d'API de luau-lsp. Si ta version de Roblox ne les supporte pas, ca throw -> me le dire.
local function domeCorner(inst: Instance)
	local c = Instance.new("UICorner") :: any
	c.CornerRadius = UDim.new(1, 0) -- tous les coins arrondis a fond...
	c.BottomLeftRadius = UDim.new(0, 0) -- ...sauf le bas, remis carre
	c.BottomRightRadius = UDim.new(0, 0)
	c.Parent = inst
end

-- Rayons PAR COIN (en SCALE) sur un UICorner neuf, en remplacant un eventuel UICorner deja pose. Champs individuels =
-- propriete recente absente du dump luau-lsp -> cast any (comme domeCorner). Chaque coin ecrit explicitement (tl, tr, br, bl).
local function customCorner(inst: Instance, tl: number, tr: number, br: number, bl: number)
	local old = inst:FindFirstChildOfClass("UICorner")
	if old then
		old:Destroy()
	end
	local c = Instance.new("UICorner") :: any
	c.TopLeftRadius = UDim.new(tl, 0)
	c.TopRightRadius = UDim.new(tr, 0)
	c.BottomRightRadius = UDim.new(br, 0)
	c.BottomLeftRadius = UDim.new(bl, 0)
	c.Parent = inst
end

-- Carte creme arrondie avec ombre douce derriere. Rend (wrapper a mettre dans un layout, card ou parenter le contenu).
local function makeCard(): (Frame, Frame)
	local wrapper = Instance.new("Frame")
	wrapper.BackgroundTransparency = 1
	wrapper.AutomaticSize = Enum.AutomaticSize.X
	wrapper.Size = UDim2.fromOffset(0, PILL_H)

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.fromScale(0.5, 0.55)
	shadow.Size = UDim2.fromScale(1, 1.12) -- scale PUR (n'affecte pas l'auto-size) ; a peine plus haute, decalee un poil bas
	shadow.BackgroundColor3 = SHADOW
	shadow.BackgroundTransparency = 0.85 -- ombre LEGERE
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	corner(shadow, CORNER)
	shadow.Parent = wrapper

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AutomaticSize = Enum.AutomaticSize.X
	card.Size = UDim2.fromScale(0, 1)
	card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	card.BorderSizePixel = 0
	card.ZIndex = 2
	corner(card, CORNER)
	card.Parent = wrapper

	return wrapper, card
end

-- Icone d'un onglet : ImageLabel si un ID est fourni, sinon un carre placeholder gris (pour voir ou ca va).
local function makeIcon(iconId: string): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = "Icon"
	img.Size = UDim2.fromOffset(ICON, ICON)
	img.BackgroundTransparency = if iconId ~= "" then 1 else 0.15
	img.BackgroundColor3 = PLACEHOLDER
	img.Image = iconId
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 3
	if iconId == "" then
		corner(img, 6)
	end
	return img
end

-- Etat de selection : on garde les boutons + un setter qui recolore.
local selected = "" -- aucun onglet selectionne par defaut (Build est une ACTION, pas une section a "rester" dessus)
local applySel: { [string]: () -> () } = {} -- id -> fonction qui applique l'etat visuel

local function setSelected(id: string)
	selected = id
	for tabId, fn in pairs(applySel) do
		fn()
		local _ = tabId
	end
end

-- Un onglet cliquable (icone + libelle). Le FOND du bouton lui-meme fond en vert au survol / a la selection (transition
-- douce). On anime la TRANSPARENCE (une couleur), jamais la taille -> aucun reflow, et l'auto-size reste intact (mettre
-- une frame en scale DANS un bouton auto-size casse tout et etire la nav pleine largeur -- erreur a ne pas refaire).
local function makeTab(parent: Instance, tab: TabDef)
	local btn = Instance.new("TextButton")
	btn.Name = tab.id
	btn.AutomaticSize = Enum.AutomaticSize.X
	-- Hauteur < carte (0.85) : la box selectionnee est INSET (petite marge haut/bas dans la pilule), centree par le row du
	-- groupe (VerticalAlignment.Center). X en auto (largeur = contenu). Le contenu (icone/label) reste centre dans le bouton.
	btn.Size = UDim2.fromScale(0, 0.85)
	btn.BackgroundColor3 = GREEN_SOFT
	btn.BackgroundTransparency = 1 -- transparent au repos (la carte creme apparait)
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.ZIndex = 3
	corner(btn, 12)
	btn.Parent = parent

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = btn

	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 8)
	row.Parent = btn

	local icon = makeIcon(tab.icon)
	icon.LayoutOrder = 1
	icon.Parent = btn

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.LayoutOrder = 2
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = TEXT_SIZE
	label.TextColor3 = TEXT
	label.Text = tab.label
	label.ZIndex = 3
	label.Visible = not TOUCH -- sur mobile : icones seules (un GuiObject invisible est ignore par le UIListLayout -> tab compacte)
	label.Parent = btn

	-- Fondu du FOND du bouton (une transparence, jamais la taille) : plein a la selection, doux au survol, transparent au repos.
	local hovered = false
	local function refresh()
		local on = selected == tab.id
		local t = if on then 0 elseif hovered then 0.45 else 1
		TweenService:Create(btn, HL_TWEEN, { BackgroundTransparency = t }):Play()
		label.TextColor3 = if (on or hovered) then TEXT_SEL else TEXT
	end
	applySel[tab.id] = refresh

	btn.MouseEnter:Connect(function()
		hovered = true
		refresh()
		if not TOUCH then
			SoundUtils.play(HOVER_SOUND) -- survol = PC seulement (pas de hover au doigt)
		end
	end)
	btn.MouseLeave:Connect(function()
		hovered = false
		refresh()
	end)
	btn.Activated:Connect(function()
		SoundUtils.play(CLICK_SOUND)
		setSelected(tab.id)
		HudNavHandler.onSelect(tab.id)
	end)
end

-- Une carte-groupe (creme) remplie des onglets d'un cote.
local function makeGroup(side: string): Frame
	local wrapper, card = makeCard()
	wrapper.Name = if side == "left" then "LeftGroup" else "RightGroup"

	-- Coins ASYMETRIQUES par cote (la pilule penche vers la feuille au centre) : haut EXTERIEUR bien rond (1), bas
	-- INTERIEUR demi-rond (0.5), les deux autres carres. Le shadow suit la meme forme pour ne pas depasser derriere.
	local shadow = wrapper:FindFirstChild("Shadow")
	if side == "left" then
		customCorner(card, 1, 0, 0.5, 0) -- tl, tr, br, bl
		if shadow then
			customCorner(shadow, 1, 0, 0.5, 0)
		end
	else
		customCorner(card, 0, 1, 0, 0.5)
		if shadow then
			customCorner(shadow, 0, 1, 0, 0.5)
		end
	end

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = card

	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	-- Centre : quand la pilule est ELARGIE pour egaler l'autre groupe (labels de longueurs differentes), les onglets
	-- restent centres dans la carte au lieu de coller a gauche.
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 4)
	row.Parent = card

	local order = 0
	local inner: GuiObject? = nil -- le tab ADJACENT A LA FEUILLE (le dernier a gauche, le premier a droite)
	for _, tab in ipairs(TABS) do
		if tab.side == side then
			order += 1
			makeTab(card, tab)
			local child = card:FindFirstChild(tab.id)
			if child and child:IsA("GuiObject") then
				child.LayoutOrder = order
				-- le plus proche de la feuille : PREMIER a droite (catalogue), DERNIER a gauche (projets)
				if side == "right" then
					inner = inner or child
				else
					inner = child
				end
			end
		end
	end
	-- La box de selection du tab COLLE a la feuille epouse la pilule sur son cote INTERIEUR : coin HAUT-interieur CARRE (0),
	-- coin BAS-interieur ROND A FOND (1) ; l'exterieur garde les 12px. Ne se voit qu'a la selection (le fond est transparent
	-- au repos). Rayons par coin = propriete recente absente du dump luau-lsp -> cast any.
	if inner then
		local c = inner:FindFirstChildOfClass("UICorner") :: any
		if c then
			if side == "left" then
				c.TopRightRadius = UDim.new(0, 0)
				c.BottomRightRadius = UDim.new(1, 0)
			else
				c.TopLeftRadius = UDim.new(0, 0)
				c.BottomLeftRadius = UDim.new(1, 0)
			end
		end
	end
	return wrapper
end

-- Bouton FEUILLE central (arbre de competences), plus grand -> depasse en haut = effet "eleve".
local function makeLeaf(): Frame
	local wrapper = Instance.new("Frame")
	wrapper.Name = "LeafHolder"
	wrapper.BackgroundTransparency = 1
	wrapper.Size = UDim2.fromOffset(LEAF_D, LEAF_D) -- carre = remplit la hauteur de la nav ; s'aligne en bas comme les pastilles

	local shadow = Instance.new("Frame")
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.fromScale(0.5, 0.55)
	shadow.Size = UDim2.fromOffset(LEAF_D + 4, LEAF_D + 4)
	shadow.BackgroundColor3 = SHADOW
	shadow.BackgroundTransparency = 0.85
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 4
	domeCorner(shadow)
	shadow.Parent = wrapper

	-- Ancree en BAS (0.5, 1) : quand on l'etire (survol / glissement), elle grandit vers le HAUT, le bas reste pose sur la
	-- barre -- l'effet "etiquette qu'on tire". Au repos, hauteur = LEAF_D (comme avant).
	local circle = Instance.new("TextButton")
	circle.Name = "Leaf"
	circle.AnchorPoint = Vector2.new(0.5, 1)
	circle.Position = UDim2.fromScale(0.5, 1)
	circle.Size = UDim2.fromOffset(LEAF_D, LEAF_D)
	circle.BackgroundColor3 = Color3.fromRGB(63, 99, 52)
	circle.AutoButtonColor = false
	circle.Text = ""
	circle.ZIndex = 5
	domeCorner(circle) -- coupole : haut arrondi, bas plat (pose sur la barre)
	circle.Parent = wrapper

	-- Icone CENTREE dans le circle (scale 0.5) : le circle etant ancre EN BAS et s'etirant vers le HAUT, son centre monte,
	-- donc l'icone MONTE avec le tiroir en restant au milieu du tab vert (jamais hors de lui). Rien a piloter a la main : le
	-- scale suit la taille du circle, elle remonte toute seule quand il se retracte.
	local icon = makeIcon(LEAF_ICON)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	-- Taille PROPORTIONNELLE au bouton (~45px sur PC), pas 45 fixe : sur mobile LEAF_D est plus petit (pas de PC_SCALE),
	-- un 45 fixe remplissait presque toute la feuille. 0.64 garde le meme ratio icone/bouton sur PC et mobile.
	local leafIconD = LEAF_D * 0.64
	icon.Size = UDim2.fromOffset(leafIconD, leafIconD)
	icon.ImageColor3 = LEAF_TINT -- feuille verte
	icon.ZIndex = 6
	icon.Parent = circle

	-- INTERACTION : PAS un simple clic. Au survol la feuille se souleve un peu (invite a "tirer l'etiquette"). On OUVRE
	-- l'interface par un GESTE : clic MAINTENU + glissement vers le HAUT au-dela de LEAF_DRAG_OPEN. Pendant le glissement la
	-- hauteur SUIT le curseur / doigt (retour direct) ; au franchissement du seuil on ouvre (onSelect), une fois par geste.
	local function extendTo(frac: number)
		TweenService:Create(circle, LEAF_EXTEND_TWEEN, { Size = UDim2.fromOffset(LEAF_D, LEAF_D * (1 + frac)) }):Play()
	end

	local hovering = false
	local dragging = false
	local dragStartY = 0
	local opened = false

	circle.MouseEnter:Connect(function()
		hovering = true
		if not TOUCH then
			SoundUtils.play(HOVER_SOUND)
		end
		if not dragging then
			extendTo(LEAF_EXTEND_HOVER)
		end
	end)
	circle.MouseLeave:Connect(function()
		hovering = false
		if not dragging then
			extendTo(0)
		end
	end)

	circle.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			opened = false
			dragStartY = input.Position.Y
			SoundUtils.play(CLICK_SOUND) -- retour de "prise"
		end
	end)

	-- Suivi du glissement en GLOBAL (le curseur / doigt peut sortir du bouton pendant le tir) ; on ne reagit que si un
	-- drag de la feuille est en cours.
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local up = dragStartY - input.Position.Y -- positif = tire vers le HAUT
			local p = math.clamp(up / LEAF_DRAG_OPEN, 0, 1)
			circle.Size = UDim2.fromOffset(LEAF_D, LEAF_D * (1 + p * LEAF_EXTEND_MAX)) -- hauteur suit le geste, direct
			icon.ImageColor3 = LEAF_TINT:Lerp(Color3.new(1, 1, 1), p) -- l'icone vire vers le BLANC au fil du glissement
			if up >= LEAF_DRAG_OPEN and not opened then
				opened = true
				HudNavHandler.onSelect("skilltree") -- OUVRE (arbre de competences, a construire plus tard)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if dragging then
				dragging = false
				extendTo(if hovering then LEAF_EXTEND_HOVER else 0) -- retour au repos (ou survol si le curseur est reste dessus)
				TweenService:Create(icon, LEAF_EXTEND_TWEEN, { ImageColor3 = LEAF_TINT }):Play() -- l'icone revient au vert
			end
		end
	end)
	return wrapper
end

-- Visibilite de la nav : affichee seulement quand le joueur a un PLOT (dans son jeu) ET pas en MODE BUILD (l'UI de build
-- prend le relais). Deux conditions -> une seule fonction, appelee quand l'une change.
local navGui: ScreenGui? = nil
local hiddenByBuild = false
local function updateVisible()
	if navGui then
		navGui.Enabled = player:GetAttribute("LeafiaPlot") ~= nil and not hiddenByBuild
	end
end

-- Cache la nav pendant le mode build (a brancher depuis le bootstrap sur l'ouverture / fermeture du build).
function HudNavHandler.setBuildActive(active: boolean)
	hiddenByBuild = active
	updateVisible()
end

local function mount()
	local playerGui = player:WaitForChild("PlayerGui", 30)
	if not playerGui or playerGui:FindFirstChild("LeafiaHudNav") then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "LeafiaHudNav"
	gui.ResetOnSpawn = false -- survit aux respawns
	gui.ScreenInsets = Enum.ScreenInsets.None -- coords plein ecran (gere aussi l'inset du BAS sur mobile) -> la nav colle au bord
	gui.DisplayOrder = 4
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui:SetAttribute("LeafiaNoSlime", true) -- pas d'effet slime sur la nav (il fait bouger le texte dans un layout auto-size)
	gui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	-- La NAV : UNE rangee centree en bas (groupe gauche + feuille + groupe droit + horloge). AnchorPoint bas-centre =
	-- toujours collee au bas de l'ecran. Elle s'auto-dimensionne a son contenu.
	local nav = Instance.new("Frame")
	nav.Name = "Nav"
	nav.AnchorPoint = Vector2.new(0.5, 1)
	nav.Position = UDim2.new(0.5, 0, 1, -7) -- effleure le bas de l'ecran (petit ecart fixe, pareil sur tout ecran)
	-- Auto-size sur les DEUX axes : la nav epouse son contenu (deja SCALE par le UIScale) en largeur ET en hauteur. Ancree
	-- en bas -> le contenu colle au bas quel que soit le scale (sinon une hauteur fixe laisse le contenu scale flotter en haut).
	nav.AutomaticSize = Enum.AutomaticSize.XY
	nav.Size = UDim2.new(0, 0, 0, 0)
	nav.BackgroundTransparency = 1
	nav.Parent = root

	-- Le UIScale va SUR la nav (son contenu), PAS sur le root : sinon il decalerait aussi les POSITIONS (la barre remonterait
	-- au milieu de l'ecran, cf le bug mobile). Ici il ne fait que reduire le CONTENU, l'ancrage bas-centre est preserve.
	local uiScale = Instance.new("UIScale") :: UIScale
	uiScale.Parent = nav

	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Bottom -- tout aligne en bas : la feuille (plus grande) depasse en HAUT seulement
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 10)
	row.Parent = nav

	local left = makeGroup("left")
	left.LayoutOrder = 1
	left.Parent = nav

	local leaf = makeLeaf()
	leaf.LayoutOrder = 2
	leaf.Parent = nav

	local right = makeGroup("right")
	right.LayoutOrder = 3
	right.Parent = nav

	-- Responsive : on MESURE la largeur naturelle de la nav (a l'echelle 1) puis on la reduit juste ce qu'il faut pour tenir
	-- dans l'ecran avec une marge. Marche PC comme mobile / tablette, quelle que soit la resolution.
	local function fit()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		uiScale.Scale = 1
		task.wait() -- laisser l'AutomaticSize se recalculer avant de mesurer
		local natural = nav.AbsoluteSize.X
		if natural > 0 then
			-- marge LARGE sur tactile : on laisse ~170px de chaque cote au joystick / bouton de saut (coins bas).
			local margin = if TOUCH then 340 else 24
			uiScale.Scale = math.clamp((camera.ViewportSize.X - margin) / natural, 0.35, 1)
		end
	end
	-- EGALISER les deux groupes : les labels de droite (CATALOGUE, EMPLOYES, BOUTIQUE) sont plus longs que ceux de gauche
	-- (BUILD, CLIENTS, PROJETS), donc la pilule droite etait plus large -> nav asymetrique, feuille pas centree. On mesure
	-- la largeur NATURELLE de chaque carte a l'echelle 1, et on force la plus etroite a la largeur de la plus large via une
	-- UISizeConstraint (contenu deja centre par le row). UNE fois (les labels ne changent pas) et AVANT fit (qui mesure la
	-- nav complete pour la mettre a l'echelle).
	task.spawn(function()
		local leftCard = left:FindFirstChild("Card")
		local rightCard = right:FindFirstChild("Card")
		if leftCard and leftCard:IsA("GuiObject") and rightCard and rightCard:IsA("GuiObject") then
			uiScale.Scale = 1
			task.wait() -- laisser l'auto-size poser les largeurs naturelles
			local w = math.max(leftCard.AbsoluteSize.X, rightCard.AbsoluteSize.X)
			local lc = Instance.new("UISizeConstraint")
			lc.MinSize = Vector2.new(w, 0)
			lc.Parent = leftCard
			local rc = Instance.new("UISizeConstraint")
			rc.MinSize = Vector2.new(w, 0)
			rc.Parent = rightCard
		end
		fit()
	end)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.spawn(fit)
		end)
	end

	setSelected("") -- aucun onglet actif au depart

	navGui = gui
	player:GetAttributeChangedSignal("LeafiaPlot"):Connect(updateVisible) -- (dis)apparait quand le joueur (dé)selectionne un plot
	updateVisible()
end

function HudNavHandler.init()
	task.spawn(mount) -- en fond : mount attend PlayerGui, ne bloque pas le boot
end

return HudNavHandler
