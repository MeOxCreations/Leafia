--!strict
-- LES TACHES : leurs icones, leurs couleurs. Data pure, aucune logique.
--
-- POURQUOI UNE TABLE ET PAS DES IDS EN DUR DANS LE HANDLER. Une icone se reutilise -- la tondeuse sert au
-- didacticiel, elle servira aux chantiers -- et un id recopie a deux endroits finit toujours par n'etre corrige
-- qu'a un seul. Ici on ecrit `TaskConfigs.ICONS.Mower`, et le jour ou l'image change, elle change partout.

export type Task = {
	-- Une cle de `ICONS`. Le dessin de la tache : ce que le joueur doit faire.
	icon: string,
	-- La teinte de la pastille sous l'icone. Chaque tache a la sienne : c'est ce qui les distingue d'un coup
	-- d'oeil quand il y en a trois a l'ecran, avant meme d'avoir lu le texte.
	tint: ColorSequence?,
	-- Ce qu'on demande, EN ANGLAIS : le traducteur de Roblox part de l'anglais.
	text: string,
	-- Ce que ca rapporte, deja mis en forme ("+ 50").
	reward: string,
	-- La monnaie affichee a cote de la recompense.
	currency: string?,
	-- De 0 a 1.
	progress: number?,
}

local TaskConfigs = {}

-- LES DESSINS DE TACHE. Ce sont eux qui vont dans `IconTaskDraw`.
TaskConfigs.ICONS = {
	Mower = "rbxassetid://128572894664436",
	Grass = "rbxassetid://72599703349189",
	GrassLots = "rbxassetid://90924932701080",
	-- Les debris au sol apres la coupe, ceux qu'il faut ramasser.
	Clippings = "rbxassetid://114282474206845",
	Leaves = "rbxassetid://107686037709324",
	-- Nom provisoire : le dessin represente un secateur, l'outil du jeu est une CISAILLE. A remplacer par un
	-- vrai dessin de cisaille -- garder le mauvais dessin ferait chercher au joueur un outil qui n'existe pas.
	Shears = "rbxassetid://114272255598885",
	Trash = "rbxassetid://91058614161927",
	Settings = "rbxassetid://72145892854726",
}

-- LA PASTILLE, EN DEUX IMAGES SUPERPOSEES. Le contour est dessine a part de son remplissage : c'est ce qui
-- permet de teinter l'interieur sans toucher au trait, qui reste blanc quelle que soit la couleur de la tache.
TaskConfigs.ICON_OUTLINE = "rbxassetid://112410882732688"
TaskConfigs.ICON_FILL = "rbxassetid://80842701479373"

-- CE QUE LA TACHE PAIE, affiche a droite de la recompense. Le texte dit COMBIEN, l'image dit EN QUOI : ecrire
-- "+ 50 XP" a cote d'une piece dirait deux fois la meme chose, et se contredirait le jour ou l'une des deux
-- change.
TaskConfigs.CURRENCIES = {
	Coins = "rbxassetid://85340926781465",
}

-- LES TEINTES DE PASTILLE. Un degrade et non une couleur plate : c'est ce qui donne le relief, et une pastille
-- unie a cote d'une barre degradee a l'air d'un element oublie.
TaskConfigs.TINTS = {
	-- Le vert de l'herbe : tondre, tailler, tout ce qui coupe du vegetal.
	Green = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("54ff5a")),
		ColorSequenceKeypoint.new(0.467, Color3.fromHex("54ff5a")),
		ColorSequenceKeypoint.new(0.482, Color3.fromHex("aeff87")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("d4ff9b")),
	}),
	-- Le brun des dechets : ramasser, vider, ranger.
	Brown = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("c98b3f")),
		ColorSequenceKeypoint.new(0.467, Color3.fromHex("c98b3f")),
		ColorSequenceKeypoint.new(0.482, Color3.fromHex("e0b06a")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("f0d09a")),
	}),
	-- Le bleu des outils : aller chercher, equiper, demarrer une machine.
	Blue = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("3fa9c9")),
		ColorSequenceKeypoint.new(0.467, Color3.fromHex("3fa9c9")),
		ColorSequenceKeypoint.new(0.482, Color3.fromHex("6ac8e0")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("9ae4f0")),
	}),
}

-- TROIS TACHES DE DEMONSTRATION, pour la commande admin `tasks`. Elles servent a JUGER l'animation : trois
-- lignes montrent la cascade, ce qu'une seule ne peut pas faire, et trois icones differentes verifient d'un coup
-- d'oeil que la pastille prend bien la teinte de sa tache.
--
-- Elles ne sont branchees sur aucune progression : c'est un banc d'essai visuel, pas un debut de systeme de
-- quetes.
TaskConfigs.DEMO_TASKS = {
	{ icon = "Mower", tint = TaskConfigs.TINTS.Green, text = "MOW THE LAWN", reward = "+ 50", currency = TaskConfigs.CURRENCIES.Coins, progress = 0.35 },
	{ icon = "Clippings", tint = TaskConfigs.TINTS.Brown, text = "RAKE THE CLIPPINGS", reward = "+ 30", currency = TaskConfigs.CURRENCIES.Coins, progress = 0.6 },
	{ icon = "Shears", tint = TaskConfigs.TINTS.Blue, text = "TRIM THE HEDGES", reward = "+ 80", currency = TaskConfigs.CURRENCIES.Coins, progress = 0.9 },
}

return TaskConfigs
