--!strict
-- BOUTONS D'ACTION TACTILES : des pilules blanches, en colonne, au-dessus du bouton de saut. MOBILE UNIQUEMENT.
--
-- ILS REMPLACENT LES BOUTONS DE `ContextActionService` (`createTouchButton = true`) : des ronds gris plats, au texte
-- illisible, poses par Roblox ou il veut et qui s'empilaient pres du bouton de saut. Ils "ne ressemblaient a rien"
-- sur telephone, et plusieurs doublaient une pilule d'interaction qui se tape deja.
--
-- LA REGLE D'EMPLOI : un bouton ici SEULEMENT quand l'action n'a pas de pilule. Prendre un objet se fait en tapant sa
-- pilule ; le reposer, changer de vue, tirer la corde n'ont rien a taper -- c'est pour eux.
--
-- Les features gardent leur `BindAction` pour le CLAVIER, avec `false` en troisieme argument, et declarent leur
-- bouton ici. Sur un appareil sans ecran tactile, `show` ne fait rien.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local TouchButtons = {}

local player = Players.LocalPlayer

-- `TouchEnabled` SEUL, jamais `and not KeyboardEnabled` : c'est une CAPACITE, vraie sur telephone ET dans l'emulateur
-- de Studio (qui garde le clavier du PC). Deja paye au journal.
local IS_TOUCH = UserInputService.TouchEnabled

-- ===== STYLE : LE BLANC DE L'INTERFACE =====
-- Les memes valeurs que la boite de dialogue et le menu des outils : fond presque blanc, texte fonce, liseré gris
-- clair. Un bouton d'une autre famille de couleurs se lirait comme un element etranger au jeu.
local BG_COLOR = Color3.fromRGB(248, 250, 248)
local TEXT_COLOR = Color3.fromRGB(44, 48, 56)
local STROKE_COLOR = Color3.fromRGB(214, 218, 224)
local STROKE_THICKNESS = 1.5
local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)

-- ===== TAILLES, EN FRACTION DE LA HAUTEUR DE L'ECRAN =====
-- La hauteur et pas des pixels : un telephone en paysage n'a que quelques centaines d'unites de haut, une tablette
-- bien plus. Des pixels fixes seraient enormes sur l'un et minuscules sur l'autre.
local BUTTON_W = 0.26
local BUTTON_H = 0.09
local GAP = 0.02
-- La hauteur de la colonne. Elle n'a pas de fond : c'est seulement la place qu'on reserve au-dessus de son bas.
local STACK_H = 0.5

