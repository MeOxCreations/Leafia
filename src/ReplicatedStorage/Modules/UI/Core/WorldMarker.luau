--!strict
-- MARQUEUR D'ATTENTION : un rond pose sur un objet du monde. Il dit "ici" sans un mot.
--
-- DEUX DESSINS DANS LE MEME ROND. Un point d'exclamation par defaut ("va la, maintenant"), ou une ICONE passee a
-- `show` ("ton outil est ici"). Meme mouvement, meme taille : c'est le dessin qui dit de quoi il s'agit.
--
-- PAS UN BillboardGui, et c'est un choix. Un Billboard vit dans le monde : il subit l'eclairage, il passe derriere
-- les objets, et sa taille depend de la distance. Celui-ci est un ScreenGui projete (WorldAnchor) : pixels
-- constants, couleurs exactes, toujours au-dessus. La primitive existe deja, on ne refait pas sa boucle.
--
-- HORS CHAMP, IL NE DISPARAIT PAS : il se plaque sur le bord de l'ecran, du cote de sa cible. Un marqueur qui
-- s'efface des qu'on tourne la tete ne repond plus a la seule question qu'il pose -- OU.
--
-- PLUSIEURS MARQUEURS A LA FOIS. Contrairement au prompt d'interaction, qui est un singleton : deux choses
-- importantes peuvent l'etre en meme temps, et se les disputer donnerait le meme bug que les prompts qui se
-- volaient la pilule. Chaque appel rend son propre marqueur, qu'on detruit quand on veut.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local WorldAnchor = require(script.Parent.WorldAnchor)

-- SI CE MODULE "N'EXISTE PAS" DANS STUDIO alors qu'il est bien sur le disque : c'est STUDIO qui l'a perdu, pas le
-- code. Un `CTRL+Z` dans l'editeur annule ce que Rojo vient de poser, et Rojo ne le repousse pas -- pour lui,
-- le fichier est deja synchronise, il n'a plus rien a envoyer. Reconnecter le plugin refait une synchro complete.

local WorldMarker = {}

-- LE ROND EST DESSINE EN CODE (un cadre arrondi), plus une image : demande du joueur. Sa couleur et son contour se
-- reglent ici, et il reste net a toutes les tailles d'ecran.
local CIRCLE_COLOR = Color3.fromRGB(228, 38, 38)
-- LE CONTOUR NOIR, en fraction de la taille du rond (`ScaledSize`) : il garde la meme epaisseur visible du PC au
-- telephone, et quand la balise grossit ou rapetisse avec la distance.
local CIRCLE_STROKE_COLOR = Color3.fromRGB(0, 0, 0)
local CIRCLE_STROKE = 0.09
-- UN OBJET INDISPONIBLE : des barreaux en diagonale (dessin du joueur) POSES PAR-DESSUS le rond rouge, sous l'icone.
-- Le rond reste -- c'est lui qui fait reconnaitre une balise ; les rayures disent "c'est la, mais pas pour toi
-- maintenant", et l'icone dit de quel outil on parle.
local LOCKED_STRIPES_IMAGE = "rbxassetid://99020394814206"
local MARK_IMAGE = "rbxassetid://78589393871508"
-- LA MARQUE A SES PROPRES PROPORTIONS, en fraction du cercle. Le dessin fait 63 x 115 pixels a sa taille
-- naturelle : lui donner un cadre CARRE l'ecraserait, et un " ! " ecrase ne ressemble plus a rien.
--
-- Le cercle etant carre, une fraction en X et la meme en Y valent le meme nombre de pixels : la largeur se
-- deduit donc de la hauteur par le rapport du dessin, et il n'y a qu'UN chiffre a regler.
local MARK_HEIGHT = 0.66
local MARK_RATIO = 63 / 115
-- OU SON PIED SE POSE dans le cercle, en fraction. Elle est ancree par le BAS (voir plus loin), donc ce chiffre
-- descend ou remonte le " ! " entier. A 1 il collerait au bord bas ; ici il tombe au milieu du cercle.
local MARK_BOTTOM = 0.83
-- UNE ICONE est carree et centree dans le cercle, en fraction de sa taille. Assez petite pour garder le bord
-- blanc visible autour : c'est lui qui fait la pastille.
local ICON_SIZE = 0.62

