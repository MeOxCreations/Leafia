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
	-- Distance a la BOITE de la haie en dessous de laquelle on reste accroche, SANS avoir a la regarder.
	--
	-- Le regard sert a s'ACCROCHER, c'est une intention. La proximite sert a RESTER, c'est un chantier. Deux
	-- questions differentes, deux reponses differentes.
	-- Sans ce maintien, contourner etait impossible : l'orientation est bloquee face a la haie, donc en
	-- glissant vers le bout l'eventail de detection finit par pointer dans le vide, et le contact tombait
	-- avant que le joueur ait avance assez pour que la face du bout l'emporte.
	-- Sortir volontairement reste possible a tout moment : la detection de sortie passe AVANT ce test.
	--
	-- 8 et non 6 : en tournant le coin, le client continue de glisser sur l'ANCIEN axe le temps que la nouvelle
	-- normale lui parvienne. Il s'ecarte donc pendant ce delai. Mesure : a 6, le tour echoue des 150 ms de
	-- latence ; a 8, il passe jusqu'a 300 ms avec un ecart maximal de 7.2 studs.
	HOLD_RANGE = 8,
	-- Le volume part du CENTRE du HumanoidRootPart, sans decalage vertical.
	--
	-- On lance un VOLUME (Blockcast) et non une ligne (Raycast). Avec une ligne, une haie plus basse ou plus
	-- haute que le nombril du personnage n'etait jamais vue : le rayon passait au-dessus ou en dessous.
	-- Ces deux valeurs sont donc REELLES, pas cosmetiques : elles definissent ce qui est teste.
	DETECT_WIDTH = 1.5,
	DETECT_HEIGHT = 4,
	-- Epaisseur du volume dans le sens du deplacement. Mince : c'est la longueur du lancer qui donne la portee.
	DETECT_THICKNESS = 0.2,

	-- Angles des lancers, en degres autour du regard. Un seul lancer droit devant ratait la haie des que le
	-- joueur se presentait un peu de biais, alors qu'il etait manifestement en train de travailler dessus.
	-- L'eventail rattrape ces approches. Le lancer qui touche le PLUS PRES gagne.
	-- En ajouter coute un Blockcast par joueur et par frame : trois suffisent largement.
	DETECT_ANGLES = { 0, -40, 40 },

	-- Avance que la nouvelle face doit prendre sur la face COURANTE pour qu'on bascule dessus, en studs.
	-- Sans cette marge, deux faces sont a egalite dans un angle de haie : le choix bascule a chaque frame et la
	-- camera part en oscillation gauche-droite. Une fois une face choisie, elle est gardee tant qu'une autre
	-- n'est pas NETTEMENT meilleure.
	FACE_SWITCH_MARGIN = 1.2,

	-- Vitesse imposee tant qu'on travaille au pied d'une haie. Passe par CharacterService.setSpeedOverride,
	-- jamais par WalkSpeed directement.
	WORK_SPEED = 8,

	-- ESPACE VITAL. Marge, en studs, ajoutee autour de chaque haie sur les cotes. Une boite invisible de cette
	-- taille empeche le joueur de se coller a la haie.
	--
	-- On laisse la PHYSIQUE faire le travail plutot que de repousser le joueur en code : elle gere le
	-- glissement le long de la haie, les sauts et les collisions entre joueurs, gratuitement et sans jamais se
	-- battre avec la simulation locale du client.
	-- VOLONTAIREMENT PLUS PETIT que WORK_DISTANCE : la boite empeche de traverser la haie, elle ne decide PAS
	-- de la distance de travail. C'est l'aimant qui la decide, et lui seul.
	--
	-- A 1.2 les deux se disputaient le placement, et la boite gagnait : ses coins tenaient le joueur trop loin
	-- au bout d'une haie, alors qu'il etait trop pres le long d'un grand cote. La distance dependait donc de
	-- l'endroit, pas du reglage.
	BUFFER_MARGIN = 0.8,
	-- Nom de la boite. Different du prefixe des haies, sinon l'auto-tag la prendrait pour une haie.
	BUFFER_NAME = "HedgeBuffer",
	-- Dossier qui rassemble toutes les boites, dans Workspace.
	--
	-- POURQUOI UN DOSSIER A PART plutot que de les ranger dans leur haie : la detection doit les IGNORER, et
	-- un filtre de raycast exclut une instance ET tous ses descendants. Rangees dans la haie, les exclure
	-- exclurait la haie elle-meme et plus rien ne serait jamais detecte.
	-- Un dossier permet de tout exclure d'un coup, avec une seule entree dans le filtre.
	BUFFER_FOLDER = "HedgeBuffers",

	-- Attribut pose sur le PERSONNAGE. Contrat serveur -> client : la camera et l'UI s'y brancheront sans qu'on
	-- ait besoin d'un remote, l'attribut se replique tout seul.
	AT_HEDGE_ATTRIBUTE = "LeafiaAtHedge",
	-- Normale de la face travaillee, en monde. Servira a orienter le joueur et la camera.
	HEDGE_NORMAL_ATTRIBUTE = "LeafiaHedgeNormal",

	-- ===== RAIL DE TRAVAIL =====
	-- Pendant l'accroche, le joueur glisse le long de la haie a distance CONSTANTE.
	--
	-- Ce n'est pas du confort, c'est ce qui rend la taille apprenable. Si la distance derive, le cadrage change,
	-- et le meme geste de souris ne coupe plus au meme endroit : le joueur ne peut developper aucune precision
	-- parce que les regles bougent sous ses pieds.
	-- Cette distance doit couvrir l'outil dans sa position la PLUS AVANCEE, jamais au repos. Trois choses la
	-- font avancer, et elles s'ADDITIONNENT :
	--   la hauteur visee   -> la pose des bras change, l'outil est plus avance a certaines hauteurs
	--   l'inclinaison      -> tiltMaxAngle (10 deg) depuis la poignee, soit 4 * sin(10) = 0.7 stud au bout
	--   le tremblement     -> vibeMaxAngle par-dessus
	--
	-- On ne peut PAS reculer le joueur seulement quand il accelere : l'aimant ne pousse jamais vers l'arriere,
	-- une poussee arriere se confondrait avec l'intention de sortir (voir MAGNET_STRENGTH). Donc UNE distance,
	-- reglee sur le cas le pire.
	--
	-- A REGLER A L'OEIL, en visant le BAS de la haie a plein regime : c'est la que la marge est la plus faible.
	-- ATTENTION pour plus tard : quand la coupe existera, une lame qui effleure la haie sera SOUHAITABLE.
	-- Ne pas trop reculer maintenant, sinon il faudra tout rapprocher a ce moment-la.
	WORK_DISTANCE = 2.5,
	-- Ecart tolere avant que l'aimant corrige. C'est aussi, exactement, l'INCERTITUDE sur la distance finale :
	-- le joueur cesse d'etre corrige des qu'il entre dans cette zone, donc il se fige n'importe ou dedans, et
	-- l'endroit depend de la direction d'ou il arrive.
	--
	-- A 0.25, l'ecart atteignait 0.49 stud entre une arrivee de loin et une arrivee de pres : en revenant sur
	-- une face deja travaillee, la distance n'etait plus la meme qu'avant. A 0.05 il tombe a 0.10, invisible.
	--
	-- Une zone morte large etait censee eviter de sentir une main dans le dos. C'est le caractere PROPORTIONNEL
	-- du rappel qui evite ca, pas sa zone morte : la force faiblit toute seule en approchant de la cible.
	-- Verifie : amplitude residuelle 0.00000 stud, aucune oscillation.
	WORK_DISTANCE_TOLERANCE = 0.05,
	-- Force MAXIMALE du rappel, entre 0 et 1. C'est une part de la direction de deplacement, pas une
	-- teleportation : on passe par le systeme de mouvement, jamais par la CFrame, sinon on se bat contre la
	-- physique et le personnage vibre.
	MAGNET_STRENGTH = 0.45,
	-- Force du rappel quand le joueur est TROP PRES. Plus faible que l'attraction : etre repousse doit se
	-- sentir comme un recadrage, pas comme une main dans le dos.
	--
	-- Sans cette poussee, rien ne ramenait un joueur arrive trop pres : il restait colle a la boite d'espace
	-- vital, et sa distance de travail dependait donc de la boite au lieu du reglage. Sur un grand cote il
	-- mangeait la haie, dans un coin la diagonale de la boite le tenait trop loin.
	MAGNET_PUSH_STRENGTH = 0.35,
	-- Ecart a partir duquel le rappel atteint sa force maximale. En dessous il pousse PROPORTIONNELLEMENT,
	-- donc de moins en moins fort a mesure qu'on approche.
	--
	-- Sans cette proportionnalite l'aimant poussait a fond jusqu'a depasser la zone morte, repartait en sens
	-- inverse, redepassait : le joueur avancait et reculait tout seul sans toucher a son clavier.
	MAGNET_RANGE = 1.5,
	-- Portee de la mesure de distance, lancee par le CLIENT vers la haie.
	MEASURE_RANGE = 10,

	-- A partir de quel alignement une poussee vers l'arriere est lue comme "je quitte le chantier".
	-- 1 = pile en arriere, 0 = perpendiculaire. 0.5 vaut environ 60 degres de tolerance : assez large pour
	-- sortir en diagonale, assez strict pour qu'un pas de cote ne decroche pas par accident.
	EXIT_DOT = 0.5,
	-- Amplitude minimale pour qu'un deplacement compte comme une VOLONTE de sortir. Une correction d'aimant est
	-- faible (0.45 au maximum), une vraie poussee au clavier vaut 1. Ce seuil les separe : les deux arrivent au
	-- serveur par le meme canal, seule leur ampleur les distingue.
	EXIT_MIN_INPUT = 0.7,
	-- Temps mort apres une sortie VOLONTAIRE, avant de pouvoir se raccrocher.
	--
	-- Sans lui : le joueur appuie sur S, le serveur decroche, mais la frame suivante le volume touche encore la
	-- haie (elle est a deux pas) donc ca raccroche, la sortie est redetectee, ca redecroche... soixante
	-- bascules par seconde, et la camera fait l'aller-retour entre Scriptable et Custom a chaque fois.
	-- Assez long pour s'eloigner d'un pas, assez court pour pouvoir revenir tout de suite.
	EXIT_COOLDOWN = 0.5,

	-- ===== PAS CHASSE =====
	-- A L'ESSAI, pas encore valide : l'effet peut etre retire. Tout ce qui le concerne (SLIDE_* et STEP_*) est
	-- regroupe ici expres, et cote client tout passe par setSlide : il n'y a qu'un bloc a enlever.
	--
	-- Devant une haie le joueur ne marche pas, il se deplace en pas chasses. Chemin sous ReplicatedStorage.
	SLIDE_ANIMATION = { "Animations", "Player", "General", "PasChasserAnimation" },
	-- Action, et NON Movement. La marche de Roblox est en Movement : a egalite de priorite les deux se
	-- melangeraient et les jambes hesiteraient entre les deux. Action passe devant.
	-- La piste ne cle QUE les jambes. La pose de maintien de l'outil est elle aussi en Action mais ne cle que
	-- les bras et le torse : les deux jouent ensemble sans se disputer un seul membre.
	SLIDE_PRIORITY = Enum.AnimationPriority.Action,
	-- Vitesse de lecture. A regler pour que les pieds ne patinent pas sur le sol a WORK_SPEED.
	SLIDE_SPEED = 1,
	SLIDE_FADE = 0.15,
	-- En dessous, on considere que le joueur ne glisse pas. Evite que la piste clignote sur une manette a peine
	-- poussee ou sur les restes d'une touche relachee.
	SLIDE_MIN_INPUT = 0.1,

	-- ===== DEPLACEMENT AU PAS =====
	-- Le joueur pousse quand son PIED TOUCHE LE SOL, pas en continu. C'est un marqueur pose dans l'animation
	-- qui declenche la poussee : le deplacement est donc cale sur l'image affichee, jamais sur une minuterie
	-- qui deriverait. C'est ce qui supprime le patinage des pieds au sol.
	STEP_MARKER = "WalkEvent1",
	-- Part de la vitesse au moment de la poussee, puis pendant le temps mort entre deux pas.
	-- STEP_GLIDE ne doit pas valoir 0 : le joueur s'arreterait NET entre chaque pas, ce qui se sent comme des
	-- a-coups et non comme une marche.
	STEP_PUSH = 1,
	-- ATTENTION : CameraController.MOVING_EXIT (0.15) doit rester SOUS cette valeur. Le champ de vision se
	-- decide sur l'intention de deplacement lissee, qui ne descend jamais sous STEP_GLIDE. Baisser STEP_GLIDE
	-- sous 0.15 ferait retomber le champ de vision entre deux pas, et il tremblerait au rythme de la marche.
	STEP_GLIDE = 0.25,
	-- Retombee de la poussee vers le glissement, par seconde. Plus haut = poussee plus seche.
	-- A REGLER en premier si le rendu ne va pas : c'est cette valeur qui decide combien de temps dure la
	-- poussee. Trop haut, le joueur avance par a-coups ; trop bas, on retrouve le deplacement continu.
	STEP_DECAY = 4,
	-- Sans marqueur recu pendant ce temps, on repasse en deplacement CONTINU.
	--
	-- FILET DE SECURITE. Une piste jouee A L'ENVERS ne declenche pas forcement ses marqueurs. Sans ce repli,
	-- le glissement d'un cote serait bloque net et rien a l'ecran ne dirait pourquoi.
	STEP_TIMEOUT = 0.6,

	-- ===== HAUTEUR DE COUPE =====
	-- Animation FIGEE, parcourue a la main selon la hauteur visee : premiere image = coupe basse, derniere
	-- image = coupe haute. On ne la joue jamais, on s'en sert comme d'une regle graduee.
	--
	-- Deux images suffisent donc a couvrir toutes les hauteurs : c'est la visee qui fait l'interpolation.
	UPDOWN_ANIMATION = { "Animations", "Player", "Tools", "HedgeTrimmer", "UpDownAnimation" },
	-- Action2 : au-dessus de la pose de maintien (Action), qui cle les MEMES bras. A egalite les deux se
	-- melangeraient et la hauteur visee ne serait jamais atteinte.
	UPDOWN_PRIORITY = Enum.AnimationPriority.Action2,
	UPDOWN_FADE = 0.2,
	-- Vitesse a laquelle les bras rejoignent la hauteur visee. Le curseur saute d'un pixel a l'autre ; sans ce
	-- lissage les bras claqueraient a chaque secousse de souris.
	-- Plus haut = plus reactif, plus nerveux. Plus bas = plus lourd, l'outil parait peser.
	UPDOWN_FOLLOW_SPEED = 12,

	-- Debordement accepte au-dela des bords de la haie, en studs. La visee reste valide dans cette marge.
	--
	-- Sans elle : viser le pied de la haie pour la balayer proprement faisait glisser le curseur SOUS la haie,
	-- il tombait sur le sol, et la pose sautait. Le lacher arrivait donc exactement la ou le joueur travaillait.
	AIM_MARGIN = 3,
	-- Zone morte aux DEUX extremites, en studs. Tout ce qui est sous ce seuil vaut le bas franc, tout ce qui
	-- est au-dessus vaut le haut franc.
	--
	-- Sans elle, tenir la pose la plus basse demanderait une visee au pixel : le joueur n'atteindrait jamais
	-- vraiment le bas, il tournerait autour. Les extremites doivent etre les positions les plus FACILES a
	-- tenir, ce sont elles qu'on utilise le plus.
	AIM_DEADZONE = 0.6,

	-- Moteur en marche. Pose par ToolStartService sur le personnage. Different de THROTTLE_ATTRIBUTE : celui-ci
	-- dit "le moteur tourne", l'autre dit "le joueur appuie sur le clic".
	ENGINE_ATTRIBUTE = "LeafiaEngine",

	-- DEBUG : liste une fois par seconde les pistes qui jouent REELLEMENT sur le joueur, avec leur priorite et
	-- leur poids. On demande a l'Animator plutot que de supposer : c'est lui qui a la reponse.
	-- A rallumer des qu'une animation se comporte bizarrement : c'est ce mouchard qui a montre que la reception
	-- tournait en boucle et se melangeait au pas chasse, chose invisible a l'oeil.
	DEBUG_SLIDE = false,

	-- ===== AIMANT : orientation forcee =====
	-- Le joueur pivote pour faire face a la haie qu'il vise. Il garde le controle de son DEPLACEMENT (il longe
	-- la haie en marchant sur le cote), mais plus de son orientation : elle est toujours bonne pour tailler.
	-- Vitesse du pivot. Assez rapide pour ne pas se sentir mou, assez lent pour ne pas claquer.
	FACE_TURN_SPEED = 11,

	-- ===== CAMERA DE TRAVAIL =====
	-- Placee du COTE du joueur (dans le prolongement de la normale de la face), donc elle regarde la haie
	-- par-dessus son epaule.
	CAMERA_DISTANCE = 13, -- recul, le long de la normale
	CAMERA_HEIGHT = 9.5, -- hauteur au-dessus du joueur
	-- Decalage lateral : c'est lui qui donne l'angle 3/4 isometrique. Le SIGNE choisit le cote, negatif pour la
	-- droite du joueur, positif pour sa gauche. Zero pour une vue bien en face.
	CAMERA_SIDE = -10,
	CAMERA_LOOK_HEIGHT = 2, -- point vise, au-dessus des pieds du joueur
	-- Recul quand le joueur ACCELERE : la camera se rapproche, l'attention se resserre sur le geste.
	-- Le lerp existant fait la transition, il n'y a rien de plus a ecrire.
	CAMERA_DISTANCE_THROTTLE = 9.5,
	-- Attribut pose par ToolStartService sur le personnage.
	THROTTLE_ATTRIBUTE = "LeafiaThrottle",
	-- Vitesse d'arrivee et de retour de la camera. Volontairement lente : une camera qui claque en place donne
	-- la nausee, meme quand la position finale est bonne.
	CAMERA_LERP_SPEED = 5,

	-- Pivot horizontal libre, au clic DROIT maintenu. Le clic gauche reste pour l'outil, et le curseur reste
	-- libre pour viser la haie : le bouton droit ne sert a rien d'autre, c'est le seul de disponible.
	-- Le personnage, lui, ne tourne pas : seule la camera pivote autour de lui.
	CAMERA_YAW_SENSITIVITY = 0.35, -- degres par pixel de souris
	-- Butee de chaque cote. Sans elle le joueur passerait derriere la haie et travaillerait a l'aveugle.
	CAMERA_YAW_LIMIT = 70,

	-- ===== CURSEUR SUR LA HAIE =====
	-- Bille posee la ou le curseur touche la haie. C'est le point qui deviendra l'endroit ou l'on taille.
	CURSOR_SIZE = 0.45,
	CURSOR_COLOR = Color3.fromRGB(255, 40, 200),
	-- Portee du lancer depuis la camera. Large : la camera est en retrait, il faut traverser la distance qui la
	-- separe de la haie.
	CURSOR_RANGE = 80,

	-- Attribut pose sur chaque haie. Le CLIENT s'en sert pour savoir si son curseur est bien sur une haie.
	-- On n'utilise pas le tag CollectionService cote client : un attribut se replique de facon certaine,
	-- inutile de parier sur autre chose.
	HEDGE_MARK_ATTRIBUTE = "LeafiaHedge",

	-- ===== ZONE DE CHANTIER =====
	-- Rectangle de beams pose au sol autour de la haie. Il montre au joueur ou se situe le travail.
	ZONE_ASSET = { "Assets", "Zones", "area_color_action" },
	-- Dossier qui rassemble les zones posees, dans Workspace.
	ZONE_FOLDER = "HedgeZones",
	-- Debordement autour de l'emprise de la haie, en studs. Un peu plus large que l'espace vital, pour que le
	-- joueur voie la zone meme colle a la haie.
	ZONE_MARGIN = 2.5,
	-- Epaisseur de la dalle. Fine : c'est un marquage au sol, pas une marche.
	ZONE_THICKNESS = 0.2,
	-- Leger soulevement pour ne pas clignoter contre le sol (deux surfaces au meme niveau se disputent
	-- l'affichage pixel par pixel).
	ZONE_LIFT = 0.05,

	-- DEBUG : dessine le volume de detection dans le monde. A passer a false avant toute publication.
	-- Delai apres un changement de face pendant lequel on NE juge PAS l'intention de sortir.
	--
	-- En tournant le coin, la normale pivote de 90 degres : le glissement lateral d'avant se retrouve aligne
	-- avec la nouvelle normale, et le test de sortie le lisait comme une fuite. Le joueur etait ejecte du
	-- chantier au moment precis ou il contournait.
	-- Assez long pour couvrir la latence de replication de la nouvelle normale vers le client, assez court
	-- pour qu'une vraie sortie juste apres un coin reste immediate.
	FACE_CHANGE_GRACE = 0.35,

	DEBUG_RAY = true,
	-- Les boites gardent leur TAILLE REELLE, celle qui est testee : la retrecir pour mieux voir ferait mentir
	-- le debug, ce qui a deja coute une soiree. C'est la TRANSPARENCE qu'on monte pour voir a travers.
	DEBUG_TRANSPARENCY = 0.82,
	-- La boite de debug reprend DETECT_WIDTH et DETECT_HEIGHT : ce qu'on voit EST ce qui est teste. Plus de
	-- taille cosmetique reglable a part, c'etait la source de la confusion.
	DEBUG_COLOR_MISS = Color3.fromRGB(255, 131, 60), -- rien devant
	DEBUG_COLOR_HIT = Color3.fromRGB(60, 255, 76), -- une haie est visee
}

return HedgeConfigs
