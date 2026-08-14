--!strict
-- Mode BUILD (client) : le joueur amenage SON plot facon Sims. INCREMENT 1, brique 1 : entrer / sortir du mode +
-- afficher le quadrillage au sol. Le placement (fantome, poser, tourner, vendre) et la sauvegarde s'empilent par-dessus.
--
-- L'UI (barre d'outils + catalogue) sera faite dans Studio et cablee par un Handler ; ce controller EXPOSE enter / exit
-- / toggle pour qu'un bouton d'UI les appelle. En attendant, une touche TEMP les declenche (BuildConfigs.TEMP_TOGGLE_KEY).
--
-- Le quadrillage est une Texture posee cote CLIENT sur PrimaryGround : locale (non repliquee) -> SEUL le joueur en
-- train de construire la voit. Elle tuile a TILE_SIZE = la MEME maille que le futur snap de placement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local BuildConfigs = require(ReplicatedStorage.Modules.Configs.BuildConfigs)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local CameraEffects = require(script.Parent.Utils.CameraEffects)
local BuildPlaceController = require(script.Parent.BuildPlaceController)
local BuildWallController = require(script.Parent.BuildWallController)
local BuildDeleteController = require(script.Parent.BuildDeleteController)

local player = Players.LocalPlayer

-- Attribut pose par PlotService a la selection : le nom du Slot (plot) du joueur. Meme nom cote serveur.
local PLOT_ATTRIBUTE = "LeafiaPlot"

local BuildController = {}

-- Hook appele quand le build s'OUVRE (true) / se FERME (false), quel que soit le declencheur (bouton nav, touche B). Le
-- bootstrap le branche (ex : cacher la nav bar pendant le build). Defaut : ne fait rien.
BuildController.onStateChanged = function(_active: boolean) end :: (boolean) -> ()

local active = false
-- Modes du build : OBJET (placer), MUR (tirer des murs), SUPPRIMER (effacer au clic). Un seul actif a la fois.
local MODE_OBJECT = "object"
local MODE_WALL = "wall"
local MODE_DELETE = "delete"
local mode = MODE_OBJECT
local prevMode = MODE_OBJECT -- mode a retrouver en sortant du mode SUPPRIMER (X pour entrer / sortir)
local gridGui: SurfaceGui? = nil -- quadrillage (SurfaceGui + carres pleins) pose au sol cote client
local gridConn: RBXScriptConnection? = nil -- anime la vague d'ouverture de la grille (coupee si on sort en plein reveal)
local gridCells: { Frame } = {} -- les Frames des cases (gardees pour les recolorer selon le mode)

-- Recolore toutes les cases : indicateur de MODE (construire = cyan, supprimer = rouge). Grille absente -> rien.
local function setGridColor(color: Color3)
	if not gridGui then
		return
	end
	for _, cell in ipairs(gridCells) do
		cell.BackgroundColor3 = color
	end
end

-- Applique un mode : le controller correspondant est actif, les deux autres en veille (setEnabled(false) range leur
-- fantome / poignee / highlight). La grille change de couleur pour dire au joueur ce qu'il fait.
local function setMode(m: string)
	mode = m
	BuildPlaceController.setEnabled(m == MODE_OBJECT)
	BuildWallController.setEnabled(m == MODE_WALL)
	BuildDeleteController.setEnabled(m == MODE_DELETE)
	setGridColor(if m == MODE_DELETE then BuildConfigs.GRID_COLOR_DELETE else BuildConfigs.GRID_COLOR_BUILD)
end

-- Le sol du plot du joueur (PrimaryGround), ou nil s'il n'a pas encore de plot / pas encore replique.
local function findGround(): BasePart?
	local slot = player:GetAttribute(PLOT_ATTRIBUTE)
	if type(slot) ~= "string" then
		return nil
	end
	local worlds = workspace:FindFirstChild("Worlds")
	local plots = worlds and worlds:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild(slot)
	local ground = plot and plot:FindFirstChild(BuildConfigs.GROUND_NAME)
	if ground and ground:IsA("BasePart") then
		return ground
	end
	return nil
end

local function hideGrid()
	if gridConn then
		gridConn:Disconnect() -- coupe reveal/vague en cours (sinon son callback toucherait une grille detruite)
		gridConn = nil
	end
	if gridGui then
		gridGui:Destroy()
		gridGui = nil
	end
	table.clear(gridCells)
end

