--!strict
-- SELECTION DE PLOT (ecran d'entree, apres le chargement). Version SIMPLE : on montre l'UI HolderSelectPlot, la
-- camera ORBITE autour d'un plot (vue iso), et :
--   - clic sur ClaimButton  -> on affiche HolderListSelectSave + HolderStart (le reste viendra apres).
--   - clic sur StartButton   -> la camera GLISSE (tween) sur le joueur, on rend la main, on cache l'UI.
--
-- L'UI (LoadSaveUI) est faite A LA MAIN dans Studio (StarterGui). Ce controller ne fait que la LOGIQUE : visibilite,
-- camera, branchement des boutons. Rien de sauvegarde pour l'instant : on valide le flux d'abord.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local UIManager = require(ReplicatedStorage.Modules.UI.Core.UIManager)
local HudSlide = require(ReplicatedStorage.Modules.UI.Core.HudSlide)
local TileField = require(ReplicatedStorage.Modules.UI.Core.TileField)
local LoadingOverlay = require(ReplicatedStorage.Modules.UI.Core.LoadingOverlay)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local PlotConfigs = require(ReplicatedStorage.Modules.Configs.PlotConfigs)
local SideNotificationHandler = require(ReplicatedStorage.Modules.UI.Notification.SideNotificationHandler)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local LoadCompanyController = require(script.Parent.LoadCompanyController)

local PlotSelectController = {}

local player = Players.LocalPlayer

local UI_NAME = "LoadSaveUI"
-- Swoosh joue quand on CHANGE de plot (Next/Prev). Chemin sous SoundService (SoundService.Sounds.UI.PassingSound).
local PASSING_SOUND = { "Sounds", "UI", "PassingSound" }

-- Camera d'orbite (vue iso). A REGLER a l'oeil selon la taille du plot.
local ORBIT_DISTANCE = 100 -- recul horizontal (plus grand = plus loin)
local ORBIT_HEIGHT = 95 -- hauteur au-dessus du centre (plus grand par rapport a la distance = plus du dessus / iso)
local ORBIT_SPEED = 12 -- degres par seconde (lent = elegant)
local ORBIT_LOOK_UP = 4 -- on vise un peu au-dessus du sol pour bien cadrer le plot
local ORBIT_CENTER_LERP = 3 -- vitesse de glissement du centre d'un plot a l'autre au Next/Prev (grand = plus sec)

-- Camera mise a jour via BindToRenderStep a la priorite Camera, PAS via RenderStepped:Connect. RenderStepped se
-- declenche au tout debut de l'etape de rendu ; a la priorite Camera on ecrit la CFrame au moment ou Roblox met
-- normalement la camera a jour, juste avant le rendu. Sans ca, la CFrame est "en avance" d'un cran sur le rendu et
-- ca micro-saccade des qu'un repere rapide bouge a l'ecran (le curseur). Cf note de CameraEffects sur la CFrame.
local ORBIT_BIND = "LeafiaPlotOrbit"

-- Glisse de fin orbite -> joueur au clic Start. Sine InOut = depart ET arrivee DOUX (pas de coup sec ni de plongeon).
local CAM_TWEEN = TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
-- PLANCHER d'affichage du rideau de chargement, compte depuis le clic CREATE. Volontairement long : ca pose un vrai
-- temps de chargement facon Sims, meme si techniquement le plot est deja pret derriere.
local LOADING_MIN = 12
-- Compte a rebours SUPPLEMENTAIRE, lance seulement une fois le personnage en place.
-- Le plancher ci-dessus part du CLIC : si le personnage arrive tard (donnees, session lock, teleportation sur le plot),
-- ce plancher est deja presque ecoule quand il apparait, et le rideau se leve dans la seconde qui suit -> transition
-- brutale, et un rideau qui parait beaucoup trop court. Ce delai-la, lui, couvre TOUJOURS la mise en place du
-- personnage, quelle que soit sa duree. Les deux se cumulent : on part au plus tard des deux.
local LOADING_AFTER_CHARACTER = 10
-- Temps pendant lequel le rideau reste seul a l'ecran AVANT qu'on demande au serveur ou aller.
-- Sur le chemin TELEPORT (nouvelle save -> tuto), le rideau n'a pas de fin a lui : la bascule de lieu le remplace.
-- Sans cette attente il n'aurait que le temps de son fondu d'entree, on ne verrait passer que la feuille.
local START_HOLD = 4
-- Valeurs MESUREES sur l'etat de repos reel de la camera de jeu (Custom) : le tween doit finir la pour que Custom
-- n'ait RIEN a corriger au handoff (ni zoom, ni saut). Important : Custom REMET sa propre inclinaison au repos
-- (~15 deg), il ne garde PAS celle qu'on lui donne -- d'ou l'obligation de finir deja a cette inclinaison.
local CAM_END_DISTANCE = 12.5 -- zoom par defaut de Custom (mesure)
local CAM_END_PITCH = 15 -- inclinaison de repos de Custom (mesure)
local CAM_FOCUS_HEIGHT = 1.4 -- hauteur du point vise au-dessus du HRP (mesure : la ou Custom vise, ~la tete)

-- Depth of field (flou de profondeur) reserve a l'ECRAN DE SELECTION : on floute le lointain pour donner du relief au
-- plot pendant qu'on choisit. L'effet vit dans Lighting (pose dans Studio). Ce controller en est le SEUL pilote : il
-- l'allume a l'ouverture de l'ecran et l'ETEINT au Start -- sinon le joueur, tout proche (~12 studs, hors zone nette),
-- serait floute. Valeurs du joueur, reglables ici.
local DOF_FOCUS_DISTANCE = 116.98
local DOF_IN_FOCUS_RADIUS = 37.735
local DOF_FAR_INTENSITY = 1
local DOF_NEAR_INTENSITY = 1

-- MISE EN PAGE MOBILE (petit ecran tactile) de l'ecran de plot : valeurs tunees par le joueur dans l'emulateur telephone.
-- Le code les FORCE sur tactile ; sur PC il ne touche a rien (la maquette Studio reste la reference PC). Chaque entree :
-- scope = ou chercher l'element ("holder" = dans HolderSelectPlot, "desc" = dans DescriptionHolder, "sub" = dans SubHolder),
-- puis les proprietes a forcer (anchor / position / size, chacune optionnelle).
type MobileTweak = { scope: string, name: string, anchor: Vector2?, position: UDim2?, size: UDim2?, transparency: number? }
local MOBILE_LAYOUT: { MobileTweak } = {
	{ scope = "holder", name = "NextButton", anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.9, 0.5), size = UDim2.fromScale(0.057, 0.101) },
	{ scope = "holder", name = "PreviousButton", anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.1, 0.5), size = UDim2.fromScale(0.057, 0.101) },
	{ scope = "holder", name = "PointPageVisualHolder", position = UDim2.fromScale(0.5, 0.78) },
	{ scope = "holder", name = "DescriptionHolder", position = UDim2.fromScale(0.5, 1.02), size = UDim2.fromScale(1.01, 0.2), transparency = 1 },
	{ scope = "desc", name = "SubHolder", anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.469), size = UDim2.fromScale(1, 0.937) },
	{ scope = "sub", name = "ClaimButton", position = UDim2.fromScale(0.865, 0.502), size = UDim2.fromScale(0.19, 0.781) },
	{ scope = "desc", name = "DescriptionText", anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.38, 0.5), size = UDim2.fromScale(0.625, 0.448) },
	{ scope = "desc", name = "Icon", position = UDim2.fromScale(0.04, 0.45), size = UDim2.fromScale(0.6, 0.6) },
}

