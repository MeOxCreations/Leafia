--!strict
-- LA BARRE DES OUTILS DU CAMION, en bas de l'ecran. Une case par outil encore range dans la benne : son dessin,
-- son nom, et un bouton pour le sortir.
--
-- L'APERCU EST LE VRAI MODELE 3D, dans un `ViewportFrame`, et pas une icone. Trois raisons. Il n'y a AUCUNE icone
-- a dessiner ni a tenir a jour -- ajouter un outil dans la benne le fait apparaitre ici tout seul. Le joueur voit
-- EXACTEMENT l'objet qu'il va recevoir, pas un symbole a interpreter. Et le jour ou un modele change, l'interface
-- change avec lui sans qu'on y touche.
--
-- ELLE NE DECIDE RIEN. On lui donne une liste de modeles et une fonction a appeler ; ce qui est ouvert, ce qui est
-- deja sorti et ce qui vole est l'affaire du controller et du serveur.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local TruckToolsHandler = {}

local player = Players.LocalPlayer

-- ===== LA BARRE =====
-- EN BAS, CENTREE. C'est la place des interfaces qu'on utilise sans quitter le jeu des yeux : le regard y descend
-- et remonte. Au milieu de l'ecran, elle cacherait le camion dont elle parle.
local BAR_POS = UDim2.fromScale(0.5, 0.955)
local SLOT_SIZE = UDim2.fromOffset(118, 142)
local SLOT_GAP = 10
-- SA PLACE CACHEE : sous le bord bas. Elle GLISSE depuis le bas plutot que d'apparaitre -- un panneau qui surgit
-- se remarque moins qu'un panneau qui ARRIVE, et le mouvement dit d'ou il vient.
local HIDDEN_POS = UDim2.fromScale(0.5, 1.35)
local SLIDE_IN = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local BG = Color3.fromRGB(28, 40, 52)
local BG_TRANSPARENCY = 0.15
local STROKE = Color3.fromRGB(255, 255, 255)
local STROKE_TRANSPARENCY = 0.65
local TEXT = Color3.fromRGB(255, 255, 255)
-- LE VERT DU JEU, celui des taches : c'est la meme famille d'action -- avancer, prendre, faire.
local TAKE = Color3.fromRGB(98, 206, 59)
local TAKE_HOVER = Color3.fromRGB(126, 226, 88)

-- La camera de l'apercu. `FOV` serre = peu de perspective, donc l'objet ne se deforme pas dans le coin du cadre.
local VIEW_FOV = 28
-- De combien on recule, en MULTIPLE de la taille de l'objet : un rateau et un seau n'ont pas la meme taille, et
-- une distance fixe montrerait l'un en entier et l'autre en gros plan.
local VIEW_BACK = 1.9
-- L'angle de vue : de trois quarts et un peu de dessus, comme une vitrine. De face, un objet plat disparait.
local VIEW_YAW = 35
local VIEW_PITCH = 18

-- ===== LES MOTS =====
-- EN ANGLAIS, comme tout texte vu par le joueur.
local TAKE_TEXT = "TAKE"
local TITLE_TEXT = "IN THE TRUCK"

local gui: ScreenGui? = nil
local bar: Frame? = nil
local row: Frame? = nil
local shown = false
local slideTween: Tween? = nil

local function getGui(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("ScreenGui")
	created.Name = "LeafiaTruckTools"
	created.ResetOnSpawn = false
	created.IgnoreGuiInset = true
	created.ScreenInsets = Enum.ScreenInsets.None
	-- Au-dessus du jeu mais SOUS les notifications : une alerte doit pouvoir passer par-dessus une vitrine.
	created.DisplayOrder = 55
	created.Parent = player:WaitForChild("PlayerGui")
	gui = created
	return created
end

-- Le cast est OBLIGATOIRE : luau-lsp ne resout pas `Instance.new("UICorner")` vers `UICorner`, et poser
-- `.CornerRadius` sur ce qu'il croit etre une `Instance` sort en erreur rouge.
local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, thickness: number, transparency: number)
	local s = Instance.new("UIStroke")
	s.Color = STROKE
	s.Thickness = thickness
	s.Transparency = transparency
	s.Parent = parent
end

--- L'APERCU 3D D'UN MODELE, cadre tout seul sur sa taille.
---
--- LE CLONE EST ANCRE ET SANS SCRIPT : un ViewportFrame ne simule rien, mais un modele qui arrive avec ses joints
--- et ses parts libres s'y affiche dans la pose ou la physique l'avait laisse.
local function preview(model: Model, parent: Instance)
	local view = Instance.new("ViewportFrame")
	view.Name = "Preview"
	view.BackgroundTransparency = 1
	view.Size = UDim2.fromScale(1, 0.62)
	view.Position = UDim2.fromScale(0.5, 0.04)
	view.AnchorPoint = Vector2.new(0.5, 0)
	view.Ambient = Color3.fromRGB(190, 190, 190)
	view.LightColor = Color3.fromRGB(255, 255, 255)
	view.Parent = parent

	local clone = model:Clone()
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			(d :: BasePart).Anchored = true
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	clone.Parent = view

	local camera = Instance.new("Camera")
	camera.FieldOfView = VIEW_FOV
	camera.Parent = view
	view.CurrentCamera = camera

	-- LA DISTANCE VIENT DE LA TAILLE DE L'OBJET, pas d'un chiffre pose a la main : un rateau et un seau n'ont pas
	-- la meme taille, et une distance fixe montrerait l'un en entier et l'autre en gros plan.
	local pivot, size = clone:GetBoundingBox()
	local reach = math.max(size.X, size.Y, size.Z) * VIEW_BACK
	local dir = CFrame.Angles(0, math.rad(VIEW_YAW), 0) * CFrame.Angles(math.rad(-VIEW_PITCH), 0, 0)
	camera.CFrame = CFrame.lookAt(pivot.Position + dir.LookVector * -reach, pivot.Position)
