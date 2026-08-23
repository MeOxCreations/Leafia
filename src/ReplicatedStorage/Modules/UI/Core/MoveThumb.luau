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
-- DYNAMIQUE : il apparait la ou le doigt se pose, dans une zone en bas a gauche. On ne mesure que le DELTA depuis
-- le point de contact, ce qui le rend insensible a l'inset de la barre Roblox -- le decalage se simplifie.
--
-- Purement client, purement visuel : il ne fait que RENDRE une valeur, il ne deplace personne.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local MoveThumb = {}

local player = Players.LocalPlayer

-- CAPACITE tactile, pas input actif : la decision doit etre stable, et vraie dans l'emulateur d'appareil de
-- Studio comme sur un vrai telephone.
local IS_TOUCH = UserInputService.TouchEnabled

-- Zone du bas-gauche ou poser le doigt fait apparaitre le joystick, en fraction d'ecran.
local ZONE_WIDTH = 0.45
local ZONE_HEIGHT = 0.55
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
-- ECART ENTRE LES DEUX REPERES D'ECRAN, MESURE et non deduit.
--
-- `InputObject.Position` et `UserInputService:GetMouseLocation()` ne partent pas forcement du meme coin, et le
-- sens de la difference ne se DEDUIT pas -- ce projet l'a paye trois fois (GetMouseLocation, WorldAnchor, puis
-- ici, ou une correction posee au raisonnement a AGGRAVE le decalage).
--
-- On arrete donc de raisonner : au moment ou le doigt se pose, on lit les DEUX et on garde leur difference. Le
-- resultat est juste quel que soit le repere de chacun, sur n'importe quel appareil, sans rien a regler.
--
-- Pourquoi viser le repere de `GetMouseLocation` : c'est celui du curseur custom du jeu, qui tombe au bon endroit
-- depuis toujours. On se cale sur ce qui est deja prouve a l'ecran plutot que sur ce qui devrait marcher.
local spaceOffset = Vector2.zero
local radius = 90
local value = Vector3.zero
local active = false

local function hideVisuals()
	finger = nil
	value = Vector3.zero
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
		-- ON MESURE L'ECART DES DEUX REPERES, ICI, au moment ou le doigt se pose : les deux valeurs designent
		-- alors le MEME point physique, donc leur difference EST le decalage. Voir `spaceOffset`.
		local raw = Vector2.new(input.Position.X, input.Position.Y)
		spaceOffset = UserInputService:GetMouseLocation() - raw
		origin = raw + spaceOffset
		local camera = workspace.CurrentCamera
		radius = math.max((if camera then camera.ViewportSize.Y else 720) * RADIUS_SCALE, 40)
		ring.Size = UDim2.fromOffset(radius * BASE_SIZE, radius * BASE_SIZE)
		head.Size = UDim2.fromOffset(radius * KNOB_SIZE, radius * KNOB_SIZE)
		ring.Position = UDim2.fromOffset(origin.X, origin.Y)
		head.Position = ring.Position
		ring.Visible = true
		head.Visible = true
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input ~= finger then
			return
		end
		-- MEME ecart qu'a la prise, applique des DEUX cotes : un delta calcule entre deux reperes differents serait
		-- faux d'un decalage constant, donc le joystick partirait deja incline.
		-- On garde l'ecart MESURE a la prise plutot que d'en relire un : celui du doigt qui tient le joystick, pas
		-- celui d'un autre doigt pose entre-temps sur l'ecran.
		local point = Vector2.new(input.Position.X, input.Position.Y) + spaceOffset
		local delta = point - origin
		local length = delta.Magnitude
		local clamped = if length > radius then delta.Unit * radius else delta
		head.Position = UDim2.fromOffset(origin.X + clamped.X, origin.Y + clamped.Y)
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
