--!strict
-- Sequence de demarrage du moteur. Volontairement MINIMALE : une couche a la fois.
--
--   Idle --(EQUIPEMENT)--> Preparing --(fin de l'anim)--> Ready --(clic)--> Pulling
--                                                           ^                  |
--                                          tirage rate      +------------------+
--                                                                              |
--                                                            Nieme tirage --> Running
--
--   Running : moteur en marche. Clic MAINTENU accelere les lames (SetThrottle), relachement les ralentit.
--
--   Preparing : PrepareToLaunchAnimation joue en entier
--   Ready     : TryLaunchAnimation FIGEE a sa premiere frame, la posture "pret a tirer"
--   Pulling   : la MEME piste, relancee a vitesse normale
--
-- Ready et Pulling partagent la meme piste : on ne fait que changer sa vitesse. Le joueur passe donc de la
-- posture au geste sans transition a fondre, il repart exactement d'ou il etait.
--
-- Le compteur de tirages, l'a-coup du moteur et le retour main droite viendront APRES validation de cette
-- couche. La version precedente avait empile six couches d'un coup et il a fallu tout jeter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local ToolConfigs = require(ReplicatedStorage.Modules.Configs.ToolConfigs)
-- Uniquement pour le NOM de l'attribut. On lit l'attribut pose sur le personnage plutot que d'appeler
-- HedgeService : une config partagee ne cree pas de dependance entre deux services.
local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)
local ToolService = require(script.Parent.ToolService)

local ToolStartService = {}

-- Action2 passe au-dessus de la pose de maintien, qui est en Action.
local SEQUENCE_PRIORITY = Enum.AnimationPriority.Action2
-- Marqueur pose dans PrepareToLaunchAnimation, a la frame ou les deux mains se rejoignent. Le passage y est
-- invisible : il n'y a aucune distance a parcourir. Un delai fixe se decalerait des qu'on retouche l'anim.
local MARKER_OTHER_HAND = "PassageOtherHandEvent"
-- Instant ou la corde arrive en butee : c'est LA que le moteur repond ou pas. Le reste de l'animation n'est
-- que le retour du bras.
local MARKER_PULL = "TryLaunchEvent"

-- Attribut pose sur le modele de l'outil a chaque butee de corde. Le client s'y branche pour ses FX.
-- Meme principe que LeafiaTool : pas de remote dans le sens serveur -> client, l'attribut se replique seul.
local PULL_TICK_ATTRIBUTE = "LeafiaPullTick"

-- Accelerateur en cours, pose sur le PERSONNAGE et non sur l'outil.
--
-- Deux controllers clients differents en ont besoin (camera de travail et champ de vision), et le personnage
-- est le seul objet que les deux tiennent deja. Le poser sur l'outil obligerait chacun a aller le chercher.
local THROTTLE_ATTRIBUTE = "LeafiaThrottle"

-- Moteur en marche, pose sur le PERSONNAGE. Different de LeafiaThrottle : celui-ci dit "le moteur tourne",
-- l'autre dit "le joueur appuie". On peut avoir le moteur en marche sans accelerer, et c'est justement l'etat
-- ou le joueur vise sa hauteur de coupe.
local ENGINE_ATTRIBUTE = "LeafiaEngine"

-- On ne previent qu'UNE FOIS par animation. Un message a chaque tirage noierait la console, ce qui revient a
-- ne rien dire.
local warnedMissingMarker: { [string]: boolean } = {}
local ACTIVATE_COOLDOWN = 0.2

type State = "Idle" | "Preparing" | "Ready" | "Pulling" | "Running"

