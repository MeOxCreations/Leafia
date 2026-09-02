--!strict
-- GUIDE AU SOL : un repere pose AUX PIEDS DU JOUEUR, qui pointe vers un endroit du monde. Il dit "c'est par la"
-- sans jamais rien ecrire, et il suit le joueur partout.
--
-- POURQUOI PAS UNE FLECHE, ni un trait entre les deux. Une fleche posee dans le monde se lit mal des qu'on tourne
-- la camera : vue de face elle disparait, vue de dessus elle ment sur la distance. Un trait (Beam) entre le joueur
-- et la cible traverse les murs et le decor, et il faut deux Attachments a tenir a jour de chaque cote.
--
-- Un repere PLAT, centre sur le joueur, n'a aucun de ces problemes : il est toujours dans le cadre, il ne depend
-- d'aucun objet, et il tourne avec le MONDE -- donc il continue de designer la bonne direction quel que soit
-- l'angle de vue.
--
-- LE MESH EST CELUI DE LA TONDEUSE (`MarkerDirection`, un demi-cercle avec une fleche a l'avant). Reutilise
-- expres : le joueur a deja appris ce que ce dessin veut dire en conduisant, et un deuxieme dessin pour la meme
-- idee est un deuxieme apprentissage pour rien.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GroundGuide = {}

local player = Players.LocalPlayer

-- ===== OU EST LE MESH =====
-- Chemin sous `ReplicatedStorage.Assets`. Le mesh vit dans Studio et Rojo ne synchronise pas les Assets : on le
-- retrouve par son chemin plutot que de le decrire en code.
--
-- SON PROPRE CHEMIN, meme si c'est aujourd'hui le meme mesh que le marqueur de la tondeuse. Les deux usages n'ont
-- rien a voir -- l'un montre un braquage, l'autre une direction a prendre -- et le jour ou l'un des deux change de
-- dessin, l'autre ne doit pas suivre.
local ASSET_PATH = { "Contents", "MarkerDirection" }

-- ===== REGLAGES A L'OEIL =====
-- TAILLE, en multiple du mesh d'origine. Posee UNE FOIS a la creation : un mesh qu'on redimensionne en jeu
-- CLIGNOTE si sa RenderFidelity est `Automatic` (Roblox echange le maillage selon la taille a l'ecran).
local SCALE = 2.2
-- ORIENTATION du mesh, en degres autour de la verticale. Le sens ne se DEDUIT pas : il depend de la facon dont le
-- mesh a ete modelise. Ca se voit a l'ecran, et c'est la seule facon de le savoir. 180 = demi-tour.
local YAW = 180
-- HAUTEUR sous le centre du joueur, en studs. La HumanoidRootPart d'un R15 flotte a peu pres trois studs au-dessus
-- du sol : on redescend d'autant pour poser le repere a ses pieds.
--
-- LEGEREMENT AU-DESSUS DU SOL, jamais dedans : pile au ras, le repere clignote contre le terrain (z-fighting).
local HEIGHT = -2.85
-- Le repere apparait et disparait en fondu. D'un coup, il attire l'oeil sur son apparition au lieu de la
-- direction qu'il montre.
local FADE_TIME = 0.3
-- Transparence quand il est visible. Pas zero : c'est une AIDE posee sur le decor, pas un objet du monde.
local SHOWN_TRANSPARENCY = 0.15
-- SOUS CETTE DISTANCE, il n'a plus rien a dire : le joueur est arrive, il voit la machine. Le laisser tourner sous
-- ses pieds ferait une girouette.
local ARRIVE_DIST = 14
-- Et sous CETTE distance-la, la direction n'a plus de sens (bruit) : on garde le dernier cap au lieu de faire
-- pivoter le repere au hasard. Meme raison que BODY_MIN_SPEED chez les papillons.
local MIN_AIM_DIST = 1.5

local guide: BasePart? = nil
local shown = false
local warned = false
local fadeTween: Tween? = nil
-- Dernier cap valable, en direction UNITAIRE horizontale. Garde quand la cible est trop proche pour donner un sens.
local lastDir: Vector3? = nil

local function asset(): BasePart?
	local node: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, step in ASSET_PATH do
		node = node and node:FindFirstChild(step)
	end
	if node and node:IsA("BasePart") then
		return node
	end
	-- UNE SEULE FOIS. Repete par image, ce message noierait la console -- et un avertissement qui defile est un
	-- avertissement qu'on n'ecoute plus.
	if not warned then
		warned = true
		warn(
			`[GroundGuide] Mesh introuvable : ReplicatedStorage.Assets.{table.concat(ASSET_PATH, ".")}. `
				.. "Rojo ne synchronise pas les Assets : il doit exister dans CETTE place."
		)
	end
	return nil
end

local function ensure(): BasePart?
	local existing = guide
	if existing and existing.Parent then
		return existing
	end
	local source = asset()
	if not source then
		return nil
	end
	local clone = source:Clone()
	clone.Name = "LeafiaGroundGuide"
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanTouch = false
	-- `CanQuery` n'a d'effet QUE parce que CanCollide est faux. Sans ca, les raycasts de la coupe verraient ce
	-- decor et croiraient a un obstacle -- et le joueur tondrait autour d'un guide invisible aux collisions.
	clone.CanQuery = false
	clone.CastShadow = false
	clone.Size = source.Size * SCALE
	-- IL NAIT INVISIBLE : la premiere image le pose a sa place, le fondu le revele ensuite. Cree visible, il
	-- apparaitrait une image a l'origine de la map avant de sauter aux pieds du joueur.
	clone.Transparency = 1
	clone.Parent = Workspace
	guide = clone
	shown = false
	return clone
end

local function fadeTo(part: BasePart, value: number)
	if fadeTween then
		fadeTween:Cancel()
	end
	local tween = TweenService:Create(part, TweenInfo.new(FADE_TIME), { Transparency = value })
	fadeTween = tween
	tween:Play()
end

--- Montre le repere aux pieds du joueur, oriente vers `target`. A appeler A CHAQUE IMAGE tant que le guidage a
--- lieu d'etre : il suit le joueur, et sa direction change quand celui-ci se deplace.
---
--- Il se cache TOUT SEUL une fois la cible atteinte (`ARRIVE_DIST`) : l'appelant n'a pas a mesurer la distance de
--- son cote, et il ne peut donc pas y mettre un seuil different de celui qui pilote l'affichage.
function GroundGuide.point(target: Vector3)
	local character = player.Character
	local rootChild = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not (rootChild and rootChild:IsA("BasePart")) then
		GroundGuide.hide()
		return
	end
	local root = rootChild :: BasePart
	local from = root.Position + Vector3.new(0, HEIGHT, 0)

	-- A PLAT. On ecrase la difference de hauteur AVANT de viser : sans ca le repere se penche des que la cible
	-- n'est pas au meme niveau, et un repere au sol penche rentre dans le sol d'un cote.
	local flat = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
	if flat.Magnitude <= ARRIVE_DIST then
		GroundGuide.hide()
		return
	end

	local part = ensure()
	if not part then
		return
	end

	local dir = lastDir or Vector3.new(0, 0, -1)
	if flat.Magnitude >= MIN_AIM_DIST then
		dir = flat.Unit
		lastDir = dir
	end
	-- `lookAt` rend un repere dont le -Z pointe la cible, avec la verticale du monde pour haut. La correction du
	-- mesh vient EN DERNIER : posee avant, elle ferait tourner la visee avec elle.
	part.CFrame = CFrame.lookAt(from, from + dir) * CFrame.Angles(0, math.rad(YAW), 0)

	if not shown then
		shown = true
		fadeTo(part, SHOWN_TRANSPARENCY)
	end
end

--- Range le repere. Idempotent : appele a chaque image quand il n'y a rien a montrer, il ne relance rien.
function GroundGuide.hide()
	local part = guide
	if not (part and part.Parent and shown) then
		return
	end
	shown = false
	fadeTo(part, 1)
end

--- Detruit tout. Celui qui cree est celui qui nettoie.
function GroundGuide.destroy()
	if fadeTween then
		fadeTween:Cancel()
		fadeTween = nil
	end
	if guide then
		guide:Destroy()
		guide = nil
	end
	shown = false
	lastDir = nil
end

return GroundGuide
