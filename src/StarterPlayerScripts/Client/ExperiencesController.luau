--!strict
-- Jauge d'EXPERIENCE du joueur. Elle SUIT le joueur (WorldAnchor, au-dessus de la tete, taille selon la distance) et
-- n'APPARAIT que quand le joueur est a une haie (attribut serveur LeafiaAtHedge), avec une anim SLIME : elle sort du
-- milieu de la tete en grossissant + montant jusqu'a sa place, et se retire pareil a l'inverse.
--
-- Trois affichages, tous pilotes par le SERVEUR (attributs sur le joueur), le client ne fait qu'obeir :
--   - la barre (SlideBar) se remplit selon XpFill (0-1) ;
--   - le texte (LevelDataCompetenceText) montre le niveau XpLevel ;
--   - le degrade (UIGradientRotate) tourne, UNIQUEMENT tant que la jauge est affichee (cf CLAUDE.md : pas de boucle
--     qui tourne cachee).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldAnchor = require(ReplicatedStorage.Modules.UI.Core.WorldAnchor)
local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)
local ExperienceConfigs = require(ReplicatedStorage.Modules.Configs.ExperienceConfigs)

local ExperiencesController = {}

local player = Players.LocalPlayer

local FOLLOW_TARGET = "HumanoidRootPart"
-- Deux offsets MONDE : d'ou la jauge SORT (milieu de la tete) et ou elle S'INSTALLE (au-dessus). L'apparition glisse
-- de l'un a l'autre. A REGLER a l'oeil.
local HEAD_OFFSET = Vector3.new(0, 1.5, 0)
local SHOWN_OFFSET = Vector3.new(0, 5, 0)
local FOLLOW_SCALE: WorldAnchor.Scale = { ref = 16, min = 0.25, max = 0.5 } -- petite, bornee

-- Apparition SLIME : rebond (Elastic) qui deborde puis se pose. Disparition plus seche.
local SHOW_TWEEN = TweenInfo.new(0.55, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local HIDE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)

local ROTATE_TWEEN = TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false) -- 3 s / tour, infini
local FILL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Attributs poses par le serveur (ExperienceService) sur le joueur : la jauge affiche la competence choisie par le
-- serveur (taille des haies pour l'instant). Noms PARTAGES via ExperienceConfigs (client + serveur d'accord).
-- LEVEL_FORMAT : mise en forme du texte de niveau, cote client uniquement.
local FILL_ATTRIBUTE = ExperienceConfigs.FILL_ATTRIBUTE
local LEVEL_ATTRIBUTE = ExperienceConfigs.LEVEL_ATTRIBUTE
local LEVEL_FORMAT = "LEVEL %d"
-- Petit "punch" du texte a chaque changement de niveau : il grossit d'un coup puis se pose (Back). Simple pour
-- l'instant, les effets viendront par-dessus.
local LEVEL_POP = 1.35
local LEVEL_POP_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local gui: ScreenGui? = nil
local holder: GuiObject? = nil
local slideBar: Frame? = nil
local levelLabel: TextLabel? = nil
local levelScale: UIScale? = nil -- pour le punch du texte au level up
local lastLevel: number? = nil -- pour ne puncher que sur un VRAI changement, pas au 1er affichage
local rotateGradient: UIGradient? = nil
local rotateTween: Tween? = nil

local shown = false -- la jauge est-elle demandee a l'ecran (joueur a une haie) ?
local appearTween: Tween? = nil
local appearProxy: NumberValue? = nil

-- ===== ROTATION DU DEGRADE (coupee des que pas affichee) =====
local function stopRotation()
	if rotateTween then
		rotateTween:Cancel()
		rotateTween = nil
	end
end

local function startRotation()
	local grad = rotateGradient
	if rotateTween or not grad then
		return
	end
	grad.Rotation = 0
	rotateTween = TweenService:Create(grad, ROTATE_TWEEN, { Rotation = 360 })
	rotateTween:Play()
end

-- Affichee = demandee (shown) ET a l'ecran (WorldAnchor met holder.Visible a false hors ecran) ET ScreenGui active.
local function isShown(): boolean
	local g, h = gui, holder
	return shown and g ~= nil and g.Enabled and h ~= nil and h.Visible
end

local function refreshRotation()
	if isShown() then
		startRotation()
	else
		stopRotation()
	end
end

-- ===== APPARITION SLIME =====
-- Un proxy (NumberValue 0->1) pilote a la fois le glissement (offset tete -> place) ET le grossissement (scaleMul).
-- Elastic fait deborder au-dela de 1 puis revenir : la jauge monte un peu trop haut + grossit un peu trop, puis se
-- pose. C'est ce debordement qui donne le rendu "slime".
local function ensureProxy(): NumberValue
	local existing = appearProxy
	if existing then
		return existing
	end
	local proxy = Instance.new("NumberValue")
	proxy.Value = 0
	appearProxy = proxy
	proxy.Changed:Connect(function(v)
		local h = holder
		if h then
			WorldAnchor.setOffset(h, HEAD_OFFSET:Lerp(SHOWN_OFFSET, v))
			WorldAnchor.setScaleMul(h, v)
		end
	end)
	return proxy
end

local function playAppear(target: number, info: TweenInfo)
	local proxy = ensureProxy()
	if appearTween then
		appearTween:Cancel()
	end
	appearTween = TweenService:Create(proxy, info, { Value = target })
	appearTween:Play()
