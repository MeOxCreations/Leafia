--!strict
-- JOYSTICK DE DEPLACEMENT TACTILE, a nous.
--
-- POURQUOI IL EXISTE. Le thumbstick tactile de Roblox cesse de remonter un vecteur de deplacement des qu'une
-- feature prend la camera en main (`GetMoveVector` rend zero). Sur mobile, le joueur ne peut alors plus bouger du
-- tout -- et rien ne le signale : l'input arrive bien au jeu, il n'arrive juste plus jusqu'a nous.
--
-- Constate deux fois : sur le travail de la haie (camera scriptee) puis sur la tondeuse. La deuxieme fois a coute
-- plusieurs corrections a cote -- verrouillage de souris, detection d'appareil -- avant qu'on remonte a la cause.
-- D'ou ce module : la prochaine feature qui prend la camera n'aura qu'a l'allumer.
--
-- FIXE, ET C'EST UN CHOIX. Il a d'abord ete DYNAMIQUE -- il apparaissait la ou le doigt se posait -- et il s'est
-- pose a cote du pouce sur tous les ecrans. Quatre tentatives pour recaler les coordonnees ont echoue, dont deux
-- qui ont AGGRAVE le decalage.
--
-- Le probleme n'etait pas le reglage mais l'APPROCHE : convertir une position de doigt en position d'interface
-- demande de savoir laquelle des deux compte la barre du haut, et ca ne se deduit pas.
--
-- En le posant a une place FIXE, exprimee en fraction d'ecran, il n'y a plus AUCUNE conversion : la place est
-- juste sur tous les formats par construction. Et le bouton ne suit que le DELTA du doigt -- une difference, qui
-- annule n'importe quel decalage de repere sans avoir a le connaitre.
--
-- Le joueur pose son pouce n'importe ou dans la zone du bas ; c'est le mouvement qui compte, pas l'endroit. C'est
-- d'ailleurs ce que font la plupart des jeux mobiles.
--
-- Purement client, purement visuel : il ne fait que RENDRE une valeur, il ne deplace personne.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local MoveThumb = {}

local player = Players.LocalPlayer

-- CAPACITE tactile, pas input actif : la decision doit etre stable, et vraie dans l'emulateur d'appareil de
-- Studio comme sur un vrai telephone.
local IS_TOUCH = UserInputService.TouchEnabled

-- Zone du bas-gauche ou poser le doigt prend le joystick, en fraction d'ecran.
local ZONE_WIDTH = 0.45
local ZONE_HEIGHT = 0.55
-- OU LE JOYSTICK EST DESSINE, en fraction d'ecran. En SCALE et pas en pixels : c'est ce qui le place au meme
-- endroit relatif sur un petit telephone comme sur une tablette, sans une ligne de calcul.
local ANCHOR_POS = UDim2.fromScale(0.17, 0.74)
-- Rayon de deplacement maximal du bouton, en fraction de la HAUTEUR d'ecran. En fraction et pas en pixels : sur
-- une tablette un rayon en pixels serait minuscule, sur un petit telephone il sortirait de l'ecran.
local RADIUS_SCALE = 0.11
local BASE_SIZE = 2.2 -- taille du cercle de fond, en multiples du rayon
local KNOB_SIZE = 0.9 -- taille du bouton, en multiples du rayon
local COLOR = Color3.fromRGB(255, 255, 255)
local BASE_TRANSPARENCY = 0.85
local KNOB_TRANSPARENCY = 0.5

local gui: ScreenGui? = nil
local base: Frame? = nil
local knob: Frame? = nil
local finger: InputObject? = nil
local origin = Vector2.zero
local radius = 90
local value = Vector3.zero
local active = false

local function hideVisuals()
	finger = nil
	value = Vector3.zero
	if knob then
		-- Le bouton revient au centre du fond : lache en pleine course, il resterait sinon colle sur le bord et la
		-- prochaine prise partirait d'une image fausse.
		(knob :: Frame).Position = ANCHOR_POS
	end
	if base then
		(base :: Frame).Visible = false
	end
	if knob then
		(knob :: Frame).Visible = false
	end
end

