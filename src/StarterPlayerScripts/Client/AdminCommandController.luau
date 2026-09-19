--!strict
-- Console admin (client). UI codee : une TextBox, un bouton EXECUTE, un PREDICTEUR (liste des commandes filtrees
-- pendant qu'on tape) et une zone de resultat. Ouvre / ferme avec F2, ou, sur ecran tactile, avec une roue dentee
-- rangee dans la barre du haut. Construite ET active SEULEMENT pour les admins (confort) ; le serveur reste
-- l'autorite (il re-verifie l'acces et n'execute que ce qu'il decide).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local TaskConfigs = require(ReplicatedStorage.Modules.Configs.TaskConfigs)
local TaskBannerHandler = require(ReplicatedStorage.Modules.UI.Task.TaskBannerHandler)
local Toast = require(ReplicatedStorage.Modules.UI.Core.Toast)
local SideNotificationHandler = require(ReplicatedStorage.Modules.UI.Notification.SideNotificationHandler)
local AdminCommandConfigs = require(ReplicatedStorage.Modules.Configs.AdminCommandConfigs)

local AdminCommandController = {}

local player = Players.LocalPlayer

-- Couleurs console (sombre, lisible).
local PANEL_BG = Color3.fromRGB(24, 26, 30)
local INPUT_BG = Color3.fromRGB(38, 41, 47)
local ROW_BG = Color3.fromRGB(32, 35, 40)
local ROW_HOVER = Color3.fromRGB(48, 52, 60)
local ACCENT = Color3.fromRGB(120, 194, 108) -- vert Leafia
local TEXT_MAIN = Color3.fromRGB(235, 238, 240)
local TEXT_DIM = Color3.fromRGB(150, 156, 164)
local FONT = Enum.Font.Code -- monospace : c'est une console

local TOGGLE_KEY = Enum.KeyCode.F2
local MAX_SUGGESTIONS = 8
-- Largeur de la console : 94 % de l'ecran, plafonnee. Un telephone en paysage n'a pas toujours 560 px a donner.
local PANEL_MAX_WIDTH = 560

-- BOUTON TACTILE. Sans clavier, pas de F2, donc pas de console. La roue se range dans la barre du haut de Roblox, juste
-- apres ses boutons (`GuiService.TopbarInset` = la place que Roblox laisse libre pour ca) : elle ne recouvre rien du
-- jeu et prend la hauteur des boutons voisins, quel que soit l'ecran. `TouchEnabled` SEUL : c'est une capacite, vraie
-- aussi dans l'emulateur de Studio (voir le journal de CLAUDE.md).
local IS_TOUCH = UserInputService.TouchEnabled
local TOUCH_ICON = "rbxassetid://72145892854726"
-- Style des cartes du jeu (le menu des outils) : fond blanc, contour gris clair, icone sombre. Console ouverte : le
-- FOND passe au vert, l'icone reste sombre -- lisible quelle que soit la couleur de l'image d'origine.
local BTN_BG = Color3.fromRGB(255, 255, 255)
local BTN_STROKE = Color3.fromRGB(206, 214, 224)
local BTN_ICON = Color3.fromRGB(32, 38, 46)
local BTN_ON = Color3.fromRGB(98, 206, 59)
local BTN_ON_STROKE = Color3.fromRGB(70, 160, 40)
local BTN_MIN, BTN_MAX = 30, 44 -- taille en px, bornee : la barre du haut change de hauteur selon l'appareil
local BTN_GAP = 6 -- ecart avec le dernier bouton de Roblox

-- Etat, cree paresseusement au 1er toggle (pas au boot : inutile tant qu'on n'ouvre pas la console).
local gui: ScreenGui? = nil
local inputBox: TextBox? = nil
local predictor: Frame? = nil
local output: TextLabel? = nil
local remote: RemoteFunction? = nil
local touchButton: ImageButton? = nil
local touchStroke: UIStroke? = nil

