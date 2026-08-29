--!strict
-- CAMERA DE CONDUITE : une orbite qui se tient DERRIERE la machine, un peu au-dessus.
--
-- Generique et sans rien connaitre de la tondeuse : l'appelant lui donne un sujet a suivre, un CAP et une avance,
-- rien de plus. Le jour ou il y aura un tracteur, il branchera le meme module.
--
-- ===== POURQUOI UNE CAMERA SCRIPTEE =====
-- Roblox n'expose AUCUN moyen de brider le yaw de sa camera par defaut. Une butee avec rebond oblige donc a
-- prendre la camera, et prendre la camera coute deux choses qu'il faut rendre a la main :
--   1. `Humanoid.CameraOffset` n'est plus applique -> secousses, bob, plongee et TRAINEE DE VIRAGE disparaissent.
--      On va donc chercher `CameraEffects.GetOffset()` et on l'applique nous-memes, comme la haie.
--   2. `CameraEffects.SetZoomBoost` agit sur les BORNES DE ZOOM DU JOUEUR, une mecanique de la camera Custom :
--      elle ne fait plus rien ici. Le recul est donc porte sur la distance d'orbite (`drive` dans `step`).
--
-- ===== LE CAP SUIT, IL NE COLLE PAS =====
-- La camera ne se plante pas derriere la machine au degre pres : son cap RATTRAPE celui de la machine avec du
-- retard. C'est ce retard qui fait glisser le joueur dans le cadre pendant un virage -- l'effet qu'on avait
-- avant via un decalage lateral, mais obtenu par le bon moyen.
--
-- ===== LA BUTEE EST ELASTIQUE =====
-- Le joueur tourne librement autour de la machine jusqu'a la limite. Au-dela, une marge resiste de plus en plus,
-- puis un mur dur. Au relachement, un ressort SOUS-AMORTI ramene a la limite avec un petit rebond. Meme recette
-- que l'orbite de la haie, et pour la meme raison : un mur sec se ressent comme un bug, un rebond se ressent
-- comme une intention.
--
-- ===== ON NE LISSE JAMAIS LA POSITION =====
-- Lisser la position d'une camera qui ORBITE coupe la corde de l'arc : elle plonge vers l'interieur du cercle
-- puis ressort, et sa distance varie pendant le pivot. On la place DIRECTEMENT sur son cercle, et on ne lisse
-- que les PARAMETRES (cap, distance). Seule exception : l'arrivee, qui glisse une fois depuis la vue de jeu.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CameraEffects = require(script.Parent.CameraEffects)

local DriveCamera = {}

export type Settings = {
	distance: number, -- rayon de l'orbite, en studs
	height: number, -- hauteur de la camera au-dessus du point vise
	lookHeight: number, -- hauteur du point vise sur le sujet
	follow: number, -- vitesse a laquelle le cap rattrape celui de la machine (le retard de virage)
	zoom: number, -- studs de recul supplementaires a pleine avance
	zoomSpeed: number,
	yawLimit: number, -- degres de chaque cote avant la butee
	yawMargin: number, -- degres elastiques au-dela de la butee
	stiffness: number, -- ressort de retour a la butee
	damping: number, -- sous 2*sqrt(stiffness) pour garder un rebond
	sensitivity: number, -- degres par pixel de souris
	touchSensitivity: number, -- degres par pixel de doigt
	enterSpeed: number, -- vitesse du glissement d'arrivee
	settleDist: number, -- distance a partir de laquelle on considere l'arrivee finie
}

local player = Players.LocalPlayer

local TWO_PI = math.pi * 2

local active = false
local subject: BasePart? = nil
local config: Settings? = nil

-- Cap de la CAMERA. Il rattrape celui de la machine, il ne lui est pas egal : voir en tete de fichier.
local camHeading = 0
-- Ecart voulu par le JOUEUR autour de ce cap, et la vitesse de son ressort de retour.
local yaw = 0
local yawVel = 0
local distance = 0

