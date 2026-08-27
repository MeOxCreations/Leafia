--!strict
-- Autorite SERVEUR sur la tondeuse PORTEE. Meme mecanique que l'echelle, en plus simple : a la prise on desancre
-- la tondeuse et on SOUDE sa RootPart au HRP du porteur. La soudure replique la position a tout le monde, sans
-- flot de remotes et sans que la tondeuse puisse tomber ou se decrocher.
--
-- CE SERVICE NE COUPE RIEN. L'herbe est CLIENTE (chaque joueur fabrique la sienne), donc la coupe l'est aussi :
-- c'est MowController qui appelle GrassZoneController.mowAt. Ici on ne decide que d'UNE chose : qui porte quoi.
--
-- L'offset de portage est CALCULE ici sur la geometrie du modele, jamais envoye par le client : il n'y a donc
-- rien a valider et rien a falsifier. Il n'est pas non plus regle a l'oeil dans la config -- voir carryC0.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local MowConfigs = require(ReplicatedStorage.Modules.Configs.MowConfigs)
local CarryUtils = require(ReplicatedStorage.Modules.Utils.CarryUtils)
local CharacterService = require(script.Parent.CharacterService)
local ToolService = require(script.Parent.ToolService)

local MowService = {}

type PartState = { anchored: boolean, canCollide: boolean }
type CarryState = {
	owner: Player,
	parts: { [BasePart]: PartState },
	weld: Weld?,
	start: AnimationTrack?, -- tirage de corde, jouee UNE fois a la prise. La pose du guidon suit.
	run: Sound?, -- boucle du moteur, clonee sur la machine. Detruite a la repose.
	launcherJoint: Motor6D?, -- poignee du lanceur accrochee a la main du joueur pendant le demarrage
	launcherHome: CFrame?, -- sa place SUR LA MACHINE, relevee a la prise pour l'y rendre ensuite
	hold: AnimationTrack?, -- pose "mains sur le guidon", figee au marqueur. Coupee a la repose.
	push: AnimationTrack?, -- pose EMBARQUE (penche en arriere). Posee image par image, jamais jouee.
	reverse: AnimationTrack?, -- pose REGARD ARRIERE. Posee elle aussi.
	reverseAmount: number, -- 0 = tete droite, 1 = tete tournee. Lisse, pour que le regard ne claque pas.
	holdGuard: RBXScriptConnection?, -- filet : rattrape la pose si le marqueur est rate (image perdue)
	motor: AnimationTrack?, -- boucle du moteur, sur l'Animator de la TONDEUSE
	lever: AnimationTrack?, -- levier d'accelerateur : on pilote sa TimePosition, on ne la laisse pas jouer
	tick: RBXScriptConnection?, -- boucle de la machine : montee en vitesse + position du levier
	speed: number, -- vitesse COURANTE du porteur, montee/descente lissee
	baseC0: CFrame, -- offset de portage au repos, sans le ballant. Le ballant se compose PAR-DESSUS.
	backDist: number, -- recul de la machine derriere sa racine. PIVOT du cabrage : autour de la racine, c'est l'arriere qui se leverait.
	lift: number, -- cabrage courant, en radians. Retombe tout seul.
	liftVel: number, -- vitesse du ressort de cabrage. C'est ELLE qu'on pousse, pas la position.
	pulls: number, -- tirages deja faits sur cette prise
	pullsNeeded: number, -- combien il en faut pour que le moteur prenne. Tire au sort a la prise.
	success: Sound?, -- le son de reussite en cours : la boucle moteur s'enchaine sur SA fin
	swing: number, -- retard angulaire courant, en radians. Positif = la machine traine d'un cote
	steerInput: number, -- braquage demande par le client, borne a [-1, 1]. Sert A L'ARRET uniquement.
	pushTime: number, -- ou l'on en est dans l'anime "embarque", en secondes. Avance quand on pousse, recule sinon.
	driveInput: number, -- avance demandee par le client, bornee a [-1, 1]. L'INTENTION, pas la vitesse mesuree.
	turnLift: number, -- cabrage DU VIRAGE, en radians. S'ajoute a `lift` (le cabrage du demarrage) sur le meme pivot.
	humanoid: Humanoid?, -- porteur, garde pour rendre le saut a la repose
	jumpWasEnabled: boolean, -- etat du saut AVANT la prise : on restaure, on ne force pas a true
	jumpHeight: number, -- valeurs REELLES d'avant, pas les defauts Roblox : un autre systeme a pu les changer
	jumpPower: number,
}

-- On cle la pose JUSTE avant la derniere image, jamais dessus : a la derniere image pile, la piste bouclee
-- repart au debut avant qu'on ait pu la figer.
local HOLD_EPSILON = 0.001
-- Duree MINIMALE pour qu'une piste soit prise au serieux. Une piste encore en cours de chargement annonce une
-- Length minuscule (voire nulle) : la comparaison `TimePosition >= Length - epsilon` devenait alors VRAIE des
-- l'image ZERO, le filet figeait la pose au tout debut, et le personnage restait droit comme un R15 sans
-- animation. Symptome trompeur : intermittent, parce que c'est une course entre le chargement et la 1re image.
local HOLD_MIN_LENGTH = 0.05
-- En dessous de cet angle (radians, ~0.06 degre) on considere la machine DROITE et on cle la valeur.
local SWING_SNAP = 0.001
local ANIMATOR_TIMEOUT = 5 -- l'Animator d'un PERSONNAGE arrive apres l'Humanoid (contrairement a un modele de map)

-- Generateur PROPRE au service : `math.random` est partage par tout le jeu, et deux features qui le
-- consomment se decalent mutuellement sans qu'on comprenne pourquoi.
local rng = Random.new()

local carried: { [Model]: CarryState } = {}

local function rootOf(model: Model): BasePart?
	local root = model.PrimaryPart or model:FindFirstChild(MowConfigs.ROOT_NAME)
	return if root and root:IsA("BasePart") then root else nil
end

-- Une tondeuse VALIDE : un Model au bon nom, avec une racine. On ne fait confiance a aucun nom envoye par le
-- client -- c'est l'instance elle-meme qu'on verifie.
local function isMower(inst: Instance?): Model?
	if not (inst and inst:IsA("Model") and inst.Name == MowConfigs.MODEL_NAME) then
		return nil
	end
	local model = inst :: Model
	if not model:IsDescendantOf(Workspace) or not rootOf(model) then
		return nil
	end
	return model
end

-- Une SEULE Instance Animation pour tout le serveur : c'est un porteur d'ID, pas un etat. La creer par prise
-- multiplierait les instances sans rien apporter.
local holdAnim: Animation? = nil
local function getHoldAnimation(): Animation
	if not holdAnim then
		local a = Instance.new("Animation")
		a.Name = "LeafiaMowerHold"
		a.AnimationId = MowConfigs.HOLD_ANIM_ID
		holdAnim = a
	end
	return holdAnim :: Animation
end

-- Animations de la MACHINE, mises en cache : ce sont des porteurs d'ID, pas des etats.
local machineAnims: { [string]: Animation } = {}
local function machineAnimation(id: string): Animation?
	if id == "" then
		return nil
	end
	local a = machineAnims[id]
	if not a then
		a = Instance.new("Animation")
		a.AnimationId = id
		machineAnims[id] = a
	end
	return a
end

-- L'Animator de la TONDEUSE. Un mesh rigge importe par le 3D Importer arrive avec un AnimationController VIDE :
-- Roblox n'y met pas d'Animator. On le CREE au lieu de renoncer -- meme piege que sur les arbres d'ambiance.
local function machineAnimator(model: Model): Animator?
	local holder: Instance? = model:FindFirstChildOfClass("AnimationController")
		or model:FindFirstChildOfClass("Humanoid")
	if not holder then
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

