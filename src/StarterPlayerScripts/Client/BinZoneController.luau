--!strict
-- LA ZONE AUTOUR DU SEAU POSE : le cercle au sol (`AreaActionCercle`), et le remplissage du seau dessine dedans.
--
-- IL NE DECIDE RIEN. C'est le serveur qui fait entrer les feuilles (RakeService, LeafCollectService). Ici on dessine
-- le MEME rayon (`BinConfigs.ZONE_RADIUS`) avec la MEME regle (`BinUtils`), donc ce qu'on voit dans le cercle est
-- dans le cercle.
--
-- CHEZ CHAQUE CLIENT, pas au serveur : c'est un dessin. Le compte vit deja sur le seau en attribut, chaque joueur
-- le lit et dessine le sien -- rien a faire transiter.
--
-- RANGE A PART, JAMAIS DANS LE SEAU. Ajouter des parts au modele du seau decalerait son pivot (il suit la boite
-- englobante), et tout ce qui le porte ou le repose partirait de travers sans que rien ne le signale.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BinConfigs = require(ReplicatedStorage.Modules.Configs.BinConfigs)
local BinUtils = require(ReplicatedStorage.Modules.Utils.BinUtils)

local BinZoneController = {}

type Zone = {
	model: Model,
	root: BasePart,
	fill: GuiObject?,
	fillSize: UDim2,
	text: TextLabel?,
	ratio: number,
	at: Vector3?,
}

local FOLDER_NAME = "LeafiaBinZones"

local zones: { [Model]: Zone } = {}
local bins: { Model } = {}
local folder: Folder? = nil
local warnedNoAsset = false

local function getFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	folder = created
	return created
end

--- Le modele du cercle, ou nil. Resolu a chaque creation : il vient de `Assets`, que Rojo ne synchronise pas.
local function template(): Model?
	local node: Instance? = ReplicatedStorage
	for _, step in BinConfigs.ZONE_ASSET_PATH do
		node = node and node:FindFirstChild(step)
	end
	if node and node:IsA("Model") then
		return node :: Model
	end
	-- ANORMAL ET ACTIONNABLE : le ramassage marche, mais le joueur ne voit aucun cercle. Dit une fois.
	if not warnedNoAsset then
		warnedNoAsset = true
		warn(
			`[BinZoneController] Pas de ReplicatedStorage.{table.concat(BinConfigs.ZONE_ASSET_PATH, ".")} : aucun `
				.. "cercle autour des seaux. Rojo ne synchronise pas Assets, il faut le copier dans CETTE place."
		)
	end
	return nil
end

--- Demi-etendue d'une part le long d'un axe du MONDE. Juste aussi pour une part tournee : c'est la projection de
--- ses trois axes sur celui qu'on mesure.
local function halfAlong(part: BasePart, axis: Vector3): number
	local cf, size = part.CFrame, part.Size
	return 0.5
		* (
			math.abs(cf.XVector:Dot(axis)) * size.X
			+ math.abs(cf.YVector:Dot(axis)) * size.Y
			+ math.abs(cf.ZVector:Dot(axis)) * size.Z
		)
end

--- Le point le plus BAS du seau : c'est la que le sol se trouve, puisqu'il est pose dessus. Aucun rayon a lancer.
local function lowestY(bin: Model): number?
	local lowest: number? = nil
	for _, d in bin:GetDescendants() do
		if d:IsA("BasePart") then
			local part = d :: BasePart
			local y = part.Position.Y - halfAlong(part, Vector3.yAxis)
			if not lowest or y < lowest then
				lowest = y
			end
		end
	end
	return lowest
end

local function scaled(size: UDim2, k: number): UDim2
	return UDim2.new(size.X.Scale * k, size.X.Offset * k, size.Y.Scale * k, size.Y.Offset * k)
end

