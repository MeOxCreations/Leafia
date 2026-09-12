--!strict
-- LA JAUGE DE REMPLISSAGE AU-DESSUS DU SEAU. Combien il reste de place, lu d'un coup d'oeil.
--
-- POURQUOI ELLE EXISTE. Un seau qui a un fond cree une decision -- continuer ou aller le vider -- mais seulement
-- si le joueur VOIT qu'il se remplit. Sans jauge, il decouvre la limite en poussant des feuilles qui n'entrent
-- plus, ce qui se lit comme une panne et pas comme un choix.
--
-- UN BILLBOARD ET PAS UN MARQUEUR PROJETE. Elle appartient a l'objet : elle doit le suivre, rapetisser avec la
-- distance, et disparaitre derriere un mur. C'est exactement ce qu'un `BillboardGui` fait sans une ligne de code,
-- alors qu'un ScreenGui projete demanderait de le refaire a la main.
--
-- COTE CLIENT PARCE QUE C'EST DE L'AFFICHAGE. Le compte vit sur le seau, en attribut pose par le serveur : ici on
-- ne fait que le lire. Deux joueurs peuvent regarder le meme seau et voir la meme chose sans qu'on envoie rien.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BinConfigs = require(ReplicatedStorage.Modules.Configs.BinConfigs)

local BinFillController = {}

local player = Players.LocalPlayer

-- CE QU'ON A DEJA EQUIPE, par seau. Sans ce registre on reposerait une jauge par passage, et il y en aurait
-- trente au bout d'une minute.
type Gauge = { gui: BillboardGui, fill: Frame, label: TextLabel, shown: boolean }
local gauges: { [Model]: Gauge } = {}

local GAUGE_NAME = "LeafiaBinFill"

local function binRoot(bin: Model): BasePart?
	return bin.PrimaryPart or bin:FindFirstChildWhichIsA("BasePart")
end

--- Le cast est OBLIGATOIRE : luau-lsp ne resout pas `Instance.new("UICorner")` vers `UICorner`.
local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function build(bin: Model): Gauge?
	local root = binRoot(bin)
	if not root then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = GAUGE_NAME
	gui.Size = UDim2.fromOffset(BinConfigs.GAUGE_WIDTH, BinConfigs.GAUGE_HEIGHT)
	gui.StudsOffsetWorldSpace = Vector3.new(0, BinConfigs.GAUGE_UP, 0)
	gui.AlwaysOnTop = false -- elle appartient au monde : un mur doit la cacher
	gui.MaxDistance = BinConfigs.GAUGE_MAX_DISTANCE
	gui.LightInfluence = 0
	gui.Adornee = root
	gui.Parent = root

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = BinConfigs.GAUGE_BACK
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = gui
	corner(back, 8)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 26, 34)
	stroke.Thickness = 2
	stroke.Transparency = 0.35
	stroke.Parent = back

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 3)
	pad.PaddingLeft = UDim.new(0, 3)
	pad.PaddingRight = UDim.new(0, 3)
	pad.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = BinConfigs.GAUGE_FILL
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner(fill, 6)

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Text = ""
	label.ZIndex = 2
	label.Parent = back

	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(20, 26, 34)
	textStroke.Thickness = 2
	textStroke.Transparency = 0.25
	textStroke.Parent = label

	return { gui = gui, fill = fill, label = label, shown = false }
end

local function gaugeFor(bin: Model): Gauge?
	local existing = gauges[bin]
	if existing and existing.gui.Parent then
		return existing
	end
	local made = build(bin)
	if made then
		gauges[bin] = made
		bin.Destroying:Once(function()
			gauges[bin] = nil
		end)
	end
	return made
end

local function update(bin: Model)
	local raw = bin:GetAttribute(BinConfigs.LEAVES_ATTRIBUTE)
	local leaves = if typeof(raw) == "number" then math.max(raw :: number, 0) else 0
	-- UN SEAU VIDE NE PORTE PAS DE JAUGE. Une barre a zero au-dessus de chaque seau du jardin ne dit rien et
	-- encombre la vue : elle apparait quand elle a quelque chose a raconter.
	if leaves <= 0 then
		local existing = gauges[bin]
		if existing then
			existing.gui.Enabled = false
			existing.shown = false
		end
		return
	end
	local gauge = gaugeFor(bin)
	if not gauge then
		return
	end
	local ratio = math.clamp(leaves / BinConfigs.LEAVES_CAPACITY, 0, 1)
	gauge.gui.Enabled = true
	gauge.shown = true
	-- ELLE GLISSE, elle ne saute pas. Une barre qui change d'un bond ne se lit pas -- on voit l'etat d'apres,
	-- jamais le mouvement, donc on ne sent pas qu'on progresse.
	TweenService:Create(gauge.fill, BinConfigs.GAUGE_TWEEN, { Size = UDim2.fromScale(ratio, 1) }):Play()
	-- PLEIN SE DIT AUTREMENT QU'UN CHIFFRE. Le joueur n'a pas a comparer deux nombres pour comprendre qu'il doit
	-- aller vider : le mot le dit, et la couleur le confirme.
	if ratio >= 1 then
		gauge.label.Text = BinConfigs.GAUGE_FULL_TEXT
		gauge.fill.BackgroundColor3 = BinConfigs.GAUGE_FULL
	else
		gauge.label.Text = `{math.floor(leaves)} / {BinConfigs.LEAVES_CAPACITY}`
		gauge.fill.BackgroundColor3 = BinConfigs.GAUGE_FILL
	end
end

function BinFillController.init()
	local nextCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextCheck then
			return
		end
		nextCheck = now + BinConfigs.GAUGE_INTERVAL
		for _, d in Workspace:GetDescendants() do
			if d:IsA("Model") and d.Name:sub(1, #BinConfigs.MODEL_PREFIX) == BinConfigs.MODEL_PREFIX then
				update(d :: Model)
			end
		end
	end)

	-- RIEN A NETTOYER AU RESPAWN : les jauges vivent sur les SEAUX, pas sur le personnage. Un seau detruit emporte
	-- la sienne, et le registre se vide avec lui.
	print(`[BinFillController] Pret : jauge de remplissage au-dessus des seaux ({player.Name}).`)
end

return BinFillController
