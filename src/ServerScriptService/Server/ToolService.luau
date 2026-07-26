--!strict
-- Autorite sur l'outil tenu par un joueur.
--
-- Il fait TROIS choses, et rien d'autre :
--   1. cloner l'outil et l'accrocher a la main
--   2. jouer la pose de maintien
--   3. tout ranger proprement
--
-- Toute la sequence de demarrage du moteur a ete retiree : elle fonctionnait, mais elle empilait cinq etats
-- et cinq pistes d'animation sur une base pas encore sure. Elle reviendra par couches.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local ToolConfigs = require(ReplicatedStorage.Modules.Configs.ToolConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local ToolService = {}

-- Attribut pose sur le modele. C'est le contrat serveur -> client pour les FX : pas de remote dans ce sens.
-- Le modele se replique tout seul, l'attribut suit, le client voit arriver les deux ensemble. Un remote
-- envoye au spawn arriverait avant que les scripts du joueur ecoutent (cf CLAUDE.md).
local TOOL_ATTRIBUTE = "LeafiaTool"
local GRIP_NAME = "ToolGrip"

local DEFAULT_TOOL = "HedgeTrimmer"

local ASSET_TIMEOUT = 10
-- Court expres : l'Animator arrive quelques frames apres le personnage, pas quelques secondes.
local ANIMATOR_TIMEOUT = 5
-- Anti-spam du toggle. Sans ca, une touche maintenue enchaine clone et destruction chaque frame.
local TOGGLE_COOLDOWN = 0.35
-- Fondu entre deux poses de maintien. Assez court pour ne pas trainer, assez long pour que le joueur ne saute
-- pas d'une pose a l'autre en une frame.
local HOLD_FADE = 0.25

export type Held = {
	tool: Model,
	toolName: string,
	config: ToolConfigs.ToolConfig,
	motor: Motor6D,
	-- Prise au REPOS, sans inclinaison. Reference a laquelle l'inclinaison du moteur s'ajoute : sans elle, elle
	-- s'accumulerait sur elle-meme et l'outil tournerait sur lui-meme.
	baseC0: CFrame,
	-- Pose de maintien en cours sur le PERSONNAGE (idle outil eteint, ou pose moteur allume). Memorisee pour
	-- pouvoir la couper quand on la remplace : sans reference, elle continuerait de jouer sous la nouvelle.
	holdTrack: AnimationTrack?,
	-- Nom de la pose de maintien courante. Sert a la REJOUER a l'identique (ex : apres l'echelle, dont le garde-fou
	-- d'anim a pu la couper) sans avoir a redeviner l'etat moteur.
	holdAnimName: string?,
	-- Motor6D de la poignee du lanceur, et son etat de repos. On memorise Part0/Parent/C0/C1 a l'equipement :
	-- sans ces valeurs, rendre la poignee a l'outil demanderait de les recalculer, et la moindre erreur
	-- laisserait la corde tendue de travers pour toujours.
	launcherMotor: Motor6D?,
	launcherHome: { part0: BasePart?, parent: Instance?, c0: CFrame, c1: CFrame }?,
	-- La corde. Elle n'a de sens que tiree : au repos ses deux Attachment sont au meme endroit, ce qui donne
	-- un trait ecrase sur l'outil. On l'allume avec le lanceur et on l'eteint avec lui.
	launcherBeam: Beam?,
	-- Pistes jouees sur l'Animator de l'OUTIL. Chargees a l'equipement : le modele est un clone neuf a chaque
	-- fois, donc son Animator aussi, et il n'y a rien a mettre en cache entre deux equipements.
	toolTracks: { [string]: AnimationTrack },
	-- Sons clones DANS le Handle a l'equipement. Deux raisons : ils sont spatialises (les autres joueurs
	-- entendent le moteur d'ou tu es), et ils meurent avec l'outil, donc rien a nettoyer.
	-- Clones une fois et non a chaque tirage : pas d'allocation au milieu du geste.
	sounds: { [string]: Sound },
	-- Volume d'origine de chaque son. Un fondu ecrase le Volume ; sans cette copie on ne saurait plus a quelle
	-- valeur revenir, et chaque fondu laisserait le son un peu plus faible que le precedent.
	soundVolumes: { [string]: number },
	-- Fondu en cours par son, pour l'annuler si le meme son repart avant la fin. Sans ca, un fondu sortant
	-- continuerait de baisser le volume d'un son qu'on vient de relancer.
	soundTweens: { [string]: Tween },
}

