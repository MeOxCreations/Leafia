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
	-- BOITE DE COLLISION. La SEULE part de la machine qui garde ses collisions une fois portee : c'est elle qui
	-- l'empeche de traverser les haies, les cloture et les portails.
	--
	-- Tout le reste est mis en CanCollide = false a la prise, et il le faut : une machine pleine de parts solides
	-- soudee au joueur se coince dans le decor et le fait sauter. Une seule boite, posee a la main dans Studio,
	-- donne une forme simple que la physique sait resoudre.
	--
	-- Elle est aussi ECARTEE de la mesure d'encombrement, comme la zone de coupe : c'est un volume logique, pas
	-- une piece de la machine. La compter fausserait la hauteur et le recul du portage.
	--
	-- ATTENTION : `CanQuery = false` n'a AUCUN effet tant que CanCollide est vrai (deja au journal). Cette boite
	-- reste donc vue par les raycasts -- a savoir si un systeme se met un jour a lancer des rayons depuis le
	-- joueur vers l'avant.
	HITBOX_NAME = "Hitbox",

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
	-- CONTOURNEMENT. Le point de prise est DERRIERE la machine : un joueur qui arrive par DEVANT marcherait droit
	-- dedans. On passe donc par un point de cote, a cette distance du centre de la tondeuse, avant de rejoindre le
	-- guidon -- ce qui decrit un arc naturel autour d'elle.
	-- A monter si le joueur frotte encore le carter en contournant.
	APPROACH_DETOUR = 4,

	-- ===== SONS =====
	-- Chemin du dossier dans SoundService. Le code ne connait QUE des noms : changer de sons ne demande de toucher
	-- qu'a ce bloc.
	--
	-- Les sons du taille-haie servaient d'emprunt en attendant ceux de la tondeuse.
	-- SI UN SON NE SORT PAS : la console dit le NOM et le DOSSIER exacts qu'elle a cherches, une fois par nom
	-- manquant. Pas besoin de deviner -- il suffit de comparer a l'arborescence de Studio.
	SOUND_FOLDER = { "Sounds", "Engins", "LawnMower" },
	-- Joue a chaque coup de corde qui RATE. Une fois, non bouclee.
	PULL_SOUND = "TryLaunchSound",
	-- Joue a la place du precedent sur le coup qui VA REUSSIR.
	--
	-- AU MOMENT DU TIRAGE, pas apres. C'est ce qui fait la difference entre "le moteur a demarre" et "je l'ai
	-- demarre" : l'oreille entend la prise pendant que le bras tire encore, donc elle l'attribue au geste. Joue
	-- une seconde plus tard, elle en ferait une consequence du hasard.
	-- Le serveur sait combien de coups il faut et combien ont ete donnes : il n'y a rien a deviner.
	-- (Nom ecrit tel qu'il est dans Studio, faute comprise -- il vaut mieux qu'il corresponde.)
	SUCCESS_SOUND = "SucessTryLaunchSound",
	-- Boucle du moteur, des qu'il a demarre et tant qu'on pousse.
	RUN_SOUND = "IdleLawnMowerSound",
	-- CHEVAUCHEMENT : de combien la boucle moteur demarre AVANT la fin du son de reussite, en secondes.
	--
	-- Sans ca, la boucle partait a l'instant meme ou le moteur prend -- c'est-a-dire par-dessus le son de
	-- reussite, qui devenait inaudible. On croyait qu'il ne jouait pas ; il jouait, il etait couvert.
	--
	-- Le faire demarrer AVANT la fin plutot qu'APRES est ce qui evite le TROU : deux sons colles bout a bout
	-- laissent un silence d'une image ou deux, et ce silence s'entend plus que la transition elle-meme.
	-- Monter si on entend encore une couture, descendre si le regime couvre trop tot la reussite.
	RUN_SOUND_OVERLAP = 0.4,
	-- HAUTEUR DE LA BOUCLE, aux DEUX BOUTS du regime. Le son passe de l'une a l'autre avec la vitesse, comme le
	-- levier monte dans son animation -- les deux racontent la meme chose.
	--
	-- Deux valeurs et pas "une base plus un ajout" : la version precedente ajoutait au ralenti une hauteur de 1
	-- PILE, cachee dans la formule. Le moteur ronflait donc a sa hauteur normale a l'arret, et rien dans la
	-- config ne montrait ce plancher ni ne permettait de le baisser.
	--
	-- Au ralenti il tourne DESSOUS : c'est ce qui fait entendre qu'il attend. Egaliser les deux = hauteur
	-- constante.
	RUN_PITCH_IDLE = 0.78,
	RUN_PITCH_FULL = 1.35,

	-- ===== DEMARRAGE =====
	-- Le joueur tire la corde avant de pousser. Jouee UNE fois a la prise ; la pose du guidon prend le relais quand
	-- elle se termine, et le MOTEUR ne demarre qu'a ce moment-la -- il tournait avant qu'on ait tire, ce qui n'a
	-- aucun sens.
	-- Vide = pas de demarrage, on enchaine directement sur la pose du guidon.
	START_ANIM_ID = "rbxassetid://88566815924193",
	-- MEME priorite que la pose du guidon : elles ne jouent jamais en meme temps, l'une remplace l'autre.
	START_PRIORITY = Enum.AnimationPriority.Action,
	-- Fondu d'entree. La sortie est geree par le fondu de la pose qui prend le relais.
	START_FADE = 0.1,
	-- La piste est FIGEE a sa premiere image des la prise : le personnage tient la corde, pret a tirer. C'est le
	-- CLIC du joueur qui la relance a vitesse normale -- on ne demarre pas une tondeuse en la regardant.
	-- Meme mecanique que le lanceur du taille-haie (voir ToolStartService : Ready puis Pulling partagent la meme
	-- piste, seule la vitesse change).
	START_ACTION = "LeafiaMowPull",
	-- L'AVANT SE LEVE quand on tire la corde : la machine se cabre sous l'a-coup, puis retombe. C'est ce petit
	-- sursaut qui donne de la FORCE au geste -- sans lui, tirer la corde n'agit que sur le personnage.
	-- Angle de POINTE atteint, en degres (approximatif : c'est un ressort, pas une cible). Divise par trois
	-- depuis 12 -- a l'ecran la machine se cabrait comme si on la soulevait du sol.
	-- NEGATIF si c'est l'arriere qui se leve chez toi : le sens depend du montage du rig, il ne se deduit pas.
	-- NOMBRE DE TIRAGES avant que le moteur prenne, tire au sort dans cet intervalle a chaque prise.
	-- Un moteur qui demarre au premier coup a chaque fois se lit comme un interrupteur. Qu'il tousse une ou deux
	-- fois avant de partir, c'est ce qui le rend vivant -- et ca rend le demarrage reussi SATISFAISANT.
	-- MIN == MAX donne un nombre fixe.
	PULL_TRIES_MIN = 2,
	PULL_TRIES_MAX = 3,

	PULL_LIFT = 4,
	-- DELAI avant le cabrage, en secondes, compte depuis le clic. Le geste ne tire pas la corde a la premiere
	-- image : la machine ne doit donc pas broncher tant que le bras n'a pas tire. A REGLER SUR TON ANIMATION,
	-- en regardant a quel instant la main part en arriere.
	-- (Le jour ou l'animation portera un MARQUEUR, s'y brancher plutot que de compter un delai : un delai fige se
	-- INSTANT DU COUP DE CORDE, lu dans l'ANIMATION. C'est un evenement pose sur la piste de tirage, a l'image ou
	-- le bras part en arriere.
	--
	-- REMPLACE UN DELAI DEVINE (0.35 s). Un delai en secondes suppose qu'on connait la cadence du geste, alors
	-- qu'elle vit dans l'animation : retoucher celle-ci decalait tout, sans que rien ne le signale. Le marqueur,
	-- lui, suit l'animation quoi qu'on lui fasse.
	--
	-- On passe par `GetMarkerReachedSignal` pendant la lecture, et JAMAIS par `GetKeyframeSequenceAsync` : le
	-- second est un appel RESEAU qui, s'il rate au boot, tue la feature pour TOUTE la session (deja au journal).
	PULL_EVENT = "TryLaunchEvent",
	-- Vitesse de retombee, en fraction par seconde. HAUTE : un a-coup doit etre sec, pas une houle.
	-- RESSORT AMORTI, pas un decalage qui retombe. La premiere version POSAIT l'angle d'un coup, en une image :
	-- la montee etait instantanee et se lisait comme un a-coup brutal. Ici la machine se souleve, freine, revient,
	-- avec un leger depassement -- c'est ce depassement qui fait "lourd" au lieu de "casse".
	-- Meme mecanique que la plongee d'atterrissage de CameraEffects, pour la meme raison.
	-- RAIDEUR : plus haut = mouvement plus rapide et plus sec.
	PULL_LIFT_STIFFNESS = 90,
	-- AMORTISSEMENT : plus haut = moins de rebond. Trop bas et la machine oscille comme un ressort de dessin anime.
	PULL_LIFT_DAMPING = 11,
	-- Attribut pose sur la tondeuse quand le moteur TOURNE. Lu par le client : une machine a l'arret ne coupe rien.
	RUNNING_ATTRIBUTE = "LeafiaMowerRunning",

	-- ===== POIGNEE DU LANCEUR =====
	-- Pendant le demarrage, la poignee QUITTE la machine pour suivre la main qui tire. Le Beam tendu entre
	-- A0Launcher (sur la tondeuse) et A1Launcher (sur la poignee) s'etire alors tout seul : on ne dessine pas la
	-- corde, on deplace ses deux bouts. Meme montage que le taille-haie.
	LAUNCHER_PART = "Launcher",
	-- Attachment PORTE PAR LA POIGNEE. Il vient se coller sur celui de la main, axes alignes -- c'est lui qui
	-- decide de l'angle de la poignee dans la main, pas un offset regle a l'oeil.
	LAUNCHER_ATTACHMENT = "A1Launcher",
	-- Main qui tire, et son attachment de prise (R15).
	PULL_HAND = "RightHand",
	PULL_HAND_ATTACHMENT = "RightGripAttachment",

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
	SPEED_MIN = 6, -- au demarrage et apres chaque arret. Bien SOUS la marche : la machine resiste
	-- Plafond cale sur la MARCHE du jeu (10), pas au-dessus. Pousser une tondeuse ne doit jamais aller plus vite
	-- que marcher les mains vides : c'est ce qui donne le poids, et ca laisse la marche libre comme reference.
	SPEED_MAX = 10,
	-- Studs/s gagnes par seconde de marche. A REGLER AVEC L'ECART, pas tout seul : sur 5 studs d'ecart (8 -> 13),
	-- Sur l'ecart actuel (6 -> 10, soit 4), 1.5 met environ 2.7 s a atteindre le plein regime. C'est CETTE
	-- duree qu'on ressent, pas le chiffre : reduire l'ecart raccourcit la montee sans toucher a la rampe.
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

	-- ===== MARQUEUR DE DIRECTION =====
	-- Un repere pose sur la machine. Chemin sous `ReplicatedStorage.Assets` : le mesh vit dans Studio, et Rojo ne
	-- synchronise pas les Assets -- l'y chercher par son chemin evite de le recopier en code.
	MARKER_PATH = { "Contents", "MarkerDirection" },
	-- DECALAGE EN PLUS du milieu de la machine, dans SON repere : X = cote, Y = hauteur, Z = arriere (donc -Z
	-- vers l'avant). Le milieu, lui, n'est pas ici : il est MESURE au premier affichage.
	--
	-- Y NEGATIF le fait DESCENDRE. Le milieu mesure tombe a mi-hauteur du carter, ce qui est bien trop haut pour
	-- une fleche au sol : on redescend d'a peu pres la demi-hauteur de la machine.
	MARKER_OFFSET = Vector3.new(0, -3.5, 0),
	-- ORIENTATION, en degres autour de la verticale. 180 = demi-tour.
	--
	-- Le sens ne se DEDUIT pas : il depend de la facon dont le mesh a ete modelise, pas d'un calcul. Ca se voit a
	-- l'ecran, et c'est la seule facon de le savoir.
	MARKER_YAW = 180,
	-- TAILLE, en multiple de celle du mesh d'origine. Appliquee UNE FOIS a la creation : un mesh qu'on
	-- redimensionne en jeu CLIGNOTE quand sa RenderFidelity est `Automatic` (Roblox echange le maillage selon la
	-- taille a l'ecran). Fixe, il ne clignote pas.
	MARKER_SCALE = 1.8,

	-- ===== LA FLECHE DEVANCE LE VIRAGE =====
	-- Elle tourne PLUS que la machine, et plus TOT : on braque, elle part tout de suite, et la tondeuse la
	-- rattrape. C'est ce decalage qui la rend utile -- une fleche calee sur le cap ne dirait rien de plus que le
	-- nez de la machine, qu'on voit deja.
	--
	-- Angle atteint a fond de braquage, en degres. NEGATIF pour partir de l'autre cote : le sens depend de la
	-- convention d'angle et de la facon dont le mesh est modelise, donc il se voit a l'ecran, il ne se deduit pas.
	MARKER_LEAD_ANGLE = 55,
	-- Vitesse a laquelle elle rejoint cet angle, en fraction par seconde. HAUTE : c'est une INTENTION qu'on
	-- montre, et une intention est immediate. Trop basse, la fleche arrive apres la machine et l'effet s'inverse.
	MARKER_LEAD_SPEED = 8,
	-- RAYON DE L'ORBITE, en studs. La fleche ne se contente pas de pivoter : elle TOURNE AUTOUR de la machine, ce
	-- qui la fait sortir du cote ou l'on va.
	-- A zero elle pivote sur place -- utile pour regler l'angle seul, sans le deplacement.
	MARKER_RADIUS = 2.5,

	-- ===== CONDUITE =====
	-- (Le seuil "le joueur demande d'avancer" n'est PAS ici : c'est STEER_MOVE_EPSILON, plus bas, deja utilise
	-- pour la meme question cote client. Un second seuil finirait par le contredire.)
	-- Une tondeuse a du POIDS : on ne pivote pas sur place avec, on decrit un ARC. Par defaut le personnage Roblox
	-- s'oriente INSTANTANEMENT vers la direction demandee (AutoRotate), ce qui donne un demi-tour sec sur un point.
	--
	-- On coupe donc AutoRotate pendant le portage, et on separe les deux commandes : avant / arriere AVANCE le long
	-- du cap, gauche / droite BRAQUE et rien d'autre. Appuyer sur la seule touche de cote ne fait pas avancer la
	-- machine d'un pouce -- on redresse, comme sur une vraie tondeuse a l'arret.
	-- Comme on ne se deplace JAMAIS lateralement, la trajectoire ne peut que se courber : c'est ca, l'arc.
	-- Le ballant de la machine et la pose des bras suivent gratuitement : ils se calculent deja sur le cap.
	STEER_ENABLED = true,
	-- RAYON DE BRAQUAGE A FOND, en studs. C'EST LE REGLAGE CENTRAL DE LA CONDUITE.
	--
	-- On ne regle plus une VITESSE DE ROTATION mais un RAYON, et ca change tout : c'est ce qui fait la difference
	-- entre une machine et une tourelle.
	--
	-- Avec une vitesse de rotation fixe, la machine tourne AUTANT par seconde qu'elle roule vite ou lentement.
	-- Resultat : a l'arret ou au pas, le moindre appui la fait pivoter beaucoup trop -- on sur-corrige, on
	-- zigzague, et on n'arrive pas a viser une bande droite. C'est ce que le joueur decrivait comme "trop vite,
	-- trop sec, stressant".
	--
	-- Avec un rayon, la rotation est proportionnelle a la DISTANCE parcourue, comme sur une vraie voiture : a fond
	-- de braquage, la machine decrit toujours le meme cercle, qu'elle aille vite ou doucement. Elle devient donc
	-- PREVISIBLE -- on sait ou elle va avant d'y aller, et c'est ca qui enleve le stress.
	--
	-- Plus PETIT = elle tourne court (nerveux, peut vite redevenir stressant). Plus GRAND = elle est lourde, il faut
	-- manoeuvrer pour se retourner.
	-- 8 -> 6 : a 8 studs l'arc etait trop large, la machine mettait trop de distance a se retourner en bout de
	-- bande. A 10 studs/s ca fait passer le braquage de 72 a 95 degres par seconde.
	STEER_RADIUS = 8,
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
	-- BRAQUER SEUL FAIT AVANCER, doucement. On ne tourne pas une tondeuse sur un point : on la fait rouler juste
	-- assez pour qu'elle pivote. Le corps tourne alors AUSSI -- c'est un vrai debut de virage, pas un ajustement.
	--
	-- En studs par seconde. Repere : la marche du jeu est a 10 studs/s. C'est une avance de MANOEUVRE, pas un
	-- deplacement.
	-- 0 = on revient au comportement d'avant : le corps reste fige et seule la machine pivote.
	--
	-- C'EST AUSSI LE BOUTON "SE REORIENTER SUR PLACE EST TROP LENT". La rotation vient de la distance parcourue :
	-- braquer sans avancer ne fait donc tourner qu'a la vitesse de ce crawl. A 2 studs/s et rayon 8, un quart de
	-- tour prenait plus de six secondes -- le joueur avait l'impression que la machine ne repondait pas.
	-- 2 -> 4, avec le rayon passe a 6 : environ 38 degres par seconde, soit un quart de tour en 2.4 s.
	STEER_CRAWL = 4,
	-- (Il n'y a plus de vitesse de rotation SEPAREE pour la manoeuvre. Avec un rayon, elle sort toute seule : en
	-- braquant a l'arret la machine avance de STEER_CRAWL, donc elle tourne d'autant -- lentement, puisqu'elle
	-- roule lentement. Un reglage de moins, et deux cas qui ne peuvent plus se contredire.)
	-- (Le braquage a l'arret n'a plus de reglage propre : la machine se braque desormais par le MEME chemin que la
	-- traine en virage -- l'input pilote directement l'angle, voir SWING_ANGLE. Un seul mecanisme, un seul bouton,
	-- et les deux cas ne peuvent plus se contredire.)
	-- RECUL DE CAMERA A LA VITESSE. La vue s'ecarte a mesure qu'on prend du regime : on voit venir la bande a
	-- tondre, et l'acceleration se RESSENT au lieu de se deviner au chiffre.
	-- S'ADDITIONNE au recul de la revelation : les deux passent par une seule valeur, sinon le dernier a ecrire
	-- ecraserait l'autre a chaque image.
	-- Studs de recul a PLEIN regime. 0 = effet coupe.
	-- ===== CAMERA DU DEMARRAGE (le tirage de corde) =====
	-- Pendant qu'on tire la corde, la camera passe DEVANT la machine, un peu de cote, et regarde le joueur. Le
	-- demarrage est le seul moment ou le joueur ne fait qu'une chose : autant la montrer. En vue de conduite on
	-- est derriere lui et on ne voit rien du geste.
	PULL_CAM_ENABLED = true,
	-- Distance DEVANT le joueur, en studs. FIXE : le plan se pose et ne bouge plus.
	--
	-- Il a existe un recul lent et continu pendant toute la scene, cense lui donner de l'ampleur. Retire : une
	-- camera qui derive en permanence pendant qu'on attend de pouvoir agir est PENIBLE, et ca se remarque bien
	-- plus qu'un plan fixe. Le mouvement, ici, c'est le geste du joueur -- pas la camera.
	-- 13 : assez loin pour tenir le joueur ET la machine dans le cadre. C'est une vue D'ENSEMBLE -- on regarde
	-- quelqu'un demarrer une tondeuse, pas un gros plan sur une main.
	-- HISTORIQUE pour ne pas refaire le tour : 9 (trop pres, on ne voyait pas la scene), 20 (trop loin, le joueur
	-- devenait une silhouette), 10, puis 13.
	PULL_CAM_FORWARD = 13,
	-- (Il y a eu une SECOUSSE de camera a chaque coup de corde. Retiree : elle attirait l'attention sur la camera
	-- au lieu du geste. La machine qui se cabre et le moteur qui tousse racontent deja le tirage, et eux sont dans
	-- la scene -- une camera qui tremble est un commentaire, pas un evenement.)
	-- INTENSITE DU VIGNETTAGE pendant la scene de demarrage, de 0 a 1. Il est eteint le reste du temps : un
	-- vignettage permanent ne dit plus rien au bout d'une minute, c'est son ARRIVEE qui resserre l'attention.
	PULL_CAM_VIGNETTE = 1,
	-- Decalage LATERAL. Le SIGNE decide du cote, et il ne se DEDUIT pas : si la camera se pose du mauvais cote,
	-- mettre -6. C'est de la famille des sens qu'on ne tranche qu'a l'ecran.
	PULL_CAM_SIDE = 6,
	-- Hauteur de l'oeil, en studs. Descendue de 3.2 : une camera au-dessus du joueur regarde le sol et ecrase la
	-- silhouette. Plus BAS que PULL_CAM_LOOK_HEIGHT, elle regarde legerement VERS LE HAUT -- c'est ce qui rend un
	-- personnage imposant, et un demarrage de moteur merite ce cadrage-la.
	PULL_CAM_HEIGHT = 1.6,
	PULL_CAM_LOOK_HEIGHT = 2.2, -- hauteur du point VISE sur le joueur (vers le torse, pas les pieds)
	-- Duree de l'arrivee et du retour. L'arrivee part de la vue de jeu EXACTE et le retour y revient : aucun saut
	-- ni au debut ni a la fin.
	-- HISTORIQUE, pour ne pas refaire le tour : 0.7 -> 0.42 -> 0.22. A chaque fois le meme retour, "c'est lent,
	-- c'est stressant". Une camera qui se DEPLACE pendant qu'on attend de pouvoir agir se subit ; on veut arriver,
	-- pas voyager. Le rebond de PULL_CAM_EASING fait le reste du travail : meme tres court, il ne claque pas.
	--
	-- Si ca redevenait trop sec, remonter par petits pas (0.26, 0.30), jamais d'un coup a l'ancienne valeur.
	PULL_CAM_IN_TIME = 0.22,
	-- LE RETOUR EST BIEN PLUS LENT QUE L'ARRIVEE, et ce n'est pas un oubli : les deux ne font pas le meme travail.
	--
	-- On ARRIVE parce qu'on veut y etre : tout ce qui traine avant de pouvoir agir se subit. On REPART parce qu'on
	-- rend la main au joueur, et une vue qui claque derriere lui donne l'impression d'avoir rate quelque chose.
	-- Monte de 0.2 : a cette vitesse la camera SAUTAIT derriere le joueur au lieu d'y revenir.
	--
	-- Meme asymetrie que le volet du rideau de chargement : couvrir vite (ca cache), decouvrir lentement (ca
	-- montre).
	PULL_CAM_OUT_TIME = 0.6,
	-- COURBE de l'arrivee et du retour. `Quad` en sortie : ca part franc et ca se pose, sans rien de plus.
	--
	-- `Back` a ete essaye : il DEPASSE la cible puis revient, ce qui donne le rebond du reste de l'interface.
	-- Retire. Un rebond va bien a un bouton qu'on presse -- c'est une reponse a un appui. Sur une camera, le
	-- depassement se lit comme une erreur de visee, et l'oeil le suit au lieu de suivre la scene.
	PULL_CAM_EASING = Enum.EasingStyle.Quad,
	-- RECUL DE CHAMP pendant le tirage, en degres ajoutes. Positif = la vue s'ELARGIT, donc le sujet parait
	-- s'eloigner : c'est le "recul" lent demande. Il se pose par la meme valeur unique que le recul de la
	-- revelation (voir applyCameraRig), sinon les deux s'ecraseraient a tour de role.
	PULL_CAM_FOV = 12,

	DRIVE_ZOOM = 4,

	-- RALENTISSEMENT EN VIRAGE. Fraction de vitesse PERDUE a fond de braquage. 0 = aucun ralentissement, 0.5 =
	-- moitie moins vite.
	--
	-- A ZERO : freiner pour tourner semblait "naturel" en theorie, ca se joue mal. On sent une machine qui MOLLIT
	-- des qu'on braque, alors que le geste central du jeu est de tondre en enchainant les virages -- donc on passe
	-- son temps a subir ce frein. Le ressenti a l'ecran a tranche contre le raisonnement.
	TURN_SLOWDOWN = 0,

	-- ===== DEBUG DE TRAJECTOIRE =====
	-- Des points poses devant la machine, qui dessinent la courbe QU'ELLE VA SUIVRE avec le braquage courant.
	-- Sert a REGLER la conduite a l'oeil au lieu de deviner : on voit tout de suite si l'arc est trop serre, trop
	-- mou, ou si le braquage part du mauvais cote.
	-- A COUPER une fois la conduite validee.
	STEER_DEBUG = false,
	-- DIAGNOSTIC D'INPUT. Affiche deux fois par seconde ce que la conduite RECOIT vraiment : le vecteur de
	-- deplacement, la vitesse de marche, et si le moteur tourne.
	--
	-- Sert a trancher une question qu'on ne peut pas trancher en lisant le code : quand la machine ne bouge pas,
	-- est-ce que l'input n'arrive pas (vecteur nul), que le moteur n'est pas vu comme demarre, ou que la vitesse
	-- est a zero ? Les trois donnent le meme symptome a l'ecran et se corrigent a trois endroits differents.
	-- A REPASSER A FALSE une fois la question reglee : ca imprime en continu.
	STEER_DEBUG_INPUT = false,
	STEER_DEBUG_POINTS = 14, -- nombre de points. Plus = courbe plus longue et plus lisible, un peu plus cher
	STEER_DEBUG_STEP = 0.09, -- secondes simulees entre deux points. Plus grand = on voit plus loin, moins precis
	STEER_DEBUG_SIZE = 0.35,
	STEER_DEBUG_COLOR = Color3.fromRGB(255, 210, 60),

	-- ===== POSE DE VIRAGE =====
	-- LE PERSONNAGE SE FAIT EMBARQUER. Quand la machine avance, il se penche en arriere, bras tendus -- comme si
	-- elle allait trop vite pour lui. C'est une blague, pas une pose realiste, et c'est voulu.
	--
	-- L'animation n'est PAS jouee : elle est POSEE, comme le levier et le regard arriere. Sa premiere image est
	-- le repos, sa DERNIERE est la pose complete -- on ecrit une IMAGE, jamais un defilement.
	--
	-- C'est ce qui donne gratuitement le "jouer a l'envers quand on s'arrete" : la position remonte vers la fin
	-- quand on pousse et redescend vers zero quand on s'arrete. Une seule valeur, deux sens, et repartir en plein
	-- retour ne demande AUCUN cas particulier -- elle change juste de direction.
	PUSH_ANIM_ID = "rbxassetid://130354141053420",
	-- MULTIPLICATEUR de la vitesse d'origine. 1 = EXACTEMENT le rythme donne dans l'editeur d'animation.
	--
	-- La position avance de `dt * PUSH_PLAY_SPEED` chaque image : c'est une lecture LINEAIRE, elle respecte donc
	-- les temps de l'animation image pour image.
	--
	-- Une version precedente lissait la position par un lerp exponentiel. Un lerp part VITE et finit LENT : il
	-- traversait les trois quarts de l'animation en quelques images puis rampait sur le reste. Le geste arrivait
	-- d'un bloc -- "trop sec" -- et les poses intermediaires passaient trop vite pour se voir. Une valeur
	-- interpolee ne peut PAS restituer un timing anime : seule une lecture lineaire le peut.
	PUSH_PLAY_SPEED = 1,
	-- AU-DESSUS de la pose du guidon (Action), sinon les deux clent les memes bras a priorite EGALE et Roblox en
	-- fait une MOYENNE au lieu de choisir -- on obtient une pose "presque bonne" qu'on croit mal animee.
	PUSH_PRIORITY = Enum.AnimationPriority.Action2,

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
	-- comme une machine qu'on POUSSE. Elle traine donc un peu dans le virage, puis rattrape.
	--
	-- PILOTE PAR L'INPUT, PAS PAR LE CAP OBSERVE. La version precedente derivait le cap du joueur (combien il avait
	-- tourne depuis l'image d'avant). Mais le serveur recoit ce cap REPLIQUE et interpole : quand le joueur arrete
	-- de tourner net, l'interpolation DEPASSE puis se corrige, la derivee change de SIGNE, et la machine repartait
	-- de l'autre cote -- un zig-zag a l'arret du virage. Aucun lissage ne rattrape une inversion reelle du signal.
	-- L'input, lui, est propre : il vaut ce que le joueur demande, sans bruit et sans depassement.
	--
	-- DEUX AMPLITUDES, selon qu'on ROULE ou qu'on manoeuvre. En pleine avance la machine se met franchement en
	-- travers -- c'est ce qui donne le poids et l'inertie ; a l'arret elle ne fait que s'orienter.
	-- Un reglage par etat, jamais une fraction de l'autre : sinon regler l'un force a compenser l'autre.
	-- Angle a fond de braquage EN ROULANT, en degres.
	SWING_ANGLE_DRIVE = 26,
	-- Angle a fond de braquage EN MANOEUVRE (a l'arret ou presque), en degres.
	SWING_ANGLE = 10,
	-- DEUX VITESSES, et l'ecart entre elles est tout l'effet.
	-- SE METTRE EN TRAVERS est rapide : la machine repond au braquage.
	SWING_RECOVER = 6,
	-- REVENIR DROIT est LENT. Un seul reglage servait les deux : en lachant la touche, la machine se realignait
	-- derriere le joueur en 0.17 s -- elle CLAQUAIT dans l'axe de la marche, ce qui ne ressemble a rien de reel.
	-- Une machine lancee revient droite toute seule, doucement, portee par son elan.
	-- BAS = revient plus lentement. Trop bas et elle reste de travers en ligne droite.
	SWING_RETURN = 1.6,
	-- VITESSE DE RETOUR MINIMALE, en degres par seconde. Le lerp exponentiel ci-dessus donne le bon ELAN au depart
	-- mais une queue interminable : depuis 26 degres, il reste encore ~5 degres de travers une seconde apres le
	-- virage et pres d'un degre au bout de trois. La machine avance donc EN CRABE en pleine ligne droite -- ce qui
	-- se lit comme un DERAPAGE, alors que la trajectoire est droite (mesure a l'ecran : 0.6 degre de glissade
	-- reelle). Le probleme n'etait donc pas le deplacement mais l'angle de la machine sur le joueur.
	--
	-- Ce plancher ne touche PAS le depart du retour (le lerp y est bien plus rapide que lui) : il ne fait que
	-- TERMINER la fin, au lieu de la laisser trainer. C'est LE knob "elle met trop longtemps a se remettre droite".
	--
	-- REPERES (temps pour effacer un travers de 26 degres, le maximum) :
	--   30  -> 0.85 s   on VOIT la machine se remettre droite
	--   80  -> 0.35 s   court mais encore lisible
	--   180 -> 0.15 s   invisible a l'oeil, sans pop : la machine EST droite des qu'on lache
	--   999 -> 1 image  vraiment instantane, mais un travers de 26 degres qui disparait d'un coup se voit
	--
	-- A 180 : le ballant fait toujours son travail PENDANT le virage (c'est la qu'il donne le poids), et il ne
	-- laisse plus rien trainer APRES. C'est l'apres qui se lisait comme un derapage.
	SWING_SETTLE = 180,
	-- Plafond absolu, en degres. Filet : les deux angles ci-dessus doivent rester EN DESSOUS, sinon c'est lui qui
	-- decide a leur place et les regler ne change plus rien.
	SWING_MAX = 40,

	-- ===== COUPE =====
	-- Rayon de coupe utilise SI la part CutZone est absente (elle donne sinon le sien, moitie de sa largeur).
	FALLBACK_RADIUS = 2.2,
	-- Point de coupe de secours, devant la racine, quand CutZone n'existe pas encore.
	FALLBACK_FORWARD = 1.6,

	-- ===== ROUES =====
	-- Les roues tournent EN CODE, pas par animation : une animation joue a vitesse fixe, donc la roue patinerait
	-- des que le joueur change d'allure. Ici l'angle vient de la distance REELLEMENT parcourue, elle colle au sol.
	-- Corollaire : ces joints ne doivent etre cles dans AUCUNE animation, sinon deux ecrivains sur le meme joint.
	-- NOMS DES ROUES -- les PARTS, pas les joints.
	--
	-- On cherchait le Motor6D par SON nom (`WheelFrontMotor6D`...). Mauvaise idee : le nom d'un joint est
	-- arbitraire et INVISIBLE dans l'Explorer tant qu'on ne deplie pas la roue, alors que le nom de la roue se lit
	-- d'un coup d'oeil. Le moindre re-export ou renommage cassait la rotation en silence.
	--
	-- On prend donc le joint dont la PART1 porte ce nom : c'est ce que Roblox fait deja pour les animations, qui
	-- retrouvent leurs cibles par le nom de la Part1 et jamais par celui du Motor6D.
	WHEEL_PARTS = { "WheelBack", "WheelFront" },
	-- Sens de rotation. Si les roues tournent a l'envers, mettre -1. Se voit a l'ecran, ne se deduit pas.
	WHEEL_DIRECTION = 1,
	-- AXE de rotation. "AUTO", ou "X" / "Y" / "Z" pour l'imposer.
	--
	-- EN AUTO, IL SE DEDUIT DE LA GEOMETRIE, et c'est fiable : une roue est LARGE x LARGE x MINCE. Son axe de
	-- rotation est donc forcement le cote le plus MINCE -- c'est ce qui fait d'elle une roue et pas un disque
	-- qu'on ferait tourner a plat.
	--
	-- Ca evite de tatonner entre trois valeurs a l'ecran, et surtout ca survit a un re-export du modele : si le rig
	-- change d'orientation dans Blender, la deduction suit toute seule.
	-- Passer a "X", "Y" ou "Z" seulement si la roue n'a pas des proportions de roue (un cube, par exemple).
	--
	-- "AUTO" prend l'axe de SYMETRIE : celui dont les deux perpendiculaires se ressemblent le plus. C'est ce qui
	-- definit une roue, et ca marche aussi bien pour un disque fin que pour une PAIRE montee sur un essieu -- le
	-- cas de cette tondeuse, ou `WheelBack` mesure 3.15 x 1.09 x 1.14 : l'essieu est le LONG cote, pas le mince.
	WHEEL_AXIS = "AUTO",
	-- Rayon de roue de secours (studs) si on n'arrive pas a le lire sur la part. Sinon il est MESURE sur la roue.
	WHEEL_RADIUS_FALLBACK = 0.6,

	-- ===== PARTICULES =====
	-- Noms des effets poses dans Studio sur le modele de la tondeuse.
	--
	-- UN NOM PEUT DESIGNER L'EMETTEUR OU CE QUI LE CONTIENT -- une part, une Attachment, un dossier. C'est ainsi
	-- qu'on construit un effet dans Studio : une PART au bon endroit, une Attachment dedans, et les emetteurs au
	-- fond. Ce sont la part et l'attachment qui portent un nom parlant ; les emetteurs, eux, s'appellent "Leafs" ou
	-- "ParticleEmitter".
	-- Nommer le CONTENEUR est donc le bon reflexe : ajouter un deuxieme emetteur dedans le fait suivre tout seul.
	--
	-- Un nom introuvable n'est PAS une erreur, mais la console le dit ET liste les noms utilisables.
	--
	-- VENT : souffle tant que la machine AVANCE, moteur en marche. Une tondeuse a l'arret ne souffle pas.
	WIND_EMITTERS = { "Wind" },
	-- HERBE PROJETEE : ne part que quand on coupe VRAIMENT. Passer une tondeuse allumee sur du beton ne doit rien
	-- projeter -- c'est cette exactitude qui fait qu'on croit a l'effet.
	CUT_EMITTERS = { "LeafCutEffectsRight", "LeafCutEffectsLeft" },
	-- Temps pendant lequel les brins continuent de voler apres la derniere touffe coupee, en secondes.
	-- SANS CA, CA CLIGNOTE : la coupe est intermittente d'une image a l'autre (un trou dans l'herbe, une touffe
	-- deja tondue), et l'emetteur s'allumerait et s'eteindrait plusieurs fois par seconde.
	CUT_EMITTER_HOLD = 0.25,
}
