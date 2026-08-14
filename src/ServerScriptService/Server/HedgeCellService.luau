--!strict
-- Pave la surface taillable des haies avec une grille de carreaux.
--
-- PRE-SYSTEME. Les carreaux ne font que se poser : rien ne les taille encore. Le but de cette etape est de
-- repondre a UNE question avant de dessiner le moindre pixel de feuille : combien ca coute ?
-- Baseline a comparer : 4.71 ms en moyenne dans Studio, mesuree avant tout gameplay.
--
-- Chaque carreau retiendra plus tard son epaisseur, et tailler la fera descendre. C'est ce contraste
-- avant / apres qui devra donner envie d'en tailler une deuxieme, pas la finesse de la grille.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)

local HedgeCellService = {}

-- Axes LOCAUX de chaque face. `up` est l'axe qu'on garde vertical dans la grille ; le troisieme se deduit.
-- Le dessus n'a pas de "haut" naturel, on lui donne Z.
local FACES: { [string]: { normal: Vector3, up: Vector3 } } = {
	["Z+"] = { normal = Vector3.new(0, 0, 1), up = Vector3.yAxis },
	["Z-"] = { normal = Vector3.new(0, 0, -1), up = Vector3.yAxis },
	["X+"] = { normal = Vector3.new(1, 0, 0), up = Vector3.yAxis },
	["X-"] = { normal = Vector3.new(-1, 0, 0), up = Vector3.yAxis },
	["Y+"] = { normal = Vector3.yAxis, up = Vector3.new(0, 0, 1) },
}

-- Carreaux poses par haie, pour pouvoir tout reprendre si la haie disparait.
local cells: { [BasePart]: Folder } = {}
local cellFolder: Folder? = nil

-- GRILLE DE RANGEMENT. Les carreaux d'une haie ranges par CASE, en repere local de la haie.
--
-- Sans elle, la coupe parcourt les ~970 carreaux d'une haie a chaque frame pour en trouver la dizaine qui est
-- sous la lame, et alloue en plus une table de 970 entrees a chaque appel de GetChildren(). Avec elle, elle ne
-- regarde que les cases autour de la lame.
--
-- EN REPERE LOCAL et non en monde : les carreaux ne bougent jamais par rapport a leur haie, la grille est donc
-- juste pour toujours, meme si la haie est deplacee. En monde, il faudrait la reconstruire a chaque
-- deplacement, et on oublierait de le faire.
local grids: { [BasePart]: { [number]: { BasePart } } } = {}
-- Nombre de carreaux par haie. Retenu ici pour que la coupe n'ait plus a demander GetChildren() juste pour
-- compter : c'est un nombre qui ne change pas, le recalculer soixante fois par seconde n'a aucun sens.
local counts: { [BasePart]: number } = {}

-- Trois indices de case en UN seul nombre, pour une seule recherche dans la table.
--
-- 1024 par axe, decale de 512 : ca couvre des indices de -512 a +511, soit des haies de 3000 studs a
-- CELL_BUCKET_SIZE = 3. Aucune haie n'approchera jamais ca.
local function bucketKey(x: number, y: number, z: number): number
	return (x + 512) * 1048576 + (y + 512) * 1024 + (z + 512)
end
-- Compte global, uniquement pour le garde-fou et le rapport de demarrage.
local total = 0

-- Modele de feuille, resolu UNE fois au demarrage. Le chercher a chaque carreau ferait des milliers de
-- parcours d'arborescence pour toujours trouver la meme chose.
local leafTemplate: BasePart? = nil

local function resolveLeaf(): BasePart?
	local source: Instance? = ReplicatedStorage
	for _, name in ipairs(HedgeConfigs.LEAF_ASSET) do
		source = source and source:FindFirstChild(name)
	end
	if not (source and source:IsA("BasePart")) then
		-- Anormal ET actionnable : sans feuilles, les haies restent des cubes verts et on se demande pourquoi.
		warn(`[HedgeCellService] Feuille introuvable : ReplicatedStorage.{table.concat(HedgeConfigs.LEAF_ASSET, ".")}`)
		return nil
	end

	local leaf = source:Clone()
	leaf.Name = "Leaf"
	leaf.Anchored = true
	leaf.Massless = true
	leaf.CanCollide = false
	leaf.CanQuery = false
	leaf.CanTouch = false
	leaf.CastShadow = false
	return leaf
