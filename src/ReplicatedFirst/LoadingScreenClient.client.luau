--!strict
-- Ecran de chargement de Leafia : fond vert, tuile qui defile, tete du grand-pere + mot LEAFIA (lettre par lettre,
-- puis une vague) au centre, barre doree qui suit le VRAI chargement, feuillages en ombre autour.
--
-- Construit ENTIEREMENT EN CODE : aucune dependance a une UI Studio, tout est ici, versionne et reglable par les
-- constantes plus bas. Les positions viennent d'un ecran monte A LA MAIN dans Studio puis RELEVE avec
-- `scripts/studio/ExporterEcranChargement.lua` : placer a la souris coute dix secondes, deviner les chiffres une heure.
--
-- AUTONOME : ne require aucun module de ReplicatedStorage. ReplicatedFirst se replique avant le reste du jeu :
-- attendre un module de ReplicatedStorage reviendrait a bloquer sur ce qu'on masque justement.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")

-- LE DESSIN DU RIDEAU, partage avec l'ecran du teleport. Voisin DANS ReplicatedFirst, donc deja la : ce require
-- n'attend aucune replication, contrairement a un module de ReplicatedStorage.
local CurtainVisual = require(script.Parent.CurtainVisual)
local WipeVisual = require(script.Parent.WipeVisual)

local player = Players.LocalPlayer
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- ===== Sons : resolution par chemin sous SoundService =====
-- AUTONOME, comme tout ce fichier : aucun require de ReplicatedStorage (SoundUtils fait la meme chose, mais le
-- requerir ici ferait attendre une replication qu'on n'a pas au moment de ReplicatedFirst).
--
-- Ces fonctions vivent AVANT le rideau parce que le rideau `return` : une definition placee plus bas ne serait
-- jamais atteinte dans ce chemin.
local function findByPath(path: { string }): Instance?
	local current: Instance = SoundService
	for _, name in ipairs(path) do
		local child = current:FindFirstChild(name)
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function findSound(path: { string }): Sound?
	local found = findByPath(path)
	return if found and found:IsA("Sound") then found else nil
end

-- Comme findSound, mais un chemin qui pointe sur un DOSSIER rend un de ses Sound AU HASARD. Deposer un echantillon
-- de plus dans Studio augmente donc la variete sans toucher au code (meme convention que le son de coupe de haie).
local function findAnySound(path: { string }): Sound?
	local found = findByPath(path)
	if not found then
		return nil
	end
	if found:IsA("Sound") then
		return found
	end
	local pool: { Sound } = {}
	for _, child in ipairs(found:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(pool, child)
		end
	end
	return if #pool > 0 then pool[math.random(#pool)] else nil
end

-- Clone et joue. On CLONE plutot que rejouer l'original : rejouer la meme instance couperait le son en cours, et
-- le clone garde les reglages faits en Studio (volume, hauteur), qui restent la source de verite.
local function playSound(source: Sound, volume: number?, speed: number?): Sound
	local sound = source:Clone()
	if volume then
		sound.Volume = volume
	end
	if speed then
		sound.PlaybackSpeed = speed
	end
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 5) -- garde-fou si Ended ne tire jamais (asset absent)
	return sound
end

-- ===== Assets EN DUR + destruction de l'ancien ecran s'il traine =====
-- LE FOND TUILE, releve sur la maquette : image, taille et transparence viennent de la.
local TILE_IMAGE = "rbxassetid://78626050824347"
local TILE_TRANSPARENCY = 0.95 -- KNOB : baisser = tuile plus visible ; monter = plus discrete
-- TileSize en SCALE (fraction de l'ImageLabel tuile, qui fait deux fois l'ecran) : c'est ainsi que le joueur l'a
-- regle a l'oeil. A REGLER a l'oeil pour l'image, pas a deduire.
local TILE_SCALE_X = 0.037
local TILE_SCALE_Y = 0.07
local TILE_SPEED = 15
-- ON NE DETRUIT PLUS `ReplicatedFirst.LoadingScreen`. Ce fichier le faisait -- l'ancien ecran n'etait plus lu, on
-- le nettoyait -- mais c'est devenu exactement l'endroit ou vit le MODELE du rideau de changement de map. Le
-- detruire au demarrage revenait a supprimer le decor juste avant de s'en servir.

