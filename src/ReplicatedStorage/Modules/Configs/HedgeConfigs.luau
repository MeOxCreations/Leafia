--!strict
-- Reglages des haies. Data pure.

local HedgeConfigs = {
	-- Tag CollectionService. C'est LUI que le jeu interroge : une seule question a poser, quelle que soit la
	-- facon dont la haie a ete marquee.
	TAG = "Hedge",

	-- Le serveur pose le tag TOUT SEUL sur les parts dont le nom commence par ce prefixe. Taguer cinquante
	-- haies a la main serait du travail pour rien, et une haie oubliee ne reagirait pas sans qu'on comprenne
	-- pourquoi.
	-- Le tag reste la source de verite : on peut toujours en taguer une a la main si elle ne suit pas la
	-- convention de nom.
	AUTO_TAG_PREFIX = "hedge_",
	-- Ou chercher, sous Workspace. On ne balaye pas tout le Workspace : ca ferait passer chaque personnage,
	-- chaque outil clone et chaque debris par le test de nom pour rien.
	AUTO_TAG_ROOT = { "Worlds", "Maps" },

	-- Portee du rayon lance DEVANT le joueur. On detecte une INTENTION, pas une proximite : passer a cote d'une
	-- haie sans la regarder ne doit rien declencher. Une detection par distance ralentissait le joueur des
	-- qu'il longeait une haie, ce qui etait penible.
	-- Court expres : il faut vraiment se planter devant.
	RAY_LENGTH = 4,
	-- Portee quand on est DEJA accroche. Volontairement plus longue : avec un seuil unique, un joueur pile a la
	-- limite entrerait et sortirait a chaque frame et sa vitesse clignoterait. Cet ecart rend l'etat stable.
	RAY_LENGTH_ENGAGED = 5.5,
	-- Le volume part du CENTRE du HumanoidRootPart, sans decalage vertical.
	--
	-- On lance un VOLUME (Blockcast) et non une ligne (Raycast). Avec une ligne, une haie plus basse ou plus
	-- haute que le nombril du personnage n'etait jamais vue : le rayon passait au-dessus ou en dessous.
	-- Ces deux valeurs sont donc REELLES, pas cosmetiques : elles definissent ce qui est teste.
	DETECT_WIDTH = 1.5,
	DETECT_HEIGHT = 4,
	-- Epaisseur du volume dans le sens du deplacement. Mince : c'est la longueur du lancer qui donne la portee.
	DETECT_THICKNESS = 0.2,

	-- Vitesse imposee tant qu'on travaille au pied d'une haie. Passe par CharacterService.setSpeedOverride,
	-- jamais par WalkSpeed directement.
	WORK_SPEED = 5,

	-- Attribut pose sur le PERSONNAGE. Contrat serveur -> client : la camera et l'UI s'y brancheront sans qu'on
	-- ait besoin d'un remote, l'attribut se replique tout seul.
	AT_HEDGE_ATTRIBUTE = "LeafiaAtHedge",
	-- Normale de la face travaillee, en monde. Servira a orienter le joueur et la camera.
	HEDGE_NORMAL_ATTRIBUTE = "LeafiaHedgeNormal",

	-- DEBUG : dessine le rayon dans le monde. A passer a false avant toute publication.
	DEBUG_RAY = true,
	-- La boite de debug reprend DETECT_WIDTH et DETECT_HEIGHT : ce qu'on voit EST ce qui est teste. Plus de
	-- taille cosmetique reglable a part, c'etait la source de la confusion.
	DEBUG_COLOR_MISS = Color3.fromRGB(255, 131, 60), -- rien devant
	DEBUG_COLOR_HIT = Color3.fromRGB(60, 255, 76), -- une haie est visee
}

return HedgeConfigs
