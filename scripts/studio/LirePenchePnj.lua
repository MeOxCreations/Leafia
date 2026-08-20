-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO, **PENDANT UNE PARTIE** (Play), pas en mode edition.
-- Hors de src/, donc Rojo ne le synchronise pas : outil d'atelier.
--
-- POURQUOI CELUI-LA EN PLUS DE RedresserPnj
-- RedresserPnj lit le C0 des Motor6D : la pose de REPOS du rig, celle qu'on voit en mode edition.
-- Une ANIMATION n'ecrit pas dans C0, elle ecrit dans `Transform`, une autre propriete du meme joint.
-- Un rig parfaitement droit a l'arret peut donc pencher des que la piste tourne, et le premier script ne verra rien.
--
-- CE QU'IL FAIT
-- Il echantillonne `Transform` pendant DUREE secondes et rapporte l'inclinaison MINIMALE et MAXIMALE vue.
-- La difference entre les deux est ce qui compte :
--   - min et max PROCHES  -> l'animation applique une inclinaison CONSTANTE. Elle se corrige par un contre-angle
--     fixe, sans toucher a l'animation.
--   - min et max ELOIGNES -> l'inclinaison fait partie du mouvement anime. La seule vraie correction est de
--     reprendre l'animation avec le corps droit.

local NOM_DU_PNJ = "OldManIdle"
local DUREE = 3

local model = workspace:FindFirstChild(NOM_DU_PNJ, true)
if not model or not model:IsA("Model") then
	warn(`[LirePenchePnj] Model "{NOM_DU_PNJ}" introuvable.`)
	return
end

local root = model:FindFirstChild("HumanoidRootPart")
if not root or not root:IsA("BasePart") then
	warn(`[LirePenchePnj] Pas de HumanoidRootPart sur "{NOM_DU_PNJ}".`)
	return
end

local joints = {}
for _, descendant in ipairs(model:GetDescendants()) do
	if descendant:IsA("Motor6D") and descendant.Part0 == root then
		joints[#joints + 1] = descendant
	end
end
if #joints == 0 then
	warn("[LirePenchePnj] Aucun Motor6D ne part de la HumanoidRootPart. Le corps n'y est donc pas accroche.")
	return
end

-- Quelles pistes tournent ? Si aucune, l'inclinaison ne vient PAS de l'animation et il faut chercher ailleurs.
local humanoid = model:FindFirstChildOfClass("Humanoid")
local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
if animator then
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		print(`[LirePenchePnj] piste en cours : {track.Animation and track.Animation.AnimationId} (poids {track.WeightCurrent})`)
	end
end

local stats = {}
for _, joint in ipairs(joints) do
	stats[joint] = { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge }
end

local deadline = os.clock() + DUREE
while os.clock() < deadline do
	for _, joint in ipairs(joints) do
		local x, _, z = joint.Transform:ToEulerAnglesYXZ()
		local s = stats[joint]
		s.minX = math.min(s.minX, x)
		s.maxX = math.max(s.maxX, x)
		s.minZ = math.min(s.minZ, z)
		s.maxZ = math.max(s.maxZ, z)
	end
	task.wait()
end

for _, joint in ipairs(joints) do
	local s = stats[joint]
	local spread = math.deg(math.max(s.maxX - s.minX, s.maxZ - s.minZ))
	print(
		`[LirePenchePnj] {joint.Name} -> {joint.Part1 and joint.Part1.Name} | `
			.. `inclinaison {math.floor(math.deg(s.minX))} a {math.floor(math.deg(s.maxX))} deg | `
			.. `roulis {math.floor(math.deg(s.minZ))} a {math.floor(math.deg(s.maxZ))} deg | `
			.. `variation {math.floor(spread)} deg`
	)
	if spread < 3 and (math.abs(math.deg(s.minX)) > 3 or math.abs(math.deg(s.minZ)) > 3) then
		print("   -> inclinaison CONSTANTE : un contre-angle fixe la corrige, sans toucher a l'animation.")
	elseif spread >= 3 then
		print("   -> l'inclinaison FAIT PARTIE du mouvement : il faut reprendre l'animation avec le corps droit.")
	end
end
