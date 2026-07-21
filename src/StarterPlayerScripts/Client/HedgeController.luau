--!strict
-- Ressenti du travail au pied d'une haie, cote client : orientation forcee face a la haie, camera de travail,
-- et le debug visuel du volume de detection.
--
-- POURQUOI COTE CLIENT. Le client possede son personnage et sa camera. Forcer l'orientation depuis le serveur
-- se battrait contre la simulation locale du joueur et donnerait du rubber-banding. Le serveur DECIDE (il pose
-- l'attribut LeafiaAtHedge), le client OBEIT.
--
-- Le decrochage est automatique : reculer eloigne le joueur, le volume de detection ne touche plus, le serveur
-- passe l'attribut a false et tout se relache ici.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)
local CameraEffects = require(script.Parent.Utils.CameraEffects)

local HedgeController = {}

local player = Players.LocalPlayer
-- Une barre par angle de l'eventail. N'en dessiner qu'une masquerait les lancers de biais, et le debug
-- mentirait a nouveau sur ce qui est reellement teste.
local debugParts: { [number]: BasePart } = {}
-- Etiquette de chaque barre : la part de portee consommee avant de toucher.
local debugLabels: { [number]: TextLabel } = {}
local cursorPart: BasePart? = nil
-- Etat local, pour ne faire les transitions qu'UNE fois au lieu de reecrire les memes proprietes chaque frame.
local engaged = false

-- Pivot horizontal de la camera autour du joueur, en radians. Remis a zero au decrochage : on retrouve
-- toujours la vue de face en revenant sur une haie.
local yaw = 0
local orbiting = false

-- Module de controle par defaut de Roblox. On lui demande l'input BRUT du joueur.
--
-- POURQUOI PAS humanoid.MoveDirection : des qu'on contraint le deplacement avec humanoid:Move(), MoveDirection
-- devient NOTRE valeur contrainte. On lirait donc notre propre sortie, et l'intention de reculer du joueur
-- serait invisible : impossible de detecter qu'il veut sortir.
-- GetMoveVector rend l'input tel qu'il a ete saisi, avant toute contrainte, et sans dependre du clavier
-- (AZERTY ou QWERTY, c'est le module de Roblox qui s'en occupe).
local controlModule: any = nil

local function getMoveVector(): Vector3
	if not controlModule then
		local ok, result = pcall(function()
			local scripts = player:WaitForChild("PlayerScripts", 10)
			local playerModule = scripts and require(scripts:WaitForChild("PlayerModule", 10)) :: any
			return playerModule and playerModule:GetControls()
		end)
		if not (ok and result) then
			return Vector3.zero
		end
		controlModule = result
	end

	local ok, vector = pcall(function()
		return controlModule:GetMoveVector()
	end)
	return if ok and typeof(vector) == "Vector3" then vector else Vector3.zero
end

-- ===== PAS CHASSE =====
-- Devant une haie le joueur ne marche pas, il se deplace en pas chasses. UNE seule piste sert aux deux sens :
-- jouee a l'envers pour l'autre cote. Le miroir est donc exact par construction, et il n'y a qu'une animation
-- a produire et a maintenir au lieu de deux qu'il faudrait garder synchronisees a la main.
--
-- POURQUOI COTE CLIENT, alors que ToolService joue ses animations cote serveur : le sens du glissement est
-- calcule ICI, frame par frame, a partir de l'input brut. Le faire trancher par le serveur ajouterait un
-- aller-retour reseau a chaque changement de direction, et les jambes partiraient du mauvais cote pendant ce
-- temps. Une animation jouee sur son PROPRE personnage se replique de toute facon aux autres joueurs.
local slideTrack: AnimationTrack? = nil
-- Sens en cours : -1 gauche, 1 droite, 0 arret. Retenu pour ne toucher a la piste qu'aux CHANGEMENTS, et non
-- soixante fois par seconde.
local slideDirection = 0

-- Part de la vitesse appliquee en ce moment. Montee d'un coup a chaque pose de pied, puis elle retombe.
local stepStrength = 1
-- Date du dernier marqueur recu. Sert au repli en deplacement continu quand plus rien n'arrive.
local lastStepAt = 0

-- ===== HAUTEUR DE COUPE =====
-- Piste FIGEE et parcourue a la main : sa premiere image est la coupe basse, sa derniere la coupe haute. On ne
-- la joue pas, on s'en sert comme d'une regle graduee que la hauteur visee promene.
local updownTrack: AnimationTrack? = nil
-- Hauteur suivie en ce moment, entre 0 et 1. Distincte de la hauteur VISEE : elle la rejoint progressivement,
-- sinon les bras claqueraient d'une position a l'autre au moindre saut de curseur.
local updownRatio = 0

local function loadTrack(animator: Animator, path: { string }, priority: Enum.AnimationPriority): AnimationTrack?
	local source: Instance? = ReplicatedStorage
	for _, name in ipairs(path) do
		source = source and source:FindFirstChild(name)
	end
	local label = table.concat(path, ".")
	if not (source and source:IsA("Animation")) then
		warn(`[HedgeController] Animation introuvable : {label}`)
		return nil
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(source :: Animation)
	end)
	if not (ok and track) then
		warn(`[HedgeController] Animation impossible a charger : {label}`)
		return nil
	end
	track.Priority = priority
	return track
