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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local TruckConfigs = require(ReplicatedStorage.Modules.Configs.TruckConfigs)
local BinConfigs = require(ReplicatedStorage.Modules.Configs.BinConfigs)
local MowConfigs = require(ReplicatedStorage.Modules.Configs.MowConfigs)

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

--- UN OUTIL SORTI DU CAMION, par son nom. On le reconnait a la pose qu'il a gardee : elle dit d'ou il vient.
---
--- ON BALAYE PLUTOT QUE DE TENIR UNE LISTE. Une liste serait un second etat a garder d'accord avec le monde, et
--- elle mentirait le jour ou un outil est detruit, deplace, ou pose par un autre chemin -- alors que la marque,
--- elle, voyage AVEC l'objet.
local function findTakenTool(toolName: string): Model?
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and d.Name == toolName and d:GetAttribute(TruckConfigs.POSE_ATTRIBUTE) ~= nil then
			return d :: Model
		end
	end
	return nil
end

--- Quelqu'un le PORTE-T-IL ? On ne range pas un objet qui est dans les mains de quelqu'un : il partirait en vol
--- en restant soude au porteur, qui se retrouverait a courir apres son propre seau.
---
--- Les deux attributs sont ceux que posent les services de portage. On les LIT depuis leurs configs plutot que
--- d'ecrire les noms ici : une chaine recopiee finit toujours par diverger de son original.
local function isHeld(model: Model): boolean
	return model:GetAttribute(MowConfigs.CARRIED_ATTRIBUTE) ~= nil
		or model:GetAttribute(BinConfigs.CARRIED_ATTRIBUTE) ~= nil
end