-- SONS. Clones sur la MACHINE (pas sur le joueur) : le son sort donc de la tondeuse, se spatialise, et tout le
-- monde l'entend puisque tout ca se passe cote serveur.
-- On CLONE au lieu de jouer l'original : deux joueurs qui tondent en meme temps ont chacun le sien.
local warnedNoSound: { [string]: boolean } = {}
local function findSound(name: string): Sound?
	local node: Instance? = SoundService
	for _, step in ipairs(MowConfigs.SOUND_FOLDER) do
		node = node and node:FindFirstChild(step)
	end
	local sound = node and node:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		return sound
	end
	-- UNE FOIS PAR NOM MANQUANT, et pas une fois pour toutes : avec un seul drapeau global, un dossier correct
	-- mais un NOM de son faux ne se signalait qu'une fois -- on corrigeait le premier et le deuxieme restait muet.
	-- Une fois par prise, en revanche, remplirait la console.
	if not warnedNoSound[name] then
		warnedNoSound[name] = true
		warn(
			`[MowService] Son "{name}" introuvable sous SoundService.`
				.. `{table.concat(MowConfigs.SOUND_FOLDER, ".")} -- verifie le NOM et le DOSSIER dans Studio.`
		)
	end
	return nil
end

-- Son PONCTUEL sur la machine : il se detruit tout seul a la fin, sinon chaque prise laisserait une instance.
-- Rend le clone joue, pour que l'appelant puisse s'y accrocher (enchainer un autre son sur sa fin, par exemple).
local function playOnce(parent: BasePart, name: string): Sound?
	local source = findSound(name)
	if not source then
		return nil
	end
	local sound = source:Clone()
	sound.Looped = false
	sound.Parent = parent
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	return sound
end

-- L'Animator du PERSONNAGE. Un seul endroit le sait : le demarrage et la pose du guidon en ont besoin, et deux
-- copies de cette recherche finiraient par diverger sur le timeout.
-- A CharacterAdded l'Animator arrive quelques frames APRES l'Humanoid : un FindFirstChildOfClass nu rend nil.
local function getAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local found = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", ANIMATOR_TIMEOUT)
	return if found and found:IsA("Animator") then found else nil
end

-- LA POIGNEE DU LANCEUR passe dans la main du joueur pendant le demarrage.
--
-- Le placement est CALCULE, pas regle a l'oeil : on met l'attachment de la poignee en C1 et celui de la main en
-- C0. Rappel du montage (deja au journal) : `Part1.CFrame = Part0.CFrame * C0 * C1:Inverse()` -- l'attachment de
-- la piece vient donc se coller exactement sur celui de la main, axes alignes. C'est l'attachment qui decide de
-- l'angle, et il est pose dans Studio une fois pour toutes.
--
-- On note d'abord sa place SUR LA MACHINE : c'est la qu'on la rendra, exactement, une fois la corde tiree.
local function attachLauncher(model: Model, character: Model, state: CarryState)
	local root = rootOf(model)
	local part = model:FindFirstChild(MowConfigs.LAUNCHER_PART, true)
	local hand = character:FindFirstChild(MowConfigs.PULL_HAND, true)
	if not (root and part and part:IsA("BasePart") and hand and hand:IsA("BasePart")) then
		return
	end
	local launcher: BasePart = part
	local handPart: BasePart = hand

	state.launcherHome = root.CFrame:ToObjectSpace(launcher.CFrame)
	-- Tout joint qui la tenait deja doit partir : deux joints sur la meme piece donnent une pose qui n'est ni
	-- l'une ni l'autre, et on chercherait l'erreur dans les attachments.
	for _, d in ipairs(model:GetDescendants()) do
		if (d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("WeldConstraint")) and (d :: any).Part1 == launcher then
			d:Destroy()
		end
	end

	local joint = Instance.new("Motor6D")
	joint.Name = "LeafiaLauncherGrip"
	joint.Part0 = handPart
	joint.Part1 = launcher
	local handAt = handPart:FindFirstChild(MowConfigs.PULL_HAND_ATTACHMENT)
	local partAt = launcher:FindFirstChild(MowConfigs.LAUNCHER_ATTACHMENT)
	if handAt and handAt:IsA("Attachment") then
		joint.C0 = handAt.CFrame
	end
	if partAt and partAt:IsA("Attachment") then
		joint.C1 = partAt.CFrame
	end
	joint.Parent = handPart
	state.launcherJoint = joint
end

-- La poignee revient a sa place sur la machine, EXACTEMENT la ou elle etait. On la re-soude plutot que de la
-- poser : sans joint elle tomberait, la tondeuse etant desancree pendant le portage.
local function releaseLauncher(model: Model, state: CarryState)
	local joint = state.launcherJoint
	state.launcherJoint = nil
	if joint then
		joint:Destroy()
	end
	local home = state.launcherHome
	state.launcherHome = nil
	local root = rootOf(model)
	local part = model:FindFirstChild(MowConfigs.LAUNCHER_PART, true)
	if not (home and root and part and part:IsA("BasePart")) then
		return
	end
	local launcher: BasePart = part
	launcher.CFrame = root.CFrame * home
	local weld = Instance.new("WeldConstraint")
	weld.Name = "LeafiaLauncherHome"
	weld.Part0 = root
	weld.Part1 = launcher
	weld.Parent = launcher
end

