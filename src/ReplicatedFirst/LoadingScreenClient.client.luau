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
local function playSound(source: Sound, volume: number?): Sound
	local sound = source:Clone()
	if volume then
		sound.Volume = volume
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
-- LA TETE DU GRAND-PERE, au-dessus du titre : elle dit de qui parle le jeu avant meme qu'on lise le nom.
local FACE_IMAGE = "rbxassetid://111069478991867"
local FACE_TRANSPARENCY = 0
local FACE_POS = Vector2.new(0.4989, 0.4188)
local FACE_SIZE = Vector2.new(0.1835, 0.1975)
-- LE MOT et le texte de chargement, poses eux aussi a la main.
local WORD_POS = Vector2.new(0.4995, 0.6205)
local WORD_SIZE = Vector2.new(0.3196, 0.1659)
local STATUS_POS = Vector2.new(0.4995, 0.6827)
local STATUS_SIZE = Vector2.new(0.553, 0.0277)

-- LE MOT ARRIVE LETTRE PAR LETTRE, puis ondule. Largeur d'une lettre = hauteur du mot x ce facteur : TextScaled
-- remplit sa case, il ne la dimensionne pas -- sans largeur imposee, toutes les lettres se tasseraient.
-- HAUTEUR DES LETTRES, en fraction de la hauteur du mot. Chaque lettre prend ensuite SA largeur (AutomaticSize) :
-- une largeur imposee, identique pour toutes, ecartait le "I" du reste comme s'il y avait un espace.
local WORD_TEXT_RATIO = 0.95
-- RESSERREMENT entre deux lettres, en fraction de leur hauteur. Negatif : les lettres se rapprochent jusqu'a se
-- toucher, comme dans un mot ecrit d'un bloc. 0 = l'espacement naturel de la police.
local WORD_KERNING = -0.08
local WORD_STAGGER = 0.07 -- decalage entre deux lettres, a l'arrivee ET dans la vague : c'est lui qui fait la vague
local WORD_DROP = 0.35 -- d'ou la lettre monte (fraction de sa case)
local WORD_IN = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local WORD_WAVE = 0.08 -- hauteur de l'ondulation (fraction de la case). KNOB
local WORD_WAVE_TIME = 1.1 -- duree d'un aller de l'ondulation. KNOB

-- LE REFLET, comme sur le titre de chapitre du didacticiel (`Modules/UI/Core/ChapterTitle`) : chaque lettre
-- s'estompe et revient, decalee sur sa voisine. ON NE PEUT PAS ECLAIRCIR DU BLANC -- il n'y a rien au-dessus du
-- blanc -- donc la lumiere se fait par la TRANSPARENCE : la lettre recule, puis revient. L'oeil lit un passage.
local WORD_SHINE_DELAY = 0.4 -- apres la pose de la derniere lettre
local WORD_SHINE_STAGGER = 0.04 -- retard entre deux lettres : c'est lui qui fait glisser le reflet
local WORD_SHINE_TIME = 0.3 -- aller-retour d'UNE lettre
local WORD_SHINE_PEAK = 0.7 -- transparence au sommet de la vague
local WORD_SHINE_PERIOD = 2.6 -- temps entre deux passages

-- LES FEUILLAGES SONT NOIRS ET TRANSPARENTS : sur le vert, ca donne une ombre de feuille, pas un dessin colle.
--
-- ILS VIVENT DANS UN CanvasGroup, et c'est LUI qui porte la transparence. Sinon deux feuilles qui se recouvrent
-- assombrissent leur intersection, et le chevauchement se voit comme une tache. Le groupe est d'abord aplati, PUIS
-- rendu transparent d'un bloc : les recouvrements disparaissent, et on n'a plus a placer les feuilles au millimetre.
--
-- MAIS UN CanvasGroup DECOUPE CE QUI DEPASSE DE SON CADRE : il dessine ses enfants dans une image de SA taille. Les
-- feuillages sont places bien au-dela (ils debordent de l'ecran expres, ils l'encadrent), donc dans un groupe de la
-- taille d'origine ils disparaissaient TOUS. Le groupe couvre donc plusieurs fois l'ecran, et les positions de
-- FOLIAGE_DATA -- ecrites pour le petit cadre -- sont converties a l'echelle du grand (voir `toHolder`).
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

-- ===== CIEL =====
local sky = frame("Sky", root)
sky.Size = UDim2.fromScale(1, 1)
sky.Position = UDim2.fromScale(0, 0)
sky.ZIndex = 1
-- Degrade du fond : vert citron en haut -> vert franc en bas. Rotation 90 = vertical (haut -> bas).
-- C'ETAIT UN CIEL BLEU : le jeu parle de pelouse et de haies, le vert le dit des la premiere seconde.
local skyGrad = Instance.new("UIGradient")
skyGrad.Rotation = 90
skyGrad.Color = ColorSequence.new(Color3.fromRGB(213, 255, 76), Color3.fromRGB(147, 255, 101))
skyGrad.Parent = sky