--- Un point sur la courbe de Bezier quadratique, de `a` a `c` en passant pres de `b`.
local function bezier(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	local u = 1 - t
	return a * (u * u) + b * (2 * u * t) + c * (t * t)
end

-- ===== L'OUTIL EN MAIN NE RESTE PAS AU SOL =====
-- Un outil sorti du camion se pose sur le terrain. Equipe, ToolService en met un exemplaire dans la main : sans
-- rien faire, le joueur le verrait donc DEUX FOIS -- dans ses mains et par terre.
--
-- ON LE REND INVISIBLE, ON NE LE DEPLACE PAS. Trois raisons. Il garde sa place, donc il RE-APPARAIT exactement la
-- quand on le range. Il garde sa marque, donc le menu des outils continue de le compter comme possede -- range
-- ailleurs, il disparaitrait du menu au moment ou on l'equipe, ce qui est l'inverse de ce qu'on veut dire. Et le
-- camion peut toujours le reprendre.
--
-- LES VALEURS D'ORIGINE SONT GARDEES : une part peut etre deja semi-transparente ou deja traversable, et les
-- remettre "a zero" les abimerait. On restitue ce qu'on a trouve, pas ce qu'on suppose.
local hidden: { [Model]: { [BasePart]: { transparency: number, collide: boolean, query: boolean } } } = {}

local function setToolHidden(model: Model, hide: boolean)
	if hide then
		if hidden[model] then
			return
		end
		local saved: { [BasePart]: { transparency: number, collide: boolean, query: boolean } } = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local part = d :: BasePart
				saved[part] = { transparency = part.Transparency, collide = part.CanCollide, query = part.CanQuery }
				part.Transparency = 1
				part.CanCollide = false
				part.CanQuery = false
			end
		end
		hidden[model] = saved
		return
	end
	local saved = hidden[model]
	if not saved then
		return
	end
	hidden[model] = nil
	for part, was in saved do
		if part.Parent then
			part.Transparency = was.transparency
			part.CanCollide = was.collide
			part.CanQuery = was.query
		end
	end
end

--- L'outil que ce personnage tient, ou nil. `LeafiaTool` est pose par ToolService sur le MODELE en main.
local function heldToolName(character: Model): string?
	for _, child in character:GetChildren() do
		local name = child:GetAttribute("LeafiaTool")
		if typeof(name) == "string" then
			return name :: string
		end
	end
	return nil
end

--- Cache l'exemplaire au sol de ce qui est en main, et remontre tout le reste.
---
--- ON BALAYE TOUT A CHAQUE FOIS plutot que de suivre les changements un par un : la liste est courte (ce qui est
--- sorti du camion), et un etat reconstruit ne peut pas se desynchroniser -- alors qu'un etat mis a jour par
--- evenements oublie toujours un cas (mort, respawn, outil detruit, second joueur).
local function syncHidden()
	local held: { [string]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local name = if character then heldToolName(character) else nil
		if name then
			held[name] = true
		end
	end
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute(TruckConfigs.POSE_ATTRIBUTE) ~= nil then
			local tool = TruckConfigs.TOOL_EQUIP[d.Name]
			setToolHidden(d :: Model, tool ~= nil and held[tool] == true)
		end
	end
end

--- FAIT SORTIR `model` DU CAMION et le pose a `landing`.
---
--- IL EST ANCRE PENDANT TOUT LE VOL, et repose ancre a l'arrivee : un modele desancre tombe, rebondit, et finit
--- ou la physique veut -- alors qu'on lui a choisi une place. Les objets qu'on PORTE seront desancres par leur
--- propre systeme quand on les prendra.
--- UNE PART DE L'OBJET, pour y accrocher un son. Sa PrimaryPart si elle existe, sinon n'importe laquelle : le
--- bruit doit venir de l'objet, et a cette distance le joueur n'entend pas de quelle piece exactement.
local function soundHost(model: Model): BasePart?
	local primary = model.PrimaryPart
	if primary then
		return primary
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function fly(model: Model, landing: CFrame, home: Instance?)
	flying[model] = true
	local from = model:GetPivot()
	local host = soundHost(model)
	-- IL SIFFLE EN PARTANT. Le son est porte par l'objet, donc il le SUIT : il quitte le camion avec lui et
	-- arrive avec lui -- alors qu'un son pose sur le camion resterait derriere.
	if host then
		SoundUtils.play(TruckConfigs.FLY_SOUND, host)
	end
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
		-- ET IL SE POSE, avec le bruit qui va avec. A la FIN, pas au depart : un choc qui precede l'atterrissage
		-- se lit comme un autre objet, ailleurs.
		if host and host.Parent then
			SoundUtils.play(TruckConfigs.DROP_SOUND, host)
		end
		-- ET IL RENTRE DANS LA BENNE, a la FIN du vol seulement. Range avant, il suivrait la carrosserie pendant
		-- qu'il vole encore -- il arriverait donc a cote de sa place si le camion bouge.
		if home and home.Parent then
			-- IL REDEVIENT VISIBLE EN RENTRANT. Range invisible, il resterait un trou dans la benne -- et rien a
			-- l'ecran ne dirait qu'il est bien revenu.
			setToolHidden(model, false)
			model.Parent = home
			-- LA MARQUE PART AVEC LUI : il n'est plus "sorti", donc l'interface le remontre comme a prendre. C'est
			-- la meme information qui sert aux deux sens, il n'y a rien a tenir d'accord.
			model:SetAttribute(TruckConfigs.POSE_ATTRIBUTE, nil)
		end
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
		-- UN SEUL CLIC, DEUX SENS : c'est la PLACE de l'objet qui decide. S'il est encore dans la benne, on le
		-- sort ; s'il en est deja sorti, on l'y remet. Le client n'a donc rien a savoir de l'etat des choses -- il
		-- designe un outil, et le serveur fait ce qui a du sens pour lui.
		local found = folder:FindFirstChild(toolName :: string)
		if found and found:IsA("Model") then
			-- SORTI EN VARIABLE, et pas `(found :: Model)` en debut de ligne : une instruction qui commence par une
			-- parenthese se lit comme la SUITE de la ligne du dessus, donc comme un appel de fonction. Piege deja
			-- paye dans ce projet.
			local inside = found :: Model
			if flying[inside] then
				return
			end
			local landing = landingFor(toolName :: string, player)
			if not landing then
				return -- pas de place connue et pas de personnage : on ne pose pas un objet nulle part
			end
			-- ON RETIENT SA POSE AVANT DE LE SORTIR, en repere du camion : c'est elle qui le ramenera exactement
			-- la, a l'angle pres, et elle reste juste meme si le camion bouge entre-temps.
			inside:SetAttribute(TruckConfigs.POSE_ATTRIBUTE, truck:GetPivot():ToObjectSpace(inside:GetPivot()))
			print(`[TruckToolsService] {player.Name} sort "{toolName}" du camion.`)
			fly(inside, landing :: CFrame)
			return
		end

		-- IL EST DEHORS : on le range. Sa pose d'origine est sur lui, en repere du camion.
		local out = findTakenTool(toolName :: string)
		if not out then
			return
		end
		local taken = out :: Model
		if flying[taken] then
			return
		end
		if isHeld(taken) then
			-- QUELQU'UN LE PORTE. Le faire voler le laisserait soude a lui : le porteur se mettrait a courir apres
			-- son propre seau. On refuse en silence -- le joueur voit l'objet dans ses mains, il n'a pas besoin
			-- qu'on le lui dise.
			return
		end
		local pose = taken:GetAttribute(TruckConfigs.POSE_ATTRIBUTE)
		if typeof(pose) ~= "CFrame" then
			return
		end
		print(`[TruckToolsService] {player.Name} range "{toolName}" dans le camion.`)
		fly(taken, truck:GetPivot() * (pose :: CFrame), folder)
	end)

	-- RIEN A NETTOYER QUAND UN JOUEUR PART : le vol vit dans une tache, pas dans sa session, et il finit tout
	-- seul. L'outil sorti appartient au MONDE, pas a celui qui l'a sorti.
	-- ON SUIT CE QUE LES JOUEURS TIENNENT. L'attribut arrive APRES l'enfant -- le modele est parente d'abord, la
	-- marque posee ensuite -- donc on ecoute les deux : l'ajout, et l'attribut qui apparait dessus.
	local function watch(character: Model)
		character.ChildAdded:Connect(function(child)
			child:GetAttributeChangedSignal("LeafiaTool"):Connect(syncHidden)
			syncHidden()
		end)
		character.ChildRemoved:Connect(syncHidden)
		syncHidden()
	end

	local function follow(player: Player)
		player.CharacterAdded:Connect(watch)
		if player.Character then
			watch(player.Character :: Model)
		end
	end

	Players.PlayerAdded:Connect(follow)
	for _, player in Players:GetPlayers() do
		follow(player)
	end
	-- ET AU DEPART D'UN JOUEUR : son outil n'est plus tenu, donc l'exemplaire au sol doit revenir.
	Players.PlayerRemoving:Connect(function()
		task.defer(syncHidden)
	end)

	print("[TruckToolsService] Pret : les outils de la benne peuvent etre sortis.")
end

return TruckToolsService
