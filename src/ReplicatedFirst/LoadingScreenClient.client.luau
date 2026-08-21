--!strict
-- Ecran de chargement de Leafia : ciel, fond tuile qui defile, badge hexagone + mot LEAFIA au centre, barre doree qui
-- suit le VRAI chargement, feuillages.
--
-- Construit ENTIEREMENT EN CODE : aucune dependance a une UI Studio, tout est ici, versionne et reglable par les
-- constantes plus bas. Les assets (logo en 4 calques, fond tuile) sont des ID EN DUR : plus rien n'est lu de l'ancien
-- ecran, on le detruit juste s'il traine encore.
--
-- AUTONOME : ne require aucun module de ReplicatedStorage. ReplicatedFirst se replique avant le reste du jeu :
-- attendre un module de ReplicatedStorage reviendrait a bloquer sur ce qu'on masque justement.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- ===== Assets EN DUR + destruction de l'ancien ecran s'il traine =====
local TILE_IMAGE = "rbxassetid://137385330828951" -- fond tuile qui defile en diagonale
local TILE_TRANSPARENCY = 0.95 -- KNOB : baisser = tuile plus visible ; monter = plus discrete
-- Plus rien n'est lu de l'ancien ecran (logo = 4 calques en dur, tile en dur) : on le detruit juste
-- s'il existe encore, pour ne pas afficher deux ecrans. Tu peux donc le supprimer de Studio quand tu veux.
do
	local old = ReplicatedFirst:FindFirstChild("LoadingScreen")
	if old then
		old:Destroy()
	end
end

-- ===== RIDEAU GRIS (fond sombre + feuille qui oscille) : pour TOUT lieu SAUF le 1er lancement de Leafia (le gros ecran herbe est
-- reserve a ce cas-la). On y va si on ARRIVE d'un teleport (donnees posees par TeleportService) OU si on n'est PAS dans
-- la place principale (tuto, chantiers : ils ne montrent JAMAIS l'ecran herbe, meme lances direct en Studio). Autonome :
-- ReplicatedFirst ne peut pas require PlacesConfig, donc l'ID de Leafia est EN DUR ici (doit valoir PlacesConfig.MAIN). =====
local MAIN_PLACE_ID = 84161484719535
if TeleportService:GetLocalPlayerTeleportData() ~= nil or game.PlaceId ~= MAIN_PLACE_ID then
	local BG = Color3.fromRGB(31, 31, 31)
	local LEAF_ID = "rbxassetid://117703108607506"
	local LEAF_TINT = Color3.fromRGB(81, 81, 81)
	-- Teinte et transparence du fond tuile. A peine detachees du fond (31, 31, 31) : on veut sentir une matiere,
	-- pas lire un papier peint. Monter TILE_TRANSPARENCY l'efface encore, la baisser le fait ressortir.
	local TILE_TINT = Color3.fromRGB(48, 48, 48)
	local TILE_TRANSPARENCY = 0.55
	-- Taille d'une tuile, en fraction de l'ecran. Deux valeurs car un ecran n'est pas carre.
	local TILE_SCALE_X = 0.075
	local TILE_SCALE_Y = 0.13
	-- Duree du rideau, comptee A PARTIR DE L'ARRIVEE DU PERSONNAGE et non du chargement du jeu. Un plancher qui part
	-- d'un autre instant que l'evenement qu'il doit couvrir ne garantit rien : a 1.4 s depuis `game:IsLoaded`, le
	-- rideau disparaissait avant meme que le joueur soit pose, et on ne le voyait pas.
	local MIN_ARRIVAL = 10

	local sg = Instance.new("ScreenGui")
	sg.Name = "LoadingScreen"
	sg.ScreenInsets = Enum.ScreenInsets.None
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 1000
	sg.Parent = player:WaitForChild("PlayerGui")

	local curtain = Instance.new("CanvasGroup")
	curtain.BackgroundColor3 = BG
	curtain.BorderSizePixel = 0
	curtain.Size = UDim2.fromScale(1, 1)
	curtain.Active = true -- absorbe les clics tant que le rideau couvre
	curtain.Parent = sg

	-- FOND TUILE, avec la MEME feuille : le rideau tient dix secondes, un aplat gris pendant dix secondes se lit
	-- comme un ecran fige. Une texture dit que la page est VIVANTE meme quand rien ne bouge.
	--
	-- Volontairement A PEINE plus clair que le fond : c'est une TEXTURE, pas un motif. La feuille du milieu doit
	-- rester la seule chose qu'on regarde -- deux elements qui reclament l'attention se la volent, et on ne voit
	-- plus ni l'un ni l'autre.
	--
	-- Enfant du CanvasGroup, donc il s'efface AVEC le rideau : rien de plus a fondre.
	local pattern = Instance.new("ImageLabel")
	pattern.Name = "Pattern"
	pattern.BackgroundTransparency = 1
	pattern.Size = UDim2.fromScale(1, 1)
	pattern.Image = LEAF_ID
	pattern.ImageColor3 = TILE_TINT
	pattern.ImageTransparency = TILE_TRANSPARENCY
	pattern.ScaleType = Enum.ScaleType.Tile
	-- TileSize en SCALE (fraction de l'ImageLabel, qui couvre l'ecran) : la tuile suit donc la taille de l'ecran.
	-- X et Y sont SEPARES parce qu'un ecran n'est pas carre : a valeur egale la feuille serait etiree.
	-- A REGLER A L'OEIL, il n'y a pas de bonne valeur calculable.
	pattern.TileSize = UDim2.fromScale(TILE_SCALE_X, TILE_SCALE_Y)
	pattern.ZIndex = 0 -- derriere la feuille du milieu, qui reste le sujet
	pattern.Parent = curtain

	-- La feuille : oscille (Rotation) + flotte (Position), deux periodes -> organique.
	local logo = Instance.new("Frame")
	logo.BackgroundTransparency = 1
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.48)
	logo.Size = UDim2.fromScale(0.267, 0.2)
	logo.Parent = curtain
	local leaf = Instance.new("ImageLabel")
	leaf.BackgroundTransparency = 1
	leaf.AnchorPoint = Vector2.new(0.5, 0.5)
	leaf.Position = UDim2.fromScale(0.5, 0.5)
	leaf.Size = UDim2.fromScale(1, 1)
	leaf.Image = LEAF_ID
	leaf.ImageColor3 = LEAF_TINT
	leaf.ScaleType = Enum.ScaleType.Fit
	local la = Instance.new("UIAspectRatioConstraint")
	la.AspectRatio = 1
	la.Parent = leaf
	leaf.Parent = logo
	leaf.Rotation = -10
	TweenService:Create(leaf, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 10 }):Play()
	TweenService:Create(leaf, TweenInfo.new(2.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromScale(0.5, 0.46) }):Play()

	-- Plus de boules qui rebondissent : la feuille qui oscille suffit a dire que ca charge, et deux animations qui
	-- disent la meme chose se volent l'attention. Le rideau tenant maintenant dix secondes, il vaut mieux qu'il soit
	-- calme.

	-- Chat + liste joueurs : la CoreGui passe AU-DESSUS des ScreenGui, le rideau ne la couvre pas -> on la coupe.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)

	-- Attente, dans l'ORDRE : le jeu charge, PUIS le personnage arrive, PUIS seulement le compte a rebours part.
	-- C'est cet ordre qui compte. Le personnage peut mettre plusieurs secondes a se mettre en place (donnees, session
	-- lock) : un compte lance avant lui serait deja ecoule quand il apparait, et le rideau se leverait dans la
	-- seconde -- exactement le defaut qu'on corrige ici.
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local character: Instance? = player.Character
	if not character then
		character = player.CharacterAdded:Wait()
	end
	if character then
		-- A CharacterAdded le personnage est parente mais pas complet : ses parts arrivent quelques images plus tard.
		character:WaitForChild("HumanoidRootPart", 10)
	end
	local startT = os.clock()
	while os.clock() - startT < MIN_ARRIVAL do
		RunService.Heartbeat:Wait()
	end

	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
	end)

	-- Fondu de TOUT le rideau (CanvasGroup) puis destruction.
	local fade = TweenService:Create(curtain, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	sg:Destroy()
	player:SetAttribute("LeafiaLoadingDone", true) -- meme signal que l'ecran principal (l'UI sait que le rideau est parti)
	return
