--!strict
-- NUAGES. Un troupeau qui traverse le ciel en boucle, sans fin.
--
-- Les nuages derivent en coordonnees MONDE et NE SUIVENT PAS le joueur : c'est ce qui garde la parallaxe. Coller le
-- ciel au joueur donnerait des nuages qui semblent avancer avec lui, ce qui tue toute impression de distance.
-- Quand l'un s'eloigne trop, il est REMIS en amont du vent, a une place tiree au hasard. Comme sa transparence monte
-- bien avant cette limite, le recyclage ne se voit jamais : il s'efface, il revient ailleurs, deja efface.
--
-- 100 % CLIENT : c'est du ciel, ca ne change aucune regle du jeu. Rien ne transite, et chaque joueur a le sien.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CloudConfigs = require(ReplicatedStorage.Modules.Configs.CloudConfigs)

local CloudController = {}

local localPlayer = Players.LocalPlayer
local rng = Random.new()

local FOLDER_NAME = "LeafiaCloudsLocal"
-- Direction du vent, calculee une fois.
local DRIFT = Vector3.new(math.cos(math.rad(CloudConfigs.HEADING)), 0, math.sin(math.rad(CloudConfigs.HEADING)))

type Cloud = {
	part: BasePart,
	speed: number, -- vitesse propre : sans ecart entre nuages, le ciel derive d'un bloc comme une image
	altitude: number,
}

local clouds: { Cloud } = {}
local folder: Folder? = nil
local heartbeat: RBXScriptConnection? = nil

-- Suit un chemin d'enfants. RE-SCAN en boucle sous UN SEUL delai, pas un WaitForChild par segment : un chemin absent
-- ferait sinon attendre le timeout autant de fois qu'il y a de segments.
local function resolvePath(from: Instance, path: { string }): Instance?
	local deadline = os.clock() + CloudConfigs.RESOLVE_TIMEOUT
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

-- Le point autour duquel le ciel est peuple. Le personnage, et la camera en repli tant qu'il n'a pas spawn : sans ce
-- repli le troupeau se formerait autour de l'origine du monde et le ciel serait vide au-dessus du joueur.
local function anchorPoint(): Vector3?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

-- Place un nuage quelque part dans le ciel autour de `center`.
-- `upwind` = true quand il s'agit d'un RECYCLAGE : on le remet alors en AMONT du vent, sinon il ressortirait
-- aussitot par le meme bord et clignoterait.
local function place(cloud: Cloud, center: Vector3, upwind: boolean)
	local radius = CloudConfigs.FIELD_RADIUS
	local offset: Vector3
	if upwind then
		-- Sur le bord amont, avec un ecart lateral au hasard : les nuages n'arrivent pas tous par le meme point.
		local side = Vector3.new(-DRIFT.Z, 0, DRIFT.X)
		offset = -DRIFT * radius + side * rng:NextNumber(-radius, radius)
	else
		-- Premiere mise en place : n'importe ou dans le disque, pour que le ciel soit deja peuple au demarrage.
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = radius * math.sqrt(rng:NextNumber()) -- racine : repartition EGALE sur le disque, pas un tas au centre
		offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
	end

	cloud.altitude = CloudConfigs.ALTITUDE + rng:NextNumber(-1, 1) * CloudConfigs.ALTITUDE_SPREAD
	cloud.part.Position = Vector3.new(center.X + offset.X, cloud.altitude, center.Z + offset.Z)
end

local function update(dt: number)
	local center = anchorPoint()
	if not center then
		return
	end

	local radius = CloudConfigs.FIELD_RADIUS
	local fadeStart = radius * CloudConfigs.FADE_START
	local fadeSpan = math.max(radius - fadeStart, 1e-3)
	local near = CloudConfigs.NEAR_TRANSPARENCY

	for _, cloud in ipairs(clouds) do
		local position = cloud.part.Position + DRIFT * (cloud.speed * dt)

		local d = position - center
		local distance = math.sqrt(d.X * d.X + d.Z * d.Z)
		if distance > radius then
			place(cloud, center, true)
		else
			cloud.part.Position = Vector3.new(position.X, cloud.altitude, position.Z)
			-- FONDU AVEC LA DISTANCE. C'est lui qui cache le recyclage : le nuage est deja invisible quand il
			-- atteint le bord, donc on ne voit jamais ni sa disparition ni sa reapparition.
			local fade = math.clamp((distance - fadeStart) / fadeSpan, 0, 1)
			cloud.part.Transparency = near + (1 - near) * fade
		end
	end
end

function CloudController.init()
	-- EN TACHE DE FOND : resolvePath peut attendre, et un init de boot ne doit jamais bloquer la sequence.
	task.spawn(function()
		local source = resolvePath(ReplicatedStorage, CloudConfigs.MESH_PATH)
		if not source or not source:IsA("BasePart") then
			warn(
				`[Clouds] Mesh introuvable : ReplicatedStorage.{table.concat(CloudConfigs.MESH_PATH, ".")}. `
					.. `Pas de nuages.`
			)
			return
		end

		-- On attend un point d'ancrage avant de peupler : place() a besoin d'un centre, et le peupler sur l'origine
		-- du monde laisserait le ciel vide au-dessus du joueur jusqu'au premier recyclage.
		local center = anchorPoint()
		while not center do
			task.wait(0.25)
			center = anchorPoint()
		end

		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME

		for _ = 1, CloudConfigs.COUNT do
			local part = source:Clone()
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false -- n'a d'effet QUE parce que CanCollide est faux
			part.CanTouch = false
			part.CastShadow = false -- une ombre de nuage coute cher et ne se voit pas d'en bas
			part.Size = source.Size * rng:NextNumber(CloudConfigs.SCALE_MIN, CloudConfigs.SCALE_MAX)
			-- Rotation au hasard AUTOUR DE LA VERTICALE seulement : un nuage reste a plat.
			part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)

			local variation = CloudConfigs.SPEED_VARIATION
			local cloud: Cloud = {
				part = part,
				speed = CloudConfigs.SPEED * (1 + rng:NextNumber(-variation, variation)),
				altitude = CloudConfigs.ALTITUDE,
			}
			place(cloud, center, false)
			clouds[#clouds + 1] = cloud
			part.Parent = created
		end

		created.Parent = workspace
		folder = created
		print(`[Clouds] {#clouds} nuage(s) en vol.`)

		heartbeat = RunService.Heartbeat:Connect(update)
	end)
end

-- Coupe la boucle et retire les nuages. La connexion vit sur RunService, qui SURVIT a ce script : sans ce Disconnect
-- explicite elle tournerait toute la session.
function CloudController.stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(clouds)
end

return CloudController
