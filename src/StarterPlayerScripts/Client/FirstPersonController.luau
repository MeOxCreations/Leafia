--!strict
-- VUE SUBJECTIVE chez le client, avec bascule vers la vue de dos.
--
-- POURQUOI PAS DANS LE HUB. Le hub sert a choisir son plot, construire, lire des interfaces : on y a besoin de
-- voir son personnage et de cliquer partout. Chez un client, on TRAVAILLE, et le travail se regarde de pres.
-- La regle est donc "tout lieu qui n'est PAS le hub", et pas une liste de lieux a tenir a jour : un futur jardin
-- de client demarrera en vue subjective sans qu'on ait rien a ajouter ici.
--
-- ON NE FABRIQUE PAS UNE CAMERA. La camera Custom de Roblox sait deja faire la vue subjective : il suffit de
-- coller ses bornes de zoom a zero. Ecrire nous-memes sa CFrame reviendrait a nous battre contre ses scripts, ce
-- qui saccade des que le joueur bouge la souris (regle en tete de CameraEffects, deja payee ailleurs).
-- Ces bornes n'ont donc qu'UN ecrivain, CameraEffects, a qui on DECLARE l'intention.
--
-- LE CORPS S'EFFACE, LES MAINS RESTENT. En vue subjective Roblox efface tout le personnage -- outil compris, or
-- l'outil est justement ce qu'on veut voir. On repasse donc par-dessus avec CharacterFade, qui garde les mains :
-- nos outils y sont soudes par un Motor6D, ils restent donc visibles avec elles.
--
-- Purement client : c'est un confort de vue, ca ne change aucune regle du jeu.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PlacesConfig = require(ReplicatedStorage.Modules.Configs.PlacesConfig)
local CameraEffects = require(script.Parent.Utils.CameraEffects)
local CursorController = require(script.Parent.CursorController)
local CharacterFade = require(script.Parent.Utils.CharacterFade)

local FirstPersonController = {}

local player = Players.LocalPlayer

-- ===== Reglages =====
local TOGGLE_ACTION = "LeafiaCameraToggle"
-- C : libre dans tout le projet (E, G, R, F, V, X, Q/Z/S/D et les chiffres sont pris).
local TOGGLE_KEY = Enum.KeyCode.C
-- Maintenir pour RENDRE le curseur (cliquer une interface). Voir la note sur le tactile plus bas.
local FREE_CURSOR_KEY = Enum.KeyCode.LeftAlt
local DOT_SIZE = 6 -- diametre du point de visee, en pixels
local DOT_COLOR = Color3.fromRGB(255, 255, 255)
local DOT_TRANSPARENCY = 0.25
-- Contour sombre. Sans lui, un point blanc disparait sur un ciel clair ou une facade blanche -- et un reticule
-- qu'on perd de vue est pire que pas de reticule.
local DOT_OUTLINE = 1
-- ECART pris pendant qu'on tient la touche du curseur. A zero, Roblox verrouille la souris au centre et refuse
-- de la rendre : lui laisser un cheveu d'ecart est la seule facon de recuperer le curseur sans quitter la vue
-- subjective. Assez petit pour que la vue ne bouge presque pas.
-- SI LA SOURIS RESTE COLLEE AU CENTRE, c'est ce nombre qu'il faut monter -- le seuil exact appartient a Roblox.
local FREE_CURSOR_GAP = 1.5
-- Attribut pose par l'ecran de chargement quand son rideau s'en va. Tant qu'il n'est pas la, on ne prend NI la
-- souris NI le curseur : voir la note dans init.
local LOADING_DONE_ATTRIBUTE = "LeafiaLoadingDone"
-- Au-dela, on demarre quand meme. Un garde-fou, pas une duree : si l'ecran de chargement disparaissait un jour
-- sans poser son attribut, la vue subjective ne s'activerait plus JAMAIS et on chercherait longtemps pourquoi.
local LOADING_TIMEOUT = 40
-- Y A-T-IL UNE SOURIS A VERROUILLER ?
--
-- CE TEST N'EST PAS UN DETAIL, il a rendu la tondeuse INJOUABLE sur mobile. La vue subjective forcait
-- `MouseBehavior = LockCenter` a chaque image, y compris sur un telephone -- et verrouiller une souris qui
-- n'existe pas casse les controles TACTILES de Roblox : le joystick ne remontait plus rien du tout. Mesure a
-- l'ecran : vecteur de deplacement a zero alors que le doigt poussait.
--
-- `MouseEnabled` et pas `TouchEnabled` : c'est la question exacte qu'on se pose. Un PC a ecran tactile a les
-- DEUX, et sa souris doit rester verrouillee ; un telephone n'a que le tactile. Tester la presence du tactile
-- aurait donc casse la vue subjective sur les PC tactiles.
local HAS_MOUSE = UserInputService.MouseEnabled
local RENDER_BIND = "LeafiaFirstPerson"

