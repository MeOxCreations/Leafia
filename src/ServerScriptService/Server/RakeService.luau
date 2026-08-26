--!strict
-- LE RATEAU. Il ramasse les petits tas de feuilles laisses au sol par la taille et les rassemble en GROS tas.
--
-- POURQUOI UN SERVICE A PART DE HedgeStockService : celui-la POSE les tas (c'est le dechet de la taille), celui-ci
-- les RAMASSE (c'est le nettoyage). Deux moments du cycle, deux fichiers -- l'entete de HedgeStockService l'avait
-- deja prevu. Le gros tas, lui, n'appartient plus a aucune haie : il vit dans son propre dossier, parce qu'il ira
-- un jour dans la Bin.
--
-- POURQUOI COTE SERVEUR : les tas sont des objets du MONDE, poses par le serveur et repliques a tous. Si le client
-- les ramassait, chaque joueur verrait une pelouse differente et le co-op serait faux des la premiere haie.
--
-- LE GESTE : le clic joue l'animation, et c'est un MARQUEUR dedans (SWEEP_EVENT) qui declenche le ramassage --
-- l'instant ou les dents touchent le sol. Jamais un delai : un delai se decale des qu'on retouche l'animation.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)
local RakeConfigs = require(ReplicatedStorage.Modules.Configs.RakeConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local ToolService = require(script.Parent.ToolService)

local RakeService = {}

-- Un petit tas EN TRAIN d'etre tire vers son gros tas. On garde le depart et l'arrivee plutot que de recalculer :
-- la cible peut grossir pendant le trajet, le point d'arrivee, lui, ne doit pas bouger.
type Pull = {
	pile: Model,
	from: CFrame,
	to: CFrame,
	target: Model, -- le gros tas qui l'avale a l'arrivee
	started: number,
}

local UP = Vector3.new(0, 1, 0)
-- Nom du modele de petit tas : DERNIER element du chemin d'asset, pas une chaine recopiee. Une deuxieme verite
-- finirait par mentir le jour ou HedgeStockService changerait d'asset.
local SMALL_NAME = HedgeConfigs.STOCK_DEBRIS_ASSET[#HedgeConfigs.STOCK_DEBRIS_ASSET]

local lastSweep: { [Player]: number } = {}
local pulls: { Pull } = {}
local pullConn: RBXScriptConnection? = nil
-- Marqueurs branches sur les pistes EN COURS, par joueur. Les pistes sortent du cache de ToolService (toujours le
-- meme objet), donc sans ce nettoyage on empilerait une connexion par coup de rateau, pour toujours.
--
-- UNE LISTE ET NON UNE SEULE : le marqueur de coup (SWEEP_EVENT) peut avoir ete pose dans l'animation du JOUEUR ou dans
-- celle de l'OUTIL. On ecoute les deux et on garde le premier qui parle (voir le garde dans onSweepRequest) :
-- ca coute deux connexions et ca supprime la question -- sinon la feature ne marche que si le marqueur est du
-- bon cote, et un marqueur du mauvais cote ne produit AUCUNE erreur, juste un rateau qui ne ramasse rien.
local markerConns: { [Player]: { RBXScriptConnection } } = {}
local pileFolder: Folder? = nil
-- Le dossier de sons existe-t-il ? Resolu UNE fois au boot, pas a chaque coup : voir playSweepSound.
local soundReady = false

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getPileFolder(): Folder
	local existing = pileFolder
	if existing and existing.Parent then
		return existing
	end
	local found = workspace:FindFirstChild(RakeConfigs.PILE_FOLDER)
	if found and found:IsA("Folder") then
		pileFolder = found
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = RakeConfigs.PILE_FOLDER
	folder.Parent = workspace
	pileFolder = folder
	return folder
end

-- Taille d'un gros tas selon ce qu'il a avale. En RACINE et non lineaire : la surface a l'ecran croit comme le
-- carre de l'echelle, donc une croissance lineaire donne des premiers coups invisibles puis une montagne.
local function scaleForCount(count: number): number
	local raw = RakeConfigs.SCALE_BASE + RakeConfigs.SCALE_PER_PILE * math.sqrt(math.max(count - 1, 0))
	return math.min(raw, RakeConfigs.SCALE_MAX)
end

-- Tous les petits tas du monde. On balaie le dossier de HedgeStockService, qui est le seul a en poser.
--
-- On PREVIENT si le dossier n'existe pas : sans ca, un rateau qui ne ramasse rien ressemble a un rateau casse,
-- alors que c'est simplement qu'aucune haie n'a encore ete taillee -- ou que le service n'est pas branche.
local function smallPiles(): { Model }
	local folder = workspace:FindFirstChild(HedgeConfigs.STOCK_FOLDER)
	local list: { Model } = {}
	if not folder then
		return list
	end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("Model") and d.Name == SMALL_NAME then
			table.insert(list, d)
		end
	end
	return list
end

-- Distance HORIZONTALE a la BOITE d'une haie, et direction SORTANTE vers le point. Y ignore : une haie est un mur.
--
-- QUATRIEME copie de ce calcul dans le projet (HedgeService, HedgeCellService, LadderMoveController, ici). Il
-- meriterait un HedgeGeomUtils partage -- a faire quand on y retouchera, pas au milieu d'une feature.
local function hedgeBoxDistance(hedge: BasePart, position: Vector3): (number, Vector3)
	local localP = hedge.CFrame:PointToObjectSpace(position)
	local half = hedge.Size * 0.5
	local dx = localP.X - math.clamp(localP.X, -half.X, half.X)
	local dz = localP.Z - math.clamp(localP.Z, -half.Z, half.Z)
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < 1e-4 then
		-- DANS la boite : aucune direction radiale definie. On sort par la face la plus proche.
		local outX = math.abs(localP.X) - half.X
		local outZ = math.abs(localP.Z) - half.Z
		local localN = if outX >= outZ
			then Vector3.new(if localP.X >= 0 then 1 else -1, 0, 0)
			else Vector3.new(0, 0, if localP.Z >= 0 then 1 else -1)
		return 0, hedge.CFrame:VectorToWorldSpace(localN)
	end
	return dist, hedge.CFrame:VectorToWorldSpace(Vector3.new(dx / dist, 0, dz / dist))
end

-- ECARTE LE POINT DE RASSEMBLEMENT DE LA BANDE OU TOMBENT LES PETITS TAS.
--
-- Le gros tas ne doit pas se former au milieu d'eux : on ne distinguerait plus ce qui est ramasse de ce qui
-- reste, et c'est justement ce que le joueur vient lire au sol.
--
-- Il etait AVANT pousse bien plus loin (au-dela de l'aimant de haie) parce qu'il devenait sinon inatteignable.
-- Ce n'est plus necessaire : l'aimant ne s'active que pour un outil de taille (ToolConfigs.cutsHedge).
--
-- La bande des petits tas s'arrete a STOCK_GAP + STOCK_WIDTH de la haie -- valeurs LUES dans HedgeConfigs, pas
-- recopiees : si la bande s'elargit, le gros tas recule tout seul.
local function pushOutOfHedgeZone(spot: Vector3): Vector3
	local clearance = HedgeConfigs.STOCK_GAP + HedgeConfigs.STOCK_WIDTH + RakeConfigs.HEDGE_CLEARANCE_MARGIN
	-- Haie la plus proche par distance a la BOITE, pas au centre : un petit buisson dont le centre est proche
	-- battrait la longue haie qu'on longe, et on pousserait le tas dans la mauvaise direction.
	local best: BasePart? = nil
	local bestDist = math.huge
	local bestNormal = Vector3.zero
	for _, inst in ipairs(CollectionService:GetTagged(HedgeConfigs.TAG)) do
		if inst:IsA("BasePart") then
			local dist, normal = hedgeBoxDistance(inst, spot)
			if dist < bestDist then
				best = inst
				bestDist = dist
				bestNormal = normal
			end
		end
	end
	if not best or bestDist >= clearance or bestNormal.Magnitude < 1e-3 then
		return spot -- deja assez loin, ou aucune haie : rien a pousser
	end
	-- On pousse le long de la normale SORTANTE : le tas s'ecarte de la haie par le cote ou il se trouve deja,
	-- donc il ne traverse jamais la haie pour aller se poser de l'autre cote.
	return spot + bestNormal * (clearance - bestDist)
end

-- Gros tas deja pose assez pres du point de rassemblement, ou nil. Sans cette fusion, chaque coup ferait son
-- propre tas et on obtiendrait une TRAINEE de petits tas au lieu d'un gros.
local function nearbyBigPile(position: Vector3): Model?
	local folder = getPileFolder()
	local best: Model? = nil
	local bestDist = RakeConfigs.MERGE_RADIUS
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") and child.Name == RakeConfigs.PILE_NAME then
			local flat = (child:GetPivot().Position - position) * Vector3.new(1, 0, 1)
			local dist = flat.Magnitude
			if dist <= bestDist then
				best = child
				bestDist = dist
			end
		end
	end
	return best
end

-- Fait grossir un gros tas d'un cran. Le grossissement est TWEENE et cale sur l'arrivee du petit tas : celui-ci
-- disparait pendant que celui-la grandit, donc la matiere a l'air de passer de l'un a l'autre.
local function growPile(pile: Model)
	local raw = pile:GetAttribute(RakeConfigs.PILE_COUNT_ATTRIBUTE)
	local count = (if typeof(raw) == "number" then raw else 0) + 1
	pile:SetAttribute(RakeConfigs.PILE_COUNT_ATTRIBUTE, count)

	local from = pile:GetScale()
	local to = scaleForCount(count)
	if to <= from + 1e-3 then
		return -- deja au plafond : rien a animer
	end
	-- Model:ScaleTo n'est pas une propriete, donc TweenService ne peut pas le tweener directement. On anime une
	-- valeur et on la reporte : un NumberValue est ce que Roblox sait tweener de plus simple.
	local driver = Instance.new("NumberValue")
	driver.Value = from
	local conn = driver.Changed:Connect(function(value: number)
		if pile.Parent then
			pile:ScaleTo(value)
		end
	end)
	local tween = TweenService:Create(driver, TweenInfo.new(RakeConfigs.GROW_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Value = to,
	})
	tween.Completed:Connect(function()
		conn:Disconnect()
		driver:Destroy()
	end)
	tween:Play()
end

-- Cree un gros tas au point donne, a partir du MEME modele que les petits : c'est le seul asset de feuilles au
-- sol qui existe, et un tas de feuilles reste un tas de feuilles, en plus gros.
local function makeBigPile(template: Model, cframe: CFrame): Model
	local pile = template:Clone()
	pile.Name = RakeConfigs.PILE_NAME
	pile:SetAttribute(RakeConfigs.PILE_COUNT_ATTRIBUTE, 0)
	for _, d in ipairs(pile:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			-- CanQuery n'a d'effet que parce que CanCollide est deja faux (deja au journal). Sans ca, le tas
			-- serait vu par le lancer du curseur de taille, qui viserait le tas au lieu de la haie.
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	pile:ScaleTo(scaleForCount(0))
	pile:PivotTo(cframe)
	pile.Parent = getPileFolder()
	return pile
end

-- Boucle de trajet des petits tas. Branchee SEULEMENT quand il y a quelque chose a tirer, et coupee des que la
-- liste est vide : une boucle qui tourne dans le vide sur le serveur coute a tout le monde.
local function stepPulls()
	local now = os.clock()
	for i = #pulls, 1, -1 do
		local pull = pulls[i]
		if not (pull.pile.Parent and pull.target.Parent) then
			-- La cible ou le tas a disparu (haie detruite, streaming) : on abandonne proprement.
			if pull.pile.Parent then
				pull.pile:Destroy()
			end
			table.remove(pulls, i)
		else
			local ratio = math.clamp((now - pull.started) / RakeConfigs.PULL_TIME, 0, 1)
			-- ARC : sin(pi * t) vaut zero aux deux bouts et 1 au milieu. Le tas decolle et se repose, il ne
			-- traverse pas le sol et n'atterrit pas en l'air.
			local lift = math.sin(ratio * math.pi) * RakeConfigs.PULL_ARC
			local spin = ratio * RakeConfigs.PULL_SPIN * math.pi * 2
			local base = pull.from:Lerp(pull.to, ratio)
			pull.pile:PivotTo(base * CFrame.new(0, lift, 0) * CFrame.Angles(0, spin, 0))
			if ratio >= 1 then
				-- ARRIVE : le petit disparait et le gros grossit, dans la meme image.
				pull.pile:Destroy()
				growPile(pull.target)
				table.remove(pulls, i)
			end
		end
	end

	if #pulls == 0 and pullConn then
		pullConn:Disconnect()
		pullConn = nil
	end
end

-- Son du coup de rateau, SPATIALISE (parente au joueur, donc les autres l'entendent d'ou il est).
--
-- Garde par `soundReady`, resolu une seule fois au boot : SoundUtils warn quand il ne trouve pas, et un warn par
-- coup de rateau noierait la console. Un son absent est NORMAL tant qu'il n'a pas ete importe, ce n'est pas une
-- panne -- on le dit une fois au demarrage et on se tait ensuite.
local function playSweepSound(host: BasePart)
	if not soundReady then
		return
	end
	local path = table.clone(RakeConfigs.SOUND_FOLDER)
	table.insert(path, RakeConfigs.SWEEP_SOUND)
	SoundUtils.play(path, host)
end

local function startPull(pile: Model, target: Model, to: CFrame)
	table.insert(pulls, {
		pile = pile,
		from = pile:GetPivot(),
		to = to,
		target = target,
		started = os.clock(),
	})
	if not pullConn then
		pullConn = RunService.Heartbeat:Connect(stepPulls)
	end
end

-- LE COUP DE RATEAU. Appele par le MARQUEUR de l'animation, pas par le clic : le ramassage doit tomber au moment
-- ou les dents touchent le sol.
local function sweep(player: Player)
	local root = getRoot(player)
	if not root then
		return
	end

	local origin = root.Position
	local look = root.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 1e-3 then
		return
	end
	forward = forward.Unit
	local right = forward:Cross(UP)

	-- LES PLUS PROCHES D'ABORD. Un rateau ramene ce qu'il a sous les dents, pas ce qu'il y a au fond.
	local found: { { pile: Model, dist: number } } = {}
	for _, pile in ipairs(smallPiles()) do
		local delta = pile:GetPivot().Position - origin
		if math.abs(delta.Y) <= RakeConfigs.MAX_HEIGHT then
			-- BANDE et non cone : on mesure separement l'avance et l'ecart lateral, donc la largeur attrapee
			-- reste la meme de pres comme de loin. Un cone attraperait tout autour des pieds du joueur.
			local ahead = delta:Dot(forward)
			local side = math.abs(delta:Dot(right))
			if ahead > 0 and ahead <= RakeConfigs.RANGE and side <= RakeConfigs.HALF_WIDTH then
				table.insert(found, { pile = pile, dist = ahead })
			end
		end
	end
	if #found == 0 then
		return
	end
	table.sort(found, function(a, b)
		return a.dist < b.dist
	end)

	-- POINT DE RASSEMBLEMENT : devant le joueur, entre lui et ce qu'il vient de ratisser. Le sol est CHERCHE par
	-- un rayon et non devine a partir du HRP : sur une pente ou un talus, une hauteur deduite du joueur poserait
	-- le tas en l'air ou l'enfoncerait.
	local spot = origin + forward * RakeConfigs.GATHER_FORWARD
	-- HORS DE LA ZONE D'AIMANT : sinon le tas se forme la ou on travaille, et revenir le chercher rattrape le
	-- joueur dans la haie. Fait AVANT le rayon de sol : la hauteur se mesure a l'endroit definitif.
	spot = pushOutOfHedgeZone(spot)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter: { Instance } = { getPileFolder() }
	local character = player.Character
	if character then
		table.insert(filter, character)
	end
	local stocks = workspace:FindFirstChild(HedgeConfigs.STOCK_FOLDER)
	if stocks then
		table.insert(filter, stocks)
	end
	params.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(spot + UP * 6, UP * -30, params)
	local groundY = if hit then hit.Position.Y else origin.Y - root.Size.Y * 0.5
	local gather = CFrame.new(spot.X, groundY + RakeConfigs.GATHER_LIFT, spot.Z)

	-- DESTINATION DU GLISSEMENT : la position REELLE du tas qui avale, jamais le point qu'on vient de calculer.
	--
	-- Les deux different des qu'on rejoint un tas existant : nearbyBigPile accepte jusqu'a MERGE_RADIUS studs
	-- d'ecart, donc les petits tas volaient vers un point pouvant etre a 5 studs a cote du gros, y disparaissaient,
	-- et le gros grossissait ailleurs. Ca se lit exactement comme "le tween ne va pas jusqu'au bout" -- alors que
	-- l'interpolation etait juste, c'est la CIBLE qui etait fausse.
	local target = nearbyBigPile(gather.Position)
	local destination = gather
	if target then
		destination = target:GetPivot()
	else
		-- On clone le PREMIER petit tas attrape plutot que de re-resoudre l'asset : il a deja le bon modele, la
		-- bonne couleur et le bon materiau, et ca evite une deuxieme facon de fabriquer la meme chose.
		target = makeBigPile(found[1].pile, gather)
	end
	local pile = target :: Model

	local taken = math.min(#found, RakeConfigs.MAX_PER_SWEEP)
	for index = 1, taken do
		startPull(found[index].pile, pile, destination)
	end

	playSweepSound(root)
end

-- UN CLIC. On joue le geste, et on branche le marqueur qui fera le ramassage a mi-animation.
local function onSweepRequest(player: Player)
	local held = ToolService.getHeld(player)
	-- LE CLIENT MENT TOUJOURS : c'est le serveur qui sait ce que le joueur tient, pas le message recu.
	if not (held and held.toolName == RakeConfigs.TOOL_NAME) then
		return
	end
	local now = os.clock()
	if now - (lastSweep[player] or 0) < RakeConfigs.COOLDOWN then
		return
	end
	lastSweep[player] = now

	local track = ToolService.getTrack(player, RakeConfigs.SWEEP_ANIM)
	if not track then
		warn(`[RakeService] Animation introuvable : Rateau/{RakeConfigs.SWEEP_ANIM}`)
		return
	end

	-- On coupe les abonnements du coup PRECEDENT. Les pistes viennent d'un cache : ce sont toujours les memes
	-- objets, donc sans ce nettoyage on empilerait un abonnement par coup de rateau, chacun ramassant a son tour.
	for _, conn in ipairs(markerConns[player] or {}) do
		conn:Disconnect()
	end
	local conns: { RBXScriptConnection } = {}
	markerConns[player] = conns

	-- UN SEUL ramassage par coup, meme si les DEUX animations portent le marqueur. On ne cherche pas a savoir
	-- laquelle l'a : la premiere qui parle gagne, l'autre est sans effet.
	local done = false
	local function onMarker()
		if done then
			return
		end
		done = true
		sweep(player)
	end

	table.insert(conns, track:GetMarkerReachedSignal(RakeConfigs.SWEEP_EVENT):Connect(onMarker))

	-- ON S'ABONNE AVANT DE JOUER, y compris cote outil. Un marqueur passe ne se rattrape pas : s'abonner apres
	-- Play, c'est rater tout marqueur place tot dans l'animation.
	--
	-- La piste d'outil n'existe QUE si le modele du rateau a un Animator. Sans lui elle est nil, donc si le
	-- marqueur est dans l'animation de l'OUTIL, personne ne l'ecoute -- et ca ne ressemble pas a un Animator
	-- manquant, ca ressemble a un marqueur manquant. D'ou le detail dans le filet plus bas.
	local toolTrack = held.toolTracks[RakeConfigs.TOOL_ANIM]
	if toolTrack then
		table.insert(conns, toolTrack:GetMarkerReachedSignal(RakeConfigs.SWEEP_EVENT):Connect(onMarker))
	end

	-- Geste PONCTUEL : on force Looped a false cote code. Le reglage de l'editeur n'est qu'une suggestion, et une
	-- piste bouclee par erreur reste a plein poids POUR TOUJOURS et pollue tout ce qui partage sa priorite.
	track.Looped = false
	-- Action2 : au-dessus de la pose de maintien (Action), sinon les deux se MELANGENT au lieu de se remplacer --
	-- a priorite egale Roblox fait une moyenne, il ne choisit pas.
	track.Priority = Enum.AnimationPriority.Action2
	track:Play(0.1)

	-- Le modele de l'outil joue son propre geste en meme temps, sur SON animator. Silencieux s'il n'en a pas :
	-- ToolService previent deja a l'equipement, inutile de crier a chaque clic.
	ToolService.playToolAnimationOnce(player, RakeConfigs.TOOL_ANIM)

	-- FILET DE SECURITE : si le marqueur ne passe pas, le rateau ne ramasserait jamais rien, sans la moindre
	-- erreur -- le genre de panne muette qui envoie chercher le bug dans la detection.
	--
	-- DECLENCHE A LA FIN REELLE DU GESTE, pas sur une duree calculee. `track.Length` vaut ZERO tant que l'asset
	-- n'est pas telecharge : un task.delay base dessus tirait au bout d'une fraction de seconde, AVANT que le
	-- marqueur ait eu la moindre chance de passer, et accusait l'animation d'un defaut qu'elle n'avait pas.
	-- On demande donc a la SOURCE quand le geste se termine.
	local stopConn: RBXScriptConnection? = nil
	local function bail(reason: string)
		if stopConn then
			stopConn:Disconnect()
			stopConn = nil
		end
		-- Le coup a pu aboutir, ou etre remplace par un coup plus recent : dans les deux cas on ne dit rien.
		if done or markerConns[player] ~= conns then
			return
		end
		-- ON DIT CE QU'ON A REELLEMENT ECOUTE. "Absent des deux animations" etait faux quand la piste de l'outil
		-- n'existait meme pas : un diagnostic qui nomme le mauvais coupable coute plus cher que pas de
		-- diagnostic du tout, il envoie travailler avec confiance dans la mauvaise direction.
		local toolState = if toolTrack
			then `ecoutee (duree {string.format("%.2f", toolTrack.Length)}s)`
			else "PAS CHARGEE -- le modele du rateau n'a pas d'Animator, donc son animation n'est ni jouee ni ecoutee"
		warn(
			`[RakeService] Marqueur "{RakeConfigs.SWEEP_EVENT}" jamais atteint ({reason}). Ramassage a la fin du geste.`
				.. `\n  piste joueur ({RakeConfigs.SWEEP_ANIM}) : ecoutee (duree {string.format("%.2f", track.Length)}s)`
				.. `\n  piste outil  ({RakeConfigs.TOOL_ANIM}) : {toolState}`
				.. `\n  Si les durees sont a 0.00, l'animation n'est pas chargee : ce n'est pas le marqueur, c'est l'asset.`
				.. `\n  Si la duree est bonne, le marqueur n'est pas dans l'asset PUBLIE : republier l'animation apres l'avoir ajoute.`
		)
		onMarker()
	end

	stopConn = track.Stopped:Connect(function()
		bail("la piste du joueur est allee au bout")
	end)
	-- Deuxieme filet : si la piste ne PART jamais (asset qui n'a pas pu se charger), Stopped ne tire pas non plus
	-- et on resterait bloque en silence. Large expres, il ne doit gagner que quand le premier est mort.
	task.delay(4, function()
		bail("aucune piste n'a rendu la main en 4s")
	end)
end

function RakeService.init()
	local remote = RemoteSetup.getRemote("RakeSweep", "Rake")
	if not (remote and remote:IsA("RemoteEvent")) then
		warn("[RakeService] Remote Rake/RakeSweep introuvable : le rateau ne ramassera rien")
		return
	end
	remote.OnServerEvent:Connect(onSweepRequest)

	-- Celui qui cree est celui qui nettoie. Un joueur qui part laisse sinon sa connexion de marqueur et son
	-- entree d'anti-spam derriere lui, pour la duree du serveur.
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, conn in ipairs(markerConns[player] or {}) do
			conn:Disconnect()
		end
		markerConns[player] = nil
		lastSweep[player] = nil
	end)

	-- Le son est OPTIONNEL : un dossier absent ne doit pas ressembler a une panne. On le dit une fois au boot,
	-- pas a chaque coup de rateau (voir playSweepSound).
	local folder: Instance? = SoundService
	for _, name in ipairs(RakeConfigs.SOUND_FOLDER) do
		folder = folder and folder:FindFirstChild(name)
	end
	soundReady = folder ~= nil and folder:FindFirstChild(RakeConfigs.SWEEP_SOUND) ~= nil
	if not soundReady then
		print(`[RakeService] Pas de son de rateau (SoundService.{table.concat(RakeConfigs.SOUND_FOLDER, ".")}.{RakeConfigs.SWEEP_SOUND}) : le reste marche`)
	end

	print("[RakeService] Rateau pret")
end

return RakeService
