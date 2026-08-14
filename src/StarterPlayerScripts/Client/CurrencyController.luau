--!strict
-- Interface ECONOMIE (coin haut de l'ecran) : pieces + reputation. HUD FIXE (pas de WorldAnchor). Elle ne fait
-- qu'AFFICHER les attributs poses par le serveur (CurrencyService) sur le joueur : le client obeit, le serveur
-- decide. A la hausse : POP du texte, DEFILE du nombre (il glisse jusqu'a la nouvelle valeur), SHINE (bande
-- blanche diagonale) et un TEXTE FLOTTANT "+X" (le montant ajoute) qui jaillit du compteur et monte en s'effacant.
--
-- La ScreenGui CurrencyUI est creee dans Studio (StarterGui). Elle doit avoir ResetOnSpawn = FALSE, sinon elle
-- est recreee a chaque respawn et les references gardees ici pointeraient sur du detruit (cf CLAUDE.md).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local CurrencyConfigs = require(ReplicatedStorage.Modules.Configs.CurrencyConfigs)
local FormatUtils = require(ReplicatedStorage.Modules.Utils.FormatUtils)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local CurrencyController = {}

local player = Players.LocalPlayer

local COINS_ATTRIBUTE = CurrencyConfigs.COINS_ATTRIBUTE
local REPUTATION_ATTRIBUTE = CurrencyConfigs.REPUTATION_ATTRIBUTE

-- Pop du texte a la hausse : grossit d'un coup puis revient (Back). Meme esprit que le punch du level up.
local POP_SCALE = 1.25
local POP_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Defile du compteur : la valeur AFFICHEE glisse jusqu'a la nouvelle (au lieu de sauter). Le format etant en
-- "3.1K", elle passe visuellement par 3.0K, 3.1K, 3.2K... jusqu'a la cible. Ease-out : vif au depart, se pose.
local COUNT_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Shine : une bande blanche diagonale qui BALAYE le texte, vite, a chaque gain. Portee par le meme UIGradient que
-- la couleur (un element n'a qu'un gradient) : pendant le balayage le shine prend la main, puis rend la teinte unie.
local SHINE_COLOR = Color3.fromRGB(255, 255, 255)
local SHINE_ANGLE = 25 -- degres : diagonale du balayage
local SHINE_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

-- Texte flottant "+X" a chaque gain de pieces : le montant ajoute apparait SOUS le bloc pieces (facon GTA / Sims),
-- descend un peu et s'efface. Police LuckiestGuy.
local FLY_COINS_COLOR = Color3.fromRGB(255, 210, 90) -- dore : ca sent la piece
local FLY_FONT = Font.fromEnum(Enum.Font.LuckiestGuy)
local FLY_GAP_FRAC = 0.12 -- espace SOUS le holder avant le "+X" (fraction de la hauteur du holder)
local FLY_HEIGHT_FRAC = 0.7 -- hauteur du "+X" (fraction de la hauteur du holder)
local FLY_DRIFT_MUL = 1.1 -- de combien il DESCEND en s'effacant (en hauteurs de holder ; negatif le ferait monter)
local FLY_TWEEN = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Couleur selon le SIGNE de la valeur affichee : blanc-vert pale si benefique (> 0), blanc pur au neutre (0),
-- rouge franc si NEGATIF (dette). Le rouge est reserve au vrai moment ou ca va mal. Prepare l'enjeu a venir :
-- bacler un chantier / casser du materiel pourra pousser le solde sous zero.
local POSITIVE_COLOR = Color3.fromRGB(205, 240, 210) -- blanc-vert pale : benefique sans agresser l'oeil
local NEUTRAL_COLOR = Color3.fromRGB(255, 255, 255) -- blanc : solde a zero, ni bien ni mal
local NEGATIVE_COLOR = Color3.fromRGB(230, 75, 75) -- rouge franc : c'est une ALERTE, il doit sauter aux yeux

-- Un compteur = un label et tout ce qui l'anime. Meme structure pour les pieces et la reputation : zero
-- duplication. `value` = valeur logique cible ; `proxy` = valeur affichee qui defile vers `value`. `shineToken`
-- distingue les balayages qui se chevauchent (clics rapides). `flyColor` nil = pas de texte flottant sur ce
-- compteur (la reputation n'a pas de "+X" dore, ca prendrait pour de la piece).
type Counter = {
	label: TextLabel,
	scale: UIScale,
	gradient: UIGradient,
	value: number,
	proxy: NumberValue,
	tween: Tween?,
	shining: boolean,
	shineToken: number,
	flyColor: Color3?,
}

local coinsCounter: Counter? = nil
local reputationCounter: Counter? = nil
local flyGui: ScreenGui? = nil -- calque a part pour les textes flottants (ScreenInsets None : pixels absolus)

local function readNumber(attribute: string): number
	local v = player:GetAttribute(attribute)
	return if typeof(v) == "number" then v else 0
end

-- UIScale / UIGradient dedies, crees sous le label s'ils manquent (pas a poser a la main dans Studio). Le gradient
-- porte a la fois la couleur unie du signe ET le balayage du shine.
local function ensureScale(label: TextLabel): UIScale
	local existing = label:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Parent = label
	return scale
end

local function ensureGradient(label: TextLabel): UIGradient
	local existing = label:FindFirstChildOfClass("UIGradient")
	if existing then
		return existing
	end
	local gradient = Instance.new("UIGradient")
	gradient.Parent = label
	return gradient
end

local function colorFor(v: number): Color3
	return if v < 0 then NEGATIVE_COLOR elseif v > 0 then POSITIVE_COLOR else NEUTRAL_COLOR
end

-- Peint une valeur AFFICHEE (celle du defile, pas forcement la cible) : texte formate + couleur du signe. Le
-- gradient porte la couleur visible (il ecrase TextColor3), SAUF pendant un shine ou c'est lui qui tient le
-- gradient : on ne le rembobine pas sous ses pieds.
local function paint(counter: Counter, shown: number)
	local color = colorFor(shown)
	counter.label.Text = FormatUtils.Abbreviate(shown)
	counter.label.TextColor3 = color
	if not counter.shining then
		counter.gradient.Color = ColorSequence.new(color)
	end
end

-- Balayage blanc diagonal. Bande blanche etroite au centre d'une sequence sinon unie (couleur du signe), qu'on
-- fait glisser d'un bord a l'autre via l'Offset du gradient. Rapide, une seule passe.
local function playShine(counter: Counter)
	counter.shineToken += 1
	local token = counter.shineToken
	counter.shining = true

	local gradient = counter.gradient
	local base = colorFor(counter.value)
	gradient.Rotation = SHINE_ANGLE
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, base),
		ColorSequenceKeypoint.new(0.4, base),
		ColorSequenceKeypoint.new(0.5, SHINE_COLOR),
		ColorSequenceKeypoint.new(0.6, base),
		ColorSequenceKeypoint.new(1, base),
	})
	gradient.Offset = Vector2.new(-1, 0)

	local tween = TweenService:Create(gradient, SHINE_TWEEN, { Offset = Vector2.new(1, 0) })
	tween.Completed:Connect(function()
		-- Ne rend la main que si aucun shine plus recent n'a demarre entre-temps (clics rapides : le nouveau
		-- balayage tient deja le gradient, ce vieux "Completed" ne doit pas rembobiner par-dessus).
		if counter.shineToken ~= token then
			return
		end
		counter.shining = false
		gradient.Rotation = 0
		gradient.Offset = Vector2.new(0, 0)
		paint(counter, counter.proxy.Value) -- restaure la couleur unie
	end)
	tween:Play()