-- AvailablePlotLabel : quand le plot est CLAIMABLE (pour l'instant : toujours), son fond PULSE doucement entre deux
-- verts. Tween qui boucle en reverse (aller-retour). Lance sur l'ecran de plot, COUPE des qu'on le quitte.
local PLOT_GREEN_A = Color3.fromRGB(41, 172, 26)
local PLOT_GREEN_B = Color3.fromRGB(93, 220, 34)
local PLOT_PULSE_TWEEN = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

-- Barres de PAGE (PointPageVisualHolder) : une par plot, clonee de Templates.PointSelectiveFrameTemplate. Celle du
-- plot SELECTIONNE est jaune et large, les autres blanches et etroites. Elles changent en douceur au Next/Prev.
local PAGE_SELECTED_COLOR = Color3.fromRGB(255, 204, 52)
local PAGE_SELECTED_SIZE = UDim2.fromScale(0.688, 0.433)
local PAGE_UNSELECTED_COLOR = Color3.fromRGB(255, 255, 255)
local PAGE_UNSELECTED_SIZE = UDim2.fromScale(0.34, 0.433)
local PAGE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Musique de jeu (posee par l'ecran de chargement, nommee "GameMusic" sous SoundService) : on la fait FONDRE a 0 a
-- l'entree dans le jeu (Start), pour un moment de silence quand la camera se pose sur le joueur (etat voulu).
local MUSIC_NAME = "GameMusic"
local MUSIC_FADE = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

-- Notification LATERALE (riche, facon Sims) a l'entree dans le jeu : renvoie le joueur vers sa boite aux lettres (le
-- point d'entree des chantiers). Apres un court delai, pour le laisser se poser. Elle apparait FERMEE (le titre) et
-- s'ouvre au clic (la description). A ETOFFER quand le vrai courrier existera (le serveur la declenchera alors).
local WELCOME_DELAY = 1.5
local WELCOME_NOTIF: SideNotificationHandler.NotifData = {
	kind = "Info",
	title = "New Mail",
	description = "A new letter just landed in your mailbox. Open it to start your first job.",
	duration = 15,
}

local orbitBound = false -- l'orbite tourne-t-elle (BindToRenderStep pose) ?
local savedWalkSpeed: number? = nil
local currentPlot: Instance? = nil -- le plot pre-selectionne (pour teleporter le joueur sur sa RootSpawnPlayer au Start)
local plotList: { Instance } = {} -- tous les plots orbitables (Slot1, Slot2...), dans l'ordre
local plotCenters: { Vector3 } = {} -- leur centre pre-calcule (parallele a plotList) : Next/Prev lit ce cache, sans re-attendre
local plotIndex = 1 -- index du plot actuellement pre-selectionne dans plotList
-- Orbite : centre COURANT (lisse) qui GLISSE vers le centre VISE quand on change de plot, et angle CONTINU (jamais remis a 0).
local orbitCenter = Vector3.zero
local orbitTargetCenter = Vector3.zero
local orbitAngle = 0
local controls: any = nil -- ControlModule du PlayerModule, pour couper les deplacements pendant le plot-select
-- References d'UI remplies dans setup (elles vivent tant que la ScreenGui vit).
local titleLabel: TextLabel? = nil -- TitleNamePlot : nom du plot
local descLabel: TextLabel? = nil -- DescriptionText : la petite description
local plotMaxLabel: TextLabel? = nil -- PlotMaxMinText : "PLOT x / y - SIZE - N TILES"
local stepLabel: TextLabel? = nil -- AmountStep : "STEP : 1 / 2" (plot) ou "2 / 2" (save)
local availableLabel: GuiObject? = nil -- AvailablePlotLabel : le cadre vert qui pulse quand claimable
local pulseTween: Tween? = nil
local pageBars: { GuiObject } = {} -- barres de page (une par plot), parallele a plotList
local tileHandle: TileField.Handle? = nil -- fond en tuiles (plot-select) : cache pendant LoadCompany, coupe au Start
-- HUD a faire GLISSER hors ecran pendant l'ecran de selection. name = le HOLDER a bouger (trouve dans PlayerGui) ;
-- hiddenY = ou il va en Y (scale) une fois cache (negatif = par le haut). Ajouter d'autres holders ici au besoin.
local HUD_SLIDES = { { name = "HolderCurrency", hiddenY = -0.5 } }

-- FindFirstChild recursif : robuste si la hierarchie exacte du GUI bouge un peu dans Studio.
local function deep(root: Instance, name: string): Instance?
	return root:FindFirstChild(name, true)
end

-- Branche un clic, que l'element soit un vrai bouton (GuiButton) ou une simple Frame.
local function onClick(obj: Instance, fn: () -> ())
	if obj:IsA("GuiButton") then
		obj.Activated:Connect(fn)
	elseif obj:IsA("GuiObject") then
		obj.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				fn()
			end
		end)
	end
end

-- Centre d'un plot = son PrimaryGround (part-sol, nom propre a un plot). C'est AUSSI le marqueur "c'est un plot" a
-- l'enumeration : un enfant sans PrimaryGround (decor...) renvoie nil et n'est pas orbitable. FindFirstChild suffit :
-- on n'arrive ici qu'apres game.Loaded (l'ecran de chargement l'attend) et apres avoir attendu le dossier Plots.
local function plotCenter(plot: Instance): Vector3?
	local ground = plot:FindFirstChild("PrimaryGround")
	if ground and ground:IsA("BasePart") then
		return ground.Position
	end
	return nil
end

local function stopOrbit()
	if orbitBound then
		RunService:UnbindFromRenderStep(ORBIT_BIND)
		orbitBound = false
	end
end

-- L'orbite lit un centre COURANT (orbitCenter) qui GLISSE vers orbitTargetCenter. Changer de plot ne fait donc que
-- deplacer la cible : la camera vole doucement vers le nouveau plot en continuant de tourner, sans coupure.
local function startOrbit()
	if orbitBound then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(ORBIT_BIND, Enum.RenderPriority.Camera.Value, function(dt: number)
		orbitCenter = orbitCenter:Lerp(orbitTargetCenter, math.min(1, ORBIT_CENTER_LERP * dt))
		orbitAngle += math.rad(ORBIT_SPEED) * dt
		local offset = Vector3.new(math.cos(orbitAngle) * ORBIT_DISTANCE, ORBIT_HEIGHT, math.sin(orbitAngle) * ORBIT_DISTANCE)
		local target = orbitCenter + Vector3.new(0, ORBIT_LOOK_UP, 0)
		camera.CFrame = CFrame.lookAt(orbitCenter + offset, target)
	end)
	orbitBound = true
end

-- Pre-selectionne le plot d'index donne (avec wrap Next/Prev) : deplace la CIBLE de l'orbite dessus, retient le plot
-- pour Claim/Start, et joue le swoosh. `instant` (au demarrage) pose le centre direct et ne sonne pas.
local function goToPlotIndex(index: number, instant: boolean?)
	if #plotList == 0 then
		return
	end
	local newIndex = (index - 1) % #plotList + 1 -- modulo Lua = a plancher, donc wrap correct dans les DEUX sens
	local didChange = newIndex ~= plotIndex
	plotIndex = newIndex
	local plot = plotList[plotIndex]
	currentPlot = plot
	orbitTargetCenter = plotCenters[plotIndex]

	-- Textes du plot (nom, description, "PLOT x / y") depuis PlotConfigs, keye sur le nom du Slot. Plus de size / tiles :
	-- tous les plots font la meme taille, donc ce label n'indique plus que quel plot on regarde, sur combien.
	local info = PlotConfigs.get(plot.Name)
	if titleLabel then
		titleLabel.Text = info.name
	end
	if descLabel then
		descLabel.Text = info.description
	end
	if plotMaxLabel then
		plotMaxLabel.Text = string.format("PLOT %d / %d", plotIndex, #plotList)
	end

	-- Barres de page : celle du plot courant devient jaune + large, les autres blanches + etroites.
	for i, bar in ipairs(pageBars) do
		local selected = i == plotIndex
		local size = if selected then PAGE_SELECTED_SIZE else PAGE_UNSELECTED_SIZE
		local color = if selected then PAGE_SELECTED_COLOR else PAGE_UNSELECTED_COLOR
		if instant then
			bar.Size = size
			bar.BackgroundColor3 = color
		else
			TweenService:Create(bar, PAGE_TWEEN, { Size = size, BackgroundColor3 = color }):Play()
		end
	end

	if instant then
		orbitCenter = orbitTargetCenter
	elseif didChange then
		SoundUtils.play(PASSING_SOUND)
	end
end

-- ControlModule du PlayerModule (deplacements). On la COUPE pendant le plot-select : sinon appuyer sur une touche met
-- humanoid.MoveDirection, et CameraController elargit le FOV en croyant qu'on bouge -> la camera "recule".
local function getControls(): any
	if controls then
		return controls
	end
	local ps = player:FindFirstChild("PlayerScripts")
	local pm = ps and ps:FindFirstChild("PlayerModule")
	if pm then
		local ok, result = pcall(function()
			return require(pm):GetControls()
		end)
		if ok then
			controls = result
		end
	end
	return controls
end

-- Enregistre les HUD a glisser UNE FOIS, en capturant leur position VISIBLE (a appeler quand ils sont a leur place).
-- Ensuite HudSlide.hideAll / showAll les fait coulisser hors ecran / en place.
local hudRegistered = false
local function registerHuds()
	if hudRegistered then
		return
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	for _, cfg in ipairs(HUD_SLIDES) do
		local element = playerGui:FindFirstChild(cfg.name, true)
		if element and element:IsA("GuiObject") then
			HudSlide.register(element, cfg.hiddenY)
		end
	end
	hudRegistered = true
end

-- Empeche le joueur de bouger pendant qu'il choisit (camera sur le plot, pas sur lui) ET coupe la reaction FOV.
local function freeze()
	local ctrls = getControls()
	if ctrls then
		ctrls:Disable()
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		savedWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 0
	end
end

local function unfreeze()
	local ctrls = getControls()
	if ctrls then
		ctrls:Enable()
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and savedWalkSpeed then
		humanoid.WalkSpeed = savedWalkSpeed
	end
	savedWalkSpeed = nil
end

-- Pulse vert de AvailablePlotLabel (plot claimable). Tween en reverse infini entre les deux verts. Lance seulement
-- sur l'ecran de plot, COUPE des qu'on le quitte (regle : pas d'effet en boucle sur une UI cachee).
local function startPulse()
	if pulseTween or not availableLabel then
		return
	end
	availableLabel.BackgroundColor3 = PLOT_GREEN_A
	local tween = TweenService:Create(availableLabel, PLOT_PULSE_TWEEN, { BackgroundColor3 = PLOT_GREEN_B })
	pulseTween = tween
	tween:Play()
end

local function stopPulse()
	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end
end

-- Bascule d'ecran : UIManager fait l'exclusivite, et on met a jour le "STEP : x / 2" + le pulse (actif seulement
-- sur l'ecran de plot). Passer TOUJOURS par ici pour changer d'ecran, jamais UIManager.show directement.
local function showScreen(name: string)
	UIManager.show(name)
	local onPlot = name == "PlotSelect"
	if stepLabel then
		stepLabel.Text = if onPlot then "STEP : 1 / 2" else "STEP : 2 / 2"
	end
	if onPlot then
		startPulse()
	else
		stopPulse()
	end
end


-- Fond la musique de jeu a 0 (moment de silence a l'entree). Elle vit sous SoundService, posee par le loading screen.
local function fadeOutMusic()
	local music = SoundService:FindFirstChild(MUSIC_NAME)
	if music and music:IsA("Sound") then
		TweenService:Create(music, MUSIC_FADE, { Volume = 0 }):Play()
	end
end

-- Allume (avec les valeurs voulues) ou eteint le depth of field de l'ecran de selection. On applique les valeurs a
-- l'allumage seulement : au Start on se contente d'eteindre. Effet absent = warn UNE fois (a l'allumage).
local function setDof(on: boolean)
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if not dof then
		if on then
			warn("[PlotSelect] DepthOfFieldEffect introuvable dans Lighting : pas de flou sur l'ecran de selection.")
		end
		return
	end
	if on then
		dof.FocusDistance = DOF_FOCUS_DISTANCE
		dof.InFocusRadius = DOF_IN_FOCUS_RADIUS
		dof.FarIntensity = DOF_FAR_INTENSITY
		dof.NearIntensity = DOF_NEAR_INTENSITY
	end
	dof.Enabled = on
end

-- Applique la mise en page MOBILE (rien sur PC). A appeler UNE fois au setup. On cherche chaque element par SCOPE pour
-- ne pas attraper un homonyme ailleurs dans le GUI. Le UICorner du DescriptionHolder est retire (coins arrondis coupes
-- au bord de l'ecran sur petit ecran).
local function applyMobileLayout(gui: ScreenGui)
	-- TouchEnabled SEUL (pas "and not KeyboardEnabled") : dans l'emulateur Studio le PC garde son clavier physique, donc
	-- KeyboardEnabled reste TRUE et "not KeyboardEnabled" bloquait TOUT le layout mobile en test. TouchEnabled est vrai
	-- dans l'emulateur ET sur vrai mobile.
	if not UserInputService.TouchEnabled then
		return
	end
	local holder = deep(gui, "HolderSelectPlot")
	if not (holder and holder:IsA("GuiObject")) then
		warn("[PlotSelect] HolderSelectPlot introuvable : pas d'ajustement mobile.")
		return
	end
	local desc = holder:FindFirstChild("DescriptionHolder", true)
	local sub = desc and desc:FindFirstChild("SubHolder", true)
	local roots: { [string]: Instance? } = { holder = holder, desc = desc, sub = sub }
	for _, tweak in ipairs(MOBILE_LAYOUT) do
		local root = roots[tweak.scope]
		local el = root and root:FindFirstChild(tweak.name, true)
		if el and el:IsA("GuiObject") then
			if tweak.anchor then
				el.AnchorPoint = tweak.anchor
			end
			if tweak.position then
				el.Position = tweak.position
			end
			if tweak.size then
				el.Size = tweak.size
			end
			if tweak.transparency then
				el.BackgroundTransparency = tweak.transparency
			end
		end
	end
	local corner = desc and desc:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Destroy()
	end
end

-- Petit pop de bienvenue qui renvoie vers la boite aux lettres, un instant apres l'entree dans le jeu.
local function notifyEntered()
	-- Retour en jeu : le playerlist ET le chat Roblox (coupes pendant le chargement ET le menu) reviennent. On les rallume
	-- ICI, une fois le rideau d'entree deja leve, pour ne pas les faire flasher par-dessus l'overlay (la CoreGui passe au-dessus).
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
	local chatWindow = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if chatWindow then
		chatWindow.Enabled = true
	end
	task.delay(WELCOME_DELAY, function()
		SideNotificationHandler.spawn(WELCOME_NOTIF)
	end)
end

-- StartButton : la camera GLISSE de l'orbite vers une vue 3e personne derriere le joueur, puis on rend la main a la
-- camera de jeu (Custom) et on cache l'UI.
-- ENTREE reelle dans le jeu (transition camera + handoff), jouee DERRIERE le rideau deja affiche par onStart.
local function enterGame(gui: ScreenGui)
	local loadingStart = os.clock()
	local function finishLoading()
		task.spawn(function()
			-- 1) ATTENDRE LE PERSONNAGE. Le rideau doit couvrir sa mise en place, pas se lever pile au moment ou il
			-- apparait. WaitForChild avec timeout sur la RootPart : a CharacterAdded le personnage est parente mais
			-- pas complet, ses parts arrivent quelques images plus tard.
			local character: Instance? = player.Character
			if not character then
				character = player.CharacterAdded:Wait()
			end
			if character then
				character:WaitForChild("HumanoidRootPart", 10)
			end
			-- 2) Puis le compte a rebours supplementaire, qui part de CE moment.
			task.wait(LOADING_AFTER_CHARACTER)
			-- 3) Et le plancher depuis le clic, conserve : si le personnage etait deja pret, le rideau reste quand
			-- meme affiche ce minimum.
			local elapsed = os.clock() - loadingStart
			if elapsed < LOADING_MIN then
				task.wait(LOADING_MIN - elapsed)
			end
			-- La notif de bienvenue part SEULEMENT quand le rideau a fini de reveler le jeu (sinon elle popait derriere).
			LoadingOverlay.hide(notifyEntered)
		end)
	end
	stopOrbit()
	stopPulse() -- on quitte l'ecran de plot : couper le pulse vert
	if tileHandle then -- on entre dans le jeu : couper le fond en tuiles
		tileHandle.stop()
		tileHandle = nil
	end
	setDof(false) -- on entre dans le jeu : couper le flou (sinon le joueur, tout proche, serait floute)
	fadeOutMusic() -- silence a l'entree dans le jeu (l'etat psychologique voulu)
	-- On DIT au serveur quel plot on a choisi : il valide et le retient (autorite -> n'ouvrir que SA boite aux lettres, etc.).
	if currentPlot then
		local selectRemote = RemoteSetup.getRemote("SelectPlot", "Plot")
		if selectRemote and selectRemote:IsA("RemoteEvent") then
			selectRemote:FireServer(currentPlot.Name)
		end
	end
	local camera = workspace.CurrentCamera
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (camera and character and hrp and hrp:IsA("BasePart")) then
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
		unfreeze()
		HudSlide.showAll() -- les HUD reglissent en place en entrant dans le jeu
		gui.Enabled = false
		finishLoading()
		return
	end
	-- Le joueur attendait dans une box noire sous la map : on le TELEPORTE sur le plot choisi (sa part RootSpawnPlayer)
	-- avant de descendre la camera sur lui. (Cote client pour l'instant : l'autorite serveur des plots viendra apres.)
	local spawn = currentPlot and currentPlot:FindFirstChild("RootSpawnPlayer", true)
	if spawn and spawn:IsA("BasePart") then
		-- On coupe la plongee de camera pour CETTE chute forcee : sinon la plongee (invisible pendant que la camera
		-- est scriptee) apparait d'un coup au passage en camera de jeu -> un "bump". CameraController lit ce drapeau.
		character:SetAttribute("LeafiaSuppressLandDip", true)
		-- On le pose FACE A SON PLOT : regard vers le centre du plot (PrimaryGround), pas l'orientation de la part
		-- RootSpawnPlayer (souvent posee de travers en Studio). Presentation : la camera se cale ensuite DERRIERE lui
		-- (elle lit son regard, l.490) -> elle cadre le plot toute seule. Repli sur l'orientation de la part si pas de centre.
		local spawnPos = spawn.CFrame.Position + Vector3.new(0, 3, 0)
		local center = currentPlot and plotCenter(currentPlot)
		local faceCF = spawn.CFrame + Vector3.new(0, 3, 0)
		if center then
			local look = Vector3.new(center.X - spawnPos.X, 0, center.Z - spawnPos.Z)
			if look.Magnitude > 1e-3 then
				faceCF = CFrame.lookAt(spawnPos, spawnPos + look.Unit)
			end
		end
		character:PivotTo(faceCF)
	end
	-- CIBLE = EXACTEMENT l'etat de repos MESURE de la camera de jeu (Custom), pour qu'elle ne corrige RIEN au handoff :
	--   * meme POINT VISE : HRP + CAM_FOCUS_HEIGHT (la ou Custom vise, ~la tete).
	--   * meme DISTANCE : CAM_END_DISTANCE (zoom par defaut).
	--   * meme INCLINAISON : CAM_END_PITCH (Custom remet SA propre inclinaison de repos, il ne garde pas la notre).
	local focus = hrp.Position + Vector3.new(0, CAM_FOCUS_HEIGHT, 0)
	local flatLook = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	flatLook = if flatLook.Magnitude > 1e-3 then flatLook.Unit else Vector3.new(0, 0, -1)
	-- Position DERRIERE le joueur, a distance EXACTE du focus, inclinee vers le bas de CAM_END_PITCH. En composant le
	-- recul horizontal (cos) et la montee (sin) sur la meme distance, |camera - focus| reste CAM_END_DISTANCE pile.
	local pitch = math.rad(CAM_END_PITCH)
	local offsetDir = (-flatLook) * math.cos(pitch) + Vector3.new(0, 1, 0) * math.sin(pitch)
	local targetPos = focus + offsetDir * CAM_END_DISTANCE
	local targetCF = CFrame.lookAt(targetPos, focus)
	local tween = TweenService:Create(camera, CAM_TWEEN, { CFrame = targetCF })
	tween:Play()
	tween.Completed:Once(function()
		-- On rend la main a la camera de jeu : la cible du tween EST deja son etat (meme focus, meme zoom), donc elle reprend pile la, sans saut.
		camera.CameraSubject = character:FindFirstChildOfClass("Humanoid")
		camera.CameraType = Enum.CameraType.Custom
		character:SetAttribute("LeafiaSuppressLandDip", nil) -- la chute d'entree est finie : les vraies receptions replongent normalement
		unfreeze()
		HudSlide.showAll() -- les HUD reglissent en place en entrant dans le jeu
		gui.Enabled = false
		finishLoading()
	end)
end

-- Cree une barre de page par plot (clonee du template) dans le holder. A appeler APRES l'enumeration des plots ;
-- goToPlotIndex les colore / dimensionne ensuite (jaune + large = selectionne, blanc + etroit = les autres).
local function buildPageBars(holder: Instance, template: GuiObject)
	for i in ipairs(plotList) do
		local bar = template:Clone()
		bar.Name = "PagePoint"
		bar.LayoutOrder = i -- garde l'ordre des plots dans le UIListLayout du holder
		bar.Visible = true
		bar.Parent = holder
		table.insert(pageBars, bar)
	end
end

local function setup(gui: ScreenGui)
	local selectPlot = deep(gui, "HolderSelectPlot")
	local claimBtn = deep(gui, "ClaimButton")

	-- Textes vivants de l'ecran de plot. grabLabel = deep + garde-fou de type (nil si absent / mauvais type).
	local function grabLabel(name: string): TextLabel?
		local o = deep(gui, name)
		return if o and o:IsA("TextLabel") then o else nil
	end
	titleLabel = grabLabel("TitleNamePlot")
	descLabel = grabLabel("DescriptionText")
	plotMaxLabel = grabLabel("PlotMaxMinText")
	stepLabel = grabLabel("AmountStep")
	local avail = deep(gui, "AvailablePlotLabel")
	availableLabel = if avail and avail:IsA("GuiObject") then avail else nil
	local pageHolder = deep(gui, "PointPageVisualHolder")
	local pageTemplate = deep(gui, "PointSelectiveFrameTemplate")

	gui.Enabled = true
	registerHuds() -- capture la position visible des HUD MAINTENANT (pendant qu'ils sont a leur vraie place)
	HudSlide.hideAll(true) -- puis on les glisse hors ecran INSTANTANEMENT (pas de flash de HUD au demarrage)
	freeze() -- deplacements coupes des maintenant (donc plus de reaction FOV a l'input), meme si l'orbite echoue
	local tilePlayerGui = player:FindFirstChildOfClass("PlayerGui")
	if tilePlayerGui then -- fond en tuiles GLOBAL (ScreenGui derriere l'UI), trou clair centre
		tileHandle = TileField.start({ parent = tilePlayerGui, screenGui = true, name = "PlotTileField" })
	end
	setDof(true) -- flou du lointain pendant la selection (relief sur le plot)
	applyMobileLayout(gui) -- ajustements de mise en page reserves au petit ecran tactile (rien sur PC)
	LoadCompanyController.ensureBackdrop(gui) -- voile blanc de fond, visible sur CET ecran ET sur Load Company
	LoadCompanyController.ensureTopBar(gui) -- StepBadge + compteur diamant : top bar commun aux 2 ecrans de selection

	-- Ecrans mutuellement exclusifs via UIManager : afficher l'un cache l'autre AUTOMATIQUEMENT (donc Claim cache
	-- HolderSelectPlot tout seul), et impossible d'en avoir deux a la fois meme en spammant les boutons.
	local plotObjs: { GuiObject } = {}
	if selectPlot and selectPlot:IsA("GuiObject") then
		table.insert(plotObjs, selectPlot)
	end
	UIManager.register("PlotSelect", plotObjs)

	showScreen("PlotSelect")

	-- On ENUMERE tous les plots orbitables et on pre-calcule leur centre UNE fois (Next/Prev lit ce cache). On ATTEND
	-- le dossier Plots : il peut arriver apres le spawn (replication / streaming), et FindFirstChild n'attend pas.
	local worlds = workspace:WaitForChild("Worlds", 10)
	local plotsFolder = worlds and worlds:WaitForChild("Plots", 10)
	if plotsFolder then
		-- Les plots (et surtout leur PrimaryGround) peuvent arriver APRES le dossier (replication / streaming). On
		-- RE-SCANNE jusqu'a en trouver au moins un, ou ~5 s. Chaque scan est instantane (FindFirstChild) : pas d'attente
		-- longue sur un enfant qui ne serait pas un plot, et on ne reste pas bloque si un plot particulier manque.
		local tries = 0
		while tries < 25 do
			plotList = {}
			plotCenters = {}
			local candidates = plotsFolder:GetChildren()
			table.sort(candidates, function(a, b) -- ordre stable et lisible (Slot1, Slot2, Slot3...)
				return a.Name < b.Name
			end)
			for _, plot in ipairs(candidates) do
				local center = plotCenter(plot) -- non-nil seulement si l'enfant a un PrimaryGround (donc un vrai plot)
				if center then
					table.insert(plotList, plot)
					table.insert(plotCenters, center)
				end
			end
			if #plotList > 0 then
				break
			end
			tries += 1
			task.wait(0.2)
		end
	end

	if #plotList > 0 then
		if pageHolder and pageTemplate and pageTemplate:IsA("GuiObject") then
			buildPageBars(pageHolder, pageTemplate)
		end
		goToPlotIndex(1, true) -- 1er plot, centre pose direct (pas de swoosh au demarrage)
		startOrbit()
	else
		warn("[PlotSelect] Aucun plot orbitable sous Worlds.Plots (streaming ou pas replique). Pas d'orbite.")
	end

	-- Claim : on ouvre l'ecran "Load a company" (construit EN CODE par LoadCompanyController ; HolderStart /
	-- HolderListSelectSave retires de Studio). On cache HolderSelectPlot et on coupe son pulse. L'orbite continue en
	-- fond (elle ne s'arrete qu'au Start). Les boutons de LoadCompany reviennent ici par CALLBACKS :
	--   BACK  -> on rouvre l'ecran de plot.
	--   START -> le rideau couvre l'ecran, PUIS (derriere lui) on ferme LoadCompany et on entre dans le jeu.
	if claimBtn then
		onClick(claimBtn, function()
			local plotName = if currentPlot then PlotConfigs.get(currentPlot.Name).name else "Plot"
			UIManager.hideAll()
			stopPulse()
			if tileHandle then -- LoadCompany a son PROPRE fond en tuiles : on cache celui du plot-select (pas de doublon)
				tileHandle.setVisible(false)
			end
			LoadCompanyController.open({
				parent = gui, -- l'ecran "Load a company" vit DANS LoadSaveUI (pas de ScreenGui a part)
				plotName = plotName,
				onBack = function()
					LoadCompanyController.close()
					if tileHandle then -- retour au plot-select : on re-affiche ses tuiles
						tileHandle.setVisible(true)
					end
					showScreen("PlotSelect")
				end,
				onStart = function(_slot)
					-- Rideau D'ABORD : il couvre l'ecran AVANT qu'on cache le menu ou qu'on bouge la camera. Sinon on verrait
					-- toute la mecanique (cartes qui disparaissent, camera qui glisse) -> pas pro. Tout se joue DERRIERE.
					LoadingOverlay.show()
					task.delay(LoadingOverlay.showTime, function()
						-- Le rideau est OPAQUE : on ferme le menu (invisible dessous) puis on demande au serveur ou aller.
						LoadCompanyController.close()
						-- On LAISSE LE RIDEAU VIVRE avant de partir. Cote teleport, la bascule de lieu le remplace des
						-- que le serveur repond : sans cette pause, il disparait avant d'avoir ete vu.
						task.wait(START_HOLD)
						-- Le SERVEUR decide : nouvelle save (tuto pas fini) -> il nous teleporte au didacticiel ; sinon on entre
						-- dans le jeu ici (transition camera). En Studio le teleport echoue cote serveur -> reponse "game".
						local action = "game"
						local startRemote = RemoteSetup.getRemote("StartGame", "Company")
						if startRemote and startRemote:IsA("RemoteFunction") then
							local ok, result = pcall(function()
								return startRemote:InvokeServer()
							end)
							if ok and type(result) == "table" and result.action == "teleport" then
								action = "teleport"
							end
						end
						-- teleport : le rideau reste affiche, le serveur nous bascule vers l'autre place. game : on entre ici,
						-- la transition camera se joue DERRIERE le rideau (enterGame le baisse a la fin via finishLoading).
						if action ~= "teleport" then
							enterGame(gui)
						end
					end)
				end,
			})
		end)
	else
		warn("[PlotSelect] ClaimButton introuvable dans LoadSaveUI.")
	end

	-- Prev / Next : changent le plot PRE-SELECTIONNE. L'orbite glisse vers le nouveau plot et currentPlot suit, donc
	-- Claim / Start portent sur le plot affiche. Le wrap (fin -> debut) se fait dans goToPlotIndex.
	local prevBtn = deep(gui, "PreviousButton")
	local nextBtn = deep(gui, "NextButton")
	if prevBtn then
		onClick(prevBtn, function()
			goToPlotIndex(plotIndex - 1)
		end)
	end
	if nextBtn then
		onClick(nextBtn, function()
			goToPlotIndex(plotIndex + 1)
		end)
	end
end

function PlotSelectController.init()
	-- On attend le perso (les donnees / le spawn peuvent tarder) PUIS l'UI dans PlayerGui, sans bloquer le boot.
	task.spawn(function()
		local _ = player.Character or player.CharacterAdded:Wait()
		local playerGui = player:WaitForChild("PlayerGui")
		local gui = playerGui:WaitForChild(UI_NAME, 30)
		if gui and gui:IsA("ScreenGui") then
			setup(gui)
		else
			warn(`[PlotSelect] {UI_NAME} introuvable dans PlayerGui.`)
		end
	end)
end

return PlotSelectController
