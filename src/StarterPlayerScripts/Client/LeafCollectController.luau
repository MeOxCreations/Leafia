--!strict
-- LA PASTILLE QUI VERSE UN TAS DE FEUILLES DANS LE SEAU, cote client : detection, badge, touche.
--
-- IL NE DECIDE RIEN. Il designe le tas le plus proche et demande ; c'est le serveur qui verifie qu'on porte bien
-- un seau, qu'on est assez pres, et qui compte les feuilles.
--
-- DETECTION RADIALE, pas une boite. Un tas est rond et pose a plat : une distance horizontale a son centre n'a
-- aucun angle mort, et elle ne depend pas de l'orientation de quoi que ce soit. Piege deja paye sur la prise de
-- l'echelle, ou deux boites laterales laissaient des trous aux extremites.
--
-- PAS A CHAQUE IMAGE. Un tas ne se deplace pas et le joueur marche : relire la liste six fois par seconde suffit,
-- et ca evite de balayer un dossier soixante fois pour un resultat identique.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarryUtils = require(ReplicatedStorage.Modules.Utils.CarryUtils)
local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)
local RakeConfigs = require(ReplicatedStorage.Modules.Configs.RakeConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local LeafCollectController = {}

local player = Players.LocalPlayer
local remote: RemoteEvent? = nil
-- LE TAS QU'ON DESIGNE, et la part qui porte son badge. On garde la PART : c'est elle que la pastille suit, et
-- c'est elle qui sert de cle au registre du prompt.
local target: Model? = nil
local anchor: BasePart? = nil
local bound = false

local function root(): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

local function ask()
	local pile = target
	local r = remote
	if pile and pile.Parent and r then
		-- ON ENVOIE LE TAS, RIEN D'AUTRE. Le serveur sait deja ce qu'on porte et ou l'on est : il n'y a donc rien
		-- a valider dans ce message, et rien a falsifier.
		r:FireServer(pile)
	end
end

--- Branche ou debranche la touche. Branchee seulement tant qu'un tas est designe : une touche qui repond partout
--- finit par repondre a la place d'une autre.
local function setBound(active: boolean)
	if active == bound then
		return
	end
	bound = active
	if active then
		ContextActionService:BindAction(RakeConfigs.COLLECT_ACTION, function(_, state: Enum.UserInputState)
			-- LA TOUCHE SUIT LE BADGE. `E` est partagee par le seau, la tondeuse, l'echelle, le camion et le
			-- grand-pere : sans ce test, un appui pres d'un tas declencherait aussi tout ce qui traine a portee.
			if state == Enum.UserInputState.Begin and InteractionPrompt.owns(anchor) then
				ask()
			end
			-- `Pass` et pas `Sink` : les voisines doivent recevoir l'appui elles aussi, chacune fera son propre
			-- test. Avaler l'input ici les casserait.
			return Enum.ContextActionResult.Pass
		end, false, RakeConfigs.COLLECT_KEYCODE)
	else
		ContextActionService:UnbindAction(RakeConfigs.COLLECT_ACTION)
	end
end

local function drop()
	if anchor then
		InteractionPrompt.release(anchor)
	end
	target, anchor = nil, nil
	setBound(false)
end

--- Le tas le plus proche a portee, ou nil. Rend aussi sa part, parce que c'est elle qui porte la pastille.
local function nearestPile(from: Vector3): (Model?, BasePart?)
	local folder = Workspace:FindFirstChild(RakeConfigs.PILE_FOLDER)
	if not folder then
		return nil, nil -- aucun tas n'a encore ete fait : le dossier n'existe meme pas
	end
	local best: Model? = nil
	local bestPart: BasePart? = nil
	local bestDist = RakeConfigs.COLLECT_RADIUS
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child.Name == RakeConfigs.PILE_NAME then
			local part = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
			if part then
				local delta = (part :: BasePart).Position - from
				local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
				if flat <= bestDist then
					bestDist, best, bestPart = flat, child :: Model, part :: BasePart
				end
			end
		end
	end
	return best, bestPart
end

local function tick()
	-- LE SEAU EST LA CONDITION. Sans lui il n'y a rien a remplir, donc rien a proposer : une pastille qui
	-- s'affiche pour une action impossible s'apprend a etre ignoree.
	if not CarryUtils.holds(player, "Bin") then
		drop()
		return
	end
	local me = root()
	if not me then
		drop()
		return
	end
	local pile, part = nearestPile((me :: BasePart).Position)
	if not (pile and part) then
		drop()
		return
	end
	if pile == target then
		return -- deja designe : on ne rejoue pas son apparition a chaque passage
	end
	if anchor then
		InteractionPrompt.release(anchor)
	end
	target, anchor = pile, part
	InteractionPrompt.show(
		part :: BasePart,
		RakeConfigs.COLLECT_KEY,
		RakeConfigs.COLLECT_ACTION_TEXT,
		Vector3.new(0, RakeConfigs.COLLECT_PROMPT_UP, 0),
		-- Tap / clic : le meme chemin que la touche. Le badge est a nous par definition quand on tape dessus.
		ask,
		RakeConfigs.COLLECT_OBJECT_TEXT,
		true -- offset relatif a la camera
	)
	setBound(true)
end

function LeafCollectController.init()
	-- EN TACHE DE FOND : `getRemote` cache un `WaitForChild`, et en ligne droite dans un init il gelerait tout le
	-- boot le temps de son timeout.
	task.spawn(function()
		remote = RemoteSetup.getRemote("CollectLeafPile", "Rake") :: RemoteEvent
	end)

	local nextCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextCheck then
			return
		end
		nextCheck = now + RakeConfigs.COLLECT_CHECK_EVERY
		tick()
	end)

	-- MORT OU RESPAWN : on lache le badge. Le personnage disparait, donc le seau aussi -- garder la pastille
	-- laisserait une invite sur un tas qu'on ne peut plus ramasser.
	player.CharacterRemoving:Connect(drop)

	print("[LeafCollectController] Pret : le seau en main, une pastille apparait sur le tas le plus proche.")
end

return LeafCollectController
