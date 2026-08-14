--!strict
-- COMBO de coupe, cote AFFICHAGE. Un nombre "xN" (police Luckiest Guy) surmonte d'une legende "COMBOS", qui SUIT le
-- joueur (WorldAnchor, a droite du corps) et monte tant qu'il taille. Purement visuel : le compteur est tenu par le
-- SERVEUR (ComboService), le client ne fait que lire l'attribut LeafiaCombo et l'animer (jaillit a l'apparition, pop a
-- chaque montee, se retire quand ca retombe a zero).
--
-- L'interface est construite EN CODE (pas de dependance a une ScreenGui de Studio) : un petit widget suivi, ca ne
-- justifie pas un asset a maintenir a la main.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldAnchor = require(ReplicatedStorage.Modules.UI.Core.WorldAnchor)
local ComboConfigs = require(ReplicatedStorage.Modules.Configs.ComboConfigs)

local ComboController = {}

local player = Players.LocalPlayer

local FOLLOW_TARGET = "HumanoidRootPart"
-- A DROITE du joueur et bien plus bas que la tete. Repere CAMERA (dernier argument de attach a true) : le X est la
-- droite de l'ECRAN, donc le compteur reste a droite du joueur meme quand la camera tourne, et le Y est le bas de
-- l'ecran (negatif = descend). Discret, pose vers le corps, pas au-dessus. A REGLER a l'oeil.
local FOLLOW_OFFSET = Vector3.new(3, -1, 0)
local FOLLOW_SCALE: WorldAnchor.Scale = { ref = 16, min = 0.14, max = 0.32 } -- beaucoup plus petit : c'est un compteur

local COMBO_FORMAT = "X%d"
local CAPTION_TEXT = "COMBOS" -- legende qui explique ce qu'est le nombre
-- FontFace plutot que Enum.Font.X : une famille absente au runtime plante avec l'enum, pas avec le chemin json (les
-- familles livrees avec Roblox sont sures). Luckiest Guy : demande du joueur.
local FONT = Font.new("rbxasset://fonts/families/LuckiestGuy.json", Enum.FontWeight.Regular)

-- Pop a chaque montee : le widget grossit d'un coup puis se pose (Back). Plus le combo grimpe, plus le pop tape (borne).
local POP_BASE = 1.25
local POP_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- Apparition (0 -> combo) : jaillit depuis rien (Back deborde puis se pose). Retrait (-> 0) : plus sec.
local SHOW_TWEEN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HIDE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- Le combo "chauffe" en montant : blanc tot, or quand ca s'accumule. Simple palier pour l'instant.
local COLOR_LOW = Color3.fromRGB(255, 255, 255)
local COLOR_HIGH = Color3.fromRGB(255, 194, 75)
local HIGH_FROM = 10
local CAPTION_COLOR = Color3.fromRGB(198, 224, 200) -- vert clair, secondaire : une legende, pas le clou
local STROKE_COLOR = Color3.fromRGB(28, 46, 30) -- vert tres fonce : lisible sur ciel comme sur haie

local COMBO_ATTRIBUTE = ComboConfigs.COMBO_ATTRIBUTE

local holder: Frame? = nil
local label: TextLabel? = nil -- le nombre "xN"
local stroke: UIStroke? = nil
local caption: TextLabel? = nil -- la legende "COMBOS"
local captionStroke: UIStroke? = nil
-- Pop de TOUT le widget (nombre + legende ensemble), pose sur un Frame interne : ils pulsent d'un bloc sans se
-- chevaucher, et WorldAnchor garde son propre UIScale de distance sur le holder (un seul UIScale utile par objet).
local widgetScale: UIScale? = nil

local shown = false -- un combo est-il actuellement affiche (combo > 0) ?

local function colorFor(combo: number): Color3
	return if combo >= HIGH_FROM then COLOR_HIGH else COLOR_LOW
end

local function popStrength(combo: number): number
	return POP_BASE + math.min(combo, 20) * 0.01
end

local function setTransparency(value: number)
	if label then
		label.TextTransparency = value
	end
	if stroke then
		stroke.Transparency = value
	end
	if caption then
		caption.TextTransparency = value
	end
	if captionStroke then
		captionStroke.Transparency = value
	end
end

