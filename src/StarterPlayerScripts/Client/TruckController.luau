--!strict
-- CAMION, cote client : dessine notre pilule stylisee a la place de l'interface Roblox par defaut.
--
-- TOUT LE TRAVAIL RESTE AU SERVEUR. Son `ProximityPrompt` garde la detection de proximite, la touche E et le tap
-- mobile ; ici on ne fait QUE l'affichage. Meme partage que la boite aux lettres.
--
-- La pilule se met du cote de la porte OPPOSE au joueur, pour ne pas tomber sur son personnage.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)
local TruckConfigs = require(ReplicatedStorage.Modules.Configs.TruckConfigs)

local TruckController = {}

local player = Players.LocalPlayer
local activeAnchor: BasePart? = nil
-- LE PROMPT COURANT, garde pour pouvoir le declencher A LA MAIN. Roblox n'ecoute plus sa touche : c'est nous qui
-- la branchons, derriere le test d'appartenance du badge.
local activePrompt: ProximityPrompt? = nil
local bound = false

--- Declenche l'ouverture. `InputHoldEnd` JUSTE APRES le `Begin`, sinon le prompt reste "maintenu" et les appuis
--- suivants tombent dans le vide.
local function trigger()
	local prompt = activePrompt
	if prompt and prompt.Parent then
		prompt:InputHoldBegin()
		prompt:InputHoldEnd()
	end
end

--- Branche ou debranche la touche. Branchee seulement tant que le camion est a portee : une touche qui repond
--- partout finit par repondre a la place d'une autre.
local function setBound(active: boolean)
	if active == bound then
		return
	end
	bound = active
	if active then
		ContextActionService:BindAction(TruckConfigs.ACTION_NAME, function(_, state: Enum.UserInputState)
			-- LA TOUCHE SUIT LE BADGE. `E` est partagee par le seau, la tondeuse, l'echelle et la porte du
			-- grand-pere : sans ce test, se tenir pres du camion l'ouvrait meme quand le badge affiche montrait
			-- un seau -- et c'est exactement ce qui arrivait, parce qu'un ProximityPrompt ecoute sa touche
			-- lui-meme, sans rien demander a personne.
			if state == Enum.UserInputState.Begin and InteractionPrompt.owns(activeAnchor) then
				trigger()
			end
			-- `Pass` et pas `Sink` : les voisines doivent recevoir l'appui elles aussi, chacune fera son propre
			-- test. Avaler l'input ici les casserait.
			return Enum.ContextActionResult.Pass
			-- PAS DE BOUTON TACTILE AUTOMATIQUE (le `false`), et c'est un bug qu'on vient de payer. Ce troisieme
			-- argument demande a Roblox de poser un bouton A L'ECRAN : il apparait des que la machine se declare
			-- TACTILE -- un PC a ecran tactile compris -- quelque part vers le bas a droite, et il se CLIQUE A LA
			-- SOURIS. Le joueur cliquait dans le vide a cote du camion et la porte s'ouvrait.
			--
			-- Il ne manque a personne : la PILULE est deja le bouton mobile de cette action, et elle n'est la que
			-- quand l'action a un sens. Les features qui gardent ce bouton sont celles dont le geste n'a PAS de
			-- pilule -- reposer la tondeuse qu'on pousse, par exemple.
		end, false, TruckConfigs.PROMPT_KEYCODE)
	else
		ContextActionService:UnbindAction(TruckConfigs.ACTION_NAME)
	end
end

local function getRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function TruckController.init()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if prompt.Name ~= TruckConfigs.PROMPT_NAME then
			return
		end
		-- Le prompt est parente a la porte : c'est elle que la pilule doit suivre.
		local anchor = prompt.Parent
		if not (anchor and anchor:IsA("BasePart")) then
			return
		end
		activeAnchor = anchor :: BasePart
		activePrompt = prompt
		setBound(true)

		-- DU COTE OPPOSE AU JOUEUR. Pile derriere le camion, une pilule centree tombe sur le personnage et on ne
		-- voit plus ni l'un ni l'autre. On la decale du cote ou il n'est pas.
		--
		-- Decide UNE FOIS a l'affichage, pas a chaque image : une pilule qui change de cote pendant qu'on marche
		-- attire l'oeil sur elle au lieu de la porte.
		local side = TruckConfigs.PROMPT_SIDE
		local root = getRoot()
		if root then
			local toPlayer = root.Position - (anchor :: BasePart).Position
			if (anchor :: BasePart).CFrame.RightVector:Dot(toPlayer) > 0 then
				side = -side
			end
		end

		InteractionPrompt.show(
			anchor :: BasePart,
			-- LA TOUCHE AFFICHEE VIENT DE LA CONFIG, plus du prompt : il n'en a plus (Roblox ne doit pas
			-- l'ecouter), et lire `Unknown` ecrirait ca sur la pilule.
			TruckConfigs.PROMPT_KEY,
			prompt.ActionText,
			Vector3.new(side, TruckConfigs.PROMPT_HEIGHT, 0),
			-- Tap / clic : le meme chemin que la touche. Le badge est a nous par definition quand on tape dessus,
			-- donc il n'y a rien a tester ici.
			trigger,
			prompt.ObjectText,
			true -- offset relatif a la camera
		)
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		if prompt.Name ~= TruckConfigs.PROMPT_NAME then
			return
		end
		-- ON RETIRE NOTRE DEMANDE, on ne cache pas la pilule. Le prompt est un SINGLETON partage par six
		-- features : `hide()` jetterait aussi les leurs, et celles encore a portee ne reviendraient jamais.
		InteractionPrompt.release(activeAnchor)
		activeAnchor = nil
		activePrompt = nil
		setBound(false)
	end)
end

return TruckController
