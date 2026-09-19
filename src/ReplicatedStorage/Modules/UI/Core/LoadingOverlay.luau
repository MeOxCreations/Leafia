--!strict
-- RIDEAU DU BOUTON START : il couvre l'entree dans le jeu, ou le depart vers le didacticiel. show() / hide().
--
-- LE MEME RIDEAU QUE L'ARRIVEE ET LE TELEPORT (`ReplicatedFirst.CurtainVisual`) : ciel bleu, tuile qui defile,
-- visage du grand-pere, couronne de points. C'etait un fond gris avec une feuille qui se remplissait, reste d'une
-- ancienne version : le joueur voyait trois ecrans de chargement differents a la suite pour un seul depart.
--
-- ET LE MEME VOILE BLANC (`ReplicatedFirst.WipeVisual`) pour entrer et sortir : il balaie l'ecran, le rideau
-- apparait (ou disparait) pendant qu'il couvre, puis il se retire. C'est le geste du chargement d'arrivee et de la
-- sortie du didacticiel ; un simple fondu ici aurait ete le seul passage du jeu a ne pas le jouer.
--
-- ReplicatedFirst est replique avant tout le reste : les modules sont la bien avant que quiconque appelle show().

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local CurtainVisual = require(ReplicatedFirst.CurtainVisual)
local WipeVisual = require(ReplicatedFirst.WipeVisual)

local LoadingOverlay = {}

local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local curtain: CanvasGroup? = nil
local stopAnimation: (() -> ())? = nil

-- Temps avant que l'ecran soit COUVERT (show) : expose pour que l'appelant sache combien attendre avant de bouger
-- quoi que ce soit derriere (camera, UI). On compte le temps tenu en plus du balayage : a la toute fin du balayage
-- le bord n'est pas encore tout a fait pose, et le menu se verrait disparaitre dans le dernier coin.
LoadingOverlay.showTime = WipeVisual.COVER_TIME + WipeVisual.HOLD

local function build()
	local sg = Instance.new("ScreenGui")
	sg.Name = "LeafiaLoadingOverlay"
	sg.ResetOnSpawn = false
	sg.ScreenInsets = Enum.ScreenInsets.None
	sg.DisplayOrder = 200 -- au-dessus de tout (la console admin est a 100) ; le voile, lui, est encore au-dessus
	sg.Enabled = false

	local group = Instance.new("CanvasGroup")
	group.Name = "Curtain"
	group.BackgroundColor3 = CurtainVisual.BG
	group.BorderSizePixel = 0
	group.Size = UDim2.fromScale(1, 1)
	group.Active = true -- absorbe les clics tant que le rideau couvre (pas de clic a l'aveugle sur le jeu derriere)
	group.Parent = sg

	-- "LOADING" : au clic, le serveur n'a pas encore dit si on entre dans le jeu ou si on part au didacticiel. Le rideau
	-- d'arrivee affichera le vrai nom du lieu.
	local built = CurtainVisual.build(group, CurtainVisual.DEST_FALLBACK)
	stopAnimation = CurtainVisual.animate(built, true)

	sg.Parent = player:WaitForChild("PlayerGui")
	gui = sg
	curtain = group
end

-- UN ALLER-RETOUR DU VOILE : il couvre, `swap` fait le changement cache dessous, il se retire, puis `onDone`.
local function wipeAround(swap: () -> (), onDone: (() -> ())?)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		swap()
		if onDone then
			onDone()
		end
		return
	end
	local wipe = WipeVisual.create(playerGui)
	-- CONDAMNE D'AVANCE : un aplat blanc colle a l'ecran cacherait le jeu entier sans aucun moyen d'en sortir. Si une
	-- seule ligne plus bas echoue, il part quand meme. La marge ne sert jamais quand tout va bien.
	task.delay(WipeVisual.COVER_TIME + WipeVisual.HOLD + WipeVisual.REVEAL_TIME + 3, function()
		wipe.gui:Destroy()
	end)
	task.spawn(function()
		wipe.sweep(0, 1, WipeVisual.COVER_TIME)
		swap()
		task.wait(WipeVisual.HOLD)
		wipe.sweep(1, 0, WipeVisual.REVEAL_TIME)
		wipe.gui:Destroy()
		if onDone then
			onDone()
		end
	end)
end

-- Affiche le rideau SOUS LE VOILE : le voile couvre, le rideau est pose, le voile se retire sur le rideau.
function LoadingOverlay.show()
	if not gui then
		build()
	end
	if not (gui and curtain) then
		return
	end
	local g = gui :: ScreenGui
	local group = curtain :: CanvasGroup
	wipeAround(function()
		group.GroupTransparency = 0
		g.Enabled = true
	end)
end

-- FIN DU CHARGEMENT : le voile couvre, le rideau est DETRUIT avec ses animations, le voile se retire sur le jeu.
-- `onRevealed` part une fois le jeu visible, pas avant : une notification lancee derriere le voile ne se verrait pas.
function LoadingOverlay.hide(onRevealed: (() -> ())?)
	print(`[Loading] rideau : hide() appele (rideau present : {gui ~= nil})`)
	if not (gui and curtain) then
		if onRevealed then
			onRevealed()
		end
		return
	end
	local g = gui :: ScreenGui
	wipeAround(function()
		-- LES ANIMATIONS D'ABORD : elles vivent sur RunService, detruire le rideau ne les couperait pas.
		local stop = stopAnimation
		stopAnimation = nil
		if stop then
			stop()
		end
		g:Destroy()
		gui = nil
		curtain = nil
	end, onRevealed)
end

return LoadingOverlay