-- ===== RIDEAU GRIS (fond sombre + feuille qui oscille) : pour TOUT lieu SAUF le 1er lancement de Leafia (le gros ecran herbe est
-- reserve a ce cas-la). On y va si on ARRIVE d'un teleport (donnees posees par TeleportService) OU si on n'est PAS dans
-- la place principale (tuto, chantiers : ils ne montrent JAMAIS l'ecran herbe, meme lances direct en Studio). Autonome :
-- ReplicatedFirst ne peut pas require PlacesConfig, donc l'ID de Leafia est EN DUR ici (doit valoir PlacesConfig.MAIN). =====
local MAIN_PLACE_ID = 84161484719535
-- Meme regle : EN DUR, et doit valoir PlacesConfig.TUTORIAL. Sert a garder le tuto epure (voir plus bas).
local TUTORIAL_PLACE_ID = 109440527457437
if TeleportService:GetLocalPlayerTeleportData() ~= nil or game.PlaceId ~= MAIN_PLACE_ID then
	-- ===== LE RIDEAU EST CONSTRUIT EN CODE =====
	-- Il l'a ete un temps a partir d'une ScreenGui modele posee dans Studio. Abandonne : Rojo ne synchronise pas
	-- StarterGui, donc le modele n'existait que dans le lieu ou on l'avait dessine, et le tuto tombait sur le
	-- rideau de secours. Le code, lui, arrive dans TOUS les lieux sans qu'on ait rien a recopier.
	--
	-- LE DESSIN ET SES ANIMATIONS VIVENT DANS `CurtainVisual`, a cote de ce fichier : le rideau du bouton START et
	-- l'ecran du teleport montrent exactement le meme. Ici il ne reste que l'attente et la sortie.

	-- Son joue quand le rideau apparait. POINTE SUR LE DOSSIER : un echantillon est tire au hasard, donc deux
	-- chargements de suite ne sonnent pas pareil. Meme dossier que le son de coupe de haie.
	local LEAF_SOUND = { "Sounds", "Environnement", "Leafs" }
	local LEAF_SOUND_VOLUME = 0.35 -- a regler a l'oreille
	local LEAF_SOUND_WAIT = 6 -- combien de temps on re-cherche le son avant d'abandonner

	-- Duree du rideau, comptee A PARTIR DE L'ARRIVEE DU PERSONNAGE et non du chargement du jeu. Un plancher qui
	-- part d'un autre instant que l'evenement qu'il doit couvrir ne garantit rien : a 1.4 s depuis `game:IsLoaded`,
	-- le rideau disparaissait avant meme que le joueur soit pose, et on ne le voyait pas.
	local MIN_ARRIVAL = 10

	-- ===== VOLET DE SORTIE =====
	-- Un aplat BLANC balaie l'ecran, on detruit le rideau PENDANT qu'il couvre, puis le blanc s'en va en balayant
	-- dans l'autre sens et le jeu apparait.
	--
	-- POURQUOI PAS UN SIMPLE FONDU. En fondant, chaque element du rideau disparait a sa maniere : la tuile, la
	-- feuille et les textes s'effacent en meme temps mais pas au meme rythme, et ca se lit comme un bug. Sous le
	-- volet, on ne voit RIEN partir -- le rideau est deja detruit quand le blanc se retire.
	-- Le dessin et le mouvement du voile vivent dans `WipeVisual` : la sortie du didacticiel joue le meme.
	local WIPE_COVER_TIME = WipeVisual.COVER_TIME
	local WIPE_HOLD = WipeVisual.HOLD -- temps couvert, pendant lequel on detruit le rideau
	local WIPE_REVEAL_TIME = WipeVisual.REVEAL_TIME

	-- ===== LE JOUEUR NE BOUGE PAS SOUS LE RIDEAU =====
	-- Le personnage est la bien avant que le rideau se leve (dix secondes au moins) : sans verrou, on marchait a
	-- l'aveugle derriere l'ecran de chargement, et on arrivait n'importe ou.
	--
	-- UNE ENTREE ANNULEE A CHAQUE IMAGE, pas une propriete : `Move` a zero et `Jump` faux, juste APRES le module de
	-- controle de Roblox (priorite Input + 1). Clavier, manette, joystick et bouton de saut tactiles passent tous
	-- par lui, donc tous sont annules -- et rien n'est ecrit que le serveur pourrait ecraser (une vitesse de marche
	-- reposee par lui au spawn rendrait les jambes). Pas d'ancrage non plus : le joueur doit pouvoir TOMBER sur son
	-- point d'apparition, sinon il atterrirait sous nos yeux a la levee du rideau.
	-- Le saut est coupe en plus sur l'etat, ce qui cache aussi le bouton de saut tactile.
	local FREEZE_BIND = "LeafiaCurtainFreeze"
	local frozenHumanoid: Humanoid? = nil
	RunService:BindToRenderStep(FREEZE_BIND, Enum.RenderPriority.Input.Value + 1, function()
		local char = player.Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if not hum then
			return
		end
		hum:Move(Vector3.zero, false)
		hum.Jump = false
		if frozenHumanoid ~= hum then
			frozenHumanoid = hum
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end
	end)
	local unfrozen = false
	local function unfreeze()
		if unfrozen then
			return
		end
		unfrozen = true
		RunService:UnbindFromRenderStep(FREEZE_BIND)
		local hum = frozenHumanoid
		if hum and hum.Parent then
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	end
	-- FILET : si une ligne du rideau echouait, le joueur resterait fige pour toute la session. Tres large -- il ne
	-- sert jamais quand tout va bien (le personnage peut mettre 15 s a arriver, plus les 10 s du rideau).
	task.delay(90, unfreeze)

	local sg = Instance.new("ScreenGui")
	sg.Name = "LeafiaCurtain"
	sg.ScreenInsets = Enum.ScreenInsets.None
	sg.ResetOnSpawn = false -- sinon le rideau est recree a chaque mort et nos references pointent sur du detruit
	sg.DisplayOrder = 1000
	sg.Parent = player:WaitForChild("PlayerGui")

	-- CanvasGroup : le fondu de sortie porte sur LUI, donc tout son contenu s'efface d'un seul mouvement au lieu
	-- de partir element par element.
	local curtain = Instance.new("CanvasGroup")
	-- Couleur de secours seulement : le cadre degrade pose par CurtainVisual couvre tout l'ecran.
	curtain.BackgroundColor3 = CurtainVisual.BG
	curtain.BorderSizePixel = 0
	curtain.Size = UDim2.fromScale(1, 1)
	curtain.Active = true -- absorbe les clics tant que le rideau couvre
	curtain.Parent = sg

	local built = CurtainVisual.build(curtain, CurtainVisual.destFor(game.PlaceId))
	-- ARRIVE PAR UN TELEPORT : le visage est DEJA a l'ecran, plein, sur l'ecran du voyage. Pas de depliage : il le
	-- ferait disparaitre puis revenir pile au moment ou les deux ecrans se relaient.
	local arrivedByTeleport = TeleportService:GetArrivingTeleportGui() ~= nil
	local stopAnimation = CurtainVisual.animate(built, not arrivedByTeleport)

	-- ===== SON =====
	-- POURQUOI UNE BOUCLE DE RECHERCHE et pas un simple FindFirstChild. Ce rideau vit dans ReplicatedFirst : quand
	-- il s'affiche, SoundService n'a pas forcement encore recu ses dossiers. Un scan unique a cet instant rendrait
	-- nil, et le son ne partirait JAMAIS -- sans la moindre erreur a l'ecran ni dans la console.
	task.spawn(function()
		local deadline = os.clock() + LEAF_SOUND_WAIT
		while sg.Parent and os.clock() < deadline do
			local source = findAnySound(LEAF_SOUND)
			if source then
				playSound(source, LEAF_SOUND_VOLUME)
				return
			end
			task.wait(0.2)
		end
	end)

	-- ===== PRECHARGEMENT DES SONS =====
	-- Le rideau tient dix secondes a ne RIEN faire. Autant s'en servir.
	--
	-- POURQUOI ICI. L'ecran de chargement PRINCIPAL precharge deja tout (il balaye SoundService parmi le reste),
	-- mais ce rideau sort par un `return` bien avant ce code. Les lieux qui l'affichent -- le tuto, et demain les
	-- jardins de clients -- n'avaient donc AUCUN son precharge.
	--
	-- Ce que ca coute quand ce n'est pas fait : la PREMIERE lecture d'un son part en retard, ou pas du tout. Sur un
	-- demarrage de tondeuse, c'est precisement le premier coup de corde qui sonne creux -- le moment ou il ne faut
	-- surtout pas.
	--
	-- EN TACHE DE FOND : `PreloadAsync` attend le reseau. Il n'a rien a faire dans le fil du rideau, qui doit
	-- continuer a s'animer pendant ce temps. Et on le laisse FINIR meme si le rideau part avant : un son
	-- precharge trop tard reste precharge.
	task.spawn(function()
		local sounds: { Instance } = {}
		for _, d in ipairs(SoundService:GetDescendants()) do
			if d:IsA("Sound") then
				sounds[#sounds + 1] = d
			end
		end
		if #sounds == 0 then
			return
		end
		-- pcall : une coupure reseau ou un asset absent ne doit pas empecher le jeu de demarrer.
		local ok = pcall(function()
			ContentProvider:PreloadAsync(sounds)
		end)
		print(`[LoadingScreen] {#sounds} son(s) precharge(s){if ok then "" else " (interrompu)"}.`)
	end)

	-- Chat + liste joueurs : la CoreGui passe AU-DESSUS des ScreenGui, le rideau ne la couvre pas -> on la coupe.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)

	-- Attente, dans l'ORDRE : le jeu charge, PUIS le personnage arrive, PUIS seulement le compte a rebours part.
	-- C'est cet ordre qui compte. Le personnage peut mettre plusieurs secondes a se mettre en place (donnees,
	-- session lock) : un compte lance avant lui serait deja ecoule quand il apparait, et le rideau se leverait
	-- dans la seconde -- exactement le defaut qu'on corrige ici.
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local character: Instance? = player.Character
	if not character then
		character = player.CharacterAdded:Wait()
	end
	if character then
		-- A CharacterAdded le personnage est parente mais pas complet : ses parts arrivent quelques images plus tard.
		character:WaitForChild("HumanoidRootPart", 10)
	end
	local startT = os.clock()
	while os.clock() - startT < MIN_ARRIVAL do
		RunService.Heartbeat:Wait()
	end

	-- LE TUTO RESTE EPURE. Ailleurs, chat et liste des joueurs reviennent normalement a la fin du chargement.
	-- Dans le didacticiel le joueur est SEUL : une liste a un seul nom et une fenetre de chat vide n'apportent
	-- rien et prennent les deux coins de l'ecran -- ceux-la memes ou s'affichent le bandeau d'objectifs et les
	-- monnaies. La fenetre de chat moderne, elle, reste coupee par `hideCoreGuis` et n'est jamais rallumee ici.
	if game.PlaceId ~= TUTORIAL_PLACE_ID then
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
		end)
	end

	-- ===== VOLET DE SORTIE =====
	local wipe = WipeVisual.create(player:WaitForChild("PlayerGui"))
	local wipeGui = wipe.gui
	local sweep = wipe.sweep

	-- CONDAMNE D'AVANCE. Un aplat blanc plein cadre est la pire chose a laisser derriere soi : il cache le jeu
	-- entier et le joueur n'a aucun moyen de s'en debarrasser. On programme donc sa destruction MAINTENANT, avant
	-- meme de l'animer -- si une seule ligne du balayage echoue, il part quand meme.
	-- La marge est large : elle ne sert jamais quand tout va bien, et elle coute une tache endormie.
	task.delay(WIPE_COVER_TIME + WIPE_HOLD + WIPE_REVEAL_TIME + 3, function()
		wipeGui:Destroy()
	end)

	sweep(0, 1, WIPE_COVER_TIME)

	-- COUVERT : on demonte le rideau pendant qu'on ne voit rien. C'est tout l'interet du volet.
	-- La boucle AVANT le Destroy : elle vit sur RunService, pas sur le GUI, donc detruire le rideau ne la
	-- couperait pas -- elle tournerait sur des instances mortes toute la session.
	stopAnimation()
	sg:Destroy()

	-- LA CAMERA SE POSE DANS LE DOS DU JOUEUR, pendant qu'on ne voit rien. Sans ca, le jeu apparaissait avec la
	-- camera tournee n'importe comment : le serveur pose le personnage sur son point d'apparition APRES que la
	-- camera a pris son angle, et elle garde celui d'avant.
	--
	-- On ne touche qu'a sa DIRECTION : la camera de jeu (Custom) relit son regard dans `camera.CFrame` a chaque
	-- image, et garde son propre zoom. Meme distance et meme inclinaison qu'elle avait, donc rien ne saute. Seulement
	-- si elle est en Custom : une camera scriptee (selection de plot) n'est pas a nous.
	local cam = workspace.CurrentCamera
	local root = if player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
	if cam and cam.CameraType == Enum.CameraType.Custom and root and root:IsA("BasePart") then
		local facing = root.CFrame.LookVector
		local flat = Vector3.new(facing.X, 0, facing.Z)
		if flat.Magnitude > 1e-3 then
			local focus = cam.Focus.Position
			local offset = cam.CFrame.Position - focus
			local dist = offset.Magnitude
			if dist > 0.5 then
				-- L'inclinaison actuelle, gardee : seule la direction au sol change.
				local rise = math.clamp(offset.Y / dist, -0.99, 0.99)
				local back = -flat.Unit * math.sqrt(1 - rise * rise)
				cam.CFrame = CFrame.lookAt(focus + (back + Vector3.new(0, rise, 0)) * dist, focus)
			end
		end
	end
	task.wait(WIPE_HOLD)

	-- LES COMMANDES REVIENNENT AVEC L'IMAGE, pas apres le balayage : le joueur qui appuie deja doit partir tout de
	-- suite, sinon la levee du rideau se lit comme un lag.
	unfreeze()

	-- ET LE JEU APPARAIT. Le meme bord repart en arriere : le volet se retire par ou il est venu.
	sweep(1, 0, WIPE_REVEAL_TIME)
	-- DETRUIT QUOI QU'IL ARRIVE. C'est la garantie qui rend ce volet sans danger : meme si le balayage partait du
	-- mauvais cote, ou si une sequence etait refusee, on ne peut pas se retrouver avec un aplat blanc colle sur
	-- le jeu pour toute la session.
	wipeGui:Destroy()
	player:SetAttribute("LeafiaLoadingDone", true) -- meme signal que l'ecran principal (l'UI sait que le rideau est parti)
	return
