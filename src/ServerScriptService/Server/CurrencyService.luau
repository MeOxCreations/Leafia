--!strict
-- ECONOMIE joueur : pieces (monnaie principale) et reputation (rang de l'entreprise). AUTORITE serveur. Le client
-- (CurrencyController) ne fait qu'AFFICHER les attributs qu'on pose ici.
--
-- Le portefeuille (coins + reputation) est la VUE LIVE de la company ACTIVE : setWallet le charge depuis la company a
-- l'entree (appele par CompanyService), et chaque gain le REECRIT dans la company active (writeToCompany) -> ca persiste
-- et alimente la carte de save. Hors company active (menu, ActiveSlot 0), l'etat vit en memoire et n'ecrit rien.
--
-- grantCoins / grantReputation sont le POINT D'ENTREE UNIQUE de tout gain : brancher dessus, jamais SetAttribute a la
-- main ailleurs. Le gain de coins n'est pas encore branche en jeu (seul le bouton DEV en Studio en donne) : ils
-- resteront a 0 en vrai jusqu'a ce que le systeme de chantiers appelle grantCoins a la fin d'un chantier (le cheque).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CurrencyConfigs = require(ReplicatedStorage.Modules.Configs.CurrencyConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local DataService = require(script.Parent.DataService)

local CurrencyService = {}

-- DEV : somme fixe donnee par le bouton de test. Le client ne fixe JAMAIS le montant (il ment toujours).
local DEV_COINS_GRANT = 1000

type Wallet = { coins: number, reputation: number }
local wallets: { [Player]: Wallet } = {}

-- Pousse l'etat courant vers le client (attributs sur le joueur). SetAttribute se replique tout seul : pas de
-- remote, pas de file a saturer, le client lit la valeur des qu'il est pret.
local function push(player: Player)
	local w = wallets[player]
	if not w then
		return
	end
	player:SetAttribute(CurrencyConfigs.COINS_ATTRIBUTE, w.coins)
	player:SetAttribute(CurrencyConfigs.REPUTATION_ATTRIBUTE, w.reputation)
end

-- Ecrit le portefeuille dans la company ACTIVE du joueur (persiste + alimente la carte de save). No-op s'il n'y a pas
-- de company active (ActiveSlot 0 : joueur au menu). La company est la SOURCE DE VERITE ; le portefeuille en est la vue.
local function writeToCompany(player: Player)
	local w = wallets[player]
	local profile = DataService.get(player)
	if not (w and profile) then
		return
	end
	local slot = profile.Data.ActiveSlot
	local company = if slot >= 1 then profile.Data.Companies[slot] else nil
	if type(company) == "table" then
		company.Coins = w.coins
		company.Reputation = w.reputation
	end
end

-- Charge un portefeuille DEPUIS la company (a l'entree dans une company). Ne reecrit PAS la company : on lit d'elle.
-- Appele par CompanyService quand le joueur entre dans une company (create / select).
function CurrencyService.setWallet(player: Player, coins: number, reputation: number)
	wallets[player] = { coins = math.max(0, math.floor(coins)), reputation = math.max(0, math.floor(reputation)) }
	push(player)
end

-- Ajoute des pieces (montant > 0). POINT D'ENTREE UNIQUE de tout gain de pieces : le futur systeme de quetes
-- appellera ceci a la fin d'un chantier (le cheque). Ignore les montants <= 0 : un gain n'enleve rien.
function CurrencyService.grantCoins(player: Player, amount: number)
	local w = wallets[player]
	if not w or amount <= 0 then
		return
	end
	w.coins += math.floor(amount)
	push(player)
	writeToCompany(player)
end

-- Ajoute de la reputation (montant > 0). La reputation se MERITE (bon boulot), elle ne s'achete pas : d'ou un
-- simple grant, sans depense possible. Le systeme de chantiers decidera du montant selon la qualite du job.
function CurrencyService.grantReputation(player: Player, amount: number)
	local w = wallets[player]
	if not w or amount <= 0 then
		return
	end
	w.reputation += math.floor(amount)
	push(player)
	writeToCompany(player)
end

-- ADMIN (console) : remet le portefeuille a zero. Runtime, comme le reste du service.
function CurrencyService.resetPlayer(player: Player)
	local w = wallets[player]
	if not w then
		return
	end
	w.coins = 0
	w.reputation = 0
	push(player)
	writeToCompany(player)
end

local function onPlayerAdded(player: Player)
	wallets[player] = { coins = 0, reputation = 0 }
	push(player)
end

local function onPlayerRemoving(player: Player)
	wallets[player] = nil
end

function CurrencyService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Joueurs deja la (demarrage a chaud en Studio).
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	-- DEV UNIQUEMENT : le bouton de test (clic sur l'icone piece) passe par ici. Gate IsStudio : sur un vrai
	-- serveur ce bloc ne s'execute pas, donc personne n'ecoute le remote et cliquer ne donne rien. Le serveur
	-- ignore tout montant envoye par le client : il donne DEV_COINS_GRANT, point.
	if RunService:IsStudio() then
		local devGrant = RemoteSetup.getRemote("DevGrantCoins", "Dev")
		if devGrant and devGrant:IsA("RemoteEvent") then
			devGrant.OnServerEvent:Connect(function(player: Player)
				CurrencyService.grantCoins(player, DEV_COINS_GRANT)
			end)
		end
	end
end

return CurrencyService
