--!strict
-- L'ECHELLE SE PLIE ET SE DEPLIE. UNE SEULE anim pour les deux sens, et UN SEUL proprietaire : ce module.
--
-- `ActionLadderAnimation` raconte tout le geste d'un bloc : 0 -> `FermerEvenement` la referme, puis
-- `FermerEvenement` -> `LadderOpenEndEvent` la rouvre. On ne joue donc jamais "une anim de repli" et "une anim de
-- depli" : on avance dans la MEME piste et on la FIGE (vitesse 0) au marqueur du milieu. C'est ce qui permet de
-- tenir la pose repliee aussi longtemps qu'on veut.
--
-- POURQUOI UN MODULE ET PAS UNE FONCTION DANS CHAQUE SERVICE. Deux endroits la replient : le portage (on la ferme
-- pour marcher avec) et le camion (elle est rangee fermee dans la benne). Deux pistes chargees sur le MEME
-- Animator joueraient EN MEME TEMPS -- a priorite egale Roblox ne choisit pas, il MELANGE -- et on aurait une
-- echelle a moitie ouverte que personne n'a demandee. Une seule piste par echelle, gardee ici, rend ca impossible.
--
-- CE MODULE NE TOUCHE PAS AUX ANCRAGES, et c'est delibere. Portee, l'echelle est soudee au porteur et TOUTES ses
-- parts sont libres ; posee, sa racine est ancree. Deux etats opposes, tenus par deux services differents. Un
-- module qui reancrerait la racine "pour bien faire" figerait l'assemblage -- donc le joueur, puisqu'ils partagent
-- la meme soudure. Celui qui veut la pose "posee au sol" appelle `standAlone` LUI-MEME.
--
-- COTE SERVEUR POUR L'ANIMATION. Une anim jouee par un client sur l'echelle ne se replique PAS aux autres : ce
-- n'est pas son personnage. Le test de NOM, lui, sert aussi aux controllers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local LadderFoldUtils = {}

-- LE NOM DES ECHELLES, PARTOUT DANS LE JEU. C'est un PREFIXE : plusieurs peuvent coexister, numerotees.
--
-- DECLARE ICI ET NULLE PART AILLEURS. Il vivait en copie dans cinq fichiers, et une copie finit toujours par
-- diverger -- la copie rangee dans la benne du camion s'appelait "Ladder", donc AUCUN des services de l'echelle
-- ne la reconnaissait : on pouvait la sortir du camion et rien d'autre. Ni la prendre, ni y monter.
LadderFoldUtils.PREFIX = "Escabaut"
-- REPLIEE OU NON, lu par le client (il coupe la grimpe sur une echelle fermee).
LadderFoldUtils.CLOSED_ATTRIBUTE = "LeafiaLadderClosed"

local ANIM_FOLDER = { "Animations", "Tools", "Ladder", "ModelAnimate" }
local MODEL_ANIM = "ActionLadderAnimation"
local CLOSE_EVENT = "FermerEvenement" -- repliee : on fige la
local OPEN_EVENT = "LadderOpenEndEvent" -- depliee (fin) : on lache

-- UNE PISTE PAR ECHELLE, et les marqueurs branches une seule fois. Rebrancher a chaque repli empilerait les
-- connexions : au dixieme, dix fonctions se declencheraient sur le meme marqueur.
local tracks: { [Model]: AnimationTrack } = {}
local wired: { [Model]: boolean } = {}

