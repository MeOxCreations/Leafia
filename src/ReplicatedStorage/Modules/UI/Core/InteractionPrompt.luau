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
local RunService = game:GetService("RunService")

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
-- ===== LE REFUS =====
-- La pilule devient ROUGE et la pastille TREMBLE, un instant. C'est la reponse a "j'ai appuye et il ne s'est rien
-- passe" : sans elle, une action verrouillee ressemble a un bug, et le joueur reappuie de plus en plus vite.
--
-- ROUGE ET SECOUSSE ENSEMBLE, jamais l'un sans l'autre. La couleur seule se remarque a peine sur un prompt deja
-- colore qui pulse ; la secousse seule ne dit pas que c'est un REFUS. Les deux ensemble ne se lisent que d'une
-- facon.
local REFUSE_COLOR = Color3.fromRGB(255, 58, 58)
-- Combien de temps elle reste rouge avant que le pulse reprenne.
local REFUSE_HOLD = 0.45
-- LA SECOUSSE PORTE SUR LA ROTATION, pas sur la position. La position du prompt est reecrite a chaque image par
-- WorldAnchor : une secousse posee dessus serait effacee avant d'etre vue. La rotation, personne n'y touche.
local REFUSE_TILT = 7 -- degres de chaque cote
local REFUSE_STEP = 0.05 -- duree d'un aller
local REFUSE_SHAKES = 3 -- allers-retours
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
-- LA PILULE ELLE-MEME et le tween de son pulse. Gardes pour le REFUS : il faut couper le pulse avant de poser le
-- rouge, sinon les deux ecrivent la meme couleur et c'est le pulse qui gagne une image plus tard.
local pill: TextButton? = nil
-- ===== LA JAUGE, SOUS LA PILULE =====
-- CERTAINS OBJETS ONT UN ETAT CHIFFRE que le joueur doit voir AVANT d'agir : un seau a moitie plein, un reservoir
-- qui se vide. L'afficher a cote, dans son propre panneau, fait DEUX choses a lire au meme endroit -- et la
-- seconde finit toujours par recouvrir la premiere.
--
-- ELLE VIT DONC DANS LE PROMPT, sous la pilule et dans le meme conteneur : elle suit l'objet, elle pope avec, elle
-- s'en va avec. Aucun appelant n'a a la placer ni a la nettoyer.
--
-- CACHEE PAR DEFAUT : seul un appelant qui APPELLE `setGauge` en a une. Les cinq autres features ne changent pas
-- d'un pixel.
local gaugeBox: Frame? = nil
local gaugeFill: Frame? = nil
local gaugeLabel: TextLabel? = nil
local GAUGE_BACK = Color3.fromRGB(24, 32, 42)
local GAUGE_FILL = Color3.fromRGB(98, 206, 59)
-- PLEIN CHANGE DE COULEUR : le joueur n'a pas a comparer deux nombres pour comprendre qu'il doit aller vider.
local GAUGE_FULL = Color3.fromRGB(255, 158, 44)
-- ELLE GLISSE, elle ne saute pas. Une barre qui change d'un bond ne se lit pas : on voit l'etat d'apres, jamais le
-- mouvement, donc on ne sent pas qu'on progresse.
local GAUGE_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local gaugeTween: Tween? = nil
local pulseTween: Tween? = nil
local refusing = false
local onActivateFn: (() -> ())? = nil
local shown = false

-- ===== UN REGISTRE DE DEMANDES, PAS UNE COURSE =====
-- Le prompt est un SINGLETON, mais l'arbitrage ne peut PAS vivre chez les appelants.
--
-- L'ancienne version etait un "dernier arrive gagne" : chaque feature regardait `currentTarget()`, voyait que la
-- pilule n'etait plus la sienne, et la reprenait. Avec DEUX objets a portee en meme temps (un seau et un camion,
-- une tondeuse et une echelle), les deux boucles se la reprenaient A CHAQUE IMAGE -- et comme `show` rejouait le
-- pop et son SON a chaque appel, ca donnait un "POPOPOPOP" a la frequence de l'ecran. La priorite ne tranchait
-- rien : a priorite EGALE (0 par defaut partout) le test `want < activePriority` laissait tout le monde passer.
--
-- Maintenant chaque feature DECLARE une demande et la retire quand elle n'a plus lieu d'etre ; c'est le module qui
-- choisit, une fois par image. Une seule question, une seule reponse -- meme raison que CarryUtils pour les mains.
type Claim = {
	target: WorldAnchor.Target,
	key: string,
	label: string,
	offset: Vector3?,
	onActivate: (() -> ())?,
	title: string?,
	cameraRelative: boolean?,
	priority: number,
}

