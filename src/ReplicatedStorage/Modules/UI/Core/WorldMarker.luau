--!strict
-- MARQUEUR D'ATTENTION : un point d'exclamation pose sur un objet du monde. Il dit "ici, maintenant" sans un mot.
--
-- PAS UN BillboardGui, et c'est un choix. Un Billboard vit dans le monde : il subit l'eclairage, il passe derriere
-- les objets, et sa taille depend de la distance. Celui-ci est un ScreenGui projete (WorldAnchor) : pixels
-- constants, couleurs exactes, toujours au-dessus. La primitive existe deja, on ne refait pas sa boucle.
--
-- PLUSIEURS MARQUEURS A LA FOIS. Contrairement au prompt d'interaction, qui est un singleton : deux choses
-- importantes peuvent l'etre en meme temps, et se les disputer donnerait le meme bug que les prompts qui se
-- volaient la pilule. Chaque appel rend son propre marqueur, qu'on detruit quand on veut.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WorldAnchor = require(script.Parent.WorldAnchor)

-- SI CE MODULE "N'EXISTE PAS" DANS STUDIO alors qu'il est bien sur le disque : c'est STUDIO qui l'a perdu, pas le
-- code. Un `CTRL+Z` dans l'editeur annule ce que Rojo vient de poser, et Rojo ne le repousse pas -- pour lui,
-- le fichier est deja synchronise, il n'a plus rien a envoyer. Reconnecter le plugin refait une synchro complete.

local WorldMarker = {}

local CIRCLE_IMAGE = "rbxassetid://124707156951795"
local MARK_IMAGE = "rbxassetid://126407419808567"

-- Taille a la distance de reference, en pixels. Le reste suit la distance via WorldAnchor.
local SIZE = 96
-- Distance a laquelle il fait exactement SIZE, et ses bornes. Sans bornes il deviendrait minuscule de loin et
-- enorme colle dessus -- un marqueur doit rester lisible, pas simuler la perspective.
local SCALE: WorldAnchor.Scale = { ref = 40, min = 0.55, max = 1.3 }
-- Au-dela, il disparait. Un marqueur visible a l'autre bout de la map n'attire pas l'attention, il l'epuise.
local MAX_DISTANCE = 160

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

local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local markers: { [Frame]: { born: number, phase: number } } = {}
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
		WorldAnchor.setOffset(frame, Vector3.new(0, rise, 0))
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
	circle.ScaleType = Enum.ScaleType.Fit
	circle.Parent = frame

	local mark = Instance.new("ImageLabel")
	mark.Name = "Mark"
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromScale(1, 1)
	mark.Image = MARK_IMAGE
	mark.ScaleType = Enum.ScaleType.Fit
	-- ENFANT DU CERCLE, pas pose a cote : il herite de sa taille et de sa place, donc les deux ne peuvent pas se
	-- decaler. Deux images placees separement finissent toujours par diverger d'un reglage.
	mark.ZIndex = 2
	mark.Parent = circle

	-- LE BALANCEMENT PART A UNE PHASE AU HASARD. Deux marqueurs poses en meme temps monteraient et descendraient
	-- ensemble, ce qui se lit comme une interface qui clignote au lieu de deux objets vivants.
	markers[frame] = { born = os.clock(), phase = math.random() * math.pi * 2 }

	WorldAnchor.attach(frame, target, offset or Vector3.zero, MAX_DISTANCE, SCALE)

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
