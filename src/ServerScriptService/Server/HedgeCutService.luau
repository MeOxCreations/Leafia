--!strict
-- LA COUPE. Ce que la lame recouvre perd ses feuilles.
--
-- C'est le coeur du jeu : tout le reste (approche, rail, camera, visee) n'existait que pour rendre ce geste
-- possible. Il doit donc rester lisible avant d'etre riche.
--
-- POURQUOI COTE SERVEUR, alors que le ressenti est client : ce qui est coupe deviendra de l'argent, une note
-- de client, une progression. Le client ment toujours. Il pourra plus tard PREDIRE la disparition pour
-- masquer la latence, mais c'est ici que ca compte.
--
-- PAS DE REQUETE SPATIALE. On mesure nous-memes la distance de chaque carreau a la lame :
--   exact, et independant de CanQuery, que les carreaux ont a false pour ne pas gener la detection de haie
--   borne, puisqu'on ne parcourt que les carreaux de la haie EN COURS de travail
--
-- Le CENTRE du carreau et non son volume entier : "ce qui est sous la lame tombe" est une regle que le joueur
-- apprend sans qu'on la lui explique.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)
local CurrencyConfigs = require(ReplicatedStorage.Modules.Configs.CurrencyConfigs)
local HedgeService = require(script.Parent.HedgeService)
local HedgeCellService = require(script.Parent.HedgeCellService)
local HedgeStockService = require(script.Parent.HedgeStockService)
local ToolService = require(script.Parent.ToolService)
local ExperienceService = require(script.Parent.ExperienceService)
local ComboService = require(script.Parent.ComboService)
local CurrencyService = require(script.Parent.CurrencyService)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local HedgeCutService = {}

-- LA LAME EN DEUX BOUTS : base et pointe, en monde, envoyes par le client.
--
-- On envoie le SEGMENT et non un seul point parce qu'une lame de taille-haie est une BARRE longue, pas une
-- bille. Avec un seul point + un rayon, le bout ne coupait pas : la sphere restait centree sur le milieu. Avec
-- le segment, on taille tout ce qui est a portee de la LIGNE de la lame, pointe comprise.
--
-- Le serveur ne peut pas lire ces positions lui-meme : la lame suit les bras, donc une animation jouee chez le
-- client dont il ne voit pas le defilement. La PORTEE est verifiee au moment de couper, la ou on a la position
-- du joueur a cet instant. Le serveur garde la vitesse de coupe et decide de quelle haie il s'agit.
type Aim = { base: Vector3, tip: Vector3 }
local aims: { [Player]: Aim } = {}

-- Date du dernier signal envoye au client. Sans elle, un balayage en enverrait soixante par seconde : le
-- reseau pour rien, et une secousse permanente au lieu d'un retour.
local lastTick: { [Player]: number } = {}
-- Carreaux amenes au ras depuis le dernier tas. Compteur qui SURVIT d'une haie a l'autre : le travail deja
-- fourni n'est jamais perdu parce qu'on a change de chantier.
local towardPile: { [Player]: number } = {}
-- Date du dernier signal d'ACHARNEMENT. Son propre rythme, bien plus rapide que celui de la coupe : une
-- secousse d'avertissement doit etre CONTINUE pour se lire comme une resistance, pas comme des a-coups.
local lastGrind: { [Player]: number } = {}
-- Date de la derniere bouchee clic-par-clic. Anti-spam serveur : le client ment, un script pourrait envoyer
-- mille CutSnip par seconde pour tailler en rafale. On borne l'intervalle, quoi que le client pretende.
local lastSnip: { [Player]: number } = {}

-- RAYON PERPENDICULAIRE de la coupe : jusqu'ou la lame taille DE PART ET D'AUTRE de sa ligne.
--
-- Plus deduit de la boite : la boite ne donne plus que la LONGUEUR (via le segment que le client envoie). La
-- largeur du coup est un reglage assume (CUT_RADIUS), pas une consequence de la taille de la boite. Ce qui
-- taille sur toute la lame maintenant, c'est le SEGMENT, pas ce rayon.
local CUT_REACH = HedgeConfigs.CUT_RADIUS + HedgeConfigs.CUT_MARGIN

