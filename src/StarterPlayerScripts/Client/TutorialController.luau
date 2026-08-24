--!strict
-- DIDACTICIEL, cote client : ce qui GUIDE le joueur. Pendant de TutorialService, qui le pose deja face a la
-- maison du grand-pere.
--
-- Deux choses, dans cet ordre :
--   1. Un HALO QUI RESPIRE sur la porte. Il dit "viens ici" sans ecrire une consigne -- donc sans rien a
--      traduire, et sans interface posee par-dessus le monde.
--   2. Un PROMPT quand on arrive devant. C'est lui qui lance la mission.
--
-- Une fois la mission lancee, les deux s'eteignent POUR DE BON : le guidage a fait son travail, et un halo qui
-- continue de battre pendant la scene tirerait l'oeil hors du plan.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)
local TutorialConfigs = require(ReplicatedStorage.Modules.Configs.TutorialConfigs)

local player = Players.LocalPlayer

local TutorialController = {}

local door: Model? = nil
local highlight: Highlight? = nil
local anchor: BasePart? = nil
local lastScanAt = 0
local lastPromptAt = 0
local lastDebugAt = 0
local startedAt = 0
-- UN DRAPEAU PAR AVERTISSEMENT, pas un seul pour les deux. Partage, le premier manquant masque le second : la
-- porte absente ferait taire le message du Highlight absent, et on chercherait au mauvais endroit.
local warnedNoDoor = false
local warnedNoHighlight = false
local elapsed = 0
local doorHint = true
local missionStarted = false
local promptShown = false
local actionBound = false
local conn: RBXScriptConnection? = nil

local function getRoot(): BasePart?
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

-- La porte, ou nil. RECHERCHE PAR NOM dans tout le Workspace, jamais par un chemin fixe : elle a deja demenage
-- une fois et elle redemenagera, et un chemin en dur transforme chaque rangement dans l'editeur en panne
-- silencieuse. Le balayage ne tourne QUE tant qu'elle n'est pas trouvee.
local function findDoor(): (Model?, BasePart?)
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == TutorialConfigs.DOOR_NAME then
			-- Reference FIXE, jamais GetPivot : le pivot d'un Model suit sa bounding box, donc ajouter la
			-- moindre part enfant le decale et le prompt part de travers sans que rien ne le signale.
			local part = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart", true)
			-- ON N'ACCEPTE QUE CE QUI EST UTILISABLE. Une porte sans aucune part ne sert a rien : soit ses parts
			-- ne sont pas encore repliquees (streaming), soit c'est un autre Model qui porte le meme nom. Dans
			-- les deux cas on continue de chercher au lieu de se figer sur elle.
			if part then
				return d, part
			end
		end
	end
	return nil, nil
end

-- Le prompt est un SINGLETON partage (echelle, tondeuse, seau, boite aux lettres). On ne cache donc QUE le
-- notre : appeler hide() sans regarder ferait disparaitre celui d'une autre feature en plein milieu.
local function hideOurs()
	if promptShown and anchor and InteractionPrompt.currentTarget() == anchor then
		InteractionPrompt.hide()
	end
	promptShown = false
end

-- La touche n'est branchee QUE quand l'action a un sens. createTouchButton fait apparaitre un bouton a l'ecran
-- sur tactile ET bind la touche sur PC : sans lui, le didacticiel serait infranchissable sans clavier.
local function setActionBound(active: boolean)
	if active == actionBound then
		return
	end
	actionBound = active
	if active then
		ContextActionService:BindAction(TutorialConfigs.ACTION_NAME, function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				-- Lu au moment de l'appui, donc bien apres que le module soit charge : pas d'appel au-dessus
				-- d'une definition, c'est le champ qui est resolu a l'usage.
				TutorialController.startMission()
			end
			-- Pass et pas Sink : E est partagee avec le seau et la tondeuse. Avaler l'input ici les casserait.
			return Enum.ContextActionResult.Pass
		end, true, TutorialConfigs.ACTION_KEY)
	else
		ContextActionService:UnbindAction(TutorialConfigs.ACTION_NAME)
	end
