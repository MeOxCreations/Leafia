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
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local CameraEffects = require(script.Parent.Utils.CameraEffects)
local CharacterFade = require(script.Parent.Utils.CharacterFade)

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

-- Normale de travail REELLEMENT appliquee, en monde. Elle poursuit la geometrie sans jamais tourner plus vite
-- que CORNER_TURN_SPEED. Remise a nil au decrochage : on se recale d'emblee sur la haie suivante au lieu d'y
-- arriver en pivotant depuis la precedente.
local workNormal: Vector3? = nil

-- Avancement du fondu du personnage, de 0 (opaque) a 1 (fantome au dosage regle).
local workFade = 0

-- Facteur de zoom de la camera de travail. 1 = le placement du reglage.
--
-- Il N'EST PAS remis a zero au decrochage, contrairement au pivot : c'est un confort de vue que le joueur
-- choisit une fois, pas un coup d'oeil ponctuel. Le reinitialiser a chaque haie le lui reprendrait.
local cameraZoom = 1

-- Module de controle par defaut de Roblox. On lui demande l'input BRUT du joueur.
--
-- POURQUOI PAS humanoid.MoveDirection : des qu'on contraint le deplacement avec humanoid:Move(), MoveDirection
-- devient NOTRE valeur contrainte. On lirait donc notre propre sortie, et l'intention de reculer du joueur
-- serait invisible : impossible de detecter qu'il veut sortir.
-- GetMoveVector rend l'input tel qu'il a ete saisi, avant toute contrainte, et sans dependre du clavier
-- (AZERTY ou QWERTY, c'est le module de Roblox qui s'en occupe).
local controlModule: any = nil