end

-- ===== Reglages =====
-- Duree minimale a l'ecran DEPUIS l'apparition, meme si tout charge en un clin d'oeil (cas Studio). C'EST LE KNOB si
-- "ca va trop vite" : la barre se remplit sur cette duree au minimum, et l'ecran ne part pas avant. Le skip (Echap)
-- reste dispo pour les impatients. Un vrai chargement plus lent, lui, prolonge naturellement.
local MIN_DURATION = 15

-- Couleurs (maquette). A REGLER a l'oeil.
local WHITE = Color3.fromRGB(255, 255, 255)
local WORDMARK_SHADOW = Color3.fromRGB(69, 171, 180) -- ombre teal sous le LEAFIA

-- Polices : Luckiest Guy (titres, chunky) et Gotham (le reste). On passe par FontFace + les familles qui LIVRENT
-- avec Roblox : pas de risque d'un Enum.Font absent qui casserait tout l'ecran au lancement.
local FONT_TITLE = Font.new("rbxasset://fonts/families/LuckiestGuy.json")
local FONT_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)

local TITLE_TEXT = "LEAFIA"

-- Messages d'etat qui defilent pendant le chargement. Generiques, aucun nom de jeu connu. A ENRICHIR librement.
local STATUS_MESSAGES = {
	"Generation des terrains",
	"Creation des massifs",
	"Plantation des haies",
	"Preparation des outils",
	"Ouverture des chantiers",
}