local states: { [Player]: State } = {}
local lastActivate: { [Player]: number } = {}
local pullCounts: { [Player]: number } = {}
-- Nombre de tirages a atteindre pour CE demarrage, tire au hasard au premier tirage. Retenu pour toute la
-- tentative : le retirer a chaque coup ferait un moteur qui redecide sans cesse, et le joueur ne saurait jamais
-- s'il approche du but. Une seule surprise par demarrage, pas une par tirage.
local pullTargets: { [Player]: number } = {}
-- Accelerateur des lames. `throttle` = le joueur maintient-il le clic. `bladeSpeed` = vitesse actuelle des
-- lames, qui suit `throttle` progressivement (voir la boucle Heartbeat). Deux tables plutot qu'une valeur
-- cible atteinte d'un coup : c'est la MONTEE progressive qui fait l'effet, pas la vitesse finale.
local throttle: { [Player]: boolean } = {}
local bladeSpeed: { [Player]: number } = {}
-- Inclinaison courante de l'outil, de 0 a 1. Suivie a part de `bladeSpeed` : le poignet encaisse tout de
-- suite, la masse des lames prend son elan. Deux grandeurs differentes, deux rythmes.
local tiltAmount: { [Player]: number } = {}
-- Ouverture du tremblement, de 0 a 1. Une valeur continue et non un booleen : couper net un sinus a 13 Hz
-- laisserait l'outil fige sur un angle quelconque, et le saut se verrait.
local vibeGate: { [Player]: number } = {}

-- Son du moteur, en trois temps : ralenti -> attaque -> maintien. L'attaque et le maintien sont deux fichiers
-- distincts qui s'enchainent bout a bout ; c'est cette suite qui dessine la courbe d'acceleration.
type EngineSound = "Idle" | "Accel" | "Sustain"
local engineSound: { [Player]: EngineSound } = {}
-- Connexion a la fin de l'attaque. Gardee pour la couper : un Connect qui survit a son geste se rebrancherait
-- au geste suivant et l'enchainement partirait en double.
local accelEndedConn: { [Player]: RBXScriptConnection } = {}

-- SEULE porte d'entree pour changer d'etat. Elle tient la table ET l'attribut du meme geste.
--
-- Six endroits ecrivaient l'etat. Poser l'attribut a cote de chacun, c'etait la garantie d'en oublier un, et
-- de chercher ensuite pourquoi le client croit le moteur eteint alors qu'il tourne.
local function setState(player: Player, state: State?)
	states[player] = state
	local character = player.Character
	if character then
		character:SetAttribute(ENGINE_ATTRIBUTE, state == "Running")
	end
end

local function clearAccelConnection(player: Player)
	local conn = accelEndedConn[player]
	if conn then
		conn:Disconnect()
		accelEndedConn[player] = nil
	end
end

local function reset(player: Player)
	setState(player, nil)
	lastActivate[player] = nil
	throttle[player] = nil
	bladeSpeed[player] = nil
	tiltAmount[player] = nil
	vibeGate[player] = nil
	clearAccelConnection(player)
	engineSound[player] = nil
	-- Sans ca, ranger l'outil en pleine acceleration laisserait la camera zoomee pour toujours.
	local character = player.Character
	if character then
		character:SetAttribute(THROTTLE_ATTRIBUTE, false)
	end
	-- Ranger l'outil remet le compteur a zero : il faudra relancer le moteur. C'est voulu, le rituel fait
	-- partie du jeu.
	pullCounts[player] = nil
	-- Et la cible avec lui : le prochain demarrage doit retirer un nouveau nombre de coups, sinon le meme se
	-- rejouerait toute la session.
	pullTargets[player] = nil
end

-- ===== Son du moteur : ralenti / attaque / maintien =====
--
-- Le pitch dynamique a ete abandonne : deux sons dedies portent deja la courbe d'acceleration, et tirer sur
-- PlaybackSpeed par-dessus doublerait l'effet. Le son design fait le travail, le code ne fait qu'enchainer.

-- RELACHEMENT. Le moteur redescend, il ne se coupe pas net : l'acceleration s'efface en fondu avec sa hauteur
-- qui tombe, pendant que le ralenti remonte. Les deux se croisent, donc il n'y a aucun trou.
--
-- La connexion a Ended est coupee AVANT le fondu : l'attaque qui s'eteint doit ecrire sa fin dans le vide, pas
-- declencher le maintien qu'on est justement en train d'annuler.
local function engineIdle(player: Player, config: ToolConfigs.ToolConfig)
	clearAccelConnection(player)
	ToolService.fadeOutSound(player, config.accelStartSound, config.engineReleaseFade, config.engineWindDownPitch)
	ToolService.fadeOutSound(player, config.accelLoopSound, config.engineReleaseFade, config.engineWindDownPitch)
	ToolService.fadeInSound(player, config.runSound, config.engineReleaseFade, true)
	engineSound[player] = "Idle"
