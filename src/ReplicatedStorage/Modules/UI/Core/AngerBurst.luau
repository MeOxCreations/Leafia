--!strict
-- COLERE EN IMAGE : le triple eclair qui saute au-dessus de quelqu'un qui s'agace, s'etire, et repart.
-- L'onomatopee de bande dessinee, en dessin plutot qu'en mot -- donc rien a traduire, et lisible par un enfant qui
-- ne lit pas encore.
--
-- UN SEUL DESSIN, ET C'EST UN CHOIX. La premiere version en posait quatre (deux eclairs, le triple, un point
-- d'exclamation) : ca faisait une gerbe, donc un EVENEMENT -- alors qu'un vieux qui rale pour la troisieme fois
-- n'est pas un evenement. Un seul eclair qui pulse dit la meme chose sans prendre toute l'image.
--
-- PAS UN BillboardGui, pour les memes raisons que WorldMarker : un Billboard subit l'eclairage, passe derriere le
-- decor, et change de taille avec la distance. Ici c'est un ScreenGui projete (WorldAnchor) : pixels constants,
-- couleurs exactes, toujours au-dessus.
--
-- PRIMITIVE REUTILISABLE : elle ne connait ni le grand-pere ni le didacticiel. On lui donne une cible, elle joue.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local WorldAnchor = require(script.Parent.WorldAnchor)

local AngerBurst = {}

local player = Players.LocalPlayer

-- ===== LE DESSIN =====
-- SA TAILLE NATURELLE, en pixels. Le rapport largeur/hauteur vient du dessin lui-meme : lui en imposer un autre
-- l'APLATIT au repos, et un eclair aplati ne ressemble plus a un eclair. Seul `BURST_SCALE` le redimensionne, et
-- il garde les proportions par construction.
local IMAGE = "rbxassetid://84029477406959"
local IMAGE_W, IMAGE_H = 114, 100
local BURST_SCALE = 0.6
-- ROUGE. `ImageColor3` MULTIPLIE le dessin : ca ne marche que parce que l'eclair est BLANC -- une forme noire
-- resterait noire quelle que soit la teinte, puisque zero multiplie par n'importe quoi fait zero. Son contour
-- sombre, lui, ne bouge pas, et c'est tant mieux : c'est lui qui le detache du decor.
local IMAGE_COLOR = Color3.fromRGB(255, 62, 48)

-- ===== LA DISTANCE =====
-- Comme WorldMarker : taille bornee pour rester lisible de loin sans devenir enorme colle dessus.
local SCALE: WorldAnchor.Scale = { ref = 40, min = 0.55, max = 1.3 }
-- Au-dela, on ne l'affiche pas. Une colere a l'autre bout de la map n'attire pas l'attention, elle l'epuise.
local MAX_DISTANCE = 140

-- ===== LE MOUVEMENT =====
-- IL JAILLIT. Il part de rien et DEPASSE sa taille avant de se poser : c'est ce depassement qui donne le coup de
-- nerf. Une echelle qui monte tout droit se lirait comme un fondu.
local POP_TIME = 0.18

-- PUIS IL PULSE : il s'ETIRE vers le haut et revient, en boucle, tout le temps qu'il reste a l'ecran.
--
-- L'ETIREMENT SE FAIT SUR LA TAILLE, jamais sur un UIScale : une echelle est UNIFORME, elle ne sait que grossir.
-- Elle ne peut donc PAS etirer, et le meme mouvement se lirait comme un simple grossissement. Meme mecanique que
-- les feuilles de l'ecran de chargement.
--
-- ET LA LARGEUR PASSE SOUS 1 : il s'affine en montant, et c'est ca qui fait la matiere molle. Grandir sans
-- s'affiner ne s'etire pas, ca GROSSIT.
local STRETCH_Y = 1.9
local STRETCH_X = 0.66
-- ET IL SE BALANCE. La rotation alterne d'un cote a l'autre a chaque pulsation, et c'est ce qui fait la
-- difference entre un objet qui respire et quelqu'un qui s'ENERVE : un mouvement vertical seul est regulier,
-- donc calme.
--
-- Elle pivote autour de l'ANCRE, qui est au pied : il se penche, il ne glisse pas.
local TILT = 11
-- SON INCLINAISON DE REPOS, en degres. Le dessin arrive droit, et droit il se lit comme un point d'exclamation
-- pose la ; penche, il a l'air d'avoir ete JETE. C'est la meme raison qui fait incliner les onomatopees dans une
-- case de bande dessinee.
--
-- TOUT LE BALANCEMENT SE JOUE AUTOUR D'ELLE, jamais autour de zero : le repos vaut cet angle, et la pulsation
-- l'ecarte de part et d'autre. Revenir a zero entre deux battements le redresserait a chaque fois, ce qui se
-- lirait comme un tic et pas comme une inclinaison.
--
-- IL A ETE COUCHE A -90 UNE VERSION, puis remis debout : l'ecran a tranche. A plat, il s'etire sur le COTE --
-- l'etirement suit le sens du dessin, pas celui de l'ecran -- et un eclair qui s'allonge a l'horizontale ne
-- monte plus, donc il ne jaillit plus. C'est la verticale qui porte le geste.
local BASE_TILT = -20
-- Montee seche, retour un peu plus long. `Back` en sortie DEPASSE une fois puis se pose ; `Elastic` oscillerait,
-- ce qui se lit comme un tremblement et pas comme de la souplesse.
local PULSE_UP = 0.11
local PULSE_BACK = 0.28

