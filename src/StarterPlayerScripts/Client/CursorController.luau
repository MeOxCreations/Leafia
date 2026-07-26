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

local player = Players.LocalPlayer

-- Zone des boutons Roblox EN HAUT A GAUCHE (logo, menu, chat, micro). Le curseur custom vit dans le PlayerGui, qui
-- est SOUS le CoreGui : sur ces boutons il passerait derriere. On repasse donc au curseur SYSTEME dans cette zone
-- (lui s'affiche par-dessus tout). Hauteur = la barre du haut (GetGuiInset). Largeur = fixe (les boutons ont une
-- taille en pixels, pas proportionnelle) ; a elargir si Roblox ajoute des boutons.
local TOP_LEFT_WIDTH = 199

local CURSOR_IMAGE = "rbxassetid://138708177636922"
-- Taille du curseur = cette fraction de la HAUTEUR du viewport. Petit et proportionnel a l'ecran. A regler a l'oeil.
local CURSOR_SCALE = 0.022
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

local CursorController = {}

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
	gui.Parent = player:WaitForChild("PlayerGui")

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
	-- Curseur systeme affiche a la place du notre (sur les boutons Roblox du haut-gauche). Retenu pour ne basculer
	-- MouseIconEnabled qu'aux CHANGEMENTS, pas chaque frame.
	local systemShown = false
	RunService.RenderStepped:Connect(function(dt: number)
		local m = UserInputService:GetMouseLocation()

		-- BOUTONS ROBLOX (haut-gauche) : on y montre le curseur SYSTEME (il passe par-dessus le CoreGui), et on cache
		-- le notre. Hauteur = la barre du haut (GetGuiInset) ; largeur = TOP_LEFT_WIDTH.
		local topInset = GuiService:GetGuiInset()
		local overCore = m.Y <= topInset.Y and m.X <= TOP_LEFT_WIDTH
		if overCore ~= systemShown then
			systemShown = overCore
			cursor.Visible = not overCore
			UserInputService.MouseIconEnabled = overCore
		end

		-- Ressort amorti vers la cible : F = -k*(x - cible) - c*v, integre en Euler. dt borne (anti-explosion au lag).
		local target = if held then SLIME_PRESSED else 0
		local step = math.min(dt, 1 / 30)
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

return CursorController
