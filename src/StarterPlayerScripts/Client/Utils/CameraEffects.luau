--!strict
-- Retours camera : secousse et pincement de champ de vision.
--
-- Purement client, et volontairement generique : ce module ne connait ni le taille-haie ni le demarrage. Il
-- saura secouer la camera pour la coupe, pour un choc, pour un pas lourd. C'est l'appelant qui donne le
-- dosage.
--
-- La secousse passe par Humanoid.CameraOffset et NON par Camera.CFrame. Ecrire dans la CFrame revient a se
-- battre chaque frame contre les scripts de camera de Roblox, ce qui produit des saccades des que le joueur
-- bouge la souris. CameraOffset est justement prevu pour ca : Roblox l'applique par-dessus sa propre camera.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CameraEffects = {}

local player = Players.LocalPlayer

-- Jetons : une nouvelle secousse annule la precedente. Sans ca, deux effets qui se chevauchent additionnent
-- leurs offsets et le dernier a se terminer remet zero alors que l'autre tournait encore.
local shakeToken = 0
local fovToken = 0

local function getHumanoid(): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

-- Secousse amortie : forte au debut, eteinte a la fin. Une secousse d'amplitude constante se lit comme une
-- panne de moteur de jeu, pas comme un impact.
function CameraEffects.Shake(intensity: number, duration: number)
	if intensity <= 0 or duration <= 0 then
		return
	end
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end

	shakeToken += 1
	local token = shakeToken

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			local dt = RunService.Heartbeat:Wait()
			-- Le personnage a pu mourir, ou une autre secousse a pris la main.
			if shakeToken ~= token or humanoid.Parent == nil then
				return
			end
			elapsed += dt

			local falloff = 1 - (elapsed / duration)
			local amount = intensity * falloff
			humanoid.CameraOffset = Vector3.new(
				(math.random() - 0.5) * 2 * amount,
				(math.random() - 0.5) * 2 * amount,
				0
			)
		end

		if shakeToken == token and humanoid.Parent then
			-- Remise a zero EXACTE : un falloff s'approche de zero sans l'atteindre, et la camera resterait
			-- decalee d'un cheveu pour toujours.
			humanoid.CameraOffset = Vector3.zero
		end
	end)
end

-- Pincement de champ de vision : on quitte la valeur de repos puis on y revient. Le retour est plus lent que
-- l'aller, comme une respiration : l'inverse donne un effet de ressort mecanique.
function CameraEffects.PunchFov(amount: number, duration: number)
	if amount == 0 or duration <= 0 then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	fovToken += 1
	local token = fovToken
	-- La valeur de repos est lue AVANT de bouger. Si un pincement est deja en cours, on la relit sur une
	-- camera deja pincee et le decalage s'accumulerait a chaque tirage.
	local base = camera.FieldOfView

	local outTween = TweenService:Create(
		camera,
		TweenInfo.new(duration * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = base + amount }
	)
	outTween:Play()
	outTween.Completed:Once(function()
		if fovToken ~= token or not camera.Parent then
			return
		end
		TweenService:Create(
			camera,
			TweenInfo.new(duration * 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = base }
		):Play()
	end)
end

return CameraEffects
