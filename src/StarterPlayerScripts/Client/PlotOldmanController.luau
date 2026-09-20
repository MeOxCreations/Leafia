--!strict
-- LE GRAND-PERE SUR CHAQUE PLOT (hub). Le modele vit dans `ReplicatedStorage.Assets.Contents.OldmanOriginal` et on en
-- pose une copie sur la part `PointSpawnOldman` de chaque plot.
--
-- 100 % CLIENT, et c'est le point : le serveur n'envoie rien, ne simule rien, et cinq grands-peres ne coutent pas un
-- octet de reseau. Ils ne servent qu'a etre vus.
--
-- SON ANIMATION EST JOUEE ICI AUSSI : `AmbientAnimService` est un service SERVEUR, il ne voit pas une copie posee par
-- le client. On reprend donc son ID dans `AmbientAnimConfigs` (une seule declaration pour tout le jeu) et on la joue
-- sur place, avec le meme depart au hasard -- cinq PNJ qui respirent a la meme image se lisent comme du faux.
--
-- LES PLOTS ARRIVENT TARD : streaming, replication. On re-scanne (chaque passe est instantanee) au lieu d'attendre un
-- enfant precis, sinon un plot manquant bloquerait tous les autres jusqu'au timeout.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AmbientAnimConfigs = require(ReplicatedStorage.Modules.Configs.AmbientAnimConfigs)

local PlotOldmanController = {}

local ASSET_PATH = { "Assets", "Contents", "OldmanOriginal" }
local POINT_NAME = "PointSpawnOldman"
-- Dossier local ou vivent les copies : a la racine du Workspace, PAS sous le plot. Un objet range sous un modele que
-- le streaming decharge part avec lui, et il ne reviendrait jamais (c'est nous qui l'avons cree, pas le serveur).
local FOLDER_NAME = "LeafiaLocalNpcs"
-- On cherche pendant ce temps-la : un plot peut arriver bien apres le spawn sur mobile.
local SCAN_TIME = 60
local SCAN_INTERVAL = 2
local WAIT_TIMEOUT = 20

-- Les points deja servis : re-scanner ne doit pas poser un deuxieme grand-pere au meme endroit.
local done: { [BasePart]: Model } = {}

local function findAsset(): Model?
	local node: Instance? = ReplicatedStorage
	for _, name in ASSET_PATH do
		node = node and node:WaitForChild(name, WAIT_TIMEOUT)
	end
	if node and node:IsA("Model") then
		return node
	end
	-- ACTIONNABLE : le modele se recopie a la main dans chaque place (Rojo ne synchronise pas Assets).
	warn(`[PlotOldman] Modele introuvable : ReplicatedStorage.{table.concat(ASSET_PATH, ".")}`)
	return nil
end

-- Joue la boucle d'ambiance du grand-pere sur sa copie. Sans Animator (mesh rigge importe sans porteur), on le cree :
-- tout serait juste par ailleurs et RIEN ne bougerait, sans la moindre erreur.
local function animate(model: Model)
	local id = AmbientAnimConfigs.ANIMATIONS[model.Name]
	if not id then
		return
	end
	local holder: Instance? = model:FindFirstChildOfClass("AnimationController")
		or model:FindFirstChildOfClass("Humanoid")
	if not holder then
		local controller = Instance.new("AnimationController")
		controller.Parent = model
		holder = controller
	end
	local animator = (holder :: Instance):FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = holder
		animator = created
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if not (ok and typeof(result) == "Instance") then
		warn(`[PlotOldman] Animation {id} non chargeable.`)
		return
	end
	local track = result :: AnimationTrack
	track.Looped = true
	track:Play()
	-- DESYNCHRONISATION, comme l'ambiance : vitesse un peu differente et depart au hasard dans la boucle.
	local spread = AmbientAnimConfigs.SPEED_VARIATION
	track:AdjustSpeed(1 + (math.random() * 2 - 1) * spread)
	if AmbientAnimConfigs.RANDOM_START and track.Length > 0 then
		track.TimePosition = math.random() * track.Length
	end
end

local function spawnAt(point: BasePart, asset: Model, folder: Folder)
	if done[point] then
		return
	end
	local copy = asset:Clone()
	copy:PivotTo(point.CFrame)
	copy.Parent = folder
	done[point] = copy
	animate(copy)
	-- LE PLOT PEUT PARTIR (streaming) : sa copie n'a plus de raison d'etre, et son point n'est plus valable.
	point.AncestryChanged:Connect(function()
		if point:IsDescendantOf(workspace) then
			return
		end
		local model = done[point]
		done[point] = nil
		if model then
			model:Destroy()
		end
	end)
end

function PlotOldmanController.init()
	task.spawn(function()
		local asset = findAsset()
		if not asset then
			return
		end
		local worlds = workspace:WaitForChild("Worlds", WAIT_TIMEOUT)
		local plots = worlds and worlds:WaitForChild("Plots", WAIT_TIMEOUT)
		if not plots then
			warn("[PlotOldman] Dossier Workspace.Worlds.Plots introuvable : aucun grand-pere pose.")
			return
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = workspace

		local deadline = os.clock() + SCAN_TIME
		local posed = 0
		while os.clock() < deadline do
			for _, plot in plots:GetChildren() do
				local point = plot:FindFirstChild(POINT_NAME)
				if point and point:IsA("BasePart") and not done[point] then
					spawnAt(point, asset, folder)
					posed += 1
				end
			end
			task.wait(SCAN_INTERVAL)
		end
		if posed == 0 then
			warn(`[PlotOldman] Aucun "{POINT_NAME}" trouve sous Workspace.Worlds.Plots : aucun grand-pere pose.`)
		else
			print(`[PlotOldman] {posed} grand-pere(s) pose(s) sur les plots.`)
		end
	end)
end

return PlotOldmanController
