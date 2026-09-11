--!strict
-- MARQUEUR D'ATTENTION : un point d'exclamation pose sur un objet du monde. Il dit "ici, maintenant" sans un mot.
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

local CIRCLE_IMAGE = "rbxassetid://124707156951795"
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
local markers: {
	[Frame]: { born: number, phase: number, mark: ImageLabel, nextPop: number, base: Vector3 },
} = {}
local stepConn: RBXScriptConnection? = nil

local function getGui(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("ScreenGui")
	created.Name = "LeafiaWorldMarkers"
	-- `None` EST OBLIGATOIRE : WorldAnchor rend des coordonnees dont l'origine est le coin ABSOLU de l'ecran. Avec
	-- l'inset par defaut, tous les marqueurs suivraient 36 px trop bas. Piege deja paye dans ce projet.
	created.ScreenInsets = Enum.ScreenInsets.None
	created.IgnoreGuiInset = true
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
		if now >= state.nextPop then
			state.nextPop = now + MARK_EVERY + math.random() * MARK_JITTER
			popMark(state.mark)
		end
	end
end

-- Pose un marqueur sur une cible. `offset` decale le point vise, en studs -- typiquement pour le mettre au-dessus
-- de la tete. Rend le marqueur, a passer a `remove`.
function WorldMarker.show(target: WorldAnchor.Target, offset: Vector3?): Frame
	local holder = getGui()

	local frame = Instance.new("Frame")
	frame.Name = "Marker"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(SIZE, SIZE)
	frame.Parent = holder

	local circle = Instance.new("ImageLabel")
	circle.Name = "Circle"
	circle.BackgroundTransparency = 1
	circle.Size = UDim2.fromScale(1, 1)
	circle.Image = CIRCLE_IMAGE
	-- `Stretch` sur les DEUX couches, et pas `Fit`. `Fit` conserve les proportions de l'image et la borne par le
	-- plus PETIT cote du cadre : une image en `Fit` ne sait que grossir et rapetisser, elle ne peut pas s'etirer.
	-- Le sursaut du " ! " le RETRECIRAIT au lieu de l'allonger. Piege deja paye sur les feuilles du chargement.
	--
	-- Le cercle est CARRE et son image aussi ; la marque, elle, porte le rapport de son propre dessin (voir
	-- MARK_RATIO). `Stretch` ne deforme donc rien au repos, et reste libre d'etirer pendant le sursaut.
	circle.ScaleType = Enum.ScaleType.Stretch
	circle.Parent = frame

	local mark = Instance.new("ImageLabel")
	mark.Name = "Mark"
	mark.BackgroundTransparency = 1
	-- AUX PROPORTIONS DU DESSIN, jamais au cadre entier : le cercle est carre, le " ! " ne l'est pas.
	mark.Size = UDim2.fromScale(MARK_HEIGHT * MARK_RATIO, MARK_HEIGHT)
	mark.Image = MARK_IMAGE
	mark.ScaleType = Enum.ScaleType.Stretch
	-- ANCRE EN BAS AU MILIEU, et c'est CE QUI REND LE SURSAUT POSSIBLE. Avec une ancre au coin, un " ! " qu'on
	-- etire pousse vers le bas autant que vers le haut et sort du cercle. Ancre par le bas, son pied ne bouge pas
	-- et il s'allonge VERS LE HAUT -- exactement comme les feuilles du chargement.
	mark.AnchorPoint = Vector2.new(0.5, 1)
	mark.Position = UDim2.fromScale(0.5, MARK_BOTTOM)
	-- ENFANT DU CERCLE, pas pose a cote : il herite de sa taille et de sa place, donc les deux ne peuvent pas se
	-- decaler. Deux images placees separement finissent toujours par diverger d'un reglage.
	mark.ZIndex = 2
	mark.Parent = circle

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
	}

	WorldAnchor.attach(frame, target, offset or Vector3.zero, MAX_DISTANCE, SCALE)
	WorldAnchor.setEdgeClamp(frame, EDGE_MARGIN)

	if not stepConn then
		stepConn = RunService.RenderStepped:Connect(step)
	end
	return frame
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