-- WorldAnchor PILOTE holder.Visible chaque frame (vrai a l'ecran, faux derriere / hors champ) : on ne cache donc PAS
-- le combo via Visible (il le rallumerait). On le cache en FONDANT le widget (transparence + retrecissement).
local function appear(combo: number)
	local l, sc = label, widgetScale
	if not (l and sc) then
		return
	end
	shown = true
	l.Text = string.format(COMBO_FORMAT, combo)
	l.TextColor3 = colorFor(combo)
	setTransparency(0)
	sc.Scale = 0
	TweenService:Create(sc, SHOW_TWEEN, { Scale = 1 }):Play()
end

local function bump(combo: number)
	local l, sc = label, widgetScale
	if not (l and sc) then
		return
	end
	l.Text = string.format(COMBO_FORMAT, combo)
	l.TextColor3 = colorFor(combo)
	sc.Scale = popStrength(combo)
	TweenService:Create(sc, POP_TWEEN, { Scale = 1 }):Play()
end

local function hide()
	if not shown then
		return
	end
	shown = false
	if label then
		TweenService:Create(label, HIDE_TWEEN, { TextTransparency = 1 }):Play()
	end
	if stroke then
		TweenService:Create(stroke, HIDE_TWEEN, { Transparency = 1 }):Play()
	end
	if caption then
		TweenService:Create(caption, HIDE_TWEEN, { TextTransparency = 1 }):Play()
	end
	if captionStroke then
		TweenService:Create(captionStroke, HIDE_TWEEN, { Transparency = 1 }):Play()
	end
	if widgetScale then
		TweenService:Create(widgetScale, HIDE_TWEEN, { Scale = 0.6 }):Play()
	end
end

local function applyCombo(combo: number)
	if combo <= 0 then
		hide()
	elseif not shown then
		appear(combo)
	else
		bump(combo)
	end
end

local function readCombo(): number
	local v = player:GetAttribute(COMBO_ATTRIBUTE)
	return if typeof(v) == "number" then v else 0
end

local function buildUi()
	local g = Instance.new("ScreenGui")
	g.Name = "ComboUI"
	g.ResetOnSpawn = false -- survit aux respawns : on garde nos references, pas de recreation
	-- REQUIS par WorldAnchor : WorldToViewportPoint rend en coords VIEWPORT (origine au coin absolu de l'ecran). Le GUI
	-- doit donc couvrir tout l'ecran (None), sinon l'inset de la barre Roblox decale le compteur de ~36 px vers le bas.
	g.ScreenInsets = Enum.ScreenInsets.None
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.DisplayOrder = 50

	local h = Instance.new("Frame")
	h.Name = "ComboHolder"
	h.BackgroundTransparency = 1
	h.Size = UDim2.fromOffset(240, 130) -- nombre + legende ; WorldAnchor le centre et le met a l'echelle
	h.Visible = false
	h.Parent = g

	-- Frame interne qui porte le POP : nombre et legende pulsent ENSEMBLE, positions relatives conservees.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = h

	local l = Instance.new("TextLabel")
	l.Name = "ComboText"
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.42)
	l.Size = UDim2.fromScale(1, 0.6)
	l.FontFace = FONT
	l.TextScaled = true
	l.Text = ""
	l.TextColor3 = COLOR_LOW
	l.TextTransparency = 1
	l.Parent = content

	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = STROKE_COLOR
	s.Transparency = 1
	s.Parent = l
	stroke = s

	local cap = Instance.new("TextLabel")
	cap.Name = "ComboCaption"
	cap.BackgroundTransparency = 1
	cap.AnchorPoint = Vector2.new(0.5, 0.5)
	cap.Position = UDim2.fromScale(0.5, 0.85)
	cap.Size = UDim2.fromScale(0.95, 0.24)
	cap.FontFace = FONT
	cap.TextScaled = true
	cap.Text = CAPTION_TEXT
	cap.TextColor3 = CAPTION_COLOR
	cap.TextTransparency = 1
	cap.Parent = content

	local capStroke = Instance.new("UIStroke")
	capStroke.Thickness = 2
	capStroke.Color = STROKE_COLOR
	capStroke.Transparency = 1
	capStroke.Parent = cap
	captionStroke = capStroke

	local sc = Instance.new("UIScale")
	sc.Scale = 1
	sc.Parent = content
	widgetScale = sc

	local playerGui = player:WaitForChild("PlayerGui")
	g.Parent = playerGui

	holder, label, caption = h, l, cap
end

local function onCharacter(char: Model)
	local h = holder
	if not h then
		return
	end
	local hrp = char:WaitForChild(FOLLOW_TARGET, 5)
	if hrp and hrp:IsA("BasePart") then
		-- cameraRelative = true : l'offset est lu dans le repere de la camera (droite / bas de l'ecran), donc le
		-- compteur reste a droite du joueur quoi qu'il arrive a la camera.
		WorldAnchor.attach(h, hrp, FOLLOW_OFFSET, 0, FOLLOW_SCALE, true)
	end
	-- Nouveau perso : on repart sur l'etat reel du combo (l'attribut peut deja etre > 0), sans animation d'apparition
	-- parasite. shown est remis a false pour que le prochain combo > 0 rejoue bien un "appear".
	shown = false
	local combo = readCombo()
	if combo > 0 then
		appear(combo)
	end
end

function ComboController.init()
	-- Comme la jauge d'XP : on attend le perso (le spawn peut tarder au chargement des donnees) avant de toucher a la
	-- PlayerGui, en tache de fond pour ne pas bloquer le boot.
	task.spawn(function()
		if not player.Character then
			player.CharacterAdded:Wait()
		end
		buildUi()
		if player.Character then
			onCharacter(player.Character)
		end
		player.CharacterAdded:Connect(onCharacter)
		player:GetAttributeChangedSignal(COMBO_ATTRIBUTE):Connect(function()
			applyCombo(readCombo())
		end)
	end)
end

return ComboController
