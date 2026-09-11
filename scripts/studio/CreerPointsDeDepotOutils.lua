-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO (pas dans le jeu, pas dans src/), en mode EDITION.
--
-- Cree le dossier `ToolsDropPoints` et une part par outil range dans la benne du camion : c'est la que chaque
-- outil se posera quand on le sortira depuis l'interface.
--
-- POURQUOI CE SCRIPT EXISTE.
-- Rojo ne synchronise QUE `src/`. Le Workspace, lui, ne voyage pas : un dossier cree par du code de jeu
-- n'existerait qu'en memoire pendant la partie et disparaitrait a l'arret. Il faut donc le creer en mode EDITION,
-- une fois, pour qu'il soit sauve avec la place -- et c'est exactement ce que fait la barre de commandes.
--
-- POURQUOI UNE PART ET PAS UN POINT.
-- L'outil prend la POSE de la part : sa position ET son orientation. Un rateau pose de travers a l'air tombe,
-- pas depose. C'est une chose qui se regle a la souris, en trois secondes, et qu'aucun chiffre dans un fichier
-- ne remplacera.
--
-- MODE D'EMPLOI
--   1. Colle ce script dans la barre de commandes et appuie sur Entree.
--   2. Ouvre `Workspace.ToolsDropPoints` : il y a une part par outil, posee derriere le camion, en eventail.
--   3. DEPLACE-LES ET TOURNE-LES a la souris, la ou tu veux que chaque outil atterrisse.
--
-- Relancer le script ne detruit RIEN : il ne cree que ce qui manque, et laisse en place ce que tu as deja
-- deplace. C'est ce qui permet de le rejouer apres avoir ajoute un sixieme outil dans la benne.

local Workspace = game:GetService("Workspace")

-- LES MEMES NOMS QUE DANS TruckConfigs. Ecrits en clair ici parce qu'un script de barre de commandes ne peut pas
-- require le jeu : a tenir d'accord a la main si jamais ils changent la-bas.
local TRUCK_NAME = "Truck"
local TOOLS_FOLDER = "ObjectsTools"
local DROP_FOLDER = "ToolsDropPoints"

-- L'EVENTAIL DE DEPART, derriere le camion. Ce ne sont que des places PROVISOIRES, faites pour etre deplacees :
-- l'important est qu'elles soient visibles et separees, pas qu'elles soient jolies.
local BEHIND = 10 -- studs derriere le camion
local SPREAD = 5 -- ecart entre deux parts
local SIZE = Vector3.new(2, 0.2, 2)

local function findTruck()
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and d.Name == TRUCK_NAME then
			return d
		end
	end
	return nil
end

local truck = findTruck()
if not truck then
	warn(`Aucun Model "{TRUCK_NAME}" dans le Workspace : rien a faire.`)
	return
end

local tools = truck:FindFirstChild(TOOLS_FOLDER)
if not tools then
	warn(`Aucun dossier "{TOOLS_FOLDER}" dans "{TRUCK_NAME}" : il n'y a aucun outil a poser.`)
	return
end

-- LE DOSSIER PEUT DEJA EXISTER : on le reutilise. Le detruire effacerait les places deja reglees a la souris,
-- et c'est precisement le travail qu'on ne veut pas refaire.
local folder = Workspace:FindFirstChild(DROP_FOLDER)
if not folder then
	folder = Instance.new("Folder")
	folder.Name = DROP_FOLDER
	folder.Parent = Workspace
	print(`Dossier "{DROP_FOLDER}" cree.`)
end

-- DERRIERE LE CAMION, ET AU SOL. On part de son pivot et on recule le long de son propre axe : le rang suit donc
-- l'orientation du camion, ou qu'il soit sur la carte.
local base = truck:GetPivot()
local created, kept = 0, 0
local index = 0

for _, tool in tools:GetChildren() do
	if tool:IsA("Model") then
		local existing = folder:FindFirstChild(tool.Name)
		if existing then
			kept += 1
		else
			local part = Instance.new("Part")
			part.Name = tool.Name
			part.Size = SIZE
			-- INVISIBLE ET TRAVERSABLE : c'est un REPERE, pas un objet. Solide, il bloquerait le joueur ; visible,
			-- il resterait a l'ecran sous l'outil pose dessus.
			part.Transparency = 1
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Anchored = true
			-- Le rang s'etale sur le cote, centre sur l'axe du camion.
			local offset = CFrame.new(index * SPREAD, 0, BEHIND)
			part.CFrame = base * offset
			part.Parent = folder
			created += 1
		end
		index += 1
	end
end

print(`Points de depot : {created} cree(s), {kept} deja en place. Deplace-les ou tu veux que les outils tombent.`)
