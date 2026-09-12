--!strict
-- Genere les zones de detection "prise d'echelle" par code, sur les deux cotes LATERAUX (gauche / droite) de
-- chaque echelle. STEP 1 : juste les deux box, VISIBLES, pour valider le placement. Les attachments + beams (le
-- marquage au sol) et l'invisibilite viendront dans les etapes suivantes.
--
-- COTE SERVEUR : les box sont ainsi repliquees, detectees et vues par tous. La detection (LadderMoveController)
-- cherche les zones par PREFIXE ZONE_BASE_NAME, donc les deux (_A / _B) comptent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LadderFoldUtils = require(ReplicatedStorage.Modules.Utils.LadderFoldUtils)

local LadderZoneService = {}

local ZONE_BASE_NAME = "box_detecte_For_Move"

-- ===== A REGLER =====
-- Emprise de la zone au sol. NOTE : la detection de PRISE n'est PLUS basee sur cette box -- elle est RADIALE cote
-- LadderMoveController (DETECT_RADIUS), sans angle mort. Cette box ne sert plus qu'au marquage au sol (Beams).
local ZONE_SIZE = Vector3.new(3, 0.2, 4)
-- Ecart LATERAL de chaque zone depuis le centre de l'echelle (axe X local = droite / gauche). Une zone a +offset
-- (droite), l'autre a -offset (gauche).
local LATERAL_OFFSET = 3
-- Box INVISIBLE : c'est une zone logique. La detection teste X/Z, l'invisibilite ne la gene pas. (Passe
-- ZONE_TRANSPARENCY a 0.5 pour re-voir le placement au besoin.)
local ZONE_COLOR = Color3.fromRGB(0, 200, 255)
local ZONE_TRANSPARENCY = 1
-- Hauteur : on raycast vers le bas pour trouver le vrai SOL et poser la zone dessus (pas de hauteur devinee).
local SURFACE_LIFT = 0.1
local RAY_UP = 10
local RAY_DOWN = 300

local function ladderRootPart(model: Model): BasePart?
	return model.PrimaryPart or (model:FindFirstChild("RootPart") :: BasePart?)
end

-- Une box de zone, cote lateral `lateralOffset` (X local de la racine), posee sur le sol, soudee a l'echelle.
local function buildZone(ladder: Model, root: BasePart, name: string, lateralOffset: number, params: RaycastParams)
	-- Point horizontal : racine decalee sur le cote (X local).
	local anchor = (root.CFrame * CFrame.new(lateralOffset, 0, 0)).Position
	-- Vrai sol sous ce point. A defaut, on retombe sur le Y de la racine.
	local origin = Vector3.new(anchor.X, root.Position.Y + RAY_UP, anchor.Z)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -RAY_DOWN, 0), params)
	local floorY = if hit then hit.Position.Y else root.Position.Y
	local pos = Vector3.new(anchor.X, floorY + SURFACE_LIFT, anchor.Z)
	-- Orientation A PLAT : yaw de la racine seulement (regard aplati).
	local flatLook = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if flatLook.Magnitude < 1e-3 then
		flatLook = Vector3.zAxis
	end

	local box = Instance.new("Part")
	box.Name = name
	box.Size = ZONE_SIZE
	box.Color = ZONE_COLOR
	box.Transparency = ZONE_TRANSPARENCY
	box.Material = Enum.Material.SmoothPlastic
	box.CanCollide = false
	box.CanQuery = false -- zone logique, ignoree par les raycasts
	box.CanTouch = false
	box.CastShadow = false
	box.Anchored = false -- fait partie de l'assemblage de l'echelle (weld ci-dessous)
	box.CFrame = CFrame.lookAt(pos, pos + flatLook)
	box.Parent = ladder

	-- Weld a la racine : la zone SUIT l'echelle (portage, repose) sans tomber. Racine ancree = box tenue.
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = box
	weld.Part1 = root
	weld.Parent = box
end

local function clearZones(ladder: Model)
	for _, child in ipairs(ladder:GetChildren()) do
		if child:IsA("BasePart") and (child.Name == ZONE_BASE_NAME .. "_A" or child.Name == ZONE_BASE_NAME .. "_B") then
			child:Destroy()
		end
	end
