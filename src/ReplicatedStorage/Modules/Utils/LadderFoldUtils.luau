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

local TruckConfigs = require(ReplicatedStorage.Modules.Configs.TruckConfigs)

local LadderFoldUtils = {}

-- LES DEUX NOMS D'UNE ECHELLE, DECLARES ICI ET NULLE PART AILLEURS.
--
-- `Escabaut` est un PREFIXE : les echelles de la carte sont numerotees. `Ladder` est le nom EXACT de la copie
-- rangee dans la benne du camion, et il ne se renomme pas : la barre du camion affiche le nom du modele tel quel,
-- donc l'appeler "Escabaut_Truck" ecrirait ca sur le bouton. Le nom sert a DEUX choses a la fois -- identifier
-- l'objet et l'annoncer au joueur -- et c'est l'affichage qui gagne : lui, le joueur le voit.
--
-- Le prefixe vivait en copie dans cinq fichiers. Une copie finit toujours par diverger, et c'est arrive : la
-- copie de la benne s'appelait "Ladder", donc AUCUN service de l'echelle ne la reconnaissait. On pouvait la sortir
-- du camion et rien d'autre -- ni la prendre, ni y monter, sans une seule erreur en console.
LadderFoldUtils.PREFIX = "Escabaut"
LadderFoldUtils.TRUCK_NAME = "Ladder"
-- REPLIEE OU NON, lu par le client (il coupe la grimpe sur une echelle fermee).
LadderFoldUtils.CLOSED_ATTRIBUTE = "LeafiaLadderClosed"

local ANIM_FOLDER = { "Animations", "Tools", "Ladder", "ModelAnimate" }
local MODEL_ANIM = "ActionLadderAnimation"
local CLOSE_EVENT = "FermerEvenement" -- repliee : on fige la
local OPEN_EVENT = "LadderOpenEndEvent" -- depliee (fin) : on lache
-- Delai avant de RELIRE l'etat des joints. Le marqueur tire pendant le calcul de l'image : les `Transform` de
-- cette image-la ne sont pas encore tous ecrits, et une lecture immediate croit voir un rig fige.
local REPORT_DELAY = 0.2

-- UNE PISTE PAR ECHELLE, et les marqueurs branches une seule fois. Rebrancher a chaque repli empilerait les
-- connexions : au dixieme, dix fonctions se declencheraient sur le meme marqueur.
local tracks: { [Model]: AnimationTrack } = {}
local wired: { [Model]: boolean } = {}

--- CE NOM EST-IL CELUI D'UNE ECHELLE ? Question de NOM SEUL : elle sert aussi pour des instances qui ne sont pas
--- des Models (invalidation de cache sur DescendantAdded, par exemple).
---
--- ON A ESSAYE DE LA RECONNAITRE A SA FORME -- "le seul modele de la benne qui porte un Humanoid" -- et la console
--- a montre que c'etait FAUX : le seau, la cisaille, le taille-haie et le rateau en ont un aussi, on leur jouait
--- donc l'anim de l'echelle. Tester la PRESENCE D'UN DETAIL pour repondre a une question d'IDENTITE attrape tout
--- ce qui partage ce detail.
function LadderFoldUtils.isLadderName(name: string): boolean
	return name:sub(1, #LadderFoldUtils.PREFIX) == LadderFoldUtils.PREFIX or name == LadderFoldUtils.TRUCK_NAME
end

--- RANGEE DANS LA BENNE, donc pas encore un objet du jardin.
---
--- Une echelle posee au sol se prend et se grimpe ; la meme echelle DANS le camion ne doit rien faire de tout ca.
--- Sans cette distinction, ouvrir le hayon ferait apparaitre une invite "prendre l'echelle" a cote de l'invite du
--- camion, pour une echelle qu'on n'a pas encore sortie.
function LadderFoldUtils.isStored(model: Model): boolean
	local folder = model:FindFirstAncestor(TruckConfigs.TOOLS_FOLDER)
	return folder ~= nil and folder:IsA("Folder")
end

--- UNE ECHELLE UTILISABLE : un Model, qui porte un nom d'echelle, et qui n'est pas encore range dans le camion.
--- C'est la question que se posent la prise, la grimpe et les zones.
function LadderFoldUtils.isLadder(inst: unknown): boolean
	if typeof(inst) ~= "Instance" or not (inst :: Instance):IsA("Model") then
		return false
	end
	local model = inst :: Model
	return LadderFoldUtils.isLadderName(model.Name) and not LadderFoldUtils.isStored(model)
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

--- LA RACINE DU RIG : la SEULE part qu'on a le droit d'ancrer, parce qu'aucun joint ne la tire.
---
--- LE CRITERE EST DANS LES JOINTS, ET NULLE PART AILLEURS : la racine est la part qu'un Motor6D tire (elle est
--- `Part0`) sans que personne ne la tire elle-meme (jamais `Part1`). Ca ne suppose ni nom, ni rangement, ni
--- reglage.
---
--- `PrimaryPart` ET LE NOM "RootPart" NE SONT QUE DES INDICES, et on les VERIFIE avant de les croire. Les deux
--- sont poses a la main, donc les deux peuvent designer une part qui est, elle aussi, tiree par un joint. L'ancrer
--- bloque alors CE joint et tout ce qui pend dessous : l'anim joue, les marqueurs tirent a l'heure, et l'echelle
--- ne se ferme qu'a moitie -- exactement le symptome qu'on cherchait. Le meme modele porte a la main se fermait
--- entierement, parce que la rien n'est ancre.
local function rootOf(model: Model): BasePart?
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
	local named = model.PrimaryPart or (model:FindFirstChild("RootPart") :: BasePart?)
	if named and not driven[named] then
		return named
	end
	if named then
		warn(
			`[LadderFold] "{model.Name}" : "{named.Name}" est TIREE par un joint, ce n'est pas la racine. `
				.. "L'ancrer bloquerait une partie du pliage ; je prends la vraie racine."
		)
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
--- l'anim tourne dans le vide et rien ne bouge. Tout libre : ce qu'aucun joint ne tient s'ecroule. La regle exacte
--- est donc : EST LIBRE CE QU'UN MOTOR6D TIRE, est ancre tout le reste. Pas "la racine et le reste libre" -- une
--- part qu'aucun joint ne pilote n'a rien pour la porter, la liberer ne fait que la faire tomber.
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
	local driven: { [BasePart]: boolean } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			local part = (d :: Motor6D).Part1
			if part then
				driven[part] = true
			end
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local part = d :: BasePart
			part.Anchored = not driven[part]
		elseif d:IsA("Humanoid") then
			local humanoid = d :: Humanoid
			humanoid.PlatformStand = true
			pcall(function()
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end)
		end
	end