end

local function setupCharacter(character: Model)
	-- Les anciennes pistes appartenaient a l'Animator du personnage precedent : elles ne pointent plus sur rien.
	slideTrack = nil
	updownTrack = nil
	slideDirection = 0

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	-- A CharacterAdded le personnage est parente mais PAS complet : l'Animator arrive quelques frames apres
	-- l'Humanoid. Un FindFirstChildOfClass seul renverrait nil ici.
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
	if not (animator and animator:IsA("Animator")) then
		return
	end

	local slide = loadTrack(animator, HedgeConfigs.SLIDE_ANIMATION, HedgeConfigs.SLIDE_PRIORITY)
	if slide then
		slide.Looped = true
		-- Le deplacement est declenche par l'IMAGE, pas par une minuterie : la poussee tombe exactement quand le
		-- pied touche le sol a l'ecran. Cause et effet sur la meme frame, c'est ce qui supprime le patinage.
		slide:GetMarkerReachedSignal(HedgeConfigs.STEP_MARKER):Connect(function()
			stepStrength = HedgeConfigs.STEP_PUSH
			lastStepAt = os.clock()
		end)
		slideTrack = slide
	end

	local updown = loadTrack(animator, HedgeConfigs.UPDOWN_ANIMATION, HedgeConfigs.UPDOWN_PRIORITY)
	if updown then
		-- Surtout PAS bouclee : elle ne se deroule jamais toute seule, c'est la visee qui la deplace.
		updown.Looped = false
		updownTrack = updown
	end
end

-- active : le joueur vise-t-il une haie, moteur en marche. ratio : 0 en bas de la haie, 1 en haut.
local function setUpDown(active: boolean, ratio: number, dt: number)
	local track = updownTrack
	if not track then
		return
	end

	if not active then
		if track.IsPlaying then
			track:Stop(HedgeConfigs.UPDOWN_FADE)
		end
		return
	end

	if not track.IsPlaying then
		-- Vitesse ZERO : la piste est lancee mais ne se deroule pas. Elle ne bougera que par TimePosition.
		track:Play(HedgeConfigs.UPDOWN_FADE, 1, 0)
		-- On part de la hauteur visee et non de la derniere connue : sinon les bras balaieraient toute la haie
		-- au premier affichage, depuis la position qu'ils avaient au chantier precedent.
		updownRatio = ratio
	end

	-- Lerp exponentiel avec dt dans le facteur : meme vitesse de suivi a 30 et a 60 FPS.
	updownRatio += (ratio - updownRatio) * math.min(1, HedgeConfigs.UPDOWN_FOLLOW_SPEED * dt)
	track.TimePosition = track.Length * math.clamp(updownRatio, 0, 1)
end

