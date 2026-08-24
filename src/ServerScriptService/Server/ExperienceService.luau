--!strict
-- PROGRESSION du joueur : gagner de l'XP en accomplissant des taches (pour l'instant : tailler des haies) et monter
-- de niveau. AUTORITE serveur. Le client (ExperiencesController) ne fait qu'AFFICHER les attributs qu'on pose ici.
--
-- La progression (niveau + xp DANS le niveau + carreaux tailles) est la VUE LIVE de la company ACTIVE : setState la
-- charge depuis la company a l'entree (appele par CompanyService), et chaque gain la REECRIT dans la company active
-- (writeToCompany) -> ca persiste et alimente la carte de save. Hors company active (menu, ActiveSlot 0), rien n'est ecrit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExperienceConfigs = require(ReplicatedStorage.Modules.Configs.ExperienceConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local DataService = require(script.Parent.DataService)

local ExperienceService = {}

-- xp = XP DANS le niveau courant (pas cumulee). flashing = level up en cours d'affichage (barre tenue pleine).
type State = { level: number, xp: number, flashing: boolean, hedges: number }
local state: { [Player]: State } = {}
local sideNotify: RemoteEvent? = nil -- notif laterale de montee de niveau (recuperee a l'init)

-- XP pour passer de `level` a `level+1`. Bornee a 1 (jamais 0 : on divise par elle pour la fraction de remplissage).
local function xpForLevel(level: number): number
	return math.max(1, math.floor(ExperienceConfigs.LEVEL_BASE * ExperienceConfigs.LEVEL_GROWTH ^ (level - 1)))
end

-- Pousse l'etat courant vers le client (attributs sur le joueur). SetAttribute se replique tout seul : pas de remote,
-- pas de file a saturer, le client lit la valeur des qu'il est pret.
local function push(player: Player)
	local s = state[player]
	if not s then
		return
	end
	player:SetAttribute(ExperienceConfigs.LEVEL_ATTRIBUTE, s.level)
	player:SetAttribute(ExperienceConfigs.FILL_ATTRIBUTE, s.xp / xpForLevel(s.level))
end

-- Ecrit la progression dans la company ACTIVE (persiste + carte de save : niveau + carreaux tailles). No-op au menu.
local function writeToCompany(player: Player)
	local s = state[player]
	local profile = DataService.get(player)
	if not (s and profile) then
		return
	end
	local slot = profile.Data.ActiveSlot
	local company = if slot >= 1 then profile.Data.Companies[slot] else nil
	if type(company) == "table" then
		company.Level = s.level
		company.Xp = s.xp
		company.HedgesTrimmed = s.hedges
	end
end

-- Charge la progression DEPUIS la company (a l'entree). Appele par CompanyService quand le joueur entre dans une company.
function ExperienceService.setState(player: Player, level: number, xp: number, hedges: number)
	state[player] = { level = math.max(1, math.floor(level)), xp = math.max(0, xp), flashing = false, hedges = math.max(0, math.floor(hedges)) }
	push(player)
end

-- Grante de l'XP. `cells` = nb de carreaux amenes au ras. Peut passer plusieurs niveaux d'un coup (gros gain).
-- Appele par la coupe (HedgeCutService.biteAt) : UN seul point, pour tous les outils et tous les contextes.
function ExperienceService.grantXp(player: Player, cells: number)
	local s = state[player]
	if not s or cells <= 0 then
		return
	end
	s.xp += cells * ExperienceConfigs.XP_PER_CELL
	s.hedges += cells -- stat de carriere : total de carreaux amenes au ras (chip HEDGES)

	local leveledUp = false
	while s.xp >= xpForLevel(s.level) do
		s.xp -= xpForLevel(s.level)
		s.level += 1
		leveledUp = true
	end

	if leveledUp then
		-- Barre PLEINE un court instant, puis le reste du nouveau niveau : le level up se LIT (gain, pas reflux). On
		-- suspend les push pendant le flash (flashing), sinon la coupe continue redescendrait la barre a la frame suivante.
		s.flashing = true
		player:SetAttribute(ExperienceConfigs.LEVEL_ATTRIBUTE, s.level)
		player:SetAttribute(ExperienceConfigs.FILL_ATTRIBUTE, 1)
		task.delay(ExperienceConfigs.LEVEL_UP_FLASH, function()
			-- Le joueur peut etre parti (state efface) ou avoir re-level pendant le flash (un nouveau delay a repris) :
			-- on ne pousse que si CET etat est toujours celui du joueur et qu'aucun autre flash n'est en cours.
			if state[player] == s and s.flashing then
				s.flashing = false
				push(player)
			end
		end)

		-- Notif laterale de montee de niveau (cote client). Le joueur est forcement en jeu (il vient de tailler), donc
		-- il ecoute deja : envoi sur.
		if sideNotify then
			sideNotify:FireClient(player, {
				kind = "Success",
				title = "LEVEL " .. s.level,
				description = "Nice! Your business is growing.",
			})
		end
	elseif not s.flashing then
		push(player)
	end
	writeToCompany(player) -- persiste niveau / xp / carreaux dans la company active
end

-- ADMIN (console) : fixe directement le niveau (test de progression), XP remise a 0 dans le niveau. Borne a 1 mini.
function ExperienceService.setLevel(player: Player, level: number)
	local s = state[player]
	if not s then
		return
	end
	s.level = math.max(1, math.floor(level))
	s.xp = 0
	s.flashing = false
	push(player)
	writeToCompany(player)
end

-- ADMIN (console) : remet la progression a zero (niveau 1, aucune XP).
function ExperienceService.resetPlayer(player: Player)
	local s = state[player]
	if not s then
		return
	end
	s.level = 1
	s.xp = 0
	s.flashing = false
	push(player)
	writeToCompany(player)
end

local function onPlayerAdded(player: Player)
	state[player] = { level = 1, xp = 0, flashing = false, hedges = 0 }
	push(player)
end

local function onPlayerRemoving(player: Player)
	state[player] = nil
end

function ExperienceService.init()
	local remote = RemoteSetup.getRemote("SideNotify", "UI")
	if remote and remote:IsA("RemoteEvent") then
		sideNotify = remote
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Joueurs deja la (demarrage a chaud en Studio).
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return ExperienceService
