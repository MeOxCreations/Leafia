--!strict
-- INPUT DE DEPLACEMENT BRUT du joueur, en repere monde.
--
-- POURQUOI PAS `humanoid.MoveDirection` : des qu'on contraint le deplacement avec `humanoid:Move`, MoveDirection
-- ne reflete plus l'INTENTION du joueur mais notre propre contrainte. On lit donc la source, le module de controle.
--
-- POURQUOI UN MODULE A PART : deux features en ont besoin (le portage d'echelle et la conduite de la tondeuse), et
-- la meme logique a deux endroits finit toujours par diverger sur l'une des deux.
--
-- ZERO YIELD PAR FRAME. `require(PlayerModule)` peut attendre 10 a 20 secondes (WaitForChild), surtout dans une
-- place secondaire. Le laisser dans la fonction appelee PAR IMAGE gelait toute la boucle appelante le temps du
-- WaitForChild. Il est donc resolu UNE fois en tache de fond, avec retry, et `get()` rend zero tant que ce n'est
-- pas pret.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local MoveInput = {}

local player = Players.LocalPlayer
local controlModule: any = nil

task.spawn(function()
	while not controlModule do
		local ok, result = pcall(function()
			local scripts = player:WaitForChild("PlayerScripts", 10)
			local playerModule = scripts and require(scripts:WaitForChild("PlayerModule", 10)) :: any
			return playerModule and playerModule:GetControls()
		end)
		if ok and result then
			controlModule = result
		else
			-- RETRY : au boot, et surtout en place secondaire, PlayerModule / GetControls peut ne pas etre pret.
			task.wait(0.3)
		end
	end
end)

-- Direction voulue par le joueur. X = pas de cote, Z = avant/arriere (negatif vers l'avant, convention Roblox).
-- Vecteur nul = le joueur ne demande rien.
function MoveInput.get(): Vector3
	local vec = Vector3.zero
	local cm = controlModule
	if cm then
		local ok, v = pcall(function()
			return cm:GetMoveVector()
		end)
		if ok and typeof(v) == "Vector3" then
			vec = v
		end
	end
	-- SECOURS CLAVIER : si le module de controle rend du VIDE (place secondaire / tuto), on lit WASD en direct pour
	-- que la feature reponde quand meme. Ne couvre PAS le tactile -- c'est un filet, pas un chemin.
	if vec.Magnitude < 0.05 then
		local x, z = 0, 0
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			z -= 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			z += 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			x -= 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			x += 1
		end
		if x ~= 0 or z ~= 0 then
			vec = Vector3.new(x, 0, z)
		end
	end
	return vec
end

return MoveInput
