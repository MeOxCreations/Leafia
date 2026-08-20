--!strict
-- HERBE DE ZONE. Remplit chaque part "ZoneGrass..." de touffes, et couche celles sur lesquelles un joueur marche.
--
-- TOUT EST LOCAL. Les touffes sont creees par CE client, dans SA copie du Workspace : rien ne part sur le reseau, ni
-- a la creation ni a l'ecrasement. C'est l'inverse du decor vegetal (FoliageService, serveur) et c'est voulu : le
-- balancement d'un arbre est le meme pour tout le monde, l'ecrasement de l'herbe depend de qui marche ou, a chaque
-- image. Repliquer ca chargerait le reseau pour un detail que chacun peut calculer chez lui.
--
-- Les touffes sont enfants de leur zone : si le streaming retire la zone, elles partent avec, sans nettoyage a ecrire.
-- Mais etre ENFANT ne veut PAS dire etre soude : une part ancree posee en coordonnees monde ne suit pas son parent.
-- D'ou la position de chaque touffe gardee dans le repere de la ZONE (localPos) et recalculee des que la zone bouge.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GrassZoneConfigs = require(ReplicatedStorage.Modules.Configs.GrassZoneConfigs)

local GrassZoneController = {}

local FOLDER_NAME = "GrassClumpsLocal"
local MAX_ANGLE = math.rad(GrassZoneConfigs.CRUSH_MAX_ANGLE)
local REST_TILT = math.rad(GrassZoneConfigs.REST_TILT)
-- Constante plutot que Vector3.yAxis : selene ne reconnait pas ce dernier comme un Vector3 et refuse Cross.
local UP = Vector3.new(0, 1, 0)

-- Repere du vent, calcule UNE fois. WIND_DIR est la direction horizontale du souffle ; WIND_AXIS est l'axe autour
-- duquel tourner pour que le HAUT de la touffe parte dans cette direction.
local WIND_DIR = Vector3.new(
	math.cos(math.rad(GrassZoneConfigs.WIND_HEADING)),
	0,
	math.sin(math.rad(GrassZoneConfigs.WIND_HEADING))
)
local WIND_AXIS = UP:Cross(WIND_DIR).Unit
local WIND_ANGLE = math.rad(GrassZoneConfigs.WIND_ANGLE)
local WIND_GUST = math.rad(GrassZoneConfigs.WIND_GUST)
local WIND_VIEW_SQ = GrassZoneConfigs.WIND_VIEW_DISTANCE * GrassZoneConfigs.WIND_VIEW_DISTANCE

-- Une touffe. On garde son PIED et sa rotation propre : le CFrame se recompose a chaque image a partir de ces
-- valeurs, JAMAIS a partir du CFrame precedent -- sinon l'inclinaison s'accumulerait et les touffes finiraient
-- couchees pour toujours.
-- localPos est dans le repere de la ZONE, basePos est sa traduction en monde (gardee en cache pour ne pas refaire
-- la multiplication a chaque image ; elle se recalcule quand la zone bouge, pas avant).
type Clump = {
	part: BasePart,
	localPos: Vector3, -- position du pied, dans le repere de la zone
	basePos: Vector3, -- la meme, en monde (cache)
	yaw: CFrame, -- rotation propre de la touffe (tirage au sort)
	halfHeight: number, -- demi-hauteur, pour remonter le CENTRE au-dessus du pied
	restTilt: number, -- inclinaison AU REPOS (radians) : une herbe parfaitement droite se lit comme du faux
	tiltDir: Vector3, -- direction horizontale de la bascule en cours
	tilt: number, -- angle d'ecrasement courant, en radians
	windPhase: number, -- decalage propre dans l'oscillation du vent (deux voisines ne bougent pas a l'identique)
	lastTilt: number, -- dernier angle REELLEMENT ecrit : sert a ne pas reecrire une touffe lointaine immobile
}

