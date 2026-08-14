--!strict
-- Filtre SERVEUR des noms (company) via le vrai filtre de Roblox (TextService). C'est LUI qui gere toutes les langues,
-- le leetspeak, les variantes et les infos perso -- pas une liste maison. TextService:FilterStringAsync ne peut
-- s'appeler QUE cote serveur : d'ou ce service. Le client envoie le nom (remote Name/FilterName), on renvoie
-- { ok, filtered } : ok = true si RIEN n'a ete censure (nom propre).

local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local NameFilterService = {}

export type FilterResult = { ok: boolean, filtered: string }

local MAX_LEN = 40 -- au-dela on refuse direct : un nom de company n'est pas un pave

local function filterName(player: Player, raw: string): FilterResult
	if #raw == 0 or #raw > MAX_LEN then
		return { ok = false, filtered = "" }
	end
	-- FilterStringAsync YIELD et peut echouer (reseau). En cas d'echec : en jeu PUBLIE on REFUSE par securite (ne jamais
	-- laisser passer du non-filtre) ; en STUDIO on ACCEPTE -- le filtre exige "Enable Studio Access to API Services",
	-- sinon il echoue et on ne pourrait plus rien tester. Le pre-check client (liste) reste actif dans tous les cas.
	local okCall, result = pcall(function()
		return TextService:FilterStringAsync(raw, player.UserId)
	end)
	if not okCall or result == nil then
		warn(`[NameFilter] FilterStringAsync a ECHOUE pour "{raw}" -- "Permettre a Studio d'acceder aux services API" actif ET session Play RELANCEE ? (en Studio on accepte par defaut, en jeu publie on refuse)`)
		return { ok = RunService:IsStudio(), filtered = raw }
	end
	local okGet, filtered = pcall(function()
		return (result :: TextFilterResult):GetNonChatStringForBroadcastAsync()
	end)
	if not okGet or type(filtered) ~= "string" then
		warn(`[NameFilter] GetNonChatStringForBroadcastAsync a ECHOUE pour "{raw}"`)
		return { ok = RunService:IsStudio(), filtered = raw }
	end
	-- DEBUG (a retirer) : montre ce que le filtre Roblox renvoie vraiment. propre = false -> le nom est refuse.
	print(`[NameFilter] "{raw}" -> "{filtered}" (propre = {filtered == raw})`)
	-- Rien censure -> la version filtree est identique au nom -> propre. Sinon (####) -> refuse.
	return { ok = filtered == raw, filtered = filtered }
end

-- Raccourci booleen pour les autres services serveur (ex CompanyService) : le nom passe-t-il le filtre ?
function NameFilterService.isClean(player: Player, raw: string): boolean
	return filterName(player, raw).ok
end

function NameFilterService.init()
	local remote = RemoteSetup.getRemote("FilterName", "Name")
	if remote and remote:IsA("RemoteFunction") then
		remote.OnServerInvoke = function(player: Player, raw: any): FilterResult
			if type(raw) ~= "string" then
				return { ok = false, filtered = "" }
			end
			return filterName(player, raw)
		end
	end
end

return NameFilterService
