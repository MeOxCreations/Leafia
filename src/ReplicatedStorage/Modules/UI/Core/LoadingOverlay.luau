--!strict
-- Rideau de chargement SECONDAIRE (style Sims) : fond gris fonce + une FEUILLE (logo) qui oscille et flotte au centre.
-- Couvre la transition d'entree dans le jeu / de changement de lieu (a l'arrivee). show() / hide().
--
-- La feuille est une BARRE DE PROGRESSION : le vert REMPLIT la feuille du bas vers le haut au fil du chargement, et arrive
-- EN HAUT (feuille toute verte) quand c'est fini (hide). FERMETURE dans l'ORDRE : la feuille finit de se remplir, PUIS le
-- CONTENU devient transparent (ImageTransparency), PUIS le fond (Curtain, CanvasGroup, via GroupTransparency). Puis DETRUIT.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LoadingOverlay = {}

local player = Players.LocalPlayer

-- Reglages.
local BG_COLOR = Color3.fromRGB(31, 31, 31) -- gris fonce
local LEAF_IMAGE = "rbxassetid://117703108607506" -- la feuille (logo)
local LEAF_COLOR = Color3.fromRGB(81, 81, 81) -- gris : un bout du degrade de la feuille
local LEAF_GREEN = Color3.fromRGB(96, 176, 68) -- vert de la marque : l'autre bout (la feuille prend la couleur du jeu)
-- REMPLISSAGE : le vert monte du BAS vers le HAUT de la feuille = barre de progression. On pilote la ColorSequence du
-- gradient (frontiere vert/gris qui monte), PAS l'Offset. CONFIRME A L'ECRAN : 270 remplit du BAS vers le haut (90
-- remplissait a l'ENVERS, du haut vers le bas). Le sens d'un gradient ne se DEDUIT PAS du raisonnement, seul l'ecran
-- tranche (meme famille que GetMouseLocation).
local LEAF_GRADIENT_ROTATION = 270
local LEAF_FILL_SOFT = 0.06 -- douceur du bord de remplissage (0 = net, plus grand = degrade liquide)
-- Le remplissage MONTE tout seul vers LEAF_PROGRESS_HOLD (on ne connait pas la duree du chargement), en ralentissant
-- (Quad Out : vite au debut, il rampe ensuite) et sans JAMAIS toucher le haut avant la fin. A hide (chargement fini),
-- LEAF_PROGRESS_FINISH le complete d'un coup jusqu'en haut -> la feuille est pleine PILE quand c'est charge.
local LEAF_PROGRESS_CLIMB = TweenInfo.new(9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LEAF_PROGRESS_HOLD = 0.9 -- plafond de la montee auto (garde le "dernier bout" pour la fin reelle)
local LEAF_PROGRESS_FINISH = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Effet de feuille : elle OSCILLE doucement (comme au vent) ET flotte de haut en bas, en boucle. Deux periodes
-- differentes -> rendu organique (jamais synchro).
local LEAF_SWAY_ANGLE = 10 -- degres d'oscillation
local LEAF_SWAY = TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local LEAF_BOB = TweenInfo.new(2.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local FADE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- fondu d'entree du rideau
-- POP d'entree de la feuille : elle grossit de 0 a sa taille via un UIScale, avec un rebond ELASTIQUE (slime prolonge :
-- overshoot puis oscillations qui se calment). Elastic Out = ce ressenti "gelatine". Monter la duree = rebond plus long.
local LEAF_POP = TweenInfo.new(0.9, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

-- Fermeture en 2 temps, en TRANSPARENCE pure : d'abord le CONTENU (la feuille), PUIS le fond. Puis destruction.
local CONTENT_FADE = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FOND_FADE = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

local gui: ScreenGui? = nil
local curtain: CanvasGroup? = nil
local logoImages: { ImageLabel } = {} -- la feuille (Icon) : rendue transparente a la fermeture (phase 1)
local logoScale: UIScale? = nil -- pilote le POP d'entree (0 -> 1) de la feuille
local progressValue: NumberValue? = nil -- 0 -> 1 : niveau de remplissage vert de la feuille (barre de progression)
local climbTween: Tween? = nil -- la montee auto du remplissage (annulee a hide pour completer d'un coup)

-- Duree du fondu d'entree (show) : exposee pour que l'appelant sache combien attendre que le rideau soit OPAQUE avant de
-- bouger quoi que ce soit derriere (camera, UI). Sinon la transition se verrait a travers le rideau encore transparent.
LoadingOverlay.showTime = FADE_IN.Time

-- ColorSequence du gradient pour un niveau de remplissage p (0 = feuille grise/vide, 1 = feuille verte/pleine). Le vert
-- occupe [0, p], une frontiere douce (LEAF_FILL_SOFT), puis le gris. "0" = le bas via LEAF_GRADIENT_ROTATION (cf plus haut).
local function progressColorSequence(p: number): ColorSequence
	p = math.clamp(p, 0, 1)
	if p <= 0 then
		return ColorSequence.new(LEAF_COLOR) -- vide : feuille toute grise
	end
	if p >= 1 then
		return ColorSequence.new(LEAF_GREEN) -- pleine : feuille toute verte
	end
	-- 4 points, temps strictement croissants dans ]0, 1[ : vert jusqu'a a, frontiere a->b, gris ensuite.
	local a = math.clamp(p, 0.001, 0.994)
	local b = math.clamp(a + LEAF_FILL_SOFT, a + 0.002, 0.999)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, LEAF_GREEN),
		ColorSequenceKeypoint.new(a, LEAF_GREEN),
		ColorSequenceKeypoint.new(b, LEAF_COLOR),
		ColorSequenceKeypoint.new(1, LEAF_COLOR),
	})
end

local function build()
	local sg = Instance.new("ScreenGui")
	sg.Name = "LeafiaLoadingOverlay"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ScreenInsets = Enum.ScreenInsets.None
	sg.DisplayOrder = 200 -- au-dessus de tout (la console admin est a 100)
	sg.Enabled = false

	local group = Instance.new("CanvasGroup")
	group.Name = "Curtain"
	group.BackgroundColor3 = BG_COLOR
	group.BorderSizePixel = 0
	group.Size = UDim2.fromScale(1, 1)
	group.GroupTransparency = 0
	group.Active = true -- absorbe les clics tant que le rideau couvre (pas de clic a l'aveugle sur le jeu derriere)
	group.Parent = sg

	-- Logo : la FEUILLE (une seule image carree, UIAspectRatioConstraint = 1). Un Frame (pas un CanvasGroup) pour ne PAS
	-- clipper la feuille quand elle tourne. Meme teinte que le logo precedent.
	local logo = Instance.new("Frame")
	logo.Name = "Logo"
	logo.BackgroundTransparency = 1
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.5)
	logo.Size = UDim2.fromScale(0.267, 0.2)
	logo.Parent = group

	-- UIScale sur le logo : scale la feuille ET ses enfants, centre sur l'ancre (0.5, 0.5) -> grossit depuis le centre.
	-- Depart a 0 ; show() le tween vers 1 (LEAF_POP) pour le pop slime a chaque apparition.
	local logoScaler = Instance.new("UIScale") :: UIScale
	logoScaler.Scale = 0
	logoScaler.Parent = logo
	logoScale = logoScaler

	local leaf = Instance.new("ImageLabel")
	leaf.Name = "Icon"
	leaf.BackgroundTransparency = 1
	leaf.BorderSizePixel = 0
	leaf.AnchorPoint = Vector2.new(0.5, 0.5)
	leaf.Position = UDim2.fromScale(0.5, 0.5)
	leaf.Size = UDim2.fromScale(1, 1)
	leaf.Image = LEAF_IMAGE
	-- ImageColor3 BLANC : la teinte vient du UIGradient. Laisser du gris ici le MULTIPLIERAIT au gradient et salirait le vert.
	leaf.ImageColor3 = Color3.new(1, 1, 1)
	leaf.ScaleType = Enum.ScaleType.Fit
	-- DEGRADE gris -> vert : le logo prend la couleur du jeu. Le gradient est ENFANT de la feuille : quand elle oscille
	-- (sway), il tourne AVEC elle, donc le sens du degrade reste cale sur la feuille (jamais de biais).
	local leafGradient = Instance.new("UIGradient")
	leafGradient.Rotation = LEAF_GRADIENT_ROTATION
	leafGradient.Color = progressColorSequence(0) -- part VIDE (feuille grise) ; show() lance le remplissage
	leafGradient.Parent = leaf
	-- Remplissage pilote par une NumberValue (0 -> 1) que show/hide tweenent : chaque changement de valeur redessine la
	-- ColorSequence (frontiere vert/gris qui monte). Meurt avec le rideau (Destroy a la fermeture).
	local pv = Instance.new("NumberValue")
	pv.Name = "Progress"
	pv.Value = 0
	pv.Parent = leaf
	pv.Changed:Connect(function(v: number)
		leafGradient.Color = progressColorSequence(v)
	end)
	progressValue = pv
	local leafAspect = Instance.new("UIAspectRatioConstraint")
	leafAspect.AspectRatio = 1
	leafAspect.Parent = leaf
	leaf.Parent = logo
	logoImages = { leaf }
	-- Effet feuille : oscillation (Rotation, comme au vent) + flottement vertical (Position). Deux tweens = 2 proprietes
	-- differentes, ils tournent en parallele sans se couper.
	leaf.Rotation = -LEAF_SWAY_ANGLE
	TweenService:Create(leaf, LEAF_SWAY, { Rotation = LEAF_SWAY_ANGLE }):Play()
	TweenService:Create(leaf, LEAF_BOB, { Position = UDim2.fromScale(0.5, 0.48) }):Play()

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
	local g = gui :: ScreenGui
	local group = curtain :: CanvasGroup
	-- Reset (securite) : contenu visible.
	for _, img in logoImages do
		img.ImageTransparency = 0
	end
	group.GroupTransparency = 1
	g.Enabled = true
	TweenService:Create(group, FADE_IN, { GroupTransparency = 0 }):Play()
	-- POP slime de la feuille : repart de 0 et rebondit jusqu'a 1 a chaque apparition.
	if logoScale then
		local scaler = logoScale :: UIScale
		scaler.Scale = 0
		TweenService:Create(scaler, LEAF_POP, { Scale = 1 }):Play()
	end
	-- REMPLISSAGE : repart du BAS (0) et monte tout seul vers le plafond (HOLD). hide() le completera jusqu'en haut.
	if progressValue then
		local pv = progressValue :: NumberValue
		if climbTween then
			climbTween:Cancel()
		end
		pv.Value = 0
		local climb = TweenService:Create(pv, LEAF_PROGRESS_CLIMB, { Value = LEAF_PROGRESS_HOLD })
		climbTween = climb
		climb:Play()
	end
end

-- FIN DU CHARGEMENT : le CONTENU (la feuille) s'efface d'abord, PUIS (seulement une fois qu'il est parti) le fond ;
-- ensuite on DETRUIT LeafiaLoadingOverlay et ses tweens. Aucun gradient tween pour fermer.
function LoadingOverlay.hide(onRevealed: (() -> ())?)
	print(`[Loading] rideau : hide() appele (rideau present : {gui ~= nil})`)
	if not (gui and curtain) then
		if onRevealed then
			onRevealed()
		end
		return
	end
	local g = gui :: ScreenGui
	local group = curtain :: CanvasGroup
	-- Phase 0 : le chargement est FINI -> on complete le remplissage de la feuille jusqu'en HAUT (le vert atteint le
	-- sommet). C'est le "fini" que le joueur voit. On coupe la montee auto d'abord.
	if progressValue then
		if climbTween then
			climbTween:Cancel()
			climbTween = nil
		end
		TweenService:Create(progressValue :: NumberValue, LEAF_PROGRESS_FINISH, { Value = 1 }):Play()
	end
	-- Phase 1 : une fois la feuille PLEINE, elle (ImageTransparency) devient transparente.
	task.delay(LEAF_PROGRESS_FINISH.Time, function()
		for _, img in logoImages do
			TweenService:Create(img, CONTENT_FADE, { ImageTransparency = 1 }):Play()
		end
		-- Phase 2 : SEULEMENT une fois le contenu transparent, le FOND (Curtain) s'efface. Puis on detruit tout.
		task.delay(CONTENT_FADE.Time, function()
			local sweep = TweenService:Create(group, FOND_FADE, { GroupTransparency = 1 })
			sweep:Play()
			sweep.Completed:Once(function()
				-- Destruction : LeafiaLoadingOverlay disparait, ses tweens meurent avec lui. Refs a zero pour qu'un futur
				-- show() reconstruise proprement.
				g:Destroy()
				gui = nil
				curtain = nil
				logoScale = nil
				progressValue = nil
				climbTween = nil
				table.clear(logoImages)
				-- Le jeu est REVELE (rideau parti) : c'est SEULEMENT ici qu'on lache ce qui doit se VOIR (ex : notif de
				-- bienvenue), sinon ca se declencherait derriere le rideau, invisible.
				if onRevealed then
					onRevealed()
				end
			end)
		end)
	end)
end

return LoadingOverlay
