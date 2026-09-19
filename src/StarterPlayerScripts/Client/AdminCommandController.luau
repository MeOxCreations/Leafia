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
local CustomKeyboard = require(ReplicatedStorage.Modules.UI.Core.CustomKeyboard)

local AdminCommandController = {}

local player = Players.LocalPlayer

-- LE STYLE DES CARTES DU JEU (menu des outils, camion) : fond blanc, contour gris clair, texte sombre, vert Leafia pour
-- ce qui agit. Une console sombre en police de terminal jurait au milieu du reste de l'interface.
local PANEL_BG = Color3.fromRGB(255, 255, 255)
local PANEL_STROKE = Color3.fromRGB(206, 214, 224)
local WELL = Color3.fromRGB(241, 244, 248) -- le creux : saisie, suggestions, resultat
local ROW_HOVER = Color3.fromRGB(230, 236, 243)
local ACCENT = Color3.fromRGB(98, 206, 59) -- vert Leafia : ce qui agit
local ACCENT_TEXT = Color3.fromRGB(70, 160, 40) -- le meme vert, fonce pour rester lisible en texte sur du blanc
local TEXT_MAIN = Color3.fromRGB(32, 38, 46)
local TEXT_DIM = Color3.fromRGB(128, 136, 146)
local FONT = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold

