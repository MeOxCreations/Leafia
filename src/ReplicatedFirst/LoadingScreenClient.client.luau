--!strict
-- Ecran de chargement de Leafia.
--
-- Ce fichier est VOLONTAIREMENT autonome : il ne require aucun module de ReplicatedStorage. ReplicatedFirst se
-- replique avant le reste du jeu, c'est tout son interet. Attendre un module de ReplicatedStorage reviendrait a
-- bloquer sur ce qu'on est justement en train de masquer.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
ReplicatedFirst:RemoveDefaultLoadingScreen()

local loadingGui = ReplicatedFirst:WaitForChild("LoadingScreen") :: ScreenGui
-- Le CanvasGroup enveloppe TOUT le bloc visuel. Il ne sert qu'a la sortie : il rend ses enfants dans un tampon
-- unique, donc un seul tween sur GroupTransparency les fait fondre ensemble, sans avoir a citer chaque element.
-- GAMEVERSION et LOADING_ASSETS_TEXT sont volontairement dehors : ce sont des textes, ils s'effacent avant.
local canvasGroup = loadingGui:WaitForChild("CanvasGroup") :: CanvasGroup
local loadHolder = canvasGroup:WaitForChild("LoadHolder") :: GuiObject
local statusLabel = loadingGui:WaitForChild("LOADING_ASSETS_TEXT") :: TextLabel
local gameVersion = loadingGui:WaitForChild("GAMEVERSION") :: TextLabel
local fontTile = loadHolder:WaitForChild("FontTile") :: ImageLabel
local cercleImage = loadHolder:WaitForChild("CercleImage") :: ImageLabel
local iconLogo = loadHolder:WaitForChild("IconLogo") :: ImageLabel
local skipButton = loadHolder:WaitForChild("SkipButton") :: ImageButton
local copyRight = loadHolder:WaitForChild("CopyRightText") :: TextLabel

local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
loadingGui.Parent = playerGui

-- ===== Config =====
local MIN_DURATION = 2 -- duree minimale a l'ecran, meme si tout est deja charge
local SKIP_APPEAR_AFTER = 2 -- delai avant que le bouton passer apparaisse

local currentAsset = ""
local animating = true
local skipRequested = false

-- ===== Masquage du chat et de la liste des joueurs =====
-- Ces deux interfaces sont de la CoreGui : elles s'affichent PAR-DESSUS notre ScreenGui, quel que soit le
-- ZIndex. Sans ca, l'intro arrive avec des noms de joueurs colles dans le coin.
local HIDDEN_CORE_GUIS = {
	Enum.CoreGuiType.Chat,
	Enum.CoreGuiType.PlayerList,
}

-- Si ce script meurt en route (erreur, asset introuvable), le chat resterait masque toute la session. Le
-- joueur ne comprend pas, ne le signale pas, et part. Ce filet le rend quoi qu'il arrive.
local CORE_GUI_SAFETY_DELAY = 60

-- On MEMORISE l'etat d'origine au lieu de forcer true a la fin : le jour ou une feature decide de garder la
-- liste des joueurs masquee, un restore en dur la rallumerait dans son dos.
local coreGuiPrevious: { [Enum.CoreGuiType]: boolean } = {}
local coreGuiRestored = false

-- Le chat moderne (TextChatService) ne passe pas toujours par la CoreGui. On agit sur les deux chemins : celui
-- qui ne s'applique pas ne fait simplement rien.
-- Doc : create.roblox.com/docs/chat/in-experience-text-chat
local chatWindow = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
local chatWindowPrevious = if chatWindow then chatWindow.Enabled else nil

