--!strict
-- MODE SUPPRESSION (build) : clic MAINTENU + slide -> on MARQUE tout ce qu'on balaie (l'asset passe en JAUNE NEON
-- semi-transparent : "va etre supprime"). La vraie suppression n'arrive qu'au RELACHEMENT. But : le joueur VOIT ce qu'il
-- va effacer AVANT que ca parte, il peut viser et s'ajuster sans regretter (rien n'est detruit tant qu'il tient le clic).
-- La cible = le descendant DIRECT du dossier Build sous le curseur (Model d'objet, ou part Wall / WallCorner).
--
-- Pilote par BuildController : start a l'entree du build ; setEnabled(true/false) selon le mode. CLIENT (prediction) :
-- la suppression est locale. Autorite serveur (remote) + sauvegarde : ensuite.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConfigs = require(ReplicatedStorage.Modules.Configs.BuildConfigs)
local BuildWallController = require(script.Parent.BuildWallController)
local BuildFx = require(script.Parent.Utils.BuildFx)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local PriceTag = require(script.Parent.Utils.PriceTag)

local WALL_PRICE = BuildConfigs.WALL_PRICE
local REFUND_COLOR = Color3.fromRGB(60, 190, 80) -- vert = coins RENDUS (supprimer rembourse)
local REFUND_GAP = 3 -- studs au-dessus de la structure ou flotte la pastille "+X"

local BuildDeleteController = {}

local FOLLOW_BIND = "LeafiaDeleteHover"
-- Highlight de SURVOL (avant le clic) : montre ce qu'un clic prendrait.
local HOVER_FILL = Color3.fromRGB(255, 220, 60)
local HOVER_OUTLINE = Color3.fromRGB(255, 240, 150)
-- MARQUE (pendant le balayage) : l'asset lui-meme passe en jaune neon semi-transparent.
local MARK_COLOR = Color3.fromRGB(255, 220, 40)
local MARK_MATERIAL = Enum.Material.Neon
local MARK_TRANSPARENCY = 0.6
-- Son joue a CHAQUE structure marquee (Appear_Sound). Pas de Sound pre-regle -> on le joue par ID (SoundUtils.playId).
local APPEAR_SOUND = "rbxassetid://138424352985426"
local APPEAR_VOLUME = 0.5

type SavedPart = { p: BasePart, color: Color3, material: Enum.Material, transparency: number }

local active = false
local enabled = false -- vrai seulement quand le mode SUPPRIMER est actif
local buildFolder: Instance? = nil
local hoverHighlights: { Highlight } = {} -- pool de surlignages du survol : 1 pour la structure + 1 par poteau qui partirait avec
local hoverTarget: Instance? = nil -- structure survolee (hors balayage)
local refundTag: PriceTag.Tag? = nil -- pastille flottante "+X" (coins rendus) sur ce qu'on va supprimer
local deleting = false -- clic maintenu : balayage de marquage en cours
-- structures MARQUEES "a supprimer" -> etat d'origine de leurs parts VISIBLES (pour restaurer si on annule / demarque).
local marked: { [Instance]: { SavedPart } } = {}
-- ORDRE du balayage (le "stroke") : sert a DEMARQUER en revenant sur ses pas (retrace) sans lever le clic.
local markedOrder: { Instance } = {}

-- Remonte de `part` jusqu'a l'enfant DIRECT du dossier Build (la "structure"), ou nil si `part` n'est pas dedans.
local function structureOf(part: Instance): Instance?
	local folder = buildFolder
	if not folder then
		return nil
	end
	local inst: Instance? = part
	while inst and inst.Parent ~= folder do
		inst = inst.Parent
	end
	-- Un poteau d'angle ne se supprime pas tout seul : on vise le MUR qui s'y rattache (le poteau partira avec, via
	-- l'auto-selection). Un poteau vraiment orphelin (aucun mur) reste supprimable direct, pour nettoyer les restes.
	if inst and inst:IsA("BasePart") and inst.Name == "WallCorner" then
		local wall = BuildWallController.wallTouchingPoint(inst.Position)
		if wall then
			return wall
		end
	end
	return inst
end

-- Surlignage numero i du pool (cree a la demande). Un par instance a surligner au survol (structure + poteaux).
local function getHoverHighlight(i: number): Highlight
	local h = hoverHighlights[i]
	if not h then
		h = Instance.new("Highlight") :: Highlight
		h.Name = "LeafiaDeleteHighlight"
		h.FillColor = HOVER_FILL
		h.FillTransparency = 0.5
		h.OutlineColor = HOVER_OUTLINE
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Enabled = false
		h.Parent = workspace
		hoverHighlights[i] = h
	end
	return h
end

local function clearHover()
	hoverTarget = nil
	for _, h in ipairs(hoverHighlights) do
		h.Adornee = nil
		h.Enabled = false
	end
end

-- Marque UNE structure "a supprimer" : on retient l'etat d'origine de ses parts VISIBLES, on les passe en jaune neon, et
-- on l'empile dans le stroke. Deja marquee -> rien. On saute les parts invisibles (ex hitbox) pour ne pas les reveler.
local function markOne(s: Instance)
	if marked[s] then
		return
	end
	local saved: { SavedPart } = {}
	local function markPart(p: BasePart)
		if p.Transparency >= 1 then
			return
		end
		table.insert(saved, { p = p, color = p.Color, material = p.Material, transparency = p.Transparency })
		p.Color = MARK_COLOR
		p.Material = MARK_MATERIAL
		p.Transparency = MARK_TRANSPARENCY
	end
	if s:IsA("BasePart") then
		markPart(s)
	end
	for _, d in ipairs(s:GetDescendants()) do
		if d:IsA("BasePart") then
			markPart(d)
		end
	end
	-- AUTO-SELECTION des poteaux d'angle : si c'est un mur, on marque AUSSI les poteaux a ses bouts qui partiraient avec lui
	-- (pas ceux encore tenus par un mur qui reste). Le joueur n'a plus a viser le poteau. Pas de rebond dessus : ca decalerait
	-- leur position et cleanupCornersFor ne les retrouverait plus a la suppression.
	if s:IsA("BasePart") and s.Name == "Wall" then
		for _, corner in ipairs(BuildWallController.orphanCornersOf(s, function(w: Instance): boolean
			return marked[w] ~= nil
		end)) do
			markPart(corner)
		end
	end
	marked[s] = saved
	table.insert(markedOrder, s)
	-- PILE au moment ou ca devient jaune : petit rebond slime + son "appear" (un par instance marquee).
	BuildFx.slimeBounce(s)
	SoundUtils.playId(APPEAR_SOUND, APPEAR_VOLUME)
end

-- Restaure UNE structure (annule le jaune, remet son etat d'origine). Sort de `marked` (mais PAS de markedOrder : le
-- caller gere l'ordre).
local function restoreOne(s: Instance)
	local saved = marked[s]
	if not saved then
		return
	end
	BuildFx.snapBounce(s) -- fige un eventuel rebond -> la structure demarquee revient net a sa place (pas de saut orphelin)
	for _, sp in ipairs(saved) do
		sp.p.Color = sp.color
		sp.p.Material = sp.material
		sp.p.Transparency = sp.transparency
	end
	marked[s] = nil
end

-- Balayage sur `target`. Nouveau -> on l'ajoute au stroke. Deja marque PLUS TOT dans le stroke -> le joueur revient sur
-- ses pas : on DEMARQUE tout ce qui a ete ajoute APRES lui (le stroke se retracte jusqu'au curseur). nil -> on ne touche rien.
local function sweepTo(target: Instance?)
	if not target then
		return
	end
	local idx = table.find(markedOrder, target)
	if not idx then
		markOne(target)
	else
		for i = #markedOrder, idx + 1, -1 do
			restoreOne(markedOrder[i])
			markedOrder[i] = nil
		end
	end
end

-- Vide la selection. commit=true -> on SUPPRIME chaque structure marquee (mur : nettoyage des poteaux orphelins d'abord).
-- commit=false -> on RESTAURE l'etat d'origine (annulation : sortie du mode sans relacher le clic).
local function clearMarks(commit: boolean)
	if commit then
		-- Passe 1 : figer TOUS les rebonds AVANT de calculer la moindre geometrie (un mur en plein saut est souleve -> ses
		-- bouts seraient faux -> son poteau d'angle ne serait pas trouve, cf le bug du clic simple).
		for _, s in ipairs(markedOrder) do
			BuildFx.snapBounce(s)
		end
		-- Passe 2 : rendre sa couleur d'origine a TOUTE part marquee. Les murs vont etre detruits (sans effet), mais un poteau
		-- PARTAGE (marque avec son mur puis finalement garde car un autre mur le tient) ne doit pas rester jaune.
		for _, s in ipairs(markedOrder) do
			for _, sp in ipairs(marked[s]) do
				sp.p.Color = sp.color
				sp.p.Material = sp.material
				sp.p.Transparency = sp.transparency
			end
		end
		-- Passe 3 : supprimer les murs ; leurs poteaux orphelins partent avec (cleanupCornersFor garde ceux encore tenus).
		for _, s in ipairs(markedOrder) do
			BuildWallController.cleanupCornersFor(s)
			s:Destroy() -- CLIENT-only ; remote de suppression + save plus tard
		end
	else
		for _, s in ipairs(markedOrder) do
			restoreOne(s)
		end
	end
	table.clear(marked)
	table.clear(markedOrder)
end

-- Structure sous le curseur (raycast filtre sur le SEUL dossier Build -> on ne vise que les objets poses, jamais le sol).
local function targetUnderCursor(): Instance?
	local camera = workspace.CurrentCamera
	local folder = buildFolder
	if not (camera and folder) then
		return nil
	end
	local m = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(m.X, m.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 3000, params)
	if not result then
		return nil
	end
	return structureOf(result.Instance)
end

-- Coins RENDUS en supprimant `s` : un segment de mur rembourse son prix ; le reste (objets, poteaux) 0 pour l'instant.
local function refundOf(s: Instance): number
	if s:IsA("BasePart") and s.Name == "Wall" then
		return WALL_PRICE
	end
	return 0
end

-- Sommet (monde) d'une structure, pour poser la pastille juste au-dessus.
local function topOf(inst: Instance): Vector3?
	if inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		return cf.Position + Vector3.new(0, size.Y * 0.5, 0)
	elseif inst:IsA("BasePart") then
		return inst.Position + Vector3.new(0, inst.Size.Y * 0.5, 0)
	end
	return nil
end

-- Montre la pastille "+X" (coins rendus) au-dessus de la cible : total de tout le marque en balayage, sinon le seul survole.
-- Total 0 (objet sans prix, rien) -> cachee.
local function updateRefundPill(target: Instance?)
	local total = 0
	local anchorInst: Instance? = nil
	if deleting then
		for _, s in ipairs(markedOrder) do
			total += refundOf(s)
		end
		anchorInst = target or markedOrder[#markedOrder]
	elseif target then
		total = refundOf(target)
		anchorInst = target
	end
	local top = if anchorInst then topOf(anchorInst) else nil
	if total > 0 and top and refundTag then
		refundTag.show(top + Vector3.new(0, REFUND_GAP, 0), "+" .. total, REFUND_COLOR)
	elseif refundTag then
		refundTag.hide()
	end
end

local function updateHover()
	if not (active and enabled) then
		return
	end
	local target = targetUnderCursor()
	if deleting then
		-- clic maintenu : on MARQUE (jaune) ce qu'on balaie, et on DEMARQUE si on revient en arriere ; suppression au relachement.
		sweepTo(target)
		updateRefundPill(target)
		return
	end
	if target ~= hoverTarget then
		hoverTarget = target
		-- On surligne la cible ET (si c'est un mur) les poteaux d'angle qui partiraient avec elle. Comme on n'est pas en
		-- balayage, aucun mur n'est "aussi supprime" -> isAlsoGone = toujours faux (un poteau partage reste bleu).
		local toShow: { Instance } = {}
		if target then
			table.insert(toShow, target)
			if target:IsA("BasePart") and target.Name == "Wall" then
				for _, corner in ipairs(BuildWallController.orphanCornersOf(target, function(_: Instance): boolean
					return false
				end)) do
					table.insert(toShow, corner)
				end
			end
		end
		for i, inst in ipairs(toShow) do
			local h = getHoverHighlight(i)
			h.Adornee = inst
			h.Enabled = true
		end
		for i = #toShow + 1, #hoverHighlights do
			hoverHighlights[i].Adornee = nil
			hoverHighlights[i].Enabled = false
		end
	end
	updateRefundPill(target) -- "+X" sur la cible survolee aussi (hors balayage)
end

function BuildDeleteController.start(ground: BasePart)
	if active then
		return
	end
	active = true
	buildFolder = ground.Parent and ground.Parent:FindFirstChild(BuildConfigs.BUILDS_FOLDER)
	refundTag = PriceTag.new()
	RunService:BindToRenderStep(FOLLOW_BIND, Enum.RenderPriority.Camera.Value + 1, updateHover)
end

function BuildDeleteController.stop()
	if not active then
		return
	end
	active = false
	enabled = false
	deleting = false
	clearMarks(false) -- ce qui restait marque est RESTAURE (on ne supprime pas a la sortie)
	buildFolder = nil
	RunService:UnbindFromRenderStep(FOLLOW_BIND)
	for _, h in ipairs(hoverHighlights) do
		h:Destroy()
	end
	table.clear(hoverHighlights)
	if refundTag then
		refundTag.destroy()
		refundTag = nil
	end
	hoverTarget = nil
end

function BuildDeleteController.setEnabled(on: boolean)
	enabled = on
	if not on then
		deleting = false
		clearMarks(false) -- on quitte le mode : la selection en cours est ANNULEE (restauree), rien n'est supprime
		clearHover()
		if refundTag then
			refundTag.hide()
		end
	end
end

function BuildDeleteController.init()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not (active and enabled) or gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			deleting = true -- debut du balayage : updateHover marque / demarque au fil du curseur tant que c'est maintenu
			sweepTo(hoverTarget) -- marque tout de suite ce qu'on survolait (nil -> rien)
			clearHover()
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		-- Relachement TOUJOURS traite : c'est LUI qui VALIDE la suppression de tout ce qui est marque.
		if input.UserInputType == Enum.UserInputType.MouseButton1 and deleting then
			deleting = false
			clearMarks(true) -- COMMIT : maintenant, et seulement maintenant, ce qui etait jaune disparait
		end
	end)
end

return BuildDeleteController