local function makeZone(): Zone?
	local source = template()
	if not source then
		return nil
	end
	local clone = source:Clone()
	local found = clone:FindFirstChild(BinConfigs.ZONE_ROOT_NAME, true)
	local root: BasePart? = if found and found:IsA("BasePart")
		then found :: BasePart
		else clone:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		clone:Destroy()
		return nil
	end
	-- UN DESSIN, RIEN D'AUTRE : il ne doit ni bloquer, ni etre vu par les lancers (curseur, sol), ni tomber.
	-- `CanQuery` ne prend effet que parce que `CanCollide` est deja faux.
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	clone.Parent = getFolder()

	-- LE CERCLE EST MIS AU RAYON DU SERVEUR. Ce n'est pas la taille posee dans Studio qui decide : sinon le dessin
	-- et la zone qui avale les feuilles diraient deux choses differentes.
	local r = root :: BasePart
	local diameter = math.max(halfAlong(r, Vector3.xAxis), halfAlong(r, Vector3.zAxis)) * 2
	if diameter > 1e-3 then
		clone:ScaleTo(clone:GetScale() * (BinConfigs.ZONE_RADIUS * 2 / diameter))
	end

	-- LE ROND GRANDIT DEPUIS LE CENTRE. On garde sa taille pleine, on le recentre sur son milieu, et on part de rien.
	local fillFound = clone:FindFirstChild(BinConfigs.ZONE_PROGRESS_FRAME, true)
	local fill: GuiObject? = if fillFound and fillFound:IsA("GuiObject") then fillFound :: GuiObject else nil
	local fillSize = UDim2.new()
	if fill then
		local f = fill :: GuiObject
		fillSize = f.Size
		local a, p = f.AnchorPoint, f.Position
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(
			p.X.Scale + (0.5 - a.X) * fillSize.X.Scale,
			p.X.Offset + (0.5 - a.X) * fillSize.X.Offset,
			p.Y.Scale + (0.5 - a.Y) * fillSize.Y.Scale,
			p.Y.Offset + (0.5 - a.Y) * fillSize.Y.Offset
		)
		f.Size = scaled(fillSize, 0)
	end
	local textFound = clone:FindFirstChild(BinConfigs.ZONE_PROGRESS_TEXT, true)
	return {
		model = clone,
		root = r,
		fill = fill,
		fillSize = fillSize,
		text = if textFound and textFound:IsA("TextLabel") then textFound :: TextLabel else nil,
		ratio = -1,
		at = nil,
	}
end

--- Pose le cercle sous le seau, au sol. Ne touche a rien si le seau n'a pas bouge.
local function place(zone: Zone, bin: Model)
	local binRoot = BinUtils.root(bin)
	local ground = lowestY(bin)
	if not (binRoot and ground) then
		return
	end
	local center = Vector3.new(
		binRoot.Position.X,
		(ground :: number) + halfAlong(zone.root, Vector3.yAxis) + BinConfigs.ZONE_LIFT,
		binRoot.Position.Z
	)
	local at = zone.at
	if at and (center - at).Magnitude < 0.02 then
		return
	end
	zone.model:PivotTo(zone.model:GetPivot() + (center - zone.root.Position))
	zone.at = center
end

local function setFill(zone: Zone, bin: Model)
	local ratio = math.clamp(BinUtils.contents(bin) / BinConfigs.LEAVES_CAPACITY, 0, 1)
	if math.abs(ratio - zone.ratio) < 1e-3 then
		return
	end
	zone.ratio = ratio
	local fill = zone.fill
	if fill then
		TweenService:Create(
			fill,
			TweenInfo.new(BinConfigs.ZONE_FILL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = scaled(zone.fillSize, ratio) }
		):Play()
	end
	local text = zone.text
	if text then
		-- PLEIN SE DIT AVEC UN MOT, comme dans le prompt du seau.
		text.Text = if ratio >= 1 then BinConfigs.GAUGE_FULL_TEXT else `{math.floor(ratio * 100)}%`
	end
end

function BinZoneController.init()
	local nextScan, nextCheck = 0, 0
	local seen: { [Model]: boolean } = {}
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		-- LA LISTE DES SEAUX se relit lentement : elle parcourt tout le Workspace, herbe comprise. Un seau qui sort du
		-- camion ou arrive par le streaming est vu au tour suivant.
		if now >= nextScan then
			nextScan = now + BinConfigs.RESCAN_INTERVAL
			BinUtils.collect(bins)
		end
		if now < nextCheck then
			return
		end
		nextCheck = now + BinConfigs.GAUGE_INTERVAL

		table.clear(seen)
		for _, bin in bins do
			-- `isBin` EST RETESTE : un seau range dans la benne reste dans la liste jusqu'au prochain balayage, et il
			-- est ancre sans porteur -- il aurait donc son cercle, dans le camion.
			if bin.Parent and BinUtils.isBin(bin) and BinUtils.isOnGround(bin) then
				local zone = zones[bin] or makeZone()
				if zone then
					zones[bin] = zone
					place(zone, bin)
					setFill(zone, bin)
					seen[bin] = true
				end
			end
		end
		for bin, zone in zones do
			if not seen[bin] then
				zone.model:Destroy()
				zones[bin] = nil
			end
		end
	end)

	print("[BinZoneController] Pret : un cercle autour de chaque seau pose.")
end

return BinZoneController
