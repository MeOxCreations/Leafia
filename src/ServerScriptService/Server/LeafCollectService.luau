--!strict
-- LES FEUILLES ENTRENT DANS LE SEAU POSE. Autorite SERVEUR : les tas et les seaux sont des objets du MONDE, et deux
-- joueurs doivent voir la meme pelouse.
--
-- DEUX CHEMINS, UNE SEULE PORTE D'ENTREE (`addLeaves`) :
--   * le rateau (RakeService) envoie direct dans le seau ce qu'il ratisse DANS sa zone ;
--   * un gros tas qui se trouve dans la zone d'un seau pose y tombe tout seul (la boucle plus bas) -- c'est le cas
--     du seau qu'on vient poser a cote d'un tas deja fait.
--
-- UN SEAU PORTE N'AVALE RIEN. On pose le seau, on ratisse vers lui : une seule regle a comprendre.
--
-- LE COMPTE VA SUR LE SEAU, en attribut. Il se replique tout seul, il voyage avec l'objet, et il survit a la
-- repose : un seau pose au sol garde ce qu'il contient, ce qui est la moindre des choses pour un seau.
--
-- ET IL A UN FOND. Un seau sans limite n'est pas un seau, c'est un trou : la jauge ne dirait rien, et aller le
-- vider ne serait jamais une decision.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BinConfigs = require(ReplicatedStorage.Modules.Configs.BinConfigs)
local BinUtils = require(ReplicatedStorage.Modules.Utils.BinUtils)
local RakeConfigs = require(ReplicatedStorage.Modules.Configs.RakeConfigs)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)

local LeafCollectService = {}

--- Le modele de feuilles a poser DANS le seau, ou nil. Resolu a chaque fois : il vient de `Assets`, que Rojo ne
--- synchronise pas -- il peut donc etre absent d'une place sans que ce soit une erreur de code.
local function leafModel(): Model?
	local node: Instance? = ReplicatedStorage
	for _, step in BinConfigs.LEAF_MODEL_PATH do
		node = node and node:FindFirstChild(step)
	end
	return if node and node:IsA("Model") then node :: Model else nil
end

--- LE TAS DE FEUILLES VISIBLE DANS LE SEAU. Il MONTE avec le remplissage.
---
--- C'EST LA MEME INFORMATION QUE LA JAUGE, dite par l'objet lui-meme : un joueur qui regarde son seau sait ou il
--- en est sans lire un chiffre, et de dos, et le son coupe.
---
--- SOUDE ET SANS MASSE. Le seau se porte, se lache et retombe : des parts simplement parentees resteraient au sol
--- pendant que le seau s'en va. Et `Massless` parce qu'un seau qui s'alourdit en se remplissant ferait ramer le
--- porteur pour une raison qu'aucun joueur ne devinerait.
---
--- ON REFAIT LA SOUDURE A CHAQUE MONTEE. Un `WeldConstraint` capture l'ecart entre ses deux parts AU MOMENT OU ON
--- L'ACTIVE : le laisser en place figerait les feuilles a la hauteur qu'elles avaient a la premiere poignee.
local function setLeafVisual(bin: Model, leaves: number)
	local existing = bin:FindFirstChild(BinConfigs.LEAF_MODEL_NAME)
	if leaves <= 0 then
		if existing then
			existing:Destroy()
		end
		return
	end
	local root = BinUtils.root(bin)
	if not root then
		return
	end
	local model: Model? = if existing and existing:IsA("Model") then existing :: Model else nil
	if not model then
		local source = leafModel()
		if not source then
			return -- pas d'asset : le compte marche quand meme, il ne se voit juste pas
		end
		local clone = (source :: Model):Clone()
		clone.Name = BinConfigs.LEAF_MODEL_NAME
		clone.Parent = bin
		model = clone
	end
	local ratio = math.clamp(leaves / BinConfigs.LEAVES_CAPACITY, 0, 1)
	local up = BinConfigs.LEAF_LOW + (BinConfigs.LEAF_HIGH - BinConfigs.LEAF_LOW) * ratio
	local body = model :: Model
	for _, d in body:GetDescendants() do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	body:PivotTo((root :: BasePart).CFrame * CFrame.new(0, up, 0))
	for _, d in body:GetDescendants() do
		if d:IsA("BasePart") then
			local part = d :: BasePart
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = root :: BasePart
			weld.Parent = part
		end
	end
end

--- Combien de feuilles ce tas represente. Un tas sans compte vaut UNE feuille : il existe, donc il valait bien
--- quelque chose -- rendre zero le ferait disparaitre sans rien rapporter.
local function leafCount(pile: Model): number
	local raw = pile:GetAttribute(RakeConfigs.PILE_COUNT_ATTRIBUTE)
	if typeof(raw) ~= "number" then
		return 1
	end
	return math.max(math.floor(raw :: number), 1)
end

--- MET DES FEUILLES DANS LE SEAU. Rend combien sont vraiment entrees : jamais plus que la place qui reste.
---
--- LA SEULE FACON DE REMPLIR UN SEAU. Le compte, le tas visible dedans et le bruit vont ensemble : un second
--- chemin qui ecrirait l'attribut a la main oublierait l'un des deux autres.
function LeafCollectService.addLeaves(bin: Model, count: number): number
	local held = BinUtils.contents(bin)
	local taken = math.min(count, BinConfigs.LEAVES_CAPACITY - held)
	if taken <= 0 then
		return 0
	end
	local total = held + taken
	bin:SetAttribute(BinConfigs.LEAVES_ATTRIBUTE, total)
	setLeafVisual(bin, total)
	local root = BinUtils.root(bin)
	if root then
		SoundUtils.play(BinConfigs.ABSORB_SOUND, root)
	end
	return taken
end

function LeafCollectService.init()
	local pool: { Model } = {}
	local nextCheck = 0

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextCheck then
			return
		end
		nextCheck = now + BinConfigs.ABSORB_INTERVAL

		-- LE DOSSIER DES TAS EST CREE PAR `RakeService` AU PREMIER TAS : il n'existe pas au demarrage. On le
		-- re-cherche a chaque passage plutot que de le resoudre une fois -- une reference prise trop tot
		-- resterait vide pour toute la session.
		local folder = Workspace:FindFirstChild(RakeConfigs.PILE_FOLDER)
		if not folder then
			return
		end
		local piles = folder:GetChildren()
		if #piles == 0 then
			return
		end
		BinUtils.collect(pool)
		if #pool == 0 then
			return
		end

		for _, child in piles do
			if child:IsA("Model") and child.Name == RakeConfigs.PILE_NAME then
				local pile = child :: Model
				local part = pile.PrimaryPart or pile:FindFirstChildWhichIsA("BasePart")
				if part then
					local bin = BinUtils.zoneBinAt(pool, (part :: BasePart).Position)
					if bin then
						-- ON N'EN MET QUE CE QUI RENTRE. Le reste du tas RESTE au sol : il faudra aller vider le
						-- seau et revenir, ce qui est exactement la decision qu'une contenance sert a creer.
						local count = leafCount(pile)
						local taken = LeafCollectService.addLeaves(bin, count)
						if taken >= count then
							pile:Destroy()
						elseif taken > 0 then
							pile:SetAttribute(RakeConfigs.PILE_COUNT_ATTRIBUTE, count - taken)
						end
					end
				end
			end
		end
	end)

	print("[LeafCollectService] Pret : ce qui est dans la zone d'un seau pose tombe dedans.")
end

return LeafCollectService
