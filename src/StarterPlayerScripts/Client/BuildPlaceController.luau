--!strict
-- PLACEMENT en mode build : un FANTOME (clone du vrai modele) suit le curseur, snappe a la grille ; R tourne ; clic
-- gauche pose, avec un effet. Pilote par BuildController (start a l'entree du build, stop a la sortie).
--
-- CLIENT pour l'instant (rendu + prediction du geste, pour valider que POSER est jouissif). L'autorite serveur (valider
-- sur le plot, tuile libre, debiter les coins, sauvegarder la recette) vient dans la tranche suivante.
--
-- Les modeles vivent dans ReplicatedStorage.Assets.Contents.Build (BuildConfigs.BUILD_ASSETS_PATH). Chacun = un Model
-- avec un Mesh (visuel) et un Hitbox (part de collision). Le HITBOX donne l'empreinte (tuiles occupees) et le point de
-- pose. On snappe a BuildConfigs.TILE_SIZE = la MEME maille que le quadrillage au sol.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfigs = require(ReplicatedStorage.Modules.Configs.BuildConfigs)
local Toast = require(ReplicatedStorage.Modules.UI.Core.Toast)
local BuildFx = require(script.Parent.Utils.BuildFx)

local TILE = BuildConfigs.TILE_SIZE

-- TEMP : touches 1..9 pour changer de modele tant que le catalogue n'existe pas (KeyCode.One.Name = "One", pas "1",
-- donc mapping explicite).
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

local BuildPlaceController = {}

