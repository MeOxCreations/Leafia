--!strict
-- CAMERA DE SCENE. Elle se pose a un endroit FIXE du monde, elle RESPIRE, puis elle rend la main a la camera de
-- jeu sans le moindre saut.
--
-- PRIMITIVE REUTILISABLE : elle ne connait ni la porte, ni le grand-pere, ni aucune scene. On lui donne une
-- CFrame, elle y va. Cinq controllers de ce projet ont chacun leur camera scriptee ; celui-ci existe pour que la
-- SIXIEME soit la derniere a etre ecrite.
--
-- LA RESPIRATION. Camera immobile dans le monde, mais jamais figee : un flottement lent, comme une camera tenue
-- a l'epaule. Ca donne de la vie sans deplacer le cadre -- la porte reste au centre du plan tout du long.
--
-- LE RETOUR VERS LA CAMERA DE JEU EST LE PIEGE, et il a deja coute cher dans ce projet :
--   * Un tween vers une CFrame FIXE plante la camera si le joueur bouge pendant la transition. On RE-ANCRE donc
--     sur sa position VIVE a chaque image.
--   * En repassant de Scriptable a Custom, Custom garde le YAW mais REMET son propre PITCH de repos. Finir sur
--     une valeur devinee laisse un saut sub-perceptible mais bien visible. On MESURE donc l'etat de repos
--     complet (distance, hauteur du focus, inclinaison) A L'ENTREE, et on finit exactement dessus.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SceneCamera = {}

local player = Players.LocalPlayer

local BIND = "LeafiaSceneCamera"

-- ===== Reglages de la respiration =====
-- Amplitude du flottement, en studs. Au-dela de ~0.35 ca cesse de respirer et ca commence a tanguer.
local SWAY_POS = 0.18
-- Roulis, en degres. Tres peu : c'est ce qui fait "tenue a la main" plutot que "posee sur un pied".
local SWAY_ROLL = 0.45
-- TROIS FREQUENCES SANS RAPPORT ENTRE ELLES. Une seule sinusoide se lit comme un balancier de metronome ; trois
-- qui ne retombent jamais ensemble donnent un mouvement qui ne se repete jamais a l'oeil.
local SWAY_A, SWAY_B, SWAY_C = 0.83, 1.27, 0.61

-- ===== LE COUP SEC =====
-- Vitesse de RETOUR du recul. Le depart, lui, est instantane : c'est ce qui en fait un coup et pas une poussee.
-- Plus haut = revient plus vite. En dessous de ~5 le recul traine et on dirait que la camera flotte.
local KICK_DECAY = 9
-- En dessous de ce reste, on met a ZERO. Un retour exponentiel n'atteint JAMAIS sa cible : sans ce clamp la
-- camera garderait un recul minuscule pour toujours, et deux coups d'affilee l'accumuleraient.
local KICK_SNAP = 0.002

-- Durees par defaut. Chaque appel peut imposer les siennes.
local ENTER_TIME = 0.8
local EXIT_TIME = 0.7

type Mode = "off" | "enter" | "hold" | "exit"

local mode: Mode = "off"
local bound = false
local elapsed = 0
local phase = 0
local target = CFrame.identity
local kick = 0
local startCF = CFrame.identity
local enterSeconds = ENTER_TIME
local exitSeconds = EXIT_TIME
local onArrived: (() -> ())? = nil
local onLeft: (() -> ())? = nil
-- Vue EXACTE au moment ou la sortie commence. Partir de la garantit qu'il n'y a aucun a-coup au depart : le
-- premier point du glissement est litteralement l'image qu'on avait a l'ecran.
local exitFrom = Vector3.zero
local exitLookAt = Vector3.zero
-- Direction camera -> joueur a la sortie, figee au depart. La recalculer chaque image la ferait tourner avec le
-- flottement de la fin de scene, et l'arrivee vibrerait.
local exitOffset = Vector3.zero

-- Etat de repos de la camera de JEU, mesure a l'entree. C'est la-dessus que la sortie doit finir, sinon le
-- passage en Custom se voit.
local restDistance = 12.5
local restFocusHeight = 1.4
local restPitch = math.rad(15)

local function getRoot(): BasePart?
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

-- Le flottement, applique PAR-DESSUS la pose de base. Il ne touche jamais a la cible : couper la respiration
-- laisse donc la camera exactement ou la scene l'a demandee.
local function breathe(base: CFrame): CFrame
	local x = math.sin(phase * SWAY_A) * SWAY_POS + math.sin(phase * SWAY_B + 1.3) * SWAY_POS * 0.4
	local y = math.sin(phase * SWAY_C + 0.7) * SWAY_POS * 0.7
	local roll = math.sin(phase * SWAY_B + 2.1) * SWAY_ROLL
	-- Le recul part sur le +Z de la CAMERA, qui est son arriere. En repere camera et pas en repere monde : le
	-- coup doit reculer quel que soit l'endroit ou elle regarde, sans qu'on ait a connaitre son orientation.
	return base * CFrame.new(x, y, kick) * CFrame.Angles(0, 0, math.rad(roll))
end

local function unbind()
	if bound then
		RunService:UnbindFromRenderStep(BIND)
		bound = false
	end
end

local function handBackToGame()
	local camera = Workspace.CurrentCamera
	if camera then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		camera.CameraType = Enum.CameraType.Custom
	end
	mode = "off"
	unbind()
	local done = onLeft
	onLeft = nil
	if done then
		done()
	end
end

local function stepCamera(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	-- La respiration avance TOUJOURS, meme pendant les transitions : la couper puis la reprendre se verrait
	-- comme un a-coup pile au moment ou l'oeil se pose sur le plan.
	phase += dt
	elapsed += dt
	-- LE RECUL REVIENT TOUT SEUL, en exponentielle : franc au depart, de plus en plus doux. Cale a zero des
	-- qu'il est negligeable -- une exponentielle n'atteint jamais sa cible, et deux coups d'affilee
	-- accumuleraient ce reste.
	if kick ~= 0 then
		kick -= kick * math.min(1, KICK_DECAY * dt)
		if math.abs(kick) < KICK_SNAP then
			kick = 0
		end
	end

	if mode == "enter" then
		local t = if enterSeconds > 0 then math.clamp(elapsed / enterSeconds, 0, 1) else 1
		local e = 1 - (1 - t) * (1 - t) -- ease out
		camera.CFrame = breathe(startCF:Lerp(target, e))
		if t >= 1 then
			mode = "hold"
			local done = onArrived
			onArrived = nil
			if done then
				done()
			end
		end
		return
	end

	if mode == "hold" then
		camera.CFrame = breathe(target)
		return
	end

	if mode == "exit" then
		local root = getRoot()
		if not root then
			handBackToGame() -- perso detruit en plein fondu : on rend la main tout de suite
			return
		end
		local t = if exitSeconds > 0 then math.clamp(elapsed / exitSeconds, 0, 1) else 1
		local e = 1 - (1 - t) * (1 - t)
		-- LA CIBLE EST RECALCULEE A CHAQUE IMAGE sur la position VIVE du joueur. Une CFrame calculee une seule
		-- fois laisserait la camera plantee derriere lui s'il repart pendant la transition.
		local focus = root.Position + Vector3.new(0, restFocusHeight, 0)
		local camPos = focus + exitOffset * restDistance
		-- ON INTERPOLE LA POSITION ET LE POINT VISE SEPAREMENT, jamais la CFrame entiere. Lerper une CFrame fait
		-- passer la camera par des orientations qui n'existent sur aucun des deux plans : elle plonge en chemin.
		--
		-- Plus de respiration ici : elle ferait trembler l'image a l'instant precis ou la camera de jeu reprend,
		-- donc pile la ou un saut se remarque.
		camera.CFrame = CFrame.lookAt(exitFrom:Lerp(camPos, e), exitLookAt:Lerp(focus, e))
		if t >= 1 then
			handBackToGame()
		end
	end
end

local function bind()
	if bound then
		return
	end
	bound = true
	-- Priorite Camera : c'est le moment de l'image ou une camera scriptee doit ecrire, apres que tout le reste a
	-- bouge et avant le rendu.
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value, stepCamera)
end

--- Prend la camera et l'amene a `cf`, puis la tient la en respirant. `onDone` est appele QUAND ELLE EST ARRIVEE :
--- c'est la que la scene commence, pas au moment de l'appel.
function SceneCamera.enter(cf: CFrame, seconds: number?, onDone: (() -> ())?)
	local camera = Workspace.CurrentCamera
	if not camera then
		if onDone then
			onDone()
		end
		return
	end

	-- ON MESURE L'ETAT DE REPOS DE LA CAMERA DE JEU AVANT de passer en Scriptable. Les trois valeurs ne se
	-- devinent pas : une distance approximee ou une inclinaison supposee laisse un saut au retour. On garde les
	-- precedentes si la mesure n'a pas de sens (camera collee au sujet, perso pas encore la).
	local root = getRoot()
	if root then
		local focus = camera.Focus.Position
		local pos = camera.CFrame.Position
		local off = pos - focus
		if off.Magnitude > 1 then
			restDistance = off.Magnitude
			restFocusHeight = focus.Y - root.Position.Y
			restPitch = math.asin(math.clamp(off.Y / off.Magnitude, -1, 1))
		end
	end

	startCF = camera.CFrame
	target = cf
	enterSeconds = seconds or ENTER_TIME
	elapsed = 0
	onArrived = onDone
	mode = "enter"
	camera.CameraType = Enum.CameraType.Scriptable
	bind()
end

--- Rend la main a la camera de jeu, en glissant. `onDone` est appele une fois Custom repris.
function SceneCamera.exit(seconds: number?, onDone: (() -> ())?)
	if mode == "off" then
		if onDone then
			onDone()
		end
		return
	end
	local camera = Workspace.CurrentCamera
	if camera then
		local cf = camera.CFrame
		exitFrom = cf.Position
		-- Ce que la camera regarde MAINTENANT, projete a la distance de repos : le glissement part donc de la
		-- vue reelle, pas d'un point approxime.
		exitLookAt = cf.Position + cf.LookVector * restDistance
		-- Direction depuis laquelle la camera de jeu regarde le joueur : son cap horizontal actuel, releve de
		-- l'inclinaison de repos mesuree a l'entree.
		local flat = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		exitOffset = (-flat) * math.cos(restPitch) + Vector3.new(0, 1, 0) * math.sin(restPitch)
	end
	exitSeconds = seconds or EXIT_TIME
	elapsed = 0
	onLeft = onDone
	mode = "exit"
	bind()
end

--- UN COUP SEC vers l'arriere, qui revient tout seul. Pour accompagner un impact -- un coup frappe a une porte.
--- Le recul est INSTANTANE et le retour progressif : l'inverse donnerait une poussee, pas un choc.
---
--- Les coups s'ADDITIONNENT : trois coups rapproches reculent plus que trois coups espaces, ce qui est
--- exactement ce que fait une vraie camera qu'on bouscule.
function SceneCamera.kick(studs: number)
	kick += studs
end

--- Coupe tout et rend la camera IMMEDIATEMENT. Pour les cas ou il n'y a plus rien a menager : mort, teleport,
--- arret du controller.
function SceneCamera.abort()
	if mode == "off" then
		return
	end
	onArrived = nil
	kick = 0
	handBackToGame()
end

--- Vrai tant que la camera appartient a une scene. Sert a ne pas en lancer une par-dessus une autre.
function SceneCamera.isActive(): boolean
	return mode ~= "off"
end

return SceneCamera
