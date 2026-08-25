--!strict
-- Reglages du DIDACTICIEL. Data pure, zero logique.
--
-- Le didacticiel a deux moities : TutorialService (serveur) place le joueur, TutorialController (client) le
-- GUIDE. Cette config sert aux deux.

return {
	-- ===== LE HALO DE LA PORTE =====
	-- Premiere chose que le joueur doit comprendre en arrivant : ou aller. On le lui MONTRE au lieu de le lui
	-- ecrire -- un halo qui respire se lit sans lire, et il ne demande aucune traduction.
	--
	-- Le Highlight est POSE DANS STUDIO, pas cree en code. C'est la ou se reglent sa couleur de contour et son
	-- mode d'affichage, a l'oeil. Le code n'y touche QU'A UNE propriete : FillTransparency. Tout le reste --
	-- OutlineColor, OutlineTransparency, DepthMode -- reste exactement ce qui a ete choisi dans l'editeur.
	DOOR_NAME = "Door",
	HIGHLIGHT_NAME = "Highlight",

	-- ON CHERCHE PAR NOM DANS TOUT LE WORKSPACE, jamais par un chemin fixe. La porte a deja demenage une fois
	-- (de House vers House.HouseModel), et elle redemenagera : un chemin en dur transforme chaque rangement dans
	-- l'editeur en panne silencieuse. Le balayage ne tourne QUE tant que la porte n'est pas trouvee, donc il ne
	-- coute rien une fois qu'elle est la. L'ergonomie prime : c'est le code qui s'adapte au rangement.
	-- Le halo RESPIRE entre ces deux transparences de remplissage. 1 = invisible, 0 = plein.
	FILL_MIN = 0.5,
	FILL_MAX = 1,
	-- Duree d'un aller-retour COMPLET (invisible -> visible -> invisible), en secondes. Un battement lent se lit
	-- comme "viens par ici" ; rapide, il se lit comme une alerte. Ne pas descendre sous ~0.8 s.
	PULSE_PERIOD = 1.6,

	-- ===== LE PROMPT DE LA PORTE =====
	-- Distance HORIZONTALE (studs) sous laquelle le prompt apparait. RADIALE, jamais une box : colle a un bout
	-- de la porte on tomberait HORS d'une box laterale, et l'agrandir ne bouche pas le trou -- elle reste au
	-- mauvais endroit. Un seul nombre, aucun angle mort, independant de l'orientation.
	--
	-- Mesuree depuis le CENTRE de la porte. Pas depuis sa PrimaryPart : celle-ci est le "Handle", la CHARNIERE,
	-- posee sur le COTE -- le badge sortait donc a cote de la porte et la distance se comptait de travers.
	-- Le centre de la boite englobante, lui, ne depend d'aucun choix de PrimaryPart.
	PROMPT_RADIUS = 10,
	-- On ne teste pas la proximite a chaque image : ca ne se voit pas et ca coute.
	PROMPT_INTERVAL = 0.15,
	PROMPT_KEY = "E",
	-- ANGLAIS, comme tout texte vu par le joueur : le traducteur de Roblox part de l'anglais, un texte francais
	-- n'est traduit nulle part et le jeu devient illisible pour presque toute la plateforme.
	PROMPT_LABEL = "KNOCK",
	PROMPT_TITLE = "GRANDPA",
	-- Decalage d'AFFICHAGE du badge, en studs, a partir du centre de la porte. A zero il est pile au milieu.
	-- Sans rapport avec PROMPT_RADIUS, qui est la distance a laquelle il apparait : deux reglages differents, ne
	-- pas confondre -- l'un dit OU il se dessine, l'autre QUAND.
	PROMPT_OFFSET = Vector3.new(0, 0, 0),
	-- ContextActionService : createTouchButton fait apparaitre un bouton a l'ecran UNIQUEMENT sur tactile ET
	-- bind la touche sur PC, d'un seul geste. Sans lui, le didacticiel serait infranchissable sans clavier --
	-- donc pour la moitie des joueurs Roblox.
	--
	-- CONFLIT CONNU : E est aussi la touche du seau, de la tondeuse et de l'echelle. Chacun ne branche la sienne
	-- que quand elle a un sens, mais un seau pose devant la porte repondrait en meme temps qu'elle.
	ACTION_NAME = "LeafiaTutorialKnock",
	ACTION_KEY = Enum.KeyCode.E,

	-- ===== LA SCENE DU GRAND-PERE =====
	-- Part optionnelle posee dans Studio : si un objet de ce nom existe, sa CFrame EST le cadrage de la scene.
	-- Rien a poser pour que ca marche -- c'est un moyen de reprendre la main sur le cadrage, pas une obligation.
	SCENE_CAM_NAME = "SceneCam1",
	-- CADRAGE PAR DEFAUT, calcule depuis le JOUEUR au moment ou il toque. Il fait deja face a la porte, donc ce
	-- repere est juste par construction. "Se mettre devant la porte" supposerait au contraire de savoir quel axe
	-- du Model est son devant -- et rien ne le garantit, ca vient du rig et pas du bon sens.
	SCENE_CAM_BACK = 6, -- studs derriere le joueur
	SCENE_CAM_UP = 2.5, -- studs au-dessus de lui
	SCENE_CAM_SIDE = 2, -- decalage lateral : un cadrage parfaitement centre est plat
	-- Ce que la camera VISE, en studs au-dessus du centre de la porte. A zero elle vise le milieu exact.
	SCENE_LOOK_UP = 0.5,

	-- Durees. Les barres et la camera partent ENSEMBLE : dans un film le cadre bouge pendant que le rideau
	-- descend, il n'attend pas.
	SCENE_BARS_TIME = 0.6,
	SCENE_CAM_IN = 1,
	SCENE_CAM_OUT = 0.8,
	-- PROVISOIRE : duree de la scene tant que les animations ne la terminent pas elles-memes. A remplacer par la
	-- fin de l'animation du grand-pere des qu'elle existe -- une duree en dur et une animation finissent toujours
	-- par se contredire, et c'est la duree qui a tort.
	SCENE_HOLD = 3,

	-- Avec StreamingEnabled la porte peut arriver BIEN apres le spawn : on la re-cherche tant qu'on ne l'a pas.
	RESCAN_INTERVAL = 2,
	-- TRACE DE MISE AU POINT. Dit ce que la detection VOIT reellement : porte trouvee ou non, distance reelle,
	-- rayon demande. "Aucun prompt" couvre plusieurs causes qui se ressemblent a l'ecran (porte introuvable /
	-- trop loin / mission deja lancee) : les separer ici evite de chercher au mauvais endroit.
	-- A remettre a false une fois le didacticiel regle.
	DEBUG = false,
	DEBUG_INTERVAL = 2,
	-- Toujours rien apres ce delai : on le DIT. Un halo qui ne s'allume jamais ne produit aucune erreur, et sans
	-- ce message on chercherait le bug dans l'animation du halo au lieu du nom de la porte.
	NOT_FOUND_WARN_AFTER = 12,
}
