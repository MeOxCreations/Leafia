--!strict
-- Terre au sol : un tas pose sous chaque haie, pour qu'elle ait l'air d'en pousser.
--
-- Sans lui, la haie est une boite verte posee sur l'herbe : la jointure entre son pied et le sol est une ligne
-- nette qui trahit le decor. Un monticule de terre a la base casse cette ligne et ancre la haie dans le jardin.
--
-- Purement decoratif : aucun etat, aucune coupe, aucun attribut. Une seule part par haie.
--
-- POURQUOI UN SERVICE A PART de HedgeBranchService : celui-la habille l'INTERIEUR de la haie, celui-ci le SOL
-- en dessous. Deux concerns, deux fichiers. Le jour ou la terre aura sa logique (boue apres la pluie, traces de
-- pas), elle tiendra ici sans toucher au reste.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)

local HedgeGroundService = {}

-- Modele de terre, resolu UNE fois. Le chercher a chaque haie ferait un parcours d'arborescence pour toujours
-- trouver la meme chose.
local dirtTemplate: BasePart? = nil
local grounds: { [BasePart]: BasePart } = {}
local groundFolder: Folder? = nil

local function resolveDirt(): BasePart?
	local source: Instance? = ReplicatedStorage
	for _, name in ipairs(HedgeConfigs.DIRT_ASSET) do
		source = source and source:FindFirstChild(name)
	end
	if not (source and source:IsA("BasePart")) then
		-- Anormal ET actionnable : sans terre, les haies flottent sur l'herbe avec une jointure nette.
		warn(`[HedgeGroundService] Terre introuvable : ReplicatedStorage.{table.concat(HedgeConfigs.DIRT_ASSET, ".")}`)
		return nil
	end

	local part = source:Clone()
	part.Name = HedgeConfigs.DIRT_NAME
	-- On garde SA couleur et SON materiau : c'est ce qui a ete regle dans Studio sur le mesh de terre. Les
	-- reecrire ici creerait une deuxieme verite qui finirait par mentir.
	part.Anchored = true
	part.Massless = true
	part.CanCollide = false
	-- CanQuery n'a d'effet que parce que CanCollide est deja faux. Sans ca, la terre au pied de la haie serait
	-- vue par le lancer du curseur, qui viserait bas et taillerait la terre au lieu de la haie.
	part.CanQuery = false
	part.CanTouch = false
	-- Au ras du sol : son ombre serait ecrasee par celle de la haie juste au-dessus. On ne la paie pas.
	part.CastShadow = false
	return part
end

local function getGroundFolder(): Folder
	local existing = groundFolder
	if existing and existing.Parent then
		return existing
	end
	local found = workspace:FindFirstChild(HedgeConfigs.DIRT_FOLDER)
	if found and found:IsA("Folder") then
		groundFolder = found
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = HedgeConfigs.DIRT_FOLDER
	folder.Parent = workspace
	groundFolder = folder
	return folder
end

local function clearHedge(hedge: BasePart)
	local ground = grounds[hedge]
	if ground then
		ground:Destroy()
		grounds[hedge] = nil
	end
end

local function buildHedge(hedge: BasePart): boolean
	clearHedge(hedge)

	local template = dirtTemplate
	if not template then
		return false
	end

	local ground = template:Clone()
	local margin = HedgeConfigs.DIRT_MARGIN
	local thickness = HedgeConfigs.DIRT_THICKNESS
	-- Emprise de la haie plus une marge FIXE de chaque cote, epaisseur reglee a part : le mesh deforme s'etire a
	-- cette boite. Le debord constant (margin) fait le tas, et il ne s'allonge pas sur les haies longues.
	ground.Size = Vector3.new(hedge.Size.X + margin * 2, thickness, hedge.Size.Z + margin * 2)

	-- HAUT DE LA TERRE au pied de la haie, remonte de DIRT_HEIGHT : le pied de la haie s'enfonce d'autant, et la
	-- jointure nette avec le sol disparait sous la terre.
	-- Centre = haut - moitie de l'epaisseur. On travaille dans le repere de la haie puis on ramene en monde :
	-- une haie tournee se traite comme une haie droite.
	local topLocalY = -hedge.Size.Y * 0.5 + HedgeConfigs.DIRT_HEIGHT
	ground.CFrame = hedge.CFrame * CFrame.new(0, topLocalY - thickness * 0.5, 0)
	ground.Parent = getGroundFolder()
	grounds[hedge] = ground
	return true
end

function HedgeGroundService.init()
	-- Resolu AVANT la premiere haie, sinon celles deja etiquetees sortiraient sans terre.
	dirtTemplate = resolveDirt()

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

	print(`[HedgeGroundService] {count} haie(s) posee(s) sur la terre`)
end

return HedgeGroundService