end

local function engineAccelerate(player: Player, config: ToolConfigs.ToolConfig)
	clearAccelConnection(player)
	-- Le ralenti s'efface, vite : l'attaque le remplace, elle ne se superpose pas. Deux regimes moteur en meme
	-- temps donnent une bouillie, pas une acceleration.
	ToolService.fadeOutSound(player, config.runSound, config.engineAccelFade)
	ToolService.stopSound(player, config.accelLoopSound)
	-- L'attaque, elle, part a PLEIN VOLUME tout de suite. La faire monter en fondu lui enleverait son mordant,
	-- et c'est ce mordant qui fait la sensation de coup d'accelerateur.
	ToolService.playSound(player, config.accelStartSound, false)
	engineSound[player] = "Accel"

	local sound = ToolService.getSound(player, config.accelStartSound)
	if not sound then
		return
	end

	-- ENCHAINEMENT : des que l'attaque atteint sa fin, le maintien prend le relais sans trou. On ecoute la fin
	-- reelle du son plutot que de compter une duree a la main : une duree codee en dur se decale des que le
	-- fichier change.
	accelEndedConn[player] = sound.Ended:Connect(function()
		clearAccelConnection(player)
		-- Le joueur a pu relacher, ranger l'outil ou mourir pendant l'attaque.
		if engineSound[player] ~= "Accel" or not throttle[player] or states[player] ~= "Running" then
			return
		end
		ToolService.playSound(player, config.accelLoopSound, true)
		engineSound[player] = "Sustain"
	end)
end

-- Fait suivre le son a l'intention du joueur. Appelee a chaque changement de throttle et a l'entree en
-- Running, jamais dans la boucle : le son change par PALIERS, contrairement a la vitesse des lames.
local function updateEngineSound(player: Player)
	local currentHeld = ToolService.getHeld(player)
	if not currentHeld or states[player] ~= "Running" then
		return
	end
	local config = currentHeld.config

	if throttle[player] then
		-- Deja en train d'accelerer ou de tenir le regime : on ne relance pas l'attaque, sinon un joueur qui
		-- garde le clic entendrait le moteur redemarrer en boucle.
		if engineSound[player] ~= "Accel" and engineSound[player] ~= "Sustain" then
			engineAccelerate(player, config)
		end
	elseif engineSound[player] ~= "Idle" then
		engineIdle(player, config)
	end
end

-- La posture : l'animation de tirage jouee a vitesse ZERO sur sa premiere frame. Le joueur garde donc
-- exactement la pose de depart du geste, corde en main.
local function enterReady(player: Player)
	-- Deux chemins mènent ici : la fin de la mise en position, et la fin d'un tirage.
	local currentHeld = ToolService.getHeld(player)
	local state = states[player]
	if not currentHeld or not (state == "Preparing" or state == "Pulling") then
		return
	end
	local animName = currentHeld.config.pullAnimation
	if not animName then
		setState(player, "Idle")
		return
	end

	local track = ToolService.getTrack(player, animName)
	if not track then
		setState(player, "Idle")
		return
	end

	track.Priority = SEQUENCE_PRIORITY
	-- Bouclee pour qu'elle ne s'arrete jamais d'elle-meme. A vitesse 0 elle ne bouclera jamais, mais sans ca
	-- Roblox pourrait la considerer terminee et la couper.
	track.Looped = true
	if not track.IsPlaying then
		track:Play()
	end
	track:AdjustSpeed(0)
	-- TimePosition APRES Play : sur une piste a l'arret, la valeur est ignoree.
	track.TimePosition = 0

	setState(player, "Ready")
end

