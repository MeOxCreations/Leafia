--!strict
-- CARTON DE CHAPITRE. Un titre qui s'ecrit lettre par lettre, en vague, puis s'efface.
--
-- POURQUOI. Les barres noires disent au joueur qu'il regarde ; le carton lui dit CE qu'il regarde. Nommer un
-- moment le transforme en chapitre d'une histoire, au lieu d'une scene de plus. Ca ne coute qu'une ligne de
-- texte et ca change ce que le joueur croit etre en train de vivre.
--
-- PRIMITIVE REUTILISABLE : elle ne connait ni le grand-pere, ni le tutoriel. On lui donne un texte, elle le
-- joue. Le chapitre 2 passera par le meme module.
--
-- MEME EXCEPTION QUE LETTERBOX a "les ScreenGui se font dans Studio" : rien a regler a l'oeil ici, et le poser
-- dans Studio obligerait a le recopier dans chaque place (Rojo ne synchronise pas StarterGui).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ChapterTitle = {}

-- MONTSERRAT NOIR, DESIGNE PAR SA FAMILLE et pas par un Enum.Font : les enums de police sont en cours de
-- depreciation (`Enum.Font.Montserrat` renvoie deja vers Gotham), alors que le chemin de famille reste stable et
-- porte le poids separement. `Heavy` est le nom Roblox du poids 900, celui qu'on appelle Black en typographie.
local FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)

-- AU-DESSUS DES BARRES NOIRES (100), puisque le titre s'ecrit DEDANS.
local DISPLAY_ORDER = 101

-- Milieu de la bande noire du bas. Letterbox en occupe 11 % : le centre tombe donc a 1 - 0.11/2. Ecrit en clair
-- plutot que calcule depuis Letterbox, pour ne pas rendre ce module dependant d'elle -- il doit pouvoir servir
-- sans barres.
local ROW_CENTER_Y = 0.945
local ROW_HEIGHT = 0.052 -- hauteur de la ligne, en part d'ecran : c'est elle qui donne la taille du texte

-- Retard entre deux lettres. C'est LUI qui fait la vague : a zero elles arrivent ensemble et il ne reste qu'un
-- fondu. Trop grand, on lit le mot plus vite qu'il ne s'affiche.
local LETTER_STAGGER = 0.035
local LETTER_TIME = 0.42 -- duree de l'arrivee d'UNE lettre
-- De combien elle monte, en part de la taille du texte. Elle arrive PAR EN DESSOUS : vers le haut elle sortirait
-- de la bande noire et passerait sur l'image.
local LETTER_RISE = 0.7

local HOLD = 2.2 -- temps ou le titre reste lisible, une fois la derniere lettre posee
local FADE_OUT = 0.6

-- On ne garde QUE la ligne : le ScreenGui se retrouve par `row.Parent` le jour ou on en a besoin.
local row: Frame? = nil
local token = {} -- annule une animation en cours quand une autre demarre

local function build(): Frame?
	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return nil
	end

	local existing = row
	if existing and existing.Parent then
		return existing
	end

	local sg = Instance.new("ScreenGui")
	sg.Name = "ChapterTitle"
	-- MEME REGLE QUE WORLDANCHOR ET LETTERBOX : sans inset, l'origine du GUI est le coin ABSOLU de l'ecran. Avec
	-- l'inset par defaut, la ligne descendrait de ~36 px et sortirait de la bande noire par le bas.
	sg.ScreenInsets = Enum.ScreenInsets.None
	-- Sinon il est recree a chaque mort, et les references gardees ici pointeraient sur du detruit.
	sg.ResetOnSpawn = false
	sg.DisplayOrder = DISPLAY_ORDER
	sg.IgnoreGuiInset = true
	sg.Parent = gui

	local frame = Instance.new("Frame")
	frame.Name = "Row"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, ROW_CENTER_Y)
	frame.Size = UDim2.fromScale(0.9, ROW_HEIGHT)
	frame.Parent = sg

	row = frame
	return frame
