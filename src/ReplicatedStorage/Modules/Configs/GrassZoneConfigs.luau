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
	BASE_COLOR = Color3.fromRGB(66, 94, 30),
	-- TACHES. Des zones un peu plus claires et un peu plus sombres, en bruit de Perlin.
	-- Sans elles la pelouse est un aplat parfaitement uniforme, et ca se lit comme du carton peint. Le bruit de
	-- Perlin donne de vraies ZONES ; un tirage au hasard par touffe donnerait du poivre et sel, ce qui est pire que
	-- rien.
	-- Calculees UNE fois a la pose, a partir de la position monde : aucun cout en jeu, et deux touffes voisines
	-- appartiennent bien a la meme tache.
	PATCH_SCALE = 0.06, -- taille des taches. Plus BAS = taches plus LARGES (0.06 = des zones d'environ 15 studs)
	PATCH_AMOUNT = 0.18, -- ecart de clarte maxi, en fraction. Monter au-dela de 0.3 fait tacheter, pas nuancer.

	-- ===== Rayures de tonte (facon terrain de foot) =====
	-- COUPEES, et c'est un choix de conception, pas un abandon.
	-- Sur un vrai terrain, les bandes claires et sombres ne sont pas peintes : elles viennent du SENS dans lequel la
	-- tondeuse a couche les brins. Les dessiner d'avance donnerait un motif fixe, identique quoi que fasse le joueur,
	-- et qui contredirait sa propre tonte des qu'il coupe en travers.
	-- Elles naitront donc de la TONTE elle-meme. La donnee necessaire existe deja : chaque touffe garde `tiltDir`, la
	-- direction de son dernier passage.
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
	WIND_SPEED = 1.7, -- vitesse de l'oscillation
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
	GUST_SCALE = 0.035, -- taille des rafales. Plus BAS = rafales plus LARGES (0.035 = des zones d'environ 30 studs)
	GUST_SPEED = 9, -- vitesse a laquelle les rafales traversent le champ, en studs par seconde
	GUST_FLOOR = 0.35, -- force du vent dans les zones les plus calmes (0 = arret complet entre deux rafales)
	-- La rafale TASSE l'herbe en plus de la coucher, et elle remonte quand la rafale passe. Fraction de hauteur perdue
	-- au coeur d'une rafale. Volontairement petite : c'est un appui, pas un pied. 0 = pas de tassement.
	GUST_SQUASH = 0.12,

	WIND_FADE_START = 10,
	WIND_VIEW_DISTANCE = 26,

	-- ===== Ecrasement =====
	-- Rayon autour du joueur ou l'herbe se couche. Mesure a l'horizontale (X/Z) : sauter ne doit pas relever l'herbe.
	CRUSH_RADIUS = 4.5,
	-- APLATISSEMENT vertical au maximum de l'ecrasement, en fraction de la hauteur.
	-- 0.98 = la touffe descend a 2 % de sa hauteur sous le pied, puis remonte. C'EST L'EFFET PRINCIPAL.
	-- Ecrasee au ras du sol. La limite est 1.0, ou elle disparaitrait tout a fait : au-dela de 0.98 il ne reste
	-- quasiment plus rien a voir, et l'effet se perd faute de matiere.
	CRUSH_SQUASH = 0.98,
	-- COULEUR DE L'HERBE ECRASEE. La touffe glisse en douceur de BASE_COLOR vers celle-ci quand on marche dessus, et
	-- revient quand elle se releve. Deux couleurs choisies plutot qu'un pourcentage d'assombrissement : on regle ce
	-- qu'on voit, et rien n'empeche de faire une trace plus CLAIRE que l'herbe -- c'est d'ailleurs ce que fait une
	-- vraie pelouse, les brins couches renvoyant plus de lumiere.
	-- Les TACHES de Perlin s'appliquent aussi a cette teinte : la trace garde donc le relief du terrain au lieu de
	-- devenir un aplat uniforme.
	-- Suit le meme ecrasement que l'aplatissement, donc la trace laissee garde sa couleur.
	CRUSHED_COLOR = Color3.fromRGB(186, 219, 128),
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
	-- TRAINEE. Fraction de l'ecrasement que le passage laisse derriere le joueur, une fois qu'il n'est plus dessus.
	-- 0.9 = l'herbe reste presque plaquee au sol derriere le joueur. Le chemin est aussi visible que sous ses pieds,
	-- il ne s'en distingue que par la couleur, qui, elle, revient tout de suite.
	-- A 0 elle se redresse entierement ; a 1 elle reste ecrasee a fond.
	FLATTEN_AMOUNT = 0.9,
	-- Vitesse a laquelle la trainee s'efface, en fraction par seconde. 0 = elle ne s'efface JAMAIS.
	-- 0.01 la fait tenir une bonne minute : de quoi voir tout son parcours, meme long. Attention en descendant plus
	-- bas : une pelouse qui n'oublie plus finit entierement pietinee, et l'effet disparait par SATURATION -- si tout
	-- est ecrase, plus rien ne se distingue.
	-- Ce couple (AMOUNT, RECOVER) est ce qui distingue une trainee d'une trace : la premiere s'en va, la seconde
	-- reste. La tonte, elle, voudra une VRAIE trace -- ce sera un autre mecanisme, pas ce reglage-ci.
	FLATTEN_RECOVER = 0.06,

	-- En dessous de cet ecart (en fraction d'ecrasement) on CLE la valeur sur sa cible. Un lerp exponentiel n'atteint jamais sa cible :
	-- sans ce clic, chaque touffe garderait un residu minuscule pour toujours, et on reecrirait son CFrame a vie.
	SNAP_EPSILON = 0.001,
}

return GrassZoneConfigs
