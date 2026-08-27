--!strict
-- Declaration CENTRALE des remotes. Un seul endroit ou ajouter un remote, range par feature.
-- Le serveur appelle RemoteSetup.init() au boot (cree les instances). Tout le monde lit via getRemote().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = {}
local createdRemotes: { [string]: RemoteEvent | RemoteFunction } = {}

local E, F = "Event", "Function"

-- Format : { nom, E ou F, dossier }
-- Vide au demarrage : on n'ajoute un remote QUE quand une feature en a reellement besoin. Une liste de
-- remotes "au cas ou" finit toujours par contenir des morts qu'on n'ose plus supprimer.
local REMOTES: { { any } } = {
	-- [ TOOL ] --
	-- Le client demande, il n'ordonne pas : il n'envoie AUCUN argument. Le serveur sait deja ce que le joueur
	-- tient, donc il n'y a rien a valider et rien a falsifier.
	{ "ToggleTool", E, "Tool" },
	{ "SelectTool", E, "Tool" }, -- equipe un outil par NOM (emplacements clavier 1/2). Le client envoie le nom, serveur valide.
	-- Clic gauche. Aucun argument : le serveur connait deja l'etat de l'outil, donc il n'y a rien a valider et
	-- rien a falsifier.
	{ "ActivateTool", E, "Tool" },
	-- Accelerateur des lames : le client dit s'il maintient le clic. UN argument booleen, valide cote serveur.
	{ "SetThrottle", E, "Tool" },

	-- [ HEDGE ] --
	-- Position MONDE du centre de la lame. UN Vector3, borne cote serveur a une distance plausible du joueur.
	--
	-- POURQUOI UN REMOTE ICI alors qu'on evite d'en ajouter. La pose des bras est jouee chez le client et
	-- pilotee image par image : Roblox replique le DEMARRAGE d'une animation, pas son defilement. Le serveur
	-- voit donc la lame figee, pendant que le joueur la voit suivre sa souris.
	--
	-- On envoie la position REELLE de la lame et non la hauteur visee : les deux different, parce que rien ne
	-- garantit qu'a 80 pour cent de visee le bras soit a 80 pour cent de la hauteur de la haie. C'est ce qui
	-- faisait couper au-dessus de la lame, la ou pointait le curseur.
	-- Le serveur garde l'autorite sur la vitesse de coupe, sur la haie concernee, et borne la portee.
	{ "SetAim", E, "Hedge" },
	-- Un COUP de cisaille (outil clic-par-clic). Aucun argument : le client dit juste "j'ai clique", le serveur
	-- decide s'il coupe (outil clic-par-clic ? pret ? en contact ?) et de combien. Anti-spam borne cote serveur.
	-- Le taille-haie n'utilise pas ce remote : il coupe en continu tant que la gachette est maintenue.
	{ "CutSnip", E, "Hedge" },
	-- Taille DEPUIS L'ECHELLE. UN booleen : le client dit "je suis en haut, pret a tailler le dessus" (true) ou
	-- "j'ai fini" (false). Le serveur ne fait PAS confiance a une haie envoyee : il CHOISIT lui-meme la haie la
	-- plus proche du joueur. Sert a activer la coupe alors que l'aimant du sol, lui, est desengage sur l'echelle.
	{ "SetLadderWork", E, "Hedge" },
	-- SUR L'ECHELLE (accroche complete, toute phase). UN booleen. Sert a DEUX choses cote serveur : desengager
	-- l'aimant du sol tant qu'on est sur l'echelle (sinon les deux systemes se disputent le joueur dans la zone),
	-- et REJOUER le maintien de l'outil a la sortie (le garde-fou d'anim de l'echelle a pu le couper).
	{ "SetOnLadder", E, "Hedge" },

	-- [ LADDER ] --
	-- PRISE / PORTAGE / REPOSE de l'echelle. Trois arguments : l'echelle (Instance), une PHASE (string), et un CFrame
	-- optionnel (l'offset de portage, a la prise). Le serveur SOUDE l'echelle au HRP du porteur (weld) : sa position,
	-- son repli et sa rotation se repliquent alors a tous, sans flot de remotes. Phases : "grab" (soude, offset c0),
	-- "close" (repli au marqueur de prise), "rotate" (tween 180 degres, toggle), "place" (retire le weld + re-ancre +
	-- deplie), "release" (retire le weld sec : mort / respawn). Le serveur valide (vraie echelle, proprietaire, proximite).
	{ "SetLadderCarry", E, "Ladder" },
	-- MONTEE sur l'echelle. Deux arguments : l'echelle (Instance) et le CFrame de montage (face a l'echelle), ou
	-- rien a la descente. A la montee, le serveur ANCRE le HRP du grimpeur et le pose a ce CFrame (tween) : ancrer
	-- + poser cote CLIENT ne se replique pas -> les autres voyaient le grimpeur de travers. Le serveur valide
	-- (vraie echelle, montage pres de l'echelle). A la descente (rien) : il desancre.
	{ "SetLadderClimb", E, "Ladder" },

	-- [ CHARACTER ] --
	-- Sprint : le client dit s'il maintient Shift. UN argument booleen, valide cote serveur.
	{ "SetSprint", E, "Character" },

	-- [ UI ] --
	-- Toast serveur -> client. Deux arguments : le TYPE (couleur d'accent) et le TEXTE. Aucune autorite en jeu :
	-- le client se contente d'afficher ce que le serveur lui demande. Sens unique, FireClient uniquement.
	-- ATTENTION avant d'emettre : un joueur qui vient de se connecter n'ecoute pas encore (ses scripts de
	-- StarterGui ne sont copies qu'au spawn). Verifier qu'il est reellement en jeu avant FireClient.
	{ "Notify", E, "UI" },
	-- Notification LATERALE (riche) serveur -> client. UN argument : la table de donnees (kind, title, description,
	-- earn / amount, icon). Le SideNotificationHandler la recoit et spawn la notif. Aucune autorite : le client
	-- affiche ce que le serveur demande. Meme precaution que Notify : le joueur doit etre en jeu (spawne) pour ecouter.
	{ "SideNotify", E, "UI" },

	-- [ PLOT ] --
	-- Le client dit quel plot il a choisi au Start (nom du Slot, string). Le serveur VALIDE que c'est un vrai Slot
	-- et retient l'attribution par joueur. Sert a l'autorite : n'ouvrir que la boite aux lettres de SON plot, etc.
	{ "SelectPlot", E, "Plot" },

	-- [ DEV ] --
	-- OUTIL DE TEST, pas une feature. Le client dit "donne-moi des pieces de test" (aucun argument : il ne fixe pas
	-- le montant, le serveur decide). Le serveur ne branche son ecoute QUE dans Studio (RunService:IsStudio) : sur
	-- un vrai serveur ce remote est mort, aucun exploit possible. A retirer si un jour on veut zero surface dev.
	{ "DevGrantCoins", E, "Dev" },

	-- [ ADMIN ] --
	-- Console admin. RemoteFunction : le client envoie la LIGNE de commande tapee (string), le serveur verifie
	-- l'acces (Studio ou UserId liste), execute, et RENVOIE le texte de resultat affiche dans la console. Le serveur
	-- seul tranche : il re-verifie l'admin et n'execute que ce qu'il decide, le client n'ordonne rien.
	{ "AdminCommand", F, "Admin" },

	-- [ NAME ] --
	-- Filtre serveur d'un nom (company). RemoteFunction : le client envoie le nom (string), le serveur le passe au vrai
	-- filtre Roblox (TextService, appelable UNIQUEMENT cote serveur) et renvoie { ok, filtered }. ok = true si RIEN n'a
	-- ete censure. Le client n'a pas le dernier mot : c'est le serveur qui tranche si le nom est propre.
	{ "FilterName", F, "Name" },

	-- [ COMPANY ] --
	-- Saves (companies) : lister / creer / renommer / supprimer / selectionner un slot. RemoteFunctions (le client a
	-- besoin de la reponse : ok + les vues fraiches). Autorite serveur (CompanyService) : le client n'ecrit RIEN, il
	-- affiche ce que le serveur renvoie.
	{ "ListCompanies", F, "Company" },
	{ "CreateCompany", F, "Company" },
	{ "RenameCompany", F, "Company" },
	{ "DeleteCompany", F, "Company" },
	{ "SelectCompany", F, "Company" },
	{ "StartGame", F, "Company" }, -- START : le serveur decide (nouvelle save -> teleport tuto, sinon -> entree jeu)

	-- [ RAKE ] --
	-- UN COUP DE RATEAU. Aucun argument : le client dit juste "j'ai clique". Le serveur sait deja ce que le joueur
	-- tient et ou il regarde, donc il n'y a rien a valider et rien a falsifier -- il choisit lui-meme les tas
	-- attrapes. Anti-spam borne cote serveur (RakeConfigs.COOLDOWN) : envoyer mille clics ne ratisse pas plus vite.
	{ "RakeSweep", E, "Rake" },

	-- [ MOW ] --
	-- PRISE / REPOSE de la tondeuse. Deux arguments : la tondeuse (Instance) et une PHASE ("grab" ou "place").
	-- Le serveur SOUDE la tondeuse au HRP du porteur, comme l'echelle : sa position se replique alors a tous sans
	-- flot de remotes. Il valide que c'est bien une tondeuse, qu'elle est libre, et que le joueur est assez pres.
	-- Aucun CFrame envoye par le client : l'offset de portage est une CONSTANTE de config, donc rien a falsifier.
	{ "SetMowerCarry", E, "Mow" },
	-- BRAQUAGE SUR PLACE. UN nombre dans [-1, 1] : combien le joueur pousse sur le cote. Le serveur en fait pivoter
	-- la TONDEUSE (pas le corps du joueur, qui reste face a sa direction). Il borne la valeur : le client peut
	-- mentir sur l'intensite, pas sur le resultat -- l'angle final est clampe cote serveur.
	-- Envoye seulement quand la valeur CHANGE assez, pas a chaque image : tenir une touche n'envoie qu'un message.
	{ "SetMowSteer", E, "Mow" },
	-- TIRAGE DE CORDE. Aucun argument : le serveur sait deja ce que le joueur porte et dans quel etat, donc il n'y
	-- a rien a valider et rien a falsifier. Il ignore le message si la tondeuse est deja lancee.
	{ "PullMowStarter", E, "Mow" },

	-- [ TUTORIAL ] --
	-- FIN DE LA SCENE D'INTRODUCTION. Aucun argument : le serveur n'a rien a valider, il ne fait que declencher
	-- la suite -- le grand-pere qui sort de chez lui.
	--
	-- La scene est CLIENT (camera, barres, fondu) mais le grand-pere qui marche est un objet du MONDE : il doit
	-- bouger pour tout le monde, donc c'est le serveur qui le deplace. Ce remote est la couture entre les deux.
	{ "TutorialSceneDone", E, "Tutorial" },

	-- [ BIN ] --
	-- PRISE / REPOSE du SEAU. Deux arguments : le seau (Instance) et une PHASE.
	--   "grab"       : la main s'est refermee, on soude.
	--   "placeStart" : le geste de repose commence. Le seau reste en main ; seul l'elan du joueur est coupe.
	--   "place"      : la main s'est rouverte, on retire le joint et on pose au sol.
	--   "release"    : repose seche, sans geste (mort / respawn).
	-- Le serveur SOUDE le seau au torse du porteur (Motor6D) : sa position se replique alors a tous sans flot de
	-- remotes. Aucun CFrame envoye par le client -- l'offset de portage est une CONSTANTE de BinConfigs, mesuree
	-- sur le rig d'animation, donc rien a falsifier. Le serveur valide (vrai seau, libre, proximite) et decide
	-- SEUL de l'endroit ou le seau retombe (rayon vers le sol).
	{ "SetBinCarry", E, "Bin" },
}

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	-- On verifie le TYPE, pas juste la presence : si un jour un objet non-Folder porte ce nom, un cast
	-- silencieux donnerait des erreurs incomprehensibles plus loin.
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function RemoteSetup.init()
	local remotesFolder = getOrCreateFolder(ReplicatedStorage, "Remotes")

	for _, r in ipairs(REMOTES) do
		local name = r[1] :: string
		local rType = r[2] :: string
		local folder = r[3] :: string?

		local parent = folder and getOrCreateFolder(remotesFolder, folder) or remotesFolder

		if not parent:FindFirstChild(name) then
			local remote = Instance.new(rType == F and "RemoteFunction" or "RemoteEvent")
			remote.Name = name
			remote.Parent = parent
		end

		local key = folder and (folder .. "/" .. name) or name
		createdRemotes[key] = parent:FindFirstChild(name) :: RemoteEvent | RemoteFunction
	end
end

function RemoteSetup.getRemote(name: string, folder: string?): (RemoteEvent | RemoteFunction)?
	local key = folder and (folder .. "/" .. name) or name
	if createdRemotes[key] then
		return createdRemotes[key]
	end

	-- Fallback pour le CLIENT : il n'appelle jamais init(), donc son cache est vide. WaitForChild avec
	-- timeout, jamais infini : un remote absent doit renvoyer nil, pas geler le script pour la session.
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		return nil
	end

	if folder then
		local subFolder = remotesFolder:WaitForChild(folder, 10)
		if not subFolder then
			return nil
		end
		return subFolder:WaitForChild(name, 10) :: RemoteEvent | RemoteFunction
	end

	return remotesFolder:WaitForChild(name, 10) :: RemoteEvent | RemoteFunction
end

function RemoteSetup.getFolder(): Folder?
	return ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
end

return RemoteSetup
