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
	TRY_PUSH = 2.2,
	-- Aussi long que le geste de poignee. Un mouvement qui finit avant lui laisserait la camera immobile pendant
	-- la moitie de la scene, ce qui casse justement l'effet de resserrement continu.
	TRY_PUSH_TIME = 2.6,
	-- Puis elle RECULE d'un coup quand la porte s'ouvre, comme si elle avait eu peur. Le recul est plus GRAND que
	-- l'approche : sinon on revient au point de depart et le mouvement se lit comme une annulation, pas comme un
	-- sursaut.
	SCARE_BACK = 3.6,
	-- VIF. C'est un reflexe, pas un mouvement de camera : au-dela d'une demi-seconde il ne se lit plus comme une
	-- reaction mais comme un travelling arriere.
	SCARE_TIME = 0.32,
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

	-- ===== LE JOUEUR S'EFFACE PENDANT LA SCENE =====
	-- On regarde le grand-pere, pas son propre dos. A 0.7 le personnage reste LISIBLE -- on sait qu'on est la --
	-- sans manger le cadre.
	--
	-- Passe par CharacterFade, donc par LocalTransparencyModifier : ca ne se replique pas. En co-op, les autres
	-- continuent de voir un personnage normal.
	SCENE_PLAYER_FADE = 0.7,
	-- ET IL DISPARAIT COMPLETEMENT quand la porte s'ouvre. A 0.7 il reste une silhouette -- suffisant tant qu'on
	-- regarde une porte fermee, mais un GRAND avatar masque le grand-pere au moment precis ou l'on doit le voir.
	--
	-- Le personnage ne porte plus aucune information a cet instant : on sait ou l'on est, c'est lui qu'on
	-- regarde. Autant liberer le cadre.
	REVEAL_PLAYER_FADE = 1,
	-- Duree du fondu vers l'invisible. Passer de 0.7 a 1 d'un coup se voit -- une silhouette qui disparait d'un
	-- claquement attire justement l'oeil sur elle.
	REVEAL_FADE_TIME = 0.45,

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
	-- Secondes apres le lancement avant de verifier qu'une animation a REELLEMENT bouge quelque chose. Assez
	-- tard pour qu'elle ait eu le temps d'ecrire, assez tot pour que le message serve encore.
	ANIM_CHECK_DELAY = 0.4,

	-- ELLE MENE LA SCENE. C'est elle qui declenche la porte, et c'est SA FIN qui termine la scene.
	GRANDPA_ANIM = "Scene1_oldman_OpenDoor",
	-- Marqueur DANS l'animation du grand-pere : l'instant ou sa main pousse la porte.
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

	-- ELLE S'ENTREBAILLE D'UN COUP. Mouvement sec : c'est la surprise, la ralentir l'enleverait.
	DOOR_HALF_ANGLE = 30,
	DOOR_HALF_TIME = 0.35,
	-- Puis elle se FIGE, le temps que le grand-pere se montre.
	DOOR_PAUSE = 1.5,
	-- ET ELLE S'OUVRE EN GRAND, LENTEMENT. C'est le moment ou l'on decouvre le grand-pere : a vitesse pleine il
	-- etait fini avant qu'on ait le temps de regarder. Deux moments differents, deux allures -- et desormais deux
	-- reglages separes, au lieu d'un facteur de vitesse applique a un segment.
	DOOR_FULL_ANGLE = 100,
	DOOR_FULL_TIME = 2.2,
	-- La porte s'ouvre du mauvais cote ? Mettre true. Le sens depend de l'orientation du modele dans Studio : ca
	-- ne se DEDUIT pas, ca se voit a l'ecran.
	DOOR_OPEN_INVERT = false,

	-- ===== L'OBJECTIF =====
	-- EN ANGLAIS, comme tout texte vu par le joueur. Le traducteur de Roblox part de l'anglais : un texte ecrit en
	-- francais n'est traduit NULLE PART, et le jeu devient illisible pour la quasi-totalite de la plateforme.
	TASK_TITLE = "MOW THE LAWN",
	-- La recompense est ECRITE, pas calculee : rien ne la verse encore. Le jour ou elle le sera, elle viendra de
	-- la source qui paie -- une valeur affichee qui ne correspond pas a ce qu'on recoit est pire que pas de
	-- valeur du tout.
	TASK_REWARD = "+ 50 XP",

	-- ===== LE GRAND-PERE SORT DE CHEZ LUI =====
	-- La scene finie, il ne reste pas plante dans l'embrasure : il marche jusque devant sa porte.
	--
	-- L'ID vit ICI, en code, et pas dans une Instance Animation : Rojo synchronise le code dans TOUTES les places,
	-- les Instances non (`Animations` est en `$ignoreUnknownInstances`, il se recopie a la main place par place).
	OLDMAN_WALK_ANIM = "rbxassetid://109013940658757",
	-- AU-DESSUS de son idle, qui tourne en permanence (AmbientAnimService, priorite `Idle`). En dessous ou a
	-- EGALITE, Roblox melangerait les deux poses au lieu de choisir : on obtiendrait une marche "presque bonne".
	-- Et comme l'idle continue dessous, il suffit d'ARRETER la marche pour qu'il revienne s'y poser.
	OLDMAN_WALK_PRIORITY = Enum.AnimationPriority.Movement,
	-- OU IL VA : une part posee dans Studio. Pas un point calcule -- le pas exact ou s'arrete un personnage dans
	-- une scene se decide a l'oeil, pas par une formule, et le deplacer ne doit demander aucun code.
	OLDMAN_WALK_TARGET = "OldManWalkTo",
	-- Sa vitesse de marche, en studs/s.
	OLDMAN_WALK_SPEED = 6,
	-- Vitesse pour laquelle l'animation a ete faite. La piste est jouee au rapport des deux, donc changer la
	-- vitesse ci-dessus ne fait pas patiner ses pieds -- et il n'y a aucune seconde valeur a garder d'accord.
	OLDMAN_WALK_REFERENCE = 8,
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
