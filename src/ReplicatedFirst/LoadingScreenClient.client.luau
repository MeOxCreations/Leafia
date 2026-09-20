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
	-- ON NETTOIE SUR `Ended`, jamais sur un delai. Ce delai etait fixe a 5 s -- valeur ecrite pour les petits pops
	-- des lettres -- et il COUPAIT en silence tout son plus long : le son d'arrivee s'arretait en plein milieu.
	-- Debris ne reste qu'en FILET, au cas ou `Ended` ne tirerait jamais (asset introuvable), et avec une valeur
	-- large plutot qu'ajustee : une borne ne doit jamais etre plus serree que ce qu'elle borne.
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, math.max(sound.TimeLength + 5, 60))
	return sound
end

-- ===== Assets EN DUR + destruction de l'ancien ecran s'il traine =====
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
local FACE_IMAGE = "rbxassetid://107162385671697" -- la tete SANS les yeux
-- LES YEUX SONT DES CALQUES A PART, dessines aux MEMES DIMENSIONS que la tete : poses par-dessus en taille (1, 1),
-- ils tombent pile en place, sans un seul chiffre a regler. Les faire regarder ailleurs revient alors a DECALER le
-- calque -- et comme ils sont tous dans le meme cadre, ils ne peuvent pas se desaligner entre eux.
local EYE = {
	LEFT = "rbxassetid://130322074892629",
	RIGHT = "rbxassetid://108086469738634",
	SHUT = "rbxassetid://80743235106162", -- les deux fermes
	WINK = "rbxassetid://133495431262696", -- l'oeil droit ferme : le clin d'oeil
	SOUND = { "Sounds", "UI", "EyeWinkSound" },
	-- ECARTEMENT, en fraction de la largeur de la tete : chaque oeil glisse vers son cote. Rectification faite
	-- ICI plutot que dans l'image, tant qu'elle reste petite. A NOTER : le calque des DEUX yeux fermes ne peut
	-- pas suivre (ses deux yeux sont dans la meme image), donc un ecart trop grand se verrait au clignement.
	SPREAD = 0.008, -- KNOB
	SOUND_VOLUME = 0.6,
	-- LE CLIN D'OEIL EST UN MOMENT ECRIT, PAS UN HASARD : il tombe a la FIN du son d'arrivee.
	--
	-- MAIS IL NE PEUT PAS DEPENDRE DE CE SON SEUL. `Ended` ne tire pas si le son n'a pas pu se telecharger, et
	-- si le son se termine AVANT que la tete ne sorte, le geste partait colle a son apparition -- le clin d'oeil
	-- tombait alors dans le meme instant que la derniere lettre, et on ne lisait plus rien.
	--
	-- LE GESTE ATTEND DONC DEUX CHOSES : que le son d'arrivee soit fini, ET une respiration apres la tete. La
	-- limite borne l'attente du son, pour qu'un son qui ne finit jamais n'emporte pas le geste avec lui.
	AFTER_FACE = 0.5, -- respiration entre l'arrivee de la tete et le clin d'oeil. KNOB
	-- COURTE : ce n'est PAS le temps du son, c'est le temps qu'on accepte de l'attendre. A 4 s, un son d'arrivee
	-- de quelques secondes repoussait le clin d'oeil au-dela de la fin du chargement : le geste n'arrivait jamais
	-- alors que tout le code etait bon. Un ecran de chargement rapide ne laisse que quelques secondes en tout.
	WINK_DEADLINE = 1.2,
	DEBUG = true, -- une ligne en console qui dit CE QUI a declenche le clin d'oeil. A repasser a false ensuite.
	-- Ecart entre deux clignements, plus du hasard : toutes les N secondes pile, ca se lit comme un metronome.
	BLINK_EVERY = 3.2,
	BLINK_JITTER = 2.4,
	SHUT_TIME = 0.09,
	WINK_TIME = 0.18, -- un clin d'oeil se TIENT, il ne claque pas comme un clignement
	-- LE SON ANNONCE, L'OEIL SE FERME SUR SA DERNIERE NOTE. On attend donc la duree du son avant de fermer. Cette
	-- duree n'est connue qu'une fois le son telecharge (`TimeLength` vaut 0 avant) : on la laisse arriver, et on
	-- retombe sur une valeur de secours si elle ne vient pas -- sinon le geste partirait instantanement.
	CLING_FALLBACK = 0.5,
	CLING_OFFSET = -0.05, -- avance (negatif) ou retard sur la derniere note. KNOB, a caler a l'oreille
	-- LA TETE PENCHE PENDANT LE CLIN D'OEIL. L'inclinaison part AVEC le son et se redresse apres : la tete
	-- accompagne le geste au lieu de le subir. Sur le GROUPE et non sur l'image : le CanvasGroup tourne son rendu
	-- entier, donc rien n'est rogne aux coins.
	TILT = 7, -- degres. KNOB
	TILT_IN = 0.35, -- temps pour pencher
	TILT_HOLD = 1, -- temps ou la tete reste penchee APRES la reouverture de l'oeil. KNOB
	TILT_OUT = 0.5, -- temps pour se redresser : plus lent, la tete "revient" au lieu de claquer
}

-- LE REGARD. Le cadre des yeux glisse de quelques pour cent seulement : au-dela, les pupilles sortiraient des
-- paupieres dessinees sur la tete.
local GAZE = {
	X = 0.016, -- amplitude horizontale, en fraction de la tete. KNOB
	Y = 0.007,
	EVERY = 1.3, -- temps entre deux coups d'oeil
	JITTER = 1.9,
	TIME = 0.22, -- duree du deplacement
}
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
-- COURT : elle doit jaillir AVEC le retour du A, pas arriver apres coup. A 0.55 s elle trainait une demi-seconde
-- derriere le geste qui est cense la projeter.
local SHOUT_IN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- ELLE NE RESTE PAS. Un eclat d'onomatopee qui s'installe devient un element de decor : il doit jaillir et partir.
local SHOUT_SOUND = { "Sounds", "UI", "AppearSound_1" }
local SHOUT_SOUND_VOLUME = 0.5
local SHOUT_SOUND_PITCH = 0.92 -- un peu bas : ca donne du poids a l'eclat
local SHOUT_HOLD = 0.1 -- temps d'affichage une fois arrivee
local SHOUT_OUT = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHOUT_OUT_GROW = 1.25 -- elle grossit en s'effacant : ca se lit comme un eclat qui se dissipe

