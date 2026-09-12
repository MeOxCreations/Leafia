--!strict
-- L'ECHELLE SE PLIE ET SE DEPLIE. UNE SEULE anim pour les deux sens, et UN SEUL proprietaire : ce module.
--
-- `ActionLadderAnimation` raconte tout le geste d'un bloc : 0 -> `FermerEvenement` la referme, puis
-- `FermerEvenement` -> `LadderOpenEndEvent` la rouvre. On ne joue donc jamais "une anim de repli" et "une anim de
-- depli" : on avance dans la MEME piste et on la FIGE (vitesse 0) au marqueur du milieu. C'est ce qui permet de
-- tenir la pose repliee aussi longtemps qu'on veut.
--
-- POURQUOI UN MODULE ET PAS UNE FONCTION DANS CHAQUE SERVICE. Deux endroits la replient maintenant : le portage
-- (on la ferme pour marcher avec) et le camion (elle est rangee fermee dans la benne). Deux pistes chargees sur le
-- MEME Animator joueraient EN MEME TEMPS -- a priorite egale Roblox ne choisit pas, il MELANGE -- et on aurait une
-- echelle a moitie ouverte que personne n'a demandee. Une seule piste par echelle, gardee ici, rend ca impossible.
--
-- COTE SERVEUR UNIQUEMENT. Une anim jouee par un client sur l'echelle ne se replique PAS aux autres : ce n'est pas
-- son personnage. Jouee par le serveur, elle part a tout le monde.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local LadderFoldUtils = {}

-- LE NOM DES ECHELLES DANS LA CARTE. C'est un PREFIXE : plusieurs echelles peuvent coexister, numerotees.
LadderFoldUtils.PREFIX = "Escabaut"
-- REPLIEE OU NON, lu par le client (il coupe la grimpe sur une echelle fermee).
LadderFoldUtils.CLOSED_ATTRIBUTE = "LeafiaLadderClosed"

local ANIM_FOLDER = { "Animations", "Tools", "Ladder", "ModelAnimate" }
local MODEL_ANIM = "ActionLadderAnimation"
local CLOSE_EVENT = "FermerEvenement" -- repliee : on fige la
local OPEN_EVENT = "LadderOpenEndEvent" -- depliee (fin) : on lache

-- UNE PISTE PAR ECHELLE, et les marqueurs branches une seule fois. Rebrancher a chaque repli empilerait les
-- connexions : au dixieme, dix fonctions se declencheraient sur le meme marqueur.
local tracks: { [Model]: AnimationTrack } = {}
local wired: { [Model]: boolean } = {}

