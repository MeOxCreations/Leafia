--!strict
-- BOITE DE DIALOGUE : un bandeau en bas de l'ecran, avec le PORTRAIT du personnage a gauche et sa replique ecrite
-- lettre par lettre a droite. Chaque replique choisit une EMOTION (nom lisible) et le dessin swappe avec un petit pop.
--
-- Primitive REUTILISABLE (narration du tuto, PNJ plus tard) : on lui passe une SEQUENCE de repliques et un callback
-- de fin. Un seul dialogue a la fois (singleton) : rejouer remplace le precedent.
--
-- Avancer : TAPER le bandeau (marche a la souris ET au tactile, donc mobile compris). Si le texte est encore en
-- train de s'ecrire, le 1er tap l'affiche EN ENTIER d'un coup ; le tap suivant passe a la replique d'apres. Sur la
-- derniere, il ferme le bandeau et appelle onDone.
--
-- Construit EN CODE (pas de template Studio), comme InteractionPrompt / Toast : drop-in, rien a preparer dans l'editeur.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)

local Dialogue = {}

local player = Players.LocalPlayer

export type Line = { speaker: string?, text: string, emotion: string? }

-- Emotions de PAPI (le meme dessin, plusieurs expressions). Une replique choisit son emotion par NOM (lisible),
-- pas par asset id brut. Emotion absente sur une ligne = on garde le dessin precedent.
-- Un seul personnage pour l'instant : le tuto ne fait parler que Papi. Quand les PNJ clients arriveront, cette table
-- devra passer en table PAR SPEAKER (EMOTIONS[speaker][emotion]) -- pas avant, ca n'aurait qu'une seule entree.
local EMOTIONS: { [string]: string } = {
	normal = "rbxassetid://128272912708514", -- neutre, au repos
	happy = "rbxassetid://74164548907866", -- content
	sad = "rbxassetid://132527109682757", -- triste
	angry = "rbxassetid://88353059391033", -- pas content
	shocked = "rbxassetid://89073402854323", -- choque
	wink = "rbxassetid://112230427558414", -- clin d'oeil, complice
}

-- ===== Style =====
-- Tailles de REFERENCE, pensees pour un ecran 1080p de haut. Un UIScale (voir refreshScale) agrandit / retrecit TOUT le
-- bandeau (dessin + texte compris) selon la hauteur reelle de l'ecran -> lisible du petit mobile a l'ultrawide, fini le
-- bandeau minuscule bloque a une largeur en pixels.
local REF_WIDTH = 800 -- largeur du bandeau a l'echelle 1
local HEIGHT = 120 -- hauteur du bandeau a l'echelle 1
local REF_HEIGHT = 1080 -- hauteur d'ecran de reference (echelle = hauteur reelle / REF_HEIGHT)
local MIN_SCALE, MAX_SCALE = 0.85, 2.4 -- bornes de l'echelle
local WIDTH_MAX_FRAC = 0.92 -- le bandeau ne depasse jamais cette fraction de la largeur ecran (ecrans etroits)
local BOTTOM_MARGIN = 28 -- marge au-dessus du bord bas de l'ecran
-- Portrait du personnage, a gauche du texte. Plus HAUT que le bandeau : le perso "sort" de la boite (sa tete depasse).
-- Regle ces valeurs quand tu vois tes dessins (leurs proportions reelles) : l'image est affichee en Fit, jamais deformee.
local PORTRAIT_X = 8 -- marge a gauche du dessin
local PORTRAIT_W = 165 -- largeur reservee au dessin
local PORTRAIT_H = 210 -- hauteur du dessin (depasse le haut du bandeau de PORTRAIT_H - HEIGHT)
-- Style BLANC (facon Sims / panneaux du menu) : fond clair, texte fonce. Le chip du nom reste jaune (accent).
local BG_COLOR = Color3.fromRGB(248, 250, 248)
local BG_TRANSPARENCY = 0.02
local TEXT_COLOR = Color3.fromRGB(44, 48, 56)
local SPEAKER_TEXT = Color3.fromRGB(24, 27, 32)
local SPEAKER_BG = Color3.fromRGB(255, 216, 92) -- chip du nom : jaune, l'accent du jeu
local BODY_FONT = Enum.Font.GothamBold -- texte de la replique en gras (Weight Bold)
local SPEAKER_FONT = Enum.Font.LuckiestGuy -- meme police display que les titres de prompt
local BODY_SIZE = 22
local CHARS_PER_SEC = 45 -- vitesse d'ecriture (graphemes par seconde)
-- SON DE FRAPPE ("tap tap tap") : une petite frappe toutes les TYPE_SOUND_EVERY lettres revelees, pitch legerement varie
-- pour ne pas sonner robotique. Le son est un Sound pose dans SoundService (comme les autres) ; ABSENT -> on ne joue rien
-- (pas de spam de warn). Depose ton tap ici en Studio : SoundService.Sounds.UI.DialogueType.
local TYPE_SOUND = { "Sounds", "UI", "DialogueType" }
local TYPE_SOUND_EVERY = 2 -- une frappe toutes les N lettres (monter = moins de taps ; 1 = a chaque lettre)
local typeSoundOk = false -- le son existe-t-il ? verifie UNE fois (voir build)
local typeAccum = 0 -- lettres accumulees depuis le dernier tap