local FOLLOW_BIND = "LeafiaBuildGhost"
local GHOST_TRANSPARENCY = 0.4
local VALID_COLOR = Color3.fromRGB(90, 220, 110)
local INVALID_COLOR = Color3.fromRGB(230, 90, 90)
local CELL_TRANSPARENCY = 0.45 -- transparence des cases d'empreinte posees au sol (montrent OU on pose)
local DROP_HEIGHT = 2.5 -- studs : d'ou le bloc tombe avant de se poser
local DROP_TIME = 0.12 -- duree de la chute (ease-in : accelere)
local SQUASH_SCALE = 0.82 -- echelle a l'impact (ecrasement du slime)
local SQUASH_TIME = 0.2 -- duree de l'ecrasement + rebond
-- LEAN : le fantome se PENCHE dans le sens ou on bouge la souris (effet de vitesse), et se redresse a l'arret. Le sens
-- de l'inclinaison ne se devine pas -> il a ete confirme a l'ecran (ordre du Cross de l'axe, plus bas). LEAN_FACTOR ne
-- regle que l'INTENSITE (jamais le sens).
local VEL_SMOOTH = 10 -- lissage de la vitesse du curseur (grand = suit vite)
local LEAN_FACTOR = 0.004 -- radians par (stud/s) de vitesse -> inclinaison
local MAX_LEAN_DEG = 16 -- inclinaison max
local GHOST_SLIDE = 16 -- vitesse de GLISSEMENT du fantome vers la case cible (grand = suit vite / plus sec, petit = plus flottant)

local active = false
local enabled = true -- mode OBJET actif (false quand on passe en mode MUR : BuildController le bascule)
local ground: BasePart? = nil
local buildFolder: Instance? = nil -- dossier Build du plot (destination des objets poses)
local assetsFolder: Instance? = nil
local models: { Model } = {} -- modeles posables enumeres depuis Assets.Contents.Build
local currentIndex = 1

local ghost: Model? = nil
local ghostHitbox: BasePart? = nil
local ghostHighlight: Highlight? = nil
local ghostRot = 0 -- degres : 0 / 90 / 180 / 270
local ghostValid = false
local ghostPivot = CFrame.identity -- pose DROITE snappee (ce qu'on posera ; le lean est purement visuel)
local ghostVel = Vector3.zero -- vitesse lissee du curseur au sol (alimente le lean)
local prevHitPos: Vector3? = nil -- position hit de la frame precedente
local ghostSmoothPos: Vector3? = nil -- position AFFICHEE lissee (glisse vers la case snappee) ; nil = colle direct (nouveau fantome)
local cellParts: { BasePart } = {} -- pool de tuiles vertes/rouges sous l'empreinte (une par case), reutilisees

-- Resout un dossier par chemin sous ReplicatedStorage.
local function resolveByPath(path: { string }): Instance?
	local node: Instance? = ReplicatedStorage
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

-- Enumere les modeles posables (Model avec un Hitbox). Relu a chaque start -> ajouter un modele dans le dossier suffit.
local function refreshModels()
	models = {}
	if not assetsFolder then
		return
	end
	for _, child in ipairs(assetsFolder:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChild(BuildConfigs.HITBOX_NAME) then
			table.insert(models, child)
		end
	end
end

local function clearGhost()
	if ghost then
		ghost:Destroy()
	end
	ghost = nil
	ghostHitbox = nil
	ghostHighlight = nil
end

-- Construit le fantome : clone transparent, hitbox invisible et non bloquant, contour Highlight pour le vert / rouge.
local function makeGhost(template: Model)
	clearGhost()
	local g = template:Clone()
	g.Name = "LeafiaBuildGhost"
	for _, d in ipairs(g:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Transparency = if d.Name == BuildConfigs.HITBOX_NAME then 1 else GHOST_TRANSPARENCY
		end
	end
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 0.75
	hl.OutlineTransparency = 0
	hl.Parent = g
	g.Parent = workspace
	ghost = g
	ghostHitbox = g:FindFirstChild(BuildConfigs.HITBOX_NAME) :: BasePart?
	ghostHighlight = hl
	ghostSmoothPos = nil -- il apparait DIRECT sur sa case (pas de glissement depuis l'ancien fantome)
end

-- Snap au sol : on cale le bord MIN de l'empreinte sur une ligne de grille (coin + n*TILE), depuis le COIN du sol -> la
-- MEME origine que le quadrillage (le SurfaceGui tuile depuis un coin). Marche pour toute taille d'empreinte, sans parite.
local function snapToGrid(v: number, corner: number, footprintStuds: number): number
	local minEdge = v - footprintStuds * 0.5
	local snappedEdge = corner + math.round((minEdge - corner) / TILE) * TILE
	return snappedEdge + footprintStuds * 0.5
end

-- Tuile d'empreinte numero i (pool reutilise : on ne cree/detruit pas des parts chaque frame). Part plate au sol.
local function getCell(i: number): BasePart
	local p = cellParts[i]
	if not p then
		p = Instance.new("Part")
		p.Name = "LeafiaBuildCell"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Size = Vector3.new(TILE * 0.94, 0.1, TILE * 0.94) -- un petit gap entre cases (look Sims)
		p.Parent = workspace
		cellParts[i] = p
	end
	return p
end

local function clearCells()
	for _, p in ipairs(cellParts) do
		p:Destroy()
	end
	table.clear(cellParts)
end

-- Suit le curseur chaque frame : raycast sur le sol, snap, place le fantome (penche selon la vitesse), teste la validite.
local function updateGhost(dt: number)
	local g = ghost
	local hb = ghostHitbox
	local gr = ground
	if not (g and hb and gr) then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local m = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(m.X, m.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { gr }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 3000, params)
	if not result then
		return -- curseur hors du sol : on laisse le fantome ou il est
	end
	-- Vitesse LISSEE du curseur au sol (pour le lean). Lissage -> pas de saccade ; a l'arret elle retombe a zero.
	local hit = result.Position
	if prevHitPos then
		local inst = (hit - prevHitPos) / math.max(dt, 1 / 120)
		ghostVel = ghostVel:Lerp(Vector3.new(inst.X, 0, inst.Z), math.min(1, VEL_SMOOTH * dt))
	end
	prevHitPos = hit
	-- Empreinte en tuiles, apres rotation (90 / 270 echangent largeur et profondeur).
	local sizeX, sizeZ = hb.Size.X, hb.Size.Z
	if ghostRot == 90 or ghostRot == 270 then
		sizeX, sizeZ = sizeZ, sizeX
	end
	local fx = math.max(1, math.round(sizeX / TILE))
	local fz = math.max(1, math.round(sizeZ / TILE))
	-- Snap dans le repere du sol.
	local localHit = gr.CFrame:PointToObjectSpace(result.Position)
	local sx = snapToGrid(localHit.X, -gr.Size.X * 0.5, fx * TILE)
	local sz = snapToGrid(localHit.Z, -gr.Size.Z * 0.5, fz * TILE)
	-- CFrame cible du HITBOX : pose sur le dessus du sol, tourne autour de la verticale. C'est la case SNAPPEE (exacte),
	-- utilisee pour ce qu'on POSE et pour la validite -- meme quand l'AFFICHAGE glisse encore vers elle.
	local topY = gr.Size.Y * 0.5
	local targetHitboxLocal = CFrame.new(sx, topY + hb.Size.Y * 0.5, sz) * CFrame.Angles(0, math.rad(ghostRot), 0)
	local targetHitboxCF = gr.CFrame * targetHitboxLocal
	-- POSE (ce qu'on posera au clic) = pose DROITE sur la case snappee. transform = cible * hitbox actuel inverse : deplace
	-- le model pour que son hitbox atterrisse pile la, et annule au passage le lean de la frame precedente.
	ghostPivot = (targetHitboxCF * hb.CFrame:Inverse()) * g:GetPivot()

	-- AFFICHAGE : le fantome GLISSE vers la case au lieu de sauter d'un coup. On lisse la POSITION (la rotation reste
	-- snappee). A l'arret on COLLE a la cible (un lerp expo ne l'atteint jamais, cf journal). Nouveau fantome (nil) = colle direct.
	local targetPos = targetHitboxCF.Position
	if ghostSmoothPos and (ghostSmoothPos - targetPos).Magnitude > 0.01 then
		ghostSmoothPos = ghostSmoothPos:Lerp(targetPos, math.min(1, GHOST_SLIDE * dt))
	else
		ghostSmoothPos = targetPos
	end
	local displayHitboxCF = CFrame.new(ghostSmoothPos) * targetHitboxCF.Rotation
	local uprightDisplay = (displayHitboxCF * hb.CFrame:Inverse()) * g:GetPivot()

	-- LEAN : on penche le fantome dans le sens du mouvement (borne), autour de sa BASE au sol -- prise sur la position
	-- AFFICHEE (lissee), pas snappee, pour que le pivot du lean suive le glissement. A l'arret ghostVel -> 0, il se redresse.
	local displayPivot = uprightDisplay
	local speed = ghostVel.Magnitude
	if speed > 0.5 then
		local axis = ghostVel.Unit:Cross(Vector3.new(0, 1, 0)) -- ordre confirme a l'ecran (echanger le Cross pour inverser)
		if axis.Magnitude > 1e-3 then
			local angle = math.min(speed * LEAN_FACTOR, math.rad(MAX_LEAN_DEG))
			local basePos = displayHitboxCF.Position - Vector3.new(0, hb.Size.Y * 0.5, 0)
			displayPivot = CFrame.new(basePos) * CFrame.fromAxisAngle(axis.Unit, angle) * CFrame.new(-basePos) * uprightDisplay
		end
	end
	g:PivotTo(displayPivot)
	-- Validite : (1) l'empreinte tient dans les limites du sol, ET (2) la case n'est pas deja prise. Pour (2) on interroge
	-- une boite RETRECIE (0.8) a l'emplacement, filtree sur le dossier Build du plot -> ne detecte qu'un VRAI chevauchement
	-- (meme case), pas un voisin qui touche juste au bord.
	local half = gr.Size * 0.5
	local withinBounds = (math.abs(sx) + fx * TILE * 0.5 <= half.X + 0.05) and (math.abs(sz) + fz * TILE * 0.5 <= half.Z + 0.05)
	local occupied = false
	if buildFolder then
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Include
		op.FilterDescendantsInstances = { buildFolder }
		occupied = #workspace:GetPartBoundsInBox(targetHitboxCF, hb.Size * 0.8, op) > 0
	end
	ghostValid = withinBounds and not occupied
	if ghostHighlight then
		local c = if ghostValid then VALID_COLOR else INVALID_COLOR
		ghostHighlight.FillColor = c
		ghostHighlight.OutlineColor = c
	end
	-- CASES d'empreinte : une tuile verte (valide) ou rouge (prise / hors plot) par case occupee. Elles montrent au
	-- joueur OU son bloc se pose (un meuble 2x1 tuiles -> 2 cases). Repere du sol, au-dessus de la grille.
	local cellColor = if ghostValid then VALID_COLOR else INVALID_COLOR
	local minX = sx - fx * TILE * 0.5
	local minZ = sz - fz * TILE * 0.5
	local used = 0
	for ix = 0, fx - 1 do
		for iz = 0, fz - 1 do
			used += 1
			local cell = getCell(used)
			cell.CFrame = gr.CFrame * CFrame.new(minX + (ix + 0.5) * TILE, topY + 0.06, minZ + (iz + 0.5) * TILE)
			cell.Color = cellColor
			cell.Transparency = CELL_TRANSPARENCY
		end
	end
	for i = used + 1, #cellParts do
		cellParts[i].Transparency = 1 -- cases en trop (empreinte plus petite qu'avant) : cachees
	end
end

-- Effet de pose SLIME : le bloc TOMBE d'un peu au-dessus (ease-in facon gravite), puis s'ECRASE a l'impact et rebondit
-- a sa taille (ecrase vite, revient en ease-out-back = leger depassement). Le son de depose joue A L'IMPACT (le thud).
local function dropAndSquash(model: Model, finalPivot: CFrame, impactPos: Vector3)
	model:PivotTo(finalPivot * CFrame.new(0, DROP_HEIGHT, 0))
	local t = 0
	local dropping = true
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function(dt: number)
		t += math.min(dt, 1 / 30)
		if dropping then
			local a = math.min(t / DROP_TIME, 1)
			model:PivotTo(finalPivot * CFrame.new(0, DROP_HEIGHT * (1 - a * a), 0)) -- a*a : accelere en tombant
			if a >= 1 then
				model:PivotTo(finalPivot)
				BuildFx.playPlace(impactPos) -- thud + poof de fumee AU SOL, a l'impact
				dropping = false
				t = 0
			end
		else
			local a = math.min(t / SQUASH_TIME, 1)
			local s: number
			if a < 0.3 then
				s = 1 + (SQUASH_SCALE - 1) * (a / 0.3) -- 1 -> ecrase
			else
				local b = (a - 0.3) / 0.7
				local c1 = 1.70158
				local c3 = c1 + 1
				local back = 1 + c3 * (b - 1) ^ 3 + c1 * (b - 1) ^ 2
				s = SQUASH_SCALE + (1 - SQUASH_SCALE) * back -- ecrase -> 1 (overshoot = rebond)
			end
			model:ScaleTo(s)
			if a >= 1 then
				model:ScaleTo(1)
				if conn then
					conn:Disconnect()
				end
			end
		end
	end)
end

local lastBlockToast = 0 -- anti-spam de la notif rouge

local function placeItem()
	local template = models[currentIndex]
	if not (active and ground and ghost and template) then
		return -- pas en train de construire
	end
	if not ghostValid then
		-- Case prise ou hors du plot : notif ROUGE (kind Warning), avec un petit anti-spam si on clique en rafale.
		if os.clock() - lastBlockToast > 0.5 then
			lastBlockToast = os.clock()
			Toast.show("Warning", "Can't build here!")
		end
		return
	end
	local placed = template:Clone()
	placed.Name = template.Name
	placed.Parent = buildFolder or workspace -- CLIENT-only ; le serveur reprendra la main (Build folder + save) apres
	-- Position AU SOL pour le poof de fumee (le pivot du bloc peut etre a mi-hauteur) : XZ du placement, Y = dessus du sol.
	local groundTopY = (ground.CFrame * CFrame.new(0, ground.Size.Y * 0.5, 0)).Position.Y
	local impactPos = Vector3.new(ghostPivot.Position.X, groundTopY, ghostPivot.Position.Z)
	dropAndSquash(placed, ghostPivot, impactPos) -- tombe, s'ecrase, rebondit + son + fumee AU SOL a l'impact
end

-- Change de modele courant (TEMP : touches 1..9 en attendant le catalogue). Reconstruit le fantome.
function BuildPlaceController.select(index: number)
	if models[index] then
		currentIndex = index
		if active then
			makeGhost(models[index])
		end
	end
end

function BuildPlaceController.start(g: BasePart)
	if active then
		return
	end
	active = true
	ground = g
	buildFolder = g.Parent and g.Parent:FindFirstChild(BuildConfigs.BUILDS_FOLDER)
	assetsFolder = resolveByPath(BuildConfigs.BUILD_ASSETS_PATH)
	refreshModels()
	if #models == 0 then
		warn("[BuildPlace] Aucun modele sous ReplicatedStorage." .. table.concat(BuildConfigs.BUILD_ASSETS_PATH, "."))
		return
	end
	currentIndex = math.clamp(currentIndex, 1, #models)
	makeGhost(models[currentIndex])
	-- Priorite juste APRES la camera : le fantome se cale sur la camera de la frame courante.
	RunService:BindToRenderStep(FOLLOW_BIND, Enum.RenderPriority.Camera.Value + 1, updateGhost)
end

function BuildPlaceController.stop()
	if not active then
		return
	end
	active = false
	ground = nil
	buildFolder = nil
	RunService:UnbindFromRenderStep(FOLLOW_BIND)
	clearGhost()
	clearCells()
end

-- Bascule mode OBJET <-> autre (mur). Off -> on cache le fantome + les cases ; on -> on recree le fantome.
function BuildPlaceController.setEnabled(on: boolean)
	enabled = on
	if not on then
		clearGhost()
		clearCells()
	elseif active and models[currentIndex] then
		makeGhost(models[currentIndex])
	end
end

function BuildPlaceController.init()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not (active and enabled) or gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			placeItem()
		elseif input.KeyCode == Enum.KeyCode.R then
			ghostRot = (ghostRot + 90) % 360
		elseif NUM_KEYS[input.KeyCode] then
			BuildPlaceController.select(NUM_KEYS[input.KeyCode])
		end
	end)
end

return BuildPlaceController
