--!strict
-- LE MENU DES OUTILS, en bas a gauche. Un bouton rond ; on clique, une colonne de cases se deplie au-dessus.
--
-- REPLIE PAR DEFAUT, ET C'EST LE POINT. Le joueur n'a pas trois outils a choisir en permanence : il en a un en
-- main, et il en change de temps en temps. Une barre ouverte en continu occuperait un coin de l'ecran pour une
-- decision qu'on prend deux fois par chantier -- alors qu'un bouton dit "il y a des outils ici" en un dessin.
--
-- EN BAS A GAUCHE, loin de la barre du camion (en bas au centre) : les deux peuvent etre ouvertes en meme temps
-- devant la benne, et deux panneaux qui se chevauchent se cliquent l'un pour l'autre.
--
-- ELLE NE DECIDE RIEN. On lui donne la liste des outils possedes et celui qui est en main ; equiper, ranger, et
-- savoir ce qu'on possede est l'affaire du controller et du serveur.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ToolHudHandler = {}

local player = Players.LocalPlayer

-- ===== LA PLACE =====
local ROOT_POS = UDim2.fromScale(0.035, 0.93)
local BUTTON_SIZE = UDim2.fromOffset(72, 72)
local SLOT_SIZE = UDim2.fromOffset(64, 64)
local SLOT_GAP = 8
-- La colonne monte DEPUIS le bouton : chaque case est posee au-dessus de la precedente.
local FIRST_RISE = 84

-- ===== LES COULEURS =====
local BG = Color3.fromRGB(28, 40, 52)
local BG_TRANSPARENCY = 0.12
local WHITE = Color3.fromRGB(255, 255, 255)
-- LE VERT DU JEU pour l'outil EN MAIN : la meme couleur que les taches et le bouton du camion, parce que c'est la
-- meme idee -- ce qui est actif, ce qui avance.
local HELD = Color3.fromRGB(98, 206, 59)
local IDLE_STROKE = 0.7
local HELD_STROKE = 0

-- ===== LE MOUVEMENT =====
-- LES CASES SORTENT L'UNE APRES L'AUTRE, pas toutes ensemble : un decalage se lit comme un deploiement, alors
-- qu'un bloc qui apparait se lit comme une fenetre. Le retard est PAR CASE, donc trois outils mettent a peine
-- plus longtemps que deux.
local STAGGER = 0.04
local OPEN_TIME = 0.22
local CLOSE_TIME = 0.14
local OPEN_EASE = TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_EASE = TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- LE BOUTON TOURNE EN S'OUVRANT. Un quart de tour suffit a dire "c'est le meme bouton, dans l'autre sens".
local BUTTON_TURN = 45
-- Le dessin du bouton : une caisse a outils. En attendant le tien, c'est l'icone de la cisaille.
local BUTTON_ICON = "rbxassetid://96003986607540"

local gui: ScreenGui? = nil
local root: Frame? = nil
local toggleButton: ImageButton? = nil
local slots: { Frame } = {}
local open = false

