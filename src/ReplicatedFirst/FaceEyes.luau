--!strict
-- LES YEUX DU GRAND-PERE, en calques par-dessus une tete dessinee SANS eux.
--
-- POURQUOI UN MODULE. Deux ecrans montrent ce visage : le grand ecran de premier lancement
-- (`LoadingScreenClient`) et le rideau de changement de map (`CurtainVisual`). La meme logique recopiee aux deux
-- endroits finirait par diverger -- un regard regle ici, un clin d'oeil corrige la-bas -- et plus personne ne
-- saurait laquelle fait foi.
--
-- COMMENT CA MARCHE. Les images des yeux ont EXACTEMENT les memes dimensions que la tete : posees dessus en
-- taille (1, 1), elles tombent pile en place, sans un seul chiffre a caler. Faire regarder ailleurs revient donc
-- a DECALER leur cadre commun -- un seul objet a bouger, aucun risque qu un oeil parte sans l autre.
--
-- CE QUE LE MODULE NE FAIT PAS : il n ecrit jamais la rotation de la tete. Le clin d oeil la PENCHE, mais les
-- deux ecrans la font aussi tanguer : il rend donc son angle (`tilt()`) et l appelant ECRIT LA SOMME. Deux
-- ecrivains sur une meme propriete, et le dernier a parler efface l autre.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local FaceEyes = {}

-- LES IMAGES. Toutes au format de la tete.
FaceEyes.HEAD = "rbxassetid://107162385671697" -- la tete SANS les yeux
local EYE_LEFT = "rbxassetid://130322074892629"
local EYE_RIGHT = "rbxassetid://108086469738634"
local EYE_SHUT = "rbxassetid://80743235106162" -- les deux fermes
local EYE_WINK = "rbxassetid://133495431262696" -- l oeil droit ferme : le clin d oeil

local SOUND_PATH = { "Sounds", "UI", "EyeWinkSound" }
local SOUND_VOLUME = 0.6

-- ECARTEMENT, en fraction de la largeur de la tete : chaque oeil glisse vers son cote. Rectification faite ici
-- plutot que dans l image, tant qu elle reste petite. A NOTER : le calque des DEUX yeux fermes ne peut pas suivre
-- (ses deux yeux sont dans la meme image), donc un ecart trop grand se verrait au clignement.
local SPREAD = 0.008

-- Ecart entre deux clignements, plus du hasard : toutes les N secondes pile, ca se lit comme un metronome.
local BLINK_EVERY = 3.2
local BLINK_JITTER = 2.4
local BLINK_SHUT_TIME = 0.09
local WINK_TIME = 0.18 -- un clin d oeil se TIENT, il ne claque pas comme un clignement

-- LE REGARD.
local GAZE_X = 0.016 -- amplitude horizontale, en fraction de la tete
local GAZE_Y = 0.007
local GAZE_UP_CHANCE = 0.4 -- part des coups d oeil qui montent
local GAZE_UP_Y = 0.015 -- de combien il leve les yeux. Trop haut, les pupilles sortent des paupieres dessinees
local GAZE_EVERY = 1.3
local GAZE_JITTER = 1.9
local GAZE_TIME = 0.22

-- LE PENCHEMENT pendant le clin d oeil.
local TILT = 7 -- degres
local TILT_IN = 0.35
local TILT_HOLD = 0 -- temps ou la tete reste penchee APRES la reouverture de l oeil
local TILT_OUT = 0.5 -- plus lent que l aller : la tete "revient" au lieu de claquer

export type Handle = {
	wink: () -> (),
	tilt: () -> number,
	stop: () -> (),
}

export type Options = {
	zIndex: number?,
	tint: Color3?,
	transparency: number?,
	-- Rappel pose sur CHAQUE calque : c est par lui que l appelant y remet son degrade de fondu. Un enfant
	-- n herite pas du UIGradient de son parent (seul un CanvasGroup le propage), donc sans ca les yeux
	-- resteraient pleins la ou la tete s estompe.
	decorate: ((ImageLabel) -> ())?,
	-- Rend `false` quand il faut abandonner (ecran detruit), et ATTEND tant que le visage n est pas affiche :
	-- sans ca, le son du clin d oeil partirait dans le vide.
	waitVisible: (() -> boolean)?,
}

local function findSound(): Sound?
	local node: Instance = SoundService
	for _, name in SOUND_PATH do
		local child = node:FindFirstChild(name)
		if not child then
			return nil
		end
		node = child
	end
	return if node:IsA("Sound") then node else nil
end

-- On CLONE plutot que rejouer l original : rejouer la meme instance couperait le son en cours. Le nettoyage se
-- fait sur `Ended` (la vraie fin, quelle que soit la duree) ; le delai n est qu un filet, large.
local function playSound(template: Sound)
	local sound = template:Clone()
	sound.Volume = SOUND_VOLUME
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, math.max(sound.TimeLength + 5, 60))
end

