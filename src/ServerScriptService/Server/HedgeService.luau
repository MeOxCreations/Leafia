--!strict
-- Detecte quand un joueur se presente devant une haie et quand il s'en ecarte : quelle haie, quelle FACE, et
-- le ralentissement au travail.
--
-- L'orientation forcee et la camera sont cote CLIENT (HedgeController) : le client possede son personnage et
-- sa camera, les forcer d'ici donnerait du rubber-banding. Ce service DECIDE et pose les attributs
-- LeafiaAtHedge / LeafiaHedgeNormal ; le client obeit.
--
-- Il ne touche JAMAIS a WalkSpeed non plus : il declare une intention a CharacterService, qui la possede.
-- Deux modules qui ecrivent la meme propriete finissent toujours par se battre.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)
local CharacterService = require(script.Parent.CharacterService)
local ToolService = require(script.Parent.ToolService)

local HedgeService = {}

-- Les quatre cotes d'une haie. On ignore le dessus et le dessous : on ne taille pas une haie en marchant
-- dessus, et les inclure ferait accrocher le joueur qui saute par-dessus.
local FACE_AXES = {
	{ axis = "X", sign = 1 },
	{ axis = "X", sign = -1 },
	{ axis = "Z", sign = 1 },
	{ axis = "Z", sign = -1 },
}

type Contact = {
	hedge: BasePart,
	-- Normale de la face, en monde : la direction vers laquelle le joueur regarde la haie.
	normal: Vector3,
	distance: number,
}

local atHedge: { [Player]: Contact } = {}
-- Instant avant lequel un joueur ne peut pas se raccrocher, apres une sortie volontaire. Sans ce temps mort la
-- haie est encore a portee la frame suivante : ca raccroche, la sortie est redetectee, ca redecroche.
local exitUntil: { [Player]: number } = {}
-- Date du dernier changement de face. Sert a NE PAS lire un contournement comme une sortie.
--
-- En tournant le coin, la normale pivote de 90 degres : le deplacement lateral d'avant devient aligne avec la
-- nouvelle normale, et le test de sortie le prenait pour une fuite. Le joueur etait ejecte du chantier au
-- moment precis ou il contournait, sans avoir rien demande.
local faceChangedAt: { [Player]: number } = {}

-- Dossier des boites d'espace vital. Cree une fois, garde ici pour servir de filtre a chaque lancer sans avoir
-- a le rechercher.
local bufferFolder: Folder? = nil
-- Quelle haie possede quelle boite. Une table plutot qu'une recherche par nom : les haies portent souvent le
-- MEME nom, et le dossier leur est commun.
local buffers: { [BasePart]: BasePart } = {}
-- Meme principe pour les zones de chantier posees au sol.
local zones: { [BasePart]: BasePart } = {}
local zoneFolder: Folder? = nil

local function getZoneFolder(): Folder
	local existing = zoneFolder
	if existing and existing.Parent then
		return existing
	end
	local found = workspace:FindFirstChild(HedgeConfigs.ZONE_FOLDER)
	if found and found:IsA("Folder") then
		zoneFolder = found
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = HedgeConfigs.ZONE_FOLDER
	folder.Parent = workspace
	zoneFolder = folder
	return folder
end

local function getBufferFolder(): Folder
	local existing = bufferFolder
	if existing and existing.Parent then
		return existing
	end
	local found = workspace:FindFirstChild(HedgeConfigs.BUFFER_FOLDER)
	if found and found:IsA("Folder") then
		bufferFolder = found
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = HedgeConfigs.BUFFER_FOLDER
	folder.Parent = workspace
	bufferFolder = folder
	return folder
end

-- Distance du joueur a la BOITE de la haie, et non a son centre. Une haie de 20 studs de long ne doit pas
-- compter comme "loin" parce qu'on se tient a son extremite.
--
-- Calcul a la main plutot que par une API : on ramene le point dans la boite en le bornant sur chaque axe, la
-- distance a ce point borne EST la distance a la boite. Marche aussi sur une haie tournee, puisqu'on travaille
-- dans son repere.
local function distanceToHedge(hedge: BasePart, position: Vector3): number
	local localPos = hedge.CFrame:PointToObjectSpace(position)
	local half = hedge.Size * 0.5
	local clamped = Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z)
	)
	return (localPos - clamped).Magnitude
