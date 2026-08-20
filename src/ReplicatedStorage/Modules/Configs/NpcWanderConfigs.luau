--!strict
-- PNJ QUI SE PROMENENT. Un modele pose dans la map se balade tout seul dans une zone, en contournant les obstacles.
--
-- Le calcul du chemin est confie a PathfindingService (Roblox) : il connait deja la maison, les arbres et les haies.
-- Ecrire un pathfinding maison couterait des jours pour un resultat moins bon.
-- Ce qui donne l'impression de VIE n'est pas le calcul du chemin mais ce qu'on met par-dessus : des pauses, une
-- vitesse qui varie, des arrets sans raison. C'est la que sont les reglages ci-dessous.

export type Npc = {
	model: string, -- nom du Model dans le Workspace
	zone: string, -- nom de la Part qui borne la balade (marqueur : elle doit etre SANS collision)
	idle: string, -- animation jouee a l'arret
	walk: string, -- animation jouee en marchant
	speed: number, -- vitesse de marche de reference, en studs par seconde
}

local NPCS: { Npc } = {
	{
		model = "OldManIdle",
		zone = "ZoneWalking",
		idle = "rbxassetid://136244394563436",
		walk = "rbxassetid://101745125575203",
		speed = 3,
	},
}

local NpcWanderConfigs = {
	NPCS = NPCS,

	-- ===== Ce qui rend la balade vivante =====
	-- Temps d'arret entre deux trajets, tire au hasard dans cet intervalle. C'est le reglage le plus important du
	-- lot : un PNJ qui repart aussitot arrive a l'air d'un robot en patrouille.
	PAUSE_MIN = 2.5,
	PAUSE_MAX = 9,
	-- Ecart de vitesse d'un trajet a l'autre, en fraction. 0.2 = entre 0.8x et 1.2x la vitesse de reference.
	-- Toujours la meme vitesse est une des choses qui trahissent le plus une machine.
	SPEED_VARIATION = 0.2,
	-- Distance MINIMALE entre le point d'arrivee et le point de depart. Sans elle, un tirage au hasard tombe parfois
	-- a deux pas et le PNJ fait des micro-deplacements qui n'ont l'air de rien.
	MIN_TRAVEL = 12,
	-- Nombre de tirages tentes pour trouver un point atteignable avant de laisser tomber ce tour.
	TARGET_TRIES = 6,

	-- ===== Animation de marche accordee a la vitesse =====
	-- Vitesse a laquelle l'animation de marche est JUSTE a sa cadence d'origine. En dessous elle est ralentie, au
	-- dessus acceleree, proportionnellement. Sans ca, un PNJ qui ralentit garde une cadence de pas trop rapide et
	-- semble PATINER -- l'oeil le voit tout de suite, meme sans savoir le nommer.
	-- A regler a l'oeil : si les pieds glissent en avant, BAISSER ; s'ils pietinent, MONTER.
	WALK_ANIM_REFERENCE = 3.5,
	-- Vitesse a laquelle la cadence rejoint sa cible. La cadence suit la vitesse REELLE, pas la vitesse demandee :
	-- au demarrage et a l'arret, elle monte et redescend progressivement au lieu de claquer.
	WALK_ANIM_SMOOTH = 6,
	-- Bornes de la cadence, pour qu'un a-coup de physique ne fasse jamais partir l'animation en vrille.
	WALK_ANIM_MIN = 0.35,
	WALK_ANIM_MAX = 2,

	-- ===== Reglages techniques =====
	-- Gabarit du personnage, pour que le chemin calcule tienne compte de sa largeur : trop petit et il rase les murs,
	-- trop grand et il se croit coince dans les passages etroits.
	AGENT_RADIUS = 2,
	AGENT_HEIGHT = 5,
	-- Delai TOTAL pour trouver un modele ou sa zone au demarrage (un seul delai pour tout, pas un par element).
	RESOLVE_TIMEOUT = 20,
	-- Hauteur de depart du rayon qui cherche le sol sous un point tire au hasard, et sa portee vers le bas.
	GROUND_ABOVE = 20,
	GROUND_BELOW = 60,
}

return NpcWanderConfigs
