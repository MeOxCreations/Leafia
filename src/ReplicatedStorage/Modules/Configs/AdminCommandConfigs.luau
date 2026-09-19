--!strict
-- Console admin : la LISTE des commandes (data pure, lue par le predicteur cote client ET par le service cote
-- serveur) + la liste des UserId admins. Une seule EXCEPTION a "zero logique" : isAdmin(), la politique d'acces,
-- centralisee ici pour que client (masque l'UI) et serveur (autorite) decident PAREIL.

local RunService = game:GetService("RunService")

local AdminCommandConfigs = {}

export type Command = {
	name: string, -- le mot-cle tape (minuscules)
	usage: string, -- forme complete affichee dans le predicteur
	description: string, -- ce que ca fait
}

-- L'ordre = l'ordre d'affichage dans le predicteur.
local COMMANDS: { Command } = {
	{ name = "help", usage = "help", description = "Liste toutes les commandes" },
	{ name = "coins", usage = "coins <montant> [joueur]", description = "Donne des pieces" },
	{ name = "reputation", usage = "reputation <montant> [joueur]", description = "Donne de la reputation" },
	{ name = "xp", usage = "xp <carreaux> [joueur]", description = "Donne de l'XP (1 carreau = une case taillee)" },
	{ name = "level", usage = "level <niveau> [joueur]", description = "Fixe le niveau" },
	{ name = "resetdata", usage = "resetdata [joueur]", description = "Remet a zero pieces, reputation, XP et save" },
	{ name = "tuto", usage = "tuto [joueur]", description = "Teleporte vers le didacticiel (place Tutorial)" },
	{ name = "hub", usage = "hub [joueur]", description = "Teleporte vers le hub principal (Leafia)" },
	-- CLIENTE : traitee par AdminCommandController et jamais envoyee au serveur. Rejouer une animation
	-- d'interface ne quitte pas cet ecran.
	{ name = "tasks", usage = "tasks [off]", description = "Rejoue le bandeau d'objectifs (3 taches de demo)" },
	-- CLIENTE aussi : affiche les deux notifications (bas au milieu + laterales), pour verifier leur dessin.
	{ name = "notif", usage = "notif", description = "Affiche des notifications de test (bas + cote)" },
	{ name = "tutodone", usage = "tutodone [joueur]", description = "Marque le tuto fini sur la save active (START entre dans le jeu)" },
}

-- UserId autorises sur les VRAIS serveurs, EN PLUS du proprietaire du jeu (admin d'office, voir isAdmin). En
-- Studio, tout le monde est admin (c'est toi qui testes).
local ADMIN_USER_IDS: { number } = {
	-- 123456789,
}

AdminCommandConfigs.COMMANDS = COMMANDS
AdminCommandConfigs.ADMIN_USER_IDS = ADMIN_USER_IDS

-- Politique d'acces. Studio -> toujours admin (le dev). Sinon -> le proprietaire du jeu, ou un UserId de la liste.
-- Le serveur reste l'autorite : cote client ca ne fait que decider si on affiche la console.
function AdminCommandConfigs.isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	-- LE PROPRIETAIRE DU JEU, sans rien recopier. Ne couvre qu'un jeu possede par un COMPTE : possede par un
	-- groupe, CreatorId designe le groupe, et il faut alors la liste ci-dessus.
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return table.find(ADMIN_USER_IDS, player.UserId) ~= nil
end

return AdminCommandConfigs
