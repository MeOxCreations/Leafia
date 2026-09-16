--!strict
-- LE DESSIN DU RIDEAU DE CHANGEMENT DE LIEU : ciel degrade, tuile, halo, visage du grand-pere, couronne de points,
-- bandeau et nom du lieu. Rien n'est anime ici -- seulement la construction.
--
-- DEUX ECRANS LE DESSINENT, et c'est pour ca qu'il vit a part :
--   * le rideau d'ARRIVEE (LoadingScreenClient), qui l'anime ;
--   * l'ecran PENDANT le teleport (TeleportController), FIGE -- aucun script ne tourne pendant le voyage.
-- Deux copies du dessin finissent toujours par diverger, et c'est arrive : l'ecran du teleport montrait encore
-- l'ancien rideau gris, avec une feuille et quatre boules, pendant que l'arrivee montrait le ciel et le grand-pere.
--
-- DANS ReplicatedFirst, a cote du rideau : il doit etre lisible avant que le reste du jeu soit replique. Un module de
-- ReplicatedStorage ferait attendre ce que le rideau est justement la pour masquer.

local CurtainVisual = {}

export type Built = { tile: ImageLabel, face: ImageLabel, dots: { Frame } }

-- COULEUR DE SECOURS DU CONTENEUR. Elle ne se voit qu'un instant -- celui ou le rideau existe deja mais ou son cadre
-- degrade n'est pas encore pose -- et partout ou ce cadre ne couvrirait pas.
--
-- Un gris fonce y creait un FLASH SOMBRE avant le ciel. On prend donc un bleu DU MEME degrade : le passage devient
-- invisible au lieu d'etre un a-coup. Une couleur de secours doit ressembler a ce qu'elle remplace, sinon elle se
-- voit precisement parce qu'elle est de secours.
CurtainVisual.BG = Color3.fromHex("2AC9F7")

-- ===== FOND TUILE =====
local TILE_IMAGE_ID = "rbxassetid://80842701479373"
-- BLANC PUR, et ce n'est pas cosmetique : un UIGradient MULTIPLIE la couleur de l'objet. Sur un gris, les valeurs du
-- degrade sont rabotees en silence et on regle une courbe dont on ne voit jamais le vrai rendu.
local TILE_TINT = Color3.fromRGB(255, 255, 255)
-- Taille d'UNE tuile, en fraction de l'ImageLabel. Lue aussi par le rideau, qui fait defiler la tuile de cette
-- periode exacte.
CurtainVisual.TILE_CELL = UDim2.fromScale(0.005, 0.01)
-- FONDU SUR LA TUILE. Plein cadre et uniforme, le motif se lit comme un papier peint et rentre en concurrence avec
-- le visage du milieu. On le laisse dense d'un cote et on le fait disparaitre de l'autre.
--
-- Une NumberSequence DOIT commencer a 0 et finir a 1, en temps strictement croissant : Roblox refuse la sequence
-- entiere sinon, et le degrade disparait sans le moindre message.
local TILE_FADE_ROTATION = 50
local TILE_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.36, 1),
	NumberSequenceKeypoint.new(0.748, 0.813),
	NumberSequenceKeypoint.new(1, 0),
})

