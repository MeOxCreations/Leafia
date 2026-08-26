--!strict
-- Gerbe d'etoiles filantes a l'ecran, tirees depuis un point du MONDE.
--
-- Primitif volontairement generique : on l'essaye d'abord sur les coups a la porte, mais il doit pouvoir servir
-- a la tondeuse ou a n'importe quel impact sans etre retouche. D'ou l'unique argument -- un point du monde --
-- plutot qu'un reglage par appelant.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local StarBurst = {}

-- LES NOMS PORTENT LA DIRECTION. Chaque image est DESSINEE pour sa branche : la faire partir ailleurs la
-- montrerait de travers. On ne tire donc pas au hasard, chaque etoile va dans son sens.
--
-- Y positif = VERS LE BAS : c'est le repere des interfaces Roblox, pas celui du monde.
local STARS: { { image: string, dir: Vector2 } } = {
	{ image = "rbxassetid://73722936185730", dir = Vector2.new(0, -1) }, -- MidUp
	{ image = "rbxassetid://79873435766212", dir = Vector2.new(0.707, -0.707) }, -- RightUp
	{ image = "rbxassetid://79916527494262", dir = Vector2.new(1, 0) }, -- RightMid
	{ image = "rbxassetid://100538612383728", dir = Vector2.new(0.707, 0.707) }, -- RightDown
	{ image = "rbxassetid://72937995219987", dir = Vector2.new(0, 1) }, -- MidDown
	{ image = "rbxassetid://121273746109732", dir = Vector2.new(-0.707, 0.707) }, -- LeftDown
	{ image = "rbxassetid://71340486659971", dir = Vector2.new(-1, 0) }, -- LeftMid
	{ image = "rbxassetid://89311879866535", dir = Vector2.new(-0.707, -0.707) }, -- LeftTop
}

-- Tout est en FRACTION DE LA HAUTEUR D'ECRAN, jamais en pixels : la gerbe garde la meme allure sur un telephone
-- et sur un grand ecran. La hauteur et pas la largeur, parce que c'est elle qui varie le moins d'un format a
-- l'autre -- en largeur, la meme valeur donnerait une gerbe ecrasee en 16:9 et enorme en 4:3.
local START_DIST = 0.03 -- elles ne partent pas du point exact : sinon elles se chevauchent toutes au depart
local TRAVEL = 0.5
local SIZE = 0.20

local TRAVEL_TIME = 0.4
local FADE_DELAY = 0.12
local FADE_TIME = 0.28
-- Transparence de depart. UNE GERBE DISCRETE : elle accompagne le coup, elle ne le remplace pas. Trop visible,
-- elle devient le sujet -- et ce qu'on doit regarder a cet instant, c'est la porte.
local START_TRANSPARENCY = 0.65

-- CALCULEE, pas ecrite a la main. Deux durees qu'on garde d'accord de tete finissent toujours par diverger : le
-- jour ou l'on allonge le fondu, la gerbe serait detruite avant de l'avoir fini.
local LIFETIME = math.max(TRAVEL_TIME, FADE_DELAY + FADE_TIME)

local player = Players.LocalPlayer
local gui: ScreenGui? = nil

local function getGui(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("ScreenGui")
	created.Name = "LeafiaStarBurst"
	-- `None` EST OBLIGATOIRE ICI. `WorldToViewportPoint` rend des coordonnees dont l'origine est le coin ABSOLU
	-- de l'ecran, la barre Roblox comprise dedans. Avec l'inset par defaut, l'origine du GUI est ~36 px plus bas
	-- et toute la gerbe suit 36 px trop bas.
	created.ScreenInsets = Enum.ScreenInsets.None
	created.IgnoreGuiInset = true
	created.ResetOnSpawn = false
	-- Sous les bandes noires du cinemascope (100) : la gerbe est DANS l'image, elle ne passe pas par-dessus le
	-- cadre.
	created.DisplayOrder = 90
	created.Parent = player:WaitForChild("PlayerGui")
	gui = created
	return created
end

-- Tire une gerbe depuis un point du monde. Sans effet si le point est derriere la camera : une etoile projetee
-- depuis l'arriere part dans le sens INVERSE, et la gerbe se replie sur elle-meme.
function StarBurst.at(worldPos: Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	if viewport.Y <= 0 then
		return -- trop tot au demarrage : la camera n'a pas encore de taille
	end

	local screenPos, onScreen = camera:WorldToViewportPoint(worldPos)
	if not onScreen then
		return
	end

	local holder = getGui()
	local origin = Vector2.new(screenPos.X, screenPos.Y)
	local height = viewport.Y
	local size = UDim2.fromOffset(height * SIZE, height * SIZE)

	-- On retient CE lot. Balayer les enfants du ScreenGui a la fin ramasserait aussi les etoiles d'une gerbe
	-- precedente encore en vol, et la detruirait avant son terme -- deux coups rapproches se couperaient l'un
	-- l'autre.
	local batch: { ImageLabel } = {}

	for _, star in ipairs(STARS) do
		local from = origin + star.dir * (height * START_DIST)
		local to = origin + star.dir * (height * TRAVEL)

		local label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromOffset(from.X, from.Y)
		-- Elle NAIT a zero et grandit en filant. Apparaitre a sa taille pleine puis se deplacer se lit comme un
		-- objet qui glisse ; grandir en partant se lit comme quelque chose qui JAILLIT.
		label.Size = UDim2.fromOffset(0, 0)
		label.Image = star.image
		label.ImageTransparency = START_TRANSPARENCY
		label.Parent = holder
		table.insert(batch, label)

		TweenService:Create(
			label,
			TweenInfo.new(TRAVEL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(to.X, to.Y), Size = size }
		):Play()

		-- LE FONDU PART EN RETARD, et il finit avant l'arrivee. Une etoile qui s'efface pile au bout de sa course
		-- a l'air de s'ARRETER ; une etoile deja effacee quand elle arrive a l'air de partir a l'infini.
		task.delay(FADE_DELAY, function()
			if label.Parent then
				TweenService:Create(
					label,
					TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ ImageTransparency = 1 }
				):Play()
			end
		end)
	end

	-- CHAQUE GERBE EMPORTE LES SIENNES. Rien n'est garde entre deux appels : pas d'etat, pas de fuite possible,
	-- et deux gerbes qui se recouvrent ne se genent pas.
	task.delay(LIFETIME, function()
		for _, label in ipairs(batch) do
			if label.Parent then
				label:Destroy()
			end
		end
	end)
end

return StarBurst
