--!strict
-- Reglages du DIDACTICIEL. Data pure, zero logique.
--
-- Le didacticiel a deux moities : TutorialService (serveur) place le joueur, TutorialController (client) le
-- GUIDE. Cette config sert aux deux.

-- LE RECUL DE FRAYEUR SE CALCULE, il ne se regle pas a la main. Il DOIT etre plus grand que l'approche, sinon la
-- camera revient pile a son point de depart et le mouvement se lit comme une annulation, pas comme un sursaut.
-- Deux nombres tenus d'accord a la main finissent toujours par se contredire : le vrai reglage, c'est de combien
-- la camera saute AU-DELA de son point de depart. Baisse SCARE_EXTRA pour un sursaut plus discret.
local TRY_PUSH = 2.2
local PRE_OPEN_PUSH = 0.8
local SCARE_EXTRA = 0.6

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
	-- Studs derriere le joueur. A ne pas confondre avec KNOCK_KICK, qui est un recul PONCTUEL a chaque coup :
	-- celui-ci est le CADRAGE, il ne bouge pas de toute la scene.
	--
	-- RECULEE : le plan de depart montre le joueur ET la maison, avant que la camera ne se resserre pendant le
	-- geste de poignee (TRY_PUSH). Trop pres au depart, ce resserrement n'a plus de place pour se voir -- c'est
	-- la DISTANCE PARCOURUE qui fait l'effet, pas la distance finale.
	SCENE_CAM_BACK = 12,
	-- Studs au-dessus du joueur. Le repere est sa RootPart, deja a hauteur de torse : plus on monte, plus la
	-- camera plonge sur lui, ce qui ecrase le decor et rapetisse le personnage. A 0.7 on est juste sous la
	-- hauteur d'yeux -- l'oeil arrive donc sur la porte de face, pas d'en haut.
	SCENE_CAM_UP = 0.7,
	-- Decalage lateral : un cadrage parfaitement centre est plat. NEGATIF = la camera passe a GAUCHE du joueur.
	-- Le cote se voit a l'ecran, il ne se deduit pas : il depend du sens dans lequel la porte s'ouvre et de ce
	-- qu'il y a autour d'elle.
	SCENE_CAM_SIDE = -2,

	-- ===== ON SE PLACE DEVANT LA PORTE =====
	-- Le joueur peut declencher la scene DE PROFIL : la detection est radiale, elle accepte n'importe quel angle.
	-- Sans replacement, il toquait alors sur le mur ou dans le vide, et la camera -- calee sur SON regard -- se
	-- retrouvait de cote. Une seule cause, trois symptomes qu'on aurait corriges separement.
	--
	-- Distance a laquelle on le pose devant la porte, en studs.
	SCENE_PLACE_DIST = 4.5,
	-- Duree du replacement. COURT : il se joue pendant que les barres descendent, donc on ne le regarde pas. Trop
	-- long, il devient un deplacement qu'on subit ; a zero, c'est une teleportation qui saute aux yeux.
	SCENE_PLACE_TIME = 0.35,

	-- ===== LA CAMERA S'APPROCHE, PUIS RECULE =====
	-- Pendant que le grand-pere se bat avec la poignee, on se rapproche LENTEMENT : l'image se resserre sans
	-- qu'on s'en rende compte, et la tension monte toute seule.
	TRY_PUSH = TRY_PUSH,
	-- Aussi long que le geste de poignee. Un mouvement qui finit avant lui laisserait la camera immobile pendant
	-- la moitie de la scene, ce qui casse justement l'effet de resserrement continu.
	TRY_PUSH_TIME = 2.6,
	-- ELLE AVANCE ENCORE UN PEU quand la porte s'entrebaille. On a passe la scene a se rapprocher : au premier
	-- mouvement du battant on ne recule pas encore, on SE PENCHE -- comme quelqu'un qui veut voir qui est
	-- derriere. Court et discret : c'est un mouvement de curiosite, pas un nouveau plan.
	PRE_OPEN_PUSH = PRE_OPEN_PUSH,
	-- Vif, cale sur l'entrebaillement lui-meme : la camera se penche PENDANT que le battant bouge, pas apres.
	PRE_OPEN_PUSH_TIME = 0.4,
	-- Puis elle RECULE d'un coup quand la porte s'ouvre EN GRAND, comme si elle avait eu peur. Calcule depuis les
	-- DEUX approches (voir en tete de fichier) : il ne peut donc plus passer sous elles, quoi qu'on change. C'est
	-- pour ca que l'avancee de curiosite entre dans le calcul -- l'ajouter sans la compter ici ferait revenir la
	-- camera pile a son point de depart, et le sursaut se lirait comme une annulation.
	SCARE_BACK = TRY_PUSH + PRE_OPEN_PUSH + SCARE_EXTRA,
	-- VIF. C'est un reflexe, pas un mouvement de camera : au-dela d'une demi-seconde il ne se lit plus comme une
	-- reaction mais comme un travelling arriere.
	SCARE_TIME = 0.32,
	-- Ce que la camera VISE, en studs au-dessus du centre de la porte. A zero elle vise le milieu exact.
	SCENE_LOOK_UP = 0.5,

	-- ===== LE PAPILLON DE LA SCENE =====
	-- Un papillon traverse le cadre pendant que le joueur toque. Il ne raconte rien et ne sert a rien -- c'est
	-- exactement pour ca qu'il compte : un plan ou SEUL le sujet bouge se lit comme une image fixe avec un acteur
	-- dessus. Un mouvement gratuit au second plan suffit a rendre le monde vivant.
	--
	-- Les deux parts sont posees dans Studio : on ne devine pas une trajectoire, on la CADRE a la main.
	BUTTERFLY_START = "ButterflyPointStart",
	BUTTERFLY_END = "ButterflyPointEnd",
	-- Apres le debut de la scene. Pas a l'instant zero : la camera est encore en train d'arriver et les barres de
	-- se poser -- le papillon passerait pendant que l'oeil cherche encore le cadre.
	BUTTERFLY_DELAY = 1.2,

	-- ===== LE PLAN DE SORTIE : le joueur ET le grand-pere, vus d'un peu au-dessus =====
	-- La camera ne rend pas la main tout de suite quand la porte est ouverte. Elle prend un dernier plan, large,
	-- ou l'on voit le joueur se pousser et le grand-pere sortir de chez lui.
	--
	-- ON CADRE L'ESPACE QUE L'ACTION VA TRAVERSER, pas le grand-pere lui-meme. Une camera qui SUIT un sujet qui
	-- marche doit bouger a chaque image, donc se battre avec la respiration du plan ; un cadre pose sur le trajet
	-- ENTIER n'a rien a suivre et laisse l'action entrer dedans. C'est aussi ce qu'on fait au cinema.
	--
	-- Duree du glissement vers ce plan, puis duree pendant laquelle on le tient.
	--
	-- LE MAINTIEN EST COURT, ET C'EST VOULU. Il a d'abord ete cale pour couvrir toute la marche du grand-pere :
	-- le joueur regardait donc sans rien faire pendant qu'un vieux traversait sa cour, sans meme savoir ce qu'il
	-- attendait. La scene est FINIE a cet instant -- ce qui reste est du jeu, pas du cinema.
	--
	-- Ce qu'on perd : la camera rend la main alors que le grand-pere est encore en route. On ne le regarde plus
	-- marcher, on le voit marcher pendant qu'on avance -- ce qui est exactement ce qu'on veut d'un PNJ.
	--
	-- Le joueur reprend la main a la FIN de ce maintien : les deux chiffres ci-dessous sont donc tout ce qui
	-- separe la fin de la scene du moment ou il peut bouger.
	EXIT_SHOT_IN = 0.8,
	EXIT_SHOT_HOLD = 0.4,
	-- DE COTE, PERPENDICULAIREMENT AU TRAJET. Premiere version : dans l'axe de la porte -- la camera se retrouvait
	-- DANS LE MUR de la maison, et on ne voyait rien. Normal : cet axe pointe vers la maison, et reculer dessus
	-- rentre dedans.
	--
	-- Un plan pris de COTE regarde en travers du trajet. La maison reste sur un bord, le jardin sur l'autre, et
	-- les deux personnages se detachent au lieu de se cacher l'un l'autre quand ils s'alignent. C'est aussi le
	-- plan a deux le plus courant au cinema, et ce n'est pas un hasard.
	--
	-- Recul MINIMUM, et part de l'ecartement entre les deux personnages. Le second fait que le plan s'ouvre tout
	-- seul si on eloigne le point d'arrivee dans Studio -- rien a re-regler.
	EXIT_SHOT_MIN_BACK = 10,
	EXIT_SHOT_SPREAD = 1.1,
	-- DE QUEL COTE ? Ca ne se DEDUIT pas : ca depend de l'orientation de la maison dans Studio, et seul l'ecran
	-- tranche. Si la camera se retrouve dans un mur ou de l'autre cote de la maison, inverser ce drapeau.
	EXIT_SHOT_INVERT = false,
	-- "Un peu du dessus" : assez pour voir les deux corps en entier et le sol entre eux, pas assez pour que ca
	-- devienne une vue de dessus (au-dela de ~12 on perd les visages).
	EXIT_SHOT_UP = 7,
	-- Ce qu'on vise, au-dessus du point milieu. Vers le torse : viser le sol met l'horizon tout en haut du cadre.
	EXIT_SHOT_LOOK_UP = 1.5,
	-- Decalage le long du TRAJET, pour ne pas etre pile au milieu. Zero = plan symetrique ; positif = decale vers
	-- le point d'arrivee, ce qui laisse plus de place devant le grand-pere qui marche.
	-- Remis a ZERO en changeant de repere : le -3 d'avant etait cale sur un decalage LATERAL, il ne veut plus
	-- rien dire le long du trajet. Un reglage garde apres un changement de sens est un reglage faux.
	EXIT_SHOT_SIDE = 0,

	-- ===== LE SECOND PLAN : IL MARCHE =====
	-- Une fois le premier plan pose, la camera GLISSE vers un second, plus bas et plus proche, pendant que le
	-- grand-pere traverse sa cour. Un plan fixe pendant que quelqu'un marche est une PHOTO ; un plan qui bouge
	-- accompagne le mouvement, et c'est ce qui fait qu'on continue de regarder.
	--
	-- MEME GEOMETRIE que le premier -- meme axe, meme cote, meme point vise -- avec d'autres reglages : le passage
	-- de l'un a l'autre est donc un glissement, pas un changement de plan. Deux constructions differentes auraient
	-- donne un saut a l'image, ce qu'on appelle un faux raccord.
	--
	-- Duree du glissement. LONGUE : c'est elle qui donne le mouvement, et elle doit couvrir une bonne part de la
	-- marche. Trop courte, la camera arrive avant lui et le plan redevient fixe.
	WALK_SHOT_IN = 2.5,
	-- LA CAMERA DESCEND (7 -> 2) : on passe d'un plan "un peu du dessus" a une CONTRE-PLONGEE, l'oeil presque au
	-- niveau du sol. Le grand-pere y parait plus grand, et son trajet plus long -- c'est le meme metre de cour,
	-- filme comme s'il en valait dix.
	WALK_SHOT_UP = 2,
	-- ET ELLE REGARDE PLUS HAUT que ce qu'elle vise d'habitude : c'est ce qui fait la contre-plongee. Camera basse
	-- ET regard bas donnerait un plan rasant, pas une contre-plongee.
	WALK_SHOT_LOOK_UP = 3.2,
	-- ET ELLE SE RAPPROCHE. Fraction du recul du premier plan : 1 = meme distance, 0.7 = un tiers plus pres. En
	-- fraction et pas en studs, pour que le rapprochement suive l'ouverture du plan quand on eloigne le point
	-- d'arrivee dans Studio -- sinon il serait juste sur une distance et faux sur toutes les autres.
	WALK_SHOT_BACK = 0.72,
	-- Decalage le long du trajet, comme pour le premier plan. Positif = vers le point d'arrivee, ce qui laisse de
	-- la place devant le marcheur.
	WALK_SHOT_SIDE = 1.5,

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
	-- RESSERREMENT SUPPLEMENTAIRE quand la porte finit de s'ouvrir et que le grand-pere apparait. S'AJOUTE au
	-- precedent : l'image se resserre une premiere fois sur la porte qui bouge, puis une seconde sur lui.
	-- Volontairement petit -- c'est un accent, pas un gros plan.
	REVEAL_ZOOM = 7,
	-- Distance MINIMALE gardee avec le sujet, quoi qu'il arrive. Elle borne l'approche du geste de poignee :
	-- sans elle, une valeur un peu forte ferait passer la camera AU TRAVERS de la porte.
	REVEAL_MIN_DIST = 5,
	-- Cadence de CE resserrement-la. L'allure par defaut de CameraEffects (1.1) est faite pour des effets de
	-- fond : elle mettrait deux secondes, et l'accent serait fini apres le moment qu'il souligne.
	REVEAL_ZOOM_SPEED = 6,

	-- ET LE CADRE S'OUVRE AVEC LE BATTANT, des qu'il s'ENTREBAILLE. Les bandes ne partent pas -- on est encore
	-- dans la scene -- elles se RETRACTENT : l'image grandit pendant qu'on se penche vers l'ouverture, donc en
	-- meme temps que l'envie de voir. Ce que la porte fait au decor, le cadre le fait a l'ecran.
	--
	-- Fraction de leur hauteur normale. A zero elles disparaitraient et la scene perdrait ce qui dit qu'elle en
	-- est une ; a 1 il ne se passe rien. Entre les deux, ca se juge a l'ecran.
	REVEAL_BARS = 0.5,
	-- Un peu plus lent que le resserrement du champ de vision : deux mouvements a la meme vitesse se lisent comme
	-- un seul effet, alors qu'on veut sentir le cadre s'ouvrir SOUS le zoom.
	REVEAL_BARS_TIME = 0.7,

	-- IL PARLE, des le premier mouvement du battant. Une voix sans visage : on entend quelqu'un qu'on ne voit pas
	-- encore, et c'est ce qui fait attendre la grande ouverture.
	--
	-- 2D comme les autres sons de la scene (voir SCENE_2D dans le controller) : une replique RACONTE, elle ne
	-- vient pas d'un point de la carte. Spatialisee, elle baisserait avec la distance de la camera pendant le plan
	-- large -- alors qu'on vient justement de tourner l'oreille vers lui.
	--
	-- IL DIT DEUX CHOSES, L'UNE APRES L'AUTRE. La premiere (`speech_0`) part des que le battant S'ENTREBAILLE :
	-- on entend quelqu'un qu'on ne voit pas encore, et c'est ca qui fait attendre la grande ouverture. La seconde
	-- (`speech_1`) enchaine des qu'il a fini de dire la premiere.
	--
	-- LA PORTE NE COMMANDE PLUS LA VOIX : elle finit de s'ouvrir pendant qu'il parle. Caler la seconde replique
	-- sur la grande ouverture faisait attendre un mouvement qui n'a rien a voir avec ce qu'il raconte.
	SPEECH0_SOUND = { "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_0" },
	-- Delai apres l'entrebaillement. COURT : sa voix doit arriver avec le mouvement du battant, pas apres.
	SPEECH0_DELAY = 0.15,
	SPEECH_SOUND = { "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_1" },
	-- Souffle entre les deux repliques. A ZERO : elles s'enchainent, comme quelqu'un qui parle sans reprendre son
	-- souffle. Le knob reste, c'est ici qu'on remet du silence si un jour la seconde arrive trop vite.
	SPEECH_GAP = 0,
	-- FILET, en secondes. La seconde replique est enchainee sur la FIN de la premiere : si le fichier n'arrive
	-- jamais, cette fin ne tire pas et la seconde ne partirait JAMAIS. Passe ce delai, on regarde si le son a
	-- seulement charge -- s'il n'a pas charge, on enchaine sans lui.
	--
	-- On ne coupe PAS un son qui joue encore : ce filet ne repond qu'a "il n'est jamais arrive", jamais a "il est
	-- plus long que prevu". Une borne ne doit jamais etre plus serree que la donnee qu'elle borne.
	SPEECH_CHAIN_TIMEOUT = 6,
	-- FILET D'ATTENTE AVANT DE RENDRE LA MAIN, en secondes. La scene ne relache le joueur qu'une fois le grand-pere
	-- TU : parti pendant qu'il parle, il court sur une replique qu'il n'entend plus, et le plan se termine tout
	-- seul dans le vide.
	--
	-- Mais on ne l'enferme JAMAIS pour de bon : si une voix ne se termine pas (asset absent, `Ended` qui ne tire
	-- pas), passe ce delai on rend la main quoi qu'il arrive. Un joueur bloque par un fichier son manquant est le
	-- pire des deux maux.
	SPEECH_WAIT_MAX = 20,
	-- DUREE SUPPOSEE d'une replique, le temps de connaitre la vraie. `TimeLength` vaut zero jusqu'a ce que l'asset
	-- soit charge : entre l'instant ou l'on lance un son et celui ou l'on sait combien il dure, il faut bien
	-- compter QUELQUE CHOSE -- sinon la scene croirait qu'il a fini de parler avant sa premiere syllabe.
	SPEECH_ASSUME = 2,

	-- ===== LE JOUEUR S'EFFACE, MAIS PAS TOUT DE SUITE =====
	-- LA SCENE A DEUX TEMPS, et le personnage n'a pas le meme role dans les deux.
	--
	-- 1) IL TOQUE. C'est LUI qu'on regarde : c'est son geste, c'est lui qui declenche l'histoire. L'effacer ici
	--    enleverait l'acteur du plan. Donc ZERO : entierement visible.
	SCENE_PLAYER_FADE = 0,
	-- 2) LA PORTE S'OUVRE. On a essaye de l'effacer ici, parce qu'un GRAND avatar masque le grand-pere. Retire :
	--    le joueur est un PERSONNAGE de la scene, pas un obstacle -- c'est lui qui a toque, c'est lui qui se
	--    pousse, et le dernier plan les montre TOUS LES DEUX. Le faire disparaitre en plein milieu de son propre
	--    role est plus etrange qu'un cadre encombre. Le probleme de l'avatar qui masque se regle par le CADRAGE
	--    (le plan de sortie est pris de cote, justement), pas en supprimant l'acteur.
	--
	--    ZERO des deux cotes : le fondu ne fait donc plus rien. On garde le chemin -- c'est le knob si un jour
	--    une scene a vraiment besoin d'effacer le joueur.
	--
	-- Passe par CharacterFade, donc par LocalTransparencyModifier : ca ne se replique pas. En co-op, les autres
	-- continuent de voir un personnage normal. Couvre le corps, les decalques (le visage) et les accessoires
	-- (cheveux, chapeaux) ; un outil tenu en main reste visible, ce qui est voulu ailleurs dans le jeu.
	REVEAL_PLAYER_FADE = 0,
	-- EN FONDU, jamais d'un coup : une silhouette qui disparait d'un claquement attire justement l'oeil sur elle,
	-- au moment ou l'on veut qu'il parte vers la porte.
	REVEAL_FADE_TIME = 0.45,

	-- Durees. Les barres et la camera partent ENSEMBLE : dans un film le cadre bouge pendant que le rideau
	-- descend, il n'attend pas.
	--
	-- ELLES S'EN VONT QUAND LE GRAND-PERE SE MET EN MARCHE, pas quand la camera rend la main. Ce qu'elles
	-- encadrent est fini a cet instant : la suite -- un vieux qui traverse sa cour -- n'est plus un plan, c'est
	-- le jeu qui reprend. Les garder pendant ce trajet ne cadrait plus rien, ca disait juste "attends encore".
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
	-- RECUL DE LA CAMERA a chaque coup, en studs. Elle part en arriere d'un coup sec et revient toute seule :
	-- l'image encaisse le choc en meme temps que la porte, donc les coups se SENTENT au lieu de s'entendre.
	-- Les trois s'additionnent -- c'est ce que fait une vraie camera qu'on bouscule.
	KNOCK_KICK = 0.3,
	-- IMPACT A CHAQUE COUP. Tous les ParticleEmitter trouves sous ce conteneur crachent d'un coup.
	--
	-- ON PREND TOUT CE QU'IL CONTIENT, sans nommer les emetteurs. Ajouter un effet dans Studio suffit alors a
	-- l'inclure : le code n'a pas a savoir combien il y en a ni comment ils s'appellent.
	--
	-- `Emit` plutot qu'allumer puis eteindre : une bouffee ponctuelle n'a AUCUN etat a rendre. Un effet qu'on
	-- allume peut rester allume -- et c'est exactement ce qui rendait la version a Beams fragile.
	KNOCK_EMIT_PARENT = "KnockEffect1",
	-- Particules crachees par emetteur et par coup. Le RESTE du reglage -- taille, duree de vie, vitesse,
	-- couleur -- vit dans Studio, sur l'emetteur : c'est la qu'on le voit.
	KNOCK_EMIT_COUNT = 1,
	-- La porte TREMBLE a chaque coup.
	DOOR_SHAKE_ANIM = "DoorShakeAnimation",
	-- Son du coup, joue AU NIVEAU DE LA PORTE. Spatial et pas global : un bruit de porte qui sort du centre de la
	-- tete se decolle de l'image, surtout avec une camera posee a six studs de la.
	KNOCK_SOUND = { "Sounds", "Scenes", "Scene1", "KnockDoorSound" },

	-- ===== LES ANIMATIONS DE LA SCENE =====
	SCENE_ANIM_FOLDER = { "Animations", "Scenes", "Scenes1" },
	-- Le Model du grand-pere dans le Workspace. MEME NOM que la cle d'AmbientAnimConfigs : les deux designent le
	-- meme objet, et les laisser diverger coupe son animation d'ambiance EN SILENCE.
	GRANDPA_NAME = "OldmanOriginal",
	-- IL S'ACHARNE SUR LA POIGNEE avant d'ouvrir : "encore cette porte, faut vraiment que je la change". Joue
	-- APRES les coups et AVANT l'ouverture. Sa fin enchaine toute seule sur l'ouverture -- c'est l'animation qui
	-- dit quand elle a fini, pas un delai pose a cote.
	TRY_OPEN_ANIM = "Scene1_oldman_TryOpenDoor",
	-- SUR QUEL MODEL cette animation se joue. Le NOM de l'animation ne le dit pas : "oldman_TryOpenDoor" peut
	-- tres bien animer la POIGNEE de la porte plutot que le vieux.
	--
	-- Et se tromper ne produit AUCUNE erreur : une animation retrouve ses cibles par leur NOM, donc si aucune ne
	-- correspond au rig, elle joue a plein poids et n'ecrit rien. Le son part, la piste tourne, l'ecran ne bouge
	-- pas -- et on cherche le bug dans le declenchement, qui est parfait.
	--
	-- C'est la PORTE : a cet instant elle est encore fermee, le grand-pere est derriere et on ne le verrait pas
	-- de toute facon. Le nom de l'animation raconte l'histoire ("oldman"), pas la cible.
	TRY_OPEN_MODEL = "Door",
	-- Le bruit de poignee qu'on secoue. Spatial, au niveau de la porte. Il va JUSQU'AU BOUT, meme si le geste se
	-- termine avant : un bruit coupe net s'entend comme un bug, alors qu'il deborde ici sans deranger personne.
	TRY_OPEN_SOUND = { "Sounds", "Scenes", "Scene1", "TryUnlockDoorSound" },
	-- IL PARLE EN SE BATTANT AVEC SA POIGNEE. Une voix avant meme que la porte bouge : on sait qu'il y a
	-- quelqu'un derriere, et on l'entend galerer. Le bruit de serrure dit qu'une porte resiste, la voix dit que
	-- c'est UN VIEUX MONSIEUR qui resiste avec elle.
	TRY_OPEN_VOICE = { "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_BeforeOpen" },
	-- Apres le debut du geste. COURT, mais pas zero : le bruit de serrure et sa voix partiraient ensemble et se
	-- masqueraient l'un l'autre. On entend d'abord la porte resister, il repond ensuite.
	TRY_OPEN_VOICE_DELAY = 0.25,
	-- COMBIEN DE FOIS IL S'Y REPREND. A DEUX, ca racontait bien une porte qui resiste -- mais l'ecran a tranche :
	-- la scene ENTIERE devient trop longue, et une seconde secousse identique n'ajoute rien qu'on n'ait deja
	-- compris a la premiere. C'est du rythme, donc ca se juge a l'ecran, pas au raisonnement.
	--
	-- A 1, tout ce qui suit se coupe tout seul : plus de relance, donc TRY_OPEN_GAP ne sert plus a rien tant
	-- qu'on ne remonte pas ce nombre.
	TRY_OPEN_TIMES = 1,
	-- Le temps de souffle entre deux secousses. A zero elles s'enchainent sans respirer et on dirait une
	-- animation qui begaie, pas quelqu'un qui reessaie.
	TRY_OPEN_GAP = 0.25,
	-- Secondes apres le lancement avant de verifier qu'une animation a REELLEMENT bouge quelque chose. Assez
	-- tard pour qu'elle ait eu le temps d'ecrire, assez tot pour que le message serve encore.
	ANIM_CHECK_DELAY = 0.4,

	-- ELLE MENE LA SCENE. C'est elle qui declenche la porte, et c'est SA FIN qui termine la scene.
	GRANDPA_ANIM = "Scene1_oldman_OpenDoor",
	-- Marqueur DANS l'animation du grand-pere : l'instant ou sa main pousse la porte.
	-- DEUX MARQUEURS, DEUX MOUVEMENTS. Le premier tombe quand il deverrouille : la porte s'entrebaille. Le second
	-- tombe sur son geste de bras : elle s'ouvre en grand. Aucun chronometre entre les deux -- c'est l'animation
	-- qui tient le rythme, et elle reste juste quoi qu'on retouche dans l'editeur.
	-- ===== LE CARTON DE CHAPITRE =====
	-- Les barres noires disent au joueur qu'il REGARDE ; ce titre lui dit CE qu'il regarde. Nommer un moment le
	-- transforme en chapitre d'une histoire, au lieu d'une scene de plus.
	--
	-- EN ANGLAIS, comme tout ce que le joueur lit : le traducteur automatique de Roblox part de l'anglais, et un
	-- texte ecrit en francais n'est traduit nulle part.
	CHAPTER_TITLE = "CHAPTER 1 : THE GRANDFATHER",
	-- Apres le debut de la scene. Le temps que les barres finissent de descendre : un titre qui s'ecrit sur une
	-- bande encore en mouvement se fait couper par elle.
	CHAPTER_DELAY = 0.8,
	DOOR_PRE_EVENT = "PreOpenEvent",
	DOOR_START_EVENT = "OuvertureDoorEvent",

	-- Le grincement de la porte qui s'ouvre. Joue au DEBUT du mouvement, avec lui : un bruit qui arrive une fois
	-- la porte deja entrebaillee sonne en retard. Spatial, au niveau de la porte.
	OPEN_SOUND = { "Sounds", "Scenes", "Scene1", "OpenDoorSound" },

	-- ===== OUVERTURE, PAR LE CODE =====
	-- La porte tournait par une ANIMATION (`Scene1_opendoor`). Elle tourne maintenant par un angle qu'on ecrit,
	-- et l'animation n'est plus lue -- elle peut rester dans Studio, personne ne la charge.
	--
	-- CE N'EST PAS UN CAPRICE DE STYLE : une pose d'animation doit etre DEFENDUE. Une piste qui se relache, un
	-- Stop venu d'ailleurs, un rebouclage rate d'une image, et la porte se referme sans qu'on sache lequel des
	-- trois -- d'ou l'epinglage a la derniere image et sa re-affirmation a chaque frame. Un CFrame pose par le
	-- code, lui, RESTE pose. Il n'y a plus rien a defendre, donc plus rien qui puisse lacher.
	--
	-- Et chaque temps se regle ici, a la seconde. Le meme reglage dans une animation demande de rouvrir Blender,
	-- de reexporter, de recharger -- et de refaire ca a chaque essai.

	-- ELLE S'ENTREBAILLE, sur `DOOR_PRE_EVENT`. Mouvement sec : c'est la surprise, la ralentir l'enleverait. Puis
	-- elle attend -- et cette attente n'est plus un reglage : elle dure le temps que le grand-pere met entre ses
	-- deux gestes dans l'animation.
	DOOR_HALF_ANGLE = 32,
	DOOR_HALF_TIME = 0.35,
	-- ELLE S'OUVRE EN GRAND, sur `DOOR_START_EVENT`, quand sa main pousse le battant. LENTEMENT : c'est le moment
	-- ou l'on decouvre le grand-pere, et a vitesse pleine il etait fini avant qu'on ait eu le temps de regarder.
	-- 85 et pas 90 : une porte s'arrete AVANT le mur, elle ne vient pas s'y coller. Au-dela elle passe dedans --
	-- le battant n'a aucune collision, rien ne l'arrete que ce chiffre.
	DOOR_FULL_ANGLE = 85,
	DOOR_FULL_TIME = 2.2,
	-- La porte s'ouvre du mauvais cote ? Mettre true. Le sens depend de l'orientation du modele dans Studio : ca
	-- ne se DEDUIT pas, ca se voit a l'ecran.
	DOOR_OPEN_INVERT = false,

	-- ===== ELLE SE REFERME DERRIERE LUI =====
	-- Une porte qu'on laisse grande ouverte en partant, ca ne ressemble a personne -- et surtout pas a un vieux
	-- chez lui. Elle se referme quand il APPROCHE de son point d'arrivee, pas quand il y est : arrivee et
	-- fermeture au meme instant se lisent comme un declic scripte, alors qu'un battant qui retombe pendant qu'il
	-- marche encore passe inapercu -- et c'est exactement ce qu'on veut d'un detail de decor.
	--
	-- Distance en studs a `OLDMAN_WALK_TARGET` sous laquelle elle part. La monter la referme plus tot.
	DOOR_CLOSE_DISTANCE = 6,
	-- LE BRUIT DU BATTANT QUI RETOMBE. C'est le grincement de l'ouverture, faute de son dedie : une porte qui se
	-- ferme fait le meme bois qui travaille. Le jour ou tu enregistres un vrai bruit de fermeture -- avec le
	-- "clac" du loquet, qui est ce qui manque ici -- il suffit de changer ce chemin, rien d'autre.
	CLOSE_SOUND = { "Sounds", "Scenes", "Scene1", "OpenDoorSound" },
	-- Elle retombe plus vite qu'elle ne s'est ouverte : l'ouverture etait l'evenement, la fermeture n'est que du
	-- rangement. Lui donner la meme lenteur en ferait un second evenement, qui volerait l'attention au depart.
	DOOR_CLOSE_TIME = 1.2,
	-- Filet : au-dela, on renonce. Sans lui, une boucle par image tournerait pour toujours le jour ou le
	-- grand-pere reste bloque en chemin.
	DOOR_CLOSE_TIMEOUT = 30,

	-- ===== LE MARQUEUR SUR LA PORTE =====
	-- Un point d'exclamation flottant au-dessus de la porte, tant qu'on n'a pas toque. Le halo dit "cet objet
	-- compte" quand on le voit deja ; le marqueur, lui, se voit de LOIN et dit ou aller.
	--
	-- Hauteur au-dessus du centre de la porte, en studs.
	DOOR_MARKER_UP = 3.5,

	-- ===== IL S'IMPATIENTE =====
	-- Tant que la machine est encore par terre, le grand-pere relance. Une phrase de temps en temps, pas un
	-- rappel qui se repete : c'est ce qui le fait exister entre deux moments scenarises, au lieu d'attendre
	-- planté a sa porte.
	--
	-- ELLES SONT LISTEES UNE PAR UNE, et pas devinees par un prefixe et un compteur. Une liste explicite se lit,
	-- se reordonne, et en ajouter une est UNE ligne -- alors qu'un nom fabrique casse en silence le jour ou
	-- l'asset s'appelle autrement.
	IMPATIENT_SOUNDS = {
		{ "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_Impatient_1" },
		{ "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_Impatient_2" },
		{ "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_Impatient_3" },
		{ "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_Impatient_4" },
		{ "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_Impatient_5" },
	},
	-- Avant la PREMIERE. Assez long pour laisser le joueur chercher tout seul : relancer quelqu'un qui vient de
	-- recevoir sa consigne, ce n'est pas de l'impatience, c'est du harcelement.
	IMPATIENT_FIRST = 14,
	-- Puis l'ecart entre deux, plus un peu de hasard. Le hasard sert a ce qu'on ne PREVOIE pas la prochaine :
	-- une cadence reguliere se lit comme une horloge, donc comme un systeme, pas comme quelqu'un qui s'agace.
	IMPATIENT_EVERY = 16,
	IMPATIENT_JITTER = 5,
	-- IL LAISSE FINIR SA PHRASE. Quand l'heure de raler tombe pendant qu'il dit autre chose -- reposer le seau,
	-- reprendre la corde -- la grogne ATTEND cette duree apres la fin de la replique au lieu de la couper.
	--
	-- PAS ZERO : enchainer a la syllabe pres se lit comme une seule phrase bizarre, pas comme deux repliques. Il
	-- faut le temps de reprendre son souffle.
	IMPATIENT_AFTER_SPEECH = 2.5,
	-- LA GERBE D'ECLAIRS qui saute au-dessus de lui pendant qu'il rale. Hauteur au-dessus de sa RootPart, en
	-- studs : au-dessus de sa tete, jamais devant son visage -- une onomatopee qui couvre le personnage cache
	-- justement celui dont on veut lire l'humeur.
	--
	-- Elle ne remplace pas la voix, elle la DOUBLE : une voix ne s'entend pas quand on est de dos ou loin, et
	-- elle ne s'entend pas du tout chez un joueur qui a coupe le son -- ce qui est le cas d'une bonne part des
	-- joueurs Roblox.
	-- LE GRAND-PERE EST PETIT, et ces studs se comptent depuis sa RootPart -- pas depuis sa tete. Regle sur un
	-- personnage de taille normale, l'eclair flottait au-dessus de la maison.
	IMPATIENT_BURST_UP = 4.5,
	-- DECALAGE LATERAL, en studs. A ZERO : l'eclair se pose AU-DESSUS de sa tete, pas a cote.
	--
	-- Il a ete decale une version, pour ne pas couvrir son visage. A l'ecran ca ne marchait pas : l'onomatopee
	-- flottait a cote de lui sans rien designer, alors qu'au-dessus de la tete elle se lit tout de suite comme
	-- SA pensee. C'est la convention de la bande dessinee, et le joueur la connait deja.
	--
	-- Lu dans le repere de la CAMERA (voir AngerBurst) : il reste du meme cote de l'ecran quel que soit l'angle
	-- de vue. Positif = a sa droite a l'ecran.
	IMPATIENT_BURST_SIDE = 0,

	-- ===== IL LE VOIT ENFIN PRENDRE LA MACHINE =====
	-- Sa replique quand le joueur met la main sur la tondeuse : il arrete de raler et lui dit quoi faire ensuite.
	--
	-- UNE SEULE FOIS PAR PARTIE. Lachez la machine, reprenez-la : il ne recommence pas. Une phrase scenarisee qui
	-- se rejoue a chaque prise cesse d'etre une reaction et devient un bruit de porte.
	PULL_ROPE_SOUND = { "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_PullTheRope" },
	-- ET S'IL LA REPOSE juste apres qu'on lui a dit de tirer la corde : il le reprend. C'est ce genre de reaction
	-- a une BETISE du joueur qui fait qu'un PNJ a l'air de regarder, au lieu de reciter un script.
	GRAB_AGAIN_SOUND = { "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_GrabMowerAgain" },
	-- Ecart minimum entre deux fois, en secondes. Celle-la se rejoue -- contrairement a PULL_ROPE, dite une seule
	-- fois -- parce qu'elle repond a une action REPETABLE. Sans ce garde, prendre et lacher la machine en boucle
	-- la ferait bafouiller, et une reaction qui se declenche trop vite cesse d'etre une reaction.
	GRAB_AGAIN_COOLDOWN = 9,
	-- ET S'IL LA REPREND, toujours sans l'avoir demarree : il redit de tirer la corde, autrement. Une SECONDE
	-- formulation et pas la premiere rejouee -- reentendre mot pour mot ce qu'on vient d'entendre sonne comme une
	-- bande qui saute, alors qu'une variante sonne comme quelqu'un qui insiste.
	PULL_ROPE_AGAIN_SOUND = { "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_Pulltherope2" },
	-- Son propre ecart minimum, separe de celui de la repose. Les deux repliques encadrent le meme aller-retour
	-- (lacher puis reprendre) : un reglage partage par les deux finirait par en desservir une.
	PULL_ROPE_AGAIN_COOLDOWN = 9,
	-- ET LE MOTEUR PART. Sa replique de satisfaction : c'est la premiere fois du jeu qu'on lui donne raison, et
	-- c'est le seul moment de tout le tuto ou il est content.
	--
	-- UNE SEULE FOIS. Le moteur peut caler et repartir ; le feliciter a chaque fois viderait la phrase de ce
	-- qu'elle dit.
	PERFECT_SOUND = { "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_Perfect" },
	-- ET S'IL PREND LE SEAU alors qu'on lui demande de tondre : le grand-pere lui dit de le reposer.
	--
	-- POURQUOI CA COMPTE. Un joueur qui attrape le mauvais outil ne sait pas qu'il s'est trompe : rien ne le lui
	-- dit, et il peut passer une minute a chercher quoi en faire. Une phrase le remet tout de suite dans le bon
	-- geste -- et c'est plus fort qu'un texte, parce que ca vient de quelqu'un qui le regarde.
	-- PLUSIEURS FACONS DE LE DIRE, tirees au hasard. Le joueur reprend le seau plus souvent qu'on ne le croit, et
	-- reentendre mot pour mot la meme phrase transforme un personnage en machine a messages.
	PUT_BIN_DOWN_SOUNDS = {
		{ "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_PutBinDown" },
		{ "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_PutBinDown2" },
		{ "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_PutBinDown3" },
	},
	-- Ecart minimum entre deux fois, en secondes. Le joueur peut prendre et reposer le seau en boucle : sans ce
	-- garde, il se ferait sermonner a chaque aller-retour, et la phrase deviendrait un bruit de porte.
	PUT_BIN_DOWN_COOLDOWN = 10,
	-- ===== LA PELOUSE EST TONDUE : IL RAPPELLE LE JOUEUR =====
	-- La tache se terminait en gris et plus rien ne se passait. Un joueur qui vient de finir son premier travail
	-- doit savoir OU aller ensuite, tout de suite : c'est le moment ou il decide s'il en fait un deuxieme.
	--
	-- Sa replique part a l'instant ou la derniere touffe tombe, et le marqueur se pose sur lui dans le meme
	-- geste : la voix dit de venir, le dessin dit ou.
	LAWN_DONE_SOUND = { "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_PerfectComeSeeMe" },
	-- ET CE QU'IL DIT QUAND LE JOUEUR ARRIVE. Il n'enchaine sur aucune tache pour le moment : la suite du
	-- scenario n'est pas ecrite, et donner une consigne qui n'existe pas serait pire que de ne rien donner.
	TALK_SOUND = { "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_HeppyForCutGrass" },
	-- ET S'IL VIENT LE VOIR SANS AVOIR FINI. Le joueur qui abandonne a mi-chemin et revient chercher la suite
	-- recoit une reponse, au lieu d'un badge qui ne fait rien : une action sans effet se lit comme un bug.
	TALK_UNDONE_SOUND = { "Sounds", "Scenes", "Scene1", "Voices", "Oldman_scene_speech_DidntFinishItAll" },
	-- Ecart minimum entre deux fois, en secondes. Celle-la se REJOUE, contrairement aux felicitations : c'est une
	-- reponse, pas une recompense. Mais un joueur qui reste plante devant lui ne doit pas l'entendre en boucle.
	TALK_UNDONE_COOLDOWN = 9,
	-- COMBIEN DE PELOUSE IL FAUT AVOIR TONDU pour avoir le droit de lui parler, en fraction.
	--
	-- SANS CA LE BADGE SORTAIT TOUT DE SUITE : on prenait la machine, on passait devant lui, et on pouvait deja
	-- lui parler sans avoir coupe un brin. La phrase "tu n'as pas fini" n'a de sens que si on a COMMENCE ; avant,
	-- elle repond a une question que le joueur ne s'est pas encore posee.
	TALK_MIN_PROGRESS = 0.15,
	-- Hauteur du marqueur au-dessus de sa RootPart, en studs. Plus haut que celui de la tondeuse : il est DEBOUT,
	-- et un point d'exclamation pose a hauteur de poitrine se lit comme un badge sur lui, pas comme un appel.
	--
	-- SA ROOTPART EST BASSE : elle sort du 3D Importer, donc elle est posee au PIED du rig et pas a mi-torse
	-- comme sur un personnage Roblox. Toutes les hauteurs de ce bloc se comptent donc depuis le SOL sous lui.
	--
	-- BIEN AU-DESSUS DE SA TETE, et pas juste au-dessus : le marqueur doit se lire de loin, par-dessus lui. Pose
	-- trop pres du crane il se lit comme un chapeau, pas comme un appel -- et il masque le visage qu'on regarde.
	GRANDPA_MARKER_UP = 15.5,
	-- A quelle distance le badge "PARLER" apparait, en studs. DISTANCE RADIALE, comme celle de la porte : une
	-- boite orientee laisse des angles morts, et il se promene -- il n'a aucune orientation stable.
	TALK_RADIUS = 11,
	TALK_PROMPT_KEY = "E",
	TALK_PROMPT_LABEL = "TALK",
	TALK_PROMPT_TITLE = "GRANDPA",
	-- Au-dessus de sa tete, mais SOUS le marqueur : les deux se liraient l'un sur l'autre. A 4.4 le badge tombait
	-- a ses pieds -- voir la note de GRANDPA_MARKER_UP : la hauteur part du sol, pas de son torse.
	TALK_PROMPT_OFFSET = Vector3.new(0, 7.5, 0),
	TALK_ACTION_NAME = "LeafiaTutorialTalk",

	-- SON VISAGE PENDANT QU'IL RALE. Jouee une fois a chaque replique.
	--
	-- EN `Action2`, une priorite AU-DESSUS de son explication (`Action`). A priorite EGALE Roblox ne choisit pas,
	-- il MELANGE : la tete recevrait la moyenne des deux poses, et on obtiendrait un visage "presque bon" qu'on
	-- irait corriger dans l'editeur alors que le probleme est ici.
	IMPATIENT_FACE_ANIM = "rbxassetid://138039446311488",
	IMPATIENT_FACE_PRIORITY = Enum.AnimationPriority.Action2,
	-- Fondu d'entree. Court : une grimace qui arrive en douceur n'est plus une grimace.
	IMPATIENT_FACE_FADE = 0.1,

	-- ===== LE MEME MARQUEUR, SUR LA TONDEUSE =====
	-- Hauteur au-dessus de la RootPart de la machine, en studs. PLUS BAS que celui de la porte : une tondeuse
	-- arrive a la taille, une porte fait deux metres. Le marqueur doit flotter juste au-dessus de l'objet qu'il
	-- designe -- trop haut, il montre le ciel et on cherche ce qu'il pointe.
	--
	-- SON PROPRE REGLAGE, et pas celui de la porte : deux objets de tailles differentes, et un reglage partage par
	-- deux moments finit toujours par les opposer.
	MOWER_MARKER_UP = 4,

	-- ===== IL EXPLIQUE POURQUOI IL A BESOIN DE NOUS =====
	-- Deuxieme replique, dite une fois qu'il a MARCHE jusque devant sa porte. C'est le serveur qui previent de son
	-- arrivee : la marche se fait chez lui, image par image, et une duree devinee cote client se decalerait des
	-- qu'on change sa vitesse ou la distance.
	--
	-- PLUS DE FICHIER SON POUR CETTE REPLIQUE : elle a ete retiree, et le chemin avec elle. Il ne restait qu'un
	-- avertissement de son introuvable a chaque scene -- un warn sur un cas NORMAL finit par etre ignore, et il
	-- emporte les vrais avec lui. Le TEXTE, lui, reste : il avance tout seul sur les `hold` ci-dessous.
	-- Il souffle en arrivant avant de parler. A zero il enchaine sans avoir repris son souffle -- et il vient de
	-- traverser sa cour.
	SPEECH2_DELAY = 0.6,
	-- LE NOM AFFICHE dans la pastille jaune. Ici et nulle part ailleurs : le jour ou il a un vrai prenom, il
	-- change a un seul endroit.
	SPEECH2_SPEAKER = "GRANDPA",
	-- SA REPLIQUE, DECOUPEE. Chaque ligne porte sa duree : elles avancent TOUTES SEULES, sans que le joueur ait a
	-- taper. Sur une replique doublee c'est obligatoire -- faire avancer a la main desynchronise le texte de la
	-- voix des la premiere ligne, et plus rien ne les recale ensuite.
	--
	-- LA SOMME DES `hold` DOIT VALOIR LA DUREE DU FICHIER SON (14.68 s pour Oldman_scene_speech_2). Ces valeurs
	-- sont proportionnelles a la longueur du texte : c'est une premiere approximation, elle se REGLE A L'OREILLE.
	-- Une ligne qui passe avant que la voix l'ait dite est le signe qu'il faut monter son `hold` et baisser celui
	-- d'a cote, pas allonger le total.
	--
	-- `emotion` est une cle de la table EMOTIONS de Dialogue : normal / happy / sad / angry / shocked / wink.
	SPEECH2_LINES = {
		{
			-- SANS TIRET CADRATIN au milieu : deux phrases nettes a la place. Un tiret long se lit mal a l'ecran,
			-- et le traducteur automatique de Roblox le rend n'importe comment.
			text = "As you can see, I'm too old for this. My back's giving out, I can't mow the lawn anymore.",
			emotion = "sad",
			hold = 6.2,
		},
		-- IL ANNONCE SON CARACTERE LUI-MEME, et c'est la meilleure place pour le dire : ses coups de gueule
		-- deviennent une blague qu'il a faite d'avance, au lieu d'une surprise qui ressemble a une faute du joueur.
		{ text = "Watch out, I shout sometimes. Haha!", emotion = "happy", hold = 2.6 },
	},

	-- ===== LES OBJECTIFS =====
	-- EN ANGLAIS, comme tout texte vu par le joueur. Le traducteur de Roblox part de l'anglais : un texte ecrit en
	-- francais n'est traduit NULLE PART, et le jeu devient illisible pour la quasi-totalite de la plateforme.
	--
	-- ILS ARRIVENT L'UN APRES L'AUTRE, et jamais avant d'avoir un sens. Le bandeau ne s'affiche plus au spawn :
	-- pendant l'ouverture, la seule chose a faire est d'aller toquer, et le halo sur la porte le dit deja mieux
	-- qu'une ligne de texte. Un objectif qu'on ne peut pas encore accomplir n'est pas un guide, c'est du bruit.

	-- ===== ON PREVIENT QUE LE GRAND-PERE A UN CARACTERE =====
	-- Une notification laterale, une fois qu'il a fini de parler. Sans elle, ses coups de gueule arrivent sans
	-- prevenir : le joueur croit avoir fait une faute, ou pire, que le jeu bugue. Annonces, ils deviennent un
	-- TRAIT DE CARACTERE -- et c'est ce qui donne envie de ne pas le faire attendre.
	--
	-- `Warning` : le rouge-orange de l'interface, avec son icone. Pas `Info` -- ce n'est pas un renseignement,
	-- c'est un avertissement.
	--
	-- EN ANGLAIS, comme tout texte vu par le joueur, et en mots simples : le public a dix ans.
	GRUMPY_NOTIF = {
		kind = "Warning",
		title = "Grandpa Is Watching",
		description = "He gets angry if you take too long. Do what he asks and he calms down.",
		duration = 14,
	},
	-- Apres la fin de sa replique. Il laisse la place au bandeau de tache, qui arrive au meme instant : les deux
	-- ensemble se marchent dessus, et on ne lit ni l'un ni l'autre.
	GRUMPY_NOTIF_DELAY = 1.6,

	-- 1) DEMARRER LA MACHINE, des qu'il a fini de parler.
	MOWER_TASK_TITLE = "START THE MOWER",
	-- AUCUNE RECOMPENSE : c'est une ETAPE, pas un chantier. Afficher une piece pour un geste qui ne paie rien
	-- apprend au joueur que les chiffres du bandeau ne veulent rien dire -- et il ne les lira plus.
	MOWER_TASK_REWARD = "",
	-- L'ICONE ET LA TEINTE de cette tache. Cles de `TaskConfigs` et non ids en dur : l'image se change a un seul
	-- endroit, et une cle fausse se signale au lieu d'afficher un carre vide.
	--
	-- BLEU : c'est la teinte des OUTILS dans TaskConfigs (aller chercher, equiper, demarrer une machine). Le vert
	-- est celui du vegetal, et il est garde pour la tonte elle-meme -- deux taches de la meme couleur se lisent
	-- comme la meme tache.
	MOWER_TASK_ICON = "Mower",
	MOWER_TASK_TINT = "Blue",

	-- 2) TONDRE, une fois la machine lancee.
	LAWN_TASK_TITLE = "MOW THE LAWN",
	-- La recompense est ECRITE, pas calculee : rien ne la verse encore. Le jour ou elle le sera, elle viendra de
	-- la source qui paie -- une valeur affichee qui ne correspond pas a ce qu'on recoit est pire que pas de
	-- valeur du tout.
	-- SANS L'UNITE : l'image de la monnaie est affichee juste a cote et le dit deja. "+ 50 XP" a cote d'une piece
	-- se lit comme une contradiction.
	LAWN_TASK_REWARD = "+ 50",
	-- Une cle de `TaskConfigs.CURRENCIES`. Sans elle, aucune image ne s'affiche a cote du chiffre.
	LAWN_TASK_CURRENCY = "Coins",
	LAWN_TASK_ICON = "Grass",
	LAWN_TASK_TINT = "Green",
	-- Souffle entre le grisage de la tache finie et l'arrivee de la suivante. Les deux au meme instant se lisent
	-- comme un remplacement ; separes, on voit d'abord qu'on a REUSSI, ensuite ce qui reste a faire.
	LAWN_TASK_DELAY = 0.9,

	-- ===== LA PARCELLE A TONDRE =====
	-- Une PART posee dans Studio, qui delimite le carre que le joueur doit tondre. Tout ce qui pousse dehors est
	-- pose DEJA COUPE.
	--
	-- POURQUOI UNE PART ET PAS UN RAYON. La forme du bout de pelouse a faire se decide a l'oeil, dans la map, en
	-- la deplacant et en la retaillant. Un rayon autour d'un point obligerait a re-regler un nombre a chaque fois
	-- qu'on bouge un massif, et ne saurait pas faire un rectangle.
	--
	-- Cherchee par son NOM, comme la porte et le point d'arrivee : on ne suppose aucun rangement. Rojo ne
	-- synchronise pas le Workspace, elle doit exister dans CETTE place.
	AREA_GRASS_NAME = "AreaGrassTutorial",
	-- A PARTIR DE QUELLE PART la tonte compte comme finie. JAMAIS 1 : il reste toujours une touffe coincee sous un
	-- massif ou contre une bordure, et chercher la derniere n'est pas du jeu, c'est de la chasse au pixel. Meme
	-- raison que l'auto-complete des haies.
	LAWN_DONE_AT = 0.95,
	-- A QUELLE FREQUENCE on recompte, en secondes. Compter chaque image parcourrait toutes les touffes de la map
	-- soixante fois par seconde pour une barre qui n'avance que d'un cheveu : ca ne se verrait pas, et ca coute.
	LAWN_COUNT_INTERVAL = 0.4,

	-- ===== LE GRAND-PERE SORT DE CHEZ LUI =====
	-- La scene finie, il ne reste pas plante dans l'embrasure : il marche jusque devant sa porte.
	--
	-- L'ID vit ICI, en code, et pas dans une Instance Animation : Rojo synchronise le code dans TOUTES les places,
	-- les Instances non (`Animations` est en `$ignoreUnknownInstances`, il se recopie a la main place par place).
	OLDMAN_WALK_ANIM = "rbxassetid://123299879163087",
	-- AU-DESSUS de son idle, qui tourne en permanence (AmbientAnimService, priorite `Idle`). En dessous ou a
	-- EGALITE, Roblox melangerait les deux poses au lieu de choisir : on obtiendrait une marche "presque bonne".
	-- Et comme l'idle continue dessous, il suffit d'ARRETER la marche pour qu'il revienne s'y poser.
	--
	-- CETTE VALEUR ECRASE CELLE DE L'EDITEUR. La priorite reglee dans l'editeur d'animation n'est qu'une
	-- suggestion : le code la repose a chaque lecture, donc c'est CE nombre-la qui compte.
	--
	-- ET ELLE DOIT RESTER SOUS `Action`, ou vit son geste d'explication. En `Action4` la marche gagnerait sur les
	-- bras et le torse, donc elle EFFACERAIT l'explication qu'elle est censee accompagner : il traverserait sa
	-- cour sans plus rien raconter. L'empilement voulu est idle < marche < explication -- les jambes a la marche,
	-- le haut du corps a l'explication.
	OLDMAN_WALK_PRIORITY = Enum.AnimationPriority.Movement,
	-- OU IL VA : une part posee dans Studio. Pas un point calcule -- le pas exact ou s'arrete un personnage dans
	-- une scene se decide a l'oeil, pas par une formule, et le deplacer ne doit demander aucun code.
	OLDMAN_WALK_TARGET = "OldManWalkTo",
	-- OU IL VA APRES AVOIR FELICITE LE JOUEUR : l'arriere du camion, ou sont les outils. Une part posee dans
	-- Studio, comme son point de sortie -- deplacer le camion n'oblige alors a toucher aucune ligne de code.
	OLDMAN_TRUCK_TARGET = "OldManWalkToTruck",
	-- IL SE TOURNE VERS LE JOUEUR POUR LUI PARLER, en tant de secondes. On ne parle pas de profil a quelqu'un
	-- qu'on felicite.
	--
	-- PAS INSTANTANE : un demi-tour pose en une image se lit comme un bug de rig. Mais pas long non plus, il
	-- repond a quelqu'un qui vient de l'interpeller.
	FACE_PLAYER_TIME = 0.45,
	-- Sa vitesse de marche, en studs/s.
	-- LENT, et c'est le sujet du plan. C'est un vieux monsieur avec une canne qui sort de chez lui : le voir
	-- traverser prend du temps, et ce temps EST ce qu'on raconte. L'animation suit cette vitesse toute seule
	-- (rapport avec OLDMAN_WALK_REFERENCE), donc baisser ce chiffre ralentit le pas ET le pied ne patine pas.
	OLDMAN_WALK_SPEED = 4,
	-- Vitesse pour laquelle l'animation a ete faite. La piste est jouee au rapport des deux, donc changer la
	-- vitesse ci-dessus ne fait pas patiner ses pieds -- et il n'y a aucune seconde valeur a garder d'accord.
	OLDMAN_WALK_REFERENCE = 8,
	-- SES JAMBES SEULES, plus vite. Multiplie la vitesse de l'ANIMATION sans toucher au trajet : il met le meme
	-- temps a traverser, mais il pietine au lieu de glisser.
	--
	-- C'EST UN DECOUPLAGE ASSUME, et il a un prix : au-dela de 1 ses pieds patinent, puisqu'ils avancent plus vite
	-- que lui. C'est justement l'effet cherche ici -- un vieux qui fait beaucoup de petits pas pour avancer peu --
	-- mais trop haut, ca se voit comme un bug. A 1, le rapport d'origine est retabli et rien ne patine.
	OLDMAN_WALK_ANIM_BOOST = 1.6,
	-- SON IDLE, par CHEMIN et pas par ID : l'Animation existe deja dans ReplicatedStorage, il n'y a aucune raison
	-- d'en recopier l'identifiant ici -- deux endroits a garder d'accord pour rien.
	--
	-- Il n'est joue QUE SI aucun idle ne tourne deja. `AmbientAnimService` en lance un au demarrage : le rejouer
	-- en ferait DEUX a la meme priorite, et Roblox n'en choisit pas un -- il les MELANGE.
	OLDMAN_IDLE_PATH = { "Player", "OldMan", "Idle" },

	-- Delai avant de VERIFIER que l'idle qu'on vient de poser joue vraiment. Une piste dont l'asset n'arrive
	-- jamais garde une longueur de zero pour toujours : le grand-pere resterait fige, sans la moindre erreur.
	-- Assez long pour laisser le telechargement finir, assez court pour que le joueur ne voie pas la statue.
	-- LE JOUEUR SE POUSSE, une fois qu'il a fini de toquer : il libere le passage pour le grand-pere. Enchainee a
	-- la fin de KNOCK_ANIM, elle tient sa derniere image comme elle -- il reste sur le cote tant que la scene dure.
	KNOCK_ASIDE_ANIM = "Scene1_TocToc2_Animation",
	-- Fondu entre les coups et le pas de cote. Les deux pistes sont en priorite Action : a priorite EGALE Roblox
	-- ne choisit pas, il MELANGE. Ce fondu est donc une transition VOULUE et courte -- au-dela on lirait une pose
	-- moyenne entre les deux, ce qui ne ressemble a rien.
	KNOCK_ASIDE_FADE = 0.2,
	-- DELAI APRES LE DEPART DU GRAND-PERE. Le pas de cote n'a de sens qu'une fois qu'il MARCHE : se decaler
	-- pendant qu'il se bat encore avec sa poignee, c'est se pousser devant une porte fermee.
	--
	-- Le compte part de l'ordre envoye au serveur, pas d'un instant devine dans la scene : c'est le seul moment
	-- qui reste juste si on rallonge la cinematique. Il reste ce petit delai a regler parce que l'ordre doit
	-- encore faire l'aller-retour et que le grand-pere met une fraction de seconde a demarrer pour de bon.
	KNOCK_ASIDE_DELAY = 0.35,
	-- FONDU DE RELACHEMENT de la pose de scene, quand les commandes reviennent au joueur.
	--
	-- SON PROPRE REGLAGE, et pas `KNOCK_ASIDE_FADE`. Les deux fondus n'ont rien a voir : celui-la est un
	-- CROISEMENT entre deux poses de scene (les coups qui laissent la place au pas de cote), celui-ci est une
	-- SORTIE vers le deplacement normal. Un reglage partage par deux moments finit toujours par les opposer.
	--
	-- Un peu plus long : le personnage se REDRESSE, et ca doit se lire comme un mouvement, pas comme un
	-- claquement de doigts.
	ASIDE_RELEASE_FADE = 0.35,

	-- ===== CE QUE L'ANIMATION A DEPLACE, ON LE REND AU PERSONNAGE =====
	-- Les poses de scene bougent le corps par son LowerTorso : le joueur qui se pousse sur le cote se DEPLACE a
	-- l'ecran, mais sa HumanoidRootPart -- la seule que la physique connaisse -- n'a pas bouge d'un stud.
	-- Relacher la pose ramene donc le corps sur sa racine, d'un coup : il se teleporte en arriere a l'instant
	-- precis ou on lui rend la main, ce qui se lit comme des commandes cassees.
	--
	-- On mesure l'ecart HORIZONTAL entre les deux, on l'applique a la racine, et on coupe la pose SANS FONDU --
	-- les deux dans la meme image. Ce qu'on retire au Transform de l'animation, on vient de l'ajouter a la racine :
	-- rien ne bouge a l'ecran. Avec un fondu, le corps se retrouverait a DEUX fois l'ecart le temps qu'il
	-- redescende, soit un saut deux fois pire que celui qu'on repare.
	--
	-- SOUS CE SEUIL on ne touche a rien : c'est du bruit, et deplacer un joueur pour trois centimetres est un
	-- risque pour rien.
	DRIFT_MIN = 0.08,
	-- ET AU-DESSUS, ON RENONCE. Une animation qui deplacerait le corps de dix studs teleporterait le joueur, sans
	-- rien pour verifier qu'il y a de la place a l'arrivee. Mieux vaut le saut visuel qu'un joueur dans un mur.
	DRIFT_MAX = 6,
	-- ET LA MEME CHOSE POUR LE CAP. Une animation qui fait pivoter le corps le tourne A L'ECRAN sans toucher a la
	-- racine : relachee, il se remet d'un coup face a sa direction d'avant. Un demi-tour joue dans l'animation se
	-- perd donc entierement -- le joueur se retrouve dos a l'endroit ou il croyait regarder.
	--
	-- On ne prend que le YAW, la rotation autour de la verticale. Le tangage et le roulis appartiennent a la pose
	-- (il se penche), pas a sa direction : les appliquer coucherait le personnage.
	--
	-- Borne en degres, un peu au-dela de 180 : un demi-tour doit passer, une valeur aberrante non.
	DRIFT_YAW_MAX = 200,
	-- Sous ce seuil, c'est du bruit de pose : on ne fait pas pivoter un joueur pour un degre.
	DRIFT_YAW_MIN = 2,

	-- A quelle distance de la FIN on fige l'animation de coups, en secondes. Le gel doit tomber JUSTE AVANT la
	-- derniere image : trop tot on coupe le dernier geste, trop tard on rate la fenetre et la piste reboucle.
	-- 0.05 s vaut une a trois images -- la pose de fin, sans le risque.
	KNOCK_HOLD_MARGIN = 0.05,

	OLDMAN_IDLE_CHECK = 3,
	-- Ecart entre les deux releves de pose du controle. Assez long pour qu'une animation lente ait bouge, assez
	-- court pour ne pas laisser une statue a l'ecran si le verdict est mauvais.
	OLDMAN_IDLE_SAMPLE = 0.35,

	-- ===== IL PARLE AVEC LES BRAS =====
	-- Arrive devant sa porte, il EXPLIQUE. Sans cette piste il debite quinze secondes de texte sans un geste, et
	-- le plan devient une photo.
	--
	-- L'ID vit ICI, en code, comme celui de la marche : Rojo synchronise le code dans TOUTES les places, les
	-- Instances non (`Animations` est en `$ignoreUnknownInstances`, elles se recopient a la main place par place).
	OLDMAN_TALK_ANIM = "rbxassetid://107093983212125",
	-- AU-DESSUS de l'idle (priorite `Idle`), qui continue de tourner dessous : il suffit d'ARRETER celle-ci pour
	-- qu'il revienne respirer, sans rien avoir a reposer. En `Action` et pas en `Movement` : Movement est la
	-- priorite de sa marche, et deux pistes a priorite EGALE ne se choisissent pas -- Roblox les MELANGE.
	OLDMAN_TALK_PRIORITY = Enum.AnimationPriority.Action,
	-- ELLE JOUE EN ENTIER, UNE FOIS. Donc pas de boucle : la piste se relache a sa derniere image.
	--
	-- POURQUOI CE CHOIX. Elle a d'abord ete bouclee et COUPEE quand il finissait de parler -- la duree venait de
	-- la replique. Mais elle porte un MARQUEUR a 14.92 s, et on ne la jouait que douze secondes : il n'etait
	-- jamais atteint. C'est l'animation qui decide maintenant, comme celle de la porte decide de la fin de la
	-- scene. Le prix : il gesticule quelques secondes apres avoir fini de parler.
	OLDMAN_TALK_LOOP = false,
	-- MARQUEUR POSE DANS CETTE ANIMATION-LA, pas dans celles de la scene. Pour l'instant il ne fait qu'un LOG : on
	-- verifie qu'il tire, et a quel instant, avant de lui accrocher quoi que ce soit.
	--
	-- ELLE EST JOUEE PAR LE SERVEUR (le grand-pere est un modele du monde), donc c'est le SERVEUR qui l'ecoute.
	-- Un marqueur ne se signale qu'a la machine qui LIT la piste : le client ne le verra jamais.
	--
	-- ET ELLE BOUCLE tant qu'il parle, donc le marqueur retombe a CHAQUE tour. Le message donne le numero de tour
	-- pour que ca se voie tout de suite.
	END_FOCUS_EVENT = "EndFocusPlayerEvent",
	-- FILET, en secondes apres la fin du dialogue. La consigne arrive normalement sur le marqueur ci-dessus ; si
	-- celui-ci ne tombe jamais -- animation republiee sans lui, asset qui ne charge pas -- le joueur resterait
	-- devant un jardin sans savoir ce qu'on lui demande. Passe ce delai, on l'affiche quand meme.
	--
	-- Un tuto qui depend d'un marqueur d'animation pour donner sa consigne doit pouvoir s'en passer : c'est la
	-- seule chose qu'il fait, et elle ne peut pas ne pas arriver.
	END_FOCUS_FALLBACK = 8,

	-- ===== IL SUIT LE JOUEUR JUSQU'A LA TONDEUSE =====
	-- Une fois la consigne donnee, le grand-pere ne reste pas plante devant sa porte : il emboite le pas au joueur
	-- qui part chercher la machine. Ce n'est pas un chantier a lui, c'est ce qui le fait exister -- un PNJ qui
	-- regarde le joueur travailler de vingt metres n'accompagne rien.
	--
	-- IL S'ARRETE des que la tondeuse est dans les mains du joueur : sa consigne est suivie, il n'a plus rien a
	-- surveiller.
	--
	-- CE QU'IL VISE : LA TONDEUSE, pas le joueur.
	--
	-- LA PREMIERE VERSION SUIVAIT LE JOUEUR, et ca se voyait : une cible qui bouge a chaque image donne un PNJ
	-- collant, qui repart et s'arrete des que l'autre change de pied. Un vieux monsieur ne fait pas ca. Ce qui
	-- l'interesse, c'est la MACHINE -- il va la ou le travail va se faire, et le joueur s'y rend en meme temps
	-- que lui. Une cible FIXE donne un deplacement lisse, sans qu'on ait rien a lisser.
	--
	-- Distance a laquelle il s'arrete de la machine, en studs. A 12 il restait spectateur a l'autre bout de la
	-- pelouse : de pres, il DESIGNE la machine -- on comprend ce qu'il montre sans qu'il ait a le dire.
	--
	-- IL NE PEUT PAS TOUJOURS Y ARRIVER, et c'est voulu : `FOLLOW_MIN_PLAYER` l'arrete avant s'il devait entrer
	-- dans le dos du joueur. Le joueur colle a la machine gagne, lui attend a cote.
	FOLLOW_MOWER_DIST = 7,
	-- HYSTERESIS : de combien il faut la depasser pour qu'il REPARTE. Sans elle, arrete pile a la distance
	-- d'arret, il repart au moindre centimetre -- des micro-pas permanents, ce qui est exactement le tic qu'on
	-- veut eviter.
	FOLLOW_HYST = 1.5,
	-- ET IL NE COLLE PAS AU JOUEUR. S'approcher plus pres que ca le ferait entrer dans son dos et passer devant
	-- la camera. Il s'arrete alors, meme s'il n'est pas encore arrive a la machine -- et il s'arrete SANS se
	-- tourner vers lui : c'est ce pivot qui gachait la sortie de la scene, joueur colle a sa porte.
	FOLLOW_MIN_PLAYER = 4.5,
	-- SON TEMPS DE REACTION, en secondes. Il ne s'ebranle pas a la milliseconde ou le joueur bouge : ce petit
	-- retard est ce qui separe un vieux monsieur d'un chien de garde.
	FOLLOW_DELAY = 1.2,
	-- VITESSE A LAQUELLE IL TOURNE, en fraction de l'ecart rattrapee par seconde.
	--
	-- IL FAISAIT DES ZIGZAG SANS ELLE, du temps ou son cap etait pose d'un coup a chaque image. Il n'a plus
	-- qu'une cible -- la machine, et seulement pendant qu'il marche -- donc l'alternance n'existe plus.
	--
	-- ELLE RESTE UTILE POUR AUTRE CHOSE : une machine reposee ailleurs pendant qu'il avance change sa cible, et
	-- un demi-tour instantane sur un PNJ qui marche se lit comme un bug de rig.
	FOLLOW_TURN = 6,
	-- A QUELLE FREQUENCE il re-cherche la machine, en secondes.
	--
	-- DEUXIEME CAUSE DES ZIGZAG : la cible etait re-choisie a CHAQUE IMAGE, depuis la position du joueur. Avec
	-- deux machines a peu pres a egale distance, elle changeait d'une image a l'autre -- il partait vers l'une,
	-- puis l'autre, sans avancer. Et un balayage de tout le Workspace par image coute cher pour rien : la reponse
	-- ne change pas soixante fois par seconde.
	FOLLOW_RESCAN = 0.75,
	-- SA VITESSE DE SUIVI, en studs/s. SON PROPRE REGLAGE, separe de sa marche de sortie (OLDMAN_WALK_SPEED, 4) :
	-- celle-la est LENTE parce qu'elle est le sujet du plan, alors qu'ici il doit tenir le rythme de quelqu'un qui
	-- traverse un jardin. Un reglage partage par les deux moments aurait fini par les opposer.
	--
	-- BIEN SOUS la vitesse de marche du joueur : il reste derriere, ce qui est exactement l'effet voulu, et a
	-- 8 studs/s il trottait -- un vieux monsieur a canne ne trottine pas. L'animation suit toute seule (elle est
	-- jouee au rapport de cette valeur), donc baisser ce chiffre ralentit le pas sans faire patiner ses pieds.
	FOLLOW_SPEED = 5.5,
	-- Vitesse de son animation de pas quand il suit, en multiple. Comme pour sa sortie, elle est jouee au RAPPORT
	-- de sa vitesse reelle sur OLDMAN_WALK_REFERENCE : ce facteur ne fait que l'accentuer, sans toucher au trajet.
	FOLLOW_ANIM_BOOST = 1.2,
	-- Fondu de son animation de pas, a l'arret comme au demarrage. Court : un vieux qui repart doit repartir, pas
	-- se fondre.
	FOLLOW_ANIM_FADE = 0.15,

	-- ===== ET ENTRE DEUX, IL SE PROMENE =====
	-- La machine une fois dans les mains du joueur, il n'a plus rien a faire -- et il restait plante la jusqu'a la
	-- fin du tuto. Quelqu'un d'immobile pendant deux minutes cesse d'etre un personnage et devient un decor.
	--
	-- DANS UNE PART POSEE DANS STUDIO, jamais dans un rayon autour de lui : un rayon l'enverrait dans la maison,
	-- dans un massif ou sur la route. La zone dit une fois pour toutes ou il a le droit d'aller, et elle se
	-- corrige a la souris -- ce qu'aucun chiffre ici ne sait faire.
	WALK_ZONE_NAME = "ZoneWalking",
	-- IL RESTE PRES DU JOUEUR : rayon maximum, mesure DEPUIS LE JOUEUR, du point qu'il peut choisir. La zone fait
	-- plus de cent studs de cote -- sans cette borne il partirait a l'autre bout du jardin, ou personne ne le voit
	-- et ou il ne raconte plus rien.
	STROLL_NEAR_PLAYER = 40,
	-- Et pas trop pres de LUI : sous cette distance le trajet ne vaut pas la peine d'etre joue, on verrait un pas
	-- et demi -- ce qui se lit comme un tic, pas comme une promenade.
	STROLL_MIN_DIST = 12,
	-- SON ALLURE DE FLANERIE. Plus lente encore que son suivi : la il ne va nulle part, il occupe le temps. Son
	-- propre reglage, parce que les deux moments n'ont pas le meme sens et finiraient par s'opposer.
	STROLL_SPEED = 3,
	-- Combien de temps il reste en place entre deux promenades, tire au hasard entre les deux bornes. Le hasard
	-- sert a ce qu'on ne PREVOIE pas le prochain depart : une cadence reguliere se lit comme une horloge.
	STROLL_WAIT_MIN = 8,
	STROLL_WAIT_MAX = 20,
	-- Distance a laquelle il considere etre arrive, en studs.
	STROLL_ARRIVE = 1.2,
	-- Combien de points il tire avant d'abandonner ce tour-ci. Toute la zone n'est pas du sol praticable et le
	-- joueur peut se tenir a son bord : quand rien ne convient, on retente plus tard plutot que de boucler.
	STROLL_TRIES = 12,
	STROLL_RETRY = 2,
	-- IL LAISSE TOMBER UNE CIBLE DEVENUE TROP LOIN DU JOUEUR. Le joueur marche pendant qu'il marche : sans cette
	-- laisse, il finirait tranquillement son trajet vers un coin que le joueur a quitte depuis longtemps.
	STROLL_LEASH = 60,
	-- Fondus d'entree ET de sortie. L'entree croise l'idle, la sortie y revient : sans eux les bras SAUTENT a la
	-- pose de repos au dernier mot.
	OLDMAN_TALK_FADE = 0.3,
	-- DUREE MAXIMALE qu'une replique peut demander, en secondes. Le client annonce la longueur de son fichier son :
	-- la valeur vient de LUI, donc on la borne. Le pire qu'un client modifie puisse faire est de faire gesticuler
	-- un PNJ, mais une duree absurde l'y figerait pour le reste de la partie.
	--
	-- Large : elle doit laisser passer la plus longue replique reelle sans la couper. Une borne plus serree que la
	-- donnee qu'elle borne coupe le cas normal en croyant arreter un abus.
	OLDMAN_TALK_MAX = 60,

	-- Distance de recherche du sol sous lui, en studs. Il est ANCRE, donc la physique ne le pose pas : on mesure
	-- sa hauteur au-dessus du sol au depart et on la lui garde a l'arrivee. Sans ca, un sol qui monte ou descend
	-- entre les deux le ferait s'enfoncer ou leviter.
	OLDMAN_WALK_GROUND_RAY = 30,

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
