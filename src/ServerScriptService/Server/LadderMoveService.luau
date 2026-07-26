--!strict
-- Autorite SERVEUR sur l'echelle en portage, par WELD. A la PRISE, on desancre l'echelle et on SOUDE sa part racine
-- au HumanoidRootPart du porteur : l'echelle devient solidaire du perso, elle le suit toute seule et se replique
-- NATIVEMENT a tous (le perso se replique deja). Pas de propriete reseau, pas de suivi serveur en continu : le weld
-- fait tout, et il TIENT l'echelle (pas de chute possible). A la REPOSE, on retire le weld et on re-ancre sur place.
--
-- On MEMORISE l'etat d'origine de chaque part (Anchored, CanCollide) et du Humanoid de l'echelle, pour le restaurer
-- exactement a la repose. Le weld cree ici est detruit a la repose.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

-- Meme prefixe que les controllers : les modeles d'echelle s'appellent Escabaut_xxx.
local LADDER_PREFIX = "Escabaut"
-- Distance MAX joueur <-> echelle a la prise (studs). Anti-triche : pas de prise a distance.
local MAX_DIST = 30

local LadderMoveService = {}

type PartState = { anchored: boolean, canCollide: boolean }
type CarryState = {
	owner: Player,
	parts: { [BasePart]: PartState },
	humanoid: Humanoid?,
	platformStand: boolean,
	weld: Weld?,
}
-- Echelles actuellement portees. nil = posee (etat normal, ancree).
local carried: { [Model]: CarryState } = {}

-- Vraie echelle ? Un Model DANS le workspace, dont le nom porte le prefixe. On refuse tout le reste (le client ment).
local function isLadder(inst: unknown): boolean
	if typeof(inst) ~= "Instance" then
		return false
	end
	local instance = inst :: Instance
	return instance:IsA("Model")
		and instance:IsDescendantOf(workspace)
		and instance.Name:sub(1, #LADDER_PREFIX) == LADDER_PREFIX
end

local function ladderRootPart(model: Model): BasePart?
	return model.PrimaryPart or (model:FindFirstChild("RootPart") :: BasePart?)
end

-- PRISE : on desancre l'echelle et on SOUDE sa racine au HRP du porteur (offset = c0, calcule cote client pour la
-- placer devant le joueur). Elle suit alors le perso, repliquee a tous, sans jamais tomber (tenue par le weld).
local function grab(player: Player, model: Model, c0: CFrame?)
	if carried[model] then
		return -- deja portee
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end
	if (model:GetPivot().Position - hrp.Position).Magnitude > MAX_DIST then
		return -- pas a portee : prise refusee
	end
	local root = ladderRootPart(model)
	if not root then
		warn(`[LadderMoveService] Pas de RootPart / PrimaryPart sur {model.Name} : soudure impossible`)
		return
	end

	local state: CarryState = { owner = player, parts = {}, humanoid = nil, platformStand = false, weld = nil }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			state.parts[d] = { anchored = d.Anchored, canCollide = d.CanCollide }
			d.Anchored = false -- une part ancree ignore le weld : il faut desancrer pour qu'elle suive
			d.CanCollide = false -- pas de collision joueur / haie / sol pendant le portage
		elseif d:IsA("Humanoid") then
			state.humanoid = d
			state.platformStand = d.PlatformStand
			d.PlatformStand = true -- le Humanoid de l'echelle ne pilote plus rien : c'est le weld qui la porte
			pcall(function()
				d:ChangeState(Enum.HumanoidStateType.Physics)
			end)
		end
	end

	local weld = Instance.new("Weld")
	weld.Part0 = hrp
	weld.Part1 = root
	if typeof(c0) == "CFrame" then
		weld.C0 = c0 -- offset : racine de l'echelle = HRP.CFrame * c0 (devant le joueur, face a la haie)
	end
	weld.Parent = root
	state.weld = weld
	carried[model] = state
end

-- REPOSE : on retire le weld et on re-ancre l'echelle exactement ou elle est (position soudee courante).
local function release(player: Player, model: Model)
	local state = carried[model]
	if not state or state.owner ~= player then
		return -- pas portee, ou pas par ce joueur (anti-grief)
	end
	local pivot = model:GetPivot() -- position ACTUELLE (soudee) : c'est la qu'on la fige

	if state.weld then
		state.weld:Destroy()
	end
	-- Coupe la vitesse residuelle avant de figer (ceinture + bretelles ; l'ancrage l'annule aussi).
	for part in pairs(state.parts) do
		if part.Parent then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	for part, saved in pairs(state.parts) do
		if part.Parent then
			part.Anchored = saved.anchored
			part.CanCollide = saved.canCollide
		end
	end
	if state.humanoid then
		state.humanoid.PlatformStand = state.platformStand
	end
	carried[model] = nil

	model:PivotTo(pivot) -- fige exactement a la derniere position soudee
end

local function onCarry(player: Player, ladder: unknown, carrying: unknown, c0: unknown)
	if not isLadder(ladder) or typeof(carrying) ~= "boolean" then
		return
	end
	local model = ladder :: Model
	if carrying then
		grab(player, model, if typeof(c0) == "CFrame" then c0 :: CFrame else nil)
	else
		release(player, model)
	end
end

function LadderMoveService.init()
	local remote = RemoteSetup.getRemote("SetLadderCarry", "Ladder")
	if remote and remote:IsA("RemoteEvent") then
		remote.OnServerEvent:Connect(onCarry)
	else
		warn("[LadderMoveService] Remote Ladder/SetLadderCarry introuvable : le portage co-op ne marchera pas")
	end

	-- Filet : si un porteur quitte le serveur en plein portage, on libere ses echelles (retire le weld + re-ancre).
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		for model, state in pairs(carried) do
			if state.owner == player then
				release(player, model)
			end
		end
	end)
end

return LadderMoveService
