--!strict
-- BOITES AUX LETTRES : le point d'entree des chantiers (a venir : courrier d'un client -> chantier -> cheque).
--
-- UNE BOITE PAR PLOT. On cable TOUTES les MailboxModel trouvees (une par Slot dans Worlds.Plots), chacune avec son
-- PROPRE etat (anim, ouvreur, ancre). Avant, une seule etait cablee (la 1re trouvee), donc sur les autres plots la
-- boite n'avait pas de prompt et ne s'ouvrait pas.
--
-- COMPORTEMENT : appuyer sur E OUVRE la boite (l'anim va de 0 jusqu'au marqueur IsOpenEvent, ou la porte est
-- ouverte, et s'y TIENT). Quand l'ouvreur S'ELOIGNE, l'anim repart EN ARRIERE jusqu'a 0 (la boite se referme).
-- L'interface des chantiers se branchera plus tard (voir le Triggered).
--
-- POURQUOI ON NE LIT PLUS LE TEMPS DU MARQUEUR A L'AVANCE (GetKeyframeSequenceAsync). Cette API est CAPRICIEUSE
-- cote serveur (reseau, rate-limit) : quand elle ratait, la boite ne s'ouvrait plus de TOUTE la session (bug
-- "parfois ca marche, parfois pas du tout"). A la place : on joue l'anim et on la FIGE quand elle ATTEINT le
-- marqueur IsOpenEvent (GetMarkerReachedSignal), lecture LOCALE et fiable.
--
-- AUTORITE serveur : l'animation est jouee cote serveur (Animator du modele), donc TOUS les joueurs la voient. On
-- pilote la VITESSE de lecture (AdjustSpeed +/- ou 0) : "jouer a telle vitesse" se replique proprement aux clients.
--
-- Les MailboxModel sont poses dans Studio (Rojo ne les synchronise pas) : on les retrouve par leur nom au boot. Le
-- ProximityPrompt est cree en code ; son AFFICHAGE est dessine cote client (MailboxController via InteractionPrompt),
-- le style Roblox par defaut etant coupe.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local PlotService = require(script.Parent.PlotService)

local MailboxService = {}

local MODEL_NAME = "MailboxModel"
local ANIMATION_PATH = { "Props", "Mailbox", "OpenCloseAnimation" }
local OPEN_EVENT = "IsOpenEvent" -- marqueur : la porte est ouverte. On FIGE la (on ne joue pas la fermeture du clip).
local SOUND_EVENT = "OuvertureEvenement" -- marqueur ou l'on joue le son (ouverture si on avance, fermeture si on recule)
local OPEN_SOUND_PATH = { "Sounds", "Game", "GlobalSounds", "OpenMailboxSound" }
local CLOSE_SOUND_PATH = { "Sounds", "Game", "GlobalSounds", "CloseMailboxSound" }
local SOUND_MAX_DISTANCE = 40 -- portee du son (studs) : seuls les joueurs PRES de la boite l'entendent, pas tout le serveur
local PROMPT_ACTION = "Ouvrir"
-- Titre affiche AU-DESSUS de la pilule du prompt (le client le lit via prompt.ObjectText et le passe a InteractionPrompt).
local PROMPT_OBJECT = "MAILBOX"
local PROMPT_DISTANCE = 8
local CLOSE_DISTANCE = 9 -- l'ouvreur au-dela de ca -> la boite se referme (un poil plus que la portee du prompt)
local ANIM_SPEED = 1 -- vitesse d'ouverture / fermeture (1 = vitesse naturelle du clip)

-- Etat d'UNE boite. `opener` = le joueur qui l'a ouverte (quand il part, elle se referme). `atOpen` = la porte a
-- atteint la pose ouverte et s'y tient.
type Mailbox = {
	anchor: BasePart,
	track: AnimationTrack,
	atOpen: boolean,
	opener: Player?,
	slotName: string?, -- le Slot (plot) auquel cette boite appartient ; nil = boite hors plot (pas de controle de propriete)
}

local mailboxes: { Mailbox } = {}
local stepping = false -- la boucle Heartbeat n'est branchee qu'UNE fois, pour toutes les boites

local function findAnimation(): Animation?
	local node: Instance? = ReplicatedStorage:FindFirstChild("Animations")
	for _, name in ipairs(ANIMATION_PATH) do
		node = node and node:FindFirstChild(name)
	end
	if node and node:IsA("Animation") then
		return node
	end
	warn(`[MailboxService] Animation introuvable : ReplicatedStorage.Animations.{table.concat(ANIMATION_PATH, ".")}`)
	return nil
