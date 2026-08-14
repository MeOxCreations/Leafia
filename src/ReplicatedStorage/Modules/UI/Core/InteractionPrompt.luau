--!strict
-- PROMPT D'INTERACTION : un badge "[E] PRENDRE" qui flotte au-dessus d'un objet quand une action est possible.
--
-- Primitive REUTILISABLE : n'importe quelle feature appelle show/hide avec SA touche et SON libelle (E, F, ...).
-- Un seul prompt a la fois (singleton) : montrer une autre cible remplace la precedente.
--
-- Il SUIT sa cible a l'ecran via WorldAnchor (un ScreenGui projete, pas un BillboardGui : pixels constants, texte
-- lisible a toute distance, pas d'eclairage). Voir WorldAnchor pour le piege de l'inset de 36 px.
--
-- MOBILE (tactile SANS clavier) : aucune touche a afficher -> on cache le badge, le prompt devient un BOUTON a
-- taper. Le declenchement passe par `onActivate` (clic / tap) ; au clavier, c'est la feature qui ecoute sa touche,
-- le prompt n'est qu'un indicateur (mais reste cliquable, en bonus).
--
-- Construit EN CODE (pas de template Studio) : drop-in, rien a preparer dans l'editeur.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local WorldAnchor = require(ReplicatedStorage.Modules.UI.Core.WorldAnchor)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)

local InteractionPrompt = {}

local player = Players.LocalPlayer
-- Mobile = tactile SANS clavier. On y montre un bouton a taper au lieu d'une touche qui n'existe pas.
local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ===== Style (simple, lisible) =====
local PILL_TRANSPARENCY = 0.15
local BADGE_COLOR = Color3.fromRGB(255, 255, 255)
local BADGE_TEXT_COLOR = Color3.fromRGB(24, 27, 32)
local LABEL_COLOR = Color3.fromRGB(255, 255, 255)
-- Le FOND de la pilule (le TextButton) PULSE entre deux roses (aller-retour en boucle), pour attirer l'oeil.
local PILL_PULSE_A = Color3.fromRGB(255, 119, 230)
local PILL_PULSE_B = Color3.fromRGB(255, 73, 216)
local PILL_PULSE = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local BADGE_SIZE = 34 -- cote du carre de la touche, en pixels
local FONT = Enum.Font.GothamBold
local TITLE_FONT = Enum.Font.LuckiestGuy -- le titre de l'objet (ex "MAILBOX") : police display, plus fun

-- APPARITION "slime" : le prompt part de 0 et rebondit en Elastic (overshoot + oscillations amorties = l'effet
-- gelee "prolonge"). Disparition : un pop-out sec et court.
local POP_IN = TweenInfo.new(0.55, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.In)
-- Son joue a l'apparition (clone depuis SoundService). Son 2D (pas de host) : c'est un retour d'interface.
local POP_SOUND = { "Sounds", "UI", "AppearSound_1" }

