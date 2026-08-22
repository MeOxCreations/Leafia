--!strict
-- Curseur custom. On CACHE le curseur systeme et on suit la souris avec une ImageLabel. Pourquoi pas Mouse.Icon :
-- celui-ci affiche l'image a sa taille NATIVE, impossible de la regler. Ici on choisit la TAILLE et on l'ADAPTE a
-- l'ecran (taille en fraction du viewport, donc proportionnelle quelle que soit la resolution).
--
-- Exception assumee a "les ScreenGui se font dans Studio" : un curseur est de la plomberie d'input, pas de l'UI de
-- feature, et il se suffit a lui-meme en code. Un seul ecrivain de MouseIconEnabled et du curseur : ce module.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputDevice = require(ReplicatedStorage.Modules.Utils.InputDevice)

local player = Players.LocalPlayer

-- Zone des boutons Roblox EN HAUT A GAUCHE (logo, menu, chat, micro). Le curseur custom vit dans le PlayerGui, qui
-- est SOUS le CoreGui : sur ces boutons il passerait derriere. On repasse donc au curseur SYSTEME dans cette zone
-- (lui s'affiche par-dessus tout). Hauteur = la barre du haut (GetGuiInset). Largeur = fixe (les boutons ont une
-- taille en pixels, pas proportionnelle) ; a elargir si Roblox ajoute des boutons.
local TOP_LEFT_WIDTH = 199

