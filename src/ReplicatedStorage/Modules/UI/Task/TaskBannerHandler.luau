--!strict
-- BANDEAU D'OBJECTIFS, en haut a gauche. Il dit CE QU'ON DOIT FAIRE, ou l'on en est, et ce que ca rapporte.
--
-- IL NE CONSTRUIT PLUS RIEN. La version precedente dessinait toute l'interface en code, le temps que la maquette
-- bouge -- chaque essai partait sur GitHub et se relisait dans le diff. La forme est maintenant figee dans
-- Studio (`StarterGui.LeafiaTaskBanner`), donc ce module la PILOTE, comme tous les autres handlers du projet.
--
-- Ce qu'il attend dans Studio, et rien d'autre :
--
--   LeafiaTaskBanner (ScreenGui)
--     Title, ThicknessTop, Background   -- le decor, on n'y touche pas
--     TemplateTask (Frame)              -- LE MODELE. Clone une fois par tache, jamais affiche tel quel.
--       Bar > Fill                      -- la jauge : c'est le Size.X de Fill qui avance
--       IconColor                       -- la pastille teintee (son UIGradient porte la couleur de la tache)
--       IconTaskDraw                    -- le dessin de la tache
--       DescriptionTask, RewardText     -- les textes
--
-- Un nom qui change dans Studio casse le pilotage : le module le DIT alors, plutot que d'echouer en silence.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TaskConfigs = require(ReplicatedStorage.Modules.Configs.TaskConfigs)

local TaskBannerHandler = {}

local GUI_NAME = "LeafiaTaskBanner"
local TEMPLATE_NAME = "TemplateTask"

-- Le Y de la premiere ligne et l'ecart entre deux, en part d'ecran. Repris du template pose dans Studio : la
-- premiere garde sa place, les suivantes se rangent dessous.
local FIRST_Y = 0.219
local ROW_GAP = 0.078

-- D'OU ELLES ARRIVENT. Hors champ a gauche, en X : elles entrent par le bord, comme les notifications. Assez
-- loin pour qu'aucun bout ne depasse avant le depart, quelle que soit la largeur de l'ecran.
local HIDDEN_X = -0.6
local SHOWN_X = 0

-- `Back Out` depasse legerement la cible avant de se poser : c'est ce qui donne le petit rebond. Repris tel quel
-- de la version precedente, le toucher etait bon.
local SLIDE_IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- Retard entre deux lignes : elles arrivent en cascade, pas en bloc. Un bloc se lit comme un panneau qui
-- apparait ; une cascade se lit comme une liste qui se REMPLIT.
local ROW_STAGGER = 0.09

-- Vitesse de remplissage de la jauge. Elle GLISSE vers sa valeur : c'est le mouvement qui se remarque, pas le
-- chiffre -- une barre qui saute a sa place ne se voit pas.
local FILL_SPEED = 6
-- Largeur de la jauge pleine, en part de `Bar`. Un poil sous 1 : a 1 pile, les coins arrondis du remplissage
-- debordent de ceux de la barre.
local FILL_MAX = 0.98
-- En dessous de cet ecart, on CLE a la cible. Un lerp exponentiel n'atteint jamais sa valeur : sans ce clou, une
-- jauge "pleine" resterait a 99,7 % pour toujours.
local FILL_SNAP = 0.004

type Row = {
	frame: Frame,
	fill: Frame?,
	target: number,
	current: number,
}

local template: Frame? = nil
local rows: { Row } = {}
local fillConn: RBXScriptConnection? = nil

--- Retrouve l'interface posee dans Studio. Rend `nil` tant qu'elle n'est pas la.
local function resolve(): boolean
	if template and template.Parent then
		return true
	end
	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChildOfClass("PlayerGui")
	local sg = gui and gui:FindFirstChild(GUI_NAME)
	if not (sg and sg:IsA("ScreenGui")) then
		return false
	end
	local model = sg:FindFirstChild(TEMPLATE_NAME)
	if not (model and model:IsA("Frame")) then
		warn(`[TaskBanner] "{GUI_NAME}" trouve mais pas de "{TEMPLATE_NAME}" dedans : rien ne s'affichera.`)
		return false
	end
	-- LE MODELE NE S'AFFICHE JAMAIS. Il reste visible dans Studio pour se regler a l'oeil ; en jeu, il ne doit
	-- servir qu'a etre clone.
	model.Visible = false
	template = model
	return true
end

local function stopFill()
	if fillConn then
		fillConn:Disconnect()
		fillConn = nil
	end
end

