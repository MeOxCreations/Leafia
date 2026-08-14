--!strict
-- Console admin (AUTORITE serveur). Recoit une ligne de commande (string) via RemoteFunction, verifie que l'appelant
-- est admin, parse, execute, et RENVOIE un texte de resultat affiche dans la console. Le client ne decide RIEN : il
-- envoie du texte, le serveur seul tranche (acces + effet). Meme gate que le reste (Studio ou UserId liste).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local AdminCommandConfigs = require(ReplicatedStorage.Modules.Configs.AdminCommandConfigs)
local CurrencyService = require(script.Parent.CurrencyService)
local ExperienceService = require(script.Parent.ExperienceService)
local DataService = require(script.Parent.DataService)
local TeleportService = require(script.Parent.TeleportService)
local PlacesConfig = require(ReplicatedStorage.Modules.Configs.PlacesConfig)
local CompanyService = require(script.Parent.CompanyService)

local AdminCommandService = {}

-- Trouve un joueur par PREFIXE de nom (Name ou DisplayName), insensible a la casse. Premier match, ou nil.
local function findPlayer(query: string): Player?
	query = query:lower()
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name:lower():sub(1, #query) == query or p.DisplayName:lower():sub(1, #query) == query then
			return p
		end
	end
	return nil
end

-- Resout la cible d'une commande. Nom donne -> ce joueur (ou erreur). Aucun nom -> l'appelant lui-meme. Le second
-- retour est un texte d'erreur ("" si tout va bien) : les handlers le renvoient tel quel a la console.
local function resolveTarget(caller: Player, nameArg: string?): (Player?, string)
	if not nameArg or nameArg == "" then
		return caller, ""
	end
	local target = findPlayer(nameArg)
	if not target then
		return nil, `Joueur introuvable : "{nameArg}"`
	end
	return target, ""
end

-- Chaque handler : (appelant, args apres le nom de commande) -> texte de resultat.
local handlers: { [string]: (Player, { string }) -> string } = {}

handlers.help = function(_caller, _args)
	local lines = { "Commandes :" }
	for _, cmd in ipairs(AdminCommandConfigs.COMMANDS) do
		table.insert(lines, `  {cmd.usage}  -  {cmd.description}`)
	end
	return table.concat(lines, "\n")
end

handlers.coins = function(caller, args)
	local amount = tonumber(args[1])
	if not amount then
		return "Usage : coins <montant> [joueur]"
	end
	local target, err = resolveTarget(caller, args[2])
	if not target then
		return err
	end
	CurrencyService.grantCoins(target, amount)
	return `+{math.floor(amount)} pieces -> {target.Name}`
end

handlers.reputation = function(caller, args)
	local amount = tonumber(args[1])
	if not amount then
		return "Usage : reputation <montant> [joueur]"
	end
	local target, err = resolveTarget(caller, args[2])
	if not target then
		return err
	end
	CurrencyService.grantReputation(target, amount)
	return `+{math.floor(amount)} reputation -> {target.Name}`
end

handlers.xp = function(caller, args)
	local cells = tonumber(args[1])
	if not cells then
		return "Usage : xp <carreaux> [joueur]"
	end
	local target, err = resolveTarget(caller, args[2])
	if not target then
		return err
	end
	ExperienceService.grantXp(target, cells)
	return `+{math.floor(cells)} carreaux d'XP -> {target.Name}`
end

handlers.level = function(caller, args)
	local level = tonumber(args[1])
	if not level then
		return "Usage : level <niveau> [joueur]"
	end
	local target, err = resolveTarget(caller, args[2])
	if not target then
		return err
	end
	ExperienceService.setLevel(target, math.floor(level))
	return `Niveau {math.floor(level)} -> {target.Name}`
end

handlers.resetdata = function(caller, args)
	local target, err = resolveTarget(caller, args[1])
	if not target then
		return err
	end
	CurrencyService.resetPlayer(target)
	ExperienceService.resetPlayer(target)
	DataService.resetData(target)
	return `Data remise a zero (pieces, reputation, XP, save) -> {target.Name}`
end

-- TEST multi-place : envoie la cible vers le didacticiel (tuto) ou le retour au hub (Leafia).
handlers.tuto = function(caller, args)
	local target, err = resolveTarget(caller, args[1])
	if not target then
		return err
	end
	local ok = TeleportService.teleportToPlace(target, PlacesConfig.TUTORIAL)
	return if ok then `Teleport -> TUTO ({target.Name})` else "Echec du teleport."
end

handlers.hub = function(caller, args)
	local target, err = resolveTarget(caller, args[1])
	if not target then
		return err
	end
	local ok = TeleportService.teleportToPlace(target, PlacesConfig.MAIN)
	return if ok then `Teleport -> HUB Leafia ({target.Name})` else "Echec du teleport."
end

-- TEST onboarding : marque le tuto FINI sur la save active, pour que le START entre dans le jeu au lieu de renvoyer au
-- tuto (sert a tester le chemin du joueur qui revient, tant que la fin de tuto n'est pas branchee).
handlers.tutodone = function(caller, args)
	local target, err = resolveTarget(caller, args[1])
	if not target then
		return err
	end
	CompanyService.markTutorialDone(target)
	return `Tuto marque FINI sur la save active -> {target.Name}`
end

-- Parse + execute UNE ligne. Renvoie TOUJOURS un texte (aucune erreur ne remonte au client).
local function run(caller: Player, raw: string): string
	if not AdminCommandConfigs.isAdmin(caller) then
		return "Acces refuse."
	end
	local words: { string } = {}
	for word in raw:gmatch("%S+") do
		table.insert(words, word)
	end
	if #words == 0 then
		return ""
	end
	local name = (table.remove(words, 1) :: string):lower()
	local handler = handlers[name]
	if not handler then
		return `Commande inconnue : "{name}". Tape help.`
	end
	local ok, result = pcall(handler, caller, words)
	if not ok then
		return `Erreur : {tostring(result)}`
	end
	return result
end

function AdminCommandService.init()
	local remote = RemoteSetup.getRemote("AdminCommand", "Admin")
	if remote and remote:IsA("RemoteFunction") then
		remote.OnServerInvoke = function(player: Player, raw: any): string
			if type(raw) ~= "string" then
				return "Commande invalide."
			end
			return run(player, raw)
		end
	end
end

return AdminCommandService
