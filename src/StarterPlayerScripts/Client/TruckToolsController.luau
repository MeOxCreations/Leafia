--!strict
-- LES OUTILS DU CAMION, cote client : la barre s'ouvre avec le hayon, et cliquer demande au serveur de sortir
-- l'outil.
--
-- IL NE DECIDE RIEN. L'etat de la porte est un attribut pose par TruckService, le contenu de la benne est le
-- dossier lui-meme, et le vol appartient au serveur. Ce module ne fait que REGARDER ces trois choses et afficher
-- ce qu'elles disent -- sans jamais garder sa propre idee de ce qui est ouvert ou de ce qui reste.
--
-- C'est ce qui rend le cas a deux joueurs correct sans une ligne de plus : celui qui sort un rateau le fait
-- quitter la benne, donc la case passe a "ranger" CHEZ LES DEUX, sans qu'on ait rien a leur envoyer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
-- LE HAYON, pour mesurer la distance depuis LUI et pas depuis le milieu du camion : la barre parle de la benne,
-- et sur un vehicule de cette longueur les deux points sont a plusieurs studs l'un de l'autre.
--
-- RE-RESOLU TANT QU'IL MANQUE : avec le streaming, le modele arrive avant ses parts.
local doorPart: BasePart? = nil
-- EST-ON ASSEZ PRES ? Garde, pour ne recalculer la barre que quand la reponse CHANGE -- pas dix fois par seconde
-- pendant qu'on tourne autour du camion.
local near = false
-- ON L'A FERMEE A LA MAIN. Tant que ce drapeau tient, la barre reste cachee meme hayon ouvert et joueur devant.
--
-- IL SE LEVE TOUT SEUL, a deux occasions : quand le joueur S'ELOIGNE, et quand la porte CHANGE d'etat. Les deux
-- disent la meme chose -- il revient au camion, donc il veut de nouveau y prendre quelque chose. Un drapeau qui ne
-- se leve que par un appel explicite finit toujours par rester coince quelque part.
local dismissed = false

--- TOUS LES OUTILS DU CAMION : ceux qui sont encore dans la benne, et ceux qui en sont sortis.
---
--- LES SORTIS SE RECONNAISSENT A LEUR MARQUE (la pose que le serveur leur a posee), pas a une liste tenue ici.
--- Une liste serait un second etat a garder d'accord avec le monde, et elle mentirait des qu'un outil est
--- detruit ou deplace autrement -- alors que la marque voyage AVEC l'objet, et vaut pour tous les joueurs.
local function allTools(): { TruckToolsHandler.Entry }
	local list: { TruckToolsHandler.Entry } = {}
	local folder = toolsFolder
	if folder and folder.Parent then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				table.insert(list, { model = child :: Model, inside = true })
			end
		end
	end
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute(TruckConfigs.POSE_ATTRIBUTE) ~= nil then
			table.insert(list, { model = d :: Model, inside = false })
		end
	end
	-- TOUJOURS DANS LE MEME ORDRE. Sans tri, une case changerait de place quand son outil passe dedans / dehors,
	-- et le joueur cliquerait a l'endroit ou etait celle d'avant.
	table.sort(list, function(a, b)
		return a.model.Name < b.model.Name
	end)
	return list
end

local function nearTruck(): boolean
	local model = truck
	if not (model and model.Parent) then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	if not (doorPart and doorPart.Parent) then
		doorPart = nil
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Name == TruckConfigs.DOOR_PART then
				doorPart = d :: BasePart
				break
			end
		end
	end
	-- A DEFAUT DE HAYON, le milieu du camion. Moins juste, mais une barre qui marche a peu pres bat une barre qui
	-- ne s'affiche pas du tout le temps que la part arrive.
	local from = if doorPart then (doorPart :: BasePart).Position else model:GetPivot().Position
	local delta = (root :: BasePart).Position - from
	return Vector3.new(delta.X, 0, delta.Z).Magnitude <= TruckConfigs.HUD_DISTANCE
end

local function askFor(toolName: string)
	local r = remote
	if r then
		-- ON ENVOIE LE NOM, RIEN D'AUTRE -- pas meme le sens de l'action. C'est la PLACE de l'objet qui decide :
		-- dans la benne il sort, dehors il rentre. Le client n'a donc aucun etat a tenir juste, et deux joueurs
		-- qui cliquent en meme temps ne peuvent pas demander deux choses contradictoires.
		r:FireServer(toolName)
	end
end

