--!strict
-- HERBE DE ZONE : on pose une part dans Studio, elle se remplit de touffes, et les touffes se couchent quand un
-- joueur marche dessus.
--
-- Tout est CLIENT. L'herbe est purement decorative : sa position ne change aucune regle du jeu, et l'ecrasement
-- depend de qui marche ou, a chaque image. Faire transiter ca par le reseau serait payer cher pour rien. Chaque
-- client fabrique donc SES touffes et les couche lui-meme.
-- La disposition reste identique chez tout le monde : le tirage au sort part d'une graine calculee sur la POSITION
-- de la zone, donc deux joueurs devant la meme zone voient exactement la meme herbe.

local GrassZoneConfigs = {
	-- Toute part dont le nom COMMENCE par ce prefixe est remplie. "ZoneGrassHandle", "ZoneGrass_Jardin"... marchent.
	ZONE_PREFIX = "ZoneGrass",

	-- Ou chercher les zones, sous Workspace. Meme racine que les haies.
	ROOT = { "Worlds", "Maps" },

	-- Le mesh a dupliquer, sous ReplicatedStorage.
	MESH_PATH = { "Assets", "Contents", "Foliages", "GrassMesh" },

	-- Mesh de l'herbe COUPEE, range A COTE de MESH_PATH. Quand une touffe est tondue, son maillage est remplace
	-- par celui-ci : une herbe rase n'a pas la meme forme qu'une herbe haute, et la raccourcir ne suffit pas a le
	-- faire croire.
	-- Introuvable = pas d'echange, la touffe se contente de raccourcir comme avant. Ce n'est donc pas bloquant.
	CUT_MESH_NAME = "GrassCut",
	-- A quel avancement de la coupe (0 a 1) on echange le maillage.
	-- A MI-COURSE et pas a la fin : la touffe est alors deja bien tassee, sa silhouette est petite, donc le
	-- changement de forme passe inapercu. Echanger a 0 (des le premier contact) rendrait le saut bien visible,
	-- puisque la touffe est encore a sa pleine hauteur.
	MOW_SWAP_AT = 0.5,

	-- ===== EMERGENCE DE L'HERBE COUPEE =====
	-- Au moment de l'echange de maillage, la touffe coupee est ENFONCEE sous la surface, et elle remonte a sa
	-- place en prenant sa couleur en chemin.
	--
	-- POURQUOI. Sans ca, l'herbe coupee APPARAIT par-dessus, deja de sa couleur : on voit qu'on AJOUTE quelque
	-- chose, pas qu'on coupe. En la faisant sortir du sol, elle a l'air d'avoir toujours ete la, dessous, cachee
	-- par l'herbe haute -- ce qui est d'ailleurs la verite d'une pelouse.
	--
	-- Duree en secondes. Assez longue pour se VOIR, assez courte pour ne pas trainer derriere la machine.
	-- La coupe elle-meme dure 0.125 s (MOW_RATE) : c'est bien trop court pour qu'on y lise une transition, et
	-- c'est justement pour ca que l'emergence a son propre temps au lieu de suivre l'avancement de la coupe.
	-- Historique : 0.35 (trop sec, ca ressemblait a un interrupteur), 0.9 (trop mou), 0.45.
	--
	-- A NE PAS CONFONDRE AVEC CUT_RISE_DELAY, juste en dessous. Celui-ci dit a quelle VITESSE la touffe descend et
	-- sort du sol ; l'autre dit QUAND elle commence. "Ca se couche trop tot" se regle avec le DELAI, "ca se couche
	-- trop lentement" avec celui-ci -- les confondre force a sacrifier l'un pour l'autre.
	--
	-- Et surtout pas MOW_RATE : celui-la decide si la touffe est coupee, pas de ce qu'on VOIT.
	CUT_RISE_TIME = 0.45,
	-- TEMPS MORT avant que la touffe commence a descendre, en secondes.
	--
	-- La lame passe, et la touffe tient encore un instant avant de tomber. C'est ce court retard qui fait la
	-- difference entre "l'herbe s'eteint sous la machine" et "la machine coupe l'herbe" : sans lui, la coupe est
	-- SIMULTANEE au passage, donc elle ressemble a un interrupteur.
	--
	-- Monte de 0.18 : la touffe tombait encore trop tot, donc trop pres de la machine.
	--
	-- ON APPROCHE DE LA LIMITE. Au-dela d'une demi-seconde, on voit la machine passer et l'herbe tomber loin
	-- DERRIERE elle -- ca cesse de se lire comme une coupe et ca ressemble a un retard d'affichage.
	CUT_RISE_DELAY = 0.35,
	-- De combien elle est enfoncee au depart, en part de sa PROPRE hauteur (1 = entierement sous la surface).
	-- RELATIF et pas en studs : l'herbe n'a pas la meme taille partout, et une valeur absolue laisserait les
	-- touffes hautes depasser pendant que les basses seraient enterrees trop profond.
	CUT_RISE_DEPTH = 1,
	-- DUREE DE LA SORTIE DE TERRE, en secondes. Elle a son PROPRE temps, et elle part IMMEDIATEMENT.
	--
	-- Elle etait accrochee au meme compteur que l'abaissement. Resultat, quand le temps mort a ete ajoute
	-- (CUT_RISE_DELAY), la touffe restait ENFOUIE pendant toute l'attente -- donc invisible -- avant de sortir.
	-- On voyait un trou dans la pelouse, puis l'herbe remonter : l'inverse de l'effet cherche.
	--
	-- Les deux moments n'ont rien a voir : SORTIR DE TERRE doit etre immediat et bref (c'est un remplacement, il
	-- ne doit pas se voir), SE COUCHER doit venir apres et se voir (c'est la coupe).
	CUT_RISE_UP_TIME = 0.15,

	-- Delai TOTAL pour trouver la racine et le mesh au demarrage (un seul delai pour tout le chemin).
	RESOLVE_TIMEOUT = 15,

	-- ===== Remplissage =====
	-- Le semis est une GRILLE, pas un tirage au hasard. Un tirage purement aleatoire laisse des trous a un endroit et
	-- des paquets a un autre : sur une surface qu'on veut COUVERTE, ca se voit tout de suite. La grille garantit que
	-- toute la surface est prise, et le JITTER casse l'alignement en damier.
	-- Touffes par stud carre. C'EST LE PREMIER BOUTON A REGLER : trop bas ca fait chauve, trop haut ca coute des parts
	-- pour rien (l'oeil ne voit plus la difference bien avant le processeur).
	-- MESURE : a 1.0 sur une carte de 4 pelouses (133x50, 133x52, 81x53, 32x7) le total montait a 18 546 parts.
	-- Injouable. A 0.2 on retombe autour de 3 700, avec des touffes 2.2x plus grosses (voir AUTO_SCALE_WITH_DENSITY)
	-- donc une couverture visuelle equivalente. C'est LE bouton pour arbitrer entre finesse et nombre de parts.
	DENSITY = 0.35,
	-- ===== PROFIL MOBILE =====
	-- Le public Roblox est majoritairement mobile. Un telephone n'a ni la puissance de calcul ni la bande passante
	-- graphique d'un PC : la meme pelouse y devient injouable alors qu'elle tourne a 200 images par seconde ici.
	--
	-- Ces valeurs REMPLACENT leurs equivalentes sur un appareil tactile. Elles ne sont pas "la version degradee" :
	-- elles sont la version qui TOURNE, et c'est la seule qui compte pour la moitie des joueurs.
	--
	-- DENSITE MOBILE. Le mecanisme de compensation (AUTO_SCALE_WITH_DENSITY) fait le gros du travail : a 0.12 les
	-- touffes sont bien plus larges, donc la pelouse reste COUVERTE. On divise le nombre de parts par trois sans
	-- que la pelouse ait l'air trouee.
	MOBILE_DENSITY = 0.12,
	-- RAYON D'ANIMATION MOBILE. C'est l'autre moitie du cout : moins de touffes ANIMEES par image, pas seulement
	-- moins de touffes. Au-dela de ce rayon elles sont posees et immobiles -- ce qui ne se voit pas de loin.
	MOBILE_WIND_VIEW_DISTANCE = 14,
	MOBILE_WIND_FADE_START = 6,
	-- Combien de touffes on cree par image pendant le semis. Plus bas sur mobile : le semis est etale sur plus
	-- d'images, donc l'arrivee dans un jardin ne fait pas tomber le jeu a genoux pendant une seconde.
	MOBILE_CREATE_BUDGET = 120,

	-- ===== ON N'ANIME PAS CE QUE PERSONNE NE REGARDE =====
	-- Roblox ne DESSINE deja pas ce qui est derriere la camera. Ce qui coute, c'est NOTRE boucle : elle calculait
	-- le vent, l'ecrasement et la couleur de touffes situees dans le dos du joueur, pour un resultat que personne
	-- ne verra jamais.
	--
	-- Le test se fait par PAVE et pas par touffe : un produit scalaire pour six studs de cote, contre un par
	-- touffe. C'est ce qui rend l'economie gratuite.
	--
	-- 100 % CLIENT, donc AUCUN risque en co-op : chaque joueur construit et anime sa propre pelouse, rien ne
	-- transite. Cacher la sienne ne peut rien changer chez les autres.
	CULL_BEHIND = true,
	-- Produit scalaire en dessous duquel un pave est considere "dans le dos". 0 = pile sur les cotes, -1 = pile
	-- derriere. On prend une valeur NEGATIVE avec de la marge : le champ de vision est large, et un pave coupe une
	-- image trop tot se verrait se figer au bord de l'ecran.
	CULL_BEHIND_DOT = -0.35,
	-- Rayon autour du JOUEUR toujours anime, quoi qu'il regarde. Sans lui, les touffes sous ses pieds cesseraient
	-- de reagir des qu'il leve les yeux -- et celles-la, il les voit forcement.
	CULL_BEHIND_KEEP = 10,

	-- ===== L'HERBE LOINTAINE DISPARAIT (MOBILE UNIQUEMENT) =====
	-- Au-dela de cette distance du bord d'une zone, toute son herbe est RETIREE de l'affichage. En dessous, elle
	-- revient.
	--
	-- MOBILE SEULEMENT. Sur PC la pelouse lointaine ne coute presque rien et fait partie du decor : voir un jardin
	-- entier de loin, c'est ce qui donne envie d'y aller. On ne s'en prive que la ou l'appareil ne suit pas.
	--
	-- ON RETIRE, ON NE DETRUIT PAS. Un seul changement de parent sur le dossier fait disparaitre des milliers de
	-- parts d'un coup, et les rend tout aussi vite. Detruire obligerait a REFAIRE le semis en revenant -- des
	-- milliers de creations etalees sur plusieurs secondes, exactement l'a-coup qu'on cherche a eviter. La memoire,
	-- elle, n'est pas le probleme ici (866 Mo mesures sur 1300 disponibles) : c'est le CPU.
	--
	-- 90 studs : bien au-dela du rayon d'animation (14 sur mobile), donc l'herbe est deja immobile depuis longtemps
	-- quand elle disparait. On ne voit jamais le basculement.
	MOBILE_UNLOAD_DISTANCE = 90,
	-- Deplacement au hasard de chaque touffe DANS sa case, en fraction de la case. 0 = alignement parfaitement
	-- regulier, 1 = la touffe peut aller jusqu'au bord de sa case.
	-- ATTENTION, c'est LUI qui fait les trous : a 0.8, deux voisines peuvent s'ecarter de 80 % d'une case, et l'ecart
	-- se voit. Les rangees en quinconce (voir GrassZoneController) cassent deja la regularite, donc une valeur
	-- moderee suffit : on garde le desordre sans ouvrir de trou.
	JITTER = 0.45,
	-- FILET DE SECURITE, jamais un reglage. La densite est CONSTANTE quelle que soit la taille de la zone : une zone
	-- deux fois plus grande recoit deux fois plus de touffes, point. Redimensionner une zone ne doit JAMAIS obliger a
	-- revenir toucher une config.
	-- Ce nombre est volontairement place hors de portee des zones reelles : il n'existe que pour qu'une part posee par
	-- erreur a 500x500 ne fabrique pas 250 000 instances et ne fasse pas tomber le client. S'il se declenche, la
	-- console le DIT avec la densite reellement obtenue -- ce n'est pas un reglage a tourner, c'est un signal que la
	-- zone est anormale.
	MAX_CLUMPS = 20000,
	-- Taille de chaque touffe, en fraction de la taille du mesh d'origine. Un peu de variete casse l'effet "copie".
	SCALE_MIN = 0.85,
	SCALE_MAX = 1.25,
	-- HAUTEUR de l'herbe, a part. Multiplie UNIQUEMENT le Y de la touffe.
	-- C'est le bouton a tourner quand l'herbe est trop haute. Passer par SCALE_MIN / SCALE_MAX retrecirait aussi la
	-- LARGEUR, donc la couverture, et rouvrirait des trous : hauteur et couverture n'ont rien a voir.
	HEIGHT_SCALE = 1.0,
	-- ZONES DE HAUTEUR. Des endroits ou l'herbe pousse plus haut, d'autres ou elle reste rase, en bruit de Perlin.
	-- Une pelouse d'une seule hauteur se lit comme une moquette ; c'est le RELIEF qui fait la matiere.
	-- Champ de bruit SEPARE de celui des couleurs, et c'est voulu : partage, les zones hautes tomberaient exactement
	-- sur les zones sombres et l'oeil y verrait un motif au lieu d'un terrain.
	-- Calcule UNE fois a la pose, comme les taches : aucun cout en jeu.
	HEIGHT_PATCH_SCALE = 0.03, -- taille des zones. Plus BAS = zones plus LARGES (0.03 = environ 30 studs)
	HEIGHT_PATCH_AMOUNT = 0.35, -- ecart de hauteur maxi, en fraction (0.35 = de 65 % a 135 % de la hauteur)
	-- La taille des touffes COMPENSE la densite : a DENSITY 0.25 elles sont deux fois plus LARGES, donc la surface
	-- reste couverte pareil avec quatre fois moins de parts.
	-- Seuls X et Z grossissent. La HAUTEUR ne bouge jamais : couvrir le sol est horizontal, et une herbe qui grandit
	-- quand on baisse la densite finit par noyer le joueur (vecu).
	-- C'est ce qui rend DENSITY ergonomique : il devient un bouton de PERFORMANCE pur, pas un bouton de "trous dans
	-- l'herbe". On le baisse sur un grand terrain sans que ca se voie a l'ecran.
	-- A DENSITY = 1 le facteur vaut 1 : le rendu actuel ne bouge pas. Mettre a false pour retrouver l'ancien
	-- comportement (touffes de taille fixe, densite qui creuse des trous quand on la baisse).
	AUTO_SCALE_WITH_DENSITY = true,
	-- Fait tourner chaque touffe d'un angle au hasard autour de la verticale.
	-- A false pour la meme raison : quand le mesh porte deja son propre desordre, cette rotation ne casse rien de plus
	-- et donne des touffes qui semblent "posees de travers" au lieu de pousser droit.
	RANDOM_YAW = false,

	-- ===== Emprise des objets poses =====
	-- Une part posee sur la zone (une haie, un objet de construction) CHASSE l'herbe sous elle. Sans ca, des brins
	-- traversent le pied de l'objet et ca se voit immediatement.
	-- Automatique : rien a taguer, rien a declarer. Tout ce qui touche le dessus de la zone compte, SAUF l'herbe
	-- elle-meme, les autres zones, et les personnages (un joueur qui traverse ne doit pas creuser un trou definitif).
	CLEAR_UNDER_PARTS = true,
	-- Degagement AUTOUR de l'emprise, en studs. Ce n'est pas qu'une securite contre les brins qui depassent : une
	-- haie posee sur la pelouse a un PIED, de la terre autour, et de l'herbe qui viendrait coller a sa base la ferait
	-- paraitre plantee au chausse-pied. Un peu d'air autour l'assied dans le decor.
	-- Trop grand laisse en revanche un ANNEAU CHAUVE visible autour de chaque objet, d'autant plus que le sol dessous
	-- est d'un vert uni : c'est ce defaut-la qui borne la valeur, pas le calcul.
	CLEAR_MARGIN = 2.8,
	-- Hauteur au-dessus de la zone dans laquelle on cherche les objets. Au-dela, une part qui vole loin du sol ne doit
	-- pas trouer la pelouse.
	CLEAR_HEIGHT = 14,
	-- Hauteur MINIMALE dont un objet doit DEPASSER du dessus de la zone pour compter.
	-- Sans ce seuil, le SOL lui-meme (la grosse part verte sous la pelouse, dont le dessus affleure la zone) est vu
	-- comme un objet pose, et son emprise couvre toute la zone : plus une seule touffe. Vecu.
	CLEAR_MIN_HEIGHT = 0.5,

	-- ===== Fleurs =====
	-- Des fleurs poussent parmi l'herbe. Ce sont des touffes comme les autres, avec un autre mesh : elles heritent
	-- donc du vent, de l'ecrasement au passage et de tous les tris de performance, sans une ligne de plus.
	-- Elles vivent dans le MEME dossier que GrassMesh.
	-- Retirer un nom d'ici, ou retirer le mesh de Studio, sont deux facons valables d'enlever une fleur : une absence
	-- est un CHOIX, elle ne declenche donc aucun avertissement. Seule une liste entierement introuvable en produit un,
	-- parce que la, c'est le chemin qui est faux.
	FLOWER_NAMES = { "Petal_2", "Petal_5" },
	-- Fraction des cases de la grille qui recoivent une fleur au lieu d'une touffe.
	-- 0.09 = une case sur onze : on est passe de fleurs rares a un semis de petites fleurs sauvages. Ca tient parce
	-- qu'elles sont PETITES ; a cette frequence avec de grosses fleurs, la pelouse disparaitrait dessous.
	-- Les deux reglages vont donc ensemble : plus il y en a, plus elles doivent etre discretes.
	FLOWER_CHANCE = 0.09,
	-- LARGEUR d'une fleur, en STUDS. Pas un multiplicateur de son mesh : on ne sait pas a quelle echelle il a ete
	-- exporte, et un facteur ne dit rien de ce qu'on verra.
	-- La LARGEUR et pas la hauteur, parce que le mesh d'une fleur est PLAT : des petales etales, peu epais. Viser
	-- une hauteur oblige a un facteur enorme, et la largeur explose avec -- des fleurs plus grandes que le joueur.
	-- Repere : un personnage fait environ 2 studs de large, donc a 0.55-1.0 une fleur en fait le quart a la moitie.
	-- Proportions gardees, et pas de compensation de densite : une fleur n'a aucune raison de grossir parce que
	-- l'herbe autour est plus clairsemee.
	FLOWER_WIDTH_MIN = 0.55,
	FLOWER_WIDTH_MAX = 1.0,
	-- HAUTEUR DE TIGE, en fraction de la hauteur de l'HERBE VOISINE. Pas en studs, et c'est le point important :
	-- la hauteur de l'herbe VARIE par zones (HEIGHT_PATCH), donc une elevation fixe fait leviter la fleur la ou
	-- l'herbe est courte et la noie la ou elle est haute. Aucun chiffre absolu ne peut convenir partout.
	-- 0.75 = la corolle se pose aux trois quarts de l'herbe locale : elle emerge sans se detacher du gazon.
	-- Au-dela de 1 elle flotte au-dessus ; en dessous de 0.5 elle disparait dedans.
	FLOWER_LIFT_RATIO = 0.75,

	-- PAS DE REGLAGE DE RENDERFIDELITY ICI : cette propriete est reservee aux plugins, un script normal ne peut pas
	-- l'ecrire ("lacking capability Plugin"). Elle se met A LA MAIN dans Studio, sur le mesh GrassMesh, et les clones
	-- en heritent. Mettre `Precise` (ou `Performance`) plutot que `Automatic` : ce dernier echange le maillage quand
	-- la taille change, ce qui fait CLIGNOTER une touffe qui s'ecrase.

	-- ===== Couleur de l'herbe =====
	-- Teinte au repos. Elle MULTIPLIE la texture du mesh : du blanc pur rend la texture telle quelle, plus la valeur
	-- est basse plus c'est sombre.
	--
	-- DEUX reglages, pas un : la SATURATION est l'ecart vert - bleu, la TEMPERATURE est l'ecart rouge - bleu.
	-- Les confondre coute une iteration, et ca a ete le cas ici :
	--   (66, 94, 30) : ecart vert/bleu de 64. Un vert de peinture, trop sature.
	--   (72, 90, 45) : desature en montant le BLEU... ce qui a rendu l'herbe FROIDE, tirant sur le bleu-vert.
	--   (138, 154, 85) : on remonte le ROUGE bien au-dessus du bleu. Meme desaturation, mais chaude.
	--   (90, 107, 49) : la meme teinte, plus SOMBRE. Elle laisse toute la place au contraste avec l'herbe tondue,
	--     qui est claire (voir MOWN_COLOR) -- c'est cet ecart qui fait voir le travail fait.
	-- Autrement dit : pour desaturer sans refroidir, il faut monter le rouge AUTANT que le bleu.
	--
	-- Les TROIS couleurs d'herbe (repos, tondue, ecrasee) doivent rester coherentes entre elles. N'en changer
	-- qu'une rend les autres bizarres PAR COMPARAISON, et on croit a un bug d'affichage.
	BASE_COLOR = Color3.fromRGB(90, 107, 49),
	-- TACHES. Des zones un peu plus claires et un peu plus sombres, en bruit de Perlin.
	-- Sans elles la pelouse est un aplat parfaitement uniforme, et ca se lit comme du carton peint. Le bruit de
	-- Perlin donne de vraies ZONES ; un tirage au hasard par touffe donnerait du poivre et sel, ce qui est pire que
	-- rien.
	-- Calculees UNE fois a la pose, a partir de la position monde : aucun cout en jeu, et deux touffes voisines
	-- appartiennent bien a la meme tache.
	-- ENFONCEMENT DE TOUTE L'HERBE dans le sol, en fraction de la hauteur de la touffe.
	--
	-- Une touffe est posee par son CENTRE sur la surface de la zone, mais la geometrie du mesh n'occupe pas
	-- forcement toute sa boite : selon la marge laissee sous les brins, elle a l'air de LEVITER.
	-- Proportionnel et pas en studs : cette marge suit la taille du mesh, donc une valeur absolue enterrerait les
	-- petites touffes et laisserait les grandes en l'air.
	-- Monter si l'herbe flotte encore, descendre si les brins sont manges par le sol.
	GROUND_SINK = 0.08,

	PATCH_SCALE = 0.06, -- taille des taches. Plus BAS = taches plus LARGES (0.06 = des zones d'environ 15 studs)
	PATCH_AMOUNT = 0.18, -- ecart de clarte maxi, en fraction. Monter au-dela de 0.3 fait tacheter, pas nuancer.

	-- ===== Rayures de tonte (facon terrain de foot) =====
	-- COUPEES, et c'est un choix de conception, pas un abandon.
	-- Sur un vrai terrain, les bandes claires et sombres ne sont pas peintes : elles viennent du SENS dans lequel la
	-- tondeuse a couche les brins. Les dessiner d'avance donnerait un motif fixe, identique quoi que fasse le joueur,
	-- et qui contredirait sa propre tonte des qu'il coupe en travers.
	-- Elles naissent donc de la TONTE elle-meme : voir le bloc BANDES DE TONTE (MOW_STRIPE_*) plus bas.
	-- Chaque touffe y garde le SENS dans lequel la tondeuse l'a coupee -- une donnee a part de `tiltDir`, qui
	-- suit les PAS du joueur : marcher sur une bande ne doit pas la reecrire.
	-- Remettre a true seulement pour un decor fige, jamais sur une pelouse qui se tond.
	STRIPE_ENABLED = false,
	STRIPE_WIDTH = 9, -- largeur d'une bande, en studs
	-- Orientation des bandes, en degres, DANS LE REPERE DE LA ZONE : tourner la part fait donc tourner les rayures avec.
	-- 0 = bandes le long du petit cote, 45 = diagonales, 90 = bandes le long du grand cote.
	-- Attention en tournant : le nombre de bandes = la longueur de la zone DANS CETTE DIRECTION divisee par STRIPE_WIDTH.
	-- Passer de 0 a 90 sur une zone de 44 x 18 fait tomber 5 bandes a 2 -- il faut alors baisser STRIPE_WIDTH avec.
	STRIPE_HEADING = 90,
	STRIPE_COLOR_A = Color3.fromRGB(143, 172, 97),
	STRIPE_COLOR_B = Color3.fromRGB(106, 140, 54),
	-- OU ecrire la couleur. VERIFIE A L'ECRAN : sur ce mesh, c'est le Color de la MESHPART qui donne la bonne teinte.
	-- Ecrire sur le SurfaceAppearance rendait l'herbe BLEUE, quelles que soient les couleurs demandees -- le TintMask
	-- ne se combine pas comme on l'imagine. Laisser a false. (true = ecrire sur le SurfaceAppearance.)
	STRIPE_ON_SURFACE = false,

	-- Touffes creees par image pendant le semis. Fabriquer 7 000 parts d'un coup gele le client environ 600 ms ; on
	-- etale donc la creation sur plusieurs images. Le joueur voit l'herbe se remplir en une fraction de seconde au
	-- lieu de subir un a-coup.
	CREATE_BUDGET = 500,

	-- Cote d'un PAVE, en studs. Les touffes sont regroupees par paves, et c'est le PAVE qu'on teste, pas la touffe :
	-- un pave hors de vue est ecarte d'un bloc, et un pave loin de tout joueur ne fait meme pas tourner le test
	-- d'ecrasement sur ses touffes. Sans ca, une zone de 1500 touffes les parcourt toutes a chaque image alors qu'au
	-- plus une vingtaine peut etre ecrasee.
	-- Plus petit = tri plus fin (moins de touffes traitees pour rien) mais plus de paves a tester. 6 studs tient les
	-- deux : un pave couvre a peu pres le rayon d'ecrasement.
	BUCKET_SIZE = 6,

	-- ===== Vent =====
	-- Le vent souffle dans UNE direction, et chaque touffe oscille autour d'une inclinaison moyenne. Le decalage de
	-- l'oscillation depend de la POSITION de la touffe le long du vent : ca fabrique des VAGUES qui traversent le
	-- champ. Sans ce decalage, tout le champ respire en bloc, au meme instant, et ca se lit comme du faux.
	WIND_HEADING = 45, -- direction du vent, en degres (0 = vers +X, 90 = vers +Z)
	WIND_ANGLE = 6, -- inclinaison MOYENNE dans le sens du vent, en degres
	WIND_GUST = 5, -- amplitude de l'oscillation autour de cette inclinaison, en degres
	-- Vitesse de l'oscillation de CHAQUE touffe : a quel rythme un brin va et vient sur lui-meme.
	-- A ne pas confondre avec GUST_SPEED, qui est la vitesse a laquelle la VAGUE traverse la pelouse. Une herbe
	-- qui vibre vite sous une vague lente donne du frisson ; l'inverse donne une houle molle. Les deux se reglent
	-- separement, et c'est voulu.
	-- Descendu de 1.7 : ca s'agitait trop pour un jardin par temps calme.
	WIND_SPEED = 1.1,
	WIND_WAVE = 0.09, -- serrage des vagues : plus haut = vagues plus courtes, qui defilent plus visiblement
	-- CHAMP D'ACTION DU VENT, mesure depuis MON PERSONNAGE (pas depuis la camera : elle peut balayer loin ou
	-- dezoomer, alors que "autour de moi" se definit par ou je suis). Hors du champ, l'herbe est STATIQUE : plus un
	-- seul calcul, plus une seule ecriture.
	-- Le vent est a pleine amplitude jusqu'a WIND_FADE_START, puis s'eteint progressivement pour atteindre ZERO pile
	-- a WIND_VIEW_DISTANCE. Ce fondu n'est pas cosmetique : sans lui, une coupure nette dessine un ANNEAU autour du
	-- joueur, ou l'herbe se fige d'un coup quand il avance. Avec, la coupure tombe la ou l'amplitude est deja nulle.
	-- Garder au moins 15 studs d'ecart entre les deux, sinon le fondu redevient visible.
	-- C'EST LE COUPLE A BAISSER si le FPS tombe : on perd du mouvement au loin, jamais de l'herbe.
	-- RAFALES. Un champ de bruit de Perlin (math.noise, integre a Roblox) qui DERIVE dans la direction du vent : des
	-- zones de vent fort et des zones calmes roulent sur le champ, au lieu d'un souffle identique partout. C'est ce
	-- qui fait la difference entre "ca bouge" et "il y a du vent".
	-- L'oscillation rapide (WIND_SPEED / WIND_GUST) reste par-dessus : elle donne le fremissement de chaque touffe,
	-- la rafale donne la respiration large du champ.
	-- EPAISSEUR d'une rafale DANS LE SENS DU VENT. Plus HAUT = lamelles plus FINES (0.09 = environ 11 studs).
	-- C'est ce chiffre qui decide si on voit des vagues qui roulent ou une grosse masse qui respire.
	GUST_SCALE = 0.09,
	-- ETIREMENT en TRAVERS du vent. C'est lui qui transforme des taches rondes en LAMELLES.
	-- Le bruit etait echantillonne a la meme frequence dans les deux directions, donc il ne pouvait produire que
	-- des paquets ronds -- une masse de vent, pas des vagues. On l'ecrase maintenant dans le repere du VENT :
	-- fin le long du souffle, long en travers.
	-- 1 = taches rondes (l'ancien comportement). Plus HAUT = lamelles plus longues et plus franches.
	GUST_STRETCH = 6,
	-- Vitesse a laquelle les rafales traversent le champ, en studs par seconde. C'est la vitesse de la VAGUE, pas
	-- celle des brins (voir WIND_SPEED).
	-- Descendu de 9 : la vague balayait la pelouse plus vite qu'on ne marche dessus, donc on la lisait comme un
	-- balayage d'effet et pas comme du vent.
	GUST_SPEED = 5.5,
	GUST_FLOOR = 0.35, -- force du vent dans les zones les plus calmes (0 = arret complet entre deux rafales)
	-- La rafale TASSE l'herbe en plus de la coucher, et elle remonte quand la rafale passe. Fraction de hauteur perdue
	-- au coeur d'une rafale. Volontairement petite : c'est un appui, pas un pied. 0 = pas de tassement.
	GUST_SQUASH = 0.12,

	-- LA CRETE DE LA VAGUE CHANGE DE COULEUR. Un brin qui se couche ne renvoie pas la lumiere de la meme facon :
	-- c'est CA qui rend le vent visible dans un vrai champ. Le mouvement seul se lit a peine, surtout de loin.
	--
	-- Premiere version : on ECLAIRCISSAIT la teinte de 10 %. Invisible -- sur un vert deja vif, quelques pour cent
	-- de luminosite se noient. Il faut une couleur FRANCHE pour que la vague se detache.
	--
	-- Couleur du HAUT de la vague. Lue via BrickColor pour ne pas recopier des valeurs a la main.
	-- ATTENTION : un nom de BrickColor inconnu retombe SILENCIEUSEMENT sur "Medium stone grey". Si la crete vire au
	-- gris, c'est le NOM qui est faux, pas le reglage.
	GUST_COLOR = BrickColor.new("Shamrock").Color,
	-- Quelle PART de cette couleur au sommet de la vague. 0 = effet coupe, 1 = la crete prend la couleur pleine et
	-- perd la nuance propre de chaque touffe. A REGLER A L'OEIL : c'est le genre d'effet qui passe vite de "vivant"
	-- a "peinture".
	--
	-- HISTORIQUE : 0.55 au depart, et ca se lisait comme de la peinture verte etalee sur la pelouse. Descendu a
	-- 0.22 : la vague se devine au lieu de s'annoncer, ce qui est le but -- du vent, pas un effet.
	GUST_TINT = 0.22,
	-- CONCENTRE l'effet sur la CRETE. La rafale est un champ doux ; applique tel quel, le teintage bave sur toute la
	-- pelouse et se lit comme un aplat, pas comme une vague. On eleve donc la valeur a cette puissance : plus HAUT
	-- = bande plus fine et plus nette, 1 = pas de concentration du tout.
	--
	-- Monte de 2.2 a 3.4 en meme temps qu'on baissait GUST_TINT. Les deux vont ENSEMBLE : baisser la teinte sans
	-- resserrer la crete rend l'effet fade PARTOUT au lieu de le rendre discret. Resserrer concentre le peu qui
	-- reste la ou la vague passe, donc on la voit encore -- mais seulement la.
	GUST_TINT_SHARPNESS = 3.4,
	-- Pas de quantification du teintage. Ecrire une couleur coute, et un pour cent d'ecart ne se voit pas.
	-- Plus GRAND = moins d'ecritures (meilleur FPS) mais la vague avance par marches. 0.02 = 50 niveaux.
	GUST_LIGHT_STEP = 0.02,

	WIND_FADE_START = 10,
	WIND_VIEW_DISTANCE = 26,

	-- ===== Ecrasement =====
	-- Rayon autour du joueur ou l'herbe se couche. Mesure a l'horizontale (X/Z) : sauter ne doit pas relever l'herbe.
	CRUSH_RADIUS = 4.5,
	-- APLATISSEMENT vertical SOUS LE PIED, en fraction de la hauteur.
	--
	-- 0.65 = la touffe descend a 35 % de sa hauteur, puis remonte. Descendu de 0.98, ou elle etait ecrasee au RAS
	-- DU SOL : un pas ne rase pas une pelouse, il la couche. A 2 % de hauteur il ne restait plus rien a voir, et
	-- ca ressemblait davantage a un passage de tondeuse qu'a un pas -- ce qui brouille justement l'information
	-- qu'on veut donner, puisque la tonte a maintenant sa propre hauteur (MOWN_SCALE_Y).
	--
	-- L'herbe DEJA TONDUE, elle, ne s'ecrase plus du tout : voir MOWN_CRUSH_DAMP. Ce reglage ne concerne donc que
	-- l'herbe haute.
	CRUSH_SQUASH = 0.65,
	-- COULEUR DE L'HERBE ECRASEE. La touffe glisse en douceur de BASE_COLOR vers celle-ci quand on marche dessus, et
	-- revient quand elle se releve. Deux couleurs choisies plutot qu'un pourcentage d'assombrissement : on regle ce
	-- qu'on voit, et rien n'empeche de faire une trace plus CLAIRE que l'herbe -- c'est d'ailleurs ce que fait une
	-- vraie pelouse, les brins couches renvoyant plus de lumiere.
	-- Les TACHES de Perlin s'appliquent aussi a cette teinte : la trace garde donc le relief du terrain au lieu de
	-- devenir un aplat uniforme.
	-- Suit le meme ecrasement que l'aplatissement, donc la trace laissee garde sa couleur.
	-- Desaturee en meme temps que BASE_COLOR : c'etait la plus criarde des trois, et laissee vive elle aurait
	-- fait ressortir la trace du joueur comme un trait fluo sur une pelouse devenue calme.
	CRUSHED_COLOR = Color3.fromRGB(184, 205, 147),
	-- Inclinaison au passage. A ZERO : l'herbe s'APLATIT, elle ne penche pas.
	-- Elle valait l'ECART entre l'ecrasement rapide et le tassement lent. Defaut vu a l'ecran : en traversant vite, on
	-- part avant que les deux se soient rejoints, donc l'ecart existe encore PENDANT la remontee -- une inclinaison
	-- surgit et disparait alors que le joueur n'est plus la. Un effet cense raconter le pas se declenchait apres lui.
	-- La remettre au-dessus de zero ramene ce defaut, sauf a faire remonter les deux valeurs a la meme vitesse.
	-- (A ne pas confondre avec l'aplatissement : il ne depend plus de cet angle depuis 0.0.229, le mettre a zero ne
	-- supprime donc plus l'ecrasement.)
	-- Volontairement MODEREE. Le mesh est un RECTANGLE de brins, pas un brin isole : a 78 degres (l'ancienne valeur,
	-- du temps ou l'inclinaison etait le seul effet) la plaque se couchait sur le flanc et se lisait comme un decor
	-- pose de travers. Maintenant que l'aplatissement fait le gros du travail, un angle discret suffit.
	-- Monter au-dela de 45 ramene le defaut.
	CRUSH_TILT_ANGLE = 0,
	-- Vitesses du ressort. Ecraser est BRUTAL (le pied arrive d'un coup), se relever est LENT : c'est cet ecart qui
	-- fait lire le poids. Deux boutons separes expres, un reglage partage forcerait a compenser dans l'autre.
	CRUSH_SPEED = 18,
	-- Vitesse a laquelle l'APLATISSEMENT s'installe, separee de celle de l'inclinaison ci-dessus.
	-- Beaucoup plus basse EXPRES : l'herbe penche d'abord, elle se tasse ensuite. Les deux effets arrivent decales,
	-- donc on les lit l'un APRES l'autre au lieu de les recevoir en bloc -- l'inclinaison a le temps d'exister.
	-- La montee, elle, reste commune (RECOVER_SPEED) : rien ne gagne a ce que la touffe se redresse en deux temps.
	-- Monter cette valeur vers CRUSH_SPEED efface le decalage ; la baisser retarde encore le tassement.
	SQUASH_SPEED = 8,
	-- Vitesse a laquelle la COULEUR redescend une fois le joueur parti. Plus vive que celle du tassement, mais elle
	-- vise la MEME cible : la couleur retombe donc rapidement au niveau de la TRAINEE, puis s'efface avec elle.
	-- Resultat : un point clair sous le pied, un chemin plus discret derriere, et une pelouse qui redevient uniforme
	-- en meme temps qu'elle se redresse.
	-- La monter rapproche le pied du chemin (moins de contraste immediat), la baisser etire le point clair derriere
	-- le joueur comme une comete.
	COLOR_RECOVER_SPEED = 7,
	-- Volontairement LENT : c'est la remontee qu'on regarde. Une herbe qui se redresse doucement derriere le joueur
	-- se voit ; une qui rebondit en un quart de seconde ne se lit pas.
	-- A 3.2, la touffe rejoint le niveau de la trainee en un peu plus d'une demi-seconde.
	RECOVER_SPEED = 3.2,
	-- TRAINEE. Fraction de l'ecrasement que le passage laisse DERRIERE le joueur, une fois qu'il n'est plus dessus.
	--
	-- A ne pas confondre avec CRUSH_SQUASH : celui-la dit a quel point l'herbe se couche SOUS le pied, celui-ci
	-- dit combien elle en garde APRES. Les deux se multiplient, donc baisser l'un allege deja l'autre.
	--
	-- 0.5 = la trainee garde la moitie de l'ecrasement. Descendu de 0.9, ou le chemin restait aussi plaque que
	-- sous les pieds : une pelouse traversee ressemblait a une pelouse tondue.
	-- A 0 elle se redresse entierement ; a 1 elle reste ecrasee a fond.
	FLATTEN_AMOUNT = 0.5,
	-- Vitesse a laquelle la trainee s'efface, en fraction par seconde. 0 = elle ne s'efface JAMAIS.
	-- 0.01 la fait tenir une bonne minute : de quoi voir tout son parcours, meme long. Attention en descendant plus
	-- bas : une pelouse qui n'oublie plus finit entierement pietinee, et l'effet disparait par SATURATION -- si tout
	-- est ecrase, plus rien ne se distingue.
	-- Ce couple (AMOUNT, RECOVER) est ce qui distingue une trainee d'une trace : la premiere s'en va, la seconde
	-- reste. La tonte, elle, voudra une VRAIE trace -- ce sera un autre mecanisme, pas ce reglage-ci.
	-- 0.25 : la trainee tient environ trois secondes et demie. C'est court -- on voit son chemin en se retournant
	-- tout de suite, plus en traversant le jardin. En montant encore, l'effet finit par s'annuler : il ne restera
	-- qu'un halo autour des pieds, sans chemin derriere. A ce moment-la c'est FLATTEN_AMOUNT qu'il faut baisser,
	-- pas cette valeur -- une trainee faible mais lisible vaut mieux qu'une trainee forte qu'on n'a pas le temps
	-- de voir.
	FLATTEN_RECOVER = 0.25,

	-- ===== TONTE =====
	-- La tonte n'est PAS un ecrasement. Une touffe pietinee se releve ; une touffe TONDUE est COUPEE et reste courte
	-- pour toujours. Elle a donc sa propre valeur, qui ne descend JAMAIS -- c'est exactement l'autre mecanisme annonce
	-- juste au-dessus, a FLATTEN_RECOVER.
	-- Les deux se cumulent sans se gener : on garde la plus COURTE des deux raisons. Marcher sur du tondu le couche
	-- encore un peu, et ca se releve ; la coupe, elle, reste dessous.

	-- TAILLE D'UNE TOUFFE ENTIEREMENT TONDUE. DEUX reglages, et il FAUT qu'ils soient separes.
	--
	-- Un seul chiffre pour les trois axes forcait a choisir entre deux defauts :
	--   - le baisser raccourcissait bien l'herbe, mais retrecissait aussi son EMPRISE AU SOL : la pelouse tondue
	--     se clairsemait et on voyait le sol entre les touffes ;
	--   - le laisser a 1 gardait la pelouse pleine, mais l'herbe tondue restait aussi HAUTE que l'herbe brute.
	-- Ces deux grandeurs n'ont rien a voir. Les separer supprime le compromis au lieu de l'arbitrer.
	--
	-- HAUTEUR. C'est ce qui fait qu'une pelouse a l'air tondue. Baisser pour raccourcir.
	--
	-- 0.25 : la valeur du tout debut, retrouvee apres avoir essaye 1, 0.6 et 0.35. On la croyait trop ecrasante --
	-- elle ne l'est pas. A l'ecran, un brin franchement comprime se lit comme de l'herbe RASE, alors qu'un brin
	-- a peine raccourci se lit comme de l'herbe mal coupee.
	--
	-- La lecon vaut au-dela de ce chiffre : la deformation d'un maillage n'est un probleme que si elle SE VOIT en
	-- tant que deformation. Sur des brins d'herbe, tous verticaux, l'ecrasement se lit comme une COUPE. C'est
	-- pour ca qu'on est revenu ici apres avoir cherche ailleurs.
	MOWN_SCALE_Y = 0.25,
	-- EMPRISE AU SOL. A 1, la touffe couvre exactement la meme surface qu'avant la coupe : aucun trou ne peut
	-- apparaitre. C'est la valeur sure, et il n'y a aucune raison d'en bouger sauf a vouloir un gazon clairseme.
	MOWN_SCALE_XZ = 1,

	-- ===== BANDES DE TONTE =====
	-- C'est la promesse tenue du bloc "Rayures de tonte" plus haut : les bandes naissent de la TONTE, elles ne
	-- sont pas dessinees d'avance. Prefixe MOW_ pour ne pas les confondre avec l'ancien systeme, coupe.
	-- Les brins couches dans un sens ne renvoient pas la lumiere comme ceux couches dans l'autre : c'est de la que
	-- viennent les bandes claires et sombres d'une vraie pelouse tondue. Chaque touffe retient le SENS dans lequel
	-- la tondeuse est passee, et s'eclaircit ou s'assombrit selon.
	--
	-- L'AXE S'APPREND DE LA PREMIERE PASSE. Une version precedente le figeait dans la config : les bandes etaient
	-- alors franches en tondant le long de cet axe, et INVISIBLES en tondant perpendiculairement -- les deux sens y
	-- donnaient la meme valeur. Le joueur ne voyait donc rien des qu'il ne tondait pas dans le bon sens.
	-- Comme on tond en ALLER-RETOUR, la premiere passe suffit a definir l'axe : tout le reste s'y aligne ou s'y
	-- oppose, quelle que soit l'orientation du jardin.
	-- BANDES DE TONTE. De combien la couleur de coupe s'ecarte, en plus ou en moins, d'une bande a l'autre.
	--
	-- LES BANDES SONT UN MOTIF DU TERRAIN, PAS LA TRACE DU TRAJET. Elles sont decidees a la POSE d'apres la
	-- position de chaque touffe, et se revelent des qu'on coupe -- quel que soit le sens dans lequel on a roule.
	--
	-- CE QUI A ETE ESSAYE AVANT : faire dependre la bande du SENS de la coupe, avec un axe appris de la premiere
	-- passe. Techniquement ca marchait, mais ca demandait au joueur de rouler droit et regulier pour meriter un
	-- beau resultat -- et il roule comme il veut. Une pelouse doit recompenser le fait d'avoir TOUT coupe, pas la
	-- discipline du trajet.
	--
	-- Leur largeur et leur orientation se reglent avec STRIPE_WIDTH et STRIPE_HEADING, partages avec les rayures
	-- decoratives : c'est le meme damier, revele au lieu d'etre peint.
	--
	-- De combien la bande SOMBRE descend sous MOWN_COLOR. Une seule direction, et c'est voulu : en eclaircissant
	-- aussi, la couleur ecrite en config n'etait celle d'AUCUNE des deux bandes, et on la reglait a l'aveugle.
	-- Ici MOWN_COLOR est la bande claire, et ce chiffre dit ou tombe l'autre.
	--
	-- 0.22 : un ecart faible se perd des que QUOI QUE CE SOIT d'autre teinte la touffe -- le pas du joueur, une
	-- rafale de vent. Une bande doit gagner ces concours-la, sinon elle n'existe que dans le code.
	MOWN_BAND_STRENGTH = 0.22,

	-- Vitesse a laquelle la coupe s'installe sous la tondeuse, en fraction par seconde.
	-- A 8, il faut 0.12 s sur une touffe pour la couper a fond : un passage normal coupe donc entierement.
	-- En BAISSANT, foncer laisse des bandes a moitie tondues qu'il faut repasser. C'est une texture de jeu
	-- interessante (elle punit la precipitation), mais ca se regle A L'OEIL, tondeuse en main. Pas maintenant.
	-- Descendu de 8, mais PAS PLUS BAS. Ce chiffre decide en combien de temps une touffe compte comme coupee : a 5
	-- il faut 0.2 s de contact, ce qu'un passage de tondeuse donne largement. Trop bas, une passe rapide laisserait
	-- des touffes a moitie coupees derriere elle -- et rien n'est plus penible que devoir repasser sur ce qu'on
	-- croit avoir fait.
	-- Pour que l'herbe descende plus DOUCEMENT, c'est CUT_RISE_TIME qu'il faut monter, pas celui-ci.
	MOW_RATE = 5,
	-- LES FLEURS SE FAUCHENT PLUS LENTEMENT QUE L'HERBE, et c'est tout l'interet : a la vitesse de l'herbe
	-- (0.125 s), une fleur disparaitrait d'un coup en passant devant la machine -- ca se lirait comme un bug.
	-- A 2.5, il lui faut 0.4 s sous le carter : le temps de la voir passer DESSOUS et fondre.
	-- En part de coupe par seconde, comme MOW_RATE.
	FLOWER_MOW_RATE = 2.5,
	-- De combien elle RETRECIT avant d'etre detruite, en part de sa taille. Sur les TROIS axes et pas seulement en
	-- hauteur : une fleur seulement aplatie ferait une crepe posee au sol. En la faisant fondre, elle a l'air
	-- avalee par la machine.
	-- 0.9 = il n'en reste qu'un dixieme au moment ou elle disparait, donc on ne voit pas le saut.
	FLOWER_MOW_SHRINK = 0.9,

	-- COULEUR DE L'HERBE TONDUE. Nettement plus CLAIRE que l'herbe haute : c'est ce qui rend le passage visible.
	--
	-- HISTORIQUE, parce que ca a change d'avis et qu'il ne faut pas refaire le tour : une version claire avait ete
	-- essayee puis REJETEE (la pelouse tondue avait l'air ECLAIREE, comme un projecteur pose dessus, au lieu
	-- d'avoir l'air rase), et on etait passe a une teinte quasi identique a l'herbe haute -- donc invisible.
	-- Ce qui a change entre-temps : l'herbe coupee a maintenant son PROPRE MAILLAGE (voir CUT_MESH_NAME). C'est la
	-- FORME qui dit "coupe" desormais, la couleur n'a plus a le faire toute seule -- elle peut donc etre claire
	-- sans que ca se lise comme de la lumiere.
	--
	-- Recoit les MEMES taches de Perlin que le reste : la partie tondue garde donc le relief du terrain au lieu de
	-- virer a l'aplat uniforme. Meme raison que CRUSHED_COLOR.
	--
	-- C'EST LA COULEUR DE LA BANDE CLAIRE, pas une teinte moyenne : les bandes ne font qu'ASSOMBRIR a partir
	-- d'elle (voir MOWN_BAND_STRENGTH). Ce qui est ecrit ici est donc exactement ce qu'on voit sur une bande
	-- claire -- rien ne vient le multiplier par-dessus.
	MOWN_COLOR = Color3.fromRGB(123, 148, 74),

	-- Part du balancement que garde une touffe tondue. Un gazon ras ne doit pas onduler comme de l'herbe haute :
	-- sans ca, la zone tondue continue de vaguer et l'avant/apres se lit beaucoup moins.
	-- 0 = la touffe tondue ne bouge plus du tout, 1 = elle bouge comme avant.
	MOW_WIND = 0.15,

	-- L'HERBE TONDUE NE SE COLORE PRESQUE PLUS QUAND ON MARCHE DESSUS. Fraction de l'effet d'ecrasement RETIREE a
	-- une touffe entierement coupee.
	-- Sans ca, la couleur d'ecrasement (fixe) passait PAR-DESSUS la bande de tonte et la lavait -- et ca arrivait
	-- systematiquement, puisque le joueur marche JUSTE DERRIERE la tondeuse : son rayon d'ecrasement couvre
	-- exactement ce qu'il vient de couper. La bande apparaissait et disparaissait aussitot.
	-- C'est aussi le bon sens : on n'ecrase pas de l'herbe deja rase. La touffe continue de s'APLATIR un peu (c'est
	-- geometrique), elle ne change simplement plus de couleur.
	-- 1 = l'ecrasement ne teinte plus du tout une touffe tondue. 0 = l'ancien comportement.
	-- DE COMBIEN L'HERBE TONDUE S'ECLAIRCIT SOUS LE PIED, en fraction de sa propre couleur.
	--
	-- Elle s'eclaircit A PARTIR DE SA COULEUR, elle ne fond pas vers une teinte fixe. C'est toute la difference :
	-- sa couleur porte deja sa BANDE, donc la bande survit sous le pas au lieu d'etre remplacee.
	--
	-- Il a fallu deux essais pour y arriver. Avec une teinte claire FIXE (celle de l'herbe haute couchee), chaque
	-- pas lavait la bande -- et le joueur marche exactement sur celle qu'il vient de couper. On avait donc coupe
	-- cet effet presque entierement pour sauver les bandes, ce qui rendait l'herbe tondue inerte sous le pied.
	-- Eclaircir au lieu de remplacer permet d'avoir les deux.
	--
	-- 0.18 = 18 % plus clair au maximum de l'ecrasement. Doit rester DISCRET : c'est un retour de pas, pas une
	-- information de jeu.
	MOWN_CRUSH_LIGHTEN = 0.18,
	-- ET L'HERBE TONDUE NE S'ECRASE PLUS DU TOUT SOUS LE PIED. Elle est deja rase : un pied n'a plus rien a y
	-- coucher, et la voir s'aplatir encore contredit ce qu'on vient de faire -- on a coupe, ce n'est pas un
	-- paillasson.
	-- 1 = l'ecrasement (hauteur ET inclinaison) est entierement supprime sur une touffe tondue. 0 = comportement
	-- d'avant. Entre les deux, il s'attenue a mesure que la coupe avance.
	MOWN_CRUSH_DAMP = 1,

	-- ===== REVELATION : voir ce qui RESTE a tondre =====
	-- Une touche maintenue peint en neon tout ce qui n'est PAS encore coupe. Le but est de rendre le PROGRES
	-- lisible : on finit un jardin quand on voit ce qu'il reste, on l'abandonne quand on ne sait plus.
	--
	-- C'est un CONFORT, pas une bequille. Si on la garde appuyee en permanence, ce n'est pas la revelation qu'il
	-- faut ameliorer, c'est le contraste tondu / pas tondu : BAISSER MOWN_SCALE et ecarter MOWN_COLOR de BASE_COLOR.
	--
	-- Le rendu passe par la MEME fonction que le reste (apply). Poser Color et Material a la main sur les touffes
	-- serait efface a l'image suivante : la couleur a deja un ecrivain.
	HIGHLIGHT_COLOR = Color3.fromRGB(16, 191, 255),
	-- CHANGER LE MATERIAU, ou non. A false, la touffe garde le sien et seule sa COULEUR change.
	-- Coupe par defaut : Neon ignore l'eclairage et rend a pleine intensite. Sur une pelouse entiere ca ne se lit
	-- plus comme un surlignage, ca eblouit -- teste, et abandonne pour cette raison.
	-- A remettre a true si un jour la revelation ne concerne qu'une petite surface.
	HIGHLIGHT_MATERIAL_ON = false,
	HIGHLIGHT_MATERIAL = Enum.Material.Neon,
	-- En dessous de cette coupe, la touffe compte comme PAS TONDUE et s'allume. A 0.5, une touffe a moitie coupee
	-- s'allume encore : on voit donc aussi les bandes baclees, pas seulement ce qu'on n'a jamais touche.
	HIGHLIGHT_THRESHOLD = 0.5,
	-- Vitesse du FONDU vers la couleur de revelation, en fraction par seconde. La bascule etait BINAIRE : l'herbe
	-- passait au bleu d'une image a l'autre, ce qui se lit comme un bug d'affichage plutot que comme un mode.
	-- BAS = plus lent. 2.5 met environ une demi-seconde a s'installer.
	HIGHLIGHT_FADE_SPEED = 2.5,
	-- Au-dessus de cette part de fondu, la touffe passe en Neon. Un materiau ne se FOND pas : il change d'un coup.
	-- On le bascule donc TOT, quand la couleur est encore presque normale -- ca se lit comme un allumage, pas comme
	-- un saut. Le fondu de couleur, lui, fait tout le travail de douceur.
	HIGHLIGHT_MATERIAL_AT = 0.02,

	-- En dessous de cet ecart (en fraction d'ecrasement) on CLE la valeur sur sa cible. Un lerp exponentiel n'atteint jamais sa cible :
	-- sans ce clic, chaque touffe garderait un residu minuscule pour toujours, et on reecrirait son CFrame a vie.
	SNAP_EPSILON = 0.001,
}

return GrassZoneConfigs
