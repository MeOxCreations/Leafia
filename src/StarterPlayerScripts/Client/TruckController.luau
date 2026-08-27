--!strict
-- CAMION, cote client : dessine notre pilule stylisee a la place de l'interface Roblox par defaut.
--
-- TOUT LE TRAVAIL RESTE AU SERVEUR. Son `ProximityPrompt` garde la detection de proximite, la touche E et le tap
-- mobile ; ici on ne fait QUE l'affichage. Meme partage que la boite aux lettres.
--
-- La pilule se met du cote de la porte OPPOSE au joueur, pour ne pas tomber sur son personnage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)
local TruckConfigs = require(ReplicatedStorage.Modules.Configs.TruckConfigs)

local TruckController = {}

local player = Players.LocalPlayer
local activeAnchor: BasePart? = nil

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
			prompt.KeyboardKeyCode.Name,
			prompt.ActionText,
			Vector3.new(side, TruckConfigs.PROMPT_HEIGHT, 0),
			function()
				-- Tap / clic : on declenche le ProximityPrompt. `InputHoldEnd` JUSTE APRES, sinon il reste
				-- "maintenu" et les appuis suivants tombent dans le vide.
				prompt:InputHoldBegin()
				prompt:InputHoldEnd()
			end,
			prompt.ObjectText,
			true -- offset relatif a la camera
		)
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		if prompt.Name ~= TruckConfigs.PROMPT_NAME then
			return
		end
		-- ON NE CACHE QUE SI C'EST LA NOTRE. Le prompt est un SINGLETON partage par six features : une autre a pu
		-- prendre la main entre-temps, et la cacher aveuglement volerait la sienne -- elle ne reviendrait alors
		-- plus jamais, sans que rien ne le signale. Le piege est note dans le journal du projet.
		if InteractionPrompt.currentTarget() == activeAnchor then
			InteractionPrompt.hide()
		end
		activeAnchor = nil
	end)
end

return TruckController
