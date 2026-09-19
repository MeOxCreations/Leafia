--!strict
-- COMPTEUR DE PERFORMANCE, en haut de l'ecran : images par seconde, pire image recente, ping.
--
-- POUR LE DEVELOPPEUR SEULEMENT (voir `AdminCommandConfigs.isAdmin` : Studio, ou le proprietaire du jeu en ligne).
-- Il sert a trouver OU le jeu ralentit, sur telephone surtout, ou la console ne s'ouvre pas.
--
-- LA PIRE IMAGE compte autant que la moyenne : un jeu a 58 images par seconde qui fige 150 ms toutes les deux
-- secondes se ressent comme "ca rame", et la moyenne ne le montre pas. On la garde affichee quelques secondes,
-- sinon un a-coup ne resterait a l'ecran qu'une demi-seconde et on le raterait.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AdminCommandConfigs = require(ReplicatedStorage.Modules.Configs.AdminCommandConfigs)

local PerfStatsController = {}

-- Interrupteur general. A false, plus rien ne s'affiche, meme pour le developpeur.
local ENABLED = true
-- Duree d'une mesure, en secondes : le texte se met a jour a ce rythme.
local WINDOW = 0.5
-- Nombre de mesures couvertes par la "pire image" (6 x 0.5 s = les 3 dernieres secondes).
local WORST_WINDOWS = 6
-- Seuils de couleur, en images par seconde. Sous 45, le joueur sent que "ca repond mal" sans savoir le nommer.
local FPS_GOOD = 55
local FPS_BAD = 45

local localPlayer = Players.LocalPlayer

local function colorFor(fps: number): string
	if fps >= FPS_GOOD then
		return "#6BE36B"
	elseif fps >= FPS_BAD then
		return "#F2B33D"
	end
	return "#FF5A5A"
end

local function build(playerGui: PlayerGui): TextLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "LeafiaPerfStats"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 1000
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 4)
	label.Size = UDim2.fromOffset(300, 20)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.RichText = true
	label.Font = Enum.Font.Code
	label.Text = ""
	label.Parent = gui
	gui.Parent = playerGui
	return label
end

function PerfStatsController.init()
	if not ENABLED or not AdminCommandConfigs.isAdmin(localPlayer) then
		return
	end
	task.spawn(function()
		local playerGui = localPlayer:WaitForChild("PlayerGui", 30)
		if not (playerGui and playerGui:IsA("PlayerGui")) then
			return
		end
		local label = build(playerGui)

		local frames = 0
		local windowStart = os.clock()
		local windowWorst = 0
		local worsts: { number } = {}

		RunService.Heartbeat:Connect(function(dt: number)
			frames += 1
			if dt > windowWorst then
				windowWorst = dt
			end
			local now = os.clock()
			local elapsed = now - windowStart
			if elapsed < WINDOW then
				return
			end

			local fps = frames / elapsed
			table.insert(worsts, windowWorst)
			if #worsts > WORST_WINDOWS then
				table.remove(worsts, 1)
			end
			local worst = 0
			for _, w in worsts do
				if w > worst then
					worst = w
				end
			end
			-- La pire image se colore comme un FPS instantane : 1 / sa duree.
			local worstColor = colorFor(if worst > 0 then 1 / worst else math.huge)
			local ping = localPlayer:GetNetworkPing() * 1000

			label.Text = string.format(
				'<font color="%s">%d FPS</font>  |  worst <font color="%s">%d ms</font>  |  ping %d ms',
				colorFor(fps),
				math.floor(fps + 0.5),
				worstColor,
				math.floor(worst * 1000 + 0.5),
				math.floor(ping + 0.5)
			)

			frames = 0
			windowStart = now
			windowWorst = 0
		end)
	end)
end

return PerfStatsController
