--!strict
-- LES TAS DE FEUILLES TOMBENT DANS LE SEAU TOUT SEULS. Autorite SERVEUR : les tas et les seaux sont des objets du
-- MONDE, et deux joueurs doivent voir la meme pelouse.
--
-- POURQUOI PAS UNE PASTILLE. Le joueur a deja le rateau en main et il POUSSE les feuilles : lui demander ensuite
-- de lacher son geste pour appuyer sur une touche coupe le seul mouvement continu de cette etape. On rate vers le
-- seau, ca rentre. Le geste EST l'action, il n'y a rien a apprendre.
--
-- POURQUOI UN SERVICE DE PLUS. Le cycle de la feuille a trois moments et trois fichiers : `HedgeStockService` les
-- POSE (c'est le dechet de la taille), `RakeService` les RASSEMBLE en gros tas, et celui-ci les EMPORTE. L'entete
-- de RakeService annoncait ce jour-la en toutes lettres -- "le gros tas ira un jour dans la Bin".
--
-- LE COMPTE VA SUR LE SEAU, en attribut. Il se replique tout seul, il voyage avec l'objet, et il survit a la
-- repose : un seau pose au sol garde ce qu'il contient, ce qui est la moindre des choses pour un seau.
--
-- ET IL A UN FOND. Un seau sans limite n'est pas un seau, c'est un trou : la jauge au-dessus ne dirait rien, et
-- aller le vider ne serait jamais une decision.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BinConfigs = require(ReplicatedStorage.Modules.Configs.BinConfigs)
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

--- La part de reference d'un seau : celle qui porte sa position et son angle.
local function binRoot(bin: Model): BasePart?
	return bin.PrimaryPart or bin:FindFirstChildWhichIsA("BasePart")
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
	local root = binRoot(bin)
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

--- Tous les seaux du monde. Re-balaye a chaque passage : un seau sort du camion en cours de partie, et une liste
--- gardee mentirait le jour ou il arrive.
local function bins(out: { Model }): { Model }
	table.clear(out)
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and d.Name:sub(1, #BinConfigs.MODEL_PREFIX) == BinConfigs.MODEL_PREFIX then
			table.insert(out, d :: Model)
		end
	end
	return out
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

local function contents(bin: Model): number
	local raw = bin:GetAttribute(BinConfigs.LEAVES_ATTRIBUTE)
	return if typeof(raw) == "number" then math.max(raw :: number, 0) else 0
end

--- LE SEAU LE PLUS PROCHE DE CE POINT, et qui a encore de la place, ou nil.
---
--- UN SEAU PLEIN NE COMPTE PAS. Sinon le tas resterait colle a lui sans jamais y entrer, et le joueur verrait des
--- feuilles qui refusent d'avancer sans que rien ne lui dise pourquoi -- alors qu'un seau plus loin, vide,
--- ferait l'affaire.
local function nearestBin(pool: { Model }, from: Vector3): (Model?, BasePart?)
	local best: Model? = nil
	local bestRoot: BasePart? = nil
	local bestDist = BinConfigs.ABSORB_RADIUS
	for _, bin in pool do
		if contents(bin) < BinConfigs.LEAVES_CAPACITY then
			local root = binRoot(bin)
			if root then
				local delta = (root :: BasePart).Position - from
				local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
				if flat <= bestDist then
					bestDist, best, bestRoot = flat, bin, root :: BasePart
				end
			end
		end
	end
	return best, bestRoot
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
		bins(pool)
		if #pool == 0 then
			return
		end

		for _, child in piles do
			if child:IsA("Model") and child.Name == RakeConfigs.PILE_NAME then
				local pile = child :: Model
				local part = pile.PrimaryPart or pile:FindFirstChildWhichIsA("BasePart")
				if part then
					local bin, root = nearestBin(pool, (part :: BasePart).Position)
					if bin and root then
						local held = bin :: Model
						-- ON N'EN MET QUE CE QUI RENTRE. Le reste du tas RESTE au sol : il faudra aller vider le
						-- seau et revenir, ce qui est exactement la decision qu'une contenance sert a creer.
						local room = BinConfigs.LEAVES_CAPACITY - contents(held)
						local taken = math.min(leafCount(pile), room)
						if taken > 0 then
							local total = contents(held) + taken
							held:SetAttribute(BinConfigs.LEAVES_ATTRIBUTE, total)
							setLeafVisual(held, total)
							SoundUtils.play(BinConfigs.ABSORB_SOUND, root :: BasePart)
							if taken >= leafCount(pile) then
								pile:Destroy()
							else
								pile:SetAttribute(
									RakeConfigs.PILE_COUNT_ATTRIBUTE,
									leafCount(pile) - taken
								)
							end
						end
					end
				end
			end
		end
	end)

	print("[LeafCollectService] Pret : un tas de feuilles pres d'un seau tombe dedans tout seul.")
end

return LeafCollectService