type Zone = {
	part: BasePart,
	clumps: { Clump },
	radius: number, -- rayon de la zone, pour l'ecarter d'un coup quand personne n'est autour
	settling: boolean, -- des touffes encore en mouvement ? on continue alors meme sans joueur pres
}

local zones: { Zone } = {}
local connections: { RBXScriptConnection } = {}
local template: BasePart? = nil
local heartbeat: RBXScriptConnection? = nil

-- ===== Resolution des dependances =====

-- Suit un chemin d'enfants sous `from`. RE-SCAN en boucle sous UN SEUL delai, pas un WaitForChild par segment : avec
-- un WaitForChild par segment, un chemin absent ferait attendre le timeout autant de fois qu'il y a de segments.
local function resolvePath(from: Instance, path: { string }): Instance?
	local deadline = os.clock() + GrassZoneConfigs.RESOLVE_TIMEOUT
	repeat
		local node: Instance? = from
		for _, name in ipairs(path) do
			node = node and node:FindFirstChild(name)
		end
		if node then
			return node
		end
		task.wait(0.25)
	until os.clock() >= deadline
	return nil
end

-- ===== Pose =====

-- Pose la touffe. On repart TOUJOURS du pied et de la rotation propre, jamais du CFrame precedent.
-- Deux inclinaisons se composent : l'ECRASEMENT (fuit le joueur, fort, direction variable) puis le VENT (direction
-- fixe, faible). Toutes deux sont calculees en MONDE, elles passent donc a gauche du yaw propre de la touffe.
-- Le dernier facteur remonte le CENTRE de la part au-dessus du pied, le long du haut DEJA incline.
local function apply(clump: Clump, windAngle: number)
	local cf = CFrame.new(clump.basePos)
	local crushAxis = UP:Cross(clump.tiltDir)
	if crushAxis.Magnitude > 1e-4 then
		cf = cf * CFrame.fromAxisAngle(crushAxis.Unit, clump.tilt)
	end
	if windAngle ~= 0 then
		cf = cf * CFrame.fromAxisAngle(WIND_AXIS, windAngle)
	end
	clump.part.CFrame = cf * clump.yaw * CFrame.new(0, clump.halfHeight, 0)
end

-- ===== Remplissage =====

-- Graine calculee sur la POSITION de la zone : le tirage au sort donne donc la MEME disposition chez tous les
-- joueurs, sans qu'un seul octet transite. Deux joueurs cote a cote voient exactement la meme herbe.
local function seedFor(part: BasePart): number
	local p = part.Position
	local raw = math.floor(p.X * 100) * 73856093 + math.floor(p.Y * 100) * 19349663 + math.floor(p.Z * 100) * 83492791
	return math.abs(raw) % 2147483647
end

