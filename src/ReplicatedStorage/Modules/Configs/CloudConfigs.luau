--!strict
-- NUAGES. Un troupeau de nuages qui traversent le ciel, en boucle et sans fin.
--
-- Le principe : les nuages derivent en coordonnees MONDE (donc ils ne collent pas au joueur, on garde la parallaxe),
-- et des que l'un s'eloigne trop, il est REMIS en amont du vent. Comme il devient transparent bien avant d'atteindre
-- cette limite, le recyclage ne se voit jamais.
--
-- 100 % CLIENT : c'est du ciel, ca ne change aucune regle du jeu. Rien ne transite.

local CloudConfigs = {
	-- Le mesh a dupliquer, sous ReplicatedStorage.
	MESH_PATH = { "Assets", "Contents", "CloudMesh" },

	-- Nombre de nuages en vol. Le cout est d'un CFrame et d'une transparence par nuage et par image : on peut monter
	-- sans crainte, c'est le RENDU d'un gros mesh translucide qui coutera avant le calcul.
	COUNT = 28,

	-- ===== Ou ils volent =====
	-- Altitude, en studs. PREMIER BOUTON A REGLER : ca depend entierement de l'echelle de ta carte.
	ALTITUDE = 250,
	-- Ecart d'altitude entre nuages : sans lui, ils forment une nappe plate et ca se voit.
	ALTITUDE_SPREAD = 70,
	-- Rayon du ciel occupe autour du joueur. Au-dela, un nuage est recycle en amont du vent.
	-- Plus grand = on voit plus loin, mais il faut plus de nuages pour que le ciel ne paraisse pas vide.
	FIELD_RADIUS = 900,

	-- ===== Comment ils bougent =====
	HEADING = 45, -- direction du vent, en degres (0 = vers +X, 90 = vers +Z)
	SPEED = 14, -- vitesse de derive, en studs par seconde
	SPEED_VARIATION = 0.35, -- ecart de vitesse entre nuages : sans lui le ciel derive d'un bloc, comme une image

	-- ===== A quoi ils ressemblent =====
	SCALE_MIN = 0.7,
	SCALE_MAX = 1.9,
	-- Transparence au plus PRES : jamais tout a fait opaque, un nuage dur a l'air d'un bloc.
	NEAR_TRANSPARENCY = 0.15,
	-- A partir de quelle fraction du rayon le nuage commence a disparaitre. En dessous il est a NEAR_TRANSPARENCY,
	-- au bord du rayon il est invisible.
	-- C'EST CE FONDU QUI CACHE LE RECYCLAGE : le baisser trop (nuages nets jusqu'au bord) ferait apparaitre et
	-- disparaitre les nuages d'un coup.
	FADE_START = 0.5,

	-- Delai TOTAL pour trouver le mesh au demarrage (un seul delai pour tout le chemin, pas un par segment).
	RESOLVE_TIMEOUT = 15,
}

return CloudConfigs
