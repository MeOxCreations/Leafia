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
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- ===== Sons : resolution par chemin sous SoundService =====
-- AUTONOME, comme tout ce fichier : aucun require de ReplicatedStorage (SoundUtils fait la meme chose, mais le
-- requerir ici ferait attendre une replication qu'on n'a pas au moment de ReplicatedFirst).
--
-- Ces fonctions vivent AVANT le rideau parce que le rideau `return` : une definition placee plus bas ne serait
-- jamais atteinte dans ce chemin.
local function findByPath(path: { string }): Instance?
	local current: Instance = SoundService
	for _, name in ipairs(path) do
		local child = current:FindFirstChild(name)
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function findSound(path: { string }): Sound?
	local found = findByPath(path)
	return if found and found:IsA("Sound") then found else nil
end

-- Comme findSound, mais un chemin qui pointe sur un DOSSIER rend un de ses Sound AU HASARD. Deposer un echantillon
-- de plus dans Studio augmente donc la variete sans toucher au code (meme convention que le son de coupe de haie).
local function findAnySound(path: { string }): Sound?
	local found = findByPath(path)
	if not found then
		return nil
	end
	if found:IsA("Sound") then
		return found
	end
	local pool: { Sound } = {}
	for _, child in ipairs(found:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(pool, child)
		end
	end
	return if #pool > 0 then pool[math.random(#pool)] else nil
end

-- Clone et joue. On CLONE plutot que rejouer l'original : rejouer la meme instance couperait le son en cours, et
-- le clone garde les reglages faits en Studio (volume, hauteur), qui restent la source de verite.
local function playSound(source: Sound, volume: number?): Sound
	local sound = source:Clone()
	if volume then
		sound.Volume = volume
	end
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 5) -- garde-fou si Ended ne tire jamais (asset absent)
	return sound
end

-- ===== Assets EN DUR + destruction de l'ancien ecran s'il traine =====
local TILE_IMAGE = "rbxassetid://137385330828951" -- fond tuile qui defile en diagonale
local TILE_TRANSPARENCY = 0.95 -- KNOB : baisser = tuile plus visible ; monter = plus discrete
-- Taille et vitesse de la tuile. LUES PAR LES DEUX ECRANS (l'intro et le rideau de changement de map) : en changer
-- un change les deux, c'est voulu -- le rideau doit ressembler a l'ecran principal.
-- TileSize en SCALE (fraction de l'ImageLabel tuile) : ca s'adapte a l'ecran. A REGLER a l'oeil pour l'image.
local TILE_SCALE_X = 0.037 -- largeur d'une tuile (fraction de la largeur de l'ImageLabel tuile)
local TILE_SCALE_Y = 0.07 -- hauteur d'une tuile (fraction de la hauteur de l'ImageLabel tuile)
local TILE_SPEED = 15
-- ON NE DETRUIT PLUS `ReplicatedFirst.LoadingScreen`. Ce fichier le faisait -- l'ancien ecran n'etait plus lu, on
-- le nettoyait -- mais c'est devenu exactement l'endroit ou vit le MODELE du rideau de changement de map. Le
-- detruire au demarrage revenait a supprimer le decor juste avant de s'en servir.

