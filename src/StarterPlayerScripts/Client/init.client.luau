--!strict
-- Bootstrap CLIENT unique. Demarre les controllers, rien d'autre.
-- Rappel de separation des roles : le client fait UI / FX / prediction. Le serveur decide.

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

print("[Client] Pret")
