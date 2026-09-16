--!strict
-- LES PASTILLES DES OUTILS POSES SUR LE TERRAIN (seaux, tondeuses, echelles). Data pure, zero logique.

local TaskConfigs = require(script.Parent.TaskConfigs)

return {
	-- L'ICONE DE CHAQUE OUTIL, dans le rond blanc de la pastille. VIDE = le " ! " a la place, et la console le dit
	-- au demarrage.
	ICONS = {
		-- Le meme dessin que la tache "START THE MOWER" : lu dans TaskConfigs, pas recopie.
		Mower = TaskConfigs.ICONS.Mower,
		Bin = "", -- A REMPLIR : "rbxassetid://..." de l'icone du seau
		Ladder = "", -- A REMPLIR : "rbxassetid://..." de l'icone de l'echelle
	} :: { [string]: string },
	-- Hauteur de la pastille au-dessus de la racine de l'outil, en studs. Une par outil : une echelle est bien plus
	-- haute qu'un seau.
	UP = {
		Mower = 4,
		Bin = 3,
		Ladder = 6,
	} :: { [string]: number },
	-- SOUS CETTE DISTANCE, pas de pastille, en studs a plat. De pres l'outil est sous les yeux, et la pastille
	-- recouvrirait l'invite pour le prendre.
	NEAR_DISTANCE = 18,
	-- De combien il faut s'eloigner EN PLUS pour qu'elle revienne, en studs. Sans cette marge, un joueur qui marche
	-- autour de la limite la fait clignoter.
	NEAR_HYSTERESIS = 4,
	-- La liste des outils se relit a ce rythme : elle parcourt tout le Workspace. Un outil qui sort du camion est vu
	-- au tour suivant.
	RESCAN_INTERVAL = 2,
	-- Qui montrer, recalcule a ce rythme.
	CHECK_INTERVAL = 0.2,
}