-- GENERATION D'OUVERTURE (une seule fois, comme un visuel d'initialisation) : les cases ne popent pas d'un coup. Une VAGUE
-- diagonale (le coin (0,0) part en premier) les fait apparaitre une par une, avec un BRUIT DE PERLIN qui casse la ligne
-- droite (front organique). Au passage de la vague, chaque case FLASHE (transparence file vers 0 = opaque, elle GLOWE avec
-- Brightness 10) et GROSSIT avec un rebond (easeOutBack), PUIS retombe a l'etat de repos (settled + taille pleine). Une
-- fois toutes posees, la connexion se coupe : cout script NUL au repos (la grille ne bouge plus).
local REVEAL_DIAGONAL_TIME = 1.6 -- temps que met le front diagonal a traverser tout le plot (plus grand = plus lent)
local REVEAL_NOISE_AMP = 0.05 -- jitter (s) du bruit -> front presque DROIT (vague lineaire). Mettre 0 = parfaitement droit
local REVEAL_NOISE_FREQ = 0.18 -- frequence spatiale du bruit (par case) : petit = grandes taches, grand = grain fin
local CELL_POP_TIME = 0.6 -- duree du pop d'UNE case (flash + grossit + retombe)
local REVEAL_FLASH_FRAC = 0.35 -- part du pop passee a MONTER vers le flash ; le reste = retour au repos
local REVEAL_FLASH_T = 0.6 -- transparence au PIC du flash (le plus visible). Plus haut = plus discret ; 0 = opaque a fond

type GridCell = { frame: Frame, delay: number, done: boolean }