-- ===== OU =====
-- COLONNE ANCREE EN BAS A DROITE, son bas pose AU-DESSUS du bouton de saut de Roblox (qui occupe environ le quart bas
-- de l'ecran, cote droit). Tout en FRACTION D'ECRAN : aucune position de doigt ou de bouton a convertir, donc aucun
-- decalage de barre a deviner (deja paye sur le joystick mobile).
local STACK_RIGHT = 0.02 -- marge droite, en fraction de la LARGEUR
local STACK_BOTTOM = 0.3 -- distance entre le bas de l'ecran et le bas de la colonne, en fraction de la HAUTEUR

-- ===== L'APPUI =====
-- Il RENTRE un peu sous le doigt : sans retour visuel, on ne sait pas si l'appui a pris.
local PRESS_SCALE = 0.9
local PRESS_TIME = 0.08

type Entry = {
	button: TextButton,
	scale: UIScale,
	onPress: (boolean) -> (),
	held: InputObject?,
}

local stack: Frame? = nil
local entries: { [string]: Entry } = {}
local order = 0

local function pressVisual(entry: Entry, down: boolean)
	TweenService:Create(entry.scale, TweenInfo.new(PRESS_TIME), { Scale = if down then PRESS_SCALE else 1 }):Play()
end

local function release(entry: Entry)
	if not entry.held then
		return
	end
	entry.held = nil
	pressVisual(entry, false)
	entry.onPress(false)
end

--- La colonne, creee a la premiere demande. Rend nil tant que la PlayerGui n'existe pas : on ne l'ATTEND pas, parce
--- que `show` est appele depuis des boucles par image -- un `WaitForChild` y gelerait la boucle entiere.
local function ensure(): Frame?
	local existing = stack
	if existing and existing.Parent then
		return existing
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end

	local sg = Instance.new("ScreenGui")
	sg.Name = "LeafiaTouchButtons"
	sg.ResetOnSpawn = false -- survit aux respawns : les features ne redeclarent pas leurs boutons a chaque mort
	sg.DisplayOrder = 5
	-- Pas de slime automatique : il fait bouger le bouton sous le doigt et se bat avec l'enfoncement ci-dessous.
	sg:SetAttribute("LeafiaNoSlime", true)
	sg.Parent = playerGui

	local column = Instance.new("Frame")
	column.Name = "Stack"
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(1, 1)
	column.Position = UDim2.fromScale(1 - STACK_RIGHT, 1 - STACK_BOTTOM)
	-- LES DEUX COTES SUR LA HAUTEUR : la colonne garde sa forme quel que soit le format d'ecran.
	column.SizeConstraint = Enum.SizeConstraint.RelativeYY
	column.Size = UDim2.fromScale(BUTTON_W, STACK_H)
	column.Parent = sg

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(GAP / STACK_H, 0)
	layout.Parent = column

	stack = column
	return column
end

--- Montre (ou met a jour) le bouton `id`. `onPress(true)` a l'appui, `onPress(false)` au relachement : une action
--- ponctuelle ignore le second, une action MAINTENUE (voir l'herbe a tondre) s'en sert pour s'eteindre.
---
--- Idempotent : l'appeler a chaque image ne recree rien. Le dernier bouton montre se pose AU-DESSUS des autres.
function TouchButtons.show(id: string, label: string, onPress: (boolean) -> ())
	if not IS_TOUCH then
		return
	end
	local existing = entries[id]
	if existing then
		existing.onPress = onPress
		if existing.button.Text ~= label then
			existing.button.Text = label
		end
		return
	end
	local column = ensure()
	if not column then
		return
	end

	local button = Instance.new("TextButton")
	button.Name = id
	button.AutoButtonColor = false
	button.BackgroundColor3 = BG_COLOR
	button.BorderSizePixel = 0
	button.Size = UDim2.fromScale(1, BUTTON_H / STACK_H)
	button.Text = label
	button.TextColor3 = TEXT_COLOR
	button.FontFace = FONT
	button.TextScaled = true
	-- PLUS RECENT = PLUS HAUT. Les boutons deja la ne bougent pas quand un nouveau arrive : le pouce les retrouve la
	-- ou il les a laisses.
	order += 1
	button.LayoutOrder = -order

	local corner = Instance.new("UICorner") :: UICorner
	corner.CornerRadius = UDim.new(1, 0) -- pilule : les bouts entierement arrondis
	corner.Parent = button
	local stroke = Instance.new("UIStroke") :: UIStroke
	stroke.Color = STROKE_COLOR
	stroke.Thickness = STROKE_THICKNESS
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.26, 0)
	pad.PaddingBottom = UDim.new(0.26, 0)
	pad.PaddingLeft = UDim.new(0.12, 0)
	pad.PaddingRight = UDim.new(0.12, 0)
	pad.Parent = button
	local scale = Instance.new("UIScale")
	scale.Parent = button

	local entry: Entry = { button = button, scale = scale, onPress = onPress, held = nil }
	entries[id] = entry

	button.InputBegan:Connect(function(input: InputObject)
		-- `Begin` SEULEMENT : `InputBegan` recoit aussi les doigts qui ont commence AILLEURS et glissent dessus -- le
		-- pouce qui tourne la camera declencherait l'action en passant. Deja paye sur le joystick.
		if input.UserInputState ~= Enum.UserInputState.Begin or entry.held then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		entry.held = input
		pressVisual(entry, true)
		entry.onPress(true)
	end)

	button.Parent = column
end

--- Retire le bouton `id`. S'il etait maintenu, l'action recoit son relachement : une vue qu'on tient ne reste pas
--- allumee parce que son bouton a disparu sous le doigt.
function TouchButtons.hide(id: string)
	local entry = entries[id]
	if not entry then
		return
	end
	entries[id] = nil
	release(entry)
	entry.button:Destroy()
end

-- LE RELACHEMENT SE LIT SUR LE DOIGT, pas sur le bouton : un doigt qui glisse hors du bouton avant de se lever ne
-- declenche jamais `InputEnded` sur lui, et l'action resterait maintenue. `TouchEnded` est le seul signal fiable pour
-- un toucher commence sur un element (journal) ; `InputEnded` couvre la souris de l'emulateur.
if IS_TOUCH then
	local function onEnded(input: InputObject)
		for _, entry in entries do
			if entry.held == input then
				release(entry)
			end
		end
	end
	UserInputService.TouchEnded:Connect(function(touch: InputObject)
		onEnded(touch)
	end)
	UserInputService.InputEnded:Connect(onEnded)
	-- LE MENU ROBLOX VOLE LE DOIGT : son toucher ne se termine alors jamais. On relache tout en l'ouvrant.
	GuiService.MenuOpened:Connect(function()
		for _, entry in entries do
			release(entry)
		end
	end)
end

return TouchButtons
