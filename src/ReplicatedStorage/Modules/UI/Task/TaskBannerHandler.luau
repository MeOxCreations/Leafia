--!strict
-- BANDEAU D'OBJECTIFS, en haut a gauche. Il dit CE QU'ON DOIT FAIRE, ou l'on en est, et ce que ca rapporte.
--
-- CONSTRUIT EN CODE, et c'est une EXCEPTION ASSUMEE a "les ScreenGui se font dans Studio".
--
-- La raison est concrete et deja payee : Rojo ne synchronise PAS StarterGui. Une interface posee dans Studio
-- n'existe que dans la place ou elle a ete faite -- il faut la recopier a la main dans chaque autre, et le jour
-- ou l'on retouche un degrade, il faut recommencer partout. Une version construite ici part sur GitHub, se relit
-- dans le diff, et arrive dans TOUTES les places d'un coup.
--
-- Meme exception que Letterbox et ChapterTitle, pour exactement la meme raison.
--
-- LES VALEURS VIENNENT DE LA MAQUETTE faite dans Studio : positions, tailles, degrades, tout est repris tel
-- quel. Studio reste l'endroit ou l'on REGLE a l'oeil ; ce fichier est l'endroit ou le reglage se FIGE.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TaskConfigs = require(ReplicatedStorage.Modules.Configs.TaskConfigs)

local TaskBannerHandler = {}

-- ===== POLICES =====
-- Montserrat par sa FAMILLE et non par un Enum.Font : les enums de police sont en cours de depreciation
-- (`Enum.Font.Montserrat` renvoie deja vers Gotham). `Heavy` est le nom Roblox du poids 900, dit Black.
local FONT_BLACK = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
-- LE TITRE A SA PROPRE POLICE. Denk One est une police d'AFFICHAGE : large, tres lisible en gros, moins a
-- l'aise sur du texte courant -- d'ou son emploi ici seulement.
--
-- Elle n'existe qu'en UNE graisse chez Google Fonts. `Heavy` est demande quand meme : si Roblox n'a pas ce
-- poids il prend le plus proche, et l'ecrire ne coute rien. Si le titre sort dans une police qui ne ressemble a
-- rien, c'est le CHEMIN qui est faux -- Roblox retombe alors sur une police par defaut sans dire un mot.
local FONT_TITLE = Font.new("rbxasset://fonts/families/DenkOne.json", Enum.FontWeight.Heavy)

-- ===== PLACEMENT DES LIGNES =====
local ROW_SIZE = UDim2.fromScale(0.331, 0.068)
local FIRST_Y = 0.219
local ROW_GAP = 0.078

-- D'OU ELLES ARRIVENT. Hors champ a gauche : elles entrent par le bord, comme les notifications.
local HIDDEN_X = -0.6
local SHOWN_X = 0

local SLIDE_IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- Retard entre deux lignes : une liste qui se REMPLIT, pas un panneau qui apparait d'un coup.
local ROW_STAGGER = 0.09

-- ===== JAUGE =====
local FILL_SPEED = 6
-- Un poil sous 1 : a 1 pile, les coins arrondis du remplissage debordent de ceux de la barre.
local FILL_MAX = 0.98
-- Un lerp exponentiel n'atteint jamais sa cible : sans ce clou, une jauge pleine resterait a 99,7 % pour
-- toujours.
local FILL_SNAP = 0.004
local FILL_HEIGHT = 0.9

local WHITE = Color3.fromRGB(255, 255, 255)
-- Le vert de la tonte, pose sur le fond de chaque ligne.
local ROW_TINT = Color3.fromRGB(98, 206, 59)

-- Le degrade de la jauge, repris de la maquette.
local FILL_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("5aff2c")),
	ColorSequenceKeypoint.new(0.551, Color3.fromHex("5bfe2e")),
	ColorSequenceKeypoint.new(0.571, Color3.fromHex("c1ff8e")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("c1ff8e")),
})
-- Un fondu du plein au transparent. Sert au trait de separation et au trait sous le titre.
local FADE_OUT_SEQ = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(1, 1),
})

