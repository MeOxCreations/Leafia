--!strict
-- TEST / DECORATION : herbe en GRILLE (mode cell) sur le sol du plot DU JOUEUR (pas tous les plots -- ca faisait exploser
-- le jeu). Clone de ReplicatedStorage.Assets.Contents.grass (skinned mesh), couleur variee par BRUIT DE PERLIN (taches
-- naturelles), balancement joue via AnimationController.
--
-- CE N'EST PAS DU GAMEPLAY : c'est de l'habillage, pose avant l'arbre de competences (la vraie progression).
--
-- QUAND : l'herbe pousse sur le plot d'un joueur quand il le SELECTIONNE (attribut LeafiaPlot pose par PlotService), UNE
-- fois par plot et par session serveur (regenere donc au redemarrage -> reprend les reglages ci-dessous). Jamais sur les
-- plots vides.
--
-- PERF : ca reste beaucoup de skinned meshes animes sur un plot. Le modele porte un Humanoid (tres cher en nombre) -> on
-- le REMPLACE par un AnimationController a la pose. Si ca rame encore : monter CELL_SIZE (moins dense) ou ANIMATE = false.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GrassService = {}

-- ===== A REGLER (knobs) =====
local ENABLED = false -- coupe tout le systeme d'un coup (test). COUPE : trop lourd (dense + anime). La vraie herbe = les cellules tondables
local CELL_SIZE = 4 -- studs entre deux brins (plus grand = moins dense = plus fluide). LE levier de perf
local JITTER = 0.45 -- decalage aleatoire, fraction de CELL_SIZE : casse la grille (0 = grille parfaite)
local RANDOM_YAW = true -- oriente chaque brin au hasard (plus naturel)
local Y_OFFSET = 0 -- ajustement de hauteur si l'herbe flotte / s'enfonce (studs). A regler a l'oeil
local MAX_PER_PLOT = 1200 -- plafond de securite par plot (evite un runaway sur un enorme sol). Monte avec la densite
local ANIMATE = true -- jouer l'animation de balancement (mettre false si ca rame)
local BATCH = 25 -- brins poses entre deux `task.wait()` : etale la generation, evite un gros hitch
-- Couleur : chaque brin prend une teinte entre COLOR_A (creux du bruit) et COLOR_B (crete) selon un bruit de Perlin de
-- sa position -> patches doux. Base de l'asset ~ (179, 255, 107). A REGLER a l'oeil.
local COLOR_A = Color3.fromRGB(120, 200, 80) -- vert plus fonce
local COLOR_B = Color3.fromRGB(190, 255, 120) -- vert plus clair
local COLOR_FREQ = 0.03 -- frequence du bruit : petit = grandes taches, grand = variation serree

local GRASS_PATH = { "Assets", "Contents", "grass" }
local ANIM_PATH = { "Animations", "Props", "Environnement", "GrassAnimation" }
local GROUND_NAME = "PrimaryGround"
local FOLDER_NAME = "LeafiaGrass" -- un seul enfant par plot ; facile a retrouver / regenerer
local PLOT_ATTRIBUTE = "LeafiaPlot" -- pose par PlotService : le Slot (nom) du plot choisi par le joueur

local grownThisSession: { [string]: boolean } = {} -- Slot -> deja herbe cette session (une fois par plot)

local function resolve(root: Instance, path: { string }): Instance?
	local node: Instance? = root
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