-- Une piste par animation et par personnage, chargee UNE FOIS au spawn.
--
-- Deux raisons, et la deuxieme compte autant que la premiere :
--   1. PERF. LoadAnimation va chercher l'asset la premiere fois. Fait au moment de jouer, ca donne un temps
--      mort visible sur le premier geste. Fait au spawn, le joueur ne le sent pas.
--   2. FUITES. On ne peut pas accumuler des pistes si on n'en cree jamais plus d'une par animation. La version
--      precedente en creait une a chaque lecture et devait ensuite les pourchasser.
--
-- Le cache est indexe par PERSONNAGE, pas par joueur : a la mort, l'Animator meurt avec, et toutes les pistes
-- deviennent des references vers du vide. On compare donc le personnage avant de servir le cache.
type AnimCache = {
	character: Model,
	tracks: { [string]: AnimationTrack },
}

local held: { [Player]: Held } = {}
local lastToggle: { [Player]: number } = {}
local animCache: { [Player]: AnimCache } = {}
local unequipListeners: { (player: Player) -> () } = {}
local equipListeners: { (player: Player) -> () } = {}

-- Assets et Animations vivent dans Studio, pas dans Rojo : au premier boot d'une place vide ils peuvent
-- manquer. WaitForChild avec timeout, jamais infini, sinon le service gele sans rien dire.
local function findIn(rootName: string, path: { string }): Instance?
	local current = ReplicatedStorage:WaitForChild(rootName, ASSET_TIMEOUT)
	if not current then
		warn(`[ToolService] ReplicatedStorage.{rootName} introuvable`)
		return nil
	end
	for _, name in ipairs(path) do
		local nextChild = current:FindFirstChild(name)
		if not nextChild then
			return nil
		end
		current = nextChild
	end
	return current
end

-- L'Animator n'existe PAS encore a CharacterAdded : Roblox le cree un instant apres. Un FindFirstChildOfClass
-- a cet instant renvoie nil et l'animation ne part jamais.
local function getAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = humanoid:WaitForChild("Animator", ANIMATOR_TIMEOUT) :: Animator?
	end
	return animator
end

-- Charge toutes les animations d'outils sur l'Animator du personnage, une bonne fois. Appelee au spawn.
-- Le cout est paye pendant que le joueur regarde son perso apparaitre, pas au milieu de son premier geste.
local function warmUpAnimations(player: Player, character: Model)
	local animator = getAnimator(character)
	if not animator then
		warn(`[ToolService] Animator absent sur {player.Name}, pas de prechauffage`)
		return
	end

	local tracks: { [string]: AnimationTrack } = {}
	for _, config in pairs(ToolConfigs) do
		local folder = findIn("Animations", { "Player", "Tools", config.animationFolder })
		if folder then
			for _, anim in ipairs(folder:GetChildren()) do
				-- On precharge TOUT le dossier, pas seulement holdAnimation : les autres animations reviendront
				-- et il n'y a aucune raison de payer leur chargement plus tard.
				if anim:IsA("Animation") and not tracks[anim.Name] then
					local ok, track = pcall(function()
						return animator:LoadAnimation(anim)
					end)
					if ok and track then
						tracks[anim.Name] = track
					end
				end
			end
		end
	end

	animCache[player] = { character = character, tracks = tracks }
end

-- Sert une piste du cache. Repli sur un chargement immediat si le prechauffage n'a pas eu lieu (personnage
-- remplace entre-temps, dossier arrive apres le spawn) : mieux vaut un temps mort qu'une animation absente.
local function getTrack(player: Player, animationFolder: string, animName: string): AnimationTrack?
	local character = player.Character
	if not character then
		return nil
	end

	local cache = animCache[player]
	if cache and cache.character == character then
		local cached = cache.tracks[animName]
		if cached then
			return cached
		end
	end

	local animator = getAnimator(character)
	if not animator then
		warn(`[ToolService] Animator absent sur {player.Name}`)
		return nil
	end
	local anim = findIn("Animations", { "Player", "Tools", animationFolder, animName })
	if not (anim and anim:IsA("Animation")) then
		warn(`[ToolService] Animation introuvable : {animationFolder}/{animName}`)
		return nil
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not (ok and track) then
		return nil
	end

	-- On la range dans le cache pour ne pas repayer, et surtout pour ne pas en creer une deuxieme.
	if cache and cache.character == character then
		cache.tracks[animName] = track
	else
		animCache[player] = { character = character, tracks = { [animName] = track } }
	end
	return track