-- FOND TUILE qui defile en DIAGONALE. ZIndex = ciel + 1 : juste AU-DESSUS du degrade (opaque, il le cacherait dessous)
-- et SOUS tout le reste (le contenu le cacherait dessus). Le decalage X ET Y a la meme vitesse donne la diagonale ;
-- on recycle chaque axe sur SA periode (la taille de tuile sur cet axe) pour boucler sans saut.
-- TileSize en SCALE (fraction de l'ImageLabel tuile) : ca s'adapte a l'ecran. A REGLER a l'oeil pour l'image.
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
	-- Periode de recyclage = la taille PIXEL d'une tuile (scale x taille de l'ImageLabel). Relue chaque frame -> suit
	-- l'ecran (rotation mobile, resize).
	local periodX = TILE_SCALE_X * tile.AbsoluteSize.X
	local periodY = TILE_SCALE_Y * tile.AbsoluteSize.Y
	if periodX <= 0 or periodY <= 0 then
		return
	end
	tileOffX = (tileOffX + TILE_SPEED * dt) % periodX
	tileOffY = (tileOffY + TILE_SPEED * dt) % periodY
	tile.Position = UDim2.new(0.5, tileOffX, 0.5, tileOffY)
end)

-- ===== LE CENTRE : tete, mot, texte de chargement =====
-- POSES DIRECTEMENT SUR LE FOND, aux valeurs relevees. C'etait une colonne avec un UIListLayout et deux contraintes
-- de ratio : elle calculait des places qu'on connait deja, et il fallait passer par elle pour bouger quoi que ce
-- soit. Trois elements, trois positions -- ce que le joueur a sous les yeux dans Studio.
local function place(gui: GuiObject, pos: Vector2, size: Vector2)
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Position = UDim2.fromScale(pos.X, pos.Y)
	gui.Size = UDim2.fromScale(size.X, size.Y)
end

local face = Instance.new("ImageLabel")
face.Name = "Face"
face.BackgroundTransparency = 1
face.Image = FACE_IMAGE
face.ImageColor3 = WHITE
face.ImageTransparency = FACE_TRANSPARENCY
face.ScaleType = Enum.ScaleType.Fit -- garde ses proportions quel que soit l'ecran
face.ZIndex = 5
place(face, FACE_POS, FACE_SIZE)
face.Parent = root

-- MOT "LEAFIA", LETTRE PAR LETTRE. SANS OMBRE : la maquette le veut plat, et une ombre teal sur du vert se lit
-- comme une bavure.
--
-- UNE LETTRE = DEUX OBJETS : une CASE que le UIListLayout range, et la lettre qui bouge LIBREMENT dedans. Animer
-- directement ce qu'un layout positionne, c'est se battre contre lui a chaque image -- il repose la position, la
-- tween la reecrit, et le resultat depend de qui parle en dernier.
local wordHolder = frame("Wordmark", root)
wordHolder.BackgroundTransparency = 1
wordHolder.ZIndex = 6
place(wordHolder, WORD_POS, WORD_SIZE)
do
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	-- RESSERREMENT : un ecart NEGATIF rapproche les lettres jusqu'a se toucher. Recalcule avec l'ecran, puisqu'il est
	-- donne en fraction de la hauteur du mot.
	local function fitGap()
		layout.Padding = UDim.new(0, wordHolder.AbsoluteSize.Y * WORD_KERNING)
	end
	fitGap()
	wordHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitGap)
	layout.Parent = wordHolder
end

local letters: { TextLabel } = {}
for i = 1, #TITLE_TEXT do
	local cell = frame("Cell" .. i, wordHolder)
	cell.BackgroundTransparency = 1
	cell.LayoutOrder = i
	cell.ZIndex = 6

	local letter = text("Letter", cell, FONT_TITLE, WHITE)
	letter.Text = TITLE_TEXT:sub(i, i)
	letter.AnchorPoint = Vector2.new(0.5, 0.5)
	letter.ZIndex = 6
	-- TEXTE A TAILLE FIXE, et c'est la LETTRE qui donne sa largeur a sa case (AutomaticSize). Avec TextScaled, c'est
	-- l'inverse : il faut imposer une largeur, la meme pour toutes, et le "I" se retrouve avec autant d'air qu'un "A".
	letter.TextScaled = false
	letter.AutomaticSize = Enum.AutomaticSize.X
	letter.Size = UDim2.fromScale(0, 1)
	cell.AutomaticSize = Enum.AutomaticSize.X
	cell.Size = UDim2.fromScale(0, 1)

	local function fitText()
		letter.TextSize = math.max(wordHolder.AbsoluteSize.Y * WORD_TEXT_RATIO, 1)
	end
	fitText()
	wordHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitText)

	letters[i] = letter

	-- ARRIVEE : la lettre monte de sous sa case en s'allumant, l'une apres l'autre.
	letter.TextTransparency = 1
	letter.Position = UDim2.fromScale(0.5, 0.5 + WORD_DROP)
	task.delay((i - 1) * WORD_STAGGER, function()
		if not letter.Parent then
			return
		end
		TweenService:Create(letter, WORD_IN, { Position = UDim2.fromScale(0.5, 0.5), TextTransparency = 0 }):Play()
		-- VAGUE : chaque lettre monte et redescend en boucle, decalee de la precedente -- c'est ce DECALAGE qui fait
		-- la vague. Lancee apres l'arrivee, sinon les deux tweens se disputent la meme position.
		task.delay(WORD_IN.Time, function()
			if not letter.Parent then
				return
			end
			TweenService:Create(
				letter,
				TweenInfo.new(WORD_WAVE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Position = UDim2.fromScale(0.5, 0.5 - WORD_WAVE) }
			):Play()
		end)
	end)