-- DEMARRAGE : le joueur tire la corde, PUIS empoigne le guidon. `onDone` enchaine la suite.
--
-- `Looped = false` et c'est voulu : c'est un geste PONCTUEL, il doit se relacher a la fin pour laisser la place a
-- la pose de maintien. (L'inverse du guidon, qui doit TENIR sa derniere image et reste donc bouclee.)
-- Le reglage de l'editeur ne suffit pas, on l'ecrit ici : une piste bouclee par erreur resterait a plein poids
-- pour toujours et polluerait tout ce qui partage sa priorite.
--
-- Sans animation configuree, on enchaine directement -- la tondeuse reste jouable.
-- LE COUP DE CORDE : ce qui se passe a l'instant EXACT ou le bras part en arriere.
--
-- Declenche par un evenement pose DANS l'animation, pas par un delai en secondes. Un delai suppose qu'on connait
-- la cadence du geste, alors qu'elle vit dans l'animation : la retoucher decalait tout en silence. Le marqueur,
-- lui, suit l'animation quoi qu'on lui fasse -- et les trois retours (secousse, toux, son) restent d'accord
-- entre eux par construction, sans qu'on ait a les recaler un par un.
local function yankStarter(model: Model, state: CarryState)
	-- Il a pu reposer la machine entre le clic et l'image du marqueur : cabrer une tondeuse qu'on ne tient plus
	-- la laisserait de travers.
	if carried[model] ~= state then
		return
	end
	-- LA MACHINE SE CABRE. On donne une VITESSE au ressort, on ne pose pas l'angle : poser l'angle la faisait
	-- monter en une seule image, donc brutalement. Une impulsion se voit monter.
	-- La vitesse a donner pour atteindre a peu pres l'angle voulu vaut angle x racine(raideur).
	state.liftVel = math.rad(MowConfigs.PULL_LIFT) * math.sqrt(MowConfigs.PULL_LIFT_STIFFNESS)

	-- LE MOTEUR TOUSSE : on joue sa boucle UNE fois, non bouclee. Il tourne, il ne PREND pas -- c'est ce qui fait
	-- comprendre qu'on essaie de le lancer, et qu'un tirage peut echouer.
	local animator = machineAnimator(model)
	local cough = machineAnimation(MowConfigs.MOTOR_ANIM_ID)
	if animator and cough then
		local ok, t = pcall(function()
			return animator:LoadAnimation(cough)
		end)
		if ok and typeof(t) == "Instance" then
			local track = t :: AnimationTrack
			track.Looped = false -- PONCTUEL : ecrit ici, le reglage de l'editeur n'est qu'une suggestion
			track.Priority = Enum.AnimationPriority.Idle
			track:Play()
		end
	end

	-- LE COUP QUI VA REUSSIR SONNE DIFFEREMMENT, et il sonne MAINTENANT -- pendant que le bras tire encore.
	--
	-- C'est ce qui fait la difference entre "le moteur a demarre" et "JE l'ai demarre" : l'oreille entend la prise
	-- au moment du geste, donc elle l'attribue au geste. Le meme son joue une seconde plus tard en ferait une
	-- consequence du hasard.
	--
	-- `pulls` compte les coups TERMINES ; celui-ci est donc le suivant. Rien a deviner : le serveur sait depuis le
	-- depart combien il en faut.
	local root = rootOf(model)
	if root then
		local decisive = state.pulls + 1 >= state.pullsNeeded
		local played = playOnce(root, if decisive then MowConfigs.SUCCESS_SOUND else MowConfigs.PULL_SOUND)
		if decisive then
			-- Garde pour que la boucle moteur puisse s'enchainer sur SA fin, et pas lui passer dessus.
			state.success = played
		end
	end
end

local function playStart(model: Model, character: Model, state: CarryState, onDone: () -> ())
	local asset = machineAnimation(MowConfigs.START_ANIM_ID)
	local animator = getAnimator(character)
	if not (asset and animator) then
		onDone()
		return
	end
	local ok, result = pcall(function()
		return animator:LoadAnimation(asset)
	end)
	if not ok or typeof(result) ~= "Instance" then
		warn(`[MowService] Demarrage non chargeable ({MowConfigs.START_ANIM_ID}).`)
		onDone()
		return
	end

	local track = result :: AnimationTrack
	track.Looped = false
	track.Priority = MowConfigs.START_PRIORITY
	state.start = track
	-- BRANCHE UNE SEULE FOIS, a la creation de la piste, et surtout pas au clic : la piste se REARME apres un
	-- tirage rate, donc une connexion posee a chaque clic s'empilerait et la machine se cabrerait deux fois, puis
	-- trois. Le signal, lui, retire a chaque passage du marqueur -- c'est exactement ce qu'on veut.
	track:GetMarkerReachedSignal(MowConfigs.PULL_EVENT):Connect(function()
		yankStarter(model, state)
	end)
	-- `Stopped` couvre la fin NORMALE comme un arret force (repose pendant le geste) : dans les deux cas la
	-- suite doit etre annulee ou enchainee, jamais laissee en plan.
	-- `Connect` et non `Once` : la piste se REARME apres un tirage rate, donc elle re-signalera sa fin.
	track.Stopped:Connect(function()
		-- Le joueur a pu reposer la tondeuse pendant le tirage : dans ce cas on rend la poignee et on s'arrete la.
		if carried[model] ~= state then
			state.start = nil
			releaseLauncher(model, state)
			return
		end

		state.pulls += 1
		if state.pulls >= state.pullsNeeded then
			-- LE MOTEUR PREND. La poignee retourne sur la machine, la suite s'enchaine.
			state.start = nil
			releaseLauncher(model, state)
			onDone()
			return
		end

		-- RATE. On se REMET en position, corde en main : le joueur peut retirer tout de suite. La poignee NE
		-- retourne PAS sur la machine -- il ne l'a jamais lachee.
		-- On relance la piste avant de la figer : une piste terminee ne repart pas en ecrivant sa TimePosition.
		-- Fondu ZERO : on revient a la pose d'ou on est parti, il n'y a rien a fondre.
		track:Play(0)
		track:AdjustSpeed(0)
		track.TimePosition = 0
	end)
	-- FIGEE A SA PREMIERE IMAGE : le personnage TIENT la corde, pret a tirer. C'est le CLIC du joueur qui la
	-- relance (voir MowService.pull) -- on ne demarre pas une tondeuse en la regardant.
	-- Meme mecanique que le lanceur du taille-haie : les deux etats partagent la piste, seule la vitesse change.
	track:Play(MowConfigs.START_FADE)
	track:AdjustSpeed(0)
	track.TimePosition = 0
	-- La poignee passe dans la main DES la posture "pret a tirer" : c'est deja elle qu'on tient.
	attachLauncher(model, character, state)
end

-- TIRAGE DE CORDE : le joueur a clique. On relance la piste figee -- c'est le seul changement, la posture etait
-- deja la bonne, donc il n'y a aucune transition a fondre.
local function pullStarter(state: CarryState)
	local track = state.start
	if not track or track.Speed ~= 0 then
		return -- pas de corde a tirer, ou deja en train de la tirer
	end
	-- ON NE FAIT QUE RELANCER LA PISTE. Tout ce qui se voit et s'entend (la machine qui se cabre, la toux du
	-- moteur, le son de la corde) part du MARQUEUR pose dans l'animation, pas d'ici -- voir yankStarter.
	track:AdjustSpeed(1)
end

