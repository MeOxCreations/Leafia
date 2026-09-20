--!strict
-- LE RIDEAU DE CHARGEMENT DE LEAFIA : ciel degrade, tuile, halo, visage du grand-pere, couronne de points, bandeau et
-- nom du lieu. Son DESSIN (`build`) et ses ANIMATIONS (`animate`).
--
-- TROIS ECRANS LE MONTRENT, et c'est pour ca qu'il vit a part :
--   * le rideau du bouton START (LoadingOverlay), anime ;
--   * l'ecran PENDANT le teleport (TeleportController), FIGE -- aucun script ne tourne pendant le voyage ;
--   * le rideau d'ARRIVEE dans une place (LoadingScreenClient), anime.
-- Trois copies finissaient par diverger, et c'est arrive : le START montrait une feuille grise qui se remplissait,
-- le teleport un fond gris a quatre boules, et seule l'arrivee montrait le ciel et le grand-pere.
--
-- DANS ReplicatedFirst : il doit etre lisible avant que le reste du jeu soit replique. Un module de ReplicatedStorage
-- ferait attendre ce que le rideau est justement la pour masquer.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local FaceEyes = require(script.Parent.FaceEyes)

local CurtainVisual = {}

export type Built = { face: ImageLabel }

-- PAS DE TUILE SUR MOBILE, a la demande du joueur apres test sur telephone. Le ciel degrade, le visage et la couronne
-- restent : seul le motif qui defile disparait.
--
-- COUPEES : le fond est un blanc nu. Le motif est garde en code plutot que supprime -- il se rallume d'une ligne,
-- et sa mecanique de defilement (periode relue a chaque image) n'est pas triviale a reecrire.

-- COULEUR DE SECOURS DU CONTENEUR. Elle ne se voit qu'un instant -- celui ou le rideau existe deja mais ou son cadre
-- degrade n'est pas encore pose -- et partout ou ce cadre ne couvrirait pas.
--
-- Une couleur de secours doit ressembler a ce qu'elle remplace, sinon elle se voit precisement parce qu'elle est
-- de secours : un gris fonce creait un FLASH SOMBRE avant le fond. Ici le fond est BLANC, comme le grand ecran de
-- premier lancement -- une seule encre noire, aucun aplat de couleur.
CurtainVisual.BG = Color3.fromRGB(255, 255, 255)

-- L'ENCRE UNIQUE. Tout le dessin du rideau en noir sur blanc : le meme parti pris que l'ecran de chargement
-- principal, pour que les deux se lisent comme un seul jeu et pas comme deux ecrans empruntes ailleurs.
local INK = Color3.fromRGB(0, 0, 0)

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
-- Un gris tres clair : il se pose SUR le fond blanc sans s'en detacher comme le ferait un aplat noir. Rend
-- exactement ce qu'il dit parce que l'image est blanche (un UIGradient multiplie la couleur de l'objet).
local BANNER_COLOR = ColorSequence.new(Color3.fromRGB(232, 232, 232))

-- ===== FOND DEGRADE =====
-- BLANC QUI SE GRISE TRES LEGEREMENT, en diagonale : seule la luminosite voyage, donc le fond se lit comme un
-- espace et pas comme un motif. 40 degres : la lumiere vient du haut-gauche. Le sens d'un UIGradient ne se DEDUIT
-- pas -- si la lumiere part du mauvais coin, ce nombre est la premiere chose a tourner.
local BG_ROTATION = 40
local BG_COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.38, Color3.fromRGB(250, 250, 250)),
	ColorSequenceKeypoint.new(0.74, Color3.fromRGB(235, 235, 235)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(214, 214, 214)),
})

