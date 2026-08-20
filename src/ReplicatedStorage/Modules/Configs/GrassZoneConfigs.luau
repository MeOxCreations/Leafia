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
	DENSITY = 1.0,
	-- Deplacement au hasard de chaque touffe DANS sa case, en fraction de la case. 0 = damier parfaitement regulier,
	-- 1 = la touffe peut aller jusqu'au bord de sa case.
	JITTER = 0.8,
	-- GARDE-FOU, pas un bouton de densite. La densite, c'est DENSITY, et elle est la meme partout : le nombre de
	-- touffes suit donc la surface de la zone, une grande zone en recoit proportionnellement plus.
	-- Ce plafond n'existe que pour qu'une part posee par erreur a 500x500 ne fabrique pas 250 000 instances. Le laisser
	-- trop bas RABOTE la densite des grandes zones (l'herbe devient clairsemee a mesure qu'on agrandit), ce qui est
	-- exactement l'inverse de ce qu'on veut. Au plafond on ESPACE la grille plutot que de couper la liste : couper
	-- laisserait une moitie de zone chauve.
	MAX_CLUMPS = 1500,
	-- Taille de chaque touffe, en fraction de la taille du mesh d'origine. Un peu de variete casse l'effet "copie".
	SCALE_MIN = 0.85,
	SCALE_MAX = 1.25,
	-- Inclinaison AU REPOS, en degres. Zero = toutes les touffes parfaitement droites, ce qui se lit comme du faux.
	REST_TILT = 6,

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
	WIND_FADE_START = 25,
	WIND_VIEW_DISTANCE = 40,

	-- ===== Ecrasement =====
	-- Rayon autour du joueur ou l'herbe se couche. Mesure a l'horizontale (X/Z) : sauter ne doit pas relever l'herbe.
	CRUSH_RADIUS = 4.5,
	-- Inclinaison maxi, en degres, pile sous les pieds. 90 = a plat par terre.
	CRUSH_MAX_ANGLE = 78,
	-- APLATISSEMENT vertical au maximum de l'ecrasement, en fraction de la hauteur. 0.45 = la touffe descend a 55 % de
	-- sa hauteur sous le pied, puis remonte. 0 = elle se couche sans s'ecraser.
	-- Pilote par le MEME angle d'ecrasement que la bascule : les deux ne peuvent donc pas se desynchroniser, et
	-- l'aplatissement herite gratuitement du ressort (brutal a la descente, lent a la remontee).
	CRUSH_SQUASH = 0.45,
	-- Vitesses du ressort. Ecraser est BRUTAL (le pied arrive d'un coup), se relever est LENT : c'est cet ecart qui
	-- fait lire le poids. Deux boutons separes expres, un reglage partage forcerait a compenser dans l'autre.
	CRUSH_SPEED = 18,
	RECOVER_SPEED = 3.5,
	-- En dessous de cet ecart (radians) on CLE l'angle sur sa cible. Un lerp exponentiel n'atteint jamais sa cible :
	-- sans ce clic, chaque touffe garderait un residu minuscule pour toujours, et on reecrirait son CFrame a vie.
	SNAP_EPSILON = 0.001,
}

return GrassZoneConfigs
