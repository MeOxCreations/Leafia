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
local RunService = game:GetService("RunService")

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

-- OU S'ARRETER, REGLABLE DANS STUDIO, en ATTRIBUT sur le modele de l'echelle.
--
-- Par defaut on fige au marqueur `FermerEvenement`, la ou l'animation dit que l'echelle est fermee. Si la pose
-- obtenue n'a pas l'air assez fermee, c'est le marqueur qui est pose trop tot, et ca se regle dans l'editeur
-- d'animation -- pas ici. En attendant, cet attribut permet de le verifier en trente secondes, sans toucher au
-- code :
--   * un nombre POSITIF  -> on continue jusqu'a CETTE seconde de l'animation, puis on fige ;
--   * -1                 -> on ne fige PAS, le geste entier se joue (fermeture puis reouverture). C'est la facon
--                           de VOIR ce que l'animation contient vraiment, sur l'echelle reelle et en jeu ;
--   * absent             -> le marqueur, comme avant.
local FOLD_STOP_ATTRIBUTE = "LeafiaFoldStop"

-- UNE PISTE PAR ECHELLE, et les marqueurs branches une seule fois. Rebrancher a chaque repli empilerait les
-- connexions : au dixieme, dix fonctions se declencheraient sur le meme marqueur.
-- L'ANIMATION QUI TIENT L'ECHELLE FERMEE, une pose et rien d'autre, bouclee.
--
-- POURQUOI UNE SECONDE ANIMATION plutot qu'un point d'arret dans la premiere. `ActionLadderAnimation` raconte le
-- geste ENTIER : elle ferme, puis elle rouvre. Aucun de ses reperes ne repond a "ou est-elle fermee" -- sa
-- derniere image est la pose OUVERTE, et son marqueur `FermerEvenement` est cale sur le geste du PORTEUR, donc
-- quelques centiemes avant la fermeture complete. Une animation dediee supprime la question au lieu de l'arbitrer.
LadderFoldUtils.CLOSED_ANIM = "rbxassetid://140251144922200"

local tracks: { [Model]: AnimationTrack } = {}
local closedTracks: { [Model]: AnimationTrack } = {}
local wired: { [Model]: boolean } = {}
-- LA BOUCLE QUI POUSSE LA LECTURE A LA MAIN, par echelle. Une seule a la fois : en relancer une sans couper la
-- precedente ferait avancer la piste deux fois plus vite, dans deux directions si elles s'opposent.
local runners: { [Model]: RBXScriptConnection } = {}
-- LA PIECE QUI TIENT L'ECHELLE EN L'AIR PENDANT LE GESTE, par echelle. Voir `holdInPlace`.
local holders: { [Model]: BasePart } = {}
local collide: { [Model]: { [BasePart]: boolean } } = {}
local HOLDER_NAME = "LeafiaFoldHolder"
-- On s'arrete un cheveu AVANT la fin : pile sur `Length`, la lecture reboucle.
local END_EPSILON = 0.001
-- COMBIEN D'IMAGES ON ESSAIE pour trouver la plus fermee. 60 sur une anim de 0.7s = une tous les centiemes, bien
-- plus fin que l'oeil. Le balayage ne tourne qu'au demarrage et au rangement, jamais en continu.
local SWEEP_STEPS = 60
-- Combien de temps on attend que l'animation soit telechargee avant d'abandonner.
local LENGTH_TIMEOUT = 10
-- Temps laisse au moteur pour poser la pose avant de la mesurer. Large : au demarrage, l'asset arrive du reseau.
local HOLD_SETTLE = 1

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
		closedTracks[model] = nil
		wired[model] = nil
		local run = runners[model]
		if run then
			run:Disconnect()
			runners[model] = nil
		end
	end)
	return loaded
end

