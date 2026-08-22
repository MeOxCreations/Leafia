--!strict
-- ACCESSOIRES QUI SUIVENT UN OS. La canne du grand-pere, et tout objet de decor pose sur un personnage SKINNE.
--
-- POURQUOI ON RECOPIE AU LIEU DE SOUDER. Un Motor6D exige DEUX BasePart. Sur un mesh skinne, les membres sont des
-- `Bone`, qui heritent d'Attachment : aucun joint ne peut s'y accrocher. `Bone.TransformedWorldCFrame` est la
-- seule propriete qui donne la position ANIMEE d'un os, et elle se LIT. On la recopie donc a chaque image.
--
-- POURQUOI COTE CLIENT. C'est du decor : rien ne depend de la position exacte de la canne, aucune regle de jeu ne
-- s'y accroche. Chaque client fait le calcul chez lui, donc c'est fluide a son propre framerate et ca ne coute
-- pas un octet de reseau. Cote serveur, il aurait fallu repliquer une CFrame soixante fois par seconde pour
-- obtenir un resultat MOINS bon (la replication est plus lente que l'affichage, l'objet aurait saccade).
--
-- L'ECRITURE TIENT parce que le serveur ne touche jamais a cet objet : une part ancree n'est repliquee que quand
-- elle CHANGE cote serveur. Le jour ou un service se mettrait a la deplacer, les deux se battraient.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PropAttachConfigs = require(ReplicatedStorage.Modules.Configs.PropAttachConfigs)

local PropFollowController = {}

-- Un accessoire resolu : l'os a suivre, la part a bouger, et l'ecart entre les deux.
type Bound = {
	bone: Bone,
	part: BasePart,
	-- Ecart CAPTURE UNE FOIS, a la premiere image. Le placement fait dans Studio est la source de verite : on le
	-- releve au lieu de demander un reglage que personne n'aurait envie de tatonner.
	offset: CFrame,
	-- Les autres parts de l'objet, avec leur ecart a la part maitresse. Un accessoire peut etre un Model de
	-- plusieurs morceaux, et ils doivent tous suivre ENSEMBLE.
	others: { { part: BasePart, offset: CFrame } },
}

local bound: { Bound } = {}

-- Cherche un descendant par nom sous une racine, sans attendre. Le re-scan est fait par l'appelant.
local function findUnder(root: Instance, name: string): Instance?
	return root:FindFirstChild(name, true)
end

-- Prepare un accessoire : trouve le personnage, l'os et l'objet, puis releve l'ecart entre l'os et l'objet.
-- Rend nil tant que l'une des trois pieces manque -- ce qui est un etat NORMAL au demarrage (streaming).
local function tryBind(entry: PropAttachConfigs.Prop): Bound?
	local model = findUnder(workspace, entry.model)
	if not (model and model:IsA("Model")) then
		return nil
	end
	local bone = findUnder(model, entry.bone)
	if not (bone and bone:IsA("Bone")) then
		return nil
	end
	-- L'objet peut trainer a la racine du Workspace ou etre deja range sous le personnage.
	local prop = findUnder(model, entry.prop) or findUnder(workspace, entry.prop)
	if not prop then
		return nil
	end

	-- Un Model n'a pas de CFrame : il faut une part maitresse. Sa PrimaryPart si elle existe, sinon la premiere.
	local main: BasePart? = nil
	if prop:IsA("BasePart") then
		main = prop
	elseif prop:IsA("Model") then
		main = prop.PrimaryPart or prop:FindFirstChildWhichIsA("BasePart", true)
	end
	if not main then
		return nil
	end
	local lead = main :: BasePart

	-- ANCRE ET SANS COLLISION. On ecrit sa CFrame a la main : la physique n'a rien a faire la-dedans, et une canne
	-- qui bouscule le personnage ou le decor serait ridicule.
	local others: { { part: BasePart, offset: CFrame } } = {}
	local function prepare(part: BasePart)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false -- n'a d'effet QUE parce que CanCollide est faux
		part.CanTouch = false
	end
	prepare(lead)
	if prop ~= lead then
		for _, d in ipairs(prop:GetDescendants()) do
			if d:IsA("BasePart") and d ~= lead then
				prepare(d)
				-- Ecart a la part MAITRESSE, releve une fois : les morceaux d'un meme objet gardent leur forme
				-- sans qu'on ait a les bouger un par un chaque image.
				others[#others + 1] = { part = d, offset = lead.CFrame:Inverse() * d.CFrame }
			end
		end
	end

	return {
		bone = bone :: Bone,
		part = lead,
		offset = (bone :: Bone).TransformedWorldCFrame:Inverse() * lead.CFrame,
		others = others,
	}
end

local function step()
	for _, item in ipairs(bound) do
		-- L'objet ou l'os ont pu disparaitre (streaming, respawn du PNJ). On saute au lieu d'ecrire dans le vide.
		if item.part.Parent and item.bone.Parent then
			local world = item.bone.TransformedWorldCFrame * item.offset
			item.part.CFrame = world
			for _, other in ipairs(item.others) do
				other.part.CFrame = world * other.offset
			end
		end
	end
end

function PropFollowController.init()
	-- EN TACHE DE FOND : le personnage et l'objet peuvent arriver tard, et un init de boot ne doit jamais bloquer
	-- la sequence en attendant quoi que ce soit.
	task.spawn(function()
		local pending = table.clone(PropAttachConfigs.PROPS)
		local deadline = os.clock() + PropAttachConfigs.RESOLVE_TIMEOUT
		-- RE-SCAN en boucle, et pas un WaitForChild par piece : une piece absente ferait attendre le timeout
		-- ENTIER avant meme d'essayer la suivante, et on cumulerait les attentes.
		while #pending > 0 and os.clock() < deadline do
			for i = #pending, 1, -1 do
				local ready = tryBind(pending[i])
				if ready then
					bound[#bound + 1] = ready
					table.remove(pending, i)
				end
			end
			if #pending > 0 then
				task.wait(0.3)
			end
		end

		-- ON NOMME CE QU'ON N'A PAS TROUVE. Un compteur global ("2 accessoires poses") ne revele jamais l'absence
		-- du troisieme : on chercherait le probleme dans l'animation alors que l'objet n'a simplement pas ete vu.
		for _, entry in ipairs(pending) do
			warn(
				`[PropFollow] Accessoire "{entry.prop}" non pose : `
					.. `modele "{entry.model}", os "{entry.bone}" -- l'un des trois est introuvable.`
			)
		end

		if #bound == 0 then
			return
		end
		-- APRES la camera : les os sont mis a jour par l'animation pendant l'image, et lire leur position trop tot
		-- donnerait l'etat de l'image PRECEDENTE. L'accessoire trainerait alors d'une image derriere la main, ce
		-- qui se voit sur un geste rapide.
		RunService:BindToRenderStep("LeafiaPropFollow", Enum.RenderPriority.Camera.Value + 1, step)
		print(`[PropFollow] {#bound} accessoire(s) accroche(s) a un os.`)
	end)
end

--- Coupe la boucle. Elle vit sur RunService, qui SURVIT a ce script : sans ce debranchement explicite elle
--- tournerait toute la session.
function PropFollowController.stop()
	pcall(function()
		RunService:UnbindFromRenderStep("LeafiaPropFollow")
	end)
	table.clear(bound)
end

return PropFollowController