-- Taille a la distance de reference, en pixels. Le reste suit la distance via WorldAnchor.
local SIZE = 46
-- Distance a laquelle il fait exactement SIZE, et ses bornes. Sans bornes il deviendrait minuscule de loin et
-- enorme colle dessus -- un marqueur doit rester lisible, pas simuler la perspective.
local SCALE: WorldAnchor.Scale = { ref = 40, min = 0.55, max = 1.3 }
-- Au-dela, il disparait. Un marqueur visible a l'autre bout de la map n'attire pas l'attention, il l'epuise.
local MAX_DISTANCE = 160
-- ET HORS CHAMP, IL RESTE A L'ECRAN, plaque sur le bord du cote de sa cible. Distance au bord, en pixels.
--
-- POURQUOI. Un marqueur qui disparait des qu'on tourne la tete ne repond plus a la seule question qu'il pose :
-- OU. Le joueur qui regarde ailleurs n'a plus rien, et rien ne lui dit qu'il regarde du mauvais cote -- il
-- cherche, alors que l'information existe. Sur le bord, elle continue de pointer.
--
-- La marge tient compte de sa taille (46 px, jusqu'a 1.3 fois de pres) : plus serree, il deborderait de l'ecran.
local EDGE_MARGIN = 42

-- ===== LA TAILLE SUIT L'ECRAN =====
-- SIZE ET EDGE_MARGIN SONT DES PIXELS POUR UN ECRAN DE 1080 DE HAUT. Un telephone n'en a que quelques centaines :
-- la pastille y prenait une grosse part de l'image et ecrasait ce qu'elle designe. On les multiplie donc par la
-- hauteur reelle / 1080, borne : lisible sur un petit ecran, pas minuscule sur un grand.
--
-- LA HAUTEUR ET PAS LA LARGEUR : un telephone en paysage est tres large et tres bas, c'est la hauteur qui manque.
-- Le calcul vit dans WorldAnchor (`screenScale`), partage avec l'onomatopee ; ici seulement le plancher des balises.
local SCREEN_MIN = 0.6
-- Derniere hauteur d'ecran appliquee : on ne retaille qu'au changement (rotation, fenetre redimensionnee).
local lastViewHeight = 0

--- Taille et marge au bord d'un marqueur, a l'echelle de l'ecran. Le grossissement selon la distance passe, lui,
--- par un UIScale (WorldAnchor) : les deux se multiplient sans se gener.
local function resize(frame: Frame)
	local s = WorldAnchor.screenScale(SCREEN_MIN)
	frame.Size = UDim2.fromOffset(SIZE * s, SIZE * s)
	WorldAnchor.setEdgeClamp(frame, EDGE_MARGIN * s)
end

-- ===== LE MOUVEMENT =====
-- Il MONTE ET DESCEND, doucement. C'est ce qui le distingue du decor : l'oeil attrape un mouvement regulier bien
-- avant une forme, meme vive.
local BOB_HEIGHT = 0.45 -- studs
local BOB_SPEED = 2.2 -- radians par seconde
-- Et il RESPIRE, un peu. Le battement est plus RAPIDE que le balancement : deux rythmes proches se synchronisent
-- a l'oeil et l'ensemble se lit comme un seul mouvement mou.
local PULSE = 0.07 -- fraction de taille
local PULSE_SPEED = 4.4

-- APPARITION. Il arrive en grossissant depuis rien : pose a sa taille, on ne remarque pas qu'il vient d'arriver.
local POP_TIME = 0.32

-- ===== LE SURSAUT DU " ! " =====
-- De temps en temps, la barre s'etire vers le HAUT puis revient. Le cercle, lui, ne bouge pas : c'est le contraste
-- entre les deux qui fait le sursaut. Tout etirer d'un bloc donnerait un simple grossissement.
--
-- RESERVE AU " ! ". Une icone qui s'etire se deforme, et un dessin d'outil deforme ne se reconnait plus.
--
-- Ecart entre deux sursauts, en secondes, plus un peu de hasard. Le hasard evite que deux marqueurs poses en meme
-- temps sursautent ENSEMBLE -- ce qui se lirait comme une interface qui clignote, pas comme deux objets vivants.
local MARK_EVERY = 2.6
local MARK_JITTER = 0.9
-- Hauteur atteinte, et largeur pendant l'etirement. La largeur passe SOUS 1 : il s'affine en montant, et c'est
-- ca qui fait la matiere molle -- grandir sans s'affiner ne s'etire pas, ca GROSSIT.
local MARK_SCALE_Y = 1.45
local MARK_SCALE_X = 0.78
-- Montee douce, retour un peu plus long. `Back` en sortie DEPASSE une fois puis se pose. `Elastic` oscillerait
-- plusieurs fois, ce qui se lit comme un tremblement.
local MARK_UP = 0.14
local MARK_BACK = 0.38

local player = Players.LocalPlayer

local gui: ScreenGui? = nil
-- `base` EST LA HAUTEUR DEMANDEE A `show`, gardee. Le balancement s'ecrit dans le MEME champ (l'offset monde de
-- WorldAnchor) : sans cette copie il n'y a pas de quoi la reconstituer, et le battement la remplace.
-- `target` est garde pour repondre a `isMarked`.
local markers: {
	[Frame]: {
		born: number,
		phase: number,
		mark: ImageLabel,
		nextPop: number,
		base: Vector3,
		icon: boolean,
		target: WorldAnchor.Target,
	},
} = {}
local stepConn: RBXScriptConnection? = nil