-- LA TETE ARRIVE AVEC UNE LETTRE, elle n'est pas la depuis le debut. Elle se devoile DU BAS VERS LE HAUT et
-- s'etire en arrivant.
--
-- ELLE PORTE DEJA un UIGradient (le fondu du montage) et Roblox n'en applique QU'UN par objet : la revelation
-- passe donc par un CanvasGroup pose autour d'elle, qui porte le second. Le groupe fait exactement la taille de la
-- tete -- un CanvasGroup CLIPPE ce qui depasse, et c'est deja ce qui avait fait disparaitre les feuillages ici.
local FACE_REVEAL = {
	TIME = 0.55,
	-- DEPART DEFORME : etroite et haute, elle revient a sa forme en rebondissant (slime). Cela EXIGE
	-- `ScaleType = Stretch` sur l'image : en `Fit`, retrecir la largeur ne deforme rien, ca RAPETISSE l'image
	-- entiere -- piege deja paye sur les feuilles de cet ecran.
	SQUASH_X = 0.68,
	SQUASH_Y = 1.3,
	EDGE = 0.3, -- douceur de la limite de revelation
	-- LARGEUR / HAUTEUR DE L'IMAGE ELLE-MEME (1 = carree). En `Stretch`, la tete prend les proportions de sa
	-- case : la case relevee sur le montage est 15 % plus large que haute, donc la tete au repos s'en trouvait
	-- elargie d'autant. On RECALCULE la largeur a partir de la hauteur et du format de l'ecran, ce qui redonne
	-- exactement le rendu d'avant (`Fit` bornait sur la hauteur) sur n'importe quel ecran. KNOB si le visage
	-- reste large ou devient etroit.
	ASPECT = 1,
	-- LE SENS D'UN OFFSET NE SE DEDUIT PAS : si elle se devoile du haut vers le bas, passer a true.
	FLIP = false,
}
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
-- LE REFLET SUR LE CONTOUR. Un UIGradient peut vivre DANS un UIStroke : c'est la facon de faire briller un contour,
-- et c'est le montage que le joueur avait fait a la main. La bande claire reste HORS CHAMP au repos (le contour est
-- donc plein) et traverse la lettre quand le reflet passe. Regroupe en table : le fichier est a 170 locales de
-- premier niveau, et Luau en refuse plus de 200 -- au-dela, le module entier meurt au chargement.
local STROKE_SHINE = {
	ROTATION = 25, -- diagonale, comme une lumiere qui glisse sur la lettre
	WIDTH = 0.18, -- largeur de la bande, en fraction de la lettre
	PEAK = 0.85, -- le contour s'efface presque au coeur de la bande
	BASE = 0, -- ailleurs il reste plein
	TIME = 0.55, -- temps de traversee d'UNE lettre
	-- LE SENS D'UN OFFSET NE SE DEDUIT PAS, il s'observe (le journal l'a paye sur le wipe de l'herbe) : si le reflet
	-- part du mauvais cote, passer a true.
	FLIP = false,
}
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
-- LE SON D'ARRIVEE DANS LE JEU, sur la PREMIERE lettre : il ouvre la scene, les petits pops des lettres passent
-- par-dessus. Il etait declare dans SoundConfigs et n'avait jamais ete joue nulle part.
local JOIN_SOUND = { "Sounds", "Game", "GlobalSounds", "JoinSound" }
local JOIN_SOUND_VOLUME = 0.55
-- LE SON DE SORTIE : il part quand l'ecran s'efface, pas a la fin du premier son. Il accompagne le passage au
-- jeu, donc il vit sur SoundService et survit a la destruction de l'ecran.
local LEAVE_SOUND = { "Sounds", "Game", "GlobalSounds", "JoinSound2" }
local LEAVE_SOUND_VOLUME = 0.55
local LETTER_SOUND = { "Sounds", "UI", "PopSound_1" }
local LETTER_SOUND_VOLUME = 0.25
local LETTER_SOUND_PITCH = 0.9 -- hauteur de la 1re lettre
local LETTER_SOUND_STEP = 0.07 -- de combien elle monte a chaque lettre suivante

-- LE MOT ARRIVE LETTRE PAR LETTRE, puis ne bouge plus : seul le reflet le traverse.
-- L'ANIMATION N'A PAS LE DROIT DE COMMENCER TANT QUE L'ECRAN NE S'AFFICHE PAS VRAIMENT.
--
-- Un tween avance avec le TEMPS, pas avec les images : pendant que le client charge (replication, assets), il ne
-- dessine presque rien, et le mot finit de s'ecrire dans le vide. Le joueur arrive, tout est deja pose -- "je n'ai
-- pas le temps de voir les lettres". On attend donc quelques images d'affilee assez rapides pour dire que l'ecran
-- tourne, avec un plafond de securite pour ne jamais rester muet.
local WARMUP_FRAMES = 4 -- images d'affilee assez rapides avant de lancer le mot
local WARMUP_MAX_DT = 0.12 -- au-dela, l'image est trop lente : le client charge encore
local WARMUP_TIMEOUT = 12 -- on lance quand meme apres ce temps : mieux vaut une anim ratee que pas d'anim