local available = game.PlaceId ~= PlacesConfig.MAIN
local firstPerson = false
local dot: Frame? = nil
local gui: ScreenGui? = nil
local bound = false

-- Le point de visee. CREE EN CODE et non pose dans Studio, contrairement au reste des interfaces : c'est un carre
-- de six pixels qui n'a rien a regler a la main, et le poser dans Studio obligerait a le recopier dans CHAQUE
-- lieu (Rojo ne synchronise pas StarterGui). Meme raison que l'ecran de chargement, qui se construit aussi seul.
local function ensureDot(): Frame?
	if dot then
		return dot
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "FirstPersonDot"
	-- ResetOnSpawn FAUX : sinon l'interface est recreee a chaque mort et les references gardees ici pointent sur
	-- du detruit. Piege deja paye sur d'autres interfaces du projet.
	screen.ResetOnSpawn = false
	-- Aucun inset : le point doit tomber au centre exact de l'ECRAN, pas au centre de la zone sous la barre
	-- Roblox -- sinon il vise 18 pixels trop bas.
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 5
	screen.Enabled = false
	screen.Parent = playerGui

	local point = Instance.new("Frame")
	point.Name = "Dot"
	point.AnchorPoint = Vector2.new(0.5, 0.5)
	point.Position = UDim2.fromScale(0.5, 0.5)
	point.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
	point.BackgroundColor3 = DOT_COLOR
	point.BackgroundTransparency = DOT_TRANSPARENCY
	point.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = DOT_OUTLINE
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Transparency = 0.4
	stroke.Parent = point
	local corner = Instance.new("UICorner") :: UICorner
	corner.CornerRadius = UDim.new(1, 0) -- rond, pas carre
	corner.Parent = point
	point.Parent = screen

	gui = screen
	dot = point
	return point
end

