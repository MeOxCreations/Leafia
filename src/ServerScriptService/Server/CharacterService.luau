--!strict
-- Reglages appliques au personnage a chaque apparition.
-- Separe de ToolService : la vitesse de marche n'a rien a voir avec ce que le joueur tient dans les mains.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterConfigs = require(ReplicatedStorage.Modules.Configs.CharacterConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local CharacterService = {}

local HUMANOID_TIMEOUT = 10
local ANIMATOR_TIMEOUT = 5

-- Etat du sprint, retenu cote serveur. Sans lui, la reprise d'apres atterrissage ne saurait pas vers quelle
-- vitesse remonter : un joueur qui retombe en tenant Shift doit retrouver le SPRINT, pas la marche.
local sprinting: { [Player]: boolean } = {}
-- Vitesse imposee par une autre feature (travail au pied d'une haie, par exemple). Tant qu'elle existe, elle
-- prime sur la marche ET le sprint.
--
-- POURQUOI PASSER PAR ICI plutot que de laisser chaque feature ecrire dans WalkSpeed : elles se battraient.
-- La haie mettrait 5, le sprint remettrait 17 la frame d'apres, la reprise d'atterrissage ferait sa rampe
-- par-dessus. Un seul module possede WalkSpeed ; les autres declarent ce qu'ils veulent, il tranche.
local speedOverride: { [Player]: number } = {}
-- Joueurs dont la vitesse est en train de rejoindre sa cible. Sert de liste de travail a la boucle : elle ne
-- touche qu'a eux, donc elle ne coute rien quand personne ne bouge de regime.
local recovering: { [Player]: boolean } = {}
-- Piste d'atterrissage de chaque joueur, gardee pour pouvoir la COUPER. Elle est en priorite Action, donc elle
-- masque la marche de Roblox tant qu'elle joue : si on la laisse aller au bout, les jambes restent figees puis
-- la marche apparait d'un coup.
local landingTracks: { [Player]: AnimationTrack } = {}

-- LA seule definition de "a quelle vitesse ce joueur devrait aller". Tout le reste s'y refere.
local function targetSpeed(player: Player): number
	local override = speedOverride[player]
	if override then
		return override
	end
	return if sprinting[player] then CharacterConfigs.SPRINT_SPEED else CharacterConfigs.WALK_SPEED
end

-- Prepare l'animation d'atterrissage et branche la reception : animation + perte de vitesse.
local function setupLanding(player: Player, character: Model, humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = humanoid:WaitForChild("Animator", ANIMATOR_TIMEOUT) :: Animator?
	end
	if not animator then
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = CharacterConfigs.LANDING_ANIMATION_ID
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		warn("[CharacterService] Animation d'atterrissage impossible a charger")
	end
	if track then
		track.Priority = CharacterConfigs.LANDING_PRIORITY
		-- FORCE non bouclee, quoi qu'en dise l'editeur. Une reception se termine par definition : bouclee, elle
		-- reste a plein poids pour toujours.
		--
		-- Consequence observee : elle est en Action, comme le pas chasse. A priorite EGALE Roblox ne choisit
		-- pas, il MELANGE les deux. Les jambes recevaient donc en permanence une moyenne entre une reception et
		-- un pas chasse, ce qui ne ressemble a rien et ne se diagnostique pas a l'oeil.
		track.Looped = false
		landingTracks[player] = track
	end

	-- StateChanged plutot qu'un test de vitesse verticale : Roblox connait deja le moment exact ou le
	-- personnage touche le sol, inutile de le redeviner a la main.
	humanoid.StateChanged:Connect(function(_, newState: Enum.HumanoidStateType)
		if newState ~= Enum.HumanoidStateType.Landed or not character.Parent then
			return
		end
		if track then
			-- Rejouee depuis le debut a chaque atterrissage. La piste n'est pas bouclee : elle s'arrete seule.
			track:Play(0.1)
		end
		-- PAS DE RALENTISSEMENT ICI, et c'est un choix : couper les jambes a l'atterrissage donnait du POIDS au
		-- saut mais rendait le jeu collant -- on retombe sans arret dans un jardin, et chaque reception coutait
		-- une demi-seconde de marche molle. L'animation, elle, reste : elle raconte l'impact sans le facturer.
	end)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", HUMANOID_TIMEOUT)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	-- Nouveau personnage : toute recuperation en cours portait sur l'ancien. Le sprint aussi repart a zero,
	-- le client le redemandera s'il tient encore la touche.
	recovering[player] = nil
	sprinting[player] = nil
	speedOverride[player] = nil
	-- L'ancienne piste appartenait a l'Animator du personnage detruit : elle ne pointe plus sur rien.
	landingTracks[player] = nil

	-- Applique cote SERVEUR : le client peut ecrire dans son propre Humanoid, donc une valeur posee la-bas ne
	-- serait qu'une suggestion. Ici elle fait autorite.
	humanoid.WalkSpeed = CharacterConfigs.WALK_SPEED
	humanoid.JumpHeight = CharacterConfigs.JUMP_HEIGHT
	-- Coupe l'auto-jump (le perso saute tout seul en butant sur le bas d'une haie / un obstacle). EN CODE ici (et pas via
	-- un reglage StarterPlayer par-place) pour que ce soit vrai dans TOUS les lieux : le tuto n'a pas le reglage de Leafia.
	humanoid.AutoJumpEnabled = false

	setupLanding(player, character, humanoid)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

-- Sprint : le client demande, le serveur decide.
local function onSetSprint(player: Player, wants: unknown)
	if typeof(wants) ~= "boolean" then
		return
	end
	sprinting[player] = wants

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	-- Pendant une recuperation on ne touche PAS a la vitesse : la boucle est seule aux commandes, et elle lira
	-- la nouvelle cible d'elle-meme. Ecrire ici remettrait le joueur a pleine vitesse en plein atterrissage.
	if recovering[player] then
		return
	end
	humanoid.WalkSpeed = targetSpeed(player)
end

-- Coupe l'animation d'atterrissage des que le joueur repart. On teste MoveDirection, l'INTENTION de deplacement
-- du joueur, et non sa vitesse reelle : au moment ou il touche le sol il glisse encore, sa vitesse n'est donc
-- pas un signal fiable. MoveDirection ne bouge que s'il pousse vraiment sur ses touches.
local function cancelLandingIfMoving()
	for player, track in pairs(landingTracks) do
		if track.IsPlaying then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid:IsA("Humanoid") and humanoid.MoveDirection.Magnitude > 0 then
				-- En fondu, pas net : la marche revient en douceur au lieu de claquer.
				track:Stop(CharacterConfigs.LANDING_CANCEL_FADE)
			end
		end
	end
end

-- Remonte la vitesse des joueurs qui viennent d'atterrir. Une seule boucle pour tout le monde, qui ne parcourt
-- que ceux en cours de recuperation : elle ne coute rien quand personne ne saute.
local function stepRecovery(dt: number)
	cancelLandingIfMoving()

	for player in pairs(recovering) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (humanoid and humanoid:IsA("Humanoid")) then
			recovering[player] = nil
			continue
		end

		-- Rampe BIDIRECTIONNELLE : elle sert a remonter apres un atterrissage, mais aussi a descendre quand une
		-- feature impose une vitesse de travail. Montee et descente ont leur propre rythme.
		local target = targetSpeed(player)
		local current = humanoid.WalkSpeed
		local rate = if target > current
			then CharacterConfigs.SPEED_SPEEDUP_RATE
			else CharacterConfigs.SPEED_SLOWDOWN_RATE
		local step = rate * dt

		if math.abs(target - current) <= step then
			-- Valeur EXACTE a l'arrivee, pas approchee : sinon le joueur garderait un ecart de vitesse minime
			-- pour toujours, et deux joueurs cote a cote finiraient par se decaler.
			humanoid.WalkSpeed = target
			recovering[player] = nil
		else
			humanoid.WalkSpeed = current + (if target > current then step else -step)
		end
	end
end

--
-- Impose une vitesse a un joueur, ou la retire avec `nil`. La transition est progressive dans les deux sens :
-- l'appelant declare une intention, il ne pilote pas la valeur frame par frame.
function CharacterService.setSpeedOverride(player: Player, speed: number?)
	if speedOverride[player] == speed then
		return
	end
	speedOverride[player] = speed
	-- Reveille la rampe : c'est elle qui rejoindra la nouvelle cible.
	recovering[player] = true
end

function CharacterService.init()
	local sprintRemote = RemoteSetup.getRemote("SetSprint", "Character")
	if sprintRemote and sprintRemote:IsA("RemoteEvent") then
		sprintRemote.OnServerEvent:Connect(onSetSprint)
	else
		warn("[CharacterService] Remote Character/SetSprint introuvable")
	end

	RunService.Heartbeat:Connect(stepRecovery)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		sprinting[player] = nil
		recovering[player] = nil
		speedOverride[player] = nil
		landingTracks[player] = nil
	end)
end

return CharacterService