-- ===== BANDEAU, EN HAUT A DROITE, derriere le nom du lieu =====
-- Retourne de 180 degres pour que sa pointe parte du bon cote : l'image a un sens, et le sens ne se DEDUIT pas.
local BANNER_IMAGE_ID = "rbxassetid://129604305857410"
local BANNER_POS = UDim2.fromScale(0.933, 0.068)
local BANNER_SIZE = UDim2.fromScale(0.479, 0.176)
local BANNER_ROTATION = 180
-- Un FONDU, pas un reflet : plein au depart, un palier sous le titre (densite constante, donc le mot reste lisible
-- d'un bout a l'autre), puis il s'ouvre jusqu'a disparaitre dans le ciel au lieu de s'arreter sur une arete.
local BANNER_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.25, 0.319),
	NumberSequenceKeypoint.new(0.798, 0.756),
	NumberSequenceKeypoint.new(1, 1),
})
-- Un bleu tres clair pris dans la famille du ciel : il se pose SUR le fond, un blanc pur se decouperait dessus. Rend
-- exactement ce qu'il dit parce que l'image est blanche (un UIGradient multiplie la couleur de l'objet).
local BANNER_COLOR = ColorSequence.new(Color3.fromRGB(166, 243, 255))

-- ===== FOND DEGRADE =====
-- CIEL, EN DIAGONALE, quatre etapes dans la MEME famille : seule la luminosite voyage, donc le fond se lit comme un
-- espace et pas comme un motif. 40 degres : la lumiere vient du haut-gauche. Le sens d'un UIGradient ne se DEDUIT
-- pas -- si la lumiere part du mauvais coin, ce nombre est la premiere chose a tourner.
local BG_ROTATION = 40
local BG_COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("6BEBFF")),
	ColorSequenceKeypoint.new(0.38, Color3.fromHex("2AC9F7")),
	ColorSequenceKeypoint.new(0.74, Color3.fromHex("1E90E2")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("1567C6")),
})

