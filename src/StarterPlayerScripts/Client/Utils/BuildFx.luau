--!strict
-- FX de POSE partages (objet ET mur) : le son de depose + le poof de fumee. Un seul endroit -> pas de duplication.
-- On clone BuildPlaceEffect a la position AU SOL, on EMIT ses ParticleEmitters (Smoke + SmokeB), et le clone se nettoie
-- tout seul (Debris). La part porteuse est rendue invisible : on ne veut que les particules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local BuildConfigs = require(ReplicatedStorage.Modules.Configs.BuildConfigs)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)

local BuildFx = {}

local PLACE_SOUND = { "Sounds", "UI", "BuildDeposeSound_1" } -- son de "depose" (thud)

local function resolveByPath(path: { string }): Instance?
	local node: Instance? = ReplicatedStorage
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

-- Son de depose + poof de fumee a `position` (a appeler a l'instant de la pose, position AU SOL).
function BuildFx.playPlace(position: Vector3)
	SoundUtils.play(PLACE_SOUND)
	local template = resolveByPath(BuildConfigs.PLACE_EFFECT_PATH)
	if not template then
		return
	end
	local fx = template:Clone()
	if fx:IsA("BasePart") then
		fx.Anchored = true
		fx.CanCollide = false
		fx.CanQuery = false
		fx.Transparency = 1
		fx.CFrame = CFrame.new(position)
	elseif fx:IsA("Model") then
		fx:PivotTo(CFrame.new(position))
	end
	fx.Parent = workspace
	for _, d in ipairs(fx:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d:Emit(BuildConfigs.PLACE_EFFECT_EMIT)
		end
	end
	Debris:AddItem(fx, 4)
end

local BOUNCE_TIME = 0.32 -- duree du rebond
local BOUNCE_HOP = 1.0 -- studs : hauteur du petit saut
local BOUNCE_SQUISH = 0.82 -- scale mini a l'ecrasement (1 = pas d'ecrasement)
local BOUNCE_HOP_END = 0.55 -- part du temps pour le saut ; le reste = ecrasement au sol + retour

-- Rebonds en cours : instance -> fonction qui la remet AU REPOS. Sert a annuler / figer un rebond (snapBounce) AVANT de
-- lire sa geometrie ou de la detruire : sinon on lirait une pose de saut (soulevee / ecrasee) -> calculs fausses.
local activeBounces: { [Instance]: () -> () } = {}

-- Petit saut + ecrasement "slime" d'une instance (Model ou BasePart), qui REVIENT a sa pose / taille d'origine. Auto-guard :
-- s'arrete si l'instance est detruite en plein rebond (ex supprimee). A jouer PILE quand l'objet doit "reagir".
function BuildFx.slimeBounce(inst: Instance)
	local model = if inst:IsA("Model") then inst :: Model else nil
	local part = if inst:IsA("BasePart") then inst :: BasePart else nil
	if not (model or part) then
		return
	end
	local originCF = if model then model:GetPivot() else (part :: BasePart).CFrame
	local originScale = if model then model:GetScale() else 1
	local originSize = if part then (part :: BasePart).Size else Vector3.one
	-- La fonction sert AUSSI de jeton d'identite : si un nouveau rebond remplace celui-ci (ou snapBounce l'annule),
	-- activeBounces[inst] ~= rest -> cette boucle s'arrete.
	local rest
	rest = function()
		if not inst.Parent then
			return
		end
		if model then
			model:PivotTo(originCF)
			model:ScaleTo(originScale)
		else
			local pt = part :: BasePart
			pt.CFrame = originCF
			pt.Size = originSize
		end
	end
	activeBounces[inst] = rest
	task.spawn(function()
		local t0 = os.clock()
		while inst.Parent and activeBounces[inst] == rest do
			local p = (os.clock() - t0) / BOUNCE_TIME
			if p >= 1 then
				break
			end
			local hop, squish
			if p < BOUNCE_HOP_END then
				hop = BOUNCE_HOP * math.sin(math.pi * (p / BOUNCE_HOP_END)) -- monte puis retombe
				squish = 1
			else
				hop = 0
				local q = (p - BOUNCE_HOP_END) / (1 - BOUNCE_HOP_END)
				squish = 1 - (1 - BOUNCE_SQUISH) * math.sin(math.pi * q) -- ecrase au sol puis se repose
			end
			if model then
				model:PivotTo(originCF * CFrame.new(0, hop, 0))
				model:ScaleTo(originScale * squish)
			else
				local pt = part :: BasePart
				pt.CFrame = originCF * CFrame.new(0, hop, 0)
				pt.Size = originSize * squish
			end
			RunService.Heartbeat:Wait()
		end
		if activeBounces[inst] == rest then -- fini naturellement (pas annule par snapBounce ni remplace)
			rest()
			activeBounces[inst] = nil
		end
	end)
end

-- Fige immediatement le rebond d'une instance (la remet au repos) s'il y en a un. A appeler AVANT de lire sa geometrie
-- ou de la detruire, sinon on travaille sur une pose de saut fausse.
function BuildFx.snapBounce(inst: Instance)
	local rest = activeBounces[inst]
	if rest then
		activeBounces[inst] = nil -- annule : la boucle du rebond verra son jeton disparaitre et s'arretera
		rest()
	end
end

return BuildFx