local function circle(name: string, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = COLOR
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.Visible = false
	-- N'AVALE AUCUN INPUT : le cercle est un DESSIN. C'est la zone invisible qui ecoute, pas lui -- sinon un doigt
	-- pose pile dessus serait ignore par la zone et le joystick ne partirait jamais.
	frame.Active = false
	local round = Instance.new("UICorner") :: UICorner
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = frame
	return frame
end

local function build()
	if gui or not IS_TOUCH then
		return
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "LeafiaMoveThumb"
	screen.ResetOnSpawn = false
	-- Coordonnees ECRAN brutes : on compare des positions de doigt a des positions d'element, il faut le meme
	-- repere des deux cotes.
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.DisplayOrder = 20
	screen.Enabled = false
	screen.Parent = playerGui

	-- ZONE D'ECOUTE, invisible et large. C'est ELLE qui est Active : un doigt pose n'importe ou dedans prend le
	-- joystick, meme loin du dessin. On ne demande pas au joueur de viser un cercle qu'il ne regarde pas.
	local zone = Instance.new("TextButton")
	zone.Name = "Zone"
	zone.BackgroundTransparency = 1
	zone.Text = ""
	zone.AutoButtonColor = false
	zone.AnchorPoint = Vector2.new(0, 1)
	zone.Position = UDim2.fromScale(0, 1)
	zone.Size = UDim2.fromScale(ZONE_WIDTH, ZONE_HEIGHT)
	zone.Parent = screen

	local ring = circle("Base", BASE_TRANSPARENCY)
	ring.Parent = screen
	local head = circle("Knob", KNOB_TRANSPARENCY)
	head.Parent = screen

	zone.InputBegan:Connect(function(input: InputObject)
		if not active or finger or input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		finger = input
		-- ON NE RETIENT QUE LE POINT DE DEPART, jamais pour le DESSINER : il ne sert qu'a mesurer un DELTA. Aucune
		-- conversion de repere n'est donc necessaire -- une difference annule n'importe quel decalage.
		origin = Vector2.new(input.Position.X, input.Position.Y)
		local camera = workspace.CurrentCamera
		radius = math.max((if camera then camera.ViewportSize.Y else 720) * RADIUS_SCALE, 40)
		ring.Size = UDim2.fromOffset(radius * BASE_SIZE, radius * BASE_SIZE)
		head.Size = UDim2.fromOffset(radius * KNOB_SIZE, radius * KNOB_SIZE)
		-- LE FOND NE BOUGE PAS. Il est pose en fraction d'ecran, donc au meme endroit relatif partout.
		ring.Position = ANCHOR_POS
		head.Position = ANCHOR_POS
		ring.Visible = true
		head.Visible = true
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input ~= finger then
			return
		end
		-- UNE DIFFERENCE, RIEN QU'UNE DIFFERENCE. C'est ce qui rend ce joystick insensible au repere : peu importe
		-- d'ou l'on compte, l'ecart entre deux points du meme repere est le meme.
		local delta = Vector2.new(input.Position.X, input.Position.Y) - origin
		local length = delta.Magnitude
		local clamped = if length > radius then delta.Unit * radius else delta
		-- Le bouton s'ecarte du FOND, qui lui ne bouge pas : on ajoute donc le delta a la position d'ancrage.
		head.Position = UDim2.new(
			ANCHOR_POS.X.Scale,
			ANCHOR_POS.X.Offset + clamped.X,
			ANCHOR_POS.Y.Scale,
			ANCHOR_POS.Y.Offset + clamped.Y
		)
		-- L'ECRAN DESCEND QUAND Y MONTE, le monde AVANCE quand Z descend : les deux conventions s'annulent, donc
		-- tirer le doigt vers le BAS donne bien Z positif, c'est-a-dire reculer.
		value = Vector3.new(clamped.X / radius, 0, clamped.Y / radius)
	end)

	-- ON ECOUTE LA FIN AU NIVEAU DU SERVICE, pas du bouton : un doigt qui GLISSE hors de la zone avant de se lever
	-- ne declencherait jamais l'evenement du bouton, et le joystick resterait colle a fond pour toujours.
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == finger then
			hideVisuals()
		end
	end)

	gui = screen
	base = ring
	knob = head
end

--- Montre le joystick (tactile uniquement). Sans effet ailleurs : sur un PC il n'y a rien a montrer.
function MoveThumb.show()
	if not IS_TOUCH or active then
		return
	end
	active = true
	build()
	local screen = gui
	if screen then
		screen.Enabled = true
	end
end

--- Le cache et remet sa valeur a zero. A appeler en SORTANT de l'etat qui l'a demande : un joystick oublie a
--- l'ecran continuerait de rendre une valeur, et le joueur se demanderait pourquoi il derive.
function MoveThumb.hide()
	if not active then
		return
	end
	active = false
	hideVisuals()
	local screen = gui
	if screen then
		screen.Enabled = false
	end
end

--- Direction demandee, dans le MEME repere que `ControlModule:GetMoveVector` : X = pas de cote, Z = arriere.
--- Vecteur nul si le joystick est cache ou si aucun doigt ne le tient.
function MoveThumb.get(): Vector3
	return if active then value else Vector3.zero
end

return MoveThumb
