--!strict
-- Bootstrap CLIENT unique. Demarre les controllers, rien d'autre.
-- Rappel de separation des roles : le client fait UI / FX / prediction. Le serveur decide.

-- PRECHARGEMENT DES ANIMS. On demande a Roblox de telecharger toutes les animations du jeu EN AVANCE, dans un
-- thread a part (non bloquant : le jeu demarre pendant que ca charge). Sans ca, la PREMIERE lecture d'une anim
-- provoque un micro-freeze le temps de la recuperer du serveur d'assets. Surtout visible sur le taille-haie et
-- l'echelle, qui enchainent plusieurs pistes.
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local animations = game:GetService("ReplicatedStorage"):FindFirstChild("Animations")
	if not animations then
		return
	end
	local toLoad: { Instance } = {}
	for _, descendant in ipairs(animations:GetDescendants()) do
		if descendant:IsA("Animation") then
			table.insert(toLoad, descendant)
		end
	end
	if #toLoad > 0 then
		ContentProvider:PreloadAsync(toLoad)
		print(`[Client] {#toLoad} animation(s) prechargee(s)`)
	end
end)

local PlacesConfig = require(game:GetService("ReplicatedStorage").Modules.Configs.PlacesConfig)

-- PLACE TUTORIAL : controllers TAILLE + feel + admin uniquement. Pas de plot-select / save UI / mailbox / HUD eco,
-- dont les ScreenGui n'existent pas dans la place tuto (ils timeouteraient). Le `return` coupe la sequence principale.
if game.PlaceId == PlacesConfig.TUTORIAL then
	local RS = game:GetService("ReplicatedStorage")
	require(script.CursorController).init()
	require(script.ClickSoundController).init()
	require(script.ButtonSlimeController).init()
	require(script.FootstepController).init()
	require(script.TeleportController).init()
	require(script.CameraController).init()
	require(script.ToolController).init()
	require(script.HedgeController).init()
	require(script.HedgeLeafController).init()
	require(RS.Modules.UI.Hedge.HedgeHologramHandler).init()
	require(RS.Modules.UI.Core.Toast).init()
	require(script.ComboController).init()
	require(RS.Modules.UI.Notification.SideNotificationHandler).init()
	-- Echelle COMPLETE dans le tuto (on l'enseigne) : grimpe + portage + auto-equip. Le flag LeafiaCarryingLadder coupe la
	-- grimpe pendant le portage (pas d'auto-accroche a sa propre echelle). Necessite la VRAIE echelle de jeu dans la map.
	require(script.LadderController).init()
	require(script.LadderMoveController).init()
	require(script.AdminCommandController).init()
	-- Herbe de zone (remplissage + ecrasement au passage). Ici AUSSI : tout est local et pilote par la config,
	-- donc il n'y a rien a recopier dans cette place. Ordre indifferent.
	require(script.GrassZoneController).init()
	-- Nuages : du ciel, rien d'autre. Local, aucun reseau. Ordre indifferent.
	require(script.CloudController).init()

	-- Musique de fond du TUTO : MusicBuild4 (du dossier des musiques de build), en boucle. Clonee (le Sound d'origine reste
	-- intact), volume force ici (le reglage Studio est ignore). En task.spawn : le Sound peut arriver un poil apres le boot.
	task.spawn(function()
		local SoundService = game:GetService("SoundService")
		local node: Instance? = SoundService
		for _, name in ipairs({ "Sounds", "Game", "Musics", "Build", "MusicBuild4" }) do
			node = node and node:WaitForChild(name, 10)
		end
		if node and node:IsA("Sound") then
			local music = node:Clone()
			music.Name = "LeafiaTutoMusic"
			music.Looped = true
			music.Volume = 0.15 -- a regler a l'oreille (0.15 = le niveau confortable de la musique de build)
			music.Parent = SoundService
			music:Play()
		end
	end)

	-- TEMP (test de la boite de dialogue) : joue la narration d'intro UNE fois, ~1.5 s apres le 1er spawn, pour regler
	-- le visuel et le texte avec le joueur. A RETIRER quand le tuto la declenchera pour de vrai (mission / TutorialService).
	task.spawn(function()
		local plr = game:GetService("Players").LocalPlayer
		local Dialogue = require(RS.Modules.UI.Core.Dialogue)
		if not game:IsLoaded() then
			game.Loaded:Wait() -- attendre que TOUT soit charge
		end
		if not plr.Character then
			plr.CharacterAdded:Wait() -- attendre que le joueur soit spawn
		end
		task.wait(3) -- puis 3 s avant d'afficher le dialogue
		Dialogue.play({
			-- EN ANGLAIS, comme tout texte vu par le joueur : le traducteur automatique de Roblox part de l'anglais.
			-- Vocabulaire simple : le public est jeune, et une phrase qu'on ne comprend pas casse l'immersion.
			{ speaker = "Papi", emotion = "wink", text = "There you are, " .. plr.DisplayName .. "! I knew you'd come." },
			{
				speaker = "Papi",
				emotion = "happy",
				text = "Look at this. My old hedge trimmer. It has cut more hedges than you can count.",
			},
			{
				speaker = "Papi",
				emotion = "sad",
				text = "I can't use it anymore. My back hurts too much.",
			},
			{
				speaker = "Papi",
				emotion = "sad",
				text = "And all my customers are gone. Their gardens are a mess now.",
			},
			{
				speaker = "Papi",
				emotion = "normal",
				text = "So I am giving you my business. The tools, the customers, everything.",
			},
			{
				speaker = "Papi",
				emotion = "happy",
				text = "Start with that hedge over there. Show me what you can do.",
			},
			{
				speaker = "Papi",
				emotion = "wink",
				text = "And don't make me look bad, kid!",
			},
		})
	end)

	print("[Client] Pret (tuto)")
	return
end

-- Curseur custom (cache le curseur systeme, suit la souris). Ordre indifferent : il ne partage rien avec les autres.
local CursorController = require(script.CursorController)
CursorController.init()

-- Son de clic global (confort). Ordre indifferent : il n'ecoute que l'input.
local ClickSoundController = require(script.ClickSoundController)
ClickSoundController.init()

-- Effet slime sur TOUS les boutons de l'UI (survol + clic). Ordre indifferent : il attend PlayerGui en tache de
-- fond et n'ajoute qu'un comportement par-dessus les interfaces faites dans Studio.
local ButtonSlimeController = require(script.ButtonSlimeController)
ButtonSlimeController.init()

-- Son de pas au sol (remplace le son de marche par defaut de Roblox). Ordre indifferent.
local FootstepController = require(script.FootstepController)
FootstepController.init()

-- Ecran de transition de teleport (SetTeleportGui). Ordre indifferent : il ne fait que declarer le GUI a Roblox.
local TeleportController = require(script.TeleportController)
TeleportController.init()

-- CameraController avant ToolController : il demarre CameraEffects (le seul ecrivain du FieldOfView), dont
-- ToolController se sert pour l'a-coup du tirage.
local CameraController = require(script.CameraController)
CameraController.init()

local ToolController = require(script.ToolController)
ToolController.init()

-- HedgeController EN DERNIER : sa camera scriptee applique le decalage compose par CameraEffects, qui doit
-- donc avoir ete calcule cette frame. L'ordre des connexions RenderStepped suit l'ordre de ces init.
local HedgeController = require(script.HedgeController)
HedgeController.init()

-- Ordre indifferent : le balancement des feuilles tourne en Heartbeat, apres le rendu, et ne partage rien avec
-- les autres controllers.
local HedgeLeafController = require(script.HedgeLeafController)
HedgeLeafController.init()

-- Herbe de zone : remplit les parts "ZoneGrass..." de touffes et les couche sous les pieds. 100% LOCAL (rien ne
-- transite), contrairement au decor vegetal qui, lui, est joue par le serveur. Ordre indifferent.
local GrassZoneController = require(script.GrassZoneController)
GrassZoneController.init()

-- Nuages qui traversent le ciel en boucle. 100% LOCAL, comme l'herbe : c'est du decor, rien ne transite.
-- Ordre indifferent, il ne partage rien avec les autres.
local CloudController = require(script.CloudController)
CloudController.init()

-- HedgeMeshController n'est PLUS demarre : il a servi de banc d'essai a la texture repetee, qui est maintenant
-- dans HedgeBranchService. Le laisser tourner poserait une plaque flottante devant le joueur a chaque spawn.
-- Le fichier reste au cas ou tu veuilles remesurer quelque chose dessus.

-- Interface : elle ne fait que LIRE des attributs poses par le serveur, donc son ordre n'a pas d'importance.
local HedgeHologramHandler = require(game:GetService("ReplicatedStorage").Modules.UI.Hedge.HedgeHologramHandler)
HedgeHologramHandler.init()

-- Toasts : primitive reutilisable. Ecoute le remote UI/Notify (serveur -> client) et expose Toast.show pour
-- les notifications purement client. Ordre indifferent, elle ne depend d'aucun autre controller.
local Toast = require(game:GetService("ReplicatedStorage").Modules.UI.Core.Toast)
Toast.init()

-- Jauge d'experience qui SUIT le joueur (WorldAnchor). Ordre indifferent : elle ne fait que suivre le perso et lire
-- l'attribut d'XP pose par le serveur (a venir).
local ExperiencesController = require(script.ExperiencesController)
ExperiencesController.init()

-- Combo de coupe : texte "xN" qui SUIT le joueur (WorldAnchor) et monte tant qu'il taille. Ordre indifferent : il ne
-- fait que suivre le perso et lire l'attribut de combo pose par le serveur.
local ComboController = require(script.ComboController)
ComboController.init()

-- Economie (HUD fixe en haut) : pieces + reputation. Ordre indifferent : il ne fait que lire les attributs poses
-- par le serveur et remplir CoinsText / ReputationText dans CurrencyUI.
local CurrencyController = require(script.CurrencyController)
CurrencyController.init()

-- Barre de NAVIGATION du HUD (bas de l'ecran). Cadre : onglets inertes pour l'instant (les sections n'existent pas encore),
-- feuille centrale -> arbre de competences (a venir). Ne s'affiche que quand le joueur a un plot. Ordre indifferent.
local HudNavHandler = require(game:GetService("ReplicatedStorage").Modules.UI.Hud.HudNavHandler)
HudNavHandler.init()

-- Notifications laterales (bas droite). Step 1 : ouverture / fermeture au clic (resize + arrondi + contour). Ordre
-- indifferent, elle ne fait que cabler les boutons des notifications existantes.
local SideNotificationHandler =
	require(game:GetService("ReplicatedStorage").Modules.UI.Notification.SideNotificationHandler)
SideNotificationHandler.init()

-- PROTOTYPE escabeau (socle minimal) : entrer dans une zone de detection -> aimant + anim UpDown. A promouvoir en
-- LadderController + LadderService, ou a retirer. Ne fait rien tant qu'on n'entre pas dans une zone.
local LadderController = require(script.LadderController)
LadderController.init()

-- PROTOTYPE : deplacer l'echelle (E dans box_detecte_For_Move -> prise + repli synchronise). Increment 1.
local LadderMoveController = require(script.LadderMoveController)
LadderMoveController.init()

-- Boite aux lettres : dessine le prompt stylise (InteractionPrompt) a la place du prompt Roblox par defaut. Ordre
-- indifferent : il ne fait qu'ecouter ProximityPromptService et afficher.
local MailboxController = require(script.MailboxController)
MailboxController.init()

-- Ecran de selection de plot (entree du jeu) : camera qui orbite un plot + boutons Claim / Start. Ordre indifferent :
-- il attend son UI (LoadSaveUI) en tache de fond.
local PlotSelectController = require(script.PlotSelectController)
PlotSelectController.init()

-- Mode BUILD (amenagement du plot facon Sims). Increment 1 : entrer / sortir + quadrillage au sol. Ordre indifferent :
-- il lit l'attribut de plot au moment d'entrer, il ne depend d'aucun autre controller au boot.
local BuildController = require(script.BuildController)
BuildController.init()

-- L'onglet BUILD de la nav entre / sort du mode build (acces PC ET mobile, sans la touche B temporaire).
HudNavHandler.onSelect = function(id: string)
	if id == "build" then
		BuildController.toggle()
	end
end

-- Et l'inverse : pendant le mode build, on CACHE la nav bar (l'UI de build prend le relais). Couvre tous les declencheurs
-- (bouton nav ET touche B), car BuildController appelle onStateChanged a chaque enter / exit.
BuildController.onStateChanged = function(active: boolean)
	HudNavHandler.setBuildActive(active)
end

-- Console admin (F2). Ordre indifferent : elle ne se construit que pour un admin, au 1er toggle, et n'ecoute que
-- l'input. Le serveur reste l'autorite sur ce qu'une commande fait.
local AdminCommandController = require(script.AdminCommandController)
AdminCommandController.init()

print("[Client] Pret")