-- direction : -1 glisse a GAUCHE, 1 glisse a DROITE, 0 arret.
local function setSlide(direction: number)
	if direction == slideDirection then
		return
	end
	slideDirection = direction

	local track = slideTrack
	if not track then
		return
	end

	if direction == 0 then
		track:Stop(HedgeConfigs.SLIDE_FADE)
		return
	end

	-- Le premier pas part a pleine poussee : demarrer a la vitesse de glissement donnerait un depart mou.
	-- La date est posee ICI et non a zero, sinon le repli de securite se declencherait le temps que le premier
	-- marqueur arrive, et chaque depart serait continu avant de passer au pas.
	stepStrength = HedgeConfigs.STEP_PUSH
	lastStepAt = os.clock()

	-- La piste est animee pour le pas chasse vers la GAUCHE. Vers la droite on la deroule a l'envers, d'ou la
	-- vitesse NEGATIVE.
	local speed = HedgeConfigs.SLIDE_SPEED * -direction

	if track.IsPlaying then
		-- On ne relance pas : la lecture repart d'ou elle en est, simplement dans l'autre sens. Les jambes
		-- changent de sens en continu au lieu de sauter a la premiere image.
		track:AdjustSpeed(speed)
		return
	end

	-- La vitesse est passee a Play et non reglee apres : sans troisieme argument, Play la remet a 1 et la
	-- premiere image partirait a l'endroit avant d'etre corrigee.
	track:Play(HedgeConfigs.SLIDE_FADE, 1, speed)
	if speed < 0 then
		-- Demarrer a l'envers depuis le debut : la lecture n'a nulle part ou reculer. On la place a la fin.
		-- TimePosition ne tient que sur une piste DEJA lancee, d'ou cette ligne apres Play et pas avant.
		track.TimePosition = track.Length
	end
end

-- Liste ce qui joue REELLEMENT sur le personnage. On interroge l'Animator au lieu de supposer : une piste
-- qu'on croit prioritaire et une piste qui l'est vraiment sont deux choses differentes, et seul le moteur sait.
local lastSlideLog = 0

local function logSlide(character: Model, stepping: boolean)
	if not HedgeConfigs.DEBUG_SLIDE then
		return
	end
	local now = os.clock()
	if now - lastSlideLog < 1 then
		return
	end
	lastSlideLog = now

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not (animator and animator:IsA("Animator")) then
		return
	end

	local lines = {}
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		table.insert(
			lines,
			`  {track.Name} | {track.Priority.Name} | poids {string.format("%.2f", track.WeightCurrent)} | vitesse {track.Speed}`
		)
	end
	-- Le mode compte AUTANT que les pistes : "continu" veut dire que les marqueurs n'arrivent plus, donc que
	-- le repli de securite a pris la main. C'est LA ligne a lire pour savoir si le pas chasse fonctionne.
	local mode = if stepping
		then `AU PAS (poussee {string.format("%.2f", stepStrength)})`
		else "CONTINU (aucun marqueur recu, repli)"
	print(`[HedgeController] {mode} | pistes ({#lines}) :\n` .. table.concat(lines, "\n"))
end

-- ===== DEBUG =====