-- Rebond a l'arrivee : la case depasse un poil sa taille finale puis se pose -> "pop" satisfaisant (peut valoir > 1).
local function easeOutBack(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	local u = t - 1
	return 1 + c3 * u * u * u + c1 * u * u
end

-- Anime la liste de cases (chacune a son `delay`) : chaque frame, on avance le temps et on met a jour les cases pas encore
-- posees. `fullPx` = taille finale du carre. Vague UNE FOIS : quand tout est pose, la connexion se coupe (fin de l'anim).
local function startGridReveal(cells: { GridCell }, fullPx: number)
	local settled = BuildConfigs.GRID_TRANSPARENCY
	local total = #cells
	local elapsed = 0
	local doneCount = 0
	gridConn = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		for _, cell in ipairs(cells) do
			if not cell.done then
				local t = (elapsed - cell.delay) / CELL_POP_TIME
				if t >= 1 then
					cell.frame.Size = UDim2.fromOffset(fullPx, fullPx)
					cell.frame.BackgroundTransparency = settled
					cell.done = true
					doneCount += 1
				elseif t > 0 then
					cell.frame.Size = UDim2.fromOffset(fullPx * math.max(0, easeOutBack(t)), fullPx * math.max(0, easeOutBack(t)))
					-- FLASH puis retour : 1 (invisible) -> REVEAL_FLASH_T (pic de visibilite) sur la 1re partie, puis -> settled.
					if t < REVEAL_FLASH_FRAC then
						cell.frame.BackgroundTransparency = 1 - (1 - REVEAL_FLASH_T) * (t / REVEAL_FLASH_FRAC)
					else
						local u = (t - REVEAL_FLASH_FRAC) / (1 - REVEAL_FLASH_FRAC)
						cell.frame.BackgroundTransparency = REVEAL_FLASH_T + (settled - REVEAL_FLASH_T) * u
					end
				end
			end
		end
		if doneCount >= total and gridConn then
			gridConn:Disconnect() -- reveal fini, la grille ne bouge plus
			gridConn = nil
		end
	end)
end

-- QUADRILLAGE : un SurfaceGui sur le dessus du sol qui porte UN carre plein par case (Frame, centre sur la case, avec un
-- joint autour). Le SurfaceGui est cale sur un COIN de la face -> aligne sur le snap (qui part du meme coin) tant que le
-- sol fait un multiple de TILE_SIZE. Cote CLIENT (parent = PlayerGui, Adornee = le sol) -> seul le batisseur le voit.
local function showGrid(ground: BasePart)
	hideGrid()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	-- On borne PixelsPerStud pour que le canvas (sol_studs * pps) ne depasse pas ~16000 px (limite Roblox) : au-dela, il
	-- serait tronque et les cases ne feraient plus TILE_SIZE studs -> decalage. Sur un sol normal, on garde le 100 net.
	local maxDim = math.max(ground.Size.X, ground.Size.Z, 1)
	local pps = math.min(BuildConfigs.GRID_PIXELS_PER_STUD, math.floor(16000 / maxDim))

	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeafiaBuildGrid"
	gui.Adornee = ground
	gui.Face = Enum.NormalId.Top -- le dessus du sol
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.ZOffset = 0
	gui.Brightness = BuildConfigs.GRID_BRIGHTNESS -- fait ressortir la grille malgre la transparence

	-- Conteneur des cases (detache le temps de tout remplir, parente au SurfaceGui a la fin -> un seul layout, pas 3000).
	local container = Instance.new("Frame")
	container.Name = "Cells"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromScale(1, 1)

	-- Une case = TILE_SIZE studs -> TILE_SIZE * pps pixels. Le carre plein occupe (1 - gap) de la case, le reste = joint.
	local cellPx = BuildConfigs.TILE_SIZE * pps
	local fullPx = cellPx * (1 - BuildConfigs.GRID_CELL_GAP)
	-- Le sol fait un multiple de TILE_SIZE (PlotService l'arrondit) -> cols/rows entiers, cases collees au coin = snap.
	local cols = math.round(ground.Size.X / BuildConfigs.TILE_SIZE)
	local rows = math.round(ground.Size.Z / BuildConfigs.TILE_SIZE)
	local maxDiag = math.max(1, (cols - 1) + (rows - 1))

	local cells: { GridCell } = {}
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local cell = Instance.new("Frame") :: Frame
			cell.BackgroundColor3 = BuildConfigs.GRID_COLOR
			cell.BorderSizePixel = 0
			cell.AnchorPoint = Vector2.new(0.5, 0.5) -- ancre au centre -> grossit depuis le centre (pas depuis un coin)
			cell.Position = UDim2.fromOffset((c + 0.5) * cellPx, (r + 0.5) * cellPx)
			cell.Size = UDim2.fromOffset(0, 0) -- part de zero : la vague la fait grossir
			cell.BackgroundTransparency = 1 -- cachee au depart
			cell.Parent = container
			table.insert(gridCells, cell) -- garde la reference pour recolorer selon le mode
			-- Delai d'apparition = front diagonal + bruit de Perlin (jitter organique). math.noise ~ [-1, 1].
			local diag = ((c + r) / maxDiag) * REVEAL_DIAGONAL_TIME
			local noise = math.noise(c * REVEAL_NOISE_FREQ, r * REVEAL_NOISE_FREQ) * REVEAL_NOISE_AMP
			table.insert(cells, { frame = cell, delay = math.max(0, diag + noise), done = false })
		end
	end

	container.Parent = gui
	gui.Parent = pg
	gridGui = gui
	startGridReveal(cells, fullPx) -- generation animee (diagonale + bruit), coupee toute seule a la fin
end

-- ===== CAMERA DE BUILD (facon Sims 4) =====
-- Vue iso qui ORBITE le centre du plot. On la place DIRECTEMENT sur le cercle au yaw / pitch / distance / focus courants
-- ecrite via BindToRenderStep a la priorite Camera. Controles :
--   ROTATION : clic DROIT + glisser (PC) ou 2 doigts en tournant (mobile) -> la cam pivote SUR PLACE (facon Studio :
--     elle reste au meme endroit, seul son regard tourne). PAS d'orbite autour d'un point (pas de grand arc).
--   PAN (se deplacer) : UN doigt (mobile) ou WASD (PC) -> deplace la cam dans le plan du sol.
--   ZOOM : pincement (mobile) ou molette (PC) -> avance / recule la cam le long de son regard (dolly).
-- Entree DOUCE : on tween de la vue de jeu vers la vue de depart, PUIS on branche la cam interactive.
local CAM_BIND = "LeafiaBuildOrbit"
local CAM_PITCH_START = 48 -- deg : inclinaison (grand = plus du dessus)
local CAM_PITCH_MIN, CAM_PITCH_MAX = 8, 82 -- bornes de l'inclinaison du regard (pas sous l'horizon / pas a la verticale)
local CAM_DISTANCE_START = 55 -- studs : recul initial (POSE la cam au depart ; ensuite le zoom la deplace)
local CAM_HEIGHT_MIN, CAM_HEIGHT_MAX = 8, 150 -- bornes de HAUTEUR de la cam au-dessus du sol (clamp du zoom + echelle du pan)
local CAM_LOOK_UP = 3 -- on vise un peu au-dessus du sol
local CAM_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- entree vers la vue orbitale
local EXIT_TIME = 0.45 -- duree du fondu de SORTIE (retour a la cam de jeu). Mieux qu'un snap/teleport.
local EXIT_BIND = "LeafiaBuildExit"
local exitBound = false
-- Etat de repos de la cam de JEU, CAPTURE a l'entree du build -> a la sortie on rend la main PILE dessus, sans pop (cf
-- journal : au passage Scriptable -> Custom, Custom garde le YAW mais remet SON pitch/zoom ; on finit donc le fondu la).
local exitDistance = 12.5
local exitFocusHeight = 1.4
local exitPitch = math.rad(15)
-- Son de transition joue en 2D quand la cam monte (entree en build). Placer le Sound a SoundService.Sounds.UI.PassingSound
-- (dans Studio). Absent -> SoundUtils warn une fois : c'est actionnable (poser le son), pas du bruit.
local PASSING_SOUND = { "Sounds", "UI", "PassingSound" }
-- Sensibilites. Les SIGNES / directions ne se DEDUISENT PAS (rendu) : si un axe part a l'envers a l'ecran, inverser
-- son signe la ou il est calcule. A confirmer a l'ecran.
local CAM_ROT_SENS = 0.006 -- rad par pixel (clic droit PC : yaw + pitch)
local CAM_ZOOM_STEP = 5 -- studs de DOLLY par cran de molette (avance / recule le long du regard)
local CAM_PINCH_SENS = 0.12 -- dolly par pixel de pincement (zoom mobile)
local CAM_TWIST_SENS = 1 -- facteur de rotation a deux doigts (yaw mobile)
local CAM_PAN_TOUCH = 0.003 -- pan au doigt : studs par pixel, x distance (dezoome = pan plus vite). Monte = glisse plus vite
local CAM_PAN_KEY = 1.1 -- pan clavier WASD : vitesse relative, x distance x dt
-- Ressort du focus (effet SLIME a l'arret du pan clavier) : le focus SUIT une cible, il la rejoint en debordant
-- LEGEREMENT puis se pose. Raideur haute = snappy ; amortissement bas = plus de rebond. A regler a l'oeil.
local FOCUS_STIFFNESS = 350
local FOCUS_DAMPING = 22
-- Meme ressort pour la ROTATION (slime au relachement du clic droit / du twist 2 doigts). Angulaire (radians) : les
-- memes valeurs donnent le meme rendu qu'en position, le ressort est invariant d'echelle. Baisse l'amortissement = plus de rebond.
local ROT_STIFFNESS = 350
local ROT_DAMPING = 22
-- Effet de FOV : la vue s'OUVRE quand on se deplace (sensation de vitesse), se referme a l'arret. Passe par
-- CameraEffects (ecrivain unique du FOV) ; CameraController rend la main pendant le build (lit isActive()).
local BUILD_FOV_BASE = 70 -- FOV au repos en build (= REST_FOV du jeu)
local BUILD_FOV_MOVE = 6 -- ouverture max a pleine vitesse de pan

local camBound = false
local camYaw = 0
local camYawTarget = 0
local camYawVel = 0
local camPitch = math.rad(CAM_PITCH_START)
local camPitchTarget = math.rad(CAM_PITCH_START)
local camPitchVel = 0
local camPos = Vector3.zero -- POSITION de la cam (ancre) : la rotation la garde FIXE (facon Studio) ; pan / zoom la deplacent
local camPosTarget = Vector3.zero -- cible du pan ; camPos la rejoint via un ressort (effet slime a l'arret)
local camPosVel = Vector3.zero -- vitesse du ressort de position
local prevPos = Vector3.zero -- position de la frame precedente, pour mesurer la vitesse (effet FOV)
local groundRefY = 0 -- hauteur du sol de reference (borne le zoom + echelle du pan)
local enterTween: Tween? = nil

-- Etat d'input.
local rmbDown = false -- clic droit (PC) : rotation yaw + pitch
local activeTouches: { InputObject } = {} -- doigts poses : 1 = pan, 2 = zoom (pincement) + rotation (twist)
local pinchPrev = 0 -- distance precedente entre 2 doigts
local twistPrev = 0 -- angle precedent entre 2 doigts

-- Perso fige pendant le build (sinon il marcherait sous la cam). On coupe aussi les controles par defaut (le thumbstick
-- mobile mangerait les touchers de pan). Le WASD reste lu en direct (IsKeyDown), independamment des controles coupes.
local frozenHumanoid: Humanoid? = nil
local savedWalkSpeed = 16
local controls: any = nil

-- Direction du REGARD depuis (yaw, pitch) : horizontale tournee par yaw, inclinee vers le bas par pitch. Unitaire.
local function lookDir(): Vector3
	local h = Vector3.new(-math.cos(camYaw), 0, -math.sin(camYaw)) -- horizontale du regard (unitaire)
	return h * math.cos(camPitch) + Vector3.new(0, -math.sin(camPitch), 0)
end

-- CFrame de la cam : ANCREE en camPos, regardant dans lookDir. La rotation ne bouge donc pas camPos (sur place).
local function buildCFrame(): CFrame
	return CFrame.lookAt(camPos, camPos + lookDir())
end

-- Hauteur de la cam au-dessus du sol de ref (echelle du pan / FOV : plus haut = plus vite). Bornee a un min positif.
local function camHeight(): number
	return math.max(camPos.Y - groundRefY, CAM_HEIGHT_MIN)
end

-- Axes horizontaux de la camera (plan du sol), deduits du yaw : fwd = la ou elle regarde, right = sa droite. Le pan
-- deplace le focus dans CE repere (pas celui du monde), pour que "vers le haut de l'ecran" = vers le fond de la vue.
local function groundAxes(): (Vector3, Vector3)
	local fwd = Vector3.new(-math.cos(camYaw), 0, -math.sin(camYaw)).Unit
	-- right = la droite ECRAN de la camera. Signe confirme a l'ecran : Q = gauche, D = droite (clavier ET pan tactile).
	local right = Vector3.new(-fwd.Z, 0, fwd.X)
	return fwd, right
end

-- Rotation (clic droit). Signes confirmes a l'ecran : glisser a droite -> tourne a droite ; baisser la souris ->
-- regarde vers le bas (plus du dessus), monter la souris -> regarde vers l'horizon.
local function applyOrbit(deltaX: number, deltaY: number)
	-- On bouge les CIBLES ; la vue les rejoint via le ressort -> rebond leger au relachement.
	camYawTarget += deltaX * CAM_ROT_SENS
	camPitchTarget = math.clamp(camPitchTarget + deltaY * CAM_ROT_SENS, math.rad(CAM_PITCH_MIN), math.rad(CAM_PITCH_MAX))
end

-- ZOOM = DOLLY : on avance / recule la cam le long de son regard (amount > 0 = vers ce qu'on regarde). On borne la
-- HAUTEUR pour ne pas traverser le sol ni partir trop haut. Instantane (pas de ressort) : cible et position ensemble.
local function applyZoom(amount: number)
	local move = lookDir() * amount
	camPos += move
	camPosTarget += move
	local minY, maxY = groundRefY + CAM_HEIGHT_MIN, groundRefY + CAM_HEIGHT_MAX
	camPos = Vector3.new(camPos.X, math.clamp(camPos.Y, minY, maxY), camPos.Z)
	camPosTarget = Vector3.new(camPosTarget.X, math.clamp(camPosTarget.Y, minY, maxY), camPosTarget.Z)
end

-- PAN au doigt : convention "j'ATTRAPE le monde et je le tire" (confirme a l'ecran) -> glisser a droite fait aller la vue
-- a GAUCHE, glisser vers le bas fait AVANCER. Echelle x hauteur (plus haut = pan plus vite) pour un ressenti constant.
local function applyPanTouch(deltaX: number, deltaY: number)
	local fwd, right = groundAxes()
	local scale = camHeight() * CAM_PAN_TOUCH
	-- Touch = INSTANTANE (pas de ressort, sinon le doigt lague) : on bouge la cible ET la position ensemble, et on tue
	-- la vitesse du ressort pour qu'un residu de rebond clavier ne parte pas en glissade. Les DEUX axes sont inverses.
	local delta = right * (-deltaX * scale) + fwd * (deltaY * scale)
	camPosTarget += delta
	camPos += delta
	camPosVel = Vector3.zero
end

-- PAN clavier (WASD) + HAUTEUR (E monte / Q descend), lu chaque frame (touches maintenues). Vitesse x hauteur x dt.
local function keyboardPan(dt: number)
	local x, z = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		z += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		z -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		x += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		x -= 1
	end
	if x ~= 0 or z ~= 0 then
		local fwd, right = groundAxes()
		-- On deplace la CIBLE (pas la position directe) : la cam la rejoint via le ressort -> rebond leger a l'arret.
		camPosTarget += (fwd * z + right * x).Unit * (camHeight() * CAM_PAN_KEY * dt)
	end
	-- HAUTEUR Y : E descend, A monte (A = KeyCode.Q sur AZERTY). Bornee comme le zoom pour ne pas percer le sol.
	local dy = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.E) then
		dy -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
		dy += 1
	end
	if dy ~= 0 then
		local newY = math.clamp(
			camPosTarget.Y + dy * (camHeight() * CAM_PAN_KEY * dt),
			groundRefY + CAM_HEIGHT_MIN,
			groundRefY + CAM_HEIGHT_MAX
		)
		camPosTarget = Vector3.new(camPosTarget.X, newY, camPosTarget.Z)
	end
end

local function updateBuildCamera(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	dt = math.min(dt, 1 / 30) -- borne le pas : garde le ressort stable si le FPS chute
	keyboardPan(dt) -- deplace la CIBLE de position
	-- RESSORT de POSITION : suit de pres pendant le mouvement, deborde legerement puis se pose a l'arret (slime).
	local disp = camPosTarget - camPos
	camPosVel += (disp * FOCUS_STIFFNESS - camPosVel * FOCUS_DAMPING) * dt
	camPos += camPosVel * dt
	-- EFFET DE FOV : vitesse REELLE de la cam (marche clavier ET tactile) -> ouverture de la vue. CameraEffects lisse.
	local speed = (camPos - prevPos).Magnitude / dt
	prevPos = camPos
	local ref = camHeight() * CAM_PAN_KEY
	local panFactor = if ref > 0 then math.clamp(speed / ref, 0, 1) else 0
	CameraEffects.SetFovBase(BUILD_FOV_BASE + panFactor * BUILD_FOV_MOVE)
	-- RESSORT de rotation : slime au relachement (le clic droit / twist bouge la cible, la vue la rejoint en debordant).
	camYawVel += ((camYawTarget - camYaw) * ROT_STIFFNESS - camYawVel * ROT_DAMPING) * dt
	camYaw += camYawVel * dt
	camPitchVel += ((camPitchTarget - camPitch) * ROT_STIFFNESS - camPitchVel * ROT_DAMPING) * dt
	camPitch += camPitchVel * dt
	-- ROTATION SUR PLACE : camPos ne bouge pas, seul le regard tourne.
	camera.CFrame = buildCFrame()
end

-- Fige le perso (pas de marche sous la cam) et coupe les controles par defaut (thumbstick mobile qui mangerait le pan).
local function freezeCharacter()
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		frozenHumanoid = humanoid
		savedWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 0
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end
	if controls then
		controls:Disable()
	end
end

local function unfreezeCharacter()
	local humanoid = frozenHumanoid
	frozenHumanoid = nil
	if humanoid and humanoid.Parent then
		humanoid.WalkSpeed = savedWalkSpeed
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
	if controls then
		controls:Enable()
	end
end

local function startBuildCamera(center: Vector3, startYaw: number)
	local focus = center + Vector3.new(0, CAM_LOOK_UP, 0)
	groundRefY = center.Y
	camYaw = startYaw
	camYawTarget = startYaw
	camYawVel = 0
	camPitch = math.rad(CAM_PITCH_START)
	camPitchTarget = camPitch
	camPitchVel = 0
	-- On POSE la cam comme l'ancienne vue (reculee + elevee, regardant le joueur) pour garder le meme cadrage de depart :
	-- camPos = focus - regard * recul. Ensuite la rotation se fait SUR PLACE autour de camPos.
	camPos = focus - lookDir() * CAM_DISTANCE_START
	camPosTarget = camPos
	camPosVel = Vector3.zero
	prevPos = camPos
	CameraEffects.SetFovBase(BUILD_FOV_BASE) -- FOV de base du build (lerp deja pendant le tween d'entree)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if exitBound then
		RunService:UnbindFromRenderStep(EXIT_BIND) -- on re-entre pendant un fondu de sortie : on l'annule
		exitBound = false
	end
	-- Capture l'etat de repos de la cam de JEU (distance / hauteur du focus / inclinaison) AVANT de passer en Scriptable,
	-- pour rendre la main a l'IDENTIQUE a la sortie. Custom vise le sujet + un offset ; on en deduit ces 3 valeurs.
	local root0 = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root0 and root0:IsA("BasePart") then
		local gFocus = camera.Focus.Position
		local gPos = camera.CFrame.Position
		local off = gPos - gFocus
		if off.Magnitude > 1 then
			exitDistance = off.Magnitude
			exitFocusHeight = gFocus.Y - root0.Position.Y
			exitPitch = math.asin(math.clamp((gPos.Y - gFocus.Y) / off.Magnitude, -1, 1))
		end
	end
	camera.CameraType = Enum.CameraType.Scriptable
	-- ENTREE DOUCE : tween de la vue actuelle (cam de jeu) vers la vue orbitale de depart, PUIS on branche l'orbite
	-- interactive. Pendant le tween c'est TweenService qui pilote la CFrame ; ensuite le render step prend la main.
	if enterTween then
		enterTween:Cancel()
	end
	enterTween = TweenService:Create(camera, CAM_TWEEN, { CFrame = buildCFrame() })
	enterTween:Play()
	SoundUtils.play(PASSING_SOUND) -- son de transition (2D), sync avec la montee de la cam
	enterTween.Completed:Once(function()
		if active and not camBound then
			RunService:BindToRenderStep(CAM_BIND, Enum.RenderPriority.Camera.Value, updateBuildCamera)
			camBound = true
		end
	end)
end

local function stopBuildCamera()
	if enterTween then
		enterTween:Cancel()
		enterTween = nil
	end
	if camBound then
		RunService:UnbindFromRenderStep(CAM_BIND)
		camBound = false
	end
	rmbDown = false
	table.clear(activeTouches)
	pinchPrev = 0
	twistPrev = 0
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if exitBound then
		RunService:UnbindFromRenderStep(EXIT_BIND) -- un fondu tournait deja : on repart proprement
		exitBound = false
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart")) then
		camera.CameraType = Enum.CameraType.Custom -- pas de perso : snap direct (rien a suivre)
		return
	end
	-- FONDU DE SORTIE (mieux qu'un snap) : on GLISSE de la vue actuelle vers la vue de jeu, en RE-ANCRANT sur la position
	-- LIVE du perso chaque frame (un tween vers une CFrame fixe planterait la cam si le joueur bouge, cf journal). Depart =
	-- la vue EXACTE de sortie -> aucun pop ; fin = l'etat de repos capture a l'entree -> Custom reprend PILE la.
	local startCamPos = camera.CFrame.Position
	local startFocus = startCamPos + camera.CFrame.LookVector * exitDistance
	local flatLook = Vector3.new(-math.cos(camYaw), 0, -math.sin(camYaw)).Unit -- direction horizontale du regard (build)
	local offsetDir = (-flatLook) * math.cos(exitPitch) + Vector3.new(0, 1, 0) * math.sin(exitPitch)
	local elapsed = 0
	exitBound = true
	RunService:BindToRenderStep(EXIT_BIND, Enum.RenderPriority.Camera.Value, function(dt: number)
		if not root.Parent then -- perso detruit (respawn) en plein fondu : on rend la main direct
			RunService:UnbindFromRenderStep(EXIT_BIND)
			exitBound = false
			camera.CameraType = Enum.CameraType.Custom
			return
		end
		elapsed += dt
		local t = math.clamp(elapsed / EXIT_TIME, 0, 1)
		local e = 1 - (1 - t) * (1 - t) -- ease out
		local targetFocus = root.Position + Vector3.new(0, exitFocusHeight, 0)
		local targetCamPos = targetFocus + offsetDir * exitDistance
		camera.CFrame = CFrame.lookAt(startCamPos:Lerp(targetCamPos, e), startFocus:Lerp(targetFocus, e))
		if t >= 1 then
			RunService:UnbindFromRenderStep(EXIT_BIND)
			exitBound = false
			camera.CameraSubject = humanoid
			camera.CameraType = Enum.CameraType.Custom -- reprise pile sur l'etat de repos -> aucun saut
		end
	end)
end

-- ===== MUSIQUE DE BUILD =====
-- En entrant en build on joue UNE musique du dossier Build AU HASARD, jamais la meme qu'a la derniere fois (si au moins
-- 2 dispos). On LIT le dossier a chaque fois -> ajouter des musiques dans Studio suffit, aucun code a toucher. Elle
-- BOUCLE (pas SoundUtils, qui detruit apres 5s) : on gere un Sound clone a la main, fondu a l'entree et a la sortie.
local MUSIC_BUILD_PATH = { "Sounds", "Game", "Musics", "Build" } -- dossier des musiques de build
local BUILD_MUSIC_VOLUME = 0.15 -- a regler a l'oreille (0.5 explosait les oreilles)
local BUILD_MUSIC_FADE = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- fade-IN (entree)
-- fade-OUT (sortie) volontairement LONG et lineaire : la musique s'eteint en douceur au lieu d'etre coupee net (trop sec).
local BUILD_MUSIC_FADE_OUT = TweenInfo.new(2.5, Enum.EasingStyle.Linear)

local rng = Random.new()
local buildMusic: Sound? = nil
local lastBuildMusicName: string? = nil -- la derniere jouee, pour ne pas la reprendre juste apres

local function buildMusicFolder(): Instance?
	local node: Instance? = SoundService
	for _, name in ipairs(MUSIC_BUILD_PATH) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

-- Tire une musique de build au hasard en EXCLUANT la derniere jouee. Si l'exclusion ne laisse rien (dossier a une
-- seule musique, ou vide), on reprend parmi tout ce qui existe.
local function pickBuildMusic(): Sound?
	local folder = buildMusicFolder()
	if not folder then
		return nil
	end
	local pool: { Sound } = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Sound") and child.Name ~= lastBuildMusicName then
			table.insert(pool, child)
		end
	end
	if #pool == 0 then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Sound") then
				table.insert(pool, child)
			end
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[rng:NextInteger(1, #pool)]
end

local function startBuildMusic()
	local template = pickBuildMusic()
	if not template then
		return -- aucune musique dans le dossier Build : silence, pas d'erreur
	end
	lastBuildMusicName = template.Name
	local music = template:Clone()
	music.Name = "LeafiaBuildMusic"
	music.Looped = true
	music.Volume = 0
	music.Parent = SoundService
	music:Play()
	buildMusic = music
	TweenService:Create(music, BUILD_MUSIC_FADE, { Volume = BUILD_MUSIC_VOLUME }):Play()
end

local function stopBuildMusic()
	local music = buildMusic
	buildMusic = nil
	if not music then
		return
	end
	local fade = TweenService:Create(music, BUILD_MUSIC_FADE_OUT, { Volume = 0 })
	fade:Play()
	fade.Completed:Once(function()
		music:Destroy()
	end)
end

-- Entre en mode build (si le joueur a un plot). Appele par la touche TEMP, et plus tard par le bouton d'UI.
function BuildController.enter()
	if active then
		return
	end
	local ground = findGround()
	if not ground then
		return -- pas de plot selectionne : rien a construire, on ne fait rien (pas une erreur)
	end
	active = true
	showGrid(ground)
	startBuildMusic()
	BuildPlaceController.start(ground)
	BuildWallController.start(ground)
	BuildDeleteController.start(ground)
	setMode(MODE_OBJECT) -- on entre en mode OBJET par defaut
	freezeCharacter()
	-- Orientation FACE AU PLOT, independante de comment le joueur est tourne : on regarde depuis l'ENTREE (RootSpawnPlayer)
	-- vers le centre du plot. Repli sur l'orientation propre du sol. Le FOCUS, lui, reste sur le joueur (il construit
	-- autour de lui) -- seule la DIRECTION vient du plot.
	local center = ground.Position
	local frontDir: Vector3? = nil
	local spawn = ground.Parent and ground.Parent:FindFirstChild("RootSpawnPlayer", true)
	if spawn and spawn:IsA("BasePart") then
		local d = Vector3.new(center.X - spawn.Position.X, 0, center.Z - spawn.Position.Z)
		if d.Magnitude > 1e-3 then
			frontDir = d.Unit
		end
	end
	if not frontDir then
		local lv = ground.CFrame.LookVector
		local d = Vector3.new(lv.X, 0, lv.Z)
		if d.Magnitude > 1e-3 then
			frontDir = d.Unit
		end
	end
	local startYaw = if frontDir then math.atan2(-frontDir.Z, -frontDir.X) else 0
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		center = root.Position -- focus sur le joueur ; l'orientation vient du plot, pas de son regard
	end
	startBuildCamera(center, startYaw)
	BuildController.onStateChanged(true) -- build ouvert (ex : cache la nav bar)
end

function BuildController.exit()
	if not active then
		return
	end
	active = false
	hideGrid()
	stopBuildCamera()
	unfreezeCharacter()
	stopBuildMusic()
	BuildPlaceController.stop()
	BuildWallController.stop()
	BuildDeleteController.stop()
	mode = MODE_OBJECT
	prevMode = MODE_OBJECT
	BuildController.onStateChanged(false) -- build ferme (ex : remontre la nav bar)
end

function BuildController.toggle()
	if active then
		BuildController.exit()
	else
		BuildController.enter()
	end
end

function BuildController.isActive(): boolean
	return active
end

function BuildController.init()
	BuildPlaceController.init() -- placement (fantome, poser, tourner) ; ses inputs sont gates sur l'etat build
	BuildWallController.init() -- mode mur (clic-drag) ; ses inputs sont gates sur l'etat build + le mode mur
	BuildDeleteController.init() -- mode suppression (clic pour effacer) ; gate sur l'etat build + le mode suppression

	-- Controles par defaut (thumbstick mobile) resolus UNE fois EN FOND : require(PlayerModule) peut yield longtemps,
	-- jamais dans le chemin d'entree en build. On les coupe pendant le build (freezeCharacter).
	task.spawn(function()
		local ok, result = pcall(function()
			local scripts = player:WaitForChild("PlayerScripts", 10)
			local pm = scripts and require(scripts:WaitForChild("PlayerModule", 10)) :: any
			return pm and pm:GetControls()
		end)
		if ok then
			controls = result
		end
	end)

	-- TEMP : raccourci clavier pour entrer / sortir tant que le bouton d'UI n'existe pas.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == BuildConfigs.TEMP_TOGGLE_KEY then
			BuildController.toggle()
		elseif active and input.KeyCode == BuildConfigs.WALL_TOGGLE_KEY then
			setMode(if mode == MODE_WALL then MODE_OBJECT else MODE_WALL) -- V : bascule objet <-> mur
		elseif active and input.KeyCode == BuildConfigs.DELETE_TOGGLE_KEY then
			-- X : entre / sort du mode SUPPRIMER (on retrouve le mode d'avant en sortant).
			if mode == MODE_DELETE then
				setMode(prevMode)
			else
				prevMode = mode
				setMode(MODE_DELETE)
			end
		end
	end)

	-- CAMERA (build seulement). PAN = 1 doigt / WASD ; ZOOM = pincement / molette ; ROTATION = 2 doigts (twist) / clic
	-- droit PC. gameProcessed ignore a la PRISE : pas de camera quand on touche l'UI du catalogue. Le relachement se
	-- traite toujours (sinon un drag reste coince).
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not active or gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rmbDown = true
			-- Souris figee pendant le glissement -> rotation infinie sans buter sur les bords. Le curseur custom se gare
			-- le temps du drag (CursorController ne touche pas MouseBehavior).
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif input.UserInputType == Enum.UserInputType.Touch then
			table.insert(activeTouches, input)
			if #activeTouches == 2 then
				local a, b = activeTouches[1].Position, activeTouches[2].Position
				pinchPrev = (a - b).Magnitude
				twistPrev = math.atan2(b.Y - a.Y, b.X - a.X)
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if rmbDown then
				applyOrbit(input.Delta.X, input.Delta.Y)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			applyZoom(input.Position.Z * CAM_ZOOM_STEP)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			if #activeTouches >= 2 then
				-- DEUX DOIGTS : pincement = zoom, rotation de la paire = yaw.
				local a, b = activeTouches[1].Position, activeTouches[2].Position
				local dist = (a - b).Magnitude
				local ang = math.atan2(b.Y - a.Y, b.X - a.X)
				if pinchPrev > 0 then
					applyZoom((dist - pinchPrev) * CAM_PINCH_SENS)
					local dAng = ang - twistPrev
					-- garde le plus court chemin d'angle (evite un saut quand atan2 passe +pi / -pi)
					if dAng > math.pi then
						dAng -= 2 * math.pi
					elseif dAng < -math.pi then
						dAng += 2 * math.pi
					end
					camYawTarget += dAng * CAM_TWIST_SENS
				end
				pinchPrev = dist
				twistPrev = ang
			elseif #activeTouches == 1 and input == activeTouches[1] then
				-- UN DOIGT : se deplacer (pan).
				applyPanTouch(input.Delta.X, input.Delta.Y)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rmbDown = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		elseif input.UserInputType == Enum.UserInputType.Touch then
			for i = #activeTouches, 1, -1 do
				if activeTouches[i] == input then
					table.remove(activeTouches, i)
				end
			end
			if #activeTouches < 2 then
				pinchPrev = 0 -- pincement / rotation reprennent a neuf au prochain 2e doigt
				twistPrev = 0
			end
		end
	end)
end

return BuildController