end

-- LE REFLET QUI TRAVERSE LE MOT, en boucle. Une seule tache pour tout le mot : c'est elle qui tient l'ordre des
-- lettres, et le decalage entre elles fait glisser la lumiere de gauche a droite.
task.spawn(function()
	task.wait((#letters - 1) * WORD_STAGGER + WORD_IN.Time + WORD_SHINE_DELAY)
	while wordHolder.Parent do
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

-- TEXTE D'ETAT ("Planting flower beds..."), juste sous le mot. Place comme les deux autres.
local statusText = text("Status", root, FONT_BOLD, WHITE)
statusText.RichText = true
statusText.ZIndex = 6
place(statusText, STATUS_POS, STATUS_SIZE)

-- ===== FEUILLAGES qui encadrent l'ecran (entree en eventail + flottement) =====
-- INLINE, comme tout ce fichier (autonome : pas de require de ReplicatedStorage). Meme idee que le module reutilisable
-- UI/Core/FoliageReveal, reduite a ce dont le loading a besoin : les feuillages JAILLISSENT depuis l'exterieur, arrivent
-- a leur place, puis flottent doucement. La position POSEE ici est la position finale ; le depart est CALCULE en la
-- projetant vers l'exterieur du centre. { image, x, y = position scale ; w, h = taille scale ; rot } ; tous ancres (0.5, 1).
-- { image ; x, y = CENTRE en fraction d'ecran ; w, h = taille en fraction d'ecran ; rot = degres }. Releve tel quel
-- sur l'ecran monte a la main : ils debordent volontairement (x et y hors de [0, 1]), ils encadrent l'ecran.
type FoliageEntry = { image: string, x: number, y: number, w: number, h: number, rot: number }
local FOLIAGE_DATA: { FoliageEntry } = {
	{ image = "rbxassetid://133121907005690", x = 0.842, y = -0.0931, w = 0.2662, h = 0.4796, rot = -108 },
	{ image = "rbxassetid://120457348978315", x = 1.0242, y = 0.315, w = 0.1141, h = 0.2769, rot = -140 },
	{ image = "rbxassetid://120457348978315", x = 1.0239, y = -0.0442, w = 0.1936, h = 0.3834, rot = -140 },
	{ image = "rbxassetid://78090496362298", x = 0.982, y = 0.5818, w = 0.1474, h = 0.3784, rot = -140 },
	{ image = "rbxassetid://78090496362298", x = 0.6205, y = 0.0208, w = 0.2973, h = 0.553, rot = 106 },
	{ image = "rbxassetid://120457348978315", x = 0.3912, y = -0.0939, w = 0.1875, h = 0.372, rot = 180 },
	{ image = "rbxassetid://106884980828867", x = 0.1678, y = -0.1345, w = 0.3184, h = 0.5778, rot = 135 },
	{ image = "rbxassetid://106884980828867", x = -0.0038, y = 0.1466, w = 0.2156, h = 0.407, rot = 103 },
	{ image = "rbxassetid://120457348978315", x = -0.1309, y = -0.0111, w = 0.2156, h = 0.407, rot = 103 },
	{ image = "rbxassetid://120457348978315", x = -0.1776, y = 0.3517, w = 0.2156, h = 0.407, rot = 103 },
	{ image = "rbxassetid://133121907005690", x = 0, y = 0.5057, w = 0.2238, h = 0.3938, rot = 83 },
	{ image = "rbxassetid://106884980828867", x = 0.084, y = 0.9218, w = 0.2773, h = 0.4523, rot = 48 },
	{ image = "rbxassetid://78090496362298", x = 0.2728, y = 1.0939, w = 0.1474, h = 0.3784, rot = -62 },
	{ image = "rbxassetid://78090496362298", x = 0.3588, y = 1.0466, w = 0.1474, h = 0.3784, rot = 0 },
	{ image = "rbxassetid://133121907005690", x = 0.9031, y = 1.0545, w = 0.2817, h = 0.5445, rot = -28 },
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
