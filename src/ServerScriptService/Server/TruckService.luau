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
	-- L'ETAT DE DEPART EST ECRIT, pas suppose. Un attribut absent se lit `nil`, et chaque lecteur devrait alors
	-- decider lui-meme si ca veut dire "fermee" ou "on ne sait pas" -- donc deux lecteurs finiraient par ne pas
	-- repondre pareil.
	model:SetAttribute(TruckConfigs.OPEN_ATTRIBUTE, false)

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

	-- LA PILULE NE SUIT PAS LA PORTE. Le prompt etait pose SUR le hayon, qui pivote en s'ouvrant : l'invite
	-- descendait avec lui, comme si elle tombait. Une invite doit rester la ou le joueur vient de la lire.
	--
	-- ON POSE DONC UNE PART FIXE a l'endroit du hayon FERME -- c'est son etat au demarrage du serveur -- et le
	-- prompt vit dessus. La detection de proximite part d'elle aussi, ce qui est plus juste : la zone ou l'action
	-- a un sens ne bouge pas quand la porte s'ouvre.
	local anchor = model:FindFirstChild(TruckConfigs.PROMPT_ANCHOR)
	if not (anchor and anchor:IsA("BasePart")) then
		local fixed = Instance.new("Part")
		fixed.Name = TruckConfigs.PROMPT_ANCHOR
		fixed.Size = Vector3.new(0.2, 0.2, 0.2)
		fixed.Transparency = 1
		fixed.CanCollide = false
		fixed.CanQuery = false
		fixed.CanTouch = false
		fixed.CastShadow = false
		fixed.Anchored = true
		fixed.CFrame = (door :: BasePart).CFrame
		fixed.Parent = model
		anchor = fixed
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = TruckConfigs.PROMPT_NAME -- le client le reconnait pour dessiner la pilule a la place
	prompt.ActionText = TruckConfigs.PROMPT_ACTION
	prompt.ObjectText = TruckConfigs.PROMPT_OBJECT
	-- UNE TOUCHE QUE PERSONNE N'A, ET SURTOUT PAS "AUCUNE TOUCHE".
	--
	-- Pourquoi on ne laisse pas `E` : un `ProximityPrompt` ecoute sa touche LUI-MEME, hors de tout arbitrage. Le
	-- joueur voyait le badge du SEAU, appuyait sur `E`, et le camion s'ouvrait -- il etait a portee, ca suffisait.
	-- C'est le CLIENT qui branche `E`, derriere le test d'appartenance du badge, comme les cinq autres features.
	--
	-- POURQUOI PAS `None` / `Unknown`, ET C'EST LE BUG LE PLUS CHER DE LA SEMAINE. Les deux valent ZERO, et c'est
	-- AUSSI le `KeyCode` que porte tout input qui n'est pas une touche : clic gauche, CLIC DROIT, molette, doigt.
	-- Le test interne de Roblox (`input.KeyCode == KeyboardKeyCode`) devenait donc vrai a CHAQUE action de souris.
	-- Demander "aucune touche" ne coupe pas l'ecoute : ca l'ouvre a tout le reste. Le hayon s'ouvrait en tournant
	-- la camera au clic droit, et la camera semblait bloquee.
	--
	-- `F13` n'existe sur aucun clavier de joueur, donc rien ne la presse jamais, et elle ne vaut pas zero : aucune
	-- souris ne lui ressemble. Notre declenchement a nous ne passe pas par la (`InputHoldBegin`, appele a la main
	-- depuis la pilule), il marche quelle que soit cette valeur.
	--
	-- LE TEMOIN QUI A TRANCHE : la boite aux lettres a le MEME montage (Custom, ClickablePrompt coupe) et n'a
	-- JAMAIS eu ce probleme. Une seule propriete differait entre les deux.
	prompt.KeyboardKeyCode = Enum.KeyCode.F13
	prompt.HoldDuration = 0 -- appui simple, pas de maintien
	prompt.MaxActivationDistance = TruckConfigs.PROMPT_DISTANCE
	-- La porte peut etre partiellement masquee par la carrosserie ou un outil pose devant : ne pas exiger la ligne
	-- de vue, sinon l'invite clignote des qu'un rien passe devant.
	prompt.RequiresLineOfSight = false
	-- PAS DE DECLENCHEMENT AU CLIC NON PLUS. En `Style = Custom` il n'y a aucune interface Roblox a viser, donc
	-- rien ne borne ce que ce reglage rend cliquable : on le coupe plutot que de decouvrir ou il s'arrete.
	--
	-- CE N'ETAIT PAS LUI, LE CLIC QUI OUVRAIT LE CAMION -- c'etait la touche reglee sur "aucune", juste au-dessus.
	-- On garde quand meme la coupure, mais le commentaire ne lui attribue plus un bug qu'elle n'a pas cause.
	--
	-- Le tap mobile ne passe pas par lui : c'est la pilule qu'on tape, et elle appelle `InputHoldBegin` a la main.
	prompt.ClickablePrompt = false
	-- CUSTOM : Roblox garde la proximite, la touche E et le tap mobile, mais n'affiche rien. La pilule est
	-- dessinee cote client.
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = anchor

	prompt.Triggered:Connect(function(_player: Player)
		-- UNE BASCULE, et rien de plus : le meme appui ouvre et referme. Aucun etat a valider -- le pire qu'un
		-- joueur puisse faire est d'ouvrir une porte de camion.
		truck.open = not truck.open
		-- ET ON LE DIT AU MONDE. L'interface des outils n'a pas a refaire la detection de proximite ni a suivre
		-- l'animation : elle demande "est-elle ouverte ?", et l'attribut repond -- chez tout le monde, y compris
		-- chez un client arrive en retard.
		model:SetAttribute(TruckConfigs.OPEN_ATTRIBUTE, truck.open)
		-- LE SON PART A L'APPUI, pas a la fin du mouvement : c'est le geste du joueur qu'il accompagne. Attendre
		-- que la porte soit ouverte le decalerait d'une seconde et il ne repondrait plus a rien.
		--
		-- Lu APRES la bascule : `truck.open` porte deja l'etat VOULU, donc il dit quel son jouer sans qu'on ait a
		-- retenir le precedent.
		if truck.open then
			SoundUtils.play(TruckConfigs.DOOR_OPEN_SOUND, door :: BasePart)
		else
			-- LA FERMETURE ARRIVE EN RETARD. Le bruit d'une porte qui claque se fait quand elle TOUCHE, pas quand
			-- on la pousse : joue a l'appui, il precedait l'image de la porte encore grande ouverte.
			task.delay(TruckConfigs.DOOR_CLOSE_SOUND_DELAY, function()
				-- ON REVALIDE AVANT DE JOUER. Un second appui pendant l'attente rouvre la porte, et le claquement
				-- partirait alors sur une porte qui s'ouvre. Le drapeau dit l'etat COURANT, pas celui d'il y a une
				-- demi-seconde.
				if not truck.open and (door :: BasePart).Parent then
					SoundUtils.play(TruckConfigs.DOOR_CLOSE_SOUND, door :: BasePart)
				end
			end)
		end
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