-- Le tirage. C'est la MEME piste que la posture, on ne fait que la relancer a vitesse normale : le joueur
-- repart exactement d'ou il etait fige, sans transition a fondre.
local function pull(player: Player)
	local currentHeld = ToolService.getHeld(player)
	if not currentHeld or states[player] ~= "Ready" then
		return
	end
	local animName = currentHeld.config.pullAnimation
	if not animName then
		return
	end

	local track = ToolService.getTrack(player, animName)
	if not track then
		return
	end

	setState(player, "Pulling")

	-- La reussite est decidee AVANT de jouer. Sinon il faudrait enchainer un echec puis une reussite, et le
	-- joueur verrait deux gestes la ou il n'en a fait qu'un.
	local config = currentHeld.config
	pullCounts[player] = (pullCounts[player] or 0) + 1
	-- Au PREMIER tirage seulement, on tire le nombre de coups a faire pour ce demarrage. Les tirages suivants
	-- comparent a cette meme cible : la surprise est posee une fois, pas rejouee a chaque coup.
	if not pullTargets[player] then
		pullTargets[player] = math.random(config.pullsMin, config.pullsMax)
	end
	local success = pullCounts[player] >= pullTargets[player]

	-- Le son part avec le GESTE, pas avec la butee : on entend la corde se derouler pendant que le bras
	-- recule. C'est le seul element de cette sequence qui commence avant le marqueur.
	ToolService.playSound(player, config.pullSound)

	track.Priority = SEQUENCE_PRIORITY
	-- Non bouclee cette fois : c'est sa fin naturelle qui ramene a la posture.
	track.Looped = false
	if not track.IsPlaying then
		track:Play()
	end
	track.TimePosition = 0
	track:AdjustSpeed(1)

	-- L'a-coup du moteur tombe sur la MEME frame que la butee de la corde. Un decalage, meme court, casse le
	-- lien entre le geste et sa consequence : le joueur ne se dit plus "j'ai fait tousser le moteur" mais "le
	-- moteur a tousse".
	local sputtered = false
	track:GetMarkerReachedSignal(MARKER_PULL):Once(function()
		sputtered = true
		if states[player] ~= "Pulling" or not ToolService.getHeld(player) then
			return
		end
		ToolService.setToolAnimationsPlaying(player, true)

		-- Signal pour les FX client (secousse camera, champ de vision). Un COMPTEUR et non un booleen : deux
		-- tirages d'affilee ecriraient la meme valeur, et l'attribut ne changerait pas, donc le client ne
		-- serait pas prevenu du second. Toujours pas de remote : l'attribut se replique tout seul.
		local tool = currentHeld.tool
		tool:SetAttribute(PULL_TICK_ATTRIBUTE, (tool:GetAttribute(PULL_TICK_ATTRIBUTE) or 0) + 1)

		if success then
			-- Le moteur part sur la MEME frame que la butee, comme l'a-coup. On ne coupe pas les animations de
			-- l'outil : elles passent d'un soubresaut a un regime continu sans rupture.
			ToolService.playSound(player, config.startSound)

			-- La pose de travail est lancee ICI, pas a la fin du tirage. Le tirage (Action2) la masque encore,
			-- donc elle monte a plein poids DERRIERE, invisible. Quand le tirage s'efface a sa fin naturelle,
			-- elle est deja la : plus de trou d'animation ou la pose par defaut de Roblox apparaissait le temps
			-- d'un fondu. C'est la couche du dessous posee A L'AVANCE, comme la regle le veut.
			ToolService.setHoldAnimation(player, config.runHoldAnimation or config.holdAnimation)
			return
		end

		task.delay(config.sputterDuration, function()
			-- Revalide apres l'attente : l'outil a pu etre range entre-temps.
			if ToolService.getHeld(player) then
				ToolService.setToolAnimationsPlaying(player, false, 0.15)
			end
		end)
	end)

	track.Stopped:Once(function()
		-- Anormal ET actionnable : sans ce marqueur, le moteur ne toussera jamais et le tirage n'aura aucune
		-- consequence a l'ecran.
		if not sputtered and not warnedMissingMarker[animName] then
			warnedMissingMarker[animName] = true
			warn(`[ToolStartService] Marqueur "{MARKER_PULL}" absent de {animName} : le moteur ne toussera pas.`)
		end

		-- Revalide : le joueur a pu ranger l'outil pendant le geste.
		if states[player] ~= "Pulling" or not ToolService.getHeld(player) then
			return
		end

		if success then
			-- Le moteur tourne : la corde n'a plus rien a faire dehors, on la rend a l'outil.
			-- L'outil, LUI, reste dans la main gauche : une fois lance, on tient le taille-haie a deux mains
			-- pour couper, on ne le repasse pas a droite. C'est ReadyToCutAnimation qui place le bras droit.
			ToolService.setLauncherHand(player, nil)
			-- L'outil reste dans la MEME main, mais plus au meme angle : on passe de la prise de demarrage a la
			-- prise de coupe. Sans ca, l'outil gardait l'angle du tirage de corde et pointait vers le ciel
			-- pendant toute la taille, ce qui ressemble a une animation ratee alors que c'est une prise.
			ToolService.setGripOffset(player, config.cutGripOffset)
			-- Le ronronnement demarre ici, pas au marqueur : le son de lancement a eu le temps de poser son
			-- "vroum" seul, et il continue de jouer par-dessus le regime etabli.
			ToolService.playSound(player, config.runSound, true)
			engineSound[player] = "Idle"
			-- La pose de travail a deja ete lancee au marqueur, sous le tirage. Ici il ne reste qu'a acter
			-- l'etat et poser la vitesse de lames au ralenti : la boucle Heartbeat prend le relais ensuite.
			bladeSpeed[player] = config.bladeIdleSpeed
			ToolService.setToolAnimationSpeed(player, config.bladeIdleSpeed)
			setState(player, "Running")
			-- L'etat est pose AVANT : updateEngineSound refuse d'agir hors Running. Si le joueur tenait deja le
			-- clic pendant le dernier tirage, l'acceleration part donc immediatement.
			updateEngineSound(player)
		else
			-- enterReady accepte l'etat "Pulling", donc pas besoin de mentir sur l'etat pour passer sa garde.
			enterReady(player)
		end
	end)
