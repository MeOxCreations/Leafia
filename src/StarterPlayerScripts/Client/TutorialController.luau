--!strict
-- DIDACTICIEL, cote client : ce qui GUIDE le joueur. Pendant de TutorialService, qui le pose deja face a la
-- maison du grand-pere.
--
-- Deux choses, dans cet ordre :
--   1. Un HALO QUI RESPIRE sur la porte. Il dit "viens ici" sans ecrire une consigne -- donc sans rien a
--      traduire, et sans interface posee par-dessus le monde.
--   2. Un PROMPT quand on arrive devant. C'est lui qui lance la mission.
--
-- Une fois la mission lancee, les deux s'eteignent POUR DE BON : le guidage a fait son travail, et un halo qui
-- continue de battre pendant la scene tirerait l'oeil hors du plan.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)
local Letterbox = require(ReplicatedStorage.Modules.UI.Core.Letterbox)
local Dialogue = require(ReplicatedStorage.Modules.UI.Core.Dialogue)
local SoundDuck = require(ReplicatedStorage.Modules.UI.Core.SoundDuck)
local StarBurst = require(ReplicatedStorage.Modules.UI.Core.StarBurst)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local TaskBannerHandler = require(ReplicatedStorage.Modules.UI.Task.TaskBannerHandler)
local WorldMarker = require(ReplicatedStorage.Modules.UI.Core.WorldMarker)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local TutorialConfigs = require(ReplicatedStorage.Modules.Configs.TutorialConfigs)
local CameraEffects = require(script.Parent.Utils.CameraEffects)
local CharacterFade = require(script.Parent.Utils.CharacterFade)
local SceneCamera = require(script.Parent.Utils.SceneCamera)

local player = Players.LocalPlayer

local TutorialController = {}

local door: Model? = nil
local highlight: Highlight? = nil
local anchor: BasePart? = nil
-- Point vise par le prompt : le CENTRE de la porte, pas sa PrimaryPart. Celle-ci est le "Handle", la CHARNIERE
-- posee sur le COTE, donc le badge sortait a cote de la porte. Le centre de la boite englobante ne depend
-- d'aucun choix de PrimaryPart, et il reste juste meme si on en change dans Studio.
local anchorPos = Vector3.zero
-- Cadrage d'ENTREE de la scene, retenu pour pouvoir avancer DEPUIS lui quand la porte s'ouvre. Relire la camera
-- a ce moment-la ne marcherait pas : elle porte le flottement de la respiration, et le rapprochement partirait
-- d'un ecart aleatoire, different a chaque partie.
local sceneCF: CFrame? = nil
local lastScanAt = 0
local lastPromptAt = 0
local lastDebugAt = 0
local startedAt = 0
-- UN DRAPEAU PAR AVERTISSEMENT, pas un seul pour les deux. Partage, le premier manquant masque le second : la
-- porte absente ferait taire le message du Highlight absent, et on chercherait au mauvais endroit.
local warnedNoDoor = false
local warnedNoHighlight = false
local elapsed = 0
local doorHint = true
-- Le point d'exclamation au-dessus de la porte. `nil` = pas affiche.
local doorMarker: Frame? = nil
local missionStarted = false
local sceneEnded = false
local controls: any = nil -- ControlModule du PlayerModule, pour couper les deplacements pendant la scene
local fadeBound = false -- la boucle qui repose la transparence a chaque image tourne-t-elle ?
local grandpaTrack: AnimationTrack? = nil
-- Angle courant de la porte, en degres (0 = fermee). Une seule valeur : la sequence n'est qu'un enchainement de
-- cibles, et repartir en plein mouvement ne demande donc aucun cas particulier.
-- Resolu EN TACHE DE FOND au demarrage : `getRemote` cache un `WaitForChild`, et l'appeler en ligne droite dans
-- un `init` gele tout le boot le temps de son timeout. Le piege est note dans le journal du projet.
local sceneDoneRemote: RemoteEvent? = nil

-- LES SONS DE LA SCENE SONT JOUES EN 2D, pas dans le monde. `nil` en hote = pas de part, donc pas de distance,
-- pas d'attenuation : le son arrive a plein volume quoi qu'il arrive.
--
-- Ils etaient poses SUR LA PORTE. Deux raisons de ne pas le faire, et la seconde compte plus que la premiere :
--   1. l'auditeur de Roblox est la CAMERA, et pendant la scene elle est a douze studs en arriere -- les coups
--      s'entendaient donc de loin, alors qu'ils sont le sujet du plan ;
--   2. dans une scene cinematique, le son se MIXE, il ne se simule pas. On vient justement de baisser tout le
--      reste du jeu pour tourner l'oreille vers la scene : y laisser une attenuation de distance revient a
--      defaire ce qu'on vient de faire.
--
-- Une constante nommee plutot qu'un `nil` nu aux trois appels : `play(son, nil)` ne dit pas POURQUOI il n'y a pas
-- d'hote, et le prochain qui passe le "corrigerait" en remettant la porte.
local SCENE_2D: BasePart? = nil

local doorAngle = 0
-- Sa pose FERMEE, relevee UNE FOIS a l'ouverture. On ne peut pas la relire ensuite : le gond fait partie du
-- modele, donc il tourne avec lui -- relire le pivot ferait tourner la porte a partir d'une base deja tournee, et
-- l'angle s'accumulerait.
local doorBasePivot: CFrame? = nil
-- Jeton du mouvement en cours. Un nouveau mouvement annule le precedent : deux boucles ecriraient sur le meme
-- modele a chaque image, et la pose finale serait celle de la derniere a FINIR, pas de la derniere demandee.
local doorSwingToken = 0
local knockTrack: AnimationTrack? = nil
local knockAsideTrack: AnimationTrack? = nil -- le pas de cote, joue quand le grand-pere se met en marche
-- REMPLIE PLUS BAS. `endScene` est defini AVANT les fonctions d'animation, et c'est pourtant lui qui declenche
-- le pas de cote : c'est le seul endroit qui sait quand le grand-pere part. Une variable de fonction evite de
-- deplacer tout un bloc pour un seul appel, et l'appel reste garde par un test.
local playAside: (() -> ())? = nil
local holdConns: { RBXScriptConnection } = {} -- surveillent la fin des pistes tenues, pour les figer
local shakeTrack: AnimationTrack? = nil
local tryTrack: AnimationTrack? = nil
-- Surveille la fin de l'animation d'ouverture, pour la figer avant qu'elle ne reboucle.
local trySound: Sound? = nil
-- Emetteurs et eclairs de l'impact, resolus une seule fois puis gardes. `nil` = pas encore cherches.
local knockEmitters: { ParticleEmitter }? = nil
-- Le conteneur lui-meme, retenu a la resolution : c'est LUI qui donne le point d'impact a l'ecran. Le relire par
-- son nom a chaque coup couterait un balayage du Workspace pour une valeur qui ne bouge pas.
local knockHolder: Instance? = nil
local promptShown = false
local actionBound = false
local conn: RBXScriptConnection? = nil

local function getRoot(): BasePart?
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

-- La porte, ou nil. RECHERCHE PAR NOM dans tout le Workspace, jamais par un chemin fixe : elle a deja demenage
-- une fois et elle redemenagera, et un chemin en dur transforme chaque rangement dans l'editeur en panne
-- silencieuse. Le balayage ne tourne QUE tant qu'elle n'est pas trouvee.
local function findDoor(): (Model?, BasePart?)
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == TutorialConfigs.DOOR_NAME then
			-- Reference FIXE, jamais GetPivot : le pivot d'un Model suit sa bounding box, donc ajouter la
			-- moindre part enfant le decale et le prompt part de travers sans que rien ne le signale.
			local part = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart", true)
			-- ON N'ACCEPTE QUE CE QUI EST UTILISABLE. Une porte sans aucune part ne sert a rien : soit ses parts
			-- ne sont pas encore repliquees (streaming), soit c'est un autre Model qui porte le meme nom. Dans
			-- les deux cas on continue de chercher au lieu de se figer sur elle.
			if part then
				return d, part
			end
		end
	end
	return nil, nil
end

-- ON RETIRE NOTRE DEMANDE, on ne cache pas la pilule. `hide()` jette les demandes de TOUT LE MONDE : une
-- feature voisine encore a portee ne reviendrait jamais. `release` ne touche que la notre, et le module
-- redonne aussitot la place au meilleur candidat restant.
local function hideOurs()
	if promptShown then
		InteractionPrompt.release(anchorPos)
	end
	promptShown = false
end

