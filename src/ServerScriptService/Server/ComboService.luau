--!strict
-- COMBO de coupe. AUTORITE serveur : le compteur vit ici, le client (ComboController) ne fait qu'AFFICHER l'attribut
-- qu'on pose (LeafiaCombo). Point d'entree UNIQUE : registerCut, appele par la coupe (HedgeCutService.biteAt) a chaque
-- carreau amene au ras, pour tous les outils et tous les contextes.
--
-- RUNTIME SEULEMENT : l'etat vit en memoire, remis a zero a chaque session. Rien a sauvegarder tant que le combo est
-- purement visuel (pas encore de bonus branche dessus).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ComboConfigs = require(ReplicatedStorage.Modules.Configs.ComboConfigs)

local ComboService = {}

-- combo = palier courant. lastBump = quand on a monte le compteur pour la derniere fois (plancher de rythme).
-- token = generation : chaque montee arme un reset, seul le DERNIER (token a jour) le declenche vraiment.
type State = { combo: number, lastBump: number, token: number }
local state: { [Player]: State } = {}

-- Repere temps interne (os.clock : monotone, insensible a l'heure systeme). Purement local a ce service.
local function push(player: Player, value: number)
	player:SetAttribute(ComboConfigs.COMBO_ATTRIBUTE, value)
end

local function reset(player: Player)
	local s = state[player]
	if not s or s.combo == 0 then
		return
	end
	s.combo = 0
	push(player, 0)
end

-- Appele par la coupe a CHAQUE carreau amene au ras. Monte le combo (borne par un plancher de rythme) et rearme le
-- reset. Rien d'autre : pas de FX, pas de son, c'est le client qui reagit au changement d'attribut.
function ComboService.registerCut(player: Player)
	local s = state[player]
	if not s then
		return
	end
	local now = os.clock()

	-- Plancher : on ne monte le compteur qu'a un rythme lisible. Un carreau fini pendant le plancher ne fait pas
	-- monter cette fois, et n'arme pas non plus de reset. Ce n'est pas grave : la prochaine montee (au plus tard
	-- MIN_INTERVAL apres, bien avant RESET_TIMEOUT) rearmera le reset. Le combo tient donc en pleine coupe.
	if now - s.lastBump < ComboConfigs.MIN_INTERVAL then
		return
	end

	s.combo += 1
	s.lastBump = now
	push(player, s.combo)

	-- Rearme le reset. Le token invalide les delays precedents : seul CE dernier carreau fini remettra le combo a
	-- zero, RESET_TIMEOUT plus tard, si aucun autre n'arrive entre-temps.
	s.token += 1
	local myToken = s.token
	task.delay(ComboConfigs.RESET_TIMEOUT, function()
		local cur = state[player]
		if cur and cur.token == myToken then
			reset(player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	state[player] = { combo = 0, lastBump = 0, token = 0 }
	push(player, 0)
end

local function onPlayerRemoving(player: Player)
	state[player] = nil
end

function ComboService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Joueurs deja la (demarrage a chaud en Studio).
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return ComboService
