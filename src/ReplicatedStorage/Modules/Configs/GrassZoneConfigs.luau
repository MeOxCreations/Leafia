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
	-- Touffes par stud carre de zone. C'EST LE PREMIER BOUTON A REGLER : trop bas ca fait chauve, trop haut ca coute
	-- des parts pour rien (l'oeil ne voit plus la difference bien avant le processeur).
	DENSITY = 0.5,
	-- Plafond par zone, garde-fou contre une part geante posee par erreur. Si une zone plafonne, on le dit dans la
	-- console : sinon on croirait a une densite mal reglee.
	MAX_CLUMPS = 400,
	-- Taille de chaque touffe, en fraction de la taille du mesh d'origine. Un peu de variete casse l'effet "copie".
	SCALE_MIN = 0.85,
	SCALE_MAX = 1.25,
	-- Inclinaison AU REPOS, en degres. Zero = toutes les touffes parfaitement droites, ce qui se lit comme du faux.
	REST_TILT = 6,

	-- ===== Ecrasement =====
	-- Rayon autour du joueur ou l'herbe se couche. Mesure a l'horizontale (X/Z) : sauter ne doit pas relever l'herbe.
	CRUSH_RADIUS = 4.5,
	-- Inclinaison maxi, en degres, pile sous les pieds. 90 = a plat par terre.
	CRUSH_MAX_ANGLE = 78,
	-- Vitesses du ressort. Ecraser est BRUTAL (le pied arrive d'un coup), se relever est LENT : c'est cet ecart qui
	-- fait lire le poids. Deux boutons separes expres, un reglage partage forcerait a compenser dans l'autre.
	CRUSH_SPEED = 18,
	RECOVER_SPEED = 3.5,
	-- En dessous de cet ecart (radians) on CLE l'angle sur sa cible. Un lerp exponentiel n'atteint jamais sa cible :
	-- sans ce clic, chaque touffe garderait un residu minuscule pour toujours, et on reecrirait son CFrame a vie.
	SNAP_EPSILON = 0.001,
}

return GrassZoneConfigs
