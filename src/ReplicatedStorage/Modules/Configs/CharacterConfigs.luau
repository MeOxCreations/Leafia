--!strict
-- Reglages du personnage joueur. Data pure.

local CharacterConfigs = {
	-- Roblox livre 16 par defaut, ce qui est une COURSE, pas une marche. Un paysagiste qui traverse un jardin
	-- en sprintant casse tout le calme du jeu. A regler au ressenti : c'est le genre de valeur qu'on ajuste
	-- trois fois avant de trouver la bonne.
	WALK_SPEED = 10,

	-- Vitesse quand le joueur maintient Shift. Applique cote serveur : le client ne fait que demander.
	SPRINT_SPEED = 17,

	-- Vitesse a laquelle on ACCELERE vers une allure plus rapide, en studs/s gagnes par seconde.
	-- S'appelait LANDING_RECOVERY_RATE du temps ou l'atterrissage coupait les jambes. Ce ralentissement a ete
	-- retire (il rendait le jeu collant : on retombe sans arret dans un jardin), donc plus rien ne "recupere" --
	-- cette rampe ne sert plus qu'a rejoindre une allure imposee par une feature, ou a la quitter.
	SPEED_SPEEDUP_RATE = 14,
	-- Vitesse de RALENTISSEMENT, quand une feature impose une allure plus lente (travail au pied d'une haie).
	-- Plus douce que la reprise : on est aspire vers le travail, on n'y est pas jete.
	SPEED_SLOWDOWN_RATE = 9,

	-- Roblox livre 7.2 par defaut, un saut trop haut pour un jeu au sol comme celui-ci. Un saut plus court
	-- garde le personnage ancre, en accord avec le rythme calme. A regler au ressenti.
	JUMP_HEIGHT = 4.5,

	-- Animation jouee a l'ATTERRISSAGE. Elle ne cle que les jambes et les pieds : le haut du corps (donc la
	-- pose de l'outil) n'est pas touche. Jouee cote serveur pour se repliquer a tout le monde.
	LANDING_ANIMATION_ID = "rbxassetid://123946662556689",
	-- Priorite Action : passe au-dessus de la marche, mais comme elle ne cle que les jambes, elle laisse les
	-- bras a la pose de l'outil (elle aussi en Action, sur d'autres os).
	LANDING_PRIORITY = Enum.AnimationPriority.Action,
	-- Etant en Action, elle ECRASE la marche de Roblox tant qu'elle joue : les jambes restent figees puis la
	-- marche arrive d'un coup. On la coupe donc des que le joueur se remet a avancer.
	-- Fondu court : assez pour que la marche revienne sans saut, assez bref pour qu'on ne sente pas d'attente.
	LANDING_CANCEL_FADE = 0.15,
}

return CharacterConfigs
