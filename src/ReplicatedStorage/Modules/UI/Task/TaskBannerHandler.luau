--!strict
-- BANDEAU D'OBJECTIF, en haut de l'ecran. Il dit CE QU'ON DOIT FAIRE, ou l'on en est, et ce que ca rapporte.
--
-- CONSTRUIT EN CODE et pas dans Studio, contrairement aux autres interfaces du projet. C'est volontaire tant que
-- la maquette bouge : chaque essai part sur GitHub, se relit dans le diff, et ne demande a personne de refaire
-- les memes reglages a la main dans une deuxieme place. Le jour ou la forme est figee, il pourra passer dans
-- Studio comme les autres.
--
-- PAS DE SYSTEME DE TACHES DERRIERE. Une seule tache s'affiche, et c'est l'appelant qui dit laquelle. Une liste
-- generique -- plusieurs taches, conditions, priorites -- se construira quand il y en aura une deuxieme et une
-- troisieme REELLEMENT differentes : c'est la qu'on saura ce qu'elles ont en commun. Le deviner avant donne une
-- usine qui ne sert qu'un cas.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local TaskBannerHandler = {}

-- ===== PLACE ET TAILLE =====
-- En FRACTION D'ECRAN : le bandeau garde ses proportions du telephone au grand ecran. En pixels, il serait enorme
-- sur mobile et perdu sur un 27 pouces.
local POS = UDim2.fromScale(0.5, 0.055)
local SIZE = UDim2.fromScale(0.46, 0.088)
-- Il ne descend jamais sous cette hauteur en pixels : sous ~54 px le texte devient illisible sur telephone.
local MIN_HEIGHT = 54

-- ===== COULEURS =====
local GREEN_BG = Color3.fromRGB(45, 133, 106)
local WHITE = Color3.fromRGB(255, 255, 255)
local ICON_GREEN = Color3.fromRGB(64, 232, 44)
local BAR_EMPTY = Color3.fromRGB(203, 203, 203)
local BAR_FILL = Color3.fromRGB(126, 226, 138)
local XP_CYAN = Color3.fromRGB(96, 240, 255)

-- Image de l'icone. VIDE = un losange dessine en code, pour ne pas dependre d'un asset qui n'existe pas encore.
-- Poser un `rbxassetid://` ici remplace le dessin sans toucher au reste.
local ICON_IMAGE = ""

-- ===== ANIMATION =====
-- Il ARRIVE PAR LE HAUT : il vient de hors-champ, donc on comprend qu'il apparait maintenant. Apparaitre sur
-- place se lit comme un element qu'on n'avait pas remarque.
local SLIDE_IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HIDDEN_POS = UDim2.fromScale(POS.X.Scale, -0.15)
-- Vitesse de remplissage de la barre, en fraction par seconde. La barre GLISSE vers sa valeur au lieu d'y sauter :
-- c'est le mouvement qui se remarque, pas la valeur.
local FILL_SPEED = 6

local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local root: Frame? = nil
local titleLabel: TextLabel? = nil
local rewardLabel: TextLabel? = nil
local barFill: Frame? = nil
local shown = false
local fillNow = 0
local fillTarget = 0
local fillConn: RBXScriptConnection? = nil