end

local function prepare(player: Player)
	local currentHeld = ToolService.getHeld(player)
	if not currentHeld then
		return
	end
	-- Outil qui coupe SANS moteur (cisaille) : il est "pret a couper" des l'equipement. On pose donc ENGINE (qui
	-- autorise la coupe, la visee et la pose de travail -- memes gates que le taille-haie) sans aucune sequence de
	-- demarrage. reset() (branche sur l'unequip) le remet a false via setState(nil). Ici ENGINE = "coupe activee".
	if currentHeld.config.cutReadyOnEquip then
		local character = player.Character
		if character then
			character:SetAttribute(ENGINE_ATTRIBUTE, true)
		end
		return
	end
	local animName = currentHeld.config.prepareAnimation
	if not animName then
		return
	end

	local track = ToolService.getTrack(player, animName)
	if not track then
		return
	end

	setState(player, "Preparing")

	track.Priority = SEQUENCE_PRIORITY
	track.Looped = false
	track:Play()
	track.TimePosition = 0
	track:AdjustSpeed(1)

	-- Once et non Connect, pour les DEUX signaux : la piste vient du cache et sera rejouee. Un Connect
	-- s'accumulerait a chaque lecture, et au dixieme demarrage de la session le passage de main partirait dix
	-- fois. Bug qui n'apparait qu'apres vingt minutes de jeu.
	track:GetMarkerReachedSignal(MARKER_OTHER_HAND):Once(function()
		task.delay(currentHeld.config.offHandDelay, function()
			-- Revalide APRES le delai, pas avant : le joueur a pu ranger l'outil ou mourir entre-temps.
			-- L'etat peut aussi etre passe a "Ready" si l'animation s'est terminee pendant l'attente, et c'est
			-- normal : le changement de main doit quand meme avoir lieu.
			local stillHeld = ToolService.getHeld(player)
			local state = states[player]
			if stillHeld and (state == "Preparing" or state == "Ready") then
				-- Les deux mains se separent au MEME instant : l'outil part a gauche, la corde a droite.
				-- Les faire a des moments differents donnerait une corde qui se tend toute seule.
				ToolService.setHand(player, stillHeld.config.offHandPart)
				ToolService.setLauncherHand(player, stillHeld.config.handPart)
			end
		end)
	end)

	track.Stopped:Once(function()
		enterReady(player)
	end)
end

local function activate(player: Player)
	if not ToolService.getHeld(player) then
		return
	end

	local now = os.clock()
	if now - (lastActivate[player] or 0) < ACTIVATE_COOLDOWN then
		return
	end
	lastActivate[player] = now

	local state = states[player] or "Idle"
	if state == "Running" then
		-- Moteur en marche : le clic ne demarre plus rien, il accelere les lames. Ca ne passe pas par ici mais
		-- par SetThrottle, qui gere le maintien du clic (presse ET relache).
		return
	elseif state == "Ready" then
		pull(player)
	elseif state == "Idle" then
		-- Ne devrait pas arriver : la mise en position part a l'equipement. Repli si elle a echoue (animation
		-- introuvable, personnage remplace au mauvais moment) pour ne pas laisser le joueur sans recours.
		prepare(player)
	end
	-- Preparing et Pulling : un geste est en cours, on ignore. Empiler deux gestes donne un bras qui tremble
	-- au lieu d'un joueur qui insiste.