end

local function show()
	if shown then
		return
	end
	shown = true
	playAppear(1, SHOW_TWEEN)
	refreshRotation()
end

local function hide()
	if not shown then
		return
	end
	shown = false
	playAppear(0, HIDE_TWEEN)
	refreshRotation() -- coupe le degrade tout de suite (shown = false)
end

-- ===== REMPLISSAGE + NIVEAU (independants du reste : appeles a chaque changement d'attribut) =====
local function applyFill(fraction: number)
	local bar = slideBar
	if bar then
		TweenService:Create(bar, FILL_TWEEN, { Size = UDim2.fromScale(1, math.clamp(fraction, 0, 1)) }):Play()
	end
end

local function applyLevel(level: number)
	local label = levelLabel
	if not label then
		return
	end
	label.Text = string.format(LEVEL_FORMAT, level)
	-- Punch UNIQUEMENT sur un vrai changement (pas au 1er affichage) : grossit d'un coup puis revient a 1.
	local scale = levelScale
	if scale and lastLevel ~= nil and level ~= lastLevel then
		scale.Scale = LEVEL_POP
		TweenService:Create(scale, LEVEL_POP_TWEEN, { Scale = 1 }):Play()
	end
	lastLevel = level
end

local function readNumber(attribute: string, fallback: number): number
	local v = player:GetAttribute(attribute)
	return if typeof(v) == "number" then v else fallback
end

-- ===== ACCROCHE AU PERSO + DECLENCHEUR HAIE =====
local function onCharacter(char: Model)
	local h = holder
	if not h then
		return
	end
	local hrp = char:WaitForChild(FOLLOW_TARGET, 5)
	if hrp and hrp:IsA("BasePart") then
		-- Demarre CACHEE au milieu de la tete (scaleMul 0). L'apparition l'amene a sa place.
		WorldAnchor.attach(h, hrp, HEAD_OFFSET, 0, FOLLOW_SCALE, false)
		WorldAnchor.setScaleMul(h, 0)
	end

	-- Nouveau perso : plus a une haie. On repart cachee, sans animation (etat propre).
	shown = false
	if appearTween then
		appearTween:Cancel()
	end
	if appearProxy then
		appearProxy.Value = 0
	end
	refreshRotation()

	-- Declencheur : la jauge apparait quand le serveur pose LeafiaAtHedge (joueur a une haie), disparait sinon.
	local function refreshHedge()
		if char:GetAttribute(HedgeConfigs.AT_HEDGE_ATTRIBUTE) == true then
			show()
		else
			hide()
		end
	end
	char:GetAttributeChangedSignal(HedgeConfigs.AT_HEDGE_ATTRIBUTE):Connect(refreshHedge)
	refreshHedge()
end

local function bind(ui: ScreenGui)
	gui = ui
	local h = ui:FindFirstChild("JaugeHolder")
	if not (h and h:IsA("GuiObject")) then
		warn("[ExperiencesController] JaugeHolder introuvable")
		return
	end
	holder = h

	local canvas = h:FindFirstChild("SlideBarCanvas")
	local bar = canvas and canvas:FindFirstChild("SlideBar")
	slideBar = if bar and bar:IsA("Frame") then bar else nil
	local grad = canvas and canvas:FindFirstChild("UIGradientRotate", true)
	rotateGradient = if grad and grad:IsA("UIGradient") then grad else nil
	local label = h:FindFirstChild("LevelDataCompetenceText", true)
	levelLabel = if label and label:IsA("TextLabel") then label else nil
	if levelLabel then
		-- UIScale dedie au punch (separe du UIScale de distance que WorldAnchor pose sur le HolderJauge).
		local s = levelLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		s.Parent = levelLabel
		levelScale = s
	end

	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	h:GetPropertyChangedSignal("Visible"):Connect(refreshRotation)
	ui:GetPropertyChangedSignal("Enabled"):Connect(refreshRotation)

	-- Remplissage + niveau pilotes par le serveur (attributs sur le joueur).
	applyFill(readNumber(FILL_ATTRIBUTE, 0))
	applyLevel(readNumber(LEVEL_ATTRIBUTE, 1))
	player:GetAttributeChangedSignal(FILL_ATTRIBUTE):Connect(function()
		applyFill(readNumber(FILL_ATTRIBUTE, 0))
	end)
	player:GetAttributeChangedSignal(LEVEL_ATTRIBUTE):Connect(function()
		applyLevel(readNumber(LEVEL_ATTRIBUTE, 1))
	end)
end

function ExperiencesController.init()
	-- Les ScreenGui de StarterGui sont copiees dans PlayerGui au SPAWN du perso, qui peut TARDER (chargement des
	-- donnees...). On attend donc le perso AVANT de chercher l'UI, en tache de fond (pas de blocage du boot). Sinon un
	-- WaitForChild court expire avant que l'UI existe (elle est pourtant bien la, juste plus tard).
	task.spawn(function()
		if not player.Character then
			player.CharacterAdded:Wait()
		end
		local playerGui = player:WaitForChild("PlayerGui")
		local ui = playerGui:WaitForChild("ExperiencesUI", 10)
		if ui and ui:IsA("ScreenGui") then
			bind(ui)
		else
			warn("[ExperiencesController] ExperiencesUI introuvable (pas copiee de StarterGui ?)")
		end
	end)
end

return ExperiencesController
