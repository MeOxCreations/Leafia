--!strict
-- Bootstrap SERVEUR unique. Il ne fait QUE deux choses : creer les remotes, puis demarrer les services.
-- Aucune logique de gameplay ici. Des qu'une regle de jeu apparait dans ce fichier, elle doit partir dans son
-- propre XxxService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local PlacesConfig = require(ReplicatedStorage.Modules.Configs.PlacesConfig)

RemoteSetup.init()

-- PLACE TUTORIAL (didacticiel) : sous-ensemble TAILLE + admin. Pas de save / plot / mailbox / economie persistante ici.
-- Tout le code est synce (meme src que Leafia), on n'INIT que le necessaire. La taille marche ; grantXp / grantCoins
-- sont des no-op (leurs services ne sont pas init ici). Le `return` coupe la sequence principale ci-dessous.
if game.PlaceId == PlacesConfig.TUTORIAL then
	require(script.CharacterService).init()
	require(script.ToolService).init()
	require(script.ToolStartService).init()
	require(script.HedgeService).init()
	require(script.HedgeCellService).init()
	require(script.HedgeBranchService).init()
	require(script.HedgeGroundService).init()
	require(script.HedgeStockService).init()
	require(script.ComboService).init()
	require(script.HedgeCutService).init()
	-- Echelle COMPLETE dans le tuto (portage + grimpe) : on l'ENSEIGNE ici (les grandes haies). Le "magnet" precedent
	-- venait surtout du rail de portage qui gelait sur getMoveVector (corrige) ; le drapeau de portage (CarryUtils) coupe deja
	-- la grimpe pendant qu'on porte. Necessite la VRAIE echelle de jeu dans la map (pas le rig d'anim Escabaut_..._rig).
	require(script.LadderMoveService).init()
	require(script.LadderZoneService).init()
	require(script.TeleportService).init()
	require(script.AdminCommandService).init() -- pour les commandes de test tuto / hub
	require(script.TutorialService).init() -- place le joueur sur RootSpawnPlayer (+ 1re haie guidee a venir)
	-- Animations d'ambiance (plantes + PNJ qui respirent, dont Papi). Ici AUSSI : les IDs sont dans la config (donc
	-- synces par Rojo), il n'y a rien a recopier dans cette place. Ordre indifferent.
	require(script.AmbientAnimService).init()
	-- Papi se promene autour de sa maison. Apres AmbientAnimService, dont il ne depend pas, mais qui ne doit PLUS
	-- piloter son Animator : c'est ce service qui possede ses deux animations.
	require(script.NpcWanderService).init()
	-- TONDEUSE : le geste central s'apprend ICI. Ce service ne fait que dire QUI porte quelle tondeuse
	-- (soudure au HRP) ; il ne coupe rien, la coupe est cliente. Necessite un Model "Tondeuse" dans la map.
	require(script.MowService).init()
	-- SEAU : meme raison que la tondeuse ci-dessus. Sans cette ligne le code est bien synce mais personne ne
	-- l'appelle : aucun prompt, aucun log, aucune erreur -- la signature d'un service gate hors de sa place.
	-- Necessite le model "Bin" dans la MAP du tuto (Rojo ne synchronise pas le Workspace).
	require(script.BinCarryService).init()
	-- RATEAU : il ramasse les tas que la taille laisse au sol. Present dans le tuto AUSSI, parce que c'est ici
	-- qu'on apprend la taille, donc ici que les premiers tas apparaissent. APRES HedgeStockService, qui les pose.
	require(script.RakeService).init()
	-- CAMION : un prompt E a l'arriere ouvre sa porte. TUTO UNIQUEMENT tant que le camion n'existe que dans cette
	-- map -- le declarer ailleurs ferait crier un avertissement pour un objet absent A RAISON, et un warn sur un
	-- cas normal finit par etre ignore.
	-- Necessite le model "Truck" et sa part "DoorBack" dans la MAP (Rojo ne synchronise pas le Workspace).
	require(script.TruckService).init()
	print("[Server] Leafia TUTO demarre")
	return
end

-- Les services se declarent UN PAR UN, dans l'ordre voulu. C'est volontairement explicite : quand un service
-- en attend un autre (data avant economie, par exemple), l'ordre se lit ici en clair.

-- EN PREMIER : la sauvegarde. Tout service qui devra lire / ecrire des donnees joueur passe par lui.
local DataService = require(script.DataService)
DataService.init()

local CharacterService = require(script.CharacterService)
CharacterService.init()

-- ToolService avant ToolStartService : le second lit l'outil tenu par le premier.
local ToolService = require(script.ToolService)
ToolService.init()

local ToolStartService = require(script.ToolStartService)
ToolStartService.init()

-- Apres CharacterService : HedgeService lui demande le ralentissement, il ne l'applique pas lui-meme.
local HedgeService = require(script.HedgeService)
HedgeService.init()

-- APRES HedgeService : c'est lui qui pose les etiquettes sur les haies, et HedgeCellService pave celles qui
-- sont deja etiquetees au demarrage.
local HedgeCellService = require(script.HedgeCellService)
HedgeCellService.init()

-- Apres HedgeService, qui pose les etiquettes. Independant des carreaux : la couche de branches est du decor
-- pose a l'interieur de la haie, elle ne sait rien de ce qui se taille dessus.
local HedgeBranchService = require(script.HedgeBranchService)
HedgeBranchService.init()

-- Apres HedgeService, qui pose les etiquettes. Independant du reste : la terre est un decor pose sous la haie,
-- elle ne sait rien de ce qui pousse dessus.
local HedgeGroundService = require(script.HedgeGroundService)
HedgeGroundService.init()

