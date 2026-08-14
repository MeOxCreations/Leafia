--!strict
-- ECRAN "LOAD A COMPANY" (selection de save / company), construit ENTIEREMENT EN CODE (choix du joueur : design mobile
-- dedie, HolderStart / HolderListSelectSave retires de Studio). Ouvert par PlotSelectController au clic Claim ; il rend
-- START et BACK par CALLBACKS (il ne connait ni la camera ni le flux d'entree, c'est PlotSelectController qui pilote).
--
-- Donnees en MOCK pour l'instant (les 3 companies de la maquette) : le systeme de save les fournira plus tard, en
-- passant une vraie liste a open(). Le badge "hexagone" est approxime par un cadre arrondi (pas d'asset hexagone) :
-- brancher une image hexagone quand elle existe. Design MOBILE d'abord ; le PC aura son propre build (memes callbacks).

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local TileField = require(ReplicatedStorage.Modules.UI.Core.TileField)
local ButtonSlime = require(ReplicatedStorage.Modules.UI.Core.ButtonSlime)
local FormatUtils = require(ReplicatedStorage.Modules.Utils.FormatUtils)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local SideNotificationHandler = require(ReplicatedStorage.Modules.UI.Notification.SideNotificationHandler)

local LoadCompanyController = {}

-- Tactile = CAPACITE (stable, vraie dans l'emulateur ET sur vrai mobile ; fausse sur PC sans ecran tactile). Sert a
-- decider du LAYOUT du NameDialog (clavier a l'ecran sur tactile, vrai clavier sur PC), pas de l'input courant.
local IS_TOUCH = UserInputService.TouchEnabled

local player = Players.LocalPlayer

-- Un slot de save. empty = "nouvelle partie". active = la company en cours (badge ACTIVE).
export type Slot = {
	slot: number,
	empty: boolean,
	name: string,
	level: number?,
	money: number?,
	reputation: number?, -- points de reputation de la company
	hedgesTrimmed: number?, -- total de haies taillees (le compteur qui celebre le coeur du jeu)
	lastPlayed: string?,
	active: boolean,
}

export type OpenConfig = {
	parent: Instance, -- la ScreenGui LoadSaveUI : l'ecran vit DEDANS (pas dans un ScreenGui a part)
	plotName: string, -- affiche sur le bouton retour ("< Willow Lane")
	onStart: (Slot) -> (), -- START PLAYING : le slot choisi
	onBack: () -> (), -- retour a la selection de plot
}

-- MOCK : remplace par les vraies saves quand la persistance existera (open() prendra la liste en argument).
-- Par defaut un nouveau joueur a 0 save : les 3 slots sont VIDES. Les vraies data viendront du save serveur.
local MOCK_SLOTS: { Slot } = {
	{ slot = 1, empty = true, name = "Empty slot", active = false },
	{ slot = 2, empty = true, name = "Empty slot", active = false },
	{ slot = 3, empty = true, name = "Empty slot", active = false },
}

-- Couleurs (approximation de la maquette, A REGLER a l'oeil).
local CARD_BG = Color3.fromRGB(244, 248, 244)
local CARD_SELECTED_BG = Color3.fromRGB(250, 244, 220)
local CARD_STROKE_SELECTED = Color3.fromRGB(242, 190, 66)
local NAME_COLOR = Color3.fromRGB(62, 62, 62)
local INFO_COLOR = Color3.fromRGB(120, 140, 126)
local TAG_NEW = Color3.fromRGB(242, 186, 58)
local LABEL_STROKE = Color3.fromRGB(90, 131, 93) -- contour (UIStroke) des clones de LabelTemplate (tag + step badge)
local WHITE = Color3.fromRGB(255, 255, 255)

-- Badge hexagone (images Outline + Fond) et niveau : GRIS quand la carte n'est PAS selectionnee, ORANGE quand elle l'est.
local BADGE_OUTLINE_IMAGE = "rbxassetid://98534207212802"
local BADGE_FOND_IMAGE = "rbxassetid://80842701479373"
local BADGE_OUTLINE_OFF = Color3.fromRGB(165, 165, 165)
local BADGE_OUTLINE_ON = Color3.fromRGB(255, 169, 49)
local LEVEL_TEXT_OFF = Color3.fromRGB(122, 122, 122)
local LEVEL_TEXT_ON = Color3.fromRGB(255, 153, 64)

-- Puces d'info (argent / reputation / haies) : chip a coins arrondis en HAUT, carres en bas. La VALEUR est VERTE si le
-- nombre est positif, ROUGE s'il est negatif.
local STAT_BG = Color3.fromRGB(172, 133, 115)
local STAT_VALUE_POS = Color3.fromRGB(187, 255, 156)
local STAT_VALUE_NEG = Color3.fromRGB(182, 0, 0)
local STAT_LABEL = WHITE

-- Tag (ACTIVE / NEW) : sa couleur PULSE doucement entre deux verts, en boucle (effet vivant, smooth).
local TAG_PULSE_A = Color3.fromRGB(141, 182, 70)
local TAG_PULSE_B = Color3.fromRGB(158, 204, 52)
local TAG_PULSE_TWEEN = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

-- Compteur de DIAMANTS (monnaie PREMIUM, rare : achetee, sert a debloquer des features). Clone de LabelTemplate restyle
-- en blanc, pose a gauche du STEP badge. Valeur MOCK : le vrai solde viendra du systeme de monnaie (serveur).
local DIAMOND_COUNT = "0"
local DIAMOND_POS = UDim2.fromScale(0.9, 0.06)
local DIAMOND_SIZE = UDim2.fromScale(0.084, 0.04)
-- Le diamant PIVOTE doucement gauche-droite en boucle (pendule Sine). Decoratif : attire l'oeil sur le compteur.
local DIAMOND_ROT = 10 -- amplitude du pivot (degres, de -X a +X)
local DIAMOND_ROT_TWEEN = TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local DIAMOND_BG = Color3.fromRGB(255, 255, 255)
local DIAMOND_STROKE = Color3.fromRGB(85, 85, 85)
local DIAMOND_ICON_IMAGE = "rbxassetid://134567363025055"
-- A zero, on n'affiche PAS "0" (solde mort) mais un APPEL A L'ACTION qui pulse en couleur : ca attire l'oeil et le
-- clic (le compteur est deja cliquable). Quand un vrai solde > 0 existera, afficher le nombre a la place.
local DIAMOND_CTA_TEXT = "+SHOP"
local DIAMOND_CTA_A = Color3.fromRGB(188, 188, 188) -- gris clair
local DIAMOND_CTA_B = Color3.fromRGB(45, 45, 45) -- gris fonce
local DIAMOND_CTA_TWEEN = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

-- Pump occasionnel du tag (NEW / ACTIVE) : petit coup de zoom qui rebondit (slime), a intervalle un peu aleatoire.
local TAG_PUMP_SCALE = 1.18
local TAG_PUMP_MIN = 1.4 -- s : intervalle mini entre deux pumps
local TAG_PUMP_MAX = 3.2 -- s : intervalle maxi
local TAG_PUMP_UP = TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TAG_PUMP_DOWN = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- rebond slime au retour

-- Fond en tuiles de CET ecran : trou clair CENTRE horizontalement (0.5). Un decalage en fraction fixe se voyait trop a
-- droite sur grand ecran (ultrawide) ; centre, il reste au milieu quelle que soit la largeur. Reglable.
local LOAD_TILE_HOLE_X = 0.5
local LOAD_TILE_HOLE_Y = 0.5
local LOAD_TILE_HOLE_INNER = 0.42
local LOAD_TILE_HOLE_OUTER = 0.72

-- Check de selection : apparait un poil APRES la selection, avec un pop slime (ressort elastique = feel "prolonge").
local CHECK_DELAY = 0.1
local CHECK_POP = TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
-- Animation du BADGE au clic d'une carte : un tour complet (revient a l'endroit) ET, EN MEME TEMPS, un resize SLIME
-- PROLONGE (on ecrase d'un coup, puis rebond Elastic aux oscillations amorties = l'effet gelee qui se prolonge).
local BADGE_CLICK_SPIN = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BADGE_CLICK_POP = TweenInfo.new(0.9, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out) -- long = slime qui se prolonge
local BADGE_CLICK_POP_FROM = 0.6 -- ecrasement de depart (fraction de 1) : plus bas = slime plus marque
-- BORNES DE TAILLE du menu sur GRAND ecran : les elements sont en scale (fraction de l'ecran), donc sur ultrawide ils
-- gonflent. On plafonne leur taille EN PIXELS pour qu'ils restent nets, tout en gardant leur POSITION (cards a gauche,
-- boutons a droite). En dessous de ces tailles, tout scale normalement. A REGLER a l'oeil.
local CARD_LIST_MAX_W = 620 -- largeur max de la colonne de cartes (a gauche)
local TITLE_MAX_W = 640 -- largeur max du titre "LOAD A COMPANY"
-- Colonne de boutons a DROITE (EDIT / CHANGE PLOT / CONTINUE) : empiles par un UIListLayout, meme largeur, alignes.
-- Largeur en scale mais BORNEE (px) pour ne pas gonfler sur grand ecran ; hauteur des boutons en pixels (aspect stable).
-- Tailles du groupe (libelles + 3 boutons) a droite, EN PIXELS. Sur MOBILE (tactile) tout est nettement PLUS PETIT :
-- sinon les boutons prennent tout l'ecran. Sur PC, plus gros (grand ecran, souris). Le groupe reste colle en bas a droite.
local BTN_COL_W = if IS_TOUCH then 190 else 410 -- largeur de la colonne de boutons (px)
local BTN_HEIGHT = if IS_TOUCH then 54 else 104 -- hauteur d'un bouton (px ; > 44 = tappable au doigt)
local BTN_GAP = if IS_TOUCH then 8 else 13 -- espace vertical entre deux boutons (px)
local LABELS_W = if IS_TOUCH then 130 else 320 -- largeur de la zone de libelles, a GAUCHE des boutons (px)
local GROUP_GAP = if IS_TOUCH then 10 else 20 -- espace horizontal entre libelles et boutons (px)
local LABEL_SLOT_H = if IS_TOUCH then 15 else 32 -- hauteur du libelle "CONTINUE IN SLOT x" (px)
local LABEL_MODE_H = if IS_TOUCH then 34 else 78 -- hauteur du libelle du nom de la save (px)
-- Slide d'entree des cartes : chacune arrive de la GAUCHE (hors ecran) a sa place, UNE PAR UNE (decalage CARD_STAGGER),
-- rebond slime. CARD_STEP = pas vertical entre deux cartes (hauteur + padding), vu qu'on les pose sans UIListLayout.
local CARD_STEP = 0.27
local CARD_HOVER = 0.02 -- gonflement au survol des cartes (defaut ButtonSlime = 0.05) : effet plus discret sur les grosses cartes
-- Poubelle (DELETE) : icone + fond rouge arrondi, cachee DERRIERE la carte (ZIndex 0) au centre, glisse sur le cote droit
-- a la selection. Y de la poubelle = centre vertical de la carte (carte : anchor (0.5, 0), hauteur 0.25 -> +0.125).
local TRASH_IMAGE = "rbxassetid://111806971740207"
local TRASH_BG = Color3.fromRGB(230, 58, 61)
local TRASH_SLIDE = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TRASH_HIDDEN_X = 0.5 -- centre de la carte (cachee derriere)
local TRASH_SHOWN_X = 1.08 -- glissee : depasse le bord droit de la carte (decalee pour ne pas coller)
local function trashPos(index: number, shown: boolean): UDim2
	return UDim2.fromScale(if shown then TRASH_SHOWN_X else TRASH_HIDDEN_X, (index - 1) * CARD_STEP + 0.06)
end
local CARD_SLIDE = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CARD_STAGGER = 0.09
-- Entree du top bar (StepBadge + diamant) : il deboule du HAUT quand le loading screen s'enleve.
local TOPBAR_SLIDE = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local FONT_TITLE = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local FONT_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local FONT_BODY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
local FONT_STAT_VALUE = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy) -- Montserrat Black
local FONT_STAT_LABEL = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium)
local FONT_DIAMOND_CTA = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Light)

