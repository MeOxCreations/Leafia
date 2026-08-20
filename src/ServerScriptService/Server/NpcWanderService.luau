--!strict
-- PNJ QUI SE PROMENENT. Chaque entree de NpcWanderConfigs.NPCS designe un modele de la map qui se balade tout seul
-- dans une zone, en contournant les obstacles (maison, arbres, haies).
--
-- COTE SERVEUR : c'est lui l'autorite sur la position du PNJ, et les animations jouees ici se repliquent a tous.
-- Deux joueurs voient donc le meme Papi au meme endroit.
--
-- Le calcul du chemin est confie a PathfindingService : il connait deja tous les obstacles de la map.
-- Ce module ne fait que DECIDER OU ALLER et RENDRE LA BALADE VIVANTE (pauses, vitesse qui varie). C'est la que se
-- joue la difference entre un promeneur et un robot en patrouille, pas dans le calcul du chemin.

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NpcWanderConfigs = require(ReplicatedStorage.Modules.Configs.NpcWanderConfigs)

local NpcWanderService = {}

local rng = Random.new()

-- Une Animation par ID : deux PNJ qui partagent une animation partagent l'instance.
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

-- Cherche un descendant du Workspace par NOM. Re-scan en boucle sous UN SEUL delai : au demarrage la map peut ne pas
-- etre entierement en place, et un WaitForChild par element ferait attendre le timeout autant de fois qu'il y a
-- d'elements manquants.
local function findByName(name: string, deadline: number): Instance?
	repeat
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if descendant.Name == name then
				return descendant
			end
		end
		task.wait(0.5)
	until os.clock() >= deadline
	return nil
end

-- Un point au hasard SUR LE SOL, dans la zone. Le rayon part d'au-dessus et descend : sans lui on viserait le centre
-- en hauteur de la zone, et le chemin partirait d'un point flottant.
local function pickGroundPoint(zone: BasePart, ignore: { Instance }): Vector3?
	local size = zone.Size
	local localPoint = Vector3.new(rng:NextNumber(-0.5, 0.5) * size.X, 0, rng:NextNumber(-0.5, 0.5) * size.Z)
	local from = zone.CFrame:PointToWorldSpace(localPoint) + Vector3.new(0, NpcWanderConfigs.GROUND_ABOVE, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- La zone elle-meme est exclue : c'est un marqueur, pas du sol. Le PNJ aussi, sinon il se detecte lui-meme.
	params.FilterDescendantsInstances = ignore

	local hit = workspace:Raycast(from, Vector3.new(0, -NpcWanderConfigs.GROUND_BELOW, 0), params)
	if not hit then
		return nil
	end
	return hit.Position
end

-- Etat d'un PNJ en balade. Regroupe pour que la boucle n'ait qu'un objet a lire.
type Walker = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	zone: BasePart,
	idleTrack: AnimationTrack,
	walkTrack: AnimationTrack,
	baseSpeed: number,
	animSpeed: number, -- cadence courante de la marche, lissee vers la vitesse reelle
}

-- Tous les promeneurs, pour qu'UNE seule boucle accorde leurs animations au lieu d'une par PNJ.
local walkers: { Walker } = {}

-- Passe de la pose d'arret a la marche, ou l'inverse. Une seule des deux pistes tourne a la fois : les laisser
-- toutes les deux jouer les melangerait (a priorite egale, Roblox fait la MOYENNE, il ne choisit pas).
local function setMoving(walker: Walker, moving: boolean)
	if moving then
		if not walker.walkTrack.IsPlaying then
			walker.idleTrack:Stop(0.2)
			walker.walkTrack:Play(0.2)
		end
	else
		if not walker.idleTrack.IsPlaying then
			walker.walkTrack:Stop(0.2)
			walker.idleTrack:Play(0.2)
		end
	end
end

-- Suit un chemin deja calcule. Retourne false des qu'une etape n'est pas atteinte : mieux vaut recalculer que
-- s'acharner sur un chemin qui ne passe plus (un joueur peut s'etre plante au milieu).
local function followPath(walker: Walker, waypoints: { PathWaypoint }): boolean
	for index, waypoint in ipairs(waypoints) do
		-- Le premier point est la position actuelle : y aller ne sert a rien et provoque un a-coup.
		if index > 1 then
			walker.humanoid:MoveTo(waypoint.Position)
			if not walker.humanoid.MoveToFinished:Wait() then
				return false
			end
		end
	end
	return true
end