end

--- Allume ou eteint le halo de la porte. A appeler avec `false` quand la scene se lance : un halo qui continue
--- de respirer pendant une cinematique tire l'oeil hors du plan.
function TutorialController.setDoorHint(on: boolean)
	doorHint = on
	local halo = highlight
	if halo and halo.Parent and not on then
		halo.FillTransparency = TutorialConfigs.FILL_MAX
	end
end

--- Le joueur a toque : la mission commence. Le guidage s'eteint DEFINITIVEMENT -- halo, prompt et touche.
--- Idempotent, parce qu'un double appui ne doit pas relancer une scene deja en cours.
---
--- C'EST ICI QUE LA SUITE SE BRANCHE : animation de la porte, sonnette, puis la scene cinematique. Rien de tout
--- ca n'existe encore, donc pour l'instant l'appui ne fait qu'eteindre le guidage.
function TutorialController.startMission()
	if missionStarted then
		return
	end
	missionStarted = true
	TutorialController.setDoorHint(false)
	hideOurs()
	setActionBound(false)
	print("[Tutorial] Mission demarree : le joueur a toque a la porte.")
end

local function step(dt: number)
	local now = os.clock()

	-- ON REVALIDE TANT QU'IL MANQUE QUELQUE CHOSE, pas seulement au premier passage. Avec StreamingEnabled le
	-- Model arrive souvent AVANT ses parts : resoudre l'ancre une seule fois la laissait a nil pour TOUTE la
	-- session, et le prompt ne sortait jamais -- sans la moindre erreur. Le Model etait pourtant bien trouve,
	-- donc on cherchait le probleme du cote de la distance ou du prompt, pas du cote de la replication.
	if not (door and door.Parent and anchor and anchor.Parent) then
		door, anchor = nil, nil
		if now - lastScanAt < TutorialConfigs.RESCAN_INTERVAL then
			return
		end
		lastScanAt = now
		door, anchor = findDoor()
		if not door then
			if not warnedNoDoor and now - startedAt > TutorialConfigs.NOT_FOUND_WARN_AFTER then
				warnedNoDoor = true
				warn(
					`[Tutorial] Aucun Model "{TutorialConfigs.DOOR_NAME}" utilisable dans le Workspace : ni halo, `
						.. "ni prompt. Rojo ne synchronise pas le Workspace, la porte doit exister dans CETTE place."
				)
			end
			return
		end
	end

	-- Le Highlight peut arriver APRES les parts : meme raison, on le re-cherche tant qu'on ne l'a pas.
	if not (highlight and highlight.Parent) then
		local halo = (door :: Model):FindFirstChild(TutorialConfigs.HIGHLIGHT_NAME)
		highlight = if halo and halo:IsA("Highlight") then halo else nil
		if not highlight and not warnedNoHighlight and now - startedAt > TutorialConfigs.NOT_FOUND_WARN_AFTER then
			warnedNoHighlight = true
			warn(
				`[Tutorial] Porte trouvee mais aucun Highlight "{TutorialConfigs.HIGHLIGHT_NAME}" dedans : elle ne `
					.. "clignotera pas. Ce Highlight se pose A LA MAIN dans Studio, dans chaque place."
			)
		end
	end

	-- ===== LE HALO =====
	local halo = highlight
	if halo and halo.Parent then
		if not doorHint then
			-- On ECRIT la valeur eteinte plutot que de sortir en silence : le halo a pu etre coupe en plein
			-- battement, et il resterait alors fige a moitie visible.
			if halo.FillTransparency ~= TutorialConfigs.FILL_MAX then
				halo.FillTransparency = TutorialConfigs.FILL_MAX
			end
		else
			elapsed += dt
			-- SINUS, pas un aller-retour lineaire. Une respiration n'a ni depart ni arrivee : le cosinus repart
			-- de lui-meme, donc aucune saccade au bouclage. Un lerp aller-retour casse a chaque extremite.
			local a = 0.5 - 0.5 * math.cos(elapsed * math.pi * 2 / TutorialConfigs.PULSE_PERIOD)
			halo.FillTransparency = TutorialConfigs.FILL_MAX
				+ (TutorialConfigs.FILL_MIN - TutorialConfigs.FILL_MAX) * a
		end
	end

	-- ===== LE PROMPT =====
	local root = getRoot()
	local target = anchor

	-- Dit ce que la detection VOIT, pas ce qu'on croit qu'elle voit.
	if TutorialConfigs.DEBUG and now - lastDebugAt >= TutorialConfigs.DEBUG_INTERVAL then
		lastDebugAt = now
		if not (door and target) then
			print(`[Tutorial] porte "{TutorialConfigs.DOOR_NAME}" pas encore utilisable (Model ou parts absents)`)
		elseif not root then
			print("[Tutorial] pas de HumanoidRootPart (personnage pas encore la)")
		else
			local d = ((target.Position - root.Position) * Vector3.new(1, 0, 1)).Magnitude
			print(
				`[Tutorial] porte "{door.Name}" | ancre "{target.Name}" a {string.format("%.1f", d)} studs `
					.. `(rayon {TutorialConfigs.PROMPT_RADIUS}) | halo {tostring(highlight ~= nil)} `
					.. `| mission lancee {tostring(missionStarted)} | touche branchee {tostring(actionBound)}`
			)
		end
	end

	if missionStarted then
		return
	end
	if now - lastPromptAt < TutorialConfigs.PROMPT_INTERVAL then
		return
	end
	lastPromptAt = now

	if not (root and target and target.Parent) then
		hideOurs()
		setActionBound(false)
		return
	end

	-- DISTANCE RADIALE, a plat. Une box orientee laisserait des angles morts : colle a un bout de la porte on
	-- tomberait dehors, et l'agrandir ne bouche pas le trou puisqu'elle reste au mauvais endroit.
	local flat = (target.Position - root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude > TutorialConfigs.PROMPT_RADIUS then
		hideOurs()
		setActionBound(false)
		return
	end

	setActionBound(true)
	-- On re-montre au CHANGEMENT de cible, mais AUSSI quand le prompt ne nous appartient plus : une autre
	-- feature a pu prendre le singleton entre-temps. Sans ce second test, le notre disparaitrait pour de bon.
	if not promptShown or InteractionPrompt.currentTarget() ~= target then
		promptShown = true
		InteractionPrompt.show(
			target,
			TutorialConfigs.PROMPT_KEY,
			TutorialConfigs.PROMPT_LABEL,
			TutorialConfigs.PROMPT_OFFSET,
			TutorialController.startMission,
			TutorialConfigs.PROMPT_TITLE
		)
	end
end

function TutorialController.init()
	if conn then
		return
	end
	startedAt = os.clock()
	-- LA BOUCLE PART MEME SI LA PORTE N'EST PAS ENCORE LA. Avec StreamingEnabled elle arrive souvent apres le
	-- spawn : sortir ici laisserait le guidage mort pour toute la session, sans la moindre erreur pour le dire.
	-- Elle coute une comparaison de date tant qu'il n'y a rien a animer.
	conn = RunService.Heartbeat:Connect(step)
end

--- Coupe tout : boucle, halo, prompt et touche. Celui qui cree est celui qui nettoie, et il nettoie TOUT.
function TutorialController.stop()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	local halo = highlight
	if halo and halo.Parent then
		halo.FillTransparency = TutorialConfigs.FILL_MAX
	end
	hideOurs()
	setActionBound(false)
	door, highlight, anchor = nil, nil, nil
end

return TutorialController
