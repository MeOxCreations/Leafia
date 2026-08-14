--!strict
-- GLISSE de HUD (cacher / montrer un element en le faisant coulisser hors ecran). Reutilisable pour n'importe quel
-- HUD (pieces, XP, carburant...).
--
-- register() capture la position D'ORIGINE (visible) de l'element. hide()/show() glissent sa position entre l'origine
-- et une position CACHEE hors ecran. SEUL LE Y bouge : le X reste EXACTEMENT celui d'origine (comme voulu). Donc il
-- faut enregistrer l'element quand il est a sa VRAIE position visible (c'est elle qu'on capture).

local TweenService = game:GetService("TweenService")

local HudSlide = {}

local TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type Entry = { element: GuiObject, shown: UDim2, hidden: UDim2, tween: Tween? }
local entries: { [GuiObject]: Entry } = {}

-- Enregistre un element. Sa position ACTUELLE devient sa position visible (origine). hiddenYScale = ou il va en Y
-- (en scale) une fois cache hors ecran (ex -0.5 = au-dessus du haut de l'ecran, 1.5 = sous le bas). Le X ne change jamais.
function HudSlide.register(element: GuiObject, hiddenYScale: number)
	local shown = element.Position
	entries[element] = {
		element = element,
		shown = shown,
		hidden = UDim2.new(shown.X.Scale, shown.X.Offset, hiddenYScale, 0),
		tween = nil,
	}
end

local function apply(entry: Entry, goal: UDim2, instant: boolean?)
	if entry.tween then
		entry.tween:Cancel()
		entry.tween = nil
	end
	if instant then
		entry.element.Position = goal
	else
		local tween = TweenService:Create(entry.element, TWEEN, { Position = goal })
		entry.tween = tween
		tween:Play()
	end
end

-- Glisse l'element hors ecran (ou l'y place direct si instant = true).
function HudSlide.hide(element: GuiObject, instant: boolean?)
	local entry = entries[element]
	if entry then
		apply(entry, entry.hidden, instant)
	end
end

-- Ramene l'element a sa position d'origine.
function HudSlide.show(element: GuiObject, instant: boolean?)
	local entry = entries[element]
	if entry then
		apply(entry, entry.shown, instant)
	end
end

function HudSlide.hideAll(instant: boolean?)
	for _, entry in pairs(entries) do
		apply(entry, entry.hidden, instant)
	end
end

function HudSlide.showAll(instant: boolean?)
	for _, entry in pairs(entries) do
		apply(entry, entry.shown, instant)
	end
end

return HudSlide