end

local function getCellFolder(): Folder
	local existing = cellFolder
	if existing and existing.Parent then
		return existing
	end
	local found = workspace:FindFirstChild(HedgeConfigs.CELL_FOLDER)
	if found and found:IsA("Folder") then
		cellFolder = found
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = HedgeConfigs.CELL_FOLDER
	folder.Parent = workspace
	cellFolder = folder
	return folder
end

-- Demi-dimension de la haie le long d'un axe LOCAL quelconque. Somme des trois composantes en valeur absolue :
-- pour un axe cardinal, ca revient a prendre la bonne demi-taille, et ca reste juste pour un axe compose.
local function halfAlong(half: Vector3, axis: Vector3): number
	return math.abs(axis.X * half.X) + math.abs(axis.Y * half.Y) + math.abs(axis.Z * half.Z)
end

-- Pave UNE face. Rend le nombre de carreaux poses (rendus a l'ecran).
--
-- `cuttable` : si vrai, chaque carreau est aussi range dans `grid`, ce qui le rend atteignable par la coupe. Si
-- faux, les carreaux sont poses et RENDUS (feuilles comprises) mais absents de la grille : on les voit, on ne
-- peut pas les tailler. C'est ce qui laisse un dessus touffu sur une haie trop haute pour qu'on l'atteigne.
local function buildFace(
	hedge: BasePart,
	parent: Folder,
	faceName: string,
	grid: { [number]: { BasePart } },
	cuttable: boolean
): number
	local face = FACES[faceName]
	if not face then
		warn(`[HedgeCellService] Face inconnue : "{faceName}"`)
		return 0
	end

	local normal, up = face.normal, face.up
	-- Repere direct : right x up doit redonner normal, sinon les carreaux seraient retournes.
	local right = up:Cross(normal)

	local half = hedge.Size * 0.5
	local halfW = halfAlong(half, right)
	local halfH = halfAlong(half, up)
	local halfD = halfAlong(half, normal)
	if halfW <= 0 or halfH <= 0 then
		return 0
	end

	-- On DEDUIT la taille reelle du nombre de carreaux, au lieu de decouper a taille fixe et de laisser une
	-- bande incomplete au bord. Les carreaux pavent donc exactement la face, sans trou ni depassement, et leur
	-- cote s'ecarte au maximum de moitie de la valeur demandee.
	local width, height = halfW * 2, halfH * 2
	local columns = math.max(1, math.round(width / HedgeConfigs.CELL_SIZE))
	local rows = math.max(1, math.round(height / HedgeConfigs.CELL_SIZE))
	local cellW, cellH = width / columns, height / rows

	-- Le dessus n'a pas de rangee "au sol" : ses quatre bordures sont donc des aretes, contrairement aux cotes.
	local isTop = faceName == "Y+"
	local thickness = HedgeConfigs.CELL_THICKNESS
	-- Le carreau est POSE sur la surface, pas encastre : on sort d'une demi-epaisseur.
	local depth = halfD + thickness * 0.5
	-- LE DESSUS SEUL descend sous le plan du haut de la haie.
	--
	-- Une feuille couchee a plat se voit sur toute sa largeur ; une feuille verticale se voit par la tranche.
	-- A hauteur egale, le dessus parait donc bien plus haut que les cotes ne paraissent larges, et la haie
	-- porte un chapeau. Le descendre le remet a niveau.
	-- Ne touche QUE la face du dessus : appliquer ca aux cotes reduirait la haie dans toutes les directions.
	if isTop then
		depth -= HedgeConfigs.CELL_TOP_DROP
	end

	local template = Instance.new("Part")
	template.Size = Vector3.new(cellW, cellH, thickness)
	template.Color = HedgeConfigs.CELL_COLOR
	template.Material = HedgeConfigs.CELL_MATERIAL
	-- Le carreau est un REPERE, pas un decor : il tient une case de la grille et la position de sa feuille.
	-- Invisible, il n'est pas rendu du tout, donc il ne coute plus rien a l'ecran.
	template.Transparency = HedgeConfigs.CELL_TRANSPARENCY
	template.Anchored = true
	-- Rien de physique non plus : il ne bloque pas, ne se fait pas voir des lancers, ne declenche aucun Touched
	-- et ne pese pas. Il ne doit exister que pour le code.
	template.Massless = true
	template.CanCollide = false
	-- CanQuery ne prend effet que parce que CanCollide est deja faux. Sans ca les carreaux resteraient vus par
	-- les lancers, et ils sont juste devant la haie : plus rien ne serait jamais detecte.
	template.CanQuery = false
	template.CanTouch = false
	-- LE reglage le plus important a ce volume. Des milliers de carreaux qui projettent une ombre, c'est fini.
	template.CastShadow = false
	template.TopSurface = Enum.SurfaceType.Smooth
	template.BottomSurface = Enum.SurfaceType.Smooth

	-- Tirage SEME sur la position de la haie : le meme jardin se regenere a l'identique d'une session a
	-- l'autre. Un decor qui change de tete a chaque relance empeche de juger un reglage.
	local seed = math.floor(hedge.Position.X * 73 + hedge.Position.Y * 37 + hedge.Position.Z * 91)
	local rng = Random.new(seed)

	for column = 0, columns - 1 do
		for row = 0, rows - 1 do
			local offset = normal * depth
				+ right * (-halfW + (column + 0.5) * cellW)
				+ up * (-halfH + (row + 0.5) * cellH)

			local cell = template:Clone()
			cell.Name = `Cell_{faceName}_{column}_{row}`
			-- POUSSE PLEINE au depart. Portee par un attribut et non par une table : elle se replique toute
			-- seule, donc chaque client sait ou poser la feuille sans qu'on envoie quoi que ce soit.
			cell:SetAttribute(HedgeConfigs.GROWTH_ATTRIBUTE, 1)

			-- BORDURE. C'est ici, et seulement ici, qu'on connait la grille : plus tard il faudrait rededuire
			-- les rangees depuis un nom, ce qui casserait au premier renommage.
			--
			-- La rangee du BAS n'est une bordure que sur le dessus. Sur un cote elle touche le sol : y detruire
			-- les feuilles ouvrirait la haie par en dessous, alors qu'aucune silhouette ne passe par la.
			--
			-- TOUTES LES AUTRES BORDURES EFFACENT, y compris des deux cotes d'une meme arete. Essaye a un seul
			-- destructeur par arete : le coin du haut se refermait, mais les cotes gardaient alors des feuilles
			-- qui depassent et qu'aucun geste ne peut atteindre. Une saillie increvable est pire qu'une fente.
			-- La fente du haut se comble autrement, par le BISEAU un peu plus bas.
			local onEdge = column == 0
				or column == columns - 1
				or row == rows - 1
				or (isTop and row == 0)
			if onEdge then
				cell:SetAttribute(HedgeConfigs.EDGE_ATTRIBUTE, true)
			end
			-- Rangee du SOL d'un COTE : pas une bordure (on ne detruit pas ses feuilles), mais dure a atteindre
			-- car la pose la plus basse des bras arrive au-dessus. On la marque pour lui donner une portee bonus a
			-- la coupe, sinon une frange de feuillus reste au ras du sol.
			if not isTop and row == 0 then
				cell:SetAttribute(HedgeConfigs.BASE_ATTRIBUTE, true)
			end
			-- Construit dans le repere de la HAIE puis ramene en monde : une haie tournee se traite donc comme
			-- une haie droite, sans un seul cas particulier.
			local placement = CFrame.fromMatrix(offset, right, up, normal)

			-- BISEAU. Les carreaux du BORD du dessus sont bascules vers l'exterieur.
			--
			-- Une vraie haie n'a pas d'arete vive, elle est cassee. Et surtout : deux surfaces perpendiculaires
			-- laissent forcement une fente des que chacune s'enfonce dans SA direction en etant taillee. Le
			-- dessus descend, le cote rentre, et le coin recule deux fois.
			-- Plutot que d'essayer de faire se toucher deux plans qui s'ecartent, on en met un TROISIEME entre
			-- les deux. Sa feuille bouche le vide, et elle reste taillable puisque sa normale regarde a
			-- mi-chemin : la lame l'atteint aussi bien par le dessus que par le cote.
			if isTop and HedgeConfigs.CELL_BEVEL_ANGLE > 0 then
				local outColumn = if column == 0 then -1 elseif column == columns - 1 then 1 else 0
				local outRow = if row == 0 then -1 elseif row == rows - 1 then 1 else 0
				if outColumn ~= 0 or outRow ~= 0 then
					-- Direction du bord, dans le plan du carreau. Un carreau de COIN appartient a DEUX bords :
					-- la somme des deux donne la diagonale, donc le biseau tourne le coin tout seul.
					local out = Vector2.new(outColumn, outRow).Unit
					-- Axe de bascule : perpendiculaire a cette direction et a la normale. Ecrit dans le repere
					-- du carreau, ou la normale est Z et le bord est dans le plan XY.
					placement *= CFrame.fromAxisAngle(
						Vector3.new(-out.Y, out.X, 0),
						math.rad(HedgeConfigs.CELL_BEVEL_ANGLE)
					)
				end
			end

			cell.CFrame = hedge.CFrame * placement

			local source = leafTemplate
			if source then
				local leaf = source:Clone()

				-- TAILLE. La feuille epouse le carreau puis s'en ecarte au hasard. Elle garde SA propre
				-- epaisseur : l'etirer dans l'axe de la normale l'aplatirait ou la gonflerait sans raison.
				local scale = HedgeConfigs.LEAF_SCALE
					* rng:NextNumber(HedgeConfigs.LEAF_SCALE_MIN, HedgeConfigs.LEAF_SCALE_MAX)
				leaf.Size = Vector3.new(cellW * scale, cellH * scale, source.Size.Z)

				-- DESORDRE. Le repere du carreau a son axe Z vers l'EXTERIEUR : tourner autour de Z fait pivoter
				-- la feuille DANS le plan de la face, tourner autour de X et Y la fait decoller.
				local spin = math.rad(HedgeConfigs.LEAF_SPIN) * rng:NextNumber(-1, 1)
				-- Le dessus a son propre basculement : plaque comme les cotes, il se lit comme un tapis. Redresse,
				-- il reprend du volume sans le risque des cotes, ou une feuille qui decolle ouvre sur l'interieur.
				local tilt = math.rad(if isTop then HedgeConfigs.LEAF_TILT_TOP else HedgeConfigs.LEAF_TILT)
				local jitter = HedgeConfigs.LEAF_JITTER
				local shift = CFrame.new(
					cellW * jitter * rng:NextNumber(-1, 1),
					cellH * jitter * rng:NextNumber(-1, 1),
					-- Avancer sur Z pose la feuille sur la face visible, pas dans l'epaisseur du carreau.
					thickness * 0.5
				)
				local turn = CFrame.Angles(tilt * rng:NextNumber(-1, 1), tilt * rng:NextNumber(-1, 1), spin)
				-- Decalage AVANT rotation : la feuille tourne alors sur elle-meme a l'endroit ou on l'a posee.
				-- Dans l'autre sens, la rotation deplacerait aussi le decalage et les feuilles partiraient en
				-- eventail autour du centre du carreau.
				leaf.CFrame = cell.CFrame * shift * turn

				-- Enfant du carreau : quand un carreau disparaitra a la taille, sa feuille partira avec lui. Un
				-- nettoyage a un seul endroit ne peut pas en oublier la moitie.
				leaf.Parent = cell
			end

			cell.Parent = parent

			-- RANGEMENT. Seulement si le carreau est taillable : hors grille, la coupe ne le trouvera jamais.
			-- `offset` est deja la position du carreau en repere local, la case se deduit d'une division, sans
			-- repasser par le monde ni relire la CFrame qu'on vient d'ecrire.
			if cuttable then
				local bucket = HedgeConfigs.CELL_BUCKET_SIZE
				local key = bucketKey(
					math.floor(offset.X / bucket),
					math.floor(offset.Y / bucket),
					math.floor(offset.Z / bucket)
				)
				local list = grid[key]
				if not list then
					list = {}
					grid[key] = list
				end
				table.insert(list, cell)
			end
		end
	end

	template:Destroy()
	return columns * rows
end

local function clearHedge(hedge: BasePart)
	local folder = cells[hedge]
	if not folder then
		return
	end
	-- On decremente par le nombre REEL de carreaux poses, pas par counts[hedge] : ce dernier ne compte que les
	-- taillables, alors que total suit tout ce qui est rendu. Les enfants directs du dossier SONT les carreaux
	-- (les feuilles sont enfants des carreaux), donc leur nombre est exactement ce qu'on a ajoute.
	total -= #folder:GetChildren()
	folder:Destroy()
	cells[hedge] = nil
	-- La grille pointe sur des carreaux qu'on vient de detruire : l'oublier ici, et nulle part ailleurs.
	-- Celui qui cree est celui qui nettoie, et il nettoie TOUT.
	grids[hedge] = nil
	counts[hedge] = nil
end

-- Pave toutes les faces demandees d'une haie. Rejouable : on reprend l'ancienne grille d'abord.
local function buildHedge(hedge: BasePart): number
	clearHedge(hedge)

	local folder = Instance.new("Folder")
	folder.Name = hedge.Name

	-- Le DESSUS est TOUJOURS taillable : maintenant qu'il y a l'echelle, on l'atteint. Avant on le bloquait sur les
	-- haies hautes parce qu'on ne l'atteignait pas du sol. Desormais c'est la PORTEE PHYSIQUE qui decide qui peut le
	-- couper : du sol la lame n'atteint pas le dessus d'une haie haute (trop loin du corps), depuis l'echelle (corps
	-- monte) oui. Une haie haute ne peut donc finir a 100% qu'avec l'echelle : c'est la progression voulue.
	local topCuttable = true

	local grid: { [number]: { BasePart } } = {}
	-- Deux comptes distincts : `rendered` est tout ce qui est pose (pese sur le budget et sur le nettoyage),
	-- `cuttable` est ce que la coupe peut atteindre (sert au pourcentage de compl4tion). Le dessus non taillable
	-- gonfle le premier sans toucher au second, sinon la haie ne pourrait jamais finir a 100 pour cent.
	local rendered = 0
	local cuttable = 0
	for _, faceName in ipairs(HedgeConfigs.CELL_FACES) do
		local canCut = not (faceName == "Y+" and not topCuttable)
		local n = buildFace(hedge, folder, faceName, grid, canCut)
		rendered += n
		if canCut then
			cuttable += n
		end
	end

	-- Le garde-fou est verifie AVANT de parenter : rien n'entre dans le monde tant qu'on n'a pas la place.
	-- Mieux vaut une haie nue qu'un jeu a quinze images par seconde qu'on met une heure a diagnostiquer.
	if total + rendered > HedgeConfigs.CELL_BUDGET then
		folder:Destroy()
		warn(
			`[HedgeCellService] Budget depasse : {total} + {rendered} > {HedgeConfigs.CELL_BUDGET}. `
				.. `"{hedge.Name}" reste nue. Monte CELL_SIZE, enleve des faces, ou releve CELL_BUDGET.`
		)
		return 0
	end

	folder.Parent = getCellFolder()
	cells[hedge] = folder
	grids[hedge] = grid
	-- counts sert au pourcentage : c'est le nombre de carreaux TAILLABLES. total suit tout ce qui est pose.
	counts[hedge] = cuttable
	total += rendered
	return rendered
