--!strict
-- PAPILLONS. Ils apparaissent dans les zones posees dans la map, volent en dents de scie, puis s'en vont.
--
-- 100 % LOCAL, comme les nuages et l'herbe. C'est du DECOR : rien ne transite par le reseau, chaque joueur a ses
-- papillons a lui, et personne ne remarquera jamais qu'ils ne sont pas aux memes endroits. Les faire vivre au
-- serveur voudrait dire repliquer une dizaine de CFrame par image pour des insectes.
--
-- ===== LE BATTEMENT POUSSE, ET C'EST TOUT LE SUJET =====
-- L'animation ne fait que battre les ailes ; le DEPLACEMENT est calcule ici. Et il n'est pas lisse : chaque
-- marqueur `BattementWingsEvent` donne une impulsion vers le haut et vers l'avant, la gravite reprend entre
-- deux. On obtient la trajectoire en dents de scie qui fait qu'un papillon se lit comme un papillon.
--
-- Un vol interpole proprement d'un point a un autre donnerait un drone. La saccade EST l'effet.
--
-- ===== IL NE VA NULLE PART =====
-- Il choisit un cap au hasard, le tient une seconde ou deux, en prend un autre. Un cap qui tourne en continu
-- dessinerait de grands cercles reguliers -- exactement ce qu'un papillon ne fait jamais.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ButterflyConfigs = require(ReplicatedStorage.Modules.Configs.ButterflyConfigs)

local ButterflyController = {}

local UP = Vector3.new(0, 1, 0)

type Zone = {
	part: BasePart,
	butterflies: { Butterfly },
	nextSpawn: number,
	want: number, -- combien cette zone veut en heberger
}

type Butterfly = {
	model: Model,
	root: BasePart,
	-- SA ZONE, ou nil pour un papillon de SCENE. C'est elle qui decide de l'aimant et de la hauteur de croisiere :
	-- un papillon lance d'un point a un autre n'en a pas, il a un BUT a la place.
	zone: Zone?,
	target: Vector3?, -- but a atteindre. nil = il flane dans sa zone.
	track: AnimationTrack?,
	-- Vitesse propre, en studs/seconde. Le battement l'alimente, la gravite et le frottement la mangent.
	velocity: Vector3,
	heading: number, -- cap VOULU, en radians. Sert a POUSSER : c'est l'intention.
	facing: number, -- cap de poussee courant : il rattrape `heading`, il ne lui est pas egal
	bodyYaw: number, -- orientation MONTREE : elle suit la vitesse reelle, pas l'intention
	roll: number, -- inclinaison courante, en radians. Vient de la VITESSE de rotation, pas du cap.
	speedMul: number, -- allure propre a ce papillon : multiplie la poussee ET son plafond
	nextTurn: number,
	turnSign: number, -- de quel cote est parti le DERNIER virage. Le suivant part de l'autre : c'est ca, le zigzag.
	noiseSeed: number, -- decalage propre dans le champ de bruit de la derive
	height: number, -- hauteur de croisiere propre a ce papillon
	dieAt: number,
	leavingAt: number?, -- instant ou le depart a commence, nil tant qu'il vit sa vie
}

local player = Players.LocalPlayer
local rng = Random.new()

local zones: { Zone } = {}
-- LES PAPILLONS DE SCENE, hors zone. Ils vivent dans leur propre liste parce qu'ils ne suivent AUCUNE des regles
-- des autres : pas d'aimant, pas de repeuplement, et surtout pas de purge a distance -- une scene se joue la ou
-- le realisateur l'a posee, pas la ou le joueur se trouve.
local loose: { Butterfly } = {}
local folder: Folder? = nil
local template: Model? = nil
local animation: Animation? = nil
local conn: RBXScriptConnection? = nil

-- Ecart d'angle le plus COURT entre deux caps. Sans ca, passer de 179 a -179 degres ferait faire un tour complet
-- au papillon pour un ecart de deux degres.
local function shortestAngle(from: number, to: number): number
	local d = (to - from) % (math.pi * 2)
	if d > math.pi then
		d -= math.pi * 2
	end
	return d
end