local function getGui(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("ScreenGui")
	created.Name = "LeafiaWorldMarkers"
	-- `None` : l'interface couvre tout l'ecran, pour qu'une balise ramenee au bord puisse aller jusqu'au bord. La
	-- POSITION, elle, ne depend plus de ce reglage : WorldAnchor la mesure par rapport a ce cadre (voir son en-tete).
	created.ScreenInsets = Enum.ScreenInsets.None
	created.ResetOnSpawn = false
	-- Sous le prompt d'interaction : quand les deux sont la, c'est l'action qu'on doit lire, pas le rappel.
	created.DisplayOrder = 50
	created.Parent = player:WaitForChild("PlayerGui")
	gui = created
	return created
end

-- LE " ! " S'ETIRE VERS LE HAUT, puis revient. Sur la MARQUE seule : le cercle ne bouge pas, et c'est le
-- contraste entre les deux qui fait le sursaut.
local function popMark(mark: ImageLabel)
	if not mark.Parent then
		return
	end
	-- LA TAILLE DE REPOS EST CELLE DU DESSIN, pas le cadre entier : le sursaut part donc de ses vraies
	-- proportions et y revient. Multiplier des facteurs par 1 marchait tant que la marque remplissait tout le
	-- cercle -- ce n'est plus le cas.
	local w, h = MARK_HEIGHT * MARK_RATIO, MARK_HEIGHT
	local normal = UDim2.fromScale(w, h)
	local up = TweenService:Create(
		mark,
		TweenInfo.new(MARK_UP, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(w * MARK_SCALE_X, h * MARK_SCALE_Y) }
	)
	up.Completed:Connect(function()
		if mark.Parent then
			TweenService:Create(mark, TweenInfo.new(MARK_BACK, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = normal,
			}):Play()
		end
	end)
	up:Play()
end

local function step()
	local now = os.clock()
	-- L'ECRAN A CHANGE DE TAILLE (telephone qu'on tourne, fenetre redimensionnee) : on retaille tout. Une
	-- comparaison par image, rien de plus tant qu'il ne bouge pas.
	local camera = workspace.CurrentCamera
	local viewHeight = if camera then camera.ViewportSize.Y else 0
	if viewHeight ~= lastViewHeight then
		lastViewHeight = viewHeight
		for frame in markers do
			resize(frame)
		end
	end
	for frame, state in markers do
		if not frame.Parent then
			continue
		end
		-- L'apparition et le battement se MULTIPLIENT au lieu de se succeder : le marqueur respire deja pendant
		-- qu'il grossit, donc il n'y a aucun instant ou il est immobile.
		local age = now - state.born
		local pop = if POP_TIME > 0 then math.clamp(age / POP_TIME, 0, 1) else 1
		-- Adouci aux deux bouts : il part de rien sans a-coup et se pose sans a-coup.
		pop = pop * pop * (3 - 2 * pop)
		local breathe = 1 + math.sin(now * PULSE_SPEED + state.phase) * PULSE
		WorldAnchor.setScaleMul(frame, pop * breathe)
		-- LE BALANCEMENT PASSE PAR L'OFFSET MONDE, pas par la position a l'ecran : il monte donc DANS LA SCENE,
		-- verticalement, quelle que soit l'orientation de la camera. Un decalage en pixels partirait de travers
		-- des qu'on incline la vue.
		local rise = (math.sin(now * BOB_SPEED + state.phase) * 0.5 + 0.5) * BOB_HEIGHT
		-- IL S'AJOUTE A LA HAUTEUR DEMANDEE, il ne la remplace pas -- et c'est un bug qui a coute trois reglages.
		-- Cette ligne posait `(0, rise, 0)` tout court : la hauteur passee a `show` etait donc effacee a la
		-- premiere image, et TOUS les marqueurs tombaient au pied de leur cible, a 0.45 stud du sol.
		--
		-- Le symptome ne ressemble pas a sa cause : on voit un marqueur trop bas, on monte le chiffre de la
		-- config... et rien ne bouge, parce que le chiffre n'a jamais ete lu plus d'une image. J'ai monte celui de
		-- la tondeuse, puis deux fois celui du grand-pere, avant de venir lire CETTE ligne.
		WorldAnchor.setOffset(frame, state.base + Vector3.new(0, rise, 0))

		-- DE TEMPS EN TEMPS. L'ecart est retire au hasard A CHAQUE fois, pas une seule : deux marqueurs partis
		-- decales finiraient sinon par se rattraper et sursauter ensemble.
		if not state.icon and now >= state.nextPop then
			state.nextPop = now + MARK_EVERY + math.random() * MARK_JITTER
			popMark(state.mark)
		end
	end
