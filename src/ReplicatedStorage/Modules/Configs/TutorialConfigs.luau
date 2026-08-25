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
	-- Studs au-dessus du joueur. Le repere est sa RootPart, deja a hauteur de torse : plus on monte, plus la
	-- camera plonge sur lui, ce qui ecrase le decor et rapetisse le personnage. A 0.7 on est juste sous la
	-- hauteur d'yeux -- l'oeil arrive donc sur la porte de face, pas d'en haut.
	SCENE_CAM_UP = 0.7,
	SCENE_CAM_SIDE = 2, -- decalage lateral : un cadrage parfaitement centre est plat
	-- Ce que la camera VISE, en studs au-dessus du centre de la porte. A zero elle vise le milieu exact.
	SCENE_LOOK_UP = 0.5,

	-- ===== LE SON BAISSE PENDANT LA SCENE =====
	-- Volume du reste du jeu pendant la cinematique, en fraction. 0.25 = un quart. Pas ZERO : un silence total
	-- s'entend comme une coupure, et le monde a l'air de s'eteindre. On veut que l'oreille se tourne vers la
	-- scene, pas que le jeu disparaisse.
	SCENE_DUCK = 0.25,
	-- Duree du fondu. Assez lent pour ne pas se remarquer, assez court pour etre en place quand la scene demarre.
	SCENE_DUCK_TIME = 0.5,

	-- ===== LE ZOOM QUAND LA PORTE S'OUVRE =====
	-- Degres RETIRES au champ de vision a l'instant ou la porte part. Moins de champ = plus serre : l'image se
	-- resserre sur la porte pile quand elle bouge, donc l'oeil y va sans qu'on lui dise.
	--
	-- On ne bouge PAS la camera pour zoomer. L'avancer risquerait de la faire traverser le perron ou la
	-- rambarde, et il faudrait alors regler un trajet par decor. Le champ de vision, lui, ne rentre dans rien.
	--
	-- 12 degres, c'est un resserrement qu'on sent sans le voir. Au-dela de ~20 ca commence a deformer les bords.
	SCENE_ZOOM = 12,

	-- Durees. Les barres et la camera partent ENSEMBLE : dans un film le cadre bouge pendant que le rideau
	-- descend, il n'attend pas.
	SCENE_BARS_TIME = 0.6,
	SCENE_CAM_IN = 1,
	SCENE_CAM_OUT = 0.8,
	-- FILET, en secondes. La scene se termine normalement a la FIN de l'animation du grand-pere. Ce delai ne sert
	-- que si elle est introuvable ou ne demarre pas : sans lui le joueur resterait coince en camera scriptee,
	-- derriere des barres noires, sans aucun moyen d'en sortir.
	SCENE_HOLD = 3,

	-- ===== LE JOUEUR TOQUE =====
	-- Animation du JOUEUR : elle OUVRE la scene. Il toque, PUIS le grand-pere vient.
	KNOCK_ANIM = "Scene1_TocToc_Animation",
	-- Un marqueur par coup. Une LISTE et pas trois constantes : ajouter un quatrieme coup dans l'editeur ne
	-- demande alors qu'une ligne ici, et le code n'a pas a savoir combien il y en a.
	KNOCK_EVENTS = { "Toc1Event", "Toc2Event", "Toc3Event" },
	-- La porte TREMBLE a chaque coup.
	DOOR_SHAKE_ANIM = "DoorShakeAnimation",
	-- Son du coup, joue AU NIVEAU DE LA PORTE. Spatial et pas global : un bruit de porte qui sort du centre de la
	-- tete se decolle de l'image, surtout avec une camera posee a six studs de la.
	KNOCK_SOUND = { "Sounds", "Scenes", "Scene1", "KnockDoorSound" },

	-- ===== LES ANIMATIONS DE LA SCENE =====
	SCENE_ANIM_FOLDER = { "Animations", "Scenes", "Scenes1" },
	-- Le Model du grand-pere dans le Workspace. ATTENTION : AmbientAnimConfigs attend "GrandFather" et ne trouve
	-- rien -- les deux devront finir par s'accorder, sinon il ne respire pas pendant qu'on lui parle.
	GRANDPA_NAME = "OldmanOriginal",
	-- IL S'ACHARNE SUR LA POIGNEE avant d'ouvrir : "encore cette porte, faut vraiment que je la change". Joue
	-- APRES les coups et AVANT l'ouverture. Sa fin enchaine toute seule sur l'ouverture -- c'est l'animation qui
	-- dit quand elle a fini, pas un delai pose a cote.
	TRY_OPEN_ANIM = "Scene1_oldman_TryOpenDoor",
	-- Le bruit de poignee qu'on secoue. Spatial, au niveau de la porte.
	TRY_OPEN_SOUND = { "Sounds", "Scenes", "Scene1", "TryUnlockDoorSound" },

	-- ELLE MENE LA SCENE. C'est elle qui declenche la porte, et c'est SA FIN qui termine la scene.
	GRANDPA_ANIM = "Scene1_oldman_OpenDoor",
	-- Marqueur DANS l'animation du grand-pere : l'instant ou sa main pousse la porte.
	DOOR_START_EVENT = "OuvertureDoorEvent",

	-- Animation de la PORTE. Un nom SEPARE de celui du grand-pere : les deux ont deja porte le meme, et un nom
	-- qui designe deux choses finit toujours par en perdre une.
	DOOR_ANIM = "Scene1_opendoor",
	-- La porte se FIGE entrebaillee a ce marqueur, le temps que le grand-pere parle, puis elle repart.
	DOOR_MID_EVENT = "MidAnimationEventDoor",
	DOOR_PAUSE = 1.5,
	-- Grand ouverte : la piste se fige la et TIENT. Sans ce gel elle irait au bout de sa duree puis se
	-- relacherait, et la porte se refermerait toute seule -- une piste non tenue rend sa pose de repos.
	DOOR_END_EVENT = "EndOpenDoorEvent",

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