-- VIF, MAIS PAS INSTANTANE. On n'attrapait rien a 0.07 s d'ecart ; a 0.22 s le mot s'ecrivait trop lentement. Ce
-- qui rend les lettres VISIBLES n'etait pas la lenteur, c'est l'attente du 1er dessin (WARMUP) : une fois cette
-- cause reglee, le geste peut redevenir rapide.
local WORD_DELAY = 0.3 -- temps avant la premiere lettre : le regard se pose sur l'ecran d'abord
local WORD_STAGGER = 0.1 -- decalage entre deux lettres
local WORD_DROP = 0.06 -- d'ou la lettre monte, en fraction de la hauteur d'ecran
local WORD_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- LE REFLET, comme sur le titre de chapitre du didacticiel (`Modules/UI/Core/ChapterTitle`) : chaque lettre
-- s'estompe et revient, decalee sur sa voisine.
-- LE DERNIER "A" FAIT TOUT : il gonfle, revient a sa taille, et c'est CE RETOUR qui lance l'onomatopee et la
-- tete. Les faire partir a l'apparition de la lettre les decollerait du geste ; ici ils sont l'onde de choc.
local WORD_LAST = {
	POP = 1.3, -- de combien le A gonfle
	-- DEUX TEMPS INEGAUX, et c'est tout l'effet : il enfle LENTEMENT, puis claque d'un coup. Un aller-retour en
	-- `reverses` ne peut pas le faire -- il rejoue la meme duree et la meme courbe a l'envers, donc un retour
	-- aussi mou que l'aller.
	GROW_TIME = 0.5,
	SNAP_TIME = 0.1, -- le choc : court, et en easing `In` pour que la vitesse soit maximale A L'ARRIVEE
}
local WORD_SHINE_DELAY = 0.4 -- apres la pose de la derniere lettre
local WORD_SHINE_STAGGER = 0.04 -- retard entre deux lettres : c'est lui qui fait glisser le reflet
local WORD_SHINE_TIME = 0.3 -- aller-retour d'UNE lettre
local WORD_SHINE_PEAK = 0.7 -- transparence au sommet de la vague
local WORD_SHINE_PERIOD = 2.6 -- temps entre deux passages

-- ===== LA TONDEUSE QUI TOND LA RANGEE D'HERBE, EN BAS =====
local MOWER = {
	IMAGE = "rbxassetid://93898580984673",
	SIZE = Vector2.new(0.1262, 0.237),
	-- Le BAS de la tondeuse (ancre 0.5, 1). Releve : centre 0.9016 + moitie de 0.237.
	GROUND_Y = 1.0201,
	START_X = -0.12, -- hors ecran a gauche
	END_X = 1.12, -- hors ecran a droite
	TIME = 7, -- duree d'une traversee, en secondes. KNOB
	PAUSE = 0.8, -- temps mort avant le passage suivant
	-- Ecrasement : elle s'aplatit un peu et s'elargit d'autant, sans quitter le sol.
	SQUASH = Vector2.new(1.04, 0.94),
	SQUASH_TIME = 0.32,
}

-- ROGNEE AU PLUS PRES DES BRINS : plus de vide transparent sous l'herbe. La rangee pose donc pile sur le sol, sans
-- rien a compenser dans le code -- et l'icone se repose telle quelle ailleurs sans trainer sa marge invisible.
local GRASS_IMAGE = "rbxassetid://87955164509294"
-- PETITES ET NOMBREUSES : une pelouse, pas une rangee de buissons. La taille et le pas vont ENSEMBLE -- reduire
-- l'un sans l'autre laisse des trous ou fait se chevaucher les touffes.
-- LA HAUTEUR SE LIT CONTRE LA TONDEUSE, pas dans l'absolu : trop courte, la rangee devient un trait et la machine
-- a l'air de rouler sur du vide.
-- 0.15 ET NON 0.22 : l'ancienne image portait environ un tiers de vide sous les brins, on compensait donc en
-- l'agrandissant. Image rognee, la meme hauteur de BRINS tient dans une case plus courte.
local GRASS_SIZE = Vector2.new(0.045, 0.09)
-- LA LIGNE DE SOL : c'est le BAS des touffes, pas leur centre. Posee ainsi, changer leur hauteur ne les fait plus
-- monter ni s'enfoncer -- elles poussent depuis le meme sol quelle que soit leur taille.
--
-- ELLE PART DE CELLE DE LA TONDEUSE : les deux roulent sur le meme sol. Elle a ete un temps ecrite a part (1.0647),
-- valeur heritee du bas des ANCIENNES touffes, deux fois plus hautes : avec des touffes courtes elle n'en laissait
-- depasser qu'un centieme d'ecran.
--
-- L'ENFONCEMENT EST A ZERO depuis que l'image est rognee : il ne servait qu'a pousser hors de l'ecran le vide que
-- l'ancienne image avait sous ses brins. Garde comme KNOB au cas ou l'herbe doive mordre dans le sol.
local GRASS_SINK = 0
local GRASS_BASE_Y = MOWER.GROUND_Y + GRASS_SINK
local GRASS_START_X = 0.013 -- centre de la premiere touffe
-- L'ECART SE DEDUIT DE LA LARGEUR, il ne s'ecrit pas a part : pose a la main, il finit toujours par ne plus
-- correspondre a la taille (a 0.026 pour des touffes de 0.052, chacune couvrait la moitie de sa voisine et la
-- rangee devenait une masse noire continue, sans touffes lisibles). Un seul nombre a regler : le RECOUVREMENT.
local GRASS_OVERLAP = 0.25 -- 0 = touffes bord a bord ; plus on monte, plus elles se serrent. KNOB
local GRASS_STEP = GRASS_SIZE.X * (1 - GRASS_OVERLAP)
local GRASS_CUT = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- vitesse de la coupe
local GRASS_WIPE_EDGE = 0.3 -- douceur du bord de coupe (0 = coupure nette)
-- LE SENS DU BALAYAGE NE SE DEDUIT PAS, il se constate a l'ecran (journal de CLAUDE.md). Si la touffe s'efface du
-- mauvais cote, inverser CE booleen -- il n'y a rien d'autre a changer.
local GRASS_WIPE_FLIP = false

