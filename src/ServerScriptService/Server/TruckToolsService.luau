--!strict
-- SORTIR UN OUTIL DE LA BENNE. Le joueur clique dans l'interface, l'objet QUITTE le camion, vole en arc, et se
-- pose sur le terrain.
--
-- COTE SERVEUR PARCE QUE L'OBJET EST REEL. Il n'est pas fabrique pour l'occasion : c'est le modele range dans la
-- benne, celui qu'on voit par le hayon ouvert. Il doit donc quitter le camion CHEZ TOUT LE MONDE -- un vol joue
-- chez le client laisserait l'outil dans la benne pour les autres, et deux joueurs ne verraient pas le meme
-- camion.
--
-- ET C'EST AUSSI CE QUI SERT DE GARDE : le client envoie un NOM, le serveur retrouve le modele lui-meme dans le
-- dossier prevu. Un client modifie ne peut donc designer que ce qui est dans la benne -- pas la maison du
-- grand-pere.
--
-- LE VOL EST UNE COURBE DE BEZIER a trois points : depart, sommet, arrivee. Une ligne droite ne se lit pas comme
-- un objet qu'on SORT mais comme un objet qui glisse ; l'arc dit qu'il a ete souleve et pose.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local TruckConfigs = require(ReplicatedStorage.Modules.Configs.TruckConfigs)

local TruckToolsService = {}

-- LES OUTILS EN VOL, pour ne pas en lancer deux fois le meme. Le modele quitte son dossier des le depart, donc il
-- n'est deja plus proposable -- mais deux clics dans la meme image arriveraient avant, et le second trouverait
-- encore l'outil en place.
local flying: { [Model]: boolean } = {}

--- Le camion, ou nil. Re-cherche a chaque fois plutot que garde : avec le streaming il arrive apres le boot, et
--- une reference resolue une seule fois resterait vide pour toute la session.
local function findTruck(): Model?
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and d.Name == TruckConfigs.MODEL_NAME then
			return d :: Model
		end
	end
	return nil
end

--- OU L'OUTIL DOIT SE POSER : la part qui porte son nom, dans le dossier des arrivees.
---
--- UNE PART ET PAS UN POINT : son ORIENTATION compte autant que sa position. Un rateau pose de travers a l'air
--- tombe, pas depose -- et c'est une chose qui se regle a la souris, pas dans un fichier.
local function findDropPoint(toolName: string): BasePart?
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Folder") and d.Name == TruckConfigs.DROP_FOLDER then
			local part = (d :: Folder):FindFirstChild(toolName)
			if part and part:IsA("BasePart") then
				return part :: BasePart
			end
		end
	end
	return nil
end

--- La pose d'arrivee : celle du point prevu, ou devant le joueur faute de mieux.
local function landingFor(toolName: string, player: Player): CFrame?
	local point = findDropPoint(toolName)
	if point then
		return point.CFrame
	end
	-- SECOURS, ET ON LE DIT. Sans ce mot, un outil qui se pose devant le joueur au lieu de sa place passerait
	-- pour un choix -- alors qu'il manque juste une part.
	warn(
		`[TruckToolsService] Aucune part "{toolName}" dans un dossier "{TruckConfigs.DROP_FOLDER}" : `
			.. "il se posera devant le joueur. Rojo ne synchronise pas le Workspace."
	)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return nil
	end
	local root = hrp :: BasePart
	local ahead = root.Position + root.CFrame.LookVector * TruckConfigs.DROP_FALLBACK_DIST
	-- A PLAT : on garde le cap du joueur mais pas son tangage, sinon l'outil se pose penche quand il regarde ses
	-- pieds ou le ciel.
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return CFrame.new(ahead)
	end
	return CFrame.lookAt(ahead, ahead + flat.Unit)
end