type Row = {
	frame: Frame,
	fill: Frame?,
	target: number,
	current: number,
}

local screen: ScreenGui? = nil
local template: Frame? = nil
local rows: { Row } = {}
local fillConn: RBXScriptConnection? = nil

--- Cree une instance, lui pose ses proprietes, la parente.
---
--- Rend `Instance` et non la classe precise : aucun appelant n'a besoin du type exact, et le rendre precis
--- ferait deduire a luau-lsp un type de tableau depuis le premier enfant, qui refuserait tous les suivants.
local function make(class: string, props: { [string]: any }, parent: Instance?): Instance
	local inst = Instance.new(class)
	-- LE LISERE PAR DEFAUT SAUTE ICI, UNE FOIS POUR TOUTES. Roblox pose `BorderSizePixel = 1` sur tout GuiObject :
	-- un trait d'un pixel autour de chaque element, qu'on ne remarque pas un par un mais qui salit l'ensemble --
	-- et qu'on oublie sur exactement celui ou ca se voit. Pose AVANT les proprietes demandees, donc un appelant
	-- qui en veut un peut toujours le redemander.
	if inst:IsA("GuiObject") then
		(inst :: GuiObject).BorderSizePixel = 0
	end
	for key, value in pairs(props) do
		(inst :: any)[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

--- Une ligne de tache, clonable a volonte. Reproduit la maquette a l'identique.
local function buildRow(parent: Instance): Frame
	local row = make("Frame", {
		Name = "TemplateTask",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Size = ROW_SIZE,
		Visible = false, -- le modele ne s'affiche jamais : il ne sert qu'a etre clone
	}, parent) :: Frame

	-- ===== LA BARRE DE PROGRESSION =====
	local bar = make("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		-- OPAQUE. En semi-transparente, le fond de la ligne se lit a travers la jauge vide et l'on ne sait plus
		-- ou elle s'arrete.
		BackgroundTransparency = 0,
		Position = UDim2.fromScale(0.145, 0.745),
		Size = UDim2.fromScale(0.39, 0.21),
		ZIndex = 1,
	}, row)
	-- Trois coins arrondis sur quatre : le coin haut-droit reste vif, c'est ce qui donne sa forme a la barre.
	make("UICorner", {
		BottomLeftRadius = UDim.new(0, 20),
		BottomRightRadius = UDim.new(0, 20),
		TopLeftRadius = UDim.new(0, 20),
		TopRightRadius = UDim.new(0, 0),
	}, bar)
	make("UIStroke", {
		Color = Color3.fromRGB(0, 0, 0),
		Thickness = 1.4,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, bar)

	local fill = make("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		Position = UDim2.fromScale(-0.001, 0.5),
		-- Part de zero : posee directement a sa valeur, on ne verrait pas qu'elle avance.
		Size = UDim2.fromScale(0, FILL_HEIGHT),
		ZIndex = 2,
	}, bar) :: Frame
	make("UICorner", { CornerRadius = UDim.new(0, 20) }, fill)
	make("UIGradient", { Color = FILL_GRADIENT }, fill)

	-- ===== LE TRAIT SOUS LE TEXTE =====
	local rule = make("Frame", {
		Name = "Rule",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		Position = UDim2.fromScale(0.112, 0.221),
		Size = UDim2.fromScale(0.86, 0.067),
	}, row)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, rule)
	make("UIGradient", { Color = ColorSequence.new(WHITE), Rotation = 89, Transparency = FADE_OUT_SEQ }, rule)

	-- IL DEBORDE LARGEMENT DE `Rule`, ET C'EST VOULU. `Rule` est un trait tres fin ; `FontColor` mesure pres de
	-- dix fois sa hauteur et descend sous lui. Ce n'est donc pas un second trait : c'est le FOND colore de la
	-- ligne, ancre sur le trait plutot que sur la ligne entiere pour le suivre s'il bouge.
	local fontColor = make("Frame", {
		Name = "FontColor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		Position = UDim2.fromScale(0.485, 5.5),
		Size = UDim2.fromScale(1.049, 9.714),
		ZIndex = 0, -- derriere tout le reste de la ligne : c'est un fond, pas un element
	}, rule)
	-- LE VERT DE LA TONTE. Il vient du gradient et non du fond du Frame : le fond reste blanc, donc le gradient
	-- le teinte franchement au lieu de s'assombrir sur une couleur deja posee.
	--
	-- C'est une couleur de TACHE, pas une couleur du bandeau : le jour ou une tache de ramassage s'affiche a
	-- cote, elle devra porter la sienne. La constante est donc le point unique a remplacer par une valeur venue
	-- de la tache, comme la teinte de la pastille juste en dessous.
	make("UIGradient", { Color = ColorSequence.new(ROW_TINT), Rotation = 80, Transparency = FADE_OUT_SEQ }, fontColor)

	-- ===== LA PASTILLE ET SON ICONE =====
	-- Trois couches empilees : le contour, la couleur de la tache, puis le dessin. Les ZIndex ne sont pas
	-- decoratifs -- sans eux le dessin passerait derriere sa propre pastille.
	make("ImageLabel", {
		Name = "FontIconOutline",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.08, 0.413),
		Size = UDim2.fromScale(0.118, 1.169),
		Image = TaskConfigs.ICON_OUTLINE,
		ImageColor3 = WHITE,
		ZIndex = 1,
	}, row)

	local iconColor = make("ImageLabel", {
		Name = "IconColor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.079, 0.419),
		Size = UDim2.fromScale(0.085, 0.862),
		Image = TaskConfigs.ICON_FILL,
		ZIndex = 2,
	}, row)
	make("UIGradient", { Color = TaskConfigs.TINTS.Green, Rotation = 32 }, iconColor)

	make("ImageLabel", {
		Name = "IconTaskDraw",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.079, 0.36),
		Size = UDim2.fromScale(0.095, 0.808),
		ZIndex = 3,
	}, row)

	-- ===== LES TEXTES =====
	make("TextLabel", {
		Name = "DescriptionTask",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.133, 0.42),
		Size = UDim2.fromScale(0.6, 0.3),
		FontFace = FONT_BLACK,
		Text = "",
		TextColor3 = WHITE,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, row)

	make("TextLabel", {
		Name = "RewardText",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.915, 0.634),
		-- PLUS GRAND QUE LA MAQUETTE. Le texte est en `TextScaled` : c'est la taille du CADRE qui decide de celle
		-- des lettres, pas un TextSize. Ancre a droite, il grandit vers la gauche et ne pousse donc pas la piece.
		Size = UDim2.fromScale(0.17, 0.58),
		FontFace = FONT_BLACK,
		Text = "",
		TextColor3 = WHITE,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 3,
	}, row)

	make("ImageLabel", {
		Name = "CurrencyImage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.943, 0.63),
		Size = UDim2.fromScale(0.055, 0.484),
		Visible = false, -- allumee seulement si la tache donne une monnaie
		ZIndex = 3,
	}, row)

	return row