-- LA COUPE PART QUAND LE NEZ DE LA MACHINE ARRIVE, PAS QUAND SON CENTRE EST DESSUS. `pos` est le CENTRE de la
-- tondeuse : tester la touffe contre lui laissait la machine rouler sur une demi-largeur d'herbe encore debout.
-- La demi-largeur se CALCULE (elle suit la taille de la tondeuse) ; le seul reglage est l'avance en plus.
-- GRISE, PAS NOIRE : en noir plein la rangee pese autant que la tondeuse et le mot, et le bas de l'ecran tire
-- l'oeil vers le decor au lieu du titre.
local GRASS_COLOR = Color3.fromRGB(158, 158, 158)
local GRASS_CUT_LEAD = 0.02 -- de combien la touffe se couche AVANT le nez, en fraction d'ecran. KNOB

-- L'HERBE REPOUSSE DERRIERE LA TONDEUSE, et la tondeuse repasse : le bas de l'ecran tourne en boucle tant que ca
-- charge. Le retard est donne en DISTANCE (fraction d'ecran derriere la machine) et non en secondes : regle ainsi,
-- il reste juste meme si on change la vitesse de la tondeuse. Le temps s'en deduit.
local GRASS_REGROW = {
	LAG = 0.34, -- a quelle distance DERRIERE la tondeuse la touffe se redresse. KNOB
	TIME = 0.5, -- duree de la pousse
}

local FOLIAGE_TINT = Color3.new(0, 0, 0)
local FOLIAGE_ALPHA = 0.89 -- KNOB : baisser = feuilles plus sombres (valeur relevee sur la maquette)
-- Taille du groupe, en fraction d'ecran. Assez grand pour contenir les feuillages QUI DEBORDENT (ils encadrent
-- l'ecran) et leur rotation, qui elargit encore leur boite.
local FOLIAGE_GROUP = 3

-- Polices : Luckiest Guy (titres, chunky) et Gotham (le reste). On passe par FontFace + les familles qui LIVRENT
-- avec Roblox : pas de risque d'un Enum.Font absent qui casserait tout l'ecran au lancement.
local FONT_TITLE = Font.new("rbxasset://fonts/families/LuckiestGuy.json")
-- LE TEXTE DE CHARGEMENT EN MONTSERRAT BLACK. Dans Roblox, "Black" s'appelle `Heavy` (900) -- `ExtraBold` (800)
-- serait un cran en dessous, et rendrait le mot plus maigre que voulu.
local FONT_STATUS = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)

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

-- L'ATTENTE DU PREMIER VRAI DESSIN. `RenderStepped` ne tire que quand une image est DESSINEE : c'est donc le seul
-- juge de "l'ecran s'affiche-t-il vraiment". PARTAGEE par le mot ET par la tondeuse : tout ce qui s'anime doit
-- partir du meme instant, sinon une animation tourne dans le vide pendant le chargement et le joueur tombe au
-- milieu d'un cycle deja commence -- l'herbe repoussait alors a partir de la sixieme touffe, sans raison visible.
local function waitForFirstFrames()
	local smooth = 0
	local deadline = os.clock() + WARMUP_TIMEOUT
	while smooth < WARMUP_FRAMES and os.clock() < deadline do
		local dt = RunService.RenderStepped:Wait()
		smooth = if dt <= WARMUP_MAX_DT then smooth + 1 else 0
	end
end

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

-- LE GROUPE PORTE LA REVELATION ET LA TAILLE ; la tete le remplit. On redimensionne le GROUPE et non la tete :
-- dedans, elle serait rognee par le clipping du CanvasGroup des qu'elle depasserait.
local faceGroup = Instance.new("CanvasGroup")
faceGroup.Name = "FaceGroup"
faceGroup.BackgroundTransparency = 1
faceGroup.ZIndex = 5
-- ANCRE EN BAS : elle s'etire VERS LE HAUT, comme si elle poussait. Ancree au centre, elle grandirait aussi vers
-- le bas et le geste se lirait comme un simple zoom.
faceGroup.AnchorPoint = Vector2.new(0.5, 1)
faceGroup.Position = UDim2.fromScale(FACE_POS.X, FACE_POS.Y + FACE_SIZE.Y / 2)
-- LA CASE DE REPOS : la hauteur relevee, et la largeur qui en decoule pour respecter le format de l'image.
--
-- RELUE A CHAQUE APPEL, ET JAMAIS GARDEE. Dans `ReplicatedFirst` on tourne AVANT que la camera soit prete :
-- `ViewportSize` y vaut (1, 1). Mesurer une seule fois au demarrage donnait donc un rapport de 1 au lieu de 0.56,
-- soit une case 1.7 fois trop large -- une tete completement aplatie, alors que le calcul etait juste. Tester que
-- la camera EXISTE ne suffit pas : il faut tester que sa mesure est UTILISABLE.
local function faceRestSize(): Vector2
	local cam = workspace.CurrentCamera
	local view = if cam then cam.ViewportSize else Vector2.zero
	-- Sous cette taille, l'ecran n'est pas encore dessine : on prend un 16/9 plutot qu'un rapport absurde.
	if view.X < 16 or view.Y < 16 then
		view = Vector2.new(1920, 1080)
	end
	return Vector2.new(FACE_SIZE.Y * (view.Y / view.X) * FACE_REVEAL.ASPECT, FACE_SIZE.Y)
end

local faceStart = faceRestSize()
faceGroup.Size = UDim2.fromScale(faceStart.X * FACE_REVEAL.SQUASH_X, faceStart.Y * FACE_REVEAL.SQUASH_Y)
faceGroup.GroupTransparency = 1 -- invisible tant que la derniere lettre ne l'a pas appelee
faceGroup.Parent = root

