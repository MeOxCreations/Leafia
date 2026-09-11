--!strict
-- LES OUTILS DU CAMION, cote client : la barre s'ouvre avec le hayon, et cliquer demande au serveur de sortir
-- l'outil.
--
-- IL NE DECIDE RIEN. L'etat de la porte est un attribut pose par TruckService, le contenu de la benne est le
-- dossier lui-meme, et le vol appartient au serveur. Ce module ne fait que REGARDER ces trois choses et afficher
-- ce qu'elles disent -- sans jamais garder sa propre idee de ce qui est ouvert ou de ce qui reste.
--
-- C'est ce qui rend le cas a deux joueurs correct sans une ligne de plus : celui qui sort un rateau le retire de
-- la benne, donc la case disparait CHEZ LES DEUX.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local TruckConfigs = require(ReplicatedStorage.Modules.Configs.TruckConfigs)
local TruckToolsHandler = require(ReplicatedStorage.Modules.UI.Truck.TruckToolsHandler)

local TruckToolsController = {}

local player = Players.LocalPlayer
local remote: RemoteEvent? = nil
-- LE CAMION ET SON DOSSIER, gardes. On les re-cherche tant qu'on n'a pas les DEUX : avec le streaming le modele
-- arrive avant ses enfants, et une reference resolue une seule fois resterait vide pour toute la session.
local truck: Model? = nil
local toolsFolder: Instance? = nil
local conns: { RBXScriptConnection } = {}

--- Les outils encore ranges dans la benne, dans l'ordre du dossier.
local function toolsInside(): { Model }
	local folder = toolsFolder
	local list: { Model } = {}
	if not (folder and folder.Parent) then
		return list
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			table.insert(list, child :: Model)
		end
	end
	return list
end

local function askFor(toolName: string)
	local r = remote
	if r then
		-- ON ENVOIE LE NOM, RIEN D'AUTRE. Le serveur retrouve le modele lui-meme : c'est ce qui fait qu'un client
		-- modifie ne peut designer que ce qui est dans la benne.
		r:FireServer(toolName)
	end
end

--- Recalcule ce qu'on montre : la barre ne s'ouvre que si le hayon est ouvert ET qu'il reste quelque chose.
---
--- UNE SEULE FONCTION POUR LES DEUX QUESTIONS. Separer "faut-il l'ouvrir" de "que contient-elle" laisserait une
--- barre vide a l'ecran le jour ou le dernier outil sort -- deux etats qui se contredisent a une image pres.
local function refresh()
	local model = truck
	local open = model ~= nil and model:GetAttribute(TruckConfigs.OPEN_ATTRIBUTE) == true
	if not open then
		TruckToolsHandler.setShown(false)
		return
	end
	local list = toolsInside()
	if #list == 0 then
		TruckToolsHandler.setShown(false)
		return
	end
	TruckToolsHandler.fill(list, askFor)
	TruckToolsHandler.setShown(true)
end

--- Branche tout ce qui doit rafraichir la barre. Rappelable : on coupe l'ancien avant de rebrancher.
local function watch(model: Model, folder: Instance)
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	truck, toolsFolder = model, folder
	-- L'ETAT DE LA PORTE, LE CONTENU DE LA BENNE, ET LA DISPARITION DU CAMION. Trois sources, trois abonnements :
	-- on ne recalcule que quand quelque chose a VRAIMENT change, plutot que de relire tout ca a chaque image.
	table.insert(conns, model:GetAttributeChangedSignal(TruckConfigs.OPEN_ATTRIBUTE):Connect(refresh))
	table.insert(conns, folder.ChildAdded:Connect(refresh))
	table.insert(conns, folder.ChildRemoved:Connect(refresh))
	table.insert(
		conns,
		model.AncestryChanged:Connect(function()
			if not model.Parent then
				truck, toolsFolder = nil, nil
				TruckToolsHandler.setShown(false)
			end
		end)
	)
	refresh()
end

function TruckToolsController.init()
	-- EN TACHE DE FOND : `getRemote` cache un `WaitForChild`, et en ligne droite dans un init il gelerait tout le
	-- boot le temps de son timeout.
	task.spawn(function()
		remote = RemoteSetup.getRemote("TakeTruckTool", "Truck") :: RemoteEvent
	end)

	-- ON CHERCHE LE CAMION TANT QU'ON NE L'A PAS, avec SON DOSSIER. Le modele arrive avant ses enfants quand le
	-- streaming le livre : se figer sur un camion sans benne laisserait la barre morte pour toute la session.
	task.spawn(function()
		local deadline = os.clock() + TruckConfigs.FIND_TIMEOUT
		while os.clock() < deadline do
			if not (truck and truck.Parent and toolsFolder and toolsFolder.Parent) then
				for _, d in Workspace:GetDescendants() do
					if d:IsA("Model") and d.Name == TruckConfigs.MODEL_NAME then
						local folder = d:FindFirstChild(TruckConfigs.TOOLS_FOLDER)
						if folder then
							watch(d :: Model, folder)
							break
						end
					end
				end
			end
			if truck and toolsFolder then
				return
			end
			task.wait(TruckConfigs.FIND_INTERVAL)
		end
		-- ON LE DIT, UNE FOIS. "Pas encore la" est normal avec le streaming ; "jamais la" ne l'est pas, et sans ce
		-- mot la barre resterait muette sans que rien n'explique pourquoi.
		warn(
			`[TruckToolsController] Aucun "{TruckConfigs.MODEL_NAME}" avec un dossier `
				.. `"{TruckConfigs.TOOLS_FOLDER}" : pas de barre d'outils. Rojo ne synchronise pas le Workspace.`
		)
	end)

	-- LA BARRE SURVIT AU RESPAWN (ResetOnSpawn est faux), mais pas nos abonnements si le camion disparait : le
	-- rescan ci-dessus les repose. Rien a faire ici -- et c'est le but.
	player.CharacterAdded:Connect(refresh)

	print("[TruckToolsController] Pret : la barre s'ouvre avec le hayon.")
end

return TruckToolsController
