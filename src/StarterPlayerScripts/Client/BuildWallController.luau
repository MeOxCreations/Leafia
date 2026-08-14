--!strict
-- MODE MUR (build) facon Sims. On CLIC-DRAG sur la grille pour tirer un mur qui GRANDIT le long des lignes (H, V ou
-- DIAGONALE), on relache pour le poser. Le fantome = une BALL au sol (l'ancre, sur un COIN de grille) + un CYLINDRE fin
-- qui monte (la poignee), GROUPES dans un Model, en Neon. Le handle se PENCHE dans le sens du curseur (comme l'objet).
-- A chaque bout d'un mur, un POTEAU cylindrique masque l'angle (les jointures entre deux murs).
--
-- Pilote par BuildController : start a l'entree du build ; setEnabled(true/false) selon le mode courant (mur vs objet).
-- CLIENT (prediction ; INCREMENT 1 : hauteur fixe). Autorite serveur + save + poignee de hauteur + chainage : ensuite.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfigs = require(ReplicatedStorage.Modules.Configs.BuildConfigs)
local BuildFx = require(script.Parent.Utils.BuildFx)
local Toast = require(ReplicatedStorage.Modules.UI.Core.Toast)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local PriceTag = require(script.Parent.Utils.PriceTag)

local TILE = BuildConfigs.TILE_SIZE
local WALL_THICKNESS = BuildConfigs.WALL_THICKNESS
local WALL_PRICE = BuildConfigs.WALL_PRICE

local BuildWallController = {}

local FOLLOW_BIND = "LeafiaWallGhost"
local WALL_COLOR = Color3.fromRGB(210, 220, 230)
local BALL_COLOR = Color3.fromRGB(192, 119, 229) -- Neon
local CYL_COLOR = Color3.fromRGB(229, 229, 229) -- Neon
local INVALID_COLOR = Color3.fromRGB(230, 70, 70) -- rouge : handle + apercu quand le mur chevauche un mur deja pose
local PREVIEW_TRANSPARENCY = 0.4
local BALL_SIZE = 0.7 -- deux fois plus petit qu'avant
local HANDLE_THICKNESS = 0.2 -- cylindre poignee plus fin
-- Lean du handle (meme effet que le fantome d'objet) : il se penche dans le sens du curseur, se redresse a l'arret.
local VEL_SMOOTH = 10
local LEAN_FACTOR = 0.004
local MAX_LEAN_DEG = 16
local HANDLE_SLIDE = 16 -- vitesse de GLISSEMENT de la poignee vers le coin sous le curseur (grand = vif, petit = flottant)
local WALL_BUILD_SOUND = "rbxassetid://106419078545029" -- "tic" joue a CHAQUE nouvelle tuile de mur qui apparait pendant le slide
local WALL_BUILD_VOLUME = 0.4
local COST_LABEL_HEIGHT = 6 -- studs AU-DESSUS du mur ou flotte la pastille de cout (plus grand = plus ecarte du mur)
local COST_COLOR = Color3.fromRGB(230, 60, 60) -- rouge = prix a payer (le style de la pastille est dans PriceTag)
-- TEMP : touches 1..9 pour choisir le TYPE de mur (hauteur). En attendant l'UI de catalogue faite dans Studio.
local NUM_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

local active = false
local enabled = false -- vrai seulement quand le mode MUR est actif
local ground: BasePart? = nil
local buildFolder: Instance? = nil

local handleModel: Model? = nil
local handleBall: BasePart? = nil
local handleCyl: BasePart? = nil
local costTag: PriceTag.Tag? = nil -- pastille flottante du COUT du mur pendant le drag ("-X" coins), creee a la demande
local previewSegments: { BasePart } = {} -- pool de segments d'apercu (reutilises chaque frame)
local previewFolder: Folder? = nil -- dossier qui regroupe le pool d'apercu (pour ne pas polluer le Workspace)
local wallTemplates: { BasePart } = {} -- meshes de mur dispo (metal_wall_type_1/2/3), enumeres au start, tries par nom
local wallTemplate: BasePart? = nil -- le mesh du mur COURANT a cloner
local wallHeight = BuildConfigs.WALL_HEIGHT -- hauteur du mur COURANT (= Size.Y du mesh choisi) ; repli sur le config
local wallColor = WALL_COLOR -- couleur du mur / des poteaux = celle du mesh COURANT, sinon fallback

local dragging = false
local startCX = 0
local startCZ = 0
local ghostVel = Vector3.zero -- vitesse lissee du curseur au sol (alimente le lean)
local prevHitPos: Vector3? = nil
local lastBlockToast = 0 -- anti-spam de la notif rouge (mur dans mur)
local lastPreviewSegs = 0 -- nb de tuiles de l'apercu la frame precedente (pour jouer un "tic" a CHAQUE nouvelle tuile)
local handleSmoothX: number? = nil -- position AFFICHEE lissee de la poignee (glisse vers le coin snappe) ; nil = colle direct
local handleSmoothZ: number? = nil

-- Coin de grille le plus proche du curseur (LOCAL du sol) + le point de contact BRUT (pour la vitesse). nil hors sol.
local function cornerFromCursor(): (number?, number?, Vector3?)
	local gr = ground
	local camera = workspace.CurrentCamera
	if not (gr and camera) then
		return nil, nil, nil
	end
	local m = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(m.X, m.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { gr }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 3000, params)
	if not result then
		return nil, nil, nil
	end
	local localHit = gr.CFrame:PointToObjectSpace(result.Position)
	local cornerX = -gr.Size.X * 0.5
	local cornerZ = -gr.Size.Z * 0.5
	local cx = cornerX + math.round((localHit.X - cornerX) / TILE) * TILE
	local cz = cornerZ + math.round((localHit.Z - cornerZ) / TILE) * TILE
	return cx, cz, result.Position
end

local function ensureHandle()
	if handleModel then
		return
	end
	local model = Instance.new("Model")
	model.Name = "LeafiaWallHandle"

	local ball = Instance.new("Part")
	ball.Name = "LeafiaWallHandleBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(BALL_SIZE, BALL_SIZE, BALL_SIZE)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CastShadow = false
	ball.Material = Enum.Material.Neon
	ball.Color = BALL_COLOR
	ball.Parent = model

	local cyl = Instance.new("Part")
	cyl.Name = "LeafiaWallHandleCyl"
	cyl.Shape = Enum.PartType.Cylinder -- axe le long de X ; on le met DEBOUT (tourne de 90 autour de Z) a la pose
	cyl.Size = Vector3.new(wallHeight, HANDLE_THICKNESS, HANDLE_THICKNESS)
	cyl.Anchored = true
	cyl.CanCollide = false
	cyl.CanQuery = false
	cyl.CastShadow = false
	cyl.Material = Enum.Material.Neon
	cyl.Color = CYL_COLOR
	cyl.Parent = model

	model.Parent = workspace
	handleModel = model
	handleBall = ball
	handleCyl = cyl
end

-- Place le handle au coin (cx,cz), incline par leanCF (rotation autour de la base = le coin au sol).
local function positionHandle(cx: number, cz: number, leanCF: CFrame, invalid: boolean)
	ensureHandle()
	local gr = ground :: BasePart
	local topY = gr.Size.Y * 0.5
	-- Repere de la BASE (le coin au sol), deja incline : ball et cyl se placent DANS ce repere -> ils penchent ensemble
	-- autour du coin quand leanCF tourne (leanCF est une rotation, elle ne bouge pas l'origine).
	local base = gr.CFrame * CFrame.new(cx, topY, cz) * leanCF
	local ball = handleBall :: BasePart
	local cyl = handleCyl :: BasePart
	ball.CFrame = base * CFrame.new(0, BALL_SIZE * 0.3, 0)
	cyl.CFrame = base * CFrame.new(0, wallHeight * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90))
	ball.Color = if invalid then INVALID_COLOR else BALL_COLOR
	cyl.Color = if invalid then INVALID_COLOR else CYL_COLOR
	ball.Transparency = 0
	cyl.Transparency = 0
end

local function hideHandle()
	if handleBall then
		handleBall.Transparency = 1
	end
	if handleCyl then
		handleCyl.Transparency = 1
	end
end

-- Rotation de lean pour la vitesse courante (identity si a l'arret). Meme sens que le fantome d'objet (confirme ecran).
local function computeLean(): CFrame
	local speed = ghostVel.Magnitude
	if speed <= 0.5 then
		return CFrame.identity
	end
	local axis = ghostVel.Unit:Cross(Vector3.new(0, 1, 0))
	if axis.Magnitude < 1e-3 then
		return CFrame.identity
	end
	local angle = math.min(speed * LEAN_FACTOR, math.rad(MAX_LEAN_DEG))
	return CFrame.fromAxisAngle(axis.Unit, angle)
end

-- Contraint le bout a une des 8 DIRECTIONS (H, V, 4 diagonales) : on snappe l'angle du geste au multiple de 45 deg, puis
-- on avance d'un nombre entier de PAS le long de cette direction (pas = TILE en H/V, TILE*racine2 en diagonale).
local function constrain(sx: number, sz: number, ex: number, ez: number): (number, number)
	local dx = ex - sx
	local dz = ez - sz
	if dx == 0 and dz == 0 then
		return sx, sz
	end
	local snapped = math.round(math.atan2(dz, dx) / (math.pi / 4)) * (math.pi / 4)
	local dirX = math.cos(snapped)
	local dirZ = math.sin(snapped)
	local isDiag = math.abs(dirX) > 0.1 and math.abs(dirZ) > 0.1
	local step = if isDiag then TILE * math.sqrt(2) else TILE
	local k = math.max(0, math.round((dx * dirX + dz * dirZ) / step))
	return sx + dirX * step * k, sz + dirZ * step * k
end

-- Segments d'un mur du coin (sx,sz) au coin (ex,ez) : UN morceau de mesh a sa taille NATIVE par "case" le long de la
-- ligne, PAS d'etirement (la taule garde son echelle). Pas = TILE en H/V (= largeur native du mesh), TILE*racine2 en
-- diagonale. Rend une liste de { cf, size } en repere MONDE. Vide si trop court (moins d'une demi-case).
type Segment = { cf: CFrame, size: Vector3 }
local function wallSegments(sx: number, sz: number, ex: number, ez: number): { Segment }
	local segs: { Segment } = {}
	local gr = ground :: BasePart
	local topY = gr.Size.Y * 0.5
	local diff = Vector3.new(ex - sx, 0, ez - sz)
	local length = diff.Magnitude
	if length < 1e-3 then
		return segs
	end
	local dir = diff.Unit
	local isDiag = math.abs(dir.X) > 0.1 and math.abs(dir.Z) > 0.1
	local step = if isDiag then TILE * math.sqrt(2) else TILE -- une case le long de la ligne
	local n = math.round(length / step)
	if n < 1 then
		return segs
	end
	for i = 0, n - 1 do
		local center = Vector3.new(sx, topY + wallHeight * 0.5, sz) + dir * ((i + 0.5) * step)
		table.insert(segs, {
			cf = gr.CFrame * CFrame.lookAt(center, center + dir),
			size = Vector3.new(WALL_THICKNESS, wallHeight, step),
		})
	end
	return segs
end

-- Un morceau de mur pret a poser : le VRAI mesh clone s'il est resolu (etire ensuite via Size le long de Z), sinon une
-- box de secours a la couleur du mur.
local function newWallPart(): BasePart
	if wallTemplate then
		return wallTemplate:Clone()
	end
	local p = Instance.new("Part")
	p.Material = Enum.Material.SmoothPlastic
	p.Color = wallColor
	return p
end

-- Le mur (ses segments) chevauche-t-il un mur DEJA pose ? On compare les CENTRES des segments, PAS des boites. Pourquoi :
-- GetPartBoundsInBox teste l'AABB (boite alignee sur les axes) des parts, et l'AABB d'un mur DIAGONAL est enorme (un
-- rectangle a 45 deg deborde d'une case sur ses voisines) -> il declenchait de faux chevauchements des qu'on connectait un
-- mur a une diagonale ou qu'on en continuait un. Deux segments sur la MEME case ont le MEME centre ; une jonction (bout-a-
-- bout, T, angle, diagonale) a des centres ecartes d'au moins ~1.5 stud. On compare AU SOL (X,Z) pour gerer les murs de
-- hauteurs differentes (leur centre est a une hauteur differente, mais la case au sol est la meme).
local OVERLAP_TOL = 1.0 -- en dessous de cette distance au sol entre deux centres = vrai chevauchement (meme case)
local function segmentsBlocked(segs: { Segment }): boolean
	if not buildFolder then
		return false
	end
	local centers: { Vector3 } = {}
	for _, child in ipairs(buildFolder:GetChildren()) do
		if child.Name == "Wall" and child:IsA("BasePart") then
			table.insert(centers, child.Position)
		end
	end
	local tol2 = OVERLAP_TOL * OVERLAP_TOL
	for _, seg in ipairs(segs) do
		local c = seg.cf.Position
		for _, wc in ipairs(centers) do
			local dx, dz = wc.X - c.X, wc.Z - c.Z
			if dx * dx + dz * dz < tol2 then
				return true
			end
		end
	end
	return false
end

-- Segment d'apercu numero i (pool reutilise : on ne clone pas des meshes chaque frame).
local function getPreviewSegment(i: number): BasePart
	local p = previewSegments[i]
	if not p then
		p = newWallPart()
		p.Name = "LeafiaWallPreviewSeg"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
		p.Parent = previewFolder or workspace
		previewSegments[i] = p
	end
	return p
end

local function showWallPreview(segs: { Segment }, blocked: boolean)
	local color = if blocked then INVALID_COLOR else wallColor
	local used = 0
	for _, seg in ipairs(segs) do
		used += 1
		local p = getPreviewSegment(used)
		p.Size = seg.size
		p.CFrame = seg.cf
		p.Color = color
		p.Transparency = PREVIEW_TRANSPARENCY
	end
	for i = used + 1, #previewSegments do
		previewSegments[i].Transparency = 1 -- segments en trop (mur plus court) : caches
	end
end

local function hideWallPreview()
	for _, p in ipairs(previewSegments) do
		p.Transparency = 1
	end
end

-- Poteau cylindrique vertical a un coin : masque l'angle moche quand deux murs se rejoignent (diametre = epaisseur mur).
local function placeCornerPost(cx: number, cz: number)
	local gr = ground :: BasePart
	local topY = gr.Size.Y * 0.5
	local worldPos = (gr.CFrame * CFrame.new(cx, topY + wallHeight * 0.5, cz)).Position
	-- DEDUP : deja un poteau a ce coin ? On ne le double pas (deux murs qui se rejoignent PARTAGENT le coin -> un seul poteau).
	if buildFolder then
		for _, child in ipairs(buildFolder:GetChildren()) do
			if child.Name == "WallCorner" and child:IsA("BasePart") and (child.Position - worldPos).Magnitude < 0.5 then
				return
			end
		end
	end
	local post = Instance.new("Part")
	post.Name = "WallCorner"
	post.Shape = Enum.PartType.Cylinder
	post.Size = Vector3.new(wallHeight, WALL_THICKNESS, WALL_THICKNESS)
	post.Anchored = true
	post.CanCollide = false
	post.CFrame = gr.CFrame * CFrame.new(cx, topY + wallHeight * 0.5, cz) * CFrame.Angles(0, 0, math.rad(90))
	post.Material = Enum.Material.SmoothPlastic
	post.Color = wallColor -- assorti au mesh du mur
	post.Parent = buildFolder or workspace
end

local function placeWall(sx: number, sz: number, ex: number, ez: number)
	local segs = wallSegments(sx, sz, ex, ez)
	if #segs == 0 then
		return -- trop court : rien a poser
	end
	if segmentsBlocked(segs) then
		-- mur dans mur : notif ROUGE (Warning) + anti-spam, on ne pose rien.
		if os.clock() - lastBlockToast > 0.5 then
			lastBlockToast = os.clock()
			Toast.show("Warning", "Can't build here!")
		end
		return
	end
	for _, seg in ipairs(segs) do
		local wall = newWallPart()
		wall.Name = "Wall"
		wall.Anchored = true
		wall.CanCollide = false -- mur decoratif : pas de collision (cf le hitbox retire pour ne pas handicaper le joueur)
		wall.Size = seg.size
		wall.CFrame = seg.cf
		wall.Parent = buildFolder or workspace -- CLIENT-only ; serveur + save plus tard
	end
	-- Poteaux d'angle aux deux bouts : jointures propres quand un autre mur arrive au meme coin.
	placeCornerPost(sx, sz)
	placeCornerPost(ex, ez)
	-- Son de depose + poof de fumee au MILIEU du mur, au sol (helper partage avec le placement d'objet).
	local gr = ground :: BasePart
	local topY = gr.Size.Y * 0.5
	BuildFx.playPlace((gr.CFrame * CFrame.new((sx + ex) * 0.5, topY, (sz + ez) * 0.5)).Position)
end

-- Pastille flottante du COUT (creee a la demande, style + adaptation ecran dans PriceTag). Le joueur voit combien le mur
-- va lui couter PENDANT qu'il le tire. Prix en rouge (a payer).
local function showCost(worldPos: Vector3, amount: number)
	if not costTag then
		costTag = PriceTag.new()
	end
	(costTag :: PriceTag.Tag).show(worldPos, "-" .. amount, COST_COLOR)
end

local function hideCost()
	if costTag then
		costTag.hide()
	end
end

-- Chaque frame : suit le curseur. En drag, montre le mur qui grandit + la poignee ancree au depart ; sinon la poignee
-- suit le curseur en se penchant selon la vitesse.
local function updateWall(dt: number)
	if not (active and enabled and ground) then
		return
	end
	local cx, cz, hit = cornerFromCursor()
	if not (cx and cz and hit) then
		hideHandle()
		hideWallPreview()
		hideCost()
		handleSmoothX, handleSmoothZ = nil, nil -- curseur hors sol : on repartira colle (pas de glissement depuis un vieux coin)
		return
	end
	if prevHitPos then
		local inst = (hit - prevHitPos) / math.max(dt, 1 / 120)
		ghostVel = ghostVel:Lerp(Vector3.new(inst.X, 0, inst.Z), math.min(1, VEL_SMOOTH * dt))
	end
	prevHitPos = hit
	if dragging then
		local ex, ez = constrain(startCX, startCZ, cx, cz)
		local segs = wallSegments(startCX, startCZ, ex, ez)
		local blocked = segmentsBlocked(segs)
		if #segs > lastPreviewSegs and not blocked then
			SoundUtils.playId(WALL_BUILD_SOUND, WALL_BUILD_VOLUME) -- "tic" a chaque nouvelle tuile valide qui apparait
		end
		lastPreviewSegs = #segs
		showWallPreview(segs, blocked)
		positionHandle(startCX, startCZ, CFrame.identity, blocked) -- ancree au depart ; ROUGE si le mur chevauche
		handleSmoothX, handleSmoothZ = startCX, startCZ -- sync : au relachement, la poignee glissera DEPUIS l'ancre
		if #segs > 0 then
			-- Cout affiche AU BOUT du mur (le coin qui suit le curseur), au-dessus, en dore : -nbSegments * prix.
			local gr = ground :: BasePart
			local topY = gr.Size.Y * 0.5
			local endWorld = (gr.CFrame * CFrame.new(ex, topY + wallHeight + COST_LABEL_HEIGHT, ez)).Position
			showCost(endWorld, #segs * WALL_PRICE)
		else
			hideCost()
		end
	else
		hideWallPreview()
		hideCost()
		-- GLISSEMENT doux de la poignee vers le coin sous le curseur (au lieu de sauter de coin en coin). A l'arret on colle
		-- (un lerp expo n'atteint jamais sa cible, cf journal). Locals hx/hz pour un narrowing propre (upvalues nilables).
		local hx, hz = handleSmoothX, handleSmoothZ
		if hx and hz then
			local a = math.min(1, HANDLE_SLIDE * dt)
			hx += (cx - hx) * a
			hz += (cz - hz) * a
			if math.abs(cx - hx) < 0.01 and math.abs(cz - hz) < 0.01 then
				hx, hz = cx, cz
			end
		else
			hx, hz = cx, cz -- premiere frame (ou apres un hors-sol) : on colle direct
		end
		handleSmoothX, handleSmoothZ = hx, hz
		positionHandle(hx, hz, computeLean(), false)
	end
end

local CORNER_TOL = 0.6 -- tolerance de position pour rattacher un poteau d'angle a un bout de mur

-- Les deux bouts (monde) d'un segment de mur : centre +/- l'axe long (Z du part) * demi-longueur.
local function wallEnds(wall: BasePart): (Vector3, Vector3)
	local half = wall.CFrame.LookVector * (wall.Size.Z * 0.5)
	return wall.CFrame.Position + half, wall.CFrame.Position - half
end

-- Un AUTRE mur (pas `exclude`) a-t-il un bout sur ce point ? Sert a savoir si un poteau est encore partage.
local function anyOtherWallTouches(point: Vector3, exclude: BasePart): boolean
	if not buildFolder then
		return false
	end
	for _, child in ipairs(buildFolder:GetChildren()) do
		if child ~= exclude and child.Name == "Wall" and child:IsA("BasePart") then
			local a, b = wallEnds(child)
			if (a - point).Magnitude < CORNER_TOL or (b - point).Magnitude < CORNER_TOL then
				return true
			end
		end
	end
	return false
end

-- Appele par le mode SUPPRIMER juste AVANT d'effacer une part : si c'est un mur, enleve les poteaux d'angle a ses bouts
-- qui ne servent plus a AUCUN autre mur (deux murs qui se rejoignent PARTAGENT un poteau -> on ne l'enleve que s'il
-- devient orphelin). Pas un mur -> ne fait rien.
function BuildWallController.cleanupCornersFor(inst: Instance)
	if not (inst:IsA("BasePart") and inst.Name == "Wall" and buildFolder) then
		return
	end
	local e1, e2 = wallEnds(inst)
	for _, child in ipairs(buildFolder:GetChildren()) do
		if child.Name == "WallCorner" and child:IsA("BasePart") then
			local p = child.Position
			local atEnd = (p - e1).Magnitude < CORNER_TOL or (p - e2).Magnitude < CORNER_TOL
			if atEnd and not anyOtherWallTouches(p, inst) then
				child:Destroy()
			end
		end
	end
end

-- Poteaux d'angle aux bouts de `wall` qui PARTIRAIENT avec lui : ceux qu'aucun AUTRE mur ne tient, sauf les murs pour
-- lesquels `isAlsoGone` renvoie vrai (les autres murs deja marques pour suppression). Sert au mode SUPPRIMER a marquer
-- automatiquement le poteau avec son mur en previsu, sans allumer un poteau encore tenu par un mur qui reste.
function BuildWallController.orphanCornersOf(wall: BasePart, isAlsoGone: (Instance) -> boolean): { BasePart }
	local out: { BasePart } = {}
	if not (wall.Name == "Wall" and buildFolder) then
		return out
	end
	local e1, e2 = wallEnds(wall)
	for _, child in ipairs(buildFolder:GetChildren()) do
		if child.Name == "WallCorner" and child:IsA("BasePart") then
			local p = child.Position
			if (p - e1).Magnitude < CORNER_TOL or (p - e2).Magnitude < CORNER_TOL then
				local shared = false
				for _, other in ipairs(buildFolder:GetChildren()) do
					if other ~= wall and other.Name == "Wall" and other:IsA("BasePart") and not isAlsoGone(other) then
						local a, b = wallEnds(other)
						if (a - p).Magnitude < CORNER_TOL or (b - p).Magnitude < CORNER_TOL then
							shared = true
							break
						end
					end
				end
				if not shared then
					table.insert(out, child)
				end
			end
		end
	end
	return out
end

-- Le premier mur dont un BOUT touche `point`, ou nil. Sert au mode suppression : viser un poteau d'angle vise en fait le
-- mur qui s'y rattache (on ne doit pas pouvoir effacer un poteau tout seul). nil si aucun mur (poteau vraiment orphelin).
function BuildWallController.wallTouchingPoint(point: Vector3): BasePart?
	if not buildFolder then
		return nil
	end
	for _, child in ipairs(buildFolder:GetChildren()) do
		if child.Name == "Wall" and child:IsA("BasePart") then
			local a, b = wallEnds(child)
			if (a - point).Magnitude < CORNER_TOL or (b - point).Magnitude < CORNER_TOL then
				return child
			end
		end
	end
	return nil
end

-- Choisit le type de mur numero i (1..#wallTemplates) : met a jour le mesh COURANT, sa hauteur (Size.Y) et sa couleur,
-- puis REBATIT la poignee (son cylindre doit refleter la nouvelle hauteur). Hors bornes -> ignore.
local function selectWall(i: number)
	local tmpl = wallTemplates[i]
	if not tmpl or tmpl == wallTemplate then
		return -- hors bornes, ou deja le mur courant (evite un rebuild inutile de la poignee)
	end
	wallTemplate = tmpl
	wallHeight = tmpl.Size.Y
	wallColor = tmpl.Color
	if handleModel then
		handleModel:Destroy() -- rebatie par ensureHandle a la bonne hauteur
		handleModel = nil
		handleBall = nil
		handleCyl = nil
	end
end

function BuildWallController.start(g: BasePart)
	if active then
		return
	end
	active = true
	ground = g
	buildFolder = g.Parent and g.Parent:FindFirstChild(BuildConfigs.BUILDS_FOLDER)
	local folder = Instance.new("Folder")
	folder.Name = "LeafiaWallPreview"
	folder.Parent = workspace
	previewFolder = folder
	-- Enumere les meshes de mur sous Assets.Contents.Build : ce sont les BaseParts (les objets, eux, sont des Models avec
	-- Hitbox -> exclus par le fait qu'un Model n'est PAS un BasePart). Tries par nom pour que 1/2/3 tombent sur type_1/2/3.
	-- selectWall lit hauteur (Size.Y) + couleur du mur choisi. Aucun mesh -> fallback box (newWallPart) + valeurs du config.
	local node: Instance? = ReplicatedStorage
	for _, name in ipairs(BuildConfigs.BUILD_ASSETS_PATH) do
		node = node and node:FindFirstChild(name)
	end
	wallTemplates = {}
	if node then
		for _, child in ipairs(node:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(wallTemplates, child)
			end
		end
		table.sort(wallTemplates, function(a, b)
			return a.Name < b.Name
		end)
	end
	selectWall(1) -- mur par defaut = le premier (le plus bas)
	RunService:BindToRenderStep(FOLLOW_BIND, Enum.RenderPriority.Camera.Value + 1, updateWall)
end

function BuildWallController.stop()
	if not active then
		return
	end
	active = false
	enabled = false
	dragging = false
	ground = nil
	buildFolder = nil
	RunService:UnbindFromRenderStep(FOLLOW_BIND)
	if handleModel then
		handleModel:Destroy()
		handleModel = nil
		handleBall = nil
		handleCyl = nil
	end
	if previewFolder then
		previewFolder:Destroy() -- emporte tout le pool d'apercu d'un coup
		previewFolder = nil
	end
	table.clear(previewSegments)
	if costTag then
		costTag.destroy()
		costTag = nil
	end
end

function BuildWallController.setEnabled(on: boolean)
	enabled = on
	if not on then
		dragging = false
		hideHandle()
		hideWallPreview()
		hideCost()
		handleSmoothX, handleSmoothZ = nil, nil
	end
end

function BuildWallController.init()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not (active and enabled) or gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local cx, cz = cornerFromCursor()
			if cx and cz then
				startCX, startCZ = cx, cz
				dragging = true
				lastPreviewSegs = 0 -- nouveau trace : le "tic" repart de zero
			end
		end
		local n = NUM_KEYS[input.KeyCode]
		if n then
			selectWall(n) -- 1/2/3... : choix du type de mur (hauteur)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		-- Relachement TOUJOURS traite (pas de filtre gameProcessed), sinon un drag reste coince.
		if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
			dragging = false
			local cx, cz = cornerFromCursor()
			if cx and cz then
				local ex, ez = constrain(startCX, startCZ, cx, cz)
				placeWall(startCX, startCZ, ex, ez)
			end
			hideWallPreview()
		end
	end)
end

return BuildWallController