local POP_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HINT_PULSE = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

-- ===== Etat =====
local gui: ScreenGui? = nil
local banner: TextButton? = nil
local speakerChip: Frame? = nil
local speakerLabel: TextLabel? = nil
local bodyLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local bannerScale: UIScale? = nil -- agrandit tout le bandeau selon la taille de l'ecran (voir refreshScale)

local sequence: { Line } = {}
local currentIndex = 0
local total = 0 -- graphemes de la replique courante
local revealed = 0 -- combien on en a ecrit (fractionnaire, arrondi a l'affichage)
local typing = false -- vrai tant que la ligne s'ecrit
local shownOnScreen = false
local onDoneFn: (() -> ())? = nil
local slideTween: Tween? = nil
local portrait: ImageLabel? = nil
local portraitScale: UIScale? = nil
local lastEmotion: string? = nil -- derniere expression affichee (pour ne popper qu'au CHANGEMENT)

-- Nombre de graphemes (accents compris) : c'est l'unite de MaxVisibleGraphemes. utf8.len peut renvoyer nil sur une
-- chaine mal formee -> on retombe sur le nombre d'octets, jamais zero.
local function graphemeCount(s: string): number
	local n = utf8.len(s)
	if n then
		return n
	end
	return #s
end

-- Le son de frappe est-il pose dans SoundService ? Verifie UNE fois pour ne pas spammer de warn s'il n'existe pas encore.
local function soundExists(path: { string }): boolean
	local node: Instance? = SoundService
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return node ~= nil and node:IsA("Sound")
end

local function shownPosition(): UDim2
	return UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN)
end
local function hiddenPosition(): UDim2
	return UDim2.fromScale(0.5, 1.6) -- entierement sous le bord bas, quelle que soit l'echelle
end

-- Echelle du bandeau selon l'ecran : basee sur la HAUTEUR (dimension stable), rabotee si l'ecran est trop ETROIT pour la
-- largeur de reference (petits mobiles). Un seul facteur pilote tout (taille, dessin, texte) -> aucune deformation. Sur
-- grand ecran (ex 3440x1440) l'echelle monte, donc le bandeau GRANDIT au lieu de rester minuscule.
local function refreshScale()
	local s = bannerScale
	if not s then
		return
	end
	local camera = workspace.CurrentCamera
	local vx = if camera then camera.ViewportSize.X else 1280
	local vy = if camera then camera.ViewportSize.Y else 720
	local scale = math.clamp(vy / REF_HEIGHT, MIN_SCALE, MAX_SCALE)
	s.Scale = math.min(scale, (WIDTH_MAX_FRAC * vx) / REF_WIDTH)
end

local function setSpeaker(name: string?)
	local chip, lbl = speakerChip, speakerLabel
	if not (chip and lbl) then
		return
	end
	if name and name ~= "" then
		lbl.Text = name
		chip.Visible = true
	else
		chip.Visible = false
	end
end

local function setHintVisible(v: boolean)
	local h = hintLabel
	if h then
		h.Visible = v
	end
end

-- Change le dessin affiche. Nom inconnu ou nil = on ne touche a rien (on garde l'expression precedente). Un petit pop
-- (UIScale) marque chaque CHANGEMENT d'expression pour que le perso ait l'air de "reagir".
local function setEmotion(name: string?)
	if not name then
		return
	end
	local id = EMOTIONS[name]
	local img = portrait
	if not (id and img) then
		return
	end
	img.Image = id
	img.Visible = true
	if name ~= lastEmotion then
		lastEmotion = name
		local sc = portraitScale
		if sc then
			sc.Scale = 0.82
			TweenService:Create(sc, POP_IN, { Scale = 1 }):Play()
		end
	end
end

local function startLine(i: number)
	local line = sequence[i]
	local body = bodyLabel
	if not (line and body) then
		return
	end
	setSpeaker(line.speaker)
	setEmotion(line.emotion)
	body.Text = line.text
	body.MaxVisibleGraphemes = 0
	total = graphemeCount(line.text)
	revealed = 0
	typing = true
	typeAccum = 0
	setHintVisible(false)
end

local function hideBanner()
	if not shownOnScreen then
		return
	end
	shownOnScreen = false
	typing = false
	setHintVisible(false)
	local b = banner
	if not b then
		return
	end
	if slideTween then
		slideTween:Cancel()
	end
	local t = TweenService:Create(b, POP_OUT, { Position = hiddenPosition() })
	slideTween = t
	t.Completed:Connect(function()
		-- Si un nouveau dialogue s'est ouvert entre-temps, on ne cache pas.
		if not shownOnScreen and slideTween == t then
			b.Visible = false
		end
	end)
	t:Play()
end

local function finish()
	local cb = onDoneFn
	onDoneFn = nil
	hideBanner()
	if cb then
		cb()
	end
end

-- Un tap sur le bandeau : finit la ligne d'un coup si elle s'ecrit encore, sinon passe a la suivante (ferme a la fin).
local function advance()
	if not shownOnScreen then
		return
	end
	if typing then
		typing = false
		local body = bodyLabel
		if body then
			body.MaxVisibleGraphemes = -1 -- tout afficher
		end
		setHintVisible(true)
		return
	end
	currentIndex += 1
	if currentIndex > #sequence then
		finish()
	else
		startLine(currentIndex)
	end
end

local function build()
	if gui and gui.Parent then
		return
	end
	typeSoundOk = soundExists(TYPE_SOUND) -- une fois : le son de frappe est-il pose ?
	local playerGui = player:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "DialogueUI"
	screen.ResetOnSpawn = false -- survit au respawn : la narration ne depend pas du personnage
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 60
	screen.Parent = playerGui

	-- Le bandeau ENTIER est un bouton : taper n'importe ou dessus avance le dialogue (souris + tactile).
	local b = Instance.new("TextButton")
	b.Name = "Banner"
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = hiddenPosition()
	b.Size = UDim2.fromOffset(REF_WIDTH, HEIGHT)
	b.BackgroundColor3 = BG_COLOR
	b.BackgroundTransparency = BG_TRANSPARENCY
	b.AutoButtonColor = false
	b.Text = ""
	b.Visible = false
	b.Parent = screen

	local corner = Instance.new("UICorner") :: UICorner
	corner.Parent = b
	-- Rayons PAR COIN (proprietes recentes de UICorner, absentes du dump d'API luau -> cast any, comme ailleurs dans le
	-- projet). Trois coins ronds a fond, bas-droit presque carre : une bulle asymetrique.
	local anyCorner = corner :: any
	anyCorner.BottomLeftRadius = UDim.new(1, 0)
	anyCorner.BottomRightRadius = UDim.new(0.05, 0)
	anyCorner.TopLeftRadius = UDim.new(1, 0)
	anyCorner.TopRightRadius = UDim.new(1, 0)

	local stroke = Instance.new("UIStroke") :: UIStroke
	stroke.Color = Color3.fromRGB(214, 218, 224) -- bord gris CLAIR et discret (le noir marquait trop sur le fond blanc)
	stroke.Transparency = 0.15
	stroke.Thickness = 1.5
	stroke.Parent = b

	-- Texte de la replique, a droite du dessin, ecrit via MaxVisibleGraphemes (voir le moteur plus bas). Position et
	-- taille en SCALE : ca suit le bandeau quelle que soit sa taille. X a 0.22 pour demarrer apres le portrait.
	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0, 0)
	body.Position = UDim2.fromScale(0.22, 0.1)
	body.Size = UDim2.fromScale(0.75, 0.82)
	body.BackgroundTransparency = 1
	body.Font = BODY_FONT
	body.TextColor3 = TEXT_COLOR
	body.TextSize = BODY_SIZE
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.RichText = false
	body.Text = ""
	body.Parent = b

	-- Chip du nom du locuteur, pose a cheval sur le bord haut a gauche. Cache si la replique n'a pas de speaker.
	local chip = Instance.new("Frame")
	chip.Name = "SpeakerChip"
	chip.AnchorPoint = Vector2.new(0, 1)
	chip.Position = UDim2.new(0.22, 0, 0, -6) -- alignee sur le debut du texte
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromOffset(0, 30)
	chip.BackgroundColor3 = SPEAKER_BG
	chip.Visible = false
	chip.Parent = b

	local chipCorner = Instance.new("UICorner") :: UICorner
	chipCorner.CornerRadius = UDim.new(0, 8)
	chipCorner.Parent = chip

	local chipPad = Instance.new("UIPadding")
	chipPad.PaddingLeft = UDim.new(0, 10)
	chipPad.PaddingRight = UDim.new(0, 10)
	chipPad.Parent = chip

	local sp = Instance.new("TextLabel")
	sp.Name = "SpeakerName"
	sp.AutomaticSize = Enum.AutomaticSize.X
	sp.Size = UDim2.fromScale(0, 1)
	sp.BackgroundTransparency = 1
	sp.Font = SPEAKER_FONT
	sp.TextColor3 = SPEAKER_TEXT
	sp.TextSize = 18
	sp.Text = ""
	sp.Parent = chip

	-- Indice "continuer" : une fleche vers le bas qui pulse, en bas a droite. Visible uniquement quand la ligne est ecrite.
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(1, 1)
	hint.Position = UDim2.new(1, -10, 1, -8)
	hint.Size = UDim2.fromOffset(24, 24)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.TextColor3 = TEXT_COLOR
	hint.TextSize = 20
	hint.Text = "\u{25BC}"
	hint.Visible = false
	hint.Parent = b

	TweenService:Create(hint, HINT_PULSE, { TextTransparency = 0.6 }):Play()

	-- Portrait du personnage, a gauche. Fit = le dessin s'affiche EN ENTIER sans deformation, quel que soit son ratio.
	-- Pose sur le bas du bandeau et plus haut que lui : la tete depasse au-dessus de la boite.
	local portraitImg = Instance.new("ImageLabel")
	portraitImg.Name = "Portrait"
	portraitImg.AnchorPoint = Vector2.new(0, 1)
	portraitImg.Position = UDim2.new(0, PORTRAIT_X, 1, 0)
	portraitImg.Size = UDim2.fromOffset(PORTRAIT_W, PORTRAIT_H)
	portraitImg.BackgroundTransparency = 1
	portraitImg.ScaleType = Enum.ScaleType.Fit
	portraitImg.Image = ""
	portraitImg.Visible = false
	portraitImg.Parent = b

	local imgScale = Instance.new("UIScale")
	imgScale.Parent = portraitImg

	-- UIScale sur le bandeau ENTIER : agrandit tout (bandeau + dessin + texte) selon l'ecran (voir refreshScale).
	local bScale = Instance.new("UIScale")
	bScale.Parent = b

	gui, banner, speakerChip, speakerLabel, bodyLabel, hintLabel = screen, b, chip, sp, body, hint
	portrait, portraitScale = portraitImg, imgScale
	bannerScale = bScale

	b.Activated:Connect(advance)

	refreshScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
	end

	-- MOTEUR D'ECRITURE : connecte une seule fois, actif seulement pendant "typing". On avance la revelation au rythme
	-- CHARS_PER_SEC ; arrive au bout, on fige la ligne et on montre l'indice de continuation.
	RunService.Heartbeat:Connect(function(dt: number)
		if not typing then
			return
		end
		local body2 = bodyLabel
		if not body2 then
			return
		end
		local prev = math.floor(revealed)
		revealed += dt * CHARS_PER_SEC
		local n = math.floor(revealed)
		if n >= total then
			n = total
			typing = false
			setHintVisible(true)
		end
		body2.MaxVisibleGraphemes = n
		-- "tap tap tap" : une frappe toutes les TYPE_SOUND_EVERY lettres revelees, pitch varie. Rien si le son est absent.
		if typeSoundOk and n > prev then
			typeAccum += n - prev
			if typeAccum >= TYPE_SOUND_EVERY then
				typeAccum = 0
				local s = SoundUtils.play(TYPE_SOUND)
				if s then
					s.PlaybackSpeed = math.random(92, 108) / 100
				end
			end
		end
	end)
end

-- Joue une SEQUENCE de repliques. onDone est appele quand le joueur a passe la derniere. Rejouer pendant un dialogue
-- en cours le remplace.
function Dialogue.play(lines: { Line }, onDone: (() -> ())?)
	build()
	local b = banner
	if not b or #lines == 0 then
		return
	end
	sequence = lines
	currentIndex = 1
	onDoneFn = onDone
	shownOnScreen = true
	b.Visible = true
	refreshScale()
	-- Glisse depuis le bas jusqu'a sa place.
	b.Position = hiddenPosition()
	if slideTween then
		slideTween:Cancel()
	end
	slideTween = TweenService:Create(b, POP_IN, { Position = shownPosition() })
	slideTween:Play()
	-- Repart sans expression : la 1re replique posera la sienne (pas d'heritage du dialogue precedent).
	lastEmotion = nil
	if portrait then
		portrait.Visible = false
	end
	startLine(1)
end

-- Ferme le dialogue tout de suite, SANS appeler onDone (annulation). Sans effet si rien n'est affiche.
function Dialogue.hide()
	onDoneFn = nil
	hideBanner()
end

function Dialogue.isOpen(): boolean
	return shownOnScreen
end

return Dialogue
