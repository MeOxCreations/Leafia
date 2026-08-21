--!strict
-- HERBE DE ZONE. Remplit chaque part "ZoneGrass..." de touffes, et couche celles sur lesquelles un joueur marche.
--
-- TOUT EST LOCAL. Les touffes sont creees par CE client, dans SA copie du Workspace : rien ne part sur le reseau, ni
-- a la creation ni a l'ecrasement. C'est l'inverse des animations d'ambiance (AmbientAnimService, serveur) et c'est voulu : le
-- balancement d'un arbre est le meme pour tout le monde, l'ecrasement de l'herbe depend de qui marche ou, a chaque
-- image. Repliquer ca chargerait le reseau pour un detail que chacun peut calculer chez lui.
--
-- Les touffes sont enfants de leur zone : si le streaming retire la zone, elles partent avec, sans nettoyage a ecrire.
-- Mais etre ENFANT ne veut PAS dire etre soude : une part ancree posee en coordonnees monde ne suit pas son parent.
-- D'ou la position de chaque touffe gardee dans le repere de la ZONE (localPos) et recalculee des que la zone bouge.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GrassZoneConfigs = require(ReplicatedStorage.Modules.Configs.GrassZoneConfigs)

local GrassZoneController = {}

local localPlayer = Players.LocalPlayer

local FOLDER_NAME = "GrassClumpsLocal"
local TILT_ANGLE = math.rad(GrassZoneConfigs.CRUSH_TILT_ANGLE)
-- Constante plutot que Vector3.yAxis : selene ne reconnait pas ce dernier comme un Vector3 et refuse Cross.
local UP = Vector3.new(0, 1, 0)

-- Repere du vent, calcule UNE fois. WIND_DIR est la direction horizontale du souffle ; WIND_AXIS est l'axe autour
-- duquel tourner pour que le HAUT de la touffe parte dans cette direction.
local WIND_DIR = Vector3.new(
	math.cos(math.rad(GrassZoneConfigs.WIND_HEADING)),
	0,
	math.sin(math.rad(GrassZoneConfigs.WIND_HEADING))
)
local WIND_AXIS = UP:Cross(WIND_DIR).Unit
local WIND_ANGLE = math.rad(GrassZoneConfigs.WIND_ANGLE)
local WIND_GUST = math.rad(GrassZoneConfigs.WIND_GUST)
-- Delai avant de refaire un semis apres un changement de taille. Assez long pour absorber une part qui recoit ses
-- proprietes en plusieurs etapes (streaming), assez court pour suivre un redimensionnement a la main dans Studio.
local REBUILD_DELAY = 0.25
-- Pas de quantification de l'APLATISSEMENT. Redimensionner une part coute plus cher que la deplacer, et la rafale
-- fait varier la hauteur en continu sur toutes les touffes visibles. On arrondit donc a ce pas : 1 % de hauteur est
-- invisible a l'oeil (0.05 stud sur une touffe de 5), mais ca divise le nombre d'ecritures de Size par dix.
-- Le pas divise 1 exactement, donc au repos l'aplatissement retombe sur 1 PILE : pas de residu fige, contrairement a
-- un garde-fou "ne pas reecrire si le delta est infime".
local SQUASH_STEP = 0.01
-- REVELATION : tout ce qui n'est pas coupe s'allume. Pilotee par MowController (touche maintenue).
-- `highlight` est l'INTENTION (touche tenue ou non), `reveal` ce qu'on AFFICHE : il rejoint l'intention en
-- douceur. Une bascule binaire se lisait comme un bug d'affichage plutot que comme un mode.
-- La valeur est GLOBALE et non par touffe : toutes s'allument ensemble, il n'y a rien a stocker mille fois.
local highlight = false
local reveal = 0
-- Fondu EN COURS. Tant qu'il l'est, tous les paves doivent etre redessines, meme ceux sans vent et sans
-- joueur a proximite : sinon la moitie de la pelouse resterait figee au milieu de la transition, et c'est
-- justement le LOIN qu'on veut voir s'allumer.
local fading = false

-- AXE DES BANDES DE TONTE, appris de la PREMIERE passe (ou impose par la config).
-- Il faut une reference pour dire "aller" et "retour" : sans elle, deux sens opposes ne se distinguent pas. Un axe
-- FIGE dans la config marchait quand on tondait le long de lui, et ne montrait RIEN en travers. Comme on tond en
-- aller-retour, la premiere passe est la meilleure reference possible : tout le reste s'y aligne ou s'y oppose.
local stripeAxis: Vector3? = nil
-- Repere des rayures, calcule une fois. Projeter la case sur cette direction donne la bande a laquelle elle appartient.
local STRIPE_COS = math.cos(math.rad(GrassZoneConfigs.STRIPE_HEADING))
local STRIPE_SIN = math.sin(math.rad(GrassZoneConfigs.STRIPE_HEADING))

-- Une touffe. On garde son PIED et sa rotation propre : le CFrame se recompose a chaque image a partir de ces
-- valeurs, JAMAIS a partir du CFrame precedent -- sinon l'inclinaison s'accumulerait et les touffes finiraient
-- couchees pour toujours.
-- localPos est dans le repere de la ZONE, basePos est sa traduction en monde (gardee en cache pour ne pas refaire
-- la multiplication a chaque image ; elle se recalcule quand la zone bouge, pas avant).
type Clump = {
	part: BasePart,
	localPos: Vector3, -- position du pied, dans le repere de la zone
	basePos: Vector3, -- la meme, en monde (cache)
	yaw: CFrame, -- rotation propre de la touffe (tirage au sort)
	baseSize: Vector3, -- taille au repos ; l'ecrasement ne fait que RABOTER son Y, jamais l'ecraser definitivement
	lift: number, -- hauteur de TIGE au repos (fleurs seulement, 0 pour l'herbe). Se comprime avec l'ecrasement.
	lastSquash: number, -- dernier aplatissement REELLEMENT ecrit : redimensionner coute plus cher que deplacer
	baseColor: Color3, -- couleur au repos, TACHE comprise
	crushedColor: Color3, -- couleur une fois ecrasee, tachee de la MEME facon : la trace garde le relief du terrain
	lastDarken: number, -- dernier melange REELLEMENT ecrit
	tiltDir: Vector3, -- sens du DERNIER passage : c'est la direction dans laquelle la touffe penche
	crush: number, -- ECRASEMENT courant (0 = debout, 1 = a fond). Reagit VITE : c'est lui qui donne l'inclinaison.
	squashCrush: number, -- le meme, mais qui TRAINE derriere : c'est lui qui donne le tassement.
	colorCrush: number, -- suit le CONTACT SEUL, sans la trace permanente : la couleur revient quand on s'en va.
	flattened: number, -- TRACE : ecrasement permanent (0 a 1). Ne fait que monter, et sert de plancher a `crush`.
	mown: number, -- COUPE : tonte permanente (0 = pas tondue, 1 = coupee). Ne descend JAMAIS, rien ne la releve.
	mowStripe: number, -- SENS de la derniere coupe, projete sur l'axe de bandes (-1 a 1). Donne la bande claire ou sombre.
	lastStripe: number, -- dernier sens REELLEMENT ecrit
	mownColor: Color3, -- couleur une fois tondue, tachee de la MEME facon : la partie tondue garde le relief du terrain
	lastMown: number, -- derniere coupe REELLEMENT ecrite : sans elle, une touffe qu'on vient de couper ne serait pas redessinee
	lastMownBlend: number, -- dernier melange de couleur de coupe REELLEMENT ecrit
	baseMaterial: Enum.Material, -- materiau de repos, releve a la pose : la revelation doit pouvoir le rendre
	lastHighlight: boolean, -- derniere revelation REELLEMENT ecrite : ecrire un Material chaque image couterait pour rien
	lastLighten: number, -- dernier eclaircissement de rafale REELLEMENT ecrit
	lastReveal: number, -- dernier fondu de revelation REELLEMENT ecrit
	windPhase: number, -- decalage propre dans l'oscillation du vent (deux voisines ne bougent pas a l'identique)
	lastCrush: number, -- dernier etat REELLEMENT ecrit : evite de reecrire une touffe lointaine immobile
	lastSquashCrush: number, -- idem pour la valeur retardee : elle peut bouger alors que l'autre est deja posee
	lastColorCrush: number, -- idem pour la couleur, qui redescend alors que les deux autres restent en place
}

-- Un PAVE : un paquet de touffes voisines, teste EN BLOC. C'est lui l'unite de travail de la boucle, pas la touffe.
-- Hors de vue, tout le pave est saute ; loin des joueurs, ses touffes ne font meme pas tourner le test d'ecrasement.
type Bucket = {
	clumps: { Clump },
	localCenter: Vector3, -- centre du pave, dans le repere de la zone
	center: Vector3, -- le meme, en monde (recalcule quand la zone bouge)
	radius: number, -- de quoi englober toutes ses touffes, hauteur comprise
	settling: boolean, -- des touffes encore en mouvement dans CE pave ?
}