-- Filtre commun a TOUS les lancers qui cherchent une haie : detection, curseur, mesure de l'aimant, debug.
--
-- Centralise expres. Il y avait trois copies de ces quatre lignes ; le jour ou un nouveau dossier doit etre
-- ignore, en oublier une donne un bug qui ne se manifeste que dans un des trois cas, et on cherche loin.
--
-- Ce qu'on exclut :
--   le personnage      -- sans lui le lancer taperait dans l'outil qu'il tient, a zero stud
--   les espaces vitaux -- ils entourent chaque haie, ils seraient touches AVANT elle
--   les carreaux       -- ils sont poses SUR la haie, meme probleme
-- Un filtre exclut une instance ET ses descendants : d'ou les dossiers a part, jamais ranges dans la haie.
local function hedgeRayParams(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local ignore: { Instance } = { character }
	for _, folderName in ipairs({ HedgeConfigs.BUFFER_FOLDER, HedgeConfigs.CELL_FOLDER }) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			table.insert(ignore, folder)
		end
	end
	params.FilterDescendantsInstances = ignore
	return params
end

-- ===== ENVOI DE LA VISEE =====
-- Le serveur ne peut PAS lire la hauteur de la lame : la pose des bras est jouee ici et pilotee image par
-- image, or Roblox replique le demarrage d'une animation, pas son defilement. Cote serveur l'outil reste donc
-- fige a une hauteur, et la coupe ne tomberait juste que par hasard.
--
-- On lui envoie donc l'INTENTION, pas le resultat : il garde l'autorite sur la vitesse de coupe et sur la haie
-- concernee, le client ne lui dit que ou il vise.
local aimRemote: RemoteEvent? = nil
-- Les deux bouts de la lame REELLEMENT envoyes : ce que le serveur a en main, pour le debug.
local lastAimBase: Vector3? = nil
local lastAimTip: Vector3? = nil
local lastAimAt = 0

local function sendAim(base: Vector3?, tip: Vector3?)
	local remote = aimRemote
	if not remote then
		return
	end

	if base == nil or tip == nil then
		lastAimBase = nil
		lastAimTip = nil
		return
	end

	-- Rien de neuf : on se tait. Un envoi par frame ferait soixante paquets par seconde et par joueur pour une
	-- lame qui bouge a peine. On juge le mouvement sur le MILIEU du segment, qui resume son deplacement.
	local now = os.clock()
	local middle = (base + tip) * 0.5
	local previous = if lastAimBase and lastAimTip then (lastAimBase + lastAimTip) * 0.5 else nil
	local moved = previous == nil or (middle - previous).Magnitude >= HedgeConfigs.AIM_SEND_STEP
	if not (moved and now - lastAimAt >= HedgeConfigs.AIM_SEND_INTERVAL) then
		return
	end

	lastAimBase = base
	lastAimTip = tip
	lastAimAt = now
	remote:FireServer(base, tip)
end

-- Derniere haie visee. Gardee pour continuer a viser SA face meme quand le curseur en sort : sans elle, le
-- moindre debordement rendrait la visee nulle. Declaree ici parce que le debug de coupe en a besoin AVANT
-- le curseur : en Luau, on n'appelle jamais au-dessus de sa definition.
local lastHedge: BasePart? = nil

-- ===== DEBUG : LA ZONE DE COUPE =====
-- Dessine le disque que le SERVEUR teste, sur la face de la haie.
--
-- Construit avec la MEME formule que HedgeCutService et avec la DERNIERE visee ENVOYEE : ce qu'on voit est
-- donc ce que le serveur a reellement en main, pas ce qu'on croit lui avoir dit. Un debug qui montre notre
-- propre version ne sert a rien quand on cherche un ecart entre les deux.
local cutZonePart: BasePart? = nil
-- Highlight du repere, garde pour teindre son remplissage selon l'etat sans le rechercher chaque frame.
local cutZoneHighlight: Highlight? = nil
local cutHitbox: BasePart? = nil

-- Apparence du repere selon ce que fait le joueur : guide (vise, pas encore taille), coupe (gachette pressee),
-- hors haie (souris sortie). Couleur + transparence changent, la forme non.
type CutLook = { color: Color3, transparency: number }
local CUT_LOOK: { [string]: CutLook } = {
	guide = { color = HedgeConfigs.DEBUG_CUT_GUIDE_COLOR, transparency = HedgeConfigs.DEBUG_CUT_GUIDE_TRANSPARENCY },
	cutting = { color = HedgeConfigs.DEBUG_CUT_CUT_COLOR, transparency = HedgeConfigs.DEBUG_CUT_CUT_TRANSPARENCY },
	off = { color = HedgeConfigs.DEBUG_CUT_OFF_COLOR, transparency = HedgeConfigs.DEBUG_CUT_OFF_TRANSPARENCY },
}

local function getCutZonePart(): BasePart
	local existing = cutZonePart
	if existing and existing.Parent then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "HedgeCutZoneDebug"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	-- Un CYLINDRE couche le long de la lame : c'est la vraie forme testee, une capsule (segment + rayon). Il
	-- montre donc fidelement la zone de coupe, base a pointe, a la vraie largeur.
	part.Shape = Enum.PartType.Cylinder

	-- HIGHLIGHT EN ALWAYS-ON-TOP. La capsule est noyee dans les feuilles qui depassent : une fois le joueur en
	-- place, on ne la voit plus. Le Highlight la redessine par-dessus tout, a travers les feuilles, sans qu'on
	-- ait a la detecter ni a la sortir de la haie. C'est le seul moyen simple de faire voir une part a coup sur,
	-- quel que soit ce qui est devant. Couleur et remplissage sont poses par frame, selon l'etat.
	cutZoneHighlight = nil
	if HedgeConfigs.DEBUG_CUT_ALWAYS_ON_TOP then
		local highlight = Instance.new("Highlight")
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.OutlineTransparency = HedgeConfigs.DEBUG_CUT_OUTLINE
		highlight.Adornee = part
		highlight.Parent = part
		cutZoneHighlight = highlight
	end

	-- Dans le Workspace et NON sous la Camera : un Highlight ne s'affiche de facon fiable que sur une part du
	-- Workspace. C'est inerte de toute facon (Anchored, CanQuery/Touch/Collide a false), donc ca ne gene rien.
	part.Parent = workspace
	cutZonePart = part
	return part
end

local function hideCutZone()
	if cutZonePart then
		cutZonePart:Destroy()
		cutZonePart = nil
	end
end

-- La boite de lame, cote CLIENT. Ici elle est a la BONNE place : c'est nous qui jouons l'animation.
local function findBlade(character: Model): BasePart?
	local cached = cutHitbox
	if cached and cached.Parent and cached:IsDescendantOf(character) then
		return cached
	end
	local found = character:FindFirstChild("HitBoxRoot", true)
	cutHitbox = if found and found:IsA("BasePart") then found else nil
	return cutHitbox
end

-- Les deux bouts de la lame, en monde : base et pointe, le long de son axe le PLUS LONG.
--
-- C'est nous qui jouons l'animation, donc la CFrame de la boite est ici a la BONNE place. On envoie ce segment
-- au serveur, qui taille tout ce qui est a portee de cette LIGNE : c'est ce qui fait couper le BOUT de la lame,
-- que la sphere centree sur un point ratait.
local function bladeSegment(blade: BasePart): (Vector3, Vector3)
	local size = blade.Size
	local axis: Vector3, half: number
	if size.X >= size.Y and size.X >= size.Z then
		axis, half = Vector3.xAxis, size.X * 0.5
	elseif size.Y >= size.Z then
		axis, half = Vector3.yAxis, size.Y * 0.5
	else
		axis, half = Vector3.zAxis, size.Z * 0.5
	end
	local reach = blade.CFrame:VectorToWorldSpace(axis) * half
	return blade.Position - reach, blade.Position + reach
end

-- Rayon PERPENDICULAIRE de la coupe. Meme valeur que le serveur (CUT_RADIUS + marge), pour que le debug montre
-- la vraie capsule et pas une approximation.
local function cutRadius(): number
	return HedgeConfigs.CUT_RADIUS + HedgeConfigs.CUT_MARGIN
end

local function drawCutZone(base: Vector3?, tip: Vector3?, state: string)
	if not HedgeConfigs.DEBUG_CUT then
		return
	end
	if not base or not tip then
		hideCutZone()
		return
	end

	-- LA CAPSULE, dessinee sur le SEGMENT ENVOYE : ce que le serveur a en main. Un cylindre couche le long de la
	-- lame, de la vraie largeur (diametre = 2 * rayon de coupe). On montre donc la zone reelle, base a pointe, au
	-- lieu d'un disque centre sur un point qui laissait croire que le bout ne coupait pas.
	local part = getCutZonePart()
	local segment = tip - base
	local length = segment.Magnitude
	if length < 1e-3 then
		hideCutZone()
		return
	end

	local direction = segment / length
	-- Un cylindre a son axe sur X : on met X le long de la lame. Le deuxieme axe est un perpendiculaire
	-- quelconque ; la verticale sauf si la lame est deja verticale, auquel cas on prend l'horizontale.
	local up = if math.abs(direction.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local perpendicular = up:Cross(direction).Unit
	local diameter = cutRadius() * 2
	part.Size = Vector3.new(length, diameter, diameter)
	part.CFrame = CFrame.fromMatrix((base + tip) * 0.5, direction, perpendicular)

	-- ETAT : guide (bien visible), coupe (discret), hors haie (orange). La transparence sert au corps ET au
	-- remplissage du Highlight, pour qu'ils racontent la meme chose. Le contour du Highlight, lui, reste net.
	local look = CUT_LOOK[state] or CUT_LOOK.guide
	part.Color = look.color
	part.Transparency = look.transparency
	local highlight = cutZoneHighlight
	if highlight then
		highlight.FillColor = look.color
		highlight.OutlineColor = look.color
		highlight.FillTransparency = look.transparency
	end
end

-- ===== SON DE COUPE =====
-- Une COPIE par coup, et non la meme instance relancee : relancer coupe le son en cours a chaque fois, on
-- n'entendrait donc que son attaque, en boucle. Des copies se superposent comme de vraies coupes.
local cutSounds: { Sound } = {}
local lastCutSoundAt = 0
-- Dernier echantillon joue. Sert a ne pas le reprendre deux fois de suite : avec deux sons, un tirage
-- totalement libre en repete un une fois sur deux, et l'oreille l'entend tout de suite.
local lastCutIndex = 0

local function playCut()
	local count = #cutSounds
	if count == 0 then
		return
	end
	local now = os.clock()
	if now - lastCutSoundAt < HedgeConfigs.CUT_SOUND_INTERVAL then
		return
	end
	lastCutSoundAt = now

	local index = math.random(count)
	if count > 1 and index == lastCutIndex then
		-- Decale d'un cran plutot que de retirer au hasard : un nouveau tirage pourrait retomber sur le meme,
		-- et boucler. Ici on sort a coup sur, en une operation.
		index = index % count + 1
	end
	lastCutIndex = index

	local source = cutSounds[index]
	local copy = source:Clone()
	-- Hauteur ET volume tires au hasard. Le meme echantillon repete a l'identique se reconnait comme une
	-- boucle en trois secondes ; ces deux variations suffisent a le rendre vivant.
	local pitch = HedgeConfigs.CUT_SOUND_PITCH
	local volume = HedgeConfigs.CUT_SOUND_VOLUME
	copy.PlaybackSpeed = source.PlaybackSpeed * (1 + (math.random() - 0.5) * 2 * pitch)
	copy.Volume = source.Volume * (1 + (math.random() - 0.5) * 2 * volume)
	copy.Parent = SoundService
	copy:Play()
	-- Se detruit tout seul a la fin : pas de liste a tenir, pas de fuite possible.
	copy.Ended:Connect(function()
		copy:Destroy()
	end)
end

-- ===== FEUILLES QUI VOLENT VERS LA ZONE =====
-- Une trainee part de la lame et retombe dans la bande de depot. Elle RELIE le geste au tas : sans elle, des
-- feuilles apparaissent au sol sans qu'on ait vu comment elles y sont allees.
--
-- La bande visee est cherchee par DISTANCE A SA SURFACE, exactement comme le serveur choisit ou poser le tas.
-- On ne peut pas la retrouver par son nom : plusieurs haies portent le meme, donc leurs dossiers aussi.
local flyTemplate: BasePart? = nil

type Flyer = {
	part: BasePart,
	from: Vector3,
	apex: Vector3,
	to: Vector3,
	elapsed: number,
	spin: number,
}

local flyers: { Flyer } = {}

-- Point de chute : la bande la plus proche des pieds du joueur, au point ou il se tient.
local function dropPoint(feet: Vector3): Vector3?
	local folder = workspace:FindFirstChild(HedgeConfigs.STOCK_FOLDER)
	if not folder then
		return nil
	end

	local zone: BasePart? = nil
	local best = math.huge
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local localPoint = descendant.CFrame:PointToObjectSpace(feet)
			local half = descendant.Size * 0.5
			local clamped = Vector3.new(
				math.clamp(localPoint.X, -half.X, half.X),
				math.clamp(localPoint.Y, -half.Y, half.Y),
				math.clamp(localPoint.Z, -half.Z, half.Z)
			)
			local distance = (localPoint - clamped).Magnitude
			if distance < best then
				best = distance
				zone = descendant
			end
		end
	end
	if not zone then
		return nil
	end

	-- MEME regle que le serveur pour poser le tas : le long de la haie on suit le joueur, en profondeur c'est
	-- le reglage. Les deux tombent donc au meme endroit sans avoir a se parler.
	local half = zone.Size * 0.5
	local inset = HedgeConfigs.STOCK_DEBRIS_INSET
	local localFeet = zone.CFrame:PointToObjectSpace(feet)
	local depthMin, depthMax = -(half.Z - inset), half.Z - inset
	-- Tirage INDEPENDANT de celui du serveur, et c'est sans consequence : les trainees partent sept fois par
	-- seconde, les tas une fois tous les six carreaux finis. Les deux ne sont deja pas synchronises, seule
	-- compte la zone commune.
	local spread = (math.random() - 0.5) * 2 * HedgeConfigs.STOCK_DEBRIS_OUT_SPREAD
	local ratio = math.clamp(HedgeConfigs.STOCK_DEBRIS_OUT + spread, 0, 1)
	local depth = depthMin + (depthMax - depthMin) * ratio
	return zone.CFrame
		* CFrame.new(math.clamp(localFeet.X, -half.X, half.X), half.Y, depth).Position
end

local function flyDebris(from: Vector3, feet: Vector3)
	local source = flyTemplate
	if not source or #flyers >= HedgeConfigs.FLY_MAX then
		return
	end
	local landing = dropPoint(feet)
	if not landing then
		return
	end

	local part = source:Clone()
	part.CFrame = CFrame.new(from)
	part.Parent = workspace.CurrentCamera

	table.insert(flyers, {
		part = part,
		from = from,
		-- Sommet au MILIEU du trajet et plus haut que les deux bouts : c'est ce qui fait l'arc.
		apex = (from + landing) * 0.5 + Vector3.new(0, HedgeConfigs.FLY_ARC, 0),
		to = landing,
		elapsed = 0,
		spin = math.random() * math.pi * 2,
	})
end

local function stepFlyers(dt: number)
	local duration = HedgeConfigs.FLY_TIME
	-- Parcours a l'ENVERS : retirer un element pendant qu'on avance decalerait les suivants et on en sauterait
	-- un a chaque suppression.
	for index = #flyers, 1, -1 do
		local flyer = flyers[index]
		flyer.elapsed += dt

		if flyer.elapsed >= duration or not flyer.part.Parent then
			flyer.part:Destroy()
			table.remove(flyers, index)
			continue
		end

		local t = flyer.elapsed / duration
		local inverse = 1 - t
		-- Bezier quadratique : (1-t)^2 * A + 2(1-t)t * B + t^2 * C
		local position = flyer.from * (inverse * inverse)
			+ flyer.apex * (2 * inverse * t)
			+ flyer.to * (t * t)
		flyer.part.CFrame = CFrame.new(position)
			* CFrame.Angles(0, flyer.spin + flyer.elapsed * HedgeConfigs.FLY_SPIN * math.pi * 2, 0)
	end
end

-- ===== PARTICULES DE COUPE =====
-- Emises la ou le curseur touche la haie, donc exactement la ou la lame travaille.
--
-- COTE CLIENT : des particules sont du ressenti pur. Les faire naitre sur le serveur reviendrait a payer du
-- reseau pour quelque chose que chaque machine sait calculer seule.
local cutEffect: BasePart? = nil
local cutHolder: BasePart? = nil
local cutEmitters: { ParticleEmitter } = {}
local warnedMissingEffect = false

-- UN SEUL support, cree une fois, deplace a chaque coupe.
--
-- Le cloner a chaque fois coutait une creation et une destruction six fois par seconde. Inutile : une
-- particule deja emise vit dans le MONDE, pas dans son emetteur. Deplacer le support n'emporte donc pas les
-- bouffees precedentes, elles restent la ou elles sont nees.
local function ensureCutHolder(): BasePart?
	local existing = cutHolder
	if existing and existing.Parent then
		return existing
	end

	local template = cutEffect
	if not template then
		return nil
	end

	local holder = template:Clone()
	holder.Anchored = true
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	-- Dans la camera : purement local, jamais replique.
	holder.Parent = workspace.CurrentCamera

	table.clear(cutEmitters)
	for _, descendant in ipairs(holder:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			-- COUPE. Un emetteur laisse actif cracherait en continu ; on ne veut que la bouffee de Emit, calee
			-- sur le moment exact de la coupe.
			descendant.Enabled = false
			table.insert(cutEmitters, descendant)
		end
	end

	cutHolder = holder
	return holder
end

local function emitCut(position: Vector3)
	-- Nom vide : effet volontairement coupe. On sort AVANT le test d'existence, pour ne pas avertir de
	-- l'absence de quelque chose qu'on a decide de ne pas utiliser.
	if HedgeConfigs.CUT_EFFECT == "" then
		return
	end

	if not cutEffect then
		if not warnedMissingEffect then
			warnedMissingEffect = true
			-- Anormal ET actionnable : sans cet effet la coupe n'a aucun retour visuel, et on chercherait
			-- longtemps pourquoi le geste parait mou.
			warn(
				`[HedgeController] Effet de coupe introuvable : `
					.. `ReplicatedStorage.Assets.Effects.{HedgeConfigs.CUT_EFFECT}`
			)
		end
		return
	end

	local holder = ensureCutHolder()
	if not holder then
		return
	end
	holder.CFrame = CFrame.new(position)

	for _, emitter in ipairs(cutEmitters) do
		-- Le nombre se regle emetteur par emetteur dans Studio, avec un repli sur la config. Une bourrasque de
		-- feuilles et une poussiere fine n'ont aucune raison d'emettre la meme quantite.
		emitter:Emit(emitter:GetAttribute("EmitCount") or HedgeConfigs.CUT_EFFECT_COUNT)
	end
end

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
-- Pose pour le DESSUS. Une piste par ORIENTATION de surface : tailler un mur vertical et une table
-- horizontale ne sont pas le meme geste, et le corps ne se place pas pareil.
local rightleftTrack: AnimationTrack? = nil
-- Piste actuellement en scene. Retenue pour ne faire la transition qu'UNE fois au changement de surface.
local poseTrack: AnimationTrack? = nil
-- Hauteur suivie en ce moment, entre 0 et 1. Distincte de la hauteur VISEE : elle la rejoint progressivement,
-- sinon les bras claqueraient d'une position a l'autre au moindre saut de curseur.
local updownRatio = 0
-- Vitesse du ressort. C'est elle qui cree le RETARD : elle part de zero, il faut donc un instant avant que les
-- bras bougent vraiment, puis ils rattrapent la souris. Un simple lissage n'a pas cette inertie, il demarre a
-- pleine vitesse et ne fait que ralentir.
local updownVelocity = 0

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

	-- SECOUSSE A LA COUPE. Le serveur incremente un compteur quand des feuilles tombent reellement ; on ne
	-- reagit donc jamais a un passage de lame dans le vide.
	--
	-- Connectee sur le PERSONNAGE : elle meurt avec lui, il n'y a rien a couper a la main. C'est aussi pour ca
	-- que l'attribut est pose la et pas sur le joueur.
	-- LA LAME QUI FORCE. Secousse SEPAREE de celle de la coupe, et plus forte : mordre dans du bois deja au ras
	-- n'est pas tailler, et le joueur doit sentir la difference AVANT que le rouge la lui montre.
	--
	-- Elle demarre AVEC le rouge, et monte jusqu'a ce que le carreau soit perdu. La main et l'oeil disent la
	-- meme chose au meme moment : le joueur relie donc tout de suite la gene a ce qu'il voit.
	character:GetAttributeChangedSignal(HedgeConfigs.DAMAGE_TICK_ATTRIBUTE):Connect(function()
		local level = character:GetAttribute(HedgeConfigs.DAMAGE_LEVEL_ATTRIBUTE)
		local raw = if typeof(level) == "number" then level else 0
		-- Remappee sur [seuil, 1] : la secousse part de son minimum PILE au seuil, au lieu de commencer deja
		-- a mi-course parce que la valeur brute y est deja haute.
		local start = HedgeConfigs.DAMAGE_SHAKE_START
		local ratio = math.clamp((raw - start) / math.max(1 - start, 1e-3), 0, 1)
		local intensity = HedgeConfigs.DAMAGE_SHAKE_MIN
			+ (HedgeConfigs.DAMAGE_SHAKE_MAX - HedgeConfigs.DAMAGE_SHAKE_MIN) * ratio
		CameraEffects.Shake(intensity, HedgeConfigs.DAMAGE_SHAKE_DURATION)
	end)

	character:GetAttributeChangedSignal(HedgeConfigs.CUT_TICK_ATTRIBUTE):Connect(function()
		CameraEffects.Shake(HedgeConfigs.CUT_SHAKE_INTENSITY, HedgeConfigs.CUT_SHAKE_DURATION)
		playCut()
		-- Les particules naissent A LA LAME, et non au curseur.
		--
		-- Le curseur est ce que le joueur VISE, la lame est ce qui COUPE. Les deux ne coincident pas : le
		-- ressort met un instant a rattraper la souris. Des feuilles qui jaillissent d'un point ou la lame
		-- n'est pas encore cassent le lien entre le geste et sa consequence.
		-- On prend la position COURANTE et non celle envoyee au serveur : a l'ecran, c'est la lame visible qui
		-- doit projeter les debris.
		local blade = findBlade(character)
		if blade then
			emitCut(blade.Position)

			-- La trainee part de la LAME et retombe aux pieds du joueur, la ou le serveur posera le tas. Les
			-- deux suivent la meme regle, donc le trajet et son resultat tombent au meme endroit.
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				flyDebris(blade.Position, root.Position)
			end
		end
	end)

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

	local rightleft = loadTrack(animator, HedgeConfigs.RIGHTLEFT_ANIMATION, HedgeConfigs.UPDOWN_PRIORITY)
	if rightleft then
		rightleft.Looped = false
		rightleftTrack = rightleft
	end
end

-- active : le joueur vise-t-il une haie, moteur en marche.
-- ratio  : 0 a 1 sur la surface visee (bas vers haut sur un cote, bord proche vers bord oppose sur le dessus).
-- onTop  : le curseur est-il sur le DESSUS de la haie.
local function setPose(active: boolean, ratio: number, onTop: boolean, dt: number)
	local wanted = if onTop then rightleftTrack else updownTrack

	-- CHANGEMENT DE SURFACE. On coupe l'ancienne pose EN FONDU et on lance la nouvelle : les deux se croisent,
	-- donc le corps glisse d'un geste a l'autre au lieu de claquer.
	if poseTrack ~= wanted then
		if poseTrack and poseTrack.IsPlaying then
			poseTrack:Stop(HedgeConfigs.UPDOWN_FADE)
		end
		poseTrack = wanted
		-- L'elan repart de zero : garder celui de l'autre surface enverrait les bras dans le sens du geste
		-- precedent, qui n'a plus rien a voir.
		updownVelocity = 0
		updownRatio = ratio
	end

	local track = wanted
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
		-- On part de la position visee et non de la derniere connue : sinon les bras balaieraient toute la haie
		-- au premier affichage, depuis la position qu'ils avaient au chantier precedent.
		updownRatio = ratio
		updownVelocity = 0
	end

	-- RESSORT AMORTI AU CRITIQUE. F = -k*x - c*v, integre en Euler.
	--
	-- k = f^2 et c = 2*f donnent l'amortissement critique EXACT : le plus rapide qui n'oscille pas. Un
	-- depassement ferait osciller la hauteur de coupe autour du point vise, et on ne pourrait plus tailler droit.
	-- Le retard vient de la vitesse : elle part de zero, donc les bras demarrent apres la souris.
	local frequency = HedgeConfigs.UPDOWN_FOLLOW_SPEED
	-- dt borne : a bas framerate, Euler explose sur un ressort raide et les bras partiraient a l'infini.
	local timeStep = math.min(dt, 1 / 30)
	local force = -(frequency * frequency) * (updownRatio - ratio) - 2 * frequency * updownVelocity
	updownVelocity += force * timeStep
	updownRatio += updownVelocity * timeStep

	-- COURSE ADAPTEE A LA HAIE. La visee est normalisee de 0 a 1 quelle que soit la hauteur : sans ce facteur,
	-- viser le sommet d'une haie basse donnait la pose la plus HAUTE de l'animation, bras au-dessus de la tete
	-- pour une haie qui arrive a la taille.
	-- Le DESSUS n'est pas concerne : sa piste couvre une portee de bras, pas une hauteur de haie.
	local span = 1
	if not onTop then
		local hedge = lastHedge
		if hedge and hedge.Parent then
			span = math.clamp(
				hedge.Size.Y / HedgeConfigs.UPDOWN_REFERENCE_HEIGHT,
				HedgeConfigs.UPDOWN_MIN_SPAN,
				1
			)
		end
	end

	track.TimePosition = track.Length * span * math.clamp(updownRatio, 0, 1)
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


-- Distance HORIZONTALE d'un point a la boite de la haie. Sert a refuser qu'un curseur pointe une haie lointaine
-- ne s'en empare comme haie de travail. Meme calcul de coin arrondi que surfaceNormal, sans la direction.
local function hedgeReach(hedge: BasePart, from: Vector3): number
	local localPoint = hedge.CFrame:PointToObjectSpace(from)
	local half = hedge.Size * 0.5
	local dx = localPoint.X - math.clamp(localPoint.X, -half.X, half.X)
	local dz = localPoint.Z - math.clamp(localPoint.Z, -half.Z, half.Z)
	return math.sqrt(dx * dx + dz * dz)
end

-- Rend la HAUTEUR VISEE sur la face de la haie, entre 0 (le pied) et 1 (le sommet), ou nil si le joueur ne
-- vise plus la haie. C'est cette valeur qui pilote la pose de coupe, et plus tard l'endroit reellement taille.
--
-- ON VISE LE PLAN DE LA FACE, PAS LA SURFACE TOUCHEE. Lire l'endroit ou le rayon tombe rendait la visee nulle
-- des qu'il ratait la haie d'un pixel : viser le pied pour le balayer proprement faisait glisser le curseur
-- sur le sol, et la pose sautait pile au moment ou le joueur travaillait. Le plan, lui, est infini : sortir
-- des bords ne le rate jamais, on n'a plus qu'a decider jusqu'ou on accepte de deborder.
-- Rend (hauteur visee, est-ce le DESSUS). nil = le joueur ne vise plus la haie.
local function updateCursor(character: Model, normal: Vector3): (number?, boolean)
	local camera = workspace.CurrentCamera
	if not camera then
		hideCursor()
		return nil, false
	end

	-- ViewportPointToRay et non ScreenPointToRay. VERIFIE A L'ECRAN : avec ScreenPointToRay la bille tombait
	-- environ 36 pixels sous le curseur, pile la hauteur de la barre Roblox. GetMouseLocation rend donc deja
	-- des coordonnees VIEWPORT, et ScreenPointToRay rajoutait l'inset une seconde fois.
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

	local params = hedgeRayParams(character)

	local result = workspace:Raycast(ray.Origin, ray.Direction * HedgeConfigs.CURSOR_RANGE, params)
	-- On lit l'ATTRIBUT et non le tag : un attribut se replique de facon certaine jusqu'au client.
	-- Ce lancer ne sert plus qu'a SAVOIR QUELLE HAIE on vise. La hauteur, elle, vient du plan.
	if result and result.Instance:GetAttribute(HedgeConfigs.HEDGE_MARK_ATTRIBUTE) == true then
		local hit = result.Instance
		local root = character:FindFirstChild("HumanoidRootPart")

		-- LE CURSEUR NE NOMME LA HAIE DE TRAVAIL QUE SI LE JOUEUR EST ASSEZ PRES D'ELLE.
		--
		-- Sans ce garde, viser une haie a l'autre bout du jardin la faisait devenir la haie de travail : la
		-- normale, l'aimant et l'orientation basculaient dessus, le joueur se tournait vers elle et SORTAIT du
		-- chantier tout seul, sans jamais toucher a S. C'etait le bug "il suffit de mettre la souris a gauche".
		-- Trop loin, on garde la haie courante : le curseur ne peut plus voler le focus a distance.
		if
			root
			and root:IsA("BasePart")
			and hedgeReach(hit, root.Position) <= HedgeConfigs.CURSOR_HEDGE_RANGE
		then
			lastHedge = hit

			-- LE DESSUS. On regarde l'inclinaison de la surface touchee : une face verticale a une normale
			-- horizontale, le dessus l'a verticale. Le curseur dit donc tout seul quelle surface on travaille,
			-- sans qu'on ait a comparer des hauteurs ni a inventer un mode.
			if result.Normal.Y >= HedgeConfigs.TOP_AIM_DOT then
				-- LE DESSUS N'EST ATTEIGNABLE QUE SUR UNE HAIE BASSE. Au-dela, on ne passe pas le taille-haie
				-- par-dessus depuis le sol : la pose gauche-droite ne se joue pas, et on reste sur la pose
				-- VERTICALE au maximum, comme un joueur qui tend les bras vers le haut sans atteindre le sommet.
				-- Meme seuil que la coupe du dessus (voir HedgeCellService). L'escabeau viendra lever ca.
				if hit.Size.Y > HedgeConfigs.TOP_CUT_MAX_HEIGHT then
					getCursorPart().Position = result.Position
					return 1, false
				end

				-- Sur le dessus, ce qui varie est un COTE et non une hauteur : le curseur a gauche fait balayer
				-- a gauche, a droite a droite. On mesure donc l'ecart le long de la haie, entre le curseur et le
				-- joueur, et non une profondeur.
				local right = (-normal):Cross(Vector3.yAxis).Unit
				local offset = (result.Position - root.Position):Dot(right)
				local reach = HedgeConfigs.TOP_REACH
				getCursorPart().Position = result.Position
				-- 0.5 = pile devant le joueur. Un ecart borne, et non la longueur de la haie : la piste doit
				-- couvrir ce que le BRAS peut atteindre, pas ce que la haie mesure.
				return math.clamp(0.5 + offset / (reach * 2), 0, 1), true
			end
		end
	end

	local hedge = lastHedge
	-- Parent verifie aussi : une haie detruite ou sortie du streaming laisserait une reference morte.
	if not (hedge and hedge.Parent) then
		hideCursor()
		return nil, false
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
		return nil, false
	end
	local distance = (planePoint - ray.Origin):Dot(normal) / denominator
	-- Negatif : le plan est DERRIERE la camera, le joueur regarde ailleurs.
	if distance <= 0 then
		hideCursor()
		return nil, false
	end
	local point = ray.Origin + direction * distance

	local height = hedge.Size.Y
	if height <= 0 then
		hideCursor()
		return nil, false
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

	-- LE BAS DE L'ECRAN EST UNE ZONE SURE : viser sous le pied de la haie garde la pose basse, quelle que soit la
	-- position laterale. Deux raisons qui vont dans le meme sens :
	--   - c'est la zone qu'on balaie le plus, la moindre sortie ne doit pas faire sauter la pose ;
	--   - en bas d'ecran le rayon est RASANT, donc son intersection avec le plan part loin, vers le bas ET sur le
	--     cote a cause de l'angle 3/4. Le `sideways` y devient donc faux et declenchait une sortie laterale
	--     fantome des qu'on visait en bas a gauche ou a droite.
	-- On IGNORE donc le test lateral quand on vise sous le pied. Au-dessus du pied, il reprend son role : sortir
	-- franchement sur le cote a hauteur de travail rend bien la main. Le haut garde aussi sa marge.
	local margin = HedgeConfigs.AIM_MARGIN
	local belowFoot = localPoint.Y < -half.Y
	local aboveTop = localPoint.Y > half.Y + margin
	local sidewaysOut = math.abs(sideways) > sidewaysHalf + margin
	if aboveTop or (sidewaysOut and not belowFoot) then
		hideCursor()
		return nil, false
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
	return math.clamp((localPoint.Y + half.Y - dead) / usable, 0, 1), false
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
	local params = hedgeRayParams(character)

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
	-- Meme raison pour la normale de travail : gardee, elle ferait pivoter le joueur depuis l'orientation de la
	-- haie precedente en arrivant sur la suivante, alors qu'il faut se caler d'emblee.
	workNormal = nil
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	hideCursor()
	-- La haie memorisee n'a de sens que pendant le chantier : la garder ferait viser la precedente en arrivant
	-- sur la suivante, le temps que le premier lancer touche.
	lastHedge = nil
	hideCutZone()
	-- Le pas chasse n'a de sens qu'au pied d'une haie. Sans cet arret il continuerait pendant que le joueur
	-- traverse le jardin, et il masquerait la marche : elle est en Movement, lui en Action.
	setSlide(0)
	-- Meme raison pour la pose de coupe : elle est en Action2, elle bloquerait les bras sur toute la carte.
	setPose(false, 0, false, 0)

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

-- Direction SORTANTE depuis le point de la haie le plus proche du joueur, dans le plan horizontal.
--
-- C'est ce qui arrondit les angles, et ca ne coute aucune interpolation : la surface a distance constante
-- d'une boite est un rectangle a coins ARRONDIS de rayon egal a cette distance. En mesurant depuis le point le
-- plus proche, cette forme sort toute seule. Le long d'un cote, le resultat est exactement la normale de la
-- face ; passe le bout, il pivote progressivement autour du coin. Il ne peut donc plus y avoir de bascule.
--
-- EN DEUX DIMENSIONS, jamais en trois. Sur une haie basse, le joueur est plus haut que le sommet : le point le
-- plus proche en 3D serait sur le DESSUS, et la normale pointerait vers le ciel. Le rail partirait a la
-- verticale, ce qui n'a aucun sens pour quelqu'un qui marche.
local function surfaceNormal(hedge: BasePart, from: Vector3): Vector3?
	local localPoint = hedge.CFrame:PointToObjectSpace(from)
	local half = hedge.Size * 0.5
	local out = Vector3.new(
		localPoint.X - math.clamp(localPoint.X, -half.X, half.X),
		0,
		localPoint.Z - math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	-- Le joueur est A L'INTERIEUR de l'emprise : aucune direction sortante n'a de sens. Ca n'arrive pas au
	-- travail, la boite invisible l'en empeche, mais un decor mal pose ne doit pas produire un rail nul.
	if out.Magnitude < 1e-3 then
		return nil
	end
	return hedge.CFrame:VectorToWorldSpace(out.Unit)
end

-- ===== BOUCLE =====

local function update(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not (character and humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		release(nil)
		-- Le personnage suivant doit naitre opaque. Sans cette remise a zero, un joueur qui meurt au pied d'une
		-- haie reapparaitrait en fantome ailleurs sur la carte, et mettrait une seconde a redevenir visible.
		workFade = 0
		hideDebug()
		hideCursor()
		return
	end

	local atHedge = character:GetAttribute(HedgeConfigs.AT_HEDGE_ATTRIBUTE) == true
	local serverNormal = character:GetAttribute(HedgeConfigs.HEDGE_NORMAL_ATTRIBUTE)

	-- FONDU DU PERSONNAGE. Pilote ICI et non dans engage / release : ces deux-la ne passent qu'une fois, alors
	-- qu'un fondu doit continuer a se resorber APRES le decrochage. Mis dans release, le joueur redeviendrait
	-- opaque d'un coup au moment ou il quitte la haie, ce qui claque plus que de ne rien faire.
	local wanted = if atHedge and HedgeConfigs.WORK_FADE then 1 else 0
	workFade += (wanted - workFade) * math.min(1, HedgeConfigs.WORK_FADE_SPEED * dt)
	-- Un lerp exponentiel n'atteint JAMAIS sa cible : il laisse un residu minuscule. A 0 ca compte, parce qu'une
	-- transparence de 0.005 suffit a faire passer la part dans le rendu TRANSPARENT de Roblox, ou le tri se fait
	-- par objet et non par profondeur : les membres se chevauchent quand on pivote la camera. On cle donc a la
	-- cible (0 ou 1) des qu'on est assez pres, pour garantir un personnage REELLEMENT opaque en sortie de haie.
	if math.abs(wanted - workFade) < 0.01 then
		workFade = wanted
	end
	CharacterFade.apply(
		character,
		HedgeConfigs.WORK_FADE_BODY * workFade,
		HedgeConfigs.WORK_FADE_HANDS * workFade
	)

	drawDebug(
		character,
		root.Position,
		root.CFrame.LookVector,
		if atHedge then HedgeConfigs.RAY_LENGTH_ENGAGED else HedgeConfigs.RAY_LENGTH
	)

	local camera = workspace.CurrentCamera
	if not (atHedge and typeof(serverNormal) == "Vector3" and camera) then
		release(humanoid)
		return
	end

	engage(humanoid)

	-- ===== NORMALE DE TRAVAIL =====
	-- Recalculee ici, et non lue telle quelle depuis le serveur.
	--
	-- Celle du serveur designe une FACE : elle est discrete, donc elle bascule d'un quart de tour d'un seul coup
	-- dans un angle. Or tout en depend, le rail, l'aimant, l'orientation, la camera, et tout sautait avec elle.
	-- La geometrie, elle, est continue par construction : voir surfaceNormal.
	-- On garde quand meme celle du serveur en repli, le temps que le premier lancer du curseur nomme la haie.
	local hedge = lastHedge
	local aimed = (if hedge and hedge.Parent then surfaceNormal(hedge, root.Position) else nil) or serverNormal

	local previous = workNormal
	if previous then
		-- PLAFOND DE ROTATION, le seul reglage du contournement.
		--
		-- La geometrie ne saute jamais, mais sa VITESSE de rotation, si : elle passe de zero a vitesse/rayon en
		-- entrant dans l'angle, soit pres de 400 degres par seconde en replacement. Le plafonner fait prendre du
		-- retard a la normale, donc le rail tourne moins vite que le joueur et l'aimant le laisse s'ecarter :
		-- l'arc S'ELARGIT au lieu de ralentir. Le joueur garde sa vitesse, il n'est jamais freine dans l'angle.
		-- Rayon obtenu = vitesse / plafond : large et coulant en se replacant, serre et precis en taillant.
		local signed = math.atan2(previous:Cross(aimed).Y, math.clamp(previous:Dot(aimed), -1, 1))
		local maxStep = math.rad(HedgeConfigs.CORNER_TURN_SPEED) * dt
		workNormal = (CFrame.Angles(0, math.clamp(signed, -maxStep, maxStep), 0) * previous).Unit
	else
		-- Premiere frame du chantier : on se cale d'emblee, au lieu d'y arriver en pivotant depuis une normale
		-- heritee de la haie precedente.
		workNormal = aimed
	end
	local normal = workNormal :: Vector3

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

	-- AIMANT. La distance est mesuree ICI et non lue depuis le serveur : une valeur repliquee arrive avec du
	-- retard, l'aimant corrigerait donc une position perimee et se mettrait a osciller.
	--
	-- CALCUL GEOMETRIQUE et non lancer de rayon. Le rayon partait du torse, a l'horizontale : sur une haie de
	-- trois studs il passait AU-DESSUS, ne touchait rien, et l'aimant ne s'activait jamais. Le joueur restait
	-- donc loin des haies basses sans qu'on comprenne pourquoi.
	-- Une haie est une boite : sa distance se calcule, elle n'a pas besoin d'etre sondee.
	local magnetHedge = lastHedge
	if magnetHedge and magnetHedge.Parent then
		local localRoot = magnetHedge.CFrame:PointToObjectSpace(root.Position)
		local localNormal = magnetHedge.CFrame:VectorToObjectSpace(normal)
		local half = magnetHedge.Size * 0.5
		-- Distance du joueur au PLAN de la face travaillee, le long de sa normale.
		local along = localRoot.X * localNormal.X + localRoot.Z * localNormal.Z
		local depth = math.abs(localNormal.X * half.X) + math.abs(localNormal.Z * half.Z)
		local gap = along - depth - HedgeConfigs.WORK_DISTANCE

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
	-- Le zoom multiplie TOUT le placement, pas le seul recul : l'angle 3/4 reste donc le meme de pres comme de
	-- loin. En ne mettant a l'echelle que le recul, la vue plongerait en zoomant et s'aplatirait en reculant.
	local camPosition = position
		+ (
			viewNormal * distance
			+ side * HedgeConfigs.CAMERA_SIDE
			+ Vector3.new(0, HedgeConfigs.CAMERA_HEIGHT, 0)
		) * cameraZoom
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
	local aim, onTop = updateCursor(character, normal)

	-- HAUTEUR DE COUPE. La pose ne sort que moteur EN MARCHE : lever le taille-haie vers le haut de la haie
	-- alors qu'il est eteint n'a aucun sens, le joueur ne taille rien.
	local engine = character:GetAttribute(HedgeConfigs.ENGINE_ATTRIBUTE) == true
	setPose(engine and aim ~= nil, aim or 0, onTop, dt)

	-- On envoie le SEGMENT REEL DE LA LAME, pas la hauteur visee.
	--
	-- Les deux ne coincident pas : rien ne garantit qu'a 80 pour cent de visee le bras place la lame a 80 pour
	-- cent de la hauteur de la haie. Envoyer la visee faisait couper la ou pointe le CURSEUR, souvent bien
	-- au-dessus de la lame. Ici, ce qu'on voit est ce qui coupe, sur TOUTE la lame, quelle que soit l'animation.
	local blade = findBlade(character)
	if engine and blade then
		local base, tip = bladeSegment(blade)
		sendAim(base, tip)
	else
		sendAim(nil, nil)
	end

	-- ETAT DU REPERE :
	--   hors haie -> la souris a quitte la haie (aim nil), la coupe ne mordra rien : orange.
	--   coupe     -> gachette pressee, il taille : discret, on ne masque pas le travail.
	--   guide     -> il vise mais ne taille pas encore : bien visible, "tu couperas ici".
	local throttling = character:GetAttribute(HedgeConfigs.THROTTLE_ATTRIBUTE) == true
	local cutState = if aim == nil then "off" elseif throttling then "cutting" else "guide"

	-- Dessine la capsule AVEC LE DERNIER SEGMENT ENVOYE : ce que le serveur a en main, pas ce qu'on croit lui
	-- avoir dit. C'est tout l'interet quand on cherche un ecart entre les deux.
	drawCutZone(lastAimBase, lastAimTip, cutState)
end

function HedgeController.init()
	-- BindToRenderStep a la priorite Camera, et NON un simple RenderStepped.
	--
	-- Le module de controle de Roblox tourne a la priorite Input (100) et appelle humanoid:Move avec l'input
	-- brut. Notre contrainte doit passer APRES, sinon il ecraserait la notre et le joueur pourrait avancer et
	-- reculer librement. Camera (200) garantit cet ordre ; un RenderStepped simple ne le garantit pas.
	local remote = RemoteSetup.getRemote("SetAim", "Hedge")
	if remote and remote:IsA("RemoteEvent") then
		aimRemote = remote
	else
		warn("[HedgeController] Remote Hedge/SetAim introuvable : la coupe ne suivra pas la visee")
	end

	do
		local node: Instance? = ReplicatedStorage
		for _, name in ipairs(HedgeConfigs.FLY_ASSET) do
			node = node and node:FindFirstChild(name)
		end
		if node and node:IsA("BasePart") then
			local model = node:Clone()
			model.Anchored = true
			model.CanCollide = false
			model.CanQuery = false
			model.CanTouch = false
			model.CastShadow = false
			flyTemplate = model
		else
			warn(`[HedgeController] Trainee introuvable : ReplicatedStorage.{table.concat(HedgeConfigs.FLY_ASSET, ".")}`)
		end
	end

	-- Les feuilles en vol tournent en Heartbeat : c'est du decor, ca n'a pas a passer avant le rendu.
	RunService.Heartbeat:Connect(stepFlyers)

	-- Resolus UNE fois : les chercher a chaque coupe ferait un parcours d'arborescence sept fois par seconde.
	if #HedgeConfigs.CUT_SOUND > 0 then
		local node: Instance? = SoundService
		for _, name in ipairs(HedgeConfigs.CUT_SOUND) do
			node = node and node:FindFirstChild(name)
		end

		if node and node:IsA("Sound") then
			-- Chemin qui designe un son precis : il n'y en aura qu'un, et c'est un cas valide.
			table.insert(cutSounds, node)
		elseif node then
			-- Chemin qui designe un DOSSIER : on prend tout ce qu'il contient. Deposer un echantillon de plus
			-- dans Studio suffit donc a enrichir la coupe.
			for _, child in ipairs(node:GetChildren()) do
				if child:IsA("Sound") then
					table.insert(cutSounds, child)
				end
			end
		end

		if #cutSounds == 0 then
			warn(`[HedgeController] Aucun son de coupe sous SoundService.{table.concat(HedgeConfigs.CUT_SOUND, ".")}`)
		end
	end

	local effects = ReplicatedStorage:FindFirstChild("Assets")
	effects = effects and effects:FindFirstChild("Effects")
	local found = effects and effects:FindFirstChild(HedgeConfigs.CUT_EFFECT)
	if found and found:IsA("BasePart") then
		cutEffect = found
	end

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
		if gameProcessed or not engaged then
			return
		end

		-- ZOOM A LA MOLETTE. Elle ne sert a rien d'autre pendant le travail : la camera est en Scriptable, donc
		-- celle de Roblox ne lit plus rien. Son zoom a elle est fige et le joueur le retrouve intact en sortant.
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			-- Position.Z vaut +1 vers l'avant. On veut alors se RAPPROCHER, donc REDUIRE le facteur : le signe
			-- s'inverse ici, une fois, plutot que dans la tete du joueur.
			--
			-- En PROPORTION et non en pas fixe : un cran doit changer la vue d'autant de pres que de loin. Avec un
			-- pas fixe, les crans sont brutaux au plus pres et imperceptibles au plus loin.
			local factor = 1 - input.Position.Z * HedgeConfigs.CAMERA_ZOOM_STEP
			cameraZoom =
				math.clamp(cameraZoom * factor, HedgeConfigs.CAMERA_ZOOM_MIN, HedgeConfigs.CAMERA_ZOOM_MAX)
			return
		end

		if not orbiting or input.UserInputType ~= Enum.UserInputType.MouseMovement then
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
