--!strict
-- Etiquette flottante au-dessus de chaque haie A FAIRE.
--
-- Elle disparait des que la haie est finie : ce qui reste a l'ecran est ce qui reste A FAIRE, jamais ce qui est
-- deja regle. Une interface qui affiche aussi le travail accompli oblige le joueur a trier lui-meme, et il
-- finit par ne plus la lire.
--
-- Ce module ne fait que PILOTER. Le placement a l'ecran appartient a WorldAnchor, l'avancement au serveur
-- (attribut LeafiaTrimmed sur la haie). Il n'y a donc rien a calculer ici, seulement a relier.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)
local WorldAnchor = require(ReplicatedStorage.Modules.UI.Core.WorldAnchor)
local InputDevice = require(ReplicatedStorage.Modules.Utils.InputDevice)

local HedgeHologramHandler = {}

local player = Players.LocalPlayer

type Entry = {
	gui: GuiObject,
	label: TextLabel?,
	-- Optionnelle a la construction : la connexion a besoin de l'entree elle-meme pour se rafraichir, donc elle
	-- est branchee juste apres. Un aller-retour connect/disconnect pour contourner ca serait du bricolage.
	connection: RBXScriptConnection?,
}

local entries: { [BasePart]: Entry } = {}
local screen: ScreenGui? = nil
local template: GuiObject? = nil

-- Construit le cartouche de secours : un point sur la cible, une ligne de rappel qui remonte, une barre, et le
-- texte pose dessus.
--
-- POURQUOI UNE LIGNE DE RAPPEL plutot qu'une etiquette posee au-dessus : elle DESIGNE l'objet au lieu de
-- flotter a cote. Avec plusieurs haies a l'ecran, une etiquette libre devient vite ambigue -- on ne sait plus
-- laquelle appartient a quoi. Et le texte se retrouve dans une zone degagee du ciel, pas dans le feuillage.
--
-- Remplace des qu'un modele nomme Template existe dans le ScreenGui.
local function buildFallback(): GuiObject
	local color = HedgeConfigs.HOLOGRAM_COLOR
	local leg = HedgeConfigs.HOLOGRAM_LEG
	local bar = HedgeConfigs.HOLOGRAM_BAR
	local angle = math.rad(HedgeConfigs.HOLOGRAM_ANGLE)

	-- Le conteneur est TRANSPARENT et centre sur la cible : WorldAnchor le pose par son milieu, donc le point
	-- d'accroche tombe pile au centre. Tout le cartouche est ensuite construit a partir de la.
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	-- Assez grand pour contenir le cartouche ET le texte au-dessus, dans les deux sens : le conteneur est
	-- centre sur la cible, donc il doit deborder autant a gauche qu'a droite meme si rien n'y est dessine.
	root.Size = UDim2.fromOffset(math.ceil(leg + bar) * 2 + 20, math.ceil(leg) * 2 + 120)

	local centre = Vector2.new(root.Size.X.Offset * 0.5, root.Size.Y.Offset * 0.5)
	-- Bout de la diagonale, donc debut de la barre.
	local elbow = centre + Vector2.new(math.cos(angle), math.sin(angle)) * leg

	-- LE POINT, sur la cible.
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromOffset(9, 9)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromOffset(centre.X, centre.Y)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.Parent = root

	local round = Instance.new("UICorner") :: UICorner
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = dot

	-- LA DIAGONALE, placee par son MILIEU et non par son bord.
	--
	-- Roblox ne garantit pas autour de quel point une rotation d'interface pivote. Place par le bord, le coude
	-- reel ne tombait pas ou on le calcule, et la barre et le texte partaient donc d'un point faux.
	-- Centree sur le milieu du segment, le resultat est le MEME quel que soit le pivot : les deux extremites
	-- sont justes par construction.
	local middle = (centre + elbow) * 0.5
	local diagonal = Instance.new("Frame")
	diagonal.Name = "Leg"
	diagonal.Size = UDim2.fromOffset(leg, 2)
	diagonal.AnchorPoint = Vector2.new(0.5, 0.5)
	diagonal.Position = UDim2.fromOffset(middle.X, middle.Y)
	diagonal.Rotation = HedgeConfigs.HOLOGRAM_ANGLE
	diagonal.BackgroundColor3 = color
	diagonal.BorderSizePixel = 0
	diagonal.Parent = root

	-- LA BARRE, horizontale, sur laquelle le texte repose.
	local line = Instance.new("Frame")
	line.Name = "Bar"
	line.Size = UDim2.fromOffset(bar, 2)
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.fromOffset(elbow.X, elbow.Y)
	line.BackgroundColor3 = color
	line.BorderSizePixel = 0
	line.Parent = root

	-- TEXTE POSE SUR la barre : ancre en bas, donc il monte au lieu de la recouvrir.
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromOffset(bar, 15)
	title.AnchorPoint = Vector2.new(0, 1)
	-- Empile au-dessus de la valeur, elle-meme posee sur la barre. Les trois se lisent donc de bas en haut :
	-- barre, chiffre, intitule.
	title.Position = UDim2.fromOffset(elbow.X, elbow.Y - 25)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Gotham
	title.TextScaled = true
	title.TextColor3 = color
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = HedgeConfigs.HOLOGRAM_TITLE
	title.Parent = root

	local value = Instance.new("TextLabel")
	value.Name = HedgeConfigs.HOLOGRAM_VALUE
	value.Size = UDim2.fromOffset(bar, 24)
	value.AnchorPoint = Vector2.new(0, 1)
	value.Position = UDim2.fromOffset(elbow.X, elbow.Y - 3)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBold
	value.TextScaled = true
	value.TextColor3 = color
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Text = "0%"
	value.Parent = root

	return root