type Zone = {
	part: BasePart,
	clumps: { Clump }, -- toutes les touffes a plat : sert au comptage, au log et au nettoyage
	buckets: { Bucket }, -- les memes, regroupees par pave : c'est CA que la boucle parcourt
	blockers: { BasePart }, -- objets poses dessus au dernier semis : on les surveille pour refaire le semis s'ils bougent
	radius: number, -- rayon de la zone, pour l'ecarter d'un coup quand personne n'est autour
	settling: boolean, -- des touffes encore en mouvement ? on continue alors meme sans joueur pres
	generation: number, -- le semis etant etale sur plusieurs images, ce compteur permet a un nouveau semis d'abandonner
	-- proprement celui d'avant au lieu de remplir la meme zone a deux
	watchers: { RBXScriptConnection }, -- ecoutes posees sur les OBSTACLES : bouger une haie doit refaire le semis
	rebuildPending: boolean, -- une reconstruction est deja programmee : on ne l'empile pas
}

-- Declaration en avance : `watchBlockers` la referme, et elle rappelle `populate` qui rappelle `watchBlockers`.
-- Le cycle est reel, il est resolu ici par une seule ligne plutot que par un detour artificiel.
local queueRebuild: (zone: Zone) -> ()

local zones: { Zone } = {}
local connections: { RBXScriptConnection } = {}
local template: BasePart? = nil
-- Meshes de fleurs, resolus au boot. Vide = pas de fleurs, et ce n'est pas une erreur.
local flowerTemplates: { BasePart } = {}
local heartbeat: RBXScriptConnection? = nil

-- ===== Resolution des dependances =====

-- Suit un chemin d'enfants sous `from`. RE-SCAN en boucle sous UN SEUL delai, pas un WaitForChild par segment : avec
-- un WaitForChild par segment, un chemin absent ferait attendre le timeout autant de fois qu'il y a de segments.
local function resolvePath(from: Instance, path: { string }): Instance?
	local deadline = os.clock() + GrassZoneConfigs.RESOLVE_TIMEOUT
	repeat
		local node: Instance? = from
		for _, name in ipairs(path) do
			node = node and node:FindFirstChild(name)
		end
		if node then
			return node
		end
		task.wait(0.25)
	until os.clock() >= deadline
	return nil
end

-- ===== Pose =====

-- Pose la touffe. On repart TOUJOURS du pied et de la rotation propre, jamais du CFrame precedent.
-- Deux inclinaisons se composent : l'ECRASEMENT (fuit le joueur, fort, direction variable) puis le VENT (direction
-- fixe, faible). Toutes deux sont calculees en MONDE, elles passent donc a gauche du yaw propre de la touffe.
-- Le dernier facteur remonte le CENTRE de la part au-dessus du pied, le long du haut DEJA incline.
local function apply(
	clump: Clump,
	windAngle: number,
	squash: number,
	tiltAngle: number,
	crush: number,
	mown: number,
	lighten: number
)
	-- La taille ne s'ECRIT que si elle a change : redimensionner une part coute plus cher que la deplacer, et une
	-- touffe debout ne doit rien payer. Pas de garde-fou "delta infime" ici : l'angle d'ecrasement se cle exactement
	-- sur sa cible, donc `squash` retombe exactement a 1 et la comparaison stricte s'arrete d'elle-meme. Un seuil
	-- figerait justement le residu au lieu de le laisser finir de remonter.
	squash = math.floor(squash / SQUASH_STEP + 0.5) * SQUASH_STEP
	if squash ~= clump.lastSquash then
		clump.part.Size = Vector3.new(clump.baseSize.X, clump.baseSize.Y * squash, clump.baseSize.Z)
		clump.lastSquash = squash
	end

	-- COULEUR. Glissement de la teinte au repos vers celle d'une touffe ecrasee. Meme quantification que la taille,
	-- meme raison : ecrire une couleur a chaque image sur des centaines de touffes coute pour rien, alors qu'un pour
	-- cent d'ecart ne se voit pas.
	-- REVELATION. Elle passe par ICI et pas par un reglage pose de l'exterieur : la couleur d'une touffe a deja un
	-- ecrivain (cette fonction, a chaque image). Peindre les touffes depuis un autre module serait efface a
	-- l'image suivante, et on chercherait pourquoi le neon clignote.
	-- Une touffe TONDUE ne s'allume pas, quel que soit le fondu en cours : c'est justement ce qui reste a faire
	-- qu'on veut voir. Elle suit donc le rendu normal, sans transition a gerer.
	local litAmount = if mown < GrassZoneConfigs.HIGHLIGHT_THRESHOLD then reveal else 0
	local litQ = math.floor(litAmount / SQUASH_STEP + 0.5) * SQUASH_STEP
	-- LE MATERIAU NE SE FOND PAS, il change d'un coup. On le bascule donc TOT, quand la couleur est encore
	-- presque normale : ca se lit comme un allumage. C'est le fondu de COULEUR qui porte la douceur.
	local neon = GrassZoneConfigs.HIGHLIGHT_MATERIAL_ON and litQ > GrassZoneConfigs.HIGHLIGHT_MATERIAL_AT
	if neon ~= clump.lastHighlight then
		clump.lastHighlight = neon
		clump.part.Material = if neon then GrassZoneConfigs.HIGHLIGHT_MATERIAL else clump.baseMaterial
	end
	do
		-- L'ECRASEMENT NE TEINTE PRESQUE PLUS une touffe TONDUE : sa couleur est deja celle d'une herbe rase, et
		-- le joueur marche juste derriere la tondeuse -- sans ca il lavait sa propre bande a chaque pas.
		-- L'APLATISSEMENT, lui, continue : il est geometrique, pas colorimetrique.
		local crushTint = crush * (1 - mown * GrassZoneConfigs.MOW_CRUSH_DAMP)
		local blend = math.floor(crushTint / SQUASH_STEP + 0.5) * SQUASH_STEP
		local mowBlend = math.floor(mown / SQUASH_STEP + 0.5) * SQUASH_STEP
		-- La rafale bouge en permanence : sans quantification, on reecrirait la couleur de chaque touffe a chaque
		-- image, pour des ecarts que l'oeil ne voit pas. Meme raison que pour l'ecrasement, avec son propre pas.
		local step = GrassZoneConfigs.GUST_LIGHT_STEP
		local light = math.floor(lighten / step + 0.5) * step
		if
			blend ~= clump.lastDarken
			or mowBlend ~= clump.lastMownBlend
			or light ~= clump.lastLighten
			or litQ ~= clump.lastReveal
			or clump.mowStripe ~= clump.lastStripe
		then
			-- DEUX melanges empiles, et l'ORDRE compte. La COUPE d'abord : elle change la couleur de REPOS de la
			-- touffe, pour toujours. L'ECRASEMENT par-dessus : lui est temporaire. Dans cet ordre, une touffe
			-- tondue PUIS pietinee revient a sa couleur de TONDUE quand le pied repart, pas a celle de l'herbe haute.
			local mown2 = clump.mownColor
			-- BANDE DE TONTE : selon le SENS ou la tondeuse est passee, la touffe renvoie plus ou moins de lumiere.
			-- On multiplie les canaux plutot que de fondre vers une couleur fixe : chaque touffe garde sa tache de
			-- Perlin, donc les bandes se posent SUR le relief du terrain au lieu de l'effacer.
			if clump.mowStripe ~= 0 and GrassZoneConfigs.MOW_STRIPE_STRENGTH > 0 then
				local k = 1 + clump.mowStripe * GrassZoneConfigs.MOW_STRIPE_STRENGTH
				mown2 = Color3.new(
					math.min(mown2.R * k, 1),
					math.min(mown2.G * k, 1),
					math.min(mown2.B * k, 1)
				)
			end
			local rest = clump.baseColor:Lerp(mown2, mowBlend)
			local final = rest:Lerp(clump.crushedColor, blend)
			-- LA CRETE PREND SA COULEUR. Un fondu VERS une couleur franche, pas un eclaircissement : quelques pour
			-- cent de luminosite sur un vert deja vif ne se voient pas, une teinte differente si.
			-- Le fondu reste PARTIEL, donc la nuance propre de chaque touffe et sa tache de Perlin survivent dessous.
			if light > 0 then
				final = final:Lerp(GrassZoneConfigs.GUST_COLOR, light)
			end
			-- LA REVELATION PASSE EN DERNIER : elle recouvre tout le reste. Un fondu, donc l'herbe glisse de sa
			-- couleur vers le bleu au lieu d'y sauter. A fondu plein on est exactement sur la couleur cible.
			if litQ > 0 then
				final = final:Lerp(GrassZoneConfigs.HIGHLIGHT_COLOR, litQ)
			end
			clump.part.Color = final
			clump.lastDarken = blend
			clump.lastMownBlend = mowBlend
			clump.lastLighten = light
			clump.lastReveal = litQ
			clump.lastStripe = clump.mowStripe
		end
	end

	-- LA TIGE SE COMPRIME comme le reste : au meme facteur que la hauteur. Une fleur ecrasee doit descendre AU SOL,
	-- pas s'aplatir en restant perchee. A l'arret (squash = 1) la tige fait sa taille pleine.
	local cf = CFrame.new(clump.basePos + UP * (clump.lift * squash))
	-- L'ecrasement se fait en HAUTEUR (la taille, juste au-dessus). Cette bascule ne sert que si on remet un angle
	-- dans la config, ce qui n'a de sens que sur un mesh d'UN SEUL BRIN.
	if tiltAngle ~= 0 then
		local crushAxis = UP:Cross(clump.tiltDir)
		if crushAxis.Magnitude > 1e-4 then
			cf = cf * CFrame.fromAxisAngle(crushAxis.Unit, tiltAngle)
		end
	end
	if windAngle ~= 0 then
		cf = cf * CFrame.fromAxisAngle(WIND_AXIS, windAngle)
	end
	-- La demi-hauteur suit l'aplatissement : sinon une touffe ecrasee flotterait au-dessus de son pied.
	clump.part.CFrame = cf * clump.yaw * CFrame.new(0, clump.baseSize.Y * squash * 0.5, 0)
