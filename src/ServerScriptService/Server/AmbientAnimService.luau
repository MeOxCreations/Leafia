--!strict
-- Joue les ANIMATIONS D'AMBIANCE de la map. Chaque modele dont le nom est liste dans AmbientAnimConfigs.ANIMATIONS
-- recoit sa boucle : les plantes (buissons, arbres) et les PNJ qui respirent sur place (Papi). Meme mecanique pour
-- les deux, d'ou un seul service -- un buisson et un grand-pere qui respirent, c'est le meme besoin.
--
-- Joue COTE SERVEUR : la boucle se replique a tout le monde, y compris aux joueurs qui arrivent plus tard, et le
-- serveur voit toute la map quoi que fasse le streaming chez le client.
--
-- Aucune Instance Animation n'est rangee dans ReplicatedStorage : elles sont creees ici a partir des IDs de la
-- config. Une place secondaire (le tuto) recoit donc la meme ambiance sans qu'on y recopie quoi que ce soit.
--
-- A savoir si ca grossit beaucoup : chaque modele anime est un Humanoid de plus a faire tourner au serveur. Sur une
-- dizaine c'est gratuit ; a plusieurs centaines, il faudra jouer ces boucles cote CLIENT (c'est purement cosmetique)
-- plutot que de les repliquer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AmbientAnimConfigs = require(ReplicatedStorage.Modules.Configs.AmbientAnimConfigs)

local AmbientAnimService = {}

local rng = Random.new()

-- Registre modele -> sa piste. Il sert au NETTOYAGE (une plante retiree de la map relache sa piste) et empeche de
-- lancer deux fois la meme boucle sur le meme modele.
local tracks: { [Model]: AnimationTrack } = {}

-- Une Animation par ID, pas une par modele : dix buissons partagent la meme instance source.
local animations: { [string]: Animation } = {}

local function getAnimation(id: string): Animation
	local existing = animations[id]
	if existing then
		return existing
	end
	local animation = Instance.new("Animation")
	animation.Name = id
	animation.AnimationId = id
	animations[id] = animation
	return animation
end

-- L'Animator d'un modele, ou nil s'il n'en a pas. Le WaitForChild couvre les modeles ajoutes en cours de
-- partie, dont l'Animator arrive quelques frames apres l'Humanoid.
local function findAnimator(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local found: Instance? = humanoid:FindFirstChildOfClass("Animator")
	if not found then
		found = humanoid:WaitForChild("Animator", AmbientAnimConfigs.ANIMATOR_TIMEOUT)
	end
	if found and found:IsA("Animator") then
		return found
	end
	return nil
end

-- Demarre la boucle d'un modele, si son nom est connu de la config et qu'il n'est pas deja anime.
-- Retourne true quand une piste a vraiment demarre (sert au comptage du log).
local function animate(model: Model): boolean
	if tracks[model] then
		return false
	end
	local id = AmbientAnimConfigs.ANIMATIONS[model.Name]
	if not id then
		return false
	end
	local animator = findAnimator(model)
	if not animator then
		return false
	end

	local ok, result = pcall(function()
		return animator:LoadAnimation(getAnimation(id))
	end)
	if not ok or typeof(result) ~= "Instance" then
		-- Anormal ET actionnable : l'ID est peut-etre faux ou l'asset pas publie sous le bon proprietaire.
		warn(`[AmbientAnim] Animation non chargeable pour "{model.Name}" ({id}).`)
		return false
	end
	local track = result :: AnimationTrack

	-- Decor ambiant : la boucle ne doit JAMAIS se relacher. Le reglage de l'editeur n'est qu'une suggestion, on
	-- l'ecrit ici. Priorite Idle : rien d'autre ne joue sur ces modeles, mais autant etre explicite.
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Idle
	track:Play()

	if AmbientAnimConfigs.SPEED_VARIATION > 0 then
		track:AdjustSpeed(1 + (rng:NextNumber() * 2 - 1) * AmbientAnimConfigs.SPEED_VARIATION)
	end

	if AmbientAnimConfigs.RANDOM_START then
		-- Length vaut 0 tant que l'asset n'est pas telecharge : le lire tout de suite rendrait toujours 0, donc un
		-- depart identique pour toutes les plantes. On attend la vraie longueur dans un thread a part, borne dans le
		-- temps pour ne pas tourner pour toujours si l'asset ne vient jamais.
		task.spawn(function()
			local deadline = os.clock() + 10
			while track.Length <= 0 and os.clock() < deadline do
				task.wait()
			end
			if track.Length > 0 then
				track.TimePosition = rng:NextNumber() * track.Length
			end
		end)
	end

	tracks[model] = track
	return true
end

-- Celui qui a lance la piste est celui qui la coupe : un modele retire de la map (build, streaming serveur, edition
-- en live) ne doit pas laisser sa piste tourner dans le vide.
local function stop(model: Model)
	local track = tracks[model]
	if not track then
		return
	end
	track:Stop()
	tracks[model] = nil
end

-- La racine a balayer, ou nil si elle n'existe pas dans cette place.
-- Re-scan en boucle plutot qu'une chaine de WaitForChild : avec un WaitForChild PAR SEGMENT, un chemin absent ferait
-- attendre le timeout QUATRE fois avant de prevenir. Ici, un seul delai couvre tout le chemin.
local function resolveRoot(): Instance?
	local deadline = os.clock() + AmbientAnimConfigs.ROOT_TIMEOUT
	repeat
		local node: Instance? = workspace
		for _, name in ipairs(AmbientAnimConfigs.ROOT) do
			node = node and node:FindFirstChild(name)
		end
		if node then
			return node
		end
		task.wait(0.25)
	until os.clock() >= deadline
	return nil
end

function AmbientAnimService.init()
	-- EN TACHE DE FOND : resolveRoot et l'attente des Animator peuvent YIELD. Un init de boot ne doit jamais attendre,
	-- et surement pas ROOT_TIMEOUT secondes pour du decor.
	task.spawn(function()
		local root = resolveRoot()
		if not root then
			warn(
				`[AmbientAnim] Dossier introuvable : Workspace.{table.concat(AmbientAnimConfigs.ROOT, ".")}. `
					.. `Aucune animation d'ambiance dans cette place.`
			)
			return
		end

		local started = 0
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("Model") and animate(descendant) then
				started += 1
			end
		end

		-- Ce qui arrive APRES le boot s'anime aussi. On n'ecoute QUE ce dossier : brancher Workspace.DescendantAdded
		-- ferait passer chaque part de personnage et chaque debris par le test de nom, des centaines de fois pour rien.
		root.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("Model") then
				animate(descendant)
			end
		end)
		root.DescendantRemoving:Connect(function(descendant)
			if descendant:IsA("Model") then
				stop(descendant)
			end
		end)

		print(`[AmbientAnim] {started} modele(s) anime(s).`)
	end)
end

return AmbientAnimService