-- Tableau et pas table indexee par la cible : une cible peut etre un Vector3, dont l'identite en tant que CLE n'est
-- pas garantie. L'ordre d'arrivee sert aussi a departager deux demandes rigoureusement equivalentes.
local claims: { Claim } = {}
local displayed: Claim? = nil
local resolveConn: RBXScriptConnection? = nil

-- Ecart de distance (studs) a partir duquel un pretendant PLUS PROCHE prend la place. Sans cette marge, deux objets
-- a distance quasi egale se la reprendraient a chaque image : on aurait remplace un clignotement par un autre.
local SWITCH_MARGIN = 2
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

	-- LA JAUGE, sous la pilule. Meme conteneur, donc meme pop et meme sortie : il n'y a rien a synchroniser.
	local bar = Instance.new("Frame")
	bar.Name = "Gauge"
	bar.LayoutOrder = 3
	bar.Size = UDim2.fromOffset(96, 16)
	bar.BackgroundColor3 = GAUGE_BACK
	bar.BackgroundTransparency = 0.1
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = box

	local barCorner = Instance.new("UICorner") :: UICorner
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	local barStroke = Instance.new("UIStroke")
	barStroke.Color = Color3.fromRGB(255, 255, 255)
	barStroke.Thickness = 1.5
	barStroke.Transparency = 0.55
	barStroke.Parent = bar

	local barPad = Instance.new("UIPadding")
	local barGap = UDim.new(0, 2)
	barPad.PaddingTop, barPad.PaddingBottom = barGap, barGap
	barPad.PaddingLeft, barPad.PaddingRight = barGap, barGap
	barPad.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GAUGE_FILL
	fill.BorderSizePixel = 0
	fill.Parent = bar

	local fillCorner = Instance.new("UICorner") :: UICorner
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.BackgroundTransparency = 1
	amount.Size = UDim2.fromScale(1, 1)
	amount.Font = FONT
	amount.TextColor3 = Color3.new(1, 1, 1)
	amount.TextScaled = true
	amount.TextStrokeColor3 = Color3.new(0, 0, 0)
	amount.TextStrokeTransparency = 0.4
	amount.ZIndex = 2
	amount.Text = ""
	amount.Parent = bar

	gaugeBox, gaugeFill, gaugeLabel = bar, fill, amount

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
	al.Text = "TAKE"
	al.Parent = btn

	-- PULSE du FOND de la pilule en boucle (aller-retour A <-> B). Une seule fois, joue en continu : ca ne se
	-- voit que quand le prompt est affiche, et ca ne coute rien sinon.
	local pulse = TweenService:Create(btn, PILL_PULSE, { BackgroundColor3 = PILL_PULSE_B })
	pulse:Play()
	pill, pulseTween = btn, pulse

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

-- ===== LE CHOIX =====

local function findClaim(target: WorldAnchor.Target): number?
	for index, claim in claims do
		if claim.target == target then
			return index
		end
	end
	return nil
end

local function targetPosition(target: WorldAnchor.Target): Vector3?
	if typeof(target) == "Vector3" then
		return target
	end
	if typeof(target) == "Instance" and target:IsA("BasePart") then
		return target.Position
	end
	return nil
end

-- Une cible detruite (streaming, objet ramasse, build) laisse une demande orpheline. Sans ce menage, la pilule
-- reapparaitrait sur un objet qui n'existe plus.
local function claimAlive(claim: Claim): boolean
	local target = claim.target
	if typeof(target) == "Instance" then
		return target.Parent ~= nil
	end
	return true
end

local function playerPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function distanceTo(claim: Claim, from: Vector3?): number
	local pos = targetPosition(claim.target)
	if not (pos and from) then
		return math.huge
	end
	return (pos - from).Magnitude
end

local function hideVisual()
	if not shown then
		return
	end
	shown = false
	displayed = nil
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