-- ===== Zoom de reveal (fin du loading) : plan large qui se resserre sur le joueur =====
-- Reveal DESACTIVE : le jeu entre par la SELECTION DE PLOT (PlotSelectController pose une camera d'orbite en
-- Scriptable des le spawn, derriere cet ecran). Le loading ne doit donc PLUS faire son propre zoom sur le joueur,
-- sinon les deux cameras se battent (tween bizarre puis saut). Il se contente de fondre : l'orbite deja posee apparait.
local ZOOM_ENABLED = false
local ZOOM_WAIT = 3
local ZOOM_DURATION = 1.5
local ZOOM_FAR_DIST = 42
local ZOOM_FAR_HEIGHT = 26
local ZOOM_FOCUS_HEIGHT = 2
local TWEEN_ZOOM = TweenInfo.new(ZOOM_DURATION, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

-- ===== Petits helpers de construction =====
local function frame(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = WHITE
	f.Parent = parent
	return f
end

local function text(name: string, parent: Instance, font: Font, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.FontFace = font
	t.TextColor3 = color
	t.TextScaled = true
	t.Text = ""
	t.Parent = parent
	return t
end

-- ===== ScreenGui racine =====
local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
-- Plein ecran, bord a bord : None ignore l'inset de la barre Roblox comme la zone de securite de l'appareil. On pose la
-- propriete MODERNE directement (le legacy IgnoreGuiInset ne se traduit pas en None dans les versions recentes : il
-- laissait l'ecran en DeviceSafeInsets, donc un bandeau non couvert en haut).
gui.ScreenInsets = Enum.ScreenInsets.None
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 1000
gui.Parent = player:WaitForChild("PlayerGui")

-- Tout le bloc visuel dans un CanvasGroup : un seul tween sur GroupTransparency le fait fondre a la sortie, sans
-- avoir a citer chaque element.
local root = Instance.new("CanvasGroup")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
-- Plein ecran ET Active : absorbe TOUS les clics pendant le chargement, sinon ils passent a travers et touchent les
-- boutons de l'UI en dessous (on cliquait "a l'aveugle" avant que l'ecran soit parti). Detruit a la fin -> l'UI
-- redevient cliquable pile quand le rideau s'en va. (Le skip est sur la touche Echap, pas un clic : rien casse.)
root.Active = true
root.Parent = gui

-- ===== CIEL =====
local sky = frame("Sky", root)
sky.Size = UDim2.fromScale(1, 1)
sky.Position = UDim2.fromScale(0, 0)
sky.ZIndex = 1
-- Degrade du ciel : 4 couleurs (cyan en haut -> bleu en bas). Rotation 90 = vertical (haut -> bas).
local skyGrad = Instance.new("UIGradient")
skyGrad.Rotation = 90
skyGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(61, 223, 255)), -- #3ddfff
	ColorSequenceKeypoint.new(0.379, Color3.fromRGB(37, 219, 255)), -- #25dbff
	ColorSequenceKeypoint.new(0.748, Color3.fromRGB(120, 226, 246)), -- #78e2f6
	ColorSequenceKeypoint.new(1, Color3.fromRGB(1, 158, 255)), -- #019eff
})
skyGrad.Parent = sky

-- FOND TUILE qui defile en DIAGONALE. ZIndex = ciel + 1 : juste AU-DESSUS du degrade (opaque, il le cacherait dessous)
-- et SOUS tout le reste (le contenu le cacherait dessus). Le decalage X ET Y a la meme vitesse donne la diagonale ;
-- on recycle chaque axe sur SA periode (la taille de tuile sur cet axe) pour boucler sans saut.
-- TileSize en SCALE (fraction de l'ImageLabel tuile) : ca s'adapte a l'ecran. A REGLER a l'oeil pour l'image.
local TILE_SCALE_X = 0.037 -- largeur d'une tuile (fraction de la largeur de l'ImageLabel tuile)
local TILE_SCALE_Y = 0.07 -- hauteur d'une tuile (fraction de la hauteur de l'ImageLabel tuile)
local TILE_SPEED = 15
local tile = Instance.new("ImageLabel")
tile.Name = "Tile"
tile.BackgroundTransparency = 1
tile.Image = TILE_IMAGE
tile.ImageTransparency = TILE_TRANSPARENCY
tile.ScaleType = Enum.ScaleType.Tile
tile.TileSize = UDim2.fromScale(TILE_SCALE_X, TILE_SCALE_Y) -- taille de la tuile (scale -> s'adapte a l'ecran)
tile.AnchorPoint = Vector2.new(0.5, 0.5)
tile.Position = UDim2.fromScale(0.5, 0.5)
tile.Size = UDim2.fromScale(2, 2) -- deborde largement pour recycler le defilement sans montrer les bords
tile.ZIndex = 2
tile.Parent = root

-- Defilement diagonal : chaque axe recycle sur SA periode (la taille PIXEL de la tuile sur cet axe) pour boucler
-- sans saut. Le modulo garde l'offset dans [0, periode).
local tileOffX, tileOffY = 0, 0
local tileConn: RBXScriptConnection? = nil
tileConn = RunService.Heartbeat:Connect(function(dt: number)
	-- Periode de recyclage = la taille PIXEL d'une tuile (scale * taille de l'ImageLabel). Relue chaque frame -> suit
	-- l'ecran (rotation mobile, resize).
	local periodX = TILE_SCALE_X * tile.AbsoluteSize.X
	local periodY = TILE_SCALE_Y * tile.AbsoluteSize.Y
	if periodX <= 0 or periodY <= 0 then
		return
	end
	tileOffX = (tileOffX + TILE_SPEED * dt) % periodX
	tileOffY = (tileOffY + TILE_SPEED * dt) % periodY
	tile.Position = UDim2.new(0.5, tileOffX, 0.5, tileOffY)
end)

-- ===== COLONNE CENTRALE (badge + mot + chargement) =====
local column = frame("Column", root)
column.AnchorPoint = Vector2.new(0.5, 0.5)
column.Position = UDim2.fromScale(0.5, 0.493)
column.Size = UDim2.fromScale(0.324, 0.928)
column.BackgroundTransparency = 1
column.ZIndex = 5
do
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	-- Trier PAR LayoutOrder (badge 1, LEAFIA 2, pilule 3, barre 4). Sinon le defaut trie par NOM (alphabetique)
	-- et l'ordre part en vrille (barre avant pilule, LEAFIA en bas...).
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.02, 0)
	layout.Parent = column
	-- Un ratio pour que la colonne garde ses proportions quel que soit l'ecran (paysage / portrait).
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 0.62
	ratio.AspectType = Enum.AspectType.FitWithinMaxSize
	ratio.Parent = column