-- (Re)cree les touffes d'une zone. Appele au boot, et de nouveau si la zone est REDIMENSIONNEE : la nouvelle surface
-- veut un autre nombre de touffes, reposer les anciennes ne suffirait pas.
local function populate(zone: Zone)
	local source = template
	if not source then
		return
	end

	local previous = zone.part:FindFirstChild(FOLDER_NAME)
	if previous then
		previous:Destroy()
	end
	table.clear(zone.clumps)

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	local size = zone.part.Size
	local zoneCFrame = zone.part.CFrame
	local rng = Random.new(seedFor(zone.part))

	-- GRILLE. Une case par touffe, sur TOUTE la surface du dessus : c'est ce qui garantit qu'aucun coin ne reste
	-- chauve. `spacing` est le cote d'une case, deduit de la densite voulue.
	local spacing = 1 / math.sqrt(GrassZoneConfigs.DENSITY)
	local cols = math.max(1, math.ceil(size.X / spacing))
	local rows = math.max(1, math.ceil(size.Z / spacing))
	if cols * rows > GrassZoneConfigs.MAX_CLUMPS then
		-- Au plafond on ESPACE la grille, on ne coupe PAS la liste : couper laisserait une moitie de zone chauve, ce
		-- qui est exactement ce qu'on veut eviter.
		local factor = math.sqrt((cols * rows) / GrassZoneConfigs.MAX_CLUMPS)
		cols = math.max(1, math.floor(cols / factor))
		rows = math.max(1, math.floor(rows / factor))
		warn(
			`[GrassZone] "{zone.part.Name}" plafonne : grille ramenee a {cols}x{rows}. `
				.. `Monte MAX_CLUMPS si tu veux plus dense.`
		)
	end

	local stepX = size.X / cols
	local stepZ = size.Z / rows
	local jitter = GrassZoneConfigs.JITTER

	for ix = 0, cols - 1 do
		for iz = 0, rows - 1 do
			local part = source:Clone()
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false -- n'a d'effet QUE parce que CanCollide est faux
			part.CanTouch = false
			part.CastShadow = false -- des centaines d'ombres de brins coutent cher et ne se voient pas
			part.Size = source.Size * rng:NextNumber(GrassZoneConfigs.SCALE_MIN, GrassZoneConfigs.SCALE_MAX)

			-- Centre de la case, plus un ecart au hasard DANS la case. Garde dans le repere de la ZONE : une zone
			-- tournee ou inclinee marche sans cas particulier, et la deplacer n'oblige qu'a retraduire ce point.
			local localPos = Vector3.new(
				-size.X * 0.5 + (ix + 0.5) * stepX + rng:NextNumber(-0.5, 0.5) * stepX * jitter,
				size.Y * 0.5,
				-size.Z * 0.5 + (iz + 0.5) * stepZ + rng:NextNumber(-0.5, 0.5) * stepZ * jitter
			)

			-- Inclinaison de repos : une direction au hasard, un petit angle.
			local restTilt = rng:NextNumber(0, REST_TILT)
			local restAngle = rng:NextNumber(0, math.pi * 2)

			local clump: Clump = {
				part = part,
				localPos = localPos,
				basePos = zoneCFrame:PointToWorldSpace(localPos),
				yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				halfHeight = part.Size.Y * 0.5,
				restTilt = restTilt,
				tiltDir = Vector3.new(math.cos(restAngle), 0, math.sin(restAngle)),
				tilt = restTilt,
				windPhase = rng:NextNumber(0, math.pi * 2),
				lastTilt = restTilt,
			}
			-- POSEE TOUT DE SUITE, pas a la 1re passe de la boucle. Dependre d'une passe ulterieure pour le placement
			-- INITIAL, c'est laisser les touffes au point de clonage si cette passe saute pour une raison ou une autre.
			apply(clump, WIND_ANGLE)
			zone.clumps[#zone.clumps + 1] = clump
			part.Parent = folder
		end
	end

	folder.Parent = zone.part

	local half = size * 0.5
	zone.radius = math.sqrt(half.X * half.X + half.Z * half.Z)
	zone.settling = true
end

-- La zone a bouge : on retraduit les pieds en monde et on reveille les touffes pour qu'elles se reposent au bon
-- endroit. Etre enfant d'une part ne suffit pas a suivre : une part ancree vit en coordonnees monde.
local function refresh(zone: Zone)
	local zoneCFrame = zone.part.CFrame
	for _, clump in ipairs(zone.clumps) do
		clump.basePos = zoneCFrame:PointToWorldSpace(clump.localPos)
		clump.lastTilt = math.huge -- force une reecriture : la touffe doit se reposer au nouvel endroit
	end
	zone.settling = true
end

-- ===== Ecrasement =====

local function updateZone(zone: Zone, positions: { Vector3 }, camPos: Vector3, now: number, dt: number)
	local radius = GrassZoneConfigs.CRUSH_RADIUS
	local moving = 0

	for _, clump in ipairs(zone.clumps) do
		-- Le joueur le PLUS proche gagne. On ne MOYENNE pas les directions : deux joueurs de part et d'autre d'une
		-- touffe la redresseraient, ce qui est l'inverse du sens voulu.
		local best = 0
		local bestDir = clump.tiltDir
		for _, pos in ipairs(positions) do
			local d = clump.basePos - pos
			d = Vector3.new(d.X, 0, d.Z) -- horizontal : sauter ne doit pas relever l'herbe
			local dist = d.Magnitude
			if dist < radius then
				local strength = 1 - dist / radius
				if strength > best then
					best = strength
					bestDir = if dist > 1e-3 then d / dist else clump.tiltDir
				end
			end
		end

		-- La cible retombe sur l'inclinaison de REPOS, pas sur zero : sinon le passage du joueur "repasserait" l'herbe
		-- parfaitement droite derriere lui, ce qui se voit comme un couloir trop propre.
		local target = if best > 0 then math.max(best * MAX_ANGLE, clump.restTilt) else clump.restTilt
		if best > 0 then
			clump.tiltDir = bestDir
		end

		-- Ecraser est BRUTAL (le pied arrive d'un coup), se relever est LENT : c'est cet ecart qui fait lire le poids.
		local speed = if target > clump.tilt then GrassZoneConfigs.CRUSH_SPEED else GrassZoneConfigs.RECOVER_SPEED
		clump.tilt += (target - clump.tilt) * (1 - math.exp(-speed * dt))
		if math.abs(target - clump.tilt) < GrassZoneConfigs.SNAP_EPSILON then
			clump.tilt = target -- un lerp exponentiel n'atteint jamais sa cible : sans ce clic, on reecrirait a vie
		end
		if clump.tilt ~= target then
			moving += 1
		end

		-- VENT. Trop loin de la CAMERA, on ne calcule rien : le mouvement d'un brin ne se voit pas a cette distance,
		-- mais il coute exactement le meme prix. C'est ce tri qui rend un grand champ abordable.
		local toCam = clump.basePos - camPos
		local far = toCam.X * toCam.X + toCam.Y * toCam.Y + toCam.Z * toCam.Z > WIND_VIEW_SQ

		local wind = 0
		if not far then
			-- Le decalage depend de la POSITION le long du vent : les touffes en amont bougent avant celles en aval,
			-- donc des vagues traversent le champ au lieu qu'il respire en bloc. windPhase casse ce qui resterait
			-- d'identique entre deux voisines exactement alignees.
			local phase = now * GrassZoneConfigs.WIND_SPEED
				- (clump.basePos.X * WIND_DIR.X + clump.basePos.Z * WIND_DIR.Z) * GrassZoneConfigs.WIND_WAVE
				+ clump.windPhase
			wind = WIND_ANGLE + WIND_GUST * math.sin(phase)
			-- Une touffe couchee sous un pied ne doit plus onduler : le vent s'efface a mesure qu'elle est ecrasee.
			local crushed = (clump.tilt - clump.restTilt) / math.max(MAX_ANGLE - clump.restTilt, 1e-3)
			wind *= 1 - math.clamp(crushed, 0, 1)
		end

		-- Pres de la camera on ecrit TOUJOURS (le vent bouge en permanence). Loin, on n'ecrit que si l'ecrasement a
		-- change : une touffe lointaine et immobile ne coute alors plus rien du tout.
		if not far or clump.tilt ~= clump.lastTilt then
			apply(clump, wind)
			clump.lastTilt = clump.tilt
		end
	end

	zone.settling = moving > 0
end

local function update(dt: number)
	if #zones == 0 then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return -- tot au boot la camera peut ne pas exister encore
	end
	local camPos = camera.CFrame.Position
	local now = os.clock()

	-- Positions des personnages, relevees UNE fois par image et partagees par toutes les zones.
	local positions: { Vector3 } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			positions[#positions + 1] = root.Position
		end
	end

	for _, zone in ipairs(zones) do
		if zone.part.Parent ~= nil then
			-- Ecarte d'un bloc les zones hors de vue. Une zone dont des touffes se relevent encore garde la main, sinon
			-- elles se figeraient couchees des qu'on tourne la camera.
			local d = zone.part.Position - camPos
			local reach = zone.radius + GrassZoneConfigs.WIND_VIEW_DISTANCE
			if d.Magnitude < reach or zone.settling then
				updateZone(zone, positions, camPos, now, dt)
			end
		end
	end
end

-- ===== Boot =====

function GrassZoneController.init()
	-- EN TACHE DE FOND : resolvePath peut attendre, et un init de boot ne doit jamais bloquer la sequence.
	task.spawn(function()
		local source = resolvePath(ReplicatedStorage, GrassZoneConfigs.MESH_PATH)
		if not source or not source:IsA("BasePart") then
			warn(
				`[GrassZone] Mesh introuvable : ReplicatedStorage.{table.concat(GrassZoneConfigs.MESH_PATH, ".")}. `
					.. `Pas d'herbe de zone.`
			)
			return
		end
		template = source

		local root = resolvePath(workspace, GrassZoneConfigs.ROOT)
		if not root then
			warn(
				`[GrassZone] Dossier introuvable : Workspace.{table.concat(GrassZoneConfigs.ROOT, ".")}. `
					.. `Pas d'herbe de zone dans cette place.`
			)
			return
		end

		local prefix = GrassZoneConfigs.ZONE_PREFIX
		local function consider(instance: Instance)
			-- Le nom D'ABORD : ce test tourne sur tout ce qui arrive dans la map, il doit rester le moins cher possible.
			if instance.Name:sub(1, #prefix) ~= prefix or not instance:IsA("BasePart") then
				return
			end
			if instance:FindFirstChild(FOLDER_NAME) then
				return -- deja remplie
			end

			local zone: Zone = { part = instance, clumps = {}, radius = 0, settling = true }
			populate(zone)
			zones[#zones + 1] = zone

			-- L'herbe SUIT sa zone. Deplacer la part (dans Studio, pendant un test, ou par du code) retraduit les
			-- pieds ; la redimensionner refait le semis, parce que la nouvelle surface veut un autre nombre de touffes.
			connections[#connections + 1] = instance:GetPropertyChangedSignal("CFrame"):Connect(function()
				refresh(zone)
			end)
			connections[#connections + 1] = instance:GetPropertyChangedSignal("Size"):Connect(function()
				populate(zone)
			end)
		end

		for _, descendant in ipairs(root:GetDescendants()) do
			consider(descendant)
		end
		-- Les zones qui arrivent apres (streaming, edition en live) se remplissent aussi. On n'ecoute QUE ce dossier :
		-- brancher workspace.DescendantAdded ferait passer chaque part de personnage par le test pour rien.
		connections[#connections + 1] = root.DescendantAdded:Connect(consider)

		if #zones == 0 then
			print(`[GrassZone] Aucune zone "{prefix}..." dans cette place.`)
			return
		end

		-- Log detaille EXPRES : quand l'herbe se pose au mauvais endroit, ces trois nombres (taille de la zone, centre
		-- de la zone, position de la 1re touffe) disent tout de suite si c'est le semis ou la zone qui est en cause.
		for _, zone in ipairs(zones) do
			local first = zone.clumps[1]
			local where = if first then tostring(first.part.Position) else "aucune"
			print(
				`[GrassZone] "{zone.part.Name}" : {#zone.clumps} touffe(s) | zone {zone.part.Size} @ `
					.. `{zone.part.Position} | 1re touffe @ {where}`
			)
		end

		heartbeat = RunService.Heartbeat:Connect(update)
	end)
end

-- Coupe TOUT ce que ce module a cree : la boucle, les ecoutes et les touffes. Ces connexions vivent sur RunService et
-- sur des parts de la map, qui SURVIVENT a ce script : sans Disconnect explicite elles tourneraient toute la session.
function GrassZoneController.stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, zone in ipairs(zones) do
		local folder = zone.part:FindFirstChild(FOLDER_NAME)
		if folder then
			folder:Destroy()
		end
	end
	table.clear(zones)
end

return GrassZoneController