-- POSE DE MAINTIEN : le joueur attrape le guidon, et TIENT la pose tant qu'il pousse.
--
-- Jouee cote SERVEUR -> elle se replique a tous, comme les animations de l'echelle.
--
-- Priorite Action : en dessous (Movement) la marche l'ecraserait. L'animation ne cle QUE le torse, la tete et les
-- bras -- si elle clait aussi les jambes, Action les figerait et le joueur glisserait sans marcher.
--
-- Looped = TRUE et non false : une piste non bouclee se RELACHE en arrivant au bout et la pose saute. On la fige
-- donc au marqueur (vitesse 0) AVANT la fin, et elle ne boucle jamais puisqu'elle n'avance plus.
local function playHold(character: Model, state: CarryState)
	local animator = getAnimator(character)
	if not animator then
		warn("[MowService] Pas d'Animator sur le porteur : pose de maintien non jouee.")
		return
	end

	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(getHoldAnimation())
	end)
	if not ok or typeof(result) ~= "Instance" then
		warn(`[MowService] Pose de maintien non chargeable ({MowConfigs.HOLD_ANIM_ID}).`)
		return
	end

	local track = result :: AnimationTrack
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:GetMarkerReachedSignal(MowConfigs.HOLD_READY_EVENT):Connect(function()
		track:AdjustSpeed(0) -- mains sur le guidon : on TIENT
	end)
	track:Play(MowConfigs.HOLD_FADE)
	track.TimePosition = 0
	state.hold = track

	-- POSE EMBARQUE, sur le MEME Animator (c'est le joueur qui se penche, pas la machine).
	-- Vitesse ZERO des le depart : on ecrit sa position, elle ne defile jamais toute seule.
	--
	-- `Looped = true` MALGRE la vitesse zero : une piste non bouclee se RELACHE en arrivant a sa derniere image,
	-- et la pose sauterait au moment precis ou l'on veut la tenir.
	local pushAsset = machineAnimation(MowConfigs.PUSH_ANIM_ID)
	if pushAsset then
		local okPush, pushTrack = pcall(function()
			return (animator :: Animator):LoadAnimation(pushAsset)
		end)
		if okPush and typeof(pushTrack) == "Instance" then
			local t = pushTrack :: AnimationTrack
			t.Looped = true
			t.Priority = MowConfigs.PUSH_PRIORITY
			t:Play(MowConfigs.HOLD_FADE)
			t:AdjustSpeed(0)
			t.TimePosition = 0
			state.push = t
		end
	end

	-- REGARD ARRIERE, meme Animator et meme principe : posee, jamais jouee.
	local backAsset = machineAnimation(MowConfigs.REVERSE_ANIM_ID)
	if backAsset then
		local okBack, backTrack = pcall(function()
			return (animator :: Animator):LoadAnimation(backAsset)
		end)
		if okBack and typeof(backTrack) == "Instance" then
			local t = backTrack :: AnimationTrack
			t.Looped = true
			t.Priority = MowConfigs.REVERSE_PRIORITY
			t:Play(MowConfigs.HOLD_FADE)
			t:AdjustSpeed(0)
			t.TimePosition = 0
			state.reverse = t
		end
	end

	-- FILET. Le marqueur suffit tant que les images tombent bien, mais une seule image perdue et la tete de
	-- lecture le DEPASSE sans que le signal serve a rien : la piste boucle alors, et la pose repart du debut.
	-- Symptome vecu : ca marche la plupart du temps, et parfois non. On surveille donc aussi la position, et
	-- on la cle juste avant la fin. Celui des deux qui arrive en premier gagne, l'autre n'a plus rien a faire.
	state.holdGuard = RunService.Heartbeat:Connect(function()
		-- `TimePosition > 0` en plus de la vitesse : une piste qui vient d'etre lancee peut annoncer une vitesse
		-- nulle avant que Play ne prenne effet. Lacher le filet a cet instant le rendrait inutile pile quand il
		-- sert -- au tout debut.
		if track.Speed == 0 and track.TimePosition > 0 then
			-- Le marqueur a fait le travail : plus rien a surveiller.
			if state.holdGuard then
				state.holdGuard:Disconnect()
				state.holdGuard = nil
			end
			return
		end
		-- Trois conditions, et les deux premieres sont des garde-fous, pas du zele :
		--   IsPlaying      -> une piste pas encore demarree n'a rien a figer ;
		--   Length credible -> une piste en cours de chargement ment sur sa duree (voir HOLD_MIN_LENGTH).
		local length = track.Length
		if track.IsPlaying and length > HOLD_MIN_LENGTH and track.TimePosition >= length - HOLD_EPSILON then
			track.TimePosition = length - HOLD_EPSILON
			track:AdjustSpeed(0)
		end
	end)
end

-- Coupe UNE pose tenue. Accepte nil : toutes ces pistes peuvent deja avoir ete rendues.
--
-- pcall : on passe aussi par ici quand le joueur MEURT en poussant. Son Animator est alors deja detruit, et
-- couper une piste morte leve. Ce n'est pas un cas anormal, donc on ne warn pas -- on nettoie, point.
local function stopPose(track: AnimationTrack?)
	if not track then
		return
	end
	local t = track :: AnimationTrack
	pcall(function()
		-- On rend la vitesse AVANT d'arreter : une piste figee a 0 ne fondrait pas, elle disparaitrait d'un coup.
		t:AdjustSpeed(1)
		t:Stop(MowConfigs.HOLD_FADE)
	end)
end

-- TOUTES LES POSES TENUES SUR LE JOUEUR SE COUPENT ICI : le guidon, le virage, le regard arriere, le tirage.
-- Elles vivent sur l'Animator du JOUEUR et non sur celui de la machine, donc elles ne partent pas avec elle.
--
-- UNE PAR UNE, ET SURTOUT PAS DANS UNE LISTE. La version d'avant les parcourait avec `ipairs` sur un tableau
-- construit a la volee -- et `ipairs` S'ARRETE AU PREMIER NIL. Or `state.start` passe a nil des que le moteur a
-- pris : la boucle ne tournait donc ZERO fois, et le regard arriere restait joue. On lachait la tondeuse, le
-- joueur gardait la tete tournee en arriere, pour toujours.
-- C'est le genre de trou qui ne se voit jamais a la lecture : le code a l'air de couvrir les trois cas.
local function stopHold(state: CarryState)
	if state.holdGuard then
		state.holdGuard:Disconnect()
		state.holdGuard = nil
	end
	stopPose(state.start)
	state.start = nil
	stopPose(state.push)
	state.push = nil
	stopPose(state.reverse)
	state.reverse = nil
	stopPose(state.hold)
	state.hold = nil
end

-- SAUT COUPE pendant le portage. On pousse une tondeuse, on ne saute pas avec.
-- On MEMORISE l'etat d'avant et on le restaure, plutot que de forcer `true` a la repose : un autre systeme peut
-- avoir de bonnes raisons d'avoir deja coupe le saut (une cinematique, un dialogue), et le lui rendre de force
-- casserait le sien.
-- DEUX gestes explicites plutot qu'un booleen : bloquer et rendre ne sont PAS symetriques. Rendre doit toujours
-- remettre les VALEURS d'origine, meme si le saut etait deja interdit avant la prise -- sinon un joueur qui prend
-- la tondeuse pendant un dialogue garderait JumpHeight a zero pour toujours.
local function blockJump(state: CarryState)
	local humanoid = state.humanoid
	if not (humanoid and humanoid.Parent) then
		return
	end
	-- LES PROPRIETES FONT LE TRAVAIL : elles se REPLIQUENT. `SetStateEnabled`, lui, n'agit que sur la machine
	-- qui l'appelle -- or c'est le CLIENT qui simule le personnage, pas le serveur. Le couper cote serveur seul
	-- laissait donc sauter, vu a l'ecran.
	-- On met les DEUX a zero : laquelle compte depend de UseJumpPower, et ce reglage peut changer sans nous.
	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0
	-- En plus, pas a la place : coupe aussi un saut deja demande du cote serveur.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

local function restoreJump(state: CarryState)
	local humanoid = state.humanoid
	if not (humanoid and humanoid.Parent) then
		return
	end
	humanoid.JumpHeight = state.jumpHeight
	humanoid.JumpPower = state.jumpPower
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, state.jumpWasEnabled)
end

-- LA MACHINE TOURNE : moteur en boucle, levier pilote a la main, et le porteur monte en vitesse.
--
-- LE LEVIER N'EST PAS "JOUE". Sa position raconte le REGIME, pas le temps qui passe : on le pose donc a vitesse
-- zero et on ecrit sa TimePosition selon la vitesse du moment. Meme mecanique que la visee haut/bas du taille-haie
-- -- une animation dont on ne lit qu'une IMAGE, jamais le defilement.
local function startMachine(model: Model, state: CarryState)
	-- BOUCLE MOTEUR. Elle demarre ICI et pas a la prise : le moteur ne tourne qu'une fois la corde tiree.
	--
	-- MAIS PAS TOUT DE SUITE : elle attend la FIN du son de reussite, qu'elle rejoint en CHEVAUCHANT. Lancee a
	-- l'instant ou le moteur prend, elle passait par-dessus lui et le rendait inaudible -- on croyait qu'il ne
	-- jouait pas.
	--
	-- On demarre AVANT la fin et pas apres : deux sons colles bout a bout laissent un silence d'une image ou deux,
	-- et ce silence s'entend plus que la transition elle-meme.
	local root = rootOf(model)
	local wait = 0
	local success = state.success
	if success and success.Parent and success.IsPlaying and success.TimeLength > 0 then
		wait = math.max(success.TimeLength - success.TimePosition - MowConfigs.RUN_SOUND_OVERLAP, 0)
	end
	local function startLoop()
		-- Il a pu reposer la machine, ou la couper, pendant ce court delai.
		if carried[model] ~= state or state.run then
			return
		end
		local engine = findSound(MowConfigs.RUN_SOUND)
		if root and engine then
			local sound = engine:Clone()
			sound.Looped = true
			sound.Parent = root
			sound:Play()
			state.run = sound
		end
	end
	if wait > 0 then
		task.delay(wait, startLoop)
	else
		startLoop()
	end
	-- Lu par le client : une machine a l'arret ne coupe rien.
	model:SetAttribute(MowConfigs.RUNNING_ATTRIBUTE, true)

	local animator = machineAnimator(model)
	if not animator then
		return
	end

	local motorAsset = machineAnimation(MowConfigs.MOTOR_ANIM_ID)
	if motorAsset then
		local ok, track = pcall(function()
			return animator:LoadAnimation(motorAsset)
		end)
		if ok and typeof(track) == "Instance" then
			local t = track :: AnimationTrack
			t.Looped = true
			t.Priority = Enum.AnimationPriority.Idle
			t:Play()
			state.motor = t
		end
	end

	local leverAsset = machineAnimation(MowConfigs.LEVER_ANIM_ID)
	if leverAsset then
		local ok, track = pcall(function()
			return animator:LoadAnimation(leverAsset)
		end)
		if ok and typeof(track) == "Instance" then
			local t = track :: AnimationTrack
			-- Looped pour que la piste ne se RELACHE jamais (sinon la pose du levier saute), vitesse zero pour
			-- qu'elle n'avance pas d'elle-meme : c'est nous qui la deplacons.
			t.Looped = true
			t.Priority = Enum.AnimationPriority.Action
			t:Play()
			t:AdjustSpeed(0)
			t.TimePosition = 0
			state.lever = t
		end
	end