--- Pose les yeux sur `head` (l ImageLabel de la tete sans yeux) et les fait vivre.
function FaceEyes.attach(head: ImageLabel, options: Options?): Handle
	local opts: Options = options or {}
	local zIndex = opts.zIndex or (head.ZIndex + 1)

	-- LE CADRE DES YEUX : c est LUI qu on deplace pour le regard, jamais les calques un par un.
	local eyes = Instance.new("Frame")
	eyes.Name = "Eyes"
	eyes.BackgroundTransparency = 1
	eyes.AnchorPoint = Vector2.new(0.5, 0.5)
	eyes.Position = UDim2.fromScale(0.5, 0.5)
	eyes.Size = UDim2.fromScale(1, 1)
	eyes.ZIndex = zIndex
	eyes.Parent = head

	local function layer(name: string, image: string, shown: boolean, dx: number): ImageLabel
		local l = Instance.new("ImageLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Image = image
		-- PAR DEFAUT, LA TEINTE DE LA TETE. Les yeux appartiennent au meme dessin : un noir en dur les laissait
		-- noirs sur le rideau, dont le visage est clair.
		l.ImageColor3 = opts.tint or head.ImageColor3
		l.ImageTransparency = opts.transparency or 0
		l.ScaleType = head.ScaleType -- meme mode que la tete, sinon les deux ne se superposent plus
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5 + dx, 0.5)
		l.Size = UDim2.fromScale(1, 1)
		l.ZIndex = zIndex
		l.Visible = shown
		if opts.decorate then
			opts.decorate(l)
		end
		l.Parent = eyes
		return l
	end

	-- Le calque du clin d oeil suit l oeil DROIT : c est le meme oeil.
	local left = layer("EyeLeft", EYE_LEFT, true, -SPREAD)
	local right = layer("EyeRight", EYE_RIGHT, true, SPREAD)
	local shut = layer("EyesShut", EYE_SHUT, false, 0)
	local wink = layer("EyeWink", EYE_WINK, false, SPREAD)

	-- LES DEUX CALQUES CACHES SE TELECHARGENT D AVANCE. Une image ne part se charger que lorsqu on l AFFICHE :
	-- ceux-la ne se montrent que deux dixiemes de seconde, donc ils n avaient jamais le temps d arriver et l oeil
	-- disparaissait au lieu de se fermer. (`IsLoaded` ne sert a rien pour le verifier : elle reste FAUSSE tant
	-- que l image n a jamais ete dessinee, meme quand l asset va tres bien.)
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ shut, wink })
		end)
	end)

	local tiltValue = Instance.new("NumberValue")
	local busy = false
	local alive = true

	local function ready(): boolean
		if not alive or not eyes.Parent then
			return false
		end
		if opts.waitVisible then
			return opts.waitVisible()
		end
		return true
	end

	local function doWink()
		if busy or not ready() then
			return
		end
		busy = true
		-- TOUT SUR LA MEME IMAGE : le son, l oeil qui se ferme, la tete qui penche.
		local cling = findSound()
		if cling then
			playSound(cling)
		end
		right.Visible = false
		wink.Visible = true
		TweenService:Create(
			tiltValue,
			TweenInfo.new(TILT_IN, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Value = TILT }
		):Play()
		task.wait(WINK_TIME)
		wink.Visible = false
		right.Visible = true
		busy = false
		task.delay(TILT_HOLD, function()
			if not alive then
				return
			end
			TweenService:Create(
				tiltValue,
				TweenInfo.new(TILT_OUT, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Value = 0 }
			):Play()
		end)
	end

	-- LES CLIGNEMENTS ORDINAIRES, qui ne font que vivre le visage.
	task.spawn(function()
		if not ready() then
			return
		end
		while alive and eyes.Parent do
			task.wait(BLINK_EVERY + math.random() * BLINK_JITTER)
			if not alive or not eyes.Parent then
				return
			end
			if not busy then
				busy = true
				left.Visible = false
				right.Visible = false
				shut.Visible = true
				task.wait(BLINK_SHUT_TIME)
				shut.Visible = false
				left.Visible = true
				right.Visible = true
				busy = false
			end
		end
	end)

	-- LE REGARD QUI SE BALADE.
	task.spawn(function()
		if not ready() then
			return
		end
		while alive and eyes.Parent do
			task.wait(GAZE_EVERY + math.random() * GAZE_JITTER)
			if not alive or not eyes.Parent then
				return
			end
			local dx, dy
			if math.random() < GAZE_UP_CHANCE then
				-- EN HAUT ET FRANCHEMENT D UN COTE : tire au hasard, le decalage lateral serait souvent quasi nul
				-- et le regard monterait tout droit, ce qui ne raconte rien.
				dx = if math.random() < 0.5 then -GAZE_X else GAZE_X
				dy = -GAZE_UP_Y -- en interface, le Y descend : vers le haut, c est donc negatif
			else
				dx = (math.random() * 2 - 1) * GAZE_X
				dy = (math.random() * 2 - 1) * GAZE_Y
			end
			TweenService:Create(eyes, TweenInfo.new(GAZE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromScale(0.5 + dx, 0.5 + dy),
			}):Play()
		end
	end)

	return {
		wink = function()
			task.spawn(doWink)
		end,
		tilt = function(): number
			return tiltValue.Value
		end,
		stop = function()
			alive = false
		end,
	}
end

return FaceEyes
