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

local function rootOf(model: Model): BasePart?
	return model.PrimaryPart or (model:FindFirstChild("RootPart") :: BasePart?)
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
