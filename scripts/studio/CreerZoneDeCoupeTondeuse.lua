-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO (pas dans le jeu, pas dans src/).
--
-- Cree la part "CutZone" sous le carter de la tondeuse : c'est ELLE qui dit ou l'herbe est coupee.
-- MowController lira sa POSITION et son rayon (moitie de sa largeur). Rien n'est pose a l'oeil : tout est calcule
-- depuis la geometrie reelle du modele, y compris le sens de l'AVANT.
--
-- Relancer le script REMPLACE proprement la zone existante : on peut le rejouer autant de fois qu'on veut.
--
-- L'AVANT est deduit du Handle (le guidon est DERRIERE, le carter DEVANT). Si la zone atterrit du mauvais cote,
-- passer FLIP a true et relancer -- ne pas la deplacer a la main, sinon le prochain lancement l'ecrasera.

local MODEL_NAME = "Tondeuse"
local ZONE_NAME = "CutZone"

local FLIP = false -- l'avant tombe du mauvais cote ? mettre true et relancer
local VISIBLE = true -- true = zone bien visible pour verifier ; repasser a false une fois valide
local HEIGHT = 0.4 -- epaisseur de la zone (studs). Plate : elle ne sert qu'a donner un point et un rayon
local WIDTH_SCALE = 1.0 -- largeur de coupe = largeur du modele x ceci. A REGLER a l'oeil sur la vraie largeur du carter
local FORWARD_PUSH = 0.0 -- avance la zone vers l'avant (studs). 0 = collee au bord avant du carter

local model = workspace:FindFirstChild(MODEL_NAME)
if not model or not model:IsA("Model") then
	warn(`[CutZone] Modele "{MODEL_NAME}" introuvable a la racine du Workspace.`)
	return
end

local root = model.PrimaryPart
if not root then
	-- Sans PrimaryPart, GetBoundingBox suit la bounding box et tout le calcul partirait de travers.
	warn(`[CutZone] "{MODEL_NAME}" n'a pas de PrimaryPart. Le regler sur RootPart avant de relancer.`)
	return
end

local handle = model:FindFirstChild("Handle", true)
if not (handle and handle:IsA("BasePart")) then
	warn("[CutZone] Part 'Handle' introuvable : impossible de deduire l'avant. Poser FLIP a la main si besoin.")
end

-- Boite du modele, ALIGNEE sur la PrimaryPart : ses axes sont donc ceux de la tondeuse, pas ceux du monde.
local boxCF, boxSize = model:GetBoundingBox()

-- QUEL AXE EST L'AVANT ? Le guidon est a l'arriere. On regarde ou tombe le Handle dans le repere de la boite :
-- l'axe horizontal ou il s'ecarte le plus est l'axe LONG de la tondeuse, et l'avant est du cote OPPOSE au guidon.
local axis, sign = "Z", 1
if handle and handle:IsA("BasePart") then
	local local_ = boxCF:PointToObjectSpace(handle.Position)
	if math.abs(local_.X) > math.abs(local_.Z) then
		axis = "X"
		sign = if local_.X > 0 then -1 else 1
	else
		axis = "Z"
		sign = if local_.Z > 0 then -1 else 1
	end
end
if FLIP then
	sign = -sign
end

-- Longueur = le cote de la boite le long de l'axe d'avancee ; largeur = l'autre cote horizontal.
local along = if axis == "X" then boxSize.X else boxSize.Z
local across = if axis == "X" then boxSize.Z else boxSize.X
local width = across * WIDTH_SCALE

-- Position : bord AVANT du carter, au niveau du SOL (bas de la boite). La zone est plate et centree en largeur.
local forwardOffset = along * 0.5 + FORWARD_PUSH - width * 0.5
local offset = if axis == "X"
	then Vector3.new(sign * forwardOffset, -boxSize.Y * 0.5 + HEIGHT * 0.5, 0)
	else Vector3.new(0, -boxSize.Y * 0.5 + HEIGHT * 0.5, sign * forwardOffset)

local old = model:FindFirstChild(ZONE_NAME, true)
if old then
	old:Destroy()
end

local zone = Instance.new("Part")
zone.Name = ZONE_NAME
zone.Size = Vector3.new(width, HEIGHT, width) -- carree : MowController prend la MOITIE de X comme rayon de coupe
zone.CFrame = boxCF * CFrame.new(offset)
zone.Anchored = false -- c'est le weld qui la tient, pas l'ancrage : sinon elle resterait sur place au portage
zone.CanCollide = false
zone.CanTouch = false -- on ne passe PAS par Touched : la coupe se fait par distance, c'est plus fiable et moins cher
zone.CanQuery = false -- n'a d'effet QUE parce que CanCollide est faux
zone.Massless = true -- ne doit rien changer a la physique de la tondeuse
zone.Transparency = if VISIBLE then 0.55 else 1
zone.Color = Color3.fromRGB(255, 90, 90)
zone.Material = Enum.Material.Neon
zone.Parent = model

local weld = Instance.new("WeldConstraint")
weld.Part0 = root
weld.Part1 = zone
weld.Parent = zone

print(
	`[CutZone] Creee sous {model:GetFullName()} | axe d'avancee {axis} sens {sign} | largeur de coupe {string.format("%.2f", width)} studs`
)
print(`[CutZone] Rayon que MowController utilisera : {string.format("%.2f", width / 2)} studs`)
print("[CutZone] Mauvais cote ? passer FLIP a true et relancer. Une fois valide : VISIBLE a false, relancer.")