-- La touche n'est branchee QUE quand l'action a un sens. createTouchButton fait apparaitre un bouton a l'ecran
-- sur tactile ET bind la touche sur PC : sans lui, le didacticiel serait infranchissable sans clavier.
local function setActionBound(active: boolean)
	if active == actionBound then
		return
	end
	actionBound = active
	if active then
		ContextActionService:BindAction(TutorialConfigs.ACTION_NAME, function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				-- Lu au moment de l'appui, donc bien apres que le module soit charge : pas d'appel au-dessus
				-- d'une definition, c'est le champ qui est resolu a l'usage.
				TutorialController.startMission()
			end
			-- Pass et pas Sink : E est partagee avec le seau et la tondeuse. Avaler l'input ici les casserait.
			return Enum.ContextActionResult.Pass
		end, true, TutorialConfigs.ACTION_KEY)
	else
		ContextActionService:UnbindAction(TutorialConfigs.ACTION_NAME)
	end
end

--- Allume ou eteint le halo de la porte. A appeler avec `false` quand la scene se lance : un halo qui continue
--- de respirer pendant une cinematique tire l'oeil hors du plan.
function TutorialController.setDoorHint(on: boolean)
	doorHint = on
	local halo = highlight
	if halo and halo.Parent and not on then
		halo.FillTransparency = TutorialConfigs.FILL_MAX
	end
end

