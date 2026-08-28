--!strict
-- BOITE AUX LETTRES cote CLIENT : dessine notre prompt stylise (InteractionPrompt, le MEME que l'echelle) a la
-- place du prompt Roblox par defaut (moche). Le ProximityPrompt du serveur (MailboxService) garde tout le travail :
-- detection de proximite, input clavier E, et Triggered qui joue l'anim cote serveur. Nous, on ne fait QUE
-- l'affichage. Sur mobile, un tap sur l'InteractionPrompt declenche le prompt (InputHoldBegin, HoldDuration 0).
--
-- PLACEMENT MALIN : le prompt se met du cote de la boite OPPOSE au joueur (le long de la droite de l'ecran), pour
-- ne pas tomber SUR le perso. Quand le joueur passe de l'autre cote, le prompt GLISSE (tween) vers l'autre bord.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)

local MailboxController = {}

local player = Players.LocalPlayer

local PROMPT_NAME = "MailboxPrompt" -- meme nom que cote serveur (MailboxService)
local PLOT_ATTRIBUTE = "LeafiaPlot" -- pose par le serveur (PlotService) sur le joueur : le nom de SON plot
local PROMPT_HEIGHT = 4 -- hauteur du prompt (ecran-haut, camera-relative). MONTE cette valeur pour le lever.
local PROMPT_SIDE = 3.5 -- decalage lateral (studs) de part et d'autre de la boite
local SIDE_LERP = 9 -- vitesse du glissement quand le prompt change de cote (haut = plus vif)
local SIDE_HYSTERESIS = 0.4 -- studs : marge avant de basculer de cote. PLUS BAS = bascule plus tot (plus strict).

local activeAnchor: BasePart? = nil
local currentSide = -1 -- -1 = prompt a GAUCHE de la boite, 1 = a DROITE
local currentX = -PROMPT_SIDE -- offset lateral courant, glisse vers currentSide * PROMPT_SIDE
local stepConn: RBXScriptConnection? = nil

local function getRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Nom du Slot (plot) auquel appartient la boite d'un prompt : on remonte les ancetres jusqu'a l'enfant DIRECT du
-- dossier Worlds.Plots. nil = boite hors plot (pas de proprietaire -> affichee pour tous).
local function mailboxSlotName(prompt: Instance): string?
	local worlds = workspace:FindFirstChild("Worlds")
	local plots = worlds and worlds:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	local node: Instance? = prompt
	while node and node.Parent do
		if node.Parent == plots then
			return node.Name -- node est le Slot
		end
		node = node.Parent
	end
	return nil
end

-- Cote de la boite OPPOSE au joueur, le long de la droite de l'ecran. -1 = a gauche, 1 = a droite. Hysteresis :
-- on ne bascule que passe une marge, sinon le prompt sauterait sans arret quand le joueur est pile aligne.
local function desiredSide(anchor: BasePart): number
	local camera = workspace.CurrentCamera
	local root = getRoot()
	if not (camera and root) then
		return currentSide
	end
	local playerSide = (root.Position - anchor.Position):Dot(camera.CFrame.RightVector)
	if playerSide > SIDE_HYSTERESIS then
		return -1 -- joueur a droite -> prompt a gauche
	elseif playerSide < -SIDE_HYSTERESIS then
		return 1 -- joueur a gauche -> prompt a droite
	end
	return currentSide -- dans la marge : on garde le cote courant
end

local function step(dt: number)
	local anchor = activeAnchor
	if not anchor then
		return
	end
	currentSide = desiredSide(anchor)
	local targetX = currentSide * PROMPT_SIDE
	-- Glissement doux (tween) vers le cote voulu, au lieu d'un saut sec.
	currentX += (targetX - currentX) * math.min(1, SIDE_LERP * dt)
	InteractionPrompt.setOffset(Vector3.new(currentX, PROMPT_HEIGHT, 0))
end

function MailboxController.init()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if prompt.Name ~= PROMPT_NAME then
			return
		end
		-- N'AFFICHER l'invite QUE sur la boite de MON plot (le serveur pose l'attribut LeafiaPlot). Sinon on la verrait
		-- sur la boite du voisin alors que le E ne fait rien : confus. Boite hors plot (slot nil) = affichee pour tous.
		local slot = mailboxSlotName(prompt)
		if slot and slot ~= player:GetAttribute(PLOT_ATTRIBUTE) then
			return
		end
		-- Le prompt est parente a une part de la boite : c'est elle que suit l'InteractionPrompt (WorldAnchor).
		local anchor = prompt.Parent
		if not (anchor and anchor:IsA("BasePart")) then
			return
		end
		activeAnchor = anchor
		-- On cale le cote TOUT DE SUITE (pas de glissement depuis l'ancienne position au 1er affichage).
		currentSide = desiredSide(anchor)
		currentX = currentSide * PROMPT_SIDE
		-- Offset RELATIF A LA CAMERA (dernier argument true) : X = ecran gauche/droite, Y = ecran haut.
		InteractionPrompt.show(
			anchor,
			prompt.KeyboardKeyCode.Name,
			prompt.ActionText,
			Vector3.new(currentX, PROMPT_HEIGHT, 0),
			function()
				-- Tap / clic : on declenche le ProximityPrompt (HoldDuration 0 -> se declenche a InputHoldBegin).
				-- InputHoldEnd JUSTE APRES : sans lui il reste "maintenu" et les clics suivants tombent dans le vide.
				prompt:InputHoldBegin()
				prompt:InputHoldEnd()
			end,
			prompt.ObjectText, -- titre au-dessus de la pilule (ex "MAILBOX")
			true -- offset relatif a la camera
		)
		if not stepConn then
			stepConn = RunService.RenderStepped:Connect(step)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		if prompt.Name ~= PROMPT_NAME then
			return
		end
		-- On ne reagit qu'a la boite qu'on affiche VRAIMENT : si on avait ignore ce prompt (boite d'un autre plot, ou
		-- deux boites a portee en meme temps), ne pas cacher l'invite de la NOTRE par erreur.
		if prompt.Parent ~= activeAnchor then
			return
		end
		local mine = activeAnchor
		activeAnchor = nil
		if stepConn then
			stepConn:Disconnect()
			stepConn = nil
		end
		-- On retire NOTRE demande, jamais la pilule entiere : `hide()` jetterait aussi celle des voisins.
		InteractionPrompt.release(mine)
	end)
end

return MailboxController