end

-- BADGE (hexagone) + lueur derriere.
local badgeHolder = frame("BadgeHolder", column)
badgeHolder.AnchorPoint = Vector2.new(0.5, 0.5)
badgeHolder.Size = UDim2.fromScale(0.5, 0.42)
badgeHolder.BackgroundTransparency = 1
badgeHolder.LayoutOrder = 1
badgeHolder.ZIndex = 5
do
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = badgeHolder
end

-- Conteneur INTERNE du logo : c'est LUI qui flotte. Le BadgeHolder, lui, est place par le UIListLayout de la colonne,
-- donc tweener sa position se battrait avec le layout. Le Logo remplit le BadgeHolder et porte les 4 calques empiles.
local logo = frame("Logo", badgeHolder)
logo.BackgroundTransparency = 1
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.fromScale(0.5, 0.5)
logo.Size = UDim2.fromScale(1, 1)
logo.ZIndex = 5

-- Un calque du logo : image plein cadre, teinte optionnelle. ZIndex croissant = plus devant.
local function layer(name: string, image: string, zindex: number, colour: Color3?): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.Image = image
	img.ScaleType = Enum.ScaleType.Fit
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = zindex
	if colour then
		img.ImageColor3 = colour
	end
	img.Parent = logo
	return img
end

-- Empilement du fond vers l'avant, comme dans l'editeur : Font2, Middle, OutlineFont, Font1.
layer("Font2", "rbxassetid://112410882732688", 2, Color3.fromRGB(142, 224, 139))
layer("Middle", "rbxassetid://78626050824347", 3, Color3.fromRGB(15, 58, 38))
local outlineFont = layer("OutlineFont", "rbxassetid://98534207212802", 0, nil)
local font1 = layer("Font1", "rbxassetid://80842701479373", 1, nil)

-- OUTLINE : un UIGradient BLANC UNI dont la TRANSPARENCE va de 0 (opaque) a 1 (invisible), qui TOURNE a l'infini :
-- un fondu qui balaie le contour en tournant. La rotation meurt avec le destroy du gui a la sortie.
local outlineGrad = Instance.new("UIGradient")
outlineGrad.Name = "UIGradientRotate"
outlineGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
outlineGrad.Transparency = NumberSequence.new(0, 1)
outlineGrad.Parent = outlineFont
TweenService
	:Create(
		outlineGrad,
		TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false),
		{ Rotation = 360 }
	)
	:Play()

-- FONT1 : un UIGradient (fond vert fonce avec une bande claire au milieu) dont l'Offset GLISSE de (-1,0) a (1,0) : la
-- bande balaie l'image, un reflet. Rapide, frequent, mais pas continu (pause entre deux passages). Couleurs du joueur.
local slideGrad = Instance.new("UIGradient")
slideGrad.Name = "UIGradientSlide"
slideGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 58, 38)),
	ColorSequenceKeypoint.new(0.309, Color3.fromRGB(15, 58, 38)),
	ColorSequenceKeypoint.new(0.522, Color3.fromRGB(144, 255, 237)),
	ColorSequenceKeypoint.new(0.693, Color3.fromRGB(15, 58, 38)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 58, 38)),
})
slideGrad.Offset = Vector2.new(-1, 0)
slideGrad.Parent = font1
local SLIDE_SWEEP = 0.6 -- duree d'un passage du reflet
local SLIDE_PAUSE = 1.4 -- temps mort entre deux passages
task.spawn(function()
	while gui.Parent do
		slideGrad.Offset = Vector2.new(-1, 0)
		TweenService:Create(
			slideGrad,
			TweenInfo.new(SLIDE_SWEEP, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Offset = Vector2.new(1, 0) }
		):Play()
		task.wait(SLIDE_SWEEP + SLIDE_PAUSE)
	end
end)

-- FLOTTEMENT du logo (le conteneur interne). Monte de 14 px et bascule de -1.5 a 1.5 degres, en boucle douce (Sine,
-- reverse). Config donnee par le joueur.
logo.Rotation = -1.5
TweenService:Create(logo, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Position = UDim2.fromScale(0.5, 0.5) - UDim2.fromOffset(0, 14),
	Rotation = 1.5,
}):Play()

-- ENTREE SLIME du logo : de (0,0) a sa taille pleine, deformation NON UNIFORME (ecrase large, rebond haut) puis un
-- tremblement Elastic PROLONGE. Anime la Size -> aucun conflit avec le flottement (Position/Rotation). Sur le logo et
-- non le BadgeHolder : ce dernier a une contrainte de ratio qui ecraserait le slime non uniforme.
logo.Size = UDim2.fromScale(0, 0)
task.spawn(function()
	local splat = TweenService:Create(
		logo,
		TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(1.12, 0.86) }
	)
	splat:Play()
	splat.Completed:Wait()
	local stretch = TweenService:Create(
		logo,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ Size = UDim2.fromScale(0.94, 1.06) }
	)
	stretch:Play()
	stretch.Completed:Wait()
	-- Elastic sur 2.4 s : le rebond traine longtemps (prolonge). L'Elastic a un nb d'oscillations FIXE, la duree les
	-- ETALE (tremblement plus lent, pas plus de coups).
	TweenService:Create(logo, TweenInfo.new(2.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 1),
	}):Play()
