--!strict
-- La couche INTERIEURE des haies : les branches qu'on voit a travers les trous.
--
-- Une haie a deux couches. Dehors, les feuilles, qui se taillent. Dedans, des branches, qui ne se taillent pas.
-- Sans cette seconde couche, une feuille detruite (sur une arete, ou a force d'etre abimee) ouvre sur du VIDE :
-- la haie devient une coquille creuse et l'illusion tombe. Avec elle, le trou montre l'interieur de la plante,
-- ce qui est exactement ce qu'on veut donner a voir quand on a trop mordu.
--
-- UNE SEULE PART PAR HAIE. C'est du decor : aucun etat, aucune coupe, aucun attribut. Le grillage de carreaux
-- ne sert qu'a ce qui se taille, et rien ici ne se taille.
--
-- POURQUOI UN SERVICE A PART de HedgeCellService : celui-la construit ce qui SE TAILLE, celui-ci ce qui se
-- voit DERRIERE. Le jour ou les branches auront leur propre logique (repousse, casse, texture carrelee), elle
-- tiendra dans ce fichier sans toucher a la grille.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)

local HedgeBranchService = {}

type Layer = {
	part: BasePart,
	-- Proportions pour lesquelles le modele a ete fait. LUES SUR LE MODELE, jamais recopiees en config : le
	-- mesh porte deja cette information, la redire ailleurs cree une deuxieme verite qui finit par mentir.
	-- Elle apparait au demarrage dans la console : si un chiffre est faux, ca se voit tout de suite.
	reference: Vector3,
}

local layers: { Layer } = {}
local branches: { [BasePart]: BasePart } = {}
local branchFolder: Folder? = nil

local function resolveLayers(): { Layer }
	local found: { Layer } = {}
	for _, path in ipairs(HedgeConfigs.BRANCH_ASSETS) do
		local source: Instance? = ReplicatedStorage
		for _, name in ipairs(path) do
			source = source and source:FindFirstChild(name)
		end
		if source and source:IsA("BasePart") then
			local part = source:Clone()
			part.Name = HedgeConfigs.BRANCH_NAME
			part.Anchored = true
			part.Massless = true
			part.CanCollide = false
			-- CanQuery n'a d'effet que parce que CanCollide est deja faux. Sans ca, cette part remplirait la
			-- haie et le lancer du curseur s'arreterait dessus au lieu d'atteindre la surface.
			part.CanQuery = false
			part.CanTouch = false
			-- Elle GARDE son ombre, contrairement aux carreaux et aux feuilles. C'est le seul volume plein de la
			-- haie : une part par haie qui porte l'ombre coute infiniment moins que des milliers de feuilles qui
			-- la porteraient chacune.
			part.CastShadow = true
			table.insert(found, { part = part, reference = source.Size })
		else
			-- Anormal ET actionnable : sans branches, chaque trou dans les feuilles montre l'interieur vide.
			warn(`[HedgeBranchService] Couche introuvable : ReplicatedStorage.{table.concat(path, ".")}`)
		end
	end
	return found
end

-- Modele qui se DEFORMERA LE MOINS sur cette haie.
--
-- Pour chaque modele on calcule les trois facteurs d'echelle a appliquer. Le rapport entre le plus grand et le
-- plus petit dit de combien la texture sera etiree : a 1 elle ne l'est pas du tout. On garde le plus petit.
--
-- CETTE REGLE VAUT MIEUX QU'UN CHOIX PAR NOM DE HAIE. Elle continue de marcher quand une taille inedite
-- arrive, elle ne demande aucune convention de nommage a tenir, et ajouter un troisieme modele ne coute qu'une
-- ligne de config. Un choix par nom, lui, se casse en silence a la premiere haie mal nommee.
local function pickLayer(size: Vector3): Layer?
	local best: Layer? = nil
	local bestStretch = math.huge
	for _, layer in ipairs(layers) do
		local reference = layer.reference
		local fx = size.X / math.max(reference.X, 1e-3)
		local fy = size.Y / math.max(reference.Y, 1e-3)
		local fz = size.Z / math.max(reference.Z, 1e-3)
		local stretch = math.max(fx, fy, fz) / math.max(math.min(fx, fy, fz), 1e-3)
		if stretch < bestStretch then
			best = layer
			bestStretch = stretch
		end
	end
	return best
