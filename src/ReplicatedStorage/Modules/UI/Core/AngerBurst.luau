--!strict
-- COLERE EN IMAGES : la gerbe d'eclairs et de points d'exclamation qui saute au-dessus de quelqu'un qui s'agace.
-- L'onomatopee de bande dessinee, en dessin plutot qu'en mot -- donc rien a traduire, et lisible par un enfant qui
-- ne lit pas encore.
--
-- PAS UN BillboardGui, pour les memes raisons que WorldMarker : un Billboard subit l'eclairage, passe derriere le
-- decor, et change de taille avec la distance. Ici c'est un ScreenGui projete (WorldAnchor) : pixels constants,
-- couleurs exactes, toujours au-dessus.
--
-- PRIMITIVE REUTILISABLE : elle ne connait ni le grand-pere ni le didacticiel. On lui donne une cible, elle joue.
-- Le jour ou un client rale sur un chantier rate, ce sera la meme gerbe.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local WorldAnchor = require(script.Parent.WorldAnchor)

local AngerBurst = {}

local player = Players.LocalPlayer

-- ===== LES DESSINS =====
-- CHAQUE IMAGE PORTE SA TAILLE NATURELLE, en pixels. Le rapport largeur/hauteur vient du dessin lui-meme : lui en
-- imposer un autre l'APLATIT, et un eclair aplati ne ressemble plus a un eclair. On ne touche donc qu'a
-- `BURST_SCALE`, qui les agrandit toutes ensemble sans jamais deformer aucune.
--
-- `x` et `y` sont des fractions du cadre, `rot` un angle en degres, `delay` le retard a l'apparition : elles ne
-- sortent pas ensemble, elles se declenchent l'une apres l'autre. Un bloc qui apparait d'un coup se lit comme une
-- image posee ; en decalage, ca se lit comme un mouvement d'humeur.
local PIECES = {
	{ image = "rbxassetid://98278550736283", w = 57, h = 118, x = 0.11, y = 0.54, rot = -16, delay = 0.09 },
	{ image = "rbxassetid://84029477406959", w = 114, h = 100, x = 0.36, y = 0.66, rot = -4, delay = 0.14 },
	{ image = "rbxassetid://97318817152559", w = 71, h = 126, x = 0.63, y = 0.46, rot = 13, delay = 0.04 },
	{ image = "rbxassetid://78589393871508", w = 63, h = 115, x = 0.89, y = 0.40, rot = 7, delay = 0 },
}

-- Cadre qui contient tout, en pixels a la distance de reference. Les `x`/`y` ci-dessus s'y rapportent : changer
-- cette taille ecarte ou resserre la gerbe entiere sans toucher a une seule position.
local FRAME_W, FRAME_H = 300, 150
-- Grossissement d'ensemble. Le seul chiffre a tourner pour une gerbe plus grosse : les proportions de chaque
-- dessin sont preservees par construction.
local BURST_SCALE = 0.85

-- ===== LA DISTANCE =====
-- Comme WorldMarker : taille bornee pour rester lisible de loin sans devenir enorme colle dessus.
local SCALE: WorldAnchor.Scale = { ref = 40, min = 0.55, max = 1.3 }
-- Au-dela, on ne l'affiche pas. Une colere a l'autre bout de la map n'attire pas l'attention, elle l'epuise.
local MAX_DISTANCE = 140

-- ===== LE MOUVEMENT =====
-- ELLE JAILLIT. Chaque image part de rien et DEPASSE sa taille avant de se poser : c'est ce depassement qui donne
-- le coup de nerf. Une echelle qui monte tout droit se lirait comme un fondu.
local POP_TIME = 0.16
local POP_OVER = 1.18
local SETTLE_TIME = 0.12
-- Puis elle tient, et elle s'efface en MONTANT un peu : une gerbe qui disparait sur place s'eteint, une gerbe qui
-- monte s'echappe.
local HOLD_TIME = 0.55
local OUT_TIME = 0.3
local OUT_RISE = 0.9 -- studs

local gui: ScreenGui? = nil

local function getGui(): ScreenGui
	local existing = gui
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("ScreenGui")
	created.Name = "LeafiaAngerBursts"
	-- `None` EST OBLIGATOIRE : WorldAnchor rend des coordonnees dont l'origine est le coin ABSOLU de l'ecran. Avec
	-- l'inset par defaut, la gerbe suivrait 36 px trop bas. Piege deja paye dans ce projet.
	created.ScreenInsets = Enum.ScreenInsets.None
	created.IgnoreGuiInset = true
	created.ResetOnSpawn = false
	-- Sous le prompt d'interaction, comme les marqueurs : quand les deux sont la, c'est l'action qu'on doit lire.
	created.DisplayOrder = 50
	created.Parent = player:WaitForChild("PlayerGui")
	gui = created
	return created
end

