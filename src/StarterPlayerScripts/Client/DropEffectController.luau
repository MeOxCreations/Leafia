--!strict
-- POUSSIERE DE POSE, cote client. Il ne decide de rien : le serveur dit ou un objet a touche le sol, il joue
-- l'effet chez ce joueur.
--
-- POURQUOI IL EXISTE. `ParticleEmitter:Emit()` ne se replique pas : un effet emis par le serveur n'apparait chez
-- personne. Le clone, lui, se replique -- donc on voit la part arriver dans le Workspace et rien en sortir, ce
-- qui ressemble a un effet casse alors que c'est la replication qui ne fait pas ce qu'on croit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropEffectUtils = require(ReplicatedStorage.Modules.Utils.DropEffectUtils)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local DropEffectController = {}

function DropEffectController.init()
	-- EN TACHE DE FOND : `getRemote` cache un WaitForChild, et en ligne droite dans un init il gele TOUT le boot
	-- le temps de son timeout.
	task.spawn(function()
		local remote = RemoteSetup.getRemote("PlayDropEffect", "Fx") :: RemoteEvent
		remote.OnClientEvent:Connect(function(position: Vector3)
			-- On verifie quand meme le type : un effet decoratif ne doit jamais faire tomber le client, meme sur
			-- un message malforme.
			if typeof(position) == "Vector3" then
				DropEffectUtils.spawnAt(position)
			end
		end)
	end)
end

return DropEffectController
