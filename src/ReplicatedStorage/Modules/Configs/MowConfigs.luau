--!strict
-- Reglages de la TONTE (pelouse tondable). Data pure, zero logique. Partage client + serveur : le client lit les noms
-- d'attributs et le rendu du brin, le serveur genere / coupe.
--
-- MEME ARCHITECTURE QUE LES HAIES, mais a plat : une pelouse = une part taguee, pavee d'une grille de CELLULES invisibles
-- (repere logique) portant chacune un BRIN d'herbe (visuel). L'attribut GROWTH (1 = haute, 0 = tondue) descend quand la
-- tondeuse passe ; le brin s'enfonce/raccourcit -> l'avant/apres. La grille spatiale (buckets) rend la coupe efficace.
--
-- Ce N'EST PAS de l'animation par brin (ca ne scalait pas) : le "vivant" vient du geste de tonte, pas du vent.

return {
	-- ===== SOURCE DE LA PELOUSE =====
	-- Tag CollectionService pose sur une PART plate = une pelouse a paver (comme "Hedge" pour les haies). Le joueur tague
	-- une part sur son plot ; LawnCellService la pave. Une part = une pelouse.
	TAG = "Lawn",
	CELL_FOLDER = "LawnCells", -- dossier Workspace ou vivent les cellules generees

	-- ===== VISUEL DU BRIN (par cellule) =====
	-- Chemin sous ReplicatedStorage vers le mesh d'un BRIN d'herbe (comme LEAF_ASSET pour les haies). IDEAL : un seul
	-- BasePart / MeshPart d'herbe STATIQUE (pas le modele anime avec Humanoid -- c'est lui qui faisait ramer). Si le chemin
	-- pointe sur un Model, LawnCellService prendra sa 1re MeshPart et jettera tout Humanoid/Animator.
	TUFT_ASSET = { "Assets", "Contents", "grass" },

	-- ===== GRILLE DE CELLULES =====
	-- Cote d'une cellule (studs). PLUS GRAND QUE LES HAIES (0.7) : une pelouse est vaste, des cellules trop fines feraient
	-- des milliers de brins = FPS au sol. 2 = compromis (assez fin pour une tonte granuleuse, assez gros pour tenir). LE
	-- levier de perf No 1. A REGLER a l'oeil selon la taille de la pelouse et le FPS.
	CELL_SIZE = 2,
	CELL_THICKNESS = 0.2, -- epaisseur de la cellule-repere vers le haut (le brin se pose dessus)
	CELL_TRANSPARENCY = 1, -- cellule invisible : ce n'est qu'un repere logique, le brin porte le visuel
	CELL_BUCKET_SIZE = 6, -- cote d'une case de la grille spatiale (studs). ~ quelques cellules. Sert a collectNear
	CELL_BUDGET = 3000, -- garde-fou : nombre max de cellules par pelouse (evite un runaway sur une enorme part)

	-- ===== POUSSE / TONTE =====
	GROWTH_ATTRIBUTE = "Growth", -- pousse du brin : 1 = haute (pas tondue), 0 = au ras. Meme nom que les haies (rendu partage)
	TRIMMED_ATTRIBUTE = "LeafiaMown", -- avancement 0->1 pose sur la PELOUSE (pour une jauge / paie de fin plus tard)
	PAID_ATTRIBUTE = "LeafiaMownPaid", -- garde "paye une fois" (cheque de fin de tonte, plus tard)
	CUT_RATE = 4.0, -- pousse retiree par seconde sous la tondeuse (plus grand = tond plus vite). A REGLER
	AUTO_COMPLETE_THRESHOLD = 0.97, -- au-dela, on finit la pelouse tout seul (derniers brins chiants a chopper)

	-- ===== ZONE DE COUPE (sous la tondeuse) =====
	-- La tondeuse coupe les cellules dans un RAYON autour de sa CutZone (une sphere, pas une lame visee). CUT_RADIUS = demi
	-- largeur du carter grosso modo ; CUT_MARGIN = tolerance. Portee de coupe = CUT_RADIUS + CUT_MARGIN. A REGLER sur la
	-- taille reelle de ta tondeuse une fois le modele pret.
	CUT_RADIUS = 2.5,
	CUT_MARGIN = 0.6,

	-- ===== RENDU DU BRIN (calcule client, comme la feuille des haies) =====
	CUT_DEPTH = 1.2, -- de combien le brin s'ENFONCE quand il passe de haut (growth 1) a ras (growth 0) : l'avant/apres
	CUT_SHRINK = 0.4, -- rapetissement du brin au ras (0 = garde sa taille, 1 = disparait). Renforce le "coupe"

	-- ===== BRIN : desordre a la pose (aleatoire seme, comme les feuilles) =====
	TUFT_SCALE = 1.0, -- echelle de base du brin (x la taille de la cellule)
	TUFT_SCALE_MIN = 0.85, -- variation d'echelle mini
	TUFT_SCALE_MAX = 1.25, -- variation d'echelle maxi
	TUFT_YAW = 180, -- rotation aleatoire max autour de la verticale (degres) : casse la regularite
	TUFT_JITTER = 0.25, -- decalage aleatoire dans la cellule (fraction de la cellule)
}