-- CADRAGE DE LA SCENE. Une part posee dans Studio a le dernier mot ; sinon on cadre depuis le JOUEUR, qui fait
-- deja face a la porte. Se placer "devant la porte" supposerait de savoir quel axe du Model est son devant --
-- rien ne le garantit, ca vient du rig.
-- DEVANT DE LA PORTE, a l'horizontale. Deduit de sa GEOMETRIE : une porte est un panneau plat, donc son cote le
-- plus mince est sa normale -- exactement le raisonnement des roues de la tondeuse.
--
-- Le SENS vient du joueur : il est forcement dehors, donc la moitie qui pointe vers lui est le dehors. Ca evite
-- d'avoir a orienter le modele d'une facon precise dans Studio, et ca survit a un retournement de la porte.
local function doorOutward(): Vector3?
	local model = door
	local root = getRoot()
	if not (model and root) then
		return nil
	end
	local cf, size = model:GetBoundingBox()
	-- On IGNORE la verticale : une porte est haute, Y ne sera jamais le plus mince, et un axe vertical ne serait
	-- de toute facon pas une direction ou se placer.
	local normal = if size.X <= size.Z then cf.RightVector else cf.LookVector
	local flat = Vector3.new(normal.X, 0, normal.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	flat = flat.Unit
	-- Vers le joueur : c'est lui qui dit de quel cote est le dehors.
	local toPlayer = (root.Position - anchorPos) * Vector3.new(1, 0, 1)
	if toPlayer:Dot(flat) < 0 then
		flat = -flat
	end
	return flat
end

-- LE CADRAGE VIENT DE LA PORTE, PAS DU JOUEUR.
--
-- Il partait de `root.CFrame.LookVector` : declencher la scene DE PROFIL posait donc la camera sur le cote, et
-- toute la mise en scene -- le plan, la porte, le grand-pere -- se jouait hors champ. Le joueur peut declencher
-- sous n'importe quel angle, la detection etant radiale : le cadrage ne doit donc rien lui devoir.
local function sceneCFrame(): CFrame?
	local placed = Workspace:FindFirstChild(TutorialConfigs.SCENE_CAM_NAME, true)
	if placed and placed:IsA("BasePart") then
		return placed.CFrame
	end
	local outward = doorOutward()
	if not outward then
		return nil
	end
	local side = outward:Cross(Vector3.new(0, 1, 0))
	local pos = anchorPos
		+ outward * TutorialConfigs.SCENE_CAM_BACK
		+ Vector3.new(0, TutorialConfigs.SCENE_CAM_UP, 0)
		+ side * TutorialConfigs.SCENE_CAM_SIDE
	return CFrame.lookAt(pos, anchorPos + Vector3.new(0, TutorialConfigs.SCENE_LOOK_UP, 0))
end

-- FAIT AVANCER OU RECULER LA CAMERA DE SCENE le long de son propre axe, depuis le plan de depart.
--
-- Toujours depuis `sceneCF` et jamais depuis la vue courante : les mouvements s'ADDITIONNERAIENT sinon, et un
-- recul apres une approche finirait plus loin ou plus pres selon l'ordre dans lequel ils se sont enchaines.
-- Ici chaque etape dit ou elle veut etre, en absolu.
local function pushScene(distance: number, seconds: number)
	local base = sceneCF
	if not base then
		return
	end
	-- Le point vise ne bouge PAS : on avance sur l'axe, donc le cadrage se resserre sans changer de sujet. Un
	-- deplacement qui change aussi la cible se lirait comme un autre plan.
	local target = anchorPos + Vector3.new(0, TutorialConfigs.SCENE_LOOK_UP, 0)
	local toward = target - base.Position
	local dist = toward.Magnitude
	if dist < 1e-3 then
		return
	end
	-- ON NE TRAVERSE JAMAIS LE SUJET. Sans cette borne, une approche trop forte -- ou un grand-pere pose plus pres
	-- que prevu -- ferait passer la camera au travers de lui.
	local step = math.clamp(distance, -math.huge, math.max(dist - TutorialConfigs.REVEAL_MIN_DIST, 0))
	SceneCamera.moveTo(CFrame.lookAt(base.Position + toward.Unit * step, target), seconds)
end

-- REPLACE LE JOUEUR DEVANT LA PORTE, face a elle.
--
-- Sans ca il toque dans la direction ou il regardait en appuyant : de profil, sur le mur ; de dos, dans le vide.
-- On GLISSE au lieu de teleporter -- le trajet est court et il se joue pendant que les barres descendent, donc
-- personne ne le regarde, mais un saut instantane se remarque toujours.
local function placeAtDoor()
	local outward = doorOutward()
	local root = getRoot()
	if not (outward and root) then
		return
	end
	local target = anchorPos + outward * TutorialConfigs.SCENE_PLACE_DIST
	-- On garde SA hauteur : le sol devant la porte n'est pas forcement au niveau du centre de la porte, et poser
	-- le joueur a la hauteur de l'ancre l'enfoncerait ou le ferait flotter.
	local to = CFrame.lookAt(Vector3.new(target.X, root.Position.Y, target.Z), Vector3.new(anchorPos.X, root.Position.Y, anchorPos.Z))
	local from = root.CFrame
	local seconds = TutorialConfigs.SCENE_PLACE_TIME
	if seconds <= 0 then
		root.CFrame = to
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local e = math.clamp((os.clock() - t0) / seconds, 0, 1)
			local live = getRoot()
			if not live then
				return -- mort ou respawn : ce trajet ne concerne plus personne
			end
			-- `Lerp` sur une CFrame interpole la position ET l'orientation d'un seul geste, par le chemin le plus
			-- court : le joueur pivote en avancant, il ne fait pas les deux l'un apres l'autre.
			live.CFrame = from:Lerp(to, e * e * (3 - 2 * e))
			if e >= 1 then
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

-- LE JOUEUR S'EFFACE PENDANT LA SCENE. On regarde le grand-pere, pas son propre dos.
--
-- `LocalTransparencyModifier` et pas `Transparency` : ca ne se replique pas, donc en co-op les autres continuent
-- de voir un personnage normal. Et ca s'AJOUTE a la transparence du jeu au lieu de l'ecraser -- il n'y a aucune
-- valeur d'origine a memoriser pour pouvoir la rendre.
local fadeToken = 0
local fadeNow = 0

-- ON REPOSE LA TRANSPARENCE A CHAQUE IMAGE, ET C'EST OBLIGATOIRE.
--
-- Le controleur de transparence du PlayerModule ecrit `LocalTransparencyModifier` sur toutes les parts du
-- personnage EN CONTINU. Une valeur posee une seule fois est donc ecrasee des l'image suivante : on demandait
-- l'invisibilite, elle tenait une frame, et le joueur restait visible sans qu'aucune erreur ne le dise.
--
-- `force` est indispensable ici : sans lui, le garde-fou "meme valeur qu'avant" de CharacterFade nous ferait
-- sauter l'ecriture -- c'est-a-dire exactement celle qui reprend la main sur Roblox.
--
-- UN SEUL ECRIVAIN : cette boucle est la seule a appeler CharacterFade. `fadePlayer` et `fadePlayerTo` ne font
-- que poser `fadeNow`. Deux ecrivains sur la meme propriete finissent toujours par se contredire.
-- APRES ROBLOX, ET C'EST TOUT L'INTERET. `RenderStepped:Connect` ne garantit AUCUN ordre : notre ecriture peut
-- tomber avant celle du controleur de transparence, qui l'ecrase aussitot -- on reposerait la valeur a chaque
-- image pour rien. `BindToRenderStep` a `Camera + 1` nous place explicitement APRES lui.
-- (Meme reglage que FirstPersonController, qui se bat contre le meme adversaire.)
local FADE_BIND = "LeafiaTutorialFade"

local function stopFadeHold()
	if not fadeBound then
		return
	end
	fadeBound = false
	RunService:UnbindFromRenderStep(FADE_BIND)
end

local function holdFade()
	if fadeBound then
		return
	end
	fadeBound = true
	RunService:BindToRenderStep(FADE_BIND, Enum.RenderPriority.Camera.Value + 1, function()
		local character = player.Character
		if not character then
			return -- mort ou respawn : le prochain fondu rebranchera sur le nouveau personnage
		end
		if fadeNow <= 0.001 then
			-- ARRIVE A ZERO : on rend la main a Roblox et on arrete de tourner. Laisser la boucle vivre couterait
			-- une ecriture par image sur une vingtaine de parts pour rien.
			CharacterFade.apply(character, 0, 0, true)
			stopFadeHold()
			return
		end
		CharacterFade.apply(character, fadeNow, fadeNow, true)
	end)
end

local function fadePlayer(amount: number)
	-- Toute nouvelle demande annule la precedente : deux fondus en cours ecriraient sur les memes parts a chaque
	-- image, et la valeur finale serait celle du dernier a FINIR, pas du dernier demande.
	fadeToken += 1
	fadeNow = amount
	if amount <= 0.001 then
		local character = player.Character
		if character then
			CharacterFade.apply(character, 0, 0, true)
		end
		stopFadeHold()
		return
	end
	holdFade()
end

-- Meme chose, mais EN FONDU. Passer d'une silhouette a l'invisible d'un coup se voit : une forme qui disparait
-- d'un claquement attire justement l'oeil sur elle, au moment ou l'on veut qu'il aille ailleurs.
local function fadePlayerTo(amount: number, seconds: number)
	fadeToken += 1
	local token = fadeToken
	local from = fadeNow
	if seconds <= 0 or math.abs(amount - from) < 0.001 then
		fadePlayer(amount)
		return
	end
	holdFade()
	task.spawn(function()
		local t0 = os.clock()
		while fadeToken == token do
			local e = math.clamp((os.clock() - t0) / seconds, 0, 1)
			if not player.Character then
				return -- mort ou respawn : le personnage a change, ce fondu ne le concerne plus
			end
			-- ON NE FAIT QUE BOUGER LA VALEUR. C'est `holdFade` qui l'ecrit, a chaque image et en force.
			fadeNow = from + (amount - from) * e
			if e >= 1 then
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

-- ===== LE JOUEUR NE BOUGE PAS PENDANT LA SCENE =====
--
-- Sans ca il continue de marcher sous une camera qui ne le suit plus : il sort du cadre, se retrouve dans le
-- decor, et une cinematique se transforme en bug. Le personnage est deja rendu transparent, mais transparent ne
-- veut pas dire immobile.
--
-- ON COUPE LE ControlModule, on ne touche PAS a `WalkSpeed`. C'est CharacterService qui en est le seul
-- proprietaire : y ecrire ici les ferait se battre, et le premier qui repasse gagne. Couper les controles
-- s'attaque a l'ENTREE (clavier, manette, joystick tactile) au lieu de la consequence, donc rien d'autre n'a
-- besoin d'etre au courant. Bonus : le saut part avec, ce qu'un WalkSpeed a zero ne bloque pas.
--
-- Resolu PARESSEUSEMENT, jamais au boot : `require(PlayerModule)` peut yield 10 a 20 s dans une place secondaire
-- comme le tuto. Ici on n'appelle qu'au moment ou le joueur declenche la scene -- PlayerModule est pret depuis
-- longtemps, et `FindFirstChild` rend la main tout de suite.
-- Le ControlModule, s'il existe. FACULTATIF, et c'est important : le blocage repose sur ContextActionService,
-- qui ne depend d'aucun module. Couper le ControlModule en plus ne sert qu'a arreter net une touche deja tenue.
--
-- ON NE PREVIENT PAS QUAND IL MANQUE. Il manque pour de bon dans certaines places (aucun PlayerModule dans
-- StarterPlayerScripts), et ca ne casse rien : le verrou tient, et  a ses propres secours pour la
-- lecture des deplacements (joystick maison, , puis WASD en direct). Un warning sur un
-- cas NORMAL et sans action possible finit par etre ignore, et il emmene les vrais avec lui.
local function getControls(): any
	if controls then
		return controls
	end
	local scripts = player:FindFirstChild("PlayerScripts")
	local playerModule = scripts and scripts:FindFirstChild("PlayerModule")
	if not playerModule then
		return nil
	end
	local ok, result = pcall(function()
		return require(playerModule):GetControls()
	end)
	if ok then
		controls = result
	end
	return controls
end

-- DEUXIEME VERROU, et il ne depend de RIEN. Couper le ControlModule suppose que le PlayerModule se comporte comme
-- celui de Roblox -- or le notre est un module CUSTOM pose dans Studio, dont on sait deja qu'il rend du vide dans
-- certains contextes (voir le secours clavier de HedgeController). Un verrou qui repose sur lui peut donc echouer
-- en silence, et c'est exactement ce qui est arrive.
--
-- ContextActionService intercepte les actions de deplacement AVANT qu'elles n'atteignent le moindre module de
-- controle. On les avale (`Sink`) : clavier, manette et joystick tactile passent tous par la, quel que soit le
-- PlayerModule installe. Le saut est dans le lot.
local FREEZE_ACTION = "LeafiaTutorialFreeze"

local function sinkMovement(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function freezePlayer()
	-- PRIORITE HAUTE : les actions de deplacement sont liees par le PlayerModule lui-meme. A priorite egale c'est
	-- le dernier lie qui gagne, ce qui dependrait de l'ordre de chargement -- donc du hasard.
	ContextActionService:BindActionAtPriority(
		FREEZE_ACTION,
		sinkMovement,
		false, -- pas de bouton tactile : on BLOQUE une action, on n'en propose pas une
		Enum.ContextActionPriority.High.Value,
		Enum.PlayerActions.CharacterForward,
		Enum.PlayerActions.CharacterBackward,
		Enum.PlayerActions.CharacterLeft,
		Enum.PlayerActions.CharacterRight,
		Enum.PlayerActions.CharacterJump
	)

	-- EN PLUS, quand il existe. Le blocage ne repose pas dessus : voir getControls.
	local ctrls = getControls()
	if ctrls then
		ctrls:Disable()
	end
end

local function unfreezePlayer()
	ContextActionService:UnbindAction(FREEZE_ACTION)
	local ctrls = getControls()
	if ctrls then
		ctrls:Enable()
	end
end

-- Rend la main au joueur : la camera glisse vers la vue de jeu pendant que les barres repartent dans les bords.
-- Idempotent : la fin normale (l'animation du grand-pere s'acheve) et le filet de secours peuvent tirer tous les
-- deux, et le second ne doit pas relancer une sortie deja en cours.
-- Cherche un Model par son NOM, comme la porte : on ne suppose aucun rangement.
-- Comme findModel, mais SANS CONDITION DE CLASSE. Un conteneur d'effets peut etre un Folder, un Model ou une
-- PART -- rien ne l'impose, et c'est ce qui vient de casser : on n'acceptait que Model ou Folder, et
-- `KnockEffect1` est une part. Le filtre etait plus strict que la realite, donc il ne trouvait rien.
--
-- Regle : quand on cherche un objet POSE PAR QUELQU'UN dans Studio, on cherche par son NOM. Sa classe est un
-- detail de rangement, pas une garantie.
local function findByName(name: string): Instance?
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
	return nil
end

-- LE DERNIER PLAN : le joueur ET le grand-pere, vus d'un peu au-dessus.
--
-- On cadre le TRAJET, pas le marcheur : on vise le milieu entre le joueur et le point d'arrivee du grand-pere,
-- et on recule d'autant qu'ils sont ecartes. Le plan n'a donc rien a suivre -- l'action entre dedans toute seule
-- et la respiration de la camera reste intacte.
local function exitShotCFrame(): CFrame?
	local root = getRoot()
	if not root then
		return nil
	end
	local walkTo = findByName(TutorialConfigs.OLDMAN_WALK_TARGET)
	-- Pas de point d'arrivee pose dans Studio : on se rabat sur la porte. Le plan est alors plus serre, mais il
	-- existe -- mieux qu'une camera qui rend la main d'un coup parce qu'une part manque.
	local endPos = if walkTo and walkTo:IsA("BasePart") then walkTo.Position else anchorPos
	local mid = (root.Position + endPos) * 0.5

	-- L'AXE DU TRAJET, a plat. C'est la ligne que le grand-pere va parcourir, et c'est elle qui donne le cadre.
	local axis = (endPos - root.Position) * Vector3.new(1, 0, 1)
	if axis.Magnitude < 1e-3 then
		-- Les deux points confondus (point d'arrivee manquant, ou colle au joueur) : on se rabat sur l'axe de la
		-- porte, qui existe toujours.
		local outward = doorOutward()
		if not outward then
			return nil
		end
		axis = outward
	end
	axis = axis.Unit

	-- PERPENDICULAIREMENT : on regarde EN TRAVERS du trajet, pas dans son axe. Dans l'axe de la porte, la camera
	-- reculait droit dans le mur de la maison.
	local across = axis:Cross(Vector3.new(0, 1, 0))
	if TutorialConfigs.EXIT_SHOT_INVERT then
		across = -across
	end

	local spread = (root.Position - endPos).Magnitude
	local back = math.max(TutorialConfigs.EXIT_SHOT_MIN_BACK, spread * TutorialConfigs.EXIT_SHOT_SPREAD)
	local pos = mid
		+ across * back
		+ Vector3.new(0, TutorialConfigs.EXIT_SHOT_UP, 0)
		-- Le long du trajet : decale le cadre vers l'arrivee pour laisser de la place devant le marcheur.
		+ axis * TutorialConfigs.EXIT_SHOT_SIDE
	return CFrame.lookAt(pos, mid + Vector3.new(0, TutorialConfigs.EXIT_SHOT_LOOK_UP, 0))
end

-- RENDRE LA MAIN, pour de bon. Separe de `endScene` parce que le plan de sortie s'intercale entre les deux : le
-- joueur reste bloque et les barres restent en place tant qu'on est encore au cinema.
local function releaseScene()
	-- LES JAMBES D'ABORD. La camera met SCENE_CAM_OUT a revenir ; si on rendait les controles seulement apres, le
	-- joueur appuierait dans le vide pendant ce temps -- et une commande qui ne repond pas se lit comme un lag.
	unfreezePlayer()
	SceneCamera.exit(TutorialConfigs.SCENE_CAM_OUT)
	Letterbox.hide(TutorialConfigs.SCENE_BARS_TIME)
	SoundDuck.restore(TutorialConfigs.SCENE_DUCK_TIME)
	CameraEffects.SetFovOffset(0)

	-- L'OBJECTIF S'AFFICHE. C'est le moment ou le joueur reprend la main : sans bandeau, il sait que la scene est
	-- finie mais pas ce qu'on attend de lui -- et c'est la premiere minute, celle ou l'on perd un joueur.
	--
	-- LA BARRE NE BOUGE PAS ENCORE : personne ne compte l'herbe coupee. Le bandeau est pose pour etre VU et
	-- juge ; le compteur de progression est un autre chantier, et c'est lui le vrai travail.
	TaskBannerHandler.show(TutorialConfigs.TASK_TITLE, TutorialConfigs.TASK_REWARD, 0)
end

local function endScene()
	if sceneEnded then
		return
	end
	sceneEnded = true

	-- LE JOUEUR REDEVIENT VISIBLE TOUT DE SUITE : c'est un plan a DEUX, il faut le voir dedans. Il etait efface
	-- parce qu'il masquait la porte ; maintenant qu'on recule, il redevient un des deux sujets.
	fadePlayer(0)

	-- LE GRAND-PERE SORT DE CHEZ LUI. C'est le SERVEUR qui le fait marcher : un PNJ qui se deplace est un objet
	-- du monde, il doit bouger pour tout le monde. La scene, elle, est purement locale -- camera, barres, fondu.
	local done = sceneDoneRemote
	if done then
		done:FireServer()
	end

	-- LE JOUEUR SE POUSSE, maintenant que le grand-pere se met en marche. Pas a la fin des coups : a ce
	-- moment-la la porte etait encore fermee, et se decaler devant une porte fermee ne veut rien dire.
	local aside = playAside
	if aside then
		task.delay(TutorialConfigs.KNOCK_ASIDE_DELAY, aside)
	end

	-- LE PLAN DE SORTIE. On garde les barres et le blocage pendant qu'il dure : c'est encore du cinema, et rendre
	-- les commandes au milieu ferait marcher le joueur dans son propre plan.
	local shot = exitShotCFrame()
	if shot then
		SceneCamera.moveTo(shot, TutorialConfigs.EXIT_SHOT_IN, function()
			task.delay(TutorialConfigs.EXIT_SHOT_HOLD, releaseScene)
		end)
	else
		-- Pas de cadrage possible (pas de personnage, pas de porte) : on ne retient pas le joueur pour rien.
		releaseScene()
	end
end

local function findModel(name: string): Model?
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == name then
			return d
		end
	end
	return nil
end

local function animatorOf(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
end

-- EST-CE QUE L'ANIMATION A REELLEMENT BOUGE QUELQUE CHOSE ? Une animation retrouve ses cibles par leur NOM : si
-- aucune ne correspond au rig, elle joue a plein poids et n'ecrit RIEN, sans la moindre erreur. La piste tourne,
-- le son part, l'ecran ne bouge pas -- et on cherche le bug dans le declenchement, qui est parfait.
--
-- On mesure donc le RESULTAT. Les animations ecrivent dans `Transform`, jamais dans `C0` : un Transform reste a
-- l'identite = personne n'a ecrit dedans. Piege deja paye deux fois -- sur les PNJ, puis sur le seau porte.
local function checkAnimMoved(model: Model, animName: string)
	task.delay(TutorialConfigs.ANIM_CHECK_DELAY, function()
		if not model.Parent then
			return
		end
		-- ON REGARDE LES DEUX SORTES DE RIG. `Motor6D` pour un modele fait de morceaux assembles, `Bone` pour un
		-- SKINNED MESH -- et le grand-pere est le second. La sonde ne connaissait que les Motor6D : elle criait
		-- donc au faux probleme sur un rig qui marchait parfaitement, et envoyait chercher une cible d'animation
		-- qui etait la bonne.
		--
		-- Les deux portent un `Transform` que l'animation ecrit, mais ils n'ont aucune classe commune (`Bone`
		-- descend d'`Attachment`, pas de `BasePart`) : d'ou la lecture non typee, qui evite d'ecrire deux fois la
		-- meme comparaison.
		local hasJoint = false
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Motor6D") or d:IsA("Bone") then
				hasJoint = true
				local moved = (d :: any).Transform
				if typeof(moved) == "CFrame" and moved ~= CFrame.identity then
					return -- au moins un joint a bouge : l'animation s'applique bien
				end
			end
		end

		-- DEUX CAUSES SEPAREES. Un rig sans aucun joint ne peut RIEN jouer, quelle que soit l'animation ; un rig
		-- qui en a mais dont rien ne bouge a recu une animation faite pour un autre modele. Le premier se corrige
		-- dans Studio, le second dans la config.
		if not hasJoint then
			warn(
				`[Tutorial] "{model.Name}" n'a ni Motor6D ni Bone : aucune animation ne peut le faire bouger. `
					.. "Ce n'est pas un rig anime."
			)
			return
		end
		warn(
			`[Tutorial] "{animName}" tourne mais n'a RIEN bouge sur "{model.Name}" : aucune de ses pistes ne porte `
				.. "le nom d'un joint de ce rig. Elle anime probablement un AUTRE model -- verifie la cible dans "
				.. "TutorialConfigs (le nom de l'animation ne dit pas sur quoi elle joue)."
		)
	end)
end

-- `fade` optionnel : zero par defaut (coupure nette, ce que veut un nettoyage), une duree quand on ENCHAINE sur
-- une autre pose et qu'un saut se verrait.
local function stopTrack(track: AnimationTrack?, fade: number?)
	if track then
		track:Stop(fade or 0)
	end
end

local function playerAnimator(): Animator?
	local character = player.Character
	return if character then animatorOf(character) else nil
end

local function loadSceneTrack(animator: Animator, animName: string): AnimationTrack?
	local node: Instance? = ReplicatedStorage
	for _, part in ipairs(TutorialConfigs.SCENE_ANIM_FOLDER) do
		node = node and node:FindFirstChild(part)
	end
	local anim = node and node:FindFirstChild(animName)
	if not (anim and anim:IsA("Animation")) then
		warn(
			`[Tutorial] Animation "{animName}" introuvable dans `
				.. `ReplicatedStorage.{table.concat(TutorialConfigs.SCENE_ANIM_FOLDER, ".")}`
		)
		return nil
	end
	return animator:LoadAnimation(anim)
end

-- LA PORTE. Elle s'ouvre a MOITIE, se FIGE le temps que le grand-pere parle, puis finit de s'ouvrir et TIENT.
--
-- Le gel se fait a la VITESSE (AdjustSpeed 0), jamais par un Stop : arreter une piste lui fait rendre sa pose de
-- repos, donc la porte se refermerait d'un coup. Et elle reste bouclee pour la meme raison -- une piste non
-- bouclee se relache a sa derniere image.
-- Pose la porte a un angle donne. Tout part de sa pose FERMEE, jamais de sa pose courante : composer les
-- rotations les unes sur les autres accumulerait l'erreur, et la porte finirait de travers.
local function setDoorAngle(deg: number)
	local model = door
	local base = doorBasePivot
	if not model or not base then
		return
	end
	doorAngle = deg
	local sign = if TutorialConfigs.DOOR_OPEN_INVERT then -1 else 1
	model:PivotTo(base * CFrame.Angles(0, math.rad(deg * sign), 0))
end

-- Fait tourner la porte jusqu'a `target`, en `seconds`. `onDone` ne part QUE si le mouvement va au bout : un
-- mouvement annule ne doit pas declencher la suite d'une sequence qui n'existe plus.
local function swingDoor(target: number, seconds: number, onDone: (() -> ())?)
	local from = doorAngle
	doorSwingToken += 1
	local token = doorSwingToken
	task.spawn(function()
		local t0 = os.clock()
		while doorSwingToken == token do
			local e = math.clamp((os.clock() - t0) / seconds, 0, 1)
			-- `Quad Out` a la main : elle part franchement et se pose en douceur. Une porte poussee perd sa vitesse
			-- en arrivant, elle ne s'arrete pas net.
			setDoorAngle(from + (target - from) * (1 - (1 - e) * (1 - e)))
			if e >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		if doorSwingToken == token and onDone then
			onDone()
		end
	end)
end

local function openDoor()
	local model = door
	if not model then
		return
	end
	-- LA POSE FERMEE, RELEVEE MAINTENANT. Le gond fait partie du modele : une fois la porte tournee, son pivot a
	-- tourne avec elle. Relire la base a chaque etape ferait donc repartir la rotation d'une base deja tournee.
	doorBasePivot = model:GetPivot()
	doorAngle = 0
	-- `GetPivot` suit la BOUNDING BOX quand le modele n'a pas de PrimaryPart : la porte tournerait alors autour de
	-- son MILIEU, comme une porte de saloon, au lieu de son gond. Ca se voit tout de suite a l'ecran, mais on
	-- chercherait la cause dans l'angle plutot que dans un champ vide.
	if not model.PrimaryPart then
		warn(
			`[Tutorial] "{model.Name}" n'a pas de PrimaryPart : elle tournera autour de son milieu, pas de son `
				.. "gond. Poser le gond en PrimaryPart dans Studio."
		)
	end
	-- L'IMAGE SE RESSERRE PILE QUAND LA PORTE PART. L'oeil suit le mouvement sans qu'on lui dise ou regarder.
	--
	-- On passe par CameraEffects et pas par `camera.FieldOfView` : il est declare SEUL ECRIVAIN de cette
	-- propriete et sa boucle tourne meme pendant la scene. Ecrire dessus en parallele donnerait un champ de
	-- vision qui vibre entre deux valeurs, et on chercherait la cause dans le zoom.
	CameraEffects.SetFovOffset(-TutorialConfigs.SCENE_ZOOM)
	-- LE NIVEAU DE FONDU DU JOUEUR pour la suite de la scene. A zero dans la config : il reste visible tout du
	-- long, parce qu'il est un personnage du plan et pas un obstacle. Le chemin reste branche -- c'est le knob si
	-- une scene doit un jour l'effacer.
	fadePlayerTo(TutorialConfigs.REVEAL_PLAYER_FADE, TutorialConfigs.REVEAL_FADE_TIME)

	-- ELLE RECULE, D'UN COUP. Comme si elle avait eu peur.
	--
	-- C'est le contraire de ce qu'elle faisait ici -- elle avancait sur le grand-pere. Mais on vient de passer
	-- toute la scene a se rapprocher pendant qu'il se bat avec la poignee : continuer d'avancer prolonge la
	-- montee au lieu de la RESOUDRE. Le sursaut arriere, lui, la casse net, et c'est ce qui fait l'evenement.
	--
	-- Le recul est plus GRAND que l'approche : revenir pile au point de depart se lirait comme une annulation.
	pushScene(-TutorialConfigs.SCARE_BACK, TutorialConfigs.SCARE_TIME)
	-- Le grincement part AVEC le mouvement, pas au marqueur de mi-course : c'est l'ouverture elle-meme qu'il
	-- accompagne, et un bruit qui arrive une fois la porte deja entrebaillee sonne en retard.
	SoundUtils.play(TutorialConfigs.OPEN_SOUND, SCENE_2D)

	-- LES DEUX ANIMATIONS DE LA PORTE S'ARRETENT ICI : le tremblement des coups et le geste de poignee. Elles
	-- ecrivent sur les memes parts que nous ; laissees en route, elles se battraient avec l'angle qu'on pose et la
	-- porte vibrerait.
	stopTrack(shakeTrack)
	stopTrack(tryTrack)
	shakeTrack, tryTrack = nil, nil

	-- L'OUVERTURE, EN DEUX TEMPS. Chaque temps s'enchaine sur la FIN du precedent, jamais sur des delais poses
	-- cote a cote : des delais deriveraient des que le jeu rame, et la grande ouverture partirait pendant que la
	-- porte s'entrebaille encore.
	swingDoor(TutorialConfigs.DOOR_HALF_ANGLE, TutorialConfigs.DOOR_HALF_TIME, function()
		task.delay(TutorialConfigs.DOOR_PAUSE, function()
			swingDoor(TutorialConfigs.DOOR_FULL_ANGLE, TutorialConfigs.DOOR_FULL_TIME, function()
				-- LE GRAND-PERE APPARAIT : l'image se resserre une seconde fois, sur LUI. Cadence imposee --
				-- l'allure par defaut de CameraEffects mettrait deux secondes, et l'accent serait fini apres le
				-- moment qu'il souligne.
				CameraEffects.SetFovOffset(
					-(TutorialConfigs.SCENE_ZOOM + TutorialConfigs.REVEAL_ZOOM),
					TutorialConfigs.REVEAL_ZOOM_SPEED
				)
			end)
		end)
	end)
end

-- LE GRAND-PERE MENE LA SCENE. Son animation declenche la porte, et sa fin termine la scene : c'est elle qui
-- sait combien de temps ca dure, pas une constante.
local function playGrandpa()
	local model = findModel(TutorialConfigs.GRANDPA_NAME)
	local animator = if model then animatorOf(model) else nil
	local track = if animator then loadSceneTrack(animator, TutorialConfigs.GRANDPA_ANIM) else nil
	if not track then
		if not model then
			warn(`[Tutorial] Model "{TutorialConfigs.GRANDPA_NAME}" introuvable : la scene se jouera a vide.`)
		elseif not animator then
			warn(`[Tutorial] Pas d'Animator sous "{TutorialConfigs.GRANDPA_NAME}" : la scene se jouera a vide.`)
		end
		-- FILET : sans lui le joueur resterait coince en camera scriptee, derriere des barres noires, sans aucun
		-- moyen d'en sortir. Une animation absente ne doit jamais devenir une partie bloquee.
		task.delay(TutorialConfigs.SCENE_HOLD, endScene)
		return
	end

	grandpaTrack = track
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	track:GetMarkerReachedSignal(TutorialConfigs.DOOR_START_EVENT):Connect(openDoor)
	-- C'EST LA FIN DE L'ANIMATION QUI TERMINE LA SCENE. Une duree en dur et une animation finissent toujours par
	-- se contredire, et c'est la duree qui a tort : elle ne suit pas quand on retouche l'animation.
	track.Stopped:Connect(endScene)
	track:Play()
	checkAnimMoved(model :: Model, TutorialConfigs.GRANDPA_ANIM)
end

-- IL S'ACHARNE SUR LA POIGNEE. Entre les coups et l'ouverture : le grand-pere se bat avec sa vieille porte.
-- Quand l'animation s'acheve, l'ouverture prend la suite -- c'est elle qui dit quand elle a fini, pas un delai
-- pose a cote qui se decalerait a la premiere retouche.
local function playTryOpen()
	-- LA CIBLE EST DANS LA CONFIG, pas deduite du nom de l'animation : "oldman_TryOpenDoor" peut tres bien
	-- animer la poignee de la porte plutot que le vieux.
	local model = findModel(TutorialConfigs.TRY_OPEN_MODEL)
	local animator = if model then animatorOf(model) else nil
	local track = if animator then loadSceneTrack(animator, TutorialConfigs.TRY_OPEN_ANIM) else nil
	if not track then
		-- ON DIT POURQUOI ON SAUTE. Sans ces deux messages l'etape disparait EN SILENCE : la scene s'enchaine
		-- normalement, rien ne casse, et on croit que le code ne joue pas l'animation alors qu'il ne trouve pas
		-- de quoi la jouer. `loadSceneTrack` parle deja quand c'est l'Animation qui manque ; ici on couvre les
		-- deux autres causes.
		if not model then
			warn(`[Tutorial] Model "{TutorialConfigs.TRY_OPEN_MODEL}" introuvable : pas de geste de poignee.`)
		elseif not animator then
			warn(`[Tutorial] Pas d'Animator sous "{TutorialConfigs.TRY_OPEN_MODEL}" : pas de geste de poignee.`)
		end
		playGrandpa() -- l'etape saute, la scene continue
		return
	end
	tryTrack = track
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	trySound = SoundUtils.play(TutorialConfigs.TRY_OPEN_SOUND, SCENE_2D)
	-- ON SE RAPPROCHE, LENTEMENT, pendant qu'il se bat avec la poignee. L'image se resserre sans qu'on s'en rende
	-- compte : la tension monte toute seule, sans qu'aucun evenement ne la signale.
	pushScene(TutorialConfigs.TRY_PUSH, TutorialConfigs.TRY_PUSH_TIME)
	checkAnimMoved(model :: Model, TutorialConfigs.TRY_OPEN_ANIM)

	local chained = false
	track.Stopped:Connect(function()
		if chained then
			return
		end
		chained = true
		-- LE SON CONTINUE. Il dure plus longtemps que le geste, et le couper net s'entend comme un bug -- alors
		-- qu'il deborde sur l'ouverture sans deranger personne. SoundUtils detruit le clone tout seul a la fin.
		trySound = nil
		playGrandpa()
	end)
	track:Play()
end

-- UN COUP : la porte tremble et on entend le choc. Appele une fois par marqueur de l'animation du joueur, donc
-- c'est l'ANIMATION qui dit quand -- pas un minuteur qui finirait par se decaler d'elle.
-- Les emetteurs du conteneur, ou une liste VIDE si on ne l'a pas trouve. On garde la liste vide en cache : sans
-- ca on re-balayerait tout le Workspace a chaque coup pour ne rien trouver.
local function getKnockEmitters(): { ParticleEmitter }
	local cached = knockEmitters
	if cached then
		return cached
	end
	local found: { ParticleEmitter } = {}
	local holder = findByName(TutorialConfigs.KNOCK_EMIT_PARENT)
	if holder then
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				table.insert(found, d)
			end
		end
	end
	-- ON DIT CE QU'ON N'A PAS TROUVE, et on distingue les deux cas : un conteneur absent et un conteneur vide se
	-- ressemblent a l'ecran -- aucun effet -- mais se corrigent a deux endroits opposes.
	if #found == 0 then
		if holder then
			warn(
				`[Tutorial] "{TutorialConfigs.KNOCK_EMIT_PARENT}" trouve mais il ne contient AUCUN ParticleEmitter.`
			)
		else
			warn(
				`[Tutorial] "{TutorialConfigs.KNOCK_EMIT_PARENT}" introuvable dans le Workspace : pas d'impact aux `
					.. "coups. Rojo ne synchronise pas le Workspace, il doit exister dans CETTE place."
			)
		end
	end
	-- ON DIT CE QU'ON A TROUVE, pas seulement ce qui manque. "Aucun effet" couvre trois causes qui se ressemblent
	-- a l'ecran : conteneur introuvable, conteneur sans emetteur, ou emetteurs bien trouves mais dont la bouffee
	-- ne se voit pas. Les deux premieres sont deja nommees ci-dessus ; celle-ci separe la troisieme -- et c'est
	-- la seule qui se corrige dans Studio, sur les emetteurs eux-memes.
	--
	-- Une fois par session, a la premiere frappe : ce n'est pas du bruit.
	if #found > 0 then
		local names = {}
		for _, e in ipairs(found) do
			table.insert(names, `{e.Parent and e.Parent.Name or "?"}/{e.Name}`)
		end
		print(`[Tutorial] {#found} emetteur(s) d'impact : {table.concat(names, ", ")}`)
	end
	knockHolder = holder
	knockEmitters = found
	return found
end

-- Le point d'impact dans le MONDE. On ne suppose pas la classe du conteneur : une part, un model ou une
-- attachment donnent leur position de trois facons differentes, et l'exiger obligerait a re-ranger Studio pour
-- faire plaisir au code.
local function knockPoint(): Vector3?
	local h = knockHolder
	if not h then
		return nil
	end
	if h:IsA("BasePart") then
		return h.Position
	elseif h:IsA("Attachment") then
		return h.WorldPosition
	elseif h:IsA("Model") then
		return h:GetPivot().Position
	end
	return nil
end

local function knockOnce()
	local model = door
	if not model then
		return -- porte pas encore repliquee : la boucle de resolution la reprendra, rien a signaler ici
	end
	SoundUtils.play(TutorialConfigs.KNOCK_SOUND, SCENE_2D)
	SceneCamera.kick(TutorialConfigs.KNOCK_KICK)

	-- L'IMPACT. Une bouffee ponctuelle, pas un effet qu'on allume : `Emit` est fini a la seconde ou il part, donc
	-- il n'y a AUCUN etat a rendre -- ni a l'arret de la scene, ni a la mort du joueur. La version precedente
	-- allumait des Beams, et il fallait un releve de leur eclat pour ne pas les laisser eteints a jamais.
	for _, emitter in ipairs(getKnockEmitters()) do
		emitter:Emit(TutorialConfigs.KNOCK_EMIT_COUNT)
	end

	-- LA GERBE D'ETOILES, a l'ecran. Elle ne remplace pas les deux effets du monde, elle les DEBORDE : particules
	-- et eclairs restent au point d'impact, la gerbe part au-dela du cadre. C'est ce qui donne l'echelle du coup.
	--
	-- `getKnockEmitters` d'abord, toujours : c'est lui qui resout le conteneur dont on tire le point.
	local point = knockPoint()
	if point then
		StarBurst.at(point)
	end

	local shake = shakeTrack
	if not shake then
		local animator = animatorOf(model)
		shake = if animator then loadSceneTrack(animator, TutorialConfigs.DOOR_SHAKE_ANIM) else nil
		if not shake then
			return
		end
		shake.Priority = Enum.AnimationPriority.Action
		shake.Looped = false
		shakeTrack = shake
	end
	-- ON REMBOBINE plutot que d'enchainer Stop puis Play. Trois coups rapproches : un Stop coupe en fondu, donc
	-- le deuxieme coup partirait par-dessus la fin du premier et le tremblement s'aplatirait.
	if shake.IsPlaying then
		shake.TimePosition = 0
	else
		shake:Play(0)
	end
end

-- JOUE UNE PISTE UNE FOIS ET TIENT SA DERNIERE IMAGE.
--
-- BOUCLEE, ET C'EST VOLONTAIRE. Une piste NON bouclee se RELACHE a sa derniere image : la pose n'est plus tenue
-- par personne et le personnage retombe en position de repos. Bouclee, elle ne relache jamais -- il ne reste
-- qu'a l'empecher de repartir au debut.
--
-- ON LA LAISSE JOUER A VITESSE NORMALE, puis on la fige. La recette habituelle du projet (vitesse 0 des le
-- depart + `TimePosition` avancee a la main) ne convient PAS : les marqueurs ne tirent que pendant une lecture
-- REELLE, et piloter le temps a la main tuerait les sons de coups et les impacts.
--
-- DEUX DECLENCHEURS, parce qu'un seul suffit a rater son coup :
--   - le seuil par image, qui attrape le cas normal ;
--   - `DidLoop`, filet pour une image sautee a bas framerate -- sans lui la piste repartirait du debut et le
--     geste se rejouerait en boucle pendant tout le reste de la scene.
local function playHolding(track: AnimationTrack, onHeld: () -> ())
	track.Looped = true
	local held = false
	local conn: RBXScriptConnection? = nil

	local function freeze()
		if held then
			return
		end
		held = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
		track:AdjustSpeed(0)
		if track.Length > 0 then
			-- Pas EXACTEMENT Length : a la derniere image pile, la lecture peut basculer de l'autre cote et
			-- reboucler. On se pose un cheveu avant.
			track.TimePosition = math.max(0, track.Length - 0.001)
		end
		onHeld()
	end

	conn = RunService.RenderStepped:Connect(function()
		-- `Length` vaut zero tant que l'asset n'est pas telecharge : sans cette garde on gelerait la piste avant
		-- meme qu'elle ait commence.
		if track.Length > 0 and track.TimePosition >= track.Length - TutorialConfigs.KNOCK_HOLD_MARGIN then
			freeze()
		end
	end)
	table.insert(holdConns, conn :: RBXScriptConnection)
	track.DidLoop:Connect(freeze)
	track:Play()
end

-- LE PAS DE COTE. On ACQUIERT AVANT DE LACHER : la nouvelle piste demarre d'abord, celle des coups se retire
-- ensuite en fondu. L'ordre inverse laisserait une image sans aucune pose tenue, et le personnage sauterait en
-- position de repos pile entre les deux.
--
-- Le fondu est court ET voulu : les deux pistes sont en priorite Action, et a priorite EGALE Roblox ne choisit
-- pas, il MELANGE. Long, on lirait une pose moyenne entre les deux.
--
-- Idempotent : la scene peut se terminer deux fois (fin normale et filet de secours), le pas de cote non.
playAside = function()
	if knockAsideTrack then
		return
	end
	local animator = playerAnimator()
	local aside = if animator then loadSceneTrack(animator, TutorialConfigs.KNOCK_ASIDE_ANIM) else nil
	if not aside then
		return
	end
	aside.Priority = Enum.AnimationPriority.Action
	knockAsideTrack = aside
	-- Elle tient sa derniere image : il reste sur le cote au lieu de revenir en pose de repos.
	playHolding(aside, function() end)
	stopTrack(knockTrack, TutorialConfigs.KNOCK_ASIDE_FADE)
end

-- LE JOUEUR TOQUE, et c'est ce qui OUVRE la scene. Chaque marqueur de son animation donne un coup ; quand elle
-- s'acheve, le grand-pere prend la suite.
local function playScene()
	local animator = playerAnimator()
	local track = if animator then loadSceneTrack(animator, TutorialConfigs.KNOCK_ANIM) else nil
	if not track then
		-- Pas d'animation de coups : on ne bloque pas la scene pour autant, le grand-pere vient quand meme.
		playTryOpen()
		return
	end
	knockTrack = track
	track.Priority = Enum.AnimationPriority.Action
	for _, eventName in ipairs(TutorialConfigs.KNOCK_EVENTS) do
		track:GetMarkerReachedSignal(eventName):Connect(knockOnce)
	end

	local chained = false
	local function chain()
		if chained then
			return
		end
		chained = true
		playTryOpen()
	end

	-- LA POSE DE FIN DES COUPS EST TENUE, et elle le reste pendant toute la scene : le joueur garde la main
	-- levee vers la porte pendant que le grand-pere se bat avec sa poignee. Le pas de cote viendra plus tard,
	-- quand il se mettra vraiment en marche (voir `playAside`).
	playHolding(track, chain)

	-- LA PISTE COUPEE DE L'EXTERIEUR enchaine quand meme (fin de scene, respawn). Le drapeau evite le double
	-- depart quand le gel a deja fait le travail.
	track.Stopped:Connect(chain)
end

--- Le joueur a toque : la mission commence. Le guidage s'eteint DEFINITIVEMENT -- halo, prompt et touche --
--- puis la scene part. Idempotent : un double appui ne doit pas relancer une scene deja en cours.
---
--- ETAT ACTUEL : les barres et la camera sont branchees, les ANIMATIONS ne le sont pas encore. La scene tient
--- donc SCENE_HOLD secondes puis rend la main. Des que l'animation du grand-pere existe, c'est ELLE qui doit
--- decider de la fin -- une duree en dur et une animation finissent toujours par se contredire.
function TutorialController.startMission()
	if missionStarted then
		return
	end
	missionStarted = true
	TutorialController.setDoorHint(false)
	hideOurs()
	setActionBound(false)
	-- AVANT TOUT LE RESTE : le joueur a appuye sur E, il tient peut-etre encore une touche de deplacement. Couper
	-- ici l'arrete net, avant que la camera ne parte et ne le laisse marcher hors champ.
	freezePlayer()

	-- LES BARRES ET LA CAMERA PARTENT ENSEMBLE. Dans un film le cadre bouge pendant que le rideau descend, il
	-- n'attend pas que le noir soit en place.
	Letterbox.show(TutorialConfigs.SCENE_BARS_TIME)
	-- LE JEU BAISSE, il ne se tait pas. Un silence total s'entend comme une coupure et le monde a l'air de
	-- s'eteindre : on veut que l'oreille se tourne vers la scene, pas que le reste disparaisse.
	SoundDuck.duck(TutorialConfigs.SCENE_DUCK, TutorialConfigs.SCENE_DUCK_TIME)
	-- LA BOITE DE DIALOGUE S'EFFACE. Elle occupe le bas de l'ecran, pile ou les barres arrivent : une bulle qui
	-- reste ouverte pendant qu'on toque parle par-dessus le geste. Elle reviendra quand la SCENE la demandera.
	Dialogue.hide()
	fadePlayer(TutorialConfigs.SCENE_PLAYER_FADE)
	-- AVANT le cadrage : les deux partent de la meme direction, mais le joueur doit etre en route pendant que la
	-- camera arrive, pas apres.
	placeAtDoor()
	local cf = sceneCFrame()
	if not cf then
		-- Pas de cadrage possible (pas de personnage) : on ne prend pas la camera pour rien.
		task.delay(TutorialConfigs.SCENE_HOLD, endScene)
		return
	end
	sceneCF = cf
	SceneCamera.enter(cf, TutorialConfigs.SCENE_CAM_IN, function()
		-- Le rappel tire QUAND LA CAMERA EST ARRIVEE : la scene commence de la, pas de l'appui. Sinon le temps de
		-- trajet mangerait le debut du plan, et il changerait avec SCENE_CAM_IN sans qu'on y pense.
		playScene()
	end)
end

local function step(dt: number)
	local now = os.clock()

	-- ON REVALIDE TANT QU'IL MANQUE QUELQUE CHOSE, pas seulement au premier passage. Avec StreamingEnabled le
	-- Model arrive souvent AVANT ses parts : resoudre l'ancre une seule fois la laissait a nil pour TOUTE la
	-- session, et le prompt ne sortait jamais -- sans la moindre erreur. Le Model etait pourtant bien trouve,
	-- donc on cherchait le probleme du cote de la distance ou du prompt, pas du cote de la replication.
	if not (door and door.Parent and anchor and anchor.Parent) then
		door, anchor = nil, nil
		if now - lastScanAt < TutorialConfigs.RESCAN_INTERVAL then
			return
		end
		lastScanAt = now
		door, anchor = findDoor()
		if not door then
			if not warnedNoDoor and now - startedAt > TutorialConfigs.NOT_FOUND_WARN_AFTER then
				warnedNoDoor = true
				warn(
					`[Tutorial] Aucun Model "{TutorialConfigs.DOOR_NAME}" utilisable dans le Workspace : ni halo, `
						.. "ni prompt. Rojo ne synchronise pas le Workspace, la porte doit exister dans CETTE place."
				)
			end
			return
		end
	end

	-- Le Highlight peut arriver APRES les parts : meme raison, on le re-cherche tant qu'on ne l'a pas.
	if not (highlight and highlight.Parent) then
		local halo = (door :: Model):FindFirstChild(TutorialConfigs.HIGHLIGHT_NAME)
		highlight = if halo and halo:IsA("Highlight") then halo else nil
		if not highlight and not warnedNoHighlight and now - startedAt > TutorialConfigs.NOT_FOUND_WARN_AFTER then
			warnedNoHighlight = true
			warn(
				`[Tutorial] Porte trouvee mais aucun Highlight "{TutorialConfigs.HIGHLIGHT_NAME}" dedans : elle ne `
					.. "clignotera pas. Ce Highlight se pose A LA MAIN dans Studio, dans chaque place."
			)
		end
	end

	-- ===== LE HALO =====
	local halo = highlight
	if halo and halo.Parent then
		if not doorHint then
			-- On ECRIT la valeur eteinte plutot que de sortir en silence : le halo a pu etre coupe en plein
			-- battement, et il resterait alors fige a moitie visible.
			if halo.FillTransparency ~= TutorialConfigs.FILL_MAX then
				halo.FillTransparency = TutorialConfigs.FILL_MAX
			end
		else
			elapsed += dt
			-- SINUS, pas un aller-retour lineaire. Une respiration n'a ni depart ni arrivee : le cosinus repart
			-- de lui-meme, donc aucune saccade au bouclage. Un lerp aller-retour casse a chaque extremite.
			local a = 0.5 - 0.5 * math.cos(elapsed * math.pi * 2 / TutorialConfigs.PULSE_PERIOD)
			halo.FillTransparency = TutorialConfigs.FILL_MAX
				+ (TutorialConfigs.FILL_MIN - TutorialConfigs.FILL_MAX) * a
		end
	end

	-- ===== LE PROMPT =====
	-- LE CENTRE DE LA PORTE, pas sa PrimaryPart. Celle-ci est le "Handle" : la CHARNIERE, posee sur le COTE. Le
	-- badge sortait donc a cote de la porte, et la distance se comptait depuis ce bord. La boite englobante ne
	-- depend d'aucun choix de PrimaryPart -- et elle reste juste si on en change dans Studio.
	--
	-- Recalculee a chaque test : deplacer la porte pendant une partie doit suivre. Une boite englobante sur une
	-- poignee de parts ne coute rien, et la valeur est IDENTIQUE tant que la porte ne bouge pas -- donc le
	-- prompt n'est pas re-affiche pour rien.
	anchorPos = (door :: Model):GetBoundingBox().Position

	-- ===== LE MARQUEUR =====
	-- Le halo dit "cet objet compte" quand on le voit deja. Le marqueur, lui, se voit de LOIN : c'est lui qui dit
	-- OU ALLER, et il disparait des qu'on a toque.
	--
	-- POSE APRES `anchorPos`, ET C'EST TOUT LE POINT. Il etait cree une trentaine de lignes plus haut, quand
	-- l'ancre valait encore son zero de depart : le marqueur naissait donc a l'ORIGINE DE LA MAP. Et comme on lui
	-- passe un POINT et non la porte elle-meme -- un instantane, pas une reference -- il n'en bougeait plus
	-- jamais.
	--
	-- Symptome trompeur : le marqueur s'affiche, il bouge, il sursaute, tout marche... a des dizaines de studs de
	-- ce qu'il designe. Rien ne ressemble moins a un bug de position qu'un objet qui fonctionne parfaitement.
	--
	-- Le point vise est le CENTRE de la porte, pas sa PrimaryPart : celle-ci est la charniere, posee sur le cote.
	if doorHint and not doorMarker then
		doorMarker = WorldMarker.show(anchorPos, Vector3.new(0, TutorialConfigs.DOOR_MARKER_UP, 0))
	elseif not doorHint and doorMarker then
		WorldMarker.remove(doorMarker)
		doorMarker = nil
	end

	local root = getRoot()

	-- Dit ce que la detection VOIT, pas ce qu'on croit qu'elle voit.
	if TutorialConfigs.DEBUG and now - lastDebugAt >= TutorialConfigs.DEBUG_INTERVAL then
		lastDebugAt = now
		if not root then
			print("[Tutorial] pas de HumanoidRootPart (personnage pas encore la)")
		else
			local d = ((anchorPos - root.Position) * Vector3.new(1, 0, 1)).Magnitude
			print(
				`[Tutorial] porte "{(door :: Model).Name}" | centre a {string.format("%.1f", d)} studs `
					.. `(rayon {TutorialConfigs.PROMPT_RADIUS}) | halo {tostring(highlight ~= nil)} `
					.. `| mission lancee {tostring(missionStarted)} | touche branchee {tostring(actionBound)}`
			)
		end
	end

	if missionStarted then
		return
	end
	if now - lastPromptAt < TutorialConfigs.PROMPT_INTERVAL then
		return
	end
	lastPromptAt = now

	if not root then
		hideOurs()
		setActionBound(false)
		return
	end

	-- DISTANCE RADIALE, a plat. Une box orientee laisserait des angles morts : colle a un bout de la porte on
	-- tomberait dehors, et l'agrandir ne bouche pas le trou puisqu'elle reste au mauvais endroit.
	local flat = (anchorPos - root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude > TutorialConfigs.PROMPT_RADIUS then
		hideOurs()
		setActionBound(false)
		return
	end

	setActionBound(true)
	-- On re-montre au CHANGEMENT de cible, mais AUSSI quand le prompt ne nous appartient plus : une autre
	-- feature a pu prendre le singleton entre-temps. Sans ce second test, le notre disparaitrait pour de bon.
	if not promptShown or InteractionPrompt.currentTarget() ~= anchorPos then
		promptShown = true
		InteractionPrompt.show(
			anchorPos,
			TutorialConfigs.PROMPT_KEY,
			TutorialConfigs.PROMPT_LABEL,
			TutorialConfigs.PROMPT_OFFSET,
			TutorialController.startMission,
			TutorialConfigs.PROMPT_TITLE
		)
	end
end

function TutorialController.init()
	if conn then
		return
	end
	startedAt = os.clock()

	-- LE REMOTE SE RESOUT EN TACHE DE FOND. `getRemote` cache un `WaitForChild` : appele en ligne droite ici, il
	-- gele TOUT le boot le temps de son timeout quand la replication tarde -- un trou de dix secondes sans la
	-- moindre erreur, juste un vide dans les horodatages. Le piege a deja ete paye dans ce projet.
	task.spawn(function()
		sceneDoneRemote = RemoteSetup.getRemote("TutorialSceneDone", "Tutorial") :: RemoteEvent
	end)

	-- MORT OU RESPAWN EN PLEINE SCENE. Sans ce filet le joueur ressuscite avec une camera scriptee et des barres
	-- noires, et AUCUN moyen d'en sortir : la scene attend une fin qui ne viendra jamais.
	player.CharacterRemoving:Connect(function()
		if SceneCamera.isActive() or Letterbox.isShown() then
			SceneCamera.abort()
			Letterbox.hide(0)
			SoundDuck.restore(0)
			CameraEffects.SetFovOffset(0)
			fadePlayer(0)
		end
	end)
	-- LA BOUCLE PART MEME SI LA PORTE N'EST PAS ENCORE LA. Avec StreamingEnabled elle arrive souvent apres le
	-- spawn : sortir ici laisserait le guidage mort pour toute la session, sans la moindre erreur pour le dire.
	-- Elle coute une comparaison de date tant qu'il n'y a rien a animer.
	conn = RunService.Heartbeat:Connect(step)
end

--- Coupe tout : boucle, halo, prompt et touche. Celui qui cree est celui qui nettoie, et il nettoie TOUT.
function TutorialController.stop()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	-- LA SCENE SURVIT AU CONTROLLER. La camera et les barres vivent dans la PlayerGui, et les pistes tournent sur
	-- des Animator du Workspace : les laisser en place figerait le joueur dans une scene qui n'existe plus, et la
	-- porte resterait ouverte sur rien. Celui qui cree est celui qui nettoie, et il nettoie TOUT.
	SceneCamera.abort()
	Letterbox.hide(0)
	-- Le son est BAISSE, pas coupe : l'oublier laisserait le jeu a un quart de volume pour toujours, et personne
	-- ne ferait le lien avec une scene finie depuis longtemps.
	SoundDuck.restore(0)
	CameraEffects.SetFovOffset(0)
	fadePlayer(0)
	-- UNE PAR UNE, jamais `ipairs` sur une liste de valeurs nilables : ipairs S'ARRETE AU PREMIER NIL. Une seule
	-- piste absente et la boucle ne tourne pas du tout -- les autres resteraient en place. Piege deja paye sur
	-- l'animation de recul de la tondeuse, qui ne s'arretait jamais.
	stopTrack(grandpaTrack)
	-- LES SURVEILLANCES MEURENT AVEC LES PISTES. Une connexion RenderStepped laissee derriere tournerait pour le
	-- reste de la partie, sur des pistes qui n'existent plus.
	for _, conn in holdConns do
		conn:Disconnect()
	end
	table.clear(holdConns)
	stopTrack(knockTrack)
	stopTrack(knockAsideTrack)
	stopTrack(shakeTrack)
	stopTrack(tryTrack)
	if doorMarker then
		WorldMarker.remove(doorMarker)
		doorMarker = nil
	end
	-- LA PORTE SE REFERME AVEC LA SCENE. On annule le mouvement en cours puis on la repose fermee : sans ca elle
	-- resterait grande ouverte pour toujours, et rejouer la scene partirait d'une porte deja ouverte.
	doorSwingToken += 1
	if doorBasePivot then
		setDoorAngle(0)
		doorBasePivot = nil
	end
	grandpaTrack, knockTrack, shakeTrack, tryTrack = nil, nil, nil, nil
	local sfx = trySound
	trySound = nil
	if sfx and sfx.Parent then
		sfx:Stop()
		sfx:Destroy()
	end
	local halo = highlight
	if halo and halo.Parent then
		halo.FillTransparency = TutorialConfigs.FILL_MAX
	end
	hideOurs()
	setActionBound(false)
	door, highlight, anchor = nil, nil, nil
	sceneCF = nil
end

return TutorialController
