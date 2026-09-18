--!strict
-- LA BARRE D'ATTENTE DU COUP DE CORDE, au-dessus de la tondeuse.
--
-- LE PROBLEME QU'ELLE REGLE : pendant le geste, un clic ne fait rien -- le serveur l'ignore, la corde est deja
-- tiree. Le joueur ne le sait pas : il clique, rien ne part, il reclique plus fort. Ca se lit comme une commande
-- qui repond mal, et ca stresse. La barre dit "ca travaille, attends ca", et quand elle disparait on peut retirer.
--
-- ELLE NE DECIDE RIEN. On lui donne une cible et l'heure SERVEUR a laquelle la corde redevient tirable (posee par
-- MowService) ; elle en tire son remplissage, image par image.
--
-- Un ScreenGui projete (WorldAnchor) et pas un BillboardGui, comme les autres jauges du jeu : pixels constants,
-- toujours au-dessus du decor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local WorldAnchor = require(ReplicatedStorage.Modules.UI.Core.WorldAnchor)

local PullTimerHandler = {}

local player = Players.LocalPlayer

-- En pixels pour un ecran de 1080 de haut ; `WorldAnchor.screenScale` la ramene a la taille d'un telephone.
local BAR_W = 84
local BAR_H = 12
local PAD = 3
local SCREEN_MIN = 0.6
-- Le blanc des cartes du jeu autour, le vert des taches dedans : c'est la meme idee -- quelque chose avance.
local CARD = Color3.fromRGB(255, 255, 255)
local TRACK = Color3.fromRGB(32, 38, 46)
local FILL = Color3.fromRGB(98, 206, 59)
local FADE_IN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local gui: ScreenGui? = nil
local group: CanvasGroup? = nil
local fill: Frame? = nil
local shown = false
-- L'ATTENTE EN COURS : quand elle a commence et quand elle finit, en temps serveur. Une nouvelle heure de fin =
-- une nouvelle attente, donc la barre repart de zero.
local startAt = 0
local endAt = 0

local function corner(parent: Instance)
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = parent
end

local function build(): CanvasGroup
	local existing = group
	if existing and existing.Parent then
		return existing
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "LeafiaPullTimer"
	sg.ResetOnSpawn = false
	sg.ScreenInsets = Enum.ScreenInsets.None
	sg.DisplayOrder = 50
	sg.Parent = player:WaitForChild("PlayerGui")

	-- UN `CanvasGroup` pour faire fondre la carte et sa jauge d'un seul reglage.
	local box = Instance.new("CanvasGroup")
	box.Name = "PullTimer"
	box.BackgroundColor3 = CARD
	box.BorderSizePixel = 0
	box.GroupTransparency = 1
	box.Visible = false
	box.Parent = sg
	corner(box)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = TRACK
	track.BorderSizePixel = 0
	track.Parent = box
	corner(track)

	local bar = Instance.new("Frame")
	bar.Name = "Fill"
	bar.BackgroundColor3 = FILL
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(0, 1)
	bar.Parent = track
	corner(bar)

	gui, group, fill = sg, box, bar
	return box
end

-- A LA TAILLE DE L'ECRAN, reposee a chaque apparition : l'ecran peut tourner entre deux coups de corde.
local function resize(box: CanvasGroup)
	local s = WorldAnchor.screenScale(SCREEN_MIN)
	local pad = math.max(math.floor(PAD * s + 0.5), 2)
	box.Size = UDim2.fromOffset(BAR_W * s, BAR_H * s)
	local track = box:FindFirstChild("Track")
	if track and track:IsA("Frame") then
		track.Position = UDim2.fromOffset(pad, pad)
		track.Size = UDim2.new(1, -pad * 2, 1, -pad * 2)
	end
end

local function hide()
	if not shown then
		return
	end
	shown = false
	local box = group
	if not box then
		return
	end
	local tween = TweenService:Create(box, FADE_OUT, { GroupTransparency = 1 })
	tween.Completed:Connect(function()
		if not shown then
			box.Visible = false
			WorldAnchor.detach(box)
		end
	end)
	tween:Play()
end

--- A appeler A CHAQUE IMAGE tant qu'une corde est en main. `readyAt` = l'heure serveur ou l'on pourra retirer
--- (nil ou deja passee : on peut tirer, la barre s'en va).
function PullTimerHandler.update(target: BasePart, readyAt: number?, up: number)
	local now = Workspace:GetServerTimeNow()
	if readyAt == nil or readyAt <= now then
		hide()
		return
	end
	local box = build()
	if readyAt ~= endAt or not shown then
		-- UNE NOUVELLE ATTENTE : la barre repart de zero, a partir de maintenant.
		startAt, endAt = now, readyAt
		if not shown then
			shown = true
			resize(box)
			WorldAnchor.attach(box, target, Vector3.new(0, up, 0))
			TweenService:Create(box, FADE_IN, { GroupTransparency = 0 }):Play()
		end
	end
	local bar = fill
	if bar then
		local span = math.max(endAt - startAt, 1e-3)
		bar.Size = UDim2.fromScale(math.clamp((now - startAt) / span, 0, 1), 1)
	end
end

--- Plus de corde a tirer (moteur lance, machine reposee) : la barre s'en va.
function PullTimerHandler.hide()
	hide()
end

--- Detruit tout. Celui qui cree est celui qui nettoie, et il nettoie TOUT.
function PullTimerHandler.destroy()
	local box = group
	if box then
		WorldAnchor.detach(box)
	end
	local holder = gui
	if holder then
		holder:Destroy()
	end
	gui, group, fill, shown = nil, nil, nil, false
end

return PullTimerHandler