end

-- ===== Reglages =====
-- Duree minimale a l'ecran DEPUIS l'apparition, meme si tout charge en un clin d'oeil (cas Studio). C'EST LE KNOB si
-- "ca va trop vite" : la barre se remplit sur cette duree au minimum, et l'ecran ne part pas avant. Le skip (Echap)
-- reste dispo pour les impatients. Un vrai chargement plus lent, lui, prolonge naturellement.
local MIN_DURATION = 15

-- Couleurs (maquette). A REGLER a l'oeil.
local WHITE = Color3.fromRGB(255, 255, 255)

-- TOUT CE BLOC EST RELEVE SUR L'ECRAN QUE LE JOUEUR A MONTE A LA MAIN dans StarterGui, avec
-- `scripts/studio/ExporterEcranChargement.lua`. Placer a la souris coute dix secondes ; deviner les memes chiffres
-- coute une heure. Positions et tailles en FRACTION D'ECRAN, au CENTRE de l'element.
--
-- L'ECRAN EST EN NOIR ET BLANC : fond blanc, tout le dessin en noir. Une seule encre, donc.
local INK = Color3.fromRGB(0, 0, 0)

-- LA TETE DU GRAND-PERE et l'ONOMATOPEE a cote d'elle. Toutes deux fondues vers le bas par un degrade (voir
-- `fadeGradient`) : c'est ce qui leur donne leur gris, sans qu'aucune couleur n'entre dans l'ecran.
local FACE_IMAGE = "rbxassetid://111069478991867"
-- CLIGNEMENT : on echange l'image. Deux suffisent (ouvert / ferme) ; l'etape "a moitie" est OPTIONNELLE -- laissee
-- vide, on passe direct d'ouvert a ferme. Avec elle, le clignement est plus doux (c'est ce que fait le rideau de
-- changement de map). VIDE partout = pas de clignement du tout.
local FACE_HALF_IMAGE = ""
local FACE_SHUT_IMAGE = "rbxassetid://92930536214559"
-- Ecart entre deux clignements, plus du hasard : toutes les N secondes pile, ca se lit comme un metronome.
local FACE_BLINK_EVERY = 3.2
local FACE_BLINK_JITTER = 2.4
local FACE_BLINK_HALF_TIME = 0.05
local FACE_BLINK_SHUT_TIME = 0.09
local FACE_POS = Vector2.new(0.5, 0.398)
local FACE_SIZE = Vector2.new(0.1835, 0.2837)
local SHOUT_IMAGE = "rbxassetid://84029477406959"
local SHOUT_POS = Vector2.new(0.6433, 0.5022)
local SHOUT_SIZE = Vector2.new(0.092, 0.2508)
local SHOUT_ROT = 20
-- ELLE JAILLIT QUAND LA DERNIERE LETTRE DU MOT SE POSE, une seule fois : c'est le "et voila" du mot. Posee d'entree
-- ou rejouee en boucle, elle ferait partie du decor et on ne la verrait plus.
local SHOUT_POP = 0.15 -- taille de depart (fraction de sa taille) : elle part de presque rien
local SHOUT_TILT = 22 -- degres de plus au depart : elle se redresse en arrivant, ca la rend vivante
-- Back = elle depasse sa taille puis revient : c'est ce depassement qui fait le cote dessin anime.
local SHOUT_IN = TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local ART_FADE_ROTATION = 210.2216 -- sens du fondu, releve sur la maquette

-- LE MOT : UNE LIGNE PAR LETTRE, a la place exacte ou le joueur l'a posee. Un `UIListLayout` avec un ecart negatif
-- avait ete essaye pour les resserrer : il les a EMPILEES les unes sur les autres. Une lettre posee a sa place ne
-- peut pas chevaucher sa voisine, et l'animation devient plus simple -- chaque lettre bouge chez elle.
local WORD_COLOR = Color3.fromRGB(102, 102, 102) -- gris : le contour noir fait le reste
-- LA TAILLE DES LETTRES VIENT DE LEUR CASE, VIA `TextScaled`, ET PAS DE `TextSize`.
--
-- C'EST `TextSize` QUI EST PLAFONNE A 100 px, pas TextScaled. Ecrire 0.13, puis 0.205, puis 0.49, puis 0.62 de la
-- hauteur d'ecran n'a donc rien change : les lettres restaient a 100 px, et le mot restait petit quoi qu'on regle.
-- (J'ai d'abord affirme l'inverse -- que TextScaled plafonnait -- c'etait faux, et ca a coute quatre essais.)
--
-- Pour AGRANDIR le mot, on agrandit donc la CASE : `WORD_SCALE`. TextScaled remplit ce qu'on lui donne.
local WORD_SCALE = 0.9 -- multiplie la taille de case relevee. 1 = exactement le montage du joueur
local WORD_STROKE_RATIO = 0.03 -- epaisseur du contour, en fraction de la hauteur de la lettre
local WORD_SIZE = Vector2.new(0.0659, 0.1789) -- taille d'une lettre (identique pour toutes, relevee)
local WORD_Y = 0.6444
local WORD_X = { 0.3777, 0.4225, 0.4808, 0.5371, 0.5762, 0.6215 } -- L E A F I A
-- RESSERREMENT DU MOT : chaque lettre est rapprochee du CENTRE du mot d'autant. 1 = les positions relevees telles
-- quelles ; en dessous, les lettres se rapprochent sans que le mot se decale ni qu'une lettre parte de travers.
-- Les lettres sont maintenant 1.35 fois plus grandes qu'au releve : a ecartement egal, elles se chevauchent
-- d'autant plus. On rend donc l'ecartement du releve (1) au lieu de le resserrer.
local WORD_SPREAD = 0.94
local STATUS_POS = Vector2.new(0.4995, 0.7299)
local STATUS_SIZE = Vector2.new(0.553, 0.0277)

