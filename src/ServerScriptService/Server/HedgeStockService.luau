--!strict
-- Zones de DEPOT au sol : une bande le long de chacun des quatre cotes de chaque haie.
--
-- Les feuilles coupees y tombent en tas, dans la zone la plus proche du joueur. Elles se ramasseront plus tard
-- au rateau, partiront dans un conteneur puis dans le camion.
--
-- C'est la raison pour laquelle ce service est separe de HedgeCellService : la grille de coupe et le cycle du
-- dechet sont deux features, pas une. Le jour ou le rateau existera, il ne touchera qu'a ce fichier.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)

local HedgeStockService = {}

local UP = Vector3.yAxis

-- Les QUATRE cotes, en axes locaux de la haie. Pas de dessus ni de dessous : une zone de depot se pose au sol.
local SIDES = {
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
}

local stocks: { [BasePart]: Folder } = {}
local stockFolder: Folder? = nil

-- Modele de tas, resolu UNE fois. Le chercher a chaque depot ferait un parcours d'arborescence pour toujours
-- trouver la meme chose.
local debrisTemplate: Model? = nil
-- Tas deja poses, PAR ZONE. Une liste par zone et non une globale : le plafond garde ainsi les quatre cotes
-- equilibres, au lieu qu'un cote tres travaille mange la place des autres.
local piles: { [BasePart]: { Model } } = {}

local function resolveDebris(): Model?
	local source: Instance? = ReplicatedStorage
	for _, name in ipairs(HedgeConfigs.STOCK_DEBRIS_ASSET) do
		source = source and source:FindFirstChild(name)
	end
	if not (source and source:IsA("Model")) then
		warn(`[HedgeStockService] Tas introuvable : ReplicatedStorage.{table.concat(HedgeConfigs.STOCK_DEBRIS_ASSET, ".")}`)
		return nil
	end

	local model = source:Clone()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			-- CanQuery n'a d'effet que parce que CanCollide est deja faux. Sans ca, un tas pose aux pieds du
			-- joueur serait vu par le lancer du curseur et par la detection de haie.
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Massless = true
		end
	end
	return model
end

local function getStockFolder(): Folder
	local existing = stockFolder
	if existing and existing.Parent then
		return existing
	end
	local found = workspace:FindFirstChild(HedgeConfigs.STOCK_FOLDER)
	if found and found:IsA("Folder") then
		stockFolder = found
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = HedgeConfigs.STOCK_FOLDER
	folder.Parent = workspace
	stockFolder = folder
	return folder
end

-- Demi-dimension de la haie le long d'un axe LOCAL. Somme des composantes en valeur absolue : pour un axe
-- cardinal ca revient a prendre la bonne demi-taille, et ca reste juste pour un axe compose.
local function halfAlong(half: Vector3, axis: Vector3): number
	return math.abs(axis.X * half.X) + math.abs(axis.Y * half.Y) + math.abs(axis.Z * half.Z)
end

local function clearHedge(hedge: BasePart)
	local folder = stocks[hedge]
	if folder then
		-- Les listes de tas pointent sur des zones de CE dossier : les oublier ici evite de garder des tables
		-- qui referencent des objets detruits.
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				piles[child] = nil
			end
		end
		folder:Destroy()
		stocks[hedge] = nil
	end
end

local function buildHedge(hedge: BasePart)
	clearHedge(hedge)

	local folder = Instance.new("Folder")
	folder.Name = hedge.Name

	local half = hedge.Size * 0.5
	local width = HedgeConfigs.STOCK_WIDTH
	local thickness = HedgeConfigs.STOCK_THICKNESS

	for index, normal in ipairs(SIDES) do
		-- Axe le long duquel la bande s'etire : celui des deux horizontaux qui n'est pas celui de la face.
		-- lateral x haut = normal, donc le repere reste direct et la dalle n'est pas retournee.
		local lateral = UP:Cross(normal)
		local halfLateral = halfAlong(half, lateral)
		local halfDepth = halfAlong(half, normal)

		local part = Instance.new("Part")
		part.Name = HedgeConfigs.STOCK_NAME
		-- X suit le cote borde, Y est l'epaisseur, Z la profondeur de la bande vers l'exterieur.
		part.Size = Vector3.new(halfLateral * 2, thickness, width)
		part.Color = HedgeConfigs.STOCK_COLOR
		part.Transparency = HedgeConfigs.STOCK_TRANSPARENCY
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.Massless = true
		part.CanCollide = false
		-- CanQuery ne prend effet que parce que CanCollide est deja faux. Sans ca, la bande serait vue par les
		-- lancers du curseur et de la detection, et elle est posee juste aux pieds du joueur.
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth

		-- AU SOL, c'est-a-dire au niveau du PIED de la haie et non de son centre. Une haie de huit studs de haut
		-- verrait sinon ses bandes flotter a mi-hauteur.
		local offset = normal * (halfDepth + HedgeConfigs.STOCK_GAP + width * 0.5)
			+ Vector3.new(0, -half.Y + thickness * 0.5 + HedgeConfigs.STOCK_LIFT, 0)
		part.CFrame = hedge.CFrame * CFrame.fromMatrix(offset, lateral, UP, normal)
		part.Parent = folder

		-- Numerote : plus tard il faudra savoir DANS QUELLE zone une feuille doit voler, et un nom unique par
		-- cote evite d'avoir a comparer des positions.
		part.Name = `{HedgeConfigs.STOCK_NAME}_{index}`
	end

	folder.Parent = getStockFolder()
	stocks[hedge] = folder