-- Etat (l'UI est construite UNE fois puis reutilisee : reset a chaque open). root = le panneau, enfant de LoadSaveUI.
local root: Frame? = nil
local tileHandle: TileField.Handle? = nil -- fond en tuiles de cet ecran (visible seulement quand l'ecran est affiche)
local fontGradient: Frame? = nil -- voile blanc de fond GLOBAL (ZIndex -5) : ecran de plot ET Load Company. Cree une fois.
local cardFrames: { TextButton } = {} -- les cartes dans l'ordre : slide d'entree UNE PAR UNE (staggered) a l'ouverture
local cardHomes: { UDim2 } = {} -- leur position d'origine (parallele a cardFrames)
local slotLabel: TextLabel? = nil -- "STARTING FRESH IN SLOT 3"
local modeLabel: TextLabel? = nil -- "New company" / nom de la company
local startTextLabel: TextLabel? = nil -- libelle du bouton BUILD : CONTINUE (save existante) ou CREATE (slot vide)
local stepTextLabel: TextLabel? = nil -- texte du StepBadge (top bar partage) : "STEP 1 OF 2" (plot) / "STEP 2 OF 2" (saves)
local cardSetters: { (boolean) -> () } = {} -- un par carte : passe la carte en (des)selectionnee
local slots: { Slot } = {}
local selectedIndex = 1
-- Pendant l'anim d'ENTREE des cartes (construction du menu), on ne sort PAS la corbeille : sinon elle apparait SEULE, hors
-- carte, un court instant (la carte glisse encore). On la sort une fois les cartes arrivees (voir open).
local suppressTrashSlide = false
local currentConfig: OpenConfig? = nil
-- Modal de nommage d'une nouvelle save (clic CREATE sur un slot VIDE) : cree une fois, cache par defaut.
local nameDialogFrame: Frame? = nil
local nameDialogBox: TextBox? = nil
local nameDialogTitle: TextLabel? = nil -- titre du modal : "SAVE NAME" (create) ou "EDIT SAVE NAME" (edit)
local nameDialogOnConfirm: ((string) -> ())? = nil
-- Dialogue de SUPPRESSION (confirmation "hold to delete"). deleteSlotIndex = slot vise pendant que le modal est ouvert.
local deleteDialogFrame: Frame? = nil
local deleteDialogNameLabel: TextLabel? = nil
local deleteSlotIndex = 0
local nameBuffer = "" -- saisie brute du clavier custom (minuscules + espaces), affichee en Title Case dans le champ
local editButtonRef: GuiObject? = nil -- bouton EDIT (renommer) : visible seulement quand un slot REMPLI est selectionne
local cardLabelTemplate: Instance? = nil -- LabelTemplate (tags NEW / ACTIVE), garde pour reconstruire une carte apres suppression
-- Poubelles (une par carte REMPLIE) : cachees DERRIERE la carte (ZIndex 0) au centre, glissent sur le cote quand la carte
-- est selectionnee. Cliquer une poubelle ouvre le modal de suppression du slot correspondant.
local trashButtons: { [number]: ImageButton } = {}
local stepBadgeRef: GuiObject? = nil
local diamondRef: GuiObject? = nil

-- Petit constructeur UI : cree une instance, applique les props, et parente les enfants passes via la cle "Children".
local function create(className: string, props: { [string]: any }): Instance
	local inst = Instance.new(className)
	local children = props.Children :: { Instance }?
	props.Children = nil
	for k, v in props do
		(inst :: any)[k] = v
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	return inst
end

-- Renvoie Instance (pas UICorner) : ces coins ne servent qu'a etre parentes via Children. Un tableau Children dont le
-- 1er element est type UICorner ferait croire a luau-lsp que TOUT le tableau doit etre des UICorner -> il rejette les
-- autres enfants (Frame, TextLabel...). Renvoyer Instance garde les Children homogenes.
local function corner(radius: number): Instance
	return create("UICorner", { CornerRadius = UDim.new(radius, 0) })
end

-- UICorner : coins arrondis (radius) SAUF ceux nommes dans squareCorners, remis a 0. ORDRE VOLONTAIRE : on pose
-- CornerRadius (qui ecrit les 4 coins) PUIS on remet les coins voulus a 0 -- via create() l'ordre des props n'est pas
-- garanti et CornerRadius ecraserait les individuels ; ici il est garanti. Rayons individuels = propriete recente -> any.
local function cornerExcept(radius: number, squareCorners: { string }): Instance
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(radius, 0)
	local anyC = c :: any
	for _, name in squareCorners do
		anyC[name] = UDim.new(0, 0)
	end
	return c
end

-- Selectionne le slot d'index donne : met a jour les cartes et le panneau de depart.
local function selectSlot(index: number)
	selectedIndex = index
	for i, setter in cardSetters do
		setter(i == index)
	end
	local slot = slots[index]
	if not slot then
		return
	end
	if slotLabel then
		slotLabel.Text = if slot.empty
			then string.format("STARTING FRESH IN SLOT %d", slot.slot)
			else string.format("CONTINUE IN SLOT %d", slot.slot)
	end
	if modeLabel then
		modeLabel.Text = if slot.empty then "New company" else slot.name
	end
	if startTextLabel then
		startTextLabel.Text = if slot.empty then "CREATE" else "CONTINUE"
	end
	if editButtonRef then
		editButtonRef.Visible = not slot.empty -- EDIT (renommer) seulement sur une company existante
	end
	-- Poubelles : celle du slot SELECTIONNE sort en glissant ; les autres restent cachees (centre, derriere la carte).
	for i, trash in trashButtons do
		if i == index and not suppressTrashSlide then
			trash.Visible = true
			TweenService:Create(trash, TRASH_SLIDE, { Position = trashPos(i, true) }):Play()
		else
			trash.Visible = false
			trash.Position = trashPos(i, false)
		end
	end
end

-- Index selectionne par defaut a l'ouverture : la company ACTIVE si elle existe, sinon le 1er slot vide, sinon le 1er.
local function defaultIndex(): number
	for i, slot in slots do
		if slot.active then
			return i
		end
	end
	for i, slot in slots do
		if slot.empty then
			return i
		end
	end
	return 1
end

-- Une PUCE de stat : valeur en haut, libelle en bas, coins arrondis en haut / carres en bas (forme "onglet").
local function makeStatChip(n: number, prefix: string, label: string): Frame
	return create("Frame", {
		BackgroundColor3 = STAT_BG,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.335, 5.1),
		Children = {
			cornerExcept(0.18, { "BottomLeftRadius", "BottomRightRadius" }),
			create("TextLabel", {
				Name = "Value",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(0.9, 0.45),
				Position = UDim2.fromScale(0.5, 0.33),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Text = prefix .. FormatUtils.Abbreviate(n),
				TextColor3 = if n >= 0 then STAT_VALUE_POS else STAT_VALUE_NEG,
				FontFace = FONT_STAT_VALUE,
				TextScaled = true,
			}),
			create("TextLabel", {
				Name = "Label",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(0.9, 0.3),
				Position = UDim2.fromScale(0.5, 0.74),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Text = label,
				TextColor3 = STAT_LABEL,
				FontFace = FONT_STAT_LABEL,
				TextScaled = true,
			}),
		},
	}) :: Frame
end

-- Les 3 puces d'une company (argent / reputation / haies taillees), en ligne. Nombres abreges (12.5K...).
local function makeInfoStats(slot: Slot): Frame
	return create("Frame", {
		Name = "InfoStatsHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.55, 0.785),
		Size = UDim2.fromScale(0.75, 0.085),
		Children = {
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0.01, 0),
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			makeStatChip(slot.money or 0, "$", "EARNED"),
			makeStatChip(slot.reputation or 0, "", "REP"),
			makeStatChip(slot.hedgesTrimmed or 0, "", "HEDGES"),
		},
	}) :: Frame
end

