--!strict
-- PAS DE SON DE PAS. Le joueur ne veut aucun son de marche. On coupe le son "Running" par defaut de Roblox
-- (volume 0) et on ne joue RIEN a la place : silence au sol. Le module reste le point unique ou remuter / rebrancher
-- un son de pas plus tard si besoin.

local Players = game:GetService("Players")

local FootstepController = {}

local player = Players.LocalPlayer

-- Coupe le son de marche par defaut (cree dans le HRP par le gestionnaire de sons de Roblox). Il ne remet jamais le
-- Volume, donc le passer a 0 le mute pour de bon. WaitForChild avec timeout : le son arrive quelques frames apres le
-- HRP, et on ne veut pas geler si un jour il n'existe pas.
local function muteDefaultRunning(char: Model)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	task.spawn(function()
		local running = hrp:WaitForChild("Running", 5)
		if running and running:IsA("Sound") then
			running.Volume = 0
		end
	end)
end

function FootstepController.init()
	if player.Character then
		muteDefaultRunning(player.Character)
	end
	player.CharacterAdded:Connect(muteDefaultRunning)
end

return FootstepController