-- Le joueur tient-il l'orbite en ce moment ? Tant qu'il la tient, le ressort ne tire pas.
local orbiting = false
local orbitTouch: InputObject? = nil

-- Glissement d'arrivee : tant qu'on n'est pas arrive, on interpole ; ensuite on place au degre pres.
local arrived = false

local connections: { RBXScriptConnection } = {}

-- Ecart d'angle le plus COURT entre deux caps. Sans ca, passer de 179 a -179 degres ferait faire un tour complet
-- a la camera pour un mouvement de deux degres.
local function shortestAngle(from: number, to: number): number
	local d = (to - from) % TWO_PI
	if d > math.pi then
		d -= TWO_PI
	end
	return d
end

-- Rubber-band : dans les clous, sensibilite pleine. Au-dela, pousser ENCORE resiste de plus en plus jusqu'a un
-- mur dur. Revenir vers le centre reste libre -- sinon on se sentirait retenu dans les deux sens.
local function applyYaw(deltaPixels: number, sensitivity: number)
	local cfg = config
	if not cfg then
		return
	end
	local limit = math.rad(cfg.yawLimit)
	local margin = math.rad(cfg.yawMargin)
	local step = -math.rad(deltaPixels * sensitivity)

	local over = 0
	if yaw > limit then
		over = yaw - limit
	elseif yaw < -limit then
		over = -limit - yaw
	end

	local pushingOut = (yaw >= limit and step > 0) or (yaw <= -limit and step < 0)
	if pushingOut then
		step *= 1 - math.clamp(over / margin, 0, 1)
	end

	yaw = math.clamp(yaw + step, -limit - margin, limit + margin)
end

-- Une image. `heading` = cap de la machine en radians (0 = regard vers -Z, comme le reste du projet).
-- `drive` = avance de 0 a 1 en valeur absolue, pour le recul.
local function step(dt: number, heading: number, drive: number)
	local cfg = config
	local part = subject
	local camera = Workspace.CurrentCamera
	if not (cfg and part and camera and part.Parent) then
		return
	end

	-- 1) LE CAP RATTRAPE. Par le plus court chemin, et en PARAMETRE : c'est un angle qu'on lisse, jamais une
	-- position. Un facteur exponentiel garde la meme vitesse quel que soit le framerate.
	camHeading += shortestAngle(camHeading, heading) * math.min(1, cfg.follow * dt)

	-- 2) LE RESSORT DE BUTEE. Il ne tire que quand le joueur a lache l'orbite : sinon on se battrait avec lui.
	if orbiting or orbitTouch then
		yawVel = 0
	else
		local limit = math.rad(cfg.yawLimit)
		local rest = math.clamp(yaw, -limit, limit)
		if yaw ~= rest or yawVel ~= 0 then
			-- Ressort SOUS-AMORTI : l'amortissement sous 2*sqrt(raideur) laisse un depassement, et c'est lui le
			-- rebond. Un ressort critique reviendrait juste, sans caractere.
			local accel = -cfg.stiffness * (yaw - rest) - cfg.damping * yawVel
			yawVel += accel * dt
			yaw += yawVel * dt
			if math.abs(yaw - rest) < 1e-4 and math.abs(yawVel) < 1e-3 then
				yaw = rest -- un ressort n'atteint jamais sa cible : sans ce clic on ecrirait a vie
				yawVel = 0
			end
		end
	end

	-- 3) LE RECUL, en PARAMETRE lui aussi. `SetZoomBoost` ne marche que sous la camera Custom (il deplace les
	-- bornes de zoom du joueur) : sous une camera scriptee il faut le porter ici, sur le rayon.
	local wanted = cfg.distance + math.abs(drive) * cfg.zoom
	distance += (wanted - distance) * math.min(1, cfg.zoomSpeed * dt)

	-- 4) LA POSE. `back` est la direction OPPOSEE au regard : le projet ecrit un cap `h` comme un regard
	-- (-sin, 0, -cos), donc l'arriere est (sin, 0, cos).
	local total = camHeading + yaw
	local focus = part.Position + Vector3.new(0, cfg.lookHeight, 0)
	local back = Vector3.new(math.sin(total), 0, math.cos(total))
	local target = CFrame.lookAt(focus + back * distance + Vector3.new(0, cfg.height, 0), focus)

	-- 5) PLACEE, PAS LISSEE. Voir l'en-tete : lisser une position qui tourne sur un arc coupe la corde.
	if arrived then
		camera.CFrame = target
	else
		camera.CFrame = camera.CFrame:Lerp(target, math.min(1, cfg.enterSpeed * dt))
		if (camera.CFrame.Position - target.Position).Magnitude < cfg.settleDist then
			arrived = true
		end
	end

	-- 6) LES EFFETS, RENDUS A LA MAIN. `Humanoid.CameraOffset` est ignore en Scriptable : sans cette ligne, la
	-- trainee de virage, les secousses, le bob et la plongee d'atterrissage disparaitraient tous d'un coup --
	-- exactement le mouvement qu'on veut garder. En repere LOCAL et APRES le placement, pour qu'un impact claque
	-- au lieu de se fondre.
	camera.CFrame = camera.CFrame * CFrame.new(CameraEffects.GetOffset())
