--!strict
-- Notifications LATERALES (bas droite), en PILE qui MONTE. Le template TemplateNotificationSide (range dans
-- NotificationUI.Templates) est CLONE dans HolderList a chaque apparition. La plus recente arrive EN BAS ; les autres
-- remontent. Quand on depasse MAX_VISIBLE, la plus VIEILLE (en haut) se REPLIE en Y (hauteur -> 0) et disparait.
--
-- Effets, chacun sur sa propriete (pas de conflit) :
--   - ENTREE / RETRAIT / OUVERTURE-FERMETURE -> la SIZE en Y (0 <-> fermee <-> ouverte). AnchorPoint (0.5, 1) sur la
--     frame : elle grandit / se replie par le BAS.
--   - SURVOL -> un UIScale (leger grossissement + rebond).
--   - TOUR du degrade du contour (UIGradientRotate) au survol -> la Rotation du gradient.
--
-- FERMETURE AUTO : chaque notif se replie seule apres LIFETIME secondes ; le temps restant s'affiche dans
-- CooldownClearNotification (visible ouvert ET ferme, a des places differentes). Le serveur declenche les notifs via
-- le remote SideNotify ; spawn() reste appelable a la main pour tester.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local FormatUtils = require(ReplicatedStorage.Modules.Utils.FormatUtils)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local SideNotificationHandler = {}

-- Geometrie (design Studio), valeurs arrondies. AnchorPoint (0.5, 1) sur la frame : hauteur qui grandit / se replie
-- par le BAS.
local WIDTH = 0.98
local CLOSED_H = 0.076
local OPEN_H = 0.356
local CLOSED_SIZE = UDim2.fromScale(WIDTH, CLOSED_H)
local OPEN_SIZE = UDim2.fromScale(WIDTH, OPEN_H)
local GONE_SIZE = UDim2.fromScale(WIDTH, 0) -- hauteur 0 : etat de RETRAIT (repli vertical par le bas, AnchorPoint 0.5,1)
local ENTER_SIZE = UDim2.fromScale(0, CLOSED_H) -- largeur 0 : etat d'ENTREE (la notif se deplie en LARGEUR, 0 -> pleine)
local CLOSED_CORNER = UDim.new(0.2, 0)
local OPEN_CORNER = UDim.new(0.08, 0)
local CLOSED_THICKNESS = 0.03
local OPEN_THICKNESS = 0.01

-- L'Image (icone) se repositionne + se retaille avec l'etat : petite en HAUT-DROITE quand la notif est ouverte (elle
-- laisse la place au contenu), plus grande a droite quand elle est fermee. Valeurs du design (Studio), arrondies.
local IMAGE_OPEN_POS = UDim2.fromScale(0.94, 0.09)
local IMAGE_OPEN_SIZE = UDim2.fromScale(0.1, 0.1)
local IMAGE_CLOSED_POS = UDim2.fromScale(0.94, 0.5)
local IMAGE_CLOSED_SIZE = UDim2.fromScale(0.4, 0.4)

-- Le texte (NameNotificationType) se repositionne + se retaille aussi selon l'etat. Valeurs du design (Studio).
local NAME_OPEN_POS = UDim2.fromScale(0.442, 0.096)
local NAME_OPEN_SIZE = UDim2.fromScale(0.837, 0.117)
local NAME_CLOSED_POS = UDim2.fromScale(0.396, 0.55)
local NAME_CLOSED_SIZE = UDim2.fromScale(0.76, 0.51)