local function getGui(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("ScreenGui")
	created.Name = "LeafiaToolHud"
	created.ResetOnSpawn = false
	created.IgnoreGuiInset = true
	created.ScreenInsets = Enum.ScreenInsets.None
	-- Sous la barre du camion : quand les deux sont la, c'est le camion qu'on vient d'ouvrir qui compte.
	created.DisplayOrder = 52
	created.Parent = player:WaitForChild("PlayerGui")
	gui = created
	return created
end

-- Le cast est OBLIGATOIRE : luau-lsp ne resout pas `Instance.new("UICorner")` vers `UICorner`.
local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.Parent = parent
	return s
end

--- Ferme ou ouvre la colonne. Les cases glissent depuis le bouton, en quinconce.
local function applyOpen()
	for index, slot in slots do
		local delay = if open then (index - 1) * STAGGER else 0
		local goal = if open
			then UDim2.fromOffset(0, -(FIRST_RISE + (index - 1) * (SLOT_SIZE.Y.Offset + SLOT_GAP)))
			else UDim2.fromOffset(0, 0)
		task.delay(delay, function()
			if not slot.Parent then
				return
			end
			TweenService:Create(slot, if open then OPEN_EASE else CLOSE_EASE, {
				Position = goal,
				-- ELLE DISPARAIT EN RENTRANT DANS LE BOUTON : la transparence et la taille suivent la position,
				-- sinon les cases s'empileraient visiblement sur lui avant de s'effacer.
				BackgroundTransparency = if open then BG_TRANSPARENCY else 1,
				Size = if open then SLOT_SIZE else UDim2.fromOffset(0, 0),
			}):Play()
			local image = slot:FindFirstChildWhichIsA("ImageLabel")
			if image then
				TweenService
					:Create(image, if open then OPEN_EASE else CLOSE_EASE, { ImageTransparency = if open then 0 else 1 })
					:Play()
			end
		end)
	end
	local button = toggleButton
	if button then
		TweenService:Create(button, OPEN_EASE, { Rotation = if open then BUTTON_TURN else 0 }):Play()
	end
end

local function build(onToggle: () -> ()): Frame
	local existing = root
	if existing and existing.Parent then
		return existing
	end
	local holder = getGui()

	local frame = Instance.new("Frame")
	frame.Name = "ToolHud"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = ROOT_POS
	frame.Size = BUTTON_SIZE
	frame.BackgroundTransparency = 1
	frame.Parent = holder

	local button = Instance.new("ImageButton")
	button.Name = "Toggle"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = BG
	button.BackgroundTransparency = BG_TRANSPARENCY
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Image = BUTTON_ICON
	button.ImageTransparency = 0.05
	-- `Fit` : un dessin etire n'est plus le dessin.
	button.ScaleType = Enum.ScaleType.Fit
	button.Parent = frame
	corner(button, 18)
	stroke(button, WHITE, 2, 0.5)
	button.Activated:Connect(onToggle)

	root, toggleButton = frame, button
	return frame
end

export type Entry = {
	-- Le nom du MODELE (ce que le joueur lit), et la cle d'equipement (ce que le serveur attend).
	label: string,
	tool: string,
	icon: string?,
	held: boolean,
}

--- REMPLIT LA COLONNE. `onPick` recoit la cle d'equipement de la case cliquee.
---
--- ON REFAIT LES CASES A CHAQUE FOIS. La liste des outils possedes et celui qui est en main viennent du monde :
--- corriger une case a la main serait un second etat a tenir d'accord avec lui.
function ToolHudHandler.fill(entries: { Entry }, onToggle: () -> (), onPick: (string) -> ())
	local frame = build(onToggle)
	for _, slot in slots do
		slot:Destroy()
	end
	table.clear(slots)

	for _, entry in entries do
		local slot = Instance.new("Frame")
		slot.Name = entry.label
		slot.AnchorPoint = Vector2.new(0, 1)
		-- ELLE NAIT SUR LE BOUTON, taille nulle : c'est `applyOpen` qui la fait monter et grandir. Posee a sa
		-- place finale, elle apparaitrait d'un coup a l'ouverture.
		slot.Position = UDim2.fromOffset(0, 0)
		slot.Size = UDim2.fromOffset(0, 0)
		slot.BackgroundColor3 = BG
		slot.BackgroundTransparency = 1
		slot.BorderSizePixel = 0
		slot.Parent = frame
		corner(slot, 14)
		-- LE CONTOUR DIT CE QUI EST EN MAIN : vert et plein pour l'outil tenu, blanc et discret pour les autres.
		-- Une couleur de FOND aurait mange le dessin de l'outil, qui est ce qu'on doit lire en premier.
		stroke(slot, if entry.held then HELD else WHITE, if entry.held then 3 else 2, if entry.held then HELD_STROKE else IDLE_STROKE)

		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.BackgroundTransparency = 1
		image.Image = entry.icon or ""
		image.ImageTransparency = 1
		image.ScaleType = Enum.ScaleType.Fit
		image.Size = UDim2.fromScale(0.78, 0.78)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Parent = slot

		-- SANS DESSIN, ON ECRIT LE NOM. Une case vide ne dit rien, et le joueur cliquerait au hasard.
		if not entry.icon then
			local name = Instance.new("TextLabel")
			name.Name = "Label"
			name.BackgroundTransparency = 1
			name.Size = UDim2.fromScale(0.9, 0.4)
			name.Position = UDim2.fromScale(0.5, 0.5)
			name.AnchorPoint = Vector2.new(0.5, 0.5)
			name.Font = Enum.Font.GothamBold
			name.TextColor3 = WHITE
			name.TextScaled = true
			name.Text = entry.label
			name.Parent = slot
		end

		local hit = Instance.new("TextButton")
		hit.Name = "Pick"
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.Parent = slot
		hit.Activated:Connect(function()
			onPick(entry.tool)
		end)

		table.insert(slots, slot)
	end
	applyOpen()
end

--- Ouvre ou ferme la colonne. Rend l'etat obtenu.
function ToolHudHandler.setOpen(on: boolean): boolean
	if on == open then
		return open
	end
	open = on
	applyOpen()
	return open
end

function ToolHudHandler.isOpen(): boolean
	return open
end

--- Montre ou cache le HUD entier : il n'a rien a dire tant qu'on ne possede aucun outil.
function ToolHudHandler.setVisible(on: boolean)
	local frame = root
	if frame then
		frame.Visible = on
	end
	if not on then
		open = false
	end
end

--- Detruit tout. Celui qui cree est celui qui nettoie, et il nettoie TOUT.
function ToolHudHandler.destroy()
	local holder = gui
	if holder then
		holder:Destroy()
	end
	gui, root, toggleButton, open = nil, nil, nil, false
	table.clear(slots)
end

return ToolHudHandler