end

-- Nombre de carreaux d'une haie. Fige a la construction : il ne change jamais, seuls les attributs des
-- carreaux bougent. C'est ce service-ci qui les cree et les detruit, personne d'autre ne touche a la table.
function HedgeCellService.getCount(hedge: BasePart): number
	return counts[hedge] or 0
end

-- AUTO-COMPLETION : met AU RAS (growth 0) tous les carreaux encore a tailler d'une haie, et rend leur nombre. Appele
-- par la coupe quand la haie franchit le seuil d'auto-completion. C'est ce service qui possede les carreaux, donc c'est
-- lui qui les termine (feuille des ARETES retiree, comme une arete arrivee au ras en coupe normale). Les carreaux ainsi
-- finis comptent pour l'XP / les debris cote appelant.
function HedgeCellService.finishRemaining(hedge: BasePart): number
	local folder = cells[hedge]
	if not folder then
		return 0
	end
	local finished = 0
	for _, cell in ipairs(folder:GetChildren()) do
		local growth = cell:GetAttribute(HedgeConfigs.GROWTH_ATTRIBUTE)
		if typeof(growth) == "number" and growth > 0 then
			cell:SetAttribute(HedgeConfigs.GROWTH_ATTRIBUTE, 0)
			finished += 1
			if HedgeConfigs.CUT_EDGE_CLEAR and cell:GetAttribute(HedgeConfigs.EDGE_ATTRIBUTE) then
				local leaf = cell:FindFirstChild("Leaf")
				if leaf then
					leaf:Destroy()
				end
			end
		end
	end
	return finished