local faceReveal = Instance.new("UIGradient")
faceReveal.Rotation = 90 -- vertical
faceReveal.Color = ColorSequence.new(WHITE)
faceReveal.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(math.min(FACE_REVEAL.EDGE, 0.999), 0),
	NumberSequenceKeypoint.new(1, 0),
})
faceReveal.Offset = Vector2.new(0, if FACE_REVEAL.FLIP then -1 else 1) -- tout masque au depart
faceReveal.Parent = faceGroup

local face = Instance.new("ImageLabel")
face.Name = "Face"
face.BackgroundTransparency = 1
face.Image = FACE_IMAGE
face.ImageColor3 = INK
-- STRETCH ET NON FIT : c'est la seule facon de l'ECRASER (Fit ne sait que grossir et rapetisser). Le prix est
-- qu'elle prend les proportions de sa case : si elle parait trop large au repos, c'est FACE_SIZE qu'on corrige.
face.ScaleType = Enum.ScaleType.Stretch
face.ZIndex = 5
face.AnchorPoint = Vector2.new(0.5, 0.5)
face.Position = UDim2.fromScale(0.5, 0.5)
face.Size = UDim2.fromScale(1, 1)
fadeGradient(face)
face.Parent = faceGroup

-- LE CADRE DES YEUX : c'est LUI qu'on deplace pour le regard, jamais les calques un par un. Un seul objet a
-- bouger, donc aucun risque qu'un oeil parte sans l'autre.
local eyes = Instance.new("Frame")
eyes.Name = "Eyes"
eyes.BackgroundTransparency = 1
eyes.AnchorPoint = Vector2.new(0.5, 0.5)
eyes.Position = UDim2.fromScale(0.5, 0.5)
eyes.Size = UDim2.fromScale(1, 1)
eyes.ZIndex = 6
eyes.Parent = faceGroup

-- Chaque etat de l'oeil est un calque pleine taille, montre ou cache. Le fondu du montage est repose sur chacun :
-- sans lui, les yeux resteraient pleins la ou la tete s'estompe, et on les verrait flotter devant elle.
local function eyeLayer(name: string, image: string, shown: boolean): ImageLabel
	local layer = Instance.new("ImageLabel")
	layer.Name = name
	layer.BackgroundTransparency = 1
	layer.Image = image
	layer.ImageColor3 = INK
	layer.ScaleType = Enum.ScaleType.Stretch -- comme la tete, sinon les deux ne se superposent plus
	layer.AnchorPoint = Vector2.new(0.5, 0.5)
	layer.Position = UDim2.fromScale(0.5, 0.5)
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 6
	layer.Visible = shown
	fadeGradient(layer)
	layer.Parent = eyes
	return layer
end

local eyeLayers = {
	left = eyeLayer("EyeLeft", EYE.LEFT, true),
	right = eyeLayer("EyeRight", EYE.RIGHT, true),
	shut = eyeLayer("EyesShut", EYE.SHUT, false),
	wink = eyeLayer("EyeWink", EYE.WINK, false),
}

-- CHAQUE OEIL GLISSE VERS SON COTE. Le calque du clin d'oeil suit l'oeil DROIT : c'est le meme oeil.
eyeLayers.left.Position = UDim2.fromScale(0.5 - EYE.SPREAD, 0.5)
eyeLayers.right.Position = UDim2.fromScale(0.5 + EYE.SPREAD, 0.5)
eyeLayers.wink.Position = UDim2.fromScale(0.5 + EYE.SPREAD, 0.5)

-- LES DEUX CALQUES CACHES SE TELECHARGENT D'AVANCE. Une image ne part se charger que lorsqu'on l'AFFICHE : celles
-- du clignement et du clin d'oeil ne se montrent que deux dixiemes de seconde, donc elles n'avaient jamais le
-- temps d'arriver -- l'oeil disparaissait au lieu de se fermer, et rien ne le signalait. En tache de fond : un
-- PreloadAsync bloque son thread jusqu'a ce que tout soit la.
task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync({ eyeLayers.shut, eyeLayers.wink })
	end)
end)

-- TANT QUE LA TETE EST CACHEE, ON NE JOUE RIEN. Les boucles demarrent au chargement, bien avant que la derniere
-- lettre ne fasse sortir le visage : sans cette attente, le son du clin d'oeil partirait dans le vide.
local function waitForFace()
	while faceGroup.Parent and faceGroup.GroupTransparency > 0.05 do
		task.wait(0.2)
	end
	return faceGroup.Parent ~= nil
end