-- Couleur du brin (bruit) : posee sur TOUTES ses SurfaceAppearance (l'asset peut en avoir plusieurs).
local function tint(clone: Instance, color: Color3)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("SurfaceAppearance") then
			d.Color = color
		end
	end
end

-- Remplace le Humanoid (trop cher en grand nombre) par un AnimationController, garde l'Animator, joue l'anim en boucle.
local function playSway(clone: Instance, animation: Animation)
	local animator: Animator? = nil
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		animator = humanoid:FindFirstChildOfClass("Animator")
		local controller = Instance.new("AnimationController")
		controller.Parent = clone
		if animator then
			animator.Parent = controller -- on garde l'Animator, on jette juste le Humanoid
		else
			animator = Instance.new("Animator")
			animator.Parent = controller
		end
		humanoid:Destroy()
	else
		local controller = clone:FindFirstChildOfClass("AnimationController")
		if not controller then
			controller = Instance.new("AnimationController")
			controller.Parent = clone
		end
		animator = controller:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = controller
		end
	end
	local track = (animator :: Animator):LoadAnimation(animation)
	track.Looped = true
	track:Play()
end

-- Pose une grille de brins sur le DESSUS d'un sol (repere du sol, donc suit son orientation). Renvoie le nombre pose.
local function growOnGround(ground: BasePart, template: Instance, animation: Animation?): number
	local parent = ground.Parent
	if not parent then
		return 0
	end
	local old = parent:FindFirstChild(FOLDER_NAME) -- idempotent : on regenere proprement
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = parent

	local halfX = ground.Size.X / 2
	local halfZ = ground.Size.Z / 2
	local topY = ground.Size.Y / 2 + Y_OFFSET
	local count = 0
	local lx = -halfX + CELL_SIZE / 2
	while lx <= halfX and count < MAX_PER_PLOT do
		local lz = -halfZ + CELL_SIZE / 2
		while lz <= halfZ and count < MAX_PER_PLOT do
			local jx = (math.random() - 0.5) * CELL_SIZE * JITTER
			local jz = (math.random() - 0.5) * CELL_SIZE * JITTER
			local yaw = if RANDOM_YAW then math.random() * math.pi * 2 else 0
			local worldCF = ground.CFrame * CFrame.new(lx + jx, topY, lz + jz) * CFrame.Angles(0, yaw, 0)

			local clone = template:Clone()
			local pos = worldCF.Position
			local n = math.noise(pos.X * COLOR_FREQ, pos.Z * COLOR_FREQ) -- ~ [-1, 1]
			tint(clone, COLOR_A:Lerp(COLOR_B, math.clamp((n + 1) / 2, 0, 1)))

			if clone:IsA("Model") then
				clone:PivotTo(worldCF)
			elseif clone:IsA("BasePart") then
				clone.CFrame = worldCF
			end
			if ANIMATE and animation then
				playSway(clone, animation)
			end
			clone.Parent = folder

			count += 1
			if count % BATCH == 0 then
				task.wait() -- etale la charge : pas de gros hitch quand un sol porte des centaines de brins
			end
			lz += CELL_SIZE
		end
		lx += CELL_SIZE
	end
	return count
end

-- Herbe sur le plot du Slot donne, si pas deja fait cette session. Le sol est PrimaryGround sous Worlds.Plots[slot].
local function growForSlot(slot: string, template: Instance, animation: Animation?)
	if grownThisSession[slot] then
		return
	end
	local worlds = Workspace:FindFirstChild("Worlds")
	local plots = worlds and worlds:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild(slot)
	local ground = plot and plot:FindFirstChild(GROUND_NAME)
	if not (ground and ground:IsA("BasePart")) then
		return -- plot pas (encore) la : on ne marque PAS -> on reessaiera au prochain signal
	end
	grownThisSession[slot] = true
	task.spawn(function()
		local n = growOnGround(ground :: BasePart, template, animation)
		print(`[GrassService] Herbe sur {slot} : {n} brins (CELL_SIZE {CELL_SIZE}, anim {tostring(ANIMATE)}).`)
	end)
end

-- Suit l'attribut LeafiaPlot d'un joueur : des qu'il occupe un plot, l'herbe pousse dessus (une fois).
local function watchPlayer(player: Player, template: Instance, animation: Animation?)
	local function check()
		local slot = player:GetAttribute(PLOT_ATTRIBUTE)
		if type(slot) == "string" and slot ~= "" then
			growForSlot(slot, template, animation)
		end
	end
	player:GetAttributeChangedSignal(PLOT_ATTRIBUTE):Connect(check)
	check() -- au cas ou le plot est deja pose (rejoin)
end

function GrassService.init()
	if not ENABLED then
		return
	end
	local template = resolve(ReplicatedStorage, GRASS_PATH)
	if not template then
		warn("[GrassService] Herbe introuvable : ReplicatedStorage.Assets.Contents.grass -> rien genere")
		return
	end
	local animAsset = resolve(ReplicatedStorage, ANIM_PATH)
	local animation: Animation? = if animAsset and animAsset:IsA("Animation") then animAsset else nil
	if ANIMATE and not animation then
		warn("[GrassService] GrassAnimation introuvable (Animations.Props.Environnement) : herbe posee SANS balancement")
	end

	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player, template, animation)
	end
	Players.PlayerAdded:Connect(function(player)
		watchPlayer(player, template, animation)
	end)
end

return GrassService
