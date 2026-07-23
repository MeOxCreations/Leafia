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

-- EN DERNIER : la coupe a besoin des carreaux poses, du contact en cours et de l'outil tenu.
local HedgeCutService = require(script.HedgeCutService)
HedgeCutService.init()

print("[Server] Leafia demarre")