local function create(className: string, props: { [string]: any }): Instance
	local inst = Instance.new(className)
	local children = props.Children :: { Instance }?
	props.Children = nil
	for k, v in props do
		(inst :: any)[k] = v
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	return inst
end

local function corner(r: number): UICorner
	return create("UICorner", { CornerRadius = UDim.new(0, r) }) :: UICorner
end

local function clearRows(pred: Frame)
	for _, child in pred:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function clearPredictor()
	local pred = predictor
	if not pred then
		return
	end
	clearRows(pred)
	pred.Visible = false
end

local function fillInput(text: string)
	local box = inputBox
	if not box then
		return
	end
	box.Text = text
	box.CursorPosition = #text + 1
	box:CaptureFocus()
end

-- Filtre les commandes par le 1er mot tape et affiche les correspondances. Des qu'il y a un espace (commande choisie,
-- on tape les arguments) on cache le predicteur : il ne predit QUE le nom de commande.
local function refreshPredictor()
	if not (predictor and inputBox) then
		return
	end
	local pred = predictor :: Frame
	local box = inputBox :: TextBox
	if box.Text:find("%s") then
		clearPredictor()
		return
	end
	clearRows(pred)
	local q = box.Text:lower()
	local shown = 0
	for _, cmd in ipairs(AdminCommandConfigs.COMMANDS) do
		if q == "" or cmd.name:sub(1, #q) == q then
			shown += 1
			if shown > MAX_SUGGESTIONS then
				break
			end
			local cmdName = cmd.name
			local row = create("TextButton", {
				Name = "Suggest_" .. cmdName,
				BackgroundColor3 = ROW_BG,
				Size = UDim2.new(1, 0, 0, 26),
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = shown,
				Children = {
					corner(4),
					create("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.new(0.42, -8, 1, 0),
						Position = UDim2.fromOffset(8, 0),
						Font = FONT,
						TextSize = 14,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextColor3 = ACCENT,
						Text = cmd.usage,
					}),
					create("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.new(0.58, -8, 1, 0),
						Position = UDim2.fromScale(0.42, 0),
						Font = FONT,
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						TextColor3 = TEXT_DIM,
						Text = cmd.description,
					}),
				},
			}) :: TextButton
			row.MouseEnter:Connect(function()
				row.BackgroundColor3 = ROW_HOVER
			end)
			row.MouseLeave:Connect(function()
				row.BackgroundColor3 = ROW_BG
			end)
			-- Clic sur une suggestion : remplit la box avec "nom " et redonne le focus pour taper les arguments.
			row.Activated:Connect(function()
				fillInput(cmdName .. " ")
				clearPredictor()
			end)
			row.Parent = pred
		end
	end
	pred.Visible = shown > 0
end

local function execute()
	if not (inputBox and output) then
		return
	end
	local box = inputBox :: TextBox
	local out = output :: TextLabel
	local text = box.Text
	if text:gsub("%s", "") == "" then
		return
	end
	clearPredictor()

	-- LES COMMANDES PUREMENT VISUELLES NE VONT PAS AU SERVEUR. Rejouer une animation d'interface ne quitte pas
	-- cet ecran : l'envoyer demanderait un remote et une reponse pour un effet que le serveur ne voit meme pas.
	-- Traitees AVANT lui, sinon il repondrait "commande inconnue" a une commande qui a fait son travail.
	local word = text:lower():match("^(%S+)")
	if word == "notif" then
		-- LES DEUX SORTES, et la laterale en deux versions (simple, puis avec un gain) : tout le dessin d'un coup.
		Toast.show("Warning", "This is a test notification.")
		SideNotificationHandler.spawn({
			kind = "Warning",
			title = "Test",
			description = "This is a side notification.",
			duration = 8,
		})
		task.delay(0.6, function()
			SideNotificationHandler.spawn({
				kind = "Info",
				title = "Level up",
				description = "You reached a new level!",
				earn = "+ 1 SKILL POINT",
				duration = 8,
			})
		end)
		out.Text = "Notifications de test affichees."
		out.Visible = true
		box.Text = ""
		box:CaptureFocus()
		return
	end
	if word == "tasks" then
		if text:lower():match("%soff%s*$") then
			TaskBannerHandler.hide()
			out.Text = "Bandeau d'objectifs range."
		else
			TaskBannerHandler.show(TaskConfigs.DEMO_TASKS)
			out.Text = `Bandeau rejoue : {#TaskConfigs.DEMO_TASKS} taches de demonstration.`
		end
		out.Visible = true
		box.Text = ""
		box:CaptureFocus()
		return
	end

	local r = remote
	if not r then
		out.Text = "Remote admin indisponible."
		out.Visible = true
		return
	end
	local ok, result = pcall(function()
		return (r :: RemoteFunction):InvokeServer(text)
	end)
	out.Text = if ok then tostring(result) else "Echec de l'appel serveur."
	out.Visible = true
	box.Text = ""
	box:CaptureFocus()