end

-- On ne tient AUCUNE liste de pistes EN COURS. On demande a l'Animator ce qui tourne reellement et on coupe
-- tout ce qui sort de ReplicatedStorage.Animations.
--
-- Stop SANS Destroy : les pistes appartiennent au cache et seront rejouees. Les detruire obligerait a les
-- recharger, donc a repayer le temps mort qu'on vient d'eliminer.
--
-- Une liste tenue a la main est une hypothese ; GetPlayingAnimationTracks est un fait. La version precedente
-- comptait ses pistes sur cinq champs repartis dans deux modules, et en oubliait quand meme.
--
-- Les animations par defaut de Roblox (marche, saut, idle) vivent dans le script Animate du personnage, pas
-- dans ReplicatedStorage : ce test ne les touche jamais.
local function stopToolAnimations(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local animationsRoot = ReplicatedStorage:FindFirstChild("Animations")
	if not animationsRoot then
		return
	end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local anim = track.Animation
		if anim and anim:IsDescendantOf(animationsRoot) then
			track:Stop(0)
		end
	end
end

-- Un outil accroche a la main ne doit ni peser ni bloquer. Sans ca le personnage marche comme s'il portait un
-- rocher, et les lames font trebucher le joueur sur ses propres pieds.
local function prepareToolParts(tool: Model)
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
end

-- Remplace la pose de maintien du personnage. `animName` a nil retire la pose sans en mettre d'autre.
-- L'ancienne sort en FONDU et n'est detruite qu'apres : un Destroy immediat couperait le fondu et le joueur
-- sauterait d'une pose a l'autre en une frame. C'est ce fondu qui rend le passage "outil eteint -> moteur
-- allume" fluide au lieu d'un a-coup.
function ToolService.setHoldAnimation(player: Player, animName: string?)
	local current = held[player]
	if not current then
		return
	end

	local previous = current.holdTrack
	current.holdTrack = nil
	current.holdAnimName = animName
	if previous then
		previous:Stop(HOLD_FADE)
		task.delay(HOLD_FADE + 0.05, function()
			previous:Destroy()
		end)
	end

	if not animName then
		return
	end
	-- Jouee cote SERVEUR : elle se replique alors a tout le monde depuis une source unique.
	local track = getTrack(player, current.config.animationFolder, animName)
	if track then
		track.Looped = true
		track.Priority = current.config.holdPriority
		track:Play(HOLD_FADE)
		current.holdTrack = track
	end
end

-- Rejoue la pose de maintien COURANTE a l'identique. Sert apres l'echelle : son garde-fou d'anim a pu couper la
-- pose de l'outil, et l'outil ne la relance pas tout seul. On la refait donc jouer, comme un re-equipement, sans
-- changer d'etat (moteur, prise). Sans outil en main : rien a faire.
function ToolService.replayHold(player: Player)
	local current = held[player]
	if current then
		ToolService.setHoldAnimation(player, current.holdAnimName)
	end
end

--
-- Un Motor6D place la piece ainsi : Handle.CFrame = Hand.CFrame * C0 * C1:Inverse()
-- Avec C1 = l'Attachment de prise, celle-ci vient se coller sur le point de prise de la main, axes alignes.
-- Autrement dit l'orientation de l'outil dans la main EST celle de l'Attachment ; l'offset la rattrape.
local function applyGrip(current: Held, hand: BasePart, attachmentName: string, offset: CFrame)
	local handle = current.motor.Part1
	if not handle then
		return
	end
	-- Les deux mains R15 ont leur propre Attachment de prise, nommee d'apres le cote.
	local handAttachment = hand:FindFirstChild(
		hand.Name == current.config.offHandPart and "LeftGripAttachment" or "RightGripAttachment"
	)
	-- Repli sur la prise principale si l'Attachment demandee n'existe pas. Sans ce repli, C1 vaudrait identity
	-- et l'outil se collerait a l'origine du Handle : le joueur le tiendrait par le vide, et on chercherait
	-- l'erreur du cote de l'orientation alors que c'est un nom qui manque.
	local toolAttachment = handle:FindFirstChild(attachmentName)
	if not toolAttachment then
		warn(`[ToolService] Attachment "{attachmentName}" absente du Handle, repli sur "{current.config.gripAttachment}"`)
		toolAttachment = handle:FindFirstChild(current.config.gripAttachment)
	end

	local c0 = if handAttachment and handAttachment:IsA("Attachment") then handAttachment.CFrame else CFrame.identity
	local c1 = if toolAttachment and toolAttachment:IsA("Attachment") then toolAttachment.CFrame else CFrame.identity

	-- On repointe Part0 du Motor6D EXISTANT au lieu de le detruire et le recreer : recreer casserait toute
	-- animation en cours sur cette chaine.
	current.motor.Part0 = hand
	-- On MEMORISE la prise de repos avant toute inclinaison. Sans elle, l'inclinaison du moteur s'accumulerait
	-- sur elle-meme frame apres frame et l'outil finirait par tourner sur lui-meme.
	current.baseC0 = c0 * offset
	current.motor.C0 = current.baseC0
	current.motor.C1 = c1
	current.motor.Parent = hand
end

function ToolService.unequip(player: Player)
	local current = held[player]
	held[player] = nil
	if not current then
		return
	end

	-- Les auditeurs d'abord : ils remettent leur etat a zero pendant que l'outil existe encore.
	for _, listener in ipairs(unequipListeners) do
		listener(player)
	end

	-- Puis les animations : une piste qui tourne sur un personnage dont l'outil vient de disparaitre laisse le
	-- joueur fige les mains vides.
	stopToolAnimations(player)

	-- Le Motor6D vit sur la MAIN du joueur, pas dans l'outil : detruire l'outil ne le supprime pas. Sans cette
	-- ligne il en resterait un de plus a chaque equipement, tous inertes, tous invisibles.
	if current.motor.Parent then
		current.motor:Destroy()
	end
	if current.tool.Parent then
		current.tool:Destroy()
	end
end

function ToolService.equip(player: Player, toolName: string): boolean
	-- Validation serveur systematique : cette fonction est atteignable depuis un remote.
	local config = ToolConfigs[toolName]
	if not config then
		warn(`[ToolService] Outil inconnu : {toolName}`)
		return false
	end

	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local hand = character:FindFirstChild(config.handPart)
	if not (hand and hand:IsA("BasePart")) then
		warn(`[ToolService] {config.handPart} introuvable sur {player.Name} (R15 requis)`)
		return false
	end

	local source = findIn("Assets", { "Tools", config.assetName })
	if not (source and source:IsA("Model")) then
		warn(`[ToolService] Modele d'outil introuvable : {config.assetName}`)
		return false
	end

	ToolService.unequip(player)

	local tool = source:Clone()
	local handle = tool:FindFirstChild(config.handleName)
	if not (handle and handle:IsA("BasePart")) then
		warn(`[ToolService] {config.handleName} introuvable dans {config.assetName}`)
		tool:Destroy()
		return false
	end

	prepareToolParts(tool)
	tool.PrimaryPart = handle

	local motor = Instance.new("Motor6D")
	motor.Name = GRIP_NAME
	motor.Part1 = handle

	-- L'attribut est pose AVANT le parentage : quand le client voit le modele arriver, l'attribut est deja
	-- lisible. Dans l'autre sens il verrait un modele nu et raterait l'effet.
	tool:SetAttribute(TOOL_ATTRIBUTE, toolName)
	tool.Parent = character

	-- Le Motor6D de la poignee porte le MEME nom que la part qu'il pilote, et il vit dans le Handle.
	local launcherMotor: Motor6D? = nil
	local launcherHome = nil
	local launcherBeam: Beam? = nil
	if config.launcherPartName then
		local found = handle:FindFirstChild(config.launcherPartName)
		if found and found:IsA("Motor6D") then
			launcherMotor = found
			launcherHome = { part0 = found.Part0, parent = found.Parent, c0 = found.C0, c1 = found.C1 }
		else
			warn(`[ToolService] Motor6D "{config.launcherPartName}" introuvable dans {config.handleName}`)
		end

		-- Recherche recursive : le Beam vit dans une Attachment du Handle, pas directement sous lui.
		launcherBeam = handle:FindFirstChildWhichIsA("Beam", true)
		if launcherBeam then
			-- Eteinte au depart : l'outil vient d'apparaitre, personne ne tire encore.
			launcherBeam.Enabled = false
		end
	end

	local current: Held = {
		tool = tool,
		toolName = toolName,
		config = config,
		motor = motor,
		-- Ecrasee par applyGrip juste apres, qui calcule la vraie prise.
		baseC0 = CFrame.identity,
		launcherMotor = launcherMotor,
		launcherHome = launcherHome,
		launcherBeam = launcherBeam,
		toolTracks = {},
		sounds = {},
		soundVolumes = {},
		soundTweens = {},
	}

	-- Sons : on clone les originaux dans le Handle. L'original reste intact dans SoundService, et chaque
	-- joueur a les siens, donc deux joueurs qui tirent en meme temps ne se coupent pas le son.
	do
		local folder: Instance? = SoundService
		for _, name in ipairs(config.soundFolder) do
			folder = folder and folder:FindFirstChild(name)
		end
		if folder then
			for _, sound in ipairs(folder:GetChildren()) do
				if sound:IsA("Sound") then
					local clone = sound:Clone()
					clone.Parent = handle
					current.sounds[sound.Name] = clone
					-- Memorise AVANT tout fondu : c'est la valeur de reference a laquelle on revient.
					current.soundVolumes[sound.Name] = clone.Volume
				end
			end
		else
			warn(`[ToolService] Dossier de sons introuvable : SoundService.{table.concat(config.soundFolder, ".")}`)
		end
	end

	-- Pistes de l'outil, chargees tout de suite : c'est le meme raisonnement que le prechauffage du
	-- personnage, le cout est paye a l'equipement plutot qu'au milieu du premier geste.
	local toolAnimator = getAnimator(tool)
	if toolAnimator then
		for _, name in ipairs(config.toolRunAnimations) do
			local anim = findIn("Animations", { "Player", "Tools", config.animationFolder, name })
			if anim and anim:IsA("Animation") then
				local ok, track = pcall(function()
					return toolAnimator:LoadAnimation(anim)
				end)
				if ok and track then
					current.toolTracks[name] = track
				end
			else
				warn(`[ToolService] Animation d'outil introuvable : {config.animationFolder}/{name}`)
			end
		end
	elseif #config.toolRunAnimations > 0 then
		warn(`[ToolService] {config.assetName} n'a pas d'Animator, ses animations ne joueront pas`)
	end
	held[player] = current
	-- Meme chemin que setHand : un seul endroit calcule une prise, donc un seul endroit a corriger.
	applyGrip(current, hand, config.gripAttachment, config.gripOffset)

	ToolService.setHoldAnimation(player, config.holdAnimation)

	-- En dernier : tout est en place, les auditeurs peuvent jouer par-dessus sans risque.
	for _, listener in ipairs(equipListeners) do
		listener(player)
	end

	return true
end

function ToolService.getHeld(player: Player): Held?
	return held[player]
end

-- Change la main qui tient l'outil. L'offset suit la main : la LeftGripAttachment de Roblox est le miroir de
-- la droite, donc la meme correction y donnerait un outil de travers.
function ToolService.setHand(player: Player, handPartName: string): boolean
	local current = held[player]
	local character = player.Character
	if not (current and character) then
		return false
	end
	local hand = character:FindFirstChild(handPartName)
	if not (hand and hand:IsA("BasePart")) then
		return false
	end

	local config = current.config
	local isOffHand = handPartName == config.offHandPart
	applyGrip(
		current,
		hand,
		if isOffHand then config.offHandAttachment else config.gripAttachment,
		if isOffHand then config.offHandGripOffset else config.gripOffset
	)
	return true
end

-- Change l'ANGLE de l'outil dans la main courante, sans changer de main.
--
-- Sert a passer de la prise de demarrage a la prise de coupe. Tirer une corde et tailler une haie ne sont pas
-- le meme geste : il n'y a aucune raison que l'outil soit tenu pareil, alors que c'est bien la meme main.
-- Aucune animation ne peut faire ce travail : l'angle de l'outil DANS la main vient du Motor6D, pas des bras.
function ToolService.setGripOffset(player: Player, offset: CFrame): boolean
	local current = held[player]
	if not current then
		return false
	end
	-- La main courante est celle que porte le Motor6D, pas une valeur qu'on garderait de son cote : l'etat reel
	-- du joint bat toujours l'etat qu'on croit avoir.
	local hand = current.motor.Part0
	if not (hand and hand:IsA("BasePart")) then
		return false
	end

	local config = current.config
	local isOffHand = hand.Name == config.offHandPart
	applyGrip(current, hand, if isOffHand then config.offHandAttachment else config.gripAttachment, offset)
	return true
end

-- Rend une piste PRETE mais NON jouee. Elle sort du cache, donc c'est toujours le meme objet pour une
-- animation donnee : l'appelant peut la configurer et la jouer sans jamais en creer une deuxieme.
function ToolService.getTrack(player: Player, animName: string): AnimationTrack?
	local current = held[player]
	if not current then
		return nil
	end
	return getTrack(player, current.config.animationFolder, animName)
end

--
-- Detache la poignee du lanceur pour la coller a une main, ou la rend a l'outil (handPartName a nil).
-- On ne dessine pas la corde : le Beam tendu entre ses deux Attachment s'etire tout seul quand ses bouts
-- s'ecartent.
function ToolService.setLauncherHand(player: Player, handPartName: string?): boolean
	local current = held[player]
	if not current then
		return false
	end
	local motor = current.launcherMotor
	local home = current.launcherHome
	if not (motor and home) then
		return false
	end

	-- La corde suit la poignee : visible tant qu'elle est tiree, eteinte des qu'elle revient sur l'outil.
	if current.launcherBeam then
		current.launcherBeam.Enabled = handPartName ~= nil
	end

	if not handPartName then
		motor.Part0 = home.part0
		motor.C0 = home.c0
		motor.C1 = home.c1
		motor.Parent = home.parent
		return true
	end

	local character = player.Character
	if not character then
		return false
	end
	local hand = character:FindFirstChild(handPartName)
	local launcher = motor.Part1
	if not (hand and hand:IsA("BasePart") and launcher) then
		return false
	end

	local handAttachment = hand:FindFirstChild(
		handPartName == current.config.offHandPart and "LeftGripAttachment" or "RightGripAttachment"
	)
	local gripAttachment = launcher:FindFirstChild(current.config.launcherAttachment)

	local c0 = if handAttachment and handAttachment:IsA("Attachment") then handAttachment.CFrame else CFrame.identity
	local c1 = if gripAttachment and gripAttachment:IsA("Attachment") then gripAttachment.CFrame else CFrame.identity

	motor.Part0 = hand
	motor.C0 = c0 * current.config.launcherGripOffset
	motor.C1 = c1
	-- Reparente sur Part1, qui vit DANS l'outil : le joint meurt donc avec l'outil. Laisse sur le Handle, il
	-- ne serait enfant ni de Part0 ni de Part1, ce que Roblox ne garantit pas de faire fonctionner.
	motor.Parent = launcher
	return true
end

-- Lance ou coupe les animations de l'OUTIL (lames, bloc moteur). Elles vivent sur son propre Animator, donc
-- elles disparaissent avec lui : rien a nettoyer au rangement.
--
-- `fadeOut` sur l'arret : les lames RALENTISSENT au lieu de se figer d'un coup, ce qui se lit comme un moteur
-- qui retombe et non comme une animation coupee.
function ToolService.setToolAnimationsPlaying(player: Player, playing: boolean, fadeOut: number?)
	local current = held[player]
	if not current then
		return
	end
	for _, track in pairs(current.toolTracks) do
		if playing then
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Idle
			if not track.IsPlaying then
				track:Play()
			end
			track:AdjustSpeed(1)
		else
			track:Stop(fadeOut or 0)
		end
	end
end

-- Annule le fondu en cours sur un son. Sans ca, un fondu sortant continuerait de baisser le volume d'un son
-- qu'on vient de relancer, et on l'entendrait disparaitre juste apres l'avoir declenche.
local function cancelSoundTween(current: Held, soundName: string)
	local tween = current.soundTweens[soundName]
	if tween then
		tween:Cancel()
		current.soundTweens[soundName] = nil
	end
end

-- Incline l'outil dans la main, proportionnellement au regime moteur. Un moteur qui monte en regime pousse
-- l'outil : sans cette reaction il monterait en puissance sans qu'on le SENTE dans les mains.
--
-- On repart TOUJOURS de la prise de repos memorisee. Multiplier la C0 courante ferait s'accumuler l'inclinaison
-- frame apres frame, et l'outil finirait par tourner sur lui-meme.
-- `extraDegrees` s'ajoute a l'inclinaison sur le MEME axe, sans etre borne : c'est par la qu'arrive le
-- tremblement de plein regime, qui doit pouvoir passer de part et d'autre de la position inclinee.
function ToolService.setGripTilt(player: Player, amount: number, extraDegrees: number?)
	local current = held[player]
	if not current then
		return
	end
	local config = current.config
	local angle = math.rad(config.tiltMaxAngle) * math.clamp(amount, 0, 1) + math.rad(extraDegrees or 0)
	current.motor.C0 = current.baseC0 * CFrame.fromAxisAngle(config.tiltAxis, angle)
end

-- Regle la vitesse de lecture des animations de l'outil (lames, bloc moteur). Sert a l'accelerateur : le
-- meme geste anime, joue plus ou moins vite selon que le joueur pousse ou non.
function ToolService.setToolAnimationSpeed(player: Player, speed: number)
	local current = held[player]
	if not current then
		return
	end
	for _, track in pairs(current.toolTracks) do
		if track.IsPlaying then
			track:AdjustSpeed(speed)
		end
	end
end

-- Joue un son de l'outil. `Play` sur un son deja en cours le relance depuis le debut, ce qui est le
-- comportement voulu : deux tirages rapproches ne doivent pas se superposer.
function ToolService.playSound(player: Player, soundName: string?, looped: boolean?)
	if not soundName then
		return
	end
	local current = held[player]
	if not current then
		return
	end
	local sound = current.sounds[soundName]
	if not sound then
		warn(`[ToolService] Son introuvable : {soundName}`)
		return
	end
	-- Un fondu en cours sur ce son doit mourir ici : sinon il continuerait a en baisser le volume juste apres
	-- qu'on l'ait relance. On restaure aussi volume et hauteur, qu'un fondu precedent a pu laisser en bas.
	cancelSoundTween(current, soundName)
	sound.Volume = current.soundVolumes[soundName] or sound.Volume
	sound.PlaybackSpeed = 1

	sound.Looped = looped == true
	-- Un son en boucle deja en cours ne se relance pas : ca produirait un hoquet au milieu du ronronnement.
	if sound.Looped and sound.IsPlaying then
		return
	end
	sound:Play()
end

-- Fait MONTER un son depuis le silence. Le son demarre a zero puis rejoint son volume d'origine.
function ToolService.fadeInSound(player: Player, soundName: string?, duration: number, looped: boolean?)
	if not soundName then
		return
	end
	local current = held[player]
	if not current then
		return
	end
	local sound = current.sounds[soundName]
	if not sound then
		return
	end

	cancelSoundTween(current, soundName)
	local target = current.soundVolumes[soundName] or sound.Volume
	sound.Looped = looped == true
	-- PlaybackSpeed remise a 1 : un fondu sortant precedent a pu la laisser en bas.
	sound.PlaybackSpeed = 1
	if not sound.IsPlaying then
		sound.Volume = 0
		sound:Play()
	end

	local tween = TweenService:Create(sound, TweenInfo.new(duration), { Volume = target })
	current.soundTweens[soundName] = tween
	tween:Play()
end

-- Fait DESCENDRE un son puis l'arrete. `pitchDown` fait aussi tomber la hauteur pendant la descente : c'est ce
-- qui fait entendre un moteur qui retombe plutot qu'un son qu'on baisse.
function ToolService.fadeOutSound(player: Player, soundName: string?, duration: number, pitchDown: number?)
	if not soundName then
		return
	end
	local current = held[player]
	if not current then
		return
	end
	local sound = current.sounds[soundName]
	if not (sound and sound.IsPlaying) then
		return
	end

	cancelSoundTween(current, soundName)
	local goal: { [string]: number } = { Volume = 0 }
	if pitchDown then
		goal.PlaybackSpeed = pitchDown
	end

	-- LINEAIRE quand on fait aussi descendre la hauteur, la courbe par defaut sinon.
	--
	-- TweenInfo.new sans style utilise Quad Out : le volume s'ecroule tout de suite puis traine. A mi-parcours
	-- il ne reste qu'un quart du volume, donc la descente de hauteur se produit quand on n'entend presque plus
	-- rien : le moteur avait l'air de se couper, pas de ralentir.
	-- En lineaire, volume et hauteur descendent du meme pas et on ENTEND la deceleration jusqu'au bout.
	local style = if pitchDown then Enum.EasingStyle.Linear else Enum.EasingStyle.Quad
	local tween = TweenService:Create(sound, TweenInfo.new(duration, style), goal)
	current.soundTweens[soundName] = tween
	tween.Completed:Connect(function(state: Enum.PlaybackState)
		-- Cancelled = le son est reparti pendant la descente. On ne touche a rien, celui qui l'a relance a
		-- deja remis le volume et la hauteur qu'il voulait.
		if state ~= Enum.PlaybackState.Completed then
			return
		end
		sound:Stop()
		-- Remise a l'etat d'origine APRES l'arret : le son est pret a etre rejoue tel quel.
		sound.Volume = current.soundVolumes[soundName] or sound.Volume
		sound.PlaybackSpeed = 1
		current.soundTweens[soundName] = nil
	end)
	tween:Play()
end

-- Rend l'instance Sound clonee dans le Handle. Sert a s'abonner a `Ended` : un son d'attaque qui se termine
-- doit pouvoir enchainer sur son maintien.
function ToolService.getSound(player: Player, soundName: string?): Sound?
	if not soundName then
		return nil
	end
	local current = held[player]
	if not current then
		return nil
	end
	return current.sounds[soundName]
end

-- Coupe un son de l'outil. Utile pour les boucles ; les sons courts s'arretent tout seuls, et de toute facon
-- ils meurent avec l'outil.
function ToolService.stopSound(player: Player, soundName: string?)
	if not soundName then
		return
	end
	local current = held[player]
	if not current then
		return
	end
	local sound = current.sounds[soundName]
	if sound then
		-- Un arret net doit aussi tuer le fondu en cours, sinon celui-ci finirait par restaurer le volume d'un
		-- son qu'on vient d'arreter.
		cancelSoundTween(current, soundName)
		sound:Stop()
		sound.Volume = current.soundVolumes[soundName] or sound.Volume
		sound.PlaybackSpeed = 1
	end
end

-- Auditeurs du rangement. Les services qui tiennent un etat lie a l'outil (sequence de demarrage, par
-- exemple) s'y branchent pour se remettre a zero.
function ToolService.onUnequip(callback: (player: Player) -> ())
	table.insert(unequipListeners, callback)