--- QUELS JOINTS N'ONT PAS BOUGE, et qu'est-ce qui les retient.
---
--- L'animation ecrit dans `Motor6D.Transform`. Un joint reste a l'identite pour exactement trois raisons : sa part
--- est ANCREE, elle est VERROUILLEE par une soudure (un `Weld` ou un `WeldConstraint` gagne contre un Motor6D,
--- toujours), ou la piste ne la cle pas du tout. On les NOMME au lieu de les compter : un compteur ne dit pas ou
--- regarder.
--- L'ETAT DES PIECES AU MOMENT OU ON FIGE : ancrees, et soudures presentes.
---
--- ON NE REGARDE PLUS `Motor6D.Transform` DEPUIS UN SCRIPT SERVEUR. Elle rendait l'identite sur les huit joints
--- pendant que l'echelle se pliait POUR DE VRAI a l'ecran : la valeur lue la n'est pas la pose evaluee par le
--- moteur de rendu. Une sonde qui designe un coupable innocent coute plus cher que pas de sonde -- elle m'a fait
--- accuser une soudure, puis un rig, pendant que l'animation faisait tres bien son travail.
local function partsState(model: Model): string
	local anchored = {}
	local welds = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if (d :: BasePart).Anchored then
				table.insert(anchored, d.Name)
			end
		elseif d:IsA("WeldConstraint") then
			local weld = d :: WeldConstraint
			local a = if weld.Part0 then (weld.Part0 :: BasePart).Name else "?"
			local b = if weld.Part1 then (weld.Part1 :: BasePart).Name else "?"
			table.insert(welds, `{a}<->{b}{if weld.Enabled then "" else "(coupee)"}`)
		end
	end
	return `ancrees = {if #anchored > 0 then table.concat(anchored, " ") else "aucune"} | `
		.. `soudures = {if #welds > 0 then table.concat(welds, " ") else "aucune"}`
end