end

--- Fabrique une case pour `model`. `onTake` est appele avec son nom quand on clique.
local function makeSlot(model: Model, onTake: (string) -> (), parent: Instance)
	local slot = Instance.new("Frame")
	slot.Name = model.Name
	slot.Size = SLOT_SIZE
	slot.BackgroundColor3 = BG
	slot.BackgroundTransparency = BG_TRANSPARENCY + 0.2
	slot.BorderSizePixel = 0
	slot.Parent = parent
	corner(slot, 14)
	stroke(slot, 1.5, STROKE_TRANSPARENCY)

	preview(model, slot)

	local name = Instance.new("TextLabel")
	name.Name = "ToolName"
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(0.92, 0.14)
	name.Position = UDim2.fromScale(0.5, 0.66)
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Font = Enum.Font.GothamBold
	name.TextColor3 = TEXT
	name.TextScaled = true
	-- LE NOM DU MODELE, tel quel. Une table de jolis noms serait une SECONDE source a tenir d'accord avec la
	-- benne : le jour ou l'un des deux bouge, l'interface annonce un outil qui n'existe plus.
	name.Text = model.Name
	name.Parent = slot

	local take = Instance.new("TextButton")
	take.Name = "Take"
	take.Size = UDim2.fromScale(0.84, 0.17)
	take.Position = UDim2.fromScale(0.5, 0.83)
	take.AnchorPoint = Vector2.new(0.5, 0)
	take.BackgroundColor3 = TAKE
	take.BorderSizePixel = 0
	take.AutoButtonColor = false
	take.Font = Enum.Font.GothamBold
	take.TextColor3 = TEXT
	take.TextScaled = true
	take.Text = TAKE_TEXT
	take.Parent = slot
	corner(take, 8)

	-- LE SURVOL EST UN RETOUR, pas une decoration : sans lui, rien ne dit que la case est cliquable avant d'avoir
	-- clique. Sur tactile il ne sert a rien et ne coute rien -- le tap declenche directement.
	take.MouseEnter:Connect(function()
		take.BackgroundColor3 = TAKE_HOVER
	end)
	take.MouseLeave:Connect(function()
		take.BackgroundColor3 = TAKE
	end)
	take.Activated:Connect(function()
		onTake(model.Name)
	end)
end

local function build(): Frame
	local existing = bar
	if existing and existing.Parent then
		return existing
	end
	local holder = getGui()

	local frame = Instance.new("Frame")
	frame.Name = "Bar"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = HIDDEN_POS
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.fromOffset(0, 186)
	frame.BackgroundColor3 = BG
	frame.BackgroundTransparency = BG_TRANSPARENCY
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = holder
	corner(frame, 18)
	stroke(frame, 2, 0.45)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = TEXT
	title.TextTransparency = 0.25
	title.TextScaled = true
	title.Text = TITLE_TEXT
	title.Parent = frame

	local list = Instance.new("Frame")
	list.Name = "Slots"
	list.BackgroundTransparency = 1
	list.AutomaticSize = Enum.AutomaticSize.X
	list.Size = UDim2.new(0, 0, 1, -22)
	list.Position = UDim2.fromOffset(0, 22)
	list.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.Name
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.Parent = list

	bar, row = frame, list
	return frame
end

--- REMPLIT LA BARRE avec `models`, et rend le nombre de cases posees.
---
--- ON REFAIT TOUT A CHAQUE FOIS plutot que de retirer la case de l'outil sorti. La benne est la SOURCE : si elle
--- dit trois outils, la barre en montre trois. Retirer une case a la main serait un second etat a tenir d'accord
--- avec elle, et c'est exactement ainsi que deux verites finissent par se contredire.
function TruckToolsHandler.fill(models: { Model }, onTake: (string) -> ()): number
	build()
	local list = row
	if not list then
		return 0
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for _, model in models do
		makeSlot(model, onTake, list)
	end
	return #models
end

--- Montre ou cache la barre. Idempotent : appelee deux fois de suite, elle ne rejoue rien.
function TruckToolsHandler.setShown(on: boolean)
	if on == shown then
		return
	end
	shown = on
	local frame = bar
	if not frame then
		return
	end
	if slideTween then
		slideTween:Cancel()
	end
	if on then
		frame.Visible = true
	end
	local tween = TweenService:Create(frame, if on then SLIDE_IN else SLIDE_OUT, {
		Position = if on then BAR_POS else HIDDEN_POS,
	})
	slideTween = tween
	tween.Completed:Connect(function()
		-- ON NE CACHE QU'A LA FIN, et seulement si personne ne l'a rouverte entre-temps : la masquer tout de
		-- suite couperait le glissement en plein vol.
		if not shown and slideTween == tween then
			frame.Visible = false
		end
	end)
	tween:Play()
end

--- Detruit tout. Celui qui cree est celui qui nettoie, et il nettoie TOUT.
function TruckToolsHandler.destroy()
	if slideTween then
		slideTween:Cancel()
		slideTween = nil
	end
	local holder = gui
	if holder then
		holder:Destroy()
	end
	gui, bar, row, shown = nil, nil, nil, false
end

return TruckToolsHandler
