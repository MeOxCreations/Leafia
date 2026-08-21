--!strict
-- Reglages de la TONDEUSE. Data pure, zero logique. Partage client + serveur.
--
-- CE FICHIER DECRIVAIT AVANT un systeme de CELLULES calque sur les haies (LawnCellService), qui n'a jamais ete
-- ecrit. On ne le suit plus : l'herbe de zone existe deja, elle est deja cliente, et elle sait deja s'ecraser.
-- La tonte s'y greffe (voir le bloc TONTE de GrassZoneConfigs) au lieu de refabriquer une grille a cote.
--
-- PARTAGE DES ROLES
--   SERVEUR (MowService)    : qui porte quoi. Portage par WELD au HRP, comme l'echelle -> tout le monde la voit.
--   CLIENT (MowController)  : detection du prompt, appel de la coupe, rotation des roues. Du visuel et de l'intention.
-- L'herbe est CLIENTE (chaque joueur fabrique la sienne), donc la coupe l'est aussi. Le jour ou une pelouse
-- tondue rapportera un cheque, c'est le SERVEUR qui comptera -- pas ces valeurs-la.

return {
	-- ===== LA TONDEUSE DANS LE MONDE =====
	-- Nom du Model pose dans Studio. Toute la detection part de la : pas de tag a maintenir en plus.
	MODEL_NAME = "Tondeuse",
	-- Part fixe qui sert de reference de position. JAMAIS GetPivot : le pivot d'un Model suit sa bounding box, donc
	-- ajouter la moindre part enfant (CutZone...) le decale et tous les calculs partent de travers.
	ROOT_NAME = "RootPart",
	-- Part posee sous le carter, creee par scripts/studio/CreerZoneDeCoupeTondeuse.lua. Sa POSITION dit ou on coupe,
	-- sa largeur donne le rayon. Absente, on retombe sur FALLBACK_* ci-dessous (le jeu tourne quand meme).
	CUT_ZONE_NAME = "CutZone",

	-- ===== PRISE =====
	-- Distance HORIZONTALE (studs) sous laquelle le prompt apparait. RADIALE, pas une box : colle a un bout de la
	-- tondeuse, une box laisse un angle mort et le prompt ne sort pas. C'est LE knob "detecter plus loin".
	DETECT_RADIUS = 8,
	PROMPT_KEY = "E",
	PROMPT_LABEL = "TAKE",
	PROMPT_TITLE = "MOWER",
	-- Hauteur d'AFFICHAGE du badge AU-DESSUS DU DESSUS de la machine. Le point d'ancrage est CALCULE par
	-- MowController (milieu en X/Z, sommet en Y, parts visibles seulement), donc il ne depend d'aucune orientation.
	--
	-- GARDER UN OFFSET PUREMENT VERTICAL. Il est exprime en repere MONDE, pas dans celui de la tondeuse : une
	-- composante X ou Z pousse le badge toujours vers le meme point cardinal, donc il se decale par rapport a la
	-- machine des qu'elle n'est pas posee dans le bon sens. C'est ce qui donnait l'impression que le badge
	-- "dependait de l'angle".
	--
	-- N'A RIEN A VOIR avec DETECT_RADIUS : monter celui-ci ne fait pas detecter plus loin, il leve juste le badge.
	PROMPT_OFFSET = Vector3.new(0, 1.5, 0),
	-- Deux prises ne peuvent pas s'enchainer plus vite que ca (secondes). Le meme geste part sinon en double quand
	-- la touche ET le bouton tactile tirent tous les deux.
	ACTION_DEBOUNCE = 0.35,

	-- ===== REVELATION =====
	-- Touche MAINTENUE qui allume en neon tout ce qui reste a tondre (le rendu vit dans GrassZoneConfigs).
	-- Maintenue et non bascule : on jette un oeil, on ne joue pas dedans. Un mode qu'on peut laisser allume
	-- deviendrait le mode NORMAL, et la pelouse ne serait plus jamais regardee pour elle-meme.
	HIGHLIGHT_ACTION = "LeafiaMowHighlight",
	-- La camera RECULE et se RESSERRE pendant la revelation : on prend du recul pour evaluer le travail. Les deux
	-- ensemble, c'est important -- reculer seul eloigne, resserrer seul montre MOINS. Combines, on voit plus de
	-- pelouse ET la perspective s'aplatit, ce qui rend les bandes oubliees lisibles.
	-- Le lissage vient de CameraEffects, il n'y a rien a animer ici.
	HIGHLIGHT_ZOOM = 9, -- studs de recul. 0 = la camera ne bouge pas
	HIGHLIGHT_FOV = -10, -- degres retires au champ de vision. Negatif = la vue se resserre
	-- Distance MAX joueur <-> tondeuse acceptee par le SERVEUR a la prise. Anti-triche : le client demande, le
	-- serveur verifie. Volontairement plus large que DETECT_RADIUS, pour tolerer la latence.
	MAX_GRAB_DIST = 20,

	-- ===== PORTAGE =====
	-- Offset de la tondeuse par rapport au HRP du porteur. On la POUSSE : elle vit DEVANT, posee au sol.
	-- FIXE et non capture a la prise : le besoin n'est pas de garder la pose du sol, c'est qu'elle revienne
	-- toujours pareil devant le joueur. Capturer l'offset ferait porter de travers une tondeuse posee de travers.
	--
	-- LES DEUX DISTANCES SONT CALCULEES, PAS REGLEES. Les valeurs a l'oeil (3.2 puis 4.6) etaient fausses parce
	-- qu'elles ignoraient la geometrie reelle du modele. MowService MESURE :
	--   - de combien la RootPart surplombe le point le plus BAS de la tondeuse -> elle se pose sur le sol ;
	--   - la distance RootPart -> Handle (le guidon) -> le joueur tombe toujours juste derriere le guidon.
	-- Changer la taille du modele ne demande donc plus AUCUN reglage ici.

	-- Espace entre le joueur et le GUIDON, en studs. Le seul bouton de distance qui reste : c'est du confort, pas
	-- de la geometrie. Trop petit, le guidon rentre dans le personnage ; trop grand, il pousse dans le vide.
	-- Recul utilise SI la CutZone est absente : sans elle on ne sait pas de quel cote regarde la machine, donc
	-- pas de quel cote la depasser. Valeur de secours uniquement, le cas normal est MESURE.
	CARRY_FALLBACK_BACK = 2.5,
	CARRY_GAP = 1.6,
	-- De combien la tondeuse FLOTTE au-dessus du sol, en studs. Petit expres : elle doit EFFLEURER l'herbe, pas
	-- leviter. Zero pile ferait mordre le carter dans le sol au moindre relief.
	CARRY_CLEARANCE = 0.08,
	-- Rotation autour de la verticale, en DEGRES, pour que l'AVANT de la tondeuse pointe loin du joueur.
	-- A REGLER A L'OEIL : le sens depend de l'orientation du modele dans Studio, il ne se deduit pas.
	CARRY_YAW = 0,
	-- Affiche les mesures du portage dans la console a chaque prise. A couper une fois le placement valide :
	-- un print par prise finit par noyer les vrais messages.
	CARRY_DEBUG = true,

	-- ===== APPROCHE =====
	-- Le joueur MARCHE jusqu'au guidon avant de prendre la tondeuse, au lieu que la machine lui saute dessus.
	--
	-- Pas de PathfindingService : on parle de quelques studs dans un jardin ouvert, `Humanoid:MoveTo` suffit. Un
	-- vrai chemin calcule serait plus fragile (bloque, sol irregulier, autre joueur) pour un gain nul a cette
	-- distance. A revoir SI un jour la tondeuse se prend derriere un obstacle.
	APPROACH_ENABLED = true,
	-- Si le joueur est DEJA a moins de ca du point de prise, on ne fabrique aucun deplacement : on prend, point.
	-- Regle apprise sur l'echelle -- un systeme de marche forcee y avait ete construit pour rien, l'arrivee tirait
	-- des la premiere image.
	APPROACH_SKIP_DIST = 1.2,
	-- Au-dela, on prend quand meme : mieux vaut une prise un peu de travers qu'un joueur bloque parce qu'un caillou
	-- lui barre le chemin.
	APPROACH_TIMEOUT = 2.5,
	-- Duree du pivot vers la tondeuse une fois arrive. Le joueur arrive DOS a elle s'il venait de l'avant : sans ce
	-- pivot, la soudure la reposerait de l'autre cote.
	APPROACH_TURN_TIME = 0.18,

	-- ===== POSE DE MAINTIEN =====
	-- Le joueur attrape le guidon des qu'il prend la tondeuse, et TIENT la pose tant qu'il pousse.
	--
	-- L'ID vit ICI, en CODE, et pas dans une Instance Animation rangee en ReplicatedStorage : Rojo synchronise le
	-- code dans TOUTES les places, les Instances non (Animations est en $ignoreUnknownInstances, il se recopie a la
	-- main place par place). Meme raison que AmbientAnimConfigs.
	HOLD_ANIM_ID = "rbxassetid://85076820474751",
	-- Marqueur pose a la fin de l'animation : les mains sont sur le guidon. On FIGE la pose la (vitesse 0) au lieu
	-- de laisser la piste finir. Lu par GetMarkerReachedSignal PENDANT la lecture (local, aucun appel reseau) et
	-- jamais par GetKeyframeSequenceAsync, qui rate parfois au boot et tue la feature pour toute la session.
	-- Plus tard, c'est de ce marqueur que partira le demarrage moteur (tirer la corde).
	HOLD_READY_EVENT = "ReadyToLaunch",
	-- Fondu d'entree / de sortie de la pose, en secondes. Court : prendre une tondeuse est un geste franc.
	HOLD_FADE = 0.15,

	-- ===== VITESSE =====
	-- Le joueur ne part pas a fond : il pousse doucement, puis prend de la vitesse tant qu'il avance. S'il s'arrete,
	-- il repart lentement. C'est ce qui fait sentir le POIDS de la machine -- une vitesse constante ne raconte rien.
	--
	-- ATTENTION au piege deja paye sur la taille : une vitesse peut etre MULTIPLIEE en aval (un pas glisse, une
	-- animation qui module). Ces chiffres sont ceux du Humanoid, pas forcement ceux qu'on RESSENT. Regler a l'oeil.
	-- A CALER SUR LA MARCHE DU JEU, pas dans le vide. Reperes de CharacterConfigs : WALK_SPEED = 10,
	-- SPRINT_SPEED = 17. Les premieres valeurs (13 -> 20) etaient au-dessus des DEUX : le joueur poussait sa
	-- tondeuse plus vite qu'il ne court, ce qui se lisait comme une course, pas comme un travail.
	-- Une tondeuse est LOURDE : on demarre plus lentement qu'a pied, et meme a plein regime on ne sprinte pas.
	SPEED_MIN = 8, -- au demarrage et apres chaque arret. Sous la marche : la machine resiste
	SPEED_MAX = 13, -- plafond. Au-dessus de la marche, bien en dessous du sprint
	-- Studs/s gagnes par seconde de marche. A REGLER AVEC L'ECART, pas tout seul : sur 5 studs d'ecart (8 -> 13),
	-- 1.5 met environ 3.3 s a atteindre le plein regime. C'est CETTE duree qu'on ressent, pas le chiffre.
	-- Plus haut = monte plus vite, et l'effet de montee en regime disparait.
	SPEED_RAMP_UP = 1.5,
	SPEED_RAMP_DOWN = 14, -- redescente a l'arret. VIVE expres : repartir doit se meriter, ralentir non
	-- En dessous de cette vitesse REELLE (studs/s), on considere que le joueur est a l'arret et le regime retombe.
	-- Se mesure sur le deplacement reel, pas sur l'intention : pousser contre un mur ne doit pas monter le regime.
	SPEED_MOVE_EPSILON = 1.5,

	-- ===== ANIMATIONS DE LA MACHINE =====
	-- Jouees sur l'Animator de la TONDEUSE (pas celui du joueur), cote serveur donc vues par tous.
	-- Les IDs vivent ICI et pas dans des Instances : Rojo ne synchronise pas ReplicatedStorage.Animations vers la
	-- place tuto. Meme raison que HOLD_ANIM_ID.
	--
	-- MOTEUR : boucle simple, tourne tant que la tondeuse est poussee.
	MOTOR_ANIM_ID = "rbxassetid://110288806032199",
	-- LEVIER d'accelerateur : sa position raconte le REGIME. On ne la laisse pas jouer -- on pilote sa TimePosition
	-- a la main, de 0 (ralenti) a sa derniere image (plein regime), selon la vitesse du moment. Meme mecanique que
	-- la visee haut/bas du taille-haie : une animation dont on ne lit qu'une IMAGE, jamais le defilement.
	LEVER_ANIM_ID = "rbxassetid://139358126737662",

	-- ===== COUPE =====
	-- Rayon de coupe utilise SI la part CutZone est absente (elle donne sinon le sien, moitie de sa largeur).
	FALLBACK_RADIUS = 2.2,
	-- Point de coupe de secours, devant la racine, quand CutZone n'existe pas encore.
	FALLBACK_FORWARD = 1.6,

	-- ===== ROUES =====
	-- Les roues tournent EN CODE, pas par animation : une animation joue a vitesse fixe, donc la roue patinerait
	-- des que le joueur change d'allure. Ici l'angle vient de la distance REELLEMENT parcourue, elle colle au sol.
	-- Corollaire : ces joints ne doivent etre cles dans AUCUNE animation, sinon deux ecrivains sur le meme joint.
	WHEEL_MOTORS = { "BackWheel", "FrontWheel" },
	-- Sens de rotation. Si les roues tournent a l'envers, mettre -1. Se voit a l'ecran, ne se deduit pas.
	WHEEL_DIRECTION = 1,
	-- AXE de rotation dans le repere du joint : "X", "Y" ou "Z". Depend de la facon dont le rig a ete monte, donc
	-- il ne se DEDUIT pas : si la roue tourne sur le mauvais axe (elle roule de travers, ou elle pivote a plat),
	-- essayer les deux autres. C'est l'ecran qui tranche, pas le raisonnement.
	WHEEL_AXIS = "X",
	-- Rayon de roue de secours (studs) si on n'arrive pas a le lire sur la part. Sinon il est MESURE sur la roue.
	WHEEL_RADIUS_FALLBACK = 0.6,
}
