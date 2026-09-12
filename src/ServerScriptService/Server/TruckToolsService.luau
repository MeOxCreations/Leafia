--!strict
-- SORTIR UN OUTIL DE LA BENNE. Le joueur clique dans l'interface, l'objet QUITTE le camion, vole en arc, et se
-- pose sur le terrain.
--
-- COTE SERVEUR PARCE QUE L'OBJET EST REEL. Il n'est pas fabrique pour l'occasion : c'est le modele range dans la
-- benne, celui qu'on voit par le hayon ouvert. Il doit donc quitter le camion CHEZ TOUT LE MONDE -- un vol joue
-- chez le client laisserait l'outil dans la benne pour les autres, et deux joueurs ne verraient pas le meme
-- camion.
--
-- ET C'EST AUSSI CE QUI SERT DE GARDE : le client envoie un NOM, le serveur retrouve le modele lui-meme dans le
-- dossier prevu. Un client modifie ne peut donc designer que ce qui est dans la benne -- pas la maison du
-- grand-pere.
--
-- LE VOL EST UNE COURBE DE BEZIER a trois points : depart, sommet, arrivee. Une ligne droite ne se lit pas comme
-- un objet qu'on SORT mais comme un objet qui glisse ; l'arc dit qu'il a ete souleve et pose.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)
local LadderFoldUtils = require(ReplicatedStorage.Modules.Utils.LadderFoldUtils)
-- VOISIN DIRECT, pas un detour par un remote : c'est le camion qui DEPLACE l'echelle, donc c'est a lui de dire
-- quand elle s'est posee. Ses zones de grimpe se calculent depuis le sol sous elle, elles ne peuvent pas se faire
-- avant l'atterrissage.
local LadderZoneService = require(script.Parent.LadderZoneService)
local TruckConfigs = require(ReplicatedStorage.Modules.Configs.TruckConfigs)
local BinConfigs = require(ReplicatedStorage.Modules.Configs.BinConfigs)
local MowConfigs = require(ReplicatedStorage.Modules.Configs.MowConfigs)

local TruckToolsService = {}

-- LES OUTILS EN VOL, pour ne pas en lancer deux fois le meme. Le modele quitte son dossier des le depart, donc il
-- n'est deja plus proposable -- mais deux clics dans la meme image arriveraient avant, et le second trouverait
-- encore l'outil en place.
local flying: { [Model]: boolean } = {}

-- Delai avant de VERIFIER que l'echelle de la benne s'est bien repliee. Large : l'anim dure moins d'un quart de
-- seconde, mais son telechargement peut trainer au demarrage d'un serveur.
local LADDER_CHECK_DELAY = 5

--- Le camion, ou nil. Re-cherche a chaque fois plutot que garde : avec le streaming il arrive apres le boot, et
--- une reference resolue une seule fois resterait vide pour toute la session.
local function findTruck(): Model?
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and d.Name == TruckConfigs.MODEL_NAME then
			return d :: Model
		end
	end
	return nil
end

--- OU L'OUTIL DOIT SE POSER : la part qui porte son nom, dans le dossier des arrivees.
---
--- UNE PART ET PAS UN POINT : son ORIENTATION compte autant que sa position. Un rateau pose de travers a l'air
--- tombe, pas depose -- et c'est une chose qui se regle a la souris, pas dans un fichier.
local function findDropPoint(toolName: string): BasePart?
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Folder") and d.Name == TruckConfigs.DROP_FOLDER then
			local part = (d :: Folder):FindFirstChild(toolName)
			if part and part:IsA("BasePart") then
				return part :: BasePart
			end
		end
	end
	return nil
end

