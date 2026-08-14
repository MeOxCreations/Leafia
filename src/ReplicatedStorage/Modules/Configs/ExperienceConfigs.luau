--!strict
-- Reglages de la PROGRESSION (XP / niveaux). Data pure, zero logique : la courbe est CALCULEE dans ExperienceService
-- a partir de ces parametres. Partage client + serveur (le client n'a besoin que des noms d'attributs).
--
-- RUNTIME POUR L'INSTANT (demande du joueur) : rien n'est sauvegarde. On valide que gagner de l'XP en taillant est
-- deja satisfaisant AVANT de brancher la persistance (DataTemplate.Skills.Trimming) et l'arbre de competences.

return {
	-- Attributs poses par le serveur sur le joueur, lus par ExperiencesController. Doivent matcher des DEUX cotes :
	-- d'ou ce fichier partage, plutot que deux chaines codees en dur qui finiraient par diverger.
	FILL_ATTRIBUTE = "XpFill", -- fraction 0-1 de progression DANS le niveau courant
	LEVEL_ATTRIBUTE = "XpLevel", -- niveau courant

	-- Gain : XP par CARREAU de haie amene au ras (l'unite de travail REELLE, pas l'intention). A REGLER a l'oeil.
	XP_PER_CELL = 10,

	-- Courbe de niveau. Le COUT par niveau est geometrique : XP pour passer de N a N+1 = LEVEL_BASE * LEVEL_GROWTH^(N-1).
	-- Un cout exponentiel donne un niveau(XP) en LOGARITHME NEPERIEN : niveau ~ 1 + ln(1 + XP / 625) / ln(1.4). Vite au
	-- debut (euphorie du debutant), ralentissement DOUX et continu ensuite, sans mur artificiel.
	-- Traduit en travail reel (carreaux amenes au ras = LEVEL_BASE / XP_PER_CELL * 1.4^(N-1)) :
	--   L1->2 = 25 carreaux, L5->6 = 96, L10->11 = 516, L20->21 = ~15000.
	-- Une premiere haie (~200 carreaux taillables) fait donc monter ~2-3 niveaux, puis chaque niveau se merite.
	-- LEVEL_BASE = cout du 1er niveau : le MONTER durcit le DEBUT. LEVEL_GROWTH = pente : la MONTER durcit le HAUT niveau.
	-- Avant : 100 / 1.3 -> 10 carreaux le 1er niveau, une haie faisait sauter 10-15 niveaux (beaucoup trop facile).
	LEVEL_BASE = 250,
	LEVEL_GROWTH = 1.4,

	-- Au level up, on TIENT la barre pleine ce temps (secondes) avant de la remettre au reste du nouveau niveau :
	-- lecture "pleine -> ca monte d'un cran -> nouvelle barre" au lieu d'un reflux qui ressemble a une perte.
	LEVEL_UP_FLASH = 0.4,
}