end

--- COUPE (ou remet) LES SOUDURES DU MODELE, EN GARDANT CELLES QU'ON A TROUVEES DEJA COUPEES.
---
--- UNE SOUDURE GAGNE TOUJOURS CONTRE UN MOTOR6D. Deux parts reliees par un `WeldConstraint` forment un bloc
--- rigide : l'animation ecrit dans les joints, et il ne se passe RIEN -- pas d'erreur, pas de ralenti, juste une
--- echelle qui reste ouverte. Mesure a l'appui : les huit joints du rig etaient restes a l'identite pendant que la
--- piste tournait normalement jusqu'a son marqueur.
---
--- ON LES REMET APRES LE PLIAGE, et c'est le point delicat : un `WeldConstraint` capture l'ecart entre ses deux
--- parts AU MOMENT OU ON L'ACTIVE. Remise apres, la soudure tient donc la pose REPLIEE -- ce qu'on veut. Remise
--- avant, elle tiendrait l'ancienne.
function LadderFoldUtils.setWelds(model: Model, enabled: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("WeldConstraint") then
			(d :: WeldConstraint).Enabled = enabled
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

--- QUELS JOINTS N'ONT PAS BOUGE, et qu'est-ce qui les retient.
---
--- L'animation ecrit dans `Motor6D.Transform`. Un joint reste a l'identite pour exactement trois raisons : sa part
--- est ANCREE, elle est VERROUILLEE par une soudure (un `Weld` ou un `WeldConstraint` gagne contre un Motor6D,
--- toujours), ou la piste ne la cle pas du tout. On les NOMME au lieu de les compter : un compteur ne dit pas ou
--- regarder.
local function stuckJoints(model: Model): string
	local stuck = {}
	local locked = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			local joint = d :: Motor6D
			local part = joint.Part1
			if part and joint.Transform == CFrame.identity then
				table.insert(stuck, if part.Anchored then part.Name .. "(ancree)" else part.Name)
			end
		elseif d:IsA("WeldConstraint") then
			local weld = d :: WeldConstraint
			local a = if weld.Part0 then (weld.Part0 :: BasePart).Name else "?"
			local b = if weld.Part1 then (weld.Part1 :: BasePart).Name else "?"
			table.insert(locked, `{a}<->{b}{if weld.Enabled then "" else "(coupee)"}`)
		end
	end
	if #stuck == 0 and #locked == 0 then
		return "tous les joints ont bouge, aucune soudure"
	end
	return `joints figes = {if #stuck > 0 then table.concat(stuck, " ") else "aucun"} | `
		.. `soudures = {if #locked > 0 then table.concat(locked, " ") else "aucune"}`
end

local function wire(model: Model, loaded: AnimationTrack)
	if wired[model] then
		return
	end
	wired[model] = true
	loaded:GetMarkerReachedSignal(CLOSE_EVENT):Connect(function()
		loaded:AdjustSpeed(0) -- fige repliee, aussi longtemps qu'il faudra
		model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, true)
		-- LES SOUDURES REVIENNENT SUR LA POSE REPLIEE : un WeldConstraint capture l'ecart au moment ou on
		-- l'active, donc remis maintenant il tient l'echelle FERMEE.
		LadderFoldUtils.setWelds(model, true)
		-- ON MESURE APRES COUP, pas dans l'instant du marqueur : le marqueur tire PENDANT le calcul de l'image, et
		-- les `Transform` de cette image ne sont pas encore tous ecrits. Lu la, le rig a l'air fige meme quand il
		-- bouge tres bien -- une sonde qui accuse a tort coute plus cher que pas de sonde.
		task.delay(REPORT_DELAY, function()
			if model.Parent then
				print(
					`[LadderFold] "{model.Name}" figee a {string.format("%.2f", loaded.TimePosition)}s `
						.. `sur {string.format("%.2f", loaded.Length)}s (marqueur {CLOSE_EVENT}). `
						.. stuckJoints(model)
				)
			end
		end)
	end)
	loaded:GetMarkerReachedSignal(OPEN_EVENT):Connect(function()
		loaded:Stop(0.1)
		model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, false)
		LadderFoldUtils.setWelds(model, true) -- rouverte : la soudure tient la pose ouverte
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
	-- LES SOUDURES SAUTENT LE TEMPS DU GESTE. Elles gagnent contre les Motor6D : tant qu'elles tiennent, la piste
	-- joue et le rig ne bouge pas d'un millimetre. Elles reviennent au marqueur, sur la pose fermee.
	LadderFoldUtils.setWelds(model, false)
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
	LadderFoldUtils.setWelds(model, false)
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
