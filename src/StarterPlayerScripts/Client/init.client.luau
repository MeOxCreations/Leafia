--!strict
-- Bootstrap CLIENT unique. Demarre les controllers, rien d'autre.
-- Rappel de separation des roles : le client fait UI / FX / prediction. Le serveur decide.

local ToolController = require(script.ToolController)
ToolController.init()

print("[Client] Pret")