--- La pose d'arrivee : celle du point prevu, ou devant le joueur faute de mieux.
local function landingFor(toolName: string, player: Player): CFrame?
	local point = findDropPoint(toolName)
	if point then
		return point.CFrame
	end
	-- UN OUTIL EQUIPABLE N'A PAS DE PLACE AU SOL, et c'est normal : il va dans l'inventaire, et son vol finit
	-- invisible. On le fait donc arriver DEVANT LE JOUEUR -- le geste se lit comme "il vient a moi" -- et on ne
	-- dit rien, parce qu'il n'y a rien a corriger.
	--
	-- POUR LE SEAU ET L'ECHELLE, EN REVANCHE, C'EST UN OUBLI : ils restent sur le terrain, on va les y chercher,
	-- donc leur place compte. On le DIT, sinon un objet qui atterrit devant le joueur au lieu de sa place
	-- passerait pour un choix.
	if not TruckConfigs.TOOL_EQUIP[toolName] then
		warn(
			`[TruckToolsService] Aucune part "{toolName}" dans un dossier "{TruckConfigs.DROP_FOLDER}" : `
				.. "il se posera devant le joueur. Rojo ne synchronise pas le Workspace."
		)
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return nil
	end
	local root = hrp :: BasePart
	local ahead = root.Position + root.CFrame.LookVector * TruckConfigs.DROP_FALLBACK_DIST
	-- A PLAT : on garde le cap du joueur mais pas son tangage, sinon l'outil se pose penche quand il regarde ses
	-- pieds ou le ciel.
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return CFrame.new(ahead)
	end
	return CFrame.lookAt(ahead, ahead + flat.Unit)
end

--- UN OUTIL SORTI DU CAMION, par son nom. On le reconnait a la pose qu'il a gardee : elle dit d'ou il vient.
---
--- ON BALAYE PLUTOT QUE DE TENIR UNE LISTE. Une liste serait un second etat a garder d'accord avec le monde, et
--- elle mentirait le jour ou un outil est detruit, deplace, ou pose par un autre chemin -- alors que la marque,
--- elle, voyage AVEC l'objet.
local function findTakenTool(toolName: string): Model?
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and d.Name == toolName and d:GetAttribute(TruckConfigs.POSE_ATTRIBUTE) ~= nil then
			return d :: Model
		end
	end
	return nil
end

--- Quelqu'un le PORTE-T-IL ? On ne range pas un objet qui est dans les mains de quelqu'un : il partirait en vol
--- en restant soude au porteur, qui se retrouverait a courir apres son propre seau.
---
--- Les deux attributs sont ceux que posent les services de portage. On les LIT depuis leurs configs plutot que
--- d'ecrire les noms ici : une chaine recopiee finit toujours par diverger de son original.
local function isHeld(model: Model): boolean
	return model:GetAttribute(MowConfigs.CARRIED_ATTRIBUTE) ~= nil
		or model:GetAttribute(BinConfigs.CARRIED_ATTRIBUTE) ~= nil
end