end

local function build()
	local sg = create("ScreenGui", {
		Name = "LeafiaAdminUI",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 100,
		Enabled = false,
	}) :: ScreenGui

	-- Sur tactile, SOUS la barre du haut : a 6 % de l'ecran, la console recouvrait la roue qui sert a la fermer.
	local top = if IS_TOUCH then UDim2.new(0.5, 0, 0, GuiService.TopbarInset.Max.Y + 8) else UDim2.fromScale(0.5, 0.06)
	local panel = create("Frame", {
		Name = "Panel",
		BackgroundColor3 = PANEL_BG,
		BackgroundTransparency = 0.05,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = top,
		Size = UDim2.fromScale(0.94, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Children = {
			corner(10),
			create("UISizeConstraint", { MaxSize = Vector2.new(PANEL_MAX_WIDTH, math.huge) }),
			create("UIStroke", { Color = Color3.fromRGB(70, 76, 84), Thickness = 1, Transparency = 0.3 }),
			create("UIPadding", {
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 12),
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
			}),
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	}) :: Frame

	create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Font = FONT,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = TEXT_DIM,
		Text = if IS_TOUCH then "ADMIN CONSOLE" else "ADMIN CONSOLE   -   F2 pour fermer",
		LayoutOrder = 1,
	}).Parent = panel

	local inputRow = create("Frame", {
		Name = "InputRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 2,
	}) :: Frame

	local box = create("TextBox", {
		Name = "Input",
		BackgroundColor3 = INPUT_BG,
		Size = UDim2.new(1, -96, 1, 0),
		Font = FONT,
		TextSize = 16,
		TextColor3 = TEXT_MAIN,
		TextXAlignment = Enum.TextXAlignment.Left,
		PlaceholderText = "Tape une commande...  (help)",
		PlaceholderColor3 = TEXT_DIM,
		Text = "",
		ClearTextOnFocus = false,
		Children = {
			corner(6),
			create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		},
	}) :: TextBox
	box.Parent = inputRow

	local runBtn = create("TextButton", {
		Name = "Execute",
		BackgroundColor3 = ACCENT,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 88, 1, 0),
		Font = FONT,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(20, 32, 18),
		Text = "EXECUTE",
		AutoButtonColor = true,
		Children = { corner(6) },
	}) :: TextButton
	runBtn.Parent = inputRow
	inputRow.Parent = panel

	local pred = create("Frame", {
		Name = "Predictor",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = 3,
		Children = {
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 3),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	}) :: Frame
	pred.Parent = panel

	local out = create("TextLabel", {
		Name = "Output",
		BackgroundColor3 = INPUT_BG,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT,
		TextSize = 14,
		TextColor3 = TEXT_DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = "",
		Visible = false,
		LayoutOrder = 4,
		Children = {
			corner(6),
			create("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
		},
	}) :: TextLabel
	out.Parent = panel

	panel.Parent = sg
	sg.Parent = player:WaitForChild("PlayerGui")

	gui = sg
	inputBox = box
	predictor = pred
	output = out

	box:GetPropertyChangedSignal("Text"):Connect(refreshPredictor)
	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			execute()
		end
	end)
	runBtn.Activated:Connect(execute)