local CURSOR_IMAGE = "rbxassetid://138708177636922"
-- Taille du curseur = cette fraction de la HAUTEUR du viewport. Petit et proportionnel a l'ecran. A regler a l'oeil.
local CURSOR_SCALE = 0.020
-- Point d'accroche = l'endroit de l'image qui "clique". (0,0) = coin haut-gauche (fleche classique).
-- Mettre 0.5,0.5 pour un point / une croix centree (recommande pour l'effet slime, il pulse alors autour du centre).
local CURSOR_ANCHOR = Vector2.new(0, 0)

-- SLIME AU CLIC : a chaque clic, le curseur se COMPRIME puis REBONDIT elastiquement (depassement) avant de se
-- stabiliser. C'est un ressort amorti SOUS-amorti : il oscille autour de la taille normale et retombe. "Reduit puis
-- ragrandit" avec du rebond = effet slime. Amortissement BAS = il rebondit longtemps, donc prolonge et satisfaisant.
-- x2 en vitesse = x4 raideur (frequence ~ racine de la raideur) et x2 amortissement (pour garder le meme rebond).
local SLIME_STIFFNESS = 1840 -- raideur du ressort (haut = rebond plus rapide, plus sec)
local SLIME_DAMPING = 24 -- amortissement (BAS = rebondit plus longtemps ; haut = plus rapide a se stabiliser)
-- Taille du curseur TANT QU'ON MAINTIENT le clic (ecart de taille, negatif = plus petit). Le ressort la vise pendant
-- l'appui ; au relachement, la cible repasse a 0 et il rebondit jusqu'a la taille normale. Un clic bref = un aller-
-- retour rapide ; un clic maintenu = curseur garde petit, puis rebond a la fin.
local SLIME_PRESSED = -0.09

-- HOVER SUR UN BOUTON : retour "vivant" et PROLONGE (dure tout le survol), distinct du choc bref au clic. Le
-- curseur GONFLE et RESPIRE doucement tant qu'il survole un bouton, puis repart a sa taille quand on le quitte.
local SLIME_HOVER = 0.14 -- gonflement en survol (ecart de taille ; positif = plus gros)
local SLIME_HOVER_PULSE = 0.03 -- amplitude de la respiration pendant le survol (0 = juste le gonflement, sans pulse)
local SLIME_HOVER_PULSE_SPEED = 4.5 -- vitesse de la respiration en rad/s (lent = elegant)

local CursorController = {}

-- CURSEUR SUPPRIME DE L'EXTERIEUR. En vue subjective la souris est verrouillee au centre : un curseur n'a plus de
-- sens, et c'est le point de visee qui prend sa place.
--
-- Un DRAPEAU lu par la boucle, et pas une ecriture faite ailleurs : ce module est le seul ecrivain du curseur et
-- de MouseIconEnabled (c'est ecrit en tete du fichier). Un autre controller qui ecrirait par-dessus se ferait
-- effacer a l'image suivante par cette boucle -- ou l'effacerait, selon lequel passe en dernier.
local suppressed = false

function CursorController.init()
	-- On coupe le curseur systeme : le notre le remplace entierement.
	UserInputService.MouseIconEnabled = false

	local gui = Instance.new("ScreenGui")
	gui.Name = "CursorGui"
	-- GetMouseLocation() donne des coords ecran BRUTES (avec la barre du haut). Sans IgnoreGuiInset, le curseur
	-- serait decale vers le bas de l'inset. Cf journal CLAUDE.md sur l'inset de la barre Roblox.
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000 -- au-dessus du reste de l'UI
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	gui.Parent = playerGui

	local cursor = Instance.new("ImageLabel")
	cursor.Name = "Cursor"
	cursor.Image = CURSOR_IMAGE
	cursor.BackgroundTransparency = 1
	cursor.AnchorPoint = CURSOR_ANCHOR
	-- Fit : garde le ratio de l'image dans le carre de taille, sans la deformer.
	cursor.ScaleType = Enum.ScaleType.Fit
	-- ZIndex haut : le curseur reste TOUJOURS au-dessus du choc au clic (cree apres, donc au-dessus sinon).
	cursor.ZIndex = 10
	cursor.Parent = gui

	-- Etat du ressort slime : slimePos = ecart de taille (0 = normal), slimeVel = sa vitesse. La CIBLE du ressort est
	-- 0 au repos, ou SLIME_PRESSED tant qu'on maintient le clic (held) : maintenu = curseur garde petit, relache =
	-- rebond a 0. Au repos, pos et vel restent a 0.
	local slimePos = 0
	local slimeVel = 0
	local held = false
	-- Survol : phase de la respiration, et etat precedent (pour ne declencher son + pulse qu'a l'ENTREE sur un bouton).
	local hoverPhase = 0
	local wasHovering = false
	-- Curseur systeme affiche a la place du notre (sur les boutons Roblox du haut-gauche). Retenu pour ne basculer
	-- MouseIconEnabled qu'aux CHANGEMENTS, pas chaque frame.
	local systemShown = false
	RunService.RenderStepped:Connect(function(dt: number)
		if suppressed then
			cursor.Visible = false
			-- On coupe AUSSI le curseur systeme : sur les boutons Roblox du haut-gauche il reprendrait la main,
			-- et on verrait une fleche reapparaitre en vue subjective.
			if systemShown then
				systemShown = false
				UserInputService.MouseIconEnabled = false
			end
			return
		end
		local m = UserInputService:GetMouseLocation()

		-- BOUTONS ROBLOX (haut-gauche) : on y montre le curseur SYSTEME (il passe par-dessus le CoreGui), et on cache
		-- le notre. Hauteur = la barre du haut (GetGuiInset) ; largeur = TOP_LEFT_WIDTH.
		local topInset = GuiService:GetGuiInset()
		local overCore = m.Y <= topInset.Y and m.X <= TOP_LEFT_WIDTH
		if overCore ~= systemShown then
			systemShown = overCore
			UserInputService.MouseIconEnabled = overCore
		end
		-- Sur TACTILE : pas de souris -> on cache notre curseur, et rien a positionner. Sinon : cache seulement sur
		-- les boutons Roblox (le curseur systeme y prend le relais). Suit InputDevice, donc bascule si le joueur change.
		local touch = InputDevice.isTouch()
		cursor.Visible = not (touch or overCore)
		if touch then
			return
		end

		-- SURVOL D'UN BOUTON, detecte UNE fois par frame (pas par event de souris : agiter la souris ne doit pas
		-- flooder le hit-test). GetGuiObjectsAtPosition rend tous les GuiObject sous le point ; l'ImageLabel du
		-- curseur n'est pas un GuiButton, il ne se compte donc pas. m.X/m.Y = coords absolues, comme AbsolutePosition
		-- des boutons (l'inset est deja dedans des deux cotes), donc ca marche quel que soit l'IgnoreGuiInset du GUI.
		local hovering = false
		for _, obj in ipairs(playerGui:GetGuiObjectsAtPosition(m.X, m.Y)) do
			if obj:IsA("GuiButton") and obj.Visible then
				hovering = true
				break
			end
		end
		-- Entree sur un bouton : la respiration repart proprement (sin(0) = 0). Le SON du survol, lui, est joue par
		-- ButtonSlime a l'entree de CHAQUE bouton (MouseEnter), pas ici : sinon survoler des boutons COLLES ne sonnait
		-- qu'une fois (on ne repassait jamais par un "aucun bouton" entre eux).
		if hovering and not wasHovering then
			hoverPhase = 0
		end
		wasHovering = hovering

		-- Ressort amorti vers la cible : F = -k*(x - cible) - c*v, integre en Euler. step borne (anti-explosion au lag).
		local step = math.min(dt, 1 / 30)
		hoverPhase += step * SLIME_HOVER_PULSE_SPEED
		-- Cible = gonflement du survol (+ respiration lente = slime PROLONGE) AJOUTE au creux du clic. Les deux se
		-- composent : survoler GONFLE, cliquer ENFONCE, relacher rend le gonflement.
		local hoverGoal = if hovering then SLIME_HOVER + math.sin(hoverPhase) * SLIME_HOVER_PULSE else 0
		local target = hoverGoal + (if held then SLIME_PRESSED else 0)
		local force = -SLIME_STIFFNESS * (slimePos - target) - SLIME_DAMPING * slimeVel
		slimeVel += force * step
		slimePos += slimeVel * step

		cursor.Position = UDim2.fromOffset(m.X, m.Y)
		local camera = workspace.CurrentCamera
		local base = if camera then camera.ViewportSize.Y * CURSOR_SCALE else 24
		local scale = 1 + slimePos
		cursor.Size = UDim2.fromOffset(base * scale, base * scale)
	end)

	-- On NE filtre PAS gameProcessed : l'effet est un retour du CURSEUR, il doit se jouer sur TOUS les clics, y compris
	-- sur les boutons d'UI (ImageButton / TextButton). C'est justement la que le feedback est le plus satisfaisant.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			-- On MAINTIENT : la cible du ressort passe a SLIME_PRESSED, le curseur se comprime et y reste tant qu'on
			-- tient. Le relachement (InputEnded) remet la cible a 0 -> rebond.
			held = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			held = false
		end
	end)

	print("[Cursor] Curseur custom actif")
end

--- Cache (ou rend) le curseur custom ET le curseur systeme. Appele par la vue subjective, qui verrouille la souris
--- au centre. Passer par ici plutot que d'ecrire MouseIconEnabled soi-meme : ce module en est le seul ecrivain.
function CursorController.setSuppressed(on: boolean)
	suppressed = on
end

return CursorController
