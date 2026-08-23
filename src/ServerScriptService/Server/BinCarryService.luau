--!strict
-- Autorite SERVEUR sur le SEAU porte. PORTAGE par MOTOR6D : a la prise on desancre le seau et on soude sa
-- racine a une part du personnage (BinConfigs.JOINT_PARENT) -> il suit le porteur et sa POSITION se replique
-- nativement a tous, sans flot de remotes et sans jamais tomber. A la repose, on retire le joint et on le pose
-- AU SOL.
--
-- POURQUOI LE SOL EST CALCULE ICI. Le seau est porte DEVANT LE TORSE, donc en l'air. Le re-ancrer sur place
-- (ce que fait l'echelle, qui est portee au ras du sol) le laisserait FLOTTER a hauteur de poitrine. On lance
-- donc un rayon vers le bas devant le joueur, et on descend le seau jusqu'a ce que son point le plus bas
-- touche. Cote serveur, parce que c'est la position finale de l'objet : le client ne fait que demander.
--
-- On memorise l'etat d'origine de chaque part (Anchored, CanCollide, Massless) pour le restaurer a la repose.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local BinConfigs = require(ReplicatedStorage.Modules.Configs.BinConfigs)

local BinCarryService = {}

type PartState = { anchored: boolean, canCollide: boolean, massless: boolean }
type CarryState = {
	owner: Player,
	parts: { [BasePart]: PartState },
	joint: Motor6D?,
	highlight: Highlight?,
	highlightWasOn: boolean,
}

local carried: { [Model]: CarryState } = {}

local function isBin(inst: unknown): Model?
	if typeof(inst) ~= "Instance" then
		return nil
	end
	local instance = inst :: Instance
	if
		instance:IsA("Model")
		and instance:IsDescendantOf(workspace)
		and instance.Name:sub(1, #BinConfigs.MODEL_PREFIX) == BinConfigs.MODEL_PREFIX
	then
		return instance
	end
	return nil
end

-- Reference FIXE du seau. Jamais GetPivot : il suit la bounding box, qu'un enfant ajoute decale sans prevenir.
local function binRoot(model: Model): BasePart?
	local root = model.PrimaryPart or model:FindFirstChild(BinConfigs.ROOT_NAME)
	return if root and root:IsA("BasePart") then root else nil
end

-- Point le plus BAS du model, en tenant compte de l'orientation de chaque part : la demi-hauteur reelle d'une
-- part tournee est la projection de ses trois axes sur la verticale. Une simple moitie de Size.Y serait fausse
-- des que le seau est pose de biais.
local function lowestY(model: Model): number
	local lowest = math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, size = d.CFrame, d.Size
			local half = (
				math.abs(cf.UpVector.Y) * size.Y
				+ math.abs(cf.RightVector.Y) * size.X
				+ math.abs(cf.LookVector.Y) * size.Z
			) * 0.5
			lowest = math.min(lowest, cf.Position.Y - half)
		end
	end
	return lowest
end

-- Sol sous un point. Rend nil si on ne touche rien : l'appelant decide du repli, ce module ne devine pas.
local function groundAt(position: Vector3, ignore: { Instance }): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local origin = position + Vector3.new(0, BinConfigs.PLACE_RAY_HEIGHT, 0)
	local length = BinConfigs.PLACE_RAY_HEIGHT + BinConfigs.PLACE_RAY_DEPTH
	local result = workspace:Raycast(origin, Vector3.new(0, -length, 0), params)
	return if result then result.Position.Y else nil
end

-- Retire le joint et rend au seau son etat d'origine. Les vitesses sont remises a zero AVANT de re-ancrer :
-- une part relachee garde son elan et partirait en glissade au moment ou on la libere.
local function detach(state: CarryState)
	if state.joint then
		state.joint:Destroy()
		state.joint = nil
	end
	for part in pairs(state.parts) do
		if part.Parent then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function restore(state: CarryState)
	for part, saved in pairs(state.parts) do
		if part.Parent then
			part.Anchored = saved.anchored
			part.CanCollide = saved.canCollide
			part.Massless = saved.massless
		end
	end
	if state.highlight and state.highlight.Parent then
		state.highlight.Enabled = state.highlightWasOn
	end
end

-- PRISE : desancre + soude la racine du seau a JOINT_PARENT du porteur, avec le C0 mesure sur le rig.
local function grab(player: Player, model: Model)
	if carried[model] then
		return -- deja porte (par nous ou par un autre)
	end
	local character = player.Character
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local anchorPart = character:FindFirstChild(BinConfigs.JOINT_PARENT)
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end
	if not (anchorPart and anchorPart:IsA("BasePart")) then
		warn(`[BinCarryService] "{BinConfigs.JOINT_PARENT}" absent de {player.Name} : rig R6 au lieu de R15 ?`)
		return
	end
	local root = binRoot(model)
	if not root then
		warn(`[BinCarryService] Pas de PrimaryPart ni de {BinConfigs.ROOT_NAME} sur {model.Name} : soudure impossible`)
		return
	end
	if (root.Position - hrp.Position).Magnitude > BinConfigs.MAX_DIST then
		return -- anti-triche : trop loin pour etre ramasse
	end

	local state: CarryState = {
		owner = player,
		parts = {},
		joint = nil,
		highlight = nil,
		highlightWasOn = false,
	}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			state.parts[d] = { anchored = d.Anchored, canCollide = d.CanCollide, massless = d.Massless }
			d.Anchored = false
			-- Un objet tenu ne doit ni bousculer son porteur ni l'alourdir : sans ca le perso se coince dans le
			-- decor et se met a sauter tout seul.
			d.CanCollide = false
			d.Massless = true
		elseif d:IsA("Highlight") and not state.highlight then
			state.highlight = d
			state.highlightWasOn = d.Enabled
		end
	end
	-- Le Highlight sert a REPERER le seau au sol. Le laisser allume le ferait briller pendant tout le portage.
	if BinConfigs.HIDE_HIGHLIGHT_WHEN_CARRIED and state.highlight then
		state.highlight.Enabled = false
	end

	local joint = Instance.new("Motor6D")
	joint.Name = BinConfigs.JOINT_NAME
	joint.Part0 = anchorPart
	joint.Part1 = root
	joint.C0 = BinConfigs.CARRY_C0
	joint.Parent = anchorPart
	state.joint = joint

	carried[model] = state
	model:SetAttribute(BinConfigs.CARRIED_ATTRIBUTE, player.UserId)
	character:SetAttribute(BinConfigs.CARRYING_ATTRIBUTE, true)
end

-- REPOSE : on detache, on oriente sur le YAW du joueur (jamais son tangage, sinon le seau se pose penche) et
-- on le descend jusqu'au sol.
local function place(player: Player, model: Model)
	local state = carried[model]
	if not state or state.owner ~= player then
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")

	detach(state)
	carried[model] = nil
	model:SetAttribute(BinConfigs.CARRIED_ATTRIBUTE, nil)
	if character then
		character:SetAttribute(BinConfigs.CARRYING_ATTRIBUTE, nil)
	end

	if hrp and hrp:IsA("BasePart") then
		local look = hrp.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		local spot = hrp.Position + flat * BinConfigs.PLACE_DISTANCE

		local ignore: { Instance } = { model }
		if character then
			table.insert(ignore, character)
		end
		-- Sol DEVANT, sinon sol SOUS LE JOUEUR (bord d'une plateforme, pont etroit) : le joueur, lui, est
		-- forcement pose sur quelque chose. Sans ce repli, le seau resterait en l'air la ou il etait.
		local groundY = groundAt(spot, ignore) or groundAt(hrp.Position, ignore)

		-- On garde la hauteur courante pour cette pose provisoire : seule l'orientation compte ici, la hauteur
		-- definitive est corrigee juste apres, une fois le point le plus bas connu.
		local base = Vector3.new(spot.X, model:GetPivot().Position.Y, spot.Z)
		local target = CFrame.lookAt(base, base + flat)
		model:PivotTo(target)
		if groundY then
			-- Mesure APRES la pose : le point le plus bas depend de l'orientation qu'on vient d'appliquer.
			local bottom = lowestY(model)
			if bottom < math.huge then
				model:PivotTo(target + Vector3.new(0, groundY - bottom, 0))
			end
		end
	end

	restore(state)
end

-- RELACHE IMMEDIAT : mort, respawn, depart. On detache et on restaure sur place, sans chercher le sol (le
-- porteur n'est plus la pour dire ou "devant" se trouve).
local function releaseImmediate(model: Model)
	local state = carried[model]
	if not state then
		return
	end
	local pivot = model:GetPivot()
	detach(state)
	carried[model] = nil
	model:SetAttribute(BinConfigs.CARRIED_ATTRIBUTE, nil)
	local character = state.owner.Character
	if character then
		character:SetAttribute(BinConfigs.CARRYING_ATTRIBUTE, nil)
	end
	model:PivotTo(pivot)
	restore(state)
end

local function releaseAllOf(player: Player)
	for model, state in pairs(carried) do
		if state.owner == player then
			releaseImmediate(model)
		end
	end
end

local function onCarry(player: Player, bin: unknown, phase: unknown)
	local model = isBin(bin)
	if not model or typeof(phase) ~= "string" then
		return
	end
	if phase == "grab" then
		grab(player, model)
	elseif phase == "place" then
		place(player, model)
	elseif phase == "release" then
		local state = carried[model]
		if state and state.owner == player then
			releaseImmediate(model)
		end
	end
end

function BinCarryService.init()
	local remote = RemoteSetup.getRemote("SetBinCarry", "Bin")
	if remote and remote:IsA("RemoteEvent") then
		remote.OnServerEvent:Connect(onCarry)
	else
		warn("[BinCarryService] Remote Bin/SetBinCarry introuvable : le portage du seau ne marchera pas")
	end

	-- MORT / RESPAWN : sans ca le seau resterait soude a un personnage detruit, donc introuvable pour toujours.
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterRemoving:Connect(function()
			releaseAllOf(player)
		end)
	end)
	Players.PlayerRemoving:Connect(releaseAllOf)
end

return BinCarryService