-- Arrondit les coins d'un element. On PARENTE ici plutot que de rendre l'objet : contrairement a ce que j'avais
-- ecrit, l'API Roblox n'a pas de methode pour ajouter un enfant -- on pose `.Parent`, et rien d'autre. Un appel a
-- une methode qui n'existe pas passe `selene` sans un mot et ne casse qu'au lancement.
--
-- Le cast est necessaire : `Instance.new("UICorner")` n'est pas resolu vers le type `UICorner` par le
-- verificateur utilise ici, et poser `.CornerRadius` sur un `Instance` nu donne une erreur. Deja note au journal.
local function addCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function build(): Frame
	local existing = root
	if existing and existing.Parent then
		return existing
	end

	local sg = Instance.new("ScreenGui")
	sg.Name = "LeafiaTaskBanner"
	-- Il survit aux respawns : sans ca il serait recree a chaque mort, et les references gardees ici pointeraient
	-- sur du detruit. Le piege est note dans le journal du projet.
	sg.ResetOnSpawn = false
	sg.ScreenInsets = Enum.ScreenInsets.None
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 40
	sg.Parent = player:WaitForChild("PlayerGui")
	gui = sg

	local frame = Instance.new("Frame")
	frame.Name = "Banner"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = HIDDEN_POS
	frame.Size = SIZE
	frame.BackgroundColor3 = GREEN_BG
	frame.BorderSizePixel = 0
	frame.Parent = sg

	local minSize = Instance.new("UISizeConstraint")
	minSize.MinSize = Vector2.new(0, MIN_HEIGHT)
	minSize.Parent = frame

	-- ===== L'ICONE, a gauche =====
	-- Carree PAR CONTRAINTE et pas par une largeur en fraction : une fraction de la LARGEUR du bandeau
	-- s'ecraserait sur un ecran etroit, alors qu'un carre reste un carre.
	local iconBox = Instance.new("Frame")
	iconBox.Name = "IconBox"
	iconBox.AnchorPoint = Vector2.new(0, 0.5)
	iconBox.Position = UDim2.fromScale(0.012, 0.5)
	iconBox.Size = UDim2.fromScale(0, 1.35)
	iconBox.BackgroundTransparency = 1
	iconBox.Parent = frame

	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = iconBox

	if ICON_IMAGE ~= "" then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.Image = ICON_IMAGE
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = iconBox
	else
		-- LOSANGE DESSINE : deux carres tournes a 45 degres, l'un blanc (le contour), l'autre vert par-dessus.
		-- Ce n'est pas l'hexagone de la maquette -- un hexagone ne se dessine pas avec des rectangles -- mais ca
		-- tient la place et la couleur en attendant l'image.
		local outer = Instance.new("Frame")
		outer.AnchorPoint = Vector2.new(0.5, 0.5)
		outer.Position = UDim2.fromScale(0.5, 0.5)
		outer.Size = UDim2.fromScale(0.62, 0.62)
		outer.Rotation = 45
		outer.BackgroundColor3 = WHITE
		outer.BorderSizePixel = 0
		outer.Parent = iconBox
		addCorner(outer, 6)

		local inner = Instance.new("Frame")
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.Position = UDim2.fromScale(0.5, 0.5)
		inner.Size = UDim2.fromScale(0.66, 0.66)
		inner.BackgroundColor3 = ICON_GREEN
		inner.BorderSizePixel = 0
		inner.Parent = outer
		addCorner(inner, 4)
	end

	-- ===== LE TRAIT DU HAUT =====
	-- Il part de l'icone et file jusqu'au bord : c'est lui qui relie les trois blocs et qui donne au bandeau son
	-- allure de barre de mission plutot que de simple rectangle vert.
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0, 0.5)
	rule.Position = UDim2.fromScale(0.13, 0.24)
	rule.Size = UDim2.new(0.86, 0, 0, 3)
	rule.BackgroundColor3 = WHITE
	rule.BorderSizePixel = 0
	rule.Parent = frame
	addCorner(rule, 2)

	-- ===== LE TITRE =====
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.fromScale(0.14, 0.42)
	title.Size = UDim2.fromScale(0.6, 0.3)
	title.BackgroundTransparency = 1
	title.TextColor3 = WHITE
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	-- EN ANGLAIS. Le traducteur de Roblox part de l'anglais : un texte ecrit en francais n'est traduit nulle part,
	-- et le jeu devient illisible pour la quasi-totalite des joueurs de la plateforme.
	title.Text = "MOW THE LAWN"
	title.Parent = frame
	titleLabel = title

	-- ===== LA RECOMPENSE =====
	local reward = Instance.new("TextLabel")
	reward.Name = "Reward"
	reward.AnchorPoint = Vector2.new(1, 0.5)
	reward.Position = UDim2.fromScale(0.978, 0.42)
	reward.Size = UDim2.fromScale(0.22, 0.3)
	reward.BackgroundTransparency = 1
	reward.TextColor3 = XP_CYAN
	reward.Font = Enum.Font.GothamBold
	reward.TextScaled = true
	reward.TextXAlignment = Enum.TextXAlignment.Right
	reward.Text = "+ 50 XP"
	reward.Parent = frame
	rewardLabel = reward

	local glow = Instance.new("UIStroke")
	glow.Color = XP_CYAN
	glow.Thickness = 2
	glow.Transparency = 0.62
	glow.Parent = reward

	-- ===== LA BARRE =====
	local barBack = Instance.new("Frame")
	barBack.Name = "Bar"
	barBack.AnchorPoint = Vector2.new(0, 0.5)
	barBack.Position = UDim2.fromScale(0.145, 0.76)
	barBack.Size = UDim2.fromScale(0.39, 0.24)
	barBack.BackgroundColor3 = BAR_EMPTY
	barBack.BorderSizePixel = 0
	barBack.Parent = frame
	addCorner(barBack, 20)

	local outline = Instance.new("UIStroke")
	outline.Color = WHITE
	outline.Thickness = 3
	outline.Parent = barBack

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = BAR_FILL
	fill.BorderSizePixel = 0
	fill.Parent = barBack
	addCorner(fill, 20)
	barFill = fill

	root = frame
	return frame
