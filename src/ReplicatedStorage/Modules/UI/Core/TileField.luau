--!strict
-- FOND EN TUILES reutilisable : une grille de tuiles qui defile en diagonale par-dessus ce qui est derriere, avec un
-- TROU clair (bord doux) au centre (ou decale). Pas de gradient radial natif en UI Roblox -> on le fait A LA MAIN, par
-- tuile, via la distance de son centre au centre du trou (dans le trou -> ImageTransparency 1 ; au bord -> transparence
-- de base ; doux entre les deux).
--
-- start(config) cree le support (soit un ScreenGui plein ecran pour un FOND GLOBAL, soit un Frame dans un parent pour un
-- FOND DE PANNEAU) et lance la boucle. Le handle rendu permet de tout couper (stop) ou de mettre en pause / cacher
-- (setVisible), pour ne pas laisser une boucle tourner sous une UI cachee.
--
-- Dimensionne sur le VIEWPORT (les deux usages actuels sont plein ecran). holeCenterX / holeCenterY (fractions du
-- viewport) permettent de DECALER le trou clair selon la mise en page (ex : ecran de company, trou a droite des cartes).

local RunService = game:GetService("RunService")

local TileField = {}

export type Config = {
	parent: Instance, -- PlayerGui (si screenGui = true) ou un GuiObject (fond de panneau)
	screenGui: boolean?, -- true = on cree notre propre ScreenGui plein ecran (fond global, derriere l'UI)
	displayOrder: number?, -- DisplayOrder du ScreenGui (defaut -5 : derriere l'UI, devant le monde 3D)
	name: string?, -- nom du support cree
	image: string?, -- tuile (defaut : la tuile hexagones du projet)
	tileFrac: number?, -- taille d'une tuile = fraction de la HAUTEUR du viewport (defaut 0.1)
	baseTransparency: number?, -- transparence des tuiles LOIN du trou (defaut 0.6)
	speed: number?, -- vitesse du defilement diagonal, px/s (defaut 30)
	holeInner: number?, -- rayon du trou TOTALEMENT clair, fraction de la hauteur (defaut 0.6)
	holeOuter: number?, -- rayon ou les tuiles retrouvent leur transparence de base (defaut 0.88)
	holeCenterX: number?, -- centre du trou en fraction de LARGEUR (defaut 0.5)
	holeCenterY: number?, -- centre du trou en fraction de HAUTEUR (defaut 0.5)
	margin: number?, -- tuiles de rab hors ecran de chaque cote (defaut 3 : le recyclage se voit pas au bord)
	zIndex: number?, -- ZIndex du support ET des tuiles (defaut 0 : passer sous les autres elements du panneau)
}

export type Handle = {
	stop: () -> (),
	setVisible: (boolean) -> (),
}

local DEFAULT_IMAGE = "rbxassetid://111706805079464"

local function num(v: number?, d: number): number
	return if v ~= nil then v else d
end

function TileField.start(config: Config): Handle
	local image = config.image or DEFAULT_IMAGE
	local tileFrac = num(config.tileFrac, 0.1)
	local baseTransparency = num(config.baseTransparency, 0.6)
	local speed = num(config.speed, 30)
	local holeInner = num(config.holeInner, 0.6)
	local holeOuter = num(config.holeOuter, 0.88)
	local holeCenterX = num(config.holeCenterX, 0.5)
	local holeCenterY = num(config.holeCenterY, 0.5)
	local margin = num(config.margin, 3)
	local zIndex = num(config.zIndex, 0)

	-- Support : ScreenGui plein ecran (fond global) OU Frame dans le parent (fond de panneau). Dans les deux cas les
	-- tuiles vivent dans un Frame plein-cadre qui les clippe. On garde `toDestroy` (ce qu'on retire au stop) a part.
	local toDestroy: Instance
	local container: Frame
	if config.screenGui then
		local sg = Instance.new("ScreenGui")
		sg.Name = config.name or "TileField"
		sg.ResetOnSpawn = false
		sg.ScreenInsets = Enum.ScreenInsets.None
		sg.DisplayOrder = num(config.displayOrder, -5)
		sg.Parent = config.parent
		local f = Instance.new("Frame")
		f.Name = "Tiles"
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 1)
		f.ClipsDescendants = true
		f.Parent = sg
		toDestroy = sg
		container = f
	else
		local f = Instance.new("Frame")
		f.Name = config.name or "TileField"
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 1)
		f.ClipsDescendants = true
		f.ZIndex = zIndex
		f.Parent = config.parent
		toDestroy = f
		container = f
	end

	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local tileSize = viewport.Y * tileFrac
	-- Grille qui couvre l'ecran + `margin` tuiles de rab de chaque cote (recyclage du defilement hors champ).
	local cols = math.ceil(viewport.X / tileSize) + margin * 2
	local rows = math.ceil(viewport.Y / tileSize) + margin * 2

	local tiles: { ImageLabel } = {}
	for _ = 1, cols * rows do
		local t = Instance.new("ImageLabel")
		t.BackgroundTransparency = 1
		t.Image = image
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Size = UDim2.fromOffset(tileSize, tileSize)
		t.ZIndex = zIndex
		t.Parent = container
		table.insert(tiles, t)
	end

	local visible = true
	local scroll = 0
	local conn = RunService.RenderStepped:Connect(function(dt: number)
		if not visible then
			return -- cache : on ne recalcule rien (pas de boucle qui tourne pour rien sous une UI cachee)
		end
		scroll = (scroll + speed * dt) % tileSize -- une seule periode : au wrap le motif est identique
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else viewport
		local cx, cy = vp.X * holeCenterX, vp.Y * holeCenterY
		local rInner = vp.Y * holeInner
		local rOuter = vp.Y * holeOuter
		local span = math.max(rOuter - rInner, 1)
		local idx = 0
		for r = 0, rows - 1 do
			for c = 0, cols - 1 do
				idx += 1
				local t = tiles[idx]
				local px = (c - margin) * tileSize + scroll + tileSize / 2
				local py = (r - margin) * tileSize + scroll + tileSize / 2
				t.Position = UDim2.fromOffset(px, py)
				local dx, dy = px - cx, py - cy
				local dist = math.sqrt(dx * dx + dy * dy)
				if dist <= rInner then
					t.ImageTransparency = 1
				elseif dist >= rOuter then
					t.ImageTransparency = baseTransparency
				else
					t.ImageTransparency = 1 + (baseTransparency - 1) * ((dist - rInner) / span)
				end
			end
		end
	end)

	local handle: Handle = {
		stop = function()
			conn:Disconnect()
			toDestroy:Destroy()
		end,
		setVisible = function(v: boolean)
			visible = v
			container.Visible = v
		end,
	}
	return handle
end

return TileField
