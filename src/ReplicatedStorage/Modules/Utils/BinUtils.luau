--!strict
-- LE SEAU VU DE L'EXTERIEUR : qu'est-ce qui est un seau, est-il pose, a-t-il de la place, lequel couvre ce point.
--
-- PARTAGE CLIENT + SERVEUR, et c'est la raison d'etre du fichier. Le cercle DESSINE chez le client et la zone qui
-- AVALE les feuilles au serveur doivent repondre exactement pareil : deux copies de la regle finiraient par
-- diverger, et le joueur verrait ses feuilles dans le cercle sans qu'elles entrent dans le seau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BinConfigs = require(ReplicatedStorage.Modules.Configs.BinConfigs)
local TruckConfigs = require(ReplicatedStorage.Modules.Configs.TruckConfigs)

local BinUtils = {}

--- Un seau DU JEU : bon prefixe, pas monte sur un rig d'animation, pas range dans la benne du camion.
---
--- LE RIG SE RECONNAIT A SON HUMANOID, pas a son nom (meme regle que BinCarryService). LA BENNE, a son camion :
--- un seau range est ancre et personne ne le porte, il passerait donc pour un seau pose.
function BinUtils.isBin(inst: Instance): boolean
	if not inst:IsA("Model") or inst.Name:sub(1, #BinConfigs.MODEL_PREFIX) ~= BinConfigs.MODEL_PREFIX then
		return false
	end
	if not inst:IsDescendantOf(Workspace) or inst:FindFirstChildOfClass("Humanoid") then
		return false
	end
	local node: Instance? = inst.Parent
	while node and node ~= Workspace do
		if node:IsA("Model") and (node:FindFirstChildOfClass("Humanoid") or node.Name == TruckConfigs.MODEL_NAME) then
			return false
		end
		node = node.Parent
	end
	return true
end

--- Tous les seaux du jeu, dans `out` (vide d'abord). Parcourt le Workspace entier : a l'appelant de choisir la
--- cadence, ce n'est pas un appel a faire a chaque image.
function BinUtils.collect(out: { Model }): { Model }
	table.clear(out)
	for _, d in Workspace:GetDescendants() do
		if BinUtils.isBin(d) then
			table.insert(out, d :: Model)
		end
	end
	return out
end

--- La part de reference du seau. Jamais GetPivot : il suit la boite englobante, qu'un enfant ajoute decale.
function BinUtils.root(bin: Model): BasePart?
	local root = bin.PrimaryPart or bin:FindFirstChild(BinConfigs.ROOT_NAME)
	if root and root:IsA("BasePart") then
		return root
	end
	return bin:FindFirstChildWhichIsA("BasePart")
end

--- Combien de feuilles il contient.
function BinUtils.contents(bin: Model): number
	local raw = bin:GetAttribute(BinConfigs.LEAVES_ATTRIBUTE)
	return if typeof(raw) == "number" then math.max(raw :: number, 0) else 0
end

--- POSE AU SOL : personne ne le porte, et sa racine est ancree.
---
--- L'ANCRAGE COMPTE AUTANT QUE L'ATTRIBUT. Porte, le seau est desancre (une part ancree ignore sa soudure) ; il
--- n'est reancre qu'a la repose. L'attribut seul dirait "pose" pendant les quelques images ou il quitte les mains.
function BinUtils.isOnGround(bin: Model): boolean
	if bin:GetAttribute(BinConfigs.CARRIED_ATTRIBUTE) ~= nil then
		return false
	end
	local root = BinUtils.root(bin)
	return root ~= nil and root.Anchored
end

--- LE SEAU POSE DONT LA ZONE COUVRE CE POINT, et qui a encore de la place. Le plus proche s'il y en a plusieurs.
---
--- `reserved` compte, par seau, les feuilles DEJA EN ROUTE vers lui : sans ca, quatre feuilles lancees vers un
--- seau a qui il reste une place partiraient toutes, et trois retomberaient.
function BinUtils.zoneBinAt(pool: { Model }, position: Vector3, reserved: { [Model]: number }?): (Model?, BasePart?)
	local best: Model? = nil
	local bestRoot: BasePart? = nil
	local bestDist = BinConfigs.ZONE_RADIUS
	for _, bin in pool do
		if bin.Parent and BinUtils.isOnGround(bin) then
			local pending = if reserved then reserved[bin] or 0 else 0
			local root = BinUtils.root(bin)
			if root and BinUtils.contents(bin) + pending < BinConfigs.LEAVES_CAPACITY then
				local delta = root.Position - position
				local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
				if flat <= bestDist then
					bestDist, best, bestRoot = flat, bin, root
				end
			end
		end
	end
	return best, bestRoot
end

return BinUtils