end

local function stopMachine(state: CarryState)
	if state.tick then
		state.tick:Disconnect()
		state.tick = nil
	end
	-- On LACHE la reference au son de reussite : il se detruit tout seul a la fin, mais garder un pointeur dessus
	-- ferait croire a une prochaine prise qu'un enchainement est en cours.
	state.success = nil
	-- Une par une, et PAS via ipairs sur une table qui peut contenir un trou : ipairs s'arrete au premier nil,
	-- donc un moteur absent aurait laisse le levier tourner pour toujours.
	local function cut(track: AnimationTrack?)
		if track then
			pcall(function()
				track:AdjustSpeed(1)
				track:Stop(MowConfigs.HOLD_FADE)
			end)
		end
	end
	cut(state.motor)
	cut(state.lever)
	if state.run then
		state.run:Destroy() -- clonee a la prise : on ne la garde pas, on la refait a la suivante
		state.run = nil
	end
	state.motor = nil
	state.lever = nil
	-- On RETIRE l'allure imposee : CharacterService reprend la main et ramene le joueur a sa marche, en
	-- douceur. Reposer une valeur nous-memes reviendrait a redevenir un deuxieme ecrivain.
	CharacterService.setSpeedOverride(state.owner, nil)
end

-- MESURE DE LA MACHINE, en une passe : son point le plus BAS, et de combien elle depasse EN ARRIERE de sa racine.
--
-- On ne compte que les parts VISIBLES : la CutZone et les autres zones logiques ne sont pas des pieces de la
-- machine, et une seule d'entre elles posee bas ou loin fausserait tout (deja paye : la tondeuse flottait).
-- Les 8 COINS de chaque part, pas son centre : une part inclinee depasse plus loin que sa position.
--
-- L'AXE D'AVANCEE est MESURE, pas devine : c'est la direction RootPart -> CutZone, et la CutZone est par
-- definition posee a l'avant, sous le carter. Sans elle on ne peut pas savoir de quel cote regarde la machine,
-- et on retombe sur un recul de config.
local function measure(model: Model, root: BasePart): (number?, number)
	local rootPos = root.Position
	local forwardDir: Vector3? = nil
	local zone = model:FindFirstChild(MowConfigs.CUT_ZONE_NAME, true)
	if zone and zone:IsA("BasePart") then
		local d = zone.Position - rootPos
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude > 1e-3 then
			forwardDir = d.Unit
		end
	end

	local low: number? = nil
	local back = 0 -- de combien la machine depasse DERRIERE la racine, le long de l'axe d'avancee
	for _, d in ipairs(model:GetDescendants()) do
		-- La zone de coupe et la boite de collision sont des volumes LOGIQUES, pas des pieces de la machine : les
		-- compter fausserait la hauteur et le recul du portage.
		if
			d:IsA("BasePart")
			and d.Name ~= MowConfigs.CUT_ZONE_NAME
			and d.Name ~= MowConfigs.HITBOX_NAME
			and d.Transparency < 1
		then
			local h = d.Size * 0.5
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local corner = (d.CFrame * CFrame.new(h.X * sx, h.Y * sy, h.Z * sz)).Position
						low = if low then math.min(low, corner.Y) else corner.Y
						if forwardDir then
							-- Projection NEGATIVE = le coin est derriere la racine. On garde le plus loin.
							back = math.max(back, -(corner - rootPos):Dot(forwardDir))
						end
					end
				end
			end
		end
	end
	return low, back
end

-- Offset de portage, CALCULE sur la geometrie reelle plutot que regle a l'oeil.
--
-- HAUTEUR : on ne descend pas d'une distance fixe sous le HRP, on vise le SOL sur lequel le joueur se tient. Le
-- HRP est toujours a HipHeight + demi-hauteur au-dessus de ses pieds : cette distance est CONNUE. Et comme le HRP
-- monte avec les pentes, la tondeuse les suit gratuitement, sans un seul raycast.
--
-- DISTANCE : c'est le GUIDON qui doit tomber a CARRY_GAP devant le joueur, pas la RootPart. La racine se place
-- donc d'autant plus loin que le guidon est en arriere d'elle. Mesure HORIZONTALE : la hauteur du guidon ne
-- doit rien changer a la distance.
--
-- Consequence : changer la taille du modele ne demande plus aucun reglage.
local function carryC0(model: Model, root: BasePart, hrp: BasePart, humanoid: Humanoid?): CFrame
	local hip = if humanoid then humanoid.HipHeight else 2
	local feet = hip + hrp.Size.Y * 0.5
	local low, back = measure(model, root)
	-- De combien la RootPart surplombe le bas de la machine : c'est ce qu'il faut remonter pour la poser au sol.
	local aboveBottom = if low then root.Position.Y - low else 0
	local down = feet - aboveBottom - MowConfigs.CARRY_CLEARANCE

	-- Le joueur se tient derriere le point le plus ARRIERE de la machine, pas derriere sa racine : la racine est
	-- a l'avant-bas du carter, s'y caler plantait le personnage AU MILIEU de la tondeuse.
	-- Faute de CutZone, on ne connait pas l'axe d'avancee : on retombe sur un recul de config.
	local forward = MowConfigs.CARRY_GAP + (if back > 0 then back else MowConfigs.CARRY_FALLBACK_BACK)

	if MowConfigs.CARRY_DEBUG then
		local r = root.CFrame
		print(
			`[MowService] PORTAGE | pieds sous HRP {string.format("%.2f", feet)}`
			.. ` | racine au-dessus du bas {string.format("%.2f", aboveBottom)}`
			.. ` | descente {string.format("%.2f", down)} | avance {string.format("%.2f", forward)}`
			.. ` | racine Y {string.format("%.2f", r.Position.Y)} bas {string.format("%.2f", low or -999)}`
			.. ` | recul mesure {string.format("%.2f", back)} | orientation racine {r:ToOrientation()}`
		)
	end
	-- ORIENTATION : on ALIGNE L'AVANT REEL DE LA MACHINE sur le regard du joueur, au lieu d'aligner betement les
	-- axes de la RootPart. Rien ne garantit que le -Z local de la racine soit l'avant de la tondeuse -- il vient du
	-- rig, pas du bon sens. Sans cette correction, la machine PIVOTAIT au moment de la prise, et on croyait qu'elle
	-- se teleportait devant le joueur.
	--
	-- L'avant reel se mesure comme partout ailleurs : RootPart -> CutZone. On le repasse en repere RACINE, et on
	-- cherche la rotation qui l'amene sur -Z (le "devant" d'un CFrame).
	local spin = math.rad(MowConfigs.CARRY_YAW)
	local zone = model:FindFirstChild(MowConfigs.CUT_ZONE_NAME, true)
	if zone and zone:IsA("BasePart") then
		local world = zone.Position - root.Position
		world = Vector3.new(world.X, 0, world.Z)
		if world.Magnitude > 1e-3 then
			local localDir = root.CFrame:VectorToObjectSpace(world.Unit)
			local flat = Vector3.new(localDir.X, 0, localDir.Z)
			if flat.Magnitude > 1e-3 then
				flat = flat.Unit
				-- Angle de cet avant par rapport a -Z, puis on tourne de l'oppose pour l'y ramener.
				spin -= math.atan2(flat.X, -flat.Z)
			end
		end
	end
	return CFrame.new(0, -down, -forward) * CFrame.Angles(0, spin, 0)