end

-- Le client dit s'il maintient le clic. On ne fait que noter l'intention : c'est la boucle Heartbeat qui la
-- traduit en vitesse de lames, progressivement, et updateEngineSound qui bascule le son.
local function setThrottle(player: Player, wants: boolean)
	-- Validation : le client ment toujours. On n'accepte qu'un vrai booleen.
	if typeof(wants) ~= "boolean" then
		return
	end
	local held = ToolService.getHeld(player)
	-- Outil clic-par-clic (cisaille) : pas de gachette maintenue. Chaque coup passe par le remote CutSnip, et
	-- THROTTLE ne doit surtout pas se poser (sinon la camera se resserrerait a chaque clic). On ignore donc
	-- presser ET relacher pour ces outils.
	if held and held.config.cutPerClick then
		return
	end
	-- Sans outil en main il n'y a rien a accelerer. Sans ce test, cliquer les mains vides posait quand meme
	-- l'attribut et resserrait le champ de vision.
	if wants and not held then
		return
	end
	if throttle[player] == wants then
		return
	end
	throttle[player] = wants

	-- Le client s'y branche pour la camera et le champ de vision. Toujours pas de remote dans ce sens :
	-- l'attribut se replique tout seul.
	local character = player.Character
	if character then
		character:SetAttribute(THROTTLE_ATTRIBUTE, wants)
	end

	updateEngineSound(player)
end

