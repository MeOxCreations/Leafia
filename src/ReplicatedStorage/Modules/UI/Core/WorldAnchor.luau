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
-- ATTENTION AU DECALAGE DE 36 PIXELS. WorldToViewportPoint rend des coordonnees SANS l'inset de la barre
-- Roblox : il va donc avec un ScreenGui dont IgnoreGuiInset est FAUX. Si l'element apparait ~36 px trop haut
-- ou trop bas, c'est ce couple qui est casse, pas le calcul. Meme piege que GetMouseLocale et ScreenPointToRay,
-- deja paye une fois.

local RunService = game:GetService("RunService")

local WorldAnchor = {}

export type Target = BasePart | Vector3

type Entry = {
	gui: GuiObject,
	target: Target,
	offset: Vector3,
	-- Au-dela, l'element est cache. 0 = jamais cache par la distance.
	maxDistance: number,
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
		world += entry.offset

		local screen, onScreen = camera:WorldToViewportPoint(world)
		-- onScreen est faux DERRIERE la camera aussi. Sans ce test, l'element reapparaitrait en miroir de
		-- l'autre cote de l'ecran des qu'on tourne le dos a sa cible.
		local far = entry.maxDistance > 0 and (world - eye).Magnitude > entry.maxDistance
		if not onScreen or far then
			gui.Visible = false
			continue
		end

		gui.Visible = true
		gui.Position = UDim2.fromOffset(screen.X, screen.Y)
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
function WorldAnchor.attach(gui: GuiObject, target: Target, offset: Vector3?, maxDistance: number?)
	-- Centre sur le point vise : sans ca c'est le COIN de l'element qui suivrait la cible, et un texte long
	-- partirait toujours vers la droite.
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Cache tant qu'on n'a pas calcule sa premiere position : sinon il clignote une frame a sa place d'editeur.
	gui.Visible = false

	entries[gui] = {
		gui = gui,
		target = target,
		offset = offset or Vector3.zero,
		maxDistance = maxDistance or 0,
	}
	ensureLoop()
end

function WorldAnchor.detach(gui: GuiObject)
	entries[gui] = nil
end

return WorldAnchor