local function hideCoreGuis()
	if chatWindow then
		chatWindow.Enabled = false
	end
	-- SetCoreGuiEnabled leve tant que la CoreGui n'est pas chargee, et on tourne dans ReplicatedFirst donc tres
	-- tot. On reessaie chaque frame au lieu d'abandonner au premier echec.
	task.spawn(function()
		local pending = table.clone(HIDDEN_CORE_GUIS)
		local deadline = os.clock() + 5
		-- coreGuiRestored dans la condition : si la sortie arrive pendant qu'on reessaie encore, cette boucle
		-- remasquerait ce que restoreCoreGuis vient de rendre.
		while #pending > 0 and not coreGuiRestored and os.clock() < deadline do
			for i = #pending, 1, -1 do
				local coreGuiType = pending[i]
				local ok = pcall(function()
					if coreGuiPrevious[coreGuiType] == nil then
						coreGuiPrevious[coreGuiType] = StarterGui:GetCoreGuiEnabled(coreGuiType)
					end
					StarterGui:SetCoreGuiEnabled(coreGuiType, false)
				end)
				if ok then
					table.remove(pending, i)
				end
			end
			if #pending > 0 then
				RunService.Heartbeat:Wait()
			end
		end
	end)
end

local function restoreCoreGuis()
	if coreGuiRestored then
		return
	end
	coreGuiRestored = true
	for coreGuiType, wasEnabled in pairs(coreGuiPrevious) do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreGuiType, wasEnabled)
		end)
	end
	if chatWindow and chatWindowPrevious ~= nil then
		chatWindow.Enabled = chatWindowPrevious
	end
end

hideCoreGuis()
task.delay(CORE_GUI_SAFETY_DELAY, restoreCoreGuis)

-- ===== Sons (tous OPTIONNELS) =====
-- Aucun son n'existe encore dans le projet. On ne warn pas quand il en manque un : un asset volontairement
-- absent qui gueule dans la console, c'est du bruit qu'on finit par ignorer, et le vrai warn passe avec.
-- Le jour ou tu poses les sons dans SoundService, ils se mettent a jouer sans toucher a ce fichier.
local SOUND_MUSIC = { "GameSounds", "Musics", "Loading Screen" }
local SOUND_LOGO_POP = { "UI", "cartoon_pop" }
local SOUND_SHOCKWAVE = { "UI", "Star_Explosion" }

local function findSound(path: { string }): Sound?
	local current: Instance = SoundService
	for _, name in ipairs(path) do
		local child = current:FindFirstChild(name)
		if not child then
			return nil
		end
		current = child
	end
	return if current:IsA("Sound") then current else nil
end