-- Un trajet complet : choisir une destination, calculer, marcher. Retourne false si rien n'a pu etre fait.
local function travel(walker: Walker, path: Path): boolean
	local ignore = { walker.model, walker.zone }

	for _ = 1, NpcWanderConfigs.TARGET_TRIES do
		local target = pickGroundPoint(walker.zone, ignore)
		-- Trop pres : un PNJ qui fait trois pas et s'arrete a l'air casse. On retire ce tirage et on en refait un.
		if target and (target - walker.root.Position).Magnitude >= NpcWanderConfigs.MIN_TRAVEL then
			local ok = pcall(function()
				path:ComputeAsync(walker.root.Position, target)
			end)
			if ok and path.Status == Enum.PathStatus.Success then
				-- La vitesse change a CHAQUE trajet. Toujours la meme allure est un des signes les plus surs d'une
				-- machine, et ca ne coute qu'une ligne.
				local variation = NpcWanderConfigs.SPEED_VARIATION
				walker.humanoid.WalkSpeed = walker.baseSpeed * (1 + rng:NextNumber(-variation, variation))

				setMoving(walker, true)
				local reached = followPath(walker, path:GetWaypoints())
				setMoving(walker, false)
				return reached
			end
		end
	end
	return false
end

-- CONTROLE : l'animation bouge-t-elle vraiment le rig ?
-- Une animation dont les noms ne collent pas au rig joue avec un poids de 1 et n'ecrit RIEN. Le PNJ glisse comme un
-- mannequin, et aucune erreur n'apparait. On mesure donc l'etat des joints, on attend, et on compare.
local function checkAnimationBites(walker: Walker, label: string)
	local joints = {}
	for _, descendant in ipairs(walker.model:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			joints[#joints + 1] = descendant
		end
	end
	if #joints == 0 then
		return
	end

	local before = {}
	for index, joint in ipairs(joints) do
		before[index] = joint.Transform
	end

	task.wait(NpcWanderConfigs.ANIM_CHECK_DELAY)

	for index, joint in ipairs(joints) do
		if joint.Transform ~= before[index] then
			return -- au moins un membre a bouge : l'animation mord bien
		end
	end

	warn(
		`[NpcWander] L'animation "{label}" de "{walker.model.Name}" JOUE mais ne bouge AUCUN membre. `
			.. `Les noms qu'elle contient ne correspondent pas a ceux du rig (voir scripts/studio/ComparerAnimEtRig).`
	)
end

-- Prepare un PNJ : verifie qu'il a de quoi marcher, charge ses deux animations. nil si quelque chose manque.
local function buildWalker(config: NpcWanderConfigs.Npc, deadline: number): Walker?
	local found = findByName(config.model, deadline)
	if not found or not found:IsA("Model") then
		warn(`[NpcWander] Model "{config.model}" introuvable dans le Workspace. Ce PNJ ne se promenera pas.`)
		return nil
	end
	local model = found :: Model

	local zoneFound = findByName(config.zone, deadline)
	if not zoneFound or not zoneFound:IsA("BasePart") then
		warn(`[NpcWander] Zone "{config.zone}" introuvable (il faut une Part). "{config.model}" ne bougera pas.`)
		return nil
	end
	local zone = zoneFound :: BasePart
	if zone.CanCollide then
		-- Anormal ET actionnable : une zone solide devient un obstacle pour le calcul du chemin, et le PNJ ne
		-- trouvera aucun trajet a l'interieur. Le symptome (il ne bouge pas) n'a rien qui pointe vers la zone.
		warn(`[NpcWander] La zone "{config.zone}" a CanCollide VRAI : elle bloque les chemins. Mets-la sans collision.`)
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(`[NpcWander] "{config.model}" n'a pas de Humanoid. Il ne peut pas marcher.`)
		return nil
	end

	-- Roblox cherche ce nom EXACT pour deplacer un personnage. Une RootPart nommee autrement laisse le Humanoid sans
	-- prise : l'animation joue, MoveTo ne fait rien, et rien dans la console ne l'explique.
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		warn(
			`[NpcWander] "{config.model}" n'a pas de part nommee "HumanoidRootPart". Renomme sa RootPart ainsi `
				.. `et mets-la en PrimaryPart, sinon il ne se deplacera jamais.`
		)
		return nil
	end
	if root.Anchored then
		warn(`[NpcWander] La HumanoidRootPart de "{config.model}" est ANCREE : il ne peut pas se deplacer.`)
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
	if not animator or not animator:IsA("Animator") then
		warn(`[NpcWander] "{config.model}" n'a pas d'Animator sous son Humanoid. Aucune animation ne sera jouee.`)
		return nil
	end

	local okIdle, idleTrack = pcall(function()
		return animator:LoadAnimation(getAnimation(config.idle))
	end)
	local okWalk, walkTrack = pcall(function()
		return animator:LoadAnimation(getAnimation(config.walk))
	end)
	if not okIdle or not okWalk then
		warn(`[NpcWander] Animations non chargeables pour "{config.model}". Verifie les IDs.`)
		return nil
	end

	local idle = idleTrack :: AnimationTrack
	local walk = walkTrack :: AnimationTrack
	-- Deux boucles, et une SEULE joue a la fois (voir setMoving). Priorites distinctes pour que la marche l'emporte
	-- si les deux se chevauchent pendant un fondu : a priorite EGALE, Roblox melange au lieu de choisir.
	idle.Looped = true
	idle.Priority = Enum.AnimationPriority.Idle
	walk.Looped = true
	walk.Priority = Enum.AnimationPriority.Movement

	humanoid.WalkSpeed = config.speed

	return {
		model = model,
		humanoid = humanoid,
		root = root,
		zone = zone,
		idleTrack = idle,
		walkTrack = walk,
		baseSpeed = config.speed,
		animSpeed = 1,
	}
end

-- ACCORDE LA CADENCE DE MARCHE A LA VITESSE REELLE, pour tous les promeneurs a la fois.
-- On lit la vitesse MESUREE (AssemblyLinearVelocity) et pas la vitesse demandee : au demarrage et a l'arret le
-- personnage n'est pas encore, ou plus, a son allure de croisiere. La cadence monte et redescend donc avec lui, au
-- lieu de claquer d'un coup a chaque depart.
local function tuneAnimations(dt: number)
	for _, walker in ipairs(walkers) do
		if walker.model.Parent and walker.walkTrack.IsPlaying then
			local velocity = walker.root.AssemblyLinearVelocity
			local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			local target = math.clamp(
				speed / NpcWanderConfigs.WALK_ANIM_REFERENCE,
				NpcWanderConfigs.WALK_ANIM_MIN,
				NpcWanderConfigs.WALK_ANIM_MAX
			)
			walker.animSpeed += (target - walker.animSpeed) * (1 - math.exp(-NpcWanderConfigs.WALK_ANIM_SMOOTH * dt))
			walker.walkTrack:AdjustSpeed(walker.animSpeed)
		end
	end
end

function NpcWanderService.init()
	-- UNE seule boucle pour tous les PNJ : elle ne fait rien tant qu'aucun ne marche.
	RunService.Heartbeat:Connect(tuneAnimations)

	for _, config in ipairs(NpcWanderConfigs.NPCS) do
		-- UN THREAD PAR PNJ : chacun a son rythme, et rien de tout ca ne doit retarder le boot.
		task.spawn(function()
			if not config.enabled then
				print(`[NpcWander] "{config.model}" est COUPE dans la config : il ne se promenera pas.`)
				return
			end
			local deadline = os.clock() + NpcWanderConfigs.RESOLVE_TIMEOUT
			local walker = buildWalker(config, deadline)
			if not walker then
				return
			end

			-- UN SEUL objet Path, reutilise a chaque trajet : en creer un par trajet laisserait des instances
			-- derriere soi pour rien.
			local path = PathfindingService:CreatePath({
				AgentRadius = NpcWanderConfigs.AGENT_RADIUS,
				AgentHeight = NpcWanderConfigs.AGENT_HEIGHT,
				AgentCanJump = false,
			})

			setMoving(walker, false)
			walkers[#walkers + 1] = walker
			-- Controle de l'idle sans bloquer la balade : elle demarre pendant que la mesure se fait.
			task.spawn(checkAnimationBites, walker, "idle")
			print(`[NpcWander] "{config.model}" se promene dans "{config.zone}".`)

			while walker.model.Parent do
				travel(walker, path)
				-- LA PAUSE. C'est elle qui separe un promeneur d'un robot en patrouille : arriver puis repartir
				-- aussitot, toujours au meme rythme, se lit immediatement comme une machine.
				task.wait(rng:NextNumber(NpcWanderConfigs.PAUSE_MIN, NpcWanderConfigs.PAUSE_MAX))
			end
		end)
	end
end

return NpcWanderService