end

-- Pose un marqueur sur une cible. `offset` decale le point vise, en studs -- typiquement pour le mettre au-dessus
-- de la tete. `icon` (un "rbxassetid://...") remplace le " ! " par ce dessin. `locked` : l'objet est la mais pas
-- disponible, des rayures se posent sur le rond. Rend le marqueur, a passer a `remove`.
function WorldMarker.show(target: WorldAnchor.Target, offset: Vector3?, icon: string?, locked: boolean?): Frame
	local holder = getGui()

	local frame = Instance.new("Frame")
	frame.Name = "Marker"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(SIZE, SIZE)
	frame.Parent = holder

	-- UN CADRE CARRE ARRONDI A FOND (`UDim.new(0.5, 0)`) : c'est un rond, a toutes les tailles. Le cadre de la balise
	-- est carre, donc rien a contraindre.
	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.BackgroundColor3 = CIRCLE_COLOR
	circle.BorderSizePixel = 0
	circle.Size = UDim2.fromScale(1, 1)
	circle.Parent = frame
	local round = Instance.new("UICorner") :: UICorner
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = circle
	local ring = Instance.new("UIStroke")
	ring.Color = CIRCLE_STROKE_COLOR
	ring.Thickness = CIRCLE_STROKE
	ring.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	ring.Parent = circle

	local mark = Instance.new("ImageLabel")
	mark.Name = "Mark"
	mark.BackgroundTransparency = 1
	if icon then
		-- UNE ICONE : carree, centree, en `Fit`. Elle ne sursaute pas, donc rien ne l'oblige a `Stretch` -- et `Fit`
		-- garde un dessin qui ne serait pas tout a fait carre sans le deformer.
		mark.Image = icon
		mark.Size = UDim2.fromScale(ICON_SIZE, ICON_SIZE)
		mark.ScaleType = Enum.ScaleType.Fit
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromScale(0.5, 0.5)
	else
		-- AUX PROPORTIONS DU DESSIN, jamais au cadre entier : le cercle est carre, le " ! " ne l'est pas.
		mark.Size = UDim2.fromScale(MARK_HEIGHT * MARK_RATIO, MARK_HEIGHT)
		mark.Image = MARK_IMAGE
		mark.ScaleType = Enum.ScaleType.Stretch
		-- ANCRE EN BAS AU MILIEU, et c'est CE QUI REND LE SURSAUT POSSIBLE. Avec une ancre au coin, un " ! " qu'on
		-- etire pousse vers le bas autant que vers le haut et sort du cercle. Ancre par le bas, son pied ne bouge
		-- pas et il s'allonge VERS LE HAUT -- exactement comme les feuilles du chargement.
		mark.AnchorPoint = Vector2.new(0.5, 1)
		mark.Position = UDim2.fromScale(0.5, MARK_BOTTOM)
	end
	-- ENFANT DU CERCLE, pas pose a cote : il herite de sa taille et de sa place, donc les deux ne peuvent pas se
	-- decaler. Deux images placees separement finissent toujours par diverger d'un reglage.
	mark.ZIndex = 3
	mark.Parent = circle

	-- LES RAYURES, entre le rond et l'icone : elles barrent le rond sans cacher de quoi il s'agit.
	if locked then
		local stripes = Instance.new("ImageLabel")
		stripes.Name = "Stripes"
		stripes.BackgroundTransparency = 1
		stripes.Size = UDim2.fromScale(1, 1)
		stripes.Image = LOCKED_STRIPES_IMAGE
		stripes.ScaleType = Enum.ScaleType.Stretch
		stripes.ZIndex = 2
		stripes.Parent = circle
	end

	-- LE BALANCEMENT PART A UNE PHASE AU HASARD. Deux marqueurs poses en meme temps monteraient et descendraient
	-- ensemble, ce qui se lit comme une interface qui clignote au lieu de deux objets vivants.
	markers[frame] = {
		born = os.clock(),
		phase = math.random() * math.pi * 2,
		mark = mark,
		-- Le PREMIER sursaut est deja decale au hasard : sinon tous les marqueurs poses au meme instant
		-- sursauteraient ensemble, et seuls les suivants se decaleraient.
		nextPop = os.clock() + POP_TIME + math.random() * MARK_JITTER,
		base = offset or Vector3.zero,
		icon = icon ~= nil,
		target = target,
	}

	WorldAnchor.attach(frame, target, offset or Vector3.zero, MAX_DISTANCE, SCALE)
	-- APRES attach : la marge au bord s'ecrit sur l'entree que `attach` vient de creer.
	resize(frame)

	if not stepConn then
		stepConn = RunService.RenderStepped:Connect(step)
	end
	return frame
