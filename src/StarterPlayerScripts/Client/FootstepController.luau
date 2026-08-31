--!strict
-- LE PAS DU JOUEUR : ce qu'on en entend, et ce qu'on en voit.
--
-- SON : le joueur ne veut aucun bruit de marche. On coupe le son "Running" par defaut de Roblox (volume 0) et on
-- ne joue RIEN a la place. Le module reste le point unique ou rebrancher un son plus tard.
--
-- IMAGE : une trainee de poussiere derriere ses pieds. Elle vit ici et pas dans un module a elle, parce qu'elle
-- a besoin d'EXACTEMENT la meme question -- "est-ce qu'il marche, au sol ?" -- et qu'une seconde detection
-- finirait par repondre autrement que celle-ci.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FootstepController = {}

local player = Players.LocalPlayer

-- Ou vit l'emetteur dans les Assets. Rojo ne synchronise PAS ce dossier : sur une place ou il manque, la
-- poussiere ne sort pas et le module le dit une fois, sans rien casser d'autre.
local DUST_PATH = { "Assets", "Effects", "Particles", "CloudsWalk" }

-- La part qui porte l'emetteur. Plate et large : c'est une flaque de poussiere au sol, pas un cube.
local DUST_SIZE = Vector3.new(2, 0.2, 2)
-- Combien de studs DERRIERE lui. La poussiere se leve la ou le pied vient de quitter le sol, pas sous le ventre.
local BACK_OFFSET = 1.2
-- Jusqu'ou on cherche le sol sous le joueur.
local GROUND_RAY = 8
-- En dessous, on considere qu'il ne marche pas. Un seuil et non zero : `MoveDirection` garde des miettes une
-- image ou deux apres le relachement de la touche, et l'emetteur clignoterait a chaque arret.
local MOVE_MIN = 0.1

local function muteDefaultRunning(char: Model)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	task.spawn(function()
		local running = hrp:WaitForChild("Running", 5)
		if running and running:IsA("Sound") then
			running.Volume = 0
		end
	end)
end

local function findDustTemplate(): ParticleEmitter?
	local node: Instance? = ReplicatedStorage
	for _, name in ipairs(DUST_PATH) do
		node = node and node:FindFirstChild(name)
	end
	return if node and node:IsA("ParticleEmitter") then node :: ParticleEmitter else nil
end

local dustConn: RBXScriptConnection? = nil
local dustPart: BasePart? = nil

local function stopDust()
	if dustConn then
		dustConn:Disconnect()
		dustConn = nil
	end
	if dustPart then
		dustPart:Destroy()
		dustPart = nil
	end
end

local function startDust(char: Model)
	stopDust() -- un respawn ne doit pas laisser la precedente derriere lui

	local template = findDustTemplate()
	if not template then
		-- ANORMAL ET ACTIONNABLE : l'asset est absent de CETTE place, et ca se corrige en le copiant.
		warn(
			`[Footstep] Emetteur introuvable (ReplicatedStorage.{table.concat(DUST_PATH, ".")}) : `
				.. "pas de poussiere au pas. Rojo ne synchronise pas les Assets, il faut le copier dans cette place."
		)
		return
	end

	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then
		return
	end

	-- ANCREE, ET DANS LE WORKSPACE. Deux pieges evites d'un coup :
	--   1. non ancree, elle tomberait sous la carte et emettrait la-bas -- l'effet "ne marcherait pas" alors
	--      qu'il jouerait parfaitement, ailleurs ;
	--   2. rangee dans le personnage, elle en decalerait la BOITE ENGLOBANTE, donc son `GetPivot` -- et tout ce
	--      qui calcule un placement dessus partirait de travers, sans que rien ne le signale.
	local part = Instance.new("Part")
	part.Name = "BackRootPart"
	part.Size = DUST_SIZE
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- sans effet si CanCollide etait vrai, d'ou l'ordre
	part.CanTouch = false
	part.Transparency = 1
	part.CastShadow = false
	part.Parent = workspace

	template:Clone().Parent = part
	dustPart = part

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	-- On s'exclut soi-meme ET le personnage : sans ca le rayon toucherait la part qu'on est en train de placer,
	-- et elle se poserait sur elle-meme.
	rayParams.FilterDescendantsInstances = { char, part }

	dustConn = RunService.Heartbeat:Connect(function()
		if not part.Parent or not hrp.Parent then
			return
		end

		-- DERRIERE LUI, dans SON dos : on recule le long de son regard, pas d'un axe du monde. Sinon la trainee
		-- change de cote selon l'orientation du personnage.
		local behind = hrp.Position - hrp.CFrame.LookVector * BACK_OFFSET
		local hit = workspace:Raycast(behind, Vector3.new(0, -GROUND_RAY, 0), rayParams)
		part.Position = if hit then hit.Position else behind

		-- IL MARCHE, ET IL EST AU SOL. `MoveDirection` dit son INTENTION -- ce qu'il demande -- alors que la
		-- vitesse dit ce qui lui arrive : pousse par autre chose, il fumerait sans avoir fait un pas.
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		local walking = grounded and humanoid.MoveDirection.Magnitude > MOVE_MIN
		for _, d in ipairs(part:GetChildren()) do
			if d:IsA("ParticleEmitter") then
				d.Enabled = walking
			end
		end
	end)
end

local function onCharacter(char: Model)
	muteDefaultRunning(char)
	startDust(char)
end

function FootstepController.init()
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	-- La part vit dans le Workspace, donc rien ne la nettoie toute seule quand le personnage disparait.
	player.CharacterRemoving:Connect(stopDust)
end

return FootstepController