--- La boucle qui fait glisser les jauges. Une seule pour toutes les lignes : une par ligne ferait tourner trois
--- connexions pour trois barres qui bougent aux memes instants.
local function startFill()
	if fillConn then
		return
	end
	fillConn = RunService.RenderStepped:Connect(function(dt)
		local moving = false
		for _, row in ipairs(rows) do
			local fill = row.fill
			if not fill or not fill.Parent then
				continue
			end
			local gap = row.target - row.current
			if math.abs(gap) <= FILL_SNAP then
				row.current = row.target
			else
				row.current += gap * math.min(dt * FILL_SPEED, 1)
				moving = true
			end
			fill.Size = UDim2.new(row.current * FILL_MAX, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
		end
		if not moving then
			stopFill() -- plus rien ne bouge : la boucle n'a plus de raison de tourner
		end
	end)
end

local function clearRows()
	for _, row in ipairs(rows) do
		row.frame:Destroy()
	end
	table.clear(rows)
	stopFill()
end

--- Remplit une ligne clonee avec une tache.
---
--- Le parametre ne s'appelle PAS `task` : ce nom masquerait le service `task` de Roblox, et un `task.delay`
--- ajoute ici un jour appellerait `.delay` sur la config au lieu du planificateur -- en silence.
local function dress(frame: Frame, entry: TaskConfigs.Task)
	local desc = frame:FindFirstChild("DescriptionTask")
	if desc and desc:IsA("TextLabel") then
		desc.Text = entry.text
	end

	local reward = frame:FindFirstChild("RewardText")
	if reward and reward:IsA("TextLabel") then
		reward.Text = entry.reward
	end

	local draw = frame:FindFirstChild("IconTaskDraw")
	if draw and draw:IsA("ImageLabel") then
		local id = TaskConfigs.ICONS[entry.icon]
		if not id then
			-- ON NOMME LA CLE MANQUANTE. "L'icone ne s'affiche pas" enverrait chercher du cote de l'image ;
			-- c'est la CLE qui est fausse, et elle se corrige a l'appel.
			warn(`[TaskBanner] Icone inconnue "{entry.icon}" : voir TaskConfigs.ICONS.`)
		end
		draw.Image = id or ""
	end

	-- LA TEINTE VA SUR LE GRADIENT DE LA PASTILLE, pas sur sa couleur : le degrade est ce qui lui donne son
	-- relief, et ecrire ImageColor3 par-dessus l'aplatirait.
	local tint = entry.tint
	if tint then
		local pastille = frame:FindFirstChild("IconColor")
		local grad = pastille and pastille:FindFirstChildOfClass("UIGradient")
		if grad then
			grad.Color = tint
		end
	end
end

--- Affiche la liste des taches. Remplace ce qui etait a l'ecran.
function TaskBannerHandler.show(tasks: { TaskConfigs.Task })
	if not resolve() then
		return
	end
	local model = template :: Frame
	clearRows()

	for i, entry in ipairs(tasks) do
		local frame = model:Clone()
		frame.Name = `Task{i}`
		frame.Visible = true
		frame.Position = UDim2.fromScale(HIDDEN_X, FIRST_Y + (i - 1) * ROW_GAP)
		frame.Parent = model.Parent
		dress(frame, entry)

		local bar = frame:FindFirstChild("Bar")
		local fillFrame = bar and bar:FindFirstChild("Fill")
		local fill = if fillFrame and fillFrame:IsA("Frame") then fillFrame else nil
		if fill then
			-- La jauge part de zero et se remplit ensuite. Posee directement a sa valeur, on ne verrait pas
			-- qu'elle avance.
			fill.Size = UDim2.new(0, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
		end

		table.insert(rows, { frame = frame, fill = fill, target = entry.progress or 0, current = 0 })

		-- EN CASCADE. Chaque ligne part apres la precedente : une liste qui se remplit, pas un panneau qui
		-- apparait d'un coup.
		local slideTo = UDim2.fromScale(SHOWN_X, frame.Position.Y.Scale)
		task.delay((i - 1) * ROW_STAGGER, function()
			if frame.Parent then
				TweenService:Create(frame, SLIDE_IN, { Position = slideTo }):Play()
			end
		end)
	end

	startFill()
end

--- Fixe l'avancement d'une ligne, de 0 a 1. `index` est sa place dans la liste passee a `show`.
function TaskBannerHandler.setProgress(index: number, value: number)
	local row = rows[index]
	if not row then
		return
	end
	row.target = math.clamp(value, 0, 1)
	startFill()
end

--- Range tout, en cascade elle aussi.
function TaskBannerHandler.hide()
	for i, row in ipairs(rows) do
		local frame = row.frame
		local out = UDim2.fromScale(HIDDEN_X, frame.Position.Y.Scale)
		task.delay((i - 1) * ROW_STAGGER, function()
			if frame.Parent then
				TweenService:Create(frame, SLIDE_OUT, { Position = out }):Play()
			end
		end)
	end
	-- On attend que la derniere soit sortie avant de detruire : detruire pendant le tween ferait disparaitre les
	-- lignes d'un coup au lieu de les faire glisser.
	local wait = (#rows - 1) * ROW_STAGGER + SLIDE_OUT.Time
	task.delay(wait, clearRows)
end

--- Tout ranger sans animation. La boucle de remplissage tourne sur RenderStepped : la laisser vivre apres la
--- fermeture ferait tourner un calcul pour des barres que personne ne regarde.
function TaskBannerHandler.destroy()
	clearRows()
end

return TaskBannerHandler