end

--- UN MARQUEUR EST-IL DEJA POSE SUR CET OBJET (ou sur une de ses parts) ? `ignore` ecarte les marqueurs de
--- l'appelant, qui ne doit pas se voir lui-meme.
---
--- Sert a ne pas empiler deux pastilles sur le meme objet quand deux features le designent en meme temps : le
--- didacticiel qui dit "demarre CETTE tondeuse", et les pastilles des outils qui disent "une tondeuse est ici".
function WorldMarker.isMarked(container: Instance, ignore: { [Frame]: boolean }?): boolean
	for frame, state in markers do
		if not (ignore and ignore[frame]) and typeof(state.target) == "Instance" then
			local target = state.target :: Instance
			if target == container or target:IsDescendantOf(container) then
				return true
			end
		end
	end
	return false
end

function WorldMarker.remove(frame: Frame?)
	if not frame then
		return
	end
	WorldAnchor.detach(frame)
	markers[frame] = nil
	frame:Destroy()
	-- LA BOUCLE MEURT AVEC LE DERNIER MARQUEUR. Une boucle par frame qui tourne sur une table vide toute la
	-- session ne coute presque rien -- mais "presque rien" repete a chaque primitive finit par se voir.
	if stepConn and next(markers) == nil then
		stepConn:Disconnect()
		stepConn = nil
	end
end

return WorldMarker
