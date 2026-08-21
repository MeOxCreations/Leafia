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

	-- ===== CONDUITE =====
	-- Une tondeuse a du POIDS : on ne pivote pas sur place avec, on decrit un ARC. Par defaut le personnage Roblox
	-- s'oriente INSTANTANEMENT vers la direction demandee (AutoRotate), ce qui donne un demi-tour sec sur un point.
	--
	-- On coupe donc AutoRotate pendant le portage, et on separe les deux commandes : avant / arriere AVANCE le long
	-- du cap, gauche / droite BRAQUE et rien d'autre. Appuyer sur la seule touche de cote ne fait pas avancer la
	-- machine d'un pouce -- on redresse, comme sur une vraie tondeuse a l'arret.
	-- Comme on ne se deplace JAMAIS lateralement, la trajectoire ne peut que se courber : c'est ca, l'arc.
	-- Le ballant de la machine et la pose des bras suivent gratuitement : ils se calculent deja sur le cap.
	STEER_ENABLED = true,
	-- Vitesse de rotation MAXIMALE, en degres par seconde. C'est LE bouton du poids ressenti.
	-- 120 = un quart de tour en 0.75 s. Plus BAS = plus lourd, plus large. Trop bas et on ne peut plus longer un
	-- massif de fleurs sans le raser.
	STEER_TURN_RATE = 120,
	-- En dessous de cette intensite d'input, on considere que le joueur ne demande rien : le cap ne bouge plus.
	-- Sans ce seuil, le bruit d'un joystick ferait tourner la tondeuse a l'arret.
	STEER_INPUT_EPSILON = 0.05,
	-- Braquage inverse ? Mettre true. Le sens depend de la convention d'angle de Roblox : il ne se DEDUIT pas,
	-- il se voit. Si appuyer a droite fait tourner a gauche, c'est ce reglage et rien d'autre.
	STEER_INVERT = false,
	-- En dessous de cette poussee avant / arriere, on considere que le joueur est A L'ARRET. Le corps ne tourne
	-- alors PLUS : c'est la MACHINE qui se braque, et les bras de l'animation racontent l'effort.
	-- On ne fait pas pivoter une tondeuse sur un point sans rouler -- on l'oriente, et le corps reste face au travail.
	STEER_MOVE_EPSILON = 0.15,
	-- Poussee angulaire donnee a la machine quand on braque A L'ARRET, en radians par seconde a fond de course.
	-- Elle est RAPPELEE par SWING_RECOVER : les deux s'equilibrent, donc tenir la touche amene la tondeuse a un
	-- angle stable au lieu de la faire tourner sans fin. L'angle atteint vaut PIVOT_GAIN / SWING_RECOVER radians.
	-- Une valeur NEGATIVE retourne le sens du braquage sur place. Le sens ne se deduit pas : il a ete fixe a
	-- l'ecran (la premiere version partait du mauvais cote).
	PIVOT_GAIN = 2.6,
	-- RECUL DE CAMERA A LA VITESSE. La vue s'ecarte a mesure qu'on prend du regime : on voit venir la bande a
	-- tondre, et l'acceleration se RESSENT au lieu de se deviner au chiffre.
	-- S'ADDITIONNE au recul de la revelation : les deux passent par une seule valeur, sinon le dernier a ecrire
	-- ecraserait l'autre a chaque image.
	-- Studs de recul a PLEIN regime. 0 = effet coupe.
	DRIVE_ZOOM = 4,

	-- ===== DEBUG DE TRAJECTOIRE =====
	-- Des points poses devant la machine, qui dessinent la courbe QU'ELLE VA SUIVRE avec le braquage courant.
	-- Sert a REGLER la conduite a l'oeil au lieu de deviner : on voit tout de suite si l'arc est trop serre, trop
	-- mou, ou si le braquage part du mauvais cote.
	-- A COUPER une fois la conduite validee.
	STEER_DEBUG = true,
	STEER_DEBUG_POINTS = 14, -- nombre de points. Plus = courbe plus longue et plus lisible, un peu plus cher
	STEER_DEBUG_STEP = 0.09, -- secondes simulees entre deux points. Plus grand = on voit plus loin, moins precis
	STEER_DEBUG_SIZE = 0.35,
	STEER_DEBUG_COLOR = Color3.fromRGB(255, 210, 60),

	-- ===== POSE DE VIRAGE =====
	-- Les bras accompagnent le virage, comme quand on redresse une vraie tondeuse. L'animation n'est PAS jouee :
	-- elle est POSEE, comme le levier. Son MILIEU est la pose droite, un bout est le virage a gauche, l'autre a
	-- droite -- on ecrit donc une IMAGE, jamais un defilement.
	--
	-- Elle est pilotee par le BALLANT (voir plus bas) : deja signe, deja proportionnel au virage, et il revient
	-- tout seul a zero quand le joueur roule droit. Rien de nouveau a lisser.
	TURN_ANIM_ID = "rbxassetid://89239700900064",
	-- Ou se trouve la pose DROITE dans l'animation, en fraction de sa duree. 0.5 = au milieu.
	TURN_POSE_MIDDLE = 0.5,
	-- Les bras partent du mauvais cote ? Mettre true. Le sens depend de la convention d'angle de Roblox ET du sens
	-- dans lequel l'animation a ete faite : ca ne se DEDUIT pas, ca se voit a l'ecran.
	TURN_POSE_INVERT = false,
	-- AU-DESSUS de la pose du guidon (Action), sinon les deux clent les memes bras a priorite EGALE et Roblox en
	-- fait une MOYENNE au lieu de choisir -- on obtient une pose "presque bonne" qu'on croit mal animee.
	TURN_PRIORITY = Enum.AnimationPriority.Action2,

	-- ===== REGARD ARRIERE =====
	-- En marche arriere, le personnage tourne la tete pour voir ou il va. Comme dans la vraie vie -- et ca dit au
	-- joueur qu'il RECULE sans avoir a lire un indicateur.
	--
	-- POSEE et non jouee, comme le levier : sa TimePosition va de 0 (tete droite) a sa derniere image (tete
	-- tournee), et on la deplace. Une piste qu'on laisse defiler rejouerait le mouvement de tete en boucle.
	REVERSE_ANIM_ID = "rbxassetid://88225605983288",
	-- AU-DESSUS de la pose de virage (Action2), qui est deja au-dessus du guidon (Action). Trois poses sur le meme
	-- corps : a priorite EGALE Roblox en ferait une moyenne au lieu de choisir.
	REVERSE_PRIORITY = Enum.AnimationPriority.Action3,
	-- Vitesse a laquelle la tete se tourne, en fraction par seconde. BAS = mouvement lent et lourd.
	REVERSE_TURN_SPEED = 4,
	-- En dessous de cette vitesse de recul REELLE (studs/s), on considere qu'on ne recule pas. Evite que la tete
	-- parte en arriere sur un simple recul de la physique (une bosse, une pente, un autre joueur qui pousse).
	REVERSE_EPSILON = 1.5,

	-- ===== BALLANT =====
	-- Soudee RIGIDE, la tondeuse pivote a l'instant meme ou le joueur tourne : elle se lit comme un objet TENU, pas
	-- comme une machine qu'on POUSSE. Une vraie tondeuse a de l'inertie -- elle traine dans le virage, puis rattrape.
	--
	-- Le ballant fait pivoter la machine AUTOUR DU JOUEUR (le guidon reste dans les mains, le carter part de cote),
	-- pas autour d'elle-meme : c'est ce qui distingue un objet pousse d'un objet porte.
	--
	-- 0 = coupe, retour a la soudure rigide.
	-- Retard pris par degre de virage. Plus HAUT = elle traine plus. Au-dela de ~1 elle part en toupie.
	SWING_GAIN = 0.55,
	-- Vitesse a laquelle elle RATTRAPE le joueur, en fraction par seconde. Plus BAS = elle traine plus longtemps.
	-- Volontairement plus lent que la prise de retard : c'est l'ecart entre les deux qui se lit comme du poids.
	SWING_RECOVER = 6,
	-- Retard MAXIMAL, en degres. Sans ce plafond, une pirouette du joueur enverrait la tondeuse a 180 degres, et
	-- elle repasserait devant lui par l'autre cote.
	SWING_MAX = 28,

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