-- DETAILS visibles UNIQUEMENT quand la notif est OUVERTE : le long texte + les points de competence gagnes. On les
-- rend VISIBLE a l'ouverture, caches a la fermeture (ces textes sont regles Visible=false par defaut dans Studio).
-- Position / taille du design.
local DESC_POS = UDim2.fromScale(0.47, 0.375)
local DESC_SIZE = UDim2.fromScale(0.757, 0.249)
local ADD_POS = UDim2.fromScale(0.526, 0.912)
local ADD_SIZE = UDim2.fromScale(0.871, 0.108)
-- Quand il y a une ICONE de monnaie (recompense) : on RETRECIT + DECALE le texte des gains a gauche pour laisser la
-- place a l'icone a droite. Sans icone (points de competence...), le texte garde ADD_POS / ADD_SIZE (pleine largeur).
local ADD_ICON_POS = UDim2.fromScale(0.48, 0.875)
local ADD_ICON_SIZE = UDim2.fromScale(0.7, 0.15)
-- L'icone elle-meme : petite, carree (UIAspectRatioConstraint), a droite du texte des gains. A REGLER a l'oeil.
local EARN_ICON_POS = UDim2.fromScale(0.89, 0.88)
local EARN_ICON_SIZE = UDim2.fromScale(0.17, 0.17)
-- Icone de TYPE (ex : warning) : image posee selon le kind, meme style que l'icone de monnaie. A REGLER a l'oeil.
local WARNING_ICON = "rbxassetid://140043743404703"
local WARN_ICON_POS = UDim2.fromScale(0.89, 0.88)
local WARN_ICON_SIZE = UDim2.fromScale(0.17, 0.17)

-- Compte a rebours avant fermeture auto (CooldownClearNotification) : TOUJOURS visible, mais a une place differente et
-- plus vif (blanc) quand la notif est ouverte, plus discret (gris) quand elle est fermee. Valeurs du design (Studio).
local COOLDOWN_OPEN_POS = UDim2.fromScale(0.18, 0.92)
local COOLDOWN_OPEN_SIZE = UDim2.fromScale(0.253, 0.101)
local COOLDOWN_CLOSED_POS = UDim2.fromScale(0.788, 0.55)
local COOLDOWN_CLOSED_SIZE = UDim2.fromScale(0.13, 0.51)
local COOLDOWN_OPEN_COLOR = Color3.fromRGB(255, 255, 255)
local COOLDOWN_CLOSED_COLOR = Color3.fromRGB(184, 184, 184)

-- Pile : on garde MAX_VISIBLE notifs. Au-dela, la plus vieille se replie a 0 et disparait. Baisser = pile plus courte.
local MAX_VISIBLE = 6
-- Duree AVANT fermeture auto (secondes) : passe ce delai, la notif se replie seule. Surchargeable par notif via
-- NotifData.duration. Monter = notifs qui restent plus longtemps a l'ecran.
local LIFETIME = 6

-- Son joue a CHAQUE nouvelle notification (2D). A creer dans SoundService.Sounds.UI (NotificationSound).
local NOTIF_SOUND = { "Sounds", "UI", "NotificationSound" }
-- MOBILE : la pile est trop petite au doigt -> UIScale + reposition (elle passait sous le bouton de saut, bas-droit).
-- On distingue TABLETTE (grand ecran) et TELEPHONE (petit ecran) : le tel a besoin de PLUS GROS et PLUS HAUT.
local TABLET_SCALE = 0.9
local TABLET_POSITION = UDim2.fromScale(0.25, 0.08) -- Y plus petit = plus haut
local PHONE_SCALE = 1.1 -- taille sur telephone (petit ecran)
local PHONE_POSITION = UDim2.fromScale(0.28, 0.06) -- plus haut sur telephone (Y plus petit = plus haut)
local PHONE_MAX_SHORT_SIDE = 600 -- cote COURT du viewport en dessous duquel = TELEPHONE (au-dessus : tablette)

local TOGGLE_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- ouverture / fermeture (clic), rapide
-- ENTREE (depliage en largeur) : son PROPRE tween, plus LENT que l'ouverture. A REGLER : monter la duree = plus lent.
local ENTER_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local COLLAPSE_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In) -- retrait (repli vers 0)
local HOVER_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- survol (mini rebond)
-- Tour du degrade au survol : LENT et lisse (ease in / out). Monter la duree = plus lent.
local SPIN_TWEEN = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local HOVER_SCALE = 1.05
-- Defilement du montant en monnaie (+0 -> valeur) a l'ouverture. Quad Out = demarre vite, ralentit a la fin (arret net).
local COUNT_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Couleur d'accent selon le TYPE de notif (comme les toasts). Type inconnu / nil = on garde les couleurs du template.
local NOTIF_COLORS: { [string]: Color3 } = {
	Info = Color3.fromRGB(70, 160, 255),
	Success = Color3.fromRGB(255, 255, 255), -- blanc (le vert se noyait dans le decor vert du jeu)
	Warning = Color3.fromRGB(255, 90, 60),
	Reward = Color3.fromRGB(255, 200, 50),
}
-- Donnees d'une notification : son type (couleur), ses textes, `earn` = ce qui a ete GAGNE (texte libre) affiche dans
-- AdditionalEarnText, `icon` = un ImageLabel de monnaie a droite du gain (recompense en Coins, genere par le code), et
-- `amount` = un montant en monnaie qui DEFILE de +0 a sa valeur a l'ouverture (prioritaire sur `earn`). Le vrai
-- declencheur (un evenement) passera ca a spawn().
export type NotifData = { kind: string?, title: string?, description: string?, earn: string?, icon: string?, amount: number?, duration: number? }