end

-- Normale CARDINALE de la face travaillee, deduite de la position du joueur dans le repere de la haie.
--
-- On n'utilise PAS la normale brute du raycast : sur un MeshPart elle vient du triangle touche, donc elle part
-- dans tous les sens sur une surface irreguliere comme une haie. Pour orienter le joueur et la camera il faut
-- une direction propre, un des quatre cotes, pas l'angle d'une feuille.
-- `currentNormal` est la face deja travaillee, s'il y en a une. Elle sert d'HYSTERESIS : dans un angle de
-- haie, deux faces sont a egalite, le choix basculerait a chaque frame et la camera partirait en oscillation
-- gauche-droite. On ne change de face que si une autre devient NETTEMENT meilleure.
local function faceNormal(hedge: BasePart, viewerPosition: Vector3, currentNormal: Vector3?): Vector3
	-- Dans le repere de la haie, une haie tournee de 37 degres se traite comme une haie droite.
	local localPos = hedge.CFrame:PointToObjectSpace(viewerPosition)
	local half = hedge.Size * 0.5

	-- De COMBIEN le joueur a depasse le plan de cette face. Positif = il se tient devant. Le plus grand
	-- designe la face qu'il travaille.
	--
	-- MESURE DEPUIS LE JOUEUR, plus depuis le point d'impact. Le point d'impact est toujours SUR la haie :
	-- sur une haie mince, toutes les faces s'y retrouvent a moins d'une demi-epaisseur l'une de l'autre. La
	-- marge d'hysteresis valant plus que ca, la face avant ne pouvait MATHEMATIQUEMENT jamais perdre, et
	-- contourner la haie par le bout etait impossible.
	-- La position du joueur, elle, s'ecarte franchement quand il contourne : les valeurs se separent, et la
	-- marge redevient ce qu'elle doit etre, une simple zone de calme.
	local function outsideOf(face): number
		local along = if face.axis == "X" then localPos.X else localPos.Z
		local halfAlong = if face.axis == "X" then half.X else half.Z
		return along * face.sign - halfAlong
	end

	local best = FACE_AXES[1]
	local bestOutside = -math.huge
	for _, face in ipairs(FACE_AXES) do
		local outside = outsideOf(face)
		if outside > bestOutside then
			bestOutside = outside
			best = face
		end
	end

	-- La face courante garde sa place tant que la meilleure ne la bat pas d'au moins la marge.
	if currentNormal then
		-- On repasse la normale dans le repere de la haie pour la comparer aux axes : la haie a pu tourner.
		local localCurrent = hedge.CFrame:VectorToObjectSpace(currentNormal)
		for _, face in ipairs(FACE_AXES) do
			local axisValue = if face.axis == "X" then localCurrent.X else localCurrent.Z
			-- Seuil large : on cherche juste a reconnaitre de quel cote pointe la normale.
			if axisValue * face.sign > 0.9 then
				if outsideOf(face) + HedgeConfigs.FACE_SWITCH_MARGIN >= bestOutside then
					best = face
				end
				break
			end
		end
	end

	local localNormal = if best.axis == "X"
		then Vector3.new(best.sign, 0, 0)
		else Vector3.new(0, 0, best.sign)
	-- VectorToWorldSpace et non PointToWorldSpace : une normale est une DIRECTION, elle ne doit pas subir la
	-- translation de la haie.
	return hedge.CFrame:VectorToWorldSpace(localNormal)
end