-- ===== RIDEAU GRIS (fond sombre + feuille qui oscille) : pour TOUT lieu SAUF le 1er lancement de Leafia (le gros ecran herbe est
-- reserve a ce cas-la). On y va si on ARRIVE d'un teleport (donnees posees par TeleportService) OU si on n'est PAS dans
-- la place principale (tuto, chantiers : ils ne montrent JAMAIS l'ecran herbe, meme lances direct en Studio). Autonome :
-- ReplicatedFirst ne peut pas require PlacesConfig, donc l'ID de Leafia est EN DUR ici (doit valoir PlacesConfig.MAIN). =====
local MAIN_PLACE_ID = 84161484719535
if TeleportService:GetLocalPlayerTeleportData() ~= nil or game.PlaceId ~= MAIN_PLACE_ID then
	-- ===== LE RIDEAU EST CONSTRUIT EN CODE =====
	-- Il l'a ete un temps a partir d'une ScreenGui modele posee dans Studio. Abandonne : Rojo ne synchronise pas
	-- StarterGui, donc le modele n'existait que dans le lieu ou on l'avait dessine, et le tuto tombait sur le
	-- rideau de secours. Le code, lui, arrive dans TOUS les lieux sans qu'on ait rien a recopier.
	-- Les valeurs ci-dessous sont celles du dessin fait dans l'editeur.
	local BG = Color3.fromRGB(31, 31, 31)

	-- FOND TUILE qui defile en diagonale.
	local TILE_IMAGE_ID = "rbxassetid://86181241708864"
	local TILE_TINT = Color3.fromRGB(38, 38, 38)
	local TILE_CELL = UDim2.fromScale(0.01, 0.017) -- taille d'UNE tuile, en fraction de l'ImageLabel
	local TILE_DRIFT = 15 -- vitesse de defilement, en pixels par seconde
	-- FONDU SUR LA TUILE. Le motif ne doit pas etre present partout avec la meme force : plein cadre et uniforme,
	-- il se lit comme un papier peint et rentre en concurrence avec la feuille du milieu. On le laisse dense d'un
	-- cote et on le fait disparaitre de l'autre.
	--
	-- La courbe part a PLAT (le motif reste franc au debut), MONTE VITE, puis s'aplatit vers l'invisible. C'est ce
	-- palier de depart qui evite que le fondu commence des le premier pixel et donne l'air d'une erreur.
	local TILE_FADE = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(0.288, 0.512),
		NumberSequenceKeypoint.new(0.6, 0.86),
		NumberSequenceKeypoint.new(1, 1),
	})

	-- BANDEAU du bas, avec son degrade de transparence.
	local BANNER_IMAGE_ID = "rbxassetid://129604305857410"
	local BANNER_POS = UDim2.fromScale(0.453, 0.904)
	local BANNER_SIZE = UDim2.fromScale(1.002, 0.132)
	-- Le bandeau n'est PAS plein d'un bout a l'autre : sa transparence monte le long de sa largeur. C'est un
	-- FONDU, pas un reflet -- il ne s'anime pas. L'avoir promene une fois a suffi a le rendre completement opaque.
	local BANNER_FADE_AT = 0.95 -- ou la transparence atteint 1
	-- TEINTE du bandeau : vert vif d'un cote, noir de l'autre. Le meme UIGradient porte donc DEUX choses -- la
	-- couleur et la transparence -- et c'est voulu : elles decrivent le meme voyage le long du bandeau, les
	-- separer sur deux objets obligerait a les garder d'accord a la main.
	--
	-- Ces valeurs rendent EXACTEMENT ce qu'elles disent parce que l'image du bandeau est en blanc pur : un
	-- UIGradient multiplie la couleur de l'objet, donc toute autre teinte les raboterait en silence.
	local BANNER_COLOR = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(142, 255, 93)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
	})

	-- FEUILLE centrale : elle oscille, elle flotte, et elle SE REMPLIT comme une jauge.
	local LEAF_ID = "rbxassetid://117703108607506"
	-- LE MEME VERT QUE LE DEBUT DU BANDEAU : la feuille et le bandeau se repondent, l'ecran a une seule couleur
	-- d'accent au lieu de deux elements gris qui se ressemblent sans se parler.
	--
	-- Le degrade pose sur la feuille ne touche QUE sa transparence (c'est lui qui la remplit) : sa couleur reste
	-- neutre, donc ce vert s'affiche tel quel.
	local LEAF_TINT = Color3.fromRGB(142, 255, 93)
	local LEAF_SIZE = UDim2.fromScale(0.2, 0.2)
	local LEAF_CENTER = UDim2.fromScale(0.5, 0.46)
	-- Calee sur MIN_ARRIVAL : la feuille finit de se remplir au moment ou le rideau s'en va. Une jauge qui se
	-- remplit AVANT la fin ment sur ce qu'il reste.
	local FILL_DURATION = 10
	local FILL_SOFT = 0.14 -- douceur du bord. 0 = coupure nette, ce qui se lit comme un masque
	local FILL_ROTATION = 270 -- sens du remplissage. 90 = l'autre sens (verifie a l'ecran : 270 est le bon)

	-- CONSEILS. En ANGLAIS : le traducteur de Roblox part de l'anglais, un texte francais n'est traduit nulle part.
	local TIPS_LABEL = "TIPS"
	-- BLANC PUR, et c'est indispensable : le degrade pose plus bas MULTIPLIE cette couleur. Sur une teinte grise,
	-- ses valeurs (#ffffff, #d6d6d6) ne rendaient pas ce qu'elles disent -- elles etaient rabotees par le gris, et
	-- on reglait donc un degrade dont on ne voyait jamais les vraies couleurs.
	-- Le blanc rend la multiplication NEUTRE : ce qui est ecrit dans TIPS_LABEL_SHADE est exactement ce qu'on voit.
	-- C'est la couleur de reference a garder des qu'un UIGradient decide de la teinte.
	local TIPS_LABEL_COLOR = Color3.fromRGB(255, 255, 255)
	-- Place de l'etiquette "TIPS". Ancree en son CENTRE : la position designe alors le milieu du bloc, ce qui la
	-- garde sur son axe quelle que soit sa taille -- avec une ancre en coin, changer la taille la deplace.
	local TIPS_LABEL_POS = UDim2.fromScale(0.07, 0.916)
	local TIPS_LABEL_SIZE = UDim2.fromScale(0.156, 0.088)
	-- NUANCE sur l'etiquette : elle reste franche sur la premiere moitie, puis s'eteint tres legerement. La
	-- cassure nette entre 0.463 et 0.483 fait un petit RESSAUT plutot qu'un degrade continu -- c'est ce qui donne
	-- l'impression d'un relief, la ou un fondu lisse aurait juste l'air sale.
	--
	-- Un UIGradient MULTIPLIE la couleur du texte : ces valeurs presque blanches ne le REPEIGNENT donc pas, elles
	-- l'assombrissent d'au plus 16 %. La teinte de base reste TIPS_LABEL_COLOR.
	local TIPS_LABEL_SHADE = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.463, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.483, Color3.fromRGB(229, 229, 229)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(214, 214, 214)),
	})
	-- Sens de la nuance, en degres. 0 = de gauche a droite, 90 = de haut en bas. Ne se DEDUIT pas : c'est l'ecran
	-- qui tranche, comme pour tous les degrades de ce fichier.
	local TIPS_LABEL_SHADE_ROTATION = 0
	local TIPS: { string } = {
		"Mow in straight lines. The stripes you leave are your signature.",
		"Pull the cord before you push. A dead engine cuts nothing.",
		"Go back over a strip the other way to flip its shade.",
		"Hold G to see what you have not cut yet.",
		"Flowers do not survive the blade. Mow around the ones you like.",
		"Press C to look through your own eyes.",
	}
	local TIP_INTERVAL = 5 -- secondes entre deux conseils
	local TIP_FADE = 0.35 -- duree du fondu de SORTIE d'un conseil
	-- REBOND LETTRE PAR LETTRE.
	-- Le retard entre deux lettres. C'est LE reglage du rythme : trop court, tout arrive ensemble et on perd
	-- l'effet ; trop long, la phrase met une eternite a s'ecrire et on la lit plus vite qu'elle ne s'affiche.
	-- 0.02 = environ une seconde pour une phrase de cinquante caracteres.
	local TIP_LETTER_STAGGER = 0.02
	local TIP_LETTER_TIME = 0.34 -- duree du rebond d'UNE lettre
	-- De combien elle monte, en part de la taille du texte. Elle arrive PAR EN DESSOUS : vers le haut, elle
	-- passerait derriere le bandeau.
	local TIP_LETTER_RISE = 0.55
	-- Largeur d'une espace, en part de la taille du texte. Roblox rogne les blancs de bord, donc une espace
	-- mesuree rend ZERO et les mots se colleraient. Valeur a l'oeil, propre a la police.
	local TIP_SPACE_WIDTH = 0.28

	-- Son joue quand le rideau apparait. POINTE SUR LE DOSSIER : un echantillon est tire au hasard, donc deux
	-- chargements de suite ne sonnent pas pareil. Meme dossier que le son de coupe de haie.
	local LEAF_SOUND = { "Sounds", "Environnement", "Leafs" }
	local LEAF_SOUND_VOLUME = 0.35 -- a regler a l'oreille
	local LEAF_SOUND_WAIT = 6 -- combien de temps on re-cherche le son avant d'abandonner

	-- Duree du rideau, comptee A PARTIR DE L'ARRIVEE DU PERSONNAGE et non du chargement du jeu. Un plancher qui
	-- part d'un autre instant que l'evenement qu'il doit couvrir ne garantit rien : a 1.4 s depuis `game:IsLoaded`,
	-- le rideau disparaissait avant meme que le joueur soit pose, et on ne le voyait pas.
	local MIN_ARRIVAL = 10

	-- ===== VOLET DE SORTIE =====
	-- Un aplat BLANC balaie l'ecran, on detruit le rideau PENDANT qu'il couvre, puis le blanc s'en va en balayant
	-- dans l'autre sens et le jeu apparait.
	--
	-- POURQUOI PAS UN SIMPLE FONDU. En fondant, chaque element du rideau disparait a sa maniere : la tuile, la
	-- feuille et les textes s'effacent en meme temps mais pas au meme rythme, et ca se lit comme un bug. Sous le
	-- volet, on ne voit RIEN partir -- le rideau est deja detruit quand le blanc se retire.
	local WIPE_COLOR = Color3.fromRGB(255, 255, 255)
	local WIPE_COVER_TIME = 0.55 -- duree pour recouvrir
	local WIPE_HOLD = 0.12 -- temps couvert, pendant lequel on detruit le rideau
	-- Plus lent que l'arrivee, et c'est voulu : on COUVRE pour cacher (autant que ce soit vite fait), on DECOUVRE
	-- pour montrer le jeu (autant que ca se savoure). Les deux n'ont pas le meme role, ils n'ont pas la meme duree.
	local WIPE_REVEAL_TIME = 0.85
	local WIPE_SOFT = 0.18 -- douceur du bord. 0 = coupure nette, ce qui se lit comme un masque
	-- SENS DU BALAYAGE, en degres. 0 = de gauche a droite, 180 = l'inverse.
	-- Il ne se DEDUIT pas -- deja au journal. Mais ici il n'y a AUCUN risque a se tromper : le volet est detruit a
	-- la fin quoi qu'il arrive, donc au pire le balayage part du mauvais cote, il ne bloque jamais le jeu.
	local WIPE_ROTATION = 0

	local sg = Instance.new("ScreenGui")
	sg.Name = "LeafiaCurtain"
	sg.ScreenInsets = Enum.ScreenInsets.None
	sg.ResetOnSpawn = false -- sinon le rideau est recree a chaque mort et nos references pointent sur du detruit
	sg.DisplayOrder = 1000
	sg.Parent = player:WaitForChild("PlayerGui")

	-- CanvasGroup : le fondu de sortie porte sur LUI, donc tout son contenu s'efface d'un seul mouvement au lieu
	-- de partir element par element.
	local curtain = Instance.new("CanvasGroup")
	curtain.BackgroundColor3 = BG
	curtain.BorderSizePixel = 0
	curtain.Size = UDim2.fromScale(1, 1)
	curtain.Active = true -- absorbe les clics tant que le rideau couvre
	curtain.Parent = sg

	-- ===== FOND TUILE =====
	-- Le defilement DIAGONAL n'est pas un caprice : horizontal ou vertical, ca se lit comme un decor qui glisse ;
	-- en diagonale, ca se lit comme un mouvement propre.
	local tile = Instance.new("ImageLabel")
	tile.Name = "Tile"
	tile.BackgroundTransparency = 1
	tile.Image = TILE_IMAGE_ID
	tile.ImageColor3 = TILE_TINT
	tile.ScaleType = Enum.ScaleType.Tile
	tile.TileSize = TILE_CELL
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Position = UDim2.fromScale(0.5, 0.5)
	tile.Size = UDim2.fromScale(2, 2) -- deborde largement : le defilement recycle sans jamais montrer les bords
	tile.ZIndex = 1
	tile.Parent = curtain
	-- Le fondu vit sur un UIGradient enfant de la tuile. Il ne s'anime PAS : c'est la tuile qui defile dessous, et
	-- comme elle ne se deplace que d'une case a la fois, le fondu reste ou il est.
	local tileFade = Instance.new("UIGradient")
	tileFade.Transparency = TILE_FADE
	tileFade.Parent = tile

	local tileConn: RBXScriptConnection? = nil
	do
		local offX, offY = 0, 0
		tileConn = RunService.Heartbeat:Connect(function(dt: number)
			-- Periode de recyclage = la taille PIXEL d'une tuile. Relue a chaque image, donc elle suit l'ecran
			-- (resize, rotation mobile). Le modulo garde l'offset dans [0, periode).
			local periodX = TILE_CELL.X.Scale * tile.AbsoluteSize.X
			local periodY = TILE_CELL.Y.Scale * tile.AbsoluteSize.Y
			if periodX <= 0 or periodY <= 0 then
				return
			end
			offX = (offX + TILE_DRIFT * dt) % periodX
			offY = (offY + TILE_DRIFT * dt) % periodY
			tile.Position = UDim2.new(0.5, offX, 0.5, offY)
		end)
	end

	-- ===== FEUILLE CENTRALE =====
	-- Elle part invisible et se revele petit a petit : le joueur ne voit plus seulement "ca charge", il voit
	-- COMBIEN il reste. Une attente qu'on peut mesurer est toujours plus courte qu'une attente muette.
	local leaf = Instance.new("ImageLabel")
	leaf.Name = "Leaf"
	leaf.BackgroundTransparency = 1
	leaf.AnchorPoint = Vector2.new(0.5, 0.5)
	leaf.Position = LEAF_CENTER
	leaf.Size = LEAF_SIZE
	leaf.Image = LEAF_ID
	leaf.ImageColor3 = LEAF_TINT
	leaf.ScaleType = Enum.ScaleType.Fit
	leaf.ZIndex = 2
	leaf.Rotation = -10
	leaf.Parent = curtain
	-- La contrainte garde la feuille CARREE : sans elle, elle s'etire avec le format de l'ecran.
	local leafRatio = Instance.new("UIAspectRatioConstraint")
	leafRatio.AspectRatio = 1
	leafRatio.DominantAxis = Enum.DominantAxis.Height
	leafRatio.Parent = leaf

	TweenService
		:Create(leaf, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Rotation = 10,
		})
		:Play()
	TweenService
		:Create(leaf, TweenInfo.new(2.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Position = UDim2.fromScale(LEAF_CENTER.X.Scale, LEAF_CENTER.Y.Scale - 0.02),
		})
		:Play()

	-- Le remplissage passe par la TRANSPARENCE du degrade, pas par sa couleur : la partie pas encore remplie est
	-- transparente, donc on voit le fond a travers. Une couleur ne se retire pas, une transparence si.
	local fill = Instance.new("UIGradient")
	fill.Name = "UIGradientFill"
	-- Le SENS ne se DEDUIT pas : le sens d'un UIGradient est une de ces choses que seul l'ecran tranche.
	fill.Rotation = FILL_ROTATION
	fill.Parent = leaf
	task.spawn(function()
		local t0 = os.clock()
		-- `sg.Parent` : la boucle meurt avec le rideau. Un `while true` tournerait toute la session sur une
		-- instance detruite.
		while sg.Parent do
			local e = math.clamp((os.clock() - t0) / FILL_DURATION, 0, 1)
			if e >= 1 then
				fill.Transparency = NumberSequence.new(0)
			else
				-- Bord ADOUCI plutot que net : une coupure franche se lit comme un masque, un degrade comme un
				-- liquide qui monte. Les temps d'une NumberSequence doivent croitre STRICTEMENT, d'ou l'ecart
				-- minimal force : sinon Roblox refuse la sequence des que le bord touche un bord.
				local b = math.clamp(e, 0.002, 0.998)
				local a = math.clamp(b - FILL_SOFT, 0.001, b - 0.001)
				fill.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(a, 0),
					NumberSequenceKeypoint.new(b, 1),
					NumberSequenceKeypoint.new(1, 1),
				})
			end
			task.wait()
		end
	end)

	-- ===== BANDEAU DU BAS =====
	local banner = Instance.new("ImageLabel")
	banner.Name = "Banner"
	banner.BackgroundTransparency = 1
	banner.Image = BANNER_IMAGE_ID
	-- BLANC PUR, ECRIT EXPLICITEMENT. C'est la valeur par defaut, mais c'est aussi ce qui rend le degrade
	-- litteral : la poser noir sur blanc evite qu'on la teinte un jour sans voir qu'on rabote BANNER_COLOR.
	banner.ImageColor3 = Color3.fromRGB(255, 255, 255)
	banner.ScaleType = Enum.ScaleType.Stretch
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = BANNER_POS
	banner.Size = BANNER_SIZE
	banner.ZIndex = 2
	banner.Parent = curtain
	-- Son degrade est un FONDU FIXE, pas un reflet a promener : sa transparence monte le long de la largeur pour
	-- que le bandeau ne soit pas plein d'un bout a l'autre. Deplacer son offset pousserait cette rampe HORS du
	-- bandeau, qui redeviendrait donc completement opaque.
	local bannerFade = Instance.new("UIGradient")
	bannerFade.Color = BANNER_COLOR
	bannerFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(BANNER_FADE_AT, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	bannerFade.Parent = banner

	-- ===== CONSEILS =====
	-- "TIPS" est une ETIQUETTE : elle est centree dans son propre bloc, a une place fixe. Le conseil, lui, est cale
	-- a GAUCHE et occupe le reste de la largeur -- c'est lui qui varie en longueur, donc c'est lui qui doit avoir
	-- de la place, pas l'etiquette.
	local tipsLabel = Instance.new("TextLabel")
	tipsLabel.Name = "TipsText"
	tipsLabel.BackgroundTransparency = 1
	tipsLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	tipsLabel.Position = TIPS_LABEL_POS
	tipsLabel.Size = TIPS_LABEL_SIZE
	tipsLabel.Text = TIPS_LABEL
	tipsLabel.TextColor3 = TIPS_LABEL_COLOR
	tipsLabel.TextScaled = true
	tipsLabel.TextXAlignment = Enum.TextXAlignment.Center
	tipsLabel.FontFace = Font.new("rbxasset://fonts/families/LuckiestGuy.json")
	tipsLabel.ZIndex = 3
	tipsLabel.Parent = curtain
	local tipsShade = Instance.new("UIGradient")
	tipsShade.Color = TIPS_LABEL_SHADE
	tipsShade.Rotation = TIPS_LABEL_SHADE_ROTATION
	tipsShade.Parent = tipsLabel

	-- ===== LE CONSEIL S'ECRIT LETTRE PAR LETTRE, CHACUNE AVEC SON REBOND =====
	--
	-- UNE ETIQUETTE PAR CARACTERE, et il n'y a pas d'autre moyen. Un TextLabel est un bloc : `MaxVisibleGraphemes`
	-- (ce qu'utilise le dialogue du jeu) revele bien les lettres une a une, mais il ne peut pas les faire BOUGER
	-- separement -- elles appartiennent toutes au meme objet. Pour un rebond par lettre, il faut un objet par
	-- lettre.
	--
	-- Le cout est acceptable ICI et nulle part ailleurs : une soixantaine d'etiquettes creees a chaque conseil, sur
	-- un ecran qui ne fait rien d'autre. Dans une interface de jeu, ce serait a proscrire.
	local tipsRow = Instance.new("Frame")
	tipsRow.Name = "TipsDescription"
	tipsRow.BackgroundTransparency = 1
	tipsRow.AnchorPoint = Vector2.new(0, 0.5)
	tipsRow.Position = UDim2.fromScale(0.15, BANNER_POS.Y.Scale)
	tipsRow.Size = UDim2.fromScale(0.8, 0.045)
	-- Les lettres DEBORDENT pendant leur rebond : elles arrivent d'en dessous. Un clip les couperait en plein vol.
	tipsRow.ClipsDescendants = false
	tipsRow.ZIndex = 3
	tipsRow.Parent = curtain

	-- Montserrat en GRAS, designee par sa FAMILLE et pas par un Enum.Font : les enums de police sont en cours de
	-- depreciation (`Enum.Font.Montserrat` renvoie deja vers Gotham), alors que le chemin de famille reste stable
	-- et porte le poids separement. C'est la forme deja utilisee partout ailleurs dans ce fichier.
	local TIP_FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)

	-- Combien de temps on attend que la ligne ait une hauteur avant d'ecrire quand meme. Voir writeTip.
	local TIP_LAYOUT_WAIT = 3
	-- Combien de temps on SURVEILLE la largeur des lettres apres les avoir placees.
	--
	-- POURQUOI SURVEILLER. Une police se charge PARESSEUSEMENT : le premier conseil peut etre dessine avec une
	-- police de secours, puis redessine avec la bonne. Roblox echange le rendu tout seul -- mais pas nos
	-- POSITIONS, calculees a la main sur les largeurs de l'ancienne. Les lettres restaient donc mal espacees, et
	-- le mot entier avait l'air d'etre dans une autre police.
	--
	-- On ne peut pas savoir QUAND la vraie police arrive : aucune API ne le dit, et deux tentatives de le deviner
	-- se sont revelees fausses. On ne devine donc plus -- on regarde si les largeurs bougent, et on replace.
	local TIP_WIDTH_WATCH = 2.5

	-- Ecrit un conseil, lettre par lettre. Rend quand tout est pose (pas quand tout est arrive).
	-- Jeton du conseil COURANT. La boucle d'animation s'arrete des qu'un nouveau conseil arrive : sans lui, deux
	-- boucles ecriraient la position des memes lettres, et la plus vieille gagnerait une image sur deux.
	local tipToken: any = nil

	local function writeTip(text: string)
		for _, child in ipairs(tipsRow:GetChildren()) do
			child:Destroy()
		end

		-- ON ATTEND QUE LA LIGNE AIT UNE HAUTEUR.
		--
		-- C'ETAIT LE BUG DU PREMIER CONSEIL. `AbsoluteSize` n'existe qu'apres le passage de la mise en page, et le
		-- tout premier conseil est ecrit AVANT la premiere image du rideau : on lisait donc ZERO, et la taille de
		-- texte retombait sur son plancher de huit pixels. Le premier conseil sortait minuscule -- ce qui ressemble
		-- a une autre police -- alors que les suivants, ecrits des secondes plus tard, tombaient juste.
		--
		-- (Une attente de POLICE avait ete essayee avant : elle ne servait a rien. `rbxasset://` designe un fichier
		-- livre AVEC le client, il n'y a donc rien a telecharger.)
		local deadline = os.clock() + TIP_LAYOUT_WAIT
		while sg.Parent and tipsRow.AbsoluteSize.Y < 1 and os.clock() < deadline do
			RunService.RenderStepped:Wait()
		end
		if not sg.Parent then
			return
		end
		-- La taille du texte se DEDUIT de la hauteur de la ligne : le conseil garde donc les memes proportions sur
		-- tous les ecrans, sans qu'on ait a poser une taille en pixels qui serait juste sur un seul.
		local size = math.max(math.floor(tipsRow.AbsoluteSize.Y), 8)

		local letters: { TextLabel } = {}
		for _, code in utf8.codes(text) do
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			-- AutomaticSize : chaque lettre prend SA largeur. Sans ca il faudrait mesurer le texte, ce qui passe
			-- par un appel asynchrone -- inutile ici, Roblox sait le faire tout seul.
			label.AutomaticSize = Enum.AutomaticSize.X
			label.Size = UDim2.fromScale(0, 1)
			label.Text = utf8.char(code)
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextSize = size
			label.TextTransparency = 1 -- invisible tant qu'elle n'est pas arrivee
			label.FontFace = TIP_FONT
			label.ZIndex = 3
			label.Parent = tipsRow
			letters[#letters + 1] = label
		end
		if #letters == 0 then
			return
		end

		-- UNE IMAGE D'ATTENTE avant de mesurer. `AbsoluteSize` n'est calcule qu'apres le passage de la mise en
		-- page : le lire tout de suite rendrait zero partout, et toutes les lettres se poseraient l'une sur
		-- l'autre.
		RunService.RenderStepped:Wait()
		if not sg.Parent then
			return
		end

		-- ===== UNE SEULE BOUCLE ECRIT LA POSITION DES LETTRES =====
		--
		-- Elle fait DEUX choses a la fois, et c'est justement pour ca qu'elle est unique :
		--   1. le X, qui vient des largeurs mesurees ;
		--   2. le Y, qui vient du rebond.
		--
		-- Ces deux-la ne peuvent pas etre confies a des mecanismes differents. Une police se charge PARESSEUSEMENT :
		-- le premier conseil peut etre dessine avec une police de SECOURS, puis redessine avec la bonne. Roblox
		-- echange le rendu tout seul -- mais pas nos POSITIONS, calculees a la main sur les largeurs de l'ancienne.
		-- Les lettres restaient donc mal espacees, et le mot entier avait l'air d'etre dans une autre police.
		--
		-- On ne peut pas savoir QUAND la vraie police arrive : aucune API ne le dit, et deux tentatives de le
		-- deviner se sont revelees fausses. On cesse donc de deviner -- on RE-MESURE a chaque image et on replace.
		--
		-- Avec des tweens sur Position, ce replacement se serait battu avec l'animation en cours : le tween aurait
		-- continue vers sa cible, calculee sur les anciennes largeurs. D'ou le rebond ecrit a la main.
		--
		-- ON PLACE A LA MAIN plutot qu'avec un UIListLayout, pour la meme raison : un layout repose ses enfants a
		-- chaque image et ecraserait le Y du rebond.
		local token = {}
		tipToken = token
		task.spawn(function()
			local t0 = os.clock()
			-- Duree totale : la derniere lettre part au bout de tous les retards cumules.
			local total = (#letters - 1) * TIP_LETTER_STAGGER + TIP_LETTER_TIME
			-- On continue un peu APRES la fin du rebond : c'est pendant ce rab qu'une police arrivee en retard se
			-- fait rattraper.
			local watchUntil = math.max(total, TIP_WIDTH_WATCH)
			while sg.Parent and tipToken == token do
				local now = os.clock() - t0

				-- LA TAILLE DU TEXTE SE RELIT A CHAQUE IMAGE, elle ne se fige pas.
				--
				-- C'ETAIT LE BUG DU PREMIER CONSEIL, et il a resiste a deux correctifs. La taille se deduit de la
				-- hauteur de la ligne, qui vaut 4.5 % de l'ecran -- mais le rideau s'affiche AVANT que le viewport
				-- ait sa taille definitive. On lisait donc une hauteur trop petite, et le premier conseil sortait
				-- minuscule alors que les suivants tombaient juste.
				--
				-- Attendre "hauteur > 0" ne suffisait pas : la valeur intermediaire est NON NULLE et FAUSSE, donc
				-- l'attente sortait tout de suite. Il n'y a pas d'instant ou l'on peut dire "maintenant c'est bon".
				-- On cesse donc de chercher cet instant -- on relit, et on corrige si ca a bouge. Meme raison que
				-- pour les largeurs juste en dessous, et ca couvre aussi le redimensionnement de la fenetre.
				local live = math.max(math.floor(tipsRow.AbsoluteSize.Y), 8)
				if live ~= size then
					size = live
					for _, label in ipairs(letters) do
						label.TextSize = size
					end
				end
				local rise = size * TIP_LETTER_RISE
				-- LARGEURS RELUES A CHAQUE IMAGE. Une espace ne mesure rien (Roblox rogne les blancs de bord) :
				-- on lui donne une avance fixe, sinon les mots se colleraient.
				local x = 0
				for i, label in ipairs(letters) do
					if not label.Parent then
						return
					end
					local progress = math.clamp((now - (i - 1) * TIP_LETTER_STAGGER) / TIP_LETTER_TIME, 0, 1)
					-- `Back` DEPASSE la place puis y revient : sur du texte ce depassement se lit comme du rebond.
					local eased = TweenService:GetValue(progress, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
					label.Position = UDim2.fromOffset(x, math.floor(rise * (1 - eased)))
					-- La transparence ne rebondit PAS : elle fond droit. Un `Back` la ferait passer sous zero, donc
					-- clignoter. Elle finit aussi plus tot que le mouvement : la lettre est deja lisible quand elle
					-- se pose.
					label.TextTransparency = 1 - math.clamp(progress * 2, 0, 1)
					local w = label.AbsoluteSize.X
					if w < 1 then
						w = size * TIP_SPACE_WIDTH
					end
					x += w
				end
				if now >= watchUntil then
					return
				end
				RunService.RenderStepped:Wait()
			end
		end)
	end

	if #TIPS > 0 then
		task.spawn(function()
			-- On DEMARRE sur un conseil au hasard : commencer toujours par le meme ferait du premier le seul que
			-- les joueurs connaissent, puisque beaucoup ne verront qu'un ou deux chargements.
			local index = math.random(#TIPS)
			writeTip(TIPS[index])
			while sg.Parent do
				task.wait(TIP_INTERVAL)
				if not sg.Parent then
					return
				end
				-- LE CONSEIL SORT D'UN BLOC, il ne se retire pas lettre par lettre. L'apparition merite d'etre
				-- detaillee, la disparition non : personne ne regarde partir un texte qu'il a fini de lire, et
				-- soixante fondus decales feraient trainer la sortie pour rien.
				for _, child in ipairs(tipsRow:GetChildren()) do
					if child:IsA("TextLabel") then
						TweenService:Create(child, TweenInfo.new(TIP_FADE), { TextTransparency = 1 }):Play()
					end
				end
				task.wait(TIP_FADE)
				if not sg.Parent then
					return
				end
				index = index % #TIPS + 1
				writeTip(TIPS[index])
			end
		end)
	end

	-- ===== SON =====
	-- POURQUOI UNE BOUCLE DE RECHERCHE et pas un simple FindFirstChild. Ce rideau vit dans ReplicatedFirst : quand
	-- il s'affiche, SoundService n'a pas forcement encore recu ses dossiers. Un scan unique a cet instant rendrait
	-- nil, et le son ne partirait JAMAIS -- sans la moindre erreur a l'ecran ni dans la console.
	task.spawn(function()
		local deadline = os.clock() + LEAF_SOUND_WAIT
		while sg.Parent and os.clock() < deadline do
			local source = findAnySound(LEAF_SOUND)
			if source then
				playSound(source, LEAF_SOUND_VOLUME)
				return
			end
			task.wait(0.2)
		end
	end)

	-- Chat + liste joueurs : la CoreGui passe AU-DESSUS des ScreenGui, le rideau ne la couvre pas -> on la coupe.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)

	-- Attente, dans l'ORDRE : le jeu charge, PUIS le personnage arrive, PUIS seulement le compte a rebours part.
	-- C'est cet ordre qui compte. Le personnage peut mettre plusieurs secondes a se mettre en place (donnees,
	-- session lock) : un compte lance avant lui serait deja ecoule quand il apparait, et le rideau se leverait
	-- dans la seconde -- exactement le defaut qu'on corrige ici.
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

	-- ===== VOLET DE SORTIE =====
	local wipeGui = Instance.new("ScreenGui")
	wipeGui.Name = "LeafiaWipe"
	wipeGui.ScreenInsets = Enum.ScreenInsets.None
	wipeGui.ResetOnSpawn = false
	wipeGui.DisplayOrder = 2000 -- AU-DESSUS du rideau : c'est lui qui doit le cacher, pas l'inverse
	wipeGui.Parent = player:WaitForChild("PlayerGui")

	local wipe = Instance.new("Frame")
	wipe.BackgroundColor3 = WIPE_COLOR
	wipe.BorderSizePixel = 0
	wipe.Size = UDim2.fromScale(1, 1)
	wipe.Parent = wipeGui

	local wipeGrad = Instance.new("UIGradient")
	wipeGrad.Rotation = WIPE_ROTATION
	wipeGrad.Parent = wipe

	-- CONDAMNE D'AVANCE. Un aplat blanc plein cadre est la pire chose a laisser derriere soi : il cache le jeu
	-- entier et le joueur n'a aucun moyen de s'en debarrasser. On programme donc sa destruction MAINTENANT, avant
	-- meme de l'animer -- si une seule ligne du balayage echoue, il part quand meme.
	-- La marge est large : elle ne sert jamais quand tout va bien, et elle coute une tache endormie.
	task.delay(WIPE_COVER_TIME + WIPE_HOLD + WIPE_REVEAL_TIME + 3, function()
		wipeGui:Destroy()
	end)

	-- ON CONSTRUIT LA SEQUENCE, ON N'ANIME PAS L'OFFSET.
	--
	-- Le sens d'un `UIGradient.Offset` est imprevisible (deja au journal, et deja paye sur cet ecran). Les TEMPS
	-- d'une NumberSequence, eux, sont deterministes : 0 est le debut du degrade, 1 sa fin. En posant les points
	-- soi-meme, on sait exactement ce qu'on fabrique.
	--
	-- `edge` va de 0 a 1 et decrit jusqu'ou le blanc s'etend. Le meme constructeur sert aux deux moitiés du
	-- mouvement : on le fait monter pour couvrir, puis redescendre pour decouvrir -- et cette descente EST le
	-- balayage inverse, sans une ligne de plus.
	local function wipeAt(edge: number)
		if edge >= 1 then
			wipeGrad.Transparency = NumberSequence.new(0) -- tout blanc
			return
		end
		if edge <= 0 then
			wipeGrad.Transparency = NumberSequence.new(1) -- rien
			return
		end
		-- Les temps doivent croitre STRICTEMENT : on force un ecart minimal, sinon Roblox refuse la sequence des
		-- que le bord touche un bord.
		local b = math.clamp(edge, 0.002, 0.998)
		local a = math.clamp(b - WIPE_SOFT, 0.001, b - 0.001)
		wipeGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(a, 0),
			NumberSequenceKeypoint.new(b, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	end

	local function sweep(from: number, to: number, duration: number)
		local t0 = os.clock()
		while true do
			local t = math.clamp((os.clock() - t0) / duration, 0, 1)
			-- Ease in-out : le bord part doucement, file au milieu, se pose. Lineaire, un balayage a l'air
			-- mecanique -- on voit une barre traverser, pas un volet.
			local eased = t * t * (3 - 2 * t)
			wipeAt(from + (to - from) * eased)
			if t >= 1 then
				return
			end
			RunService.RenderStepped:Wait()
		end
	end

	wipeAt(0)
	sweep(0, 1, WIPE_COVER_TIME)

	-- COUVERT : on demonte le rideau pendant qu'on ne voit rien. C'est tout l'interet du volet.
	-- La boucle AVANT le Destroy : elle vit sur RunService, pas sur le GUI, donc detruire le rideau ne la
	-- couperait pas -- elle tournerait sur des instances mortes toute la session.
	if tileConn then
		tileConn:Disconnect()
		tileConn = nil
	end
	sg:Destroy()
	task.wait(WIPE_HOLD)

	-- ET LE JEU APPARAIT. Le meme bord repart en arriere : le volet se retire par ou il est venu.
	sweep(1, 0, WIPE_REVEAL_TIME)
	-- DETRUIT QUOI QU'IL ARRIVE. C'est la garantie qui rend ce volet sans danger : meme si le balayage partait du
	-- mauvais cote, ou si une sequence etait refusee, on ne peut pas se retrouver avec un aplat blanc collé sur
	-- le jeu pour toute la session.
	wipeGui:Destroy()
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