-- LE CLIN D'OEIL, appele du dehors (la fin du son d'arrivee). Le drapeau evite qu'il se croise avec un
-- clignement : les deux ecrivent les memes calques, et celui qui finit en dernier gagnerait.
-- LE SON D'ARRIVEE EN COURS, pose par la premiere lettre et lu par le planificateur du clin d'oeil.
local joinSoundPlaying: Sound? = nil
local eyesBusy = false
local winkDone = false
local function winkOnce(reason: string)
	-- UNE SEULE FOIS, quel que soit le nombre de declencheurs : la fin du son et la limite de temps peuvent tres
	-- bien tomber toutes les deux.
	if winkDone or eyesBusy or not eyes.Parent then
		return
	end
	if not waitForFace() then -- le son peut finir avant que la tete soit sortie
		return
	end
	if winkDone or not eyes.Parent then -- l'attente ci-dessus a pu durer : on reteste
		return
	end
	winkDone = true
	if EYE.DEBUG then
		local w = eyeLayers.wink
		print(
			`[Loading] clin d'oeil ({reason}) : image={w.Image} chargee={w.IsLoaded} `
				.. `taille={w.AbsoluteSize} transparence={w.ImageTransparency} groupe={faceGroup.GroupTransparency}`
		)
	end
	eyesBusy = true
	TweenService:Create(
		faceGroup,
		TweenInfo.new(EYE.TILT_IN, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Rotation = EYE.TILT }
	):Play()
	-- LE SON D'ABORD, L'OEIL ENSUITE : il se ferme sur le "cling" final, pas a l'attaque.
	local cling = findSound(EYE.SOUND)
	if cling then
		local playing = playSound(cling, EYE.SOUND_VOLUME)
		local deadline = os.clock() + 1
		while playing.TimeLength <= 0 and os.clock() < deadline do
			task.wait(0.05)
		end
		local length = if playing.TimeLength > 0 then playing.TimeLength else EYE.CLING_FALLBACK
		task.wait(math.max(length + EYE.CLING_OFFSET, 0))
		if not eyes.Parent then
			eyesBusy = false
			return
		end
	end
	eyeLayers.right.Visible = false
	eyeLayers.wink.Visible = true
	task.wait(EYE.WINK_TIME)
	eyeLayers.wink.Visible = false
	eyeLayers.right.Visible = true
	eyesBusy = false
	-- ELLE RESTE PENCHEE UN MOMENT : se redresser dans le meme geste que la reouverture ferait un aller-retour
	-- mecanique. Elle tient la pose, puis revient.
	task.delay(EYE.TILT_HOLD, function()
		if not faceGroup.Parent then
			return
		end
		TweenService:Create(
			faceGroup,
			TweenInfo.new(EYE.TILT_OUT, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Rotation = 0 }
		):Play()
	end)
end

-- QUAND LE CLIN D'OEIL SE JOUE. Un seul endroit decide, plutot que deux declencheurs qui se doublaient : la fin
-- du son et une limite de temps pouvaient tomber dans n'importe quel ordre, donc le geste changeait de place
-- d'une partie a l'autre.
task.spawn(function()
	if not waitForFace() then
		return
	end
	task.wait(EYE.AFTER_FACE)
	-- On laisse le son d'arrivee se terminer, sans l'attendre indefiniment.
	local limit = os.clock() + EYE.WINK_DEADLINE
	while joinSoundPlaying and joinSoundPlaying.IsPlaying and os.clock() < limit do
		task.wait(0.1)
	end
	winkOnce(if joinSoundPlaying then "apres le son d'arrivee" else "pas de son d'arrivee")
end)

-- LES CLIGNEMENTS ORDINAIRES, qui ne font que vivre le visage.
task.spawn(function()
	if not waitForFace() then
		return
	end
	while eyes.Parent do
		-- Un ecart CONSTANT se lit comme un metronome : on ajoute du hasard.
		task.wait(EYE.BLINK_EVERY + math.random() * EYE.BLINK_JITTER)
		if not eyes.Parent then
			return
		end
		if not eyesBusy then
			eyesBusy = true
			eyeLayers.left.Visible = false
			eyeLayers.right.Visible = false
			eyeLayers.shut.Visible = true
			task.wait(EYE.SHUT_TIME)
			eyeLayers.shut.Visible = false
			eyeLayers.left.Visible = true
			eyeLayers.right.Visible = true
			eyesBusy = false
		end
	end
end)

-- LE REGARD QUI SE BALADE.
task.spawn(function()
	if not waitForFace() then
		return
	end
	while eyes.Parent do
		task.wait(GAZE.EVERY + math.random() * GAZE.JITTER)
		if not eyes.Parent then
			return
		end
		TweenService:Create(
			eyes,
			TweenInfo.new(GAZE.TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromScale(
					0.5 + (math.random() * 2 - 1) * GAZE.X,
					0.5 + (math.random() * 2 - 1) * GAZE.Y
				),
			}
		):Play()
	end
end)

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

-- CE QUE LA DERNIERE LETTRE DECLENCHE. Ecrit ici, avant la boucle : une fonction ne s'appelle jamais au-dessus
-- de sa definition.
local function revealFace()
	if not faceGroup.Parent then
		return
	end
	faceGroup.GroupTransparency = 0
	-- MESUREE MAINTENANT : l'ecran est dessine depuis plusieurs images, la camera a donc sa vraie taille.
	local rest = faceRestSize()
	faceGroup.Size = UDim2.fromScale(rest.X * FACE_REVEAL.SQUASH_X, rest.Y * FACE_REVEAL.SQUASH_Y)
	-- LE REBOND EST SUR LA FORME (Back), pas sur la revelation : un Back sur un devoilement ferait REDESCENDRE la
	-- limite en fin de course, donc reapparaitre un bout deja revele.
	TweenService:Create(
		faceGroup,
		TweenInfo.new(FACE_REVEAL.TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(rest.X, rest.Y) }
	):Play()
	TweenService:Create(
		faceReveal,
		TweenInfo.new(FACE_REVEAL.TIME * 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Offset = Vector2.new(0, if FACE_REVEAL.FLIP then 1 else -1) }
	):Play()
end

local function burstShout()
	if not shout.Parent then
		return
	end
	local cry = findSound(SHOUT_SOUND)
	if cry then
		playSound(cry, SHOUT_SOUND_VOLUME, SHOUT_SOUND_PITCH)
	end
	local pop = TweenService:Create(shout, SHOUT_IN, {
		ImageTransparency = 0,
		Rotation = SHOUT_ROT,
		Size = UDim2.fromScale(SHOUT_SIZE.X, SHOUT_SIZE.Y),
	})
	pop.Completed:Once(function()
		task.delay(SHOUT_HOLD, function()
			if not shout.Parent then
				return
			end
			TweenService:Create(shout, SHOUT_OUT, {
				ImageTransparency = 1,
				Size = UDim2.fromScale(SHOUT_SIZE.X * SHOUT_OUT_GROW, SHOUT_SIZE.Y * SHOUT_OUT_GROW),
			}):Play()
		end)
	end)
	pop:Play()