-- Fait descendre la pousse de tout ce que la lame recouvre. Rend le nombre de carreaux entames cette frame.
--
-- On ne SUPPRIME rien sur les faces : la feuille rentre dans la haie et retrecit a mesure que sa pousse
-- descend. Une feuille qui disparait laisse un trou, donc un desordre different ; une feuille qui rentre
-- jusqu'a un plan commun forme une SURFACE PLATE. C'est toute la difference entre detruire et tailler.
-- Seules les ARETES font exception, et pour une raison visuelle precise (voir CUT_EDGE_CLEAR).
-- Carreaux ramasses autour de la lame. UNE seule table, reutilisee a chaque frame et par tous les joueurs.
--
-- Elle est sure malgre le partage : elle est remplie et entierement consommee dans le meme appel, sans aucun
-- point d'attente entre les deux. Rien ne peut s'intercaler.
-- Ses entrees au-dela du compte rendu sont des restes du tour precedent : on ne lit JAMAIS au-dela, jamais de
-- ipairs dessus.
local scratch: { BasePart } = {}

-- cutStep : pousse retiree sous la lame cette passe (taux * dt en maintenu, bouchee fixe en clic-par-clic).
-- hurtStep : degat inflige au vieux bois deja au ras sur la meme passe. Les deux montants sont calcules par
-- l'appelant : cutWith ne connait plus ni le temps ni l'outil, il applique juste ce qu'on lui donne.
local function cutWith(
	player: Player,
	root: BasePart,
	hedge: BasePart,
	cutStep: number,
	hurtStep: number
): (number, number, number)
	local total = HedgeCellService.getCount(hedge)
	if total <= 0 then
		return 0, 0, 0
	end

	local aim = aims[player]
	if not aim then
		return 0, 0, 0
	end
	local base, tip = aim.base, aim.tip
	local segment = tip - base
	local segmentLengthSquared = segment:Dot(segment)
	local middle = (base + tip) * 0.5

	-- PORTEE DU BRAS. Le client dit ou est sa lame ; on refuse un MILIEU de lame qu'aucun bras ne pourrait
	-- atteindre. Il ne peut donc pas tailler a l'autre bout de la haie sans s'y rendre.
	if (middle - root.Position).Magnitude > HedgeConfigs.CUT_REACH_MAX then
		return 0, 0, 0
	end

	-- CAPSULE, plus une sphere. On taille ce qui est a `reach` de la LIGNE de la lame, base a pointe. La sphere
	-- ne couvrait qu'un point (le milieu), donc le bout ne coupait pas : illogique pour une barre longue.
	--
	-- Toujours pas de projection sur une face : le test du bon cote (produit avec l'axe Z du carreau) suffit a
	-- ecarter la face arriere, et laisse tailler le dessus et les coins.
	--
	-- Compare au CARRE : on evite une racine carree par carreau, et l'ordre est le meme.
	local reach = CUT_REACH
	local reachSquared = reach * reach
	-- BORDURES : portee et tolerance elargies (coutures de coin / arete, ou la lame arrive de biais sur la face
	-- d'a cote). Voir HedgeConfigs. N'affecte que les cellules marquees EDGE, la pleine face garde reach / tolerance.
	local edgeReach = reach + HedgeConfigs.CUT_EDGE_REACH_BONUS
	local edgeReachSquared = edgeReach * edgeReach
	local edgeTolerance = HedgeConfigs.CUT_SURFACE_TOLERANCE + HedgeConfigs.CUT_EDGE_SURFACE_BONUS
	-- BASE (rangee du sol) : bonus encore plus genereux, la pose la plus basse des bras arrive au-dessus d'elle.
	local baseReach = reach + HedgeConfigs.CUT_BASE_REACH_BONUS
	local baseReachSquared = baseReach * baseReach
	local baseTolerance = HedgeConfigs.CUT_SURFACE_TOLERANCE + HedgeConfigs.CUT_BASE_SURFACE_BONUS

	-- On ramasse autour du MILIEU, avec un rayon qui englobe toute la capsule (demi-longueur + rayon). Le test
	-- precis au segment, juste apres, filtre ce sur-ensemble.
	-- La plus GRANDE des portees (bordure ou base) pour ne rater aucune cellule a portee elargie au ramassage.
	local gather = math.sqrt(segmentLengthSquared) * 0.5 + math.max(edgeReach, baseReach)

	local cut = 0
	local finished = 0
	local hurtNow = 0
	-- Degats le plus AVANCE parmi les carreaux mordus cette frame. Le maximum et non la moyenne : c'est le
	-- pire endroit qui doit faire trembler, sinon un seul carreau en train de mourir passerait inapercu
	-- au milieu de voisins intacts.
	local grind = 0

	-- ON NE PARCOURT PLUS TOUTE LA HAIE. Le service des carreaux les range dans une grille a la construction :
	-- on ne recupere ici que ceux des cases autour de la lame, soit une trentaine au lieu de neuf cent. Le test
	-- geometrique qui suit est inchange, il s'applique juste a beaucoup moins de monde.
	--
	-- Au passage, ca supprime le GetChildren() par frame, qui allouait une table de neuf cent entrees a chaque
	-- appel : c'etait probablement plus cher que la boucle elle-meme.
	local nearby = HedgeCellService.collectNear(hedge, middle, gather, scratch)
	for index = 1, nearby do
		local cell = scratch[index]
		if cell.Parent then
			local growth = cell:GetAttribute(HedgeConfigs.GROWTH_ATTRIBUTE)
			local damage = cell:GetAttribute(HedgeConfigs.DAMAGE_ATTRIBUTE)
			local spent = typeof(damage) == "number" and damage >= 1
			-- Deja au ras ET deja abime : plus rien a lui faire. Ce test passe AVANT la geometrie, qui coute
			-- bien plus cher.
			if typeof(growth) == "number" and (growth > 0 or not spent) then
				local cellPos = cell.Position
				-- POINT DE LA LAME LE PLUS PROCHE DU CARREAU. On projette le carreau sur le segment base-pointe,
				-- borne a [0, 1] : le pied de la perpendiculaire s'il tombe sur la lame, sinon le bout le plus
				-- proche. C'est ce point, et non le milieu fixe, qui sert de reference. Segment degenere (base ==
				-- pointe) : on retombe sur la base, donc l'ancien comportement point.
				local t = if segmentLengthSquared > 1e-6
					then math.clamp((cellPos - base):Dot(segment) / segmentLengthSquared, 0, 1)
					else 0
				local closest = base + segment * t
				local toBlade = closest - cellPos
				-- LA LAME EST-ELLE DU BON COTE ? L'axe Z d'un carreau pointe vers l'exterieur de sa face : si le
				-- point de lame le plus proche est devant lui, ce produit est positif.
				--
				-- Sur une haie mince, la face ARRIERE est a deux studs : elle tomberait dans la portee et se
				-- taillerait toute seule. Mais ses carreaux regardent a l'oppose, donc la lame est DERRIERE eux,
				-- et ils sont ecartes. Ce test ne connait pas la notion de face travaillee : le dessus et les
				-- coins deviennent taillables des que la lame les atteint.
				local outward = toBlade:Dot(cell.CFrame.ZVector)
				-- Portee et tolerance selon le TYPE de cellule. BASE (rangee du sol) d'abord, car un coin bas est
				-- aussi Edge (colonne 0) : la base a la portee la plus large, la pose basse arrive au-dessus d'elle.
				-- Edge = coin / arete (la lame arrive de biais sur la face d'a cote). Sinon pleine face, inchangee.
				local isBase = cell:GetAttribute(HedgeConfigs.BASE_ATTRIBUTE) == true
				local isEdge = not isBase and cell:GetAttribute(HedgeConfigs.EDGE_ATTRIBUTE) == true
				local cellReachSquared = if isBase then baseReachSquared elseif isEdge then edgeReachSquared else reachSquared
				local cellTolerance = if isBase then baseTolerance elseif isEdge then edgeTolerance else HedgeConfigs.CUT_SURFACE_TOLERANCE
				if outward > -cellTolerance and toBlade:Dot(toBlade) <= cellReachSquared then
					if growth <= 0 then
						-- DEJA AU RAS : on tape dans le vieux bois. Le carreau s'abime au lieu de se tailler.
						--
						-- Bien plus lent que la coupe : il faut s'acharner. Un joueur qui passe normalement ne
						-- doit jamais abimer par accident, sinon la punition devient du hasard.
						local hurt = math.min((damage or 0) + hurtStep, 1)
						cell:SetAttribute(HedgeConfigs.DAMAGE_ATTRIBUTE, hurt)
						grind = math.max(grind, hurt)
						cut += 1
						if hurt >= 1 then
							hurtNow += 1
							-- La feuille morte part : la couche de bois derriere prend le relais, et c'est elle qui
							-- raconte le degat. Le CARREAU reste, avec son attribut : il faudra encore le compter dans la
							-- note du client, et peut-etre le soigner un jour.
							if HedgeConfigs.DAMAGE_CLEAR then
								local leaf = cell:FindFirstChild("Leaf")
								if leaf then
									leaf:Destroy()
								end
							end
						end
						continue
					end

					local next = math.max(growth - cutStep, 0)
					cell:SetAttribute(HedgeConfigs.GROWTH_ATTRIBUTE, next)
					cut += 1
					if next <= 0 then
						finished += 1
						-- ARETE ARRIVEE AU RAS : la feuille part. Une feuille rase qui depasse encore de
						-- l'arete garde le contour flou alors que toute la face est nette, donc elle enleve au
						-- resultat au lieu d'y ajouter.
						--
						-- Ne passe ici qu'UNE fois : entrer dans ce bloc exige growth > 0 juste avant.
						if HedgeConfigs.CUT_EDGE_CLEAR and cell:GetAttribute(HedgeConfigs.EDGE_ATTRIBUTE) then
							local leaf = cell:FindFirstChild("Leaf")
							if leaf then
								leaf:Destroy()
							end
						end
					end
				end
			end
		end
	end

	-- AVANCEMENT et DEGATS, tenus en incrementiel. Recompter tous les carreaux a chaque frame serait
	-- absurde alors qu'on sait exactement combien viennent de basculer.
	if finished > 0 then
		local done = (hedge:GetAttribute(HedgeConfigs.TRIMMED_ATTRIBUTE) or 0) * total + finished
		local ratio = math.clamp(done / total, 0, 1)
		-- AUTO-COMPLETION : des qu'on franchit le seuil (les derniers % chiants : dessus, recoins), on finit le reste
		-- tout seul. Les carreaux finis d'office s'ajoutent a `finished` -> l'appelant leur donne XP / combo / debris
		-- comme s'ils avaient ete tailles a la main (le joueur a fait le gros du travail, il touche tout).
		if ratio >= HedgeConfigs.AUTO_COMPLETE_THRESHOLD and ratio < 1 then
			finished += HedgeCellService.finishRemaining(hedge)
			ratio = 1
		end
		hedge:SetAttribute(HedgeConfigs.TRIMMED_ATTRIBUTE, ratio)
		-- CHEQUE DE FIN DE HAIE : la 1re fois qu'une haie atteint 100%, le joueur touche sa paie (coins). UNE seule fois
		-- (garde PAID_ATTRIBUTE) : sans lui, continuer a passer la lame sur une haie finie la re-paierait. La persistance
		-- (company active) et l'UI ("+X" flottant) suivent seules. Sur la place tuto, grantCoins est un no-op (voulu).
		-- Co-op : c'est le joueur qui AMENE la haie a 100% qui touche le cheque (garde -> un seul versement). A raffiner
		-- si on veut partager la paie entre contributeurs.
		if ratio >= 1 and hedge:GetAttribute(HedgeConfigs.PAID_ATTRIBUTE) ~= true then
			hedge:SetAttribute(HedgeConfigs.PAID_ATTRIBUTE, true)
			local payout = CurrencyConfigs.HEDGE_BASE_PAYOUT + math.floor(total * CurrencyConfigs.HEDGE_PER_CELL_PAYOUT)
			CurrencyService.grantCoins(player, payout)
		end
	end
	if hurtNow > 0 then
		local ruined = (hedge:GetAttribute(HedgeConfigs.DAMAGED_ATTRIBUTE) or 0) * total + hurtNow
		hedge:SetAttribute(HedgeConfigs.DAMAGED_ATTRIBUTE, math.clamp(ruined / total, 0, 1))
	end

	-- Trois nombres : ce qui a ete ENTAME cette frame (retours immediats), ce qui a ete FINI (depot au sol),
	-- et le pire etat d'abimage touche (secousse). Un carreau entame n'est pas un travail accompli.
	return cut, finished, grind
end

-- Incremente un compteur d'evenement sur le personnage. Le client ecoute le CHANGEMENT, pas la valeur : c'est
-- ainsi qu'un evenement ponctuel (une bouchee, un degat) passe par un attribut sans remote dedie.
local function bumpCounter(character: Instance, attribute: string)
	character:SetAttribute(attribute, (character:GetAttribute(attribute) or 0) + 1)
end

-- Signale que la lame FORCE dans du vieux bois deja au ras (secousse cote client), au plus une fois par
-- intervalle. Partage par la coupe continue et le clic-par-clic : abimer se ressent pareil quel que soit l'outil.
local function emitGrind(character: Instance, player: Player, grind: number, now: number)
	if grind < HedgeConfigs.DAMAGE_SHAKE_START then
		return
	end
	if now - (lastGrind[player] or 0) < HedgeConfigs.DAMAGE_TICK_INTERVAL then
		return
	end
	lastGrind[player] = now
	character:SetAttribute(HedgeConfigs.DAMAGE_LEVEL_ATTRIBUTE, grind)
	bumpCounter(character, HedgeConfigs.DAMAGE_TICK_ATTRIBUTE)
end

-- Une passe de coupe pour un joueur : trouve la haie en cours, cale la reference de portee, taille du montant
-- demande, et depose au sol ce qui est arrive au ras. Rend (entame, fini, pire abimage) ; l'appelant emet les
-- retours (secousse, tick de coupe) selon sa cadence propre.
local function biteAt(player: Player, character: Model, cutStep: number, hurtStep: number): (number, number, number)
	-- On ne parcourt que la haie EN COURS de travail. Sans cette borne il faudrait tester toutes les haies de
	-- la carte, pour un joueur qui n'en touche qu'une.
	local contact = HedgeService.getContact(player)
	if not contact then
		return 0, 0, 0
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return 0, 0, 0
	end

	-- REFERENCE DE PORTEE. Normalement le HumanoidRootPart : la lame doit rester a portee de bras du centre du
	-- joueur. Mais sur l'echelle, ce root est ANCRE EN BAS pendant que l'animation monte le corps : la lame est
	-- alors a plusieurs studs au-dessus du root et la portee la rejetterait. On mesure donc depuis le LowerTorso
	-- (le corps reellement en hauteur). La portee reste verifiee, juste depuis le bon point.
	local reference: BasePart = root
	if HedgeService.isLadderTrimming(player) then
		local torso = character:FindFirstChild("LowerTorso") or character:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			reference = torso
		end
	end

	local cut, finished, grind = cutWith(player, reference, contact.hedge, cutStep, hurtStep)

	-- DEPOT AU SOL. Un tas tous les N carreaux AMENES AU RAS : on depose ce qui a reellement ete retire, on ne
	-- paie jamais l'intention. Le reste est GARDE d'une haie a l'autre : sinon changer de chantier effacerait un
	-- travail deja fourni, et le joueur ne comprendrait pas pourquoi.
	if finished > 0 then
		local pending = (towardPile[player] or 0) + finished
		local drops = math.floor(pending / HedgeConfigs.STOCK_DEBRIS_PER_CELLS)
		towardPile[player] = pending - drops * HedgeConfigs.STOCK_DEBRIS_PER_CELLS
		for _ = 1, drops do
			-- On passe la position du JOUEUR : la zone est choisie par proximite, donc le tas tombe la ou il se
			-- tient, y compris dans un angle ou deux faces se disputent le travail.
			HedgeStockService.drop(contact.hedge, root.Position)
		end
		-- XP : chaque carreau amene au ras rapporte de l'experience. Point UNIQUE pour tous les outils et tous les
		-- contextes (taille-haie continu ET cisaille au clic passent par biteAt). Runtime : ExperienceService ne
		-- sauvegarde pas encore.
		ExperienceService.grantXp(player, finished)
		-- COMBO : meme signal honnete que l'XP (un carreau REELLEMENT amene au ras). Le service borne le rythme et
		-- gere l'expiration ; ici on se contente de dire "un vrai coup vient d'aboutir".
		ComboService.registerCut(player)
	end

	return cut, finished, grind
end

local function step(dt: number)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then
			continue
		end

		-- Moteur eteint : les lames ne tournent pas, rien ne coupe. On lit les attributs plutot que d'appeler
		-- ToolStartService : deux services qui ne se connaissent pas restent retouchables separement.
		if character:GetAttribute(HedgeConfigs.ENGINE_ATTRIBUTE) ~= true then
			continue
		end

		-- Outil clic-par-clic (cisaille) : il ne coupe PAS en continu ici. Chaque coup arrive par le remote
		-- CutSnip, une bouchee fixe a la fois. Le taille-haie (maintenu) passe, lui, par le reste de la boucle.
		local held = ToolService.getHeld(player)
		if held and held.config.cutPerClick then
			continue
		end

		if
			HedgeConfigs.CUT_NEEDS_THROTTLE
			and character:GetAttribute(HedgeConfigs.THROTTLE_ATTRIBUTE) ~= true
		then
			continue
		end

		-- Vitesse de coupe propre a l'outil (cutRateScale) : le taille-haie a plein regime (1), un modele inferieur
		-- plus lentement. C'est ce qui fait sentir l'upgrade. L'acharnement (DAMAGE_RATE) reste global.
		local rateScale = if held and held.config.cutRateScale then held.config.cutRateScale else 1
		local cut, _finished, grind =
			biteAt(player, character, HedgeConfigs.CUT_RATE * rateScale * dt, HedgeConfigs.DAMAGE_RATE * dt)

		local now = os.clock()
		emitGrind(character, player, grind, now)

		-- Tick de coupe ESPACE : la boucle tourne a chaque frame, sans borne le client jouerait 60 retours/s.
		if cut > 0 and now - (lastTick[player] or 0) >= HedgeConfigs.CUT_TICK_INTERVAL then
			lastTick[player] = now
			bumpCounter(character, HedgeConfigs.CUT_TICK_ATTRIBUTE)
		end
	end
end

function HedgeCutService.init()
	local aimRemote = RemoteSetup.getRemote("SetAim", "Hedge")
	if aimRemote and aimRemote:IsA("RemoteEvent") then
		aimRemote.OnServerEvent:Connect(function(player: Player, base: unknown, tip: unknown)
			-- Validation stricte : le client ment toujours. Deux Vector3, et rien d'autre.
			if typeof(base) ~= "Vector3" or typeof(tip) ~= "Vector3" then
				return
			end
			-- LONGUEUR DE LAME PLAUSIBLE. Sans ce garde, le client enverrait un segment geant pour tailler toute
			-- la haie d'un coup. On borne a une longueur de lame realiste ; la PORTEE (ou est la lame par rapport
			-- au joueur) est verifiee plus tard, au moment de couper, avec la position du joueur a cet instant.
			if (tip - base).Magnitude > HedgeConfigs.CUT_BLADE_MAX_LENGTH then
				return
			end
			aims[player] = { base = base, tip = tip }
		end)
	else
		warn("[HedgeCutService] Remote Hedge/SetAim introuvable")
	end

	-- COUPE CLIC-PAR-CLIC (cisaille). Chaque clic du client = une bouchee fixe, valide ici comme le reste :
	-- le client ne fait que declencher, le serveur decide s'il coupe et de combien.
	local snipRemote = RemoteSetup.getRemote("CutSnip", "Hedge")
	if snipRemote and snipRemote:IsA("RemoteEvent") then
		snipRemote.OnServerEvent:Connect(function(player: Player)
			local character = player.Character
			if not character then
				return
			end
			-- Meme garde que le taille-haie : l'outil doit etre pret a couper. La cisaille pose ENGINE des
			-- l'equipement (cutReadyOnEquip), donc ce test passe des qu'elle est en main.
			if character:GetAttribute(HedgeConfigs.ENGINE_ATTRIBUTE) ~= true then
				return
			end
			-- Seul un outil clic-par-clic repond ici, et c'est SA config qui donne la taille de la bouchee. Un
			-- client qui envoie CutSnip en tenant le taille-haie (maintenu) est ignore.
			local held = ToolService.getHeld(player)
			local bite = if held then held.config.cutPerClick else nil
			if not bite then
				return
			end
			-- ANTI-SPAM. Un clic humain ne depasse pas une douzaine par seconde ; au-dela c'est un script. On borne
			-- l'intervalle entre deux bouchees, cote serveur, quoi que le client envoie.
			local now = os.clock()
			if now - (lastSnip[player] or 0) < HedgeConfigs.CUT_CLICK_MIN_INTERVAL then
				return
			end
			lastSnip[player] = now

			-- LES LAMES CLAQUENT. Anim du MODEL de l'outil, jouee une fois, cote serveur -> vue par tous. On la
			-- joue a CHAQUE clic accepte, meme si rien n'est coupe (viser dans le vide) : le geste doit suivre le
			-- clic, pas le resultat. Le taille-haie n'a pas de cutAnimation (ses lames tournent en continu).
			if held and held.config.cutAnimation then
				ToolService.playToolAnimationOnce(player, held.config.cutAnimation)
			end

			-- Meme rapport coupe/degat que le taille-haie a plein regime, applique en une bouchee fixe : abimer le
			-- vieux bois reste aussi lent, seul le rythme (un clic = une bouchee) change.
			local hurt = bite * HedgeConfigs.DAMAGE_RATE / HedgeConfigs.CUT_RATE
			local cut, _finished, grind = biteAt(player, character, bite, hurt)
			emitGrind(character, player, grind, now)
			-- Retour de coupe a CHAQUE clic qui mord, sans intervalle : le clic EST deja l'evenement, l'espacer
			-- retirerait au joueur le retour de son propre geste.
			if cut > 0 then
				bumpCounter(character, HedgeConfigs.CUT_TICK_ATTRIBUTE)
			end
		end)
	else
		warn("[HedgeCutService] Remote Hedge/CutSnip introuvable")
	end

	-- Heartbeat : la coupe est une decision de jeu, elle n'a pas a passer avant le rendu de l'image.
	RunService.Heartbeat:Connect(step)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastTick[player] = nil
		aims[player] = nil
		towardPile[player] = nil
		lastGrind[player] = nil
		lastSnip[player] = nil
	end)
end

return HedgeCutService
