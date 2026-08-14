--!strict
-- Accroche un element d'interface a un POINT DU MONDE.
--
-- Primitive reutilisable : elle ne connait ni les haies, ni les clients, ni les taches. On lui donne un objet
-- d'interface et une cible, elle le maintient dessus. Tout ce qui doit flotter au-dessus de quelque chose
-- passera par ici, sinon la meme boucle serait reecrite dans chaque interface.
--
-- POURQUOI PAS UN BillboardGui : un Billboard vit dans le monde, donc il subit l'eclairage, il passe derriere
-- les objets et sa taille depend de la distance. Une interface posee dans un ScreenGui garde ses pixels, ses
-- polices et son ordre d'affichage. C'est le bon choix pour du texte qu'on doit LIRE.
--
-- ATTENTION AU DECALAGE DE 36 PIXELS. WorldToViewportPoint rend des coordonnees VIEWPORT, dont l'origine est le
-- COIN ABSOLU de l'ecran (l'inset de la barre Roblox est DEDANS). Le ScreenGui qui recoit ces coords doit donc
-- couvrir tout l'ecran : ScreenInsets = None (equivaut a IgnoreGuiInset = true). Avec l'inset par defaut
-- (CoreUiSafeInsets), l'origine du GUI est ~36 px plus bas et l'element suit d'autant trop bas. Verifie a l'ecran :
-- le commentaire d'origine disait l'inverse (IgnoreGuiInset FAUX), c'etait faux. Meme famille de piege que
-- GetMouseLocation / ViewportPointToRay, deja paye une fois.

local RunService = game:GetService("RunService")

local WorldAnchor = {}

export type Target = BasePart | Vector3

-- Grossissement selon la distance (optionnel). Facteur 1 a `ref` studs ; plus proche = plus grand, plus loin = plus
-- petit, borne par [min, max]. Applique via un UIScale sur l'element (cree a la demande). Sans ca, l'element garde
-- ses pixels quelle que soit la distance (comportement par defaut, bon pour du texte a lire).
export type Scale = { ref: number, min: number, max: number }

type Entry = {
	gui: GuiObject,
	target: Target,
	offset: Vector3,
	-- Offset exprime dans le repere de la CAMERA (droite / haut / avant a l'ecran) au lieu du monde : l'element reste
	-- alors du meme cote de l'ecran quand on tourne la camera.
	cameraRelative: boolean,
	-- Au-dela, l'element est cache. 0 = jamais cache par la distance.
	maxDistance: number,
	scale: Scale?,
	-- Multiplicateur du grossissement (1 = normal), pour animer une apparition / disparition (0 = invisible).
	scaleMul: number,
	uiScale: UIScale?,
}

local entries: { [GuiObject]: Entry } = {}
local connection: RBXScriptConnection? = nil

local function positionOf(target: Target): Vector3?
	if typeof(target) == "Vector3" then
		return target
	end
	-- Parent verifie : une part detruite ou sortie du streaming laisserait l'element fige en plein ecran.
	return if target.Parent then target.Position else nil
end

local function update()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position

	for gui, entry in pairs(entries) do
		if not gui.Parent then
			entries[gui] = nil
			continue
		end

		local world = positionOf(entry.target)
		if not world then
			gui.Visible = false
			continue
		end
		-- Offset repere camera (reste du meme cote de l'ecran quand on tourne) ou repere monde (fixe dans la scene).
		world += if entry.cameraRelative then camera.CFrame:VectorToWorldSpace(entry.offset) else entry.offset

		local screen, onScreen = camera:WorldToViewportPoint(world)
		-- onScreen est faux DERRIERE la camera aussi. Sans ce test, l'element reapparaitrait en miroir de
		-- l'autre cote de l'ecran des qu'on tourne le dos a sa cible.
		local distance = (world - eye).Magnitude
		local far = entry.maxDistance > 0 and distance > entry.maxDistance
		if not onScreen or far then
			gui.Visible = false
			continue
		end

		gui.Visible = true
		gui.Position = UDim2.fromOffset(screen.X, screen.Y)

		-- Grossissement selon la distance (billboard-like) : taille apparente ~ 1/distance, bornee. Le UIScale est
		-- cree a la demande (reutilise un existant), donc rien a preparer sur l'element cote Studio.
		local scale = entry.scale
		if scale then
			local us = entry.uiScale
			if not us then
				us = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
				us.Parent = gui
				entry.uiScale = us
			end
			us.Scale = math.clamp(scale.ref / math.max(distance, 0.01), scale.min, scale.max) * entry.scaleMul
		end
	end
end

local function ensureLoop()
	if connection then
		return
	end
	-- RenderStepped : la position doit etre calculee AVANT que l'image soit dessinee, sinon l'element traine
	-- d'une frame derriere sa cible des qu'on tourne la camera.
	connection = RunService.RenderStepped:Connect(update)
end

--
-- Accroche `gui` a `target`. `offset` decale le point vise dans le monde, en studs.
-- Rappeler avec le meme gui remplace simplement la cible.
function WorldAnchor.attach(
	gui: GuiObject,
	target: Target,
	offset: Vector3?,
	maxDistance: number?,
	scale: Scale?,
	cameraRelative: boolean?
)
	-- Centre sur le point vise : sans ca c'est le COIN de l'element qui suivrait la cible, et un texte long
	-- partirait toujours vers la droite.
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Cache tant qu'on n'a pas calcule sa premiere position : sinon il clignote une frame a sa place d'editeur.
	gui.Visible = false

	entries[gui] = {
		gui = gui,
		target = target,
		offset = offset or Vector3.zero,
		cameraRelative = cameraRelative or false,
		maxDistance = maxDistance or 0,
		scale = scale,
		scaleMul = 1,
		uiScale = nil,
	}
	ensureLoop()
end

-- Deplace le point vise en cours de route (offset anime). Sans effet si `gui` n'est pas accroche.
function WorldAnchor.setOffset(gui: GuiObject, offset: Vector3)
	local entry = entries[gui]
	if entry then
		entry.offset = offset
	end
end

-- Multiplie le grossissement (1 = normal, 0 = invisible). Sert aux animations d'apparition / disparition. N'a d'effet
-- que si l'element a ete accroche avec une option scale (sinon aucun UIScale n'est cree).
function WorldAnchor.setScaleMul(gui: GuiObject, mul: number)
	local entry = entries[gui]
	if entry then
		entry.scaleMul = mul
	end
end

function WorldAnchor.detach(gui: GuiObject)
	entries[gui] = nil
end

return WorldAnchor