-- Lance un VOLUME devant le joueur et rend le contact s'il touche une haie.
--
-- Blockcast et non Raycast : une ligne ne voyait que ce qui se trouvait pile a la hauteur du nombril du
-- personnage. Une haie plus basse ou plus haute passait dessous ou dessus sans jamais etre detectee, alors
-- qu'on est manifestement devant elle.
-- `current` : le contact deja en cours, s'il existe. Sa normale sert d'hysteresis dans les angles de haie.
local function castForward(character: Model, root: BasePart, length: number, current: Contact?): Contact?
	local origin = root.Position
	-- LookVector du HumanoidRootPart : il ne s'incline jamais, le volume reste donc horizontal meme en pente.
	local direction = root.CFrame.LookVector

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Le personnage : sans lui le volume taperait dans l'outil qu'il tient, a zero stud.
	-- Le dossier des boites d'espace vital : elles entourent chaque haie, donc elles seraient touchees AVANT
	-- elle et plus aucune haie ne serait jamais detectee.
	params.FilterDescendantsInstances = { character, getBufferFolder() }

	local size = Vector3.new(HedgeConfigs.DETECT_WIDTH, HedgeConfigs.DETECT_HEIGHT, HedgeConfigs.DETECT_THICKNESS)

	-- EVENTAIL de lancers. Un seul lancer droit devant ratait la haie des que le joueur se presentait de biais,
	-- alors qu'il etait manifestement en train de travailler dessus. On garde le contact le plus PROCHE.
	local best: RaycastResult? = nil
	for _, angle in ipairs(HedgeConfigs.DETECT_ANGLES) do
		-- Une CFrame de rotation pure appliquee a un Vector3 le fait tourner sans le deplacer.
		local rayDirection = CFrame.Angles(0, math.rad(angle), 0) * direction
		-- La boite part orientee comme SON lancer : sa profondeur suit sa propre direction.
		local start = CFrame.lookAt(origin, origin + rayDirection)
		local result = workspace:Blockcast(start, size, rayDirection * length, params)

		if result and CollectionService:HasTag(result.Instance, HedgeConfigs.TAG) then
			if best == nil or result.Distance < best.Distance then
				best = result
			end
		end
	end

	if not best then
		return nil
	end

	local hit = best.Instance :: BasePart
	-- L'hysteresis ne vaut que sur la MEME haie : en changeant de haie, la face repart de zero.
	local previousNormal = if current and current.hedge == hit then current.normal else nil

	local contact: Contact = {
		hedge = hit,
		-- La face se deduit de la position du JOUEUR, pas du point touche : c'est lui qui contourne la haie.
		normal = faceNormal(hit, origin, previousNormal),
		distance = best.Distance,
	}
	return contact
end

local function leaveHedge(player: Player)
	if not atHedge[player] then
		return
	end
	atHedge[player] = nil
	CharacterService.setSpeedOverride(player, nil)

	local character = player.Character
	if character then
		character:SetAttribute(HedgeConfigs.AT_HEDGE_ATTRIBUTE, false)
	end
end

