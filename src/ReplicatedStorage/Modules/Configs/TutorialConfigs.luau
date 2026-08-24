--!strict
-- Reglages du DIDACTICIEL. Data pure, zero logique.
--
-- Le didacticiel a deux moities : TutorialService (serveur) place le joueur, TutorialController (client) le
-- GUIDE. Cette config sert aux deux.

return {
	-- ===== LE HALO DE LA PORTE =====
	-- Premiere chose que le joueur doit comprendre en arrivant : ou aller. On le lui MONTRE au lieu de le lui
	-- ecrire -- un halo qui respire se lit sans lire, et il ne demande aucune traduction.
	--
	-- Le Highlight est POSE DANS STUDIO, pas cree en code. C'est la ou se reglent sa couleur de contour et son
	-- mode d'affichage, a l'oeil. Le code n'y touche QU'A UNE propriete : FillTransparency. Tout le reste --
	-- OutlineColor, OutlineTransparency, DepthMode -- reste exactement ce qui a ete choisi dans l'editeur.
	DOOR_NAME = "Door",
	HIGHLIGHT_NAME = "Highlight",

	-- Chemin normal de la porte. Essaye EN PREMIER parce qu'il coute trois FindFirstChild, la ou un balayage du
	-- Workspace parcourt des milliers d'instances. Si la maison est rangee ailleurs un jour, le balayage de
	-- secours la retrouve quand meme : le chemin est une optimisation, pas une obligation.
	DOOR_PATH = { "Worlds", "Maps", "Assets", "House" },

	-- Le halo RESPIRE entre ces deux transparences de remplissage. 1 = invisible, 0 = plein.
	FILL_MIN = 0.5,
	FILL_MAX = 1,
	-- Duree d'un aller-retour COMPLET (invisible -> visible -> invisible), en secondes. Un battement lent se lit
	-- comme "viens par ici" ; rapide, il se lit comme une alerte. Ne pas descendre sous ~0.8 s.
	PULSE_PERIOD = 1.6,

	-- ===== LE PROMPT DE LA PORTE =====
	-- Distance HORIZONTALE (studs) sous laquelle le prompt apparait. RADIALE, jamais une box : colle a un bout
	-- de la porte on tomberait HORS d'une box laterale, et l'agrandir ne bouche pas le trou -- elle reste au
	-- mauvais endroit. Un seul nombre, aucun angle mort, independant de l'orientation.
	--
	-- Mesuree depuis la PrimaryPart de la porte, jamais depuis GetPivot : le pivot d'un Model suit sa bounding
	-- box, donc ajouter la moindre part enfant le decale sans prevenir.
	PROMPT_RADIUS = 10,
	-- On ne teste pas la proximite a chaque image : ca ne se voit pas et ca coute.
	PROMPT_INTERVAL = 0.15,
	PROMPT_KEY = "E",
	-- ANGLAIS, comme tout texte vu par le joueur : le traducteur de Roblox part de l'anglais, un texte francais
	-- n'est traduit nulle part et le jeu devient illisible pour presque toute la plateforme.
	PROMPT_LABEL = "KNOCK",
	PROMPT_TITLE = "GRANDPA",
	-- Hauteur d'AFFICHAGE du badge au-dessus de la porte. Sans rapport avec PROMPT_RADIUS, qui est la distance a
	-- laquelle il apparait : deux reglages differents, ne pas confondre.
	PROMPT_OFFSET = Vector3.new(0, 3, 0),
	-- ContextActionService : createTouchButton fait apparaitre un bouton a l'ecran UNIQUEMENT sur tactile ET
	-- bind la touche sur PC, d'un seul geste. Sans lui, le didacticiel serait infranchissable sans clavier --
	-- donc pour la moitie des joueurs Roblox.
	--
	-- CONFLIT CONNU : E est aussi la touche du seau, de la tondeuse et de l'echelle. Chacun ne branche la sienne
	-- que quand elle a un sens, mais un seau pose devant la porte repondrait en meme temps qu'elle.
	ACTION_NAME = "LeafiaTutorialKnock",
	ACTION_KEY = Enum.KeyCode.E,

	-- Avec StreamingEnabled la porte peut arriver BIEN apres le spawn : on la re-cherche tant qu'on ne l'a pas.
	RESCAN_INTERVAL = 2,
	-- Toujours rien apres ce delai : on le DIT. Un halo qui ne s'allume jamais ne produit aucune erreur, et sans
	-- ce message on chercherait le bug dans l'animation du halo au lieu du nom de la porte.
	NOT_FOUND_WARN_AFTER = 12,
}
