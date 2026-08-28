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

-- L'Animator d'un modele. On le CREE s'il manque, au lieu d'attendre puis d'abandonner.
--
-- Un mesh RIGGE importe par le 3D Importer arrive avec un AnimationController VIDE : Roblox n'y met pas d'Animator.
-- Sans cette creation, tout est juste par ailleurs (le rig, l'anim, le nom du modele) et RIEN ne joue -- exactement
-- le genre d'echec silencieux qui envoie chercher le bug dans l'animation pendant une heure.
--
-- On ne YIELD pas : cote serveur, un modele pose dans Studio est complet des le boot, il n'y a rien a attendre.
-- (Different d'un personnage joueur, dont l'Animator arrive bien quelques frames apres l'Humanoid.)
local function findAnimator(model: Model): Animator
	local holder: Instance? = model:FindFirstChildOfClass("AnimationController")
		or model:FindFirstChildOfClass("Humanoid")
	if not holder then
		-- Le modele est NOMME dans la config : il est donc cense s'animer. On lui pose un porteur.
		-- AnimationController et pas Humanoid : bien moins cher au serveur, et suffisant pour une boucle d'ambiance.
		local controller = Instance.new("AnimationController")
		controller.Parent = model
		holder = controller
	end
	local found = (holder :: Instance):FindFirstChildOfClass("Animator")
	if found then
		return found
	end
	local animator = Instance.new("Animator")
	animator.Parent = holder
	return animator
end

-- UNE PART ANCREE IGNORE SON MOTOR6D : l'animation joue, les joints bougent, et rien ne se deplace a l'ecran, sans
-- la moindre erreur. C'est LE piege de cette feature, et il ne se voit qu'a l'oeil -- donc on le dit.
--
-- ON NE COMPTE QUE CE QU'ON PEUT PROUVER : les parts qu'un Motor6D est CENSE bouger (ses `Part1`) et qui sont
-- ancrees. Celles-la sont vraiment bloquees. Une part ancree que rien ne pilote -- la racine du rig, un accessoire
-- pose a cote -- ne regarde pas l'animation, et la nommer envoie chercher un probleme qui n'existe pas.
--
-- L'ANCIENNE VERSION COMPARAIT A `model.PrimaryPart`, et c'etait faux. Un modele sorti du 3D Importer n'a
-- normalement PAS de PrimaryPart : la comparaison tombait sur `nil`, donc la RootPart -- ancree EXPRES, a juste
-- titre -- etait comptee comme fautive. La sonde accusait la seule part qui avait raison.
--
-- Rien pour les SKINNED MESH : ils sont pilotes par des `Bone`, qui deforment le maillage sans passer par la
-- physique. Une part ancree s'y anime tres bien, donc il n'y a rien a signaler.
local function warnIfAnchored(model: Model)
	local blocked: { string } = {}
	-- PAR LES EXTREMITES DU JOINT, jamais par son rangement dans l'arbre : un Motor6D peut vivre n'importe ou.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			local driven = d.Part1
			if driven and driven.Anchored then
				table.insert(blocked, driven.Name)
			end
		end
	end
	if #blocked > 0 then
		warn(
			`[AmbientAnim] "{model.Name}" : {table.concat(blocked, ", ")} ANCREE(S) alors qu'un Motor6D doit les `
				.. `bouger. L'animation va jouer sans que rien ne bouge. Les desancrer -- la racine, elle, reste ancree.`
		)
	end
end

-- Demarre la boucle d'un modele, si son nom est connu de la config et qu'il n'est pas deja anime.
-- Retourne true quand une piste a vraiment demarre (sert au comptage du log).
local seen: { [string]: number } = {} -- nom de la config -> combien de modeles trouves. Sert a dire ce qui MANQUE.

local function animate(model: Model): boolean
	if tracks[model] then
		return false
	end
	local id = AmbientAnimConfigs.ANIMATIONS[model.Name]
	if not id then
		return false
	end
	local animator = findAnimator(model)
	warnIfAnchored(model)

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
	-- Compte APRES le succes : une entree qui n'apparait pas ici n'a vraiment rien anime.
	seen[model.Name] = (seen[model.Name] or 0) + 1
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

		-- Ce qui arrive APRES le boot s'anime aussi. La racine etant tout le Workspace, ce callback voit passer chaque
		-- carreau de haie et chaque debris de coupe : le `IsA("Model")` les ecarte avant tout autre test, et un Model
		-- ne coute qu'une lecture de nom. Mesure faite : ce n'est pas un poste de depense.
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

		-- CE QUI MANQUE, nomme. Une entree de config qu'on ne trouve nulle part est presque toujours un modele mal
		-- nomme ou range hors de la racine -- et sans ce mot, ca se cherche a l'aveugle (vecu deux fois).
		for name in pairs(AmbientAnimConfigs.ANIMATIONS) do
			if not seen[name] then
				warn(
					`[AmbientAnim] "{name}" est dans la config mais RIEN n'a ete anime sous ce nom. `
						.. `Verifie le nom EXACT du Model dans le Workspace (il n'y a pas de recherche approchante).`
				)
			end
		end

		local detail = {}
		for name, count in pairs(seen) do
			detail[#detail + 1] = `{name} x{count}`
		end
		print(`[AmbientAnim] {started} modele(s) anime(s) : {table.concat(detail, ", ")}`)
	end)
end

return AmbientAnimService