local function wire(model: Model, loaded: AnimationTrack)
	if wired[model] then
		return
	end
	wired[model] = true
	local function freeze()
		loaded:AdjustSpeed(0) -- fige repliee, aussi longtemps qu'il faudra
		model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, true)
		-- LES SOUDURES REVIENNENT SUR LA POSE REPLIEE : un WeldConstraint capture l'ecart au moment ou on
		-- l'active, donc remis maintenant il tient l'echelle FERMEE.
		LadderFoldUtils.setWelds(model, true)
		task.delay(REPORT_DELAY, function()
			if model.Parent then
				print(
					`[LadderFold] "{model.Name}" figee a {string.format("%.2f", loaded.TimePosition)}s `
						.. `sur {string.format("%.2f", loaded.Length)}s. `
						.. `poids={string.format("%.2f", loaded.WeightCurrent)} `
						.. partsState(model)
				)
			end
		end)
	end

	loaded:GetMarkerReachedSignal(CLOSE_EVENT):Connect(function()
		local stopAt = model:GetAttribute(FOLD_STOP_ATTRIBUTE)
		if typeof(stopAt) ~= "number" then
			freeze() -- le cas normal : l'animation dit elle-meme ou elle est fermee
			return
		end
		if stopAt < 0 then
			-- MODE OBSERVATION : on laisse le geste ENTIER se jouer. Utile pour voir, en jeu et sur l'echelle
			-- reelle, ou se trouve vraiment la pose fermee -- l'editeur d'animation ne montre pas le rig en place.
			print(
				`[LadderFold] "{model.Name}" : {FOLD_STOP_ATTRIBUTE} = -1, on ne fige pas. `
					.. `Le marqueur {CLOSE_EVENT} est a {string.format("%.2f", loaded.TimePosition)}s `
					.. `sur {string.format("%.2f", loaded.Length)}s.`
			)
			return
		end
		local extra = stopAt - loaded.TimePosition
		if extra <= 0 then
			freeze()
			return
		end
		print(
			`[LadderFold] "{model.Name}" : {FOLD_STOP_ATTRIBUTE} = {stopAt}s, on continue `
				.. `{string.format("%.2f", extra)}s apres le marqueur.`
		)
		task.delay(extra, freeze)
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

--- LES NOMS DES PIECES QUE L'ANIMATION VA CHERCHER, dans l'ordre du rig.
---
--- UNE ANIMATION RETROUVE LES MEMBRES PAR LE NOM DE LA `Part1` DE CHAQUE JOINT. Si aucun nom ne correspond, elle
--- joue avec un poids de 1, avance normalement, declenche ses marqueurs a l'heure -- et n'ecrit RIEN, sans la
--- moindre erreur. C'est exactement ce qu'on observe. Comparer les noms de DEUX rigs qui devraient etre identiques
--- repond en une ligne, et sans appel reseau (lire la KeyframeSequence en demande un, et il rate souvent au boot).
function LadderFoldUtils.rigParts(model: Model): string
	local names = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			local part = (d :: Motor6D).Part1
			table.insert(names, if part then part.Name else "?")
		end
	end
	table.sort(names)
	return table.concat(names, " ")
end

--- TENIR L'ECHELLE EXACTEMENT COMME LE PORTEUR LA TIENT, le temps du geste.
---
--- POURQUOI. Portee a la main, l'echelle se plie PARFAITEMENT ; rangee dans la benne, la meme animation sur le
--- meme modele ne fait rien. Il ne reste qu'une difference entre les deux situations : dans les mains, AUCUNE part
--- n'est ancree -- l'echelle est tenue par une soudure au porteur. Dans la benne, on ancrait sa racine.
---
--- On reproduit donc le montage qui marche, sans porteur : une petite part ANCREE, invisible, posee sur la racine,
--- et une soudure entre les deux. Tout le reste de l'echelle est libre, exactement comme dans les mains, et rien
--- ne tombe puisque l'assemblage pend a une part ancree.
local function holdInPlace(model: Model)
	if holders[model] then
		return
	end
	local root = rootOf(model)
	if not root then
		warn(`[LadderFold] Aucune racine sur "{model.Name}" : je ne peux pas la tenir pour l'animer.`)
		return
	end
	local holder = Instance.new("Part")
	holder.Name = HOLDER_NAME
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Anchored = true
	holder.CFrame = root.CFrame
	holder.Parent = model

	local weld = Instance.new("Weld")
	weld.Part0 = holder
	weld.Part1 = root
	weld.Parent = holder

	-- SEULES LES PIECES QU'UN JOINT TIRE SONT LIBEREES, plus la racine (tenue par notre soudure). Tout le reste --
	-- une zone de detection, un decor -- n'a rien a bouger : le liberer ne ferait que le faire tomber pendant qu'on
	-- coupe les soudures.
	local driven: { [BasePart]: boolean } = { [root] = true }
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			local part = (d :: Motor6D).Part1
			if part then
				driven[part] = true
			end
		end
	end
	local saved: { [BasePart]: boolean } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= holder and driven[d :: BasePart] then
			local part = d :: BasePart
			saved[part] = part.CanCollide
			part.Anchored = false
			part.CanCollide = false
		elseif d:IsA("Humanoid") then
			local humanoid = d :: Humanoid
			humanoid.PlatformStand = true
			pcall(function()
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end)
		end
	end
	holders[model] = holder
	collide[model] = saved
end

--- Fin du geste : on retire la piece qui tenait, on rend les collisions, on re-ancre ce qu'aucun joint ne tire.
local function releaseHold(model: Model)
	local holder = holders[model]
	if not holder then
		return
	end
	holders[model] = nil
	holder:Destroy() -- emporte la soudure, qui est son enfant
	local saved = collide[model]
	collide[model] = nil
	if saved then
		for part, value in saved do
			if part.Parent then
				part.CanCollide = value
			end
		end
	end
	LadderFoldUtils.standAlone(model)
end

local function stopRunner(model: Model)
	local run = runners[model]
	if run then
		run:Disconnect()
		runners[model] = nil
	end
end

--- TENIR L'ECHELLE FERMEE, INDEFINIMENT, avec l'animation qui ne fait que ca.
---
--- C'est le repli du camion : une echelle rangee reste fermee tant qu'on ne la sort pas. La piste est BOUCLEE et
--- ne contient que la pose fermee, donc il n'y a ni fin a rattraper, ni marqueur a viser, ni image a chercher.
---
--- ON MESURE L'ENCOMBREMENT a trois moments : avant, pendant qu'on la tient comme un porteur, et apres l'avoir
--- reposee sur sa racine ancree. C'est la seule sonde d'animation qui ne mente pas, et elle repond aux deux seules
--- questions qui restent -- est-ce que l'anim s'applique, et est-ce que la reancrer la casse.
function LadderFoldUtils.holdClosed(model: Model): boolean
	local animator = animatorOf(model)
	if not animator then
		warn(`[LadderFold] "{model.Name}" n'a pas de Humanoid : rien ne peut l'animer.`)
		return false
	end
	local existing = closedTracks[model]
	if existing then
		if not existing.IsPlaying then
			existing:Play(0)
		end
		return true
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = LadderFoldUtils.CLOSED_ANIM
	local ok, result = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if not (ok and typeof(result) == "Instance") then
		warn(`[LadderFold] Animation fermee ({LadderFoldUtils.CLOSED_ANIM}) non chargeable sur "{model.Name}".`)
		return false
	end
	local closed = result :: AnimationTrack
	closed.Looped = true
	closed.Priority = Enum.AnimationPriority.Action
	closedTracks[model] = closed

	-- UNE SEULE PISTE SUR CE RIG. A priorite egale Roblox ne choisit pas, il MELANGE : la piste du geste complet
	-- et celle de la pose fermee donneraient une echelle a moitie ouverte que personne n'a demandee.
	local other = tracks[model]
	if other then
		other:Stop(0)
	end
	stopRunner(model)
	-- LES SOUDURES SAUTENT : une soudure gagne contre un Motor6D, le rig ne bougerait pas d'un millimetre.
	LadderFoldUtils.setWelds(model, false)
	holdInPlace(model)

	local before = model:GetExtentsSize()
	closed:Play(0)
	task.delay(HOLD_SETTLE, function()
		if not model.Parent then
			return
		end
		local held = model:GetExtentsSize()
		releaseHold(model)
		LadderFoldUtils.setWelds(model, true)
		model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, true)
		task.delay(HOLD_SETTLE, function()
			if not model.Parent then
				return
			end
			local after = model:GetExtentsSize()
			local function box(v: Vector3): string
				return string.format("%.1f/%.1f/%.1f", v.X, v.Y, v.Z)
			end
			print(
				`[LadderFold] "{model.Name}" fermee : encombrement {box(before)} -> tenue {box(held)} -> `
					.. `posee {box(after)}. piste={string.format("%.2f", closed.Length)}s `
					.. `poids={string.format("%.2f", closed.WeightCurrent)}`
			)
			if (held - before).Magnitude < 0.05 then
				warn(
					`[LadderFold] "{model.Name}" N'A PAS BOUGE. Une animation retrouve les pieces PAR LEUR NOM : `
						.. `si les pistes de l'animation ne portent pas les memes noms que les pieces du rig, elle `
						.. `joue et n'ecrit rien. Pieces de ce rig : {LadderFoldUtils.rigParts(model)}`
				)
			end
		end)
	end)
	return true