-- Met la pilule sur une demande. LE POP ET SON SON NE REPARTENT QUE SI LA CIBLE CHANGE : toutes les features
-- redemandent leur place a chaque image, et rejouer l'apparition a chaque appel etait exactement le "POPOPOPOP".
--- Cache la jauge et coupe son glissement. Appele a chaque changement de cible : la jauge appartient a l'objet
--- qu'on quitte, et la laisser afficherait le remplissage d'un seau sur le badge d'autre chose.
local function clearGauge()
	if gaugeTween then
		gaugeTween:Cancel()
		gaugeTween = nil
	end
	local bar, fill = gaugeBox, gaugeFill
	if bar then
		bar.Visible = false
	end
	if fill then
		fill.Size = UDim2.fromScale(0, 1)
	end
end

local function applyClaim(claim: Claim?)
	if not claim then
		clearGauge()
		hideVisual()
		return
	end
	build()
	local box, kl, al, bdg, ttl, sc = container, keyLabel, actionLabel, badge, titleLabel, scale
	if not (box and kl and al and bdg and ttl and sc) then
		return
	end
	local previous = displayed
	local isNew = not shown or previous == nil or previous.target ~= claim.target

	kl.Text = claim.key
	al.Text = claim.label
	bdg.Visible = not IS_TOUCH -- pas de touche a montrer sur mobile
	ttl.Text = claim.title or ""
	ttl.Visible = claim.title ~= nil and claim.title ~= "" -- pas de ligne vide si aucun titre (ex l'echelle)
	onActivateFn = claim.onActivate
	displayed = claim
	shown = true

	if isNew then
		-- NOUVELLE CIBLE, NOUVELLE JAUGE. Elle appartient a l'objet qu'on quitte : la laisser afficherait le
		-- remplissage d'un seau sur le badge d'une tondeuse, pendant le temps qu'il faut a son proprietaire pour
		-- la reposer -- et ce temps se voit.
		clearGauge()
		box.Visible = true
		WorldAnchor.attach(box, claim.target, claim.offset, nil, nil, claim.cameraRelative)
		-- APPARITION "slime" : on repart de 0 et on rebondit jusqu'a l'echelle cible (Elastic), + le son de pop.
		if popTween then
			popTween:Cancel()
		end
		sc.Scale = 0
		popTween = TweenService:Create(sc, POP_IN, { Scale = baseScale })
		popTween:Play()
		SoundUtils.play(POP_SOUND)
	else
		-- Meme cible : on rafraichit seulement ce qui a pu bouger (le libelle, l'offset). Aucun effet visuel.
		WorldAnchor.setOffset(box, claim.offset or Vector3.zero)
	end
end

-- Choisit qui occupe la pilule : priorite la plus haute, puis le PLUS PROCHE du joueur, puis le premier arrive.
-- Celui qui est deja affiche garde une marge (SWITCH_MARGIN) : c'est ce qui empeche deux objets a egale distance
-- de se la disputer image apres image.
local function resolve()
	for index = #claims, 1, -1 do
		if not claimAlive(claims[index]) then
			table.remove(claims, index)
		end
	end

	local from = playerPosition()
	local best: Claim? = nil
	local bestDistance = math.huge
	for _, claim in claims do
		local distance = distanceTo(claim, from)
		local leader = best
		if
			leader == nil
			or claim.priority > leader.priority
			or (claim.priority == leader.priority and distance < bestDistance)
		then
			best, bestDistance = claim, distance
		end
	end

	-- HYSTERESIS : on ne prend la place a celui qui l'occupe que si on est FRANCHEMENT mieux place.
	local current = displayed
	if current and best and best ~= current and findClaim(current.target) then
		if best.priority == current.priority and distanceTo(current, from) - bestDistance < SWITCH_MARGIN then
			best = current
		end
	end

	applyClaim(best)

	-- La boucle meurt avec la derniere demande : rien a arbitrer, rien a faire tourner.
	if #claims == 0 and resolveConn then
		resolveConn:Disconnect()
		resolveConn = nil
	end
end

-- Declare une demande d'affichage sur `target` (BasePart suivie, ou Vector3 fixe). `key` = la touche affichee
-- (ex "E"), `label` = l'action (ex "TAKE"). `offset` decale le point vise dans le monde (studs), pour flotter
-- au-dessus. Sur mobile, le badge de touche est cache ; `onActivate` est appele au tap (et au clic, en bonus).
--
-- `priority` (0 par defaut) passe devant la distance quand deux demandes se recouvrent.
--
-- LA DEMANDE RESTE ENREGISTREE tant qu'on n'appelle pas `release`. C'est ce qui rend l'appel repetable sans rien
-- casser : redemander a chaque image ne fait que rafraichir, et une feature qui perd la place la RETROUVE toute
-- seule des que l'autre relache -- sans avoir a re-detecter quoi que ce soit.
--
-- Rend true si la pilule est A NOUS a cet instant, false si quelqu'un d'autre l'occupe. Un false n'est PAS un
-- echec : la demande est enregistree, et elle sera servie des que la place se libere.
function InteractionPrompt.show(
	target: WorldAnchor.Target,
	key: string,
	label: string,
	offset: Vector3?,
	onActivate: (() -> ())?,
	title: string?,
	cameraRelative: boolean?,
	priority: number?
): boolean
	local claim: Claim = {
		target = target,
		key = key,
		label = label,
		offset = offset,
		onActivate = onActivate,
		title = title,
		cameraRelative = cameraRelative,
		priority = priority or 0,
	}
	local index = findClaim(target)
	if index then
		-- ON REECRIT LA DEMANDE EN PLACE : garder son rang d'arrivee evite qu'une feature qui redemande a chaque
		-- image passe sans arret devant les autres au depart de la file.
		claims[index] = claim
	else
		table.insert(claims, claim)
	end

	if not resolveConn then
		resolveConn = RunService.RenderStepped:Connect(resolve)
	end
	resolve()
	return displayed == claim
end

-- Retire la demande de `target`. A appeler des que l'action n'a plus lieu d'etre (on s'est eloigne, l'objet est
-- pris, les mains sont occupees). C'est le pendant OBLIGATOIRE de `show` : une demande jamais retiree ferait
-- reapparaitre la pilule sur un objet qu'on a quitte.
--
-- IL N'Y A VOLONTAIREMENT PAS DE `hide()` GLOBAL. Il existait, et c'etait le piege : une feature qui cache "le
-- prompt" jette les demandes des autres, et celles encore a portee ne reviennent jamais. Le jour ou une scene
-- devra vraiment vider l'ecran, ce sera une fonction A ELLE, qui met les demandes en pause et les REND ensuite.
function InteractionPrompt.release(target: WorldAnchor.Target?)
	if not target then
		return
	end
	local index = findClaim(target)
	if not index then
		return
	end
	table.remove(claims, index)
	resolve()
end

-- Deplace le prompt EN COURS d'affichage (le meme repere que le offset passe a show : monde, ou camera si
-- cameraRelative). L'appelant anime l'offset lui-meme (ex : glisser d'un cote a l'autre). Sans effet si rien n'est
-- affiche. L'offset est aussi ecrit dans la demande, sinon le rafraichissement de l'image suivante l'annulerait.
function InteractionPrompt.setOffset(offset: Vector3)
	local box = container
	local current = displayed
	if current then
		current.offset = offset
	end
	if box then
		WorldAnchor.setOffset(box, offset)
	end
