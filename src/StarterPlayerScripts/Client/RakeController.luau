--!strict
-- RATEAU, cote client. Il ne fait qu'UNE chose : dire au serveur "j'ai clique".
--
-- Tout le reste vit dans RakeService : les tas sont des objets du MONDE, repliques a tous. Le client n'a aucune
-- autorite dessus, et il n'a meme pas besoin de savoir ou ils sont.
--
-- POURQUOI UN REMOTE A LUI et pas ActivateTool : ActivateTool sert la sequence de DEMARRAGE du taille-haie, et
-- CutSnip la coupe de haie. Le rateau ne coupe rien et ne demarre rien -- lui donner son propre message evite
-- d'aller ajouter un cas particulier dans deux services qui ne le concernent pas.
--
-- MOBILE : le clic passe deja par le tactile (Enum.UserInputType.Touch est traite comme le clic gauche, meme
-- regle que ToolController). C'est l'EQUIPEMENT qui reste au clavier -- voir la note dans ToolController.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RakeConfigs = require(ReplicatedStorage.Modules.Configs.RakeConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local RakeController = {}

local TOOL_ATTRIBUTE = "LeafiaTool"

local player = Players.LocalPlayer
local sweepRemote: RemoteEvent? = nil

-- Le rateau est-il en main ? On lit l'attribut que ToolService pose sur le modele de l'outil : il se replique
-- avec le modele, donc rien a synchroniser et rien a rater au spawn.
--
-- Ce test n'est PAS une securite (le serveur revalide de toute facon) : il evite juste d'envoyer un message a
-- chaque clic de la partie, y compris quand le joueur taille ou conduit la tondeuse.
local function holdingRake(): boolean
	local character = player.Character
	if not character then
		return false
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:GetAttribute(TOOL_ATTRIBUTE) == RakeConfigs.TOOL_NAME then
			return true
		end
	end
	return false
end

function RakeController.init()
	-- EN TACHE DE FOND : getRemote cache un WaitForChild, et appele en ligne droite dans un init il gele TOUT le
	-- boot le temps du timeout (deja paye, voir le journal). Tant que ce n'est pas resolu, les clics ne partent
	-- pas -- ce qui n'a aucune consequence, le rateau n'est pas encore en main au premier dixieme de seconde.
	task.spawn(function()
		local remote = RemoteSetup.getRemote("RakeSweep", "Rake")
		if remote and remote:IsA("RemoteEvent") then
			sweepRemote = remote
		else
			warn("[RakeController] Remote Rake/RakeSweep introuvable : le rateau ne ramassera rien")
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- gameProcessed est vrai quand le joueur clique dans une interface ou tape dans le chat. Sans ce test,
		-- cliquer sur un bouton donnerait aussi un coup de rateau.
		if gameProcessed then
			return
		end
		local isClick = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		if not isClick then
			return
		end
		local remote = sweepRemote
		if remote and holdingRake() then
			-- Aucun argument : le serveur sait deja ce que le joueur tient et ou il regarde. Il choisit
			-- lui-meme les tas attrapes, et il borne la cadence.
			remote:FireServer()
		end
	end)
end

return RakeController