end

--- LA FERMER MAINTENANT, sans ceremonie ni mesure : on la voit se replier tout de suite.
---
--- SERT AVANT LE TRAJET DE RANGEMENT. `holdClosed` mesure et rend la main une seconde plus tard, ce qui tombe en
--- plein vol -- il reancrerait des pieces pendant que le modele se deplace. Ici on ferme, et l'appelant reprend la
--- main quand il veut avec `settle`.
function LadderFoldUtils.closeNow(model: Model): boolean
	local animator = animatorOf(model)
	if not animator then
		return false
	end
	local closed = closedTracks[model]
	if not closed then
		local anim = Instance.new("Animation")
		anim.AnimationId = LadderFoldUtils.CLOSED_ANIM
		local ok, result = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		if not (ok and typeof(result) == "Instance") then
			return false
		end
		closed = result :: AnimationTrack
		closed.Looped = true
		closed.Priority = Enum.AnimationPriority.Action
		closedTracks[model] = closed
	end
	local other = tracks[model]
	if other then
		other:Stop(0) -- deux pistes sur le meme rig se melangent
	end
	stopRunner(model)
	LadderFoldUtils.setWelds(model, false)
	holdInPlace(model)
	;(closed :: AnimationTrack):Play(0)
	model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, true)
	return true
