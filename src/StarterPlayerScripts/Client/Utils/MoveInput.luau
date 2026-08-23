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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoveThumb = require(ReplicatedStorage.Modules.UI.Core.MoveThumb)

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
	-- SECOURS N.1 : NOTRE PROPRE JOYSTICK.
	--
	-- Le thumbstick tactile de Roblox cesse de remonter quoi que ce soit des qu'une feature prend la camera en
	-- main. Les features concernees allument alors le notre (voir MoveThumb), et il passe AVANT les autres secours
	-- parce que c'est le seul qui reflete VRAIMENT ce que le doigt fait a cet instant.
	if vec.Magnitude < 0.05 then
		local thumb = MoveThumb.get()
		if thumb.Magnitude > 0.05 then
			vec = thumb
		end
	end

	-- SECOURS N.2 : LE HUMANOID LUI-MEME.
	--
	-- `GetMoveVector` rend ZERO sur certains appareils tactiles -- mesure a l'ecran, joystick pousse a fond. On ne
	-- sait pas pourquoi, et on cesse de chercher : il existe une AUTRE source de la meme information, que Roblox
	-- remplit lui-meme quel que soit le controleur (doigt, clavier, manette).
	--
	-- `MoveDirection` est en repere MONDE, alors que tout le reste attend du repere CAMERA (X = cote, Z = arriere,
	-- la convention de `GetMoveVector`). On le RAMENE donc dans le repere de la camera, sinon on melangerait deux
	-- reperes -- piege deja paye sur la conduite de la tondeuse.
	--
	-- POURQUOI CA MARCHE MALGRE LE COMMENTAIRE EN TETE DE CE FICHIER : on le lit AVANT que la boucle appelante
	-- n'appelle `Move` sur cette image. A cet instant il porte encore la demande du module de controle de Roblox,
	-- c'est-a-dire l'intention du joueur -- pas notre contrainte.
	if vec.Magnitude < 0.05 then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local camera = workspace.CurrentCamera
		if humanoid and camera then
			local world = humanoid.MoveDirection
			if world.Magnitude > 0.05 then
				local relative = camera.CFrame:VectorToObjectSpace(world)
				-- A PLAT : une camera qui plonge donnerait une composante verticale, sans aucun sens pour un
				-- deplacement au sol.
				local flat = Vector3.new(relative.X, 0, relative.Z)
				if flat.Magnitude > 0.05 then
					vec = flat.Unit * math.min(world.Magnitude, 1)
				end
			end
		end
	end

	-- SECOURS N.3, CLAVIER : si les deux precedents rendent du VIDE (place secondaire / tuto ou PlayerModule pas
	-- encore pret), on lit WASD en direct pour que la feature reponde quand meme.
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
