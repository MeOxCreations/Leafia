--!strict
-- Balancement des feuilles de haie.
--
-- POURQUOI COTE CLIENT, alors que les feuilles sont creees par le serveur : une part que le SERVEUR bouge
-- replique sa CFrame a tous les joueurs. Des milliers de feuilles animees, ce serait la bande passante entiere
-- depensee pour du decor. Ici chaque client calcule le mouvement chez lui, et rien ne part sur le reseau.
--
-- Le serveur ne touche plus aux feuilles apres les avoir posees : rien ne vient ecraser ce qu'on fait.
--
-- TROIS ECONOMIES, dans l'ordre de ce qu'elles rapportent :
--
--   1. GROUPES. Les feuilles sont rangees par haie. On teste la distance de la HAIE, pas de chaque feuille :
--      un test au lieu de plusieurs centaines. Une haie hors de portee ne coute donc plus rien du tout,
--      quel que soit le nombre de feuilles qu'elle porte. C'est de loin le plus gros gain.
--   2. TRANCHES. Dans une haie active, on ne met a jour qu'une fraction des feuilles par frame. Un
--      balancement lent n'a pas besoin de soixante images par seconde.
--   3. REPOS. Une haie qui sort de portee est remise a plat UNE fois, puis oubliee.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)

local HedgeLeafController = {}

