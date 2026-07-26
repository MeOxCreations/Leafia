--!strict
-- Sauvegarde du joueur via ProfileStore (loleris), avec session locking. UN profil par joueur, charge au join,
-- relache au depart. Autorite serveur : tout ce qui doit persister vit dans profile.Data.
--
-- MINIMAL VOLONTAIREMENT (regle d'or du CLAUDE.md). On ne pose PAS d'economie / progression dans le template tant
-- que le geste de tailler n'est pas valide sur de vraies personnes. Ici, juste la plomberie qui PROUVE que le
-- save/load tourne. Etoffer le template plus tard, quand le coeur est valide.
--
-- STUDIO : sans "Enable Studio Access to API Services" (parametres du jeu), ProfileStore passe en MOCK -> ca charge
-- et se comporte normalement, mais rien ne persiste entre deux tests. En jeu publie, ca sauvegarde pour de vrai.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local ProfileStore = require(ServerStorage:WaitForChild("ProfileStore"))
-- Template = valeurs par defaut d'un nouveau joueur, dans son propre module. On AJOUTE les champs la-bas, pas ici.
local TEMPLATE = require(ServerStorage:WaitForChild("DataTemplateUser"))

local PlayerStore = ProfileStore.New("PlayerData_v1", TEMPLATE)
-- Profil actif par joueur. nil = pas (encore) charge, ou deja relache.
local profiles: { [Player]: any } = {}

local DataService = {}

-- Le profil d'un joueur, ou nil s'il n'est pas charge. Les autres services LISENT / ECRIVENT profile.Data via ca.
function DataService.get(player: Player): any
	return profiles[player]
end

local function onPlayerAdded(player: Player)
	-- StartSessionAsync YIELD : le joueur peut partir pendant. Cancel arrete la tentative s'il n'est plus la.
	local profile = PlayerStore:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- Session prise ailleurs / erreur persistante : on ne joue pas sans donnees, on renvoie.
		player:Kick("Chargement des donnees impossible. Reconnecte-toi.")
		return
	end

	profile:AddUserId(player.UserId) -- conformite GDPR (associe la donnee au joueur)
	profile:Reconcile() -- complete avec les champs manquants du template

	-- Session terminee sur CE serveur (relache, ou volee par un autre serveur) : on lache le profil et on ejecte,
	-- le joueur ne doit pas continuer avec des donnees qui ne sauvegardent plus.
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Ta session de donnees s'est terminee (ouverte ailleurs ?). Reconnecte-toi.")
	end)

	-- Le joueur est-il encore la apres le yield ?
	if player.Parent == Players then
		profiles[player] = profile
		-- Preuve que save/load fonctionne : on ecrit dans Data, ca persistera.
		if profile.Data.FirstJoin == 0 then
			profile.Data.FirstJoin = os.time()
		end
		profile.Data.Sessions += 1
		print(`[DataService] {player.Name} : donnees chargees (session #{profile.Data.Sessions})`)
	else
		-- Parti pendant le chargement : on relache tout de suite pour liberer le lock.
		profile:EndSession()
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile:EndSession() -- declenche OnSessionEnd, qui nettoie profiles[player]
	end
end

function DataService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Joueurs deja presents (demarrage a chaud en Studio) : on les charge aussi, chacun dans son thread (yield).
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService
