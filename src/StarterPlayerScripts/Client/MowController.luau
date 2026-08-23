--!strict
-- LA TONDEUSE, cote client. Trois choses, et rien d'autre :
--   1. le prompt "[E] TAKE" quand on s'approche (detection RADIALE, aucun angle mort)
--   2. l'appel de la COUPE, chaque image, sous la part CutZone
--   3. la rotation des ROUES, calculee sur la distance reellement parcourue
--
-- Le PORTAGE lui-meme appartient au serveur (MowService) : c'est lui qui soude la tondeuse au porteur, donc tout
-- le monde la voit au meme endroit. Ici on ne fait que demander, afficher et couper.
--
-- POURQUOI LA COUPE EST CLIENTE : l'herbe de zone est fabriquee par CHAQUE client (GrassZoneController), elle
-- n'existe pas cote serveur. Faire transiter la coupe par le reseau reviendrait a payer cher pour rien. Le jour ou
-- tondre rapportera un cheque, c'est le serveur qui comptera -- pas ces appels-la.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local MowConfigs = require(ReplicatedStorage.Modules.Configs.MowConfigs)
local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)
local GrassZoneController = require(script.Parent.GrassZoneController)
local CameraEffects = require(script.Parent.Utils.CameraEffects)
local Vignette = require(ReplicatedStorage.Modules.UI.Core.Vignette)
local MoveThumb = require(ReplicatedStorage.Modules.UI.Core.MoveThumb)
local MoveInput = require(script.Parent.Utils.MoveInput)

local MowController = {}

local ACTION_NAME = "LeafiaMowerCarry"
-- La conduite tourne en BindToRenderStep JUSTE APRES le personnage, et surtout PAS sur Heartbeat.
-- Le module de controle de Roblox appelle `humanoid:Move` a chaque image, avant la physique. Un Move
-- concurrent envoye depuis Heartbeat arrive APRES la physique : une image sur deux partait dans notre
-- direction, l'autre dans celle du joueur, et le personnage partait dans tous les sens.
-- En se placant apres lui dans la MEME image, on ecrase sa demande avant que la physique ne la lise.
local STEER_BIND = "LeafiaMowSteer"
-- Touche reelle du bind. Volontairement en dur plutot que `Enum.KeyCode[PROMPT_KEY]` : une indexation par
-- chaine n'est pas verifiable par le type-checker, et une faute dans la config donnerait une erreur a
-- l'execution au lieu d'un rouge a l'ecriture. PROMPT_KEY ne sert qu'a AFFICHER la touche.
local ACTION_KEY = Enum.KeyCode.E
-- REVELATION : touche MAINTENUE qui allume ce qui reste a tondre. G, libre dans tout le projet.
local HIGHLIGHT_KEY = Enum.KeyCode.G
local CARRIED_ATTRIBUTE = "LeafiaCarriedBy" -- pose par MowService : UserId du porteur
local RESCAN_INTERVAL = 2 -- secondes entre deux balayages du Workspace (streaming : une tondeuse peut arriver tard)
local PROMPT_INTERVAL = 0.15 -- on ne teste pas la proximite a chaque image, ca ne se voit pas et ca coute

local player = Players.LocalPlayer

local carryRemote: RemoteEvent? = nil
local steerRemote: RemoteEvent? = nil
local pullRemote: RemoteEvent? = nil
local pullBound = false
-- Dernier braquage ENVOYE. On ne renvoie que sur un vrai changement : tenir une touche ne doit pas remplir
-- le reseau d'un message par image pour une valeur qui ne bouge pas.
local lastSteerSent = 0
local mowers: { Model } = {}
local lastScanAt = 0
local lastPromptAt = 0
local lastActionAt = 0
local promptTarget: Model? = nil -- tondeuse dont le prompt est affiche (pour ne le remontrer qu'au CHANGEMENT)
-- Point d'ancrage REELLEMENT passe au prompt, garde tel quel : on le recalculerait sinon a chaque test, et la
-- moindre difference de virgule ferait croire que le singleton ne nous appartient plus.
local promptAnchor: Vector3? = nil
local actionBound = false
local lastInputLog = 0 -- throttle du diagnostic d'input (voir STEER_DEBUG_INPUT)
local debugLabel: TextLabel? = nil

-- Affiche une ligne de diagnostic EN HAUT DE L'ECRAN. Cree l'etiquette a la premiere utilisation.
--
-- Volontairement moche et lisible : c'est un outil de mesure, pas une interface. Il disparait avec
-- STEER_DEBUG_INPUT.
local function showDebug(text: string)
	local label = debugLabel
	if not label then
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then
			return
		end
		local screen = Instance.new("ScreenGui")
		screen.Name = "MowDebug"
		screen.ResetOnSpawn = false
		screen.IgnoreGuiInset = true
		screen.DisplayOrder = 5000
		screen.Parent = playerGui
		local made = Instance.new("TextLabel")
		made.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		made.BackgroundTransparency = 0.35
		made.Position = UDim2.fromScale(0.5, 0.02)
		made.AnchorPoint = Vector2.new(0.5, 0)
		made.Size = UDim2.fromScale(0.44, 0.16)
		made.TextColor3 = Color3.fromRGB(255, 255, 255)
		made.TextScaled = true
		made.Font = Enum.Font.Code
		-- N'AVALE AUCUN INPUT : un panneau pose par-dessus le joystick tactile empecherait justement de bouger,
		-- et on croirait avoir aggrave le bug qu'on mesure.
		made.Active = false
		made.Parent = screen
		debugLabel = made
		label = made
	end
	label.Text = text
end

local lastCutAt = 0 -- instant de la derniere touffe coupee : les brins volent encore un peu apres
local lastCutPos: Vector3? = nil -- position de coupe a l'image precedente : donne la distance parcourue
-- CONDUITE en cours. Sert a ne couper AutoRotate qu'une fois, et surtout a le RENDRE une fois -- une
-- restauration ecrite a chaque image ecraserait un autre systeme qui l'aurait coupe pour ses raisons.
-- Revelation tenue ? Lue par le calcul du recul de camera, qui additionne ses deux raisons.
local revealOn = false
local steering = false
local autoRotateWas = true
-- UN ANGLE PAR ROUE, jamais un compteur partage. Avec une seule variable, la premiere roue de la boucle
-- avancait l'angle et la seconde repartait de la : l'angle progressait DEUX fois par image (les roues
-- tournaient deux fois trop vite) et les deux n'etaient jamais au meme endroit.
-- Cle par le Motor6D lui-meme : deux tondeuses posees dans la map ne se marchent pas dessus non plus.
local wheelAngles: { [Motor6D]: number } = {}
local connection: RBXScriptConnection? = nil

-- ===== CAMERA DU DEMARRAGE =====
-- Elle passe devant la machine, de cote, et regarde le joueur tirer la corde.
--
-- TOUT EST EXPRIME EN OFFSETS RELATIFS AU JOUEUR, jamais en positions monde. Une cible calculee une fois laisse
-- la camera plantee des que le sujet bouge, et l'arrivee comme le retour doivent SUIVRE le joueur pour ne pas
-- laisser de trou. C'est la lecon deja payee sur le retour de camera de la taille de haie.
local UP = Vector3.new(0, 1, 0)
local PULL_CAM_BIND = "LeafiaMowPullCam"
local pullCamOn = false -- la camera de demarrage est-elle demandee ? (lu par applyCameraRig pour le champ)
local pullCamBound = false
local pullPhase: string? = nil -- "in" (arrivee), "hold" (en place), "out" (retour)
local pullElapsed = 0
-- Etat de la camera de JEU, capture AVANT de passer en Scriptable : l'arrivee en part et le retour y revient.
local pullSavedFocus: Vector3? = nil -- (camera.Focus - HRP)
local pullSavedCam: Vector3? = nil -- (camera.Position - camera.Focus) : l'angle ET le zoom reels
-- SECOUSSE du coup de corde. Amplitude COURANTE en studs : elle monte d'un coup au tirage et s'eteint toute
-- seule. Une secousse amortie plutot qu'un a-coup : rapprocher la camera puis la faire repartir donnait un "TAC"
-- Le plan au moment ou l'on lache : le retour part de LA, pas de la cible theorique.
local pullExitFocus = Vector3.zero
local pullExitCam = Vector3.zero
-- Les offsets REELLEMENT poses a la derniere image. C'est d'eux que part le retour -- et pas de `camera.Focus`,
-- qui garderait la valeur laissee par la camera de jeu tant qu'on ne l'ecrit pas.
local pullLastFocus = Vector3.zero
local pullLastCam = Vector3.zero

-- REVELATION : l'herbe s'allume ET la camera prend du recul. UN SEUL point d'entree pour les deux -- les
-- appeler separement finirait par laisser la camera reculee alors que l'herbe est deja eteinte.
local function setReveal(on: boolean)
	revealOn = on
	GrassZoneController.setHighlight(on)
	-- Le champ de vision est pose par applyCameraRig, pas ici : il a DEUX raisons (la revelation et la camera de
	-- demarrage) et deux ecrivains finiraient par s'ecraser a tour de role, une image sur deux.
end

-- LA CAMERA DE CONDUITE : le recul, pose une seule fois par image.
-- LE RECUL A DEUX RAISONS : la revelation, et la vitesse. Elles passent par UNE SEULE valeur -- deux
-- appelants ecrivant chacun la sienne, le dernier de l'image ecraserait l'autre, et le recul clignoterait.
-- La vitesse se MESURE sur le deplacement reel plutot que de recopier la valeur du serveur : c'est ce que le
-- joueur voit, et ca marche meme si un autre systeme le ralentit.
local function applyCameraRig(hrp: BasePart?, carrying: boolean)
	local total = if revealOn then MowConfigs.HIGHLIGHT_ZOOM else 0
	if carrying and hrp and MowConfigs.DRIVE_ZOOM > 0 and MowConfigs.SPEED_MAX > 0 then
		local v = hrp.AssemblyLinearVelocity
		local speed = math.sqrt(v.X * v.X + v.Z * v.Z)
		total += math.clamp(speed / MowConfigs.SPEED_MAX, 0, 1) * MowConfigs.DRIVE_ZOOM
	end
	CameraEffects.SetZoomBoost(total)
	-- LE CHAMP DE VISION, MEME REGLE : deux raisons, une seule ecriture. Elles s'ADDITIONNENT plutot que de se
	-- choisir -- reveler pendant qu'on tire la corde est possible, et le recul doit alors valoir les deux.
	local fov = if revealOn then MowConfigs.HIGHLIGHT_FOV else 0
	if pullCamOn then
		fov += MowConfigs.PULL_CAM_FOV
	end
	CameraEffects.SetFovOffset(fov)
end

-- LE PLAN DE TIRAGE, en offsets relatifs au joueur. Deux valeurs, dans la meme convention que la camera de jeu :
-- le point VISE (par rapport au joueur) et la position de l'oeil (par rapport a ce point vise). C'est cette
-- convention qui permet d'interpoler entre ce plan et la vue de jeu sans jamais melanger deux reperes.
--
-- On part du REGARD du joueur et pas de l'orientation de la machine : la machine est soudee devant lui, donc les
-- deux disent la meme chose, mais le regard se lit sans avoir a deviner quel axe du modele pointe vers l'avant.
local function pullShotOffsets(hrp: BasePart): (Vector3, Vector3)
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-4 then flat.Unit else Vector3.new(0, 0, -1)
	local side = flat:Cross(UP)
	local forward = MowConfigs.PULL_CAM_FORWARD
	local focusOffset = Vector3.new(0, MowConfigs.PULL_CAM_LOOK_HEIGHT, 0)
	local eye = flat * forward + side * MowConfigs.PULL_CAM_SIDE + UP * MowConfigs.PULL_CAM_HEIGHT
	return focusOffset, eye - focusOffset
end

-- Une image de la camera de demarrage. Arrivee, maintien et retour passent tous par ici : les trois ne different
-- que par les deux offsets a poser, et les separer aurait donne trois fois la meme trigonometrie.
local function stepPullCam(dt: number)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local savedFocus, savedCam = pullSavedFocus, pullSavedCam
	if not (camera and root and root:IsA("BasePart") and savedFocus and savedCam) then
		-- Le personnage a disparu (mort, changement de lieu) : on rend la camera tout de suite plutot que de
		-- tenir un plan sur un joueur qui n'existe plus.
		pullPhase = nil
		pullCamBound = false
		RunService:UnbindFromRenderStep(PULL_CAM_BIND)
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
		return
	end
	local hrp = root :: BasePart
	local shotFocus, shotCam = pullShotOffsets(hrp)

	local focusOffset, camOffset = shotFocus, shotCam
	if pullPhase == "in" then
		pullElapsed += dt
		local t = math.clamp(pullElapsed / MowConfigs.PULL_CAM_IN_TIME, 0, 1)
		-- ON EMPRUNTE LA COURBE A TweenService plutot que d'ecrire l'interpolation a la main : `GetValue` rend
		-- l'alpha d'un style d'easing, donc on obtient un rebond elastique sans avoir a le coder -- et on peut en
		-- changer depuis la config sans toucher a ce fichier.
		local a = TweenService:GetValue(t, MowConfigs.PULL_CAM_EASING, Enum.EasingDirection.Out)
		focusOffset = savedFocus:Lerp(shotFocus, a)
		camOffset = savedCam:Lerp(shotCam, a)
		if t >= 1 then
			pullPhase = "hold"
		end
	elseif pullPhase == "out" then
		pullElapsed += dt
		local t = math.clamp(pullElapsed / MowConfigs.PULL_CAM_OUT_TIME, 0, 1)
		local a = TweenService:GetValue(t, MowConfigs.PULL_CAM_EASING, Enum.EasingDirection.Out)
		-- On revient vers l'etat EXACT de la camera de jeu capture a l'entree. Viser une valeur approchee laisse
		-- un micro-saut a la reprise : sub-perceptible a la lecture, tres visible a l'ecran.
		focusOffset = pullExitFocus:Lerp(savedFocus, a)
		camOffset = pullExitCam:Lerp(savedCam, a)
		if t >= 1 then
			pullPhase = nil
			pullCamBound = false
			RunService:UnbindFromRenderStep(PULL_CAM_BIND)
			camera.CameraType = Enum.CameraType.Custom
			return
		end
	end

	-- LE FOCUS EST RE-ANCRE SUR LA POSITION VIVE DU JOUEUR A CHAQUE IMAGE. Une CFrame calculee une fois laisserait
	-- la camera plantee des que le sujet bouge, et le retour finirait a cote de lui.
	-- On memorise le plan NON SECOUE : le retour doit partir d'une vue propre, pas d'une position de tremblement
	-- attrapee au hasard.
	pullLastFocus, pullLastCam = focusOffset, camOffset

	local focus = hrp.Position + focusOffset
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(focus + camOffset, focus)
	-- On ecrit AUSSI le Focus : c'est lui que Roblox utilise comme point d'ecoute des sons 3D, et le laisser sur
	-- la valeur de la camera de jeu ferait entendre la scene depuis l'ancien point de vue.
	camera.Focus = CFrame.new(focus)
end

-- Demande ou relache la camera de demarrage. Idempotent : appelable a chaque image sans rien casser.
local function setPullCam(on: boolean)
	if on == pullCamOn then
		return
	end
	pullCamOn = on
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (MowConfigs.PULL_CAM_ENABLED and camera and root and root:IsA("BasePart")) then
		return
	end
	local hrp = root :: BasePart

	if on then
		-- L'ETAT DE LA CAMERA DE JEU SE CAPTURE AVANT DE PASSER EN SCRIPTABLE, et il se MESURE : la distance
		-- camera -> Focus est le vrai zoom (pas la distance au joueur), et l'offset Focus -> joueur donne la
		-- hauteur du regard. Devinees, ces deux valeurs laissent un saut a la reprise.
		pullSavedFocus = camera.Focus.Position - hrp.Position
		pullSavedCam = camera.CFrame.Position - camera.Focus.Position
		pullPhase = "in"
		pullElapsed = 0
		-- LE VIGNETTAGE N'EXISTE QUE POUR CE MOMENT. Il est eteint le reste du temps : un vignettage permanent ne
		-- dit plus rien au bout d'une minute, c'est son ARRIVEE qui resserre l'attention.
		Vignette.setStrength(MowConfigs.PULL_CAM_VIGNETTE)
		if not pullCamBound then
			pullCamBound = true
			RunService:BindToRenderStep(PULL_CAM_BIND, Enum.RenderPriority.Camera.Value, stepPullCam)
		end
	elseif pullCamBound then
		-- LE RETOUR PART DU PLAN COURANT, pas de la cible theorique : on peut lacher la machine en pleine
		-- arrivee, et repartir d'ailleurs ferait un saut au moment meme ou l'on veut de la douceur.
		pullExitFocus, pullExitCam = pullLastFocus, pullLastCam
		Vignette.setStrength(0)
		pullPhase = "out"
		pullElapsed = 0
	end
end

local function rootOf(model: Model): BasePart?
	local root = model.PrimaryPart or model:FindFirstChild(MowConfigs.ROOT_NAME)
	return if root and root:IsA("BasePart") then root else nil
end

-- OU accrocher le badge : au-dessus du milieu de la machine, point CALCULE et non une part.
--
-- Accroche a une part, le badge se pose sur le CENTRE de cette part -- et le centre d'un mesh de guidon herite du
-- rig, pas du bon sens. Le badge partait donc devant la tondeuse, et se deplacait autour d'elle quand elle etait
-- posee de biais : ce n'etait pas un probleme d'angle, c'etait le POINT qui n'etait pas le bon.
--
-- On prend le milieu en X/Z et le point le plus HAUT des parts VISIBLES (la CutZone et les zones logiques ne sont
-- pas des pieces de la machine). Independant de l'orientation, par construction.
local function promptAnchorOf(model: Model): Vector3?
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false
	for _, d in ipairs(model:GetDescendants()) do
		-- Zone de coupe et boite de collision ECARTEES : ce sont des volumes logiques, pas des pieces de la
		-- machine. Les compter deplacerait le badge vers un point qui n'existe sur rien de visible.
		if
			d:IsA("BasePart")
			and d.Name ~= MowConfigs.CUT_ZONE_NAME
			and d.Name ~= MowConfigs.HITBOX_NAME
			and d.Transparency < 1
		then
			local h = d.Size * 0.5
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local c = (d.CFrame * CFrame.new(h.X * sx, h.Y * sy, h.Z * sz)).Position
						lo = Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z))
						hi = Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z))
						found = true
					end
				end
			end
		end
	end
	if not found then
		return nil
	end
	return Vector3.new((lo.X + hi.X) * 0.5, hi.Y, (lo.Z + hi.Z) * 0.5)
end

-- Balayage du Workspace. RE-SCAN periodique et non une seule fois au boot : avec le streaming, une tondeuse
-- posee loin n'existe pas encore chez le client au demarrage, et un scan unique ne la verrait jamais.
local function refreshMowers(now: number)
	if now - lastScanAt < RESCAN_INTERVAL then
		return
	end
	lastScanAt = now
	table.clear(mowers)
	for _, d in ipairs(Workspace:GetDescendants()) do
		-- Filtre bon marche d'abord : IsA("Model") ecarte des milliers de parts avant toute comparaison de nom.
		if d:IsA("Model") and d.Name == MowConfigs.MODEL_NAME and rootOf(d) then
			mowers[#mowers + 1] = d
		end
	end
end

-- La tondeuse que JE porte, s'il y en a une.
local function myMower(): Model?
	for _, model in ipairs(mowers) do
		if model:GetAttribute(CARRIED_ATTRIBUTE) == player.UserId then
			return model
		end
	end
	return nil
end

-- Tondeuse LIBRE la plus proche, sous DETECT_RADIUS. Distance HORIZONTALE a une part FIXE (la racine), jamais a
-- GetPivot : le pivot d'un Model suit sa bounding box, donc la CutZone soudee le decalerait. Un rayon plutot
-- qu'une box : colle a un bout de la tondeuse, une box laisse un angle mort et le prompt ne sort pas.
local function freeMowerNear(from: Vector3): (Model?, BasePart?)
	local best, bestRoot = nil, nil
	local bestDist = MowConfigs.DETECT_RADIUS
	for _, model in ipairs(mowers) do
		if model:GetAttribute(CARRIED_ATTRIBUTE) == nil then
			local root = rootOf(model)
			if root then
				local d = root.Position - from
				local dist = math.sqrt(d.X * d.X + d.Z * d.Z)
				if dist < bestDist then
					bestDist, best, bestRoot = dist, model, root
				end
			end
		end
	end
	return best, bestRoot
end

-- OU on coupe, et sur quel rayon. La part CutZone (posee par scripts/studio/) fait autorite : sa position dit le
-- point, sa largeur donne le rayon. Absente, on retombe devant la racine -- le jeu tourne quand meme, il coupe
-- juste moins juste, et le message le DIT une fois plutot que d'echouer en silence.
local warnedNoCutZone = false
local function cutPointOf(model: Model): (Vector3?, number)
	local zone = model:FindFirstChild(MowConfigs.CUT_ZONE_NAME, true)
	if zone and zone:IsA("BasePart") then
		return zone.Position, zone.Size.X * 0.5
	end
	local root = rootOf(model)
	if not root then
		return nil, 0
	end
	if not warnedNoCutZone then
		warnedNoCutZone = true
		warn(
			`[MowController] Pas de part "{MowConfigs.CUT_ZONE_NAME}" sous {model.Name} : coupe approximative. `
				.. "Lancer scripts/studio/CreerZoneDeCoupeTondeuse.lua dans la barre de commandes."
		)
	end
	return (root.CFrame * CFrame.new(0, 0, -MowConfigs.FALLBACK_FORWARD)).Position, MowConfigs.FALLBACK_RADIUS
end

-- ROUES. L'angle vient de la DISTANCE parcourue, pas du temps : la roue colle donc au sol quelle que soit
-- l'allure du joueur, et elle s'arrete pile quand il s'arrete. Une animation, elle, patinerait.
-- Les Motor6D des roues, cherches DANS TOUT LE MODELE et memorises.
--
-- La version d'avant les cherchait sous la seule RootPart, avec des noms qui n'etaient pas les bons. Elle ne
-- trouvait donc RIEN, sans un mot : les roues ne tournaient jamais et rien ne disait pourquoi. C'est exactement
-- le genre d'echec silencieux qui coute des heures -- d'ou l'avertissement plus bas.
--
-- MEMOIRE A UNE ENTREE : on ne porte qu'une machine a la fois, donc une seule suffit, et elle ne garde qu'une
-- reference -- rien a nettoyer. Parcourir les descendants a chaque image, en revanche, se paierait.
local wheelMotorsModel: Model? = nil
local wheelMotorsList: { Motor6D } = {}

local function wheelMotorsOf(model: Model): { Motor6D }
	if wheelMotorsModel == model then
		return wheelMotorsList
	end
	local found: { Motor6D } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			for _, name in ipairs(MowConfigs.WHEEL_MOTORS) do
				if d.Name == name then
					found[#found + 1] = d
					break
				end
			end
		end
	end
	wheelMotorsModel = model
	wheelMotorsList = found
	if #found == 0 then
		-- ACTIONNABLE : la liste est renseignee, donc les roues DOIVENT tourner, mais aucun joint ne porte ces
		-- noms. Sans ce message, on regarde une tondeuse qui glisse sans savoir ou chercher.
		warn(
			`[Mow] Aucun Motor6D de roue trouve dans "{model.Name}" `
				.. `(cherches : {table.concat(MowConfigs.WHEEL_MOTORS, ", ")}). Les roues ne tourneront pas.`
		)
	end
	return found
end

-- ===== PARTICULES =====
-- Les emetteurs d'un modele, cherches UNE fois et memorises. Meme memoire a une entree que les roues : on ne
-- porte qu'une machine a la fois, donc rien a nettoyer, et on ne parcourt pas les descendants a chaque image.
local emitterModel: Model? = nil
local emittersByName: { [string]: { ParticleEmitter } } = {}
-- Les noms REELLEMENT presents, gardes pour pouvoir les afficher quand un nom attendu manque.
local emitterNamesSeen: { string } = {}
local emitterWarned = false

local function emittersOf(model: Model, names: { string }): { ParticleEmitter }
	if emitterModel ~= model then
		emitterModel = model
		table.clear(emittersByName)
		table.clear(emitterNamesSeen)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				local list = emittersByName[d.Name]
				if not list then
					list = {}
					emittersByName[d.Name] = list
					emitterNamesSeen[#emitterNamesSeen + 1] = d.Name
				end
				list[#list + 1] = d
			end
		end
		emitterWarned = false
	end
	local found: { ParticleEmitter } = {}
	local missing: { string } = {}
	for _, name in ipairs(names) do
		local list = emittersByName[name]
		if list then
			for _, emitter in ipairs(list) do
				found[#found + 1] = emitter
			end
		else
			missing[#missing + 1] = name
		end
	end

	-- ON DIT CE QU'ON N'A PAS TROUVE, ET ON LISTE CE QU'IL Y A.
	--
	-- Sans ca, un nom d'emetteur mal orthographie donne exactement le meme resultat qu'un effet coupe : rien. On
	-- cherche alors le probleme dans le code, dans les conditions, dans les particules elles-memes -- partout sauf
	-- dans le nom.
	-- Lister les emetteurs REELLEMENT presents evite l'aller-retour : la reponse est dans le message.
	if #missing > 0 and not emitterWarned then
		emitterWarned = true
		warn(
			`[Mow] Emetteur(s) introuvable(s) sous "{model.Name}" : {table.concat(missing, ", ")}. `
				.. `Presents dans le modele : {if #emitterNamesSeen > 0 then table.concat(emitterNamesSeen, ", ") else "AUCUN"}.`
		)
	end
	return found
end

-- Allume ou eteint un groupe d'emetteurs. On n'ECRIT QUE SUR CHANGEMENT : reposer la meme valeur a chaque image
-- sur plusieurs emetteurs coute pour rien.
local function setEmitters(model: Model, names: { string }, on: boolean)
	for _, emitter in ipairs(emittersOf(model, names)) do
		if emitter.Enabled ~= on then
			emitter.Enabled = on
		end
	end
end

local function spinWheels(model: Model, distance: number)
	-- `== 0` et non `<= 0` : une distance NEGATIVE est une marche arriere, et les roues doivent tourner a
	-- l'envers. La rejeter les figeait des qu'on recule.
	if distance == 0 then
		return
	end
	for _, motor in ipairs(wheelMotorsOf(model)) do
		local wheel = motor.Part1
		-- Rayon MESURE sur la roue plutot que devine : changer la taille du modele ne demande alors aucun reglage.
		local radius = MowConfigs.WHEEL_RADIUS_FALLBACK
		if wheel then
			local s = wheel.Size
			radius = math.max(s.X, s.Y, s.Z) * 0.5
		end
		if radius > 1e-3 then
			-- Distance SIGNEE : negative en marche arriere, donc les roues tournent a l'envers toutes seules.
			local delta = MowConfigs.WHEEL_DIRECTION * distance / radius
			local angle = ((wheelAngles[motor] or 0) + delta) % (math.pi * 2)
			wheelAngles[motor] = angle
			-- AXE DEDUIT DE LA GEOMETRIE. Une roue est LARGE x LARGE x MINCE : son axe de rotation est le cote le
			-- plus MINCE, c'est ce qui fait d'elle une roue et pas un disque qu'on ferait tourner a plat.
			-- Plus fiable que trois essais a l'ecran, et ca survit a un re-export du modele : si le rig change
			-- d'orientation dans Blender, la deduction suit toute seule.
			local axis = MowConfigs.WHEEL_AXIS
			if axis == "AUTO" and wheel then
				local w = wheel.Size
				if w.X <= w.Y and w.X <= w.Z then
					axis = "X"
				elseif w.Y <= w.Z then
					axis = "Y"
				else
					axis = "Z"
				end
			end
			local spin = if axis == "Y"
				then CFrame.Angles(0, angle, 0)
				elseif axis == "Z" then CFrame.Angles(0, 0, angle)
				else CFrame.Angles(angle, 0, 0)
			-- On ecrit C0, PAS Transform : Transform appartient a l'Animator. Corollaire, ces joints ne doivent
			-- etre cles dans AUCUNE animation, sinon deux ecrivains se disputent le meme joint.
			local base = motor:GetAttribute("LeafiaBaseC0")
			if typeof(base) ~= "CFrame" then
				base = motor.C0
				motor:SetAttribute("LeafiaBaseC0", base)
			end
			motor.C0 = (base :: CFrame) * spin
		end
	end
end

-- ===== DEBUG DE TRAJECTOIRE =====
-- Des points qui dessinent la courbe QUE LA MACHINE VA SUIVRE avec le braquage courant. On SIMULE quelques
-- dixiemes de seconde en avant, avec exactement la meme formule que la conduite : si la courbe affichee ne
-- correspond pas au trajet reel, c'est que la formule a change d'un cote et pas de l'autre.
--
-- Purement local et purement visuel : aucune collision, aucun raycast, rien ne le voit.
local trailFolder: Folder? = nil
local trailParts: { BasePart } = {}

local function clearTrail()
	if trailFolder then
		trailFolder:Destroy()
		trailFolder = nil
	end
	table.clear(trailParts)
end

-- Points crees UNE fois puis REUTILISES : en recreer a chaque image ferait des centaines d'instances par seconde.
local function trailPoint(index: number): BasePart
	local existing = trailParts[index]
	if existing then
		return existing
	end
	if not trailFolder then
		local folder = Instance.new("Folder")
		folder.Name = "LeafiaMowTrail"
		folder.Parent = Workspace
		trailFolder = folder
	end
	local part = Instance.new("Part")
	part.Name = "TrailPoint"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(MowConfigs.STEER_DEBUG_SIZE, MowConfigs.STEER_DEBUG_SIZE, MowConfigs.STEER_DEBUG_SIZE)
	part.Color = MowConfigs.STEER_DEBUG_COLOR
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	-- CanQuery n'a d'effet que parce que CanCollide est faux : sinon les raycasts la verraient quand meme.
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = trailFolder
	trailParts[index] = part
	return part
end

-- Simule la trajectoire a partir de l'etat COURANT, avec la meme formule que la conduite.
local function drawTrail(origin: Vector3, yaw: number, turnPerSec: number, speed: number)
	local simYaw = yaw
	local simPos = origin
	local step = MowConfigs.STEER_DEBUG_STEP
	for i = 1, MowConfigs.STEER_DEBUG_POINTS do
		simYaw -= turnPerSec * step
		local f = Vector3.new(-math.sin(simYaw), 0, -math.cos(simYaw))
		simPos += f * speed * step
		-- Les points RETRECISSENT avec la distance : on lit le SENS de la courbe d'un coup d'oeil.
		local shrink = 1 - (i - 1) / MowConfigs.STEER_DEBUG_POINTS * 0.6
		local size = MowConfigs.STEER_DEBUG_SIZE * shrink
		local point = trailPoint(i)
		point.Size = Vector3.new(size, size, size)
		point.CFrame = CFrame.new(simPos)
	end
end

-- CONDUITE, facon VEHICULE. Deux commandes qui ne se melangent pas :
--   avant / arriere -> on AVANCE le long du cap ;
--   gauche / droite -> on BRAQUE, et RIEN d'autre. Appuyer sur la seule touche de cote ne doit pas faire avancer
--                      la tondeuse d'un pouce, exactement comme on redresse une machine a l'arret.
--
-- C'est ce decouplage qui donne l'arc : on ne se DEPLACE jamais lateralement, donc la trajectoire ne peut que se
-- courber. Le ballant de la machine et la pose des bras suivent gratuitement, ils se calculent deja sur le cap.
--
-- L'input est PROJETE sur le regard horizontal de la camera, jamais lu en axes monde : "avancer" veut dire la
-- direction avant de la CAMERA, dont les composantes monde changent des qu'on tourne la vue. Lire un axe brut ne
-- marcherait que dans une seule orientation (piege deja paye sur la grimpe d'echelle).
local function steer(humanoid: Humanoid, hrp: BasePart, dt: number)
	-- UNE MACHINE A L'ARRET NE SE POUSSE PAS. Tant que la corde n'a pas ete tiree, c'est un poids mort : ni
	-- avance, ni braquage. On pouvait jusqu'ici promener la tondeuse sans jamais la demarrer, ce qui vidait le
	-- demarrage de tout son sens -- il n'etait plus qu'une animation qu'on pouvait ignorer.
	--
	-- Meme raison que la coupe, deja bloquee plus bas par le meme attribut : les deux consequences du demarrage
	-- se lisent au meme endroit.
	local mower = myMower()
	if not (mower and mower:GetAttribute(MowConfigs.RUNNING_ATTRIBUTE) == true) then
		-- On ECRIT zero, on ne se contente pas de sortir : ce bind passe APRES le module de controle de Roblox,
		-- donc ne rien faire laisserait SA demande de deplacement s'appliquer.
		humanoid:Move(Vector3.zero, false)
		clearTrail()
		return
	end
	-- `GetMoveVector` rend un vecteur RELATIF A LA CAMERA : X = cote, Z = arriere. C'est POUR CA que
	-- `Humanoid:Move(v, true)` existe -- le `true` demande a Roblox d'y appliquer la camera.
	-- On lit donc ses composantes DIRECTEMENT. Les projeter sur des axes MONDE melangeait deux reperes :
	-- un simple "avance" produisait une composante laterale fantome qui dependait de l'orientation de la
	-- vue, et la tondeuse partait en virage sans qu'on touche aux touches de cote.
	local mv = MoveInput.get()
	local forwardAmount = math.clamp(-mv.Z, -1, 1)
	local lateralAmount = math.clamp(mv.X, -1, 1)

	-- DIAGNOSTIC A L'ECRAN. Voir MowConfigs.STEER_DEBUG_INPUT.
	--
	-- AFFICHE, PAS IMPRIME : ce probleme n'existe que sur mobile, et sur un telephone la console n'est pas
	-- lisible. Un diagnostic qu'on ne peut pas lire la ou le bug se produit ne sert a rien.
	--
	-- Quand la machine ne bouge pas, TROIS causes donnent exactement le meme symptome et se corrigent a trois
	-- endroits differents : l'input n'arrive pas, le moteur n'est pas vu comme demarre, ou la vitesse est a zero.
	if MowConfigs.STEER_DEBUG_INPUT and os.clock() - lastInputLog > 0.2 then
		lastInputLog = os.clock()
		showDebug(
			`input {string.format("%.2f", mv.X)} , {string.format("%.2f", mv.Z)}`
				.. `\nvitesse {string.format("%.1f", humanoid.WalkSpeed)}`
				.. `\nmoteur {if mower:GetAttribute(MowConfigs.RUNNING_ATTRIBUTE) == true then "ON" else "OFF"}`
				.. `\ntactile {if UserInputService.TouchEnabled then "oui" else "non"}`
		)
	end

	local look = hrp.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	if facing.Magnitude < 1e-4 then
		return
	end
	facing = facing.Unit
	local yaw = math.atan2(-facing.X, -facing.Z)

	-- LE BRAQUAGE PART TOUJOURS AU SERVEUR : c'est lui qui tient la soudure, donc lui qui fait pivoter la
	-- MACHINE. Envoye seulement sur un vrai changement, pas a chaque image.
	-- LE RETOUR A ZERO PART TOUJOURS, meme s'il est plus petit que le seuil. Sans ce cas particulier, relacher
	-- la touche apres une poussee legere (0.05, un stick a peine effleure) ne franchissait pas le seuil : le
	-- serveur gardait ce reste de braquage et poussait la machine de travers POUR TOUJOURS.
	local releasing = lateralAmount == 0 and lastSteerSent ~= 0
	if steerRemote and (releasing or math.abs(lateralAmount - lastSteerSent) > 0.08) then
		lastSteerSent = lateralAmount
		steerRemote:FireServer(lateralAmount)
	end

	-- BRAQUER SEUL FAIT ROULER, doucement, et le corps tourne AVEC. On ne fait pas pivoter une tondeuse sur un
	-- point : on la fait avancer juste assez pour qu'elle tourne. C'est ce petit roulement qui rend le
	-- mouvement credible -- sans lui, le personnage pivotait sur ses talons comme une tourelle.
	local braking = math.abs(forwardAmount) > MowConfigs.STEER_MOVE_EPSILON
	local turning = math.abs(lateralAmount) > MowConfigs.STEER_INPUT_EPSILON
	local drive = forwardAmount
	if turning and not braking and MowConfigs.STEER_CRAWL > 0 then
		-- `Move` prend une FRACTION de la WalkSpeed, pas une vitesse. On divise donc par la vitesse courante :
		-- l'avance de manoeuvre reste a STEER_CRAWL studs/s meme quand la tondeuse monte en regime.
		local walk = humanoid.WalkSpeed
		drive = if walk > 0.1 then math.clamp(MowConfigs.STEER_CRAWL / walk, 0, 1) else 0
	end
	-- DEUX TAUX DE ROTATION, et c'est le coeur du ressenti : en pleine avance on braque franchement ; en simple
	-- manoeuvre on ne fait qu'INFLECHIR la trajectoire, qui part surtout vers l'avant. Au taux plein, une
	-- machine qui avance a peine braquait comme en pleine course : ca se lit comme un pivot sur place, pas
	-- comme une tondeuse qu'on repositionne.
	local steerSign = if MowConfigs.STEER_INVERT then -1 else 1
	-- LA ROTATION VIENT DE LA DISTANCE PARCOURUE, pas du temps. C'est la definition d'un rayon de braquage : a
	-- fond de braquage la machine decrit toujours le meme cercle, qu'elle roule vite ou doucement.
	--
	-- `drive` est une FRACTION de la WalkSpeed (c'est ce que `Humanoid:Move` attend), donc on la multiplie pour
	-- retrouver des studs par seconde. Le braquage partiel reduit l'angle, donc agrandit le rayon -- exactement
	-- comme un volant qu'on ne tourne qu'a moitie.
	local rolling = math.abs(drive) * humanoid.WalkSpeed
	local radius = math.max(MowConfigs.STEER_RADIUS, 0.5)
	local turnRate = math.deg(rolling / radius)
	-- EN MARCHE ARRIERE, ON INVERSE. On se deplace le long de -cap : tourner le cap a droite envoie donc la
	-- machine a GAUCHE. Sans cette inversion, reculer en braquant part du cote oppose a ce que le joueur
	-- demande -- et c'est justement en marche arriere qu'on a le moins de reperes pour s'en remettre.
	-- Le braquage de MANOEUVRE (sans avance) garde le sens normal : on ne recule pas, on repositionne.
	local dirSign = if forwardAmount < -MowConfigs.STEER_MOVE_EPSILON then -1 else 1
	-- Le corps ne tourne QUE s'il roule vraiment : soit le joueur avance, soit l'avance de manoeuvre le fait
	-- rouler. A STEER_CRAWL = 0 on retrouve donc le comportement d'avant (corps fige, machine qui pivote),
	-- comme la config le promet.
	-- Plus besoin de demander si le joueur avance : s'il ne roule pas, `rolling` vaut zero et la machine ne tourne
	-- pas, toute seule. Une tondeuse a l'arret ne pivote pas sur elle-meme.
	if turning then
		yaw -= lateralAmount * steerSign * dirSign * math.rad(turnRate) * dt
		hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, yaw, 0)
		facing = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	end

	-- AVANCE le long du cap. Une valeur NEGATIVE recule, et les roues suivent : leur distance est projetee sur
	-- l'avant de la machine, donc elle est negative elle aussi.
	-- ON RALENTIT POUR TOURNER, comme avec n'importe quelle machine. Braquer a fond en pleine avance donnait un
	-- mouvement trop vif : le joueur filait ET pivotait, ce qui ne ressemble a rien de reel.
	-- Ne s'applique qu'a l'avance REELLE : la manoeuvre est deja lente, la ralentir encore la figerait.
	if braking then
		drive *= 1 - math.abs(lateralAmount) * MowConfigs.TURN_SLOWDOWN
	end
	humanoid:Move(facing * drive, false)

	if MowConfigs.STEER_DEBUG then
		-- MEME formule que le braquage ci-dessus, sinon la courbe affichee ne serait pas celle qu'on suit.
		-- MEME taux que celui reellement applique : une courbe dessinee avec l'autre mentirait sur le trajet.
		local turnPerSec = if turning then lateralAmount * steerSign * dirSign * math.rad(turnRate) else 0
		-- Vitesse MESUREE, pas supposee : la courbe montre alors le trajet reel, y compris si un autre systeme
		-- ralentit le joueur.
		local v = hrp.AssemblyLinearVelocity
		local speed = math.sqrt(v.X * v.X + v.Z * v.Z)
		-- A l'arret on montre quand meme la courbe, sinon on ne pourrait pas regler le braquage sans rouler.
		if speed < 1 then
			speed = MowConfigs.SPEED_MIN
		end
		local yawNow = math.atan2(-facing.X, -facing.Z)
		drawTrail(Vector3.new(hrp.Position.X, hrp.Position.Y - 2, hrp.Position.Z), yawNow, turnPerSec, speed)
	end
end

local function request(model: Model, phase: string)
	if not carryRemote then
		return
	end
	if os.clock() - lastActionAt < MowConfigs.ACTION_DEBOUNCE then
		return -- la touche ET le bouton tactile peuvent tirer ensemble : un seul geste passe
	end
	lastActionAt = os.clock()
	carryRemote:FireServer(model, phase)
end

-- AVANT de la machine, en horizontal. Mesure (RootPart -> CutZone, posee a l'avant sous le carter), jamais devine.
-- Un seul endroit le sait : le point de prise ET le sens de rotation des roues en dependent, et deux calculs
-- separes finiraient par diverger.
local function forwardOf(model: Model): Vector3?
	local root = rootOf(model)
	local zone = model:FindFirstChild(MowConfigs.CUT_ZONE_NAME, true)
	if not (root and zone and zone:IsA("BasePart")) then
		return nil
	end
	local d = zone.Position - root.Position
	d = Vector3.new(d.X, 0, d.Z)
	return if d.Magnitude > 1e-3 then d.Unit else nil
end

-- OU le joueur doit se tenir pour prendre la tondeuse : derriere le point le plus ARRIERE de la machine, face a
-- elle. L'axe d'avancee est MESURE (RootPart -> CutZone, posee a l'avant), jamais devine.
-- Rend le point au sol et la direction a regarder, ou nil si on ne sait pas de quel cote regarde la machine.
local function grabSpot(model: Model): (Vector3?, Vector3?)
	local root = rootOf(model)
	local forward = forwardOf(model)
	if not (root and forward) then
		return nil, nil
	end
	-- Meme geometrie que cote serveur : recul de la machine + l'ecart de confort. On repart du plus loin en
	-- arriere, pas de la racine, sinon on se plante au milieu de la tondeuse.
	local back = 0
	for _, part in ipairs(model:GetDescendants()) do
		if
			part:IsA("BasePart")
			and part.Name ~= MowConfigs.CUT_ZONE_NAME
			and part.Name ~= MowConfigs.HITBOX_NAME
			and part.Transparency < 1
		then
			back = math.max(back, -(part.Position - root.Position):Dot(forward))
		end
	end
	return root.Position - forward * (back + MowConfigs.CARRY_GAP), forward
end

-- APPROCHE : le joueur MARCHE jusqu'au guidon, puis prend. C'est lui qui va a la machine, pas l'inverse.
--
-- Si on est DEJA sur place, on ne fabrique AUCUN deplacement : construire une marche forcee pour un joueur deja
-- arrive a deja coute un systeme entier sur l'echelle. On mesure d'abord, on marche seulement si besoin.
-- PIVOT vers la machine. Sans lui, un joueur venu par l'avant -- ou deja sur place mais regardant ailleurs --
-- prend la tondeuse dos a elle, et la soudure la repose de l'autre cote. On croit alors que la MACHINE a saute
-- devant le joueur, alors que c'est le joueur qui n'etait pas oriente.
local function turnTo(facing: Vector3)
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	if not (part and part:IsA("BasePart")) then
		return
	end
	local root: BasePart = part
	local from = root.CFrame
	local to = CFrame.lookAt(from.Position, from.Position + facing)
	local t0 = os.clock()
	while os.clock() - t0 < MowConfigs.APPROACH_TURN_TIME do
		local a = (os.clock() - t0) / MowConfigs.APPROACH_TURN_TIME
		root.CFrame = from:Lerp(to, a)
		task.wait()
	end
	root.CFrame = to
end

-- Marche jusqu'a un point, ou abandonne au bout de APPROACH_TIMEOUT. Mieux vaut une prise un peu de travers
-- qu'un joueur bloque parce qu'un caillou lui barre le chemin.
local function walkTo(humanoid: Humanoid, point: Vector3)
	local done = false
	local conn = humanoid.MoveToFinished:Connect(function()
		done = true
	end)
	humanoid:MoveTo(point)
	local deadline = os.clock() + MowConfigs.APPROACH_TIMEOUT
	while not done and os.clock() < deadline do
		task.wait()
	end
	conn:Disconnect()
end

local approaching = false

-- APPROCHE : le joueur MARCHE jusqu'au guidon, CONTOURNE la machine s'il arrive par devant, pivote, puis prend.
-- C'est lui qui va a la tondeuse -- elle ne bouge jamais.
--
-- Si on est DEJA sur place, on ne fabrique AUCUN deplacement : construire une marche forcee pour un joueur deja
-- arrive a deja coute un systeme entier sur l'echelle. On mesure d'abord, on marche seulement si besoin.
local function approachThenGrab(model: Model, onArrived: () -> ())
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local spot, facing = grabSpot(model)
	if not (MowConfigs.APPROACH_ENABLED and humanoid and hrp and hrp:IsA("BasePart") and spot and facing) then
		onArrived()
		return
	end

	local hum: Humanoid = humanoid
	local root: BasePart = hrp
	local target: Vector3 = spot
	local look: Vector3 = facing
	local rootModel = rootOf(model)

	approaching = true
	task.spawn(function()
		local flat = Vector3.new(root.Position.X - target.X, 0, root.Position.Z - target.Z)
		if flat.Magnitude > MowConfigs.APPROACH_SKIP_DIST then
			-- CONTOURNEMENT. Le point de prise est DERRIERE la machine : un joueur qui arrive par devant marcherait
			-- droit dedans (et se ferait bloquer, ou la traverserait). On passe donc par un point de COTE d'abord,
			-- du cote ou il se trouve deja -- c'est le chemin le plus court, et il decrit un arc naturel.
			if rootModel then
				local toPlayer = root.Position - rootModel.Position
				toPlayer = Vector3.new(toPlayer.X, 0, toPlayer.Z)
				local inFront = toPlayer:Dot(look) > 0
				if inFront then
					-- Perpendiculaire a l'avant de la machine (rotation de 90 degres : x,z -> -z,x).
					local side = Vector3.new(-look.Z, 0, look.X)
					-- Du cote ou le joueur est deja. Pile en face (produit nul), on en choisit un plutot que zero,
					-- sinon le detour serait nul et on repasserait dans la machine.
					local sign = if toPlayer:Dot(side) >= 0 then 1 else -1
					walkTo(hum, rootModel.Position + side * (sign * MowConfigs.APPROACH_DETOUR))
				end
			end
			walkTo(hum, target)
		end

		-- Le pivot a lieu MEME quand on a saute la marche : c'est lui qui evite que la machine paraisse sauter.
		turnTo(look)
		-- Relache SEULEMENT ici : le pivot fait partie du geste, un second appui pendant qu'il tourne relancerait
		-- une marche par-dessus celle qui vient de finir.
		approaching = false
		onArrived()
	end)
end

-- UN SEUL declencheur pour prendre ET reposer : la meme touche, le meme bouton, le meme anti-spam.
local function toggleCarry()
	local mine = myMower()
	if mine then
		request(mine, "place")
		return
	end
	if approaching then
		return -- deja en train de rejoindre une tondeuse : on ne relance pas la marche par-dessus
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local target = freeMowerNear(hrp.Position)
		if target then
			approachThenGrab(target, function()
				request(target, "grab")
			end)
		end
	end
end

-- La touche n'est branchee QUE quand l'action a un sens (pres d'une tondeuse, ou en train d'en pousser une).
-- createTouchButton fait apparaitre un bouton a l'ecran sur tactile, et bind la touche sur PC, d'un seul geste :
-- sans lui, deposer la tondeuse serait injouable sans clavier.
-- TIRAGE DE CORDE au CLIC. Branche uniquement quand il y a une corde a tirer : une tondeuse deja lancee ne doit
-- pas laisser un bouton a l'ecran, et un clic sans effet apprend au joueur a ne plus cliquer.
-- createTouchButton fait apparaitre un bouton sur tactile ET bind le clic sur PC, d'un seul geste.
local function setPullBound(active: boolean)
	if active == pullBound then
		return
	end
	pullBound = active
	if active then
		ContextActionService:BindAction(MowConfigs.START_ACTION, function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin and pullRemote then
				pullRemote:FireServer()
			end
			return Enum.ContextActionResult.Pass
		end, true, Enum.UserInputType.MouseButton1)
	else
		ContextActionService:UnbindAction(MowConfigs.START_ACTION)
	end
end

local function setActionBound(active: boolean)
	if active == actionBound then
		return
	end
	actionBound = active
	if active then
		ContextActionService:BindAction(ACTION_NAME, function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				toggleCarry()
			end
			return Enum.ContextActionResult.Pass
		end, true, ACTION_KEY)
		-- MAINTENUE, pas une bascule : on jette un oeil, on ne joue pas dedans. Un mode qu'on peut laisser allume
		-- deviendrait le mode NORMAL, et la pelouse ne serait plus jamais regardee pour elle-meme.
		-- End ET Cancel : perdre le focus (alt-tab, une UI qui s'ouvre) doit eteindre, sinon ca reste allume a vie.
		ContextActionService:BindAction(MowConfigs.HIGHLIGHT_ACTION, function(_, state: Enum.UserInputState)
			setReveal(state == Enum.UserInputState.Begin)
			return Enum.ContextActionResult.Pass
		end, true, HIGHLIGHT_KEY)
	else
		ContextActionService:UnbindAction(ACTION_NAME)
		ContextActionService:UnbindAction(MowConfigs.HIGHLIGHT_ACTION)
		-- On s'eloigne la touche enfoncee : sans ca la pelouse resterait allumee pour de bon.
		setReveal(false)
	end
end

-- Le prompt est un SINGLETON partage (dialogue de Papi, echelle, boite aux lettres...). On ne cache donc QUE
-- le notre : appeler hide() sans regarder ferait disparaitre celui d'un autre en plein milieu.
local function hideOurs()
	local anchor = promptAnchor
	if anchor and InteractionPrompt.currentTarget() == anchor then
		InteractionPrompt.hide()
	end
	promptTarget = nil
	promptAnchor = nil
end

local function updatePrompt(hrp: BasePart, carrying: Model?)
	if carrying then
		-- On pousse : plus de badge sur la tondeuse (on est dessus), mais l'action reste branchee pour la reposer.
		hideOurs()
		setActionBound(true)
		return
	end

	local target, root = freeMowerNear(hrp.Position)
	if target and root then
		setActionBound(true)
		-- On re-montre au CHANGEMENT de tondeuse, mais AUSSI quand le prompt ne nous appartient plus : une autre
		-- feature a pu prendre le singleton (un dialogue s'ouvre pendant qu'on est a cote). Sans ce second test,
		-- notre prompt disparaitrait pour de bon alors que rien n'a change de notre point de vue.
		local anchor = promptAnchorOf(target) or root.Position
		if target ~= promptTarget or InteractionPrompt.currentTarget() ~= anchor then
			promptTarget = target
			promptAnchor = anchor
			InteractionPrompt.show(
				anchor,
				MowConfigs.PROMPT_KEY,
				MowConfigs.PROMPT_LABEL,
				MowConfigs.PROMPT_OFFSET,
				toggleCarry,
				MowConfigs.PROMPT_TITLE
			)
		end
	elseif promptTarget then
		hideOurs()
		setActionBound(false)
	else
		setActionBound(false)
	end
end

local function update(dt: number)
	local now = os.clock()
	refreshMowers(now)

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end

	local mine = myMower()

	if now - lastPromptAt >= PROMPT_INTERVAL then
		lastPromptAt = now
		updatePrompt(hrp :: BasePart, mine)
	end

	-- CONDUITE. AutoRotate coupe seulement pendant le portage, et RENDU des qu'on lache : sans ca, un joueur qui
	-- repose sa tondeuse resterait incapable de se tourner, et il chercherait longtemps pourquoi.
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if mine and humanoid and MowConfigs.STEER_ENABLED then
		if not steering then
			steering = true
			autoRotateWas = humanoid.AutoRotate
			humanoid.AutoRotate = false
			-- APRES le personnage dans la MEME image : on ecrase la demande du module de controle avant que la
			-- physique ne la lise. Sur Heartbeat on arrivait apres elle, une image trop tard.
			RunService:BindToRenderStep(STEER_BIND, Enum.RenderPriority.Character.Value + 1, function(step: number)
				local ch = player.Character
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				if hum and root and root:IsA("BasePart") then
					steer(hum, root, step)
				end
			end)
		end
	elseif steering then
		steering = false
		pcall(function()
			RunService:UnbindFromRenderStep(STEER_BIND)
		end)
		clearTrail()
		if humanoid then
			humanoid.AutoRotate = autoRotateWas
		end
	end

	-- UNE MACHINE A L'ARRET NE COUPE RIEN, ET NE SE POUSSE PAS. Tant que la corde n'a pas ete tiree, on tient un
	-- objet, pas une tondeuse. C'est aussi ce qui donne du SENS au demarrage : sans ca, tirer la corde ne serait
	-- qu'une animation de plus.
	--
	-- LU ICI, AU-DESSUS de la sortie anticipee : la camera de demarrage doit etre RELACHEE quand on lache la
	-- machine, et le `return` plus bas empecherait ce relachement -- la camera resterait plantee sur le plan de
	-- tirage, sans plus rien a filmer.
	local running = mine ~= nil and mine:GetAttribute(MowConfigs.RUNNING_ATTRIBUTE) == true
	setPullCam(mine ~= nil and not running)
	-- NOTRE JOYSTICK, tant qu'on pousse la machine. Celui de Roblox cesse de remonter un vecteur des qu'une feature
	-- prend la camera en main -- et la conduite en prend une. Sur mobile, sans lui, le joueur ne bouge pas du tout.
	-- Sur PC il ne s'affiche meme pas : MoveThumb ne fait rien hors tactile.
	if mine then
		MoveThumb.show()
	else
		MoveThumb.hide()
	end
	applyCameraRig(hrp :: BasePart, mine ~= nil)

	if not mine then
		setPullBound(false)
		lastCutPos = nil
		-- ON ETEINT CE QU'ON A ALLUME. Une machine reposee garderait sinon son vent et ses brins d'herbe en vol
		-- pour toujours : les emetteurs vivent sur le MODELE, ils ne partent pas avec le portage.
		local last = emitterModel
		if last then
			setEmitters(last, MowConfigs.WIND_EMITTERS, false)
			setEmitters(last, MowConfigs.CUT_EMITTERS, false)
		end
		return
	end
	setPullBound(not running)

	local point, radius = cutPointOf(mine)
	if not point then
		return
	end

	-- DISTANCE PARCOURUE, a l'horizontale : monter une pente ne doit pas faire tourner les roues plus vite, et
	-- sauter ne doit pas les faire tourner du tout.
	-- SIGNEE : on projette le deplacement sur l'AVANT de la machine. Une distance toujours positive ferait
	-- tourner les roues a l'endroit meme en marche arriere, et l'oeil le voit tout de suite.
	local distance = 0
	if lastCutPos then
		local d = point - lastCutPos
		local flatD = Vector3.new(d.X, 0, d.Z)
		local forward = forwardOf(mine)
		distance = if forward then flatD:Dot(forward) else flatD.Magnitude
	end
	lastCutPos = point

	spinWheels(mine, distance)

	-- LE VENT SOUFFLE QUAND CA AVANCE, moteur en marche. Une machine a l'arret ne souffle pas, et une machine
	-- eteinte encore moins.
	setEmitters(mine, MowConfigs.WIND_EMITTERS, running and math.abs(distance) > 1e-3)
	-- LES BRINS CONTINUENT DE VOLER un court instant apres la derniere touffe. La coupe est intermittente d'une
	-- image a l'autre (un trou dans l'herbe, une touffe deja tondue) : sans ce delai, l'emetteur clignoterait
	-- plusieurs fois par seconde.
	setEmitters(mine, MowConfigs.CUT_EMITTERS, os.clock() - lastCutAt < MowConfigs.CUT_EMITTER_HOLD)
	-- La coupe tourne MEME A L'ARRET : rester sur place finit de tondre la touffe sous le carter, au lieu de laisser
	-- un rond a moitie coupe qu'on ne comprend pas.
	if running then
		local cutNow = GrassZoneController.mowAt(point, radius, dt)
		-- L'HERBE NE VOLE QUE SI ON EN COUPE VRAIMENT. Passer une tondeuse allumee sur du beton ne projette rien --
		-- c'est cette exactitude qui fait qu'on croit a l'effet.
		if cutNow > 0 then
			lastCutAt = os.clock()
		end
	end
end

function MowController.init()
	-- getRemote cache un WaitForChild : en ligne droite dans un init, il gele TOUT le boot le temps du timeout.
	task.spawn(function()
		carryRemote = RemoteSetup.getRemote("SetMowerCarry", "Mow") :: RemoteEvent
		steerRemote = RemoteSetup.getRemote("SetMowSteer", "Mow") :: RemoteEvent
		pullRemote = RemoteSetup.getRemote("PullMowStarter", "Mow") :: RemoteEvent
	end)

	-- On branche la boucle MEME si aucune tondeuse n'est encore la : avec le streaming, "absente au demarrage" est
	-- un etat normal, et un `return` ici ne se rattraperait jamais. Elle sort en trois lignes tant qu'il n'y a rien.
	connection = RunService.Heartbeat:Connect(update)

	-- Nouveau perso : le prompt d'avant pointait sur une position morte, et on ne porte plus rien.
	player.CharacterAdded:Connect(function()
		hideOurs()
		setPullBound(false)
		lastCutPos = nil
		steering = false -- nouveau perso : il arrive avec son AutoRotate, notre etat ne le concerne plus
		setReveal(false)
		setActionBound(false)
	end)
end

function MowController.stop()
	-- Le joystick vit dans PlayerGui, pas dans ce module : sans ce retrait il resterait a l'ecran apres l'arret,
	-- et il continuerait de rendre une valeur que plus personne ne lit.
	MoveThumb.hide()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	setActionBound(false)
	setPullBound(false)
	hideOurs()
	-- On rend la camera : sans ca, arreter le controller laisserait la vue reculee et decalee pour toujours.
	CameraEffects.SetZoomBoost(0)
	if steering then
		steering = false
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.AutoRotate = autoRotateWas
		end
	end
	lastCutPos = nil
	setReveal(false)
end

return MowController
