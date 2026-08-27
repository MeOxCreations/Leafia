--!strict
-- LE CAMION. Reglages du prompt d'ouverture et de sa porte arriere.

local TruckConfigs = {
	-- LE NOM DU MODELE DANS LE WORKSPACE, pas une etiquette libre. Le renommer dans Studio sans le changer ici
	-- coupe le prompt EN SILENCE : plus rien ne le trouve. C'est aussi la cle de son animation d'ambiance, dans
	-- AmbientAnimConfigs -- deux endroits a changer ensemble.
	MODEL_NAME = "Truck",
	-- La part qui porte le prompt. UNE PART PRECISE et pas le modele entier : sinon l'invite s'affiche des qu'on
	-- longe la carrosserie, y compris a l'avant ou l'action n'a aucun sens.
	DOOR_PART = "DoorBack",

	-- ===== LE PROMPT =====
	-- Le client le reconnait par ce nom pour dessiner notre pilule a la place de l'interface Roblox par defaut.
	PROMPT_NAME = "TruckPrompt",
	-- EN ANGLAIS, comme tout texte vu par le joueur : le traducteur de Roblox part de l'anglais.
	PROMPT_ACTION = "OPEN",
	PROMPT_OBJECT = "TRUCK",
	-- Distance d'activation, en studs. Genereuse : on s'approche du camion avec une tondeuse devant soi.
	PROMPT_DISTANCE = 12,
	-- Hauteur de la pilule au-dessus de la porte, et son decalage lateral. Le decalage evite qu'elle tombe SUR le
	-- personnage quand on est pile derriere le camion.
	PROMPT_HEIGHT = 3,
	PROMPT_SIDE = 2.5,

	-- ===== LA PORTE =====
	-- Chemin de l'animation sous ReplicatedStorage.Animations.
	DOOR_ANIM_PATH = { "General", "TruckOpenDoorAnimation" },
	-- Elle n'a rien a partager : le camion ne joue que son idle d'ambiance, en priorite `Idle`. `Action` passe
	-- au-dessus sans discussion.
	DOOR_PRIORITY = Enum.AnimationPriority.Action,
	-- Vitesses d'ouverture et de fermeture, en multiple du rythme de l'editeur.
	--
	-- DEUX VALEURS et pas une : ouvrir est un geste qu'on regarde, refermer est une formalite. Un seul reglage
	-- forcerait a choisir entre une ouverture qui claque et une fermeture qui traine.
	DOOR_OPEN_SPEED = 1,
	DOOR_CLOSE_SPEED = 1.6,
	-- Les sons de la porte, sous SoundService. UN PAR SENS : ouvrir et refermer ne font pas le meme bruit, et le
	-- meme son dans les deux sens s'entend comme un enregistrement rejoue.
	--
	-- Joues A L'APPUI, pas a la fin du mouvement : c'est le geste du joueur qu'ils accompagnent.
	--
	-- SPATIAUX, poses sur la porte -- contrairement aux sons de la scene du tuto, qui sont mixes en 2D. Ici on
	-- n'est pas dans un plan de cinema : c'est un objet du monde, il doit s'entendre depuis la ou il est, et
	-- moins fort quand on s'en eloigne.
	DOOR_OPEN_SOUND = { "Sounds", "Game", "GlobalSounds", "OpenDoorTruckSound" },
	DOOR_CLOSE_SOUND = { "Sounds", "Game", "GlobalSounds", "CloseDoorTruckSound" },
	-- RETARD DU SON DE FERMETURE, en secondes. Le bruit d'une porte qui claque arrive quand elle TOUCHE, pas quand
	-- on la pousse : joue a l'appui, il precedait l'image de la porte encore grande ouverte.
	--
	-- Le son d'ouverture, lui, n'a PAS de retard : il accompagne le geste, qui commence tout de suite. Deux
	-- moments differents, deux reglages -- un seul aurait force a decaler les deux.
	DOOR_CLOSE_SOUND_DELAY = 0.5,

	-- ===== RECHERCHE =====
	-- Avec StreamingEnabled le camion peut arriver bien apres le demarrage. On le re-cherche jusqu'a le trouver,
	-- puis on abandonne en le disant : "absent au demarrage" est un etat NORMAL, "absent pour toujours" ne l'est
	-- pas.
	FIND_INTERVAL = 2,
	FIND_TIMEOUT = 60,
}

return TruckConfigs
