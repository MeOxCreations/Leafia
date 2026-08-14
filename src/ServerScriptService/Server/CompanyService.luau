--!strict
-- SAVES (companies) : chaque joueur a jusqu'a 3 slots INDEPENDANTS, persistes dans le profil (DataService/ProfileStore).
-- AUTORITE serveur : lister / creer / renommer / supprimer / selectionner passent TOUS par ici, jamais par le client.
-- Le client n'affiche que la VUE renvoyee.
--
-- SERIALISATION : Companies est un tableau PLEIN de 3 cases (false = vide), pas un tableau a trous -- un trou casse la
-- serialisation JSON du DataStore. Chaque case remplie = une table Company (que du plat).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local DataService = require(script.Parent.DataService)
local NameFilterService = require(script.Parent.NameFilterService)
-- Economie / progression LIVE : on charge la company active dedans a l'entree (activate). Ces services, eux, reecrivent
-- dans la company active a chaque gain (ils dependent de DataService, pas de CompanyService -> pas de cycle).
local CurrencyService = require(script.Parent.CurrencyService)
local ExperienceService = require(script.Parent.ExperienceService)
-- Onboarding : une NOUVELLE save (tuto pas fini) part au didacticiel au START, au lieu d'entrer dans le hub.
local TeleportService = require(script.Parent.TeleportService)
local PlacesConfig = require(ReplicatedStorage.Modules.Configs.PlacesConfig)

local CompanyService = {}

local MAX_SLOTS = 3
local NAME_MAX = 22

-- Une company PERSISTEE (dans profile.Data.Companies[i]). Stats a 0 a la creation ; la sync avec le jeu (Coins/level
-- live) viendra quand on branchera le gameplay sur le slot actif. Que du plat (serialisable).
export type Company = {
	Name: string,
	Coins: number,
	Reputation: number,
	Level: number,
	Xp: number, -- XP DANS le niveau courant (progression fine, preservee entre sessions)
	HedgesTrimmed: number, -- total de carreaux amenes au ras (stat de carriere -> chip HEDGES de la carte)
	Playtime: number, -- secondes cumulees
	TutorialDone: boolean, -- le didacticiel a-t-il ete termine sur cette save (false -> START renvoie au tuto)
	CreatedAt: number,
	LastPlayed: number,
}

-- Vue CLIENT d'un slot (ce que l'ecran de selection affiche). empty = case vide.
export type SlotView = {
	slot: number,
	empty: boolean,
	name: string,
	level: number?,
	money: number?,
	reputation: number?,
	hedgesTrimmed: number?,
	playtime: number?,
	lastPlayed: string?, -- deja formate ("2h ago") cote serveur, pret a afficher
	active: boolean,
}

local function newCompany(name: string): Company
	local now = os.time()
	return {
		Name = name,
		Coins = 0,
		Reputation = 0,
		Level = 1,
		Xp = 0,
		HedgesTrimmed = 0,
		Playtime = 0,
		TutorialDone = false,
		CreatedAt = now,
		LastPlayed = now,
	}
end

-- "il y a X" a partir d'un timestamp (pour l'affichage des cartes).
local function formatAgo(ts: number): string
	local d = os.time() - ts
	if d < 60 then
		return "just now"
	elseif d < 3600 then
		return `{math.floor(d / 60)}m ago`
	elseif d < 86400 then
		return `{math.floor(d / 3600)}h ago`
	end
	return `{math.floor(d / 86400)}d ago`
end

-- Construit la vue des 3 slots depuis le profil. Slot vide -> { empty = true }.
local function buildViews(player: Player): { SlotView }
	local views: { SlotView } = {}
	local profile = DataService.get(player)
	local companies = if profile then profile.Data.Companies else nil
	local active = if profile then profile.Data.ActiveSlot else 0
	for i = 1, MAX_SLOTS do
		local c = if companies then companies[i] else nil
		if type(c) == "table" then
			table.insert(views, {
				slot = i,
				empty = false,
				name = c.Name,
				level = c.Level,
				money = c.Coins,
				reputation = c.Reputation,
				hedgesTrimmed = c.HedgesTrimmed,
				playtime = c.Playtime,
				lastPlayed = formatAgo(c.LastPlayed),
				active = i == active,
			})
		else
			table.insert(views, { slot = i, empty = true, name = "Empty slot", active = false })
		end
	end
	return views
end

-- Nettoie + valide un nom : borne la longueur, refuse le vide, passe le filtre serveur (Roblox TextService).
local function cleanName(player: Player, raw: string): string?
	local name = raw:match("^%s*(.-)%s*$") or "" -- trim
	if #name == 0 or #name > NAME_MAX then
		return nil
	end
	if not NameFilterService.isClean(player, name) then
		return nil
	end
	return name
end

local function slotValid(slot: any): boolean
	return type(slot) == "number" and slot >= 1 and slot <= MAX_SLOTS and slot % 1 == 0
end

