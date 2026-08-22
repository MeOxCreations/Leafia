--!strict
-- VIGNETTAGE : les bords de l'ecran s'assombrissent, le centre reste clair.
--
-- POURQUOI. L'oeil va spontanement vers la zone la plus lumineuse. Assombrir la peripherie ramene donc le regard
-- au milieu -- la ou se trouve le joueur -- sans rien lui demander et sans rien ecrire a l'ecran. C'est le moyen
-- le moins cher de dire "regarde ici".
--
-- EXCEPTION ASSUMEE a "les ScreenGui se font dans Studio" : c'est une image posee plein cadre, sans rien a regler
-- a la main, et la poser dans Studio obligerait a la recopier dans CHAQUE lieu (Rojo ne synchronise pas
-- StarterGui). Meme raison que le curseur et l'ecran de chargement.
--
-- ETIREE, ET C'EST VOULU. Le vignettage doit toucher les QUATRE bords quel que soit l'ecran : c'est sa seule
-- obligation. Garder ses proportions laisserait des bandes claires sur les cotes en 21/9 -- exactement ce qu'il
-- est cense supprimer. La deformation d'un degrade doux ne se voit pas ; un bord manquant, si.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Vignette = {}

local player = Players.LocalPlayer

-- ===== Reglages =====
local IMAGE = "rbxassetid://74658820247403"
-- Teinte du voile. Noir pur = assombrit franchement. Une teinte legerement coloree (bleu nuit, brun) donne une
-- ambiance, mais decale les couleurs du jeu sur les bords : a n'essayer qu'a l'oeil.
local TINT = Color3.fromRGB(0, 0, 0)
-- Transparence au repos. C'EST LE BOUTON PRINCIPAL : plus BAS = bords plus sombres.
-- Un vignettage se sent, il ne se voit pas. Des qu'on peut le montrer du doigt, il est trop fort.
local BASE_TRANSPARENCY = 0.45
-- Duree d'un changement d'intensite. Un vignettage qui change d'un coup se lit comme un bug d'affichage.
local FADE_TIME = 0.6

-- SOUS l'interface de jeu, AU-DESSUS du monde. Un DisplayOrder negatif garantit qu'aucun bouton, aucun texte et
-- aucune notification ne passe sous le voile : assombrir sa propre interface n'aurait aucun sens.
local DISPLAY_ORDER = -10

local image: ImageLabel? = nil
-- ETEINT PAR DEFAUT. Un vignettage permanent finit par ne plus rien dire : l'oeil s'y habitue en une minute, et
-- il ne reste qu'une image plus sombre. Il ne vaut que s'il ARRIVE -- c'est le changement qui resserre
-- l'attention, pas la valeur. On l'allume donc pour un MOMENT precis (le demarrage de la tondeuse) et on
-- l'eteint apres.
local strength = 0
local tween: Tween? = nil

local function transparencyFor(amount: number): number
	-- On interpole entre INVISIBLE (1) et la transparence de repos. A amount = 0 le voile disparait vraiment,
	-- au lieu de laisser un residu qu'on ne saurait pas expliquer.
	return 1 - (1 - BASE_TRANSPARENCY) * math.clamp(amount, 0, 1)
end

local building = false

local function build()
	local playerGui = player:WaitForChild("PlayerGui", 20)
	if not (playerGui and playerGui:IsA("PlayerGui")) then
		building = false
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "VignetteGui"
	-- AUCUN INSET : le voile doit couvrir l'ecran ENTIER, barre Roblox comprise. Avec l'inset par defaut, une
	-- bande claire de la hauteur de la barre resterait en haut.
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.IgnoreGuiInset = true
	-- Sinon il est recree a chaque mort et la reference gardee ici pointe sur du detruit.
	screen.ResetOnSpawn = false
	screen.DisplayOrder = DISPLAY_ORDER
	screen.Parent = playerGui

	local label = Instance.new("ImageLabel")
	label.Name = "Vignette"
	label.BackgroundTransparency = 1
	label.Image = IMAGE
	label.ImageColor3 = TINT
	label.ImageTransparency = transparencyFor(strength)
	label.ScaleType = Enum.ScaleType.Stretch
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	-- NE MANGE AUCUN CLIC. Un voile plein cadre qui absorbe l'input rendrait tout le jeu incliquable, et on
	-- chercherait le probleme dans les boutons.
	label.Active = false
	label.Parent = screen

	image = label
	building = false
end

--- Cree le voile s'il n'existe pas encore. Idempotent, et NE BLOQUE JAMAIS : l'attente de PlayerGui se fait en
--- tache de fond. Un `WaitForChild` en ligne droite dans un init de boot gele toute la sequence le temps du
--- timeout -- piege deja paye ailleurs dans ce projet.
function Vignette.init()
	if image or building then
		return
	end
	building = true
	task.spawn(build)
end

--- Intensite du voile, de 0 (eteint) a 1 (pleine force). Le changement est FONDU : un vignettage qui bascule d'un
--- coup se lit comme un bug d'affichage. Sert aux moments ou l'on veut resserrer l'attention (une scene scriptee,
--- un demarrage de moteur) sans avoir a connaitre la valeur de repos.
function Vignette.setStrength(amount: number)
	strength = math.clamp(amount, 0, 1)
	local label = image
	if not label then
		return
	end
	-- On COUPE le fondu en cours avant d'en lancer un autre : deux tweens sur la meme propriete se disputent
	-- l'image a chaque frame, et la valeur finale devient celle du dernier a finir, pas du dernier demande.
	if tween then
		tween:Cancel()
	end
	local next_ = TweenService:Create(
		label,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ ImageTransparency = transparencyFor(strength) }
	)
	tween = next_
	next_:Play()
end

return Vignette
