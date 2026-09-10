--!strict
-- JAUGE DE COMPETENCE, posee dans le monde a cote de quelqu'un. Elle monte pendant qu'il pratique.
--
-- PAS UN BillboardGui, pour les memes raisons que WorldMarker et AngerBurst : un Billboard subit l'eclairage,
-- passe derriere le decor, et sa taille depend de la distance. Ici c'est un ScreenGui projete (WorldAnchor) :
-- pixels constants, couleurs exactes, toujours au-dessus.
--
-- PRIMITIVE REUTILISABLE : elle ne connait ni la tonte, ni le joueur, ni aucun niveau. On lui donne une cible et
-- une fraction. Le jour ou la taille de haie a sa propre competence, ce sera la meme jauge.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local SkillConfigs = require(script.Parent.Parent.Parent.Configs.SkillConfigs)
local WorldAnchor = require(script.Parent.WorldAnchor)

local SkillBar = {}

local player = Players.LocalPlayer

-- Comme WorldMarker : bornee pour rester lisible de loin sans devenir enorme colle dessus.
local SCALE: WorldAnchor.Scale = { ref = 30, min = 0.6, max = 1.25 }
local MAX_DISTANCE = 90

local gui: ScreenGui? = nil
local frame: Frame? = nil
local fill: Frame? = nil
local shown = false
local fadeTween: Tween? = nil
local fillTween: Tween? = nil

local function getGui(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("ScreenGui")
	created.Name = "LeafiaSkillBar"
	-- `None` EST OBLIGATOIRE : WorldAnchor rend des coordonnees dont l'origine est le coin ABSOLU de l'ecran. Avec
	-- l'inset par defaut, la jauge suivrait 36 px trop bas. Piege deja paye dans ce projet.
	created.ScreenInsets = Enum.ScreenInsets.None
	created.IgnoreGuiInset = true
	created.ResetOnSpawn = false
	-- Sous les marqueurs : une jauge est un ETAT, un marqueur est un APPEL. L'appel passe devant.
	created.DisplayOrder = 45
	created.Parent = player:WaitForChild("PlayerGui")
	gui = created
	return created
end

-- Le cast est OBLIGATOIRE : luau-lsp ne resout pas `Instance.new("UICorner")` vers `UICorner`, et poser
-- `.CornerRadius` sur ce qu'il croit etre une `Instance` sort en erreur rouge.
local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner") :: UICorner
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function build(): Frame
	local existing = frame
	if existing and existing.Parent then
		return existing
	end
	local holder = getGui()

	local back = Instance.new("Frame")
	back.Name = "SkillBar"
	back.Size = UDim2.fromOffset(SkillConfigs.BAR_WIDTH, SkillConfigs.BAR_HEIGHT)
	back.BackgroundColor3 = SkillConfigs.BAR_BACK
	back.BackgroundTransparency = 1 -- elle nait invisible : le fondu la revele
	back.BorderSizePixel = 0
	back.Parent = holder
	corner(back, SkillConfigs.BAR_HEIGHT // 2)

	local stroke = Instance.new("UIStroke")
	stroke.Color = SkillConfigs.BAR_STROKE
	stroke.Thickness = SkillConfigs.BAR_STROKE_THICKNESS
	stroke.Transparency = 1
	stroke.Parent = back

	local bar = Instance.new("Frame")
	bar.Name = "Fill"
	-- ANCREE A GAUCHE : la jauge se remplit depuis la gauche, donc seule sa LARGEUR change. Centree, elle
	-- grandirait des deux cotes -- ce qui ne ressemble pas a un remplissage.
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.fromScale(0, 0.5)
	bar.Size = UDim2.fromScale(0, 1)
	bar.BackgroundColor3 = SkillConfigs.BAR_COLOR
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.Parent = back
	corner(bar, SkillConfigs.BAR_HEIGHT // 2)

	frame, fill = back, bar
	return back
end

local function fadeTo(value: number)
	local back, bar = frame, fill
	if not (back and bar) then
		return
	end
	if fadeTween then
		fadeTween:Cancel()
	end
	local info = TweenInfo.new(SkillConfigs.BAR_FADE_TIME)
	local backGoal = if value >= 1 then 1 else SkillConfigs.BAR_BACK_TRANSPARENCY
	local tween = TweenService:Create(back, info, { BackgroundTransparency = backGoal })
	fadeTween = tween
	tween:Play()
	TweenService:Create(bar, info, { BackgroundTransparency = value }):Play()
	local stroke = back:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, info, { Transparency = value }):Play()
	end
end

--- Montre la jauge a cote de `target` et la remplit a `amount` (0 a 1).
---
--- A appeler autant de fois qu'on veut : elle ne se recree pas, elle se remplit. Le remplissage est ANIME, donc
--- deux appels rapproches ne font pas sauter la barre -- elle glisse d'une valeur a l'autre.
function SkillBar.show(target: WorldAnchor.Target, amount: number)
	local back = build()
	local bar = fill
	if not bar then
		return
	end

	-- A COTE de la tete, et le decalage lateral suit la CAMERA : en repere monde, la jauge passerait derriere le
	-- personnage des qu'on tourne autour de lui. `cameraRelative` la garde toujours du meme cote a l'ecran.
	WorldAnchor.attach(
		back,
		target,
		Vector3.new(SkillConfigs.BAR_SIDE, SkillConfigs.BAR_UP, 0),
		MAX_DISTANCE,
		SCALE,
		true
	)

	if fillTween then
		fillTween:Cancel()
	end
	local goal = UDim2.fromScale(math.clamp(amount, 0, 1), 1)
	local tween = TweenService:Create(bar, TweenInfo.new(SkillConfigs.BAR_FILL_TIME), { Size = goal })
	fillTween = tween
	tween:Play()

	if not shown then
		shown = true
		fadeTo(0)
	end
end

--- Range la jauge. Idempotent : appelee alors qu'elle est deja partie, elle ne relance rien.
function SkillBar.hide()
	if not shown then
		return
	end
	shown = false
	fadeTo(1)
end

--- POSE LA VALEUR SANS ANIMER. Sert au premier affichage apres un chargement : glisser depuis zero raconterait
--- une progression qui vient d'avoir lieu, alors que le joueur l'a gagnee dans une session precedente.
function SkillBar.setInstant(amount: number)
	local bar = fill
	if not bar then
		return
	end
	if fillTween then
		fillTween:Cancel()
		fillTween = nil
	end
	bar.Size = UDim2.fromScale(math.clamp(amount, 0, 1), 1)
end

--- Detruit tout. Celui qui cree est celui qui nettoie, et il nettoie TOUT : l'entree de WorldAnchor survivrait au
--- Destroy et sa boucle continuerait de calculer une position pour un objet mort.
function SkillBar.destroy()
	if fadeTween then
		fadeTween:Cancel()
		fadeTween = nil
	end
	if fillTween then
		fillTween:Cancel()
		fillTween = nil
	end
	local back = frame
	if back then
		WorldAnchor.detach(back)
		back:Destroy()
	end
	frame, fill = nil, nil
	shown = false
end

return SkillBar
