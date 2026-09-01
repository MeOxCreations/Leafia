--!strict
-- PAPILLONS. Reglages du vol, du peuplement et de la duree de vie. Data pure, zero logique.

return {
	-- ===== OU LES TROUVER =====
	-- Le modele a cloner, et le dossier de zones dans le Workspace. Cherches par leur NOM, pas par un chemin
	-- complet : un objet pose par quelqu'un dans Studio se retrouve par son nom, son rangement est un detail.
	MESH_PATH = { "Assets", "Contents", "Animals", "ButterflyMesh" },
	-- CHAQUE PART de ce dossier est une zone, quel que soit son nom : imposer un nom obligerait a le retaper a
	-- chaque nouvelle zone, et une zone mal nommee ne dirait rien en echouant.
	ZONE_FOLDER = "ButterflyZones",
	-- L'animation de battement d'ailes, et le marqueur pose dedans a l'instant ou les ailes claquent.
	ANIM_PATH = { "Animations", "Animals", "Butterfly", "Butterfly_flying_Animation" },
	WING_EVENT = "BattementWingsEvent",

	-- Avec le streaming, les zones peuvent arriver bien apres le boot. On re-scanne jusqu'a les trouver.
	FIND_TIMEOUT = 45,
	FIND_INTERVAL = 1.5,

	-- ===== COMBIEN, ET QUAND =====
	-- Par zone. On ne remplit pas d'un coup au demarrage : ils arrivent un par un, comme s'ils passaient par la.
	PER_ZONE_MIN = 2,
	PER_ZONE_MAX = 4,
	-- Ecart entre deux apparitions, en secondes, plus un peu de hasard. Sans hasard, une zone vide se remplit
	-- toujours au meme rythme et ca se lit comme une machine.
	SPAWN_EVERY = 6,
	SPAWN_JITTER = 5,
	-- DUREE DE VIE. Un papillon FINIT par s'en aller : c'est ce qui rend son passage precieux au lieu d'en faire
	-- un element de decor fixe. Il monte et disparait, il ne s'evapore pas sur place.
	LIFE_MIN = 22,
	LIFE_MAX = 45,
	-- Temps que dure le depart (montee + fondu), en secondes.
	LEAVE_TIME = 3,
	LEAVE_RISE = 14, -- studs gagnes pendant le depart

	-- ===== LE PAPILLON DE SCENE =====
	-- Un papillon qu'on lance d'un point A vers un point B, pour une scene. Il reutilise tout le reste -- le
	-- battement, le zigzag, le roulis, la couleur -- il a juste un BUT au lieu d'une zone.
	--
	-- Le zigzag reste ACTIF pendant le trajet : un papillon qui file droit vers sa cible ne ressemble plus a un
	-- papillon, et c'est justement le zigzag qui vend l'ambiance dans un plan pose.
	--
	-- Distance a laquelle on le considere arrive. Genereuse : le zigzag l'empeche de viser au stud pres, et
	-- exiger la precision le ferait tourner autour du point sans jamais "arriver".
	SCENE_ARRIVE_DIST = 5,
	-- Filet de securite : meme s'il n'arrive jamais (cible inatteignable, aimant absent), il finit par partir.
	-- Sans ca, un papillon de scene rate resterait a l'ecran pour le reste de la partie.
	SCENE_LIFE_MAX = 40,
	-- De combien il vise a cote de sa cible, en radians. A zero il fonce en ligne droite malgre le zigzag ; un
	-- peu de biais lui laisse le temps de flaner en chemin.
	SCENE_AIM_JITTER = 0.45,

	-- RIEN NE VIT LOIN DU JOUEUR. Au-dela, la zone se vide et cesse d'etre mise a jour : un papillon que personne
	-- ne voit coute exactement autant qu'un papillon qu'on regarde.
	VIEW_DISTANCE = 140,

	-- ===== LE VOL =====
	-- LE BATTEMENT POUSSE. Chaque marqueur de l'animation donne une impulsion vers le HAUT et vers l'AVANT : c'est
	-- ce qui fait la trajectoire en dents de scie d'un papillon, et pourquoi il ne ressemble pas a un drone.
	-- Sans ca on obtient un vol lisse, et un vol lisse ne se lit jamais comme un insecte.
	-- LA PORTANCE MONTE AVEC LA POUSSEE. Elle n'a pas de rapport avec la taille du modele -- un papillon plus
	-- petit n'est pas plus lourd -- mais elle doit rester en proportion de l'avance : une machine qui pousse fort
	-- vers l'avant et peu vers le haut file a l'horizontale, et la dent de scie disparait.
	FLAP_UP = 7, -- studs/seconde ajoutes vers le haut a chaque battement
	-- LA POUSSEE VERS L'AVANT, et c'est ELLE qui regle la vitesse de vol -- pas SPEED_MIN/MAX. Battre des ailes
	-- plus vite ne fait qu'accelerer les ailes : l'impulsion est divisee par la vitesse de lecture, expres, pour
	-- que les deux reglages ne se battent pas. Pour aller plus vite, c'est ici.
	FLAP_FORWARD = 8.5,
	-- Entre deux battements il RETOMBE. Plus fort que la gravite reelle serait brutal, plus faible le ferait
	-- planer comme un oiseau : c'est cet ecart avec FLAP_UP qui donne le rebond caracteristique.
	GRAVITY = 11,
	-- Frottement de l'air, par seconde. Il empeche les impulsions de s'accumuler a l'infini et fait retomber la
	-- vitesse entre deux coups d'ailes.
	DRAG = 1.8,
	-- Plafond de vitesse horizontale. Il borne le resultat de FLAP_FORWARD : monter la poussee sans monter ce
	-- plafond ne change rien du tout, les deux vont ensemble.
	MAX_SPEED = 19,
	-- CHACUN SON ALLURE. Un multiplicateur tire par papillon, applique A LA FOIS a la poussee et au plafond --
	-- ne toucher qu'a l'un des deux ne changerait rien (une poussee bridee par un plafond commun, ou un plafond
	-- jamais atteint faute de poussee).
	--
	-- Sans ca, dix papillons dans la meme zone avancent tous exactement au meme rythme : l'oeil lit un systeme,
	-- pas des individus. C'est la meme raison que la taille et la vitesse d'ailes variables.
	SPEED_VAR_MIN = 0.7,
	SPEED_VAR_MAX = 1.35,

	-- ===== LE ZIGZAG =====
	-- Un papillon ne va nulle part, et surtout il ne va JAMAIS TOUT DROIT. Trois mecanismes se superposent pour
	-- obtenir ca, et il en faut bien trois : chacun tout seul donne quelque chose de faux.
	--
	-- 1) DES VIRAGES FREQUENTS. Toutes les demi-secondes environ. Espaces de deux secondes, on voyait de longs
	--    segments rectilignes entre deux decisions -- exactement le "tout droit" qu'on veut supprimer.
	TURN_EVERY = 0.35,
	TURN_JITTER = 0.4,
	-- De combien il tourne d'un coup, en degres. C'est un MAXIMUM : chaque virage tire entre 40 % et 100 % de
	-- cette valeur, sinon tous les virages ont la meme amplitude et ca redevient un motif.
	TURN_ANGLE = 75,
	--
	-- 2) ILS ALTERNENT. C'EST LE COEUR DU ZIGZAG, et c'est ce qui manquait.
	--    Un tirage purement au hasard part deux ou trois fois du meme cote et dessine des CERCLES -- ce qu'on
	--    voyait. En forcant le virage suivant a partir de l'autre cote, on obtient gauche-droite-gauche : un
	--    zigzag. La probabilite reste sous 1 pour qu'il puisse enchainer deux fois du meme cote de temps en
	--    temps, sinon l'alternance devient elle-meme un motif regulier.
	TURN_ALTERNATE = 0.78,
	--
	-- 3) UNE DERIVE CONTINUE, par-dessus. Entre deux virages, le cap ondule doucement : aucun segment n'est donc
	--    jamais parfaitement droit, meme sur une demi-seconde. Sans elle, le vol reste une suite de traits.
	WANDER_AMOUNT = 1.1, -- radians par seconde, au maximum
	WANDER_SCALE = 0.45, -- lenteur de l'ondulation : plus bas = plus lent, plus mou
	--
	-- Vitesse a laquelle il s'oriente vers son nouveau cap. RELEVEE avec la frequence des virages : trop molle,
	-- il n'aurait jamais fini un virage avant qu'on lui en demande un autre, et le zigzag se moyennerait en
	-- ligne droite. Deux reglages qui doivent monter ensemble.
	TURN_SPEED = 6,

	-- ===== LE CORPS REGARDE OU IL VA =====
	-- Deux directions differentes, et il faut les distinguer : le CAP VOULU sert a pousser (c'est l'intention),
	-- la VITESSE REELLE sert a orienter le corps (c'est ce qui se voit). Le rappel du bord, la gravite et l'elan
	-- du battement precedent font que les deux ne coincident presque jamais -- oriente sur l'intention, le
	-- papillon volait EN CRABE.
	--
	-- Vitesse a laquelle le corps se realigne sur son deplacement. Haute : c'est une CORRECTION, pas un mouvement
	-- a admirer. Trop basse, il traine visiblement de travers derriere sa trajectoire.
	BODY_TURN_SPEED = 8,
	-- En dessous de cette vitesse horizontale, la direction n'a plus de sens (bruit numerique) : on garde la
	-- derniere orientation au lieu de faire pivoter le papillon au hasard quand il est presque immobile.
	BODY_MIN_SPEED = 0.4,

	-- ===== IL S'INCLINE DANS LES VIRAGES, COMME UN AVION =====
	-- Le roulis vient de la VITESSE DE ROTATION, pas de l'angle : c'est en tournant qu'on s'incline, pas en ayant
	-- tourne. Un roulis cale sur le cap laisserait le papillon penche en ligne droite.
	--
	-- Combien de roulis par unite de vitesse de rotation. Monter ce chiffre rend le vol plus acrobatique.
	BANK_GAIN = 0.55,
	-- Inclinaison maximale, en degres. Au-dela d'environ 60 on ne voit plus les ailes de face et ca devient un
	-- tonneau.
	BANK_MAX = 50,
	-- Vitesse a laquelle il prend et rend son inclinaison. Plus bas que le realignement du corps : l'inclinaison
	-- doit TRAINER un peu derriere le virage, sinon elle claque et on ne la lit plus comme du poids.
	BANK_SPEED = 5,
	-- Le sens depend de l'orientation du modele dans Blender : ca ne se DEDUIT pas, ca se voit a l'ecran. Regle
	-- a `true` apres essai -- le papillon penchait a l'exterieur du virage au lieu de l'interieur.
	BANK_INVERT = true,

	-- ===== LA ZONE EST UN AIMANT =====
	-- Aucun mur, aucune teleportation : plus il s'eloigne, plus la zone tire fort. Il fait donc demi-tour tout
	-- seul, et de l'exterieur ca se lit comme un papillon qui change d'avis.
	--
	-- Marge, en studs, a partir du bord ou l'aimant commence a agir.
	EDGE_MARGIN = 4,
	EDGE_PUSH = 8,
	-- DE COMBIEN LA FORCE GRANDIT par stud de depassement. C'est ce qui garantit le retour : une force CONSTANTE
	-- pouvait perdre contre l'elan d'un battement, et le papillon partait pour de bon. Une force qui grandit
	-- finit toujours par gagner, sans jamais avoir besoin d'un mur.
	EDGE_GAIN = 0.9,
	-- SORTI DE LA ZONE, IL DECIDE DE RENTRER : son prochain cap vise le centre au lieu d'etre tire au hasard. Il
	-- bat alors des ailes DANS la bonne direction, au lieu d'etre traine de cote par l'aimant -- un retour qu'on
	-- lit comme une intention, pas comme un courant d'air. Un peu de hasard pour que ce ne soit pas une ligne
	-- droite de fourmi.
	EDGE_HOME_JITTER = 0.6, -- radians
	-- Et il redecide TOUT DE SUITE au lieu d'attendre son prochain virage : dehors, deux secondes d'attente le
	-- laissent s'eloigner pour rien.
	EDGE_TURN_NOW = true,
	-- Hauteur de vol au-dessus du BAS de la zone, et de combien il peut s'en ecarter. La zone donne l'emprise au
	-- sol ; la hauteur se regle ici, sinon il faudrait redimensionner la part a chaque essai.
	FLY_HEIGHT = 3.5,
	FLY_HEIGHT_RANGE = 2.5,
	-- PLANCHER DUR, au-dessus du bas de la zone. Le rappel vers la hauteur de croisiere est une force DOUCE, et
	-- une force douce ne garantit jamais une borne : entre deux battements la gravite faisait passer le papillon
	-- SOUS la map. Une borne, ca se clampe, ca ne se ressort pas.
	--
	-- Mesure depuis le BAS DE LA ZONE : poser la part de facon que son dessous affleure le sol suffit a caler
	-- tous les papillons d'un coup, sans toucher a un seul reglage.
	MIN_HEIGHT = 1.2,

	-- ===== L'ANIMATION =====
	-- Chacun bat des ailes a son propre rythme. Deux papillons parfaitement synchrones se lisent comme un seul
	-- objet duplique -- meme piege que les plantes de l'ambiance.
	--
	-- CE REGLAGE NE CHANGE QUE L'ASPECT DES AILES. Chaque battement pousse le papillon : battre deux fois plus
	-- vite donnerait deux fois plus d'impulsions par seconde, et le papillon decollerait comme une fusee. Le
	-- controller DIVISE donc l'impulsion par cette vitesse. On peut monter ce chiffre autant qu'on veut sans
	-- retoucher FLAP_UP -- deux reglages qu'il faudrait compenser l'un par l'autre finiraient par se battre.
	SPEED_MIN = 3.6,
	SPEED_MAX = 4.8,
	-- ===== LA TAILLE =====
	-- UN SEUL BOUTON POUR LA TAILLE GENERALE, un autre pour la variete. C'etait un couple min/max, et changer la
	-- taille globale obligeait alors a bouger les DEUX en gardant leur ecart -- deux reglages qu'il faut tenir
	-- d'accord a la main finissent toujours par se contredire.
	--
	-- Multiplie la taille du modele tel qu'il est dans ReplicatedStorage. 1 = taille d'origine, 2 = deux fois plus
	-- gros. C'est ici qu'on regle si les papillons sont trop petits ou trop gros a l'ecran.
	SCALE = 0.3,
	-- De combien ils different les uns des autres, en fraction. 0.15 = plus ou moins 15 %. A zero ils sont tous
	-- rigoureusement identiques, et l'oeil repere la repetition avant de reperer la forme.
	SCALE_VARIATION = 0.15,

	-- ===== LA COULEUR DES AILES =====
	-- Les parts a teinter. Le reste du modele (corps, antennes) garde sa couleur : c'est la teinte des AILES qui
	-- distingue une espece, pas celle du corps.
	WING_PARTS = { "Aile1", "Aile2" },
	-- Une couleur tiree au hasard par papillon. Le blanc reste dans le lot -- c'est une vraie couleur de
	-- papillon, il ne fallait juste pas que ce soit la SEULE.
	--
	-- Toutes choisies pour ressortir sur du VERT : le jardin est vert, et un papillon vert serait invisible.
	-- C'est pour ca qu'il n'y en a pas dans la liste, meme si ca existe dans la nature.
	--
	-- NI NOIR NI COULEUR SOMBRE, pour la meme raison a l'envers : une aile sombre se lit comme une ombre ou un
	-- trou dans le decor, pas comme un insecte. Toutes les teintes ci-dessous sont CLAIRES.
	WING_COLORS = {
		Color3.fromRGB(255, 255, 255), -- blanc
		Color3.fromRGB(255, 214, 84), -- jaune
		Color3.fromRGB(255, 146, 62), -- orange
		Color3.fromRGB(255, 110, 160), -- rose
		Color3.fromRGB(224, 78, 78), -- rouge
		Color3.fromRGB(140, 194, 255), -- bleu ciel
		Color3.fromRGB(186, 142, 255), -- lavande
	},
}
