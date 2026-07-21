--!strict
-- Bootstrap CLIENT unique. Demarre les controllers, rien d'autre.
-- Rappel de separation des roles : le client fait UI / FX / prediction. Le serveur decide.

-- CameraController avant ToolController : il demarre CameraEffects (le seul ecrivain du FieldOfView), dont
-- ToolController se sert pour l'a-coup du tirage.
local CameraController = require(script.CameraController)
CameraController.init()

local ToolController = require(script.ToolController)
ToolController.init()

local HedgeController = require(script.HedgeController)
HedgeController.init()

print("[Client] Pret")