-- ===== LE VISAGE DU GRAND-PERE, AU CENTRE =====
-- Un visage dit CHEZ QUI l'on va -- c'est lui, le personnage qu'on va rencontrer. De face, et trois images pour le
-- clignement (ouvert, a moitie, ferme).
-- LA TETE EST CELLE DE L ECRAN PRINCIPAL, dessinee SANS yeux : ils sont des calques poses dessus par `FaceEyes`,
-- qui gere aussi le regard, le clignement et le clin d oeil. Un seul visage pour les deux ecrans, donc un seul
-- endroit a regler -- et le personnage est le meme partout.
local FACE_FRONT = FaceEyes.HEAD
-- LES DEUX COTES EN FRACTION DE LA HAUTEUR (`RelativeYY`), comme la couronne de points. La largeur etait en fraction
-- de la LARGEUR : sur un telephone (2340 x 1080, bien plus large qu'un ecran PC) la tete, en `Stretch`, sortait 22 %
-- plus large que haute -- ecrasee. 0.2365 = l'ancienne largeur (0.133) ramenee a la hauteur d'un ecran 16:9.
-- SUR PC, 60 % de cette taille : a pleine taille elle mangeait le milieu d'un grand ecran (demande du joueur). Le
-- telephone garde la sienne, reglee a part et jugee bonne. `TouchEnabled` seul, comme SHOW_TILE.
local FACE_PC_SCALE = 0.6
local FACE_K = if UserInputService.TouchEnabled then 1 else FACE_PC_SCALE
-- LE VISAGE EST LE SUJET DE L ECRAN : il porte le personnage, tout le reste n est que de l attente. Un facteur
-- unique plutot que deux nombres retouches a la main -- les proportions de la tete ne bougent pas avec lui.
local FACE_SCALE = 1.9
local FACE_SIZE = UDim2.fromScale(0.2365 * FACE_K * FACE_SCALE, 0.229 * FACE_K * FACE_SCALE)
-- IL SE DEPLIE EN ARRIVANT. Ecrase a plat sur la verticale, puis il s'ouvre en rebondissant.
--
-- `Elastic` en sortie : elle DEPASSE la taille visee puis oscille en s'amortissant -- c'est ce depassement qui fait
-- la matiere molle. Assez long pour qu'on VOIE les oscillations : sous ~0.4 s, Elastic n'a pas le temps d'osciller
-- et rend la meme chose qu'un ease ordinaire.
local FACE_POP_TIME = 0.75
-- Un souffle avant de partir : deplier pile a l'image zero, ca se perd dans le fondu d'arrivee du rideau.
local FACE_POP_DELAY = 0.15
-- IL TANGUE, tres doucement. FAIBLE ET LENT, les deux ensemble : une amplitude large ferait un metronome, une
-- amplitude faible mais rapide un tremblement.
local FACE_SWAY_ANGLE = 4 -- degres de chaque cote
local FACE_SWAY_SPEED = 0.6 -- radians par seconde : un aller-retour complet en une dizaine de secondes
-- LE CLIN D OEIL, une fois le visage pose. Compte depuis le depliage : avant lui, la tete est encore a plat.
local FACE_WINK_AFTER = 1.2
-- Duree de chaque etape. TRES court : un clignement lent se lit comme de la fatigue ou un bug d'affichage.

-- ===== DESTINATION =====
-- Le lieu ou l'on va, en haut a droite. ReplicatedFirst ne peut pas require PlacesConfig : les identifiants sont EN
-- DUR ici, a tenir d'accord a la main -- c'est le prix de tourner aussi tot.
local DEST_BY_PLACE: { [number]: string } = {
	[84161484719535] = "LEAFIA",
	[109440527457437] = "TUTORIAL",
	[124669452423388] = "CLIENT",
	[77113670151896] = "TEST",
}
-- QUAND ON NE SAIT PAS ENCORE OU L'ON VA : le START (le serveur n'a pas encore repondu) et l'ecran du teleport.
CurtainVisual.DEST_FALLBACK = "LOADING"
local DEST_POS = UDim2.fromScale(0.988, 0.056)
local DEST_SIZE = UDim2.fromScale(0.3, 0.075)

--- Le nom affiche pour ce lieu.
function CurtainVisual.destFor(placeId: number): string
	return DEST_BY_PLACE[placeId] or CurtainVisual.DEST_FALLBACK
end