end)

-- MOT "LEAFIA" (ombre + texte).
local wordmarkHolder = frame("Wordmark", column)
wordmarkHolder.Size = UDim2.fromScale(0.95, 0.172)
wordmarkHolder.BackgroundTransparency = 1
wordmarkHolder.LayoutOrder = 2
wordmarkHolder.ZIndex = 5

local wordShadow = text("Shadow", wordmarkHolder, FONT_TITLE, WORDMARK_SHADOW)
wordShadow.Text = TITLE_TEXT
wordShadow.Size = UDim2.fromScale(1, 1)
wordShadow.Position = UDim2.fromScale(0, 0.06)
-- LineHeight > 1 : c'est ce qui decale l'ombre vers le bas (le corps du texte descend dans sa boite). Semi-transparente.
wordShadow.LineHeight = 2.15
wordShadow.TextTransparency = 0.59
wordShadow.TextWrapped = true
wordShadow.ZIndex = 5

local wordmark = text("Text", wordmarkHolder, FONT_TITLE, WHITE)
wordmark.Text = TITLE_TEXT
wordmark.Size = UDim2.fromScale(1, 1)
wordmark.ZIndex = 6

-- TEXTE D'ETAT ("Preparation des massifs..."). Pose BAS sur l'ecran (sur root, HORS de la colonne centrale) : le joueur
-- le veut plus bas. KNOB : le Y (0.72) le monte / descend.
local statusText = text("Text", root, FONT_BOLD, WHITE)
statusText.RichText = true
statusText.AnchorPoint = Vector2.new(0.5, 0.5)
statusText.Position = UDim2.fromScale(0.5, 0.72)
statusText.Size = UDim2.fromScale(0.8, 0.04)
statusText.ZIndex = 6

-- ===== FEUILLAGES qui encadrent l'ecran (entree en eventail + flottement) =====
-- INLINE, comme tout ce fichier (autonome : pas de require de ReplicatedStorage). Meme idee que le module reutilisable
-- UI/Core/FoliageReveal, reduite a ce dont le loading a besoin : les feuillages JAILLISSENT depuis l'exterieur, arrivent
-- a leur place, puis flottent doucement. La position POSEE ici est la position finale ; le depart est CALCULE en la
-- projetant vers l'exterieur du centre. { image, x, y = position scale ; w, h = taille scale ; rot } ; tous ancres (0.5, 1).
type FoliageEntry = { image: string, x: number, y: number, w: number, h: number, rot: number }
local FOLIAGE_DATA: { FoliageEntry } = {
	{ image = "rbxassetid://133121907005690", x = 1.242, y = 0.196, w = 0.484, h = 0.872, rot = -108 },
	{ image = "rbxassetid://133121907005690", x = 1.584, y = 1.114, w = 0.475, h = 0.822, rot = -108 },
	{ image = "rbxassetid://120457348978315", x = 1.584, y = 0.41, w = 0.392, h = 0.74, rot = -140 },
	{ image = "rbxassetid://120457348978315", x = 1.425, y = 0.131, w = 0.352, h = 0.697, rot = -140 },
	{ image = "rbxassetid://78090496362298", x = 1.383, y = 0.626, w = 0.268, h = 0.688, rot = -140 },
	{ image = "rbxassetid://78090496362298", x = 0.808, y = -0.009, w = 0.272, h = 0.693, rot = 106 },
	{ image = "rbxassetid://120457348978315", x = 0.13, y = -0.068, w = 0.295, h = 0.524, rot = 180 },
	{ image = "rbxassetid://106884980828867", x = -0.175, y = 0.054, w = 0.598, h = 0.768, rot = 135 },
	{ image = "rbxassetid://106884980828867", x = -0.452, y = 0.309, w = 0.392, h = 0.74, rot = 103 },
	{ image = "rbxassetid://120457348978315", x = -0.647, y = -0.058, w = 0.392, h = 0.74, rot = 103 },
	{ image = "rbxassetid://120457348978315", x = -0.732, y = 0.627, w = 0.392, h = 0.74, rot = 103 },
	{ image = "rbxassetid://133121907005690", x = -0.392, y = 0.756, w = 0.407, h = 0.716, rot = 83 },
	{ image = "rbxassetid://106884980828867", x = -0.55, y = 1.194, w = 0.498, h = 0.834, rot = 125 },
}
local FOLIAGE_SPREAD = 1.55 -- d'ou ils partent (position projetee vers l'exterieur). KNOB
local FOLIAGE_STAGGER = 0.03 -- decalage entre 2 feuillages a l'arrivee (l'eventail). KNOB
local FOLIAGE_AMPLITUDE = 0.03 -- hauteur du flottement (scale). KNOB
-- Etirement au DEPART (multiplie la taille normale), qui se pose a la normale a l'arrivee EN MEME TEMPS que le move :
-- un peu plus long (Y) et un peu plus fin (X) -> effet d'etirement dynamique. 1 = pas d'etirement. KNOB
local FOLIAGE_STRETCH_X = 0.94
local FOLIAGE_STRETCH_Y = 1.12
local FOLIAGE_IN = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- Back = petit depassement (pos ET taille)

