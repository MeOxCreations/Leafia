--!strict
-- LE VOILE BLANC : un aplat blanc qui balaie l'ecran pour le couvrir, puis se retire dans l'autre sens.
--
-- UN SEUL DESSIN POUR DEUX MOMENTS : la fin du rideau de chargement (on detruit le rideau pendant qu'il couvre) et la
-- sortie du didacticiel (on part vers le hub pendant qu'il couvre). Le joueur doit reconnaitre le meme geste.
--
-- DANS ReplicatedFirst, comme CurtainVisual : l'ecran de chargement tourne avant que ReplicatedStorage soit la.
--
-- ON CONSTRUIT LA SEQUENCE, ON N'ANIME PAS L'OFFSET. Le sens d'un `UIGradient.Offset` est imprevisible (deja au
-- journal). Les TEMPS d'une NumberSequence, eux, sont deterministes : 0 est le debut du degrade, 1 sa fin.

local RunService = game:GetService("RunService")

local WipeVisual = {}

-- Duree pour couvrir, temps couvert, duree pour decouvrir. Decouvrir est plus lent que couvrir : on COUVRE pour
-- cacher (autant que ce soit vite fait), on DECOUVRE pour montrer le jeu (autant que ca se savoure).
WipeVisual.COVER_TIME = 0.55
WipeVisual.HOLD = 0.12
WipeVisual.REVEAL_TIME = 0.85

local COLOR = Color3.fromRGB(255, 255, 255)
-- Douceur du bord. 0 = coupure nette, ce qui se lit comme un masque.
local SOFT = 0.18
-- Sens du balayage, en degres. 0 = de gauche a droite.
local ROTATION = 0

export type Wipe = {
	gui: ScreenGui,
	-- `edge` de 0 (rien) a 1 (tout blanc).
	set: (edge: number) -> (),
	-- Fait glisser le bord de `from` a `to`, en `duration` secondes. Rend la main a la fin.
	sweep: (from: number, to: number, duration: number) -> (),
}

--- Pose un voile (encore invisible) dans `parent` (le PlayerGui). Au-dessus de tout, rideau compris.
function WipeVisual.create(parent: Instance): Wipe
	local gui = Instance.new("ScreenGui")
	gui.Name = "LeafiaWipe"
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2000 -- AU-DESSUS du rideau : c'est lui qui doit le cacher, pas l'inverse

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = COLOR
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui

	local grad = Instance.new("UIGradient")
	grad.Rotation = ROTATION
	grad.Parent = frame

	local function set(edge: number)
		if edge >= 1 then
			grad.Transparency = NumberSequence.new(0) -- tout blanc
			return
		end
		if edge <= 0 then
			grad.Transparency = NumberSequence.new(1) -- rien
			return
		end
		-- Les temps doivent croitre STRICTEMENT : on force un ecart minimal, sinon Roblox refuse la sequence des que
		-- le bord touche un bord.
		local b = math.clamp(edge, 0.002, 0.998)
		local a = math.clamp(b - SOFT, 0.001, b - 0.001)
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(a, 0),
			NumberSequenceKeypoint.new(b, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	end

	local function sweep(from: number, to: number, duration: number)
		local t0 = os.clock()
		while gui.Parent do
			local t = math.clamp((os.clock() - t0) / math.max(duration, 1e-3), 0, 1)
			-- Ease in-out : le bord part doucement, file au milieu, se pose. Lineaire, on voit une barre traverser.
			set(from + (to - from) * (t * t * (3 - 2 * t)))
			if t >= 1 then
				return
			end
			RunService.RenderStepped:Wait()
		end
	end

	set(0)
	gui.Parent = parent
	return { gui = gui, set = set, sweep = sweep }
end

return WipeVisual