-- Construit une carte de slot. Renvoie le bouton et un setter (on/off) qui pilote l'etat selectionne (couleurs badge,
-- niveau, contour, check).
local function makeCard(slot: Slot, index: number): (TextButton, (boolean) -> ())
	local badgeText = if slot.empty then "+" else tostring(slot.level or 0)
	local info = if slot.empty
		then "One mower, zero dollars"
		else "Last played " .. (slot.lastPlayed or "?")

	local stroke = create("UIStroke", { Thickness = 3, Color = CARD_STROKE_SELECTED, Enabled = false }) :: UIStroke
	-- Check : petit rond en bas a droite, signale LA carte selectionnee (pop slime a l'apparition via checkScale).
	local checkScale = create("UIScale", {}) :: UIScale
	local check = create("TextLabel", {
		Name = "Check",
		BackgroundColor3 = TAG_NEW,
		Size = UDim2.fromScale(0.25, 0.25),
		Position = UDim2.fromScale(0.985, 0.84),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "✓",
		TextColor3 = WHITE,
		FontFace = FONT_BOLD,
		TextScaled = true,
		Visible = false,
		Children = {
			cornerExcept(1, { "BottomLeftRadius" }),
			create("UIAspectRatioConstraint", {}),
			checkScale,
		},
	}) :: TextLabel

	-- Badge : Outline (contour hexagone, se colore a la selection) DERRIERE, Fond (blanc) legerement plus petit par
	-- dessus, niveau au-dessus. Refs gardees pour recolorer a la selection.
	local outlineImage = create("ImageLabel", {
		Name = "Outline",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Image = BADGE_OUTLINE_IMAGE,
		ImageColor3 = BADGE_OUTLINE_OFF,
	}) :: ImageLabel
	local levelText = create("TextLabel", {
		Name = "LevelPlayerDataText",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.72, 0.72),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = badgeText,
		TextColor3 = LEVEL_TEXT_OFF,
		FontFace = FONT_TITLE,
		TextScaled = true,
	}) :: TextLabel

	local badgeScale = create("UIScale", {}) :: UIScale
	local badgeFrame = create("Frame", {
		Name = "Badge",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.18, 0.6),
		Position = UDim2.fromScale(0.02, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
			badgeScale,
			create("UIAspectRatioConstraint", { AspectRatio = 0.91 }),
			outlineImage,
			create("ImageLabel", {
				Name = "Fond",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.999, 0.999),
				Image = BADGE_FOND_IMAGE,
				ImageColor3 = WHITE,
			}),
			levelText,
		},
	}) :: Frame

	local card = create("TextButton", {
		Name = "Card" .. index,
		BackgroundColor3 = CARD_BG,
		Size = UDim2.fromScale(1, 0.25),
		AnchorPoint = Vector2.new(0.5, 0),
		AutoButtonColor = false,
		Text = "",
		Children = {
			corner(0.18),
			stroke,
			badgeFrame,
			create("TextLabel", {
				Name = "NameText",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(0.62, 0.26),
				Position = UDim2.fromScale(0.75, 0.2),
				AnchorPoint = Vector2.new(1, 0.5),
				Text = slot.name,
				TextColor3 = NAME_COLOR,
				FontFace = FONT_TITLE,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			create("TextLabel", {
				Name = "InfoText",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(0.68, 0.118),
				Position = UDim2.fromScale(0.14, 0.36),
				AnchorPoint = Vector2.new(0, 0.5),
				Text = info,
				TextColor3 = INFO_COLOR,
				FontFace = FONT_BODY,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			check,
		},
	}) :: TextButton

	-- 3 puces de stats (argent / reputation / haies) : seulement pour une company EXISTANTE (rien sur un slot vide).
	if not slot.empty then
		makeInfoStats(slot).Parent = card
	end

	local function setSelected(on: boolean)
		card.BackgroundColor3 = if on then CARD_SELECTED_BG else CARD_BG
		stroke.Enabled = on
		outlineImage.ImageColor3 = if on then BADGE_OUTLINE_ON else BADGE_OUTLINE_OFF
		levelText.TextColor3 = if on then LEVEL_TEXT_ON else LEVEL_TEXT_OFF
		if on then
			-- Le Check apparait un poil APRES, avec un pop slime. Garde-fou : si on a change de carte entre-temps (clic
			-- rapide d'une carte a l'autre), on ne le montre pas -> pas de check fantome.
			task.delay(CHECK_DELAY, function()
				if selectedIndex ~= index then
					return
				end
				checkScale.Scale = 0
				check.Visible = true
				TweenService:Create(checkScale, CHECK_POP, { Scale = 1 }):Play()
			end)
		else
			check.Visible = false
		end
	end

	-- Feedback au clic : le badge fait un TOUR COMPLET (revient a l'endroit) + un resize slime prolonge, en meme temps. Visuel.
	local function playBadgePop()
		badgeFrame.Rotation = 0
		local spin = TweenService:Create(badgeFrame, BADGE_CLICK_SPIN, { Rotation = 360 })
		spin.Completed:Connect(function()
			badgeFrame.Rotation = 0 -- 360 == 0 : on remet a plat pour le prochain clic
		end)
		spin:Play()
		badgeScale.Scale = BADGE_CLICK_POP_FROM
		TweenService:Create(badgeScale, BADGE_CLICK_POP, { Scale = 1 }):Play()
	end

	card.Activated:Connect(function()
		playBadgePop()
		selectSlot(index)
	end)

	-- Hover slime plus DISCRET sur les cartes (gonflement reduit vs le defaut). On bind AVANT le controller global :
	-- bind est idempotent, donc notre reglage (hover faible) gagne, l'auto-bind qui suit skippe.
	ButtonSlime.bind(card, { hover = CARD_HOVER })

	return card, setSelected
end

-- Clone un template stylise du joueur (bouton OU label), le nomme, ecrit son libelle sur son enfant "Text", le place, et
-- renvoie (clone, cible de clic). La cible de clic = le bouton lui-meme s'il en est un (nil pour un label).
local function cloneTemplate(template: Instance, name: string, text: string, size: UDim2, position: UDim2, anchor: Vector2): (GuiObject, GuiButton?)
	local clone = template:Clone() :: GuiObject
	clone.Name = name
	clone.Visible = true
	clone.Size = size
	clone.Position = position
	clone.AnchorPoint = anchor
	local label = clone:FindFirstChild("Text", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
	return clone, (if clone:IsA("GuiButton") then clone else nil)
end

-- Force la couleur du contour (UIStroke direct) d'un clone de LabelTemplate (le template en porte une, on la remplace).
local function setLabelStroke(el: Instance)
	local s = el:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = LABEL_STROKE
	end
end

-- EDIT (renommer) : degrade violet vif -> rose clair, porte par le UIGradient. Fond BLANC pour que le gradient rende
-- ses couleurs EXACTES : un UIGradient MULTIPLIE le BackgroundColor3, donc un fond teinte fausserait les deux points.
local EDIT_COLOR_TOP = Color3.fromRGB(211, 41, 245) -- #d329f5 (point 1)
local EDIT_COLOR_BOTTOM = Color3.fromRGB(255, 187, 254) -- #ffbbfe (point 2)

local function recolorButton(button: GuiObject, top: Color3, bottom: Color3)
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	for _, d in button:GetDescendants() do
		if d:IsA("UIGradient") then
			d.Color = ColorSequence.new(top, bottom)
		end
	end
end

-- Effet "slash bling" sur un tag : le CanvasSlashVisual (CanvasGroup pose DANS le LabelTemplate, invisible par defaut)
-- devient visible, et ses slashs BALAIENT de gauche (hors champ) a droite (hors champ), vite, en boucle avec une pause.
-- Ne balaie que quand l'ecran est affiche. Geometrie DEVINEE (Y de repos capture, X balaye) : a regler a l'oeil.
local SLASH_SWEEP = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLASH_START_X = -0.6 -- X de depart (hors champ gauche)
local SLASH_END_X = 1.6 -- X d'arrivee (hors champ droite)
local SLASH_PERIOD = 2.5 -- secondes entre deux balayages

local function animateSlash(tag: Instance)
	local canvas = tag:FindFirstChild("CanvasSlashVisual", true)
	if not (canvas and canvas:IsA("GuiObject")) then
		return
	end
	canvas.Visible = true
	local slashes: { GuiObject } = {}
	local restY: { number } = {}
	for _, child in canvas:GetChildren() do
		if child:IsA("GuiObject") and string.find(child.Name, "Slash") ~= nil then
			table.insert(slashes, child)
			table.insert(restY, child.Position.Y.Scale)
		end
	end
	if #slashes == 0 then
		return
	end
	task.spawn(function()
		while canvas.Parent do
			if root and root.Visible then
				for i, s in slashes do
					s.Position = UDim2.fromScale(SLASH_START_X, restY[i])
					TweenService:Create(s, SLASH_SWEEP, { Position = UDim2.fromScale(SLASH_END_X, restY[i]) }):Play()
				end
			end
			task.wait(SLASH_PERIOD)
		end
	end)
end

-- Fait PULSER doucement la couleur du tag (ACTIVE / NEW) entre deux verts, en boucle (effet vivant). Le tween boucle
-- en reverse a l'infini ; pas besoin de le couper, l'ecran est transitoire.
local function pulseTag(tag: GuiObject)
	tag.BackgroundColor3 = TAG_PULSE_A
	TweenService:Create(tag, TAG_PULSE_TWEEN, { BackgroundColor3 = TAG_PULSE_B }):Play()
end

-- Fait "pomper" le tag de temps en temps : un coup de zoom rapide qui rebondit (slime), pas en continu. Attire l'oeil
-- sans fatiguer. Meme garde-fou que le slash : ne tourne QUE quand l'ecran est affiche, et s'arrete si le tag disparait.
local function pumpTag(tag: GuiObject)
	local scale = create("UIScale", { Scale = 1 }) :: UIScale
	scale.Parent = tag
	task.spawn(function()
		while tag.Parent do
			-- Intervalle un peu aleatoire : "assez frequent" sans etre metronomique.
			task.wait(TAG_PUMP_MIN + math.random() * (TAG_PUMP_MAX - TAG_PUMP_MIN))
			if root and root.Visible then
				scale.Scale = 1
				local up = TweenService:Create(scale, TAG_PUMP_UP, { Scale = TAG_PUMP_SCALE })
				up:Play()
				up.Completed:Wait()
				TweenService:Create(scale, TAG_PUMP_DOWN, { Scale = 1 }):Play()
			end
		end
	end)
end

-- Compteur de diamants a 0 : appel a l'action clignotant au lieu d'un "0" mort. Pulse la couleur du texte entre deux
-- teintes premium, en boucle. Quand un vrai solde arrivera, afficher le nombre (couleur fixe) a la place.
local function startDiamondCta(label: TextLabel)
	label.Text = DIAMOND_CTA_TEXT
	label.FontFace = FONT_DIAMOND_CTA
	label.TextColor3 = DIAMOND_CTA_A
	TweenService:Create(label, DIAMOND_CTA_TWEEN, { TextColor3 = DIAMOND_CTA_B }):Play()
end

-- Construit toute l'UI UNE fois (Frame enfant du parent = LoadSaveUI) et la met en cache.
-- Clavier CUSTOM du modal (pas le natif) : lettres d'un clavier normal, SANS accents ni symboles. Layout QWERTY
-- (remplacer KB_ROWS par les rangees azerty si voulu). Ce qu'on tape va dans nameBuffer (minuscules), affiche en
-- Title Case dans le champ. Derniere rangee : effacer, espace, valider.
local KB_ROWS = { "qwertyuiop", "asdfghjkl", "zxcvbnm" }
local KB_MAX_LEN = 22
local KB_KEY_BG = Color3.fromRGB(252, 252, 252)
local KB_KEY_TEXT = Color3.fromRGB(55, 55, 55)
local KB_SPECIAL_BG = Color3.fromRGB(206, 210, 206)
local KB_KEY_PRESS = Color3.fromRGB(252, 232, 154) -- couleur d'APPUI d'une touche (retour a sa couleur d'origine au relachement)

-- 1re lettre de chaque mot en majuscule (affichage + sauvegarde).
local function titleCase(s: string): string
	return (s:gsub("(%w+)", function(w)
		return w:sub(1, 1):upper() .. w:sub(2):lower()
	end))
end

local function refreshNameDisplay()
	local box = nameDialogBox
	if box then
		box.Text = titleCase(nameBuffer)
	end
end

-- Cache / re-affiche l'ecran de save (cartes, titre, boutons, tuiles + top bar) pour que le modal de nommage soit
-- SEUL et net, au lieu d'etre juste assombri par le backdrop.
local function setSaveScreenVisible(visible: boolean)
	if root then
		root.Visible = visible
	end
	if stepBadgeRef then
		stepBadgeRef.Visible = visible
	end
	if diamondRef then
		diamondRef.Visible = visible
	end
end

-- Filtre de nom (liste NOIRE cote client) pour un retour INSTANTANE (secousse rouge). Formes NORMALISEES : minuscules,
-- sans espaces ni ponctuation ("T.a Gueule" -> "tagueule", "MeOx Dev" -> "meoxdev"). IMPORTANT : pour un nom AFFICHE aux
-- autres joueurs, Roblox EXIGE le vrai filtre SERVEUR (TextService:FilterStringAsync), a brancher quand la save existera.
-- Cette liste ne le remplace PAS : elle donne juste le retour immediat sur les cas evidents. A etoffer / ajuster.
local BANNED_WORDS = {
	"tagueule", "tgueule", "tageule", "tageul", "tagueul", "tgeul", "fermela", "fermetagueule", "encule", "enculer",
	"enfoire", "fdp", "filsdepute", "pute", "putain",
	"merde", "connard", "conard", "connasse", "salope", "salaud", "nique", "niquer", "batard", "pede", "tapette",
	"bite", "couille", "chier", "bordel", "pisse", "fuck", "fuk", "shit", "bitch", "asshole", "cunt", "nigg",
	"faggot", "whore", "slut", "rape", "meoxdev", "meoxii", "admin", "moderator", "modo", "roblox", "staff",
}

local function isNameClean(name: string): boolean
	local norm = (name:lower():gsub("[%s%p]", "")) -- minuscules, sans espaces ni ponctuation
	for _, bad in BANNED_WORDS do
		if norm:find(bad, 1, true) then -- true = recherche PLATE (pas un motif)
			return false
		end
	end
	return true
end

-- Envoie le nom au VRAI filtre serveur (Roblox TextService, via le remote) et renvoie true s'il est propre. En cas
-- d'echec (remote absent, reseau), on REFUSE par securite : on ne laisse jamais passer un nom non verifie.
local filterRemote: RemoteFunction? = nil
local function filterNameOnServer(name: string): boolean
	if not filterRemote then
		local r = RemoteSetup.getRemote("FilterName", "Name")
		if r and r:IsA("RemoteFunction") then
			filterRemote = r
		end
	end
	local remote = filterRemote
	if not remote then
		return false
	end
	local ok, result = pcall(function()
		return remote:InvokeServer(name)
	end)
	if not ok or type(result) ~= "table" then
		return false
	end
	return (result :: any).ok == true
end

-- ===== SAVES (companies) : appels au serveur (CompanyService). ATTENTION : ca YIELD (InvokeServer). =====
local function invokeCompany(remoteName: string, ...: any): any
	local r = RemoteSetup.getRemote(remoteName, "Company")
	if not (r and r:IsA("RemoteFunction")) then
		return nil
	end
	local packed = table.pack(...)
	local ok, result = pcall(function()
		return r:InvokeServer(table.unpack(packed, 1, packed.n))
	end)
	return if ok then result else nil
end

-- Recupere les 3 slots REELS du serveur -> remplit `slots`. En cas d'echec, 3 slots vides (on peut toujours creer).
local function refreshCompanies()
	local views = invokeCompany("ListCompanies")
	slots = if type(views) == "table" then views else MOCK_SLOTS
end

local function createCompanyOnServer(slot: number, name: string): boolean
	local res = invokeCompany("CreateCompany", slot, name)
	return type(res) == "table" and (res :: any).ok == true
end

local function selectCompanyOnServer(slot: number): boolean
	local res = invokeCompany("SelectCompany", slot)
	return type(res) == "table" and (res :: any).ok == true
end

local function renameCompanyOnServer(slot: number, name: string): boolean
	local res = invokeCompany("RenameCompany", slot, name)
	return type(res) == "table" and (res :: any).ok == true
end

local function deleteCompanyOnServer(slot: number): boolean
	local res = invokeCompany("DeleteCompany", slot)
	return type(res) == "table" and (res :: any).ok == true
end

-- Modal de nommage (nouvelle save) : apparait au clic CREATE sur un slot VIDE, AVANT le loading. Cree une fois, cache
-- par defaut. Le backdrop est Active -> il bloque les clics derriere (vrai modal). Le champ est en LECTURE SEULE (pas de
-- clavier natif) : on saisit avec le clavier custom en dessous.
local function buildNameDialog(parent: Instance)
	if nameDialogFrame then
		return
	end

	local box = create("TextBox", {
		Name = "NameInput",
		BackgroundColor3 = Color3.fromRGB(236, 239, 236),
		Size = UDim2.fromScale(0.86, 0.35),
		Position = UDim2.fromScale(0.5, 0.48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "",
		PlaceholderText = "My Landscaping Co.",
		PlaceholderColor3 = Color3.fromRGB(150, 150, 150),
		TextColor3 = NAME_COLOR,
		FontFace = FONT_BODY,
		TextScaled = true,
		TextEditable = not IS_TOUCH, -- PC : on tape au VRAI clavier (box editable) ; tactile : lecture seule + clavier custom
		ClipsDescendants = true,
		ZIndex = 62,
		Children = {
			corner(0.25),
			create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		},
	}) :: TextBox

	-- Boutons CANCEL / CREATE : clones du TemplateButton stylise (comme START / CHANGE), pas des rectangles plats.
	local btnTemplate = parent:FindFirstChild("TemplateButton", true)
	local function dialogButton(btnName: string, text: string, pos: UDim2, cancel: boolean): GuiButton
		if btnTemplate and btnTemplate:IsA("GuiObject") then
			-- Le TemplateButton EST un bouton -> le clone aussi : cast en GuiButton, il sert et pour l'affichage et pour .Activated.
			local clone = cloneTemplate(btnTemplate, btnName, text, UDim2.fromScale(0.3, 0.26), pos, Vector2.new(0.5, 0.5)) :: GuiButton
			clone.ZIndex = 62
			-- Sous ZIndexBehavior Global, les enfants du template (ZIndex bas) passeraient DERRIERE le panneau (61). On
			-- remonte tout le sous-arbre au-dessus, en gardant l'ordre interne (offset constant). Inoffensif en Sibling.
			for _, d in clone:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex += 62
				end
			end
			local kb = clone:FindFirstChild("KeybindHolder", true)
			if kb and kb:IsA("GuiObject") then
				kb.Visible = false -- pas de raccourci clavier dans le modal
			end
			if cancel then
				-- CANCEL : degrade ROUGE (fond blanc pour que le gradient rende ses couleurs exactes), texte blanc, contour rouge fonce.
				recolorButton(clone, Color3.fromRGB(230, 58, 61), Color3.fromRGB(230, 114, 116))
				local ct = clone:FindFirstChild("Text", true)
				if ct and ct:IsA("TextLabel") then
					ct.TextColor3 = Color3.fromRGB(255, 255, 255)
					local ts = ct:FindFirstChildOfClass("UIStroke")
					if ts then
						ts.Color = Color3.fromRGB(144, 17, 17)
					end
				end
			end
			return clone
		end
		-- Fallback si le TemplateButton manque : bouton simple, pour ne pas casser le modal.
		local b = create("TextButton", {
			Name = btnName,
			BackgroundColor3 = if cancel then Color3.fromRGB(230, 58, 61) else TAG_PULSE_A,
			Size = UDim2.fromScale(0.3, 0.26),
			Position = pos,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Text = text,
			TextColor3 = WHITE,
			FontFace = FONT_TITLE,
			TextScaled = true,
			ZIndex = 62,
			Children = { corner(0.3) },
		}) :: TextButton
		return b
	end

	local confirmBtn = dialogButton("Confirm", "CREATE", UDim2.fromScale(0.68, 0.84), false)
	local cancelBtn = dialogButton("Cancel", "CANCEL", UDim2.fromScale(0.32, 0.84), true)

	local dialogTitle = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.86, 0.18),
		Position = UDim2.fromScale(0.5, 0.16),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "SAVE NAME", -- openNameDialog le passe a "EDIT SAVE NAME" en mode edit
		TextColor3 = NAME_COLOR,
		FontFace = FONT_TITLE,
		TextScaled = true,
		ZIndex = 62,
	}) :: TextLabel

	-- Coins du panneau : haut LEGEREMENT arrondi (0.06), bas TRES arrondi (0.8) -> forme voulue. CornerRadius pose les
	-- quatre, puis on remonte les deux du bas a 0.8. Rayons individuels = propriete recente -> cast any.
	local panelCorner = Instance.new("UICorner") :: UICorner
	panelCorner.CornerRadius = UDim.new(0.06, 0)
	local anyPanelCorner = panelCorner :: any
	anyPanelCorner.BottomLeftRadius = UDim.new(0.8, 0)
	anyPanelCorner.BottomRightRadius = UDim.new(0.8, 0)

	-- Sur PC (pas de clavier a l'ecran) le panneau est CENTRE (0.5, 0.5) ; sur tactile il reste HAUT pour laisser le
	-- clavier dessous. Taille bornee (UISizeConstraint) pour ne pas devenir enorme sur grand ecran.
	local panel = create("Frame", {
		Name = "Panel",
		BackgroundColor3 = Color3.fromRGB(248, 250, 248),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = if IS_TOUCH then UDim2.fromScale(0.5, 0.28) else UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.44, 0.26),
		ZIndex = 61,
		Children = {
			panelCorner :: Instance, -- cast : sinon le tableau se type { UICorner } et rejette les autres enfants
			dialogTitle,
			box,
			confirmBtn,
			cancelBtn,
			create("UISizeConstraint", { MaxSize = Vector2.new(760, 420) }),
		},
	})

	-- Le clavier vit SOUS le panneau. Rangees empilees (UIListLayout vertical) ; chaque rangee est un UIListLayout
	-- horizontal centre -> les rangees plus courtes restent centrees, touches de largeur uniforme.
	local keyboard = create("Frame", {
		Name = "Keyboard",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.68),
		Size = UDim2.fromScale(0.72, 0.48),
		Visible = IS_TOUCH, -- clavier a l'ecran SEULEMENT sur tactile ; sur PC on tape au vrai clavier
		ZIndex = 61,
		Children = {
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0.025, 0),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	})

	local backdrop = create("Frame", {
		Name = "NameDialog",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Active = true,
		Visible = false,
		ZIndex = 60,
		Children = { panel, keyboard },
	}) :: Frame

	backdrop.Parent = parent
	nameDialogFrame = backdrop
	nameDialogBox = box
	nameDialogTitle = dialogTitle

	-- Secousse ROUGE rapide gauche-droite du champ quand le nom est refuse (gros mot / usurpation). Ne relance pas si
	-- deja en cours. On decale la Position X du champ en va-et-vient qui s'amortit, texte en rouge, puis on remet tout.
	local shaking = false
	local function shakeRed()
		if shaking then
			return
		end
		shaking = true
		-- Warning lateral pour EXPLIQUER le refus (la secousse seule ne dit pas pourquoi).
		SideNotificationHandler.spawn({
			kind = "Warning",
			title = "Name not allowed",
			description = "That name isn't allowed. Pick a different one.",
			duration = 6,
		})
		local home = box.Position
		box.TextColor3 = Color3.fromRGB(215, 45, 45)
		task.spawn(function()
			local amp = 0.025
			for i = 1, 7 do
				local dir = if i % 2 == 0 then 1 else -1
				box.Position = UDim2.new(home.X.Scale + dir * amp, home.X.Offset, home.Y.Scale, home.Y.Offset)
				task.wait(0.035)
				amp *= 0.78
			end
			box.Position = home
			task.wait(0.35)
			box.TextColor3 = NAME_COLOR
			shaking = false
		end)
	end

	local filtering = false
	local function confirm()
		if filtering then
			return -- appel serveur en cours : on ignore les re-clics
		end
		-- Source du nom : sur PC on tape dans la box (vrai clavier) ; sur tactile c'est le buffer du clavier custom.
		local raw = if IS_TOUCH then nameBuffer elseif nameDialogBox then nameDialogBox.Text else ""
		local name = titleCase((raw:gsub("^%s+", ""):gsub("%s+$", ""))) -- trim + Title Case
		if name == "" then
			name = "My Company"
		end
		-- 1) Pre-check CLIENT (instantane) sur les cas evidents -> secousse immediate, sans meme appeler le serveur.
		if not isNameClean(name) then
			shakeRed()
			return
		end
		-- 2) VRAI filtre SERVEUR (Roblox TextService, async) : lui attrape tout le reste (toutes langues, leet, variantes).
		filtering = true
		task.spawn(function()
			local clean = filterNameOnServer(name)
			filtering = false
			if not clean then
				shakeRed() -- refuse par le filtre Roblox
				return
			end
			backdrop.Visible = false
			setSaveScreenVisible(true) -- re-affiche le menu ; onStart posera le rideau par-dessus juste apres
			local cb = nameDialogOnConfirm
			nameDialogOnConfirm = nil
			if cb then
				cb(name)
			end
		end)
	end
	local function appendChar(c: string)
		if #nameBuffer < KB_MAX_LEN then
			nameBuffer ..= c
			refreshNameDisplay()
		end
	end
	local function backspace()
		nameBuffer = nameBuffer:sub(1, -2)
		refreshNameDisplay()
	end
	confirmBtn.Activated:Connect(confirm)
	-- PC : Entree dans la box valide directement (sur tactile, c'est le bouton OK du clavier custom qui valide).
	if not IS_TOUCH then
		box.FocusLost:Connect(function(enterPressed: boolean)
			if enterPressed then
				confirm()
			end
		end)
	end
	cancelBtn.Activated:Connect(function()
		backdrop.Visible = false
		nameDialogOnConfirm = nil
		setSaveScreenVisible(true) -- retour a l'ecran de save
	end)

	-- Une touche : widthScale = fraction de la LARGEUR du clavier (touches uniformes).
	local function makeKey(labelText: string, widthScale: number, bg: Color3, textColor: Color3, onClick: () -> ()): TextButton
		local btn = create("TextButton", {
			Name = "Key_" .. labelText,
			BackgroundColor3 = bg,
			Size = UDim2.fromScale(widthScale, 1),
			Text = labelText,
			TextColor3 = textColor,
			FontFace = FONT_BOLD,
			TextScaled = true,
			AutoButtonColor = false, -- on gere la couleur d'appui a la main (InputBegan / InputEnded)
			ZIndex = 62,
			Children = {
				corner(0.16),
				create("UIPadding", {
					PaddingTop = UDim.new(0.2, 0),
					PaddingBottom = UDim.new(0.2, 0),
					PaddingLeft = UDim.new(0.08, 0),
					PaddingRight = UDim.new(0.08, 0),
				}),
			},
		}) :: TextButton
		btn.Activated:Connect(onClick)
		-- Retour visuel d'appui : la touche vire au jaune chaud tant qu'on la maintient, puis revient a sa couleur (bg).
		btn.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				btn.BackgroundColor3 = KB_KEY_PRESS
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

	local function makeRow(order: number): Frame
		return create("Frame", {
			Name = "Row" .. order,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0.2),
			LayoutOrder = order,
			Children = {
				create("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0.008, 0),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
		}) :: Frame
	end

	-- Rangees de lettres.
	for r, rowStr in KB_ROWS do
		local rowFrame = makeRow(r)
		for i = 1, #rowStr do
			local ch = rowStr:sub(i, i)
			local key = makeKey(ch:upper(), 0.088, KB_KEY_BG, KB_KEY_TEXT, function()
				appendChar(ch)
			end)
			key.LayoutOrder = i
			key.Parent = rowFrame
		end
		rowFrame.Parent = keyboard
	end

	-- Derniere rangee : effacer, espace (large), valider.
	local specialRow = makeRow(#KB_ROWS + 1)
	local delKey = makeKey("<", 0.16, KB_SPECIAL_BG, KB_KEY_TEXT, backspace)
	delKey.LayoutOrder = 1
	delKey.Parent = specialRow
	local spaceKey = makeKey("SPACE", 0.46, KB_SPECIAL_BG, KB_KEY_TEXT, function()
		appendChar(" ")
	end)
	spaceKey.LayoutOrder = 2
	spaceKey.Parent = specialRow
	local okKey = makeKey("OK", 0.16, TAG_PULSE_A, WHITE, confirm)
	okKey.LayoutOrder = 3
	okKey.Parent = specialRow
	specialRow.Parent = keyboard
end

-- Ouvre le modal de nommage : vide la saisie et l'affiche. PAS de focus natif (le champ est en lecture seule).
local function openNameDialog(onConfirm: (string) -> (), initialName: string?)
	if not nameDialogFrame then
		return
	end
	nameDialogOnConfirm = onConfirm
	nameBuffer = if initialName then initialName:lower() else "" -- pre-rempli pour EDIT (renommer), vide pour CREATE
	if nameDialogTitle then
		nameDialogTitle.Text = if initialName then "EDIT SAVE NAME" else "SAVE NAME"
	end
	refreshNameDisplay()
	setSaveScreenVisible(false) -- cacher l'ecran de save derriere : le modal est seul, net
	local frame = nameDialogFrame :: Frame
	frame.Visible = true
	-- PC : on donne le focus a la box pour taper tout de suite au vrai clavier.
	if not IS_TOUCH and nameDialogBox then
		nameDialogBox:CaptureFocus()
	end
end

-- Construit UNE carte (+ son tag NEW / ACTIVE) et l'enregistre dans les listes. Renvoie la carte NON PARENTEE : c'est
-- l'appelant qui la parente (build via la CardList, le DELETE via le parent de l'ancienne carte). Sert a reconstruire
-- une carte passee de REMPLIE a VIDE apres suppression, sans refaire tout l'ecran.
-- Forward-declare : spawnCard (ci-dessous) branche le clic de la poubelle sur openDeleteDialog, defini plus bas.
local openDeleteDialog: (index: number) -> ()

local function spawnCard(slot: Slot, index: number): TextButton
	local card, setter = makeCard(slot, index)
	local home = UDim2.fromScale(0.5, (index - 1) * CARD_STEP)
	card.Position = home
	cardFrames[index] = card
	cardHomes[index] = home
	cardSetters[index] = setter
	local labelTemplate = cardLabelTemplate
	if labelTemplate and labelTemplate:IsA("GuiObject") and (slot.empty or slot.active) then
		local tagText = if slot.empty then "NEW" else "ACTIVE"
		local tag = cloneTemplate(labelTemplate, "Tag", tagText, UDim2.fromScale(0.203, 0.243), UDim2.fromScale(0.98, 0.177), Vector2.new(1, 0.5))
		setLabelStroke(tag)
		-- Coin bas-gauche du tag CARRE (comme le check) : BottomLeftRadius a 0. Cast any (rayons individuels recents).
		local tagCorner = tag:FindFirstChildOfClass("UICorner")
		if tagCorner then
			local c = tagCorner :: any
			c.BottomLeftRadius = UDim.new(0, 0)
		end
		tag.Parent = card
		animateSlash(tag)
		pulseTag(tag)
		pumpTag(tag)
	end
	-- Poubelle DELETE : seulement pour un slot REMPLI. Cachee (Visible false) tant que la carte n'est pas selectionnee ;
	-- selectSlot la revele et la fait glisser. Clic -> modal de suppression du slot.
	if not slot.empty then
		local trash = create("ImageButton", {
			Name = "Trash",
			BackgroundColor3 = TRASH_BG,
			Image = "",
			AutoButtonColor = true,
			Visible = false,
			Size = UDim2.fromScale(0.12, 0.1),
			Position = trashPos(index, false),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 0,
			Children = {
				cornerExcept(0.3, { "BottomLeftRadius" }), -- coin bas-gauche carre (comme les tags)
				create("UIAspectRatioConstraint", { AspectRatio = 1 }),
				create("ImageLabel", {
					Name = "Icon",
					BackgroundTransparency = 1,
					Image = TRASH_IMAGE,
					Size = UDim2.fromScale(0.62, 0.62),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
				}),
			},
		}) :: ImageButton
		trash.Activated:Connect(function()
			openDeleteDialog(index)
		end)
		trashButtons[index] = trash
	end
	return card
end

-- Reconstruit la carte d'un slot SUR PLACE (apres DELETE : remplie -> vide). Detruit l'ancienne (ce qui STOPPE ses
-- boucles de tag, qui testent .Parent) et repose une carte neuve au meme endroit, meme parent.
local function rebuildCard(index: number)
	local old = cardFrames[index]
	local parent = if old then old.Parent else nil
	if old then
		old:Destroy()
	end
	local oldTrash = trashButtons[index]
	if oldTrash then
		oldTrash:Destroy()
		trashButtons[index] = nil
	end
	local card = spawnCard(slots[index], index)
	card.Parent = parent
	local newTrash = trashButtons[index] -- spawnCard en recree une si le nouveau slot est REMPLI
	if newTrash then
		newTrash.Parent = parent
	end
end

-- Modal de SUPPRESSION : confirmation par MAINTIEN (hold to delete). Cree une fois, cache par defaut.
local DELETE_HOLD_TIME = 1.0
local function buildDeleteDialog(parent: Instance)
	if deleteDialogFrame then
		return
	end

	local title = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.86, 0.16),
		Position = UDim2.fromScale(0.5, 0.14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "DELETE SAVE?",
		TextColor3 = NAME_COLOR,
		FontFace = FONT_TITLE,
		TextScaled = true,
		ZIndex = 62,
	})

	local nameLabel = create("TextLabel", {
		Name = "TargetName",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.86, 0.12),
		Position = UDim2.fromScale(0.5, 0.33),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = 'Delete "Save"?',
		TextColor3 = NAME_COLOR,
		FontFace = FONT_BODY,
		TextScaled = true,
		ZIndex = 62,
	}) :: TextLabel

	local warnLabel = create("TextLabel", {
		Name = "Warning",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.86, 0.09),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "This can't be undone.",
		TextColor3 = Color3.fromRGB(150, 60, 60),
		FontFace = FONT_BODY,
		TextScaled = true,
		ZIndex = 62,
	})

	-- HOLD TO DELETE et KEEP IT : clones du TemplateButton stylise (rouge / vert). Le HOLD recoit un remplissage (grandit
	-- au maintien) + son label PAR DESSUS. fill garde une ref pour le tween. Fallback en boutons simples si pas de template.
	local btnTemplate = parent:FindFirstChild("TemplateButton", true)
	local function styleClone(clone: GuiButton)
		clone.ZIndex = 62
		-- Sous ZIndexBehavior Global, les enfants du template (ZIndex bas) passeraient derriere le panneau : on remonte tout.
		for _, d in clone:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex += 62
			end
		end
		local kb = clone:FindFirstChild("KeybindHolder", true)
		if kb and kb:IsA("GuiObject") then
			kb.Visible = false
		end
	end

	local fill = create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.fromRGB(255, 120, 122),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Position = UDim2.fromScale(0, 0.5),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 2,
	}) :: Frame
	local holdLabel = create("TextLabel", {
		Name = "HoldLabel",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.9, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "HOLD TO DELETE",
		TextColor3 = WHITE,
		FontFace = FONT_TITLE,
		TextScaled = true,
		ZIndex = 10,
	}) :: TextLabel

	local holdBtn: GuiButton
	local keepBtn: GuiButton
	if btnTemplate and btnTemplate:IsA("GuiObject") then
		local hb = cloneTemplate(btnTemplate, "HoldToDelete", "", UDim2.fromScale(0.8, 0.17), UDim2.fromScale(0.5, 0.68), Vector2.new(0.5, 0.5)) :: GuiButton
		recolorButton(hb, Color3.fromRGB(205, 48, 50), Color3.fromRGB(150, 30, 32))
		styleClone(hb)
		-- Le remplissage vit dans un CanvasGroup qui le CLIP aux coins ARRONDIS du bouton (rendu propre, pas de coin carre
		-- qui depasse). Le CanvasGroup copie le rayon du UICorner du bouton pour coller pile a sa forme.
		local hbCorner = hb:FindFirstChildOfClass("UICorner") :: UICorner?
		local groupRadius = if hbCorner then hbCorner.CornerRadius else UDim.new(0.3, 0)
		fill.ZIndex = 1
		local fillClip = create("CanvasGroup", {
			Name = "FillClip",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 64,
			Children = {
				create("UICorner", { CornerRadius = groupRadius }),
				fill,
			},
		})
		fillClip.Parent = hb
		holdLabel.ZIndex = 72 -- le label reste par-dessus le remplissage
		holdLabel.Parent = hb
		holdBtn = hb

		local kp = cloneTemplate(btnTemplate, "KeepIt", "KEEP IT", UDim2.fromScale(0.8, 0.13), UDim2.fromScale(0.5, 0.89), Vector2.new(0.5, 0.5)) :: GuiButton
		styleClone(kp)
		keepBtn = kp
	else
		holdBtn = create("TextButton", {
			Name = "HoldToDelete",
			BackgroundColor3 = Color3.fromRGB(150, 40, 42),
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.fromScale(0.8, 0.17),
			Position = UDim2.fromScale(0.5, 0.68),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ClipsDescendants = true,
			Children = { corner(0.3), fill, holdLabel },
		}) :: TextButton
		keepBtn = create("TextButton", {
			Name = "KeepIt",
			BackgroundColor3 = TAG_PULSE_A,
			Text = "KEEP IT",
			TextColor3 = WHITE,
			FontFace = FONT_TITLE,
			TextScaled = true,
			Size = UDim2.fromScale(0.8, 0.13),
			Position = UDim2.fromScale(0.5, 0.89),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Children = { corner(0.3) },
		}) :: TextButton
	end

	-- Centre + taille BORNEE (UISizeConstraint) : en scale pur le panneau s'etirait enorme sur grand ecran (ultrawide).
	local panel = create("Frame", {
		Name = "Panel",
		BackgroundColor3 = Color3.fromRGB(248, 250, 248),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.42, 0.44),
		ZIndex = 61,
		Children = {
			corner(0.06),
			title,
			nameLabel,
			warnLabel,
			holdBtn,
			keepBtn,
			create("UISizeConstraint", { MaxSize = Vector2.new(720, 620) }),
		},
	})

	local backdrop = create("Frame", {
		Name = "DeleteDialog",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Active = true,
		Visible = false,
		ZIndex = 60,
		Children = { panel },
	}) :: Frame

	backdrop.Parent = parent
	deleteDialogFrame = backdrop
	deleteDialogNameLabel = nameLabel

	-- Maintien : le remplissage grandit sur DELETE_HOLD_TIME ; s'il TERMINE (non annule) -> suppression.
	local fillTween = TweenService:Create(fill, TweenInfo.new(DELETE_HOLD_TIME, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
	local function resetFill()
		fillTween:Cancel()
		fill.Size = UDim2.fromScale(0, 1)
	end
	local function closeDelete()
		resetFill()
		backdrop.Visible = false
		setSaveScreenVisible(true)
	end
	fillTween.Completed:Connect(function(state: Enum.PlaybackState)
		if state ~= Enum.PlaybackState.Completed then
			return -- annule (relache avant la fin) : on ne supprime pas
		end
		local idx = deleteSlotIndex
		local slot = slots[idx]
		if slot and not slot.empty and deleteCompanyOnServer(slot.slot) then
			slots[idx] = { slot = slot.slot, empty = true, name = "Empty slot", active = false }
			rebuildCard(idx)
			if idx == selectedIndex then
				selectSlot(idx) -- MAJ des libelles + visibilite EDIT / DELETE (le slot est vide maintenant)
			end
		end
		closeDelete()
	end)
	holdBtn.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			fill.Size = UDim2.fromScale(0, 1)
			fillTween:Play()
		end
	end)
	holdBtn.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resetFill()
		end
	end)
	holdBtn.MouseLeave:Connect(resetFill)
	keepBtn.Activated:Connect(closeDelete)