-- Charge les stats de la company ACTIVE dans l'economie live (portefeuille + progression). Appele a l'ENTREE dans une
-- company (create / select) : la company est la source de verite, l'economie live n'en est que la vue de travail.
local function activate(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local slot = profile.Data.ActiveSlot
	local company = if slot >= 1 then profile.Data.Companies[slot] else nil
	if type(company) ~= "table" then
		return
	end
	CurrencyService.setWallet(player, company.Coins, company.Reputation)
	ExperienceService.setState(player, company.Level, company.Xp or 0, company.HedgesTrimmed or 0)
end

-- CREER une company dans un slot VIDE. Renvoie ok + les vues fraiches.
local function create(player: Player, slot: number, rawName: string): (boolean, { SlotView })
	local profile = DataService.get(player)
	if not (profile and slotValid(slot)) then
		return false, buildViews(player)
	end
	if type(profile.Data.Companies[slot]) == "table" then
		return false, buildViews(player) -- slot deja pris
	end
	local name = cleanName(player, rawName)
	if not name then
		return false, buildViews(player) -- nom vide / trop long / refuse par le filtre
	end
	profile.Data.Companies[slot] = newCompany(name)
	profile.Data.ActiveSlot = slot -- on joue direct la company qu'on vient de creer
	activate(player) -- charge ses stats fraiches (0 / niveau 1) dans l'economie live
	return true, buildViews(player)
end

-- RENOMMER une company existante.
local function rename(player: Player, slot: number, rawName: string): (boolean, { SlotView })
	local profile = DataService.get(player)
	if not (profile and slotValid(slot) and type(profile.Data.Companies[slot]) == "table") then
		return false, buildViews(player)
	end
	local name = cleanName(player, rawName)
	if not name then
		return false, buildViews(player)
	end
	profile.Data.Companies[slot].Name = name
	return true, buildViews(player)
end

-- SUPPRIMER une company (remet la case a false). Si c'etait la company jouee, plus de slot actif.
local function remove(player: Player, slot: number): (boolean, { SlotView })
	local profile = DataService.get(player)
	if not (profile and slotValid(slot) and type(profile.Data.Companies[slot]) == "table") then
		return false, buildViews(player)
	end
	profile.Data.Companies[slot] = false
	if profile.Data.ActiveSlot == slot then
		profile.Data.ActiveSlot = 0
	end
	return true, buildViews(player)
end

-- SELECTIONNER la company jouee (CONTINUE). Met a jour LastPlayed. (Nom selectSlot : `select` est une globale Lua.)
local function selectSlot(player: Player, slot: number): (boolean, { SlotView })
	local profile = DataService.get(player)
	if not (profile and slotValid(slot) and type(profile.Data.Companies[slot]) == "table") then
		return false, buildViews(player)
	end
	profile.Data.ActiveSlot = slot
	profile.Data.Companies[slot].LastPlayed = os.time()
	activate(player) -- charge les stats sauvegardees de la company dans l'economie live
	return true, buildViews(player)
end

-- START : ce qui se passe quand le joueur lance sa company active. Nouvelle save (tuto pas fini) -> on l'ENVOIE au
-- didacticiel (autre place) et on renvoie "teleport". Sinon -> "game", le client entre dans le jeu ici (transition
-- camera). En Studio le teleport echoue toujours (pcall cote TeleportService) -> on retombe sur "game" : pratique pour
-- tester le hub sans quitter Studio.
local function startGame(player: Player): { action: string }
	local profile = DataService.get(player)
	local slot = if profile then profile.Data.ActiveSlot else 0
	local company = if profile and slot >= 1 then profile.Data.Companies[slot] else nil
	if type(company) == "table" and not company.TutorialDone then
		if TeleportService.teleportToPlace(player, PlacesConfig.TUTORIAL) then
			return { action = "teleport" }
		end
	end
	return { action = "game" }
end

-- Marque le didacticiel FINI sur la company active. A appeler a la fin du tuto (a brancher) ou via la commande admin
-- tutodone. Une fois pose, le START entre direct dans le jeu.
function CompanyService.markTutorialDone(player: Player)
	local profile = DataService.get(player)
	local slot = if profile then profile.Data.ActiveSlot else 0
	local company = if profile and slot >= 1 then profile.Data.Companies[slot] else nil
	if type(company) == "table" then
		company.TutorialDone = true
	end
end

function CompanyService.init()
	local function bind(name: string, handler: (Player, ...any) -> ...any)
		local remote = RemoteSetup.getRemote(name, "Company")
		if remote and remote:IsA("RemoteFunction") then
			remote.OnServerInvoke = handler :: any
		end
	end

	bind("ListCompanies", function(player: Player)
		return buildViews(player)
	end)
	bind("CreateCompany", function(player: Player, slot: any, rawName: any)
		if not slotValid(slot) or type(rawName) ~= "string" then
			return { ok = false, companies = buildViews(player) }
		end
		local ok, views = create(player, slot, rawName)
		return { ok = ok, companies = views }
	end)
	bind("RenameCompany", function(player: Player, slot: any, rawName: any)
		if not slotValid(slot) or type(rawName) ~= "string" then
			return { ok = false, companies = buildViews(player) }
		end
		local ok, views = rename(player, slot, rawName)
		return { ok = ok, companies = views }
	end)
	bind("DeleteCompany", function(player: Player, slot: any)
		if not slotValid(slot) then
			return { ok = false, companies = buildViews(player) }
		end
		local ok, views = remove(player, slot)
		return { ok = ok, companies = views }
	end)
	bind("SelectCompany", function(player: Player, slot: any)
		if not slotValid(slot) then
			return { ok = false, companies = buildViews(player) }
		end
		local ok, views = selectSlot(player, slot)
		return { ok = ok, companies = views }
	end)
	bind("StartGame", function(player: Player)
		return startGame(player)
	end)
end

return CompanyService