-- Apres HedgeService, qui pose les etiquettes. Independant des carreaux : les zones de depot bordent la haie,
-- elles ne dependent pas de ce qui pousse dessus.
local HedgeStockService = require(script.HedgeStockService)
HedgeStockService.init()

-- Progression : XP gagnee en accomplissant (tailler, pour l'instant). RUNTIME seulement, pas de sauvegarde. Avant
-- HedgeCutService, qui l'appelle a chaque carreau amene au ras.
local ExperienceService = require(script.ExperienceService)
ExperienceService.init()

-- Combo de coupe (compteur qui monte tant qu'on taille, retombe a l'arret). RUNTIME. Avant HedgeCutService, qui
-- l'appelle sur le meme signal que l'XP (un carreau amene au ras).
local ComboService = require(script.ComboService)
ComboService.init()

-- Economie : pieces + reputation. RUNTIME (pas de sauvegarde tant que le gain n'est pas branche). Independant :
-- il pose les attributs a 0 des le join pour que le CurrencyUI soit vivant. Le futur systeme de quetes appellera
-- CurrencyService.grantCoins a la fin d'un chantier (le cheque).
local CurrencyService = require(script.CurrencyService)
CurrencyService.init()

-- EN DERNIER : la coupe a besoin des carreaux poses, du contact en cours et de l'outil tenu.
local HedgeCutService = require(script.HedgeCutService)
HedgeCutService.init()

-- Autorite serveur sur la POSITION des echelles (repose synchronisee). Independant du reste.
local LadderMoveService = require(script.LadderMoveService)
LadderMoveService.init()

-- Genere les zones de detection "prise d'echelle" (invisibles) + leur marquage beams, des deux cotes de chaque
-- echelle. Repliquees, donc detectees et vues par tous.
local LadderZoneService = require(script.LadderZoneService)
LadderZoneService.init()

-- Teleport vers les chantiers (autre place de l'experience). Squelette : rien ne part tant qu'une mission ne l'appelle.
local TeleportService = require(script.TeleportService)
TeleportService.init()

-- Autorite serveur sur le PLOT choisi par chaque joueur (runtime pour l'instant). AVANT MailboxService : ce dernier
-- lit PlotService pour n'ouvrir que la boite du plot POSSEDE.
local PlotService = require(script.PlotService)
PlotService.init()

-- Boite aux lettres (une PAR plot) : E dessus joue son animation d'ouverture (point d'entree des futurs chantiers).
-- Il retrouve les modeles poses en Studio dans chaque Slot et leur colle un ProximityPrompt. N'ouvre que SA boite.
local MailboxService = require(script.MailboxService)
MailboxService.init()

-- Herbe decorative (TEST) : grille de brins animes + couleur en bruit de Perlin, sur le sol de chaque plot. Habillage,
-- pas du gameplay. Apres PlotService (il lui faut les plots) ; genere en tache de fond, ne bloque pas le boot.
local GrassService = require(script.GrassService)
GrassService.init()

-- Tondeuse PORTEE : autorite sur qui pousse quelle tondeuse (soudure au HRP, comme l'echelle). Ne coupe RIEN --
-- l'herbe est cliente, c'est MowController qui la tond. Ordre indifferent : il n'ecoute qu'un remote et le Workspace.
local MowService = require(script.MowService)
MowService.init()

-- Autorite serveur sur le SEAU porte (soudure au torse, repose au sol). Independant du reste : il n'ecoute
-- qu'un remote et le Workspace.
local BinCarryService = require(script.BinCarryService)
BinCarryService.init()

-- RATEAU : ramasse les petits tas laisses au sol par la taille et les rassemble en gros tas.
-- APRES HedgeStockService, qui est celui qui POSE ces tas : sans lui il n'y aurait rien a ramasser.
local RakeService = require(script.RakeService)
RakeService.init()

-- Animations d'ambiance : les plantes (arbres, buissons) et les PNJ qui respirent sur place. Boucles jouees cote
-- serveur, donc repliquees a tous. Habillage, pas du gameplay. Ordre indifferent : il ne lit aucun autre service,
-- il ne fait que balayer la map.
local AmbientAnimService = require(script.AmbientAnimService)
AmbientAnimService.init()

-- PNJ qui se promenent (Papi autour de sa maison). Le chemin vient de PathfindingService, qui connait deja les
-- obstacles de la map. Ce service POSSEDE les animations de ses PNJ : AmbientAnimService ne doit pas les toucher,
-- deux ecrivains sur le meme Animator finiraient par se battre. Ordre indifferent.
local NpcWanderService = require(script.NpcWanderService)
NpcWanderService.init()

-- Console admin : recoit les commandes tapees (remote Admin/AdminCommand), verifie l'acces et dispatche vers les
-- services (Currency, Experience, Data). En dernier : il APPELLE ces services au moment des commandes, pas a l'init.
local AdminCommandService = require(script.AdminCommandService)
AdminCommandService.init()

-- Filtre serveur des noms (company) via TextService (Roblox) : le seul endroit ou FilterStringAsync peut s'appeler.
-- Repond au remote Name/FilterName. Ordre indifferent (ne depend d'aucun autre service).
local NameFilterService = require(script.NameFilterService)
NameFilterService.init()

-- Saves (companies) : 3 slots persistes par joueur (create / rename / delete / select). Autorite serveur. Depend de
-- DataService (le profil) et NameFilterService (filtre du nom) -> apres eux.
local CompanyService = require(script.CompanyService)
CompanyService.init()

print("[Server] Leafia demarre")