-- Degrade "arc-en-ciel" (limite a quelques couleurs) qui DEFILE sur le texte "+X points de competence". On cycle la
-- palette dans le temps et on pose deux couleurs decalees sur son UIGradient. Depart = les 2 couleurs du design.
local RAINBOW = {
	Color3.fromRGB(219, 255, 61), -- #dbff3d
	Color3.fromRGB(176, 255, 112), -- #b0ff70
	Color3.fromRGB(100, 255, 205), -- une 3e (menthe) pour l'effet
}
local RAINBOW_SPEED = 0.8 -- vitesse du defile (cycles de palette par seconde). Monter = plus vif.

local notifications: { GuiObject } = {} -- index 1 = la PLUS VIEILLE (en haut de la pile)
local template: GuiObject? = nil
local holderList: Instance? = nil
local spawnOrder = 0 -- LayoutOrder croissant -> la plus recente en bas

-- Aspect ouvert / ferme : SIZE en Y + arrondi + contour. Sert aussi a l'ENTREE (depuis GONE_SIZE -> ferme).
-- Repositionne + retaille un enfant nomme (l'icone, le texte...) selon l'etat ouvert / ferme. Tween ou instantane.
local function moveChild(
	frame: GuiObject,
	name: string,
	open: boolean,
	instant: boolean,
	openPos: UDim2,
	openSize: UDim2,
	closedPos: UDim2,
	closedSize: UDim2
)
	local child = frame:FindFirstChild(name)
	if not (child and child:IsA("GuiObject")) then
		return
	end
	local pos = if open then openPos else closedPos
	local size = if open then openSize else closedSize
	if instant then
		child.Position = pos
		child.Size = size
	else
		TweenService:Create(child, TOGGLE_TWEEN, { Position = pos, Size = size }):Play()
	end
end

-- Un DETAIL (texte visible SEULEMENT quand la notif est ouverte) : on pose sa position / taille et on le rend VISIBLE
-- quand ouvert, cache quand ferme. Visible plutot que taille 0 : ces textes sont Visible=false par defaut dans Studio.
local function showDetail(frame: GuiObject, name: string, open: boolean, pos: UDim2, size: UDim2)
	local child = frame:FindFirstChild(name)
	if child and child:IsA("GuiObject") then
		child.Position = pos
		child.Size = size
		child.Visible = open
	end
end

-- Fait DEFILER le montant d'un TextLabel de +0 a `amount` (compteur de gain). Se nettoie tout seul a la fin. Si le
-- label disparait entre-temps (notif retiree), on n'ecrit plus dedans (garde sur .Parent).
local function countUp(label: TextLabel, amount: number)
	local proxy = Instance.new("NumberValue")
	proxy.Changed:Connect(function(v)
		if label.Parent then
			-- Format abrege (K / M / B...) pour les grosses sommes : 1454000 -> "+1.45M". Reutilise FormatUtils.
			label.Text = "+" .. FormatUtils.Abbreviate(v)
		end
	end)
	local tween = TweenService:Create(proxy, COUNT_TWEEN, { Value = amount })
	tween.Completed:Connect(function()
		if label.Parent then
			label.Text = "+" .. FormatUtils.Abbreviate(amount) -- valeur finale exacte, abregee
		end
		proxy:Destroy() -- coupe aussi sa connexion Changed
	end)
	tween:Play()
end

-- Aspect ouvert / ferme d'une notif : la FRAME (taille + arrondi + contour), puis l'ICONE et le TEXTE (position + taille).
local function apply(frame: GuiObject, open: boolean, instant: boolean)
	local corner = frame:FindFirstChildOfClass("UICorner") :: UICorner?
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	local size = if open then OPEN_SIZE else CLOSED_SIZE
	local radius = if open then OPEN_CORNER else CLOSED_CORNER
	local thickness = if open then OPEN_THICKNESS else CLOSED_THICKNESS
	if instant then
		frame.Size = size
		if corner then
			corner.CornerRadius = radius
		end
		if stroke then
			stroke.Thickness = thickness
		end
	else
		TweenService:Create(frame, TOGGLE_TWEEN, { Size = size }):Play()
		if corner then
			TweenService:Create(corner, TOGGLE_TWEEN, { CornerRadius = radius }):Play()
		end
		if stroke then
			TweenService:Create(stroke, TOGGLE_TWEEN, { Thickness = thickness }):Play()
		end
	end

	moveChild(frame, "Image", open, instant, IMAGE_OPEN_POS, IMAGE_OPEN_SIZE, IMAGE_CLOSED_POS, IMAGE_CLOSED_SIZE)
	moveChild(frame, "NameNotificationType", open, instant, NAME_OPEN_POS, NAME_OPEN_SIZE, NAME_CLOSED_POS, NAME_CLOSED_SIZE)
	-- Details : VISIBLE seulement quand la notif est ouverte (ils sont Visible=false par defaut dans Studio).
	showDetail(frame, "DescriptionText", open, DESC_POS, DESC_SIZE)
	-- Gains : si une icone de monnaie existe (recompense), le texte se DECALE a gauche et l'icone s'affiche a droite.
	local coinIcon = frame:FindFirstChild("IconCurrency")
	showDetail(frame, "AdditionalEarnText", open, if coinIcon then ADD_ICON_POS else ADD_POS, if coinIcon then ADD_ICON_SIZE else ADD_SIZE)
	if coinIcon and coinIcon:IsA("GuiObject") then
		coinIcon.Visible = open
	end
	local warnIcon = frame:FindFirstChild("IconWarning")
	if warnIcon and warnIcon:IsA("GuiObject") then
		warnIcon.Visible = open
	end

	-- Compte a rebours : toujours visible, il se DEPLACE et change de COULEUR selon l'etat (blanc ouvert, gris ferme).
	moveChild(frame, "CooldownClearNotification", open, instant, COOLDOWN_OPEN_POS, COOLDOWN_OPEN_SIZE, COOLDOWN_CLOSED_POS, COOLDOWN_CLOSED_SIZE)
	local cooldown = frame:FindFirstChild("CooldownClearNotification")
	if cooldown and cooldown:IsA("TextLabel") then
		local col = if open then COOLDOWN_OPEN_COLOR else COOLDOWN_CLOSED_COLOR
		if instant then
			cooldown.TextColor3 = col
		else
			TweenService:Create(cooldown, TOGGLE_TWEEN, { TextColor3 = col }):Play()
		end
	end

	-- A l'OUVERTURE (clic, pas l'etat initial instantane), le montant en monnaie DEFILE de +0 a sa valeur.
	if open and not instant then
		local amount = frame:GetAttribute("EarnAmount")
		local earnLabel = frame:FindFirstChild("AdditionalEarnText")
		if typeof(amount) == "number" and earnLabel and earnLabel:IsA("TextLabel") then
			countUp(earnLabel, amount)
		end
	end
