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
	-- Part sur laquelle le badge est ACCROCHE. Rien a voir avec la DETECTION, qui reste sur la RootPart (une part
	-- fixe, qui ne bouge pas quand on ajoute des enfants au modele). Ici c'est purement OU on le voit.
	-- "Handle" = le guidon, a hauteur des mains : c'est la qu'on lit "prendre". La RootPart, elle, est a l'avant-bas
	-- du carter, donc le badge y flottait devant la machine.
	-- Introuvable -> on retombe sur la RootPart, sans rien casser.
	PROMPT_PART_NAME = "Handle",
	-- Hauteur d'AFFICHAGE du badge au-dessus de la part d'ancrage. N'A RIEN A VOIR avec DETECT_RADIUS : monter
	-- celui-ci ne fait pas detecter plus loin, il ne fait que lever le badge.
	-- Petit depuis que l'ancrage est le guidon : il est deja a bonne hauteur, il n'y a plus a rattraper.
	PROMPT_OFFSET = Vector3.new(0, 5, 3),
	-- Deux prises ne peuvent pas s'enchainer plus vite que ca (secondes). Le meme geste part sinon en double quand
	-- la touche ET le bouton tactile tirent tous les deux.
	ACTION_DEBOUNCE = 0.35,

	-- ===== REVELATION =====
	-- Touche MAINTENUE qui allume en neon tout ce qui reste a tondre (le rendu vit dans GrassZoneConfigs).
	-- Maintenue et non bascule : on jette un oeil, on ne joue pas dedans. Un mode qu'on peut laisser allume
	-- deviendrait le mode NORMAL, et la pelouse ne serait plus jamais regardee pour elle-meme.
	HIGHLIGHT_ACTION = "LeafiaMowHighlight",
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
	-- Part qui sert de GUIDON pour le calcul de distance. Souvent la meme que PROMPT_PART_NAME, mais ce sont
	-- deux besoins differents : l'un dit ou AFFICHER le badge, l'autre ou se tient la MAIN du joueur. Les
	-- confondre marcherait aujourd'hui et mentirait le jour ou l'un des deux bouge.
	HANDLE_NAME = "Handle",
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
