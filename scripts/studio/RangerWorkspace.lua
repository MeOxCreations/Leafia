--[[
	RANGER LE WORKSPACE. A coller dans la barre de commandes de Studio.

	CE QU'IL FAIT : il cree les dossiers attendus s'ils manquent, puis il deplace ce qui traine A LA RACINE du
	Workspace vers le bon dossier. Il ne touche JAMAIS au contenu de Worlds (Maps, Plots, Visuels, Debris) : c'est la
	que vit la carte, et le code la cherche par ce chemin.

	IL COMMENCE EN APERCU. Tel quel, il n'ecrit rien : il imprime ce qu'il FERAIT, ligne par ligne. On lit, et si ca
	convient on repasse avec PREVIEW = false. Un rangement qu'on ne peut pas relire avant de l'appliquer est un
	rangement qu'on annule ensuite a la main, objet par objet.

	IL NE DEVINE RIEN. Ce qu'il ne connait pas, il le LAISSE et il le NOMME a la fin. Un objet range au hasard est
	pire qu'un objet mal range : on ne sait plus ou il est passe.

	PRUDENCE : enregistre ou publie la place avant d'appliquer.
]]

local PREVIEW = true

-- ===== CE QUE LE CODE CHERCHE PAR CHEMIN : on n'y touche sous aucun pretexte. =====
-- HedgeConfigs.AUTO_TAG_ROOT et GrassZoneConfigs.ROOT valent { "Worlds", "Maps" } ; PlotService, MailboxService,
-- BuildController et PlotOldmanController lisent Workspace.Worlds.Plots.
local WORLDS = "Worlds"
local WORLD_FOLDERS = { "Maps", "Plots", "Visuels", "Debris" }
-- Tout ce qui ne part pas chez les joueurs : bancs d'essai, decor de test, restes d'avatar.
local DEV = "Dev"

-- Ce qui reste a la racine, quoi qu'il arrive.
local KEEP = {
	Camera = true,
	Terrain = true,
	[WORLDS] = true,
	[DEV] = true,
}

-- Par NOM EXACT : ou va cet objet. Le nom est ce que Studio affiche.
local BY_NAME = {
	Default = DEV, -- ancien dossier fourre-tout
	Dev = DEV,
	Particles = DEV,
	Laptop = DEV,
	CurrencyRoot = DEV,
	Baseplate = DEV,
	Plane = "Maps", -- le grand sol : il fait partie du decor
}

-- Par CLASSE, pour ce qui n'a pas de nom stable. Pas de `Model` ici, volontairement : un Model a la racine se nomme,
-- il ne se devine pas.
local BY_CLASS = {
	Accessory = DEV, -- restes d'un avatar de test
}

local moves, kept, unknown = {}, {}, {}

local function folder(parent, name)
	local found = parent:FindFirstChild(name)
	if found then
		return found
	end
	if PREVIEW then
		table.insert(moves, `CREER  Workspace{parent == workspace and "" or "." .. parent.Name}.{name}`)
		return nil
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	table.insert(moves, `CREE   {created:GetFullName()}`)
	return created
end

local worlds = folder(workspace, WORLDS)
for _, name in ipairs(WORLD_FOLDERS) do
	if worlds then
		folder(worlds, name)
	end
end
local dev = folder(workspace, DEV)
local maps = worlds and worlds:FindFirstChild("Maps")

local function destinationFor(child)
	local target = BY_NAME[child.Name] or BY_CLASS[child.ClassName]
	-- "MeOxDev's hats", "Machin's hats" : le dossier d'accessoires que Studio laisse apres un test.
	if not target and child.Name:match("'s hats$") then
		target = DEV
	end
	-- Une part nue posee a la racine appartient au decor.
	if not target and child:IsA("BasePart") then
		target = "Maps"
	end
	return target
end

-- ON REGARDE AUSSI SOUS `Terrain`. Roblox accepte qu'on y parente des objets, et c'est la que finit par s'entasser
-- tout ce qu'on pose "vite fait" -- personne ne va chercher un dossier de test sous le terrain. Rien n'a de raison
-- d'y vivre : ce qui s'y trouve part dans Dev.
local candidates = workspace:GetChildren()
for _, child in ipairs(workspace.Terrain:GetChildren()) do
	table.insert(candidates, child)
end

for _, child in ipairs(candidates) do
	if KEEP[child.Name] and child.Parent == workspace then
		table.insert(kept, child.Name)
		continue
	end
	-- SOUS TERRAIN, tout part dans Dev, sauf ce que la liste des noms envoie ailleurs. Une part posee la n'est pas du
	-- decor : c'est quelque chose qu'on a lache en travaillant.
	local target = if child.Parent == workspace then destinationFor(child) else BY_NAME[child.Name] or DEV
	if not target then
		table.insert(unknown, `{child.Name} ({child.ClassName})`)
		continue
	end
	-- En apercu les dossiers n'existent pas encore (on ne les a pas crees) : on affiche donc le CHEMIN VOULU, pas
	-- celui d'une instance qu'on n'a pas.
	local label = if target == DEV then `Workspace.{DEV}` else `Workspace.{WORLDS}.Maps`
	table.insert(moves, `{child.Name} ({child.ClassName})  ->  {label}`)
	if not PREVIEW then
		local parent = if target == DEV then dev else maps
		if parent then
			child.Parent = parent
		else
			table.insert(unknown, `{child.Name} : dossier {label} introuvable`)
		end
	end
end

-- ON APLATIT LES POUPEES RUSSES. `Default` contient un dossier `Dev`, qui contient le reste : deplace tel quel, ca
-- donnerait Workspace.Dev.Default.Dev.<tout>. On remonte le contenu d'un cran tant qu'il reste une coquille, et on
-- jette la coquille vide -- un dossier vide qui porte le nom du dossier parent n'aide personne.
if not PREVIEW and dev then
	for _ = 1, 3 do -- trois tours suffisent : au-dela ce n'est plus une coquille, c'est un rangement voulu
		local shell = dev:FindFirstChild("Default") or dev:FindFirstChild("Dev")
		if not shell then
			break
		end
		for _, child in ipairs(shell:GetChildren()) do
			child.Parent = dev
		end
		table.insert(moves, `{shell.Name} vide -> supprime (son contenu remonte dans {DEV})`)
		shell:Destroy()
	end
end

print(("="):rep(70))
print(if PREVIEW then "APERCU : rien n'a ete touche. PREVIEW = false pour appliquer." else "APPLIQUE.")
print(("="):rep(70))
for _, line in ipairs(moves) do
	print("  " .. line)
end
print(`Laisses en place : {table.concat(kept, ", ")}`)
if #unknown > 0 then
	print(("-"):rep(70))
	print("PAS RANGES, parce qu'on ne sait pas ou ils vont. A placer a la main :")
	for _, line in ipairs(unknown) do
		print("  " .. line)
	end
end
