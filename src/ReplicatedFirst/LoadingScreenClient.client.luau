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

-- Lueur posee DERRIERE le logo, qui vacille comme une torche dans la nuit.
local GLOW_IMAGE = "rbxassetid://108057663284590"
local GLOW_SCALE = 1.8 -- taille par rapport au logo : une lueur deborde de ce qu'elle eclaire, sinon c'est un cadre
local GLOW_TRANSPARENCY = 0.6 -- transparence MOYENNE, autour de laquelle la flamme monte et descend
local GLOW_FLICKER = 0.18 -- amplitude du vacillement : de combien la transparence bat autour de la moyenne

-- ===== Zoom de reveal (fin du loading) =====
-- La camera part LOIN sur le joueur (plan large), puis zoome sur lui pendant que l'ecran se leve.
local ZOOM_ENABLED = true
local ZOOM_WAIT = 3 -- attente max du personnage avant de renoncer au zoom, en secondes
local ZOOM_DURATION = 1.5 -- duree du zoom, en secondes
local ZOOM_FAR_DIST = 42 -- recul de depart, en studs : le plan large
local ZOOM_FAR_HEIGHT = 26 -- hauteur de depart : une vue haute et large
-- Pas de position d'arrivee reglee ici : le zoom finit PILE sur la camera de jeu (Roblox), capturee avant qu'on
-- prenne la main. C'est ce qui evite le saut ("TAC") au retour a la camera par defaut.
local ZOOM_FOCUS_HEIGHT = 2 -- point vise du plan large, au-dessus des pieds du joueur
local TWEEN_ZOOM = TweenInfo.new(ZOOM_DURATION, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

-- ===== Lueur derriere le logo =====
-- Posee DANS le loadHolder, donc dans le CanvasGroup : le fondu de sortie l'emporte avec tout le reste, sans
-- qu'on ait a la citer. Centree sur le logo, ZIndex juste en dessous pour rester derriere lui.
-- On lit la taille du logo MAINTENANT : l'intro (slime) ne l'ecrase qu'a son lancement, bien plus tard, donc on
-- capte ici sa taille finale reglee dans Studio.
local logoGlow = Instance.new("ImageLabel")
logoGlow.Name = "LogoGlow"
logoGlow.BackgroundTransparency = 1
logoGlow.AnchorPoint = iconLogo.AnchorPoint
logoGlow.Position = iconLogo.Position
logoGlow.SizeConstraint = iconLogo.SizeConstraint
-- Plus grande que le logo dans les deux axes, en gardant Scale ET Offset : la taille Studio peut etre dans l'un
-- ou l'autre, ce facteur s'applique aux deux sans supposer lequel.
logoGlow.Size = UDim2.new(
	iconLogo.Size.X.Scale * GLOW_SCALE,
	iconLogo.Size.X.Offset * GLOW_SCALE,
	iconLogo.Size.Y.Scale * GLOW_SCALE,
	iconLogo.Size.Y.Offset * GLOW_SCALE
)
logoGlow.Image = GLOW_IMAGE
logoGlow.ImageTransparency = GLOW_TRANSPARENCY
-- Un cran sous le logo : derriere lui, mais devant le fond. Si la lueur se retrouvait cachee par le fond, c'est
-- ce ZIndex qu'il faudrait remonter.
logoGlow.ZIndex = iconLogo.ZIndex - 1
logoGlow.Parent = loadHolder

-- Petite echelle a part, pour faire respirer le halo sans toucher a sa taille de base.
local glowScale = Instance.new("UIScale")
glowScale.Parent = logoGlow

-- VACILLEMENT DE TORCHE. math.noise donne une variation ORGANIQUE, pas un clignotement regulier : deux octaves
-- se superposent, une houle lente et un frisson rapide, comme une vraie flamme. La transparence bat autour de
-- sa moyenne, et le halo respire un peu avec.
-- AUTO-NETTOYANT : a la sortie, le loadHolder est detruit, le glow perd son parent, et la boucle se coupe seule.
-- Pas besoin de la citer dans la sequence de sortie, qui a deja assez a gerer.
local glowT0 = os.clock()
local glowConn: RBXScriptConnection? = nil
glowConn = RunService.Heartbeat:Connect(function()
	if not logoGlow.Parent then
		if glowConn then
			glowConn:Disconnect()
			glowConn = nil
		end
		return
	end
	local t = os.clock() - glowT0
	local flick = math.noise(t * 1.6) + math.noise(t * 7 + 50) * 0.5
	logoGlow.ImageTransparency = math.clamp(GLOW_TRANSPARENCY + flick * GLOW_FLICKER, 0, 1)
	glowScale.Scale = 1 + flick * 0.05
end)

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

-- ===== Tweens preconfigures =====
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
-- C'est CE tween qui fait le "prolonge" : Elastic sur plus de deux secondes, le logo continue de gigoter
-- longtemps apres avoir atteint sa taille finale. L'Elastic de Roblox a un nombre d'oscillations FIXE : monter
-- la duree ne rajoute pas de rebonds, elle les ETALE. Un tremblement plus lent qui traine, pas plus de coups.
-- C'est le seul chiffre a toucher pour faire durer le rebond plus ou moins longtemps.
local LOGO_SLIME_SETTLE = TweenInfo.new(2.2, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

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

buildLogoShine()

-- ===== Etats de depart : tout a zero =====
iconLogo.Size = UDim2.new(0, 0, 0, 0)
-- Onde de choc retiree : on cache le cercle une fois pour toutes plutot que de l'animer.
cercleImage.Visible = false
skipButton.ImageTransparency = 1

-- ===== Skip (bouton + touche Echap) =====
local function skipLoading()
	if skipRequested then
		return
	end
	skipRequested = true
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

	-- 3. Le tremblement final. On ne l'ATTEND PAS : l'impact visuel est deja passe, bloquer ici n'apporterait
	-- rien. Le logo gigote donc pendant que la suite de la sequence continue.
	TweenService:Create(iconLogo, LOGO_SLIME_SETTLE, { Size = iconLogoSize }):Play()
end

playIntroSequence()
-- Le reflet ne part qu'APRES l'intro : pendant l'impact du slime, un balayage en plus rend l'image illisible.
-- Le tremblement final, lui, tourne encore ici, et le reflet par dessus rend bien.
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

statusLabel.Text = "Ready"

task.wait(if skipRequested then 0 else 0.4)

-- ============================================================
-- ===== SORTIE =====
-- ============================================================

-- ===== ZOOM DE REVEAL =====
-- La camera part LOIN sur le joueur (plan large) et zoomera sur lui pendant que l'ecran se leve. On la met en
-- place DES MAINTENANT, cachee derriere l'ecran encore plein : quand le fondu commencera, le plan large est deja
-- la, et il n'y a aucun a-coup au premier instant du reveal.
--
-- Le personnage peut ne pas etre pret : on l'attend un court instant, et si vraiment il n'arrive pas, on renonce
-- au zoom plutot que de bloquer le reveal. Mieux vaut un reveal sans zoom qu'un ecran fige.
local camera = workspace.CurrentCamera

-- Plan derriere le joueur, dans le sens ou il regarde. RECALCULE a chaque appel depuis la position COURANTE de
-- l'ancre : c'est ce qui permet a la camera de SUIVRE un joueur qui bouge pendant le zoom, au lieu de viser un
-- point fige. La camera de jeu se posera au meme endroit, donc rendre la main a la fin ne fait pas sauter l'image.
local function zoomShot(anchor: BasePart, dist: number, height: number): CFrame
	local focus = anchor.Position + Vector3.new(0, ZOOM_FOCUS_HEIGHT, 0)
	local back = anchor.CFrame.LookVector
	return CFrame.lookAt(focus - back * dist + Vector3.new(0, height, 0), focus)
end

local zoomRoot: BasePart? = nil
-- Depart (plan large) et arrivee (camera de jeu capturee) du zoom. Fixes une fois pour toutes : le joueur est
-- verrouille pendant le reveal, donc ni l'un ni l'autre ne bouge, et on lerp simplement de l'un a l'autre.
local zoomFarCFrame: CFrame? = nil
local zoomGameCFrame: CFrame? = nil
do
	local deadline = os.clock() + ZOOM_WAIT
	local root: BasePart? = nil
	repeat
		local char = player.Character
		local found = char and char:FindFirstChild("HumanoidRootPart")
		if found and found:IsA("BasePart") then
			root = found
			break
		end
		RunService.Heartbeat:Wait()
	until os.clock() >= deadline

	if ZOOM_ENABLED and camera and root then
		zoomRoot = root
		-- ARRIVEE DU ZOOM = la camera de jeu (Roblox, Custom) telle qu'elle est MAINTENANT, capturee AVANT qu'on
		-- prenne la main. Le zoom finira pile dessus, donc le retour a Custom a la fin ne fait aucun saut ("TAC").
		-- Valable parce que le joueur est verrouille juste apres : sa position, et donc celle de la camera de jeu,
		-- ne bouge plus jusqu'a la fin du reveal.
		zoomGameCFrame = camera.CFrame
		-- ON BLOQUE LE JOUEUR le temps du reveal, en ancrant son root. Sinon, s'il se met a marcher ET tourner
		-- pendant le zoom (il est impatient), le code re-cadre sur lui a chaque frame et ECRASE sa rotation : le
		-- suivi parait "strict", saccade, moche. Immobile, il n'y a plus rien a ecraser et le cinematique reste
		-- propre. On lui rend le controle a la toute fin, quand la camera de jeu reprend la main.
		root.Anchored = true
		zoomFarCFrame = zoomShot(root, ZOOM_FAR_DIST, ZOOM_FAR_HEIGHT)
		camera.CameraType = Enum.CameraType.Scriptable
		-- Plan large en place tout de suite, cache derriere l'ecran encore plein : aucun a-coup au premier reveal.
		camera.CFrame = zoomFarCFrame
	end
end

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
TweenService:Create(iconLogo, TWEEN_EXIT, { ImageTransparency = 1 }):Play()

-- On coupe la boucle du logo AVANT de faire disparaitre sa cible : un tween de sortie et une animation qui
-- tourne encore se disputent la meme propriete.
stopLogoShine()

task.wait(0.35)

-- Fondu final du fond.
TweenService:Create(fontTile, TWEEN_FADE, { ImageTransparency = 1 }):Play()
fadeText(copyRight)

-- Un seul tween pour tout le bloc. C'est la raison d'etre du CanvasGroup : sans lui il faudrait citer chaque
-- element un par un, et tout ce qu'on ajoutera plus tard resterait affiche.
local holderFade = TweenService:Create(canvasGroup, TWEEN_FADE, { GroupTransparency = 1 })
holderFade:Play()
-- LE ZOOM part EN MEME TEMPS que le fondu : le joueur decouvre le plan large qui se resserre sur lui. Le zoom
-- dure plus longtemps que le fondu, donc il continue une fois l'ecran entierement leve.
--
-- BOUCLE PAR FRAME avec l'easing de TWEEN_ZOOM (GetValue). On lerp du plan large vers la CAMERA DE JEU capturee.
-- Deux CFrame fixes : le joueur est verrouille, rien ne bouge, donc pas besoin de recalculer depuis lui a chaque
-- frame. Et finir pile sur la camera de jeu est ce qui supprime le saut au retour a Custom.
local zoomActive = zoomRoot ~= nil and camera ~= nil and zoomFarCFrame ~= nil and zoomGameCFrame ~= nil
local zoomDone = not zoomActive
if zoomActive then
	local cam = camera :: Camera
	local far = zoomFarCFrame :: CFrame
	local target = zoomGameCFrame :: CFrame
	task.spawn(function()
		local duration = TWEEN_ZOOM.Time
		local start = os.clock()
		while true do
			local raw = if duration > 0 then math.clamp((os.clock() - start) / duration, 0, 1) else 1
			local a = TweenService:GetValue(raw, TWEEN_ZOOM.EasingStyle, TWEEN_ZOOM.EasingDirection)
			cam.CFrame = far:Lerp(target, a)
			if raw >= 1 then
				break
			end
			-- RenderStepped : la camera doit etre posee AVANT le rendu de la frame, sinon elle traine d'une image.
			RunService.RenderStepped:Wait()
		end
		zoomDone = true
	end)
end
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

-- Le zoom fini, on rend la main a la camera de jeu (Custom). On ATTEND sa fin d'abord : couper avant ferait
-- sauter l'image de la position scriptee a celle de Roblox. Comme l'arrivee du zoom est calee sur la distance
-- de jeu, ce passage est deja quasi invisible.
if zoomActive then
	while not zoomDone do
		RunService.Heartbeat:Wait()
	end
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
	-- Reveal fini : on rend au joueur le controle qu'on lui avait retire (voir l'ancrage plus haut).
	if zoomRoot and zoomRoot.Parent then
		zoomRoot.Anchored = false
	end
end

if loadingMusic then
	-- Fondu sonore : couper net une musique au moment ou l'image disparait s'entend comme un bug.
	local fadeOut = TweenService:Create(loadingMusic, TWEEN_FADE, { Volume = 0 })
	fadeOut:Play()
	fadeOut.Completed:Wait()
	loadingMusic:Destroy()
end