end

-- Retire une notif : sa hauteur se replie a 0 (par le bas, AnchorPoint 0.5,1), puis elle disparait. La liste se
-- compacte pendant, donc les autres descendent doucement pour combler.
local function collapse(frame: GuiObject)
	local tween = TweenService:Create(frame, COLLAPSE_TWEEN, { Size = GONE_SIZE })
	tween:Play()
	tween.Completed:Connect(function()
		frame:Destroy()
	end)
end

-- ===== COMPTE A REBOURS + FERMETURE AUTO =====
-- Texte du rebours : un dixieme, sans zero devant ("6.4s", "0.3s").
local function formatCooldown(remaining: number): string
	return string.format("%.1fs", remaining)
end

-- Retire une notif de la pile PROPREMENT. Idempotent (une notif peut etre visee A LA FOIS par son minuteur et par le
-- plafond MAX_VISIBLE) : le drapeau Dismissed evite de la replier deux fois. `collapse` ne fait que le visuel.
local function dismiss(frame: GuiObject)
	if frame:GetAttribute("Dismissed") then
		return
	end
	frame:SetAttribute("Dismissed", true)
	local index = table.find(notifications, frame)
	if index then
		table.remove(notifications, index)
	end
	collapse(frame)
end

-- Chaque frame : rafraichit le texte du rebours de chaque notif, et replie celles arrivees a zero. Parcours a L'ENVERS
-- car dismiss retire de `notifications` en cours de route.
local function tickCountdowns()
	local now = os.clock()
	for i = #notifications, 1, -1 do
		local frame = notifications[i]
		local closeAt = frame:GetAttribute("CloseAt")
		if typeof(closeAt) == "number" then
			local remaining = math.max(0, closeAt - now)
			local label = frame:FindFirstChild("CooldownClearNotification")
			if label and label:IsA("TextLabel") then
				label.Text = formatCooldown(remaining)
			end
			if remaining <= 0 then
				dismiss(frame)
			end
		end
	end
