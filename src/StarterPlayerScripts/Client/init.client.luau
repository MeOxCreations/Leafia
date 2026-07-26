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

-- Curseur custom (cache le curseur systeme, suit la souris). Ordre indifferent : il ne partage rien avec les autres.
local CursorController = require(script.CursorController)
CursorController.init()

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

-- PROTOTYPE escabeau (socle minimal) : entrer dans une zone de detection -> aimant + anim UpDown. A promouvoir en
-- LadderController + LadderService, ou a retirer. Ne fait rien tant qu'on n'entre pas dans une zone.
local LadderController = require(script.LadderController)
LadderController.init()

-- PROTOTYPE : deplacer l'echelle (E dans box_detecte_For_Move -> prise + repli synchronise). Increment 1.
local LadderMoveController = require(script.LadderMoveController)
LadderMoveController.init()

print("[Client] Pret")