end

--- Le decor : le titre, son ombre, et le trait sous lui. Construit une seule fois.
local function buildHeader(parent: Instance)
	local thickness = make("Frame", {
		Name = "ThicknessTop",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		Position = UDim2.fromScale(0.003, 0.175),
		Size = UDim2.fromScale(0.339, 0.006),
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, thickness)
	make("UIGradient", { Color = ColorSequence.new(WHITE), Rotation = 87, Transparency = FADE_OUT_SEQ }, thickness)

	local title = make("TextLabel", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.063, 0.15),
		Size = UDim2.fromScale(0.115, 0.042),
		FontFace = FONT_TITLE,
		Text = "TASKS",
		TextColor3 = WHITE,
		TextScaled = true,
		-- CALE A GAUCHE. Le titre coiffe une colonne de taches alignees a gauche : centre, il flotterait au-dessus
		-- d'elles au lieu de les commencer.
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	}, parent)
	make("UIGradient", {
		Name = "UIGradientTitle",
		-- A 90, le degrade descend du HAUT vers le BAS des lettres : le mot s'assombrit vers sa base. A zero il
		-- irait de gauche a droite et le premier caractere serait plus clair que le dernier.
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHex("ffffff")),
			ColorSequenceKeypoint.new(0.635, Color3.fromHex("ffffff")),
			ColorSequenceKeypoint.new(0.645, Color3.fromHex("e5e5e5")),
			ColorSequenceKeypoint.new(1, Color3.fromHex("e2e2e2")),
		}),
	}, title)

	-- L'OMBRE EST UN SECOND LABEL, legerement decale et SOUS le titre. Un contour (`TextStroke`) entourerait les
	-- lettres de tous les cotes ; ici on veut une ombre PORTEE, donc un decalage.
	local shadow = make("TextLabel", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.52, 0.55),
		Size = UDim2.fromScale(1.003, 1),
		-- MEME POLICE QUE LE TITRE, sinon l'ombre ne suit plus la forme des lettres et se lit comme un second mot.
		FontFace = FONT_TITLE,
		Text = "TASKS",
		TextColor3 = Color3.fromRGB(0, 0, 0),
		TextScaled = true,
		-- MEME CALAGE QUE LE TITRE : centree alors qu'il est a gauche, l'ombre se decalerait d'autant que le mot
		-- est plus court que son cadre.
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 1,
	}, title)
	make("UIGradient", {
		Name = "UIGradientShadow",
		Color = ColorSequence.new(WHITE),
		Rotation = -95,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.495, 0.0938),
			NumberSequenceKeypoint.new(0.766, 0.363),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, shadow)