--- Dessine le rideau dans `container` (plein ecran). FIGE : rien ne bouge tant qu'on n'appelle pas `animate`.
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

	local face = Instance.new("ImageLabel")
	face.Name = "OldManFace"
	face.BackgroundTransparency = 1
	face.Image = FACE_FRONT
	-- `Stretch` ET SURTOUT PAS `Fit` : l'animation l'ECRASE a plat puis le deplie. En `Fit`, ecraser sa hauteur ferait
	-- RETRECIR la tete entiere au lieu de l'aplatir -- une image en `Fit` ne sait que grossir et rapetisser. Le prix :
	-- la tete prend les proportions de son cadre, d'ou le `RelativeYY` juste en dessous.
	face.ImageColor3 = INK -- noir sur blanc : sans ca, la tete blanche disparaitrait dans le fond
	face.ScaleType = Enum.ScaleType.Stretch
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.SizeConstraint = Enum.SizeConstraint.RelativeYY
	-- POSE A SA TAILLE PLEINE : c'est l'image figee du teleport. `animate` la replie a plat avant de la deplier.
	face.Size = FACE_SIZE
	FaceEyes.fade(face) -- le meme fondu que sur le grand ecran : il efface le bas du visage et lui donne son gris
	face.ZIndex = 5
	face.Parent = container

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
	dest.TextColor3 = Color3.fromRGB(0, 0, 0)
	dest.TextScaled = true
	dest.TextXAlignment = Enum.TextXAlignment.Right
	-- MONTSERRAT HEAVY (la graisse 900) : une lettre nette, et les accents des langues que Roblox traduit.
	dest.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy, Enum.FontStyle.Normal)
	dest.ZIndex = 4
	dest.Parent = container

	return { face = face }
end

--- Anime un rideau construit par `build` : la tuile defile, le visage se deplie (si `pop`), tangue et cligne, la
--- couronne tourne. Rend la fonction qui ARRETE tout -- a appeler AVANT de detruire le rideau, parce que les boucles
--- vivent sur RunService et survivraient a ses instances.
---
--- `pop` a faux : le visage est deja a l'ecran a sa taille (arrivee apres un teleport). Le replier pour le deplier le
--- ferait disparaitre puis revenir pile au moment ou deux ecrans se relaient.
function CurtainVisual.animate(built: Built, pop: boolean): () -> ()
	local face = built.face
	local alive = true
	local conns: { RBXScriptConnection } = {}

	-- Les calques suivent la tete : poses DANS elle, ils heritent de sa taille et de son depliage sans un calcul.
	-- Le fondu se REPOSE sur chaque calque : un enfant n herite pas du UIGradient de son parent, et sans lui les
	-- yeux resteraient pleins la ou la tete s estompe.
	local eyes = FaceEyes.attach(face, { zIndex = face.ZIndex + 1, decorate = FaceEyes.fade })

	-- LE TANGAGE. Le temps ECOULE et pas un compteur par image : a bas FPS, un compteur ralentirait la rotation.
	local swayTime = 0
	table.insert(
		conns,
		RunService.Heartbeat:Connect(function(dt: number)
			-- Un sinus : il ralentit en arrivant a un bout et repart. Un aller-retour lineaire claquerait aux bouts.
			swayTime += dt
			-- LA SOMME DES DEUX : le tangage ici, le penchement du clin d oeil dans `FaceEyes`. Chacun ecrivant de
			-- son cote, le dernier a parler effacerait l autre.
			face.Rotation = math.sin(swayTime * FACE_SWAY_SPEED) * FACE_SWAY_ANGLE + eyes.tilt()
		end)
	)

	if pop then
		-- A PLAT AU DEPART, grandi depuis son CENTRE : le haut et le bas s'ecartent ensemble, ce qui se lit comme un
		-- depliage.
		face.Size = UDim2.fromScale(FACE_SIZE.X.Scale, 0)
		task.delay(FACE_POP_DELAY, function()
			if not alive then
				return
			end
			TweenService:Create(
				face,
				TweenInfo.new(FACE_POP_TIME, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
				{ Size = FACE_SIZE }
			):Play()
		end)
	end

	-- IL REGARDE AUTOUR DE LUI, CLIGNE, ET FAIT UN CLIN D OEIL. Tout vient de `FaceEyes` : le meme visage vit de
	-- la meme facon sur les deux ecrans.
	task.delay(FACE_WINK_AFTER, function()
		if alive then
			eyes.wink()
		end
	end)

	return function()
		alive = false
		eyes.stop() -- ses boucles vivent sur des threads a elles : detruire le rideau ne les couperait pas
		for _, conn in conns do
			conn:Disconnect()
		end
		table.clear(conns)
	end
end

return CurtainVisual