end

-- Depose un tas dans la zone la plus proche de `from`, a un endroit tire au hasard dedans.
--
-- La zone est choisie par PROXIMITE et non par la face travaillee : dans un angle, le joueur est entre deux
-- faces, et le tas doit tomber la ou il se tient, pas la ou le code a decide qu'il travaillait.
function HedgeStockService.drop(hedge: BasePart, from: Vector3)
	local template = debrisTemplate
	local folder = stocks[hedge]
	if not (template and folder) then
		return
	end

	-- ZONE LA PLUS PROCHE, mesuree a sa SURFACE et non a son centre.
	--
	-- Au centre, une bande longue perdait contre une bande courte des que le joueur travaillait pres d'un bout :
	-- le centre du BOUT etait plus proche que le centre du grand cote, alors qu'il avait les pieds sur celui-ci.
	-- Les feuilles tombaient donc de l'autre cote de la haie.
	local zone: BasePart? = nil
	local best = math.huge
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			local localPoint = child.CFrame:PointToObjectSpace(from)
			local half = child.Size * 0.5
			-- Point le plus proche DANS la bande : la distance a ce point est la distance a la bande.
			local clamped = Vector3.new(
				math.clamp(localPoint.X, -half.X, half.X),
				math.clamp(localPoint.Y, -half.Y, half.Y),
				math.clamp(localPoint.Z, -half.Z, half.Z)
			)
			local distance = (localPoint - clamped).Magnitude
			if distance < best then
				best = distance
				zone = child
			end
		end
	end
	if not zone then
		return
	end

	-- AUX PIEDS DU JOUEUR, pas au hasard dans la zone.
	--
	-- Disperser les tas partout ferait un decor ; les poser la ou il travaille fait une TRACE. On voit son
	-- parcours au sol, donc ce qui est fait et ce qui reste. Le hasard ne sert plus qu'a eviter que deux tas se
	-- superposent exactement.
	local inset = HedgeConfigs.STOCK_DEBRIS_INSET
	local jitter = HedgeConfigs.STOCK_DEBRIS_JITTER
	local half = zone.Size * 0.5
	local feet = zone.CFrame:PointToObjectSpace(from)

	-- L'axe Z de la bande pointe vers l'EXTERIEUR de la haie : -half.Z est le bord cote haie, +half.Z le bord
	-- oppose. On place donc la profondeur par reglage et non d'apres le joueur, qui se tient toujours du cote
	-- haie et y collerait tous les tas.
	local depthMin, depthMax = -(half.Z - inset), half.Z - inset
	-- Profondeur TIREE autour du reglage : sans dispersion, tous les tas s'alignent et on lit la mecanique au
	-- lieu de voir des feuilles. Bornee a la bande, donc jamais de debordement sur l'herbe.
	local spread = (math.random() - 0.5) * 2 * HedgeConfigs.STOCK_DEBRIS_OUT_SPREAD
	local ratio = math.clamp(HedgeConfigs.STOCK_DEBRIS_OUT + spread, 0, 1)
	local depth = depthMin + (depthMax - depthMin) * ratio

	local offset = Vector3.new(
		math.clamp(feet.X + (math.random() - 0.5) * 2 * jitter, -(half.X - inset), half.X - inset),
		half.Y,
		depth
	)

	local pile = template:Clone()
	local scale = math.random() * (HedgeConfigs.STOCK_DEBRIS_SCALE_MAX - HedgeConfigs.STOCK_DEBRIS_SCALE_MIN)
		+ HedgeConfigs.STOCK_DEBRIS_SCALE_MIN
	pile:ScaleTo(scale)
	-- Oriente au hasard autour de la verticale : sans ca tous les tas sont alignes et on voit la grille.
	pile:PivotTo(zone.CFrame * CFrame.new(offset) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	pile.Parent = folder

	local list = piles[zone]
	if not list then
		list = {}
		piles[zone] = list
	end
	table.insert(list, pile)
	-- PLAFOND : le plus ancien part. Sans lui, une haie qui repousse et se retaille empilerait pour toujours.
	if #list > HedgeConfigs.STOCK_DEBRIS_MAX then
		local oldest = table.remove(list, 1)
		if oldest then
			oldest:Destroy()
		end
	end
end

function HedgeStockService.init()
	-- Resolu AVANT le premier depot possible.
	debrisTemplate = resolveDebris()

	local count = 0
	for _, instance in ipairs(CollectionService:GetTagged(HedgeConfigs.TAG)) do
		if instance:IsA("BasePart") then
			buildHedge(instance)
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

	print(`[HedgeStockService] {count * #SIDES} zones de depot sur {count} haie(s)`)
end

return HedgeStockService