-- Fait suivre la vitesse des lames a l'intention du joueur, un cran par frame. Une seule boucle pour tous les
-- joueurs : pas une connexion par personne. Elle ne touche qu'aux joueurs en Running, donc elle ne coute rien
-- quand personne ne taille.
local function stepBlades(dt: number)
	for player, state in pairs(states) do
		if state == "Running" then
			local currentHeld = ToolService.getHeld(player)
			if currentHeld then
				local config = currentHeld.config
				local target = if throttle[player] then config.bladeMaxSpeed else config.bladeIdleSpeed
				local speed = bladeSpeed[player] or config.bladeIdleSpeed

				-- Montee et descente ont des vitesses differentes : la lame prend son elan lentement mais
				-- retombe plus vite, ce qui rend le relachement franc sans rendre l'acceleration brutale.
				local rate = if target > speed then config.bladeAccel else config.bladeDecel
				local step = rate * dt
				if math.abs(target - speed) <= step then
					speed = target
				else
					speed += if target > speed then step else -step
				end

				bladeSpeed[player] = speed
				ToolService.setToolAnimationSpeed(player, speed)

				-- L'inclinaison suit la MEME rampe que les lames : une seule source de verite pour le regime.
				-- Image, son et reaction de couple ne peuvent donc pas se desynchroniser.
				-- L'inclinaison a son PROPRE rythme, et vise directement l'ACCELERATEUR plutot que la vitesse de
				-- lame atteinte.
				--
				-- Les lames montent lentement parce que c'est une masse qui prend son elan, et le son est cale
				-- dessus. La reaction de couple, elle, est immediate : c'est le poignet qui encaisse, pas un
				-- volant d'inertie. Les caler ensemble rendait le geste mou.
				-- Lerp exponentiel : depart franc, arrivee douce, et jamais de depassement.
				local tiltTarget = if throttle[player] then 1 else 0
				local tilt = tiltAmount[player] or 0
				tilt += (tiltTarget - tilt) * math.min(1, config.tiltFollowSpeed * dt)
				tiltAmount[player] = tilt

				-- TREMBLEMENT. L'outil bat de part et d'autre de sa position inclinee : un sinus donne
				-- naturellement l'alternance dans un sens puis dans l'autre.
				--
				-- Il n'apparait que dans le HAUT du regime. Present des le ralenti il se lirait comme un defaut
				-- d'affichage ; reserve a plein regime il se lit comme une machine qui force, et il recompense
				-- le joueur qui tient l'accelerateur.
				-- Horloge partagee plutot qu'une phase par joueur : une table de moins a nettoyer, et deux
				-- outils qui tremblent en phase ne se remarque pas.
				-- PAS AU PIED D'UNE HAIE. Le tremblement dit "la machine tourne dans le vide, elle force pour
				-- rien". En pleine taille il dit donc le contraire de ce qu'on veut montrer, et il brouille un
				-- geste de precision.
				-- On lit l'attribut pose sur le personnage plutot que d'appeler HedgeService : deux services qui
				-- ne se connaissent pas restent deux services qu'on peut retoucher separement.
				local character = player.Character
				local working = character ~= nil
					and character:GetAttribute(HedgeConfigs.AT_HEDGE_ATTRIBUTE) == true
				local gate = vibeGate[player] or 0
				gate += ((if working then 0 else 1) - gate) * math.min(1, config.vibeGateSpeed * dt)
				vibeGate[player] = gate

				local span = math.max(1 - config.vibeStart, 1e-3)
				local intensity = math.clamp((tilt - config.vibeStart) / span, 0, 1) * gate
				local vibe = 0
				if intensity > 0 then
					vibe = math.sin(os.clock() * config.vibeFrequency * 2 * math.pi) * config.vibeMaxAngle * intensity
				end

				-- L'inclinaison est REDUITE au pied d'une haie : elle fait pivoter la lame, qui finissait dans la
				-- haie. Le meme `gate` sert aux deux, donc la transition est deja lissee.
				-- gate vaut 1 hors chantier et 0 devant une haie : on interpole entre pleine inclinaison et
				-- inclinaison de travail.
				local scale = config.tiltWorkingScale + (1 - config.tiltWorkingScale) * gate
				ToolService.setGripTilt(player, tilt * scale, vibe)
			end
		end
	end
end

function ToolStartService.init()
	-- Sortir l'outil met AUTOMATIQUEMENT le joueur en position. Le clic ne sert plus qu'a tirer.
	-- Un premier clic pour "se preparer" ne decidait de rien : sortir l'outil, c'est deja dire qu'on veut s'en
	-- servir. Une manipulation qui n'offre aucun choix au joueur n'est pas du gameplay, c'est un peage.
	ToolService.onEquip(prepare)

	-- Ranger l'outil annule la sequence. ToolService coupe deja les pistes ; ici on remet juste l'etat a zero,
	-- sinon un clic apres re-equipement ne ferait rien.
	ToolService.onUnequip(reset)

	local activateRemote = RemoteSetup.getRemote("ActivateTool", "Tool")
	if activateRemote and activateRemote:IsA("RemoteEvent") then
		activateRemote.OnServerEvent:Connect(activate)
	else
		warn("[ToolStartService] Remote Tool/ActivateTool introuvable")
	end

	local throttleRemote = RemoteSetup.getRemote("SetThrottle", "Tool")
	if throttleRemote and throttleRemote:IsA("RemoteEvent") then
		throttleRemote.OnServerEvent:Connect(setThrottle)
	else
		warn("[ToolStartService] Remote Tool/SetThrottle introuvable")
	end

	RunService.Heartbeat:Connect(stepBlades)

	Players.PlayerRemoving:Connect(reset)
end

return ToolStartService