end

-- Remplit `out` avec les carreaux susceptibles d'etre a `radius` de `position`, et rend leur nombre.
--
-- ON REMPLIT UNE TABLE FOURNIE au lieu d'en rendre une neuve : l'appelant en garde UNE seule et la reutilise a
-- chaque frame. Rendre une table ici en creerait soixante par seconde et par joueur, a ramasser ensuite.
--
-- "Susceptibles" : on rend le contenu des cases qui touchent la sphere, pas le resultat d'un test exact. Les
-- carreaux rendus sont donc un SUR-ENSEMBLE, a l'appelant de faire son test precis. C'est le but : remplacer
-- neuf cent tests par une trentaine, pas les supprimer.
function HedgeCellService.collectNear(
	hedge: BasePart,
	position: Vector3,
	radius: number,
	out: { BasePart }
): number
	local grid = grids[hedge]
	if not grid then
		return 0
	end

	local point = hedge.CFrame:PointToObjectSpace(position)
	local bucket = HedgeConfigs.CELL_BUCKET_SIZE
	-- Portee EN CASES, arrondie au-dessus : une sphere de 2.5 sur des cases de 3 peut deborder sur la voisine,
	-- donc il en faut une de chaque cote. Arrondir en dessous ferait rater des carreaux au bord, et la coupe
	-- aurait des trous qu'on mettrait longtemps a relier a ce reglage.
	local span = math.ceil(radius / bucket)
	local cx = math.floor(point.X / bucket)
	local cy = math.floor(point.Y / bucket)
	local cz = math.floor(point.Z / bucket)

	local count = 0
	for dx = -span, span do
		for dy = -span, span do
			for dz = -span, span do
				local list = grid[bucketKey(cx + dx, cy + dy, cz + dz)]
				if list then
					for _, cell in ipairs(list) do
						count += 1
						out[count] = cell
					end
				end
			end
		end
	end
	return count
