--!strict
-- Sequence de demarrage du moteur. Volontairement MINIMALE : une couche a la fois.
--
--   Idle --(EQUIPEMENT)--> Preparing --(fin de l'anim)--> Ready --(clic)--> Pulling
--                                                           ^                  |
--                                          tirage rate      +------------------+
--                                                                              |
--                                                            Nieme tirage --> Running
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

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
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

-- On ne previent qu'UNE FOIS par animation. Un message a chaque tirage noierait la console, ce qui revient a
-- ne rien dire.
local warnedMissingMarker: { [string]: boolean } = {}
local ACTIVATE_COOLDOWN = 0.2

type State = "Idle" | "Preparing" | "Ready" | "Pulling" | "Running"

local states: { [Player]: State } = {}
local lastActivate: { [Player]: number } = {}
local pullCounts: { [Player]: number } = {}

local function reset(player: Player)
	states[player] = nil
	lastActivate[player] = nil
	-- Ranger l'outil remet le compteur a zero : il faudra relancer le moteur. C'est voulu, le rituel fait
	-- partie du jeu.
	pullCounts[player] = nil
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
		states[player] = "Idle"
		return
	end

	local track = ToolService.getTrack(player, animName)
	if not track then
		states[player] = "Idle"
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

	states[player] = "Ready"
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

	states[player] = "Pulling"

	-- La reussite est decidee AVANT de jouer. Sinon il faudrait enchainer un echec puis une reussite, et le
	-- joueur verrait deux gestes la ou il n'en a fait qu'un.
	local config = currentHeld.config
	pullCounts[player] = (pullCounts[player] or 0) + 1
	local success = pullCounts[player] >= config.pullsToStart

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
			-- Le moteur tourne : la corde n'a plus rien a faire dehors, et l'outil revient dans la main qui
			-- travaille. Le lanceur d'abord, la main ensuite : dans l'autre ordre, la poignee reste une frame
			-- accrochee a une main qui tient deja l'outil, et la corde se plie.
			ToolService.setLauncherHand(player, nil)
			ToolService.setHand(player, config.handPart)
			-- Le ronronnement demarre ici, pas au marqueur : le son de lancement a eu le temps de poser son
			-- "vroum" seul, et il continue de jouer par-dessus le regime etabli.
			ToolService.playSound(player, config.runSound, true)
			-- Le joueur change de posture : il tient un outil qui tourne, pas un outil mort. Le fondu de
			-- setHoldAnimation lie l'idle a la pose de travail au lieu d'un saut sec.
			ToolService.setHoldAnimation(player, config.runHoldAnimation or config.holdAnimation)
			states[player] = "Running"
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
	local animName = currentHeld.config.prepareAnimation
	if not animName then
		return
	end

	local track = ToolService.getTrack(player, animName)
	if not track then
		return
	end

	states[player] = "Preparing"

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
		-- La coupe viendra ici. Le moteur tourne deja, il n'y a plus rien a demarrer.
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

	Players.PlayerRemoving:Connect(reset)
end

return ToolStartService