--- Recalcule ce qu'on montre : la barre ne s'ouvre que si le hayon est ouvert ET qu'il reste quelque chose.
---
--- UNE SEULE FONCTION POUR LES DEUX QUESTIONS. Separer "faut-il l'ouvrir" de "que contient-elle" laisserait une
--- barre vide a l'ecran le jour ou le dernier outil sort -- deux etats qui se contredisent a une image pres.
-- ON COALESCE LES RAFRAICHISSEMENTS. Le streaming pose des dizaines de modeles d'un coup, et chacun reveille
-- l'abonnement au monde : recalculer a chaque fois relirait tout le Workspace autant de fois pour un resultat
-- identique. Un drapeau et une image d'attente suffisent -- piege deja paye sur la reconstruction de l'herbe.
local pending = false

local function refreshNow()
	local model = truck
	local open = model ~= nil and model:GetAttribute(TruckConfigs.OPEN_ATTRIBUTE) == true
	if not open then
		TruckToolsHandler.setShown(false)
		return
	end
	-- ET ON DOIT ETRE DEVANT. Le hayon reste ouvert quand on s'en va -- c'est normal, une porte ne se referme pas
	-- toute seule -- mais une barre d'outils qui suit le joueur a l'autre bout du jardin n'a plus de sujet : elle
	-- occupe le bas de l'ecran pour un camion qu'on ne voit meme plus.
	if not near then
		TruckToolsHandler.setShown(false)
		return
	end
	if dismissed then
		return -- fermee a la main : elle reviendra quand il s'eloignera ou rouvrira le hayon
	end
	local list = allTools()
	if #list == 0 then
		TruckToolsHandler.setShown(false)
		return
	end
	TruckToolsHandler.fill(list, askFor)
	TruckToolsHandler.setShown(true)
end

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

--- Branche tout ce qui doit rafraichir la barre. Rappelable : on coupe l'ancien avant de rebrancher.
local function watch(model: Model, folder: Instance)
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	truck, toolsFolder = model, folder
	doorPart = nil -- autre camion, autre hayon
	-- L'ETAT DE LA PORTE, LE CONTENU DE LA BENNE, ET LA DISPARITION DU CAMION. Trois sources, trois abonnements :
	-- on ne recalcule que quand quelque chose a VRAIMENT change, plutot que de relire tout ca a chaque image.
	table.insert(
		conns,
		model:GetAttributeChangedSignal(TruckConfigs.OPEN_ATTRIBUTE):Connect(function()
			dismissed = false -- il touche a la porte : il revient chercher quelque chose
			refresh()
		end)
	)
	table.insert(conns, folder.ChildAdded:Connect(refresh))
	table.insert(conns, folder.ChildRemoved:Connect(refresh))
	-- ET LE MONDE, pour les outils SORTIS : ils n'appartiennent plus a la benne, donc ses evenements a elle ne
	-- disent plus rien d'eux. On ne recalcule que sur ce qui peut etre un outil (un Model), pas sur chaque part
	-- posee ou retiree de la carte.
	local function onWorld(inst: Instance)
		if inst:IsA("Model") then
			refresh()
		end
	end
	table.insert(conns, Workspace.DescendantAdded:Connect(onWorld))
	table.insert(conns, Workspace.DescendantRemoving:Connect(onWorld))
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

	-- ON SUIT LA DISTANCE, mais on ne recalcule la barre QUE quand la reponse change. Un booleen garde, et
	-- l'immense majorite des passages ne fait rien du tout.
	--
	-- PAS A CHAQUE IMAGE : une barre qui apparait un dixieme de seconde apres le pas ne se remarque pas, et
	-- relire une distance a 60 Hz pour ca n'a aucun interet.
	local nextCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextCheck then
			return
		end
		nextCheck = now + TruckConfigs.HUD_CHECK_EVERY
		local close = nearTruck()
		if close ~= near then
			near = close
			if not close then
				dismissed = false -- il s'en va : la prochaine fois qu'il revient, la barre est la
			end
			refresh()
		end
	end)

	-- LA BARRE SURVIT AU RESPAWN (ResetOnSpawn est faux), mais pas nos abonnements si le camion disparait : le
	-- rescan ci-dessus les repose. Rien a faire ici -- et c'est le but.
	player.CharacterAdded:Connect(refresh)

	print("[TruckToolsController] Pret : la barre s'ouvre avec le hayon, et se cache quand on s'eloigne.")
end

--- FERME LA BARRE, sans attendre que le joueur s'eloigne.
---
--- POUR QUAND IL VIENT DE PRENDRE CE QU'ON LUI DEMANDAIT. La barre a fait son travail : la laisser ouverte
--- oblige a s'ecarter du camion pour voir le jardin, juste au moment ou on lui dit d'aller ailleurs.
---
--- ELLE REVIENDRA TOUTE SEULE : voir `dismissed`.
function TruckToolsController.close()
	if dismissed then
		return
	end
	dismissed = true
	refresh()
end

return TruckToolsController