-- UN SON PAR LETTRE, de plus en plus haut : six fois le meme son a la meme hauteur sonne comme une machine, alors
-- qu'une gamme qui monte se lit comme un mot qui s'ecrit. Le son est OPTIONNEL : sur l'ecran de chargement il peut
-- ne pas encore exister (le serveur le pose au demarrage), et dans ce cas on laisse passer en silence.
local LETTER_SOUND = { "Sounds", "UI", "PopSound_1" }
local LETTER_SOUND_VOLUME = 0.25
local LETTER_SOUND_PITCH = 0.9 -- hauteur de la 1re lettre
local LETTER_SOUND_STEP = 0.07 -- de combien elle monte a chaque lettre suivante

-- LE MOT ARRIVE LETTRE PAR LETTRE, puis ne bouge plus : seul le reflet le traverse.
local WORD_STAGGER = 0.07 -- decalage entre deux lettres, a l'arrivee ET dans la vague : c'est lui qui fait la vague
local WORD_DROP = 0.06 -- d'ou la lettre monte, en fraction de la hauteur d'ecran
local WORD_IN = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- LE REFLET, comme sur le titre de chapitre du didacticiel (`Modules/UI/Core/ChapterTitle`) : chaque lettre
-- s'estompe et revient, decalee sur sa voisine.
local WORD_SHINE_DELAY = 0.4 -- apres la pose de la derniere lettre
local WORD_SHINE_STAGGER = 0.04 -- retard entre deux lettres : c'est lui qui fait glisser le reflet
local WORD_SHINE_TIME = 0.3 -- aller-retour d'UNE lettre
local WORD_SHINE_PEAK = 0.7 -- transparence au sommet de la vague
local WORD_SHINE_PERIOD = 2.6 -- temps entre deux passages

-- ===== LA TONDEUSE QUI TOND LA RANGEE D'HERBE, EN BAS =====
local MOWER_IMAGE = "rbxassetid://93898580984673"
local MOWER_SIZE = Vector2.new(0.1262, 0.237)
-- Le BAS de la tondeuse (ancre 0.5, 1). Releve : centre 0.9016 + moitie de 0.237.
local MOWER_GROUND_Y = 1.0201
local MOWER_START_X = -0.12 -- hors ecran a gauche
local MOWER_END_X = 1.12 -- hors ecran a droite
local MOWER_TIME = 7 -- duree d'une traversee, en secondes. KNOB
local MOWER_PAUSE = 1.6 -- temps mort avant le passage suivant (l'herbe repousse hors champ)
-- Ecrasement : elle s'aplatit un peu et s'elargit d'autant, sans quitter le sol.
local MOWER_SQUASH_X, MOWER_SQUASH_Y = 1.04, 0.94
local MOWER_SQUASH_TIME = 0.32

local GRASS_IMAGE = "rbxassetid://90924932701080"
local GRASS_SIZE = Vector2.new(0.0987, 0.1525)
local GRASS_Y = 0.9884 -- centre de la rangee (releve)
local GRASS_START_X = 0.0384 -- centre de la premiere touffe (releve)
local GRASS_STEP = 0.0813 -- ecart entre deux touffes (releve)
local GRASS_CUT = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- vitesse de la coupe
local GRASS_WIPE_EDGE = 0.18 -- douceur du bord de coupe (0 = coupure nette)
-- LE SENS DU BALAYAGE NE SE DEDUIT PAS, il se constate a l'ecran (journal de CLAUDE.md). Si la touffe s'efface du
-- mauvais cote, inverser CE booleen -- il n'y a rien d'autre a changer.
local GRASS_WIPE_FLIP = false

local FOLIAGE_TINT = Color3.new(0, 0, 0)
local FOLIAGE_ALPHA = 0.89 -- KNOB : baisser = feuilles plus sombres (valeur relevee sur la maquette)
-- Taille du groupe, en fraction d'ecran. Assez grand pour contenir les feuillages QUI DEBORDENT (ils encadrent
-- l'ecran) et leur rotation, qui elargit encore leur boite.
local FOLIAGE_GROUP = 3

-- Polices : Luckiest Guy (titres, chunky) et Gotham (le reste). On passe par FontFace + les familles qui LIVRENT
-- avec Roblox : pas de risque d'un Enum.Font absent qui casserait tout l'ecran au lancement.
local FONT_TITLE = Font.new("rbxasset://fonts/families/LuckiestGuy.json")
local FONT_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)

local TITLE_TEXT = "LEAFIA"

-- Messages d'etat qui defilent pendant le chargement. Generiques, aucun nom de jeu connu. A ENRICHIR librement.
local STATUS_MESSAGES = {
	"Shaping the ground",
	"Planting flower beds",
	"Planting the hedges",
	"Getting the tools ready",
	"Opening the job sites",
}