--- UNE ECHELLE SE RECONNAIT A SON NOM, et a rien d'autre.
---
--- ON A ESSAYE DE LA RECONNAITRE A SA FORME -- "le seul modele de la benne qui porte un Humanoid" -- et la console
--- a montre que c'etait FAUX : le seau, la cisaille, le taille-haie et le rateau en ont un aussi, on leur jouait
--- donc l'anim de l'echelle. Tester la PRESENCE D'UN DETAIL pour repondre a une question d'IDENTITE attrape tout
--- ce qui partage ce detail.
function LadderFoldUtils.isLadder(inst: unknown): boolean
	if typeof(inst) ~= "Instance" or not (inst :: Instance):IsA("Model") then
		return false
	end
	local name = (inst :: Instance).Name
	return name:sub(1, #LadderFoldUtils.PREFIX) == LadderFoldUtils.PREFIX
end

local function resolveAnim(): Animation?
	local node: Instance = ReplicatedStorage
	for _, step in ANIM_FOLDER do
		local child = node:FindFirstChild(step)
		if not child then
			return nil
		end
		node = child
	end
	local anim = node:FindFirstChild(MODEL_ANIM)
	return if anim and anim:IsA("Animation") then anim else nil
end

--- YIELD. A appeler dans une tache a part, au demarrage du serveur.
---
--- Sans ca, le PREMIER repli de la session trouve l'asset pas encore charge : ses marqueurs ne tirent pas, la
--- piste va jusqu'au bout, et l'echelle finit DEPLIEE alors qu'on venait de la fermer.
function LadderFoldUtils.preload()
	local anim = resolveAnim()
	if not anim then
		warn(`[LadderFold] Animation "{MODEL_ANIM}" introuvable : l'echelle ne se pliera jamais.`)
		return
	end
	pcall(function()
		ContentProvider:PreloadAsync({ anim :: Animation })
	end)
end

--- LA RACINE DU RIG : la part que tout le reste suit.
---
--- ON NE SE FIE PAS A `PrimaryPart`, QUI EST FACULTATIF. Un modele sorti du 3D Importer n'en a normalement pas, et
--- une copie posee a la main dans une benne encore moins. Le vrai critere est dans les JOINTS : la racine est la
--- part qu'un Motor6D TIRE (elle est `Part0`) sans que personne ne la tire elle-meme (jamais `Part1`). Ca ne
--- suppose ni nom, ni rangement, ni reglage.
local function rootOf(model: Model): BasePart?
	local named = model.PrimaryPart or (model:FindFirstChild("RootPart") :: BasePart?)
	if named then
		return named
	end
	local driven: { [BasePart]: boolean } = {}
	local drivers: { [BasePart]: boolean } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			local joint = d :: Motor6D
			if joint.Part0 then
				drivers[joint.Part0 :: BasePart] = true
			end
			if joint.Part1 then
				driven[joint.Part1 :: BasePart] = true
			end
		end
	end
	for part in drivers do
		if not driven[part] then
			return part
		end
	end
	return nil
end

--- LA POSE "POSEE AU SOL" : racine ancree, tout le reste libre, et le Humanoid mis au repos.
---
--- LES DEUX EXTREMES TOMBENT, pour des raisons opposees. Tout ancre : une part ancree ignore son Motor6D, donc
--- l'anim tourne dans le vide et rien ne bouge. Tout libre : l'echelle s'ecroule. Il faut exactement ce partage.
---
--- LE HUMANOID EST MIS AU REPOS parce que le portage le fait deja, et que le portage MARCHE. Laisse dans son etat
--- normal, il fait tourner sa machine d'etat par-dessus l'anim : il essaie de tenir debout, et il repose des
--- `Transform` que la piste vient d'ecrire.
---
--- A N'APPELER QUE SUR UNE ECHELLE POSEE. Portee, elle est soudee au porteur et toutes ses parts sont libres :
--- reancrer la racine figerait l'assemblage entier, donc le joueur avec.
function LadderFoldUtils.standAlone(model: Model)
	local root = rootOf(model)
	if not root then
		warn(`[LadderFold] Aucune racine trouvee sur "{model.Name}" : je ne touche a rien, elle tomberait.`)
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local part = d :: BasePart
			part.Anchored = part == root
		elseif d:IsA("Humanoid") then
			local humanoid = d :: Humanoid
			humanoid.PlatformStand = true
			pcall(function()
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end)
		end
	end
end

local function animatorOf(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

--- La piste de CETTE echelle, chargee au besoin. `LoadAnimation` ne DEMARRE rien : la preparer d'avance ne peut
--- rien melanger, et ca evite que le premier geste attende le reseau.
function LadderFoldUtils.track(model: Model): AnimationTrack?
	local existing = tracks[model]
	if existing then
		return existing
	end
	local anim = resolveAnim()
	local animator = animatorOf(model)
	if not (anim and animator) then
		warn(
			`[LadderFold] "{model.Name}" ne peut pas s'animer : `
				.. `{if anim then "aucun Humanoid dans le modele" else "animation introuvable"}.`
		)
		return nil
	end
	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(anim :: Animation)
	end)
	if not (ok and typeof(result) == "Instance") then
		warn(`[LadderFold] Chargement de l'anim rate pour "{model.Name}".`)
		return nil
	end
	local loaded = result :: AnimationTrack
	loaded.Looped = false
	tracks[model] = loaded
	model.Destroying:Once(function()
		tracks[model] = nil
		wired[model] = nil
	end)
	return loaded
end

local function wire(model: Model, loaded: AnimationTrack)
	if wired[model] then
		return
	end
	wired[model] = true
	loaded:GetMarkerReachedSignal(CLOSE_EVENT):Connect(function()
		loaded:AdjustSpeed(0) -- fige repliee, aussi longtemps qu'il faudra
		model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, true)
		-- OU EXACTEMENT ON S'ARRETE, et sur quelle longueur. Si la pose figee n'a pas l'air assez fermee, c'est le
		-- MARQUEUR qui est pose trop tot dans l'editeur d'animation -- ces deux nombres le disent, et aucun reglage
		-- de code ne peut le corriger.
		print(
			`[LadderFold] "{model.Name}" figee a {string.format("%.2f", loaded.TimePosition)}s `
				.. `sur {string.format("%.2f", loaded.Length)}s (marqueur {CLOSE_EVENT}).`
		)
	end)
	loaded:GetMarkerReachedSignal(OPEN_EVENT):Connect(function()
		loaded:Stop(0.1)
		model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, false)
	end)