local foliageHolder = frame("HolderFoliage", root)
foliageHolder.AnchorPoint = Vector2.new(0.5, 0.5)
foliageHolder.Position = UDim2.fromScale(0.5, 0.5)
foliageHolder.Size = UDim2.fromScale(0.55, 0.55)
foliageHolder.BackgroundTransparency = 1
foliageHolder.ZIndex = 8 -- par-dessus le fond : ils encadrent l'ecran (le contenu central est ailleurs)

local foliageIdle: { Tween } = {}
for i, d in FOLIAGE_DATA do
	local leaf = Instance.new("ImageLabel")
	leaf.Name = "Foliage" .. i
	leaf.BackgroundTransparency = 1
	leaf.Image = d.image
	leaf.AnchorPoint = Vector2.new(0.5, 1)
	leaf.Rotation = d.rot
	leaf.ZIndex = 8
	leaf.Parent = foliageHolder

	local openPos = UDim2.fromScale(d.x, d.y)
	local openSize = UDim2.fromScale(d.w, d.h)
	-- depart : projete vers l'exterieur du centre du holder (0.5, 0.5), donc chacun sort de son bon cote ; et ETIRE
	-- (plus long, plus fin) -> il se pose a sa taille normale EN MEME TEMPS que le move, pour la dynamique.
	leaf.Position = UDim2.fromScale(0.5 + (d.x - 0.5) * FOLIAGE_SPREAD, 0.5 + (d.y - 0.5) * FOLIAGE_SPREAD)
	leaf.Size = UDim2.fromScale(d.w * FOLIAGE_STRETCH_X, d.h * FOLIAGE_STRETCH_Y)
	local dur = 1.9 + ((i * 0.37) % 1) * 1.1 -- flottement varie mais STABLE par feuillage (pas de random par frame)
	task.delay((i - 1) * FOLIAGE_STAGGER, function()
		if not leaf.Parent then
			return
		end
		local inTween = TweenService:Create(leaf, FOLIAGE_IN, { Position = openPos, Size = openSize })
		inTween:Play()
		inTween.Completed:Connect(function()
			if not leaf.Parent then
				return
			end
			-- flottement : monte de AMPLITUDE puis redescend, en boucle qui s'inverse (Sine)
			local up = UDim2.fromScale(d.x, d.y - FOLIAGE_AMPLITUDE)
			local t = TweenService:Create(
				leaf,
				TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Position = up }
			)
			t:Play()
			foliageIdle[#foliageIdle + 1] = t
		end)
	end)
end

-- ===== Etat / skip =====
local skipRequested = false
local function skipLoading()
	skipRequested = true
end
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		skipLoading()
	end
end)

-- ===== Masquage chat + liste joueurs (CoreGui, par-dessus notre ScreenGui) =====
local HIDDEN_CORE_GUIS = { Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList }
local CORE_GUI_SAFETY_DELAY = 60
local coreGuiPrevious: { [Enum.CoreGuiType]: boolean } = {}
local coreGuiRestored = false
local chatWindow = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")

local function hideCoreGuis()
	if chatWindow then
		chatWindow.Enabled = false
	end
	task.spawn(function()
		local pending = table.clone(HIDDEN_CORE_GUIS)
		local deadline = os.clock() + 5
		while #pending > 0 and not coreGuiRestored and os.clock() < deadline do
			for i = #pending, 1, -1 do
				local coreGuiType = pending[i]
				local ok = pcall(function()
					if coreGuiPrevious[coreGuiType] == nil then
						coreGuiPrevious[coreGuiType] = StarterGui:GetCoreGuiEnabled(coreGuiType)
					end
					StarterGui:SetCoreGuiEnabled(coreGuiType, false)
				end)
				if ok then
					table.remove(pending, i)
				end
			end
			if #pending > 0 then
				RunService.Heartbeat:Wait()
			end
		end
	end)
end

local function restoreCoreGuis()
	if coreGuiRestored then
		return
	end
	coreGuiRestored = true
	for coreGuiType, wasEnabled in pairs(coreGuiPrevious) do
		-- Le PLAYERLIST et le CHAT restent coupes apres le chargement : dans la place principale, le MENU (LoadSave UI :
		-- choix du plot et de la save) suit l'ecran de chargement et doit rester epure. C'est PlotSelectController qui les
		-- RALLUME a l'entree en jeu. Cette branche (ecran herbe) ne s'atteint QUE dans la place principale au 1er
		-- lancement direct, donc un menu suit TOUJOURS ici. En place secondaire (rideau gris) chat / playerlist reviennent normalement.
		if coreGuiType ~= Enum.CoreGuiType.PlayerList and coreGuiType ~= Enum.CoreGuiType.Chat then
			pcall(function()
				StarterGui:SetCoreGuiEnabled(coreGuiType, wasEnabled)
			end)
		end
	end
	-- La fenetre de chat (chatWindow) reste coupee elle aussi : rallumee a l'entree en jeu (PlotSelectController).
end

hideCoreGuis()
task.delay(CORE_GUI_SAFETY_DELAY, restoreCoreGuis)

