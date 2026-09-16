--!strict
-- RIDEAU DU BOUTON START : il couvre l'entree dans le jeu, ou le depart vers le didacticiel. show() / hide().
--
-- LE MEME RIDEAU QUE L'ARRIVEE ET LE TELEPORT (`ReplicatedFirst.CurtainVisual`) : ciel bleu, tuile qui defile,
-- visage du grand-pere, couronne de points. C'etait un fond gris avec une feuille qui se remplissait, reste d'une
-- ancienne version : le joueur voyait trois ecrans de chargement differents a la suite pour un seul depart.
--
-- ReplicatedFirst est replique avant tout le reste : le module est la bien avant que quiconque appelle show().

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")

local CurtainVisual = require(ReplicatedFirst.CurtainVisual)

local LoadingOverlay = {}

local player = Players.LocalPlayer

-- Fondu d'entree : court, le rideau doit couvrir vite ce qui se passe derriere.
local FADE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Fondu de sortie, d'UN SEUL mouvement : le CanvasGroup efface tout son contenu comme une seule image. Faire partir
-- chaque element a son rythme se lit comme un bug.
local FADE_OUT = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

local gui: ScreenGui? = nil
local curtain: CanvasGroup? = nil
local stopAnimation: (() -> ())? = nil

-- Duree du fondu d'entree (show) : exposee pour que l'appelant sache combien attendre que le rideau soit OPAQUE avant de
-- bouger quoi que ce soit derriere (camera, UI). Sinon la transition se verrait a travers le rideau encore transparent.
LoadingOverlay.showTime = FADE_IN.Time

local function build()
	local sg = Instance.new("ScreenGui")
	sg.Name = "LeafiaLoadingOverlay"
	sg.ResetOnSpawn = false
	sg.ScreenInsets = Enum.ScreenInsets.None
	sg.DisplayOrder = 200 -- au-dessus de tout (la console admin est a 100)
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

-- Affiche le rideau en FONDU (fade-in).
function LoadingOverlay.show()
	if not gui then
		build()
	end
	if not (gui and curtain) then
		return
	end
	local group = curtain :: CanvasGroup
	group.GroupTransparency = 1
	;(gui :: ScreenGui).Enabled = true
	TweenService:Create(group, FADE_IN, { GroupTransparency = 0 }):Play()
end

-- FIN DU CHARGEMENT : le rideau s'efface d'un seul mouvement, puis il est DETRUIT avec ses animations.
-- `onRevealed` part une fois le jeu visible, pas avant : une notification lancee derriere le rideau ne se verrait pas.
function LoadingOverlay.hide(onRevealed: (() -> ())?)
	print(`[Loading] rideau : hide() appele (rideau present : {gui ~= nil})`)
	if not (gui and curtain) then
		if onRevealed then
			onRevealed()
		end
		return
	end
	local g = gui :: ScreenGui
	local fade = TweenService:Create(curtain :: CanvasGroup, FADE_OUT, { GroupTransparency = 1 })
	fade.Completed:Once(function()
		-- LES ANIMATIONS D'ABORD : elles vivent sur RunService, detruire le rideau ne les couperait pas.
		local stop = stopAnimation
		stopAnimation = nil
		if stop then
			stop()
		end
		g:Destroy()
		gui = nil
		curtain = nil
		if onRevealed then
			onRevealed()
		end
	end)
	fade:Play()
end

return LoadingOverlay
