--!strict
-- Bootstrap SERVEUR unique. Il ne fait QUE deux choses : creer les remotes, puis demarrer les services.
-- Aucune logique de gameplay ici. Des qu'une regle de jeu apparait dans ce fichier, elle doit partir dans son
-- propre XxxService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

RemoteSetup.init()

-- Les services se declarent UN PAR UN, dans l'ordre voulu. C'est volontairement explicite : quand un service
-- en attend un autre (data avant economie, par exemple), l'ordre se lit ici en clair.

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

print("[Server] Leafia demarre")
