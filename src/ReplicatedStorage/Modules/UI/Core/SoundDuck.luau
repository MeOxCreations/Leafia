--!strict
-- BAISSE LE SON DU JEU, le temps d'une scene. Pendant une cinematique, la musique et les bruits d'ambiance
-- tirent l'oreille ailleurs : baisser le reste ramene l'attention sur ce qui se joue, sans rien couper.
--
-- COMMENT. Un SoundGroup pose sur TOUS les Sound de SoundService. Baisser le GROUPE baisse tout d'un coup, sans
-- jamais toucher au `Volume` de chaque son -- celui-la reste ce qui a ete regle dans Studio, et Studio reste la
-- source de verite. Un module qui reecrirait les volumes un par un devrait les memoriser pour les rendre, et il
-- finirait par en perdre un.
--
-- LES CLONES EN HERITENT, et c'est ce qui rend l'affaire simple. `SoundUtils` joue chaque son ponctuel en
-- CLONANT celui de SoundService, et un clone copie son SoundGroup : les bruits declenches PENDANT la scene sont
-- donc baisses aussi, sans une ligne de plus.
--
-- CE QUE CA NE COUVRE PAS : les Sound poses sur des parts du Workspace. Ils vivent hors de SoundService, donc
-- hors du groupe. A traiter le jour ou il y en aura un qui gene -- pas avant, ce serait deviner.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local SoundDuck = {}

local GROUP_NAME = "LeafiaGameSounds"

local group: SoundGroup? = nil
local tween: Tween? = nil

-- On n'ADOPTE que les sons SANS groupe. Voler ceux qui en ont deja un ecraserait un reglage fait dans Studio,
-- et le rendre ensuite demanderait de retenir lequel appartenait a qui.
local function adopt(inst: Instance)
	local g = group
	if g and inst:IsA("Sound") and inst.SoundGroup == nil then
		inst.SoundGroup = g
	end
end

local function ensure()
	if group then
		return
	end
	local existing = SoundService:FindFirstChild(GROUP_NAME)
	if existing and existing:IsA("SoundGroup") then
		group = existing
	else
		local made = Instance.new("SoundGroup")
		made.Name = GROUP_NAME
		made.Volume = 1
		made.Parent = SoundService
		group = made
	end
	for _, d in ipairs(SoundService:GetDescendants()) do
		adopt(d)
	end
	-- LES SONS ARRIVENT APRES. La musique du tuto est un clone cree au boot, et chaque bruit ponctuel est un
	-- clone cree a l'instant ou il se joue : sans cette ecoute, seuls ceux presents a la premiere baisse
	-- seraient concernes.
	SoundService.DescendantAdded:Connect(adopt)
end

local function fadeTo(volume: number, seconds: number)
	ensure()
	local g = group
	if not g then
		return
	end
	-- On COUPE le fondu en cours avant d'en lancer un autre : deux tweens sur la meme propriete se disputent le
	-- groupe a chaque image, et la valeur finale devient celle du dernier a FINIR, pas du dernier demande.
	if tween then
		tween:Cancel()
	end
	local next_ = TweenService:Create(
		g,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Volume = volume }
	)
	tween = next_
	next_:Play()
end

--- Baisse le jeu a `amount` (fraction de son volume normal), en `seconds`.
function SoundDuck.duck(amount: number, seconds: number)
	fadeTo(math.clamp(amount, 0, 1), math.max(seconds, 0))
end

--- Rend au jeu son volume normal.
function SoundDuck.restore(seconds: number)
	fadeTo(1, math.max(seconds, 0))
end

return SoundDuck