end

--- Construit l'interface si elle n'existe pas encore. Rend `false` tant que le PlayerGui n'est pas la.
local function build(): boolean
	local existing = screen
	if existing and existing.Parent and template then
		return true
	end
	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return false
	end

	local sg = make("ScreenGui", {
		Name = "LeafiaTaskBanner",
		-- SANS INSET : l'origine du GUI devient le coin ABSOLU de l'ecran. Avec l'inset par defaut, tout le
		-- bandeau descendrait d'environ 36 px, la hauteur de la barre Roblox.
		ScreenInsets = Enum.ScreenInsets.None,
		-- Sinon il est recree a chaque mort, et les references gardees ici pointeraient sur du detruit.
		ResetOnSpawn = false,
		DisplayOrder = 5,
	}, gui) :: ScreenGui

	buildHeader(sg)
	template = buildRow(sg)
	screen = sg
	return true
end

local function stopFill()
	if fillConn then
		fillConn:Disconnect()
		fillConn = nil
	end
end

--- Une seule boucle pour toutes les jauges : une par ligne ferait tourner trois connexions pour trois barres qui
--- avancent aux memes instants. Elle se coupe quand plus rien ne bouge.
local function startFill()
	if fillConn then
		return
	end
	fillConn = RunService.RenderStepped:Connect(function(dt)
		local moving = false
		for _, row in ipairs(rows) do
			local fill = row.fill
			if not fill or not fill.Parent then
				continue
			end
			local gap = row.target - row.current
			if math.abs(gap) <= FILL_SNAP then
				row.current = row.target
			else
				row.current += gap * math.min(dt * FILL_SPEED, 1)
				moving = true
			end
			fill.Size = UDim2.fromScale(row.current * FILL_MAX, FILL_HEIGHT)
		end
		if not moving then
			stopFill()
		end
	end)
end

local function clearRows()
	for _, row in ipairs(rows) do
		row.frame:Destroy()
	end
	table.clear(rows)
	stopFill()
end