--- Un point sur la courbe de Bezier quadratique, de `a` a `c` en passant pres de `b`.
local function bezier(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	local u = 1 - t
	return a * (u * u) + b * (2 * u * t) + c * (t * t)
end

--- FAIT SORTIR `model` DU CAMION et le pose a `landing`.
---
--- IL EST ANCRE PENDANT TOUT LE VOL, et repose ancre a l'arrivee : un modele desancre tombe, rebondit, et finit
--- ou la physique veut -- alors qu'on lui a choisi une place. Les objets qu'on PORTE seront desancres par leur
--- propre systeme quand on les prendra.
local function fly(model: Model, landing: CFrame)
	flying[model] = true
	local from = model:GetPivot()
	-- LE SOMMET EST AU MILIEU, REMONTE. C'est lui qui fait l'arc, et le calculer depuis les deux bouts le garde
	-- juste ou que soit le camion : un sommet ecrit en dur ne vaudrait que pour une seule carte.
	local middle = (from.Position + landing.Position) * 0.5 + Vector3.new(0, TruckConfigs.FLY_ARC_HEIGHT, 0)
	local spin = math.rad(360 * TruckConfigs.FLY_SPINS)

	-- ON L'ANCRE ET ON LE SORT DU CAMION. Tant qu'il est enfant du modele, il suit la carrosserie -- et il
	-- resterait "range" pour l'interface, qui lit le contenu du dossier.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			(d :: BasePart).Anchored = true
		end
	end
	model.Parent = Workspace

	task.spawn(function()
		local t0 = os.clock()
		while true do
			local e = math.clamp((os.clock() - t0) / TruckConfigs.FLY_TIME, 0, 1)
			if not model.Parent then
				flying[model] = nil
				return -- detruit en vol : plus rien a poser
			end
			local pos = bezier(from.Position, middle, landing.Position, e)
			-- IL TOURNE EN VOLANT, PUIS IL SE REDRESSE. Un objet qui garde son angle tout du long a l'air tire
			-- par une ficelle ; un tour sur lui-meme dit qu'il a ete LANCE. Mais il doit arriver DROIT, sinon il
			-- se pose a l'angle ou le hasard du tour l'a laisse -- donc sur la fin, sa rotation revient vers
			-- celle du point d'arrivee.
			local turned = from.Rotation * CFrame.Angles(0, spin * e, 0)
			local settle = TruckConfigs.FLY_SETTLE_FROM
			local rot = if e <= settle
				then turned
				else turned:Lerp(landing.Rotation, (e - settle) / math.max(1 - settle, 1e-3))
			model:PivotTo(CFrame.new(pos) * rot.Rotation)
			if e >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		model:PivotTo(landing)
		flying[model] = nil
	end)
end

function TruckToolsService.init()
	local remote = RemoteSetup.getRemote("TakeTruckTool", "Truck") :: RemoteEvent

	remote.OnServerEvent:Connect(function(player, toolName)
		-- LE CLIENT MENT TOUJOURS : on ne prend que ce qui est une chaine, et on ne s'en sert que comme d'une CLE
		-- dans le dossier du camion. Tout le reste -- ou est l'outil, ou il va -- est decide ici.
		if type(toolName) ~= "string" then
			return
		end
		local truck = findTruck()
		if not truck then
			return
		end
		-- LA PORTE DOIT ETRE OUVERTE. Le client ne montre l'interface que dans ce cas, mais un client modifie
		-- pourrait envoyer le remote sans elle : on ne fait pas confiance a l'affichage pour garder une regle.
		if truck:GetAttribute(TruckConfigs.OPEN_ATTRIBUTE) ~= true then
			return
		end
		local folder = truck:FindFirstChild(TruckConfigs.TOOLS_FOLDER)
		if not folder then
			warn(
				`[TruckToolsService] Aucun dossier "{TruckConfigs.TOOLS_FOLDER}" dans "{truck.Name}" : `
					.. "il n'y a rien a sortir. Rojo ne synchronise pas le Workspace."
			)
			return
		end
		local model = folder:FindFirstChild(toolName :: string)
		if not (model and model:IsA("Model")) or flying[model :: Model] then
			return -- deja sorti, deja en vol, ou nom inconnu : rien a faire, et rien a dire
		end
		local landing = landingFor(toolName :: string, player)
		if not landing then
			return -- pas de place connue et pas de personnage : on ne pose pas un objet nulle part
		end
		print(`[TruckToolsService] {player.Name} sort "{toolName}" du camion.`)
		fly(model :: Model, landing :: CFrame)
	end)

	-- RIEN A NETTOYER QUAND UN JOUEUR PART : le vol vit dans une tache, pas dans sa session, et il finit tout
	-- seul. L'outil sorti appartient au MONDE, pas a celui qui l'a sorti.
	print("[TruckToolsService] Pret : les outils de la benne peuvent etre sortis.")
end

return TruckToolsService
