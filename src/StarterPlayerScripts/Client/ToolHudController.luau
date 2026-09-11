--!strict
-- LE MENU DES OUTILS, cote client : il liste ce que le joueur POSSEDE, et un clic equipe ou range.
--
-- POSSEDER, ICI, C'EST AVOIR SORTI L'OUTIL DU CAMION. La marque que le serveur pose sur un outil sorti
-- (`POSE_ATTRIBUTE`) sert donc une troisieme fois : elle dit d'ou il vient, ou il se range, ET qu'il est a nous.
-- Une liste de possession tenue a part serait un second etat a garder d'accord avec le monde -- et elle mentirait
-- le jour ou l'outil est remis dans la benne par l'autre joueur.
--
-- ET SEULEMENT CE QUI S'EQUIPE EN MAIN : la table `TOOL_EQUIP` fait le tri. Le seau et l'echelle n'y sont pas --
-- ce sont des objets qu'on va chercher et qu'on porte, et les mettre ici les ferait apparaitre dans les mains
-- depuis l'autre bout du jardin.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local ToolHudHandler = require(ReplicatedStorage.Modules.UI.Tool.ToolHudHandler)
local TruckConfigs = require(ReplicatedStorage.Modules.Configs.TruckConfigs)

local ToolHudController = {}

-- Pose par ToolService sur le MODELE de l'outil en main, et parente au personnage : c'est ainsi qu'on sait ce
-- qu'on tient. On demande l'ETAT, jamais un indice observe sur un cas particulier.
local TOOL_ATTRIBUTE = "LeafiaTool"

local player = Players.LocalPlayer
local selectRemote: RemoteEvent? = nil
local pending = false

--- L'outil tenu par le personnage, ou nil.
local function heldTool(): string?
	local character = player.Character
	if not character then
		return nil
	end
	for _, child in character:GetChildren() do
		local name = child:GetAttribute(TOOL_ATTRIBUTE)
		if typeof(name) == "string" then
			return name :: string
		end
	end
	return nil
end

--- CE QU'ON POSSEDE : les outils sortis du camion qui s'equipent en main.
---
--- L'ORDRE EST TOUJOURS LE MEME (trie par nom) : sans tri, une case changerait de place quand un outil est
--- range ou ressorti, et le joueur cliquerait la ou etait celle d'avant.
local function owned(): { ToolHudHandler.Entry }
	local held = heldTool()
	local list: { ToolHudHandler.Entry } = {}
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute(TruckConfigs.POSE_ATTRIBUTE) ~= nil then
			local tool = TruckConfigs.TOOL_EQUIP[d.Name]
			if tool then
				table.insert(list, {
					label = d.Name,
					tool = tool,
					icon = TruckConfigs.TOOL_ICONS[d.Name],
					held = held == tool,
				})
			end
		end
	end
	table.sort(list, function(a, b)
		return a.label < b.label
	end)
	return list
end

local function pick(toolName: string)
	local remote = selectRemote
	if remote then
		-- LE MEME OUTIL DEJA EN MAIN LE RANGE : c'est `ToolService.selectTool` qui en decide, pas nous. Une
		-- bascule tenue ici devrait deviner ce que le serveur a fait de notre derniere demande.
		remote:FireServer(toolName)
	end
end

local function onToggle()
	ToolHudHandler.setOpen(not ToolHudHandler.isOpen())
end

local function refreshNow()
	local list = owned()
	ToolHudHandler.fill(list, onToggle, pick)
	-- RIEN A MONTRER TANT QU'ON NE POSSEDE RIEN. Un bouton qui n'ouvre que du vide se clique une fois, puis
	-- jamais -- et il occupe un coin de l'ecran pour rien pendant toute la partie.
	ToolHudHandler.setVisible(#list > 0)
end

--- ON COALESCE. Le streaming pose des dizaines de modeles d'un coup, et chacun reveille l'abonnement au monde :
--- recalculer a chaque fois relirait tout le Workspace pour un resultat identique. Piege deja paye sur la
--- reconstruction de l'herbe.
local function refresh()
	if pending then
		return
	end
	pending = true
	task.defer(function()
		pending = false
		refreshNow()
	end)
end

--- Suit ce que le personnage tient : c'est ce qui met la case en vert.
local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		-- L'ATTRIBUT ARRIVE APRES L'ENFANT. Le modele est parente d'abord, l'attribut pose ensuite : lire tout de
		-- suite rendrait `nil` et la case resterait grise. On attend donc son arrivee, et on recalcule aussi a
		-- l'ajout -- l'un des deux suffit selon l'ordre, et les deux ne coutent rien.
		child:GetAttributeChangedSignal(TOOL_ATTRIBUTE):Connect(refresh)
		refresh()
	end)
	character.ChildRemoved:Connect(refresh)
	refresh()
end

function ToolHudController.init()
	task.spawn(function()
		selectRemote = RemoteSetup.getRemote("SelectTool", "Tool") :: RemoteEvent
	end)

	-- CE QUI PEUT CHANGER LA LISTE : un outil qui sort du camion ou qui y rentre (un Model qui arrive ou part), et
	-- sa marque de possession. On filtre sur les Models : une part posee dans la carte ne concerne pas ce menu.
	local function onWorld(inst: Instance)
		if inst:IsA("Model") then
			refresh()
		end
	end
	Workspace.DescendantAdded:Connect(onWorld)
	Workspace.DescendantRemoving:Connect(onWorld)

	local character = player.Character
	if character then
		watchCharacter(character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	refresh()
	print("[ToolHudController] Pret : le menu des outils s'ouvre en bas a gauche.")
end

return ToolHudController
