--!strict
-- Reglages du personnage joueur. Data pure.

local CharacterConfigs = {
	-- Roblox livre 16 par defaut, ce qui est une COURSE, pas une marche. Un paysagiste qui traverse un jardin
	-- en sprintant casse tout le calme du jeu. A regler au ressenti : c'est le genre de valeur qu'on ajuste
	-- trois fois avant de trouver la bonne.
	WALK_SPEED = 10,

	-- Hauteur de saut par defaut de Roblox. On la garde telle quelle pour l'instant : rien dans le jeu ne
	-- demande de sauter, donc rien ne justifie d'y toucher.
	JUMP_HEIGHT = 7.2,
}

return CharacterConfigs