end

local function getBranchFolder(): Folder
	local existing = branchFolder
	if existing and existing.Parent then
		return existing
	end
	local found = workspace:FindFirstChild(HedgeConfigs.BRANCH_FOLDER)
	if found and found:IsA("Folder") then
		branchFolder = found
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = HedgeConfigs.BRANCH_FOLDER
	folder.Parent = workspace
	branchFolder = folder
	return folder
end

local function clearHedge(hedge: BasePart)
	local branch = branches[hedge]
	if branch then
		branch:Destroy()
		branches[hedge] = nil
	end
end

local function buildHedge(hedge: BasePart): boolean
	clearHedge(hedge)

	local layer = pickLayer(hedge.Size)
	if not layer then
		return false
	end

	local branch = layer.part:Clone()

	-- VOLUME DU BOIS DEFINI EN STUDS, pas en pourcentage. Un pourcentage recule les faces d'autant plus que la
	-- haie est grande : les extremites d'une haie longue baillent pendant que celles d'une courte collent. Deux
	-- marges absolues (cotes et haut) donnent au contraire un recul CONSTANT sur toutes les faces, quelle que
	-- soit la taille de la haie. Le max(...) garde un minimum de matiere si une haie est plus petite qu'une marge,
	-- plutot qu'un volume nul ou negatif.
	local side = HedgeConfigs.BRANCH_SIDE_CLEARANCE
	local width = math.max(hedge.Size.X - side * 2, hedge.Size.X * 0.2)
	local depth = math.max(hedge.Size.Z - side * 2, hedge.Size.Z * 0.2)
	local height = math.max(hedge.Size.Y - HedgeConfigs.BRANCH_TOP_CLEARANCE, hedge.Size.Y * 0.2)
	local size = Vector3.new(width, height, depth)
	branch.Size = size

	-- LE BAS RESTE A FLEUR DU SOL, quelles que soient les marges.
	--
	-- Une haie pose par terre. Une couche simplement centree flotterait, et la fente sous elle se verrait de
	-- loin sur toute la longueur. On la redescend donc de la moitie de ce qu'elle a perdu en hauteur : le bas
	-- retombe pile sur celui de la haie, et tout le retrait part vers le haut, la ou il ne se voit pas.
	branch.CFrame = hedge.CFrame * CFrame.new(0, -(hedge.Size.Y - size.Y) * 0.5, 0)
	branch.Parent = getBranchFolder()
	branches[hedge] = branch
	return true
end

function HedgeBranchService.init()
	-- Resolus AVANT la premiere haie, sinon celles deja etiquetees sortiraient creuses.
	layers = resolveLayers()

	local count = 0
	for _, instance in ipairs(CollectionService:GetTagged(HedgeConfigs.TAG)) do
		if instance:IsA("BasePart") and buildHedge(instance) then
			count += 1
		end
	end

	CollectionService:GetInstanceAddedSignal(HedgeConfigs.TAG):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			buildHedge(instance)
		end
	end)

	CollectionService:GetInstanceRemovedSignal(HedgeConfigs.TAG):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			clearHedge(instance)
		end
	end)

	-- On annonce les proportions LUES sur chaque modele. C'est le seul moyen de verifier d'un coup d'oeil que
	-- le choix automatique a de quoi travailler : un modele dont la taille ne correspond a rien se repere ici,
	-- pas apres une demi-heure a se demander pourquoi une haie est mal habillee.
	local report = {}
	for _, layer in ipairs(layers) do
		local r = layer.reference
		table.insert(report, `{math.round(r.X)}x{math.round(r.Y)}x{math.round(r.Z)}`)
	end
	print(
		`[HedgeBranchService] {count} haie(s) habillee(s), {#layers} modele(s) : {table.concat(report, ", ")}`
	)
end

return HedgeBranchService