end

-- Auditeurs de la sortie d'outil. Emis APRES que tout soit en place : modele parente, prise appliquee, pose
-- de maintien lancee. Un auditeur peut donc jouer une animation par-dessus sans risque.
function ToolService.onEquip(callback: (player: Player) -> ())
	table.insert(equipListeners, callback)
end

function ToolService.toggle(player: Player)
	local now = os.clock()
	if now - (lastToggle[player] or 0) < TOGGLE_COOLDOWN then
		return
	end
	lastToggle[player] = now

	if held[player] then
		ToolService.unequip(player)
	else
		ToolService.equip(player, DEFAULT_TOOL)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	-- La mort detruit le personnage donc l'outil, mais la table garderait une entree pointant sur un modele
	-- mort : le toggle suivant croirait ranger un outil deja disparu, et il faudrait appuyer deux fois.
	held[player] = nil
	lastToggle[player] = nil
	-- Le cache pointe sur l'ancien Animator, mort avec l'ancien personnage.
	animCache[player] = nil

	-- En arriere-plan : le prechauffage attend l'Animator et charge plusieurs assets, il n'a aucune raison de
	-- retarder le reste de l'apparition.
	task.spawn(warmUpAnimations, player, character)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

function ToolService.init()
	local toggleRemote = RemoteSetup.getRemote("ToggleTool", "Tool")
	if toggleRemote and toggleRemote:IsA("RemoteEvent") then
		toggleRemote.OnServerEvent:Connect(function(player: Player)
			ToolService.toggle(player)
		end)
	else
		warn("[ToolService] Remote Tool/ToggleTool introuvable")
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		held[player] = nil
		lastToggle[player] = nil
		animCache[player] = nil
	end)
end

return ToolService