-- Une image de la vue subjective : on efface le corps et on tient le curseur.
--
-- PAR IMAGE et pas une fois a la bascule, pour les deux. Roblox REECRIT la transparence du personnage et le
-- comportement de la souris a chaque image quand la camera est collee a la tete : une valeur posee une seule
-- fois serait effacee a l'image suivante. On passe donc APRES lui (priorite Camera + 1) et on repose la notre.
local function step()
	-- LE CORPS S'EFFACE AU RYTHME DE LA CAMERA, pas d'un coup. Effacer d'un bloc pendant que la vue glisse encore
	-- montrerait un trou a la place du personnage le temps du voyage.
	local amount = CameraEffects.GetFirstPersonAmount()
	local character = player.Character
	if character then
		-- `true` = on REECRIT meme quand rien n'a change chez nous. Roblox repose sa propre transparence a chaque
		-- image en vue subjective : sans ca, nos mains seraient effacees des l'image suivant la derniere ecriture.
		CharacterFade.apply(character, amount, 0, true)
		-- ET ON REMET LES OUTILS VISIBLES PAR-DESSUS ROBLOX, qui les efface avec le reste : il n'epargne que les
		-- parts rangees sous un `Tool`, or les notres sont des `Model`. Sans cette ligne, on tient un taille-haie
		-- invisible.
		CharacterFade.keepToolsVisible(character)
	end
	-- TOUT CE QUI SUIT N'EST POSE QUE TANT QU'ON VEUT LA VUE SUBJECTIVE.
	--
	-- Pendant le glissement de SORTIE la boucle tourne encore -- elle finit de faire reapparaitre le corps -- mais
	-- elle ne doit plus toucher ni a la souris ni au curseur. Sans ce garde-fou elle les REPRENAIT au joueur image
	-- apres image, juste apres que la bascule les lui ait rendus, et la derniere ecriture avant le debranchement
	-- restait en place : souris collee au centre et curseur invisible, en pleine vue de dos.
	if not firstPerson then
		return
	end

	-- CURSEUR RENDU tant que la touche est maintenue. Le reticule s'efface avec, sinon on aurait un point de
	-- visee ET une fleche a l'ecran, et on ne saurait plus lequel des deux compte.
	local free = UserInputService:IsKeyDown(FREE_CURSOR_KEY)
	local screen = gui
	if screen then
		screen.Enabled = not free
	end
	-- LE CURSEUR PASSE PAR CursorController, jamais par MouseIconEnabled en direct : le jeu affiche un curseur
	-- CUSTOM (une ImageLabel qui suit la souris), et couper l'icone systeme ne l'aurait pas efface -- il serait
	-- reste plante au centre de l'ecran par-dessus le point de visee. Ce module est le seul ecrivain des deux.
	-- SANS SOURIS, ON NE TOUCHE A RIEN. Pas de curseur a cacher, pas de souris a verrouiller -- et surtout, y
	-- toucher casse les controles tactiles.
	if not HAS_MOUSE then
		return
	end
	CursorController.setSuppressed(not free)
	-- ON RECULE D'UN CHEVEU pour que Roblox cesse de verrouiller la souris. Ecrire MouseBehavior apres lui ne
	-- suffit PAS : il repose la sienne et gagne (verifie a l'ecran). Tant que la camera est collee a la tete, la
	-- souris lui appartient -- il faut donc ne plus y etre tout a fait.
	CameraEffects.SetFirstPersonGap(if free then FREE_CURSOR_GAP else 0)
	UserInputService.MouseBehavior = if free then Enum.MouseBehavior.Default else Enum.MouseBehavior.LockCenter
end

local function setFirstPerson(on: boolean)
	if on == firstPerson or not available then
		return
	end
	firstPerson = on
	CameraEffects.SetFirstPerson(on)
	if on then
		ensureDot()
		if not bound then
			bound = true
			-- APRES la camera dans la MEME image : Roblox pose son comportement de souris et sa transparence de
			-- personnage a la priorite Camera, et le dernier qui ecrit gagne.
			RunService:BindToRenderStep(RENDER_BIND, Enum.RenderPriority.Camera.Value + 1, step)
		end
		return
	end

	-- ON REND TOUT DE SUITE CE QUI EST BINAIRE : la souris, le curseur, le reticule. Rien a faire glisser la, et
	-- garder la souris verrouillee pendant que la vue recule serait desagreable.
	if HAS_MOUSE then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		CursorController.setSuppressed(false)
		CameraEffects.SetFirstPersonGap(0)
	end
	local screen = gui
	if screen then
		screen.Enabled = false
	end

	-- LE CORPS, LUI, REVIENT AU RYTHME DE LA CAMERA. On garde donc la boucle branchee jusqu'a ce que le
	-- glissement soit VRAIMENT fini, et c'est elle qui debranche et nettoie. Couper ici laisserait un personnage
	-- invisible pendant que la vue recule -- on regarderait un trou s'eloigner.
	if not bound then
		return
	end
	task.spawn(function()
		while CameraEffects.GetFirstPersonAmount() > 0 and not firstPerson do
			RunService.RenderStepped:Wait()
		end
		-- On a pu rebasculer en vue subjective entre-temps : dans ce cas la boucle doit RESTER branchee.
		if firstPerson or not bound then
			return
		end
		bound = false
		RunService:UnbindFromRenderStep(RENDER_BIND)
		local character = player.Character
		if character then
			CharacterFade.clear(character)
		end
	end)
end

function FirstPersonController.init()
	if not available then
		return
	end

	-- BASCULE. Passe par ContextActionService et pas par UserInputService : `createTouchButton = true` cree un
	-- bouton a l'ecran UNIQUEMENT sur tactile ET cable la touche sur PC, d'un seul geste. Une bascule qui
	-- n'existerait qu'au clavier serait inatteignable pour la moitie des joueurs Roblox.
	ContextActionService:BindAction(TOGGLE_ACTION, function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			setFirstPerson(not firstPerson)
		end
		return Enum.ContextActionResult.Pass
	end, true, TOGGLE_KEY)
	ContextActionService:SetTitle(TOGGLE_ACTION, "VIEW")

	-- LE CURSEUR LIBRE N'A PAS DE PENDANT TACTILE, et c'est voulu : sans souris il n'y a rien a liberer, le doigt
	-- touche directement l'interface. C'est la seule exception a la regle "tout input clavier a son bouton".

	-- ON DEMARRE EN VUE SUBJECTIVE chez le client. Apres l'arrivee du personnage : effacer un corps qui n'existe
	-- pas encore ne fait rien, et on se retrouverait en vue subjective avec un personnage plein a l'ecran.
	task.spawn(function()
		local character = player.Character or player.CharacterAdded:Wait()
		-- Le personnage est parente avant d'etre complet : on laisse ses parts arriver avant de les effacer.
		character:WaitForChild("Humanoid", 10)

		-- ON ATTEND QUE LE RIDEAU DE CHARGEMENT SOIT PARTI.
		--
		-- Il tient dix secondes APRES l'arrivee du personnage. Prendre la souris a cet instant verrouillait le
		-- curseur au centre et l'effacait pendant tout ce temps : le joueur se retrouvait devant un ecran qu'il ne
		-- peut de toute facon pas viser, sans pouvoir bouger sa souris -- ca ressemble a un jeu fige, pas a un
		-- chargement.
		--
		-- Sondage plutot qu'une ecoute d'evenement : l'attribut peut deja etre pose quand on arrive ici, et une
		-- ecoute seule attendrait alors un changement qui n'aura jamais lieu.
		local deadline = os.clock() + LOADING_TIMEOUT
		while player:GetAttribute(LOADING_DONE_ATTRIBUTE) ~= true and os.clock() < deadline do
			task.wait(0.2)
		end
		setFirstPerson(true)
	end)

	-- A LA MORT, on relache. Le personnage suivant est neuf : la transparence posee sur l'ancien ne le suit pas,
	-- et rester en vue subjective pendant l'ecran de mort n'a aucun sens.
	player.CharacterAdded:Connect(function(character: Model)
		if not firstPerson then
			return
		end
		character:WaitForChild("Humanoid", 10)
		-- On repasse par la bascule pour que TOUT soit repose sur le nouveau personnage, sans rien supposer.
		firstPerson = false
		setFirstPerson(true)
	end)
end

--- La vue subjective est-elle active ? Lue par les systemes qui doivent s'adapter (viser, cadrer un plan).
function FirstPersonController.isActive(): boolean
	return firstPerson
end

--- Coupe la vue subjective de l'exterieur, sans toucher a la bascule du joueur : une camera scriptee (plan de
--- travail, cinematique) doit pouvoir reprendre la main sans se battre avec nous.
function FirstPersonController.setEnabled(on: boolean)
	setFirstPerson(on)
end

return FirstPersonController