end

-- REPOSE : on retire la soudure et on rend a chaque part son etat d'origine. Celui qui a modifie est celui qui
-- restaure, et il restaure TOUT : un nettoyage reparti finit toujours par oublier un champ.
local function release(model: Model)
	local state = carried[model]
	if not state then
		return
	end
	if state.weld then
		state.weld:Destroy()
		state.weld = nil
	end
	for part, saved in pairs(state.parts) do
		if part.Parent then
			part.Anchored = saved.anchored
			part.CanCollide = saved.canCollide
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	stopHold(state)
	stopMachine(state)
	restoreJump(state)
	releaseLauncher(model, state) -- filet : repose (ou mort) en plein tirage
	carried[model] = nil
	model:SetAttribute("LeafiaCarriedBy", nil)
	model:SetAttribute(MowConfigs.RUNNING_ATTRIBUTE, nil)
	CarryUtils.release(state.owner, "Mower")
end

local function grab(player: Player, model: Model)
	if carried[model] then
		return -- deja portee, par ce joueur ou un autre
	end
	-- LES MAINS SONT DEJA PRISES (seau, echelle). Ce service ne verifiait RIEN avant : on pouvait pousser la
	-- tondeuse en portant un seau ou une echelle.
	if not CarryUtils.isFree(player) then
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end
	local root = rootOf(model)
	if not root then
		return
	end
	-- Proximite : le client DEMANDE, le serveur verifie. Sur la RootPart, pas sur GetPivot (que la CutZone decale).
	if (root.Position - hrp.Position).Magnitude > MowConfigs.MAX_GRAB_DIST then
		return
	end

	-- MESURE AVANT DE TOUCHER A QUOI QUE CE SOIT : des qu'on desancre, la physique peut deja avoir fait bouger
	-- la tondeuse d'un poil, et l'offset serait calcule sur une pose qui n'existe plus.
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local c0 = carryC0(model, root, hrp :: BasePart, humanoid)

	local state: CarryState = {
		owner = player,
		parts = {},
		weld = nil,
		start = nil,
		run = nil,
		launcherJoint = nil,
		launcherHome = nil,
		hold = nil,
		turn = nil,
		reverse = nil,
		reverseAmount = 0,
		holdGuard = nil,
		motor = nil,
		lever = nil,
		tick = nil,
		speed = 0, -- a l'arret tant que la corde n'a pas ete tiree ; la rampe monte a SPEED_MIN au demarrage
		baseC0 = c0,
		backDist = select(2, measure(model, root)),
		lift = 0,
		liftVel = 0,
		pulls = 0,
		-- Tire A LA PRISE et pas a chaque tirage : le compte doit etre stable pendant la sequence, sinon le
		-- moteur pourrait ne jamais prendre (ou prendre au premier coup) selon les tirages successifs.
		pullsNeeded = rng:NextInteger(MowConfigs.PULL_TRIES_MIN, MowConfigs.PULL_TRIES_MAX),
		swing = 0,
		steerInput = 0,
		pushTime = 0,
		driveInput = 0,
		turnLift = 0,
		humanoid = humanoid,
		jumpWasEnabled = if humanoid then humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) else true,
		jumpHeight = if humanoid then humanoid.JumpHeight else 7.2,
		jumpPower = if humanoid then humanoid.JumpPower else 50,
	}
	blockJump(state)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			state.parts[d] = { anchored = d.Anchored, canCollide = d.CanCollide }
			d.Anchored = false
			-- LA BOITE DE COLLISION GARDE SES COLLISIONS, tout le reste les perd.
			--
			-- Sans elle, la machine traversait les haies, les cloture et les portails : soudee au joueur et sans
			-- collision, elle n'existait pour la physique. Avec toutes ses parts solides, en revanche, elle se
			-- coincait dans le decor et faisait sauter le porteur -- une forme compliquee accrochee a un
			-- personnage est ingerable pour le moteur.
			-- Une seule boite simple, posee a la main dans Studio, resout les deux.
			local isHitbox = d.Name == MowConfigs.HITBOX_NAME
			d.CanCollide = isHitbox
			if isHitbox then
				-- MASSLESS : elle borne le passage, elle n'alourdit pas le joueur. Sans ca, elle change la masse
				-- de son assemblage et donc sa facon de marcher, de tomber et de monter une pente.
				d.Massless = true
				-- Pas de Touched : rien n'ecoute cet evenement, et une boite qui frotte le decor en tirerait des
				-- centaines par seconde.
				d.CanTouch = false
			end
		end
	end

	local weld = Instance.new("Weld")
	weld.Part0 = hrp
	weld.Part1 = root
	weld.C0 = c0
	weld.Parent = root
	state.weld = weld
	carried[model] = state
	-- Lu par le client pour savoir si c'est LUI qui pousse (donc s'il doit couper et tourner les roues).
	model:SetAttribute("LeafiaCarriedBy", player.UserId)
	-- ON POUSSE LA TONDEUSE A DEUX MAINS : plus d'outil pendant ce temps.
	--
	-- On RANGE l'outil au lieu de refuser la prise. Refuser laisserait le joueur appuyer sur E devant sa tondeuse
	-- sans que rien ne se passe et sans savoir pourquoi -- un cul-de-sac. Le ranger est ce qu'il aurait fait
	-- lui-meme, et la reciproque (sortir un outil pendant qu'on pousse) est bien REFUSEE, elle, dans ToolService.
	CarryUtils.claim(player, "Mower")
	ToolService.unequip(player)

	-- SEQUENCE : on tire la corde, PUIS on empoigne le guidon et le moteur se lance. Le moteur demarrait avec
	-- la prise, donc il tournait avant meme qu'on ait tire -- ca n'avait aucun sens a l'oreille comme a l'oeil.
	playStart(model, character :: Model, state, function()
		playHold(character :: Model, state)
		startMachine(model, state)
	end)

	-- BOUCLE DE LA MACHINE : montee en vitesse du porteur, et position du levier qui la raconte.
	-- Separee du filet de la pose : deux responsabilites, deux connexions, chacune coupee a son heure.
	state.tick = RunService.Heartbeat:Connect(function(dt: number)
		local hum = state.humanoid
		local char = hum and hum.Parent
		local rootPart = char and char:FindFirstChild("HumanoidRootPart")
		if not (hum and hum.Parent and rootPart and rootPart:IsA("BasePart")) then
			return
		end

		-- Vitesse REELLE, pas l'intention : pousser contre un mur ne doit pas faire monter le regime.
		local v = (rootPart :: BasePart).AssemblyLinearVelocity
		local moving = math.sqrt(v.X * v.X + v.Z * v.Z) > MowConfigs.SPEED_MOVE_EPSILON

		-- MOTEUR ARRETE = ON NE BOUGE PAS. Le client se bloque deja tout seul, mais le client ment toujours :
		-- l'autorite est ici. Cible ZERO, donc la rampe de CharacterService descend le porteur a l'arret.
		-- On ne sort PAS de la boucle pour autant : le cabrage a la corde et la soudure se calculent plus bas,
		-- et ils doivent continuer de tourner justement pendant que le moteur ne tourne pas.
		local running = model:GetAttribute(MowConfigs.RUNNING_ATTRIBUTE) == true
		-- Montee LENTE, descente VIVE : on gagne sa vitesse, on ne la garde pas gratuitement.
		local target = if not running then 0 elseif moving then MowConfigs.SPEED_MAX else MowConfigs.SPEED_MIN
		local rate = if moving and running then MowConfigs.SPEED_RAMP_UP else MowConfigs.SPEED_RAMP_DOWN
		if state.speed < target then
			state.speed = math.min(target, state.speed + rate * dt)
		else
			state.speed = math.max(target, state.speed - rate * dt)
		end
		-- On DECLARE l'allure, on n'ecrit pas dans WalkSpeed : CharacterService en est le seul proprietaire, et
		-- ecrire directement le ferait se battre avec le sprint et les autres features (sa regle, en tete de
		-- son fichier). Sa rampe est plus rapide que la notre, donc c'est bien NOTRE montee qu'on ressent.
		CharacterService.setSpeedOverride(state.owner, state.speed)

		-- BALLANT. La machine traine derriere le braquage, puis rattrape : c'est cet ecart qui se lit comme du POIDS.
		--
		-- PILOTE PAR L'INPUT, pas par le cap observe. Deriver le cap (combien le joueur a tourne depuis l'image
		-- d'avant) semblait naturel, mais le serveur recoit ce cap REPLIQUE et interpole : a l'arret net d'un
		-- virage, l'interpolation DEPASSE puis se corrige, la derivee change de SIGNE, et la machine repartait de
		-- l'autre cote -- un zig-zag. Aucun lissage ne rattrape une inversion reelle du signal ; il fallait cesser
		-- de deriver.
		--
		-- Un seul chemin pour les deux cas (en roulant ET a l'arret) : ils ne peuvent donc plus se contredire.
		local steerSign = if MowConfigs.STEER_INVERT then -1 else 1
		local maxSwing = math.rad(MowConfigs.SWING_MAX)
		-- AMPLITUDE selon l'etat : franche en roulant (poids, inertie), discrete en manoeuvre (on s'oriente).
		-- Le passage d'un angle a l'autre n'a pas besoin d'etre lisse a la main : c'est la CIBLE qui change, et
		-- l'approche vers elle (SWING_RECOVER) fait deja tout le travail.
		local swingAngle = if moving then MowConfigs.SWING_ANGLE_DRIVE else MowConfigs.SWING_ANGLE
		local target = math.clamp(
			-state.steerInput * steerSign * math.rad(swingAngle),
			-maxSwing,
			maxSwing
		)
		-- DEUX VITESSES : on se met en travers vite, on revient droit LENTEMENT. C'est l'ecart entre les deux qui
		-- fait l'elan -- avec une seule vitesse, lacher la touche faisait CLAQUER la machine dans l'axe de la
		-- marche, et rien ne ressemble moins a une machine lancee.
		local rate = if math.abs(target) > math.abs(state.swing)
			then MowConfigs.SWING_RECOVER
			else MowConfigs.SWING_RETURN
		local step = (target - state.swing) * math.min(1, rate * dt)
		-- PLANCHER DE VITESSE (SWING_SETTLE). Un lerp exponentiel n'atteint jamais sa cible : passe l'elan du
		-- depart, il traine des degres de travers pendant des SECONDES. Sur une machine qu'on regarde de dos en
		-- ligne droite, ca ne se lit pas comme du poids, ca se lit comme un DERAPAGE -- alors que la trajectoire
		-- est droite (0.6 degre mesure). On garde donc le lerp pour l'elan, et on impose une vitesse minimale pour
		-- que la fin se termine. Le clamp empeche de depasser la cible quand il ne reste presque rien.
		local floor = math.rad(MowConfigs.SWING_SETTLE) * dt
		if math.abs(step) < floor then
			step = math.clamp(target - state.swing, -floor, floor)
		end
		state.swing += step
		-- Cle a la cible : un lerp exponentiel ne l'atteint jamais, et la machine garderait un demi-degre de
		-- travers POUR TOUJOURS -- avec les bras decentres avec elle, puisqu'ils lisent la meme valeur.
		if math.abs(target - state.swing) < SWING_SNAP then
			state.swing = target
		end

		-- REGARD ARRIERE. On mesure le recul REEL (vitesse projetee sur le cap), pas l'intention : une bosse ou un
		-- autre joueur qui pousse ne doivent pas faire tourner la tete, et un recul reel doit la tourner meme si
		-- l'input vient d'ailleurs.
		local look = (rootPart :: BasePart).CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		-- Garde-fou : `.Unit` sur un vecteur nul rend du NaN, et un NaN pose dans une TimePosition empoisonne la
		-- piste pour de bon. Le cas est rare (le HRP est droit), mais il ne coute rien a ecarter.
		local backward = if flatLook.Magnitude > 1e-4 then -v:Dot(flatLook.Unit) else 0
		local wantBack = if backward > MowConfigs.REVERSE_EPSILON then 1 else 0
		state.reverseAmount += (wantBack - state.reverseAmount)
			* math.min(1, MowConfigs.REVERSE_TURN_SPEED * dt)
		local back = state.reverse
		if back and back.Length > HOLD_MIN_LENGTH then
			back.TimePosition = math.clamp(state.reverseAmount, 0, 1) * (back.Length - HOLD_EPSILON)
		end

		-- POSE EMBARQUE. Le personnage se penche en arriere quand on pousse, et se redresse quand on lache.
		--
		-- ON LIT L'INTENTION, pas la vitesse mesuree. La mesure arrive en retard -- le temps que la machine prenne
		-- sa vitesse -- et ce retard entre l'appui et le geste se ressent tout de suite. Le regard arriere, lui,
		-- garde la mesure : il repond a "ou va la machine", une question sur le MONDE. Celle-ci repond a "que
		-- demande le joueur", une question sur l'INTENTION -- ce ne sont pas les memes, et elles n'ont donc pas la
		-- meme source.
		--
		-- MEME SEUIL que le client (`STEER_MOVE_EPSILON`), qui s'en sert deja pour "le joueur demande d'avancer".
		-- Une seule question, une seule reponse.
		local pushing = state.driveInput > MowConfigs.STEER_MOVE_EPSILON

		local push = state.push
		if push and push.Length > HOLD_MIN_LENGTH then
			-- LECTURE LINEAIRE, dans un sens ou dans l'autre. On avance la position de `dt * vitesse`, donc
			-- l'animation se joue au rythme ou elle a ete faite -- ses temps sont respectes image pour image.
			--
			-- Un lissage (lerp) a la place donnerait un depart rapide et une fin lente : il traverserait les trois
			-- quarts du geste en quelques images. Une valeur interpolee ne peut PAS restituer un timing anime.
			--
			-- On s'arrete a Length - epsilon : sur la derniere image PILE, une piste bouclee est deja repartie a
			-- zero, et la pose claquerait au repos juste au moment ou elle est la plus marquee.
			-- UNE VITESSE PAR SENS. L'aller se joue au rythme de l'editeur, le retour plus vif : se laisser
			-- embarquer est progressif, se redresser est un reflexe.
			local step = if pushing
				then dt * MowConfigs.PUSH_PLAY_SPEED
				else -dt * MowConfigs.PUSH_RETURN_SPEED
			state.pushTime = math.clamp(state.pushTime + step, 0, push.Length - HOLD_EPSILON)
			push.TimePosition = state.pushTime
		end

		-- LE NEZ SE LEVE POUR TOURNER. On appuie sur le guidon, les roues avant decollent, et la machine pivote sur
		-- ses roues arriere. Sans ca elles frottent, et le virage glisse comme sur de la glace.
		--
		-- Sur l'INTENTION de braquage, pas sur la rotation obtenue : on souleve le nez POUR tourner, donc le geste
		-- vient avant le virage, pas apres.
		local liftWant = math.abs(state.steerInput) * math.rad(MowConfigs.TURN_LIFT)
		state.turnLift += (liftWant - state.turnLift) * math.min(1, MowConfigs.TURN_LIFT_SPEED * dt)
		-- Cle a la cible : un lerp exponentiel n'y arrive jamais, et la machine garderait une fraction de degre de
		-- nez en l'air pour toujours -- assez pour que les roues ne touchent plus tout a fait le sol.
		if math.abs(liftWant - state.turnLift) < SWING_SNAP then
			state.turnLift = liftWant
		end

		local weld = state.weld
		if weld then
			-- La rotation passe A GAUCHE de l'offset : la machine pivote AUTOUR DU JOUEUR (le guidon reste dans
			-- les mains, le carter part de cote). A droite, elle tournerait sur elle-meme -- un objet porte.
			-- CABRAGE, pivote autour de l'ARRIERE : les roues restent au sol et le nez se leve. Autour de la racine
			-- (a l'avant-bas du carter) c'est l'arriere qui se serait souleve.
			-- Apres baseC0 on est dans le repere ALIGNE : l'avant sur -Z, donc l'arriere sur +Z, le lateral sur X.
			-- LES DEUX CABRAGES SE SOMMENT : celui du demarrage a la corde et celui du virage. Meme pivot, meme
			-- calcul -- deux `pitch` separes se disputeraient la soudure, et le dernier ecrit gagnerait.
			local pitch = CFrame.identity
			local liftTotal = state.lift + state.turnLift
			if math.abs(liftTotal) > 1e-4 then
				local d = state.backDist
				pitch = CFrame.new(0, 0, d) * CFrame.Angles(liftTotal, 0, 0) * CFrame.new(0, 0, -d)
			end
			weld.C0 = CFrame.Angles(0, state.swing, 0) * state.baseC0 * pitch
		end

		-- LE LEVIER RACONTE LE REGIME. Ratio 0 au ralenti, 1 a plein regime, et on ecrit l'IMAGE correspondante.
		-- On s'arrete a Length - epsilon : sur la derniere image pile, une piste bouclee est deja repartie a zero.
		-- Le cabrage retombe tout seul. Cle a zero : un lerp exponentiel n'y arrive jamais, et la machine
		-- garderait une fraction de degre de nez en l'air pour toujours.
		-- RESSORT AMORTI : F = -k*x - c*v, integre en Euler. Suffisant pour un effet de moins d'une seconde.
		-- La machine se souleve, freine, revient, avec un leger depassement -- c'est lui qui fait "lourd".
		if state.lift ~= 0 or state.liftVel ~= 0 then
			local accel = -MowConfigs.PULL_LIFT_STIFFNESS * state.lift - MowConfigs.PULL_LIFT_DAMPING * state.liftVel
			state.liftVel += accel * dt
			state.lift += state.liftVel * dt
			-- On cle les DEUX : un ressort tend vers zero sans jamais l'atteindre, et une vitesse residuelle
			-- relancerait le calcul a vie pour un angle invisible.
			if math.abs(state.lift) < SWING_SNAP and math.abs(state.liftVel) < SWING_SNAP then
				state.lift = 0
				state.liftVel = 0
			end
		end

		-- LE SON MONTE AVEC LE REGIME, comme le levier : les deux racontent la meme chose, ils doivent donc
		-- venir du meme ratio. Deux calculs separes finiraient par se decaler.
		local span = MowConfigs.SPEED_MAX - MowConfigs.SPEED_MIN
		local ratio = if span > 1e-3 then math.clamp((state.speed - MowConfigs.SPEED_MIN) / span, 0, 1) else 0
		if state.run then
			local idle = MowConfigs.RUN_PITCH_IDLE
			state.run.PlaybackSpeed = idle + ratio * (MowConfigs.RUN_PITCH_FULL - idle)
		end

		local lever = state.lever
		if lever and lever.Length > 0 then
			lever.TimePosition = ratio * (lever.Length - HOLD_EPSILON)
		end
	end)
end

-- Toutes les tondeuses portees par ce joueur. Il n'en porte qu'une, mais boucler evite qu'un etat orphelin
-- survive a une deconnexion et bloque la tondeuse pour tout le monde.
local function releaseAllOf(player: Player)
	for model, state in pairs(carried) do
		if state.owner == player then
			release(model)
		end
	end
end

function MowService.init()
	-- PRECHARGEMENT. Le filet rattrape une piste pas encore chargee, mais mieux vaut qu'elle le soit deja :
	-- a la 1re prise d'une session, l'asset arrive parfois APRES le Play, et la pose part de travers.
	-- En task.spawn : c'est un appel RESEAU, il n'a rien a faire dans le chemin de boot.
	task.spawn(function()
		local assets: { Instance } = { getHoldAnimation() }
		for _, id in ipairs({ MowConfigs.MOTOR_ANIM_ID, MowConfigs.LEVER_ANIM_ID, MowConfigs.PUSH_ANIM_ID, MowConfigs.REVERSE_ANIM_ID, MowConfigs.START_ANIM_ID }) do
			local a = machineAnimation(id)
			if a then
				assets[#assets + 1] = a
			end
		end
		-- pcall : un asset absent ou une coupure reseau ne doit pas empecher la tondeuse de fonctionner.
		pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)
	end)

	local remote = RemoteSetup.getRemote("SetMowerCarry", "Mow") :: RemoteEvent

	remote.OnServerEvent:Connect(function(player: Player, inst: unknown, phase: unknown)
		if type(phase) ~= "string" then
			return
		end
		local model = isMower(inst :: Instance?)
		if not model then
			return
		end
		if phase == "grab" then
			grab(player, model)
		elseif phase == "place" then
			-- Seul le porteur repose sa tondeuse. Sinon n'importe qui la ferait tomber des mains d'un autre.
			local state = carried[model]
			if state and state.owner == player then
				release(model)
			end
		end
	end)

	-- TIRAGE DE CORDE. Aucun argument : le serveur sait deja ce que le joueur porte et dans quel etat. Il ignore
	-- le message si la machine est deja lancee -- un clic de plus ne relance pas le geste.
	local pullRemote = RemoteSetup.getRemote("PullMowStarter", "Mow") :: RemoteEvent
	pullRemote.OnServerEvent:Connect(function(player: Player)
		for _, state in pairs(carried) do
			if state.owner == player then
				pullStarter(state)
			end
		end
	end)

	-- BRAQUAGE. Le client DEMANDE, le serveur borne : un client qui enverrait 50 n'obtiendrait pas plus d'angle,
	-- parce que le resultat est de toute facon clampe par SWING_MAX plus bas.
	-- Le message porte AUSSI l'avance demandee : c'est la meme donnee -- la conduite -- envoyee au meme rythme.
	local steerRemote = RemoteSetup.getRemote("SetMowSteer", "Mow") :: RemoteEvent
	steerRemote.OnServerEvent:Connect(function(player: Player, value: unknown, drive: unknown)
		if type(value) ~= "number" or value ~= value then
			return -- pas un nombre, ou NaN : un NaN se propagerait dans l'angle et figerait la machine de travers
		end
		-- L'avance est FACULTATIVE : un client d'une version precedente n'en envoie pas, et il doit continuer a
		-- braquer normalement plutot que d'etre rejete.
		local wantDrive = if type(drive) == "number" and drive == drive then math.clamp(drive, -1, 1) else 0
		for _, state in pairs(carried) do
			if state.owner == player then
				state.steerInput = math.clamp(value, -1, 1)
				state.driveInput = wantDrive
			end
		end
	end)

	-- Mort / respawn / depart : on lache. Une soudure sur un HRP detruit laisserait la tondeuse introuvable.
	Players.PlayerRemoving:Connect(releaseAllOf)
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterRemoving:Connect(function()
			releaseAllOf(player)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterRemoving:Connect(function()
			releaseAllOf(player)
		end)
	end
end

return MowService