end

-- La cible AFFICHEE en ce moment, ou nil si le prompt est cache. A tester avant de conclure que "mon prompt
-- est deja a l'ecran" : le singleton a pu passer a quelqu'un d'autre entre-temps.
--- REFUSE L'ACTION, VISIBLEMENT : la pilule rougit et la pastille tremble.
---
--- A appeler quand le joueur appuie sur une action VERROUILLEE. Sans ce retour, il a appuye et il ne s'est rien
--- passe -- ce qui se lit comme un bug, et il reappuie de plus en plus vite.
---
--- Silencieuse si rien n'est affiche, et ignoree si un refus joue deja : deux refus empiles se battraient pour la
--- meme couleur et la meme rotation, et on verrait la pilule rester rouge.
function InteractionPrompt.refuse()
	local btn, box = pill, container
	if not (btn and box and shown) or refusing then
		return
	end
	refusing = true

	-- LE PULSE EST COUPE D'ABORD. Il ecrit la meme propriete en boucle : laisse en route, il reposerait sa couleur
	-- par-dessus le rouge a son tour suivant, et le refus clignoterait au lieu de se voir.
	local pulse = pulseTween
	if pulse then
		pulse:Cancel()
	end
	btn.BackgroundColor3 = REFUSE_COLOR

	task.spawn(function()
		-- LA SECOUSSE : un aller, un retour, plusieurs fois. Sur la ROTATION, que personne d'autre n'ecrit.
		for i = 1, REFUSE_SHAKES do
			local side = if i % 2 == 1 then 1 else -1
			if not box.Parent then
				break
			end
			TweenService:Create(box, TweenInfo.new(REFUSE_STEP), { Rotation = REFUSE_TILT * side }):Play()
			task.wait(REFUSE_STEP)
		end
		if box.Parent then
			TweenService:Create(box, TweenInfo.new(REFUSE_STEP), { Rotation = 0 }):Play()
		end
		task.wait(math.max(0, REFUSE_HOLD - REFUSE_SHAKES * REFUSE_STEP))
		-- ET LE PULSE REPREND. Recree et pas relance : un tween annule ne repart pas de la ou il en etait, et le
		-- garder aurait laisse la pilule sur la couleur du refus.
		refusing = false
		local current = pill
		if current and current.Parent then
			current.BackgroundColor3 = PILL_PULSE_A
			local again = TweenService:Create(current, PILL_PULSE, { BackgroundColor3 = PILL_PULSE_B })
			pulseTween = again
			again:Play()
		end
	end)