-- ===== Sons (tous OPTIONNELS, aucun warn si absent) =====
local SOUND_MUSIC = { "GameSounds", "Musics", "Loading Screen" }
-- Musique du MENU (fond) : lancee a la SORTIE du loading (pendant le reveal), joue pendant la selection de plot, puis
-- fondue a 0 a l'entree dans le jeu (PlotSelectController). Chemin calque sur l'arbre Studio. Autonome : on clone /
-- joue le Sound direct, aucun require de ReplicatedStorage.
local SOUND_GAME_MUSIC = { "Sounds", "Game", "Musics", "MusicMainMenu" }
-- Volume FORCE de la musique du jeu (le reglage du Sound dans Studio est donc ignore ici). A regler a l'oreille.
local GAME_MUSIC_VOLUME = 0.04
local function findSound(path: { string }): Sound?
	local current: Instance = SoundService
	for _, name in ipairs(path) do
		local child = current:FindFirstChild(name)
		if not child then
			return nil
		end
		current = child
	end
	return if current:IsA("Sound") then current else nil
end
local loadingMusic: Sound? = nil
do
	local source = findSound(SOUND_MUSIC)
	if source then
		local music = source:Clone()
		music.Looped = true
		music.Parent = SoundService
		music:Play()
		loadingMusic = music
	end
end

-- ===== Moniteur de FPS (moyenne glissante) : asservit la collecte / le prechargement =====
local currentFPS = 60
local fpsConn: RBXScriptConnection? = nil
do
	local frameTimes: { number } = {}
	fpsConn = RunService.Heartbeat:Connect(function(dt: number)
		table.insert(frameTimes, dt)
		if #frameTimes > 20 then
			table.remove(frameTimes, 1)
		end
		local sum = 0
		for _, ft in ipairs(frameTimes) do
			sum += ft
		end
		if sum > 0 then
			currentFPS = #frameTimes / sum
		end
	end)
end

-- ===== Etat de sortie : `ready` passe a true quand on peut sortir (tout charge ET duree minimale ecoulee). =====
local ready = false
local screenStart = os.clock() -- reference du temps a l'ecran (duree minimale avant de pouvoir sortir)

-- ===== Collecte des assets a precharger (asservie au FPS) =====
local LOADABLE: { [string]: boolean } = {
	Decal = true,
	Texture = true,
	ImageLabel = true,
	ImageButton = true,
	MeshPart = true,
	SpecialMesh = true,
	FileMesh = true,
	Sound = true,
	Animation = true,
	ParticleEmitter = true,
	Shirt = true,
	Pants = true,
	ShirtGraphic = true,
	SurfaceAppearance = true,
}
local seen: { [Instance]: boolean } = {}
local assetsToLoad: { Instance } = {}
local collectFinished = false
local TARGET_FPS = 25