-- LE TRIPLE ECLAIR SEUL, centre. Pour un coup ponctuel -- un effort qui ne donne rien, un a-coup -- ou la gerbe
-- entiere raconterait une colere qu'il n'y a pas.
--
-- Meme forme que PIECES, donc le meme moteur les joue toutes les deux : une gerbe n'est qu'une LISTE de dessins.
local SPARK = {
	{ image = "rbxassetid://84029477406959", w = 114, h = 100, x = 0.5, y = 0.5, rot = 0, delay = 0 },
}

type Piece = { image: string, w: number, h: number, x: number, y: number, rot: number, delay: number }

local function burst(target: WorldAnchor.Target, offset: Vector3?, pieces: { Piece })
	local holder = getGui()

	local frame = Instance.new("Frame")
	frame.Name = "AngerBurst"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(FRAME_W * BURST_SCALE, FRAME_H * BURST_SCALE)
	frame.Parent = holder

	local base = offset or Vector3.zero
	WorldAnchor.attach(frame, target, base, MAX_DISTANCE, SCALE)

	local images: { ImageLabel } = {}
	for _, piece in pieces do
		local label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.Image = piece.image
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(piece.x, piece.y)
		label.Size = UDim2.fromOffset(piece.w * BURST_SCALE, piece.h * BURST_SCALE)
		label.Rotation = piece.rot
		-- `Fit` : le cadre a DEJA le rapport du dessin, donc Fit et Stretch donnent la meme image -- mais Fit
		-- garantit qu'une erreur de saisie sur `w` ou `h` retrecit le dessin au lieu de l'ecraser.
		label.ScaleType = Enum.ScaleType.Fit
		label.Parent = frame

		-- LE JAILLISSEMENT PASSE PAR UN UIScale, jamais par la taille. Une echelle est UNIFORME : elle ne PEUT pas
		-- deformer, donc l'eclair reste un eclair quelle que soit l'etape de l'animation. Animer `Size` demanderait
		-- de tenir les deux axes d'accord a la main, et le premier arrondi aplatirait le dessin.
		local us = Instance.new("UIScale")
		us.Scale = 0
		us.Parent = label
		images[#images + 1] = label

		task.delay(piece.delay, function()
			if not label.Parent then
				return
			end
			local up = TweenService:Create(
				us,
				TweenInfo.new(POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = POP_OVER }
			)
			up.Completed:Connect(function()
				if label.Parent then
					TweenService
						:Create(us, TweenInfo.new(SETTLE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Scale = 1,
						})
						:Play()
				end
			end)
			up:Play()
		end)
	end

	-- LE DEPART. Le compte part de la DERNIERE image sortie, pas du debut : sinon la piece la plus retardee
	-- n'aurait presque pas le temps d'exister avant qu'on efface tout.
	local last = 0
	for _, piece in pieces do
		last = math.max(last, piece.delay)
	end
	task.delay(last + POP_TIME + SETTLE_TIME + HOLD_TIME, function()
		if not frame.Parent then
			return
		end
		for _, label in images do
			TweenService
				:Create(label, TweenInfo.new(OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					ImageTransparency = 1,
				})
				:Play()
		end
		-- ELLE MONTE EN PARTANT. On bouge le point VISE dans le monde et pas la position a l'ecran : la gerbe
		-- continue ainsi de suivre son personnage pendant qu'elle s'echappe, meme s'il marche.
		local steps = 12
		task.spawn(function()
			for i = 1, steps do
				if not frame.Parent then
					return
				end
				WorldAnchor.setOffset(frame, base + Vector3.new(0, OUT_RISE * (i / steps), 0))
				task.wait(OUT_TIME / steps)
			end
		end)
		task.delay(OUT_TIME, function()
			-- CELUI QUI CREE EST CELUI QUI NETTOIE, et il nettoie TOUT : l'entree de WorldAnchor survivrait au
			-- Destroy et sa boucle continuerait de calculer une position pour un objet mort.
			WorldAnchor.detach(frame)
			frame:Destroy()
		end)
	end)
end

--- Fait jaillir la gerbe ENTIERE au-dessus de `target`, puis nettoie tout. Rien a garder chez l'appelant.
---
--- `offset` decale le point vise, en studs -- typiquement pour la poser au-dessus de la tete.
function AngerBurst.play(target: WorldAnchor.Target, offset: Vector3?)
	burst(target, offset, PIECES)
end

--- LE TRIPLE ECLAIR SEUL. Pour un a-coup, un effort qui ne donne rien : un seul dessin, centre sur le point.
---
--- La gerbe entiere dit "il est en colere" ; celle-ci ne dit que "ca a cogne". Les melanger userait la premiere.
function AngerBurst.spark(target: WorldAnchor.Target, offset: Vector3?)
	burst(target, offset, SPARK)
end

return AngerBurst
