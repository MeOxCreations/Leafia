--!strict
-- LES TAS DE FEUILLES ENTRENT DANS LE SEAU. Autorite SERVEUR : le joueur DEMANDE, le serveur verifie et agit.
--
-- POURQUOI UN SERVICE DE PLUS. Le cycle de la feuille a trois moments et trois fichiers : `HedgeStockService` les
-- POSE (c'est le dechet de la taille), `RakeService` les RASSEMBLE en gros tas, et celui-ci les EMPORTE. L'entete
-- de RakeService annoncait ce jour-la en toutes lettres -- "le gros tas ira un jour dans la Bin".
--
-- CE QU'IL VERIFIE, ET POURQUOI CHACUN. Le client ment toujours : il envoie un MODELE, et rien d'autre.
--   * ce modele est bien un gros tas, et il est bien dans le dossier des tas -- sinon on pourrait faire avaler
--     n'importe quoi au seau, la maison du grand-pere comprise ;
--   * le joueur PORTE un seau -- l'action n'existe pas sans lui ;
--   * il est ASSEZ PRES -- sinon on vide le jardin depuis le trottoir.
--
-- LE COMPTE VA SUR LE SEAU, en attribut. Il se replique tout seul, il voyage avec l'objet, et il survit a la
-- repose : un seau pose au sol garde ce qu'il contient, ce qui est la moindre des choses pour un seau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BinConfigs = require(ReplicatedStorage.Modules.Configs.BinConfigs)
local CarryUtils = require(ReplicatedStorage.Modules.Utils.CarryUtils)
local RakeConfigs = require(ReplicatedStorage.Modules.Configs.RakeConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local BinCarryService = require(script.Parent.BinCarryService)

local LeafCollectService = {}

--- Le dossier des gros tas, ou nil. Re-cherche a chaque fois : il est cree par `RakeService` au premier tas, donc
--- il n'existe pas au demarrage -- une reference resolue une seule fois resterait vide pour toute la session.
local function pileFolder(): Instance?
	return Workspace:FindFirstChild(RakeConfigs.PILE_FOLDER)
end

--- La position d'un tas, ou nil s'il n'a aucune part (streaming en cours).
local function pilePosition(pile: Model): Vector3?
	local part = pile.PrimaryPart or pile:FindFirstChildWhichIsA("BasePart")
	return if part then (part :: BasePart).Position else nil
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

function LeafCollectService.init()
	local remote = RemoteSetup.getRemote("CollectLeafPile", "Rake") :: RemoteEvent

	remote.OnServerEvent:Connect(function(player, pile)
		-- LE CLIENT MENT TOUJOURS. On n'accepte qu'un Model, et on ne s'en sert que comme d'une CLE a retrouver
		-- dans le dossier des tas : tout le reste -- qui peut, de combien, a quelle distance -- se decide ici.
		if typeof(pile) ~= "Instance" or not (pile :: Instance):IsA("Model") then
			return
		end
		local model = pile :: Model
		if model.Name ~= RakeConfigs.PILE_NAME then
			return
		end
		local folder = pileFolder()
		if not (folder and model.Parent == folder) then
			return -- pas un tas du jeu : on ne fait pas avaler n'importe quoi au seau
		end
		if not CarryUtils.holds(player, "Bin") then
			return -- l'action n'existe pas sans seau dans les mains
		end
		local bin = BinCarryService.carriedBy(player)
		if not bin then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		local here = pilePosition(model)
		if not here then
			return
		end
		local delta = (root :: BasePart).Position - (here :: Vector3)
		if Vector3.new(delta.X, 0, delta.Z).Magnitude > RakeConfigs.COLLECT_RADIUS then
			return -- trop loin : on ne vide pas le jardin depuis le trottoir
		end

		-- LE COMPTE S'AJOUTE AU SEAU, il ne le remplace pas : on y verse plusieurs tas.
		local held = bin :: Model
		local before = held:GetAttribute(BinConfigs.LEAVES_ATTRIBUTE)
		local total = (if typeof(before) == "number" then before :: number else 0) + leafCount(model)
		held:SetAttribute(BinConfigs.LEAVES_ATTRIBUTE, total)

		-- LE SON EST PORTE PAR LE SEAU et pas par le tas : le tas disparait dans l'instant, et un son pose sur un
		-- objet detruit se coupe avec lui.
		local host = held.PrimaryPart or held:FindFirstChildWhichIsA("BasePart")
		if host then
			SoundUtils.play(RakeConfigs.COLLECT_SOUND, host :: BasePart)
		end
		model:Destroy()
		print(`[LeafCollect] {player.Name} verse un tas dans son seau : {total} feuille(s) dedans.`)
	end)

	-- RIEN A NETTOYER AU DEPART D'UN JOUEUR : le compte vit sur le SEAU, qui est un objet du monde. Ce qu'il
	-- contient ne lui appartient pas plus que le seau lui-meme.
	print("[LeafCollectService] Pret : le seau en main, E verse un tas de feuilles dedans.")
end

return LeafCollectService