end

-- MOT "LEAFIA", LETTRE PAR LETTRE, chacune a sa place relevee.
local letters: { TextLabel } = {}
local shines: { UIGradient } = {}
-- Le depart de chaque lettre, garde de cote : il ne part qu'une fois l'ecran vraiment affiche (voir plus bas).
local starts: { () -> () } = {}
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
	local shine = Instance.new("UIGradient")
	shine.Rotation = STROKE_SHINE.ROTATION
	shine.Color = ColorSequence.new(WHITE) -- blanc uni : seule la TRANSPARENCE travaille ici
	shine.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, STROKE_SHINE.BASE),
		NumberSequenceKeypoint.new(math.max(0.5 - STROKE_SHINE.WIDTH, 0.001), STROKE_SHINE.BASE),
		NumberSequenceKeypoint.new(0.5, STROKE_SHINE.PEAK),
		NumberSequenceKeypoint.new(math.min(0.5 + STROKE_SHINE.WIDTH, 0.999), STROKE_SHINE.BASE),
		NumberSequenceKeypoint.new(1, STROKE_SHINE.BASE),
	})
	-- AU REPOS, LA BANDE EST DEHORS. Sans ca, chaque lettre garderait un trou clair en plein milieu de son contour,
	-- en permanence -- et on croirait le contour mal dessine.
	local sweep = 1 + STROKE_SHINE.WIDTH * 2
	local shineFrom = if STROKE_SHINE.FLIP then sweep else -sweep
	shine.Offset = Vector2.new(shineFrom, 0)
	shine.Parent = stroke
	shines[i] = shine
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
	starts[i] = function()
		if not letter.Parent then
			return
		end
		-- LE SON DE LA LETTRE. Cherche au moment de jouer, pas au boot : a l'ouverture de l'ecran, le serveur n'a pas
		-- forcement encore pose les sons.
		local click = findSound(LETTER_SOUND)
		if click then
			playSound(click, LETTER_SOUND_VOLUME, LETTER_SOUND_PITCH + (i - 1) * LETTER_SOUND_STEP)
		end
		if i == 1 then
			local welcome = findSound(JOIN_SOUND)
			if welcome then
				joinSoundPlaying = playSound(welcome, JOIN_SOUND_VOLUME)
				if EYE.DEBUG then
					local length = if joinSoundPlaying then joinSoundPlaying.TimeLength else 0
					print(`[Loading] son d'arrivee joue, duree connue = {length}`)
				end
			elseif EYE.DEBUG then
				print("[Loading] son d'arrivee INTROUVABLE sous SoundService")
			end
		end
		-- ELLE ARRIVE ET ELLE RESTE : aucune ondulation ensuite. Le mot doit se lire pose, pas flotter.
		TweenService:Create(letter, WORD_IN, { Position = home, TextTransparency = 0 }):Play()
		TweenService:Create(stroke, WORD_IN, { Transparency = 0 }):Play()
		-- LE DERNIER "A" GONFLE PUIS REVIENT, et l'onomatopee et la tete partent AVEC LUI, pas apres son retour :
		-- enchaines, ils arrivaient une demi-seconde trop tard et se lisaient comme trois evenements separes.
		-- `reverses = true` fait l'aller-retour en un seul tween. Il peut demarrer tout de suite : l'arrivee de la
		-- lettre anime sa POSITION, jamais sa taille, donc les deux tweens ne se disputent rien.
		if i == #TITLE_TEXT then
			local home_size = letter.Size
			local swell = TweenService:Create(
				letter,
				TweenInfo.new(WORD_LAST.GROW_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{
					Size = UDim2.fromScale(
						home_size.X.Scale * WORD_LAST.POP,
						home_size.Y.Scale * WORD_LAST.POP
					),
				}
			)
			swell.Completed:Once(function()
				if not letter.Parent then
					return
				end
				local snap = TweenService:Create(
					letter,
					TweenInfo.new(WORD_LAST.SNAP_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
					{ Size = home_size }
				)
				-- L'IMPACT EST LA : la lettre vient de reprendre sa taille, et c'est ce choc qui projette
				-- l'onomatopee et fait sortir la tete. Les lancer a l'APPARITION de la lettre les detachait du
				-- geste ; ici ils en sont la consequence.
				snap.Completed:Once(function()
					letter.Size = home_size
					revealFace()
					burstShout()
				end)
				snap:Play()
			end)
			swell:Play()
		end
	end
end

-- L'ATTENTE, puis le depart des lettres.
task.spawn(function()
	waitForFirstFrames()
	task.wait(WORD_DELAY)
	for i, start in ipairs(starts) do
		task.delay((i - 1) * WORD_STAGGER, start)
	end
	-- LE REFLET attend la derniere lettre : il part d'ici, donc il suit l'attente lui aussi.
	task.wait((#starts - 1) * WORD_STAGGER + WORD_IN.Time + WORD_SHINE_DELAY)
	while root.Parent do
		for i, letter in ipairs(letters) do
			task.delay((i - 1) * WORD_SHINE_STAGGER, function()
				if not letter.Parent then
					return
				end
				-- LE CONTOUR ET LE REMPLISSAGE BRILLENT ENSEMBLE : un seul reflet, pas deux effets qui se croisent.
				local grad = shines[i]
				if grad then
					local sweep = 1 + STROKE_SHINE.WIDTH * 2
					local to = if STROKE_SHINE.FLIP then -sweep else sweep
					grad.Offset = Vector2.new(-to, 0)
					TweenService:Create(
						grad,
						TweenInfo.new(STROKE_SHINE.TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
						{ Offset = Vector2.new(to, 0) }
					):Play()
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
local statusText = text("Status", root, FONT_STATUS, INK)
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

type Blade = { gui: ImageLabel, grad: UIGradient, x: number, cut: boolean, id: number }
local blades: { Blade } = {}
local x = GRASS_START_X
while x < 1 + GRASS_STEP do
	local blade = Instance.new("ImageLabel")
	blade.Name = "Grass"
	blade.BackgroundTransparency = 1
	blade.Image = GRASS_IMAGE
	blade.ImageColor3 = GRASS_COLOR
	-- ANCREE PAR LE BAS : une touffe qui repousse sort de TERRE. Ancree au centre, elle grandirait aussi vers le bas,
	-- donc elle s'enfoncerait dans le sol en meme temps qu'elle pousse.
	blade.AnchorPoint = Vector2.new(0.5, 1)
	blade.Position = UDim2.fromScale(x, GRASS_BASE_Y)
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

	table.insert(blades, { gui = blade, grad = grad, x = x, cut = false, id = 0 })
	x += GRASS_STEP
end

local mower = Instance.new("ImageLabel")
mower.Name = "Mower"
mower.BackgroundTransparency = 1
mower.Image = MOWER.IMAGE
mower.ImageColor3 = INK
-- ANCRE EN BAS AU MILIEU : l'ecrasement se fait alors vers le sol, comme une vraie masse posee dessus. Ancree au
-- centre, la tondeuse s'enfoncerait ET se souleverait a chaque pas.
mower.AnchorPoint = Vector2.new(0.5, 1)
mower.Size = UDim2.fromScale(MOWER.SIZE.X, MOWER.SIZE.Y)
mower.Position = UDim2.fromScale(MOWER.START_X, MOWER.GROUND_Y)
-- BIEN AU-DESSUS DE L'HERBE : la machine passe DEVANT les touffes, sinon elle a l'air de rouler derriere elles.
-- Large exprès (l'herbe est a 7) : un ecart d'un seul cran se perd des qu'un autre element s'intercale.
mower.ZIndex = 12
mower.Parent = root

-- ECRASEMENT : elle s'aplatit et se retend sans arret, sans jamais quitter le sol. Sur la TAILLE et pas la position :
-- un rebond la ferait sauter, or elle roule.
TweenService:Create(
	mower,
	TweenInfo.new(MOWER.SQUASH_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Size = UDim2.fromScale(MOWER.SIZE.X * MOWER.SQUASH.X, MOWER.SIZE.Y * MOWER.SQUASH.Y) }
):Play()

-- LE PASSAGE : la tondeuse traverse, et chaque touffe se fait couper QUAND ELLE LA DEPASSE. On avance la position a
-- la main image par image plutot qu'en tween, justement pour pouvoir comparer -- un tween ne dit pas ou il en est.
local mowConn: RBXScriptConnection? = nil
task.spawn(function()
	-- ELLE PART AVEC LE "L" : meme attente, meme delai. Lancee des le boot, elle tondait pendant que le client
	-- chargeait encore, et l'ecran s'ouvrait sur une pelouse a moitie fauchee.
	waitForFirstFrames()
	task.wait(WORD_DELAY)
	-- LE RETARD DE REPOUSSE EN SECONDES : la distance voulue, divisee par la vitesse de la tondeuse.
	local speed = (MOWER.END_X - MOWER.START_X) / MOWER.TIME
	local regrowDelay = GRASS_REGROW.LAG / speed
	local regrowIn = TweenInfo.new(GRASS_REGROW.TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	while root.Parent do
		local travelled = 0
		-- ON NE REDRESSE PLUS L'HERBE AU DEPART : chaque touffe repousse toute seule derriere la machine. La remettre
		-- debout ici ferait sauter d'un coup celles qui sont encore couchees, juste avant que la tondeuse revienne.
		-- Seul le drapeau se rouvre, et il est sans danger : la tondeuse part de HORS ECRAN, donc a gauche de tout.
		for _, blade in blades do
			blade.cut = false
		end
		local done = false
		mowConn = RunService.Heartbeat:Connect(function(dt: number)
			travelled += dt / MOWER.TIME
			local pos = MOWER.START_X + (MOWER.END_X - MOWER.START_X) * math.min(travelled, 1)
			mower.Position = UDim2.fromScale(pos, MOWER.GROUND_Y)
			for _, blade in blades do
				if not blade.cut and pos + MOWER.SIZE.X / 2 + GRASS_CUT_LEAD >= blade.x then
					blade.cut = true
					TweenService:Create(blade.grad, GRASS_CUT, {
						Offset = Vector2.new(if GRASS_WIPE_FLIP then -1 else 1, 0),
					}):Play()
					-- ELLE REPOUSSE UNE FOIS LA MACHINE LOIN. Le jeton evite qu'une repousse en retard ne redresse une
					-- touffe que le passage SUIVANT vient de recouper -- elle se releverait sous la lame.
					blade.id += 1
					local id = blade.id
					task.delay(regrowDelay, function()
						if blade.id ~= id or not blade.gui.Parent then
							return
						end
						blade.grad.Offset = Vector2.new(if GRASS_WIPE_FLIP then 1 else -1, 0)
						blade.gui.Size = UDim2.fromScale(GRASS_SIZE.X, 0)
						TweenService:Create(blade.gui, regrowIn, {
							Size = UDim2.fromScale(GRASS_SIZE.X, GRASS_SIZE.Y),
						}):Play()
					end)
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
		-- LE TEMPS QU'ELLE REVIENNE PAR LA GAUCHE. Court : l'herbe n'a plus besoin d'etre remise debout en coulisse,
		-- elle s'est deja redressee derriere la machine.
		task.wait(MOWER.PAUSE)
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

-- LE SON DE SORTIE, sur la MEME image que le debut du fondu : l'oreille et l'oeil doivent partir ensemble.
do
	local leave = findSound(LEAVE_SOUND)
	if leave then
		playSound(leave, LEAVE_SOUND_VOLUME)
	end
end

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