end

--- LA TENIR, ET RENDRE LA PIECE QUI LA TIENT.
---
--- Deplacer CETTE piece deplace toute l'echelle -- elle y est soudee -- SANS ancrer ses morceaux, donc sans
--- empecher l'animation de jouer. C'est ce qui permet de l'ouvrir EN PLEIN TRAJET : un modele dont on ancre les
--- parts pour le transporter ne peut plus s'animer du tout.
function LadderFoldUtils.hold(model: Model): BasePart?
	holdInPlace(model)
	return holders[model]
end

--- La racine du rig, pour qui a besoin de la piloter lui-meme.
function LadderFoldUtils.rootPart(model: Model): BasePart?
	return rootOf(model)
end

--- FIN DE LA TENUE : on retire la piece qui tenait l'echelle en l'air et on remet ses soudures. A appeler quand on
--- reprend la main sur le modele -- juste avant de le deplacer, par exemple.
function LadderFoldUtils.settle(model: Model)
	releaseHold(model)
	LadderFoldUtils.setWelds(model, true)
end

--- L'ECHELLE SORT DU CAMION : on lache la pose fermee, elle reprend sa forme ouverte.
function LadderFoldUtils.releaseClosed(model: Model)
	local closed = closedTracks[model]
	if closed then
		closed:Stop(0.15)
	end
	model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, false)
end