end

--- LA JAUGE DE L'OBJET AFFICHE. `ratio` a `nil` la cache ; sinon elle va de 0 a 1, avec son texte au milieu.
---
--- ELLE NE S'AFFICHE QUE SI LE PROMPT EST A `target`. Sans ce test, un seau pose a dix metres ecrirait sa jauge
--- sur le badge d'une tondeuse -- le prompt est un SINGLETON, et tout ce qui s'y ecrit doit passer par la meme
--- question : est-ce que c'est encore a moi ?
function InteractionPrompt.setGauge(target: WorldAnchor.Target?, ratio: number?, label: string?)
	local bar, fill, amount = gaugeBox, gaugeFill, gaugeLabel
	if not (bar and fill and amount) then
		return
	end
	if ratio == nil or not InteractionPrompt.owns(target) then
		bar.Visible = false
		return
	end
	local value = math.clamp(ratio :: number, 0, 1)
	bar.Visible = true
	amount.Text = label or ""
	fill.BackgroundColor3 = if value >= 1 then GAUGE_FULL else GAUGE_FILL
	if gaugeTween then
		gaugeTween:Cancel()
	end
	local tween = TweenService:Create(fill, GAUGE_TWEEN, { Size = UDim2.fromScale(value, 1) })
	gaugeTween = tween
	tween:Play()
end

function InteractionPrompt.currentTarget(): WorldAnchor.Target?
	local current = displayed
	return if shown and current then current.target else nil
end

--- LA PILULE EST-ELLE A `target` A CET INSTANT ?
---
--- A TESTER AVANT D'AGIR SUR UN APPUI DE TOUCHE, et c'est un bug qu'on vient de payer. `E` est partagee par le
--- seau, la tondeuse, l'echelle et la porte du didacticiel. Chacun garde son propre bind et rend `Pass` (avaler
--- l'input casserait les autres), donc UN appui reveille TOUT ce qui est a portee : un seau pose a cote d'une
--- tondeuse, et le joueur prend la machine ET part marcher vers le seau.
---
--- Le badge, lui, est deja arbitre -- le plus proche gagne. Ce test fait simplement SUIVRE LA TOUCHE A CE QUE LE
--- JOUEUR VOIT : une seule action par appui, celle qu'il a lue a l'ecran.
---
--- L'exception est le geste INVERSE (reposer ce qu'on tient) : il n'y a alors aucun badge, et rien a arbitrer
--- puisque personne d'autre ne peut reposer notre objet. Les appelants gardent donc ce chemin en dehors du test.
function InteractionPrompt.owns(target: WorldAnchor.Target?): boolean
	return target ~= nil and InteractionPrompt.currentTarget() == target
end

return InteractionPrompt