end

local function getScreen(): ScreenGui?
	local existing = screen
	if existing and existing.Parent then
		return existing
	end

	local gui = player:FindFirstChild("PlayerGui")
	if not gui then
		return nil
	end

	local found = gui:FindFirstChild(HedgeConfigs.HOLOGRAM_GUI)
	if found and found:IsA("ScreenGui") then
		screen = found
	else
		local created = Instance.new("ScreenGui")
		created.Name = HedgeConfigs.HOLOGRAM_GUI
		created.ResetOnSpawn = false
		-- IgnoreGuiInset FAUX, obligatoire : WorldToViewportPoint rend des coordonnees SANS l'inset de la barre
		-- Roblox. A vrai, tout serait decale d'environ 36 pixels vers le haut.
		created.IgnoreGuiInset = false
		created.Parent = gui
		screen = created
	end

	-- Le modele est cherche DANS le ScreenGui : c'est la que tu le poseras depuis Studio, et il remplacera
	-- l'etiquette de secours sans qu'on touche au code.
	local model = (screen :: ScreenGui):FindFirstChild(HedgeConfigs.HOLOGRAM_TEMPLATE)
	if model and model:IsA("GuiObject") then
		model.Visible = false
		template = model
	end

	return screen
end

local function refresh(entry: Entry, hedge: BasePart)
	local done = hedge:GetAttribute(HedgeConfigs.TRIMMED_ATTRIBUTE)
	local ratio = if typeof(done) == "number" then done else 0

	-- FINIE : l'etiquette s'efface. C'est le seul retour dont le joueur a besoin pour savoir qu'il peut passer
	-- a la suivante.
	if ratio >= 1 then
		entry.gui.Parent = nil
		return
	end

	local parent = getScreen()
	if parent and entry.gui.Parent ~= parent then
		entry.gui.Parent = parent
	end
	if entry.label then
		entry.label.Text = `{math.floor(ratio * 100)}%`
	end
end

local function add(hedge: BasePart)
	if entries[hedge] then
		return
	end
	local parent = getScreen()
	if not parent then
		return
	end

	local source = template
	local gui = if source then source:Clone() else buildFallback()
	gui.Name = hedge.Name
	gui.Visible = false
	-- MOBILE : le cartouche est en pixels fixes, il parait enorme sur petit ecran. On le retrecit d'un coup via un
	-- UIScale. Fige a la creation (le device change rarement en session) ; on reutilise un UIScale d'un eventuel
	-- template plutot que d'en empiler un deuxieme.
	if InputDevice.isTouch() then
		local uiScale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		uiScale.Scale = HedgeConfigs.HOLOGRAM_TOUCH_SCALE
		uiScale.Parent = gui
	end

	local label = gui:FindFirstChild(HedgeConfigs.HOLOGRAM_VALUE)
	if not (label and label:IsA("TextLabel")) then
		-- Repli sur le premier TextLabel : ca evite d'imposer un nom precis dans une interface que tu dessines
		-- toi-meme.
		label = gui:FindFirstChildWhichIsA("TextLabel", true)
	end

	gui.Parent = parent
	WorldAnchor.attach(
		gui,
		hedge,
		-- Au-dessus du SOMMET et non du centre : sur une haie haute, une etiquette centree serait dans le
		-- feuillage.
		Vector3.new(0, hedge.Size.Y * 0.5 + HedgeConfigs.HOLOGRAM_LIFT, 0),
		HedgeConfigs.HOLOGRAM_RANGE
	)

	local entry: Entry = {
		gui = gui,
		label = if label and label:IsA("TextLabel") then label else nil,
		connection = nil,
	}
	-- L'avancement vient du SERVEUR : on ecoute son attribut au lieu de recompter les carreaux ici.
	entry.connection = hedge:GetAttributeChangedSignal(HedgeConfigs.TRIMMED_ATTRIBUTE):Connect(function()
		refresh(entry, hedge)
	end)

	entries[hedge] = entry
	refresh(entry, hedge)
end

local function remove(hedge: BasePart)
	local entry = entries[hedge]
	if not entry then
		return
	end
	if entry.connection then
		entry.connection:Disconnect()
	end
	WorldAnchor.detach(entry.gui)
	entry.gui:Destroy()
	entries[hedge] = nil
end

function HedgeHologramHandler.init()
	for _, instance in ipairs(CollectionService:GetTagged(HedgeConfigs.TAG)) do
		if instance:IsA("BasePart") then
			add(instance)
		end
	end

	CollectionService:GetInstanceAddedSignal(HedgeConfigs.TAG):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			add(instance)
		end
	end)

	CollectionService:GetInstanceRemovedSignal(HedgeConfigs.TAG):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			remove(instance)
		end
	end)
end

return HedgeHologramHandler