-- On joue une COPIE, jamais l'original : deux lectures qui se chevauchent sur la meme instance se coupent
-- l'une l'autre, et l'original garde un Playing a true qui fausse tout le reste.
local function playSound(path: { string }, volumeScale: number?)
	local source = findSound(path)
	if not source then
		return
	end
	local sound = source:Clone()
	if volumeScale then
		sound.Volume = source.Volume * volumeScale
	end
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	-- Filet de securite : un son qui ne se termine jamais (asset absent, echec de chargement) ne doit pas
	-- rester accroche a SoundService pour la session entiere.
	task.delay(10, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local loadingMusic: Sound? = nil
do
	local source = findSound(SOUND_MUSIC)
	if source then
		local music = source:Clone()
		music.Looped = true
		music.Parent = SoundService
		music:Play()
		loadingMusic = music
	end
end

-- ===== Tips de gameplay =====
-- Textes joueur : en anglais, c'est la langue par defaut sur la plateforme. Aucun nom de jeu connu cite.
local TIPS = {
	"Every client has a deadline. Late work costs you your rating.",
	"Trim slow and clean. A rushed hedge shows.",
	"Your rating decides which clients call you back.",
	"Tools wear down. Keep an eye on your gear.",
	"Bigger jobs pay more, but they are harder to finish in time.",
	"Reinvest early. A better tool pays for itself in one job.",
	"Work with a friend to take on the long jobs.",
	"Your company grows only as fast as your reputation.",
}

-- ===== Tweens preconfigures =====
local TWEEN_SHOCK = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- Sortie DOUCE. En Back In sur un retrecissement vers zero, l'element grossit d'abord (l'overshoot du Back)
-- puis s'effondre d'un coup : lu comme une aspiration brutale, au moment precis ou le joueur vient de demander
-- a passer. On fond au lieu d'ecraser.
local TWEEN_EXIT = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_FADE = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_TEXT_FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

-- ===== Memorisation des tailles cibles (celles reglees dans Studio) =====
local iconLogoSize = iconLogo.Size
local skipButtonSize = skipButton.Size

-- ===== SLIME D'APPARITION DU LOGO =====
-- Un slime, ce n'est pas un simple grossissement : c'est une deformation NON UNIFORME. La matiere s'ecrase
-- large et plate a l'impact, rebondit haute et fine, puis tremblote avant de se figer. Un UIScale ne peut pas
-- faire ca (il est uniforme), donc on anime la Size en dissociant X et Y.
local LOGO_SPLAT_X, LOGO_SPLAT_Y = 1.18, 0.82 -- ecrase : large et aplati
local LOGO_STRETCH_X, LOGO_STRETCH_Y = 0.93, 1.09 -- rebond : etire vers le haut
local LOGO_SLIME_SPLAT = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local LOGO_SLIME_STRETCH = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
-- C'est CE tween qui fait le "prolonge" : Elastic sur presque une seconde, le logo continue de gigoter
-- longtemps apres avoir atteint sa taille finale.
local LOGO_SLIME_SETTLE = TweenInfo.new(0.95, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

-- Multiplie X et Y separement en gardant Scale ET Offset : la taille Studio peut etre exprimee dans l'un,
-- l'autre, ou les deux, et n'en traiter qu'un casserait la mise en page selon le reglage.
local function logoSize(fx: number, fy: number): UDim2
	return UDim2.new(
		iconLogoSize.X.Scale * fx,
		iconLogoSize.X.Offset * fx,
		iconLogoSize.Y.Scale * fy,
		iconLogoSize.Y.Offset * fy
	)
end

-- ===== POINTS DE CHARGEMENT (4 boules qui rebondissent en vague) =====
-- Pas de barre de progression. Une barre PROMET une duree ; des points disent juste "ca travaille". C'est plus
-- honnete ici, puisqu'on ne connait pas la duree reelle du prechargement, et ca evite l'effet "barre bloquee a
-- 80%" qui donne l'impression que le jeu a plante.
-- Construits EN CODE : rien a poser dans Studio, tous les reglages sont ci-dessous.
local DOT_COUNT = 4
local DOT_Y = 0.72 -- position verticale du groupe dans le holder (sous le logo)
local DOT_COLOR = Color3.fromRGB(255, 255, 255)

-- Ces tailles sont en pixels de REFERENCE, pas en pixels reels : un UIScale (voir applyDotsScale) les remet a
-- l'echelle de l'ecran du joueur. On raisonne donc ici sur un 1080p et on oublie le reste.
local DOT_REF_HEIGHT = 1080
local DOT_SIZE = 16 -- diametre d'un point
local DOT_GAP = 12 -- espace entre deux points
local DOT_RISE = 20 -- hauteur du saut
-- Bornes de l'echelle : sans elles un tres petit ecran rendrait les points illisibles, et un 4K en ferait des
-- grosses billes.
local DOT_SCALE_MIN = 0.75
local DOT_SCALE_MAX = 2

-- Montee franche puis retombee elastique : c'est le "slime". La descente dure plus longtemps que la montee,
-- sinon le rebond parait mecanique.
local DOT_UP_TIME = 0.16
local DOT_DOWN_TIME = 0.34
local DOT_UP = TweenInfo.new(DOT_UP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local DOT_DOWN = TweenInfo.new(DOT_DOWN_TIME, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

-- Periode d'un point : juste de quoi contenir montee + descente. Plus long, et il reste une pause morte entre
-- deux sauts, ce qui donne "rebond, pause, rebond" au lieu d'une vague qui circule.
local DOT_PERIOD = DOT_UP_TIME + DOT_DOWN_TIME
-- Decalage entre deux points voisins. Reparti sur la periode : quand la vague sort du dernier point, elle
-- repart du premier, donc le mouvement ne s'arrete jamais.
local DOT_STEP = DOT_PERIOD / (DOT_COUNT + 1)

local dotsScale: UIScale? = nil
local dots: { Frame } = {}
local dotsRunning = false
local viewportConn: RBXScriptConnection? = nil

-- L'echelle suit la HAUTEUR de l'ecran. Un UIScale multiplie aussi les offsets des enfants, donc les sauts
-- suivent automatiquement : rien a toucher dans la boucle d'animation.
local function applyDotsScale()
	local scale = dotsScale
	if not scale then
		return
	end
	local cam = workspace.CurrentCamera
	local height = if cam then cam.ViewportSize.Y else DOT_REF_HEIGHT
	if height <= 0 then
		return
	end
	scale.Scale = math.clamp(height / DOT_REF_HEIGHT, DOT_SCALE_MIN, DOT_SCALE_MAX)
end

local function buildBounceDots()
	local holder = Instance.new("Frame")
	holder.Name = "LoadingDots"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, DOT_Y)
	holder.Size = UDim2.fromOffset(DOT_COUNT * DOT_SIZE + (DOT_COUNT - 1) * DOT_GAP, DOT_SIZE + DOT_RISE)
	holder.BackgroundTransparency = 1
	holder.Parent = loadHolder

	local scale = Instance.new("UIScale")
	scale.Parent = holder
	dotsScale = scale

	for i = 1, DOT_COUNT do
		local d = Instance.new("Frame")
		d.Name = "Dot" .. i
		-- AnchorPoint en BAS : le point saute vers le haut, sa base reste posee sur la meme ligne.
		d.AnchorPoint = Vector2.new(0, 1)
		d.Position = UDim2.fromOffset((i - 1) * (DOT_SIZE + DOT_GAP), holder.Size.Y.Offset)
		d.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
		d.BackgroundColor3 = DOT_COLOR
		d.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0) -- cercle parfait
		corner.Parent = d
		d.Parent = holder
		dots[i] = d
	end

	applyDotsScale()

	local cam = workspace.CurrentCamera
	if cam then
		viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyDotsScale)
	end
end

-- Chaque point a SA propre boucle, decalee de DOT_STEP : c'est ce qui donne la vague plutot qu'un
-- clignotement synchrone. Un timer unique partage aurait demande de gerer les phases a la main.
local function startBounceDots()
	if dotsRunning then
		return
	end
	dotsRunning = true
	local startAt = os.clock()
	for i, d in ipairs(dots) do
		task.spawn(function()
			local phase = (i - 1) * DOT_STEP
			local baseY = d.Position.Y.Offset
			local x = d.Position.X.Offset
			local cycle = 0
			while dotsRunning and d.Parent do
				-- On vise un instant ABSOLU au lieu d'enchainer des task.wait relatifs. Chaque wait arrondit au
				-- frame suivant ; cumule sur des centaines de cycles, les points derivent les uns par rapport aux
				-- autres et la vague se transforme en bouillie.
				local target = startAt + phase + cycle * DOT_PERIOD
				local delay = target - os.clock()
				if delay > 0 then
					task.wait(delay)
				end
				if not (dotsRunning and d.Parent) then
					break
				end

				TweenService:Create(d, DOT_UP, { Position = UDim2.fromOffset(x, baseY - DOT_RISE) }):Play()
				task.wait(DOT_UP_TIME)
				if not (dotsRunning and d.Parent) then
					break
				end
				TweenService:Create(d, DOT_DOWN, { Position = UDim2.fromOffset(x, baseY) }):Play()

				cycle += 1
			end
		end)
	end
end

local function stopBounceDots()
	dotsRunning = false
	-- Le LoadingScreen se detruit a la fin, mais cette connexion vit sur la CAMERA, pas sur lui : sans ce
	-- Disconnect elle resterait active toute la session en gardant des Frames mortes en memoire.
	if viewportConn then
		viewportConn:Disconnect()
		viewportConn = nil
	end
end

-- ===== REFLET DU LOGO (balayage en transparence) =====
-- La COULEUR du gradient reste blanche partout : le logo garde ses teintes d'origine, on ne l'assombrit
-- jamais. C'est la TRANSPARENCE du gradient qu'on sculpte : une bande translucide etroite qui glisse sur
-- l'image. Le logo s'efface juste sur le passage de la bande, puis redevient plein.
local LOGO_SHINE_FADE = 0.55 -- transparence au coeur de la bande (0 = rien ne se passe, 1 = trou complet)
local LOGO_SHINE_ROT = 20 -- angle du balayage en degres : une diagonale rend mieux qu'une verticale
local LOGO_SHINE_SWEEP = 0.9 -- duree d'une traversee
local LOGO_SHINE_PAUSE = 1.6 -- temps mort entre deux reflets, sinon l'effet devient clignotant et fatigant
-- On sort du cadre des deux cotes : avec la rotation, s'arreter pile a 1 laisserait un coin non balaye.
local LOGO_SHINE_TRAVEL = 1.25

local logoGradient: UIGradient? = nil
local shineRunning = false

local function buildLogoShine()
	-- Si Studio en a deja pose un SUR LE LOGO, on le REUTILISE : deux UIGradient empiles sur la meme image
	-- donnent un resultat imprevisible (leurs transparences se cumulent) et seul le dernier suivrait notre
	-- animation. Le gradient pose sur LoadHolder, lui, n'est pas concerne : on n'y touche pas.
	local existing = iconLogo:FindFirstChildOfClass("UIGradient")
	local g = existing or Instance.new("UIGradient")
	g.Name = "LogoShine"
	g.Rotation = LOGO_SHINE_ROT

	-- Blanc uni : le gradient ne touche pas aux couleurs du logo.
	g.Color = ColorSequence.new(Color3.new(1, 1, 1))
	-- Tout est opaque sauf une bande etroite au milieu. C'est elle qui balaie l'image.
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.42, 0),
		NumberSequenceKeypoint.new(0.5, LOGO_SHINE_FADE),
		NumberSequenceKeypoint.new(0.58, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
	g.Offset = Vector2.new(-LOGO_SHINE_TRAVEL, 0)
	g.Parent = iconLogo
	logoGradient = g
end

local function startLogoShine()
	if shineRunning then
		return
	end
	shineRunning = true
	task.spawn(function()
		while shineRunning do
			local g = logoGradient
			if not (g and g.Parent) then
				break
			end
			g.Offset = Vector2.new(-LOGO_SHINE_TRAVEL, 0)
			TweenService:Create(
				g,
				TweenInfo.new(LOGO_SHINE_SWEEP, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Offset = Vector2.new(LOGO_SHINE_TRAVEL, 0) }
			):Play()
			task.wait(LOGO_SHINE_SWEEP + LOGO_SHINE_PAUSE)
		end
	end)
end

local function stopLogoShine()
	shineRunning = false
end

buildBounceDots()
buildLogoShine()

-- ===== Etats de depart : tout a zero =====
iconLogo.Size = UDim2.new(0, 0, 0, 0)
cercleImage.Size = UDim2.new(0, 0, 0, 0)
cercleImage.ImageTransparency = 0
skipButton.ImageTransparency = 1

-- ===== Skip (bouton + touche Echap) =====
local function skipLoading()
	if skipRequested then
		return
	end
	skipRequested = true
	animating = false
end

skipButton.MouseButton1Click:Connect(skipLoading)

local skipHoverInfo = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
skipButton.MouseEnter:Connect(function()
	if skipRequested then
		return
	end
	TweenService:Create(skipButton, skipHoverInfo, {
		Size = UDim2.new(
			skipButtonSize.X.Scale * 1.12,
			skipButtonSize.X.Offset * 1.12,
			skipButtonSize.Y.Scale * 1.12,
			skipButtonSize.Y.Offset * 1.12
		),
	}):Play()
end)
skipButton.MouseLeave:Connect(function()
	if skipRequested then
		return
	end
	TweenService:Create(skipButton, skipHoverInfo, { Size = skipButtonSize }):Play()
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		skipLoading()
	end
end)

-- Le bouton n'apparait qu'apres un delai : propose trop tot, il invite a passer une intro que le joueur n'a
-- pas encore vue.
task.delay(SKIP_APPEAR_AFTER, function()
	if skipRequested then
		return
	end
	TweenService:Create(skipButton, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		ImageTransparency = 0,
	}):Play()
end)

-- ===== Defilement du fond tuile =====
local TILE = 20
local SPEED = 15
local tileOffset = 0
fontTile.Size = UDim2.new(1, TILE * 2, 1, TILE * 2)
fontTile.TileSize = UDim2.fromOffset(TILE, TILE)

local heartbeatConn: RBXScriptConnection? = nil
heartbeatConn = RunService.Heartbeat:Connect(function(dt: number)
	tileOffset += SPEED * dt
	if tileOffset >= TILE then
		tileOffset -= TILE
	end
	fontTile.Position = UDim2.new(0.5, tileOffset, 0.5, tileOffset)
end)

-- ===== Moniteur de FPS (moyenne glissante sur ~20 frames) =====
-- Sert a asservir la collecte et le prechargement : sur une machine faible, avaler le travail d'un coup fait
-- tomber le jeu a 5 FPS avant meme que le joueur ait joue une seconde.
local currentFPS = 60
local fpsConn: RBXScriptConnection? = nil
do
	local frameTimes: { number } = {}
	fpsConn = RunService.Heartbeat:Connect(function(dt: number)
		table.insert(frameTimes, dt)
		if #frameTimes > 20 then
			table.remove(frameTimes, 1)
		end
		local sum = 0
		for _, t in ipairs(frameTimes) do
			sum += t
		end
		if sum > 0 then
			currentFPS = #frameTimes / sum
		end
	end)
end

-- ===== Boucle des tips =====
task.spawn(function()
	local tipIndex = 0
	local tipTimer = 0

	while animating do
		if currentAsset ~= "" then
			statusLabel.Text = currentAsset
		else
			tipTimer += 0.2
			if tipTimer >= 4 then
				tipTimer = 0
				tipIndex = (tipIndex % #TIPS) + 1
				statusLabel.Text = TIPS[tipIndex]
			end
		end
		task.wait(0.2)
	end
end)

-- ============================================================
-- L'animation demarre TOUT DE SUITE. On ne bloque pas sur game.Loaded ici : l'intro tourne pendant que Roblox
-- finit de charger le jeu en arriere-plan. C'est tout l'interet d'etre dans ReplicatedFirst.
-- ============================================================

-- ===== Collecte des assets a precharger (asservie au FPS) =====
local LOADABLE: { [string]: boolean } = {
	Decal = true,
	Texture = true,
	ImageLabel = true,
	ImageButton = true,
	MeshPart = true,
	SpecialMesh = true,
	FileMesh = true,
	Sound = true,
	Animation = true,
	ParticleEmitter = true,
	Shirt = true,
	Pants = true,
	ShirtGraphic = true,
	SurfaceAppearance = true,
}
local seen: { [Instance]: boolean } = {}
local assetsToLoad: { Instance } = {}
local collectFinished = false

local TARGET_FPS = 25 -- on garde le joueur au-dessus de ca pendant la collecte

local function collect(container: Instance)
	local descendants = container:GetDescendants()
	local i = 1
	local n = #descendants

	while i <= n do
		-- Taille du paquet selon le FPS mesure en direct : bon FPS, on avance vite ; mauvais FPS, on touche a
		-- peine.
		local chunk: number
		if currentFPS >= TARGET_FPS then
			chunk = 40
		elseif currentFPS >= 15 then
			chunk = 12
		else
			chunk = 4
		end

		local processed = 0
		while i <= n and processed < chunk do
			local inst = descendants[i]
			if LOADABLE[inst.ClassName] and not seen[inst] then
				seen[inst] = true
				assetsToLoad[#assetsToLoad + 1] = inst
			end
			i += 1
			processed += 1
		end

		-- On cede le thread. FPS tres bas ou skip demande : on respire une frame de plus.
		RunService.Heartbeat:Wait()
		if currentFPS < 15 or skipRequested then
			RunService.Heartbeat:Wait()
		end
	end
end

task.spawn(function()
	collect(game:GetService("ReplicatedStorage"))
	collect(game:GetService("StarterGui"))
	-- SoundService : les sons du jeu vivent la, pas dans ReplicatedStorage. Sans cette ligne, le tout premier
	-- son de chaque type se telecharge au moment ou on le joue, et il manque.
	collect(game:GetService("SoundService"))
	collectFinished = true
end)

-- ===== Sequence d'animation du logo =====
local function playIntroSequence()
	if skipRequested then
		return
	end

	playSound(SOUND_LOGO_POP, 0.3)

	-- 1. L'impact : le logo arrive en s'ecrasant, large et aplati.
	local splat = TweenService:Create(iconLogo, LOGO_SLIME_SPLAT, { Size = logoSize(LOGO_SPLAT_X, LOGO_SPLAT_Y) })
	splat:Play()
	splat.Completed:Wait()
	if skipRequested then
		return
	end

	-- 2. Le rebond : la matiere repart dans l'autre sens, haute et fine.
	local stretch =
		TweenService:Create(iconLogo, LOGO_SLIME_STRETCH, { Size = logoSize(LOGO_STRETCH_X, LOGO_STRETCH_Y) })
	stretch:Play()
	stretch.Completed:Wait()
	if skipRequested then
		return
	end

	-- 3. Le tremblement final. On ne l'ATTEND PAS : l'impact visuel est deja passe, et bloquer ici une seconde
	-- de plus decalerait l'onde de choc bien apres le moment ou le logo a "tape". Le logo gigote donc pendant
	-- que le cercle part, ce qui lie les deux au lieu de les mettre a la queue leu leu.
	TweenService:Create(iconLogo, LOGO_SLIME_SETTLE, { Size = iconLogoSize }):Play()

	-- Cercle : onde de choc
	cercleImage.Size = UDim2.new(0, 0, 0, 0)
	cercleImage.ImageTransparency = 0
	TweenService:Create(cercleImage, TWEEN_SHOCK, {
		Size = UDim2.fromScale(1.509, 2.685),
		ImageTransparency = 1,
	}):Play()
	task.delay(0.3, function()
		if skipRequested then
			return
		end
		playSound(SOUND_SHOCKWAVE)
	end)
end

playIntroSequence()
-- Les points ne rebondissent qu'APRES l'intro : pendant l'apparition du logo ils lui voleraient la vedette.
startBounceDots()
-- Meme raison pour le reflet : pendant l'impact du slime, un balayage en plus rend l'image illisible. Le
-- tremblement final, lui, tourne encore ici, et le reflet par dessus rend bien.
startLogoShine()

-- ===== On attend que le jeu soit charge avant de finaliser la sortie =====
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- ===== Prechargement (continue en fond meme apres un skip) =====
local startTime = os.clock()
local preloadFinished = false

task.spawn(function()
	while not collectFinished do
		RunService.Heartbeat:Wait()
	end

	-- Apres un skip, le joueur JOUE : on precharge par petits lots espaces pour ne pas hacher sa partie.
	-- Sinon on peut pousser plus fort, personne n'est encore aux commandes.
	local batchSize = if skipRequested then 20 else 15
	local i = 1
	local n = #assetsToLoad
	while i <= n do
		local batch: { Instance } = {}
		for j = i, math.min(i + batchSize - 1, n) do
			batch[#batch + 1] = assetsToLoad[j]
		end
		-- pcall obligatoire : PreloadAsync leve sur un asset invalide ou une coupure reseau, et une erreur ici
		-- laisserait l'ecran de chargement bloque pour toujours.
		pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)
		i += #batch

		if skipRequested then
			task.wait(0.25)
		else
			RunService.Heartbeat:Wait()
			if currentFPS < TARGET_FPS then
				task.wait(0.05)
			end
		end
	end
	preloadFinished = true
end)

-- ===== Sortie : quand tout est pret ET que la duree minimale est passee, OU sur skip =====
while not skipRequested do
	if preloadFinished and os.clock() - startTime >= MIN_DURATION then
		break
	end
	RunService.Heartbeat:Wait()
end

animating = false
statusLabel.Text = "Ready"

task.wait(if skipRequested then 0 else 0.4)

-- ============================================================
-- ===== SORTIE =====
-- ============================================================

-- Les textes s'effacent en premier : ils se lisent, donc les faire disparaitre en meme temps que le reste
-- donne une bouillie illisible pendant une demi-seconde.
local function fadeText(label: TextLabel)
	TweenService:Create(label, TWEEN_TEXT_FADE, { TextTransparency = 1 }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TWEEN_TEXT_FADE, { Transparency = 1 }):Play()
	end
end

fadeText(statusLabel)
fadeText(gameVersion)

skipButton.Active = false
skipButton.AutoButtonColor = false

-- Tout sort en FONDU, sans changement de taille : rien n'est ecrase ni aspire. L'ecran s'efface, ce qui se lit
-- comme une transition et non comme un evenement.
TweenService:Create(skipButton, TWEEN_EXIT, { ImageTransparency = 1 }):Play()
TweenService:Create(cercleImage, TWEEN_EXIT, { ImageTransparency = 1 }):Play()
TweenService:Create(iconLogo, TWEEN_EXIT, { ImageTransparency = 1 }):Play()

-- On coupe les boucles AVANT de faire disparaitre leurs cibles : un tween de sortie et une animation qui
-- tourne encore se disputent la meme propriete, et le point continue de sauter en s'effacant.
stopBounceDots()
stopLogoShine()
for _, d in ipairs(dots) do
	TweenService:Create(d, TWEEN_EXIT, { BackgroundTransparency = 1 }):Play()
end

task.wait(0.35)

-- Fondu final du fond.
TweenService:Create(fontTile, TWEEN_FADE, { ImageTransparency = 1 }):Play()
fadeText(copyRight)

-- Un seul tween pour tout le bloc. C'est la raison d'etre du CanvasGroup : sans lui il faudrait citer chaque
-- element un par un, et tout ce qu'on ajoutera plus tard resterait affiche.
local holderFade = TweenService:Create(canvasGroup, TWEEN_FADE, { GroupTransparency = 1 })
holderFade:Play()
holderFade.Completed:Wait()

-- ===== Nettoyage =====
-- Ces connexions vivent sur RunService, pas sur le GUI : detruire le GUI ne les coupe pas. Sans ce bloc elles
-- tourneraient toute la session sur des instances mortes.
if heartbeatConn then
	heartbeatConn:Disconnect()
	heartbeatConn = nil
end
if fpsConn then
	fpsConn:Disconnect()
	fpsConn = nil
end

loadingGui:Destroy()
restoreCoreGuis()

if loadingMusic then
	-- Fondu sonore : couper net une musique au moment ou l'image disparait s'entend comme un bug.
	local fadeOut = TweenService:Create(loadingMusic, TWEEN_FADE, { Volume = 0 })
	fadeOut:Play()
	fadeOut.Completed:Wait()
	loadingMusic:Destroy()
end
