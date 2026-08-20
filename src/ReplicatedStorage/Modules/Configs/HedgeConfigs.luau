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
	-- Distance MAXIMALE, en studs, a laquelle le curseur peut nommer une haie comme haie de travail. Au-dela, on
	-- garde la haie courante : viser une haie lointaine ne doit pas la rendre soudain "de travail" et faire
	-- pivoter puis sortir le joueur. Un peu au-dela de HOLD_RANGE (la portee ou le serveur garde l'accroche) :
	-- ce qui est plus loin que ca n'est de toute facon jamais la haie qu'on travaille.
	CURSOR_HEDGE_RANGE = 9,
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
	--
	-- C'est aussi ce qui decide de COMBIEN on depasse le bout avant que la face tourne : le depassement vaut
	-- WORK_DISTANCE + cette marge. Les 2.5 studs de WORK_DISTANCE ne sont pas reglables ici, ils viennent de la
	-- distance a laquelle le joueur se tient : tant qu'il est plus "dehors" du cote avant que du cote bout,
	-- l'avant gagne, et c'est geometriquement juste.
	-- 0.4 et non 1.2 : mesure sur 400 frames de pietinement dans l'angle, avec bruit, 0 oscillation jusqu'a
	-- 0.4. A 0.2 il en reste 2, a 0 il y en a 201.
	FACE_SWITCH_MARGIN = 0.4,

	-- Deux allures au pied d'une haie, selon que la gachette est pressee. Passent par
	-- CharacterService.setSpeedOverride, jamais par WalkSpeed directement.
	--
	-- Lame a l'arret, le joueur se REPLACE : il longe la haie pour aller ou il veut travailler, et il n'a
	-- aucune raison de trainer. Plus rapide meme que la marche normale (10), parce qu'il glisse en pas chasses
	-- le long d'un rail, sans rien a eviter.
	WORK_SPEED = 13,
	-- Dans l'ARRONDI d'un angle, le joueur suit un arc plus long qu'une face plate : a WORK_SPEED constante, le
	-- contournement traine. On accelere donc dans le virage pour compenser. La vitesse interpole de WORK_SPEED
	-- (face plate) a cette valeur (coin le plus serre, a 45 degres). NE S'APPLIQUE QU'AU replacement, pas a la
	-- coupe : tailler reste un geste de precision. Le monter rend le contournement plus vif, le baisser vers
	-- WORK_SPEED le neutralise.
	WORK_SPEED_CORNER = 18,
	-- Gachette pressee, il TRAVAILLE : geste de precision, il faut ralentir.
	--
	-- C'est ce qui donne enfin un COUT a la gachette. Sans ecart, la presser en permanence n'avait aucun
	-- inconvenient, donc personne ne la relachait et elle ne voulait plus rien dire.
	-- L'ecart doit rester GRAND : c'est lui qu'on sent, pas la valeur absolue.
	--
	-- INCHANGE, ET C'EST VOLONTAIRE. La vitesse de coupe ne se regle PAS ici quand le pas chasse change : voir
	-- STEP_GLIDE_CUT. Tenter de compenser un plancher de glisse par un facteur sur cette valeur demande de
	-- connaitre la cadence reelle des pas (qui vit dans l'animation, pas dans la config) : ca se devine mal et ca
	-- tombe a cote. On garde les deux vitesses telles qu'elles sont ressenties, et on donne a chaque allure son
	-- propre plancher.
	CUT_SPEED = 5,

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
	-- ObjectValue pose sur le PERSONNAGE par le serveur : la haie de travail (l'instance). Un attribut ne peut
	-- pas porter une Instance, d'ou l'ObjectValue, qui lui SE REPLIQUE au client. Sert a ce que l'aimant et
	-- l'orientation s'accrochent des l'entree dans la zone, sans attendre que le curseur nomme la haie.
	WORK_HEDGE_VALUE = "LeafiaWorkHedge",
	-- Pose par le serveur quand le joueur taille DEPUIS L'ECHELLE (sommet). Le client s'en sert pour dessiner le
	-- guide de coupe (le cylindre) alors que l'accroche au sol, elle, est desengagee.
	LADDER_TRIM_ATTRIBUTE = "LeafiaLadderTrim",

	-- ===== RAIL DE TRAVAIL =====
	-- Pendant l'accroche, le joueur glisse le long de la haie a distance CONSTANTE.
	--
	-- Ce n'est pas du confort, c'est ce qui rend la taille apprenable. Si la distance derive, le cadrage change,
	-- et le meme geste de souris ne coupe plus au meme endroit : le joueur ne peut developper aucune precision
	-- parce que les regles bougent sous ses pieds.
	-- Cette distance doit couvrir l'outil dans sa position la PLUS AVANCEE. Une seule chose le fait encore
	-- avancer au pied d'une haie : la HAUTEUR VISEE, qui change la pose des bras.
	--
	-- Elle valait 2.5 quand l'inclinaison de couple (0.7 stud au bout de lame) et le tremblement s'y ajoutaient.
	-- Les deux sont desormais eteints au chantier (tiltWorkingScale = 0), donc cette reserve ne sert plus.
	--
	-- ELLE DECIDE AUSSI DU CONTOURNEMENT. Le joueur depasse le bout d'une haie de WORK_DISTANCE +
	-- FACE_SWITCH_MARGIN avant que la face tourne, et ce n'est pas un reglage : en longeant une face a W studs,
	-- il est "dehors" de W en permanence, donc le bout ne le rattrape qu'a W. Verifie : aucun coefficient de
	-- penalite ne change ce point, la geometrie est invariante.
	-- Baisser cette valeur rapproche le joueur ET raccourcit le contournement, d'un seul geste.
	--
	-- A REGLER A L'OEIL, en visant le BAS de la haie : c'est la que la marge de lame est la plus faible.
	-- Une lame qui EFFLEURE la haie est souhaitable ; une lame qui rentre dedans ne l'est pas.
	WORK_DISTANCE = 1.9,
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

	-- A partir de quel alignement une poussee vers l'arriere est lue comme "je quitte le chantier".
	-- 1 = pile en arriere, 0 = perpendiculaire. 0.5 vaut environ 60 degres de tolerance : assez large pour
	-- sortir en diagonale, assez strict pour qu'un pas de cote ne decroche pas par accident.
	EXIT_DOT = 0.5,
	-- Amplitude minimale pour qu'un deplacement compte comme une VOLONTE de sortir. Une correction d'aimant est
	-- faible (0.45 au maximum), une vraie poussee vaut ~1. Ce seuil les separe : les deux arrivent au serveur par le
	-- meme canal, seule leur ampleur les distingue. Baisse a 0.55 (au lieu de 0.7) : un JOYSTICK analogique tire en
	-- arriere n'atteignait pas 0.7 (contrairement a la touche S = 1.0 pile), donc on ne pouvait pas sortir sur MOBILE.
	-- On reste juste au-dessus du max de l'aimant (0.45) pour ne pas confondre une correction avec une sortie.
	EXIT_MIN_INPUT = 0.55,
	-- Temps mort apres une sortie VOLONTAIRE, avant de pouvoir se raccrocher.
	--
	-- Sans lui : le joueur appuie sur S, le serveur decroche, mais la frame suivante le volume touche encore la
	-- haie (elle est a deux pas) donc ca raccroche, la sortie est redetectee, ca redecroche... soixante
	-- bascules par seconde, et la camera fait l'aller-retour entre Scriptable et Custom a chaque fois.
	-- Assez long pour s'eloigner d'un pas, assez court pour pouvoir revenir tout de suite.
	EXIT_COOLDOWN = 0.5,
	-- Temps mort apres avoir QUITTE L'ECHELLE, avant que l'accroche au sol puisse se declencher. La base de l'echelle
	-- est souvent DANS la zone d'une haie : sans ce delai, descendre de l'echelle re-agriperait le joueur d'emblee
	-- (aimant + orientation forcee + camera iso), pile quand il veut s'en aller -> la camera "bloque" un instant.
	-- Assez long pour s'eloigner d'abord. A REGLER si la base des echelles est plus / moins pres des haies.
	LADDER_EXIT_GRACE = 0.9,

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
	--
	-- C'EST LUI QUI DECIDE DE LA VITESSE REELLE, pas WORK_SPEED. Le joueur passe le plus clair de son temps a ce
	-- plancher (la poussee ne dure que 0.19 s), donc sa vitesse moyenne vaut a peu pres WORK_SPEED * ce nombre,
	-- releve par la part de poussee. A 0.25 le replacement se trainait a environ 5 studs/s, soit moitie moins que
	-- la marche normale, alors que WORK_SPEED annonce 13. Le monter vers 1 rend le deplacement continu et efface
	-- le pas chasse ; le baisser rend les a-coups plus francs mais ralentit tout.
	-- NE VAUT QUE POUR LE REPLACEMENT, lame a l'arret. En taillant, c'est STEP_GLIDE_CUT qui s'applique.
	STEP_GLIDE = 0.5,
	-- Le meme plancher, mais GACHETTE PRESSEE. Reste a 0.25, la valeur historique : la coupe garde donc exactement
	-- la vitesse qu'elle avait avant qu'on accelere le replacement.
	--
	-- DEUX PLANCHERS ET NON UN SEUL parce que ce plancher multiplie la vitesse : un reglage unique fait bouger les
	-- deux allures ensemble, et on ne peut plus accelerer le replacement sans accelerer la coupe avec. Corriger ca
	-- en baissant CUT_SPEED demanderait de connaitre la cadence des pas (elle vit dans l'animation) : essaye, et
	-- tombe a cote. Ici chaque allure a son plancher, donc chacune se regle sans toucher a l'autre.
	-- A GARDER AU-DESSUS de CameraController.MOVING_EXIT (0.15), comme STEP_GLIDE : c'est le plus BAS des deux qui
	-- decide, sinon le champ de vision tremble au rythme des pas pendant la coupe.
	STEP_GLIDE_CUT = 0.25,
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
	-- Pose pour le DESSUS de la haie. Meme principe : figee, parcourue a la main. Premiere image = bord proche,
	-- derniere = bord oppose.
	--
	-- Une piste par ORIENTATION de surface, et non une seule qu'on tordrait : tailler un mur vertical et une
	-- table horizontale ne sont pas le meme geste, et le corps ne se place pas pareil.
	RIGHTLEFT_ANIMATION = { "Animations", "Player", "Tools", "HedgeTrimmer", "RightLeftAnimation" },
	-- Inclinaison minimale de la surface visee pour basculer sur la pose du DESSUS. 1 = pile a l'horizontale.
	--
	-- 0.6 vaut environ 53 degres : bien au-dessus de ce qu'une face verticale peut donner, meme sur une haie
	-- posee de travers. On ne bascule donc jamais par erreur en travaillant un cote.
	TOP_AIM_DOT = 0.6,
	-- Action2 : au-dessus de la pose de maintien (Action), qui cle les MEMES bras. A egalite les deux se
	-- melangeraient et la hauteur visee ne serait jamais atteinte.
	UPDOWN_PRIORITY = Enum.AnimationPriority.Action2,
	UPDOWN_FADE = 0.2,
	-- Hauteur de haie pour laquelle la pose a ete ANIMEE, en studs.
	--
	-- La visee est normalisee de 0 a 1 sur la haie : sur une haie de trois studs, viser le sommet donnait donc
	-- la pose la plus HAUTE de l'animation, bras tendus au-dessus de la tete pour une haie qui arrive a la
	-- taille. On divise la course de la piste par le rapport des hauteurs.
	-- A caler sur la haie qui a servi de modele en animant.
	UPDOWN_REFERENCE_HEIGHT = 8,
	-- Course minimale conservee, quelle que soit la petitesse de la haie. Sans ce plancher, une haie tres basse
	-- figerait la pose sur une seule image et le geste disparaitrait.
	UPDOWN_MIN_SPAN = 0.25,

	-- Portee laterale de la pose du DESSUS, en studs de part et d'autre du joueur.
	--
	-- Sur le dessus, ce qui varie n'est pas une hauteur mais un COTE : le curseur a gauche fait balayer a
	-- gauche, a droite a droite. La piste couvre donc cet ecart-la, et non la profondeur de la haie.
	TOP_REACH = 3,
	-- Raideur du RESSORT qui amene les bras a la hauteur visee, en oscillations par seconde environ.
	--
	-- Un ressort et non un simple lissage : un lissage demarre INSTANTANEMENT puis ralentit, donc le baisser
	-- rend le geste mou sans jamais le rendre en retard. Un ressort doit d'abord prendre son elan : les bras
	-- partent apres la souris, la rattrapent, et s'arretent sans depasser. C'est ca, du poids.
	--
	-- Amorti au CRITIQUE (voir HedgeController) : il ne depasse jamais la cible. Un depassement ferait
	-- osciller la hauteur de coupe autour du point vise, et la taille deviendrait imprecise.
	-- Plus haut = plus reactif. Plus bas = l'outil parait lourd.
	--
	-- Mesure du temps pour parcourir toute la hauteur d'une haie : 12 -> 0.33 s, 9 -> 0.45 s, 6.5 -> 0.62 s,
	-- 5 -> 0.78 s, 4 -> 0.98 s.
	-- En dessous de 4 l'outil ne suit plus la souris, il la subit : viser devient un combat.
	--
	-- CETTE VALEUR DEPEND DE LA CAMERA. Elle etait montee a 10 pour la vue 1re personne, ou l'oeil est a la tete :
	-- le curseur tombe presque a la verticale sur la haie, la hauteur visee est donc stable et le ressort peut
	-- etre sec. En vue iso le rayon arrive DE BIAIS, le meme pixel de souris couvre bien plus de hauteur de haie
	-- et le signal est plus nerveux -- un ressort raide amplifie ce bruit au lieu de l'absorber, et la visee parait
	-- sauter toute seule. Elle etait redescendue a 6.5, la valeur d'avant la 1re personne.
	-- Remontee a 12 a la demande : le retard se sentait comme une visee qui ne repond pas. Si la visee se met a
	-- sauter d'elle-meme, c'est ce bruit-la qui ressort -- redescendre plutot que chercher ailleurs.
	-- NB : le taille-haie a sa PROPRE valeur (ToolConfigs.HedgeTrimmer.poseFollowSpeed), qui prime sur celle-ci.
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

	-- ===== PERSONNAGE EN FANTOME =====
	-- Au pied d'une haie, le corps du joueur s'efface pour laisser voir ce qu'il taille.
	--
	-- TOUT S'EFFACE SAUF CE QUI TIENT L'OUTIL. Les mains restent nettes parce qu'elles sont le point de
	-- contact entre le joueur et son taille-haie : sans elles, l'outil flotterait tout seul et la scene ne se
	-- lirait plus. Les avant-bras, eux, n'apportent rien que le corps n'apporte deja.
	-- Ce qu'on veut n'est pas "cacher le corps", c'est "voir a travers" : il reste une silhouette.
	--
	-- Le prix a garder en tete : sur Roblox, l'avatar est ce que le joueur a choisi et parfois paye. L'effacer
	-- completement pendant l'activite principale, c'est le lui reprendre au moment ou il regarde l'ecran.
	-- D'ou des valeurs qui laissent une silhouette, et pas un chantier vide.
	WORK_FADE = true,
	-- Tronc, tete, JAMBES ET BRAS, accessoires.
	-- Pas 1 : il doit rester une silhouette. A transparence pleine le joueur ne sait plus ou est son personnage
	-- ni ou il regarde, et le pas chasse le long de la haie devient illisible.
	WORK_FADE_BODY = 0.85,
	-- Les mains seules. Elles tiennent l'outil, elles restent nettes.
	WORK_FADE_HANDS = 0.2,
	-- Vitesse du fondu. Il ne se declenche PAS sur la gachette mais sur l'accroche a la haie : lie a la
	-- gachette, il clignoterait a chaque pression et donnerait mal au crane.
	WORK_FADE_SPEED = 5,

	-- ===== CONTOURNEMENT DES ANGLES =====
	-- Plafond de rotation de la normale de travail, en degres par seconde.
	--
	-- La normale n'est plus celle que le serveur a choisie : le client la recalcule depuis le point de la haie
	-- le plus proche du joueur. La surface a distance constante d'une boite n'est pas quatre plans, c'est un
	-- rectangle a coins ARRONDIS de rayon egal a cette distance. L'arrondi vient donc de la geometrie, il n'y a
	-- aucune interpolation a inventer, et il ne peut pas y avoir de bascule d'un quart de tour.
	--
	-- Reste que sa VITESSE de rotation, elle, saute : elle passe de zero a vitesse/rayon en entrant dans
	-- l'angle. A 13 studs/s sur un rayon de 1.9, ca fait 390 degres par seconde, le quart de tour expedie en un
	-- quart de seconde. C'est exactement la sensation seche a supprimer.
	--
	-- Ce plafond ELARGIT l'arc au lieu de le ralentir : la normale prend du retard, le rail tourne donc moins
	-- vite que le joueur et l'aimant le laisse s'ecarter. Rayon obtenu = vitesse / plafond. A 200 deg/s :
	--   replacement (13 studs/s) -> arc de 3.7 studs, quart de tour en 0.45 s
	--   en taillant (5 studs/s)  -> le plafond ne mord pas, arc naturel de 1.9 stud
	-- Autrement dit : vite = large et coulant, lentement = serre et precis. Le joueur decide en accelerant.
	CORNER_TURN_SPEED = 200,

	-- ===== CAMERA DE TRAVAIL =====
	-- Placee du COTE du joueur (dans le prolongement de la normale de la face), donc elle regarde la haie
	-- par-dessus son epaule.
	CAMERA_DISTANCE = 13, -- recul, le long de la normale
	CAMERA_HEIGHT = 9.5, -- hauteur au-dessus du joueur
	-- Decalage lateral : c'est lui qui donne l'angle 3/4 isometrique. Le SIGNE choisit le cote, negatif pour la
	-- droite du joueur, positif pour sa gauche. Zero pour une vue bien en face.
	CAMERA_SIDE = -10,
	-- MOBILE : depart plus DE FACE (moins de decalage lateral). Sur petit ecran, l'angle 3/4 se lit moins bien et
	-- la visee au doigt est plus naturelle bien en face. Le joueur peut ensuite tourner librement (orbite tactile).
	CAMERA_SIDE_TOUCH = -5,
	CAMERA_LOOK_HEIGHT = 2, -- point vise, au-dessus des pieds du joueur
	-- Recul quand le joueur ACCELERE : la camera se rapproche, l'attention se resserre sur le geste. La transition
	-- est lissee EN PARAMETRE (CAMERA_DISTANCE_LERP), pas via la position de la camera (placee direct, cf orbite).
	CAMERA_DISTANCE_THROTTLE = 9.5,
	-- Vitesse de lissage du recul (rapproche / ressort a l'acceleration). En parametre : ne deforme pas l'orbite.
	CAMERA_DISTANCE_LERP = 8,

	-- PREMIERE PERSONNE (experimental). Vrai -> la camera de travail passe A LA TETE du joueur, regard vers la haie, au
	-- lieu de la vue iso 3/4. La visee (souris / doigt) suit toute seule (le rayon part de cette camera). On peut voir
	-- ses bras / son corps (une cam scriptee ne cache pas le perso comme la 1re personne native de Roblox), d'ou le
	-- masquage local a l'engage.
	--
	-- REPASSE A FALSE : dans ce mode la vue est FIGEE. La branche 1re personne de HedgeController ne lit ni le pivot
	-- (yaw) ni le zoom, donc le clic droit, le glissement du doigt et la molette ne font RIEN a l'ecran, alors que le
	-- code d'orbite tourne quand meme. On taille sous un angle impose, et on ne peut pas aller voir ce qu'on coupe.
	-- La vue iso, elle, a deja l'orbite, le zoom, le rubber-band de butee et le rapproche a l'acceleration.
	-- Le remettre a true demande d'abord de brancher yaw et cameraZoom sur le placement de l'oeil.
	CAMERA_FIRST_PERSON = false,
	-- Vue RAPPROCHEE DE COTE (near-first-person). Droit dans la haie = plat et illisible ; on DECALE l'oeil sur le cote
	-- pour voir la surface taillee DE BIAIS. FP_SIDE est le knob principal (l'angle "de cote").
	FP_SIDE = -4, -- decalage lateral de l'oeil (studs). Signe = cote (negatif = droite du joueur). PLUS GRAND = plus de biais
	FP_BACK = 2.5, -- recul de l'oeil DERRIERE la tete (loin de la haie), pour englober le geste
	FP_HEIGHT = 2, -- hauteur de l'oeil au-dessus de la tete
	FP_LOOK_FORWARD = 1, -- le point VISE est ce nombre de studs DEVANT le joueur (dans la haie)
	FP_LOOK_HEIGHT = 0, -- ajustement vertical du point vise (studs)
	-- Attribut pose par ToolStartService sur le personnage.
	THROTTLE_ATTRIBUTE = "LeafiaThrottle",
	-- Vitesse du GLISSE d'arrivee a l'engage (depuis la cam de jeu jusqu'a la vue de travail). Volontairement lente :
	-- une camera qui claque en place donne la nausee. Une fois arrivee, la camera n'est PLUS lissee : elle se place
	-- direct sur son cercle (orbite 1:1) car lisser la position deformait l'orbite (cf HedgeController).
	CAMERA_LERP_SPEED = 5,
	-- Distance a la cible (studs) sous laquelle l'arrivee est TERMINEE : en dessous, la camera passe en placement
	-- direct (fin du glisse d'engage).
	CAMERA_SETTLE_DIST = 4,

	-- ZOOM A LA MOLETTE, pendant le travail seulement.
	--
	-- FACTEUR sur tout le placement (recul, hauteur, decalage lateral) et non sur le seul recul : c'est ce qui
	-- garde l'angle 3/4. En ne touchant qu'au recul, la vue s'aplatit en s'eloignant et plonge en se
	-- rapprochant, donc le cadrage regle plus haut ne tient qu'a une seule valeur de zoom.
	-- Le point VISE, lui, ne bouge pas : le joueur reste au meme endroit de l'ecran.
	CAMERA_ZOOM_STEP = 0.1, -- fraction par cran de molette, appliquee en proportion
	CAMERA_ZOOM_MIN = 0.55, -- au plus pres
	CAMERA_ZOOM_MAX = 1.7, -- au plus loin
	-- Le zoom SURVIT au chantier, contrairement au pivot : c'est une preference de confort, pas un coup d'oeil.
	-- Le remettre a 1 en quittant chaque haie obligerait a le regler a chaque fois.

	-- Pivot horizontal libre, au clic DROIT maintenu. Le clic gauche reste pour l'outil, et le curseur reste
	-- libre pour viser la haie : le bouton droit ne sert a rien d'autre, c'est le seul de disponible.
	-- Le personnage, lui, ne tourne pas : seule la camera pivote autour de lui.
	CAMERA_YAW_SENSITIVITY = 0.35, -- degres par pixel de souris
	-- TACTILE : degres par pixel de GLISSEMENT du doigt (hors de la haie = orbite). Un doigt parcourt plus de
	-- pixels qu'une souris, donc plus BAS pour ne pas tourner trop vite. A REGLER a l'oeil.
	CAMERA_YAW_TOUCH_SENSITIVITY = 0.22,
	-- Butee de chaque cote. Sans elle le joueur passerait derriere la haie et travaillerait a l'aveugle.
	CAMERA_YAW_LIMIT = 70,
	-- RUBBER-BAND de la butee : au lieu d'un mur sec, on peut ETIRER l'orbite de tant de degres au-dela de la
	-- limite, avec une resistance croissante (marge elastique). Au relachement, retour a la limite par ressort.
	CAMERA_YAW_MARGIN = 12,
	-- Ressort de retour a la limite quand on relache au-dela. Raideur haute = revient vite. L'amortissement SOUS
	-- 2*sqrt(raideur) (ici 2*sqrt(220) ~ 29.7) laisse un REBOND : c'est ce rebond qui donne le "slime". A REGLER a l'oeil.
	CAMERA_YAW_SNAP_STIFFNESS = 220,
	CAMERA_YAW_SNAP_DAMPING = 16,

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

	-- ===== CELLULES DE POUSSE =====
	-- La surface taillable d'une haie, decoupee en carreaux. Chacun retiendra plus tard son epaisseur, et
	-- tailler la fera descendre : c'est ce qui donnera l'avant / apres.
	-- Pour l'instant ils ne font que se poser. On veut d'abord savoir ce que ca COUTE.

	-- Cote vise d'un carreau, en studs. La grille s'ajuste ensuite pour tomber juste sur la face : les carreaux
	-- font donc rarement exactement cette taille, mais ils PAVENT la surface sans trou ni depassement.
	--
	-- Commencer GRAND. On peut toujours affiner apres avoir mesure ; partir fin et decouvrir que ca ne tient
	-- pas oblige a tout refaire, art compris.
	-- MEME taille pour toutes les haies, grandes comme petites. Une grande haie a donc plus de carreaux, mais
	-- un client reel n'en a jamais des dizaines : le compte total reste raisonnable, et le grain fin est le meme
	-- partout. Le grossissement adaptatif essaye ici deformait le rendu des grandes haies custom pour un gain
	-- de perf dont on n'a pas besoin.
	CELL_SIZE = 0.7,
	-- Epaisseur, vers l'exterieur de la haie. C'est elle qui descendra a la taille.
	CELL_THICKNESS = 0.2,
	-- INVISIBLE. Le carreau n'est qu'un REPERE : il tient une case de la grille, il ne se voit pas. Ce qu'on
	-- voit, c'est la feuille posee dessus.
	--
	-- Une part invisible n'est pas rendue du tout : ni surface a dessiner, ni texture, ni transparence a trier.
	-- Autant de gagne sur le poste le plus cher de cette feature.
	-- A passer a 0.7 pour VOIR la grille pendant un reglage, et remettre a 1 apres.
	CELL_TRANSPARENCY = 1,
	-- Ne servent que si CELL_TRANSPARENCY est baisse pour un reglage.
	CELL_COLOR = Color3.fromRGB(62, 152, 24),
	CELL_MATERIAL = Enum.Material.SmoothPlastic,

	-- Faces a couvrir, en axes LOCAUX de la haie. "Y+" est le dessus.
	--
	-- Une seule face au depart, VOLONTAIREMENT : c'est la mesure qui dira si on peut en ajouter. Ajouter les
	-- autres ensuite est une ligne ; decouvrir apres coup que cinq faces ne tiennent pas coute une semaine
	-- d'art.
	CELL_FACES = { "Z+", "Z-", "X+", "X-", "Y+" },
	-- Dossier qui rassemble les cellules, dans Workspace.
	--
	-- MEME RAISON QUE HedgeBuffers : elles se posent DEVANT la haie, donc tous les lancers les toucheraient
	-- avant elle et plus rien ne serait detecte. Un dossier a part permet de les exclure d'un coup. Rangees
	-- dans la haie, les exclure exclurait la haie elle-meme.
	CELL_FOLDER = "HedgeCells",
	-- De combien les carreaux du DESSUS descendent sous le plan du haut de la haie, en studs. 0 = a fleur.
	--
	-- Ne concerne que la face du dessus. Une feuille couchee a plat se voit sur toute sa largeur, une feuille
	-- verticale se voit par la tranche : a hauteur egale le dessus parait donc bien plus epais que les cotes, et
	-- la haie porte un chapeau. Ce reglage le remet a niveau.
	--
	-- ATTENTION A LA COUCHE DE BRANCHES. Le dessus taille finit a CELL_TOP_DROP + CUT_DEPTH sous le haut de la
	-- haie ; le sommet du bois, lui, s'arrete a BRANCH_TOP_CLEARANCE sous ce meme haut. Garder
	-- BRANCH_TOP_CLEARANCE >= CELL_TOP_DROP + CUT_DEPTH, sinon le bois ressort par le dessus des feuilles rasees.
	CELL_TOP_DROP = 0.01,
	-- Bascule vers l'exterieur des carreaux du BORD du dessus, en degres. 0 = arete vive.
	--
	-- C'est ce qui casse l'angle du haut. Deux surfaces perpendiculaires s'ecartent forcement en etant
	-- taillees, chacune s'enfoncant dans SA direction : le dessus descend, le cote rentre. Aucun reglage ne
	-- fera se toucher deux plans qui reculent l'un par rapport a l'autre.
	-- Un carreau couche entre les deux, lui, comble le vide avec sa propre feuille. Et il reste taillable :
	-- sa normale regarde a mi-chemin, la lame l'atteint par le dessus comme par le cote.
	--
	-- 45 = biseau franc a mi-chemin. Plus bas, la haie garde un angle plus carre.
	CELL_BEVEL_ANGLE = 45,
	-- Hauteur de haie, en studs, AU-DELA DE LAQUELLE le dessus n'est plus atteignable depuis le sol.
	--
	-- On ne passe le taille-haie par-dessus une haie que si elle nous arrive a peu pres a hauteur des bras : au
	-- dela, le dessus reste touffu tant que le joueur n'aura pas d'escabeau pour se hisser.
	-- CE SEUIL GOUVERNE DEUX CHOSES, et c'est volontaire (ce qu'on n'atteint pas, on ne peut ni le tailler ni
	-- prendre la pose pour) :
	--   - la COUPE du dessus, cote serveur : au-dela, les carreaux du dessus sont poses et rendus (feuilles
	--     pleines, un haut pas encore taille) mais absents de la grille, donc increvables, et hors du
	--     pourcentage sinon la haie ne finirait jamais a 100.
	--   - la POSE gauche-droite du dessus, cote client : au-dela, elle ne se joue pas, on reste sur la pose
	--     verticale au maximum.
	TOP_CUT_MAX_HEIGHT = 3.5,
	-- Cote d'une CASE de rangement, en studs. Les carreaux y sont ranges a la construction pour que la coupe
	-- n'ait plus a tous les parcourir : elle ne regarde que les cases autour de la lame.
	--
	-- A REGLER PRES DE LA PORTEE DE LA LAME (environ 2.5). Trop petit, on interroge beaucoup de cases pour rien ;
	-- trop grand, chaque case contient trop de carreaux et le tri ne sert plus. Le nombre de cases interrogees
	-- vaut (2 * ceil(portee / ce cote) + 1) au cube : a 3 pour une portee de 2.5, ca fait 27.
	CELL_BUCKET_SIZE = 3,

	-- ===== TERRE AU SOL =====
	-- Un tas de terre a la base de la haie : elle a l'air d'en sortir, au lieu d'etre posee sur l'herbe comme
	-- une boite. Purement decoratif, une part par haie.
	DIRT_ASSET = { "Assets", "Contents", "dirt_mesh_ground" },
	DIRT_FOLDER = "HedgeGrounds",
	DIRT_NAME = "HedgeGround",
	-- Debord de la terre autour du pied, en STUDS, sur chaque cote. C'est ce debord qui fait le tas.
	--
	-- EN STUDS ET NON EN POURCENTAGE : une marge fixe donne le meme debord partout, alors qu'un pourcentage le
	-- fait grandir avec la dimension. Sur une haie de 30 de long, un pourcentage debordait de plusieurs studs au
	-- bout mais a peine sur les cotes : le tas partait en pointe. Une marge fixe encadre la haie proprement,
	-- quelle que soit sa longueur.
	DIRT_MARGIN = 0.8,
	-- Epaisseur du tas, en studs. C'est la taille du mesh sur la verticale : la baisser l'APLATIT. Son sommet ne
	-- bouge pas (fixe par DIRT_HEIGHT), c'est le dessous qui remonte, donc le tas devient plus plat sans se
	-- deplacer.
	DIRT_THICKNESS = 0.5,
	-- HAUTEUR du tas, en studs : de combien son sommet depasse le pied de la haie. C'est LE reglage a monter ou
	-- descendre pour placer la terre. Positif = le tas remonte, le pied de la haie s'y enfonce et la jointure
	-- nette avec le sol disparait. Negatif = le tas s'enfonce sous le sol.
	DIRT_HEIGHT = 0.7,

	-- ===== COUCHE DE BRANCHES =====
	-- Ce qu'on voit A TRAVERS la haie quand une feuille est partie : coupee sur une arete, ou detruite a force
	-- d'etre abimee. Sans elle, un trou ouvre sur du vide et la haie se revele creuse.
	--
	-- Les modeles disponibles, DANS L'ORDRE OU ON VEUT LES PROPOSER. Aucune taille de reference n'est ecrite
	-- ici : le service lit celle de chaque modele directement sur le mesh, et choisit celui qui se deformera le
	-- moins sur la haie a habiller. Recopier les dimensions ici creerait une deuxieme verite qui finit par
	-- mentir des qu'un modele est retouche dans Studio.
	-- Ajouter un troisieme type de haie ne demande donc qu'une ligne de plus.
	BRANCH_ASSETS = {
		{ "Assets", "Contents", "Foliages", "Haie", "couche_largehaie_branche_type_1" },
		{ "Assets", "Contents", "Foliages", "Haie", "couche_smallhaie_branche_type_1" },
	},
	BRANCH_FOLDER = "HedgeBranches",
	BRANCH_NAME = "HedgeBranch",
	-- Le volume du bois est defini par des MARGES EN STUDS, pas par un pourcentage de la haie. Une marge sur les
	-- cotes, une sur le haut ; le bas reste toujours a fleur du sol (voir HedgeBranchService).
	--
	-- POURQUOI EN STUDS. Un pourcentage recule les faces d'autant plus que la haie est grande : a 0.88, une haie
	-- de 15 de long voit ses extremites reculer de 0.9 stud pendant qu'une de 6 ne recule que de 0.36. Resultat,
	-- les bouts des longues haies baillent et le dessus des petites ressort au travers des feuilles rasees. Une
	-- marge en studs donne le meme recul partout, quelle que soit la taille.
	--
	-- Recul LATERAL, en studs : de combien le bois rentre sous chaque face verticale (longueur ET largeur).
	-- SEUIL : une feuille taillee a fond rentre de CUT_DEPTH (0.7). En dessous de ~0.5, le bois commence a
	-- ressortir au travers d'une face fraichement rasee ; bien au-dessus, un grand trou laisse voir PAST le bois
	-- jusqu'a l'autre cote. Le baisser POUSSE le bois vers les extremites, le monter le rentre.
	BRANCH_SIDE_CLEARANCE = 0.3,
	-- Recul du HAUT, en studs : de combien le sommet du bois reste sous le haut de la haie.
	--
	-- Le dessus taille finit a CELL_TOP_DROP + CUT_DEPTH sous le haut. A garder >= cette somme (soit 1.0) pour
	-- que le bois finisse toujours SOUS la surface taillee, petite haie comme grande, sinon il ressort par le
	-- dessus. Le baisser fait remonter le bois, le monter l'enfonce.
	BRANCH_TOP_CLEARANCE = 0.65,
	-- Garde-fou. Au-dela, on refuse de generer et on le dit : mieux vaut une haie nue qu'un jeu a 15 images
	-- par seconde qu'on met une heure a diagnostiquer.
	CELL_BUDGET = 4000,

	-- ===== FEUILLES =====
	-- MeshPart clone au centre de chaque carreau, dans ReplicatedStorage.
	LEAF_ASSET = { "Assets", "Contents", "AssetLeafsType1" },
	-- Taille par rapport au carreau. Au-dessus de 1 les feuilles se CHEVAUCHENT, ce qui cache la grille mais
	-- multiplie la surface transparente a dessiner. C'est le reglage a surveiller en premier si ca rame.
	LEAF_SCALE = 1.3,

	-- DESORDRE. Sans lui, toutes les feuilles sont identiques et alignees : l'oeil voit la grille avant de voir
	-- la haie, et aucun detail de texture ne rattrape ca.
	--
	-- Le tirage est SEME sur la position de la haie : le meme jardin se regenere donc a l'identique d'une
	-- session a l'autre. Un decor qui change de tete a chaque relance empeche de juger un reglage.
	-- Taille, en part de LEAF_SCALE.
	LEAF_SCALE_MIN = 1.9,
	LEAF_SCALE_MAX = 2.3,
	-- Rotation dans le PLAN de la face, en degres. C'est celle qui coute le moins et se voit le plus : une
	-- feuille tournee ne ressemble plus a sa voisine.
	LEAF_SPIN = 50,
	-- Peignage a la taille, en degres, dans le PLAN de la face. En plus de son orientation de naissance, chaque
	-- feuille pivote progressivement d'autant de degres a mesure qu'elle est taillee : 0 a pousse pleine, tout ce
	-- reglage a ras. Les feuilles poussues partent dans tous les sens, les taillees s'alignent dans une meme
	-- direction. C'est un signal gratuit et fort : le desordre pousse, le propre est peigne.
	-- Calcule CHEZ CHAQUE CLIENT (voir HedgeLeafController), comme le reste du rendu des feuilles.
	LEAF_TRIM_SPIN = 0.2,
	-- Basculement HORS du plan, en degres. A garder petit : trop, et les feuilles decollent de la surface,
	-- laissant voir les carreaux entre elles.
	LEAF_TILT = 0.1,
	-- Meme chose, mais RESERVE a la face du dessus. Une feuille couchee a plat sur le dessus se lit comme un
	-- tapis : vue de biais, on ne voit que des plans horizontaux alignes. La redresser lui rend du volume et
	-- casse la surface plate. Distinct de LEAF_TILT parce que les cotes, eux, doivent RESTER plaques : une
	-- feuille verticale qui decolle laisse voir l'interieur entre les carreaux, alors qu'une feuille du dessus
	-- qui se redresse retombe sur ses voisines. On peut donc pousser le dessus sans abimer les cotes.
	LEAF_TILT_TOP = 18,
	-- Decalage dans le plan, en part du carreau. C'est CE reglage qui casse vraiment la grille : deux feuilles
	-- peuvent etre tournees differemment et rester alignees comme du carrelage.
	-- Au-dela de 0.5 elles sortent de leur carreau et des trous apparaissent.
	LEAF_JITTER = 0.2,

	-- Balancement, calcule CHEZ CHAQUE CLIENT.
	--
	-- Jamais cote serveur : une part que le serveur bouge replique sa CFrame a tous les joueurs. Mille feuilles
	-- animees, c'est la bande passante entiere pour du decor.
	LEAF_SWAY_ANGLE = 7, -- degres
	LEAF_SWAY_SPEED = 1, -- oscillations par seconde
	-- Au-dela de cette distance de la camera, une feuille ne bouge plus. Personne ne voit un balancement de
	-- sept degres a soixante-dix studs, autant ne pas le payer.
	-- Distance a la HAIE, pas a la feuille : la portee de sa sphere englobante s'y ajoute. Au-dela, la haie
	-- entiere est endormie et ses feuilles ne sont meme plus parcourues.
	--
	-- ATTENTION : la distance part de la CAMERA, pas du joueur. En vue de travail elle est a une vingtaine de
	-- studs derriere lui, donc une portee reglee sur ce qui parait proche a l'oeil endort la haie qu'on taille.
	LEAF_RANGE = 15,
	-- Nombre de frames sur lesquelles on etale la mise a jour. 4 = un quart des feuilles par frame, donc chacune
	-- bouge a 15 images par seconde au lieu de 60.
	--
	-- Un balancement lent n'a pas besoin de 60 : l'oeil ne fait pas la difference, et ca divise le cout par
	-- quatre. Monter cette valeur si ca rame, jusqu'a ce que le mouvement devienne saccade.
	LEAF_BATCH = 4,

	-- ===== COUPE =====
	-- Marge ajoutee autour de la boite de lame, en studs. Un carreau est coupe quand son CENTRE entre dedans.
	--
	-- Tester le centre et non le volume entier donne une regle simple que le joueur apprend sans qu'on la lui
	-- explique : ce qui est sous la lame tombe. Tester un chevauchement partiel couperait des carreaux qu'on
	-- ne croit pas toucher, et ce genre de faute se ressent tout de suite sans savoir la nommer.
	-- ===== EMPRISE DE LA LAME =====
	-- La coupe est calculee GEOMETRIQUEMENT, a partir de la hauteur visee et de la position du joueur. Elle ne
	-- lit PAS la position reelle de l'outil.
	--
	-- Pourquoi : la pose des bras est jouee chez le client et pilotee image par image. Roblox replique le
	-- demarrage d'une animation, pas son defilement. Le serveur voyait donc la lame figee a une hauteur pendant
	-- que le joueur la voyait suivre sa souris, et la coupe ne tombait juste que par hasard.
	--
	-- Le VISUEL reste l'animation, la REGLE est ce rectangle. Separer les deux rend aussi la coupe
	-- previsible : elle tombe exactement ou vise le curseur, quelle que soit la pose des bras.
	--
	-- RAYON PERPENDICULAIRE de la coupe, en studs : jusqu'ou la lame taille DE PART ET D'AUTRE de sa ligne.
	--
	-- La coupe est une CAPSULE : le carreau tombe si son centre est a moins de ce rayon de la LIGNE de la lame
	-- (base a pointe), pas d'un seul point. C'est ce qui fait couper TOUTE la lame, le bout compris. La longueur
	-- vient du segment que le client envoie (la boite de l'outil) ; ce rayon, lui, est la LARGEUR du coup.
	-- Le baisser resserre le coup autour de la lame, le monter l'elargit.
	-- KNOB UNIQUE : le cylindre d'aide lit CETTE valeur (diametre = (CUT_RADIUS + CUT_MARGIN) * 2), donc le
	-- visuel et la vraie coupe retrecissent ENSEMBLE. Le guide ne ment jamais.
	CUT_RADIUS = 0.8,
	-- Plus utilise : la largeur du coup est CUT_RADIUS, la longueur vient du segment. Garde a 1 par securite si
	-- un ancien reglage y fait encore reference.
	CUT_RADIUS_SCALE = 0.8,
	-- Marge ajoutee aux deux, en studs.
	CUT_MARGIN = 0.6,
	-- COINS / ARETES plus faciles a finir. Les cellules de BORDURE (marquees EDGE_ATTRIBUTE a la construction)
	-- recoivent DEUX bonus : un peu plus de PORTEE, et une TOLERANCE de surface plus large (lame plus rasante
	-- acceptee). C'est aux coutures entre deux faces que la lame, calee sur une face, arrive DE BIAIS sur les
	-- cellules de la face d'a cote : sans ces bonus, des feuillus de coin restent hors d'atteinte et finir une haie
	-- devient un combat (cf regle d'or : tailler doit rester jouissif). N'affecte QUE les bordures : la coupe en
	-- pleine face ne bouge pas d'un poil. A REGLER a l'oeil (monter si des coins resistent encore).
	CUT_EDGE_REACH_BONUS = 0.6,
	CUT_EDGE_SURFACE_BONUS = 0.5,
	-- BAS des cotes (rangee du sol). Dur a atteindre : la pose la plus BASSE des bras (frame 0 de l'anim) arrive
	-- AU-DESSUS de cette rangee, donc sans aide une frange de feuillus reste au ras du sol. Marquee BASE_ATTRIBUTE
	-- et PAS Edge (on ne DETRUIT pas ces feuilles : ca ouvrirait la haie par en dessous). Bonus de portee plus
	-- GENEREUX que les aretes, pour que le geste bas attrape enfin la frange. A REGLER a l'oeil.
	CUT_BASE_REACH_BONUS = 1.2,
	CUT_BASE_SURFACE_BONUS = 0.5,
	-- De combien la lame peut etre EN DECA de la surface d'un carreau et le couper quand meme, en studs.
	--
	-- Sans cette marge, il fallait etre strictement du cote exterieur. Sur le DESSUS d'une haie basse, la lame
	-- arrive PILE au niveau de la surface : le produit scalaire valait presque zero et rien ne passait. Le
	-- joueur balayait le dessus sans effet, ce qui ressemble a une detection cassee.
	--
	-- Ne compromet PAS la protection de la face arriere : sur une haie de deux studs, ses carreaux sont a 2.6
	-- studs derriere la lame, donc tres loin de cette marge.
	CUT_SURFACE_TOLERANCE = 0.8,
	-- Envoi de la position de lame au serveur : deplacement minimal (en studs) et temps minimal entre deux
	-- paquets.
	--
	-- Sans ces deux garde-fous, ce serait soixante paquets par seconde et par joueur pour une position qui
	-- bouge a peine. 0.15 stud est bien en dessous de la taille d'un carreau : on ne perd aucune precision
	-- utile.
	AIM_SEND_STEP = 0.15,
	AIM_SEND_INTERVAL = 0.05,
	-- Distance maximale acceptee entre le joueur et la lame qu'il declare, en studs.
	--
	-- Le client dit ou est sa lame ; sans cette borne il pourrait la declarer a l'autre bout de la haie et
	-- tailler sans se deplacer. A caler au-dessus de la portee reelle bras + outil, sinon on refuserait des
	-- coupes legitimes.
	CUT_REACH_MAX = 8,
	-- Longueur MAXIMALE du segment de lame acceptee du client, en studs. Le client envoie les deux bouts de sa
	-- lame ; sans ce garde il enverrait un segment geant pour tailler toute la haie d'un coup. A caler un peu
	-- au-dessus de la vraie longueur de lame, pas plus.
	CUT_BLADE_MAX_LENGTH = 12,

	-- ===== POUSSE D'UN CARREAU =====
	-- Chaque carreau retient sa POUSSE, de 1 (pas taille) a 0 (au ras). Tailler la fait descendre ; la feuille
	-- rentre d'autant dans la haie.
	--
	-- C'EST LE COEUR DE LA SATISFACTION. Une feuille qui disparait laisse un trou : le desordre change de
	-- forme, il ne diminue pas. Une feuille qui RENTRE jusqu'a un plan commun cree une surface plate, et c'est
	-- ca, voir le desordre devenir propre.
	GROWTH_ATTRIBUTE = "Growth",
	-- De combien la feuille rentre entre pousse pleine et ras, en studs. C'est l'amplitude de l'avant/apres :
	-- trop peu et on ne voit rien, trop et la haie se creuse.
	CUT_DEPTH = 0.7,
	-- Taille de la feuille AU RAS, en part de sa taille de depart.
	--
	-- L'enfoncement seul ne suffit pas : sur des feuilles larges, rentrer de 0.7 stud une feuille qui en fait
	-- deux ne se voit presque pas. C'est le RETRECISSEMENT qui rend la coupe evidente, parce qu'il change la
	-- SILHOUETTE et pas seulement la profondeur.
	-- Pas zero : une feuille qui disparait laisse un trou, et on retombe sur le probleme qu'on a passe la
	-- soiree a corriger. Elle doit rester la, juste rase.
	CUT_LEAF_SHRINK = 0.35,
	-- Taille MINIMALE d'une feuille taillee, en studs. 0 = pas de plancher.
	--
	-- Difference avec CUT_LEAF_SHRINK, qui est une FRACTION : chaque feuille nait avec une taille tiree au
	-- hasard, donc une fraction leur laisse leur ecart de depart et la surface rase reste irreguliere. Un
	-- plancher absolu les rapproche toutes de la meme taille : la surface taillee devient plus UNIFORME.
	--
	-- C'est un choix de rendu, pas un reglage de confort. Uniforme = "c'est propre, c'est fini". Irregulier =
	-- "c'est taille mais ca vit encore". Les deux se defendent, mais ils ne racontent pas la meme chose.
	--
	-- ATTENTION, C'EST DES STUDS, donc ca depend de CELL_SIZE et de LEAF_SCALE. Une feuille mesure aujourd'hui
	-- de 0.88 a 1.64 stud a pousse pleine, et de 0.31 a 0.57 au ras. Un plancher POSE AU-DESSUS de cette
	-- derniere plage ne rend pas la surface plus propre : il MANGE la fin de la coupe, et le joueur taille sans
	-- plus rien voir bouger. Pose au-dessus de 0.88, il fait carrement GROSSIR les petites feuilles.
	-- Chaque fois que CELL_SIZE ou LEAF_SCALE bouge, cette valeur est a revoir.
	-- A 0.4 : la surface rase passe d'un ecart de 1.85x a 1.4x, et seule la plus petite feuille perd ses 16
	-- derniers pourcents de retrecissement.
	CUT_LEAF_MIN_SIZE = 1.3,

	-- Carreau de BORDURE. Marque a la creation, parce que c'est la seule fois ou on connait la grille.
	EDGE_ATTRIBUTE = "Edge",
	-- Carreau de la rangee du SOL (bas d'un cote). Distinct de Edge : il recoit un bonus de PORTEE a la coupe
	-- (frange dure a atteindre), mais SANS destruction de feuille (garder la haie fermee par en dessous).
	BASE_ATTRIBUTE = "Base",
	-- Sur une arete, une feuille arrivee au ras est DETRUITE au lieu de rester rase.
	--
	-- La silhouette d'une haie, c'est ses aretes : les faces se voient de face, les aretes se decoupent sur le
	-- ciel. Une feuille rase qui depasse encore de l'arete garde le contour flou, alors que toute la face est
	-- nette. Elle enleve donc au resultat au lieu d'y ajouter.
	-- Uniquement sur les BORDURES : au milieu d'une face, un trou serait un manque, pas une coupe.
	CUT_EDGE_CLEAR = true,
	-- Pousse retiree par seconde sous la lame. 3.5 = un carreau passe de plein a ras en 0.29 seconde.
	--
	-- PROGRESSIF et non instantane : un aplanissement immediat ne demande aucun travail, donc n'en vaut aucun.
	-- Mais trop lent, le joueur a l'impression que l'outil ne mord pas. Le bon reglage est celui ou il voit la
	-- surface descendre SANS avoir a attendre : le geste doit rester continu, pas devenir du polissage.
	CUT_RATE = 3.5,
	-- Part du balancement conservee a ras. Une cellule taillee bouge presque plus.
	--
	-- Signal gratuit et tres fort : le desordre remue, le propre est immobile. L'oeil voit la ligne de coupe se
	-- former sans qu'on ait rien a lui expliquer, et sans une seule icone a l'ecran.
	TRIMMED_SWAY = 0.12,
	-- Couleur d'une feuille TAILLEE au ras. La feuille vire du vert frais (celui de l'asset, environ 58,113,38)
	-- vers ce vert plus sombre a mesure que la pousse descend.
	--
	-- Deuxieme lecture du geste, gratuite : vert clair = a faire, vert fonce = fait, rouge = trop. La couleur
	-- FRAICHE n'est PAS reglee ici : elle vient du SurfaceAppearance de la feuille, seule source de verite.
	-- La retaper en config donnerait deux valeurs a garder d'accord, et l'une finirait par mentir.
	TRIMMED_COLOR = Color3.fromRGB(44, 86, 29),

	-- VARIANTES de la couleur de coupe. Chaque feuille tire la sienne dans cette palette (par un hash de sa position,
	-- cote client) : une haie taillee montre alors des TACHES de tons legerement differents au lieu d'un vert uniforme,
	-- ce qui fait plus vivant / naturel. Format { couleur, poids }. La base domine, les accents sont plus rares.
	-- Regler les poids pour doser : plus de poids sur la base = taches plus rares ; plus sur un accent = il ressort plus.
	TRIMMED_COLOR_VARIANTS = {
		{ color = Color3.fromRGB(44, 86, 29), weight = 6 }, -- base (la meme que TRIMMED_COLOR) : dominante
		{ color = Color3.fromRGB(66, 86, 44), weight = 2 }, -- accent CLAIR
		{ color = Color3.fromRGB(49, 95, 32), weight = 2 }, -- accent moyen
		{ color = Color3.fromRGB(37, 70, 24), weight = 2 }, -- accent SOMBRE
	},

	-- DEGRADE VERTICAL. Le BAS de la haie tire vers ce vert sombre (moins de lumiere l'atteint : plus naturel qu'un
	-- vert uniforme du sol au sommet). Dose maximale tout en bas, nulle en haut. S'applique a la couleur FINALE, donc
	-- sur la haie fraiche comme taillee.
	BOTTOM_GRADIENT_COLOR = Color3.fromRGB(37, 70, 24),
	-- Force du degrade tout en bas (0 = aucun, 1 = le bas devient pleinement BOTTOM_GRADIENT_COLOR). A doser a l'oeil.
	BOTTOM_GRADIENT_STRENGTH = 0.65,

	-- ===== SUR-TAILLE =====
	-- Un carreau deja au ras qu'on continue de raser s'ABIME. C'est l'enjeu du geste : sans consequence a trop
	-- insister, la precision ne vaut rien et le joueur balaie sans reflechir.
	--
	-- Portee par un attribut, comme la pousse : le serveur decide, chaque client en deduit le rendu. Quelle que
	-- soit la facon dont on montrera les degats plus tard (feuille retiree, teinte, mesh enfonce), c'est CETTE
	-- donnee qu'il faudra, et elle ne changera pas.
	DAMAGE_ATTRIBUTE = "Damage",
	-- Degats ajoutes par seconde sous la lame, une fois le carreau au ras.
	--
	-- BIEN PLUS LENT que la coupe (3.5) : il faut vraiment s'acharner. Un joueur qui passe normalement ne doit
	-- jamais abimer par accident, sinon la punition devient du hasard et il cesse d'essayer d'etre precis.
	--
	-- 0.22 et non 0.55 : a 0.55 il fallait balayer sans jamais s'arreter, donc la punition arrivait AVANT que
	-- le joueur ait eu le temps de comprendre la regle. Une sanction qu'on ne voit pas venir n'apprend rien.
	-- Ici il faut quinze fois plus de temps a s'acharner qu'a faire le travail : impossible par accident,
	-- evident quand on insiste.
	DAMAGE_RATE = 0.16,
	-- Couleur d'un carreau completement abime. La feuille vire vers elle a mesure des degats.
	--
	-- LA COULEUR ET LA TRANSPARENCE SE COMBATTENT : une feuille a 97 pour cent transparente ne montre plus
	-- aucune couleur. Il faut choisir lequel des deux porte le message.
	-- Ici c'est la COULEUR : une plaque rouge se lit a dix metres, alors qu'un trou ne se lit que de face.
	DAMAGE_COLOR = Color3.fromRGB(159, 44, 44),
	-- Part de degats a partir de laquelle la couleur COMMENCE a apparaitre.
	--
	-- Sans ce seuil, le rouge montait des le premier pourcent : un joueur qui s'attarde une seconde voyait deja
	-- sa haie rougir, donc la sanction commencait AVANT qu'il ait rien fait de mal.
	-- Avec, il existe une zone ou l'on abime sans que ca se voie. C'est ce qui rend la regle apprenable : on a
	-- le temps de s'ecarter, et quand le rouge arrive, il veut dire quelque chose.
	DAMAGE_TINT_START = 0.5,
	-- Part de degats a partir de laquelle la feuille commence a s'EFFACER, et transparence atteinte au bout.
	--
	-- Plus TARD que la teinte, jamais en meme temps : un fondu qui accompagne le rouge le lave, et on perd le
	-- seul signal qui portait le message. Ici le rouge s'installe d'abord, franc, puis la feuille s'efface.
	-- Le fondu ne sert qu'a preparer la disparition : sans lui elle sauterait d'un coup.
	DAMAGE_FADE_START = 0.8,
	DAMAGE_FADE_MAX = 0.8,
	-- Retirer la feuille completement abimee.
	--
	-- Possible SEULEMENT parce qu'une couche de bois habille l'interieur de la haie : sans elle on verrait le
	-- vide, et un trou est un desordre, pas un degat. Avec elle, la feuille morte laisse voir la branche nue,
	-- ce qui est exactement ce qu'on voit sur une haie taillee trop court.
	DAMAGE_CLEAR = true,

	-- ===== LA LAME QUI FORCE =====
	-- L'ecran tremble quand on mord dans du bois deja au ras. Il tremble de plus en plus fort a mesure que le
	-- carreau s'abime.
	--
	-- ELLE DEMARRE AVEC LE ROUGE, pas avant. Essayee en avertissement precoce, elle arrivait trop tot et
	-- trop souvent : le joueur la subissait sans comprendre a quoi elle repondait, puisque rien ne se voyait
	-- encore. Un signal qu'on ne peut pas relier a une cause n'avertit pas, il agace.
	-- La zone de grace redevient donc VRAIMENT silencieuse, et les deux retours partent ensemble.
	DAMAGE_TICK_ATTRIBUTE = "LeafiaGrindTick",
	-- Intensite courante, de 0 a 1, lue par le client quand le compteur bouge. Deux attributs et non un : un
	-- compteur garantit le signal meme quand l'intensite ne change pas, l'autre porte la valeur.
	DAMAGE_LEVEL_ATTRIBUTE = "LeafiaGrindLevel",
	DAMAGE_TICK_INTERVAL = 0.1,
	-- Degats a partir desquels l'ecran tremble. Cale sur DAMAGE_TINT_START : la main et l'oeil disent la meme
	-- chose au meme moment, donc le joueur relie tout de suite l'un a l'autre.
	DAMAGE_SHAKE_START = 0.5,
	-- Secousse au declenchement, puis au maximum. En studs, c'est un DEPLACEMENT.
	--
	-- Volontairement PROCHE de la secousse de coupe (0.02) au depart : c'est une gene qui s'installe, pas une
	-- alarme. Une alarme se subit ; une gene se corrige.
	DAMAGE_SHAKE_MIN = 0.03,
	DAMAGE_SHAKE_MAX = 0.1,
	DAMAGE_SHAKE_DURATION = 0.12,
	-- Part de la haie abimee, posee sur la HAIE. Servira a la note du client.
	DAMAGED_ATTRIBUTE = "LeafiaDamaged",

	-- Avancement de la haie, de 0 a 1, pose sur la HAIE. Servira a la jauge et a l'experience.
	TRIMMED_ATTRIBUTE = "LeafiaTrimmed",
	-- AUTO-COMPLETION : au-dela de ce ratio (les derniers % chiants a aller chercher : dessus, recoins), on finit la
	-- haie TOUT SEUL. Le joueur a fait le gros du travail, on lui epargne la chasse aux carreaux perdus (equilibre
	-- patient / impatient). Sur une haie HAUTE, atteindre ce seuil exige deja l'echelle (le dessus fait plus que ca) ->
	-- l'echelle reste necessaire, l'auto-completion ne mange que la derniere frange.
	AUTO_COMPLETE_THRESHOLD = 0.95,
	-- Garde "paye une fois" pose sur la HAIE : true des qu'elle a verse son cheque de fin (100%). Sans lui, continuer
	-- a passer la lame sur une haie deja finie la re-paierait. HedgeCutService le lit / le pose. (Si un jour les haies
	-- repoussent et doivent re-payer, c'est ici qu'on remettra l'attribut a nil au moment de la repousse.)
	PAID_ATTRIBUTE = "LeafiaPaid",

	-- ===== HOLOGRAMME DE CHANTIER =====
	-- Une etiquette accrochee au-dessus de chaque haie a faire. Elle disparait quand la haie est finie : ce qui
	-- reste a l'ecran est ce qui reste A FAIRE, jamais ce qui est deja regle.
	HOLOGRAM_GUI = "HedgeHolograms",
	-- Modele a cloner, cherche dans ce ScreenGui. Absent, une etiquette minimale est construite en code : on ne
	-- veut pas attendre un asset pour verifier que le systeme marche.
	HOLOGRAM_TEMPLATE = "Template",
	-- TextLabel a remplir dans le modele. Absent, on ecrit dans le premier TextLabel trouve.
	HOLOGRAM_VALUE = "Value",
	-- Hauteur au-dessus du SOMMET de la haie, en studs.
	HOLOGRAM_LIFT = 2.5,
	-- Au-dela, l'etiquette est cachee. Un jardin entier d'etiquettes lisibles a cinquante studs ne montre plus
	-- rien : c'est du bruit, pas de l'information.
	HOLOGRAM_RANGE = 70,
	-- MOBILE : le cartouche est en PIXELS fixes, donc enorme sur un petit ecran. On le retrecit d'un coup via un
	-- UIScale pose a la creation sur tactile. 1 = pas de changement. A REGLER a l'oeil.
	HOLOGRAM_TOUCH_SCALE = 0.55,
	-- Titre affiche au-dessus de la valeur.
	HOLOGRAM_TITLE = "Taille",
	HOLOGRAM_COLOR = Color3.fromRGB(255, 255, 255),
	-- Ligne de rappel : longueur de la diagonale et de la barre, en pixels, et angle de la diagonale.
	--
	-- Une ligne qui PART du point et remonte, plutot qu'une etiquette posee au-dessus : elle designe l'objet au
	-- lieu de flotter a cote, et le texte se retrouve dans une zone degagee du ciel plutot que dans le feuillage.
	HOLOGRAM_LEG = 46,
	HOLOGRAM_BAR = 78,
	HOLOGRAM_ANGLE = -42,

	-- Effet emis a la coupe, dans ReplicatedStorage.Assets.Effects. Cote CLIENT : des particules sont du
	-- ressenti pur, les repliquer serait payer du reseau pour quelque chose que chacun peut calculer.
	-- VIDE = aucun effet, et aucun avertissement. C'est un etat NORMAL, pas une erreur : on coupe un retour le
	-- temps de juger le geste sans lui.
	CUT_EFFECT = "LeafCutEffectsRoot",
	-- Nombre de particules par bouffee. Surchargeable emetteur par emetteur avec un attribut "EmitCount", comme
	-- pour les effets d'outil.
	-- Le support de l'effet est cree UNE fois puis deplace : pas de duree de vie a regler, rien a detruire.
	CUT_EFFECT_COUNT = 8,

	-- Couper exige-t-il de MAINTENIR l'accelerateur ?
	--
	-- true : le clic sert a quelque chose, et la boucle devient "je vise, j'accelere, ca tombe". false : les
	-- lames coupent des qu'elles tournent, le clic ne sert plus qu'au bruit.
	CUT_NEEDS_THROTTLE = true,
	-- Intervalle minimal entre deux bouchees clic-par-clic (cisaille), en secondes. Anti-spam serveur : un clic
	-- humain ne depasse pas une douzaine par seconde, au-dela c'est un script qui veut tailler en rafale. 0.08 =
	-- environ douze clics par seconde, large pour la main, ferme pour le reste.
	CUT_CLICK_MIN_INTERVAL = 0.08,

	-- TACTILE : cadence a laquelle la cisaille RE-declenche toute seule quand on glisse le doigt (drag-to-cut). C'est
	-- une cadence DELIBEREE, pas le plancher anti-triche : la cisaille doit rester lente (l'outil pourri du debut).
	-- Tirer au plancher (0.08) la rendait aussi rapide qu'un spam-clic, donc "beaucoup trop vite" sur mobile.
	-- A REGLER a l'oeil (monter = plus lent). Le serveur borne toujours en dessous a CUT_CLICK_MIN_INTERVAL.
	CUT_TOUCH_SNIP_INTERVAL = 0.3,

	-- Compteur pose sur le PERSONNAGE a chaque fois que des feuilles tombent. Le client s'y branche pour ses
	-- retours. Un COMPTEUR et non un booleen : deux coupes d'affilee ecriraient la meme valeur, l'attribut ne
	-- changerait pas, et le client raterait la seconde. Toujours pas de remote, l'attribut se replique seul.
	CUT_TICK_ATTRIBUTE = "LeafiaCutTick",
	-- Temps minimal entre deux signaux, en secondes.
	--
	-- Sans lui le serveur en enverrait soixante par seconde pendant un balayage : le reseau pour rien, et une
	-- secousse permanente au lieu d'un retour. Cet ecart laisse un blanc entre deux secousses, donc chacune se
	-- remarque.
	CUT_TICK_INTERVAL = 0.15,
	-- Secousse camera a chaque signal. TRES faible : elle doit se sentir sans se voir. Une secousse qu'on
	-- remarque fatigue au bout de trente secondes de taille, et on taille beaucoup.
	CUT_SHAKE_INTENSITY = 0.02, -- en studs, c'est un DEPLACEMENT
	CUT_SHAKE_DURATION = 0.1,

	-- Sons de coupe, dans SoundService. Chemin en liste, comme pour les outils. VIDE = aucun son, sans warn.
	--
	-- POINTE SUR LE DOSSIER, pas sur un son : TOUS les Sound qu'il contient sont pris, et un est tire au hasard
	-- a chaque coupe. Deposer un echantillon de plus dans Studio augmente donc la variete sans toucher au code.
	-- Un chemin qui designe directement un Sound marche aussi, il n'y en aura simplement qu'un.
	CUT_SOUND = { "Sounds", "Environnement", "Leafs" },
	-- Temps minimal entre deux declenchements, en secondes.
	--
	-- Le signal de coupe arrive environ sept fois par seconde ; un son de 0.7 s joue a ce rythme donnerait cinq
	-- copies superposees en permanence, donc une bouillie. Cet ecart les espace assez pour qu'on entende des
	-- coups distincts.
	CUT_SOUND_INTERVAL = 0.22,
	-- Variation ALEATOIRE de hauteur, en part de 1. Sans elle, le meme echantillon repete se reconnait tout de
	-- suite comme une boucle et devient penible en trente secondes. C'est le reglage le moins cher qui separe
	-- un son de jeu d'un bip.
	CUT_SOUND_PITCH = 0.14,
	-- Variation ALEATOIRE de volume, en part de 1. Plus discrete que la hauteur, mais c'est elle qui donne
	-- l'impression que certaines branches resistent plus que d'autres.
	CUT_SOUND_VOLUME = 0.25,

	-- ===== ZONES DE DEPOT AU SOL =====
	-- Une bande posee au sol le long de chaque cote. Les feuilles coupees y voleront, s'y entasseront, et se
	-- ramasseront plus tard au rateau.
	--
	-- Pose des maintenant alors que rien n'y tombe encore : c'est ce qui permet de regler l'emprise A L'OEIL
	-- avant d'ecrire la trajectoire des feuilles. Une courbe reglee sur une zone qui bouge ensuite est une
	-- courbe a refaire.
	STOCK_NAME = "GroundStockLeafsRoot",
	STOCK_FOLDER = "HedgeGroundStocks",
	-- Profondeur de la bande, vers l'exterieur de la haie. Sa LONGUEUR suit le cote qu'elle borde.
	STOCK_WIDTH = 3,
	-- ECART entre le bord de la haie et le debut de la bande. Distinct de la largeur : on veut pouvoir eloigner
	-- la zone sans l'agrandir, sinon regler l'un abime l'autre.
	-- C'est aussi la place ou le joueur se tient pour tailler : une zone de depot sous ses pieds serait
	-- illisible, et les feuilles y voleraient a travers lui.
	STOCK_GAP = 1,
	-- Epaisseur de la dalle. Fine : c'est un marquage au sol, pas une marche.
	STOCK_THICKNESS = 0.4,
	-- Leger soulevement pour ne pas clignoter contre le sol : deux surfaces au meme niveau se disputent
	-- l'affichage pixel par pixel.
	STOCK_LIFT = 0.05,
	STOCK_COLOR = Color3.fromRGB(255, 40, 200),
	STOCK_TRANSPARENCY = 0.8,

	-- Tas de feuilles coupees, deposes dans la zone. Modele dans ReplicatedStorage.
	STOCK_DEBRIS_ASSET = { "Assets", "Contents", "LeafsDebrisGroundType1" },
	-- Carreaux amenes au ras pour deposer UN tas.
	--
	-- Un tas par carreau ferait des centaines de modeles par haie. Ce rythme-la donne une dizaine de tas par
	-- face : assez pour qu'on VOIE le travail s'accumuler, assez peu pour que ca reste lisible et gratuit.
	STOCK_DEBRIS_PER_CELLS = 6,
	-- Plafond par ZONE. Au-dela, le plus ancien est retire.
	--
	-- Sans lui, une haie qui repousse et se retaille indefiniment empilerait des modeles pour toujours. Un
	-- plafond par zone garde en plus les quatre cotes equilibres.
	STOCK_DEBRIS_MAX = 30,
	-- Variation de taille, pour que deux tas voisins ne soient pas jumeaux.
	STOCK_DEBRIS_SCALE_MIN = 0.75,
	STOCK_DEBRIS_SCALE_MAX = 1.3,
	-- Marge gardee au bord de la zone, en studs : un tas pose pile sur le bord deborderait sur l'herbe.
	STOCK_DEBRIS_INSET = 0.6,
	-- Dispersion autour des PIEDS du joueur, en studs.
	--
	-- Les tas tombent la ou il travaille, pas au hasard dans la zone : c'est ce qui fait qu'on VOIT son
	-- parcours au sol, et qu'un cote fini se distingue d'un cote a faire. Ce nombre ne sert qu'a eviter que
	-- deux tas se superposent exactement au meme endroit.
	STOCK_DEBRIS_JITTER = 0.8,
	-- OU dans la profondeur de la bande, de 0 (bord cote haie) a 1 (bord exterieur).
	--
	-- Les deux axes de la zone ne jouent pas le meme role, et c'est voulu :
	--   le LONG de la haie -> suit le joueur, c'est ce qui dessine sa trace
	--   la PROFONDEUR      -> ce reglage, fixe, pour degager le pied de la haie
	-- Suivre le joueur dans les deux sens collait les tas contre la haie, la ou il se tient pour tailler : ils
	-- se melangeaient au feuillage et genaient le passage.
	STOCK_DEBRIS_OUT = 0.7,
	-- Dispersion AUTOUR de cette profondeur, dans la meme unite (0 a 1).
	--
	-- Sans elle, tous les tas s'alignent sur une seule ligne et on lit la mecanique au lieu de voir des
	-- feuilles. Certaines vont plus loin que d'autres, comme quand on balaie vraiment.
	-- Le resultat reste borne a la bande : on ne deborde jamais sur l'herbe.
	STOCK_DEBRIS_OUT_SPREAD = 0.4,

	-- DEBUG : dessine le volume de detection dans le monde. A passer a false avant toute publication.
	-- Delai apres un changement de face pendant lequel on NE juge PAS l'intention de sortir.
	--
	-- En tournant le coin, la normale pivote de 90 degres : le glissement lateral d'avant se retrouve aligne
	-- avec la nouvelle normale, et le test de sortie le lisait comme une fuite. Le joueur etait ejecte du
	-- chantier au moment precis ou il contournait.
	-- Assez long pour couvrir la latence de replication de la nouvelle normale vers le client, assez court
	-- pour qu'une vraie sortie juste apres un coin reste immediate.
	FACE_CHANGE_GRACE = 0.35,

	-- REPERE DE COUPE (guide visuel joueur). Un disque translucide plaque SUR la surface, a l'endroit vise :
	-- "tu couperas ici". Remplace l'ancien cylindre-capsule debug (Neon + Highlight always-on-top) qui faisait une
	-- grosse masse blanche devant la vue. Construit depuis la DERNIERE visee ENVOYEE (ce que le serveur a en main),
	-- pour rester fidele a ou ca coupe reellement.
	VISUAL_CUT_ENABLED = true,
	-- Modele CLONE pour le repere : une Part FINE (Y = epaisseur) avec un SurfaceGui sur sa face du HAUT (le cercle
	-- OutlineFrame + PointCenterFrame). Vit dans ReplicatedStorage.Assets.Effects (cote Studio). On le clone, on
	-- l'oriente A PLAT contre la surface visee (sa face du haut suit la NORMALE) et on redimensionne X / Z pour couvrir
	-- la coupe. Le DESSUS d'une haie devient donc plat tout seul, la face reste verticale.
	VISUAL_CUT_TEMPLATE = "VisualRootTarget",
	-- TROIS ETATS : la couleur et la transparence changent selon ce que fait le joueur, la forme non. Toujours
	-- assez transparent pour ne JAMAIS masquer la haie qu'on travaille.
	--
	-- COULEUR SELON LA MATIERE sous la lame : BLANC s'il reste des feuilles a couper, ORANGE si c'est NU (rien a faire).
	-- Approximation cote client : quand on TAILLE sans qu'aucun coup ne morde depuis VISUAL_CUT_DRY_TIME, on est sur du
	-- nu -> orange. Sinon (des feuilles tombent, ou on ne fait que viser) -> blanc.
	VISUAL_CUT_FOLIAGE_COLOR = Color3.fromRGB(255, 255, 255), -- il reste a couper -> blanc
	VISUAL_CUT_BARE_COLOR = Color3.fromRGB(255, 140, 25), -- deja nu -> orange
	VISUAL_CUT_DRY_TIME = 0.2, -- temps a tailler SANS qu'un coup morde avant de passer en "nu" (orange), en secondes
	-- OU SE PLACE LE REPERE DE COUPE (le cercle blanc).
	-- true  : il suit le CURSEUR, la ou on pointe sur la haie. Plus direct a lire, on regarde ou on vise.
	-- false : il suit la LAME, c'est-a-dire ce que le serveur va REELLEMENT couper.
	--
	-- A savoir avant de basculer : les deux ne coincident pas. Le serveur coupe sur le segment de LAME, et rien ne
	-- garantit qu'a 80 pour cent de visee le bras place la lame a 80 pour cent de la hauteur de la haie -- surtout
	-- lateralement, ou le curseur peut etre loin des mains. A `true`, le cercle designe donc parfois un endroit qui
	-- ne sera pas coupe. C'est un choix de LISIBILITE contre un choix d'HONNETETE, pas un bug d'un cote ou de l'autre.
	VISUAL_CUT_FOLLOWS_CURSOR = true,
	-- (anciens etats guide/coupe, gardes pour la transparence ; la couleur vient maintenant de la matiere ci-dessus)
	VISUAL_CUT_GUIDE_TRANSPARENCY = 0.8,
	VISUAL_CUT_CUT_TRANSPARENCY = 0.7,
	-- HORS HAIE : rare (souris sortie -> le repere est deja cache). Orange d'avertissement, au cas ou.
	VISUAL_CUT_OFF_COLOR = Color3.fromRGB(255, 140, 20),
	VISUAL_CUT_OFF_TRANSPARENCY = 0.8,
	-- Epaisseur du disque le long de la normale (fin = plaque contre la surface). Le diametre, lui, est CALCULE
	-- pour couvrir la coupe (longueur de lame + largeur taillee).
	VISUAL_CUT_THICKNESS = 0.15,
	-- Recul du disque hors de la surface, pour qu'il pose SUR les feuilles au lieu de vibrer dedans (z-fighting).
	VISUAL_CUT_SURFACE_OFFSET = 0.1,
	-- Facteur sur la taille du cercle (le diametre couvre la coupe : longueur de lame + largeur taillee). < 1 pour un
	-- repere plus PETIT et discret ; ne change QUE le visuel, pas la coupe reelle. A REGLER a l'oeil.
	VISUAL_CUT_SIZE_SCALE = 0.55,
	-- SLIME + PRESSAGE du cercle : un ressort amorti pilote son echelle. Il JAILLIT de 0 a l'apparition (rebond slime),
	-- et se PRESSE (retrecit un peu) tant qu'on taille, puis rebondit a l'arret. Amortissement BAS = rebond visible.
	VISUAL_CUT_SLIME_STIFFNESS = 350, -- raideur (haut = pop plus rapide / plus sec)
	VISUAL_CUT_SLIME_DAMPING = 11, -- amortissement (bas = rebondit plus, effet slime ; haut = se pose vite)
	VISUAL_CUT_PRESS_SCALE = 0.9, -- echelle cible tant qu'on TAILLE (pressage leger). 1 = pas de pressage.
	-- Impulsion donnee au ressort a CHAQUE coup (tick de coupe / clic) : le cercle gonfle d'un coup puis rebondit ->
	-- un slime a chaque coupe. Vitesse en echelle/s. 0 = pas de pop au coup. A REGLER a l'oeil.
	VISUAL_CUT_CLICK_KICK = 4,

	DEBUG_RAY = false,
	-- Les boites gardent leur TAILLE REELLE, celle qui est testee : la retrecir pour mieux voir ferait mentir
	-- le debug, ce qui a deja coute une soiree. C'est la TRANSPARENCE qu'on monte pour voir a travers.
	DEBUG_TRANSPARENCY = 0.82,
	-- La boite de debug reprend DETECT_WIDTH et DETECT_HEIGHT : ce qu'on voit EST ce qui est teste. Plus de
	-- taille cosmetique reglable a part, c'etait la source de la confusion.
	DEBUG_COLOR_MISS = Color3.fromRGB(255, 131, 60), -- rien devant
	DEBUG_COLOR_HIT = Color3.fromRGB(60, 255, 76), -- une haie est visee
}

return HedgeConfigs