end

-- Cable une notif : clic (ouvre / ferme) + survol (grossit un poil + un tour du degrade du contour).
local function wireNotification(frame: GuiObject)
	-- Icone : sa contrainte d'aspect doit RESPECTER notre Size (FitWithinMaxSize), sinon en ScaleWithParentSize elle la
	-- derive du parent et le resize (0.4 ferme <-> 0.1 ouvert) ne se verrait pas. Une fois par notif suffit.
	local imageChild = frame:FindFirstChild("Image")
	if imageChild then
		local aspect = imageChild:FindFirstChildOfClass("UIAspectRatioConstraint")
		if aspect then
			aspect.AspectType = Enum.AspectType.FitWithinMaxSize
		end
	end

	local button = frame:FindFirstChild("SelectButton")
	local spinChild = frame:FindFirstChild("UIGradientRotate", true)
	local spin = if spinChild and spinChild:IsA("UIGradient") then spinChild else nil
	if not (button and button:IsA("GuiButton")) then
		warn(`[SideNotification] SelectButton (GuiButton) introuvable sur {frame.Name}`)
		return
	end

	local open = false
	button.Activated:Connect(function()
		open = not open
		apply(frame, open, false)
	end)

	-- Survol sur un UIScale dedie (independant de la Size). AnchorPoint (0.5, 1) -> grossit vers le haut.
	local scale = frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = frame
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, HOVER_TWEEN, { Scale = HOVER_SCALE }):Play()
		if spin then
			spin.Rotation = 0 -- repart de 0 a chaque survol (360 = 0, aucun saut)
			TweenService:Create(spin, SPIN_TWEEN, { Rotation = 360 }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, HOVER_TWEEN, { Scale = 1 }):Play()
	end)
end

-- Teinte une notif selon son TYPE : SEUL le degrade de fond (UIGradientNotificationColor) va de la couleur vers une
-- version assombrie (volume). Le contour (UIStroke) n'est PAS touche. Type inconnu / nil = on ne touche a rien.
local function applyColor(frame: GuiObject, kind: string?)
	local color = if typeof(kind) == "string" then NOTIF_COLORS[kind] else nil
	if not color then
		return
	end
	local gradient = frame:FindFirstChild("UIGradientNotificationColor")
	if gradient and gradient:IsA("UIGradient") then
		local dark = Color3.new(color.R * 0.55, color.G * 0.55, color.B * 0.55)
		gradient.Color = ColorSequence.new(color, dark)
	end
end

-- Pose le texte d'un TextLabel enfant (titre, description...). Texte nil = on ne touche pas (garde le placeholder Studio).
local function setText(frame: GuiObject, name: string, text: string?)
	if not text then
		return
	end
	local child = frame:FindFirstChild(name)
	if child and child:IsA("TextLabel") then
		child.Text = text
	end
end

