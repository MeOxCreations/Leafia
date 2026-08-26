--!strict
-- Reglages du RATEAU. Data pure, zero logique.
--
-- CE QUE FAIT LE RATEAU : il ramasse les petits tas que la taille laisse au sol (poses par HedgeStockService) et
-- les rassemble en GROS tas. Le joueur TIRE A LUI : les petits tas glissent vers ses pieds et fusionnent.
--
-- PARTAGE DES ROLES
--   SERVEUR (RakeService)   : autorite. Il choisit les tas, les deplace, les fusionne. Les tas sont des objets du
--                             monde repliques : seul le serveur peut les toucher, sinon chaque joueur verrait
--                             une pelouse differente.
--   CLIENT (RakeController) : dit "j'ai clique", rien d'autre.
--
-- CE QUI VIENDRA PLUS TARD : prendre un gros tas et le vider dans la Bin. Rien n'est prevu ici pour ca, mais les
-- gros tas sont ranges dans leur PROPRE dossier et portent leur compte en attribut, donc ils seront trouvables.

local RakeConfigs = {
	-- ===== IDENTITE =====
	-- Nom de l'outil dans ToolConfigs. C'est LUI que le serveur compare a ce que le joueur tient.
	TOOL_NAME = "Rake",
	-- Animation du JOUEUR (les bras), jouee une fois par coup de rateau.
	SWEEP_ANIM = "RatissageHumanAnimation",
	-- Animation du MODELE de l'outil, jouee en meme temps. Elle a besoin que le rateau ait un Animator et des
	-- Motor6D dont les Part1 portent les noms des poses (voir le journal du CLAUDE.md).
	TOOL_ANIM = "RatissageAnimation",
	-- Marqueur DANS l'animation du joueur : l'instant ou les dents touchent le sol. C'est LUI qui declenche le
	-- ramassage, jamais un delai -- un delai se decale des qu'on retouche l'animation.
	-- Lu par GetMarkerReachedSignal pendant la lecture (local, aucun appel reseau), et pas par
	-- GetKeyframeSequenceAsync : cet appel-la rate au boot une session sur deux et tue la feature pour toute la
	-- session (deja paye sur la boite aux lettres).
	-- Deux T a "Rattissage" : c'est bien le nom pose dans l'animation, et il ne suit PAS l'orthographe des noms
	-- de pistes (RatissageAnimation, un seul T). Ne pas "corriger" en le lisant.
	SWEEP_EVENT = "RattissageEvent",

	-- ===== CADENCE =====
	-- Deux coups de rateau ne peuvent pas s'enchainer plus vite que ca, en secondes. Borne cote SERVEUR : un
	-- client modifie qui envoie mille clics par seconde ne ratisse pas plus vite.
	-- A caler sur la duree de l'animation : plus court, les gestes se coupent entre eux.
	COOLDOWN = 0.55,

	-- ===== EMPRISE DU COUP =====
	-- Jusqu'ou le rateau attrape, en studs devant le joueur.
	RANGE = 7,
	-- Demi-largeur de la zone attrapee, en studs de part et d'autre de l'axe du regard. Une BANDE et non un
	-- cone : un rateau balaie une largeur constante, il ne s'evase pas avec la distance.
	HALF_WIDTH = 2.6,
	-- Ecart vertical MAXIMAL accepte entre le joueur et un tas. Empeche d'aspirer les tas d'un etage au-dessus
	-- ou d'une terrasse en contrebas, que la mesure a plat ne distingue pas.
	MAX_HEIGHT = 6,
	-- Nombre de petits tas ramasses par coup, au plus. Les plus PROCHES d'abord.
	-- Bas expres : le joueur doit voir le tas grossir coup apres coup. Tout aspirer d'un coup supprime le geste.
	MAX_PER_SWEEP = 4,

	-- ===== LE GLISSEMENT =====
	-- Duree du trajet d'un petit tas vers le gros, en secondes. C'est ca qu'on VOIT : sans ce trajet, les tas
	-- disparaissent et reapparaissent ailleurs, et le geste ne se lit plus.
	PULL_TIME = 0.35,
	-- Hauteur du petit saut pendant le trajet, en studs. Une ligne droite au ras du sol se lit comme un
	-- glissement de bug ; un arc se lit comme des feuilles qu'on ramene.
	PULL_ARC = 0.8,
	-- Rotation du tas pendant son trajet, en tours complets. Il roule vers le gros tas au lieu de glisser a
	-- plat.
	PULL_SPIN = 0.75,

	-- ===== LE GROS TAS =====
	-- Dossier du Workspace ou vivent les gros tas. A PART des petits (HedgeGroundStocks) : ceux-la
	-- appartiennent a leur haie, les gros n'appartiennent plus a rien -- ils partiront a la Bin.
	PILE_FOLDER = "LeafPiles",
	-- Nom donne a un gros tas. Sert a le retrouver (fusion, et plus tard le ramassage vers la Bin).
	PILE_NAME = "BigLeafPile",
	-- Attribut qui retient COMBIEN de petits tas il a avale. C'est lui qui donne la taille, et plus tard ce
	-- qu'il vaut une fois vide dans la Bin.
	PILE_COUNT_ATTRIBUTE = "LeafiaLeafCount",
	-- Distance sous laquelle un coup de rateau REJOINT un gros tas existant au lieu d'en creer un deuxieme.
	-- Sans elle, chaque coup ferait son propre tas et on obtiendrait une trainee, pas un tas.
	MERGE_RADIUS = 5,
	-- Ou le gros tas se forme, en studs DEVANT le joueur. Le joueur tire a lui, donc le tas se pose entre lui et
	-- ce qu'il vient de ratisser. Assez loin pour ne pas se former dans ses jambes.
	GATHER_FORWARD = 2.2,
	-- MARGE gardee au-dela de la bande ou tombent les PETITS tas, en studs.
	--
	-- Le gros tas etait pousse tres loin (au-dela de l'aimant de haie, ~9.5 studs) parce qu'il devenait sinon
	-- inatteignable : s'en approcher accrochait le joueur a la haie. Ce n'est plus un probleme -- l'aimant ne
	-- s'active QUE pour un outil de taille (ToolConfigs.cutsHedge), donc ni le rateau ni les mains vides ne le
	-- declenchent. Le tas peut revenir pres de la haie.
	--
	-- Il reste une raison de le degager, plus modeste : ne pas se former AU MILIEU des petits tas, ou on ne
	-- distinguerait plus ce qui est ramasse de ce qui reste. La bande des petits tas s'arrete a
	-- STOCK_GAP + STOCK_WIDTH de la haie ; RakeService ajoute cette marge par-dessus. Une seule verite, lue dans
	-- HedgeConfigs : si la bande s'elargit, le gros tas recule tout seul.
	HEDGE_CLEARANCE_MARGIN = 1,
	-- Hauteur du tas au-dessus du sol trouve, en studs. Petit : il doit poser dans l'herbe, pas leviter.
	GATHER_LIFT = 0,
	-- ===== TAILLE DU GROS TAS =====
	-- Echelle a un seul petit tas avale, puis gain par tas supplementaire.
	-- La croissance est en RACINE et non lineaire : un tas deux fois plus large parait quatre fois plus gros a
	-- l'ecran (c'est une surface). En lineaire, les premiers coups ne se voient presque pas et les derniers
	-- donnent une montagne.
	SCALE_BASE = 1.1,
	SCALE_PER_PILE = 0.42,
	-- Plafond. Sans lui, une haie retaillee dix fois donne un tas plus grand que la maison.
	SCALE_MAX = 3.2,
	-- Duree du grossissement, en secondes. Cale sur l'arrivee d'un petit tas : il disparait PENDANT que le gros
	-- grossit, donc la matiere a l'air de passer de l'un a l'autre.
	GROW_TIME = 0.25,

	-- ===== SONS =====
	-- Dossier dans SoundService. Vide = aucun son, et aucune erreur.
	SOUND_FOLDER = { "Sounds", "Tools", "Rake" },
	-- Joue a chaque coup de rateau, depuis la position du joueur (donc spatialise pour les autres).
	SWEEP_SOUND = "RakeSweepSound",
}

return RakeConfigs