-- ===== Zoom de reveal (fin du loading) : plan large qui se resserre sur le joueur =====
-- Reveal DESACTIVE : le jeu entre par la SELECTION DE PLOT (PlotSelectController pose une camera d'orbite en
-- Scriptable des le spawn, derriere cet ecran). Le loading ne doit donc PLUS faire son propre zoom sur le joueur,
-- sinon les deux cameras se battent (tween bizarre puis saut). Il se contente de fondre : l'orbite deja posee apparait.
local ZOOM_ENABLED = false
local ZOOM_WAIT = 3
local ZOOM_DURATION = 1.5
local ZOOM_FAR_DIST = 42
local ZOOM_FAR_HEIGHT = 26
local ZOOM_FOCUS_HEIGHT = 2
local TWEEN_ZOOM = TweenInfo.new(ZOOM_DURATION, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

-- ===== Petits helpers de construction =====
local function frame(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = WHITE
	f.Parent = parent
	return f
end

local function text(name: string, parent: Instance, font: Font, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.FontFace = font
	t.TextColor3 = color
	t.TextScaled = true
	t.Text = ""
	t.Parent = parent
	return t
end

-- ===== ScreenGui racine =====
local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
-- Plein ecran, bord a bord : None ignore l'inset de la barre Roblox comme la zone de securite de l'appareil. On pose la
-- propriete MODERNE directement (le legacy IgnoreGuiInset ne se traduit pas en None dans les versions recentes : il
-- laissait l'ecran en DeviceSafeInsets, donc un bandeau non couvert en haut).
gui.ScreenInsets = Enum.ScreenInsets.None
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 1000
gui.Parent = player:WaitForChild("PlayerGui")

-- Tout le bloc visuel dans un CanvasGroup : un seul tween sur GroupTransparency le fait fondre a la sortie, sans
-- avoir a citer chaque element.
local root = Instance.new("CanvasGroup")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
-- Plein ecran ET Active : absorbe TOUS les clics pendant le chargement, sinon ils passent a travers et touchent les
-- boutons de l'UI en dessous (on cliquait "a l'aveugle" avant que l'ecran soit parti). Detruit a la fin -> l'UI
-- redevient cliquable pile quand le rideau s'en va. (Le skip est sur la touche Echap, pas un clic : rien casse.)
root.Active = true
root.Parent = gui

-- ===== LE FOND : blanc, et la tuile qui defile par-dessus =====
-- PLUS DE CIEL COLORE : l'ecran est en NOIR ET BLANC. Le fond reste blanc, avec un gris tres leger dans le bas --
-- il pose le sol sous la rangee d'herbe sans dessiner de ligne.
local sky = frame("Sky", root)
sky.Size = UDim2.fromScale(1, 1)
sky.Position = UDim2.fromScale(0, 0)
sky.ZIndex = 1
do
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90 -- vertical : haut -> bas
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.8372, Color3.fromRGB(249, 255, 250)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(193, 193, 193)),
	})
	grad.Parent = sky
end

local tile = Instance.new("ImageLabel")
tile.Name = "Tile"
tile.BackgroundTransparency = 1
tile.Image = TILE_IMAGE
tile.ImageTransparency = TILE_TRANSPARENCY
tile.ScaleType = Enum.ScaleType.Tile
tile.TileSize = UDim2.fromScale(TILE_SCALE_X, TILE_SCALE_Y)
tile.AnchorPoint = Vector2.new(0.5, 0.5)
tile.Position = UDim2.fromScale(0.5, 0.5)
tile.Size = UDim2.fromScale(2, 2) -- deborde largement pour recycler le defilement sans montrer les bords
tile.ZIndex = 2
tile.Parent = root

-- Defilement diagonal : chaque axe recycle sur SA periode (la taille PIXEL de la tuile sur cet axe) pour boucler
-- sans saut. Le modulo garde l'offset dans [0, periode).
local tileOffX, tileOffY = 0, 0
local tileConn: RBXScriptConnection? = nil
tileConn = RunService.Heartbeat:Connect(function(dt: number)
	local periodX = TILE_SCALE_X * tile.AbsoluteSize.X
	local periodY = TILE_SCALE_Y * tile.AbsoluteSize.Y
	if periodX <= 0 or periodY <= 0 then
		return
	end
	tileOffX = (tileOffX + TILE_SPEED * dt) % periodX
	tileOffY = (tileOffY + TILE_SPEED * dt) % periodY
	tile.Position = UDim2.new(0.5, tileOffX, 0.5, tileOffY)
end)

-- ===== LE CENTRE : tete, onomatopee, mot, texte de chargement =====
-- POSES DIRECTEMENT SUR LE FOND, aux valeurs relevees sur l'ecran monte a la main.
local function place(gui: GuiObject, pos: Vector2, size: Vector2)
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = UDim2.fromScale(pos.X, pos.Y)
	gui.Size = UDim2.fromScale(size.X, size.Y)
end

-- LE DEGRADE QUI EFFACE LE BAS DES IMAGES NOIRES : c'est lui qui donne le fondu gris de la tete et de l'onomatopee.
-- Blanc uni, transparence de 0 a 1 : seule la transparence travaille, la couleur ne sert qu'a exister.
local function fadeGradient(parent: Instance)
	local grad = Instance.new("UIGradient")
	grad.Rotation = ART_FADE_ROTATION
	grad.Color = ColorSequence.new(WHITE)
	grad.Transparency = NumberSequence.new(0, 1)
	grad.Parent = parent
end

local face = Instance.new("ImageLabel")
face.Name = "Face"
face.BackgroundTransparency = 1
face.Image = FACE_IMAGE
face.ImageColor3 = INK
face.ScaleType = Enum.ScaleType.Fit -- garde ses proportions quel que soit l'ecran
face.ZIndex = 5
place(face, FACE_POS, FACE_SIZE)
fadeGradient(face)
face.Parent = root

-- LE CLIGNEMENT, en changeant d'image. Rien a faire tant que les deux variantes ne sont pas fournies : mieux vaut un
-- visage qui ne cligne pas qu'une image vide au milieu de l'ecran.
if FACE_SHUT_IMAGE ~= "" then
	task.spawn(function()
		while face.Parent do
			-- Un ecart CONSTANT se lit comme un metronome : on ajoute du hasard.
			task.wait(FACE_BLINK_EVERY + math.random() * FACE_BLINK_JITTER)
			if not face.Parent then
				return
			end
			if FACE_HALF_IMAGE ~= "" then
				face.Image = FACE_HALF_IMAGE
				task.wait(FACE_BLINK_HALF_TIME)
			end
			face.Image = FACE_SHUT_IMAGE
			task.wait(FACE_BLINK_SHUT_TIME)
			if FACE_HALF_IMAGE ~= "" then
				face.Image = FACE_HALF_IMAGE
				task.wait(FACE_BLINK_HALF_TIME)
			end
			face.Image = FACE_IMAGE
		end
	end)
end

-- L'ONOMATOPEE (les trois eclats a cote de la tete). Elle apparait au debut de chaque passage de tondeuse : posee
-- une fois pour toutes, elle ferait partie du decor et on ne la verrait plus.
local shout = Instance.new("ImageLabel")
shout.Name = "Shout"
shout.BackgroundTransparency = 1
shout.Image = SHOUT_IMAGE
shout.ImageColor3 = INK
shout.ImageTransparency = 1
shout.ScaleType = Enum.ScaleType.Fit
shout.Rotation = SHOUT_ROT + SHOUT_TILT
shout.ZIndex = 5
place(shout, SHOUT_POS, SHOUT_SIZE * SHOUT_POP)
fadeGradient(shout)
shout.Parent = root

-- MOT "LEAFIA", LETTRE PAR LETTRE, chacune a sa place relevee.
local letters: { TextLabel } = {}
for i = 1, #TITLE_TEXT do
	local letter = text("Letter" .. i, root, FONT_TITLE, WORD_COLOR)
	letter.Text = TITLE_TEXT:sub(i, i)
	letter.TextScaled = true -- la lettre remplit sa case ; c'est la case qui donne la taille (voir WORD_SCALE)
	letter.RichText = true
	letter.ZIndex = 9
	local home_x = WORD_X[i] or 0.5
	local middle = ((WORD_X[1] or 0.5) + (WORD_X[#WORD_X] or 0.5)) / 2
	place(letter, Vector2.new(middle + (home_x - middle) * WORD_SPREAD, WORD_Y), WORD_SIZE * WORD_SCALE)

	-- LE CONTOUR NOIR, en fraction de la HAUTEUR de la lettre : en pixels fixes il serait gras sur telephone et fin
	-- sur grand ecran. `Contextual` suit le texte, pas la boite.
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = letter
	-- Le contour suit la HAUTEUR REELLE de la lettre, relue a chaque changement d'ecran (rotation, resize) : en
	-- pixels fixes il serait gras sur telephone et fin sur grand ecran.
	local function fitStroke()
		stroke.Thickness = math.max(letter.AbsoluteSize.Y * WORD_STROKE_RATIO, 1)
	end
	fitStroke()
	letter:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitStroke)

	letters[i] = letter

	-- ARRIVEE : la lettre monte d'en dessous en s'allumant, l'une apres l'autre. Sa place finale est SA place : on
	-- part de plus bas, on y revient.
	local home = letter.Position
	local from = UDim2.new(home.X.Scale, home.X.Offset, home.Y.Scale + WORD_DROP, home.Y.Offset)
	letter.TextTransparency = 1
	stroke.Transparency = 1
	letter.Position = from
	task.delay((i - 1) * WORD_STAGGER, function()
		if not letter.Parent then
			return
		end
		-- LE SON DE LA LETTRE. Cherche au moment de jouer, pas au boot : a l'ouverture de l'ecran, le serveur n'a pas
		-- forcement encore pose les sons.
		local click = findSound(LETTER_SOUND)
		if click then
			playSound(click, LETTER_SOUND_VOLUME, LETTER_SOUND_PITCH + (i - 1) * LETTER_SOUND_STEP)
		end
		-- ELLE ARRIVE ET ELLE RESTE : aucune ondulation ensuite. Le mot doit se lire pose, pas flotter.
		TweenService:Create(letter, WORD_IN, { Position = home, TextTransparency = 0 }):Play()
		TweenService:Create(stroke, WORD_IN, { Transparency = 0 }):Play()
		-- LA DERNIERE LETTRE APPELLE L'ONOMATOPEE : elle jaillit comme si le "A" venait de la projeter.
		if i == #TITLE_TEXT then
			TweenService:Create(shout, SHOUT_IN, {
				ImageTransparency = 0,
				Rotation = SHOUT_ROT,
				Size = UDim2.fromScale(SHOUT_SIZE.X, SHOUT_SIZE.Y),
			}):Play()
		end
	end)
end

-- LE REFLET QUI TRAVERSE LE MOT, en boucle. Une seule tache pour tout le mot : c'est elle qui tient l'ordre des
-- lettres, et le decalage entre elles fait glisser la lumiere de gauche a droite.
task.spawn(function()
	task.wait((#letters - 1) * WORD_STAGGER + WORD_IN.Time + WORD_SHINE_DELAY)
	while root.Parent do
		for i, letter in ipairs(letters) do
			task.delay((i - 1) * WORD_SHINE_STAGGER, function()
				if not letter.Parent then
					return
				end
				local half = TweenInfo.new(WORD_SHINE_TIME / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				local dim = TweenService:Create(letter, half, { TextTransparency = WORD_SHINE_PEAK })
				dim.Completed:Once(function()
					if letter.Parent then
						TweenService:Create(letter, half, { TextTransparency = 0 }):Play()
					end
				end)
				dim:Play()
			end)
		end
		task.wait(WORD_SHINE_PERIOD)
	end
end)

-- TEXTE D'ETAT ("Planting flower beds..."), juste sous le mot.
local statusText = text("Status", root, FONT_BOLD, INK)
statusText.RichText = true
statusText.ZIndex = 6
place(statusText, STATUS_POS, STATUS_SIZE)

-- ===== LA TONDEUSE ET L'HERBE DU BAS =====
-- L'HERBE EST GENEREE, pas posee une par une : une rangee reguliere se decrit par un pas et une hauteur, et elle
-- s'adapte alors a n'importe quelle largeur d'ecran. Les toucher a la main obligerait a les repositionner toutes a
-- chaque changement.
local grassRow = frame("GrassRow", root)
grassRow.BackgroundTransparency = 1
grassRow.AnchorPoint = Vector2.new(0.5, 0.5)
grassRow.Position = UDim2.fromScale(0.5, 0.5)
grassRow.Size = UDim2.fromScale(1, 1)
grassRow.ZIndex = 7

type Blade = { gui: ImageLabel, grad: UIGradient, x: number, cut: boolean }
local blades: { Blade } = {}
local x = GRASS_START_X
while x < 1 + GRASS_STEP do
	local blade = Instance.new("ImageLabel")
	blade.Name = "Grass"
	blade.BackgroundTransparency = 1
	blade.Image = GRASS_IMAGE
	blade.ImageColor3 = INK
	blade.AnchorPoint = Vector2.new(0.5, 0.5)
	blade.Position = UDim2.fromScale(x, GRASS_Y)
	blade.Size = UDim2.fromScale(GRASS_SIZE.X, GRASS_SIZE.Y)
	blade.ZIndex = 7
	blade.Parent = grassRow

	-- LA COUPE PASSE PAR UN DEGRADE, comme le joueur l'a demande : une bande transparente balaie la touffe de gauche
	-- a droite, dans le sens de la tondeuse.
	--
	-- LE SENS D'UN `UIGradient.Offset` NE SE DEDUIT PAS, il se constate a l'ecran (deja paye, voir le journal de
	-- CLAUDE.md). D'ou `GRASS_WIPE_FLIP` : si la touffe s'efface du mauvais cote, on inverse ce booleen, on ne
	-- reecrit rien.
	local grad = Instance.new("UIGradient")
	grad.Rotation = 0
	grad.Color = ColorSequence.new(WHITE)
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(math.min(0.5 + GRASS_WIPE_EDGE, 0.999), 0),
		NumberSequenceKeypoint.new(1, 0),
	})
	grad.Offset = Vector2.new(if GRASS_WIPE_FLIP then 1 else -1, 0)
	grad.Parent = blade

	table.insert(blades, { gui = blade, grad = grad, x = x, cut = false })
	x += GRASS_STEP
end

local mower = Instance.new("ImageLabel")
mower.Name = "Mower"
mower.BackgroundTransparency = 1
mower.Image = MOWER_IMAGE
mower.ImageColor3 = INK
-- ANCRE EN BAS AU MILIEU : l'ecrasement se fait alors vers le sol, comme une vraie masse posee dessus. Ancree au
-- centre, la tondeuse s'enfoncerait ET se souleverait a chaque pas.
mower.AnchorPoint = Vector2.new(0.5, 1)
mower.Size = UDim2.fromScale(MOWER_SIZE.X, MOWER_SIZE.Y)
mower.Position = UDim2.fromScale(MOWER_START_X, MOWER_GROUND_Y)
mower.ZIndex = 9
mower.Parent = root

-- ECRASEMENT : elle s'aplatit et se retend sans arret, sans jamais quitter le sol. Sur la TAILLE et pas la position :
-- un rebond la ferait sauter, or elle roule.
TweenService:Create(
	mower,
	TweenInfo.new(MOWER_SQUASH_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Size = UDim2.fromScale(MOWER_SIZE.X * MOWER_SQUASH_X, MOWER_SIZE.Y * MOWER_SQUASH_Y) }
):Play()

-- LE PASSAGE : la tondeuse traverse, et chaque touffe se fait couper QUAND ELLE LA DEPASSE. On avance la position a
-- la main image par image plutot qu'en tween, justement pour pouvoir comparer -- un tween ne dit pas ou il en est.
local mowConn: RBXScriptConnection? = nil
task.spawn(function()
	while root.Parent do
		local travelled = 0
		for _, blade in blades do
			blade.cut = false
			blade.grad.Offset = Vector2.new(if GRASS_WIPE_FLIP then 1 else -1, 0)
			blade.gui.ImageTransparency = 0
		end
		local done = false
		mowConn = RunService.Heartbeat:Connect(function(dt: number)
			travelled += dt / MOWER_TIME
			local pos = MOWER_START_X + (MOWER_END_X - MOWER_START_X) * math.min(travelled, 1)
			mower.Position = UDim2.fromScale(pos, MOWER_GROUND_Y)
			for _, blade in blades do
				if not blade.cut and pos >= blade.x then
					blade.cut = true
					TweenService:Create(blade.grad, GRASS_CUT, {
						Offset = Vector2.new(if GRASS_WIPE_FLIP then -1 else 1, 0),
					}):Play()
				end
			end
			if travelled >= 1 then
				done = true
			end
		end)
		repeat
			task.wait(0.1)
		until done or not root.Parent
		if mowConn then
			mowConn:Disconnect()
			mowConn = nil
		end
		-- L'HERBE REPOUSSE HORS CHAMP : la tondeuse est sortie par la droite, personne ne voit le retour.
		task.wait(MOWER_PAUSE)
	end
end)

-- ===== FEUILLAGES qui encadrent l'ecran (entree en eventail + flottement) =====
-- INLINE, comme tout ce fichier (autonome : pas de require de ReplicatedStorage). Meme idee que le module reutilisable
-- UI/Core/FoliageReveal, reduite a ce dont le loading a besoin : les feuillages JAILLISSENT depuis l'exterieur, arrivent
-- a leur place, puis flottent doucement. La position POSEE ici est la position finale ; le depart est CALCULE en la
-- projetant vers l'exterieur du centre. { image, x, y = position scale ; w, h = taille scale ; rot } ; tous ancres (0.5, 1).
-- { image ; x, y = CENTRE en fraction d'ecran ; w, h = taille en fraction d'ecran ; rot = degres }. Releve tel quel
-- sur l'ecran monte a la main : ils debordent volontairement (x et y hors de [0, 1]), ils encadrent l'ecran.
type FoliageEntry = { image: string, x: number, y: number, w: number, h: number, rot: number }
local FOLIAGE_DATA: { FoliageEntry } = {
	{ image = "rbxassetid://120457348978315", x = -0.1309, y = -0.0111, w = 0.2156, h = 0.407, rot = 103 },
	{ image = "rbxassetid://120457348978315", x = -0.1776, y = 0.3517, w = 0.2156, h = 0.407, rot = 103 },
}
local FOLIAGE_SPREAD = 1.55 -- d'ou ils partent (position projetee vers l'exterieur). KNOB
local FOLIAGE_STAGGER = 0.03 -- decalage entre 2 feuillages a l'arrivee (l'eventail). KNOB
local FOLIAGE_AMPLITUDE = 0.03 -- hauteur du flottement (scale). KNOB
-- Etirement au DEPART (multiplie la taille normale), qui se pose a la normale a l'arrivee EN MEME TEMPS que le move :
-- un peu plus long (Y) et un peu plus fin (X) -> effet d'etirement dynamique. 1 = pas d'etirement. KNOB
local FOLIAGE_STRETCH_X = 0.94
local FOLIAGE_STRETCH_Y = 1.12
local FOLIAGE_IN = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- Back = petit depassement (pos ET taille)

-- CanvasGroup et pas Frame : c'est le GROUPE qui porte la transparence, donc deux feuilles qui se recouvrent ne
-- font pas une tache plus sombre a leur intersection (voir FOLIAGE_ALPHA).
-- Conversion ECRAN -> GROUPE : le groupe fait FOLIAGE_GROUP fois l'ecran, donc un ecart au centre y est divise
-- d'autant, et une taille aussi. Les valeurs de FOLIAGE_DATA restent lisibles en fraction d'ECRAN.
local FOLIAGE_FACTOR = 1 / FOLIAGE_GROUP
local function toHolder(v: number): number
	return 0.5 + (v - 0.5) * FOLIAGE_FACTOR
end

local foliageHolder = Instance.new("CanvasGroup")
foliageHolder.Name = "HolderFoliage"
foliageHolder.AnchorPoint = Vector2.new(0.5, 0.5)
foliageHolder.Position = UDim2.fromScale(0.5, 0.5)
foliageHolder.Size = UDim2.fromScale(FOLIAGE_GROUP, FOLIAGE_GROUP)
foliageHolder.BackgroundTransparency = 1
foliageHolder.BorderSizePixel = 0
foliageHolder.GroupTransparency = FOLIAGE_ALPHA
foliageHolder.ZIndex = 8 -- par-dessus le fond : ils encadrent l'ecran (le contenu central est ailleurs)
foliageHolder.Parent = root

local foliageIdle: { Tween } = {}
for i, d in FOLIAGE_DATA do
	local leaf = Instance.new("ImageLabel")
	leaf.Name = "Foliage" .. i
	leaf.BackgroundTransparency = 1
	leaf.Image = d.image
	leaf.ImageColor3 = FOLIAGE_TINT
	-- ANCRE AU CENTRE : les valeurs relevees sont des CENTRES, et c'est aussi autour du centre que Roblox fait tourner
	-- un element -- les deux coincident, donc la rotation ne deplace rien.
	leaf.AnchorPoint = Vector2.new(0.5, 0.5)
	leaf.Rotation = d.rot
	leaf.ZIndex = 8
	leaf.Parent = foliageHolder

	local openPos = UDim2.fromScale(toHolder(d.x), toHolder(d.y))
	local openSize = UDim2.fromScale(d.w * FOLIAGE_FACTOR, d.h * FOLIAGE_FACTOR)
	-- depart : projete vers l'exterieur du centre du holder (0.5, 0.5), donc chacun sort de son bon cote ; et ETIRE
	-- (plus long, plus fin) -> il se pose a sa taille normale EN MEME TEMPS que le move, pour la dynamique.
	leaf.Position = UDim2.fromScale(
		toHolder(0.5 + (d.x - 0.5) * FOLIAGE_SPREAD),
		toHolder(0.5 + (d.y - 0.5) * FOLIAGE_SPREAD)
	)
	leaf.Size = UDim2.fromScale(d.w * FOLIAGE_STRETCH_X * FOLIAGE_FACTOR, d.h * FOLIAGE_STRETCH_Y * FOLIAGE_FACTOR)
	local dur = 1.9 + ((i * 0.37) % 1) * 1.1 -- flottement varie mais STABLE par feuillage (pas de random par frame)
	task.delay((i - 1) * FOLIAGE_STAGGER, function()
		if not leaf.Parent then
			return
		end
		local inTween = TweenService:Create(leaf, FOLIAGE_IN, { Position = openPos, Size = openSize })
		inTween:Play()
		inTween.Completed:Connect(function()
			if not leaf.Parent then
				return
			end
			-- flottement : monte de AMPLITUDE puis redescend, en boucle qui s'inverse (Sine)
			local up = UDim2.fromScale(toHolder(d.x), toHolder(d.y - FOLIAGE_AMPLITUDE))
			local t = TweenService:Create(
				leaf,
				TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Position = up }
			)
			t:Play()
			foliageIdle[#foliageIdle + 1] = t
		end)
	end)
end

-- ===== Etat / skip =====
local skipRequested = false
local function skipLoading()
	skipRequested = true
end
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		skipLoading()
	end
end)

-- ===== Masquage chat + liste joueurs (CoreGui, par-dessus notre ScreenGui) =====
local HIDDEN_CORE_GUIS = { Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList }
local CORE_GUI_SAFETY_DELAY = 60
local coreGuiPrevious: { [Enum.CoreGuiType]: boolean } = {}
local coreGuiRestored = false
local chatWindow = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")

local function hideCoreGuis()
	if chatWindow then
		chatWindow.Enabled = false
	end
	task.spawn(function()
		local pending = table.clone(HIDDEN_CORE_GUIS)
		local deadline = os.clock() + 5
		while #pending > 0 and not coreGuiRestored and os.clock() < deadline do
			for i = #pending, 1, -1 do
				local coreGuiType = pending[i]
				local ok = pcall(function()
					if coreGuiPrevious[coreGuiType] == nil then
						coreGuiPrevious[coreGuiType] = StarterGui:GetCoreGuiEnabled(coreGuiType)
					end
					StarterGui:SetCoreGuiEnabled(coreGuiType, false)
				end)
				if ok then
					table.remove(pending, i)
				end
			end
			if #pending > 0 then
				RunService.Heartbeat:Wait()
			end
		end
	end)
end

local function restoreCoreGuis()
	if coreGuiRestored then
		return
	end
	coreGuiRestored = true
	for coreGuiType, wasEnabled in pairs(coreGuiPrevious) do
		-- Le PLAYERLIST et le CHAT restent coupes apres le chargement : dans la place principale, le MENU (LoadSave UI :
		-- choix du plot et de la save) suit l'ecran de chargement et doit rester epure. C'est PlotSelectController qui les
		-- RALLUME a l'entree en jeu. Cette branche (ecran herbe) ne s'atteint QUE dans la place principale au 1er
		-- lancement direct, donc un menu suit TOUJOURS ici. En place secondaire (rideau gris) chat / playerlist reviennent normalement.
		if coreGuiType ~= Enum.CoreGuiType.PlayerList and coreGuiType ~= Enum.CoreGuiType.Chat then
			pcall(function()
				StarterGui:SetCoreGuiEnabled(coreGuiType, wasEnabled)
			end)
		end
	end
	-- La fenetre de chat (chatWindow) reste coupee elle aussi : rallumee a l'entree en jeu (PlotSelectController).
end

hideCoreGuis()
task.delay(CORE_GUI_SAFETY_DELAY, restoreCoreGuis)

-- ===== Sons (tous OPTIONNELS, aucun warn si absent) =====
local SOUND_MUSIC = { "GameSounds", "Musics", "Loading Screen" }
-- Musique du MENU (fond) : lancee a la SORTIE du loading (pendant le reveal), joue pendant la selection de plot, puis
-- fondue a 0 a l'entree dans le jeu (PlotSelectController). Chemin calque sur l'arbre Studio. Autonome : on clone /
-- joue le Sound direct, aucun require de ReplicatedStorage.
local SOUND_GAME_MUSIC = { "Sounds", "Game", "Musics", "MusicMainMenu" }
-- Volume FORCE de la musique du jeu (le reglage du Sound dans Studio est donc ignore ici). A regler a l'oreille.
local GAME_MUSIC_VOLUME = 0.04
local loadingMusic: Sound? = nil
do
	local source = findSound(SOUND_MUSIC)
	if source then
		local music = source:Clone()
		music.Looped = true
		music.Parent = SoundService
		music:Play()
		loadingMusic = music
	end
end

-- ===== Moniteur de FPS (moyenne glissante) : asservit la collecte / le prechargement =====
local currentFPS = 60
local fpsConn: RBXScriptConnection? = nil
do
	local frameTimes: { number } = {}
	fpsConn = RunService.Heartbeat:Connect(function(dt: number)
		table.insert(frameTimes, dt)
		if #frameTimes > 20 then
			table.remove(frameTimes, 1)
		end
		local sum = 0
		for _, ft in ipairs(frameTimes) do
			sum += ft
		end
		if sum > 0 then
			currentFPS = #frameTimes / sum
		end
	end)
end

-- ===== Etat de sortie : `ready` passe a true quand on peut sortir (tout charge ET duree minimale ecoulee). =====
local ready = false
local screenStart = os.clock() -- reference du temps a l'ecran (duree minimale avant de pouvoir sortir)

-- ===== Collecte des assets a precharger (asservie au FPS) =====
local LOADABLE: { [string]: boolean } = {
	Decal = true,
	Texture = true,
	ImageLabel = true,
	ImageButton = true,
	MeshPart = true,
	SpecialMesh = true,
	FileMesh = true,
	Sound = true,
	Animation = true,
	ParticleEmitter = true,
	Shirt = true,
	Pants = true,
	ShirtGraphic = true,
	SurfaceAppearance = true,
}
local seen: { [Instance]: boolean } = {}
local assetsToLoad: { Instance } = {}
local collectFinished = false
local TARGET_FPS = 25

local function collect(container: Instance)
	local descendants = container:GetDescendants()
	local i = 1
	local n = #descendants
	while i <= n do
		local chunk: number
		if currentFPS >= TARGET_FPS then
			chunk = 40
		elseif currentFPS >= 15 then
			chunk = 12
		else
			chunk = 4
		end
		local processed = 0
		while i <= n and processed < chunk do
			local inst = descendants[i]
			if LOADABLE[inst.ClassName] and not seen[inst] then
				seen[inst] = true
				assetsToLoad[#assetsToLoad + 1] = inst
			end
			i += 1
			processed += 1
		end
		RunService.Heartbeat:Wait()
		if currentFPS < 15 or skipRequested then
			RunService.Heartbeat:Wait()
		end
	end
end

task.spawn(function()
	collect(game:GetService("ReplicatedStorage"))
	collect(game:GetService("StarterGui"))
	collect(game:GetService("SoundService"))
	collectFinished = true
end)

-- ===== Texte d'etat qui defile (PLUS de barre ni de %) : une barre en pourcentage fait COMPTER le temps au joueur
-- ("putain c'est long"). Un texte qui change donne l'impression que le monde se construit sous ses yeux. =====
local statusIndex = 1
local function refreshStatus()
	statusText.Text = STATUS_MESSAGES[statusIndex] .. "..."
end
refreshStatus()

task.spawn(function()
	while not skipRequested and not ready do
		task.wait(1.6)
		statusIndex = statusIndex % #STATUS_MESSAGES + 1
		if not ready then
			refreshStatus()
		end
	end
end)

-- ===== Attente du jeu charge =====
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- ===== Prechargement (continue en fond meme apres un skip) =====
local preloadFinished = false
task.spawn(function()
	while not collectFinished do
		RunService.Heartbeat:Wait()
	end
	local batchSize = if skipRequested then 20 else 15
	local i = 1
	local n = #assetsToLoad
	while i <= n do
		local batch: { Instance } = {}
		for j = i, math.min(i + batchSize - 1, n) do
			batch[#batch + 1] = assetsToLoad[j]
		end
		pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)
		i += #batch
		if skipRequested then
			task.wait(0.2)
		else
			RunService.Heartbeat:Wait()
			if currentFPS < TARGET_FPS then
				task.wait(0.05)
			end
		end
	end
	preloadFinished = true
end)

-- ===== Sortie : quand tout est pret ET la duree minimale passee, OU sur skip =====
while not skipRequested do
	if preloadFinished and os.clock() - screenStart >= MIN_DURATION then
		break
	end
	RunService.Heartbeat:Wait()
end

-- Etat final "Ready!" avant le fondu de sortie ; on le laisse une image a l'ecran.
ready = true
statusText.Text = "Ready!"
task.wait(if skipRequested then 0 else 0.35)

-- ============================================================
-- ===== SORTIE : fondu + zoom de reveal =====
-- ============================================================
local TWEEN_FADE = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local camera = workspace.CurrentCamera

local function zoomShot(anchor: BasePart, dist: number, height: number): CFrame
	local focus = anchor.Position + Vector3.new(0, ZOOM_FOCUS_HEIGHT, 0)
	local back = anchor.CFrame.LookVector
	return CFrame.lookAt(focus - back * dist + Vector3.new(0, height, 0), focus)
end

local zoomRoot: BasePart? = nil
local zoomFarCFrame: CFrame? = nil
local zoomGameCFrame: CFrame? = nil
do
	local deadline = os.clock() + ZOOM_WAIT
	local charRoot: BasePart? = nil
	repeat
		local char = player.Character
		local found = char and char:FindFirstChild("HumanoidRootPart")
		if found and found:IsA("BasePart") then
			charRoot = found
			break
		end
		RunService.Heartbeat:Wait()
	until os.clock() >= deadline

	if ZOOM_ENABLED and camera and charRoot then
		zoomRoot = charRoot
		-- ARRIVEE = un plan DERRIERE le joueur, a la DISTANCE et la HAUTEUR de la camera de jeu capturee. On FORCE le
		-- derriere (via le LookVector du perso) : la camera de jeu au spawn est parfois DEVANT lui (angle herite), et le
		-- reveal finissait alors FACE a lui. En gardant la distance de la camera de jeu, Custom (meme zoom) reprend au
		-- meme endroit sans saut, et comme il conserve l'angle courant, il reste DERRIERE.
		local focus = charRoot.Position + Vector3.new(0, ZOOM_FOCUS_HEIGHT, 0)
		local gameOffset = camera.CFrame.Position - focus
		local gameDist = math.max(Vector3.new(gameOffset.X, 0, gameOffset.Z).Magnitude, 8)
		zoomGameCFrame = zoomShot(charRoot, gameDist, gameOffset.Y)
		-- On ANCRE le joueur le temps du reveal : sinon, s'il marche et tourne, le re-cadrage ecrase sa rotation
		-- et le suivi parait saccade. Immobile, le cinematique reste propre. On lui rend le controle a la fin.
		charRoot.Anchored = true
		zoomFarCFrame = zoomShot(charRoot, ZOOM_FAR_DIST, ZOOM_FAR_HEIGHT)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = zoomFarCFrame
	end
end

-- Fondu de tout le bloc en une fois (CanvasGroup). Le zoom part EN MEME TEMPS et dure plus longtemps.
local fade = TweenService:Create(root, TWEEN_FADE, { GroupTransparency = 1 })
fade:Play()

-- MUSIQUE DU JEU : demarre AVEC le reveal. Elle boucle et vit sur SoundService, donc elle survit a la destruction
-- de l'ecran. Volume force a GAME_MUSIC_VOLUME (le reglage du Sound dans Studio est ignore).
do
	local source = findSound(SOUND_GAME_MUSIC)
	if source then
		local music = source:Clone()
		music.Name = "GameMusic" -- nom stable pour que le jeu puisse la retrouver (ex : la faire fondre a l'entree)
		music.Looped = true
		music.Volume = GAME_MUSIC_VOLUME
		music.Parent = SoundService
		music:Play()
	else
		-- Musique ATTENDUE (pas un son decoratif optionnel) : si elle manque, on le signale -- anormal ET actionnable.
		warn(`[LoadingScreen] Musique du jeu introuvable : SoundService.{table.concat(SOUND_GAME_MUSIC, ".")}`)
	end
end

local zoomActive = zoomRoot ~= nil and camera ~= nil and zoomFarCFrame ~= nil and zoomGameCFrame ~= nil
local zoomDone = not zoomActive
if zoomActive then
	local cam = camera :: Camera
	local far = zoomFarCFrame :: CFrame
	local target = zoomGameCFrame :: CFrame
	task.spawn(function()
		local duration = TWEEN_ZOOM.Time
		local start = os.clock()
		while true do
			local raw = if duration > 0 then math.clamp((os.clock() - start) / duration, 0, 1) else 1
			local a = TweenService:GetValue(raw, TWEEN_ZOOM.EasingStyle, TWEEN_ZOOM.EasingDirection)
			cam.CFrame = far:Lerp(target, a)
			if raw >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		zoomDone = true
	end)
end
fade.Completed:Wait()

-- ===== Nettoyage des connexions (elles vivent sur RunService, pas sur le GUI) =====
if tileConn then
	tileConn:Disconnect()
end
for _, t in foliageIdle do
	t:Cancel() -- couper le flottement des feuillages (boucles infinies) avant de detruire l'ecran
end
if fpsConn then
	fpsConn:Disconnect()
end

gui:Destroy()
player:SetAttribute("LeafiaLoadingDone", true) -- signal pour l'UI (ex : entree du top bar de selection) : l'ecran est parti
restoreCoreGuis()

-- Retour a la camera de jeu (Custom) une fois le zoom fini : couper avant ferait sauter l'image.
if zoomActive then
	while not zoomDone do
		RunService.Heartbeat:Wait()
	end
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
	if zoomRoot and zoomRoot.Parent then
		zoomRoot.Anchored = false
	end
end

if loadingMusic then
	local fadeOut = TweenService:Create(loadingMusic, TWEEN_FADE, { Volume = 0 })
	fadeOut:Play()
	fadeOut.Completed:Wait()
	loadingMusic:Destroy()
end