local function getDebugPart(index: number): BasePart
	local existing = debugParts[index]
	if existing and existing.Parent then
		return existing
	end

	local part = Instance.new("Part")
	part.Name = `HedgeRayDebug_{index}`
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	-- CanTouch a false aussi : sans ca cette boite declencherait les Touched des autres systemes.
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	-- On voit A TRAVERS plutot que de retrecir la boite : sa taille EST celle qui est testee, la reduire
	-- ferait mentir le debug, et un debug qui ment coute plus cher que pas de debug du tout.
	part.Transparency = HedgeConfigs.DEBUG_TRANSPARENCY
	-- Dans Camera et non workspace : rien de ce qui vit la n'est replique ni sauvegarde, c'est l'endroit des
	-- objets purement visuels et locaux.
	part.Parent = workspace.CurrentCamera

	-- Part de portee CONSOMMEE avant de toucher. C'est le chiffre qui manque a l'oeil : de face, une barre
	-- courte et une barre longue se ressemblent, alors qu'elles ne disent pas du tout la meme chose.
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(64, 22)
	-- Decalees les unes au-dessus des autres : au centre elles se superposeraient et seraient illisibles.
	billboard.StudsOffset = Vector3.new(0, 0.8 * index, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	debugParts[index] = part
	debugLabels[index] = label
	return part
end

local function hideDebug()
	for index, part in pairs(debugParts) do
		-- Le label vit DANS la part : la detruire l'emporte. On vide juste la table, sinon elle garderait des
		-- references vers des objets morts.
		part:Destroy()
		debugParts[index] = nil
		debugLabels[index] = nil
	end
end

-- ===== CURSEUR SUR LA HAIE =====
-- Bille posee la ou le curseur touche la haie. C'est ce point qui deviendra l'endroit ou l'on taille : le
-- construire maintenant sert d'abord a VOIR ou on vise, et servira ensuite de cible reelle.

local function getCursorPart(): BasePart
	local existing = cursorPart
	if existing and existing.Parent then
		return existing
	end

	local part = Instance.new("Part")
	part.Name = "HedgeCursor"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * HedgeConfigs.CURSOR_SIZE
	part.Color = HedgeConfigs.CURSOR_COLOR
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	-- CanQuery a false fonctionne ici : la bille n'a pas de collision. Sans ca elle se trouverait elle-meme au
	-- lancer suivant et resterait collee devant la camera.
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = workspace.CurrentCamera

	cursorPart = part
	return part
end

local function hideCursor()
	if cursorPart then
		cursorPart:Destroy()
		cursorPart = nil
	end
end

-- Derniere haie visee. Gardee pour continuer a viser SA face meme quand le curseur en sort : sans elle, le
-- moindre debordement rendrait la visee nulle.
local lastHedge: BasePart? = nil

-- Rend la HAUTEUR VISEE sur la face de la haie, entre 0 (le pied) et 1 (le sommet), ou nil si le joueur ne
-- vise plus la haie. C'est cette valeur qui pilote la pose de coupe, et plus tard l'endroit reellement taille.
--
-- ON VISE LE PLAN DE LA FACE, PAS LA SURFACE TOUCHEE. Lire l'endroit ou le rayon tombe rendait la visee nulle
-- des qu'il ratait la haie d'un pixel : viser le pied pour le balayer proprement faisait glisser le curseur
-- sur le sol, et la pose sautait pile au moment ou le joueur travaillait. Le plan, lui, est infini : sortir
-- des bords ne le rate jamais, on n'a plus qu'a decider jusqu'ou on accepte de deborder.
local function updateCursor(character: Model, normal: Vector3): number?
	local camera = workspace.CurrentCamera
	if not camera then
		hideCursor()
		return nil
	end

	-- ViewportPointToRay et non ScreenPointToRay. VERIFIE A L'ECRAN : avec ScreenPointToRay la bille tombait
	-- environ 36 pixels sous le curseur, pile la hauteur de la barre Roblox. GetMouseLocation rend donc deja
	-- des coordonnees VIEWPORT, et ScreenPointToRay rajoutait l'inset une seconde fois.
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local buffers = workspace:FindFirstChild(HedgeConfigs.BUFFER_FOLDER)
	params.FilterDescendantsInstances = if buffers then { character, buffers } else { character }

	local result = workspace:Raycast(ray.Origin, ray.Direction * HedgeConfigs.CURSOR_RANGE, params)
	-- On lit l'ATTRIBUT et non le tag : un attribut se replique de facon certaine jusqu'au client.
	-- Ce lancer ne sert plus qu'a SAVOIR QUELLE HAIE on vise. La hauteur, elle, vient du plan.
	if result and result.Instance:GetAttribute(HedgeConfigs.HEDGE_MARK_ATTRIBUTE) == true then
		lastHedge = result.Instance
	end

	local hedge = lastHedge
	-- Parent verifie aussi : une haie detruite ou sortie du streaming laisserait une reference morte.
	if not (hedge and hedge.Parent) then
		hideCursor()
		return nil
	end

	-- PLAN DE LA FACE. Son point de passage est la surface de la haie du cote ou se tient le joueur.
	-- VectorToObjectSpace plutot que de piocher dans Size au hasard : ca marche aussi si la haie est tournee.
	local localNormal = hedge.CFrame:VectorToObjectSpace(normal)
	local half = hedge.Size * 0.5
	local depth = math.abs(localNormal.X * half.X) + math.abs(localNormal.Y * half.Y) + math.abs(localNormal.Z * half.Z)
	local planePoint = hedge.Position + normal * depth

	local direction = ray.Direction.Unit
	local denominator = direction:Dot(normal)
	-- Rayon quasi parallele au plan : l'intersection part a l'infini. Aucun resultat exploitable.
	if math.abs(denominator) < 1e-4 then
		hideCursor()
		return nil
	end
	local distance = (planePoint - ray.Origin):Dot(normal) / denominator
	-- Negatif : le plan est DERRIERE la camera, le joueur regarde ailleurs.
	if distance <= 0 then
		hideCursor()
		return nil
	end
	local point = ray.Origin + direction * distance

	local height = hedge.Size.Y
	if height <= 0 then
		hideCursor()
		return nil
	end

	-- On repasse dans le repere de la haie pour borner. Un plan est INFINI : sans ces bornes, viser vingt studs
	-- a cote de la haie donnait une visee parfaitement valide, et la pose de coupe se declenchait dans le vide.
	local localPoint = hedge.CFrame:PointToObjectSpace(point)

	-- Axe LATERAL : celui des deux axes horizontaux qui n'est pas celui de la face.
	local sideways, sidewaysHalf
	if math.abs(localNormal.X) > math.abs(localNormal.Z) then
		sideways, sidewaysHalf = localPoint.Z, half.Z
	else
		sideways, sidewaysHalf = localPoint.X, half.X
	end

	-- Meme marge dans toutes les directions : deborder d'un cheveu en balayant un bord ne doit pas lacher la
	-- visee, mais viser franchement a cote rend la main.
	local margin = HedgeConfigs.AIM_MARGIN
	if math.abs(localPoint.Y) > half.Y + margin or math.abs(sideways) > sidewaysHalf + margin then
		hideCursor()
		return nil
	end

	getCursorPart().Position = point

	-- ZONES MORTES. On remappe [deadzone, hauteur - deadzone] sur [0, 1] : tout ce qui est plus bas vaut le bas
	-- franc, tout ce qui est plus haut vaut le haut franc. Ce sont les positions les plus utilisees, elles
	-- doivent etre les plus faciles a tenir.
	local dead = math.min(HedgeConfigs.AIM_DEADZONE, height * 0.4)
	local usable = height - dead * 2
	if usable <= 0 then
		return 0.5
	end
	-- localPoint.Y va de -half.Y (le pied) a +half.Y (le sommet) : on le ramene d'abord a une hauteur au-dessus
	-- du pied.
	return math.clamp((localPoint.Y + half.Y - dead) / usable, 0, 1)
end

-- La couleur se decide LANCER PAR LANCER, plus globalement : savoir "une haie est detectee" n'apprend rien,
-- savoir LEQUEL des trois la voit et a quelle distance, si.
local function drawDebug(character: Model, origin: Vector3, direction: Vector3, length: number)
	if not HedgeConfigs.DEBUG_RAY then
		return
	end

	-- MEME volume et MEME filtre que le serveur : ce qu'on voit est exactement ce qui est teste. Oublier les
	-- boites d'espace vital ici ferait s'arreter la barre de debug avant la haie, alors que le serveur, lui,
	-- la detecte : le debug mentirait.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local buffers = workspace:FindFirstChild(HedgeConfigs.BUFFER_FOLDER)
	params.FilterDescendantsInstances = if buffers then { character, buffers } else { character }

	local size = Vector3.new(HedgeConfigs.DETECT_WIDTH, HedgeConfigs.DETECT_HEIGHT, HedgeConfigs.DETECT_THICKNESS)

	-- MEMES angles que le serveur. N'en dessiner qu'un masquerait les lancers de biais, et on ne comprendrait
	-- pas pourquoi une haie sur le cote est detectee.
	for index, angle in ipairs(HedgeConfigs.DETECT_ANGLES) do
		local rayDirection = CFrame.Angles(0, math.rad(angle), 0) * direction
		local start = CFrame.lookAt(origin, origin + rayDirection)
		local result = workspace:Blockcast(start, size, rayDirection * length, params)
		local drawLength = if result then result.Distance else length

		local part = getDebugPart(index)
		part.Size = Vector3.new(HedgeConfigs.DETECT_WIDTH, HedgeConfigs.DETECT_HEIGHT, math.max(drawLength, 0.05))
		-- Le recul de moitie fait PARTIR la boite de l'origine au lieu d'etre centree dessus.
		part.CFrame = start * CFrame.new(0, 0, -drawLength * 0.5)
		-- Couleur PAR LANCER et non plus globale : trois barres toutes vertes alors qu'une seule touchait ne
		-- disaient pas laquelle travaillait.
		part.Color = if result then HedgeConfigs.DEBUG_COLOR_HIT else HedgeConfigs.DEBUG_COLOR_MISS

		local label = debugLabels[index]
		if label then
			if result then
				label.Text = `{math.round(result.Distance / length * 100)}%`
				label.TextColor3 = HedgeConfigs.DEBUG_COLOR_HIT
			else
				label.Text = "vide"
				label.TextColor3 = HedgeConfigs.DEBUG_COLOR_MISS
			end
		end
	end
end

-- ===== TRANSITIONS =====

local function release(humanoid: Humanoid?)
	if not engaged then
		return
	end
	engaged = false
	-- On repart toujours d'une vue de face en revenant sur une haie : garder le pivot d'un chantier precedent
	-- placerait le joueur de biais sans qu'il comprenne pourquoi.
	yaw = 0
	orbiting = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	hideCursor()
	-- La haie memorisee n'a de sens que pendant le chantier : la garder ferait viser la precedente en arrivant
	-- sur la suivante, le temps que le premier lancer touche.
	lastHedge = nil
	-- Le pas chasse n'a de sens qu'au pied d'une haie. Sans cet arret il continuerait pendant que le joueur
	-- traverse le jardin, et il masquerait la marche : elle est en Movement, lui en Action.
	setSlide(0)
	-- Meme raison pour la pose de coupe : elle est en Action2, elle bloquerait les bras sur toute la carte.
	setUpDown(false, 0, 0)

	if humanoid then
		-- On rend au joueur le pivot automatique de son personnage.
		humanoid.AutoRotate = true
	end

	local camera = workspace.CurrentCamera
	if camera then
		-- Custom rend la main a la camera par defaut de Roblox. Elle reprend a SA position, il peut donc y avoir
		-- un petit saut : c'est le prix a payer pour ne pas reimplementer toute la camera par defaut.
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function engage(humanoid: Humanoid)
	if engaged then
		return
	end
	engaged = true

	-- Sans ca, Roblox tourne le personnage dans la direction ou il MARCHE : le joueur qui longe la haie se
	-- retrouverait de profil, et impossible de tailler.
	humanoid.AutoRotate = false

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

-- ===== BOUCLE =====

local function update(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not (character and humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		release(nil)
		hideDebug()
		hideCursor()
		return
	end

	local atHedge = character:GetAttribute(HedgeConfigs.AT_HEDGE_ATTRIBUTE) == true
	local normal = character:GetAttribute(HedgeConfigs.HEDGE_NORMAL_ATTRIBUTE)

	drawDebug(
		character,
		root.Position,
		root.CFrame.LookVector,
		if atHedge then HedgeConfigs.RAY_LENGTH_ENGAGED else HedgeConfigs.RAY_LENGTH
	)

	local camera = workspace.CurrentCamera
	if not (atHedge and typeof(normal) == "Vector3" and camera) then
		release(humanoid)
		return
	end

	engage(humanoid)

	-- ===== RAIL DE TRAVAIL =====
	-- Le joueur glisse LE LONG de la haie, a distance constante. On ne remappe pas ses touches : on retire de
	-- son deplacement la composante qui n'a nulle part ou aller. Q/D glissent, Z ne fait rien une fois en
	-- place, S sort (le serveur decroche des qu'il pousse vers l'arriere).
	--
	-- La distance CONSTANTE n'est pas du confort : sans elle le cadrage derive, et le meme geste de souris ne
	-- coupe plus au meme endroit. La taille deviendrait inapprenable.
	-- Les axes de travail sont ceux de la FACE, jamais ceux de la camera. Le joueur regarde la haie : sa droite
	-- longe la haie, son avant y va. Passer par la camera faisait partir D en diagonale des qu'elle etait
	-- decalee sur le cote.
	local right = (-normal):Cross(Vector3.yAxis).Unit

	-- L'input brut : X = pas de cote, Z = avant / arriere (negatif vers l'avant, convention Roblox).
	local moveVector = getMoveVector()

	-- SORTIE. Seule la part ARRIERE de l'axe Z compte : le joueur pousse franchement en arriere, il quitte le
	-- chantier. On le laisse partir SANS contrainte, et c'est cette direction non contrainte que le serveur lit
	-- dans MoveDirection pour decrocher tout de suite.
	if moveVector.Z > HedgeConfigs.EXIT_MIN_INPUT then
		-- Il s'en va : c'est de la marche normale, pas un pas chasse.
		setSlide(0)
		humanoid:Move(normal * moveVector.Z + right * moveVector.X, false)
		return
	end

	-- GLISSEMENT. La touche AVANT glisse dans le meme sens que la touche GAUCHE : devant la haie il n'y a nulle
	-- part ou avancer, autant que la touche serve plutot que de ne rien faire.
	--
	-- math.min(Z, 0) ne garde que l'avant : la part arriere vient d'etre traitee comme une sortie, elle ne doit
	-- surtout pas se transformer en glissement, sinon S ne ferait plus sortir.
	local lateral = math.clamp(moveVector.X + math.min(moveVector.Z, 0), -1, 1)

	-- Les jambes suivent le sens du glissement. On lit `lateral` et non l'input brut : c'est le deplacement
	-- REEL apres contrainte, donc avant + droite qui s'annulent laissent bien le joueur immobile ET jambes au
	-- repos, au lieu de le figer sur place en continuant a pietiner.
	setSlide(if math.abs(lateral) < HedgeConfigs.SLIDE_MIN_INPUT then 0 else math.sign(lateral))

	-- DEPLACEMENT AU PAS. Le corps avance quand le PIED POUSSE, puis il glisse sur son elan jusqu'au pas
	-- suivant. La poussee vient du marqueur de l'animation, cette ligne ne fait que la laisser retomber.
	stepStrength = math.max(HedgeConfigs.STEP_GLIDE, stepStrength - HedgeConfigs.STEP_DECAY * dt)

	-- Repli : sans marqueur depuis trop longtemps, on repasse en continu plutot que de bloquer le joueur.
	local stepping = os.clock() - lastStepAt < HedgeConfigs.STEP_TIMEOUT
	local constrained = right * lateral * (if stepping then stepStrength else 1)

	logSlide(character, stepping)

	-- AIMANT. La distance est mesuree ICI, par un lancer local vers la haie, et NON lue depuis le serveur : une
	-- valeur repliquee arrive avec du retard, l'aimant corrigerait donc une position perimee et se mettrait a
	-- osciller.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local buffers = workspace:FindFirstChild(HedgeConfigs.BUFFER_FOLDER)
	params.FilterDescendantsInstances = if buffers then { character, buffers } else { character }

	local measure = workspace:Raycast(root.Position, -normal * HedgeConfigs.MEASURE_RANGE, params)
	if measure then
		local gap = measure.Distance - HedgeConfigs.WORK_DISTANCE
		-- Rappel PROPORTIONNEL a l'ecart dans les deux cas : il faiblit en approchant de la cible, donc il ne
		-- la depasse jamais et n'oscille pas autour.
		if gap > HedgeConfigs.WORK_DISTANCE_TOLERANCE then
			-- TROP LOIN. La normale sort de la haie : s'en rapprocher, c'est aller dans son sens INVERSE.
			local strength = math.clamp(gap / HedgeConfigs.MAGNET_RANGE, 0, 1) * HedgeConfigs.MAGNET_STRENGTH
			constrained += -normal * strength
		elseif gap < -HedgeConfigs.WORK_DISTANCE_TOLERANCE then
			-- TROP PRES. Cette poussee arriere avait ete supprimee parce que le serveur la confondait avec
			-- l'intention de sortir : il decrochait, ca raccrochait, l'aimant repoussait, ca redecrochait.
			-- Elle revient parce que le serveur sait maintenant s'en garder : tant que la distance de travail
			-- n'est pas retablie, il NE JUGE PLUS l'intention de sortir (voir HedgeService.updatePlayer).
			-- On ne cherche donc plus a distinguer les deux signaux : on choisit quand la question se pose.
			local strength = math.clamp(-gap / HedgeConfigs.MAGNET_RANGE, 0, 1) * HedgeConfigs.MAGNET_PUSH_STRENGTH
			constrained += normal * strength
		end
	end

	-- Move ecrase la direction calculee par le module de controle. On ne l'appelle QUE pendant l'accroche :
	-- hors haie, le joueur doit retrouver son deplacement normal.
	humanoid:Move(constrained, false)

	-- ORIENTATION. La normale sort de la haie ; le joueur doit donc regarder dans le sens INVERSE.
	local position = root.Position
	local lookTarget = position - normal
	local desired = CFrame.lookAt(position, lookTarget)
	-- Lerp exponentiel avec dt dans le facteur : meme vitesse de pivot a 30 et a 60 FPS.
	root.CFrame = root.CFrame:Lerp(desired, math.min(1, HedgeConfigs.FACE_TURN_SPEED * dt))

	-- CAMERA. Placee du cote du joueur, en retrait le long de la normale, avec un decalage lateral qui donne
	-- l'angle 3/4. On la calcule a partir de la NORMALE et non du regard du joueur : elle reste donc stable
	-- pendant que le personnage pivote.
	--
	-- Le pivot du joueur tourne la NORMALE utilisee par la camera, pas le personnage : celui-ci reste face a la
	-- haie pendant qu'on regarde son travail sous un autre angle.
	local viewNormal = CFrame.Angles(0, yaw, 0) * normal
	-- Le cote se prend perpendiculairement a cette direction, dans le plan horizontal.
	local side = viewNormal:Cross(Vector3.yAxis).Unit
	-- Accelerer rapproche la camera : l'attention se resserre sur le geste. Le lerp de la camera fait la
	-- transition tout seul, il n'y a rien de plus a ecrire.
	local throttling = character:GetAttribute(HedgeConfigs.THROTTLE_ATTRIBUTE) == true
	local distance = if throttling then HedgeConfigs.CAMERA_DISTANCE_THROTTLE else HedgeConfigs.CAMERA_DISTANCE
	local camPosition = position
		+ viewNormal * distance
		+ side * HedgeConfigs.CAMERA_SIDE
		+ Vector3.new(0, HedgeConfigs.CAMERA_HEIGHT, 0)
	local camLook = position + Vector3.new(0, HedgeConfigs.CAMERA_LOOK_HEIGHT, 0)

	local target = CFrame.lookAt(camPosition, camLook)
	camera.CFrame = camera.CFrame:Lerp(target, math.min(1, HedgeConfigs.CAMERA_LERP_SPEED * dt))

	-- Humanoid.CameraOffset n'est applique que par la camera par defaut de Roblox : en Scriptable il est
	-- ignore. Sans cette ligne, secousses, bob et plongee disparaitraient des qu'on travaille une haie, donc
	-- exactement la ou le retour de coupe devra se voir.
	-- Applique APRES le lerp et en repere local, pour que le decalage ne soit pas lisse : un impact doit
	-- claquer, pas se fondre.
	camera.CFrame = camera.CFrame * CFrame.new(CameraEffects.GetOffset())

	-- Apres la camera : la bille se calcule depuis la camera de CETTE frame, sinon elle viserait a partir de
	-- l'image precedente et flotterait en arriere pendant les pivots.
	local aim = updateCursor(character, normal)

	-- HAUTEUR DE COUPE. La pose ne sort que moteur EN MARCHE : lever le taille-haie vers le haut de la haie
	-- alors qu'il est eteint n'a aucun sens, le joueur ne taille rien.
	local engine = character:GetAttribute(HedgeConfigs.ENGINE_ATTRIBUTE) == true
	setUpDown(engine and aim ~= nil, aim or 0, dt)
end

function HedgeController.init()
	-- BindToRenderStep a la priorite Camera, et NON un simple RenderStepped.
	--
	-- Le module de controle de Roblox tourne a la priorite Input (100) et appelle humanoid:Move avec l'input
	-- brut. Notre contrainte doit passer APRES, sinon il ecraserait la notre et le joueur pourrait avancer et
	-- reculer librement. Camera (200) garantit cet ordre ; un RenderStepped simple ne le garantit pas.
	RunService:BindToRenderStep("LeafiaHedge", Enum.RenderPriority.Camera.Value, update)

	-- Les pistes se chargent au spawn, JAMAIS dans la boucle : setupCharacter attend l'Animator, et un
	-- WaitForChild dans un BindToRenderStep bloquerait le rendu de la frame.
	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		task.spawn(setupCharacter, player.Character)
	end

	-- PIVOT au clic DROIT maintenu. Le gauche reste a l'outil et le curseur reste libre pour viser la haie ;
	-- le bouton droit est le seul disponible.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not engaged then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbiting = true
			-- Le curseur reste sur place pendant le glissement : sans ca il partirait hors de l'ecran au bout
			-- de deux pivots, et la bille de visee avec lui.
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		-- Pas de filtre gameProcessed au relachement : le pivot ne doit jamais rester coince.
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbiting = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not (orbiting and engaged) then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		-- Seul le deplacement HORIZONTAL compte : la hauteur de vue reste celle du reglage, on ne veut pas que
		-- le joueur puisse se retrouver a regarder ses pieds ou le ciel en plein travail.
		local limit = math.rad(HedgeConfigs.CAMERA_YAW_LIMIT)
		yaw = math.clamp(yaw - math.rad(input.Delta.X * HedgeConfigs.CAMERA_YAW_SENSITIVITY), -limit, limit)
	end)

	player.CharacterRemoving:Connect(function()
		-- Le personnage disparait : on relache tout, sinon la camera resterait bloquee en Scriptable sur un
		-- personnage mort et le joueur ne verrait plus rien apres son respawn.
		release(nil)
		hideDebug()
		hideCursor()
		-- Les pistes appartiennent a l'Animator qui part avec le personnage : les garder ferait travailler sur
		-- des pistes mortes au prochain spawn, sans jamais d'erreur pour le signaler.
		slideTrack = nil
		updownTrack = nil
		slideDirection = 0
	end)
end

return HedgeController
