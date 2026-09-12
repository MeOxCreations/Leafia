--!strict
-- LE CAMION. Reglages du prompt d'ouverture et de sa porte arriere.

local TruckConfigs = {
	-- LE NOM DU MODELE DANS LE WORKSPACE, pas une etiquette libre. Le renommer dans Studio sans le changer ici
	-- coupe le prompt EN SILENCE : plus rien ne le trouve. C'est aussi la cle de son animation d'ambiance, dans
	-- AmbientAnimConfigs -- deux endroits a changer ensemble.
	MODEL_NAME = "Truck",
	-- La part qui porte le prompt. UNE PART PRECISE et pas le modele entier : sinon l'invite s'affiche des qu'on
	-- longe la carrosserie, y compris a l'avant ou l'action n'a aucun sens.
	DOOR_PART = "DoorBack",

	-- ===== LE PROMPT =====
	-- Le client le reconnait par ce nom pour dessiner notre pilule a la place de l'interface Roblox par defaut.
	PROMPT_NAME = "TruckPrompt",
	-- EN ANGLAIS, comme tout texte vu par le joueur : le traducteur de Roblox part de l'anglais.
	PROMPT_ACTION = "OPEN",
	-- LA TOUCHE, ET SON NOM AFFICHE. Le `ProximityPrompt` ne l'ecoute PLUS (il ouvrait le camion pendant qu'on
	-- lisait le badge d'un seau) : c'est le client qui la branche, derriere le test d'appartenance du badge.
	-- Les deux vont ensemble -- afficher "E" en ecoutant autre chose serait un mensonge a l'ecran.
	PROMPT_KEY = "E",
	PROMPT_KEYCODE = Enum.KeyCode.E,
	-- Le nom de l'action liee a la touche. Deux features qui partagent un nom se debranchent l'une l'autre.
	ACTION_NAME = "LeafiaTruckOpen",
	PROMPT_OBJECT = "TRUCK",
	-- Distance d'activation, en studs. LA MEME QUE TOUT LE RESTE DU JEU -- seau, tondeuse, boite aux lettres :
	-- 8 partout.
	--
	-- ELLE ETAIT A 12, LA PLUS GRANDE DU PROJET, et c'est ce qui faisait gagner le camion contre un seau pose
	-- juste devant le joueur. Le badge va au PLUS PROCHE, mais celui qui l'a deja le GARDE tant qu'un autre n'est
	-- pas plus proche de 2 studs (l'hysteresis, qui empeche le clignotement). En portant 4 studs plus loin que les
	-- autres, le camion prenait le badge EN PREMIER, de loin, puis le gardait pendant qu'on se penchait sur autre
	-- chose. Ca ressemblait a une zone disproportionnee ; c'etait une portee disproportionnee.
	--
	-- Le commentaire d'avant justifiait les 12 par "on arrive avec une tondeuse devant soi" -- sauf que la
	-- tondeuse, elle, se detecte a 8. Un objet ne peut pas demander plus de portee que celui qu'on pousse.
	PROMPT_DISTANCE = 8,
	-- Hauteur de la pilule au-dessus de la porte, et son decalage lateral. Le decalage evite qu'elle tombe SUR le
	-- personnage quand on est pile derriere le camion.
	PROMPT_HEIGHT = 3,
	PROMPT_SIDE = 2.5,

	-- ===== LA PORTE =====
	-- Chemin de l'animation sous ReplicatedStorage.Animations.
	DOOR_ANIM_PATH = { "General", "TruckOpenDoorAnimation" },
	-- Elle n'a rien a partager : le camion ne joue que son idle d'ambiance, en priorite `Idle`. `Action` passe
	-- au-dessus sans discussion.
	DOOR_PRIORITY = Enum.AnimationPriority.Action,
	-- Vitesses d'ouverture et de fermeture, en multiple du rythme de l'editeur.
	--
	-- DEUX VALEURS et pas une : ouvrir est un geste qu'on regarde, refermer est une formalite. Un seul reglage
	-- forcerait a choisir entre une ouverture qui claque et une fermeture qui traine.
	DOOR_OPEN_SPEED = 1,
	DOOR_CLOSE_SPEED = 1.6,
	-- Les sons de la porte, sous SoundService. UN PAR SENS : ouvrir et refermer ne font pas le meme bruit, et le
	-- meme son dans les deux sens s'entend comme un enregistrement rejoue.
	--
	-- Joues A L'APPUI, pas a la fin du mouvement : c'est le geste du joueur qu'ils accompagnent.
	--
	-- SPATIAUX, poses sur la porte -- contrairement aux sons de la scene du tuto, qui sont mixes en 2D. Ici on
	-- n'est pas dans un plan de cinema : c'est un objet du monde, il doit s'entendre depuis la ou il est, et
	-- moins fort quand on s'en eloigne.
	DOOR_OPEN_SOUND = { "Sounds", "Game", "GlobalSounds", "OpenDoorTruckSound" },
	DOOR_CLOSE_SOUND = { "Sounds", "Game", "GlobalSounds", "CloseDoorTruckSound" },
	-- RETARD DU SON DE FERMETURE, en secondes. Le bruit d'une porte qui claque arrive quand elle TOUCHE, pas quand
	-- on la pousse : joue a l'appui, il precedait l'image de la porte encore grande ouverte.
	--
	-- Le son d'ouverture, lui, n'a PAS de retard : il accompagne le geste, qui commence tout de suite. Deux
	-- moments differents, deux reglages -- un seul aurait force a decaler les deux.
	DOOR_CLOSE_SOUND_DELAY = 0.5,

	-- ELLE SE FERME AVANT DE PARTIR, en secondes. On range une echelle REPLIEE : la voir se fermer PUIS rentrer
	-- raconte le geste dans l'ordre ou on le ferait. Fermee a l'arrivee, c'est la meme image finale mais la
	-- cause arrive apres l'effet.
	--
	-- Assez pour qu'on la voie se fermer, pas assez pour qu'on attende.
	CLOSE_BEFORE_FLY = 0.35,

	-- ===== L'ETAT DE LA PORTE, LU PAR LE CLIENT =====
	-- Un ATTRIBUT sur le modele, pas un remote : il se replique tout seul, il arrive avec le camion quand le
	-- streaming le livre, et un client qui se connecte en retard le lit sans qu'on ait a le lui renvoyer.
	OPEN_ATTRIBUTE = "LeafiaTruckOpen",

	-- ===== LES OUTILS RANGES DANS LA BENNE =====
	-- Le dossier qui les contient, dans le modele du camion. Chaque enfant est un outil qu'on peut sortir, POSE
	-- A LA MAIN dans Studio avec son orientation : le code ne les range pas, il les sort.
	TOOLS_FOLDER = "ObjectsTools",
	-- LE DESSIN D'UN OUTIL, par le nom de son modele dans la benne. Un dessin se lit d'un coup d'oeil a petite
	-- taille ; un modele 3D montre l'objet exact mais depend de son angle et de son eclairage.
	--
	-- CEUX QUI N'EN ONT PAS TOMBENT SUR L'APERCU 3D, et c'est voulu : un outil ajoute dans la benne apparait dans
	-- la barre tout de suite, meme sans dessin. On en ajoute un ici le jour ou il existe, et rien d'autre ne
	-- bouge -- alors qu'exiger un dessin ferait disparaitre l'outil de l'interface en attendant.
	--
	-- Les cles sont les NOMS DES MODELES, pas des etiquettes libres : c'est la benne qui decide, pas cette table.
	TOOL_ICONS = {
		Shear = "rbxassetid://96003986607540",
		HedgeTrimmer = "rbxassetid://90444880289298",
		Bin = "rbxassetid://127321612230568",
	},

	-- LA MARQUE D'UN OUTIL SORTI DU CAMION : sa pose D'ORIGINE, gardee en repere du camion.
	--
	-- ELLE SERT A DEUX CHOSES A LA FOIS, et c'est pour ca qu'elle est un attribut et pas une liste. Elle DIT que
	-- cet objet vient de la benne -- donc qu'on peut l'y remettre, et le retrouver suffit a le savoir, meme apres
	-- un rechargement de la carte. Et elle dit OU il s'y rangeait, au centimetre et a l'angle pres.
	--
	-- EN REPERE DU CAMION, jamais en monde : le camion peut bouger entre-temps, et une pose monde le ferait
	-- revenir a cote de la benne au lieu de dedans.
	POSE_ATTRIBUTE = "LeafiaTruckPose",

	-- CE QUI S'EQUIPE EN MAIN, et sous quel nom. La cle est le nom du MODELE dans la benne, la valeur est la cle
	-- de `ToolConfigs` -- les deux ne se ressemblent pas toujours : le modele "LeafRake" est l'outil "Rake".
	--
	-- ABSENT DE CETTE TABLE = PAS EQUIPABLE, et c'est la regle entiere. Le seau et l'echelle ne s'equipent pas :
	-- ce sont des objets qu'on va chercher et qu'on PORTE. Les mettre dans un menu les ferait apparaitre dans les
	-- mains par magie, depuis l'autre bout du jardin.
	TOOL_EQUIP = {
		Shear = "Shear",
		HedgeTrimmer = "HedgeTrimmer",
		LeafRake = "Rake",
	},

	-- Ou chacun se pose une fois sorti : un dossier de parts, une par outil, NOMMEE COMME LUI.
	--
	-- UNE PART PAR OUTIL et pas un point unique : deux outils lances de suite se poseraient l'un dans l'autre. Et
	-- c'est une part, donc son ORIENTATION compte aussi -- un rateau pose de travers a l'air tombe, pas depose.
	DROP_FOLDER = "ToolsDropPoints",
	-- Faute de part, il se pose devant celui qui l'a demande, a cette distance en studs. Un secours, pas le cas
	-- normal : le service le DIT quand il s'en sert, sinon on croirait que c'est voulu.
	DROP_FALLBACK_DIST = 6,

	-- ===== LA SORTIE, DU CAMION AU SOL =====
	-- Il ne se teleporte pas : il SORT du hayon et se pose. Trajet COURT ET BAS, aucune acrobatie.
	--
	-- IL A VOLE EN ARC, AVEC UN TOUR SUR LUI-MEME, et c'etait faux. Un arc haut raconte un objet LANCE ; or le
	-- joueur ne lance rien, il prend une echelle rangee dans une benne. Sur un objet long, le tour acheve de le
	-- transformer en pantin. On garde juste ce que fait un bras : ca sort, ca descend, ca se pose.
	--
	-- LE POINT DE CONTROLE EST A COTE DE LA BENNE, A SA HAUTEUR -- pas au-dessus du trajet. L'objet quitte donc le
	-- camion a l'HORIZONTALE, comme on le tire vers soi, avant de descendre vers le sol. A zero, la courbe
	-- redevient une droite et l'objet part en diagonale a travers le hayon.
	SLIDE_OUT = 4,
	-- ET IL MONTE, en studs au-dessus de la benne. C'est ce qui redonne un ARC au trajet : sans lui l'objet part
	-- a plat et descend en biais, ce qui se lit comme une glissade. Avec, il est SOULEVE puis pose.
	--
	-- Separe de `SLIDE_OUT` : l'un dit a quelle distance du camion il s'ecarte, l'autre a quelle hauteur il
	-- passe. Un seul reglage pour les deux forcerait a choisir entre un objet qui frole la carrosserie et un arc
	-- qui part trop loin derriere.
	SLIDE_UP = 5,
	-- Duree, en secondes. COURTE : le trajet est un enchainement entre deux etats, pas un plan a regarder. Un
	-- geste d'interface qui traine se ressent comme une attente des la deuxieme fois qu'on le voit.
	FLY_TIME = 0.45,
	-- IL SE MET DROIT TOUT DE SUITE, EN L'AIR, et fait le reste du chemin dans sa pose d'arrivee. Fraction du
	-- trajet au bout de laquelle il a fini de se redresser.
	--
	-- PAS SUR TOUT LE TRAJET : en etalant la rotation du depart a l'arrivee, l'objet se pose a l'instant PILE ou
	-- il finit de tourner, et les deux mouvements se masquent l'un l'autre -- on ne voit ni l'un ni l'autre. En le
	-- redressant sur le premier tiers, on lit DEUX choses a la suite : il se met droit, puis il descend se poser.
	--
	-- A 1, on revient au cas mou. Plus bas, le redressement claque.
	STRAIGHTEN_BY = 0.35,
	-- LE SIFFLEMENT DU DEPART, et le choc de la pose. Deux moments, deux sons : un seul bruit pour les deux
	-- raconterait un objet qui glisse d'un bout a l'autre, alors qu'il est LANCE puis POSE.
	--
	-- SPATIAUX, portes par l'objet lui-meme : ils viennent donc du camion au depart et du sol a l'arrivee, en
	-- suivant le vol entre les deux. Mixes en 2D, ils sonneraient dans la tete du joueur alors que la chose se
	-- passe a dix metres.
	FLY_SOUND = { "Sounds", "UI", "PassingSound" },
	DROP_SOUND = { "Sounds", "Game", "GlobalSounds", "DropSound" },

	-- ===== RECHERCHE =====
	-- Avec StreamingEnabled le camion peut arriver bien apres le demarrage. On le re-cherche jusqu'a le trouver,
	-- puis on abandonne en le disant : "absent au demarrage" est un etat NORMAL, "absent pour toujours" ne l'est
	-- pas.
	FIND_INTERVAL = 2,
	FIND_TIMEOUT = 60,
}

return TruckConfigs