type Leaf = {
	part: BasePart,
	-- Le carreau qui la porte. C'est LUI qui retient la pousse, dans un attribut pose par le serveur.
	cell: BasePart,
	-- CFrame du carreau, retenue une fois : un carreau ne bouge jamais.
	cellCFrame: CFrame,
	-- Position de la feuille DANS le repere de son carreau, a pousse pleine. Le serveur ne deplace jamais la
	-- feuille : il ne fait que descendre la pousse, et chaque client en deduit ou la poser.
	--
	-- C'est ce qui evite que serveur et client se disputent la meme CFrame. Le serveur possede la DONNEE
	-- (combien il reste de pousse), le client possede le RENDU (ou ca se traduit a l'ecran).
	spawnLocal: CFrame,
	-- Taille a pousse pleine. La feuille RETRECIT en etant taillee : l'enfoncement seul ne se voit presque pas
	-- sur une feuille large, alors qu'un changement de silhouette saute aux yeux.
	spawnSize: Vector3,
	-- Derniere pousse REELLEMENT appliquee a la taille. Ecrire Size a chaque frame sur un MeshPart coute cher
	-- pour rien : on ne le fait que quand la valeur a bouge.
	shownGrowth: number,
	-- Derniers degats REELLEMENT appliques. Meme raison : on n'ecrit la transparence que quand la valeur bouge.
	shownDamage: number,
	-- Teinte d'origine, retenue pour pouvoir revenir dessus. Sans elle, un carreau soigne un jour resterait
	-- rouge : on n'aurait plus la couleur de depart.
	spawnColor: Color3,
	-- Couleur de coupe PROPRE a cette feuille (tiree de la palette). C'est ce qui donne les taches de tons differents
	-- une fois taillee, au lieu d'un vert uniforme. Deduite de la position, comme phase : pareille sur tous les clients.
	trimmedColor: Color3,
	-- Present si la feuille a un SurfaceAppearance. C'est LUI qui porte la couleur quand il existe : la teinte
	-- de la part est alors ignoree par le moteur.
	appearance: SurfaceAppearance?,
	-- Decalage propre a chaque feuille. Sans lui toute la haie oscillerait d'un seul bloc, ce qui ressemble a
	-- une erreur d'affichage et pas a du vent.
	phase: number,
	-- La feuille bouge-t-elle en ce moment. Sert a ne la remettre a plat qu'UNE fois quand elle sort de la
	-- bulle du joueur, au lieu de reecrire sa CFrame de repos a chaque frame pour rien.
	swaying: boolean,
}

type Group = {
	leaves: { Leaf },
	-- Sphere englobante, calculee a la construction. C'est elle qu'on teste, une fois, au lieu de chaque
	-- feuille.
	center: Vector3,
	radius: number,
	-- Bornes verticales des feuilles de la haie (calculees avec la sphere). Servent au DEGRADE vertical : situer
	-- chaque feuille entre le bas (minY) et le haut (maxY) pour doser l'assombrissement du bas.
	minY: number,
	maxY: number,
	-- Ou reprendre dans CETTE haie au prochain tour. Un curseur par groupe evite de reconstruire une liste
	-- globale a chaque fois que le joueur entre ou sort d'une portee.
	cursor: number,
	active: boolean,
	-- Sphere pas encore calculee : les feuilles arrivent par paquets, on attend qu'elles soient toutes la.
	dirty: boolean,
}

local groups: { [Instance]: Group } = {}

-- Palette de couleurs de coupe (base + accents), poids total precalcule une fois.
local TRIMMED_VARIANTS = HedgeConfigs.TRIMMED_COLOR_VARIANTS
local TRIMMED_WEIGHT_TOTAL = 0
for _, v in ipairs(TRIMMED_VARIANTS) do
	TRIMMED_WEIGHT_TOTAL += v.weight
end

-- Couleur de coupe DE CETTE feuille : tiree de la palette par un hash de sa POSITION (deterministe, donc identique
-- sur tous les clients et rien a synchroniser, meme idee que phase). Feuilles voisines = valeurs differentes -> des
-- TACHES de tons melanges une fois la haie taillee, au lieu d'un aplat uniforme.
local function pickTrimmedColor(position: Vector3): Color3
	local h = math.sin(position.X * 12.9898 + position.Y * 78.233 + position.Z * 37.719) * 43758.5453
	local r = (h - math.floor(h)) * TRIMMED_WEIGHT_TOTAL -- fraction 0..1 * poids total
	for _, v in ipairs(TRIMMED_VARIANTS) do
		r -= v.weight
		if r <= 0 then
			return v.color
		end
	end
	return TRIMMED_VARIANTS[1].color
end

local function addLeaf(group: Group, part: BasePart)
	local cell = part.Parent
	if not (cell and cell:IsA("BasePart")) then
		return
	end

	local position = part.Position
	-- Phase DEDUITE de la position plutot que tiree au hasard : deux feuilles voisines ont des phases
	-- differentes, et rien n'a besoin d'etre stocke ni synchronise entre les clients.
	local phase = position.X * 0.7 + position.Y * 1.9 + position.Z * 1.3
	local cellCFrame = cell.CFrame
	local found = part:FindFirstChildOfClass("SurfaceAppearance")
	local appearance: SurfaceAppearance? = found
	table.insert(group.leaves, {
		part = part,
		cell = cell,
		cellCFrame = cellCFrame,
		-- Le serveur ne deplace jamais la feuille : sa CFrame est donc toujours celle de la pousse pleine,
		-- meme pour un joueur qui arrive sur une haie deja taillee.
		spawnLocal = cellCFrame:Inverse() * part.CFrame,
		spawnSize = part.Size,
		-- Volontairement impossible : force une premiere mise a l'echelle des la premiere frame, y compris
		-- pour un joueur qui arrive sur une haie DEJA taillee.
		shownGrowth = -1,
		shownDamage = -1,
		spawnColor = appearance and appearance.Color or part.Color,
		trimmedColor = pickTrimmedColor(position),
		appearance = appearance,
		phase = phase,
		-- Au repos au depart : sa CFrame de naissance est deja sa pose de repos a pousse pleine, donc rien a
		-- corriger tant qu'elle n'est pas entree dans la bulle.
		swaying = false,
	})
	group.dirty = true
end

-- Position de repos d'une feuille pour la pousse actuelle, et cette pousse.
--
-- Elle RENTRE dans la haie a mesure que la pousse descend : l'axe Z du carreau pointe vers l'exterieur, donc
-- avancer en -Z enfonce la feuille. Toutes les feuilles taillees se retrouvent ainsi sur un meme plan, et
-- c'est cette surface plate qui donne l'avant / apres.
local function restOf(leaf: Leaf): (CFrame, number)
	local growth = leaf.cell:GetAttribute(HedgeConfigs.GROWTH_ATTRIBUTE)
	local value = if typeof(growth) == "number" then growth else 1
	local sink = (1 - value) * HedgeConfigs.CUT_DEPTH
	-- PEIGNAGE. La feuille pivote sur elle-meme a mesure qu'elle est taillee, dans le plan de la face (axe Z du
	-- carreau, qui apres spawnLocal est l'axe propre de la feuille). A pousse pleine : rien. A ras : tout le
	-- reglage. Mis DANS restOf et pas seulement dans le balancement pour qu'une feuille au repos, hors de la
	-- bulle du joueur, garde quand meme son orientation de taille.
	local comb = math.rad(HedgeConfigs.LEAF_TRIM_SPIN) * (1 - value)
	return leaf.cellCFrame * CFrame.new(0, 0, -sink) * leaf.spawnLocal * CFrame.Angles(0, 0, comb), value
end

-- Sphere englobante du groupe. Recalculee seulement quand des feuilles ont ete ajoutees.
local function refresh(group: Group)
	group.dirty = false
	local count = #group.leaves
	if count == 0 then
		group.radius = 0
		return
	end

	local minimum = group.leaves[1].part.Position
	local maximum = minimum
	for index = 2, count do
		local position = group.leaves[index].part.Position
		minimum = minimum:Min(position)
		maximum = maximum:Max(position)
	end
	group.center = (minimum + maximum) * 0.5
	group.radius = (maximum - group.center).Magnitude
	group.minY = minimum.Y
	group.maxY = maximum.Y
end

-- Remet les feuilles a plat. Appele UNE fois quand une haie sort de portee : sans ca elles resteraient figees
-- sur l'angle qu'elles avaient au moment ou on a cesse de les suivre.
local function rest(group: Group)
	for _, leaf in ipairs(group.leaves) do
		if leaf.part.Parent then
			leaf.part.CFrame = (restOf(leaf))
			-- Remise a plat effectuee : sans ca, la bulle la remettrait a plat une SECONDE fois en la voyant
			-- encore marquee comme bougeante, pour la meme valeur.
			leaf.swaying = false
		end
	end
end

-- Les feuilles detruites sont retirees ICI, pendant le parcours, et non par un signal.
--
-- Un signal par feuille, ce sont des milliers de connexions a tenir et a couper. La tranche passe de toute
-- facon sur chacune : il suffit de regarder si elle existe encore.
-- Retrait par ECHANGE avec la derniere : immediat, alors que table.remove decale tout ce qui suit.
local function drop(group: Group, index: number)
	local last = #group.leaves
	group.leaves[index] = group.leaves[last]
	group.leaves[last] = nil
	group.dirty = true
end

local function sway(
	group: Group,
	now: number,
	pulsation: number,
	amplitude: number,
	eye: Vector3,
	bubbleSquared: number
)
	local count = #group.leaves
	if count == 0 then
		return
	end
	local slice = math.max(1, math.ceil(count / HedgeConfigs.LEAF_BATCH))

	for _ = 1, slice do
		if group.cursor > #group.leaves then
			group.cursor = 1
		end
		local leaf = group.leaves[group.cursor]
		if not leaf then
			break
		end

		if not leaf.part.Parent then
			drop(group, group.cursor)
			continue
		end

		-- LA BULLE. Seules les feuilles a portee du joueur bougent : sur une grande haie, on n'anime que la
		-- portion pres de lui, pas la face d'en face qu'il ne voit meme pas.
		--
		-- Mesuree depuis le CARREAU, dont la position est stockee : aucune lecture de la part a l'ecran. Au
		-- carre des deux cotes, donc pas de racine carree par feuille.
		-- Ce test est bien plus leger que l'ecriture de CFrame qu'il evite : c'est ce qui le rend rentable.
		if (leaf.cellCFrame.Position - eye).Magnitude ^ 2 > bubbleSquared then
			-- Hors bulle. On la remet a plat une seule fois, puis on ne la touche plus : une feuille immobile
			-- qu'on sait deja immobile ne coute que ce test de distance.
			if leaf.swaying then
				leaf.part.CFrame = (restOf(leaf))
				leaf.swaying = false
			end
			group.cursor += 1
			continue
		end

		local restCFrame, growth = restOf(leaf)
		leaf.swaying = true

		-- SUR-TAILLE. La feuille s'efface a mesure que le carreau s'abime, et le corps de la haie apparait
		-- dessous : c'est la plaque chauve du vieux bois, exactement ce qu'on voit sur une haie trop coupee.
		--
		-- On efface au lieu de retirer : un carreau abime doit rester une CASE, pas un trou. Il faudra pouvoir
		-- le montrer, le compter dans la note du client, et peut-etre le soigner un jour.
		local damage = leaf.cell:GetAttribute(HedgeConfigs.DAMAGE_ATTRIBUTE)
		local hurt = if typeof(damage) == "number" then damage else 0
		-- La couleur depend de DEUX choses : la pousse (vert frais -> vert taille) et les degats (-> rouge).
		-- On la recalcule donc des que l'une OU l'autre bouge. Le fondu, lui, ne suit que les degats.
		local damageChanged = math.abs(hurt - leaf.shownDamage) > 0.001
		local growthChanged = math.abs(growth - leaf.shownGrowth) > 0.001

		if damageChanged or growthChanged then
			-- ETAGE 1 : le vert vire du FRAIS (feuille intacte) au TAILLE (feuille au ras) a mesure que la
			-- pousse descend. spawnColor est la couleur de l'asset : c'est elle le vert frais, on ne la reecrit
			-- pas en config pour ne pas avoir deux verites a garder d'accord.
			local trimmed = math.clamp(1 - growth, 0, 1)
			local base = leaf.spawnColor:Lerp(leaf.trimmedColor, trimmed)
			-- DEGRADE VERTICAL : le bas de la haie tire vers un vert sombre, dose maximale tout en bas, nulle en haut.
			-- Sur la couleur FINALE, donc visible haie fraiche comme taillee. minY/maxY viennent de refresh (deja passe).
			local spanY = math.max(group.maxY - group.minY, 1e-3)
			local heightT = math.clamp((leaf.part.Position.Y - group.minY) / spanY, 0, 1)
			base = base:Lerp(HedgeConfigs.BOTTOM_GRADIENT_COLOR, (1 - heightT) * HedgeConfigs.BOTTOM_GRADIENT_STRENGTH)
			-- ETAGE 2 : le ROUGE d'acharnement, par-dessus, une fois passe le seuil. En dessous, le carreau
			-- s'abime sans que ca se voie : c'est la marge qui rend la regle apprenable au lieu de punitive.
			local tintStart = HedgeConfigs.DAMAGE_TINT_START
			local tint = math.clamp((hurt - tintStart) / math.max(1 - tintStart, 1e-3), 0, 1)
			local final = base:Lerp(HedgeConfigs.DAMAGE_COLOR, tint)
			-- Le SurfaceAppearance porte la couleur quand il existe : la teinte de la part est alors ignoree par
			-- le moteur. Chaque feuille a le sien, puisqu'elle est clonee.
			local appearance = leaf.appearance
			if appearance then
				appearance.Color = final
			else
				leaf.part.Color = final
			end
		end

		if damageChanged then
			leaf.shownDamage = hurt
			-- FONDU. La feuille s'efface a mesure que le carreau s'abime, le vieux bois apparait dessous : la
			-- plaque chauve d'une haie trop coupee. Bornee : une feuille invisible laisse un trou. Son PROPRE
			-- seuil, plus tard que la teinte : accompagner le rouge le laverait au moment ou il compte.
			local ratio = math.clamp(hurt, 0, 1)
			local fadeStart = HedgeConfigs.DAMAGE_FADE_START
			local fade = math.clamp((ratio - fadeStart) / math.max(1 - fadeStart, 1e-3), 0, 1)
			leaf.part.Transparency = fade * HedgeConfigs.DAMAGE_FADE_MAX
		end

		-- RETRECISSEMENT. Ecrit seulement quand la pousse a bouge : Size sur un MeshPart est bien plus cher
		-- qu'une CFrame, et l'ecrire a chaque frame pour la meme valeur ne changerait rien a l'ecran.
		if growthChanged then
			leaf.shownGrowth = growth
			local shrink = HedgeConfigs.CUT_LEAF_SHRINK
			local size = leaf.spawnSize * (shrink + (1 - shrink) * growth)

			-- PLANCHER ABSOLU, s'il est demande. Il ne s'applique qu'a la largeur et a la hauteur : l'epaisseur
			-- est celle du mesh, la forcer l'epaissirait sans rien apporter a la lecture.
			--
			-- BORNE A LA TAILLE DE DEPART de CHAQUE feuille. Sans ca, un plancher regle plus haut que la plus
			-- petite feuille la fait GROSSIR en etant taillee : l'inverse exact de ce qu'on raconte, et invisible
			-- au reglage puisque la taille de depart est tiree au hasard. Les grandes feuilles, elles, retrecissent
			-- normalement, donc rien ne signale l'erreur a l'ecran.
			local floor = HedgeConfigs.CUT_LEAF_MIN_SIZE
			if floor > 0 then
				size = Vector3.new(
					math.max(size.X, math.min(floor, leaf.spawnSize.X)),
					math.max(size.Y, math.min(floor, leaf.spawnSize.Y)),
					size.Z
				)
			end
			leaf.part.Size = size
		end
		-- LE BALANCEMENT S'EFFACE AVEC LA POUSSE. Une cellule taillee ne remue presque plus.
		--
		-- Signal gratuit et tres fort : le desordre bouge, le propre est immobile. La ligne de coupe se lit
		-- toute seule, sans une icone ni un mot a l'ecran.
		local reach = amplitude
			* (HedgeConfigs.TRIMMED_SWAY + (1 - HedgeConfigs.TRIMMED_SWAY) * growth)
		local angle = math.sin(now * pulsation + leaf.phase) * reach
		-- Deux axes, avec des amplitudes differentes : une rotation sur un seul axe se lit comme un essuie
		-- glace. Le melange donne un flottement.
		leaf.part.CFrame = restCFrame * CFrame.Angles(angle * 0.5, 0, angle)
		group.cursor += 1
	end
end

-- D'ou on mesure la distance aux haies.
--
-- DU PERSONNAGE, pas de la camera. En vue de travail la camera est a une vingtaine de studs derriere le
-- joueur : mesurer depuis elle endormait la haie qu'il est en train de tailler. Une haie endormie n'applique
-- plus la pousse, donc les feuilles restaient en place a l'ecran alors que le serveur les avait bien coupees.
-- Le joueur voyait sa coupe "s'actualiser" en se rapprochant, et croyait a un rate de detection.
--
-- Le personnage est aussi ce qui a du SENS : on regarde toujours autour de lui, jamais autour de la camera.
local function viewpoint(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	-- Repli le temps d'un respawn : mieux vaut animer depuis la camera que ne plus rien animer.
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position
end

local function step()
	local eye = viewpoint()
	if not eye then
		return
	end

	local now = os.clock()
	local pulsation = HedgeConfigs.LEAF_SWAY_SPEED * 2 * math.pi
	local amplitude = math.rad(HedgeConfigs.LEAF_SWAY_ANGLE)
	local range = HedgeConfigs.LEAF_RANGE
	-- Rayon de la bulle par feuille, au carre : la distance de chaque feuille lui est comparee sans racine.
	local bubbleSquared = range * range

	for _, group in pairs(groups) do
		if group.dirty then
			refresh(group)
		end

		-- PREMIER FILTRE, PAR HAIE. Une haie dont meme le bord le plus proche depasse la portee sort ici, et ses
		-- centaines de feuilles ne sont meme pas parcourues. La bulle par feuille, plus fine, ne s'applique
		-- qu'aux haies qui passent ce test.
		local inRange = (group.center - eye).Magnitude <= range + group.radius

		if inRange then
			group.active = true
			sway(group, now, pulsation, amplitude, eye, bubbleSquared)
		elseif group.active then
			-- Transition seulement : une haie deja endormie ne coute plus qu'une soustraction de vecteurs.
			group.active = false
			rest(group)
		end
	end
end

local function collect(folder: Instance)
	-- Un groupe par ENFANT DIRECT du dossier, c'est-a-dire par haie : HedgeCellService range les carreaux de
	-- chaque haie dans son propre sous-dossier.
	local function register(hedgeFolder: Instance)
		if groups[hedgeFolder] then
			return
		end
		local group: Group = {
			leaves = {},
			center = Vector3.zero,
			radius = 0,
			minY = 0,
			maxY = 0,
			cursor = 1,
			active = true,
			dirty = true,
		}
		groups[hedgeFolder] = group

		for _, descendant in ipairs(hedgeFolder:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.Name == "Leaf" then
				addLeaf(group, descendant)
			end
		end

		hedgeFolder.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("BasePart") and descendant.Name == "Leaf" then
				addLeaf(group, descendant)
			end
		end)
	end

	for _, child in ipairs(folder:GetChildren()) do
		register(child)
	end
	folder.ChildAdded:Connect(register)
	folder.ChildRemoved:Connect(function(child: Instance)
		groups[child] = nil
	end)
end

function HedgeLeafController.init()
	-- Le dossier est cree par le serveur au demarrage : il peut ne pas encore etre replique ici.
	task.spawn(function()
		local folder = workspace:WaitForChild(HedgeConfigs.CELL_FOLDER, 30)
		if not folder then
			-- Pas de warn : une carte sans haie est un cas NORMAL, pas une anomalie.
			return
		end
		collect(folder)
	end)

	-- Heartbeat et non RenderStepped : le balancement est du decor, il n'a aucune raison de passer avant le
	-- rendu de la frame. Ce qui doit etre pret AVANT l'image, c'est la camera, pas les feuilles.
	RunService.Heartbeat:Connect(step)
end

return HedgeLeafController