-- CLIC / TAP : squish "slime" PROLONGE. On ecrase d'un coup puis on rebondit en Elastic (overshoot + oscillations
-- amorties = l'effet gelee qui se prolonge). Retour d'interface satisfaisant a chaque appui.
local PRESS_SQUISH = 0.8 -- a combien on ecrase au clic (fraction de l'echelle courante)
local PRESS_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

local gui: ScreenGui? = nil
local container: Frame? = nil -- le conteneur vertical (titre + pilule), c'est LUI que WorldAnchor suit
local badge: Frame? = nil
local keyLabel: TextLabel? = nil
local actionLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil -- titre de l'objet, au-dessus de la pilule (ex "MAILBOX")
local scale: UIScale? = nil
local onActivateFn: (() -> ())? = nil
local shown = false
-- Echelle CIBLE (proportionnelle a l'ecran) : c'est vers elle que le pop d'apparition tend, pas vers 1. Sinon un
-- gros / petit ecran perdrait sa mise a l'echelle des la 1re apparition.
local baseScale = 1
local popTween: Tween? = nil

local function isPopping(): boolean
	return popTween ~= nil and popTween.PlaybackState == Enum.PlaybackState.Playing
end

local function refreshScale()
	local camera = workspace.CurrentCamera
	local vy = if camera then camera.ViewportSize.Y else 1080
	-- Proportionnel a la hauteur d'ecran (repere 1080p), borne pour rester lisible sans devenir enorme.
	baseScale = math.clamp(vy / 1080, 0.75, 1.4)
	-- On ne touche PAS a l'echelle pendant un pop : le tween la pilote (sinon on ecraserait l'animation).
	local s = scale
	if s and not isPopping() then
		s.Scale = baseScale
	end
end

local function build()
	if gui and gui.Parent then
		return
	end
	local playerGui = player:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "InteractionPromptUI"
	screen.ResetOnSpawn = false -- survit au respawn : le prompt ne depend pas du personnage
	screen.IgnoreGuiInset = false -- WorldToViewportPoint rend SANS l'inset -> ce ScreenGui doit le compter
	screen.DisplayOrder = 50
	screen.Parent = playerGui

	-- Conteneur VERTICAL : le TITRE de l'objet au-dessus, la PILULE (touche + action) en dessous, centres. C'est LUI
	-- que WorldAnchor suit, et sur lui qu'on met l'echelle -> titre + pilule popent / squishent ENSEMBLE.
	local box = Instance.new("Frame")
	box.Name = "PromptBox"
	box.AutomaticSize = Enum.AutomaticSize.XY
	box.Size = UDim2.fromOffset(0, 0)
	box.BackgroundTransparency = 1
	box.Parent = screen

	local boxLayout = Instance.new("UIListLayout")
	boxLayout.FillDirection = Enum.FillDirection.Vertical
	boxLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	boxLayout.Padding = UDim.new(0, 4)
	boxLayout.SortOrder = Enum.SortOrder.LayoutOrder
	boxLayout.Parent = box

	-- TITRE de l'objet (ex "MAILBOX"), au-dessus de la pilule. Blanc + contour pour la lisibilite. Cache si vide.
	local ttl = Instance.new("TextLabel")
	ttl.Name = "Title"
	ttl.AutomaticSize = Enum.AutomaticSize.XY
	ttl.Size = UDim2.fromOffset(0, 0)
	ttl.BackgroundTransparency = 1
	ttl.Font = TITLE_FONT
	ttl.TextColor3 = Color3.new(1, 1, 1)
	ttl.TextSize = 18
	ttl.TextStrokeColor3 = Color3.new(0, 0, 0)
	ttl.TextStrokeTransparency = 0.35
	ttl.LayoutOrder = 1
	ttl.Text = ""
	ttl.Visible = false
	ttl.Parent = box

	-- La PILULE ENTIERE est un bouton : cliquer / taper n'importe ou dessus declenche l'action.
	local btn = Instance.new("TextButton")
	btn.Name = "Prompt"
	btn.LayoutOrder = 2
	btn.AutomaticSize = Enum.AutomaticSize.XY -- s'ajuste au contenu (badge + libelle)
	btn.Size = UDim2.fromOffset(0, 0)
	btn.BackgroundColor3 = PILL_PULSE_A
	btn.BackgroundTransparency = PILL_TRANSPARENCY
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Parent = box

	local btnCorner = Instance.new("UICorner") :: UICorner
	btnCorner.CornerRadius = UDim.new(1, 0) -- pilule
	btnCorner.Parent = btn

	local btnPad = Instance.new("UIPadding")
	local pad = UDim.new(0, 8)
	btnPad.PaddingTop, btnPad.PaddingBottom = pad, pad
	btnPad.PaddingLeft = UDim.new(0, 10)
	btnPad.PaddingRight = UDim.new(0, 14)
	btnPad.Parent = btn

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = btn

	-- Badge de la touche (carre arrondi clair, lettre sombre). Cache sur mobile.
	local bdg = Instance.new("Frame")
	bdg.Name = "KeyBadge"
	bdg.Size = UDim2.fromOffset(BADGE_SIZE, BADGE_SIZE)
	bdg.BackgroundColor3 = BADGE_COLOR
	bdg.LayoutOrder = 1
	bdg.Parent = btn

	local bdgCorner = Instance.new("UICorner") :: UICorner
	bdgCorner.CornerRadius = UDim.new(0, 8)
	bdgCorner.Parent = bdg

	local kl = Instance.new("TextLabel")
	kl.Name = "Key"
	kl.Size = UDim2.fromScale(1, 1)
	kl.BackgroundTransparency = 1
	kl.Font = FONT
	kl.TextColor3 = BADGE_TEXT_COLOR
	kl.TextScaled = true
	kl.Text = "E"
	kl.Parent = bdg
	-- Un peu de marge dans le badge pour que la lettre ne colle pas aux bords.
	local klPad = Instance.new("UIPadding")
	local p = UDim.new(0, 5)
	klPad.PaddingTop, klPad.PaddingBottom, klPad.PaddingLeft, klPad.PaddingRight = p, p, p, p
	klPad.Parent = kl

	-- Libelle de l'action.
	local al = Instance.new("TextLabel")
	al.Name = "Action"
	al.AutomaticSize = Enum.AutomaticSize.X
	al.Size = UDim2.fromOffset(0, BADGE_SIZE)
	al.BackgroundTransparency = 1
	al.Font = FONT
	al.TextColor3 = LABEL_COLOR
	al.TextSize = 20
	al.LayoutOrder = 2
	al.Text = "PRENDRE"
	al.Parent = btn

	-- PULSE du FOND de la pilule en boucle (aller-retour A <-> B). Une seule fois, joue en continu : ca ne se
	-- voit que quand le prompt est affiche, et ca ne coute rien sinon.
	TweenService:Create(btn, PILL_PULSE, { BackgroundColor3 = PILL_PULSE_B }):Play()

	local sc = Instance.new("UIScale")
	sc.Parent = box

	gui, container, badge, keyLabel, actionLabel, titleLabel, scale = screen, box, bdg, kl, al, ttl, sc

	btn.Activated:Connect(function()
		-- Squish "slime" prolonge : on ecrase d'un coup puis on rebondit (Elastic) jusqu'a l'echelle courante.
		local s = scale
		if s then
			s.Scale = baseScale * PRESS_SQUISH
			popTween = TweenService:Create(s, PRESS_TWEEN, { Scale = baseScale })
			popTween:Play()
		end
		if onActivateFn then
			onActivateFn()
		end
	end)
	refreshScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
	end
end

-- Montre le prompt sur `target` (BasePart suivie, ou Vector3 fixe). `key` = la touche affichee (ex "E"), `label`
-- = l'action (ex "PRENDRE"). `offset` decale le point vise dans le monde (studs), pour flotter au-dessus. Sur
-- mobile, le badge de touche est cache ; `onActivate` est appele au tap (et au clic, partout, en bonus).
function InteractionPrompt.show(
	target: WorldAnchor.Target,
	key: string,
	label: string,
	offset: Vector3?,
	onActivate: (() -> ())?,
	title: string?,
	cameraRelative: boolean?
)
	build()
	local box, kl, al, bdg, ttl, s = container, keyLabel, actionLabel, badge, titleLabel, scale
	if not (box and kl and al and bdg and ttl and s) then
		return
	end
	kl.Text = key
	al.Text = label
	bdg.Visible = not IS_TOUCH -- pas de touche a montrer sur mobile
	ttl.Text = title or ""
	ttl.Visible = title ~= nil and title ~= "" -- pas de ligne vide si aucun titre (ex l'echelle)
	onActivateFn = onActivate
	WorldAnchor.attach(box, target, offset, nil, nil, cameraRelative)
	shown = true

	-- APPARITION "slime" : on repart de 0 et on rebondit jusqu'a l'echelle cible (Elastic), + le son de pop.
	if popTween then
		popTween:Cancel()
	end
	s.Scale = 0
	popTween = TweenService:Create(s, POP_IN, { Scale = baseScale })
	popTween:Play()
	SoundUtils.play(POP_SOUND)
end

-- Deplace le prompt EN COURS d'affichage (le meme repere que le offset passe a show : monde, ou camera si
-- cameraRelative). L'appelant anime l'offset lui-meme (ex : glisser d'un cote a l'autre). Sans effet si rien n'est
-- affiche.
function InteractionPrompt.setOffset(offset: Vector3)
	local box = container
	if box then
		WorldAnchor.setOffset(box, offset)
	end
end

function InteractionPrompt.hide()
	if not shown then
		return
	end
	shown = false
	onActivateFn = nil
	local box, s = container, scale
	if not box then
		return
	end
	if popTween then
		popTween:Cancel()
	end
	-- POP-OUT : on retrecit vite puis on detache. Si on RE-montre pendant (shown repasse true), on n'efface pas.
	if s then
		local t = TweenService:Create(s, POP_OUT, { Scale = 0 })
		popTween = t
		t.Completed:Connect(function()
			if not shown and popTween == t then
				WorldAnchor.detach(box)
				box.Visible = false
			end
		end)
		t:Play()
	else
		WorldAnchor.detach(box)
		box.Visible = false
	end
end

return InteractionPrompt