end

local function setupLadder(ladder: Model)
	local root = ladderRootPart(ladder)
	if not root then
		warn(`[LadderZoneService] Pas de RootPart / PrimaryPart sur {ladder.Name} : zones non generees`)
		return
	end
	-- Idempotent : on retire d'anciennes zones generees avant d'en refaire (redemarrage / re-setup).
	clearZones(ladder)
	-- Le raycast au sol doit IGNORER l'echelle (sinon il taperait dans ses propres marches).
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ladder }
	buildZone(ladder, root, ZONE_BASE_NAME .. "_A", LATERAL_OFFSET, params)
	buildZone(ladder, root, ZONE_BASE_NAME .. "_B", -LATERAL_OFFSET, params)
end

-- LE NOM DES ECHELLES VIT DANS `LadderFoldUtils`, une seule fois pour tout le jeu -- et le test ecarte aussi
-- celle qui dort dans la benne du camion : on ne pose pas de zone de grimpe sur un objet pas encore sorti.
-- LE NOM DES ECHELLES VIT DANS `LadderFoldUtils`, une seule fois pour tout le jeu -- et `isLadder` ecarte aussi
-- celle qui dort dans la benne du camion : on ne pose pas de zone de grimpe sur un objet pas encore sorti.
local function isLadderModel(inst: Instance): boolean
	return LadderFoldUtils.isLadder(inst)
end

-- CELLES QU'ON A DEJA EQUIPEES. Une echelle peut etre vue plusieurs fois (demarrage, sortie du camion, retour) et
-- lui reposer ses zones a chaque passage en empilerait des copies.
local zoned: { [Model]: boolean } = {}

--- Pose les zones si l'echelle est utilisable, et SINON attend qu'elle le devienne.
---
--- CELLE DU CAMION N'EST PAS UTILISABLE TANT QU'ELLE EST DANS LA BENNE, et quand elle en sort elle ne fait que
--- CHANGER de parent a l'interieur du Workspace. Or `DescendantAdded` ne se declenche que pour ce qui ENTRE dans
--- le Workspace : un objet qui y etait deja n'y rentre pas une seconde fois. On l'aurait donc ratee pour toujours,
--- et une echelle sans zones ne se prend ni ne se grimpe. On ecoute son ascendance A ELLE, qui, elle, bouge.
local function watchLadder(model: Model)
	if zoned[model] then
		return
	end
	if isLadderModel(model) then
		zoned[model] = true
		setupLadder(model)
		return
	end
	model.AncestryChanged:Connect(function()
		if not zoned[model] and isLadderModel(model) then
			zoned[model] = true
			task.defer(setupLadder, model)
		end
	end)
end

--- A APPELER QUAND UNE ECHELLE VIENT DE SE POSER, ou de repartir dans le camion.
---
--- LA HAUTEUR DES ZONES VIENT D'UN RAYON VERS LE SOL, donc elles ne valent que pour l'endroit ou l'echelle se
--- trouvait AU MOMENT de leur construction. Une echelle qui quitte la benne change de parent AVANT de voler : les
--- zones se posaient donc pendant qu'elle etait encore sur le camion, et elles la suivaient ensuite de travers --
--- l'echelle etait bien la, au sol, et ni la prise ni la grimpe ne la voyaient.
function LadderZoneService.refresh(ladder: Model)
	if isLadderModel(ladder) then
		setupLadder(ladder)
	else
		-- Repartie dans le camion : pas de zone de grimpe sur un objet range.
		clearZones(ladder)
	end
end

function LadderZoneService.init()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") and LadderFoldUtils.isLadderName(inst.Name) then
			watchLadder(inst :: Model)
		end
	end
	-- Echelle ajoutee apres coup (rare : elles sont posees en Studio). task.defer : laisser le model se peupler.
	Workspace.DescendantAdded:Connect(function(inst: Instance)
		if inst:IsA("Model") and LadderFoldUtils.isLadderName(inst.Name) then
			task.defer(watchLadder, inst :: Model)
		end
	end)
end

return LadderZoneService