--- Remplit une ligne avec une tache.
---
--- Le parametre ne s'appelle PAS `task` : ce nom masquerait le service `task` de Roblox, et un `task.delay`
--- ajoute ici un jour appellerait `.delay` sur la config au lieu du planificateur -- en silence.
local function dress(frame: Frame, entry: TaskConfigs.Task)
	local desc = frame:FindFirstChild("DescriptionTask")
	if desc and desc:IsA("TextLabel") then
		desc.Text = entry.text
	end

	local reward = frame:FindFirstChild("RewardText")
	if reward and reward:IsA("TextLabel") then
		reward.Text = entry.reward
	end

	local draw = frame:FindFirstChild("IconTaskDraw")
	if draw and draw:IsA("ImageLabel") then
		local id = TaskConfigs.ICONS[entry.icon]
		if not id then
			-- ON NOMME LA CLE MANQUANTE. "L'icone ne s'affiche pas" enverrait chercher du cote de l'image ;
			-- c'est la CLE qui est fausse, et elle se corrige a l'appel.
			warn(`[TaskBanner] Icone inconnue "{entry.icon}" : voir TaskConfigs.ICONS.`)
		end
		draw.Image = id or ""
	end

	local currency = frame:FindFirstChild("CurrencyImage")
	if currency and currency:IsA("ImageLabel") then
		currency.Image = entry.currency or ""
		currency.Visible = entry.currency ~= nil
	end

	-- LA TEINTE VA SUR LE GRADIENT de la pastille, pas sur sa couleur : le degrade lui donne son relief, et
	-- ecrire ImageColor3 par-dessus l'aplatirait.
	local tint = entry.tint
	if tint then
		local pastille = frame:FindFirstChild("IconColor")
		local grad = pastille and pastille:FindFirstChildOfClass("UIGradient")
		if grad then
			grad.Color = tint
		end
	end
end

--- Affiche la liste des taches. Remplace ce qui etait a l'ecran.
function TaskBannerHandler.show(tasks: { TaskConfigs.Task })
	if not build() then
		warn("[TaskBanner] Pas de PlayerGui : aucun objectif ne s'affichera.")
		return
	end
	local model = template :: Frame
	clearRows()

	for i, entry in ipairs(tasks) do
		local frame = model:Clone()
		frame.Name = `Task{i}`
		frame.Visible = true
		frame.Position = UDim2.fromScale(HIDDEN_X, FIRST_Y + (i - 1) * ROW_GAP)
		frame.Parent = model.Parent
		dress(frame, entry)

		local bar = frame:FindFirstChild("Bar")
		local fillFrame = bar and bar:FindFirstChild("Fill")
		local fill = if fillFrame and fillFrame:IsA("Frame") then fillFrame else nil

		table.insert(rows, { frame = frame, fill = fill, target = entry.progress or 0, current = 0 })

		-- EN CASCADE : chaque ligne part apres la precedente.
		local slideTo = UDim2.fromScale(SHOWN_X, frame.Position.Y.Scale)
		task.delay((i - 1) * ROW_STAGGER, function()
			if frame.Parent then
				TweenService:Create(frame, SLIDE_IN, { Position = slideTo }):Play()
			end
		end)
	end

	startFill()
end

--- Fixe l'avancement d'une ligne, de 0 a 1. `index` est sa place dans la liste passee a `show`.
function TaskBannerHandler.setProgress(index: number, value: number)
	local row = rows[index]
	if not row then
		return
	end
	row.target = math.clamp(value, 0, 1)
	startFill()
end

--- Range tout, en cascade elle aussi.
function TaskBannerHandler.hide()
	local count = #rows
	for i, row in ipairs(rows) do
		local frame = row.frame
		local out = UDim2.fromScale(HIDDEN_X, frame.Position.Y.Scale)
		task.delay((i - 1) * ROW_STAGGER, function()
			if frame.Parent then
				TweenService:Create(frame, SLIDE_OUT, { Position = out }):Play()
			end
		end)
	end
	-- On attend la sortie de la derniere : detruire pendant le tween ferait disparaitre les lignes d'un coup au
	-- lieu de les faire glisser.
	task.delay(math.max(count - 1, 0) * ROW_STAGGER + SLIDE_OUT.Time, clearRows)
end

--- Tout ranger sans animation. La boucle de remplissage tourne sur RenderStepped : la laisser vivre apres la
--- fermeture ferait tourner un calcul pour des barres que personne ne regarde.
function TaskBannerHandler.destroy()
	clearRows()
end

return TaskBannerHandler