--- Un point sur la courbe de Bezier quadratique, de `a` a `c` en passant pres de `b`.
local function bezier(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	local u = 1 - t
	return a * (u * u) + b * (2 * u * t) + c * (t * t)
end

-- ===== UN OUTIL QUI S'EQUIPE NE RESTE PAS PAR TERRE =====
-- Sorti de la benne, un outil equipable entre dans l'INVENTAIRE : c'est le menu en bas a gauche qui le porte, et
-- ToolService en met un exemplaire dans la main quand on l'equipe. Le laisser visible au sol le montrerait donc
-- DEUX FOIS -- par terre et dans les mains -- et obligerait a lui trouver une place sur le terrain alors qu'il
-- n'y en a pas besoin. Seuls le seau et l'echelle, qu'on va CHERCHER et qu'on PORTE, ont une place au sol.
--
-- ON LE REND INVISIBLE, ON NE LE DETRUIT PAS. Trois raisons, et chacune tient a elle seule. Il garde sa MARQUE,
-- donc le menu continue de savoir qu'on le possede. Le camion peut toujours le REPRENDRE, avec sa pose d'origine
-- intacte. Et il n'y a aucun etat de possession a tenir ailleurs : l'objet EST la preuve.
--
-- LES VALEURS D'ORIGINE SONT GARDEES : une part peut etre deja semi-transparente ou deja traversable, et les
-- remettre "a zero" les abimerait. On restitue ce qu'on a trouve, pas ce qu'on suppose.
local hidden: { [Model]: { [BasePart]: { transparency: number, collide: boolean, query: boolean } } } = {}

local function setToolHidden(model: Model, hide: boolean)
	if hide then
		if hidden[model] then
			return
		end
		local saved: { [BasePart]: { transparency: number, collide: boolean, query: boolean } } = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local part = d :: BasePart
				saved[part] = { transparency = part.Transparency, collide = part.CanCollide, query = part.CanQuery }
				part.Transparency = 1
				part.CanCollide = false
				part.CanQuery = false
			end
		end
		hidden[model] = saved
		return
	end
	local saved = hidden[model]
	if not saved then
		return
	end
	hidden[model] = nil
	for part, was in saved do
		if part.Parent then
			part.Transparency = was.transparency
			part.CanCollide = was.collide
			part.CanQuery = was.query
		end
	end
end

--- FAIT SORTIR `model` DU CAMION et le pose a `landing`.
---
--- IL EST ANCRE PENDANT TOUT LE VOL, et repose ancre a l'arrivee : un modele desancre tombe, rebondit, et finit
--- ou la physique veut -- alors qu'on lui a choisi une place. Les objets qu'on PORTE seront desancres par leur
--- propre systeme quand on les prendra.
--- UNE PART DE L'OBJET, pour y accrocher un son. Sa PrimaryPart si elle existe, sinon n'importe laquelle : le
--- bruit doit venir de l'objet, et a cette distance le joueur n'entend pas de quelle piece exactement.
local function soundHost(model: Model): BasePart?
	local primary = model.PrimaryPart
	if primary then
		return primary
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

--- SORT L'OBJET DE LA BENNE ET L'Y REMET, sans vol, sans bruit, sans que personne ne le voie.
---
--- POURQUOI CETTE BIZARRERIE EXISTE. Au demarrage, le repli de l'echelle rangee dans la benne ne se jouait qu'A
--- MOITIE. Le MEME repli, sur la MEME echelle, joue entierement des qu'on l'a sortie du camion puis remise -- le
--- joueur l'a verifie, et c'est la seule mesure qu'on ait. J'ai propose plusieurs causes a ce qui differe entre
--- les deux chemins (ancrages, soudures, etat du Humanoid) sans reussir a en prouver une seule ; reproduire le
--- chemin qui MARCHE bat une explication qu'on n'a pas.
---
--- CE QUE CA REFAIT, exactement comme le retour d'un vol : tout ancrer, quitter le dossier, y revenir, se reposer
--- a sa place. Avec une image d'attente a chaque etape -- si la difference tient a ce que le moteur refait
--- l'assemblage, elle ne peut pas se produire dans la meme image.
---
--- YIELD. A appeler dans une tache a part.
local function resetInPlace(model: Model, home: Instance)
	local pose = model:GetPivot()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			(d :: BasePart).Anchored = true
		end
	end
	model.Parent = Workspace
	task.wait()
	model.Parent = home
	model:PivotTo(pose)
	task.wait()
end

local function fly(model: Model, landing: CFrame, home: Instance?)
	flying[model] = true
	local from = model:GetPivot()
	local host = soundHost(model)
	-- VISIBLE PENDANT TOUT LE VOL, quoi qu'il arrive ensuite. Un outil equipable ressorti de l'inventaire part
	-- invisible sinon : on cliquerait "ranger" et rien ne bougerait a l'ecran.
	setToolHidden(model, false)
	-- IL SIFFLE EN PARTANT. Le son est porte par l'objet, donc il le SUIT : il quitte le camion avec lui et
	-- arrive avec lui -- alors qu'un son pose sur le camion resterait derriere.
	if host then
		SoundUtils.play(TruckConfigs.FLY_SOUND, host)
	end
	-- LE SOMMET EST AU MILIEU, REMONTE. C'est lui qui fait l'arc, et le calculer depuis les deux bouts le garde
	-- juste ou que soit le camion : un sommet ecrit en dur ne vaudrait que pour une seule carte.
	local middle = (from.Position + landing.Position) * 0.5 + Vector3.new(0, TruckConfigs.FLY_ARC_HEIGHT, 0)
	local spin = math.rad(360 * TruckConfigs.FLY_SPINS)

	-- ON L'ANCRE ET ON LE SORT DU CAMION. Tant qu'il est enfant du modele, il suit la carrosserie -- et il
	-- resterait "range" pour l'interface, qui lit le contenu du dossier.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			(d :: BasePart).Anchored = true
		end
	end
	model.Parent = Workspace

	task.spawn(function()
		local t0 = os.clock()
		while true do
			local e = math.clamp((os.clock() - t0) / TruckConfigs.FLY_TIME, 0, 1)
			if not model.Parent then
				flying[model] = nil
				return -- detruit en vol : plus rien a poser
			end
			local pos = bezier(from.Position, middle, landing.Position, e)
			-- IL TOURNE EN VOLANT, PUIS IL SE REDRESSE. Un objet qui garde son angle tout du long a l'air tire
			-- par une ficelle ; un tour sur lui-meme dit qu'il a ete LANCE. Mais il doit arriver DROIT, sinon il
			-- se pose a l'angle ou le hasard du tour l'a laisse -- donc sur la fin, sa rotation revient vers
			-- celle du point d'arrivee.
			local turned = from.Rotation * CFrame.Angles(0, spin * e, 0)
			local settle = TruckConfigs.FLY_SETTLE_FROM
			local rot = if e <= settle
				then turned
				else turned:Lerp(landing.Rotation, (e - settle) / math.max(1 - settle, 1e-3))
			model:PivotTo(CFrame.new(pos) * rot.Rotation)
			if e >= 1 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		model:PivotTo(landing)
		-- ET IL SE POSE, avec le bruit qui va avec. A la FIN, pas au depart : un choc qui precede l'atterrissage
		-- se lit comme un autre objet, ailleurs.
		if host and host.Parent then
			SoundUtils.play(TruckConfigs.DROP_SOUND, host)
		end
		-- ET IL RENTRE DANS LA BENNE, a la FIN du vol seulement. Range avant, il suivrait la carrosserie pendant
		-- qu'il vole encore -- il arriverait donc a cote de sa place si le camion bouge.
		if home and home.Parent then
			model.Parent = home
			-- LA MARQUE PART AVEC LUI : il n'est plus "sorti", donc l'interface le remontre comme a prendre. C'est
			-- la meme information qui sert aux deux sens, il n'y a rien a tenir d'accord.
			model:SetAttribute(TruckConfigs.POSE_ATTRIBUTE, nil)
		elseif TruckConfigs.TOOL_EQUIP[model.Name] then
			-- IL DISPARAIT A L'ARRIVEE : il est dans l'inventaire, pas sur la pelouse. Le vol reste VU -- c'est lui
			-- qui dit "tu viens de le prendre" -- et seule la pose finale s'efface.
			setToolHidden(model, true)
		end
		-- L'ECHELLE SE PLIE POUR RENTRER, ET S'OUVRE EN ARRIVANT AU SOL. Une echelle se range fermee dans une
		-- benne, et ne sert a rien fermee sur une pelouse : c'est la MEME regle que le portage, ou elle se referme
		-- dans les mains et se rouvre des qu'on la pose.
		--
		-- APRES LE VOL, pas avant : le trajet ancre toutes ses parts pour que rien ne tombe en route, et une part
		-- ancree ignore son Motor6D. Repliee pendant le vol, elle arriverait donc figee dans la pose du depart.
		if LadderFoldUtils.isLadderName(model.Name) then
			-- LE VOL A TOUT ANCRE pour que rien ne tombe en route, et une part ancree ignore son Motor6D. On lui
			-- rend donc sa pose "posee au sol" AVANT de l'animer, sinon la piste tourne dans le vide.
			LadderFoldUtils.standAlone(model)
			if home and home.Parent then
				LadderFoldUtils.foldToEnd(model)
			else
				LadderFoldUtils.unfoldFromEnd(model)
			end
			-- SES ZONES SE REFONT ICI, une fois posee. Avant l'atterrissage, le rayon vers le sol tape le camion.
			LadderZoneService.refresh(model)
		end
		flying[model] = nil
	end)
end

function TruckToolsService.init()
	local remote = RemoteSetup.getRemote("TakeTruckTool", "Truck") :: RemoteEvent

	remote.OnServerEvent:Connect(function(player, toolName)
		-- LE CLIENT MENT TOUJOURS : on ne prend que ce qui est une chaine, et on ne s'en sert que comme d'une CLE
		-- dans le dossier du camion. Tout le reste -- ou est l'outil, ou il va -- est decide ici.
		if type(toolName) ~= "string" then
			return
		end
		local truck = findTruck()
		if not truck then
			return
		end
		-- LA PORTE DOIT ETRE OUVERTE. Le client ne montre l'interface que dans ce cas, mais un client modifie
		-- pourrait envoyer le remote sans elle : on ne fait pas confiance a l'affichage pour garder une regle.
		if truck:GetAttribute(TruckConfigs.OPEN_ATTRIBUTE) ~= true then
			return
		end
		local folder = truck:FindFirstChild(TruckConfigs.TOOLS_FOLDER)
		if not folder then
			warn(
				`[TruckToolsService] Aucun dossier "{TruckConfigs.TOOLS_FOLDER}" dans "{truck.Name}" : `
					.. "il n'y a rien a sortir. Rojo ne synchronise pas le Workspace."
			)
			return
		end
		-- UN SEUL CLIC, DEUX SENS : c'est la PLACE de l'objet qui decide. S'il est encore dans la benne, on le
		-- sort ; s'il en est deja sorti, on l'y remet. Le client n'a donc rien a savoir de l'etat des choses -- il
		-- designe un outil, et le serveur fait ce qui a du sens pour lui.
		local found = folder:FindFirstChild(toolName :: string)
		if found and found:IsA("Model") then
			-- SORTI EN VARIABLE, et pas `(found :: Model)` en debut de ligne : une instruction qui commence par une
			-- parenthese se lit comme la SUITE de la ligne du dessus, donc comme un appel de fonction. Piege deja
			-- paye dans ce projet.
			local inside = found :: Model
			if flying[inside] then
				return
			end
			local landing = landingFor(toolName :: string, player)
			if not landing then
				return -- pas de place connue et pas de personnage : on ne pose pas un objet nulle part
			end
			-- ON RETIENT SA POSE AVANT DE LE SORTIR, en repere du camion : c'est elle qui le ramenera exactement
			-- la, a l'angle pres, et elle reste juste meme si le camion bouge entre-temps.
			inside:SetAttribute(TruckConfigs.POSE_ATTRIBUTE, truck:GetPivot():ToObjectSpace(inside:GetPivot()))
			print(`[TruckToolsService] {player.Name} sort "{toolName}" du camion.`)
			fly(inside, landing :: CFrame)
			return
		end

		-- IL EST DEHORS : on le range. Sa pose d'origine est sur lui, en repere du camion.
		local out = findTakenTool(toolName :: string)
		if not out then
			return
		end
		local taken = out :: Model
		if flying[taken] then
			return
		end
		if isHeld(taken) then
			-- QUELQU'UN LE PORTE. Le faire voler le laisserait soude a lui : le porteur se mettrait a courir apres
			-- son propre seau. On refuse en silence -- le joueur voit l'objet dans ses mains, il n'a pas besoin
			-- qu'on le lui dise.
			return
		end
		local pose = taken:GetAttribute(TruckConfigs.POSE_ATTRIBUTE)
		if typeof(pose) ~= "CFrame" then
			return
		end
		print(`[TruckToolsService] {player.Name} range "{toolName}" dans le camion.`)
		fly(taken, truck:GetPivot() * (pose :: CFrame), folder)
	end)

	-- L'ECHELLE QUI DORT DEJA DANS LA BENNE EST REPLIEE, avant que personne n'y touche. Elle est POSEE ouverte
	-- dans Studio -- c'est sa seule pose editable, la fermeture n'existe que dans l'animation -- donc sans ca le
	-- joueur ouvre le hayon sur une echelle grande ouverte en travers du chargement.
	--
	-- ON PRECHARGE AVANT DE PLIER. Sans ca les marqueurs de l'anim ne tirent pas, la piste va jusqu'au bout, et
	-- l'echelle se retrouve DEPLIEE -- exactement l'inverse de ce qu'on vient de demander.
	--
	-- ET ON ATTEND LE CAMION : avec le streaming il arrive apres le demarrage. "Absent au demarrage" est normal,
	-- "absent pour toujours" ne l'est pas -- d'ou le delai de garde, et un message qui NOMME ce qu'il y a dans la
	-- benne quand aucune echelle n'y est reconnue.
	task.spawn(function()
		LadderFoldUtils.preload()
		local deadline = os.clock() + TruckConfigs.FIND_TIMEOUT
		while os.clock() < deadline do
			local truck = findTruck()
			local folder = truck and truck:FindFirstChild(TruckConfigs.TOOLS_FOLDER)
			if folder then
				local names = {}
				local ladders = {}
				for _, d in (folder :: Instance):GetChildren() do
					table.insert(names, d.Name)
					if LadderFoldUtils.isLadderName(d.Name) then
						table.insert(ladders, d :: Model)
					end
				end
				if #ladders == 0 then
					warn(
						`[TruckToolsService] Aucune echelle dans la benne : son modele doit s'appeler `
							.. `"{LadderFoldUtils.TRUCK_NAME}" ou "{LadderFoldUtils.PREFIX}...". `
							.. `Il y a : {table.concat(names, ", ")}`
					)
					return
				end
				-- L'ECHELLE DE LA CARTE SERT DE TEMOIN. Son repli marche (c'est celle qu'on porte a la main), donc
				-- si les deux rigs n'ont pas les MEMES noms de pieces, l'anim ne peut rien ecrire sur celle de la
				-- benne -- elle chercherait des membres qui n'existent pas chez elle.
				local witness: Model? = nil
				for _, d in Workspace:GetDescendants() do
					if d:IsA("Model") and d.Name:sub(1, #LadderFoldUtils.PREFIX) == LadderFoldUtils.PREFIX then
						witness = d :: Model
						break
					end
				end

				for _, ladder in ladders do
					print(`[TruckToolsService] Repli de "{ladder.Name}" : {LadderFoldUtils.describe(ladder)}`)
					print(`[TruckToolsService] Pieces benne  : {LadderFoldUtils.rigParts(ladder)}`)
					if witness then
						print(
							`[TruckToolsService] Pieces carte "{(witness :: Model).Name}" : `
								.. LadderFoldUtils.rigParts(witness :: Model)
						)
					else
						print("[TruckToolsService] Aucune echelle de carte pour comparer les noms de pieces.")
					end
					-- LE MEME CHEMIN QUE LE RANGEMENT A LA MAIN, qui lui plie l'echelle entierement. Voir
					-- `resetInPlace` : on reproduit ce qui marche au lieu d'expliquer ce qui ne marche pas.
					resetInPlace(ladder, folder :: Instance)
					LadderFoldUtils.standAlone(ladder)
					LadderFoldUtils.foldToEnd(ladder)
					-- ET PAS DE ZONE DE GRIMPE SUR UNE ECHELLE RANGEE. L'aller-retour l'a fait passer une image
					-- hors du camion, ce qui a pu lui en poser.
					LadderZoneService.refresh(ladder)
				end
				-- ON MESURE LE RESULTAT, on ne suppose pas que ca a marche. Le repli peut echouer EN SILENCE de
				-- trois facons -- anim pas encore chargee (marqueurs muets), rig sans joints, racine introuvable --
				-- et dans les trois cas l'echelle reste simplement ouverte, sans la moindre erreur.
				task.delay(LADDER_CHECK_DELAY, function()
					for _, ladder in ladders do
						if ladder.Parent and ladder:GetAttribute(LadderFoldUtils.CLOSED_ATTRIBUTE) ~= true then
							warn(
								`[TruckToolsService] "{ladder.Name}" n'est PAS repliee apres {LADDER_CHECK_DELAY}s. `
									.. LadderFoldUtils.describe(ladder)
							)
						end
					end
				end)
				return
			end
			task.wait(TruckConfigs.FIND_INTERVAL)
		end
		warn("[TruckToolsService] Camion introuvable : l'echelle de la benne restera ouverte.")
	end)

	-- RIEN A NETTOYER QUAND UN JOUEUR PART : le vol vit dans une tache, pas dans sa session, et il finit tout
	-- seul. L'outil sorti appartient au MONDE, pas a celui qui l'a sorti.
	-- RIEN A SUIVRE SUR LES JOUEURS. La regle ne depend plus de ce qu'ils TIENNENT mais de ce que l'outil EST :
	-- equipable et sorti de la benne = invisible, point. Un etat qui ne depend de personne ne peut pas se
	-- desynchroniser -- la version d'avant ecoutait les mains de chacun pour arriver au meme resultat.
	print("[TruckToolsService] Pret : les outils de la benne peuvent etre sortis.")
end

return TruckToolsService