end

--- Affiche `text`, lettre par lettre. Un nouvel appel remplace celui en cours.
function ChapterTitle.show(text: string)
	local frame = build()
	if not frame or text == "" then
		return
	end

	local mine = {}
	token = mine
	frame:ClearAllChildren()

	-- UNE LETTRE = UN LABEL. `AutomaticSize` laisse Roblox mesurer chaque caractere : sans lui il faudrait
	-- mesurer le texte a la main, et cette mesure serait fausse tant que la police n'est pas arrivee.
	local letters: { TextLabel } = {}
	for _, code in utf8.codes(text) do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromScale(0, 1)
		label.Text = utf8.char(code)
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextTransparency = 1 -- invisible tant qu'elle n'est pas arrivee
		label.FontFace = FONT
		label.Parent = frame
		letters[#letters + 1] = label
	end
	if #letters == 0 then
		return
	end

	task.spawn(function()
		-- UNE IMAGE D'ATTENTE avant de mesurer : `AbsoluteSize` n'est calcule qu'apres le passage de la mise en
		-- page. Le lire tout de suite rendrait zero, et toutes les lettres se poseraient l'une sur l'autre.
		RunService.RenderStepped:Wait()
		if token ~= mine or not frame.Parent then
			return
		end

		local t0 = os.clock()
		local total = (#letters - 1) * LETTER_STAGGER + LETTER_TIME

		-- UNE SEULE BOUCLE ECRIT LA POSITION, et elle RE-MESURE a chaque image.
		--
		-- Une police se charge PARESSEUSEMENT : le titre peut etre dessine avec une police de secours, puis
		-- redessine avec Montserrat. Roblox echange le rendu tout seul, mais pas nos positions, calculees sur les
		-- largeurs de l'ancienne -- les lettres resteraient mal espacees. Aucune API ne dit quand la vraie police
		-- arrive, donc on ne devine pas : on relit et on replace. Ca couvre aussi le redimensionnement de fenetre.
		--
		-- C'est aussi pour ca qu'il n'y a pas d'UIListLayout : un layout reposerait ses enfants a chaque image et
		-- ecraserait le Y de la vague.
		while token == mine and frame.Parent do
			local now = os.clock() - t0
			local size = math.max(math.floor(frame.AbsoluteSize.Y), 8)

			local width = 0
			for _, label in ipairs(letters) do
				label.TextSize = size
				width += label.AbsoluteSize.X
			end

			local x = (frame.AbsoluteSize.X - width) * 0.5
			for i, label in ipairs(letters) do
				local e = math.clamp((now - (i - 1) * LETTER_STAGGER) / LETTER_TIME, 0, 1)
				-- `Quad Out` a la main : la lettre part franchement et se pose en douceur.
				local eased = 1 - (1 - e) * (1 - e)
				label.Position = UDim2.new(0, math.round(x), 0.5, math.round((1 - eased) * size * LETTER_RISE))
				label.AnchorPoint = Vector2.new(0, 0.5)
				label.TextTransparency = 1 - eased
				x += label.AbsoluteSize.X
			end

			if now >= total then
				break
			end
			RunService.RenderStepped:Wait()
		end

		if token ~= mine or not frame.Parent then
			return
		end

		task.wait(HOLD)
		if token ~= mine or not frame.Parent then
			return
		end

		-- LE MOT PART D'UN BLOC. La vague servait a le faire ARRIVER ; la refaire a l'envers ferait un second
		-- evenement, alors qu'on est en train de rendre l'attention a la scene.
		local info = TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, label in ipairs(letters) do
			TweenService:Create(label, info, { TextTransparency = 1 }):Play()
		end
	end)
end

--- Coupe immediatement ce qui est affiche. A appeler quand une scene est interrompue.
function ChapterTitle.hide()
	token = {}
	local frame = row
	if frame and frame.Parent then
		frame:ClearAllChildren()
	end
end

return ChapterTitle