function LadderFoldUtils.isLadder(inst: unknown): boolean
	if typeof(inst) ~= "Instance" then
		return false
	end
	local instance = inst :: Instance
	return instance:IsA("Model") and instance.Name:sub(1, #LadderFoldUtils.PREFIX) == LadderFoldUtils.PREFIX
end

--- PLIABLE : soit elle porte le nom des echelles de la carte, soit elle en a la FORME.
---
--- LE NOM RESTE LA REGLE, mais une copie rangee a la main dans une benne s'appelle ce qu'on veut, et une regle qui
--- ne marche que si un nom a ete bien tape n'en est pas une. Le secours ne peut pas se tromper de cible : dans une
--- benne, les outils sont des meshes, et le seul modele a porter un `Humanoid` est un RIG -- c'est justement ce
--- qui lui permet de se plier.
function LadderFoldUtils.isFoldable(inst: unknown): boolean
	if typeof(inst) ~= "Instance" or not (inst :: Instance):IsA("Model") then
		return false
	end
	local model = inst :: Model
	return LadderFoldUtils.isLadder(model) or model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function resolveAnim(): Animation?
	local node: Instance = ReplicatedStorage
	for _, step in ANIM_FOLDER do
		local child = node:FindFirstChild(step)
		if not child then
			return nil
		end
		node = child
	end
	local anim = node:FindFirstChild(MODEL_ANIM)
	return if anim and anim:IsA("Animation") then anim else nil
end

--- YIELD. A appeler dans une tache a part, au demarrage du serveur.
---
--- Sans ca, le PREMIER repli de la session trouve l'asset pas encore charge : ses marqueurs ne tirent pas, la
--- piste va jusqu'au bout, et l'echelle finit DEPLIEE alors qu'on venait de la fermer.
function LadderFoldUtils.preload()
	local anim = resolveAnim()
	if not anim then
		warn(`[LadderFold] Animation "{MODEL_ANIM}" introuvable : l'echelle ne se pliera jamais.`)
		return
	end
	pcall(function()
		ContentProvider:PreloadAsync({ anim :: Animation })
	end)
end

--- LA RACINE DU RIG : la part que tout le reste suit.
---
--- ON NE SE FIE PAS A `PrimaryPart`, QUI EST FACULTATIF. Un modele sorti du 3D Importer n'en a normalement pas, et
--- une copie posee a la main dans une benne encore moins. Une sonde dont le repere est une propriete facultative
--- accuse tout le monde le jour ou elle est vide -- ici elle aurait renonce en silence, et l'echelle serait restee
--- grande ouverte sans que rien n'explique pourquoi.
---
--- LE VRAI CRITERE EST DANS LES JOINTS : la racine est la part qu'un Motor6D TIRE (elle est `Part0`) sans que
--- personne ne la tire elle-meme (elle n'est jamais `Part1`). Ca ne suppose ni nom, ni rangement, ni reglage.
local function rootOf(model: Model): BasePart?
	local named = model.PrimaryPart or (model:FindFirstChild("RootPart") :: BasePart?)
	if named then
		return named
	end
	local driven: { [BasePart]: boolean } = {}
	local drivers: { [BasePart]: boolean } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			local joint = d :: Motor6D
			if joint.Part0 then
				drivers[joint.Part0 :: BasePart] = true
			end
			if joint.Part1 then
				driven[joint.Part1 :: BasePart] = true
			end
		end
	end
	for part in drivers do
		if not driven[part] then
			return part
		end
	end
	return nil
end

--- RACINE ANCREE, LE RESTE LIBRE. Une part ANCREE ignore son Motor6D quoi qu'on ecrive dedans : une echelle dont
--- tous les morceaux sont ancres ne bougera pas d'un millimetre, sans la moindre erreur. Et l'inverse tombe --
--- racine libre = l'echelle s'ecroule. Il faut donc exactement ce partage, et il doit etre REPOSE a chaque fois :
--- le vol depuis le camion ancre TOUT pour que rien ne tombe en route.
function LadderFoldUtils.freeJoints(model: Model)
	local root = rootOf(model)
	if not root then
		warn(`[LadderFold] Ni PrimaryPart ni RootPart sur "{model.Name}" : je ne touche a rien, elle tomberait.`)
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local part = d :: BasePart
			part.Anchored = part == root
		end
	end
end

local function animatorOf(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

--- La piste de CETTE echelle, chargee au besoin. `LoadAnimation` ne DEMARRE rien : la preparer d'avance ne peut
--- rien melanger, et ca evite que le premier geste attende le reseau.
function LadderFoldUtils.track(model: Model): AnimationTrack?
	local existing = tracks[model]
	if existing then
		return existing
	end
	local anim = resolveAnim()
	local animator = animatorOf(model)
	if not (anim and animator) then
		warn(
			`[LadderFold] "{model.Name}" ne peut pas s'animer : `
				.. `{if anim then "aucun Humanoid dans le modele" else "animation introuvable"}.`
		)
		return nil
	end
	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(anim :: Animation)
	end)
	if not (ok and typeof(result) == "Instance") then
		warn(`[LadderFold] Chargement de l'anim rate pour "{model.Name}".`)
		return nil
	end
	local loaded = result :: AnimationTrack
	loaded.Looped = false
	tracks[model] = loaded
	model.Destroying:Once(function()
		tracks[model] = nil
		wired[model] = nil
	end)
	return loaded
end

local function wire(model: Model, loaded: AnimationTrack)
	if wired[model] then
		return
	end
	wired[model] = true
	loaded:GetMarkerReachedSignal(CLOSE_EVENT):Connect(function()
		loaded:AdjustSpeed(0) -- fige repliee, aussi longtemps qu'il faudra
		model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, true)
	end)
	loaded:GetMarkerReachedSignal(OPEN_EVENT):Connect(function()
		loaded:Stop(0.1)
		model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, false)
	end)
end

--- CE QUE LE MODULE VOIT DE CE MODELE. A afficher quand un repli ne donne rien : une sonde qui dit seulement
--- "ca n'a pas marche" ne designe personne, celle-ci nomme la piece qui manque.
function LadderFoldUtils.describe(model: Model): string
	local root = rootOf(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local joints = 0
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			joints += 1
		end
	end
	return `racine={if root then root.Name else "AUCUNE"} Humanoid={if humanoid then "oui" else "NON"} `
		.. `Motor6D={joints} piste={if tracks[model] then "chargee" else "AUCUNE"} `
		.. `anim={if resolveAnim() then "trouvee" else "INTROUVABLE"}`
end

--- REPLI : 0 -> `FermerEvenement`, puis on fige. Sans effet si elle est deja fermee ou en train de se fermer.
function LadderFoldUtils.fold(model: Model): boolean
	local loaded = LadderFoldUtils.track(model)
	if not loaded then
		return false
	end
	wire(model, loaded)
	if loaded.IsPlaying then
		return true -- deja repliee (figee au marqueur) ou en route : on ne repart pas de zero
	end
	LadderFoldUtils.freeJoints(model)
	loaded:Play(0)
	loaded.TimePosition = 0
	loaded:AdjustSpeed(1)
	return true
end

--- DEPLI : on REPART de la ou on avait fige, vers `LadderOpenEndEvent`. C'est la suite du meme geste, pas une
--- seconde animation -- d'ou l'absence de tout `Play` ici.
function LadderFoldUtils.unfold(model: Model)
	local loaded = tracks[model]
	if not (loaded and loaded.IsPlaying) then
		model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, false)
		return
	end
	LadderFoldUtils.freeJoints(model)
	loaded:AdjustSpeed(1)
end

--- COUPE SEC, sans depli : mort, respawn, depart du porteur. L'echelle reste dans la pose ou elle est.
function LadderFoldUtils.stop(model: Model)
	local loaded = tracks[model]
	if loaded then
		loaded:Stop(0)
	end
	model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, false)
end

return LadderFoldUtils