end

-- Joue un son d'une boite, SPATIAL et a PORTEE LIMITEE : seuls les joueurs PRES d'elle l'entendent, pas tout le
-- serveur (le son est joue serveur, mais InverseTapered le fait taire au-dela de SOUND_MAX_DISTANCE).
local function playBoxSound(anchor: BasePart, path: { string })
	local sound = SoundUtils.play(path, anchor)
	if sound then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMaxDistance = SOUND_MAX_DISTANCE
	end
end

-- L'ouvreur de CETTE boite est-il encore assez pres ?
local function openerStillNear(mb: Mailbox): boolean
	local p = mb.opener
	if not p then
		return false
	end
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	return (root.Position - mb.anchor.Position).Magnitude <= CLOSE_DISTANCE
end

-- Chaque frame, pour UNE boite : l'ouvreur est la -> on OUVRE (vitesse +, le marqueur IsOpenEvent fige la pose
-- ouverte) ; sinon on FERME (vitesse -, jusqu'a 0). Looped = true tient la pose au bout mais wrapperait a l'autre
-- extremite : on CLAMP donc a un frame de chaque borne (0 et Length) avant que la lecture ne la depasse.
local function stepMailbox(mb: Mailbox, dt: number)
	local t = mb.track
	-- L'ouvreur est parti -> on oublie, la cible redevient FERME.
	if mb.opener and not openerStillNear(mb) then
		mb.opener = nil
	end
	local wantOpen = mb.opener ~= nil
	local pos = t.TimePosition
	-- Ferme, personne, deja a 0 : rien a faire (economie).
	if not wantOpen and not mb.atOpen and pos <= 0.001 then
		if t.Speed ~= 0 then
			t:AdjustSpeed(0)
		end
		return
	end
	local margin = ANIM_SPEED * dt + 0.005 -- distance parcourue en un frame : on fige AVANT de franchir la borne
	if wantOpen then
		-- OUVERTURE : on avance jusqu'a IsOpenEvent (le marqueur fige + pose atOpen). Filet anti-wrap : si on atteint
		-- presque la fin sans avoir croise le marqueur, on considere la boite ouverte et on fige quand meme.
		if mb.atOpen then
			if t.Speed ~= 0 then
				t:AdjustSpeed(0)
			end
		elseif t.Length > margin and pos >= t.Length - margin then
			mb.atOpen = true
			if t.Speed ~= 0 then
				t:AdjustSpeed(0)
			end
		elseif t.Speed ~= ANIM_SPEED then
			t:AdjustSpeed(ANIM_SPEED)
		end
	else
		-- FERMETURE : on recule jusqu'a 0, en figeant a 0 AVANT de wrapper vers l'autre bout.
		mb.atOpen = false
		if pos <= margin then
			t.TimePosition = 0
			if t.Speed ~= 0 then
				t:AdjustSpeed(0)
			end
		elseif t.Speed ~= -ANIM_SPEED then
			t:AdjustSpeed(-ANIM_SPEED)
		end
	end
end

-- Une SEULE boucle Heartbeat pour toutes les boites (branchee a la 1re boite cablee).
local function ensureStepping()
	if stepping then
		return
	end
	stepping = true
	RunService.Heartbeat:Connect(function(dt: number)
		for _, mb in ipairs(mailboxes) do
			stepMailbox(mb, dt)
		end
	end)
end

local function setup(model: Model, slotName: string?)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local anim = findAnimation()
	if not (animator and anim) then
		warn(`[MailboxService] Animator ou animation manquant sur {model:GetFullName()} : elle ne s'ouvrira pas.`)
		return
	end
	-- Un Humanoid affiche par defaut un nom et une barre de vie : sur une boite aux lettres, ce serait moche.
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	-- Une part solide pour porter l'invite. RootPart si elle existe (la base ancree du modele), sinon la PrimaryPart,
	-- sinon n'importe quelle part.
	local anchor = model:FindFirstChild("RootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not (anchor and anchor:IsA("BasePart")) then
		warn(`[MailboxService] Aucune part pour poser le ProximityPrompt sur {model:GetFullName()}.`)
		return
	end

	-- Looped = TRUE meme si on ne boucle jamais. Sinon, arrivee au bout (IsOpenEvent est souvent le dernier
	-- evenement), la piste se RELACHE et la pose ouverte SAUTE (retour ferme). Avec Looped = true elle tient sa
	-- derniere image ; c'est notre boucle qui pilote la vitesse (+ ouvrir, - fermer, 0 tenir) et qui CLAMP aux deux
	-- bouts pour ne jamais wrapper. Jouee GELEE (vitesse 0) a TimePosition 0 = boite FERMEE.
	local loaded = animator:LoadAnimation(anim)
	loaded.Looped = true
	loaded:Play(0, 1, 0)
	loaded.TimePosition = 0

	local mb: Mailbox = {
		anchor = anchor,
		track = loaded,
		atOpen = false,
		opener = nil,
		slotName = slotName,
	}

	-- FIN D'OUVERTURE : quand l'anim atteint IsOpenEvent EN OUVRANT (Speed > 0), on FIGE (boite ouverte). Fiable et
	-- local. Au repli on ne repasse pas ce marqueur en avant (on part deja de lui vers 0), donc rien dans l'autre sens.
	loaded:GetMarkerReachedSignal(OPEN_EVENT):Connect(function()
		if loaded.Speed > 0 then
			loaded:AdjustSpeed(0)
			mb.atOpen = true
		end
	end)

	-- SONS : le marqueur OuvertureEvenement est franchi dans les DEUX sens. On avance (Speed > 0) = ouverture -> son
	-- d'ouverture ; on recule (Speed < 0) = fermeture -> son de fermeture. A PORTEE LIMITEE (playBoxSound).
	loaded:GetMarkerReachedSignal(SOUND_EVENT):Connect(function()
		if loaded.Speed > 0 then
			playBoxSound(anchor, OPEN_SOUND_PATH)
		elseif loaded.Speed < 0 then
			playBoxSound(anchor, CLOSE_SOUND_PATH)
		end
	end)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MailboxPrompt" -- le client le reconnait pour dessiner notre prompt stylise a la place
	prompt.ActionText = PROMPT_ACTION
	prompt.ObjectText = PROMPT_OBJECT
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0 -- appui simple, pas de maintien
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	-- La boite peut etre partiellement masquee (pied fin, decor) : ne pas exiger la ligne de vue, sinon l'invite
	-- clignote quand un rien passe devant.
	prompt.RequiresLineOfSight = false
	-- Style CUSTOM : on n'affiche PAS l'UI Roblox par defaut (moche). Le prompt garde la detection de proximite,
	-- l'input clavier E et le Triggered ; l'AFFICHAGE est dessine cote client (MailboxController via InteractionPrompt).
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = anchor
	-- Appui sur E (ou tap) : CETTE boite retient QUI l'a ouverte. La boucle fait le reste (ouvre, referme au depart).
	-- AUTORITE : on n'ouvre QUE si le joueur POSSEDE le plot de cette boite (celui qu'il a choisi au Start). Une boite
	-- hors plot (slotName nil) reste ouvrable par tous (ancien comportement, pas de proprietaire).
	prompt.Triggered:Connect(function(player: Player)
		if mb.slotName and not PlotService.ownsSlot(player, mb.slotName) then
			return
		end
		mb.opener = player
	end)

	table.insert(mailboxes, mb)
	ensureStepping()
end

function MailboxService.init()
	local found = 0
	-- Une boite PAR PLOT : on cherche une MailboxModel dans chaque Slot. Recherche SCOPEE au plot (pas de GetDescendants
	-- sur tout le Workspace, qui balaierait les milliers de carreaux de haie ranges ailleurs, dans Worlds.Maps).
	local worlds = workspace:FindFirstChild("Worlds")
	local plots = worlds and worlds:FindFirstChild("Plots")
	if plots then
		for _, slot in ipairs(plots:GetChildren()) do
			local model = slot:FindFirstChild(MODEL_NAME, true)
			if model and model:IsA("Model") then
				setup(model, slot.Name)
				found += 1
			end
		end
	end
	-- Fallback : une boite posee HORS plot (ancien placement) -> on la prend si aucune n'a ete trouvee dans les plots.
	if found == 0 then
		local single = workspace:FindFirstChild(MODEL_NAME, true)
		if single and single:IsA("Model") then
			setup(single)
			found += 1
		end
	end

	if found == 0 then
		warn(`[MailboxService] Aucune {MODEL_NAME} trouvee (posee dans Studio ?).`)
	else
		print(`[MailboxService] {found} boite(s) aux lettres cablee(s)`)
	end
end

return MailboxService