end

local function disconnectAll()
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)
end

-- Prend la camera. `heading` sert a demarrer le cap DEJA aligne sur la machine : partir de zero ferait pivoter
-- toute l'orbite au premier instant, alors qu'on veut seulement glisser depuis la vue de jeu.
function DriveCamera.enter(part: BasePart, heading: number, settings: Settings)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	subject = part
	config = settings
	camHeading = heading
	yaw = 0
	yawVel = 0
	distance = settings.distance
	arrived = false
	orbiting = false
	orbitTouch = nil

	camera.CameraType = Enum.CameraType.Scriptable
	active = true

	disconnectAll()

	-- SOURIS : clic droit maintenu = orbite. Le gauche reste libre pour tout le reste.
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				orbiting = true
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				orbiting = false
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input, processed)
			if processed or not orbiting then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				local cfg = config
				if cfg then
					applyYaw(input.Delta.X, cfg.sensitivity)
				end
			end
		end)
	)

	-- TACTILE : un doigt qui glisse tourne la camera. On ecarte les touchers DEJA traites par une interface --
	-- c'est ce qui laisse le joystick de deplacement tranquille sans avoir a le connaitre.
	table.insert(
		connections,
		UserInputService.TouchStarted:Connect(function(input, processed)
			if not processed and not orbitTouch then
				orbitTouch = input
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.TouchMoved:Connect(function(input, processed)
			if processed or input ~= orbitTouch then
				return
			end
			local cfg = config
			if cfg then
				applyYaw(input.Delta.X, cfg.touchSensitivity)
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.TouchEnded:Connect(function(input)
			if input == orbitTouch then
				orbitTouch = nil
			end
		end)
	)
end

-- Une image de conduite. Sans effet tant qu'on n'a pas pris la camera.
function DriveCamera.step(dt: number, heading: number, drive: number)
	if active then
		step(dt, heading, drive)
	end
end

-- REND LA CAMERA. On repasse en Custom sans transition : Custom recale son propre pitch de repos de toute facon,
-- donc un glissement d'arrivee vers un etat qu'elle va corriger ne ferait qu'ajouter une seconde de flou avant
-- le meme resultat. Le vrai confort viendra d'une sortie dediee si le saut se voit a l'usage.
function DriveCamera.exit()
	if not active then
		return
	end
	active = false
	subject = nil
	config = nil
	orbiting = false
	orbitTouch = nil
	disconnectAll()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid:IsA("Humanoid") then
			camera.CameraSubject = humanoid
		end
	end
end

function DriveCamera.isActive(): boolean
	return active
end

return DriveCamera
