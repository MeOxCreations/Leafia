--!strict
-- Reglages du personnage joueur. Data pure.

local CharacterConfigs = {
	-- Roblox livre 16 par defaut, ce qui est une COURSE, pas une marche. Un paysagiste qui traverse un jardin
	-- en sprintant casse tout le calme du jeu. A regler au ressenti : c'est le genre de valeur qu'on ajuste
	-- trois fois avant de trouver la bonne.
	WALK_SPEED = 10,

	-- Vitesse quand le joueur maintient Shift. Applique cote serveur : le client ne fait que demander.
	SPRINT_SPEED = 17,

	-- Roblox livre 7.2 par defaut, un saut trop haut pour un jeu au sol comme celui-ci. Un saut plus court
	-- garde le personnage ancre, en accord avec le rythme calme. A regler au ressenti.
	JUMP_HEIGHT = 4.5,

	-- Animation jouee a l'ATTERRISSAGE. Elle ne cle que les jambes et les pieds : le haut du corps (donc la
	-- pose de l'outil) n'est pas touche. Jouee cote serveur pour se repliquer a tout le monde.
	LANDING_ANIMATION_ID = "rbxassetid://123946662556689",
	-- Priorite Action : passe au-dessus de la marche, mais comme elle ne cle que les jambes, elle laisse les
	-- bras a la pose de l'outil (elle aussi en Action, sur d'autres os).
	LANDING_PRIORITY = Enum.AnimationPriority.Action,
}

return CharacterConfigs