local function findByPath(root: Instance, path: { string }): Instance?
	local node: Instance? = root
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function playerPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- Un point au hasard dans la zone, a hauteur de vol. On tire dans la boite ENTIERE en X et Z, mais la hauteur
-- vient de la config : la part sert d'emprise au sol, pas de volume de vol -- sinon regler la hauteur voudrait
-- dire redimensionner la part a chaque essai.
local function spawnPoint(zone: Zone, height: number): Vector3
	local part = zone.part
	local half = part.Size * 0.5
	local local1 = Vector3.new(
		rng:NextNumber(-half.X, half.X),
		0,
		rng:NextNumber(-half.Z, half.Z)
	)
	local ground = part.Position.Y - half.Y
	local flat = part.CFrame:PointToWorldSpace(local1)
	return Vector3.new(flat.X, ground + height, flat.Z)
end

local function destroy(butterfly: Butterfly)
	local track = butterfly.track
	if track then
		track:Stop(0)
	end
	butterfly.model:Destroy()
end

-- Fabrique un papillon a un endroit donne. `zone` nil = papillon de SCENE : pas d'aimant, pas de hauteur de
-- croisiere, il suit son `target` puis s'en va.
local function spawnOne(zone: Zone?, now: number, at: Vector3?, target: Vector3?): Butterfly?
	local source = template
	if not source then
		return nil
	end
	local model = source:Clone()
	local root = model.PrimaryPart
	if not (root and root:IsA("BasePart")) then
		model:Destroy()
		return nil
	end

	-- ANCRE : on ecrit son CFrame nous-memes a chaque image. La physique n'a rien a dire sur un papillon, et la
	-- laisser faire le ferait tomber au sol des la premiere frame.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			-- Invisible aux raycasts : sinon la coupe de l'herbe et les prompts croiraient a un obstacle qui
			-- passe. `CanQuery` n'a d'effet que parce que CanCollide est faux.
			d.CanQuery = false
			d.CastShadow = false
		end
	end

	local height = ButterflyConfigs.FLY_HEIGHT
		+ rng:NextNumber(-ButterflyConfigs.FLY_HEIGHT_RANGE, ButterflyConfigs.FLY_HEIGHT_RANGE)
	-- CHACUN SA TAILLE. Des papillons rigoureusement identiques trahissent le clone : l'oeil repere la repetition
	-- avant de reperer la forme. Applique AVANT le placement -- ScaleTo travaille autour du pivot, et le faire
	-- ensuite deplacerait le papillon qu'on vient de poser.
	local variation = ButterflyConfigs.SCALE_VARIATION
	model:ScaleTo(ButterflyConfigs.SCALE * (1 + rng:NextNumber(-variation, variation)))

	-- ET CHACUN SA COULEUR D'AILES. On ne teinte QUE les ailes : la couleur du corps ne distingue rien, celle des
	-- ailes fait l'espece. Les deux ailes prennent la MEME teinte -- un papillon depareille se lit comme un bug.
	local palette = ButterflyConfigs.WING_COLORS
	local wingColor = palette[rng:NextInteger(1, #palette)]
	for _, name in ButterflyConfigs.WING_PARTS do
		local wing = model:FindFirstChild(name, true)
		if wing and wing:IsA("BasePart") then
			wing.Color = wingColor
		end
	end
	-- Le point de depart vient de la zone, ou est impose (papillon de scene).
	local start = at or (if zone then spawnPoint(zone, height) else Vector3.zero)
	-- IL PART DEJA TOURNE VERS SON BUT quand il en a un : demarrer sur un cap au hasard le ferait faire demi-tour
	-- au premier virage, ce qui se voit tout de suite dans un plan pose.
	local heading = rng:NextNumber(0, math.pi * 2)
	if target then
		local aim = (target - start) * Vector3.new(1, 0, 1)
		if aim.Magnitude > 1e-3 then
			heading = math.atan2(-aim.Unit.X, -aim.Unit.Z)
		end
	end
	model:PivotTo(CFrame.new(start) * CFrame.Angles(0, heading, 0))
	model.Parent = Workspace

	local butterfly: Butterfly = {
		model = model,
		root = root,
		zone = zone,
		target = target,
		track = nil,
		velocity = Vector3.zero,
		heading = heading,
		facing = heading,
		bodyYaw = heading,
		roll = 0,
		speedMul = rng:NextNumber(ButterflyConfigs.SPEED_VAR_MIN, ButterflyConfigs.SPEED_VAR_MAX),
		nextTurn = now + rng:NextNumber(0, ButterflyConfigs.TURN_EVERY),
		turnSign = if rng:NextNumber() < 0.5 then -1 else 1,
		-- Chacun son coin du champ de bruit : deux papillons voisins onduleraient sinon exactement pareil, et on
		-- lirait un banc de poissons au lieu de deux insectes.
		noiseSeed = rng:NextNumber(0, 1000),
		height = height,
		-- Un papillon de SCENE ne meurt pas de vieillesse : il part en arrivant. Le delai n'est qu'un filet, pour
		-- qu'un but inatteignable ne le laisse pas a l'ecran tout le reste de la partie.
		dieAt = now
			+ if target
				then ButterflyConfigs.SCENE_LIFE_MAX
				else rng:NextNumber(ButterflyConfigs.LIFE_MIN, ButterflyConfigs.LIFE_MAX),
		leavingAt = nil,
	}

	-- L'ANIMATION, et le marqueur qui pousse. Sans elle le papillon vole quand meme -- ailes figees, mais il
	-- avance : on ne prive pas la scene d'un decor entier pour un asset qui n'a pas charge.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	local anim = animation
	if animator and anim then
		local ok, result = pcall(function()
			return (animator :: Animator):LoadAnimation(anim :: Animation)
		end)
		if ok and typeof(result) == "Instance" then
			local track = result :: AnimationTrack
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Idle
			track:Play()
			local speed = rng:NextNumber(ButterflyConfigs.SPEED_MIN, ButterflyConfigs.SPEED_MAX)
			track:AdjustSpeed(speed)
			-- L'IMPULSION SE DIVISE PAR LA VITESSE DE LECTURE, et c'est ce qui DECOUPLE les deux reglages.
			--
			-- Battre des ailes deux fois plus vite, c'est recevoir deux fois plus d'impulsions par seconde : sans
			-- cette division, accelerer l'animation ferait decoller le papillon comme une fusee, et il faudrait
			-- re-regler FLAP_UP a chaque essai. Avec elle, la poussee MOYENNE ne bouge pas -- impulsion divisee
			-- par deux, deux fois plus souvent -- et SPEED ne change plus que l'aspect des ailes.
			--
			-- Compenser a la main aurait marche une fois, puis se serait retrouve faux au reglage suivant.
			local flapScale = 1 / math.max(speed, 0.01)
			-- CHAQUE BATTEMENT POUSSE. C'est le marqueur pose dans l'editeur qui commande le deplacement : les
			-- ailes et le mouvement ne peuvent donc pas se desynchroniser, quelle que soit la vitesse de lecture.
			track:GetMarkerReachedSignal(ButterflyConfigs.WING_EVENT):Connect(function()
				local forward = Vector3.new(-math.sin(butterfly.facing), 0, -math.cos(butterfly.facing))
				-- L'ALLURE PROPRE ne touche que la poussee VERS L'AVANT. La portance reste commune : un papillon
				-- lent doit rester un papillon, pas un papillon qui tombe.
				butterfly.velocity += UP * (ButterflyConfigs.FLAP_UP * flapScale)
					+ forward * (ButterflyConfigs.FLAP_FORWARD * flapScale * butterfly.speedMul)
			end)
			butterfly.track = track
		end
	end

	if zone then
		table.insert(zone.butterflies, butterfly)
	end
	return butterfly
end

-- Une image de vol.
local function stepButterfly(butterfly: Butterfly, now: number, dt: number): boolean
	if not butterfly.model.Parent then
		return false
	end

	-- LE DEPART. Il monte et s'efface au lieu de disparaitre sur place : un objet qui s'evapore sous les yeux
	-- casse l'illusion bien plus qu'un objet qui s'en va.
	local leaving = butterfly.leavingAt
	if not leaving and now >= butterfly.dieAt then
		leaving = now
		butterfly.leavingAt = leaving
	end
	if leaving then
		local e = (now - leaving) / ButterflyConfigs.LEAVE_TIME
		if e >= 1 then
			destroy(butterfly)
			return false
		end
		for _, d in butterfly.model:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = e
			end
		end
		butterfly.velocity += UP * (ButterflyConfigs.LEAVE_RISE * dt)
	end

	local pos = butterfly.root.Position
	local zone = butterfly.zone
	local target = butterfly.target

	-- IL EST ARRIVE ? Un papillon de scene s'en va des qu'il touche son but : il n'a plus rien a faire la, et le
	-- laisser tourner autour transformerait un passage en decor.
	if target and not leaving then
		local gap = (target - pos) * Vector3.new(1, 0, 1)
		if gap.Magnitude < ButterflyConfigs.SCENE_ARRIVE_DIST then
			butterfly.dieAt = now
		end
	end

	-- OU EN EST-IL PAR RAPPORT A SA ZONE ? Calcule AVANT la decision de cap : c'est ce qui permet au papillon de
	-- decider de rentrer, au lieu d'etre seulement tire. Un papillon de scene n'a pas de zone : rien a depasser.
	local overX, overZ, overshoot = 0, 0, 0
	local part = if zone then zone.part else nil
	local half = if part then part.Size * 0.5 else Vector3.zero
	local inZone = if part then part.CFrame:PointToObjectSpace(pos) else Vector3.zero
	if part then
		local margin = ButterflyConfigs.EDGE_MARGIN
		overX = math.abs(inZone.X) - (half.X - margin)
		overZ = math.abs(inZone.Z) - (half.Z - margin)
		overshoot = math.max(overX, overZ, 0)
	end

	-- LE CAP CHANGE, par a-coups. Un nouveau but tous les TURN_EVERY environ, jamais une rotation continue.
	--
	-- SAUF S'IL EST SORTI : la il vise le centre, et il redecide TOUT DE SUITE. Attendre son prochain virage le
	-- laisserait s'eloigner deux secondes de plus pour rien.
	local outside = overshoot > 0
	local mustTurn = now >= butterfly.nextTurn or (outside and ButterflyConfigs.EDGE_TURN_NOW)
	if not leaving and mustTurn then
		butterfly.nextTurn = now
			+ ButterflyConfigs.TURN_EVERY
			+ rng:NextNumber(0, ButterflyConfigs.TURN_JITTER)
		if target then
			-- IL VISE SON BUT, mais de BIAIS. Viser pile en ligne droite annulerait le zigzag et donnerait une
			-- trajectoire de fleche -- or c'est le zigzag qui vend le papillon dans un plan pose.
			local aim = (target - pos) * Vector3.new(1, 0, 1)
			if aim.Magnitude > 1e-3 then
				local jitter = ButterflyConfigs.SCENE_AIM_JITTER
				butterfly.heading = math.atan2(-aim.Unit.X, -aim.Unit.Z) + rng:NextNumber(-jitter, jitter)
			end
		elseif outside and part then
			-- IL DECIDE DE RENTRER. Son cap vise le centre, donc il BAT DES AILES dans la bonne direction au lieu
			-- d'etre traine de cote par l'aimant. C'est ce qui fait lire le retour comme une intention.
			local toCenter = (part.Position - pos) * Vector3.new(1, 0, 1)
			if toCenter.Magnitude > 1e-3 then
				local home = toCenter.Unit
				local jitter = ButterflyConfigs.EDGE_HOME_JITTER
				butterfly.heading = math.atan2(-home.X, -home.Z) + rng:NextNumber(-jitter, jitter)
			end
		else
			-- IL PART DE L'AUTRE COTE QUE LA DERNIERE FOIS. C'est ca qui fait le zigzag : un tirage purement au
			-- hasard enchaine deux ou trois virages du meme cote et dessine un cercle.
			--
			-- Pas TOUJOURS, quand meme : une alternance parfaite est un motif, et un motif se repere. La
			-- probabilite laisse passer un virage sur cinq du meme cote.
			local sign = butterfly.turnSign
			if rng:NextNumber() < ButterflyConfigs.TURN_ALTERNATE then
				sign = -sign
			end
			butterfly.turnSign = sign
			-- Amplitude tiree entre 40 % et 100 % : des virages tous identiques redeviendraient un motif.
			local swing = math.rad(ButterflyConfigs.TURN_ANGLE)
			butterfly.heading += sign * rng:NextNumber(swing * 0.4, swing)
		end
	end

	-- LA DERIVE CONTINUE, par-dessus les virages. Entre deux decisions le cap ondule doucement : aucun segment
	-- n'est jamais parfaitement droit, meme sur une demi-seconde.
	--
	-- Du bruit de Perlin et pas du hasard par image : le hasard pur donnerait un tremblement, le bruit donne une
	-- ondulation. C'est la difference entre un papillon et une mouche electrocutee.
	if not leaving then
		local wave = math.noise(now * ButterflyConfigs.WANDER_SCALE + butterfly.noiseSeed, 0, 0) * 2
		butterfly.heading += wave * ButterflyConfigs.WANDER_AMOUNT * dt
	end

	-- L'AIMANT. Aucun mur, aucune teleportation : la force GRANDIT avec le depassement, donc elle finit toujours
	-- par gagner. Une force constante pouvait perdre contre l'elan d'un battement, et le papillon partait pour de
	-- bon -- c'est exactement ce qui se passait.
	local pull = Vector3.zero
	if part and overX > 0 then
		pull += part.CFrame.RightVector * -math.sign(inZone.X)
	end
	if part and overZ > 0 then
		pull += part.CFrame.LookVector * -math.sign(inZone.Z)
	end
	if pull.Magnitude > 1e-3 then
		local strength = ButterflyConfigs.EDGE_PUSH * (1 + overshoot * ButterflyConfigs.EDGE_GAIN)
		butterfly.velocity += pull.Unit * (strength * dt)
	end

	-- LE CAP DE POUSSEE rattrape le cap voulu. C'est la DIRECTION DANS LAQUELLE IL BAT DES AILES, pas celle dans
	-- laquelle son corps pointe : les deux sont separees plus bas, et c'est ce qui corrige le vol en crabe.
	butterfly.facing += shortestAngle(butterfly.facing, butterfly.heading)
		* math.min(1, ButterflyConfigs.TURN_SPEED * dt)

	-- GRAVITE ET FROTTEMENT. C'est l'ECART entre eux et l'impulsion du battement qui fait la dent de scie : sans
	-- gravite il monterait indefiniment, sans frottement les impulsions s'additionneraient a l'infini.
	butterfly.velocity -= UP * (ButterflyConfigs.GRAVITY * dt)
	butterfly.velocity *= 1 - math.min(1, ButterflyConfigs.DRAG * dt)

	-- La vitesse HORIZONTALE est bornee, pas la verticale : c'est le battement qui doit rester libre de le
	-- soulever, alors qu'un papillon rapide en translation devient une mouche.
	-- Le plafond suit la MEME allure que la poussee : brider un papillon rapide au plafond commun le ramenerait
	-- au rythme de tous les autres, et la variation d'allure ne se verrait que sur les lents.
	local topSpeed = ButterflyConfigs.MAX_SPEED * butterfly.speedMul
	local flat = Vector3.new(butterfly.velocity.X, 0, butterfly.velocity.Z)
	if flat.Magnitude > topSpeed then
		flat = flat.Unit * topSpeed
		butterfly.velocity = Vector3.new(flat.X, butterfly.velocity.Y, flat.Z)
	end

	-- IL REVIENT A SA HAUTEUR DE CROISIERE. Doucement : c'est une tendance, pas un rail -- le battement doit
	-- pouvoir le faire monter au-dessus et la gravite le faire descendre en dessous.
	-- Depuis sa zone quand il en a une ; depuis son BUT sinon -- un papillon de scene doit finir a la hauteur ou
	-- on l'attend, pas a celle d'une zone qui n'existe pas.
	if not leaving then
		local wanted = if part
			then (part.Position.Y - half.Y) + butterfly.height
			else (if target then target.Y else pos.Y)
		butterfly.velocity += UP * ((wanted - pos.Y) * dt)
	end

	local newPos = pos + butterfly.velocity * dt

	-- LE PLANCHER EST UN MUR, pas une suggestion. Le rappel vers la hauteur de croisiere est une force douce, et
	-- une force douce ne garantit AUCUNE borne : entre deux battements, la gravite faisait passer le papillon
	-- sous la map. Une borne se clampe.
	--
	-- Pas pendant le DEPART : la, il monte pour s'en aller, le plancher n'a plus rien a defendre.
	if not leaving and part then
		local floor = (part.Position.Y - half.Y) + ButterflyConfigs.MIN_HEIGHT
		if newPos.Y < floor then
			newPos = Vector3.new(newPos.X, floor, newPos.Z)
			-- On n'annule que la composante DESCENDANTE : garder la montante laisse le prochain battement le
			-- relancer normalement au lieu de le coller au sol une image de plus.
			if butterfly.velocity.Y < 0 then
				butterfly.velocity = Vector3.new(butterfly.velocity.X, 0, butterfly.velocity.Z)
			end
		end
	end

	-- LE CORPS REGARDE OU IL VA VRAIMENT, et pas ou il VOUDRAIT aller.
	--
	-- Le rappel du bord pousse de cote, la gravite tire vers le bas, et l'elan du battement precedent survit au
	-- changement de cap : la vitesse reelle n'est presque jamais alignee sur l'intention. En orientant le modele
	-- sur `facing`, le papillon volait de biais -- il regardait droit devant tout en derivant en travers.
	--
	-- On le realigne donc sur son DEPLACEMENT. C'est une correction, pas un mouvement a admirer : elle est rapide.
	local before = butterfly.bodyYaw
	local flatVel = Vector3.new(butterfly.velocity.X, 0, butterfly.velocity.Z)
	if flatVel.Magnitude > ButterflyConfigs.BODY_MIN_SPEED then
		-- Meme convention que partout dans le projet : un cap `h` se lit comme un regard (-sin h, 0, -cos h).
		local wanted = math.atan2(-flatVel.X, -flatVel.Z)
		butterfly.bodyYaw += shortestAngle(butterfly.bodyYaw, wanted)
			* math.min(1, ButterflyConfigs.BODY_TURN_SPEED * dt)
	end

	-- IL S'INCLINE DANS LE VIRAGE, COMME UN AVION.
	--
	-- Le roulis vient de la VITESSE DE ROTATION, pas du cap : c'est EN tournant qu'on s'incline, pas en AYANT
	-- tourne. Cale sur le cap, le papillon resterait penche en ligne droite.
	--
	-- On mesure donc de combien le corps a tourne pendant CETTE image, ramene par seconde.
	local turnRate = shortestAngle(before, butterfly.bodyYaw) / math.max(dt, 1e-4)
	local maxRoll = math.rad(ButterflyConfigs.BANK_MAX)
	local sign = if ButterflyConfigs.BANK_INVERT then -1 else 1
	local wantedRoll = math.clamp(-turnRate * ButterflyConfigs.BANK_GAIN * sign, -maxRoll, maxRoll)
	-- Il PREND et REND son inclinaison plus lentement qu'il ne tourne : elle traine derriere le virage, et c'est
	-- ce retard qui se lit comme du poids. Instantanee, elle claque et on ne la voit plus.
	butterfly.roll += (wantedRoll - butterfly.roll) * math.min(1, ButterflyConfigs.BANK_SPEED * dt)

	-- Le roulis APRES le cap, donc autour de l'axe du regard : compose avant, il ferait pivoter tout le repere et
	-- le papillon partirait de travers au lieu de pencher.
	butterfly.model:PivotTo(
		CFrame.new(newPos) * CFrame.Angles(0, butterfly.bodyYaw, 0) * CFrame.Angles(0, 0, butterfly.roll)
	)
	return true
end

local function clearZone(zone: Zone)
	for _, butterfly in zone.butterflies do
		destroy(butterfly)
	end
	table.clear(zone.butterflies)
end

local function update(dt: number)
	local from = playerPosition()
	local now = os.clock()

	for _, zone in zones do
		if not zone.part.Parent then
			continue
		end
		-- RIEN NE VIT LOIN DU JOUEUR. On vide la zone au lieu de laisser tourner des papillons que personne ne
		-- voit : ils coutent exactement le meme prix vus ou non.
		local far = not from
			or (Vector3.new(zone.part.Position.X - from.X, 0, zone.part.Position.Z - from.Z)).Magnitude
				> ButterflyConfigs.VIEW_DISTANCE
		if far then
			if #zone.butterflies > 0 then
				clearZone(zone)
			end
			continue
		end

		for index = #zone.butterflies, 1, -1 do
			if not stepButterfly(zone.butterflies[index], now, dt) then
				table.remove(zone.butterflies, index)
			end
		end

		-- ILS ARRIVENT UN PAR UN. Remplir la zone d'un coup se lirait comme une apparition ; espaces, ils ont
		-- l'air de passer par la.
		if #zone.butterflies < zone.want and now >= zone.nextSpawn then
			zone.nextSpawn = now
				+ ButterflyConfigs.SPAWN_EVERY
				+ rng:NextNumber(0, ButterflyConfigs.SPAWN_JITTER)
			spawnOne(zone, now)
		end
	end

	-- LES PAPILLONS DE SCENE, mis a jour quoi qu'il arrive. Pas de test de distance : ils sont poses pour etre
	-- VUS a un moment precis, et les couper parce que le joueur est loin viderait le plan de son sujet.
	for index = #loose, 1, -1 do
		if not stepButterfly(loose[index], now, dt) then
			table.remove(loose, index)
		end
	end
end

local function collectZones()
	local host = folder
	if not host then
		return
	end
	table.clear(zones)
	local now = os.clock()
	for _, child in host:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(zones, {
				part = child,
				butterflies = {},
				nextSpawn = now + rng:NextNumber(0, ButterflyConfigs.SPAWN_JITTER),
				want = rng:NextInteger(ButterflyConfigs.PER_ZONE_MIN, ButterflyConfigs.PER_ZONE_MAX),
			})
		end
	end
end

-- LANCE UN PAPILLON DE A VERS B. Pour une scene : il traverse le cadre, puis s'en va.
--
-- Il reutilise TOUT le vol normal -- battement, zigzag, roulis, couleur, taille. Seule la decision de cap change :
-- au lieu de flaner dans une zone, il vise son but. C'est ce qui garantit qu'il ressemble aux autres : un
-- papillon de scene ecrit a part aurait fini par voler differemment sans que personne s'en apercoive.
--
-- Sans effet tant que le modele n'est pas resolu (place sans papillons) : une scene ne doit pas dependre d'un
-- decor pour se jouer.
function ButterflyController.flyTo(from: Vector3, to: Vector3)
	local butterfly = spawnOne(nil, os.clock(), from, to)
	if butterfly then
		table.insert(loose, butterfly)
	end
end

function ButterflyController.init()
	if conn then
		return
	end

	-- EN TACHE DE FOND. Avec le streaming, les zones arrivent bien apres le boot -- et un `init` qui attend gele
	-- tout le demarrage du client. On re-scanne jusqu'a trouver, puis on branche.
	task.spawn(function()
		local mesh = findByPath(ReplicatedStorage, ButterflyConfigs.MESH_PATH)
		if mesh and mesh:IsA("Model") then
			template = mesh
		else
			warn(
				`[Butterfly] Modele introuvable : ReplicatedStorage.`
					.. `{table.concat(ButterflyConfigs.MESH_PATH, ".")}. Aucun papillon.`
			)
			return
		end

		local anim = findByPath(ReplicatedStorage, ButterflyConfigs.ANIM_PATH)
		if anim and anim:IsA("Animation") then
			animation = anim
		else
			-- ANORMAL MAIS PAS BLOQUANT : ils voleront ailes figees plutot que pas du tout.
			warn(
				`[Butterfly] Animation introuvable : ReplicatedStorage.`
					.. `{table.concat(ButterflyConfigs.ANIM_PATH, ".")}. Ailes figees.`
			)
		end

		local deadline = os.clock() + ButterflyConfigs.FIND_TIMEOUT
		while os.clock() < deadline do
			local found = Workspace:FindFirstChild(ButterflyConfigs.ZONE_FOLDER, true)
			if found and found:IsA("Folder") and #found:GetChildren() > 0 then
				folder = found
				collectZones()
				break
			end
			task.wait(ButterflyConfigs.FIND_INTERVAL)
		end

		if #zones == 0 then
			warn(
				`[Butterfly] Aucun dossier "{ButterflyConfigs.ZONE_FOLDER}" avec des parts apres `
					.. `{ButterflyConfigs.FIND_TIMEOUT} s. Aucun papillon dans cette place.`
			)
			return
		end

		-- Une zone ajoutee ou retiree en cours de partie (streaming, edition en direct) est prise en compte.
		local host = folder
		if host then
			host.ChildAdded:Connect(collectZones)
			host.ChildRemoved:Connect(collectZones)
		end

		print(`[Butterfly] {#zones} zone(s) trouvee(s).`)
		conn = RunService.Heartbeat:Connect(update)
	end)
end

return ButterflyController