end

openDeleteDialog = function(index: number)
	if not deleteDialogFrame then
		return
	end
	local slot = slots[index]
	if not slot or slot.empty then
		return
	end
	deleteSlotIndex = index
	if deleteDialogNameLabel then
		deleteDialogNameLabel.Text = string.format('Delete "%s"?', slot.name)
	end
	setSaveScreenVisible(false)
	local frame = deleteDialogFrame :: Frame
	frame.Visible = true
end

local function build(parent: Instance): Frame
	if root then
		return root
	end

	cardSetters = {} -- `slots` est deja rempli par refreshCompanies() (appele dans open avant build)
	local labelTemplate = parent:FindFirstChild("LabelTemplate", true) -- pour les tags ACTIVE / NEW et le STEP badge
	cardLabelTemplate = labelTemplate -- garde pour reconstruire une carte apres un DELETE
	buildNameDialog(parent) -- modal de nommage (nouvelle save), cache par defaut
	buildDeleteDialog(parent) -- modal de suppression (hold to delete), cache par defaut

	-- Cartes empilees A LA MAIN (pas de UIListLayout) pour pouvoir les faire glisser UNE PAR UNE a l'ouverture.
	local cardChildren: { Instance } = {}
	for i, slot in slots do
		table.insert(cardChildren, spawnCard(slot, i))
	end

	-- slotLabel + modeLabel : A GAUCHE du bouton (qui occupe la droite du panneau). Alignes a droite, ils finissent avant
	-- le bouton -> plus de chevauchement.
	slotLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.56, 0.26),
		Position = UDim2.fromScale(0.56, 0.28),
		AnchorPoint = Vector2.new(1, 0.5),
		Text = "STARTING FRESH IN SLOT 3",
		TextColor3 = WHITE,
		FontFace = FONT_BODY,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
	}) :: TextLabel
	modeLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.56, 0.4),
		Position = UDim2.fromScale(0.56, 0.66),
		AnchorPoint = Vector2.new(1, 0.5),
		Text = "New company",
		TextColor3 = WHITE,
		FontFace = FONT_TITLE,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
	}) :: TextLabel
	-- START PLAYING (dans le panneau) et CHANGE PLOT (au-dessus, il remplace l'ancien bouton retour moche) : deux clones
	-- du TemplateButton stylise du joueur. Clic branche plus bas.
	local startButton: GuiObject?, startClick: GuiButton? = nil, nil
	local changeButton: GuiObject?, changeClick: GuiButton? = nil, nil
	local editButton: GuiObject?, editClick: GuiButton? = nil, nil
	local template = parent:FindFirstChild("TemplateButton", true)
	if template and template:IsA("GuiObject") then
		-- Meme taille pour les 3 (largeur = colonne, hauteur fixe) ; la position vient du UIListLayout, pas d'un scale
		-- hardcode. AnchorPoint (0,0) : la mise en page les aligne, l'anchor ne doit pas les decaler.
		local uniform = UDim2.new(1, 0, 0, BTN_HEIGHT)
		startButton, startClick =
			cloneTemplate(template, "StartButton", "BUILD", uniform, UDim2.new(), Vector2.new(0, 0))
		changeButton, changeClick =
			cloneTemplate(template, "ChangePlotButton", "CHANGE PLOT", uniform, UDim2.new(), Vector2.new(0, 0))
		local eb, ec =
			cloneTemplate(template, "EditButton", "EDIT", uniform, UDim2.new(), Vector2.new(0, 0))
		editButton, editClick = eb, ec
		recolorButton(eb, EDIT_COLOR_TOP, EDIT_COLOR_BOTTOM)
	else
		warn("[LoadCompany] Templates.TemplateButton introuvable : boutons START / CHANGE PLOT absents.")
	end

	-- KeybindHolder (la puce "E") de chaque bouton : repositionne en bas a droite du bouton.
	if startButton then
		local kb = startButton:FindFirstChild("KeybindHolder", true)
		if kb and kb:IsA("GuiObject") then
			kb.AnchorPoint = Vector2.new(0.5, 0.5)
			kb.Position = UDim2.fromScale(0.9, 0.753)
			kb.Size = UDim2.fromScale(0.3, 0.3)
		end
	end
	if changeButton then
		local kb = changeButton:FindFirstChild("KeybindHolder", true)
		if kb and kb:IsA("GuiObject") then
			kb.AnchorPoint = Vector2.new(0.5, 0.5)
			kb.Position = UDim2.fromScale(0.92, 0.753)
			kb.Size = UDim2.fromScale(0.3, 0.3)
		end
		local ct = changeButton:FindFirstChild("Text", true)
		if ct and ct:IsA("TextLabel") then
			ct.Size = UDim2.fromScale(0.75, 0.38)
			ct.Position = UDim2.fromScale(0.499, 0.55)
		end
	end
	if editButton then
		local kb = editButton:FindFirstChild("KeybindHolder", true)
		if kb and kb:IsA("GuiObject") then
			kb.Visible = false -- EDIT n'a pas de raccourci (E est deja pris par CHANGE PLOT / CONTINUE)
		end
		local stroke = editButton:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Color3.fromRGB(210, 72, 223) -- contour du bouton, violet vif
		end
		local ct = editButton:FindFirstChild("Text", true)
		if ct and ct:IsA("TextLabel") then
			ct.Size = UDim2.fromScale(0.75, 0.45)
			ct.Position = UDim2.fromScale(0.5, 0.52)
			local ts = ct:FindFirstChildOfClass("UIStroke")
			if ts then
				ts.Color = Color3.fromRGB(162, 95, 204) -- contour du texte, violet plus doux
			end
		end
		editButton.Visible = false -- cache par defaut ; selectSlot l'affiche sur un slot rempli
	end

	-- Libelle du bouton START (BUILD) : selectSlot le passe a CONTINUE (save existante) ou CREATE (slot vide).
	if startButton then
		local st = startButton:FindFirstChild("Text", true)
		if st and st:IsA("TextLabel") then
			startTextLabel = st
		end
	end

	-- Cote DROIT : deux blocs COTE A COTE (UIListLayout horizontal), colles en bas a droite ->
	--   [ libelles CONTINUE IN SLOT x / nom ]  [ colonne EDIT / CHANGE PLOT / CONTINUE ]
	-- Les libelles restent a GAUCHE des boutons quel que soit l'ecran (le groupe les colle). Tout glisse en BLOC a l'exit.

	-- Bloc des LIBELLES (a gauche), empiles, alignes a droite, colles en bas (VerticalAlignment Bottom).
	local labelsChildren: { Instance } = {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	if slotLabel then
		slotLabel.Size = UDim2.new(1, 0, 0, LABEL_SLOT_H)
		slotLabel.Position = UDim2.new()
		slotLabel.AnchorPoint = Vector2.new(0, 0)
		slotLabel.TextXAlignment = Enum.TextXAlignment.Right
		slotLabel.LayoutOrder = 1
		table.insert(labelsChildren, slotLabel)
	end
	if modeLabel then
		modeLabel.Size = UDim2.new(1, 0, 0, LABEL_MODE_H)
		modeLabel.Position = UDim2.new()
		modeLabel.AnchorPoint = Vector2.new(0, 0)
		modeLabel.TextXAlignment = Enum.TextXAlignment.Right
		modeLabel.LayoutOrder = 2
		table.insert(labelsChildren, modeLabel)
	end
	local labelsBox = create("Frame", {
		Name = "SaveLabels",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(LABELS_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Children = labelsChildren,
	})

	-- Bloc des BOUTONS (a droite) : meme largeur, empiles, espaces regulierement.
	local columnChildren: { Instance } = {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, BTN_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	local function addBtn(el: Instance?, order: number)
		if el then
			(el :: GuiObject).LayoutOrder = order
			table.insert(columnChildren, el)
		end
	end
	addBtn(editButton, 1)
	addBtn(changeButton, 2)
	addBtn(startButton, 3)
	local buttonColumn = create("Frame", {
		Name = "ButtonColumn",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(BTN_COL_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Children = columnChildren,
	})

	-- Groupe HORIZONTAL : libelles a gauche, boutons a droite, colle en bas a droite de l'ecran. Glisse en bloc a l'exit.
	local rightGroup = create("Frame", {
		Name = "RightGroup",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.985, 0.945),
		AutomaticSize = Enum.AutomaticSize.XY,
		Children = {
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				Padding = UDim.new(0, GROUP_GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			labelsBox,
			buttonColumn,
		},
	})

	-- Titre + liste de cartes crees A PART (pas inline) : on garde une ref pour les faire glisser hors ecran a l'exit.
	local titleInst = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.4, 0.06),
		Position = UDim2.fromScale(0.035, 0.2),
		AnchorPoint = Vector2.new(0, 0.5),
		Text = "LOAD A COMPANY",
		TextColor3 = WHITE,
		FontFace = FONT_TITLE,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local cardListInst = create("Frame", {
		Name = "CardList",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.312, 0.635),
		Position = UDim2.fromScale(0.035, 0.584),
		AnchorPoint = Vector2.new(0, 0.5),
		Children = cardChildren,
	})

	-- Bornes de taille sur GRAND ecran : cards a gauche et titre gardent leur position mais arretent de gonfler
	-- (UISizeConstraint plafonne l'AbsoluteSize). La colonne de boutons a droite a sa propre borne (voir plus haut).
	create("UISizeConstraint", { MaxSize = Vector2.new(CARD_LIST_MAX_W, math.huge) }).Parent = cardListInst
	create("UISizeConstraint", { MaxSize = Vector2.new(TITLE_MAX_W, math.huge) }).Parent = titleInst

	-- Le panneau vit DANS LoadSaveUI (parent), cache par defaut. Fond NOIR TRANSPARENT : on voit le plot qui orbite derriere.
	local rootFrame = create("Frame", {
		Name = "HolderLoadCompany",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Children = { titleInst, cardListInst, rightGroup },
	}) :: Frame

	-- Les poubelles (creees non parentees par spawnCard) rejoignent la CardList, EN FRERE de leur carte : c'est ce qui
	-- leur permet de passer DERRIERE la carte (ZIndex 0 < carte). Enfants de la carte, elles passeraient devant.
	for _, trash in trashButtons do
		trash.Parent = cardListInst
	end
	editButtonRef = editButton

	if startClick then
		startClick.Activated:Connect(function()
			if not currentConfig then
				return
			end
			local slot = slots[selectedIndex]
			if slot.empty then
				-- Nouvelle save : on demande d'abord un NOM, puis seulement on demarre (le loading vient apres).
				openNameDialog(function(name)
					-- Le serveur CREE la company (persiste + refiltre le nom). Si ok, on entre en jeu.
					if createCompanyOnServer(slot.slot, name) and currentConfig then
						currentConfig.onStart(slot)
					end
				end)
			else
				-- Slot rempli : on SELECTIONNE la company (ActiveSlot / LastPlayed), puis on entre en jeu.
				if selectCompanyOnServer(slot.slot) and currentConfig then
					currentConfig.onStart(slot)
				end
			end
		end)
	end
	if changeClick then
		changeClick.Activated:Connect(function()
			if currentConfig then
				currentConfig.onBack()
			end
		end)
	end
	if editClick then
		editClick.Activated:Connect(function()
			if not currentConfig then
				return
			end
			local idx = selectedIndex
			local slot = slots[idx]
			if not slot or slot.empty then
				return -- pas d'edit sur un slot vide (le bouton est cache, garde-fou)
			end
			-- Modal de nommage PRE-REMPLI avec le nom actuel. Validation : rename serveur, puis MAJ visuelle en place.
			openNameDialog(function(name)
				if not renameCompanyOnServer(slot.slot, name) then
					return
				end
				slot.name = name
				local card = cardFrames[idx]
				local nameText = if card then card:FindFirstChild("NameText", true) else nil
				if nameText and nameText:IsA("TextLabel") then
					nameText.Text = name
				end
				if idx == selectedIndex then
					selectSlot(idx) -- rafraichit les libelles du bas (nom de la company selectionnee)
				end
			end, slot.name)
		end)
	end

	-- Fond en tuiles PROPRE a cet ecran (trou clair CENTRE, derriere l'UI via ZIndex 0). Cache par defaut.
	local th = TileField.start({
		parent = rootFrame,
		name = "TileBg",
		zIndex = 0,
		holeCenterX = LOAD_TILE_HOLE_X,
		holeCenterY = LOAD_TILE_HOLE_Y,
		holeInner = LOAD_TILE_HOLE_INNER,
		holeOuter = LOAD_TILE_HOLE_OUTER,
	})
	th.setVisible(false)
	tileHandle = th

	rootFrame.Parent = parent
	root = rootFrame
	return rootFrame
end

-- Cree UNE FOIS le voile blanc de fond (FontGradient, ZIndex -5) dans LoadSaveUI. Backdrop GLOBAL : visible sur l'ecran
-- de plot ET sur Load Company. Il se cache tout seul avec la ScreenGui quand on entre dans le jeu. Appele au setup du plot.
function LoadCompanyController.ensureBackdrop(parent: Instance)
	if fontGradient then
		return
	end
	local fg = create("Frame", {
		Name = "FontGradient",
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.05, 1.05),
		ZIndex = -5,
		Children = {
			create("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.158, 0.819),
					NumberSequenceKeypoint.new(0.299, 0.956),
					NumberSequenceKeypoint.new(0.72, 1),
					NumberSequenceKeypoint.new(0.935, 1),
					NumberSequenceKeypoint.new(1, 0),
				}),
			}),
		},
	}) :: Frame
	fg.Parent = parent
	fontGradient = fg
end

-- Cree UNE FOIS le TOP BAR commun aux DEUX ecrans de selection (StepBadge + compteur de diamants) dans LoadSaveUI. Au-dessus
-- de tout (ZIndex 50) et toujours visible ; seul le numero d'etape change (1 sur le plot, 2 sur les saves). Appele au setup.
function LoadCompanyController.ensureTopBar(parent: Instance)
	if stepTextLabel then
		return
	end
	local labelTemplate = parent:FindFirstChild("LabelTemplate", true)
	if not (labelTemplate and labelTemplate:IsA("GuiObject")) then
		return
	end

	local stepBadge = cloneTemplate(labelTemplate, "StepBadge", "STEP 1 OF 2", UDim2.fromScale(0.078, 0.038), UDim2.fromScale(0.985, 0.06), Vector2.new(1, 0.5))
	setLabelStroke(stepBadge)
	stepBadge.ZIndex = 50
	stepBadge.Parent = parent
	local st = stepBadge:FindFirstChild("Text", true)
	if st and st:IsA("TextLabel") then
		stepTextLabel = st
	end

	-- Compteur de DIAMANTS a gauche du StepBadge : clone du LabelTemplate restyle en blanc (icone = CurrencyImageIcon).
	local d = cloneTemplate(labelTemplate, "DiamondDataPlayerViewLabel", DIAMOND_COUNT, DIAMOND_SIZE, DIAMOND_POS, Vector2.new(1, 0.5))
	d.ZIndex = 50
	d.BackgroundColor3 = DIAMOND_BG
	local dText = d:FindFirstChild("Text", true)
	if dText and dText:IsA("TextLabel") then
		dText.Name = "DiamondDataAmountText"
		dText.TextXAlignment = Enum.TextXAlignment.Right
		dText.AnchorPoint = Vector2.new(1, 0.5)
		dText.Position = UDim2.fromScale(0.9, 0.5)
		dText.Size = UDim2.fromScale(0.6, 0.6)
		startDiamondCta(dText)
	end
	local dStroke = d:FindFirstChildOfClass("UIStroke")
	if dStroke then
		dStroke.Color = DIAMOND_STROKE
	end
	local iconScale = create("UIScale", {}) :: UIScale
	local icon = create("ImageLabel", {
		Name = "CurrencyImageIcon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.15, 0.5),
		Size = UDim2.fromScale(0.65, 0.65),
		Image = DIAMOND_ICON_IMAGE,
		Children = {
			create("UIAspectRatioConstraint", { AspectRatio = 0.94 }),
			iconScale,
		},
	})
	icon.Parent = d
	local iconGui = icon :: ImageLabel

	-- Pivot lent gauche-droite en boucle (pendule). On GARDE la tween pour la couper le temps d'un tour au survol.
	local function startPendulum(): Tween
		iconGui.Rotation = -DIAMOND_ROT
		return TweenService:Create(iconGui, DIAMOND_ROT_TWEEN, { Rotation = DIAMOND_ROT })
	end
	local pendulum = startPendulum()
	pendulum:Play()

	-- Bouton invisible plein-cadre : rend TOUT le compteur cliquable (a brancher plus tard sur la boutique de diamants).
	local clickArea = create("TextButton", {
		Name = "ClickArea",
		Text = "RIEN",
		TextTransparency = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	}) :: TextButton
	clickArea.Parent = d

	-- Au SURVOL : le diamant fait la MEME anim que le badge des cartes (un TOUR complet + resize slime prolonge). On coupe
	-- le pendule pendant le tour, on le relance a la fin. Garde-fou : pas de nouveau tour tant que l'actuel tourne.
	local spinning = false
	clickArea.MouseEnter:Connect(function()
		if spinning then
			return
		end
		spinning = true
		pendulum:Cancel()
		iconGui.Rotation = 0
		local spin = TweenService:Create(iconGui, BADGE_CLICK_SPIN, { Rotation = 360 })
		spin.Completed:Connect(function()
			spinning = false
			pendulum = startPendulum()
			pendulum:Play()
		end)
		spin:Play()
		iconScale.Scale = BADGE_CLICK_POP_FROM
		TweenService:Create(iconScale, BADGE_CLICK_POP, { Scale = 1 }):Play()
	end)
	d.Parent = parent
	stepBadgeRef = stepBadge
	diamondRef = d

	-- Entree : StepBadge + diamant deboulent du HAUT (hors ecran) a leur place, mais SEULEMENT quand le loading screen est
	-- parti (attribut pose par LoadingScreenClient a sa fin) -- sinon le slide se jouerait derriere lui, invisible.
	local stepHome = stepBadge.Position
	local diamondHome = d.Position
	stepBadge.Position = UDim2.new(stepHome.X.Scale, stepHome.X.Offset, -0.25, 0)
	d.Position = UDim2.new(diamondHome.X.Scale, diamondHome.X.Offset, -0.25, 0)
	task.spawn(function()
		local waited = 0
		while not player:GetAttribute("LeafiaLoadingDone") and waited < 30 do
			task.wait(0.1)
			waited += 0.1
		end
		TweenService:Create(stepBadge, TOPBAR_SLIDE, { Position = stepHome }):Play()
		TweenService:Create(d, TOPBAR_SLIDE, { Position = diamondHome }):Play()
	end)
end

function LoadCompanyController.open(config: OpenConfig)
	currentConfig = config
	refreshCompanies() -- lit les VRAIS slots du serveur (ou 3 vides en secours) AVANT de construire les cartes
	local frame = build(config.parent)
	-- CORBEILLE : on la garde RENTREE pendant l'anim d'entree des cartes (sinon elle apparait seule, hors carte, un court
	-- instant, moche). suppressTrashSlide empeche selectSlot de la sortir ; on la sort a la fin de l'entree (plus bas).
	suppressTrashSlide = true
	selectSlot(defaultIndex())
	if stepTextLabel then -- on est a l'etape 2 (choix de la save)
		stepTextLabel.Text = "STEP 2 OF 2"
	end
	if tileHandle then
		tileHandle.setVisible(true)
	end
	-- Entree UNE PAR UNE : on pose toutes les cartes hors ecran (gauche), puis on lance leur slide avec un decalage
	-- croissant (Card1 d'abord, puis Card2, puis Card3).
	for i, card in cardFrames do
		card.Position = UDim2.new(-0.6, 0, cardHomes[i].Y.Scale, cardHomes[i].Y.Offset)
	end
	for i, card in cardFrames do
		task.delay((i - 1) * CARD_STAGGER, function()
			TweenService:Create(card, CARD_SLIDE, { Position = cardHomes[i] }):Play()
		end)
	end
	frame.Visible = true
	-- Toutes les cartes sont arrivees (dernier slide fini) : on autorise la corbeille et on sort celle de la carte selectionnee.
	task.delay((#cardFrames - 1) * CARD_STAGGER + CARD_SLIDE.Time, function()
		suppressTrashSlide = false
		local trash = trashButtons[selectedIndex]
		if trash then
			trash.Visible = true
			TweenService:Create(trash, TRASH_SLIDE, { Position = trashPos(selectedIndex, true) }):Play()
		end
	end)
end

function LoadCompanyController.close()
	if stepTextLabel then -- retour a l'etape 1 (choix du plot)
		stepTextLabel.Text = "STEP 1 OF 2"
	end
	if tileHandle then
		tileHandle.setVisible(false)
	end
	if root then
		root.Visible = false
	end
end

return LoadCompanyController
