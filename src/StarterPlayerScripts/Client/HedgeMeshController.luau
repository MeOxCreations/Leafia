--!strict
-- Etape 1 : une part portant une image de surface, batie sur le modele de GroundGrillVisualBuild.
--
-- L'idee : remplacer des centaines de feuilles en volume par UNE image plaquee. Une SurfaceGui est un seul
-- objet, quel que soit le detail dessine dessus, alors que chaque feuille est une instance a repliquer, a
-- placer et a animer.
--
-- POURQUOI COTE CLIENT. Le serveur garde la DONNEE (la pousse de chaque carreau), le client fabrique le RENDU.
-- C'est deja la regle que suit HedgeLeafController, et elle devient obligatoire des qu'on generera de la
-- geometrie a l'execution : celle-la ne se replique pas.
--
-- Rien du reste du jeu ne connait ce module. Il peut etre supprime a tout moment sans rien casser.

local Players = game:GetService("Players")

local HedgeMeshController = {}

local player = Players.LocalPlayer

-- Reglages d'essai. Ils remonteront dans HedgeConfigs quand le module aura prouve qu'il sert a quelque chose ;
-- les garder ici tant que ca bouge evite de polluer une config que tout le jeu lit.
-- PLAQUE, pas cube. L'epaisseur ne sert qu'a exister : c'est la face du DESSUS qui porte l'image, et une part
-- epaisse montrerait ses quatre cotes nus autour. Ce qu'on veut est un panneau, pas un bloc.
local PART_SIZE = Vector3.new(6, 0.128, 6)
-- Image affichee.
local IMAGE = "rbxassetid://115672537128548"
-- Teinte appliquee a l'image. Blanc = l'image telle quelle.
local IMAGE_COLOR = Color3.fromRGB(58, 4, 4)
-- Cote d'une tuile, en PIXELS de la SurfaceGui.
--
-- C'EST LUI QUI REND LA TEXTURE INDEPENDANTE DE LA TAILLE. En mode Tile, l'image se repete tous les
-- TILE_SIZE pixels au lieu de s'etirer sur toute la surface. Comme la SurfaceGui compte PIXELS_PER_STUD pixels
-- par stud, un motif fait toujours TILE_SIZE / PIXELS_PER_STUD studs, sur une haie de 6 comme de 20.
-- A 400 px et 200 px/stud : un motif tous les 2 studs.
local TILE_SIZE = 400
-- Face de la part qui porte l'image.
local FACE = Enum.NormalId.Top
-- Definition de l'image, en pixels par stud. Plus haut = plus net et plus cher. 200 comme sur ta grille.
local PIXELS_PER_STUD = 200
-- Au-dela, Roblox cesse de dessiner la SurfaceGui. C'est le reglage de perf le plus direct de cet objet :
-- une image tres detaillee qu'on ne voit pas de loin ne coute alors plus rien.
local MAX_DISTANCE = 1000

local host: BasePart? = nil

-- La part d'accueil. Rendue au reste du module pour que la suite s'y accroche sans avoir a la retrouver.
function HedgeMeshController.getHost(): BasePart?
	return host
end

local function build(character: Model)
	if host and host.Parent then
		return
	end

	local part = Instance.new("Part")
	part.Name = "HedgeMesh"
	part.Size = PART_SIZE
	part.Material = Enum.Material.SmoothPlastic
	-- INVISIBLE, mais son image ne l'est pas. Une SurfaceGui se dessine independamment de la transparence de sa
	-- part : il ne reste donc que l'image, sans la tranche de plastique autour.
	-- SmoothPlastic quand meme, et pas au hasard : les autres materiaux ajoutent un relief calcule que le moteur
	-- traite meme sur une surface qu'on ne voit pas.
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	-- CanQuery et CanTouch suivent CanCollide, et ce n'est pas du zele : CanQuery ne prend effet QUE si
	-- CanCollide est deja faux. Sans les trois, cette part serait vue par le lancer du curseur et par la
	-- detection de haie, et plus rien ne serait jamais detecte derriere elle.
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false

	local surface = Instance.new("SurfaceGui")
	surface.Name = "SurfaceGui"
	surface.Face = FACE
	-- PixelsPerStud et non FixedSize : la definition suit la taille de la part. Une haie deux fois plus longue
	-- garde donc la meme finesse d'image, sans qu'on ait un chiffre a recalculer a la main.
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = PIXELS_PER_STUD
	surface.MaxDistance = MAX_DISTANCE
	-- 1 = l'image recoit la lumiere de la scene, comme n'importe quelle surface. A 0 elle serait lumineuse en
	-- pleine nuit, et la haie flotterait hors de l'ambiance du jardin.
	surface.LightInfluence = 1
	surface.ClipsDescendants = true
	surface.Adornee = part
	surface.Parent = part

	local image = Instance.new("ImageLabel")
	image.Name = "ImageLabel"
	image.Image = IMAGE
	image.ImageColor3 = IMAGE_COLOR
	-- REPETEE, pas etiree. Etiree, le motif se deforme des qu'une haie n'est pas carree, et deux haies de
	-- tailles differentes n'ont pas le meme grain. Repetee, le grain est le meme partout et pour toujours.
	image.ScaleType = Enum.ScaleType.Tile
	image.TileSize = UDim2.fromOffset(TILE_SIZE, TILE_SIZE)
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	-- Ancree au centre et posee au centre : l'image reste centree quoi qu'il arrive a la taille de la part.
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(1, 1)
	image.Parent = surface

	-- DEVANT LE JOUEUR, jamais a l'origine du monde. Une part posee en (0, 0, 0) tombe presque toujours hors
	-- de vue ou sous le terrain, et on croit que le code n'a rien fait alors qu'il a tout fait.
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root and root:IsA("BasePart") then
		part.CFrame = root.CFrame * CFrame.new(0, 2, -10)
	else
		part.CFrame = CFrame.new(0, 10, 0)
	end

	-- DIRECTEMENT dans le Workspace, sans dossier tant qu'il n'y en a qu'une : on la trouve du premier coup
	-- dans l'Explorer. Elle ira dans un dossier quand elles seront plusieurs.
	part.Parent = workspace

	host = part
	print(
		`[HedgeMeshController] Part posee en {part.Position}, image {FACE.Name} de `
			.. `{math.round(PART_SIZE.X * PIXELS_PER_STUD)}x{math.round(PART_SIZE.Z * PIXELS_PER_STUD)} px`
			.. (if IMAGE == "" then " - AUCUNE IMAGE, remplis IMAGE en tete du module" else "")
	)
end

function HedgeMeshController.init()
	-- Le personnage peut deja etre la (rejouer sans relancer) ou arriver apres : les deux cas sont couverts,
	-- et `build` se garde d'en poser une deuxieme.
	local character = player.Character
	if character then
		task.spawn(build, character)
	end
	player.CharacterAdded:Connect(build)
end

return HedgeMeshController
