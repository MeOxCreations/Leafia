--!strict
-- Template des donnees d'un joueur : les valeurs par defaut d'un NOUVEAU profil, et LA structure de reference de
-- tout ce qui se sauvegarde. C'est le SEUL endroit ou on declare des champs sauvegardes. profile:Reconcile()
-- (DataService) ajoute les champs nouveaux ici aux profils EXISTANTS sans ecraser le reste : on etoffe a tout moment.
--
-- SERVER-ONLY (ServerStorage) : la structure des donnees ne regarde pas le client, il recoit via des remotes.
--
-- RAPPEL SERIALISATION : un DataStore ne garde que du PLAT (nombres, textes, booleens, tables de ces types). PAS
-- d'Instance, PAS de Vector3/CFrame/Color3. D'ou les builds stockes en RECETTES (id + x/y/z/ry), reconstruits au join.
--
-- Chaque champ ici est juste le SCHEMA : le systeme derriere (economie, build, reputation...) se code quand on
-- l'attaque, et selon la regle d'or, quand le geste de tailler est valide.

return {
	-- ===== META (plomberie) =====
	Sessions = 0, -- +1 a chaque join : preuve que save/load marche
	FirstJoin = 0, -- os.time du tout premier join, pose une seule fois
	-- Nombre de fois ou le joueur a VENDU son entreprise et reparti (le "rebirth" facon Leafia). Voir Company.
	Rebirths = 0,

	-- ===== ECONOMIE =====
	Coins = 0, -- monnaie principale (CurrencyUI)

	-- ===== PROGRESSION (style Sims : de l'XP par ACTION / competence) =====
	-- Une entree par competence. On commence par la taille ; on ajoute les autres metiers/actions ensuite. Le niveau
	-- peut aussi se DERIVER de l'XP a la lecture (une courbe dans un Config) au lieu d'etre stocke : a trancher quand
	-- on code la progression. Pour l'instant on garde les deux, c'est plus simple.
	Skills = {
		Trimming = { Xp = 0, Level = 1 }, -- tailler les haies (la jauge de ExperiencesUI)
	},

	-- ===== REPUTATION de l'entreprise =====
	Reputation = 0, -- renommee de l'entreprise du joueur : attire plus ou moins de clients / de valeur

	-- ===== ENTREPRISE (le BUILD du joueur, mur par mur) =====
	Company = {
		Name = "", -- nom de l'entreprise, choisi par le joueur
		-- Liste de RECETTES serialisees (QUE du plat). Le futur PlacementService les reconstruit au join :
		-- pour chaque recette, clone le template de build (par son id) et le PivotTo a la position.
		-- Exemple : { { id = "mur_droit", x = 4.5, y = 0, z = -2, ry = 90 }, ... }
		Builds = {},
		-- Notoriete accumulee du batiment (ce qui fait qu'un autre joueur voudra RACHETER l'entreprise). A definir
		-- quand on code la vente entre joueurs (gros systeme a part : valuation + transfert de donnees cross-joueur).
		Notoriety = 0,
	},

	-- ===== PREMIUM / PASS =====
	-- Les GAMEPASSES ne se stockent PAS ici : on les verifie EN DIRECT (MarketplaceService:UserOwnsGamePassAsync)
	-- pour qu'un achat compte tout de suite. On ne garde que ce qui est propre a Leafia (abonnement custom, etc.).
	Premium = {
		Vip = false, -- exemple de statut/abonnement custom
	},

	-- ===== SETTINGS (interface) =====
	Settings = {
		Music = true, -- musique on/off
		Sfx = true, -- effets sonores on/off
		-- keybinds, options d'affichage, etc. a venir
	},
}