local function collect(container: Instance)
	local descendants = container:GetDescendants()
	local i = 1
	local n = #descendants
	while i <= n do
		local chunk: number
		if currentFPS >= TARGET_FPS then
			chunk = 40
		elseif currentFPS >= 15 then
			chunk = 12
		else
			chunk = 4
		end
		local processed = 0
		while i <= n and processed < chunk do
			local inst = descendants[i]
			if LOADABLE[inst.ClassName] and not seen[inst] then
				seen[inst] = true
				assetsToLoad[#assetsToLoad + 1] = inst
			end
			i += 1
			processed += 1
		end
		RunService.Heartbeat:Wait()
		if currentFPS < 15 or skipRequested then
			RunService.Heartbeat:Wait()
		end
	end
end

task.spawn(function()
	collect(game:GetService("ReplicatedStorage"))
	collect(game:GetService("StarterGui"))
	collect(game:GetService("SoundService"))
	collectFinished = true
end)

-- ===== Texte d'etat qui defile (PLUS de barre ni de %) : une barre en pourcentage fait COMPTER le temps au joueur
-- ("putain c'est long"). Un texte qui change donne l'impression que le monde se construit sous ses yeux. =====
local statusIndex = 1
local function refreshStatus()
	statusText.Text = STATUS_MESSAGES[statusIndex] .. "..."
end
refreshStatus()

task.spawn(function()
	while not skipRequested and not ready do
		task.wait(1.6)
		statusIndex = statusIndex % #STATUS_MESSAGES + 1
		if not ready then
			refreshStatus()
		end
	end
end)

-- ===== Attente du jeu charge =====
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- ===== Prechargement (continue en fond meme apres un skip) =====
local preloadFinished = false
task.spawn(function()
	while not collectFinished do
		RunService.Heartbeat:Wait()
	end
	local batchSize = if skipRequested then 20 else 15
	local i = 1
	local n = #assetsToLoad
	while i <= n do
		local batch: { Instance } = {}
		for j = i, math.min(i + batchSize - 1, n) do
			batch[#batch + 1] = assetsToLoad[j]
		end
		pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)
		i += #batch
		if skipRequested then
			task.wait(0.2)
		else
			RunService.Heartbeat:Wait()
			if currentFPS < TARGET_FPS then
				task.wait(0.05)
			end
		end
	end
	preloadFinished = true
end)

-- ===== Sortie : quand tout est pret ET la duree minimale passee, OU sur skip =====
while not skipRequested do
	if preloadFinished and os.clock() - screenStart >= MIN_DURATION then
		break
	end
	RunService.Heartbeat:Wait()
end

-- Etat final "C'est pret !" avant le fondu de sortie ; on le laisse une image a l'ecran.
ready = true
statusText.Text = "C'est pret !"
task.wait(if skipRequested then 0 else 0.35)

-- ============================================================
-- ===== SORTIE : fondu + zoom de reveal =====
-- ============================================================
local TWEEN_FADE = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local camera = workspace.CurrentCamera

local function zoomShot(anchor: BasePart, dist: number, height: number): CFrame
	local focus = anchor.Position + Vector3.new(0, ZOOM_FOCUS_HEIGHT, 0)
	local back = anchor.CFrame.LookVector
	return CFrame.lookAt(focus - back * dist + Vector3.new(0, height, 0), focus)
end

local zoomRoot: BasePart? = nil
local zoomFarCFrame: CFrame? = nil
local zoomGameCFrame: CFrame? = nil
do
	local deadline = os.clock() + ZOOM_WAIT
	local charRoot: BasePart? = nil
	repeat
		local char = player.Character
		local found = char and char:FindFirstChild("HumanoidRootPart")
		if found and found:IsA("BasePart") then
			charRoot = found
			break
		end
		RunService.Heartbeat:Wait()
	until os.clock() >= deadline

	if ZOOM_ENABLED and camera and charRoot then
		zoomRoot = charRoot
		-- ARRIVEE = un plan DERRIERE le joueur, a la DISTANCE et la HAUTEUR de la camera de jeu capturee. On FORCE le
		-- derriere (via le LookVector du perso) : la camera de jeu au spawn est parfois DEVANT lui (angle herite), et le
		-- reveal finissait alors FACE a lui. En gardant la distance de la camera de jeu, Custom (meme zoom) reprend au
		-- meme endroit sans saut, et comme il conserve l'angle courant, il reste DERRIERE.
		local focus = charRoot.Position + Vector3.new(0, ZOOM_FOCUS_HEIGHT, 0)
		local gameOffset = camera.CFrame.Position - focus
		local gameDist = math.max(Vector3.new(gameOffset.X, 0, gameOffset.Z).Magnitude, 8)
		zoomGameCFrame = zoomShot(charRoot, gameDist, gameOffset.Y)
		-- On ANCRE le joueur le temps du reveal : sinon, s'il marche et tourne, le re-cadrage ecrase sa rotation
		-- et le suivi parait saccade. Immobile, le cinematique reste propre. On lui rend le controle a la fin.
		charRoot.Anchored = true
		zoomFarCFrame = zoomShot(charRoot, ZOOM_FAR_DIST, ZOOM_FAR_HEIGHT)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = zoomFarCFrame
	end
end

-- Fondu de tout le bloc en une fois (CanvasGroup). Le zoom part EN MEME TEMPS et dure plus longtemps.
local fade = TweenService:Create(root, TWEEN_FADE, { GroupTransparency = 1 })
fade:Play()

-- MUSIQUE DU JEU : demarre AVEC le reveal. Elle boucle et vit sur SoundService, donc elle survit a la destruction
-- de l'ecran. Volume force a GAME_MUSIC_VOLUME (le reglage du Sound dans Studio est ignore).
do
	local source = findSound(SOUND_GAME_MUSIC)
	if source then
		local music = source:Clone()
		music.Name = "GameMusic" -- nom stable pour que le jeu puisse la retrouver (ex : la faire fondre a l'entree)
		music.Looped = true
		music.Volume = GAME_MUSIC_VOLUME
		music.Parent = SoundService
		music:Play()
	else
		-- Musique ATTENDUE (pas un son decoratif optionnel) : si elle manque, on le signale -- anormal ET actionnable.
		warn(`[LoadingScreen] Musique du jeu introuvable : SoundService.{table.concat(SOUND_GAME_MUSIC, ".")}`)
	end
end

local zoomActive = zoomRoot ~= nil and camera ~= nil and zoomFarCFrame ~= nil and zoomGameCFrame ~= nil
local zoomDone = not zoomActive
if zoomActive then
	local cam = camera :: Camera
	local far = zoomFarCFrame :: CFrame
	local target = zoomGameCFrame :: CFrame
	task.spawn(function()
		local duration = TWEEN_ZOOM.Time
		local start = os.clock()
		while true do
			local raw = if duration > 0 then math.clamp((os.clock() - start) / duration, 0, 1) else 1
			local a = TweenService:GetValue(raw, TWEEN_ZOOM.EasingStyle, TWEEN_ZOOM.EasingDirection)
			cam.CFrame = far:Lerp(target, a)
			if raw >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		zoomDone = true
	end)
end
fade.Completed:Wait()

-- ===== Nettoyage des connexions (elles vivent sur RunService, pas sur le GUI) =====
if tileConn then
	tileConn:Disconnect()
end
for _, t in foliageIdle do
	t:Cancel() -- couper le flottement des feuillages (boucles infinies) avant de detruire l'ecran
end
if fpsConn then
	fpsConn:Disconnect()
end

gui:Destroy()
player:SetAttribute("LeafiaLoadingDone", true) -- signal pour l'UI (ex : entree du top bar de selection) : l'ecran est parti
restoreCoreGuis()

-- Retour a la camera de jeu (Custom) une fois le zoom fini : couper avant ferait sauter l'image.
if zoomActive then
	while not zoomDone do
		RunService.Heartbeat:Wait()
	end
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
	if zoomRoot and zoomRoot.Parent then
		zoomRoot.Anchored = false
	end
end

if loadingMusic then
	local fadeOut = TweenService:Create(loadingMusic, TWEEN_FADE, { Volume = 0 })
	fadeOut:Play()
	fadeOut.Completed:Wait()
	loadingMusic:Destroy()
end