--- REPLI : ON CHERCHE L'IMAGE OU L'ECHELLE EST LA PLUS FERMEE, ET ON LA TIENT.
---
--- POURQUOI ON LA CHERCHE AU LIEU DE LA CONNAITRE. L'animation raconte tout le geste d'un bloc : elle FERME, puis
--- elle ROUVRE. Sa derniere image est donc la pose OUVERTE -- s'arreter au bout referme puis rouvre l'echelle sous
--- les yeux du joueur, ce qui est exactement ce qu'on a vu. Et le marqueur `FermerEvenement` ne vaut pas mieux ici :
--- il est pose pour le PORTAGE, ou il doit tomber pile sur le geste du personnage, quelques centiemes avant la
--- fermeture complete. Deux reperes, aucun des deux ne repond a la question "quand est-elle le plus fermee".
---
--- ALORS ON MESURE. On parcourt la piste image par image et on garde celle ou l'ENCOMBREMENT du modele est le plus
--- petit : une echelle repliee occupe forcement moins de place qu'une echelle ouverte. Ca ne suppose rien de
--- l'animation, ca se refait tout seul si elle est remontee, et ca ne peut pas se tromper de quelques centiemes
--- comme un marqueur pose a la main.
---
--- `LeafiaFoldStop` sur le modele force un temps precis, si jamais on veut autre chose que le plus ferme.
---
--- YIELD (le balayage prend une image par echantillon). Lance dans sa propre tache.
function LadderFoldUtils.foldTightest(model: Model): boolean
	local loaded = LadderFoldUtils.track(model)
	if not loaded then
		return false
	end
	stopRunner(model)
	-- LES SOUDURES SAUTENT LE TEMPS DU GESTE : une soudure gagne contre un Motor6D, l'echelle ne bougerait pas.
	LadderFoldUtils.setWelds(model, false)
	holdInPlace(model)
	loaded.Looped = true -- sinon la piste se RELACHE au bout et la pose tenue saute
	loaded:Play(0)
	loaded:AdjustSpeed(0) -- on pilote la lecture a la main : aucune chance de reboucler

	task.spawn(function()
		-- La longueur n'est connue qu'une fois l'asset arrive.
		local deadline = os.clock() + LENGTH_TIMEOUT
		while loaded.Length <= 0 and os.clock() < deadline do
			RunService.Heartbeat:Wait()
		end
		local length = loaded.Length
		if length <= 0 or not model.Parent then
			warn(`[LadderFold] "{model.Name}" : animation jamais chargee, elle restera ouverte.`)
			releaseHold(model)
			LadderFoldUtils.setWelds(model, true)
			return
		end

		local before = model:GetExtentsSize()
		local best = 0
		local override = model:GetAttribute(FOLD_STOP_ATTRIBUTE)
		if typeof(override) == "number" and override >= 0 then
			best = math.min(override, length - END_EPSILON)
		else
			local smallest = math.huge
			for i = 0, SWEEP_STEPS do
				loaded.TimePosition = (i / SWEEP_STEPS) * (length - END_EPSILON)
				RunService.Heartbeat:Wait() -- laisser le moteur poser la pose avant de la mesurer
				if not model.Parent then
					return
				end
				local size = model:GetExtentsSize().Magnitude
				if size < smallest then
					smallest = size
					best = loaded.TimePosition
				end
			end
		end

		loaded.TimePosition = best
		RunService.Heartbeat:Wait()
		local after = model:GetExtentsSize()
		releaseHold(model)
		model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, true)
		-- LES SOUDURES REVIENNENT SUR LA POSE FERMEE : un WeldConstraint capture l'ecart entre ses deux parts au
		-- moment ou on l'active, donc remis maintenant il tient l'echelle repliee.
		LadderFoldUtils.setWelds(model, true)
		local shrunk = before.Magnitude - after.Magnitude
		print(
			`[LadderFold] "{model.Name}" tenue a {string.format("%.2f", best)}s sur `
				.. `{string.format("%.2f", length)}s. encombrement `
				.. `{string.format("%.1f/%.1f/%.1f", before.X, before.Y, before.Z)} -> `
				.. `{string.format("%.1f/%.1f/%.1f", after.X, after.Y, after.Z)} `
				.. `({if shrunk < 0.05 then "RIEN N'A BOUGE" else `elle a rapetisse de {string.format("%.1f", shrunk)}`}). `
				.. partsState(model)
		)
	end)
	return true
end

--- REOUVERTURE : on REMONTE la meme piste jusqu'a sa premiere image, puis on la lache. Pas une seconde animation
--- et pas un saut : le geste inverse, c'est le meme geste a l'envers.
function LadderFoldUtils.unfoldFromEnd(model: Model)
	local loaded = tracks[model]
	if not (loaded and loaded.IsPlaying) then
		model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, false)
		return
	end
	stopRunner(model)
	LadderFoldUtils.setWelds(model, false)
	holdInPlace(model)
	runners[model] = RunService.Heartbeat:Connect(function(dt: number)
		if not model.Parent then
			stopRunner(model)
			releaseHold(model)
			return
		end
		local next = math.max(loaded.TimePosition - dt, 0)
		loaded.TimePosition = next
		if next > 0 then
			return
		end
		stopRunner(model)
		loaded:Stop(0)
		releaseHold(model)
		model:SetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE, false)
		LadderFoldUtils.setWelds(model, true)
	end)
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
	-- ON REPREND LA PISTE A NOTRE COMPTE. `foldToEnd` la laisse en `Looped = true` et pilotee a la main : reprendre
	-- une lecture normale par-dessus la ferait reboucler au debut au lieu de s'arreter.
	stopRunner(model)
	local closed = closedTracks[model]
	if closed then
		closed:Stop(0) -- deux pistes sur le meme rig se melangent
	end
	loaded.Looped = false
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
