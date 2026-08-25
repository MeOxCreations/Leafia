--!strict
-- BARRES NOIRES DE CINEMA. Deux bandes qui glissent depuis le haut et le bas de l'ecran.
--
-- POURQUOI. Elles ne servent pas a decorer : elles DISENT au joueur que la main lui est retiree. Tant qu'elles
-- sont la, il regarde ; quand elles partent, il rejoue. C'est la convention la plus lisible qui existe, et elle
-- ne demande aucune traduction.
--
-- PRIMITIVE REUTILISABLE : elle ne connait ni le grand-pere, ni la porte, ni aucune scene. On l'allume, on
-- l'eteint. Toute scene scriptee passera par ici, sinon la meme paire de Frames serait recopiee a chaque fois.
--
-- EXCEPTION ASSUMEE a "les ScreenGui se font dans Studio" : deux rectangles noirs sans rien a regler a l'oeil, et
-- les poser dans Studio obligerait a les recopier dans CHAQUE place (Rojo ne synchronise pas StarterGui). Meme
-- raison que le vignettage, le curseur et l'ecran de chargement.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Letterbox = {}

local player = Players.LocalPlayer

-- ===== Reglages =====
-- Hauteur d'UNE bande, en fraction de la hauteur d'ecran. En fraction et pas en pixels : sur un telephone une
-- valeur en pixels mangerait la moitie de l'ecran, sur un grand ecran elle ne se verrait pas.
local BAR_HEIGHT = 0.11
-- Duree par defaut du glissement. Assez lent pour se lire comme un rideau, assez court pour ne pas faire
-- attendre. Chaque appel peut imposer la sienne.
local SLIDE_TIME = 0.5
-- AU-DESSUS DE TOUT. Une barre de cinema qui passe sous une interface de jeu ne veut plus rien dire : c'est
-- justement l'interface qu'elle est censee remplacer le temps de la scene.
local DISPLAY_ORDER = 100

local gui: ScreenGui? = nil
local top: Frame? = nil
local bottom: Frame? = nil
local tweens: { Tween } = {}
local shown = false

local function bar(name: string, anchorY: number, posY: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, anchorY)
	frame.Position = UDim2.fromScale(0.5, posY)
	-- ON PART A ZERO : la bande GLISSE depuis le bord, elle n'apparait pas d'un coup. Ancree sur ce bord, faire
	-- grandir sa hauteur suffit -- pas besoin d'animer aussi la position, qui se decalerait a coup sur.
	frame.Size = UDim2.fromScale(1, 0)
	-- N'AVALE AUCUN CLIC. Deux bandes qui absorbent l'input rendraient le haut et le bas de l'ecran morts, et on
	-- chercherait le probleme dans les boutons.
	frame.Active = false
	return frame
end

local function build()
	if gui then
		return
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "LetterboxGui"
	-- AUCUN INSET : les bandes doivent toucher les bords ABSOLUS de l'ecran, barre Roblox comprise. Avec l'inset
	-- par defaut, une bande de jeu resterait visible au-dessus de la barre du haut.
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.IgnoreGuiInset = true
	-- Sinon elle est recreee a chaque mort et les references gardees ici pointent sur du detruit.
	screen.ResetOnSpawn = false
	screen.DisplayOrder = DISPLAY_ORDER
	screen.Enabled = false
	screen.Parent = playerGui

	local t = bar("Top", 0, 0)
	t.Parent = screen
	local b = bar("Bottom", 1, 1)
	b.Parent = screen

	gui, top, bottom = screen, t, b
end

-- Coupe les glissements en cours avant d'en lancer d'autres : deux tweens sur la meme propriete se disputent la
-- bande a chaque image, et la valeur finale devient celle du dernier a FINIR, pas du dernier demande.
local function cancelTweens()
	for _, t in ipairs(tweens) do
		t:Cancel()
	end
	table.clear(tweens)
end

local function slide(height: number, seconds: number, onDone: (() -> ())?)
	local t, b = top, bottom
	if not (t and b) then
		if onDone then
			onDone()
		end
		return
	end
	cancelTweens()
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goal = { Size = UDim2.fromScale(1, height) }
	local a = TweenService:Create(t, info, goal)
	local c = TweenService:Create(b, info, goal)
	tweens = { a, c }
	if onDone then
		a.Completed:Connect(function()
			onDone()
		end)
	end
	a:Play()
	c:Play()
end

--- Fait glisser les bandes a l'ecran. `seconds` remplace la duree par defaut ; `onDone` est appele quand elles
--- sont en place -- c'est la que la scene peut commencer, pas avant.
function Letterbox.show(seconds: number?, onDone: (() -> ())?)
	build()
	local screen = gui
	if not screen then
		if onDone then
			onDone()
		end
		return
	end
	screen.Enabled = true
	shown = true
	slide(BAR_HEIGHT, seconds or SLIDE_TIME, onDone)
end

--- Les fait repartir dans les bords. Le ScreenGui n'est eteint qu'A LA FIN : le couper tout de suite ferait
--- disparaitre les bandes d'un coup au lieu de les laisser glisser.
function Letterbox.hide(seconds: number?, onDone: (() -> ())?)
	if not gui then
		if onDone then
			onDone()
		end
		return
	end
	shown = false
	slide(0, seconds or SLIDE_TIME, function()
		-- On revalide : une nouvelle scene a pu rallumer les bandes pendant que celles-ci partaient.
		if not shown and gui then
			(gui :: ScreenGui).Enabled = false
		end
		if onDone then
			onDone()
		end
	end)
end

--- Vrai tant que les bandes sont demandees. Sert a ne pas relancer une scene par-dessus une autre.
function Letterbox.isShown(): boolean
	return shown
end

return Letterbox