end

-- ===== Remplissage =====

-- Graine calculee sur la POSITION de la zone : le tirage au sort donne donc la MEME disposition chez tous les
-- joueurs, sans qu'un seul octet transite. Deux joueurs cote a cote voient exactement la meme herbe.
local function seedFor(part: BasePart): number
	local p = part.Position
	local raw = math.floor(p.X * 100) * 73856093 + math.floor(p.Y * 100) * 19349663 + math.floor(p.Z * 100) * 83492791
	return math.abs(raw) % 2147483647
end

-- (Re)cree les touffes d'une zone. Appele au boot, et de nouveau si la zone est REDIMENSIONNEE : la nouvelle surface
-- veut un autre nombre de touffes, reposer les anciennes ne suffirait pas.
-- Cette part doit-elle chasser l'herbe ? Tout ce qui touche le dessus de la zone compte, SAUF trois familles.
local function isBlocker(part: BasePart, zonePart: BasePart): boolean
	if part == zonePart then
		return false
	end
	-- Une autre zone d'herbe est un simple marqueur, pas un objet pose.
	if part.Name:sub(1, #GrassZoneConfigs.ZONE_PREFIX) == GrassZoneConfigs.ZONE_PREFIX then
		return false
	end
	-- Une touffe d'herbe ne se chasse pas elle-meme.
	local parent = part.Parent
	if parent and parent.Name == FOLDER_NAME then
		return false
	end
	-- Un PERSONNAGE qui traverse la pelouse ne doit pas y creuser un trou definitif : l'emprise est calculee une fois,
	-- elle ne se refait pas quand il repart.
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return false
	end
	-- Une part rangee SOUS une autre part (les carreaux d'une haie, les touffes sous leur zone) est un detail de cet
	-- objet : c'est l'objet lui-meme qui porte l'emprise. Les prendre en plus ferait des milliers de tests pour rien,
	-- et saturerait la limite de la recherche au point de faire RATER le vrai objet.
	if part:FindFirstAncestorWhichIsA("BasePart") then
		return false
	end
	return true
end

-- Les objets poses sur la zone, releves UNE fois par semis.
local function collectBlockers(zone: Zone): { BasePart }
	local blockers: { BasePart } = {}
	if not GrassZoneConfigs.CLEAR_UNDER_PARTS then
		return blockers
	end

	local size = zone.part.Size
	local height = GrassZoneConfigs.CLEAR_HEIGHT
	-- Boite posee SUR la face du dessus, de la hauteur ou l'herbe peut etre genee.
	local box = zone.part.CFrame * CFrame.new(0, size.Y * 0.5 + height * 0.5, 0)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { zone.part }
	params.MaxParts = 500

	-- Plan du DESSUS de la zone, et sa verticale : c'est par rapport a lui qu'on mesure de combien un objet depasse.
	local up = zone.part.CFrame.UpVector
	local topPlane = zone.part.Position + up * (size.Y * 0.5)

	for _, part in ipairs(workspace:GetPartBoundsInBox(box, Vector3.new(size.X, height, size.Z), params)) do
		if isBlocker(part, zone.part) then
			-- De combien le SOMMET de cet objet depasse-t-il la pelouse ? On projette sa demi-taille sur la verticale
			-- de la zone, ce qui reste juste meme si l'objet est pose de travers.
			local cf = part.CFrame
			local half = part.Size * 0.5
			local reach = math.abs(cf.RightVector:Dot(up)) * half.X
				+ math.abs(cf.UpVector:Dot(up)) * half.Y
				+ math.abs(cf.LookVector:Dot(up)) * half.Z
			local top = (part.Position - topPlane):Dot(up) + reach
			-- SANS CE TEST, le sol sous la pelouse (dont le dessus affleure la zone) passe pour un objet pose et son
			-- emprise efface toute l'herbe.
			if top >= GrassZoneConfigs.CLEAR_MIN_HEIGHT then
				blockers[#blockers + 1] = part
			end
		end
	end
	return blockers
end

-- Ce point est-il sous un objet pose ? Test en repere OBJET : une haie posee de travers chasse l'herbe sous ELLE, pas
-- sous une boite alignee sur le monde. Seul le sol compte (X/Z), la hauteur est deja bornee par la boite de recherche.
local function isCovered(worldPos: Vector3, blockers: { BasePart }): boolean
	local margin = GrassZoneConfigs.CLEAR_MARGIN
	for _, blocker in ipairs(blockers) do
		local p = blocker.CFrame:PointToObjectSpace(worldPos)
		local half = blocker.Size * 0.5
		if math.abs(p.X) <= half.X + margin and math.abs(p.Z) <= half.Z + margin then
			return true
		end
	end
	return false
end

-- Regroupe les touffes deja creees en paves. Appele en fin de semis, et jamais dans le chemin par-image.
local function buildBuckets(zone: Zone, zoneCFrame: CFrame, localY: number)
	local side = GrassZoneConfigs.BUCKET_SIZE
	local byKey: { [string]: { Clump } } = {}
	for _, clump in ipairs(zone.clumps) do
		local key = `{math.floor(clump.localPos.X / side)}:{math.floor(clump.localPos.Z / side)}`
		local list = byKey[key]
		if not list then
			list = {}
			byKey[key] = list
		end
		list[#list + 1] = clump
	end

	table.clear(zone.buckets)
	for _, list in pairs(byKey) do
		-- Bornes REELLES des touffes du pave, pas celles de la case theorique : l'ecart au hasard peut pousser une
		-- touffe hors de sa case, et un rayon trop court la ferait disparaitre des tests sans qu'on comprenne pourquoi.
		local minX, maxX = math.huge, -math.huge
		local minZ, maxZ = math.huge, -math.huge
		local tallest = 0
		for _, clump in ipairs(list) do
			minX = math.min(minX, clump.localPos.X)
			maxX = math.max(maxX, clump.localPos.X)
			minZ = math.min(minZ, clump.localPos.Z)
			maxZ = math.max(maxZ, clump.localPos.Z)
			-- La tige compte dans la hauteur : une fleur perchee depasse, et le rayon doit l'englober.
			tallest = math.max(tallest, clump.baseSize.Y + clump.lift)
		end
		local cx, cz = (minX + maxX) * 0.5, (minZ + maxZ) * 0.5
		local dx, dz = maxX - cx, maxZ - cz
		local localCenter = Vector3.new(cx, localY, cz)
		zone.buckets[#zone.buckets + 1] = {
			clumps = list,
			localCenter = localCenter,
			center = zoneCFrame:PointToWorldSpace(localCenter),
			-- Demi-diagonale du pave PLUS la touffe la plus haute : le rayon doit englober ce qu'on VOIT, pas
			-- seulement les pieds.
			radius = math.sqrt(dx * dx + dz * dz) + tallest,
			settling = true,
		}
	end
end

-- ETALE SUR PLUSIEURS IMAGES. Fabriquer des milliers de parts d'un coup gele le client (mesure : ~600 ms pour 7 000).
-- Peut donc YIELD : tous les appelants doivent etre dans un thread a part.
local function populate(zone: Zone)
	local grassSource = template
	if not grassSource then
		return
	end

	-- Un semis qui demarre ANNULE celui d'avant. Sans ce compteur, deux semis etales se rempliraient en meme temps
	-- dans la meme zone et on aurait le double de touffes, moitie a la mauvaise place.
	zone.generation += 1
	local generation = zone.generation

	local previous = zone.part:FindFirstChild(FOLDER_NAME)
	if previous then
		previous:Destroy()
	end
	table.clear(zone.clumps)

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	local size = zone.part.Size
	local zoneCFrame = zone.part.CFrame
	local rng = Random.new(seedFor(zone.part))

	-- GRILLE. Une case par touffe, sur TOUTE la surface du dessus : c'est ce qui garantit qu'aucun coin ne reste
	-- chauve. `spacing` est le cote d'une case, deduit de la densite voulue.
	local spacing = 1 / math.sqrt(GrassZoneConfigs.DENSITY)
	local cols = math.max(1, math.ceil(size.X / spacing))
	local rows = math.max(1, math.ceil(size.Z / spacing))
	if cols * rows > GrassZoneConfigs.MAX_CLUMPS then
		-- Au plafond on ESPACE la grille, on ne coupe PAS la liste : couper laisserait une moitie de zone chauve, ce
		-- qui est exactement ce qu'on veut eviter.
		local factor = math.sqrt((cols * rows) / GrassZoneConfigs.MAX_CLUMPS)
		cols = math.max(1, math.floor(cols / factor))
		rows = math.max(1, math.floor(rows / factor))
		-- On annonce la DENSITE REELLEMENT obtenue, pas seulement la taille de la grille : c'est ce chiffre-la qui
		-- explique une herbe clairsemee, et sans lui on tourne le bouton DENSITY dans le vide en se demandant
		-- pourquoi rien ne change.
		local got = (cols * rows) / math.max(size.X * size.Z, 1e-3)
		warn(
			`[GrassZone] "{zone.part.Name}" PLAFONNE : densite {string.format("%.2f", got)} au lieu de `
				.. `{GrassZoneConfigs.DENSITY} (grille {cols}x{rows} sur {math.floor(size.X)}x{math.floor(size.Z)} studs). `
				.. `Cette zone est anormalement grande : verifie sa taille dans Studio.`
		)
	end

	local stepX = size.X / cols
	local stepZ = size.Z / rows
	local jitter = GrassZoneConfigs.JITTER
	-- Les touffes grossissent quand l'espacement grandit : la surface reste couverte pareil avec moins de parts.
	-- Calcule sur l'espacement REEL (apres le filet de securite), pas sur celui demande : si le filet a du espacer la
	-- grille, les touffes compensent aussi -- sinon ce cas rare rouvrirait des trous.
	-- A DENSITY = 1 sans plafond, le pas vaut 1 et le facteur est neutre : le rendu actuel ne bouge pas.
	local densityScale = if GrassZoneConfigs.AUTO_SCALE_WITH_DENSITY then math.sqrt(stepX * stepZ) else 1

	local blockers = collectBlockers(zone)
	zone.blockers = blockers
	local skipped = 0
	local budget = GrassZoneConfigs.CREATE_BUDGET
	local made = 0
	local flowersMade = 0

	for ix = 0, cols - 1 do
		for iz = 0, rows - 1 do
			-- TOUS LES TIRAGES D'ABORD, avant le test d'emprise. Ainsi la disposition reste identique chez tous les
			-- joueurs meme si l'un d'eux n'a pas encore recu l'objet qui chasse l'herbe (streaming) : il verra une
			-- touffe de plus, jamais un semis different.
			local jx = rng:NextNumber(-0.5, 0.5)
			local jz = rng:NextNumber(-0.5, 0.5)
			local scale = rng:NextNumber(GrassZoneConfigs.SCALE_MIN, GrassZoneConfigs.SCALE_MAX)
			local _ = rng:NextNumber(0, 1) -- tirage conserve pour que la disposition ne change pas (ancien restTilt)
			local restAngle = rng:NextNumber(0, math.pi * 2)
			local yawAngle = rng:NextNumber(0, math.pi * 2)
			local windPhase = rng:NextNumber(0, math.pi * 2)
			-- Tire ici avec les autres : la suite du hasard reste identique qu'il y ait des fleurs ou non, donc
			-- changer FLOWER_CHANCE ne redistribue pas toute la pelouse.
			local flowerRoll = rng:NextNumber()
			local flowerPick = rng:NextInteger(1, math.max(#flowerTemplates, 1))

			-- Centre de la case, dans le repere de la ZONE.
			-- QUINCONCE : une rangee sur deux est poussee d'un quart de case a droite, l'autre d'un quart a gauche.
			-- L'ecart entre deux rangees voisines fait donc une DEMI-case, ce qui est l'empilement qui couvre le mieux
			-- un plan a nombre egal de touffes -- une grille carree laisse des losanges vides entre quatre voisines.
			-- Le decalage est symetrique (et pas +0.5 sur une rangee sur deux) pour qu'aucune touffe ne sorte de la zone.
			local stagger = if iz % 2 == 0 then stepX * 0.25 else -stepX * 0.25
			local cellX = -size.X * 0.5 + (ix + 0.5) * stepX + stagger
			local cellZ = -size.Z * 0.5 + (iz + 0.5) * stepZ

			-- FLEUR ou touffe d'herbe ? Decide AVANT la position, parce qu'une fleur est SURELEVEE : posee au ras
			-- comme une touffe, elle serait noyee dans une herbe qui la depasse.
			-- Pour le reste c'est une touffe comme les autres : elle herite du vent, de l'ecrasement et de tous les
			-- tris sans rien de special.
			local isFlower = #flowerTemplates > 0 and flowerRoll < GrassZoneConfigs.FLOWER_CHANCE
			local source = if isFlower then flowerTemplates[flowerPick] else grassSource
			if isFlower then
				flowersMade += 1
			end

			-- Position AU SOL d'abord, sans elevation : c'est elle qui sert a lire les bruits de Perlin (qui ne
			-- regardent que X et Z) et a savoir quelle hauteur fait l'herbe ICI.
			local groundLocal =
				Vector3.new(cellX + jx * stepX * jitter, size.Y * 0.5, cellZ + jz * stepZ * jitter)
			local groundPos = zoneCFrame:PointToWorldSpace(groundLocal)

			-- ZONES DE HAUTEUR. Deuxieme champ de bruit, DECALE du premier (le 3e argument de math.noise change de
			-- plan) : les zones hautes ne tombent donc pas sur les zones sombres, ce qui se lirait comme un motif.
			local hScale = GrassZoneConfigs.HEIGHT_PATCH_SCALE
			local heightPatch = math.noise(groundPos.X * hScale, groundPos.Z * hScale, 17.3)
			-- Plancher a 0.2 : une touffe de hauteur nulle ou negative serait invisible ou retournee.
			local heightFactor = math.max(1 + heightPatch * 2 * GrassZoneConfigs.HEIGHT_PATCH_AMOUNT, 0.2)

			-- ELEVATION DE LA FLEUR, en fraction de la hauteur qu'aurait l'HERBE a cet endroit precis. Une elevation
			-- fixe ne peut pas marcher : l'herbe varie par zones, donc la fleur leviterait la ou elle est courte et
			-- disparaitrait la ou elle est haute. En la calant sur l'herbe voisine, elle emerge pareil PARTOUT.
			local lift = 0
			if isFlower then
				local grassHeight = grassSource.Size.Y * scale * GrassZoneConfigs.HEIGHT_SCALE * heightFactor
				lift = grassHeight * GrassZoneConfigs.FLOWER_LIFT_RATIO
			end

			-- Position gardee = celle du SOL, PAS le sommet de la tige. L'elevation est appliquee A LA POSE, ou elle
			-- peut se comprimer avec l'ecrasement : figee dans le point, la fleur s'aplatirait en restant perchee.
			local localPos = groundLocal
			local basePos = groundPos

			-- Sous un objet pose : pas de touffe DU TOUT. On ne la cree pas pour la detruire ensuite.
			if isCovered(basePos, blockers) then
				skipped += 1
				continue
			end

			local part = source:Clone()
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false -- n'a d'effet QUE parce que CanCollide est faux
			part.CanTouch = false
			part.CastShadow = false -- des centaines d'ombres de brins coutent cher et ne se voient pas
			-- RenderFidelity ne s'ecrit PAS ici : c'est une propriete reservee aux plugins ("lacking capability
			-- Plugin"). Elle se regle A LA MAIN sur le mesh source dans Studio, et les clones en heritent.
			-- Elle compte : a `Automatic`, Roblox echange le maillage quand la taille change, et une touffe qui passe
			-- a 2 % de sa hauteur en une fraction de seconde le fait clignoter.
			if isFlower then
				-- On vise une LARGEUR en studs et on en deduit le facteur. La largeur, PAS la hauteur : le mesh d'une
				-- fleur est plat, donc viser sa hauteur demande un facteur enorme et fait exploser sa largeur.
				-- Proportions gardees, et pas de compensation de densite.
				local width = rng:NextNumber(GrassZoneConfigs.FLOWER_WIDTH_MIN, GrassZoneConfigs.FLOWER_WIDTH_MAX)
				part.Size = source.Size * (width / math.max(source.Size.X, 1e-3))
			else
				-- Le grossissement de compensation ne touche QUE X et Z. Couvrir le sol est une affaire HORIZONTALE :
				-- une touffe plus large cache plus de terre, une touffe plus haute ne cache rien de plus et noie le
				-- joueur.
				part.Size = Vector3.new(
					source.Size.X * scale * densityScale,
					source.Size.Y * scale * GrassZoneConfigs.HEIGHT_SCALE * heightFactor,
					source.Size.Z * scale * densityScale
				)
			end

			-- COULEUR. Teinte de base, eventuellement remplacee par celle de sa bande de tonte.
			-- Une FLEUR garde exactement la sienne : ni teinte d'herbe, ni tache, ni virage au vert en s'ecrasant.
			-- Elle s'aplatit et se penche comme le reste, mais elle ne change pas de couleur sous le pied.
			local color = GrassZoneConfigs.BASE_COLOR
			-- RAYURES. La bande se decide sur le centre de CASE, pas sur la position finale : sinon l'ecart au hasard
			-- ferait baver les bandes l'une dans l'autre et on perdrait la ligne nette d'un terrain tondu.
			if GrassZoneConfigs.STRIPE_ENABLED then
				local band = math.floor((cellX * STRIPE_COS + cellZ * STRIPE_SIN) / GrassZoneConfigs.STRIPE_WIDTH) % 2
				color = if band == 0 then GrassZoneConfigs.STRIPE_COLOR_A else GrassZoneConfigs.STRIPE_COLOR_B
			end

			-- TACHES. Le bruit se lit sur la position MONDE, donc deux touffes voisines tombent dans la meme tache et
			-- les zones traversent les bords de la grille sans se voir. Calcule une fois ici, jamais en jeu.
			local patchScale = GrassZoneConfigs.PATCH_SCALE
			local patch = math.noise(groundPos.X * patchScale, groundPos.Z * patchScale, 0)
			local tint = 1 + patch * 2 * GrassZoneConfigs.PATCH_AMOUNT -- math.noise rend environ [-0.5, 0.5]
			local function tinted(c: Color3): Color3
				return Color3.new(
					math.clamp(c.R * tint, 0, 1),
					math.clamp(c.G * tint, 0, 1),
					math.clamp(c.B * tint, 0, 1)
				)
			end

			local crushedColor: Color3
			local mownColor: Color3
			if isFlower then
				-- Les TROIS couleurs sont IDENTIQUES : le melange devient un non-evenement, sans un seul test a
				-- ajouter dans la boucle par-image. Une fleur tondue RACCOURCIT, elle ne verdit pas.
				color = source.Color
				crushedColor = color
				mownColor = color
			else
				color = tinted(color)
				-- La couleur d'ecrasement recoit la MEME tache : sans ca, tout le chemin parcouru virerait a l'aplat
				-- uniforme et effacerait le relief que les taches viennent de donner.
				crushedColor = tinted(GrassZoneConfigs.CRUSHED_COLOR)
				-- La couleur de COUPE recoit la meme tache, pour la meme raison : une pelouse tondue doit garder le relief
				-- du terrain, sinon la partie tondue se lit comme une moquette posee dessus.
				mownColor = tinted(GrassZoneConfigs.MOWN_COLOR)
			end

			local surface = part:FindFirstChildOfClass("SurfaceAppearance")
			if surface and GrassZoneConfigs.STRIPE_ON_SURFACE then
				surface.Color = color
			else
				part.Color = color
			end

			local clump: Clump = {
				part = part,
				localPos = localPos,
				basePos = basePos,
				-- Le tirage a bien lieu meme quand RANDOM_YAW est faux : la suite de nombres au hasard reste identique,
				-- donc basculer ce reglage ne redistribue PAS toute la pelouse.
				yaw = if GrassZoneConfigs.RANDOM_YAW then CFrame.Angles(0, yawAngle, 0) else CFrame.identity,
				baseSize = part.Size,
				lift = lift,
				lastSquash = 1,
				-- Relevee APRES la pose des rayures et de la tache : c'est bien SA nuance locale qui glissera.
				baseColor = part.Color,
				crushedColor = crushedColor,
				lastDarken = 0,
				tiltDir = Vector3.new(math.cos(restAngle), 0, math.sin(restAngle)),
				crush = 0,
				squashCrush = 0,
				colorCrush = 0,
				flattened = 0,
				mown = 0,
				mowStripe = 0,
				lastStripe = 0,
				mownColor = mownColor,
				lastMown = 0,
				lastMownBlend = 0,
				baseMaterial = part.Material,
				lastHighlight = false,
				lastLighten = 0,
				lastReveal = 0,
				windPhase = windPhase,
				lastCrush = 0,
				lastSquashCrush = 0,
				lastColorCrush = 0,
			}
			-- POSEE TOUT DE SUITE, pas a la 1re passe de la boucle. Dependre d'une passe ulterieure pour le placement
			-- INITIAL, c'est laisser les touffes au point de clonage si cette passe saute pour une raison ou une autre.
			-- Pose initiale : jamais tondue, jamais ecrasee, et aucune rafale (le 7e argument). Un argument
			-- oublie passerait ici en nil, et le calcul de l'eclaircissement leverait au premier semis --
			-- selene ne voit pas un argument manquant, seul l'appel reel le montre.
			apply(clump, WIND_ANGLE, 1, 0, 0, 0, 0)
			zone.clumps[#zone.clumps + 1] = clump
			part.Parent = folder

			made += 1
			if made % budget == 0 then
				task.wait()
				if zone.generation ~= generation then
					-- Un autre semis a pris la main (zone redimensionnee). On abandonne SANS rien detruire : c'est lui
					-- qui a deja vide la liste et qui pose le nouveau dossier.
					folder:Destroy()
					return
				end
				-- Le dossier n'est parente qu'a la fin ; on le rend visible des la 1re pause pour que l'herbe
				-- apparaisse progressivement au lieu de surgir d'un bloc.
				folder.Parent = zone.part
			end
		end
	end

	if flowersMade > 0 then
		print(`[GrassZone] "{zone.part.Name}" : {flowersMade} fleur(s) parmi l'herbe.`)
	end

	if skipped > 0 then
		-- On NOMME les objets, pas seulement leur nombre : le jour ou une pelouse se vide entierement, cette ligne dit
		-- tout de suite QUI l'a mangee. Vecu -- c'etait le sol lui-meme.
		local names = {}
		for i = 1, math.min(#blockers, 6) do
			names[i] = blockers[i].Name
		end
		if #blockers > 6 then
			names[#names + 1] = `... +{#blockers - 6}`
		end
		print(
			`[GrassZone] "{zone.part.Name}" : {skipped} touffe(s) retirees sous {#blockers} objet(s) `
				.. `[{table.concat(names, ", ")}]`
		)
	end

	folder.Parent = zone.part
	buildBuckets(zone, zoneCFrame, size.Y * 0.5)

	local half = size * 0.5
	zone.radius = math.sqrt(half.X * half.X + half.Z * half.Z)
	zone.settling = true
end

-- SURVEILLE LES OBSTACLES. L'emprise des objets poses est calculee AU SEMIS : sans ces ecoutes, deplacer ou
-- redimensionner une haie laisse l'herbe pousser au travers, et rien ne le signale.
-- On n'ecoute que les obstacles DEJA trouves (une poignee), pas toute la map : une haie posee ailleurs pendant la
-- partie demande encore un relancement, mais la retailler ou la bouger se voit tout de suite.
local function watchBlockers(zone: Zone)
	for _, connection in ipairs(zone.watchers) do
		connection:Disconnect()
	end
	table.clear(zone.watchers)

	for _, blocker in ipairs(zone.blockers) do
		for _, property in ipairs({ "CFrame", "Size" }) do
			zone.watchers[#zone.watchers + 1] = blocker:GetPropertyChangedSignal(property):Connect(function()
				queueRebuild(zone)
			end)
		end
	end
end

-- Log detaille, appele a CHAQUE pose (pas seulement au boot : une zone peut arriver bien plus tard par le streaming).
-- Ces nombres disent tout de suite si c'est le semis ou la zone qui est en cause quand l'herbe atterrit de travers.
local function logZone(zone: Zone)
	local first = zone.clumps[1]
	local where = if first then tostring(first.part.Position) else "aucune"
	print(
		`[GrassZone] "{zone.part.Name}" : {#zone.clumps} touffe(s) en {#zone.buckets} pave(s) | zone {zone.part.Size} @ `
			.. `{zone.part.Position} | 1re touffe @ {where}`
	)
end

-- Refait le semis, EN DIFFERE et UNE SEULE FOIS. Un redimensionnement a la souris emet des dizaines de changements
-- par seconde : sans ce garde, chacun relancerait un semis complet de plusieurs milliers de touffes.
queueRebuild = function(zone: Zone)
	if zone.rebuildPending then
		return
	end
	zone.rebuildPending = true
	task.delay(REBUILD_DELAY, function()
		zone.rebuildPending = false
		if zone.part.Parent ~= nil then
			populate(zone)
			-- Les obstacles ont pu changer : on repose les ecoutes sur la nouvelle liste.
			watchBlockers(zone)
			logZone(zone)
		end
	end)
end

-- La zone a bouge : on retraduit les pieds en monde et on reveille les touffes pour qu'elles se reposent au bon
-- endroit. Etre enfant d'une part ne suffit pas a suivre : une part ancree vit en coordonnees monde.
local function refresh(zone: Zone)
	local zoneCFrame = zone.part.CFrame
	for _, clump in ipairs(zone.clumps) do
		clump.basePos = zoneCFrame:PointToWorldSpace(clump.localPos)
		clump.lastCrush = math.huge -- force une reecriture : la touffe doit se reposer au nouvel endroit
	end
	-- Les centres de paves servent a TOUS les tests de distance : les oublier ici trierait sur l'ancienne position,
	-- et l'herbe cesserait de reagir sans qu'on voie pourquoi.
	for _, bucket in ipairs(zone.buckets) do
		bucket.center = zoneCFrame:PointToWorldSpace(bucket.localCenter)
		bucket.settling = true
	end
	zone.settling = true
end

-- ===== Ecrasement =====

-- Anime UN pave. `players` ne contient que les joueurs capables de toucher ce pave : elle est VIDE pour la quasi
-- totalite d'entre eux, et c'est tout l'interet -- la recherche d'ecrasement se reduit alors a rien.
-- `windScale` (0 a 1) vaut pour TOUT le pave : a 6 studs de cote, ses touffes sont toutes a la meme distance de la
-- camera, inutile de mesurer chacune. A 0, le pave ne calcule plus de vent du tout.
-- Retourne le nombre de touffes encore en mouvement.
local function updateBucket(bucket: Bucket, players: { Vector3 }, now: number, dt: number, windScale: number): number
	local radius = GrassZoneConfigs.CRUSH_RADIUS
	local moving = 0

	for _, clump in ipairs(bucket.clumps) do
		-- Le joueur le PLUS proche gagne. On ne MOYENNE pas les directions : deux joueurs de part et d'autre d'une
		-- touffe la redresseraient, ce qui est l'inverse du sens voulu.
		local best = 0
		local bestDir = clump.tiltDir
		for _, pos in ipairs(players) do
			local d = clump.basePos - pos
			d = Vector3.new(d.X, 0, d.Z) -- horizontal : sauter ne doit pas relever l'herbe
			local dist = d.Magnitude
			if dist < radius then
				local strength = 1 - dist / radius
				if strength > best then
					best = strength
					bestDir = if dist > 1e-3 then d / dist else clump.tiltDir
				end
			end
		end

		-- TRACE. Le passage laisse un ecrasement PERMANENT. On ne garde que le maximum jamais atteint : repasser au
		-- meme endroit ne releve rien, et s'eloigner ne l'efface pas.
		if best > 0 then
			clump.flattened = math.max(clump.flattened, best * GrassZoneConfigs.FLATTEN_AMOUNT)
			-- La direction est celle du DERNIER passage : la trace garde le sens du pas qui l'a faite.
			clump.tiltDir = bestDir
		elseif GrassZoneConfigs.FLATTEN_RECOVER > 0 then
			clump.flattened = math.max(0, clump.flattened - GrassZoneConfigs.FLATTEN_RECOVER * dt)
		end

		-- CIBLE D'ECRASEMENT, en fraction : le plus ecrase entre le pied EN COURS et la trace DEJA laissee.
		-- Quand le pied repart, l'herbe remonte donc jusqu'a la trace et s'y arrete, pas jusqu'a sa hauteur pleine.
		local target = math.max(best, clump.flattened)

		-- Ecraser est BRUTAL (le pied arrive d'un coup), se relever est LENT : c'est cet ecart qui fait lire le poids.
		-- DEUX VITESSES, une seule cible. L'inclinaison suit `crush`, qui claque ; le tassement suit `squashCrush`,
		-- qui traine. On lit donc l'herbe pencher PUIS se tasser, au lieu de recevoir les deux en bloc.
		-- La montee est commune : rien ne gagne a ce que la touffe se redresse en deux temps.
		local speed = if target > clump.crush then GrassZoneConfigs.CRUSH_SPEED else GrassZoneConfigs.RECOVER_SPEED
		clump.crush += (target - clump.crush) * (1 - math.exp(-speed * dt))
		if math.abs(target - clump.crush) < GrassZoneConfigs.SNAP_EPSILON then
			clump.crush = target -- un lerp exponentiel n'atteint jamais sa cible : sans ce clic, on reecrirait a vie
		end

		local squashSpeed = if target > clump.squashCrush
			then GrassZoneConfigs.SQUASH_SPEED
			else GrassZoneConfigs.RECOVER_SPEED
		clump.squashCrush += (target - clump.squashCrush) * (1 - math.exp(-squashSpeed * dt))
		if math.abs(target - clump.squashCrush) < GrassZoneConfigs.SNAP_EPSILON then
			clump.squashCrush = target
		end

		-- COULEUR : elle vise la MEME cible que le tassement, donc elle garde la teinte ecrasee sur la TRAINEE. Elle
		-- a en revanche sa propre vitesse de retour, plus vive : en quittant la touffe, la couleur retombe vite au
		-- niveau de la trainee, puis s'efface avec elle. On voit donc un point clair sous le pied, un chemin plus
		-- discret derriere, et une pelouse qui redevient uniforme en une minute.
		local colorSpeed = if target > clump.colorCrush
			then GrassZoneConfigs.CRUSH_SPEED
			else GrassZoneConfigs.COLOR_RECOVER_SPEED
		clump.colorCrush += (target - clump.colorCrush) * (1 - math.exp(-colorSpeed * dt))
		if math.abs(target - clump.colorCrush) < GrassZoneConfigs.SNAP_EPSILON then
			clump.colorCrush = target
		end

		if
			clump.crush ~= target
			or clump.squashCrush ~= target
			or clump.colorCrush ~= target
			or clump.mown ~= clump.lastMown
			or clump.mowStripe ~= clump.lastStripe
		then
			moving += 1
		end

		-- L'ECRASEMENT EST LA VALEUR MAITRESSE, et tout en decoule : l'aplatissement en hauteur, l'extinction du
		-- vent, et l'inclinaison si on en remet une. Une seule grandeur lissee, donc rien ne peut se desynchroniser,
		-- et chaque effet herite gratuitement du ressort (sec a la descente, lent a la remontee).
		-- C'etait l'inverse avant : tout etait tire de l'ANGLE, donc mettre l'angle a zero tuait l'aplatissement avec.
		local crushed = clump.crush
		-- Le tassement et l'assombrissement partent de la valeur RETARDEE : ils arrivent apres l'inclinaison.
		local squash = 1 - clump.squashCrush * GrassZoneConfigs.CRUSH_SQUASH
		-- LA COUPE S'AJOUTE AU PIETINEMENT, et on garde la plus COURTE des deux raisons plutot que de les additionner :
		-- deux effets qui s'additionnent finiraient sous zero et la touffe disparaitrait. Une touffe tondue reste donc
		-- courte pour toujours, et un pied la couche encore un peu par-dessus, sans jamais la faire remonter au-dessus.
		squash = math.min(squash, 1 - clump.mown * GrassZoneConfigs.MOW_CUT)

		local wind = 0
		local gustSquash = 1
		-- Eclaircissement de la rafale. Zero hors du vent : une touffe lointaine ou immobile ne doit rien payer,
		-- et rien ne reste eclairci quand le vent s'eteint (la valeur decroit avec windScale jusqu'a zero).
		local lighten = 0
		if windScale > 0 then
			-- RAFALE. Champ de bruit de Perlin qui DERIVE dans la direction du vent : des zones fortes et des zones
			-- calmes roulent sur le champ. Sans lui, toutes les touffes recoivent exactement le meme souffle et ca se
			-- lit comme un ventilateur, pas comme du vent.
			local drift = now * GrassZoneConfigs.GUST_SPEED
			-- Projection de la touffe sur les deux axes du vent. `across` utilise la perpendiculaire de WIND_DIR
			-- (on tourne de 90 degres : x,z -> -z,x), donc les deux axes restent coherents si le vent change.
			local along = clump.basePos.X * WIND_DIR.X + clump.basePos.Z * WIND_DIR.Z
			local across = clump.basePos.X * -WIND_DIR.Z + clump.basePos.Z * WIND_DIR.X
			local gust = math.noise(
				-- ECHANTILLONNE DANS LE REPERE DU VENT, pas en X/Z du monde. En X/Z, la meme frequence part dans les
				-- deux directions et le bruit ne peut faire que des taches RONDES : une masse de vent. Ici on
				-- separe le long du souffle (fin) et le travers (etire) -> des lamelles qui roulent.
				-- Le defilement (drift) ne s'applique qu'a l'axe du vent : c'est par la que la vague avance.
				(along - drift) * GrassZoneConfigs.GUST_SCALE,
				across * GrassZoneConfigs.GUST_SCALE / GrassZoneConfigs.GUST_STRETCH,
				0
			) * 2 -- math.noise rend environ [-0.5, 0.5] : on ramene a [-1, 1]
			local floor = GrassZoneConfigs.GUST_FLOOR
			local gustStrength = floor + (1 - floor) * math.clamp(gust * 0.5 + 0.5, 0, 1)

			-- Le decalage depend de la POSITION le long du vent : les touffes en amont bougent avant celles en aval,
			-- donc des vagues traversent le champ au lieu qu'il respire en bloc. windPhase casse ce qui resterait
			-- d'identique entre deux voisines exactement alignees.
			local phase = now * GrassZoneConfigs.WIND_SPEED
				- (clump.basePos.X * WIND_DIR.X + clump.basePos.Z * WIND_DIR.Z) * GrassZoneConfigs.WIND_WAVE
				+ clump.windPhase
			-- Une touffe couchee sous un pied ne doit plus onduler, et une touffe lointaine ondule de moins en moins.
			-- Une touffe TONDUE ne doit presque plus onduler : un gazon ras qui vague comme de l'herbe haute efface
			-- l'avant/apres qu'on vient tout juste de produire, et c'est lui le coeur du geste.
			local mowWind = 1 - clump.mown * (1 - GrassZoneConfigs.MOW_WIND)
			wind = (WIND_ANGLE + WIND_GUST * math.sin(phase)) * gustStrength * (1 - crushed) * windScale * mowWind

			-- La rafale TASSE l'herbe au passage, puis la laisse remonter. Seule la partie FORTE de la rafale ecrase
			-- (math.max(gust, 0)) : une zone calme ne doit pas tasser l'herbe en permanence.
			gustSquash = 1 - GrassZoneConfigs.GUST_SQUASH * math.max(gust, 0) * (1 - crushed) * windScale
			-- MEME champ que le tassement, donc la vague qu'on VOIT est exactement celle qui couche l'herbe.
			-- Une touffe deja couchee (pied) ou tondue ne scintille pas : elle ne bouge plus, elle n'a pas a briller.
			-- On ne garde que la moitie POSITIVE du bruit : le creux d'une vague ne doit rien teinter.
			-- La puissance CONCENTRE l'effet sur la crete -- sans elle le teintage bave sur toute la pelouse et se
			-- lit comme un aplat au lieu d'une vague qui passe.
			local crest = math.max(gust, 0) ^ GrassZoneConfigs.GUST_TINT_SHARPNESS
			-- LE TEINTAGE DE RAFALE NE TOUCHE PAS L'HERBE TONDUE. `(1 - clump.mown)` et non `mowWind` : un gazon
			-- ras ne vague pas, donc il ne change pas de couleur -- et surtout, ce teintage passait PAR-DESSUS la
			-- bande de tonte et la brouillait. Le BALANCEMENT, lui, garde sa part (mowWind) : un reste de
			-- fremissement est joli, un reste de couleur efface le travail du joueur.
			lighten = GrassZoneConfigs.GUST_TINT * crest * (1 - crushed) * windScale * (1 - clump.mown)
		end

		-- Tant que le vent souffle sur ce pave on ecrit TOUJOURS (il bouge en permanence). Une fois le vent eteint,
		-- on n'ecrit plus que si l'ecrasement a change : une touffe lointaine et immobile ne coute alors plus rien.
		-- On compare les DEUX valeurs : la lente peut encore bouger alors que la rapide est deja posee.
		-- La REVELATION change l'aspect sans qu'aucune valeur d'animation ne bouge : sans ce test, une touffe
		-- immobile et loin du joueur ne serait jamais repeinte, et la moitie de la pelouse resterait eteinte.
		-- `fading` et non un booleen "allume ou non" : le fondu passe par des valeurs INTERMEDIAIRES, et une
		-- comparaison binaire ne les voit pas. Avec elle, l'allumage passait par accident (l'etat changeait) mais
		-- l'EXTINCTION ne redessinait rien : l'herbe hors du vent restait bleue pour toujours.
		if
			windScale > 0
			or fading
			or clump.crush ~= clump.lastCrush
			or clump.squashCrush ~= clump.lastSquashCrush
			or clump.colorCrush ~= clump.lastColorCrush
			or clump.mown ~= clump.lastMown
			or clump.mowStripe ~= clump.lastStripe
		then
			-- L'INCLINAISON EST L'ECART entre l'ecrasement rapide et le tassement lent, ramene sur la cible.
			-- Au moment du pas l'ecart est maximal ; une fois le lent arrive, il est NUL et la touffe est droite.
			-- Ecrire ca en (1 - tassement) laissait un residu permanent : le tassement plafonne a FLATTEN_AMOUNT a
			-- cause de la trace, donc il n'atteint jamais 1 et l'inclinaison ne tombait jamais a zero.
			local tilt = 0
			if target > 1e-3 then
				tilt = TILT_ANGLE * math.clamp((clump.crush - clump.squashCrush) / target, 0, 1)
			end
			apply(clump, wind, squash * gustSquash, tilt, clump.colorCrush, clump.mown, lighten)
			clump.lastCrush = clump.crush
			clump.lastSquashCrush = clump.squashCrush
			clump.lastColorCrush = clump.colorCrush
			clump.lastMown = clump.mown
		end
	end

	return moving
end

local function updateZone(zone: Zone, positions: { Vector3 }, anchor: Vector3, now: number, dt: number)
	local windReach = GrassZoneConfigs.WIND_VIEW_DISTANCE
	local crushReach = GrassZoneConfigs.CRUSH_RADIUS
	local zoneMoving = 0
	local near: { Vector3 } = {} -- reutilisee d'un pave a l'autre : pas une table neuve par pave et par image

	local fadeStart = GrassZoneConfigs.WIND_FADE_START
	local fadeSpan = math.max(windReach - fadeStart, 1e-3)

	for _, bucket in ipairs(zone.buckets) do
		local d = bucket.center - anchor
		-- On retranche le rayon du pave : sinon un pave a cheval sur la limite serait ecarte alors qu'une partie de ses
		-- touffes est bien visible.
		local dist = d.Magnitude - bucket.radius
		-- Plein vent jusqu'a fadeStart, puis extinction progressive, zero pile a windReach. Au-dela on ne calcule plus
		-- rien -- et comme l'amplitude y est deja nulle, la coupure ne se voit pas.
		local windScale = math.clamp((windReach - dist) / fadeSpan, 0, 1)
		-- Un pave dont des touffes se relevent encore garde la main meme sans vent, sinon elles se figeraient couchees
		-- des qu'on tourne la camera.
		if windScale > 0 or bucket.settling or fading then
			table.clear(near)
			for _, pos in ipairs(positions) do
				local h = bucket.center - pos
				if math.sqrt(h.X * h.X + h.Z * h.Z) - bucket.radius < crushReach then
					near[#near + 1] = pos
				end
			end

			local moving = updateBucket(bucket, near, now, dt, windScale)
			bucket.settling = moving > 0
			zoneMoving += moving
		end
	end

	zone.settling = zoneMoving > 0
end

local function update(dt: number)
	if #zones == 0 then
		return
	end

	-- ANCRE DU CHAMP D'ACTION : mon personnage. La camera ne sert que de repli tant qu'il n'a pas spawn -- sans elle
	-- le champ serait centre sur l'origine du monde et toute l'herbe serait figee au premier chargement.
	local anchor: Vector3
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		anchor = root.Position
	else
		local camera = workspace.CurrentCamera
		if not camera then
			return -- tot au boot, ni perso ni camera : rien a ancrer
		end
		anchor = camera.CFrame.Position
	end
	local now = os.clock()

	-- FONDU DE LA REVELATION. Une seule valeur pour toute la pelouse : elles s'allument ensemble.
	local revealTarget = if highlight then 1 else 0
	if reveal ~= revealTarget then
		reveal += (revealTarget - reveal) * math.min(1, GrassZoneConfigs.HIGHLIGHT_FADE_SPEED * dt)
		-- Un lerp exponentiel n'atteint JAMAIS sa cible : sans ce clic, on redessinerait toute la pelouse a
		-- vie pour un residu invisible. Meme piege que l'ecrasement.
		if math.abs(revealTarget - reveal) < GrassZoneConfigs.SNAP_EPSILON then
			reveal = revealTarget
		end
	end
	fading = reveal ~= revealTarget

	-- Positions des personnages, relevees UNE fois par image et partagees par toutes les zones.
	local positions: { Vector3 } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			positions[#positions + 1] = root.Position
		end
	end

	for _, zone in ipairs(zones) do
		if zone.part.Parent ~= nil then
			-- Ecarte d'un bloc les zones hors de vue. Une zone dont des touffes se relevent encore garde la main, sinon
			-- elles se figeraient couchees des qu'on tourne la camera.
			local d = zone.part.Position - anchor
			local reach = zone.radius + GrassZoneConfigs.WIND_VIEW_DISTANCE
			-- `fading` passe AUSSI ici, pas seulement au niveau des paves : une zone entiere trop loin etait sautee,
			-- donc son herbe ne s'allumait jamais et restait verte pendant que le reste passait au bleu.
			if d.Magnitude < reach or zone.settling or fading then
				updateZone(zone, positions, anchor, now, dt)
			end
		end
	end
end

-- ===== Boot =====

-- ===== REVELATION =====

-- Allume / eteint la revelation : tout ce qui n'est pas encore coupe passe en neon. Appelee par MowController
-- (touche maintenue). Le RENDU, lui, vit dans apply : la couleur d'une touffe n'a qu'un seul ecrivain.
function GrassZoneController.setHighlight(on: boolean)
	-- On ne pose que l'INTENTION. Le fondu et le reveil des paves sont geres par la boucle : elle sait, elle,
	-- quand la transition est finie. Forcer les paves ici ne les reveillerait qu'une image, pas le temps du fondu.
	highlight = on
	fading = true
end

-- ===== TONTE =====

-- Coupe l'herbe dans un rayon autour d'un point. A appeler A CHAQUE IMAGE par le controller de la tondeuse, avec la
-- position de son carter.
--
-- La coupe est PERMANENTE : `mown` ne fait que monter. Repasser dessus ne releve rien, s'eloigner ne l'efface pas.
-- C'est toute la difference avec le PIETINEMENT, qui, lui, se releve (voir FLATTEN_RECOVER dans la config). Les deux
-- cohabitent sans se marcher dessus : marcher sur du tondu le couche encore un peu, puis ca remonte jusqu'a la coupe.
--
-- Rend le nombre de touffes REELLEMENT coupees cette image. Zero = la tondeuse tourne dans le vide : de quoi couper le
-- son de coupe ou faire avancer une jauge sans avoir a recompter derriere.
function GrassZoneController.mowAt(worldPos: Vector3, radius: number, dt: number, direction: Vector3?): number
	local rate = GrassZoneConfigs.MOW_RATE * dt
	-- SENS de la coupe, projete sur l'axe de bandes. Calcule UNE fois pour toute la passe : il est le meme pour
	-- toutes les touffes de cette image, le refaire par touffe couterait pour rien.
	-- Repasser dans l'autre sens REECRIT la bande : c'est exactement ce que fait une vraie tondeuse.
	local stripe = 0
	if direction and GrassZoneConfigs.MOW_STRIPE_STRENGTH > 0 then
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude > 1e-3 then
			flat = flat.Unit
			if not stripeAxis then
				-- Axe impose par la config s'il est non nul, sinon APPRIS de cette premiere passe.
				local forced = GrassZoneConfigs.MOW_STRIPE_AXIS
				local flatForced = Vector3.new(forced.X, 0, forced.Z)
				stripeAxis = if flatForced.Magnitude > 1e-3 then flatForced.Unit else flat
			end
			stripe = math.clamp(flat:Dot(stripeAxis :: Vector3), -1, 1)
		end
	end
	local total = 0

	for _, zone in ipairs(zones) do
		-- On ecarte la zone ENTIERE d'un coup quand la tondeuse est loin. La carte en compte plusieurs et la tondeuse
		-- n'en touche qu'une : sans ce test on parcourrait toutes les touffes de la map a chaque image.
		local zd = zone.part.Position - worldPos
		if math.sqrt(zd.X * zd.X + zd.Z * zd.Z) - zone.radius > radius then
			continue
		end

		local zoneCut = 0
		for _, bucket in ipairs(zone.buckets) do
			local bd = bucket.center - worldPos
			if math.sqrt(bd.X * bd.X + bd.Z * bd.Z) - bucket.radius > radius then
				continue
			end

			local bucketCut = 0
			for _, clump in ipairs(bucket.clumps) do
				-- Une touffe deja coupee a fond ne coute plus rien : c'est le cas le plus frequent sur une pelouse
				-- qu'on finit, et c'est justement la que le joueur repasse le plus.
				do
					local d = clump.basePos - worldPos
					-- Horizontal, comme le pietinement : la hauteur ne doit pas compter, sinon la tondeuse raterait
					-- justement les touffes les plus hautes, celles qu'on vient couper.
					if math.sqrt(d.X * d.X + d.Z * d.Z) < radius then
						if clump.mown < 1 then
							clump.mown = math.min(1, clump.mown + rate)
							bucketCut += 1
						end
						-- LA BANDE SE REECRIT MEME SUR UNE TOUFFE DEJA COUPEE. On sautait auparavant toute touffe deja tondue
						-- a fond : la bande restait donc figee sur la PREMIERE passe, et repasser dans l'autre sens ne
						-- changeait plus rien -- alors que c'est tout l'interet. Une vraie tondeuse reecrit la bande a chaque
						-- passage.
						if stripe ~= clump.mowStripe then
							clump.mowStripe = stripe
							bucketCut += 1 -- reveille le pave : sans ca la nouvelle bande ne serait pas dessinee
						end
					end
				end
			end

			-- Le pave doit CONTINUER a etre mis a jour, meme sans vent et sans joueur assez pres : sinon la coupe
			-- qu'on vient de poser ne serait jamais dessinee. Meme piege que les touffes qui se figent couchees.
			if bucketCut > 0 then
				bucket.settling = true
				zoneCut += bucketCut
			end
		end

		if zoneCut > 0 then
			zone.settling = true
			total += zoneCut
		end
	end

	return total
end

function GrassZoneController.init()
	-- EN TACHE DE FOND : resolvePath peut attendre, et un init de boot ne doit jamais bloquer la sequence.
	task.spawn(function()
		local source = resolvePath(ReplicatedStorage, GrassZoneConfigs.MESH_PATH)
		if not source or not source:IsA("BasePart") then
			warn(
				`[GrassZone] Mesh introuvable : ReplicatedStorage.{table.concat(GrassZoneConfigs.MESH_PATH, ".")}. `
					.. `Pas d'herbe de zone.`
			)
			return
		end
		template = source

		-- FLEURS. Elles vivent a cote de GrassMesh : on remonte d'un cran depuis son chemin. Aucune n'est trouvee ->
		-- pas de fleurs, et ce n'est PAS une erreur (une place peut ne pas les avoir).
		local foliages = source.Parent
		if foliages then
			for _, name in ipairs(GrassZoneConfigs.FLOWER_NAMES) do
				local mesh = foliages:FindFirstChild(name)
				if mesh and mesh:IsA("BasePart") then
					flowerTemplates[#flowerTemplates + 1] = mesh
				end
			end
			-- Une fleur manquante ne dit RIEN : la retirer de Studio est une facon valable de l'enlever, et prevenir
			-- pour un choix delibere finit par noyer les vrais messages.
			-- En revanche, une liste NON VIDE dont on ne trouve AUCUN element, ca c'est anormal et actionnable : le
			-- chemin est faux, ou les meshes ont ete deplaces.
			if #GrassZoneConfigs.FLOWER_NAMES > 0 and #flowerTemplates == 0 then
				warn(
					`[GrassZone] Aucune des fleurs listees n'existe a cote de GrassMesh `
						.. `({table.concat(GrassZoneConfigs.FLOWER_NAMES, ", ")}). Verifie ou elles sont rangees.`
				)
			end
		end

		local root = resolvePath(workspace, GrassZoneConfigs.ROOT)
		if not root then
			warn(
				`[GrassZone] Dossier introuvable : Workspace.{table.concat(GrassZoneConfigs.ROOT, ".")}. `
					.. `Pas d'herbe de zone dans cette place.`
			)
			return
		end

		local prefix = GrassZoneConfigs.ZONE_PREFIX
		local function consider(instance: Instance)
			-- Le nom D'ABORD : ce test tourne sur tout ce qui arrive dans la map, il doit rester le moins cher possible.
			if instance.Name:sub(1, #prefix) ~= prefix or not instance:IsA("BasePart") then
				return
			end
			if instance:FindFirstChild(FOLDER_NAME) then
				return -- deja remplie
			end

			local zone: Zone = {
				part = instance,
				clumps = {},
				buckets = {},
				blockers = {},
				radius = 0,
				settling = true,
				generation = 0,
				watchers = {},
				rebuildPending = false,
			}
			zones[#zones + 1] = zone
			-- EN TACHE DE FOND : le semis est etale sur plusieurs images, donc il YIELD. Cette fonction est aussi
			-- branchee sur DescendantAdded : y attendre bloquerait ce signal pour tout le reste de la map.
			task.spawn(function()
				populate(zone)
				watchBlockers(zone)
				logZone(zone)
			end)

			-- L'herbe SUIT sa zone. Deplacer la part (dans Studio, pendant un test, ou par du code) retraduit les
			-- pieds ; la redimensionner refait le semis, parce que la nouvelle surface veut un autre nombre de touffes.
			connections[#connections + 1] = instance:GetPropertyChangedSignal("CFrame"):Connect(function()
				refresh(zone)
			end)

			-- Le semis se refait en DIFFERE, par le meme chemin que les obstacles qui bougent. Une part qui arrive par
			-- le streaming recoit ses proprietes en plusieurs fois : Size a change trois fois en 80 ms, donc 570
			-- touffes reconstruites trois fois pour rien. On attend que ca se calme, puis on reconstruit une fois.
			connections[#connections + 1] = instance:GetPropertyChangedSignal("Size"):Connect(function()
				queueRebuild(zone)
			end)
		end

		for _, descendant in ipairs(root:GetDescendants()) do
			consider(descendant)
		end
		-- Les zones qui arrivent apres (streaming, edition en live) se remplissent aussi. On n'ecoute QUE ce dossier :
		-- brancher workspace.DescendantAdded ferait passer chaque part de personnage par le test pour rien.
		connections[#connections + 1] = root.DescendantAdded:Connect(consider)

		if #zones == 0 then
			print(`[GrassZone] Aucune zone "{prefix}..." au demarrage (elles peuvent arriver ensuite par le streaming).`)
		end

		-- LA BOUCLE SE BRANCHE DE TOUTE FACON, meme sans une seule zone au demarrage. Un `return` etait pose ici sur
		-- "aucune zone", et il sautait ce Connect : une zone arrivee 3 s plus tard par le streaming etait bien remplie
		-- (l'herbe s'affichait, jolie) mais plus rien ne l'animait ni ne l'ecrasait. `update` sort tout de suite tant
		-- que la liste est vide, donc ne rien brancher n'economisait rien.
		heartbeat = RunService.Heartbeat:Connect(update)
	end)
end

-- Coupe TOUT ce que ce module a cree : la boucle, les ecoutes et les touffes. Ces connexions vivent sur RunService et
-- sur des parts de la map, qui SURVIVENT a ce script : sans Disconnect explicite elles tourneraient toute la session.
function GrassZoneController.stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, zone in ipairs(zones) do
		for _, watcher in ipairs(zone.watchers) do
			watcher:Disconnect()
		end
		table.clear(zone.watchers)
		local folder = zone.part:FindFirstChild(FOLDER_NAME)
		if folder then
			folder:Destroy()
		end
	end
	table.clear(zones)
end

return GrassZoneController