end

-- Affiche le bandeau. `progress` va de 0 a 1.
function TaskBannerHandler.show(title: string, reward: string, progress: number?)
	local frame = build()
	local t = titleLabel
	if t then
		t.Text = title
	end
	local r = rewardLabel
	if r then
		r.Text = reward
	end
	TaskBannerHandler.setProgress(progress or 0)

	if shown then
		return
	end
	shown = true
	frame.Position = HIDDEN_POS
	TweenService:Create(frame, SLIDE_IN, { Position = POS }):Play()
end

-- Fixe l'avancement, de 0 a 1. La barre GLISSE vers la valeur : c'est le mouvement qui se remarque, pas le
-- chiffre -- une barre qui saute a sa place ne se voit pas.
function TaskBannerHandler.setProgress(value: number)
	fillTarget = math.clamp(value, 0, 1)
	if fillConn then
		return
	end
	fillConn = RunService.RenderStepped:Connect(function(dt: number)
		local bar = barFill
		if not (bar and bar.Parent) then
			return
		end
		fillNow += (fillTarget - fillNow) * math.min(1, FILL_SPEED * dt)
		-- Cle a la cible : un lerp exponentiel ne l'atteint jamais, et une barre "pleine" resterait a 99 % pour
		-- toujours -- ce qui se lit comme un objectif jamais fini.
		if math.abs(fillTarget - fillNow) < 0.002 then
			fillNow = fillTarget
		end
		bar.Size = UDim2.fromScale(fillNow, 1)
	end)
end

function TaskBannerHandler.hide()
	local frame = root
	if not (shown and frame and frame.Parent) then
		return
	end
	shown = false
	TweenService:Create(frame, SLIDE_OUT, { Position = HIDDEN_POS }):Play()
end

-- Tout ranger. La boucle de remplissage tourne sur RenderStepped : la laisser vivre apres la fermeture ferait
-- tourner un calcul pour une barre que personne ne regarde.
function TaskBannerHandler.destroy()
	if fillConn then
		fillConn:Disconnect()
		fillConn = nil
	end
	if gui then
		gui:Destroy()
		gui = nil
	end
	root, titleLabel, rewardLabel, barFill = nil, nil, nil, nil
	shown = false
	fillNow, fillTarget = 0, 0
end

return TaskBannerHandler
