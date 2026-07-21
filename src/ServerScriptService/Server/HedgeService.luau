--!strict
-- Detecte quand un joueur se presente devant une haie et quand il s'en ecarte.
--
-- COUCHE 1, volontairement minimale : reperer la haie, reperer la FACE, ralentir le joueur. Pas encore
-- d'orientation forcee, pas de champ de force, pas de camera. Ils viendront dessus une fois celle-ci validee.
--
-- Ce service ne touche JAMAIS a WalkSpeed : il declare une intention a CharacterService, qui possede la
-- vitesse. Deux modules qui ecrivent la meme propriete finissent toujours par se battre.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)
local CharacterService = require(script.Parent.CharacterService)

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

-- Normale CARDINALE de la face touchee, deduite de la position du point d'impact dans le repere de la haie.
--
-- On n'utilise PAS la normale brute du raycast : sur un MeshPart elle vient du triangle touche, donc elle part
-- dans tous les sens sur une surface irreguliere comme une haie. Pour orienter le joueur et la camera il faut
-- une direction propre, un des quatre cotes, pas l'angle d'une feuille.
local function faceNormal(hedge: BasePart, hitPosition: Vector3): Vector3
	-- Dans le repere de la haie, une haie tournee de 37 degres se traite comme une haie droite.
	local localPos = hedge.CFrame:PointToObjectSpace(hitPosition)
	local half = hedge.Size * 0.5

	local best = FACE_AXES[1]
	local bestGap = math.huge

	for _, face in ipairs(FACE_AXES) do
		local along = if face.axis == "X" then localPos.X else localPos.Z
		local halfAlong = if face.axis == "X" then half.X else half.Z
		-- Ecart entre le point d'impact et le plan de cette face. Le plus petit gagne : c'est la face sur
		-- laquelle on a tape.
		local gap = math.abs(along - halfAlong * face.sign)
		if gap < bestGap then
			bestGap = gap
			best = face
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
local function castForward(character: Model, root: BasePart, length: number): Contact?
	local origin = root.Position
	-- LookVector du HumanoidRootPart : il ne s'incline jamais, le volume reste donc horizontal meme en pente.
	local direction = root.CFrame.LookVector

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Sans ca le volume taperait dans le personnage lui-meme et dans l'outil qu'il tient, a zero stud.
	params.FilterDescendantsInstances = { character }

	local size = Vector3.new(HedgeConfigs.DETECT_WIDTH, HedgeConfigs.DETECT_HEIGHT, HedgeConfigs.DETECT_THICKNESS)
	-- La boite part orientee comme le regard : sa profondeur suit la direction du lancer.
	local start = CFrame.lookAt(origin, origin + direction)

	local result = workspace:Blockcast(start, size, direction * length, params)
	if not result then
		return nil
	end

	local hit = result.Instance
	if not (hit and CollectionService:HasTag(hit, HedgeConfigs.TAG)) then
		-- Quelque chose bloque le passage sans etre une haie : mur, decor, autre joueur.
		return nil
	end

	local contact: Contact = {
		hedge = hit,
		normal = faceNormal(hit, result.Position),
		distance = result.Distance,
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

	local current = atHedge[player]
	-- Deja au travail : on cherche plus loin avant de lacher. Sinon on cherche plus court avant d'accrocher.
	local length = if current then HedgeConfigs.RAY_LENGTH_ENGAGED else HedgeConfigs.RAY_LENGTH
	local contact = castForward(character, root, length)

	if not contact then
		leaveHedge(player)
		return
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
