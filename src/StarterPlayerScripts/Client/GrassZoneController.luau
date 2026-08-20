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
	tilt: number, -- angle courant, en radians
	resting: boolean, -- au repos ? une touffe au repos ne se reecrit pas
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

	local wanted = math.floor(size.X * size.Z * GrassZoneConfigs.DENSITY)
	local count = math.min(wanted, GrassZoneConfigs.MAX_CLUMPS)
	if count < wanted then
		-- Anormal ET actionnable : sans ce mot, une zone plafonnee ressemble a une densite mal reglee, et on tourne
		-- le bouton DENSITY dans le vide sans que rien ne change.
		warn(
			`[GrassZone] "{zone.part.Name}" plafonne a {count} touffes (il en faudrait {wanted}). `
				.. `Monte MAX_CLUMPS ou baisse DENSITY.`
		)
	end

	for _ = 1, count do
		local part = source:Clone()
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false -- n'a d'effet QUE parce que CanCollide est faux
		part.CanTouch = false
		part.CastShadow = false -- des centaines d'ombres de brins coutent cher et ne se voient pas
		part.Size = source.Size * rng:NextNumber(GrassZoneConfigs.SCALE_MIN, GrassZoneConfigs.SCALE_MAX)

		-- Un point au hasard sur la face du DESSUS de la zone, garde dans le repere de la zone : une zone tournee ou
		-- inclinee marche donc sans cas particulier, et deplacer la zone n'oblige qu'a retraduire ce point.
		local localPos = Vector3.new(
			rng:NextNumber(-0.5, 0.5) * size.X,
			size.Y * 0.5,
			rng:NextNumber(-0.5, 0.5) * size.Z
		)

		-- Inclinaison de repos : une direction au hasard, un petit angle.
		local restTilt = rng:NextNumber(0, REST_TILT)
		local restAngle = rng:NextNumber(0, math.pi * 2)

		zone.clumps[#zone.clumps + 1] = {
			part = part,
			localPos = localPos,
			basePos = zoneCFrame:PointToWorldSpace(localPos),
			yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
			halfHeight = part.Size.Y * 0.5,
			restTilt = restTilt,
			tiltDir = Vector3.new(math.cos(restAngle), 0, math.sin(restAngle)),
			tilt = restTilt,
			resting = false, -- false expres : la 1re passe ecrit la pose de repos
		}
		part.Parent = folder
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
		clump.resting = false
	end
	zone.settling = true
end

-- ===== Ecrasement =====

-- Pose la touffe. On repart TOUJOURS du pied et de la rotation propre, jamais du CFrame precedent.
-- L'ordre compte : la bascule est calculee en MONDE (elle fuit le joueur), elle doit donc etre a gauche du yaw.
-- Le dernier facteur remonte le CENTRE de la part au-dessus du pied, le long du haut DEJA incline.
local function apply(clump: Clump)
	local axis = UP:Cross(clump.tiltDir)
	if axis.Magnitude < 1e-4 then
		return
	end
	local tilt = CFrame.fromAxisAngle(axis.Unit, clump.tilt)
	clump.part.CFrame = CFrame.new(clump.basePos) * tilt * clump.yaw * CFrame.new(0, clump.halfHeight, 0)
end

local function updateZone(zone: Zone, positions: { Vector3 }, dt: number)
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

		local resting = clump.tilt == target and best <= 0
		-- Le "not clump.resting" fait la DERNIERE ecriture, celle qui repose la touffe. Sans elle, elle se figerait a
		-- un cheveu de sa pose de repos.
		if not resting or not clump.resting then
			apply(clump)
		end
		clump.resting = resting
		if not resting then
			moving += 1
		end
	end

	zone.settling = moving > 0
end

local function update(dt: number)
	if #zones == 0 then
		return
	end

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
			-- Ecarte d'un coup les zones ou personne ne marche. Une zone dont des touffes se relevent encore continue
			-- d'etre traitee, sinon elles se figeraient couchees des que le joueur s'eloigne.
			local near = false
			local center = zone.part.Position
			local reach = zone.radius + GrassZoneConfigs.CRUSH_RADIUS
			for _, pos in ipairs(positions) do
				local d = center - pos
				if Vector3.new(d.X, 0, d.Z).Magnitude < reach then
					near = true
					break
				end
			end
			if near or zone.settling then
				updateZone(zone, positions, dt)
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

		local total = 0
		for _, zone in ipairs(zones) do
			total += #zone.clumps
		end
		print(`[GrassZone] {#zones} zone(s), {total} touffe(s).`)

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