end

--- CE QUE LE MODULE VOIT DE CE MODELE. A afficher quand un repli ne donne rien : une sonde qui dit seulement "ca
--- n'a pas marche" ne designe personne, celle-ci nomme la piece qui manque.
function LadderFoldUtils.describe(model: Model): string
	local root = rootOf(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local joints = 0
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			joints += 1
		end
	end
	return `racine={if root then root.Name else "AUCUNE"} Humanoid={if humanoid then "oui" else "NON"} `
		.. `Motor6D={joints} piste={if tracks[model] then "chargee" else "AUCUNE"} `
		.. `anim={if resolveAnim() then "trouvee" else "INTROUVABLE"}`
end

--- REPLI : 0 -> `FermerEvenement`, puis on fige. Sans effet si elle est deja fermee ou en train de se fermer.
function LadderFoldUtils.fold(model: Model): boolean
	local loaded = LadderFoldUtils.track(model)
	if not loaded then
		return false
	end
	wire(model, loaded)
	if loaded.IsPlaying then
		return true -- deja repliee (figee au marqueur) ou en route : on ne repart pas de zero
	end
	loaded:Play(0)
	loaded.TimePosition = 0
	loaded:AdjustSpeed(1)
	return true
end

--- DEPLI : on REPART de la ou on avait fige, vers `LadderOpenEndEvent`. C'est la suite du meme geste, pas une
--- seconde animation -- d'ou l'absence de tout `Play` ici.
function LadderFoldUtils.unfold(model: Model)
	local loaded = tracks[model]
	if not (loaded and loaded.IsPlaying) then
		model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, false)
		return
	end
	loaded:AdjustSpeed(1)
end

--- COUPE SEC, sans depli : mort, respawn, depart du porteur. L'echelle reste dans la pose ou elle est.
function LadderFoldUtils.stop(model: Model)
	local loaded = tracks[model]
	if loaded then
		loaded:Stop(0)
	end
	model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, false)
end

return LadderFoldUtils