-- Combien de temps il reste, une fois apparu.
local HOLD_TIME = 2
-- Puis il s'efface en MONTANT un peu : un eclair qui disparait sur place s'eteint, un eclair qui monte s'echappe.
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
	-- l'inset par defaut, l'eclair suivrait 36 px trop bas. Piege deja paye dans ce projet.
	created.ScreenInsets = Enum.ScreenInsets.None
	created.IgnoreGuiInset = true
	created.ResetOnSpawn = false
	-- Sous le prompt d'interaction, comme les marqueurs : quand les deux sont la, c'est l'action qu'on doit lire.
	created.DisplayOrder = 50
	created.Parent = player:WaitForChild("PlayerGui")
	gui = created
	return created
end

--- Fait jaillir un eclair au-dessus de `target`, le laisse pulser, puis nettoie tout. Rien a garder chez
--- l'appelant.
---
--- `offset` decale le point vise, en studs -- typiquement pour le poser au-dessus de la tete.
function AngerBurst.play(target: WorldAnchor.Target, offset: Vector3?)
	local holder = getGui()

	local w, h = IMAGE_W * BURST_SCALE, IMAGE_H * BURST_SCALE
	local normal = UDim2.fromOffset(w, h)

	local label = Instance.new("ImageLabel")
	label.Name = "AngerBurst"
	label.BackgroundTransparency = 1
	label.Image = IMAGE
	label.ImageColor3 = IMAGE_COLOR
	label.Size = UDim2.fromOffset(0, 0)
	-- `Stretch` ET SURTOUT PAS `Fit`. `Fit` conserve les proportions et borne l'image par le plus PETIT cote du
	-- cadre : elle ne sait alors que grossir et rapetisser, jamais s'etirer -- la pulsation la RETRECIRAIT au lieu
	-- de l'allonger. Piege deja paye sur les feuilles du chargement.
	label.ScaleType = Enum.ScaleType.Stretch
	label.Rotation = BASE_TILT
	label.Parent = holder

	-- ANCRE EN BAS AU MILIEU, et c'est CE QUI REND L'ETIREMENT POSSIBLE. Avec une ancre au centre, un eclair qu'on
	-- allonge pousse vers le bas autant que vers le haut : il grandit des deux cotes au lieu de se dresser. Ancre
	-- par le bas, son pied ne bouge pas et il monte.
	--
	-- WorldAnchor pose lui aussi une ancre -- il centre ce qu'il accroche -- donc on la remet APRES lui.
	-- L'OFFSET EST LU DANS LE REPERE DE LA CAMERA (dernier argument), pas dans celui du monde. Un decalage
	-- lateral en repere monde passerait DERRIERE le personnage des qu'on tourne autour de lui : l'eclair
	-- disparaitrait, ou se retrouverait du mauvais cote. En repere camera, il reste toujours a cote de sa tete a
	-- l'ecran, quelle que soit la vue.
	local base = offset or Vector3.zero
	WorldAnchor.attach(label, target, base, MAX_DISTANCE, SCALE, true)
	label.AnchorPoint = Vector2.new(0.5, 1)

	TweenService
		:Create(label, TweenInfo.new(POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = normal })
		:Play()

	-- LA PULSATION TOURNE TANT QU'IL EST LA. Une boucle plutot qu'un nombre de cycles calcule : changer `HOLD_TIME`
	-- ne demande alors de recalculer rien du tout, et le dernier cycle est coupe net par le depart -- ce qui ne se
	-- voit pas, puisqu'il part en fondu par-dessus.
	task.spawn(function()
		task.wait(POP_TIME)
		local side = 1
		while label.Parent do
			-- LA TAILLE ET L'ANGLE DANS LE MEME TWEEN : deux tweens separes sur le meme objet finissent toujours
			-- par se decaler d'une image ou deux, et le balancement ne tomberait plus avec l'etirement.
			TweenService
				:Create(label, TweenInfo.new(PULSE_UP, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					Size = UDim2.fromOffset(w * STRETCH_X, h * STRETCH_Y),
					Rotation = BASE_TILT + TILT * side,
				})
				:Play()
			task.wait(PULSE_UP)
			if not label.Parent then
				return
			end
			TweenService
				:Create(label, TweenInfo.new(PULSE_BACK, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = normal,
					Rotation = BASE_TILT,
				})
				:Play()
			task.wait(PULSE_BACK)
			-- IL REPART DE L'AUTRE COTE. Toujours du meme cote, ca se lirait comme un tic ; en alternance, comme
			-- quelqu'un qui s'agite.
			side = -side
		end
	end)

	task.delay(POP_TIME + HOLD_TIME, function()
		if not label.Parent then
			return
		end
		TweenService
			:Create(label, TweenInfo.new(OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				ImageTransparency = 1,
			})
			:Play()
		-- IL MONTE EN PARTANT. On bouge le point VISE dans le monde et pas la position a l'ecran : il continue
		-- ainsi de suivre son personnage pendant qu'il s'echappe, meme si celui-ci marche.
		local steps = 12
		task.spawn(function()
			for i = 1, steps do
				if not label.Parent then
					return
				end
				WorldAnchor.setOffset(label, base + Vector3.new(0, OUT_RISE * (i / steps), 0))
				task.wait(OUT_TIME / steps)
			end
		end)
		task.delay(OUT_TIME, function()
			-- CELUI QUI CREE EST CELUI QUI NETTOIE, et il nettoie TOUT : l'entree de WorldAnchor survivrait au
			-- Destroy et sa boucle continuerait de calculer une position pour un objet mort.
			WorldAnchor.detach(label)
			label:Destroy()
		end)
	end)
end

return AngerBurst