-- Cree (ou reutilise) une icone nommee sur la notif (monnaie, warning...). Carree, cachee au depart (apply la rend
-- visible a l'ouverture). Si le template contient deja une icone de ce nom, on la reutilise ; sinon on la genere.
local function addIcon(frame: GuiObject, name: string, imageId: string, pos: UDim2, size: UDim2)
	local existing = frame:FindFirstChild(name)
	local icon: ImageLabel
	if existing and existing:IsA("ImageLabel") then
		icon = existing
	else
		icon = Instance.new("ImageLabel")
		icon.Name = name
		icon.BackgroundTransparency = 1
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = 1 -- carree
		ratio.Parent = icon
		icon.Parent = frame
	end
	icon.Image = imageId
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = pos
	icon.Size = size
	icon.ZIndex = 2
	icon.Visible = false -- detail : apply() la rend visible a l'ouverture
end

-- Fait APPARAITRE une notif : clone le template, le TEINTE + remplit ses TEXTES selon `data`, la met EN BAS de la pile
-- et la fait grandir (les autres remontent). Au-dela de MAX_VISIBLE, la plus vieille se replie a 0. Point d'entree du
-- vrai systeme (un evenement appellera spawn(data)).
function SideNotificationHandler.spawn(data: NotifData?): GuiObject?
	local tmpl, list = template, holderList
	if not (tmpl and list) then
		return nil
	end
	local d: NotifData = data or {}
	local clone = tmpl:Clone() :: GuiObject
	applyColor(clone, d.kind)
	setText(clone, "NameNotificationType", d.title)
	setText(clone, "DescriptionText", d.description)
	setText(clone, "AdditionalEarnText", d.earn or "") -- "" si rien de gagne (info / avertissement)
	if d.amount then
		-- Montant en monnaie : on stocke la valeur (l'ouverture la fera DEFILER) et on part de +0.
		clone:SetAttribute("EarnAmount", d.amount)
		setText(clone, "AdditionalEarnText", "+0")
	end
	if d.icon then
		addIcon(clone, "IconCurrency", d.icon, EARN_ICON_POS, EARN_ICON_SIZE)
	else
		-- Pas de gain en monnaie : pas d'icone (au cas ou le template en contienne une, on la retire).
		local stale = clone:FindFirstChild("IconCurrency")
		if stale then
			stale:Destroy()
		end
	end
	-- Icone de TYPE selon le kind (warning...). Meme principe que l'icone de monnaie.
	if d.kind == "Warning" then
		addIcon(clone, "IconWarning", WARNING_ICON, WARN_ICON_POS, WARN_ICON_SIZE)
	end
	spawnOrder += 1
	clone.LayoutOrder = spawnOrder -- croissant -> la plus recente en bas
	clone.Visible = true
	clone.Parent = list
	SoundUtils.play(NOTIF_SOUND) -- petit son a l'apparition

	wireNotification(clone)
	-- Aspect ferme (arrondi, contour, icone, texte) pose INSTANTANEMENT, puis l'ENTREE : on repart d'une largeur 0 et
	-- on deplie en largeur avec ENTER_TWEEN (plus lent que l'ouverture). Le UIListLayout gere la position.
	apply(clone, false, true)
	clone.Size = ENTER_SIZE
	TweenService:Create(clone, ENTER_TWEEN, { Size = CLOSED_SIZE }):Play()

	-- Fermeture auto : echeance posee maintenant, et on affiche le temps plein tout de suite (evite un flash du
	-- placeholder du design). Le tick (Heartbeat) fait descendre le texte puis replie la notif a zero.
	local lifetime = d.duration or LIFETIME
	clone:SetAttribute("CloseAt", os.clock() + lifetime)
	local cooldownLabel = clone:FindFirstChild("CooldownClearNotification")
	if cooldownLabel and cooldownLabel:IsA("TextLabel") then
		cooldownLabel.Text = formatCooldown(lifetime)
	end

	table.insert(notifications, clone)

	while #notifications > MAX_VISIBLE do
		dismiss(notifications[1]) -- la plus vieille (en haut) se replie a 0
	end
	return clone
end

-- Couleur de la palette a un "avancement" continu (phase) : lerp entre deux couleurs voisines, en boucle.
local function paletteAt(phase: number): Color3
	local n = #RAINBOW
	local x = phase % n
	local i = math.floor(x)
	return RAINBOW[i + 1]:Lerp(RAINBOW[(i + 1) % n + 1], x - i)
end

-- Anime le degrade "+points de competence" de chaque notif : deux couleurs de la palette, decalees, qui defilent.
-- Une seule boucle globale (Heartbeat) pour toutes les notifs ; no-op tant qu'il n'y en a aucune.
local function animateRainbow()
	local t = os.clock() * RAINBOW_SPEED
	local seq = ColorSequence.new(paletteAt(t), paletteAt(t + 0.5))
	for _, frame in ipairs(notifications) do
		local text = frame:FindFirstChild("AdditionalEarnText")
		local gradient = text and text:FindFirstChild("UIGradientColor")
		if gradient and gradient:IsA("UIGradient") then
			gradient.Color = seq
		end
	end
end

function SideNotificationHandler.init()
	-- Une seule boucle globale (Heartbeat), no-op tant qu'aucune notif n'existe : le degrade arc-en-ciel des gains ET le
	-- compte a rebours de fermeture auto.
	RunService.Heartbeat:Connect(function()
		animateRainbow()
		tickCountdowns()
	end)

	-- Les ScreenGui de StarterGui sont copiees dans PlayerGui au SPAWN du perso (qui peut tarder : chargement des
	-- donnees...). On attend le perso AVANT de chercher l'UI, en tache de fond (pas de blocage du boot).
	task.spawn(function()
		local player = Players.LocalPlayer
		if not player.Character then
			player.CharacterAdded:Wait()
		end
		local playerGui = player:WaitForChild("PlayerGui")
		local ui = playerGui:WaitForChild("NotificationUI", 10)
		if not ui then
			warn("[SideNotification] NotificationUI introuvable")
			return
		end
		-- Coords PLEIN ECRAN : l'inset de la barre Roblox est ignore, l'origine devient le coin ABSOLU de l'ecran.
		-- Le placement de la pile s'exprime alors sur tout l'ecran, coherent entre appareils.
		if ui:IsA("ScreenGui") then
			ui.ScreenInsets = Enum.ScreenInsets.None
		end
		local templates = ui:FindFirstChild("Templates")
		local tmpl = templates and templates:FindFirstChild("TemplateNotificationSide")
		holderList = ui:FindFirstChild("HolderList", true)
		if not (tmpl and tmpl:IsA("GuiObject")) then
			warn("[SideNotification] Templates.TemplateNotificationSide introuvable")
			return
		end
		if not holderList then
			warn("[SideNotification] HolderList introuvable")
			return
		end
		template = tmpl
		tmpl.Visible = false -- blueprint : on n'affiche que les clones

		-- La pile grandit vers le HAUT (nouvelles en bas). Le padding du UIListLayout n'est pas touche.
		local layout = holderList:FindFirstChildOfClass("UIListLayout")
		if layout then
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		end

		-- MOBILE : on grossit la pile (trop petite au doigt). UIScale sur HolderList ; son AnchorPoint 1,0.5 la garde
		-- collee au bord droit en grandissant. TouchEnabled sans clavier = telephone / tablette.
		if UserInputService.TouchEnabled then -- TouchEnabled SEUL : dans l'emulateur Studio KeyboardEnabled reste true (clavier PC) et bloquait le mobile
			-- TELEPHONE (petit ecran) vs TABLETTE : le tel a besoin de plus gros et plus haut. On regarde le cote COURT
			-- du viewport (independant de l'orientation).
			local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
			local isPhone = vp ~= nil and math.min(vp.X, vp.Y) < PHONE_MAX_SHORT_SIDE
			local uiScale = holderList:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			uiScale.Scale = if isPhone then PHONE_SCALE else TABLET_SCALE
			uiScale.Parent = holderList
			-- On REPOSITIONNE la pile (elle passait sous le bouton de saut, coin bas-droit).
			if holderList:IsA("GuiObject") then
				holderList.Position = if isPhone then PHONE_POSITION else TABLET_POSITION
			end
		end

		-- Notifications REELLES : le serveur envoie la data (level up, paiement d'un chantier...) via SideNotify, on la
		-- spawn. Aucune autorite : on affiche ce que le serveur demande. Pour tester a la main : appeler
		-- SideNotificationHandler.spawn({ ... }) depuis la barre de commandes.
		local remote = RemoteSetup.getRemote("SideNotify", "UI")
		if remote and remote:IsA("RemoteEvent") then
			remote.OnClientEvent:Connect(function(data)
				if typeof(data) == "table" then
					SideNotificationHandler.spawn(data)
				end
			end)
		else
			warn("[SideNotification] Remote UI/SideNotify introuvable : les notifs serveur n'arriveront pas")
		end
	end)
end

return SideNotificationHandler