end

-- Texte flottant "+X" : apparait SOUS le bloc pieces (le HOLDER, parent du texte), descend un peu et s'efface.
-- Vit dans flyGui (ScreenInsets None) pour se placer aux pixels absolus sans se faire rogner par le cadre du HUD.
local function spawnFly(label: TextLabel, amount: number, color: Color3)
	local gui = flyGui
	if not gui then
		return
	end
	-- On se cale sous le HOLDER (le parent), pas sous le seul texte : le "+X" apparait sous tout le bloc pieces.
	local parent = label.Parent
	local anchor: GuiObject = if parent and parent:IsA("GuiObject") then parent else label
	local size = anchor.AbsoluteSize
	local centerX = anchor.AbsolutePosition.X + size.X / 2
	local topY = anchor.AbsolutePosition.Y + size.Y + size.Y * FLY_GAP_FRAC

	local fly = Instance.new("TextLabel")
	fly.Name = "Fly"
	fly.BackgroundTransparency = 1
	fly.AnchorPoint = Vector2.new(0.5, 0)
	fly.Size = UDim2.fromOffset(size.X, size.Y * FLY_HEIGHT_FRAC)
	fly.Position = UDim2.fromOffset(centerX, topY)
	fly.FontFace = FLY_FONT
	fly.TextScaled = true
	fly.Text = "+" .. FormatUtils.Abbreviate(amount)
	fly.TextColor3 = color
	fly.TextStrokeColor3 = Color3.new(0, 0, 0)
	fly.TextStrokeTransparency = 0.4
	fly.ZIndex = 50
	fly.Parent = gui

	local drift = size.Y * FLY_DRIFT_MUL
	TweenService:Create(fly, FLY_TWEEN, {
		Position = UDim2.fromOffset(centerX, topY + drift),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(fly, FLY_TWEEN.Time)
end

local function newCounter(label: TextLabel, flyColor: Color3?): Counter
	local proxy = Instance.new("NumberValue")
	proxy.Value = 0
	local counter: Counter = {
		label = label,
		scale = ensureScale(label),
		gradient = ensureGradient(label),
		value = 0,
		proxy = proxy,
		tween = nil,
		shining = false,
		shineToken = 0,
		flyColor = flyColor,
	}
	-- La valeur affichee suit le proxy : chaque pas du defile repeint le texte (et sa couleur).
	proxy.Changed:Connect(function(v)
		paint(counter, v)
	end)
	paint(counter, 0) -- etat de depart visible (0 en blanc) avant meme la 1re valeur
	return counter
end

-- Pose une nouvelle cible. `animate` = false pour l'affichage initial (pas de defile, pop, shine ni fly), true
-- pour un vrai changement en jeu (defile + pop + shine + texte flottant a la hausse).
local function setTarget(counter: Counter, target: number, animate: boolean)
	local previous = counter.value
	counter.value = target

	if counter.tween then
		counter.tween:Cancel()
		counter.tween = nil
	end

	if not animate then
		counter.proxy.Value = target -- .Changed peint tout de suite (sauf si deja egal, deja peint au depart)
		return
	end

	-- Pop + shine + fly UNIQUEMENT a la hausse (un gain) : le retour visuel recompense le gain, il ne souligne pas
	-- une depense.
	if target > previous then
		counter.scale.Scale = POP_SCALE
		TweenService:Create(counter.scale, POP_TWEEN, { Scale = 1 }):Play()
		playShine(counter)
		if counter.flyColor then
			spawnFly(counter.label, target - previous, counter.flyColor)
		end
	end

	-- Le defile part de la valeur AFFICHEE courante (pas de la cible precedente) : si un defile etait en cours, il
	-- reprend d'ou l'oeil en est, sans a-coup.
	local tween = TweenService:Create(counter.proxy, COUNT_TWEEN, { Value = target })
	counter.tween = tween
	tween:Play()
end

local function bind(ui: ScreenGui)
	local coins = ui:FindFirstChild("CoinsText", true)
	if coins and coins:IsA("TextLabel") then
		coinsCounter = newCounter(coins, FLY_COINS_COLOR)
	else
		warn("[CurrencyController] CoinsText introuvable dans CurrencyUI")
	end

	local rep = ui:FindFirstChild("ReputationText", true)
	if rep and rep:IsA("TextLabel") then
		reputationCounter = newCounter(rep, nil) -- pas de "+X" flottant sur la reputation
	else
		warn("[CurrencyController] ReputationText introuvable dans CurrencyUI")
	end

	-- Affichage initial sans defile ni pop, puis on suit les changements d'attributs (avec defile + pop + shine + fly).
	if coinsCounter then
		setTarget(coinsCounter, readNumber(COINS_ATTRIBUTE), false)
	end
	if reputationCounter then
		setTarget(reputationCounter, readNumber(REPUTATION_ATTRIBUTE), false)
	end
	player:GetAttributeChangedSignal(COINS_ATTRIBUTE):Connect(function()
		if coinsCounter then
			setTarget(coinsCounter, readNumber(COINS_ATTRIBUTE), true)
		end
	end)
	player:GetAttributeChangedSignal(REPUTATION_ATTRIBUTE):Connect(function()
		if reputationCounter then
			setTarget(reputationCounter, readNumber(REPUTATION_ATTRIBUTE), true)
		end
	end)

	-- DEV UNIQUEMENT : dans Studio, cliquer l'icone piece (CoinsImage, un ImageButton) demande des pieces de test
	-- au serveur (qui decide du montant). Gate IsStudio : en prod on ne branche meme pas le clic, et le serveur
	-- n'ecoute pas. Activated marche a la souris ET au tactile, donc ca teste aussi sur mobile.
	if RunService:IsStudio() then
		local coinsImage = ui:FindFirstChild("CoinsImage", true)
		if coinsImage and coinsImage:IsA("GuiButton") then
			local devGrant = RemoteSetup.getRemote("DevGrantCoins", "Dev")
			if devGrant and devGrant:IsA("RemoteEvent") then
				coinsImage.Activated:Connect(function()
					devGrant:FireServer()
				end)
			end
		end
	end
end

function CurrencyController.init()
	-- Les ScreenGui de StarterGui ne sont copiees dans PlayerGui qu'au SPAWN, qui peut TARDER (chargement des
	-- donnees). On attend donc le perso AVANT de chercher l'UI, en tache de fond (pas de blocage du boot). Avec
	-- ResetOnSpawn = false, ce bind unique suffit : la ScreenGui survit aux respawns.
	task.spawn(function()
		if not player.Character then
			player.CharacterAdded:Wait()
		end
		local playerGui = player:WaitForChild("PlayerGui")

		-- Calque des textes flottants : cree en code, ScreenInsets None (pixels absolus, cf le placement dans
		-- spawnFly), survit aux respawns. Au-dessus du HUD via DisplayOrder.
		local fg = Instance.new("ScreenGui")
		fg.Name = "CurrencyFly"
		fg.ResetOnSpawn = false
		fg.ScreenInsets = Enum.ScreenInsets.None
		fg.DisplayOrder = 50
		fg.Parent = playerGui
		flyGui = fg

		local ui = playerGui:WaitForChild("CurrencyUI", 10)
		if ui and ui:IsA("ScreenGui") then
			bind(ui)
		else
			warn("[CurrencyController] CurrencyUI introuvable (pas copiee de StarterGui ?)")
		end
	end)
end

return CurrencyController