local function updatePlayer(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		leaveHedge(player)
		return
	end

	-- MAINS VIDES = PAS DE CHANTIER. Sans outil il n'y a rien a faire devant une haie : lui coller la camera de
	-- travail, lui bloquer l'orientation et le ralentir serait une contrainte sans contrepartie, et il ne
	-- comprendrait meme pas pourquoi il ne peut plus avancer.
	--
	-- Teste AVANT tout le reste, et pas seulement a l'accroche : ranger l'outil en plein chantier doit relacher
	-- le joueur, pas le laisser coince jusqu'a ce qu'il pense a reculer.
	if not ToolService.getHeld(player) then
		leaveHedge(player)
		return
	end

	local current = atHedge[player]

	-- SORTIE VOLONTAIRE. Le joueur pousse franchement vers l'arriere : il quitte le chantier, on le lache tout
	-- de suite sans attendre que le volume de detection le perde. Sans ca il faudrait reculer plusieurs studs a
	-- vitesse de travail avant d'etre libere, ce qui donnerait une sortie molle.
	--
	-- MoveDirection est l'INTENTION du joueur, deja repliquee au serveur : aucun remote a ajouter.
	-- Le contournement qu'on vient d'autoriser ressemble a une fuite : la normale a pivote de 90 degres, donc
	-- le glissement lateral d'avant pointe maintenant vers la sortie. On laisse au joueur ET au client le temps
	-- de se realigner sur la nouvelle face avant de rejuger son intention.
	local turning = os.clock() - (faceChangedAt[player] or 0) < HedgeConfigs.FACE_CHANGE_GRACE

	-- TROP PRES : l'aimant est en train de repousser le joueur. Sa poussee arrive ici par le meme canal qu'une
	-- vraie touche ET dans la meme direction : aucun moyen de les distinguer une fois melangees.
	--
	-- Alors on ne cherche pas a les distinguer, on choisit QUAND poser la question. Tant que la distance de
	-- travail n'est pas retablie, l'intention de sortir n'est pas jugee. Le joueur qui pousse vraiment vers
	-- l'arriere sortira des qu'il aura repris sa distance, soit un dixieme de seconde plus tard.
	local tooClose = current ~= nil
		and distanceToHedge(current.hedge, root.Position)
			< HedgeConfigs.WORK_DISTANCE + HedgeConfigs.WORK_DISTANCE_TOLERANCE

	if current and not turning and not tooClose then
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid:IsA("Humanoid") then
			local move = humanoid.MoveDirection
			-- Magnitude proche de 1 : une vraie poussee du joueur, pas une correction d'aimant. Les deux
			-- arrivent par le meme canal, seule leur AMPLEUR les distingue.
			if move.Magnitude > HedgeConfigs.EXIT_MIN_INPUT and move:Dot(current.normal) > HedgeConfigs.EXIT_DOT then
				-- Temps mort : la haie reste a portee la frame suivante, on raccrocherait aussitot.
				exitUntil[player] = os.clock() + HedgeConfigs.EXIT_COOLDOWN
				leaveHedge(player)
				return
			end
		end
	end

	-- Sortie recente : on refuse toute nouvelle accroche jusqu'a la fin du temps mort.
	if not current and os.clock() < (exitUntil[player] or 0) then
		return
	end

	-- MAINTIEN PAR PROXIMITE. Une fois accroche, on ne redemande plus au joueur de REGARDER la haie : on
	-- verifie seulement qu'il est encore a cote.
	--
	-- Sans ca, contourner une haie etait impossible. L'orientation du joueur est bloquee face a la haie ; en
	-- glissant vers le bout, son eventail de detection finit donc par pointer dans le vide. Le contact tombait
	-- AVANT qu'il ait avance assez pour que la face du bout l'emporte, il se raccrochait aussitot sur la face
	-- avant, et il tournait en rond.
	--
	-- Le REGARD sert a s'accrocher, c'est une intention. La PROXIMITE sert a rester, c'est un chantier. Ce ne
	-- sont pas les memes questions, elles n'ont pas a avoir la meme reponse.
	local contact: Contact? = nil
	local held = if current then distanceToHedge(current.hedge, root.Position) else math.huge
	if current and held <= HedgeConfigs.HOLD_RANGE then
		contact = {
			hedge = current.hedge,
			-- Recalculee chaque frame depuis la position du joueur : c'est elle qui lui fait tourner le coin.
			normal = faceNormal(current.hedge, root.Position, current.normal),
			distance = held,
		}
	else
		-- Deja au travail : on cherche plus loin avant de lacher. Sinon plus court avant d'accrocher.
		local length = if current then HedgeConfigs.RAY_LENGTH_ENGAGED else HedgeConfigs.RAY_LENGTH
		contact = castForward(character, root, length, current)
	end

	if not contact then
		leaveHedge(player)
		return
	end

	-- Marque le pivot AVANT d'ecrire le nouveau contact : c'est lui qui ouvre le delai de grace ci-dessus.
	-- Compare a 0.99 et non a l'egalite : deux normales cardinales identiques peuvent differer d'un epsilon
	-- apres les allers-retours de repere, et on rouvrirait le delai a chaque frame pour rien.
	if current and current.normal:Dot(contact.normal) < 0.99 then
		faceChangedAt[player] = os.clock()
	end

	atHedge[player] = contact
	character:SetAttribute(HedgeConfigs.AT_HEDGE_ATTRIBUTE, true)
	-- La normale est mise a jour meme si la haie ne change pas : le joueur peut contourner vers une autre face.
	character:SetAttribute(HedgeConfigs.HEDGE_NORMAL_ATTRIBUTE, contact.normal)

	if not current then
		-- Premiere accroche : on impose l'allure de travail. CharacterService fait la descente en douceur.
		CharacterService.setSpeedOverride(player, HedgeConfigs.WORK_SPEED)
	end
end

-- Etat courant, pour les services qui en auront besoin (coupe, camera, UI).
function HedgeService.getContact(player: Player): Contact?
	return atHedge[player]
end

-- ESPACE VITAL : une boite invisible un peu plus large que la haie, pour que le joueur ne puisse pas s'y
-- coller.
--
-- On laisse la PHYSIQUE repousser plutot que d'ecrire un repoussement en code. Elle gere le glissement le long
-- de la haie, les sauts et les collisions entre joueurs, sans jamais se battre avec la simulation locale du
-- client. Un repoussement code aurait fait vibrer le personnage a chaque frame.
--
-- ATTENTION : `CanQuery = false` ne sert a RIEN ici. Cette propriete n'a d'effet que si `CanCollide` est faux.
-- Une part solide est donc toujours vue par les raycasts, quoi qu'on mette dans CanQuery. C'est pour ca que la
-- boite est rangee dans un DOSSIER a part : la detection l'exclut explicitement.
--
-- Le dossier est indispensable. Un filtre de raycast exclut une instance ET ses descendants : si la boite
-- etait enfant de la haie, l'exclure exclurait la haie et plus rien ne serait jamais detecte.
local function ensureBuffer(hedge: BasePart)
	local existing = buffers[hedge]
	if existing and existing.Parent then
		return
	end

	local margin = HedgeConfigs.BUFFER_MARGIN * 2
	local buffer = Instance.new("Part")
	buffer.Name = HedgeConfigs.BUFFER_NAME
	buffer.Anchored = true
	buffer.CanCollide = true
	buffer.CanTouch = false
	buffer.CastShadow = false
	buffer.Transparency = 1
	-- Elargie sur les COTES seulement. En l'etirant aussi en hauteur, son toit depasserait celui de la haie et
	-- le joueur se retrouverait a marcher sur du vide au-dessus.
	buffer.Size = hedge.Size + Vector3.new(margin, 0, margin)
	buffer.CFrame = hedge.CFrame
	buffer.Parent = getBufferFolder()

	buffers[hedge] = buffer

	-- La boite ne vit plus DANS la haie : rien ne la detruirait avec elle. On refait le lien a la main, sinon
	-- une haie supprimee laisserait un mur invisible en plein milieu du jardin.
	hedge.Destroying:Once(function()
		buffers[hedge] = nil
		buffer:Destroy()
	end)
end

-- ZONE DE CHANTIER : le rectangle de beams pose au sol autour de la haie.
--
-- PIEGE : redimensionner une part EN SCRIPT ne deplace pas ses Attachment, contrairement a l'outil Echelle de
-- Studio. Les beams resteraient donc a la taille du modele d'origine. On remet les attachments a l'echelle
-- nous-memes, proportionnellement, ce qui marche quelle que soit la facon dont ils ont ete disposes.
local function ensureZone(hedge: BasePart)
	local existing = zones[hedge]
	if existing and existing.Parent then
		return
	end

	local template: Instance? = ReplicatedStorage
	for _, name in ipairs(HedgeConfigs.ZONE_ASSET) do
		template = template and template:FindFirstChild(name)
	end
	if not (template and template:IsA("BasePart")) then
		warn(`[HedgeService] Zone introuvable : ReplicatedStorage.{table.concat(HedgeConfigs.ZONE_ASSET, ".")}`)
		return
	end

	local zone = template:Clone()
	local margin = HedgeConfigs.ZONE_MARGIN * 2
	local newSize =
		Vector3.new(hedge.Size.X + margin, HedgeConfigs.ZONE_THICKNESS, hedge.Size.Z + margin)
	local ratio = newSize / template.Size

	zone.Size = newSize
	for _, d in ipairs(zone:GetDescendants()) do
		if d:IsA("Attachment") then
			d.Position = d.Position * ratio
		end
	end

	-- Seulement le LACET de la haie : si elle est legerement inclinee, la zone doit rester a plat au sol.
	local _, yaw = hedge.CFrame:ToEulerAnglesYXZ()
	local groundY = hedge.Position.Y - hedge.Size.Y * 0.5 + HedgeConfigs.ZONE_THICKNESS * 0.5 + HedgeConfigs.ZONE_LIFT
	zone.CFrame = CFrame.new(hedge.Position.X, groundY, hedge.Position.Z) * CFrame.Angles(0, yaw, 0)

	zone.Anchored = true
	zone.CanCollide = false
	-- CanQuery fonctionne ici : la dalle n'a pas de collision. Sans ca elle serait touchee par la detection et
	-- par le curseur, qui se poserait dessus au lieu de la haie.
	zone.CanQuery = false
	zone.CanTouch = false
	zone.CastShadow = false
	zone.Parent = getZoneFolder()

	zones[hedge] = zone
	hedge.Destroying:Once(function()
		zones[hedge] = nil
		zone:Destroy()
	end)
end

-- Pose le tag sur une part si son nom annonce une haie. Le tag reste la source de verite du jeu ; cette
-- fonction ne fait que le remplir pour ne pas avoir a le faire a la main sur chaque haie posee dans Studio.
local function autoTag(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	if instance.Name:sub(1, #HedgeConfigs.AUTO_TAG_PREFIX) ~= HedgeConfigs.AUTO_TAG_PREFIX then
		return
	end
	-- HasTag avant AddTag : reposer un tag existant declencherait GetInstanceAddedSignal pour rien.
	if not CollectionService:HasTag(instance, HedgeConfigs.TAG) then
		CollectionService:AddTag(instance, HedgeConfigs.TAG)
	end
	-- Marque lisible par le CLIENT, qui en a besoin pour savoir si son curseur est sur une haie. Un attribut
	-- se replique de facon certaine ; on ne parie pas sur la replication du tag.
	instance:SetAttribute(HedgeConfigs.HEDGE_MARK_ATTRIBUTE, true)
	ensureBuffer(instance)
	ensureZone(instance)
end

-- Balaye le dossier des cartes et suit ce qui s'y ajoute ensuite. On ne surveille QUE ce dossier : brancher
-- Workspace.DescendantAdded ferait passer chaque part de personnage, chaque outil clone et chaque debris par
-- le test de nom, des centaines de fois pour rien.
local function setupAutoTag(): number
	local root: Instance = workspace
	for _, name in ipairs(HedgeConfigs.AUTO_TAG_ROOT) do
		local child = root:FindFirstChild(name)
		if not child then
			warn(`[HedgeService] Dossier introuvable : Workspace.{table.concat(HedgeConfigs.AUTO_TAG_ROOT, ".")}`)
			return 0
		end
		root = child
	end

	local tagged = 0
	for _, descendant in ipairs(root:GetDescendants()) do
		autoTag(descendant)
		if CollectionService:HasTag(descendant, HedgeConfigs.TAG) then
			tagged += 1
		end
	end

	-- Les haies posees APRES le demarrage (Rojo qui synchronise, copie dans Studio) sont taguees a leur tour.
	root.DescendantAdded:Connect(autoTag)

	return tagged
end

function HedgeService.init()
	-- UNE boucle pour tous les joueurs. Le cout tient au nombre de haies taguees, pas au nombre de scripts.
	RunService.Heartbeat:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			updatePlayer(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		atHedge[player] = nil
		exitUntil[player] = nil
		faceChangedAt[player] = nil
	end)

	local tagged = setupAutoTag()
	if tagged == 0 then
		-- Anormal ET actionnable : sans une seule haie taguee, rien ne se declenchera jamais et on chercherait
		-- l'erreur dans le code.
		warn(
			`[HedgeService] Aucune haie trouvee. Attendu : des parts nommees "{HedgeConfigs.AUTO_TAG_PREFIX}..." `
				.. `dans Workspace.{table.concat(HedgeConfigs.AUTO_TAG_ROOT, ".")}, ou taguees "{HedgeConfigs.TAG}".`
		)
	else
		print(`[HedgeService] {tagged} haie(s) prete(s).`)
	end
end

return HedgeService
