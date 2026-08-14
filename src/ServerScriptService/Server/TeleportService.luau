--!strict
-- Envoi du joueur vers une AUTRE place de la MEME experience (ex : le chantier d'un client). Cote SERVEUR, comme
-- recommande par Roblox : plus fiable qu'un teleport client. L'ecran de transition, lui, est pose cote client
-- (TeleportController, via SetTeleportGui).
--
-- SQUELETTE : la place de destination (les chantiers) n'existe pas encore. teleportToPlace() est pret ; une feature
-- de mission l'appellera avec le placeId quand ce sera le moment. On ne branche rien tout seul ici.

local Players = game:GetService("Players")
local Teleport = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local RETRIES = 3 -- un teleport peut echouer (reseau, serveur cible plein) : on reessaie plutot que d'abandonner
local RETRY_WAIT = 2 -- secondes entre deux essais

local TeleportService = {}

-- Envoie UN joueur vers une place de la meme experience. `data` (optionnel) est relu a l'arrivee via
-- Player:GetJoinData().TeleportData (ex : quel client, quelle haie). Retourne true si le teleport est bien parti.
function TeleportService.teleportToPlace(player: Player, placeId: number, data: { [string]: any }?): boolean
	if not (player and player.Parent == Players) then
		return false
	end

	-- En STUDIO les teleports ne partent JAMAIS (TeleportAsync throw) : inutile de perdre RETRIES x RETRY_WAIT a echouer.
	-- On rend false tout de suite -> l'appelant retombe sur son fallback (rester dans le hub, ce qui est voulu en Studio).
	if RunService:IsStudio() then
		return false
	end

	local options = Instance.new("TeleportOptions")
	-- On pose TOUJOURS des donnees, avec un marqueur : a l'arrivee, l'ecran de chargement lit GetLocalPlayerTeleportData
	-- pour savoir "on vient d'un teleport" -> il affiche le rideau GRIS + boules (pas le gros ecran herbe du 1er lancement).
	local payload: { [string]: any } = data or {}
	payload.leafiaTeleport = true
	options:SetTeleportData(payload)

	for attempt = 1, RETRIES do
		local ok, err = pcall(function()
			Teleport:TeleportAsync(placeId, { player }, options)
		end)
		if ok then
			return true
		end
		warn(`[TeleportService] Echec teleport (essai {attempt}/{RETRIES}) : {err}`)
		task.wait(RETRY_WAIT)
	end
	return false
end

function TeleportService.init()
	-- Rien a brancher pour l'instant : le teleport partira d'une feature (mission acceptee) plus tard.
end

return TeleportService