end

-- La roue dit si la console est ouverte : fond vert tant qu'elle l'est.
local function refreshTouchButton(open: boolean)
	local button, stroke = touchButton, touchStroke
	if button and stroke then
		button.BackgroundColor3 = if open then BTN_ON else BTN_BG
		stroke.Color = if open then BTN_ON_STROKE else BTN_STROKE
	end
end

local function toggle()
	if not gui then
		build()
	end
	local g = gui
	if not g then
		return
	end
	g = g :: ScreenGui
	g.Enabled = not g.Enabled
	refreshTouchButton(g.Enabled)
	if g.Enabled then
		refreshPredictor()
		if inputBox then
			(inputBox :: TextBox):CaptureFocus()
		end
	else
		clearPredictor()
	end
end

-- LA ROUE DENTEE (ecran tactile). Sa place se MESURE a chaque changement de la barre du haut ou de l'ecran (rotation,
-- tablette), jamais une fois pour toutes. Position relative a l'ORIGINE REELLE du ScreenGui : sur mobile, meme en
-- `ScreenInsets.None`, elle ne tombe pas forcement sur le coin de l'ecran (meme piege que WorldAnchor).
local function buildTouchButton()
	local playerGui = player:WaitForChild("PlayerGui", 30)
	if not playerGui then
		return
	end
	local sg = create("ScreenGui", {
		Name = "LeafiaAdminButton",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 100,
	}) :: ScreenGui
	local button = create("ImageButton", {
		Name = "AdminButton",
		BackgroundColor3 = BTN_BG,
		BackgroundTransparency = 0.05,
		AutoButtonColor = false,
		Image = "",
		Size = UDim2.fromOffset(BTN_MAX, BTN_MAX),
		Children = {
			create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			create("ImageLabel", {
				Name = "Icon",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.62, 0.62),
				Image = TOUCH_ICON,
				ImageColor3 = BTN_ICON,
				ScaleType = Enum.ScaleType.Fit,
			}),
		},
	}) :: ImageButton
	local stroke = create("UIStroke", {
		Color = BTN_STROKE,
		Thickness = 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
	stroke.Parent = button
	button.Parent = sg
	sg.Parent = playerGui
	touchButton = button
	touchStroke = stroke

	local function place()
		local inset = GuiService.TopbarInset
		local origin = sg.AbsolutePosition
		local size, x, y
		if inset.Height > 0 then
			size = math.clamp(inset.Height - 8, BTN_MIN, BTN_MAX)
			x = inset.Min.X + BTN_GAP
			y = inset.Min.Y + (inset.Height - size) / 2
		else
			-- Barre du haut absente (masquee par une scene) : coin haut gauche, a distance du bord.
			size, x, y = BTN_MAX, 12, 12
		end
		button.Size = UDim2.fromOffset(size, size)
		button.Position = UDim2.fromOffset(x - origin.X, y - origin.Y)
	end
	place()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)
	sg:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
	button.Activated:Connect(toggle)
end

function AdminCommandController.init()
	-- Pas admin : on ne construit rien et on n'ecoute meme pas la touche.
	if not AdminCommandConfigs.isAdmin(player) then
		return
	end
	-- Remote en tache de fond : getRemote fait un WaitForChild interne (jusqu'a 10 s), il ne doit pas geler le boot.
	task.spawn(function()
		local r = RemoteSetup.getRemote("AdminCommand", "Admin")
		if r and r:IsA("RemoteFunction") then
			remote = r
		end
	end)
	UserInputService.InputBegan:Connect(function(inputObj: InputObject, _gameProcessed: boolean)
		-- F2 meme si une UI a "consomme" l'evenement, sinon impossible de fermer en tapant dans la box.
		if inputObj.KeyCode == TOGGLE_KEY then
			toggle()
		end
	end)
	if IS_TOUCH then
		task.spawn(buildTouchButton) -- attend PlayerGui : hors du boot
	end
end

return AdminCommandController