-- `TouchEnabled` SEUL : c'est une capacite, vraie aussi dans l'emulateur de Studio (voir le journal de CLAUDE.md).
local IS_TOUCH = UserInputService.TouchEnabled
-- SUR TELEPHONE, C'EST LA HAUTEUR QUI MANQUE : un ecran en paysage fait ~360 points, et le clavier en prend la
-- moitie. La console tactile est donc COMPACTE -- texte plus petit, suggestions en pastilles sur UNE ligne qui defile,
-- resultat dans une zone de hauteur fixe qui defile. La version PC garde sa liste verticale avec les descriptions.
-- (Premiere version tactile : texte a 17 et huit lignes de suggestions, la console sortait par le bas de l'ecran.)
local TEXT_SIZE = if IS_TOUCH then 14 else 15
local TITLE_H = 24
local INPUT_H = 34
local ROW_H = 26 -- ligne de suggestion (PC)
local CHIP_H = 28 -- pastille de suggestion (tactile)
local OUTPUT_H = 90 -- zone de resultat (tactile), elle defile au-dela
local PAD = if IS_TOUCH then 10 else 14
local GAP = if IS_TOUCH then 6 else 8

local TOGGLE_KEY = Enum.KeyCode.F2
local MAX_SUGGESTIONS = 8 -- PC seulement : sur tactile la ligne de pastilles defile, on les montre toutes
-- Largeur de la console : 94 % de l'ecran, plafonnee.
local PANEL_MAX_WIDTH = if IS_TOUCH then 460 else 560

-- CLAVIER DU JEU (tactile) : le clavier du telephone recouvrait la moitie de l'ecran, console comprise. Chiffres en
-- tete (montants, niveaux), `_` en plus pour les noms de joueurs. Tout en minuscules : c'est ce qu'attendent les
-- commandes.
local KB_ROWS = { "1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm" }
local KEY_PRESS = Color3.fromRGB(211, 240, 197) -- vert tres pale tant qu'on appuie
local KB_MAX_WIDTH, KB_MAX_HEIGHT = 520, 300
local INPUT_MAX_LEN = 60

-- BOUTON TACTILE. Sans clavier, pas de F2, donc pas de console. Au depart, la roue se range dans la barre du haut de
-- Roblox, juste apres ses boutons (`GuiService.TopbarInset` = la place que Roblox laisse libre pour ca) : elle ne
-- recouvre rien du jeu et prend la hauteur des boutons voisins, quel que soit l'ecran. On peut ensuite la GLISSER
-- ailleurs au doigt ; un simple appui ouvre la console.
-- Console ouverte : le FOND passe au vert, l'icone reste sombre -- lisible quelle que soit la couleur de l'image.
local TOUCH_ICON = "rbxassetid://72145892854726"
local BTN_MIN, BTN_MAX = 30, 44 -- taille en px, bornee : la barre du haut change de hauteur selon l'appareil
local BTN_GAP = 6 -- ecart avec le dernier bouton de Roblox
-- Distance (px) au-dela de laquelle un appui devient un GLISSER. En dessous, c'est un appui : un doigt tremble toujours
-- un peu, et la console ne s'ouvrirait jamais si le moindre pixel comptait comme un deplacement.
local DRAG_THRESHOLD = 10
-- PLACE PAR DEFAUT DANS LE HUB : a droite du nom du plot ("STARTER PLOT") de l'ecran de choix, la ou le joueur l'a
-- demandee. Prise au PREMIER moment ou ce nom est a l'ecran, puis figee : elle ne suit pas le nom quand on change de
-- plot et ne disparait pas avec lui en entrant dans le jeu. Ailleurs (didacticiel), la barre du haut.
local ANCHOR_UI = "LoadSaveUI"
local ANCHOR_LABEL = "TitleNamePlot"
local ANCHOR_GAP = 12 -- px entre la fin du texte et la roue
local ANCHOR_WAIT = 30 -- s : au-dela, on renonce et la roue reste dans la barre du haut

-- Etat, cree paresseusement au 1er toggle (pas au boot : inutile tant qu'on n'ouvre pas la console).
local gui: ScreenGui? = nil
local inputBox: TextBox? = nil
local predictor: GuiObject? = nil
local output: TextLabel? = nil
-- Ce qui apparait avec le resultat : le texte lui-meme sur PC, sa zone qui defile sur tactile.
local outputBox: GuiObject? = nil
local closeButton: TextButton? = nil
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

local function clearRows(pred: Instance)
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

-- SUR TACTILE, JAMAIS LE FOCUS NATIF : il ouvrirait le clavier du telephone par-dessus celui du jeu.
local function focusInput(box: TextBox)
	if not IS_TOUCH then
		box:CaptureFocus()
	end
end

local function fillInput(text: string)
	local box = inputBox
	if not box then
		return
	end
	box.Text = text
	box.CursorPosition = #text + 1
	focusInput(box)
end

-- Filtre les commandes par le 1er mot tape et affiche les correspondances. Des qu'il y a un espace (commande choisie,
-- on tape les arguments) on cache le predicteur : il ne predit QUE le nom de commande.
local function refreshPredictor()
	if not (predictor and inputBox) then
		return
	end
	local pred = predictor :: GuiObject
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
			local cmdName = cmd.name
			if IS_TOUCH then
				-- PASTILLE : le nom seul, assez gros pour le doigt. La description ne tiendrait pas.
				local chip = create("TextButton", {
					Name = "Suggest_" .. cmdName,
					BackgroundColor3 = WELL,
					AutoButtonColor = false,
					Size = UDim2.fromScale(0, 1),
					AutomaticSize = Enum.AutomaticSize.X,
					Font = FONT_BOLD,
					TextSize = TEXT_SIZE,
					TextColor3 = ACCENT_TEXT,
					Text = cmdName,
					LayoutOrder = shown,
					Children = {
						create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
						create("UIStroke", {
							Color = PANEL_STROKE,
							Thickness = 1,
							ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						}),
						create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
					},
				}) :: TextButton
				chip.Activated:Connect(function()
					fillInput(cmdName .. " ")
					clearPredictor()
				end)
				chip.Parent = pred
				continue
			end
			if shown > MAX_SUGGESTIONS then
				break
			end
			local row = create("TextButton", {
				Name = "Suggest_" .. cmdName,
				BackgroundColor3 = WELL,
				Size = UDim2.new(1, 0, 0, ROW_H),
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = shown,
				Children = {
					corner(8),
					create("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.new(0.42, -10, 1, 0),
						Position = UDim2.fromOffset(10, 0),
						Font = FONT_BOLD,
						TextSize = TEXT_SIZE - 1,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						TextColor3 = ACCENT_TEXT,
						Text = cmd.usage,
					}),
					create("TextLabel", {
						BackgroundTransparency = 1,
						Size = UDim2.new(0.58, -10, 1, 0),
						Position = UDim2.fromScale(0.42, 0),
						Font = FONT,
						TextSize = TEXT_SIZE - 2,
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
				row.BackgroundColor3 = WELL
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

local function showOutput(text: string)
	local out, shownBox = output, outputBox
	if out then
		out.Text = text
	end
	if shownBox then
		shownBox.Visible = true
		if shownBox:IsA("ScrollingFrame") then
			shownBox.CanvasPosition = Vector2.zero -- un nouveau resultat se lit depuis le debut
		end
	end
end

local function execute()
	if not (inputBox and output) then
		return
	end
	local box = inputBox :: TextBox
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
		showOutput("Notifications de test affichees.")
		box.Text = ""
		focusInput(box)
		return
	end
	if word == "tasks" then
		if text:lower():match("%soff%s*$") then
			TaskBannerHandler.hide()
			showOutput("Bandeau d'objectifs range.")
		else
			TaskBannerHandler.show(TaskConfigs.DEMO_TASKS)
			showOutput(`Bandeau rejoue : {#TaskConfigs.DEMO_TASKS} taches de demonstration.`)
		end
		box.Text = ""
		focusInput(box)
		return
	end

	local r = remote
	if not r then
		showOutput("Remote admin indisponible.")
		return
	end
	local ok, result = pcall(function()
		return (r :: RemoteFunction):InvokeServer(text)
	end)
	showOutput(if ok then tostring(result) else "Echec de l'appel serveur.")
	box.Text = ""
	focusInput(box)
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
	-- PAS D'EFFET SLIME ici : les pastilles se dimensionnent seules dans une ligne, et le grossissement du slime les
	-- ferait bouger (meme raison que la barre de navigation).
	sg:SetAttribute("LeafiaNoSlime", true)

	-- Sur tactile : SOUS la barre du haut (sinon la console recouvrait la roue qui sert a la fermer), et a GAUCHE --
	-- le clavier du jeu prend la moitie droite. Cote a cote, les deux tiennent dans un telephone en paysage ; empiles,
	-- ils n'y tenaient pas.
	local topY = GuiService.TopbarInset.Max.Y + 8
	local panel = create("Frame", {
		Name = "Panel",
		BackgroundColor3 = PANEL_BG,
		AnchorPoint = if IS_TOUCH then Vector2.new(0, 0) else Vector2.new(0.5, 0),
		Position = if IS_TOUCH then UDim2.new(0.02, 0, 0, topY) else UDim2.fromScale(0.5, 0.06),
		Size = UDim2.fromScale(if IS_TOUCH then 0.47 else 0.94, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Children = {
			corner(14),
			create("UISizeConstraint", { MaxSize = Vector2.new(PANEL_MAX_WIDTH, math.huge) }),
			create("UIStroke", { Color = PANEL_STROKE, Thickness = 1.5 }),
			create("UIPadding", {
				PaddingTop = UDim.new(0, PAD),
				PaddingBottom = UDim.new(0, PAD),
				PaddingLeft = UDim.new(0, PAD),
				PaddingRight = UDim.new(0, PAD),
			}),
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		},
	}) :: Frame

	-- TITRE + FERMER. Une croix a portee de pouce : fermer ne doit pas obliger a retrouver la roue.
	local titleRow = create("Frame", {
		Name = "TitleRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, TITLE_H),
		LayoutOrder = 1,
	}) :: Frame
	create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(TITLE_H + 8), 1, 0),
		Font = FONT_BOLD,
		TextSize = TEXT_SIZE + 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = TEXT_MAIN,
		Text = if IS_TOUCH then "ADMIN CONSOLE" else "ADMIN CONSOLE   -   F2 pour fermer",
	}).Parent = titleRow
	local close = create("TextButton", {
		Name = "Close",
		BackgroundColor3 = WELL,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(TITLE_H, TITLE_H),
		AutoButtonColor = true,
		Font = FONT_BOLD,
		TextSize = TEXT_SIZE - 1,
		TextColor3 = TEXT_DIM,
		Text = "X",
		Children = { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) },
	}) :: TextButton
	close.Parent = titleRow
	titleRow.Parent = panel

	local inputRow = create("Frame", {
		Name = "InputRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, INPUT_H),
		LayoutOrder = 2,
	}) :: Frame

	local box = create("TextBox", {
		Name = "Input",
		BackgroundColor3 = WELL,
		Size = UDim2.new(1, -100, 1, 0),
		Font = FONT,
		TextSize = TEXT_SIZE,
		TextColor3 = TEXT_MAIN,
		TextXAlignment = Enum.TextXAlignment.Left,
		PlaceholderText = "Tape une commande...  (help)",
		PlaceholderColor3 = TEXT_DIM,
		Text = "",
		ClearTextOnFocus = false,
		TextEditable = not IS_TOUCH, -- tactile : lecture seule, on tape au clavier du jeu
		Children = {
			corner(8),
			create("UIStroke", { Color = PANEL_STROKE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		},
	}) :: TextBox
	box.Parent = inputRow

	local runBtn = create("TextButton", {
		Name = "Execute",
		BackgroundColor3 = ACCENT,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 92, 1, 0),
		Font = FONT_BOLD,
		TextSize = TEXT_SIZE - 1,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "EXECUTE",
		AutoButtonColor = true,
		Children = { corner(8) },
	}) :: TextButton
	runBtn.Parent = inputRow
	inputRow.Parent = panel

	-- SUGGESTIONS. PC : une liste verticale, nom + description. Tactile : une seule ligne de pastilles qui defile.
	local pred: GuiObject
	if IS_TOUCH then
		pred = create("ScrollingFrame", {
			Name = "Predictor",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, CHIP_H),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 0,
			Visible = false,
			LayoutOrder = 3,
			Children = {
				create("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 6),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
		}) :: ScrollingFrame
	else
		pred = create("Frame", {
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
	end
	pred.Parent = panel

	-- RESULTAT. PC : il grandit avec son texte. Tactile : zone de hauteur fixe qui defile -- la liste de `help`
	-- pousserait sinon la console hors de l'ecran.
	local out = create("TextLabel", {
		Name = "Output",
		BackgroundColor3 = WELL,
		BackgroundTransparency = if IS_TOUCH then 1 else 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = FONT,
		TextSize = TEXT_SIZE - 1,
		TextColor3 = TEXT_MAIN,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = "",
		Visible = IS_TOUCH, -- sur tactile, c'est sa zone qui apparait et disparait
		LayoutOrder = 4,
		Children = {
			corner(8),
			create("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}),
		},
	}) :: TextLabel
	local shownBox: GuiObject = out
	if IS_TOUCH then
		shownBox = create("ScrollingFrame", {
			Name = "OutputBox",
			BackgroundColor3 = WELL,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, OUTPUT_H),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = TEXT_DIM,
			Visible = false,
			LayoutOrder = 4,
			Children = { corner(8) },
		}) :: ScrollingFrame
		out.Parent = shownBox
	end
	shownBox.Parent = panel

	-- LE CLAVIER DU JEU (tactile), a droite de la console, de la barre du haut jusqu'en bas de l'ecran.
	if IS_TOUCH then
		local keyboard = create("Frame", {
			Name = "Keyboard",
			BackgroundColor3 = PANEL_BG,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(0.98, 0, 0, topY),
			Size = UDim2.new(0.49, 0, 1, -(topY + 12)),
			Children = {
				corner(14),
				create("UIStroke", { Color = PANEL_STROKE, Thickness = 1.5 }),
				create("UISizeConstraint", { MaxSize = Vector2.new(KB_MAX_WIDTH, KB_MAX_HEIGHT) }),
				create("UIPadding", {
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
				}),
				create("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0.025, 0),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
		}) :: Frame
		CustomKeyboard.fill(keyboard, {
			rows = KB_ROWS,
			keyWidth = 0.088,
			rowHeight = 0.17,
			extraKeys = { "_" },
			font = Font.fromEnum(FONT_BOLD),
			zIndex = 2,
			keyColor = WELL,
			specialColor = ROW_HOVER,
			textColor = TEXT_MAIN,
			pressColor = KEY_PRESS,
			confirmColor = ACCENT,
			confirmTextColor = Color3.new(1, 1, 1),
			onChar = function(c: string)
				if #box.Text < INPUT_MAX_LEN then
					box.Text ..= c
				end
			end,
			onBackspace = function()
				box.Text = box.Text:sub(1, -2)
			end,
			onConfirm = execute,
		})
		keyboard.Parent = sg
	end

	panel.Parent = sg
	sg.Parent = player:WaitForChild("PlayerGui")

	gui = sg
	inputBox = box
	predictor = pred
	output = out
	outputBox = shownBox
	closeButton = close

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
		button.BackgroundColor3 = if open then ACCENT else PANEL_BG
		stroke.Color = if open then ACCENT_TEXT else PANEL_STROKE
	end
end

local function toggle()
	if not gui then
		build()
		local close = closeButton
		if close then
			close.Activated:Connect(toggle)
		end
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
			focusInput(inputBox :: TextBox)
		end
	else
		clearPredictor()
	end
end

-- LA ROUE DENTEE (ecran tactile). Sa place se MESURE a chaque changement de la barre du haut ou de l'ecran (rotation,
-- tablette), jamais une fois pour toutes. Position relative a l'ORIGINE REELLE du ScreenGui : sur mobile, meme en
-- `ScreenInsets.None`, elle ne tombe pas forcement sur le coin de l'ecran (meme piege que WorldAnchor).
-- Une fois POSEE -- glissee a la main, ou calee a cote du nom du plot -- elle reste la (pour la session : rien n'est
-- sauvegarde), seulement ramenee dans l'ecran si celui-ci change de taille.
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
		BackgroundColor3 = PANEL_BG,
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
				ImageColor3 = TEXT_MAIN,
				ScaleType = Enum.ScaleType.Fit,
			}),
		},
	}) :: ImageButton
	local stroke = create("UIStroke", {
		Color = PANEL_STROKE,
		Thickness = 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
	stroke.Parent = button
	button.Parent = sg
	sg.Parent = playerGui
	touchButton = button
	touchStroke = stroke

	-- Vrai des que la place est decidee (glisser, ou nom du plot) : la barre du haut ne la deplace plus.
	local pinned = false

	local function clampToScreen(x: number, y: number, size: number): (number, number)
		local area = sg.AbsoluteSize
		return math.clamp(x, 0, math.max(area.X - size, 0)), math.clamp(y, 0, math.max(area.Y - size, 0))
	end

	local function place()
		local inset = GuiService.TopbarInset
		local size = if inset.Height > 0 then math.clamp(inset.Height - 8, BTN_MIN, BTN_MAX) else BTN_MAX
		button.Size = UDim2.fromOffset(size, size)
		local x, y
		if pinned then
			x, y = button.Position.X.Offset, button.Position.Y.Offset
		elseif inset.Height > 0 then
			local origin = sg.AbsolutePosition
			x = inset.Min.X + BTN_GAP - origin.X
			y = inset.Min.Y + (inset.Height - size) / 2 - origin.Y
		else
			-- Barre du haut absente (masquee par une scene) : coin haut gauche, a distance du bord.
			x, y = 12, 12
		end
		x, y = clampToScreen(x, y, size)
		button.Position = UDim2.fromOffset(x, y)
	end
	place()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)
	sg:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
	sg:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)

	-- LA FIN DU TEXTE du nom du plot, pas le bord du label : le label peut etre bien plus large que son texte, et la
	-- roue se poserait loin du mot. Les deux positions sont dans le meme repere (`AbsolutePosition`), on retranche
	-- l'origine de notre ScreenGui, comme pour la barre du haut.
	-- `Visible` ne dit rien des parents : un label visible dans un ecran cache n'est pas a l'ecran.
	local function onScreen(gui: GuiObject): boolean
		local node: Instance? = gui
		while node and not node:IsA("ScreenGui") do
			if node:IsA("GuiObject") and not node.Visible then
				return false
			end
			node = node.Parent
		end
		return node ~= nil and (node :: ScreenGui).Enabled
	end

	local function anchorSpot(): (number?, number?)
		local ui = playerGui:FindFirstChild(ANCHOR_UI)
		local found = ui and ui:FindFirstChild(ANCHOR_LABEL, true)
		if not (found and found:IsA("TextLabel") and found.TextBounds.X > 0 and onScreen(found)) then
			return nil, nil
		end
		local label = found :: TextLabel
		local pos, size, text = label.AbsolutePosition, label.AbsoluteSize, label.TextBounds
		local right
		if label.TextXAlignment == Enum.TextXAlignment.Left then
			right = pos.X + text.X
		elseif label.TextXAlignment == Enum.TextXAlignment.Right then
			right = pos.X + size.X
		else
			right = pos.X + (size.X + text.X) / 2
		end
		local origin = sg.AbsolutePosition
		local side = button.AbsoluteSize.X
		return right + ANCHOR_GAP - origin.X, pos.Y + size.Y / 2 - side / 2 - origin.Y
	end
	-- L'ECRAN DE CHOIX ARRIVE APRES LE SPAWN, et son nom peut encore glisser en place. On attend qu'il soit la ET
	-- immobile (deux mesures identiques), sinon la roue se poserait au milieu de son animation d'entree.
	task.spawn(function()
		local deadline = os.clock() + ANCHOR_WAIT
		local lastX, lastY = nil, nil
		while not pinned and os.clock() < deadline do
			local x, y = anchorSpot()
			if x and y and x == lastX and y == lastY then
				local cx, cy = clampToScreen(x, y, button.AbsoluteSize.X)
				button.Position = UDim2.fromOffset(cx, cy)
				pinned = true
				return
			end
			lastX, lastY = x, y
			task.wait(0.5)
		end
	end)

	-- APPUYER OU GLISSER. On ne lit que des ECARTS au point de depart : convertir une position de doigt en position
	-- d'interface est un pari sur la barre du haut, un ecart ne l'est pas (journal de CLAUDE.md). Et c'est nous qui
	-- decidons de l'appui, pas `Activated` : il tirerait aussi au lacher d'un glisser, puisque la roue suit le doigt.
	local held: InputObject? = nil
	local startPoint = Vector2.zero
	local startX, startY = 0, 0
	local dragging = false

	local function release(tap: boolean)
		if not held then
			return
		end
		held = nil
		if tap and not dragging then
			toggle()
		end
		dragging = false
	end

	local function moved(position: Vector3)
		local delta = Vector2.new(position.X, position.Y) - startPoint
		if not dragging and delta.Magnitude < DRAG_THRESHOLD then
			return
		end
		dragging = true
		pinned = true
		local x, y = clampToScreen(startX + delta.X, startY + delta.Y, button.AbsoluteSize.X)
		button.Position = UDim2.fromOffset(x, y)
	end

	button.InputBegan:Connect(function(input: InputObject)
		-- SEULEMENT un doigt qui COMMENCE ici : sans ce test, le pouce qui tourne la camera serait capture en passant
		-- dessus (journal de CLAUDE.md).
		if held or input.UserInputState ~= Enum.UserInputState.Begin then
			return
		end
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1 then
			return
		end
		held = input
		startPoint = Vector2.new(input.Position.X, input.Position.Y)
		startX, startY = button.Position.X.Offset, button.Position.Y.Offset
		dragging = false
	end)
	-- TouchMoved / TouchEnded et pas InputChanged / InputEnded : seuls les premiers tirent de facon fiable pour un
	-- geste commence SUR un element. La souris (emulateur de Studio) passe par les seconds.
	UserInputService.TouchMoved:Connect(function(touch: InputObject)
		if touch == held then
			moved(touch.Position)
		end
	end)
	UserInputService.TouchEnded:Connect(function(touch: InputObject)
		if touch == held then
			release(true)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local h = held
		if h and h.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement then
			moved(input.Position)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local h = held
		if h and h.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1 then
			release(true)
		end
	end)
	-- Le menu Roblox vole le doigt : son toucher ne se termine alors JAMAIS, et la roue resterait accrochee.
	GuiService.MenuOpened:Connect(function()
		release(false)
	end)
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
