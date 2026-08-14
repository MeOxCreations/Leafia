--!strict
-- Constantes du mode BUILD (data pure, zero logique). PARTAGE client + serveur : la maille TILE_SIZE sert A LA FOIS au
-- snap de placement (client : fantome ; serveur : validation) ET au quadrillage au sol. Une SEULE valeur, sinon la
-- grille visuelle ne collerait pas aux cases ou les objets s'aimantent -> ca paraitrait casse.
--
-- Le catalogue des objets posables (categories, prix, tailles, verrous de niveau) viendra dans son propre Config
-- (BuildCatalogConfigs) quand on attaque le placement. Ici : juste les reglages du MODE lui-meme.

local BuildConfigs = {
	-- Cote d'une tuile, en studs. Maille commune au snap ET au quadrillage (les deux la lisent -> toujours synchro). Base
	-- du jeu = un bloc 3x3x3 (le Hitbox de reference fait 3x9x3 = 1 tuile au sol). A regler a l'oeil sur le plot.
	TILE_SIZE = 3,

	-- QUADRILLAGE au sol en build : un SurfaceGui + une ImageLabel en mode TILE (nommee TileGridBuild), pose cote CLIENT
	-- sur PrimaryGround (seul le batisseur la voit). CHOIX du SurfaceGui plutot que Texture : il tuile depuis un COIN de
	-- la face (origine NETTE), donc la grille s'aligne PILE sur le snap (qui part du meme coin) -- tant que le sol fait un
	-- multiple de TILE_SIZE. Une Texture, elle, a une phase (ou commencent les cases) impossible a deviner et differente
	-- selon l'image : c'etait la cause du decalage.
	GRID_TEXTURE = "rbxassetid://104656073939032", -- l'image d'UNE case (300x300)
	GRID_PIXELS_PER_STUD = 100, -- resolution du SurfaceGui (100 * TILE_SIZE 3 = 300 px = l'image en 1:1, net). Borne en
	-- code pour ne pas depasser la limite de canvas Roblox (~17000 px) sur les grands sols.
	-- La grille est faite de CARRES PLEINS (un Frame par case), pas de lignes : de loin une ligne fait moins d'1 pixel et
	-- DISPARAIT (minification), un carre plein reste visible. Les valeurs ci-dessous reglent ces carres.
	GRID_TRANSPARENCY = 0.94, -- transparence de chaque carre au repos (0 = plein, 1 = invisible). 0.94 = tres discret
	GRID_BRIGHTNESS = 10, -- Brightness du SurfaceGui : fait GLOWER les carres (les fait ressortir malgre la transparence)
	GRID_COLOR = Color3.fromRGB(255, 255, 255), -- couleur des carres (base ; le mode la remplace, voir ci-dessous)
	GRID_COLOR_BUILD = Color3.fromRGB(120, 220, 255), -- cases en mode CONSTRUIRE (objet / mur) : cyan
	GRID_COLOR_DELETE = Color3.fromRGB(255, 90, 90), -- cases en mode SUPPRIMER : rouge
	GRID_CELL_GAP = 0.14, -- part de la case laissee en JOINT autour du carre (0.14 = 14% de vide -> le quadrillage se lit)

	-- Nom de la part du plot sur laquelle on construit (le sol). Doit exister dans chaque plot Model.
	GROUND_NAME = "PrimaryGround",
	-- Dossier du plot ou atterrissent les objets poses (deja present dans chaque plot).
	BUILDS_FOLDER = "Build",

	-- MODELES POSABLES : chacun un Model (Mesh + Hitbox) sous ReplicatedStorage.<ce chemin>. Le Hitbox donne l'empreinte
	-- (tuiles occupees) et sert au test de place ; il reste invisible. A la pose on CLONE le modele tel quel dans le
	-- dossier Build du plot. Ajouter un modele dans ce dossier suffit pour qu'il devienne posable (comme les musiques).
	BUILD_ASSETS_PATH = { "Assets", "Contents", "Build" },
	HITBOX_NAME = "Hitbox",

	-- VFX de pose : ce Part/Model (sous ReplicatedStorage) est clone a la position du bloc pose, et TOUS ses
	-- ParticleEmitters (Smoke, SmokeB...) sont EMIT d'un coup a l'impact. Le clone se nettoie tout seul apres.
	PLACE_EFFECT_PATH = { "Assets", "Effects", "Build", "BuildPlaceEffect" },
	PLACE_EFFECT_EMIT = 50, -- particules emises par emetteur au moment de la pose

	-- MODE MUR : mur fin tire au clic-drag le long des lignes de grille (snap sur les COINS de grille, pas au centre des
	-- cases comme les objets). Hauteur fixe pour l'instant ; la poignee de hauteur reglable viendra apres.
	WALL_HEIGHT = 9, -- studs (3 tuiles, = hauteur du mesh de mur)
	WALL_THICKNESS = 0.3, -- epaisseur en studs (= epaisseur du mesh metal_wall_type_1)
	WALL_MODEL = "metal_wall_type_1", -- mesh du mur, sous BUILD_ASSETS_PATH (Assets.Contents.Build)
	WALL_PRICE = 15, -- coins PAR SEGMENT (une tuile de mur). Cout total affiche pendant le drag = nb segments * ce prix.
	-- Pour l'instant c'est un VISUEL du prix ; la vraie deduction viendra avec l'autorite serveur (spendCoins).
	WALL_TOGGLE_KEY = Enum.KeyCode.V, -- TEMP : bascule mode objet <-> mur
	DELETE_TOGGLE_KEY = Enum.KeyCode.X, -- TEMP : entre / sort du mode SUPPRIMER (effacer une structure au clic)

	-- TEMP : raccourci pour entrer / sortir du build tant que le bouton d'UI n'existe pas. A retirer quand l'UI
	-- (faite dans Studio) declenchera enter / exit elle-meme.
	TEMP_TOGGLE_KEY = Enum.KeyCode.B,
}

return BuildConfigs
