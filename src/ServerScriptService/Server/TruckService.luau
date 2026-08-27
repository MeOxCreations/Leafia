--!strict
-- LE CAMION. Un prompt E a l'ARRIERE ouvre sa porte ; un second appui la referme.
--
-- MEME MOTIF QUE LA BOITE AUX LETTRES, et ce n'est pas un hasard : c'est le seul du projet qui n'a besoin d'AUCUN
-- remote. Roblox se charge de la proximite, de la touche E et du tap mobile via `ProximityPrompt` ; son
-- `Triggered` arrive deja cote serveur, avec le joueur en argument. Un remote maison referait tout ca moins bien,
-- et il faudrait valider la distance a la main.
--
-- Le style du prompt est `Custom` : Roblox garde la detection et l'input, mais n'affiche RIEN. La pilule est
-- dessinee cote client (TruckController), comme pour la boite.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local TruckConfigs = require(ReplicatedStorage.Modules.Configs.TruckConfigs)

local TruckService = {}

type Truck = {
	model: Model,
	track: AnimationTrack?,
	open: boolean, -- ce qu'on VEUT : la porte glisse vers cet etat, elle n'y saute pas
	time: number, -- ou l'on en est dans l'animation, en secondes
}

local trucks: { Truck } = {}
local stepConn: RBXScriptConnection? = nil

-- Cherche un objet par son NOM dans tout le Workspace. Aucun rangement impose : obliger a poser un objet au bon
-- endroit pour qu'il fonctionne est un piege qui a deja coute plusieurs diagnostics dans ce projet.
local function findByName(name: string): Instance?
	for _, d in Workspace:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

local function findAnimation(): Animation?
	local node: Instance? = ReplicatedStorage:FindFirstChild("Animations")
	for _, name in TruckConfigs.DOOR_ANIM_PATH do
		node = node and node:FindFirstChild(name)
	end
	if node and node:IsA("Animation") then
		return node
	end
	warn(
		`[TruckService] Animation introuvable : ReplicatedStorage.Animations.`
			.. `{table.concat(TruckConfigs.DOOR_ANIM_PATH, ".")}`
	)
	return nil
end

-- LA PORTE GLISSE VERS SON ETAT, dans un sens ou dans l'autre.
--
-- La piste n'est PAS jouee : on ecrit sa position. C'est ce qui donne gratuitement la fermeture -- la meme
-- animation, lue a l'envers -- sans avoir a en faire une seconde ni a gerer deux pistes qui se marcheraient
-- dessus.
--
-- `Looped = true` MALGRE la vitesse zero : une piste non bouclee se RELACHE en arrivant a sa derniere image, et
-- la porte se refermerait toute seule au moment precis ou elle finit de s'ouvrir.
local function step(dt: number)
	for _, truck in trucks do
		local track = truck.track
		if not (track and track.Length > 0.01) then
			continue
		end
		local usable = track.Length - 0.001
		local speed = if truck.open then TruckConfigs.DOOR_OPEN_SPEED else -TruckConfigs.DOOR_CLOSE_SPEED
		truck.time = math.clamp(truck.time + dt * speed, 0, usable)
		track.TimePosition = truck.time
	end
end

local function setup(model: Model)
	-- LE PROMPT VA SUR LA PORTE, pas sur le camion. Une part precise plutot que le modele entier : sinon il
	-- s'affiche des qu'on longe la carrosserie, y compris a l'avant, ou l'action n'a aucun sens.
	local door = model:FindFirstChild(TruckConfigs.DOOR_PART, true)
	if not (door and door:IsA("BasePart")) then
		warn(
			`[TruckService] Aucune part "{TruckConfigs.DOOR_PART}" dans "{model.Name}" : pas de prompt. `
				.. "Rojo ne synchronise pas le Workspace, elle doit exister dans CETTE place."
		)
		return
	end

	local truck: Truck = { model = model, track = nil, open = false, time = 0 }

	-- L'ANIMATION EST FACULTATIVE : sans elle le prompt marche quand meme, la porte ne bouge simplement pas. On ne
	-- prive pas le joueur d'une interaction pour un asset manquant.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	local anim = findAnimation()
	if animator and anim then
		local ok, result = pcall(function()
			return (animator :: Animator):LoadAnimation(anim :: Animation)
		end)
		if ok and typeof(result) == "Instance" then
			local t = result :: AnimationTrack
			t.Looped = true
			t.Priority = TruckConfigs.DOOR_PRIORITY
			t:Play()
			t:AdjustSpeed(0)
			t.TimePosition = 0
			truck.track = t
		end
	elseif not animator then
		warn(`[TruckService] Pas d'Animator sous "{model.Name}" : la porte ne bougera pas.`)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = TruckConfigs.PROMPT_NAME -- le client le reconnait pour dessiner la pilule a la place
	prompt.ActionText = TruckConfigs.PROMPT_ACTION
	prompt.ObjectText = TruckConfigs.PROMPT_OBJECT
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0 -- appui simple, pas de maintien
	prompt.MaxActivationDistance = TruckConfigs.PROMPT_DISTANCE
	-- La porte peut etre partiellement masquee par la carrosserie ou un outil pose devant : ne pas exiger la ligne
	-- de vue, sinon l'invite clignote des qu'un rien passe devant.
	prompt.RequiresLineOfSight = false
	-- CUSTOM : Roblox garde la proximite, la touche E et le tap mobile, mais n'affiche rien. La pilule est
	-- dessinee cote client.
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = door

	prompt.Triggered:Connect(function(_player: Player)
		-- UNE BASCULE, et rien de plus : le meme appui ouvre et referme. Aucun etat a valider -- le pire qu'un
		-- joueur puisse faire est d'ouvrir une porte de camion.
		truck.open = not truck.open
		-- LE SON PART A L'APPUI, pas a la fin du mouvement : c'est le geste du joueur qu'il accompagne. Attendre
		-- que la porte soit ouverte le decalerait d'une seconde et il ne repondrait plus a rien.
		--
		-- Lu APRES la bascule : `truck.open` porte deja l'etat VOULU, donc il dit quel son jouer sans qu'on ait a
		-- retenir le precedent.
		local path = if truck.open then TruckConfigs.DOOR_OPEN_SOUND else TruckConfigs.DOOR_CLOSE_SOUND
		SoundUtils.play(path, door :: BasePart)
	end)

	table.insert(trucks, truck)

	if not stepConn then
		stepConn = RunService.Heartbeat:Connect(step)
	end
end

function TruckService.init()
	-- Avec StreamingEnabled le camion peut arriver BIEN apres le demarrage : on le cherche, et s'il n'est pas la
	-- on repasse. Sans ca, un camion qui arrive en retard n'aurait jamais son prompt -- et rien ne le dirait.
	task.spawn(function()
		local deadline = os.clock() + TruckConfigs.FIND_TIMEOUT
		while os.clock() < deadline do
			local model = findByName(TruckConfigs.MODEL_NAME)
			if model and model:IsA("Model") then
				setup(model)
				return
			end
			task.wait(TruckConfigs.FIND_INTERVAL)
		end
		warn(
			`[TruckService] Aucun modele "{TruckConfigs.MODEL_NAME}" trouve apres `
				.. `{TruckConfigs.FIND_TIMEOUT} s : pas de prompt sur le camion.`
		)
	end)
end

return TruckService