end

function HedgeCellService.init()
	-- Resolu AVANT le premier pavage, sinon les haies deja etiquetees sortiraient nues.
	leafTemplate = resolveLeaf()

	local hedges = 0
	for _, instance in ipairs(CollectionService:GetTagged(HedgeConfigs.TAG)) do
		if instance:IsA("BasePart") then
			if buildHedge(instance) > 0 then
				hedges += 1
			end
		end
	end

	CollectionService:GetInstanceAddedSignal(HedgeConfigs.TAG):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			buildHedge(instance)
		end
	end)

	CollectionService:GetInstanceRemovedSignal(HedgeConfigs.TAG):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			clearHedge(instance)
		end
	end)

	-- Le compte est ce qu'on vient CHERCHER a cette etape : c'est lui qu'on compare a la baseline de 4.71 ms.
	-- Le compte est ce qu'on vient CHERCHER a cette etape. On annonce le nombre d'INSTANCES et non de carreaux :
	-- chaque carreau porte une feuille, c'est donc le double qui pese sur le moteur.
	local instances = if leafTemplate then total * 2 else total
	print(
		`[HedgeCellService] {total} carreaux ({instances} instances) sur {hedges} haie(s), `
			.. `faces : {table.concat(HedgeConfigs.CELL_FACES, " ")}`
	)
end

return HedgeCellService