-- ===== LE VISAGE DU GRAND-PERE, AU CENTRE =====
-- Un visage dit CHEZ QUI l'on va -- c'est lui, le personnage qu'on va rencontrer. De face, et trois images pour le
-- clignement (ouvert, a moitie, ferme) : le rideau les alterne.
CurtainVisual.FACE_FRONT = "rbxassetid://116099459878511"
CurtainVisual.FACE_FRONT_HALF = "rbxassetid://95027481047570"
CurtainVisual.FACE_FRONT_SHUT = "rbxassetid://92930536214559"
-- LES DEUX COTES EN FRACTION DE LA HAUTEUR (`RelativeYY`), comme la couronne de points. La largeur etait en fraction
-- de la LARGEUR : sur un telephone (2340 x 1080, bien plus large qu'un ecran PC) la tete, en `Stretch`, sortait 22 %
-- plus large que haute -- ecrasee. 0.2365 = l'ancienne largeur (0.133) ramenee a la hauteur d'un ecran 16:9.
CurtainVisual.FACE_SIZE = UDim2.fromScale(0.2365, 0.229)

-- ===== LE HALO =====
-- Il DETACHE le grand-pere du ciel, qui a pratiquement sa couleur. Plus grand que le visage : un halo qui s'arrete au
-- bord de ce qu'il eclaire n'est pas un halo, c'est un contour.
local GLOW_IMAGE_ID = "rbxassetid://108057663284590"
local GLOW_COLOR = Color3.fromRGB(99, 221, 255)
local GLOW_SIZE = UDim2.fromScale(0.34, 0.6)

-- ===== DESTINATION =====
-- Le lieu ou l'on va, en haut a droite. ReplicatedFirst ne peut pas require PlacesConfig : les identifiants sont EN
-- DUR ici, a tenir d'accord a la main -- c'est le prix de tourner aussi tot.
local DEST_BY_PLACE: { [number]: string } = {
	[84161484719535] = "LEAFIA",
	[109440527457437] = "TUTORIAL",
	[124669452423388] = "CLIENT",
	[77113670151896] = "TEST",
}
CurtainVisual.DEST_FALLBACK = "LOADING"
local DEST_POS = UDim2.fromScale(0.988, 0.056)
local DEST_SIZE = UDim2.fromScale(0.3, 0.075)

-- ===== LA COURONNE DE POINTS, en bas =====
-- Elle ne promet rien d'autre que "ca travaille", et c'est la seule chose qu'on sache.
local SPIN_POS = UDim2.fromScale(0.5, 0.92)
-- Cote du cadre carre, en fraction de la HAUTEUR de l'ecran (voir `RelativeYY` a la construction).
local SPIN_SIZE = 0.08
-- Sous 8 la rotation se lit comme une suite de sauts ; au-dela de 16 les points se touchent.
local SPIN_DOTS = 12
-- Rayon du cercle, en fraction du cadre. 0.5 poserait les centres sur le bord et les points depasseraient.
local SPIN_RADIUS = 0.38
local SPIN_DOT = 0.16
local SPIN_COLOR = Color3.fromRGB(255, 255, 255)
-- Transparence du point de TETE et du plus pale. Le second n'est pas a 1 : les points eteints restent VISIBLES,
-- sinon on ne voit plus une couronne qui tourne mais un point qui saute.
local SPIN_HEAD_T = 0
local SPIN_TAIL_T = 0.78
-- De combien le point de tete grossit. Le meme dessin en deux tailles se distingue mieux qu'en deux gris.
local SPIN_HEAD_SCALE = 1.35

--- Le nom affiche pour ce lieu.
function CurtainVisual.destFor(placeId: number): string
	return DEST_BY_PLACE[placeId] or CurtainVisual.DEST_FALLBACK
end

--- Allume la couronne pour une tete a la position `head` (de 0 a 1 sur le cercle).
---
--- LES POINTS NE BOUGENT PAS : seule leur transparence et leur taille tournent. La meme fonction sert a l'animation
--- du rideau et a l'image figee du teleport -- les deux ne peuvent donc pas dessiner deux couronnes differentes.
function CurtainVisual.paintSpinner(dots: { Frame }, head: number)
	for i, dot in dots do
		if dot.Parent then
			-- DISTANCE DERRIERE LA TETE, de 0 (c'est elle) a presque 1. Le modulo fait le tour tout seul.
			local d = (head - (i - 1) / SPIN_DOTS) % 1
			dot.BackgroundTransparency = SPIN_HEAD_T + (SPIN_TAIL_T - SPIN_HEAD_T) * d
			local s = SPIN_DOT * (1 + (SPIN_HEAD_SCALE - 1) * (1 - d))
			dot.Size = UDim2.fromScale(s, s)
		end
	end
end

--- Dessine le rideau dans `container` (plein ecran). Rend ce que l'appelant peut animer.
function CurtainVisual.build(container: GuiObject, destText: string): Built
	-- FOND DEGRADE sur un cadre dedie, au fond du tas : un UIGradient pose sur le conteneur teinterait TOUT ce qu'il
	-- contient -- le texte blanc virerait au bleu.
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	bg.BorderSizePixel = 0
	bg.Size = UDim2.fromScale(1, 1)
	bg.ZIndex = 0
	bg.Active = false
	bg.Parent = container
	local bgGradient = Instance.new("UIGradient")
	bgGradient.Color = BG_COLOR
	bgGradient.Rotation = BG_ROTATION
	bgGradient.Parent = bg

	local tile = Instance.new("ImageLabel")
	tile.Name = "Tile"
	tile.BackgroundTransparency = 1
	tile.Image = TILE_IMAGE_ID
	tile.ImageColor3 = TILE_TINT
	tile.ScaleType = Enum.ScaleType.Tile
	tile.TileSize = CurtainVisual.TILE_CELL
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Position = UDim2.fromScale(0.5, 0.5)
	tile.Size = UDim2.fromScale(2, 2) -- deborde largement : le defilement recycle sans jamais montrer les bords
	tile.ZIndex = 2
	tile.Parent = container
	local tileFade = Instance.new("UIGradient")
	tileFade.Transparency = TILE_FADE
	tileFade.Rotation = TILE_FADE_ROTATION
	tileFade.Parent = tile

	-- LE HALO EN PREMIER, donc DERRIERE le visage.
	local glow = Instance.new("ImageLabel")
	glow.Name = "FaceGlow"
	glow.BackgroundTransparency = 1
	glow.Image = GLOW_IMAGE_ID
	glow.ImageColor3 = GLOW_COLOR
	glow.ScaleType = Enum.ScaleType.Fit
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = GLOW_SIZE
	glow.ZIndex = 3
	glow.Parent = container

	local face = Instance.new("ImageLabel")
	face.Name = "OldManFace"
	face.BackgroundTransparency = 1
	face.Image = CurtainVisual.FACE_FRONT
	-- `Stretch` ET SURTOUT PAS `Fit` : le rideau l'ECRASE a plat puis le deplie. En `Fit`, ecraser sa hauteur ferait
	-- RETRECIR la tete entiere au lieu de l'aplatir -- une image en `Fit` ne sait que grossir et rapetisser. Le prix :
	-- la tete prend les proportions de son cadre, d'ou le `RelativeYY` juste en dessous.
	face.ScaleType = Enum.ScaleType.Stretch
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.SizeConstraint = Enum.SizeConstraint.RelativeYY
	-- POSE A SA TAILLE PLEINE. C'est l'image figee du teleport ; le rideau, lui, la replie a plat avant de la deplier.
	face.Size = CurtainVisual.FACE_SIZE
	face.ZIndex = 5
	face.Parent = container

	local spinner = Instance.new("Frame")
	spinner.Name = "Spinner"
	spinner.BackgroundTransparency = 1
	spinner.AnchorPoint = Vector2.new(0.5, 0.5)
	spinner.Position = SPIN_POS
	-- CARRE PAR CONSTRUCTION : `RelativeYY` calcule les DEUX cotes sur la hauteur, sinon la couronne devient un ovale
	-- des que l'ecran n'est pas carre -- c'est-a-dire toujours.
	spinner.SizeConstraint = Enum.SizeConstraint.RelativeYY
	spinner.Size = UDim2.fromScale(SPIN_SIZE, SPIN_SIZE)
	spinner.ZIndex = 4
	spinner.Parent = container

	local dots: { Frame } = {}
	for i = 1, SPIN_DOTS do
		local a = (i - 1) / SPIN_DOTS * math.pi * 2
		local dot = Instance.new("Frame")
		dot.Name = `Dot{i}`
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		-- L'ANGLE PART DU HAUT et tourne dans le sens des aiguilles : l'axe Y d'une interface DESCEND, d'ou le `-cos`.
		dot.Position = UDim2.fromScale(0.5 + math.sin(a) * SPIN_RADIUS, 0.5 - math.cos(a) * SPIN_RADIUS)
		dot.Size = UDim2.fromScale(SPIN_DOT, SPIN_DOT)
		dot.BackgroundColor3 = SPIN_COLOR
		dot.BorderSizePixel = 0
		dot.ZIndex = 4
		-- Le cast est OBLIGATOIRE : luau-lsp ne resout pas `Instance.new("UICorner")` vers `UICorner`.
		local corner = Instance.new("UICorner") :: UICorner
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = dot
		dot.Parent = spinner
		dots[i] = dot
	end
	CurtainVisual.paintSpinner(dots, 0)

	local banner = Instance.new("ImageLabel")
	banner.Name = "Banner"
	banner.BackgroundTransparency = 1
	banner.Image = BANNER_IMAGE_ID
	-- BLANC PUR, ECRIT EXPLICITEMENT : c'est ce qui rend BANNER_COLOR litteral. La teinte se regle la-bas, jamais ici.
	banner.ImageColor3 = Color3.fromRGB(255, 255, 255)
	banner.ScaleType = Enum.ScaleType.Stretch
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = BANNER_POS
	banner.Size = BANNER_SIZE
	banner.Rotation = BANNER_ROTATION
	banner.ZIndex = 3
	banner.Parent = container
	local bannerFade = Instance.new("UIGradient")
	bannerFade.Color = BANNER_COLOR
	bannerFade.Transparency = BANNER_FADE
	bannerFade.Parent = banner

	local dest = Instance.new("TextLabel")
	dest.Name = "ClientName"
	dest.BackgroundTransparency = 1
	-- Ancree a DROITE : un nom long grandit vers la gauche et garde son bord droit aligne.
	dest.AnchorPoint = Vector2.new(1, 0.5)
	dest.Position = DEST_POS
	dest.Size = DEST_SIZE
	dest.Text = destText
	dest.TextColor3 = Color3.fromRGB(255, 255, 255)
	dest.TextScaled = true
	dest.TextXAlignment = Enum.TextXAlignment.Right
	-- MONTSERRAT HEAVY (la graisse 900) : une lettre nette, et les accents des langues que Roblox traduit.
	dest.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Normal)
	dest.ZIndex = 4
	dest.Parent = container

	return { tile = tile, face = face, dots = dots }
end

return CurtainVisual
