-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO, EN MODE EDITION (pas en Play).
-- Hors de src/, donc Rojo ne le synchronise pas : c'est un outil d'atelier, pas du code de jeu.
--
-- PROBLEME QU'IL REGLE
-- Un PNJ dont le corps penche alors que le Model, lui, est droit.
-- Le Humanoid FORCE sa HumanoidRootPart a rester verticale. Si le Motor6D qui accroche le corps a cette root porte
-- une rotation (parce que le rig a ete pose de travers, ou importe depuis un logiciel qui n'a pas le meme axe
-- vertical), alors une fois la root redressee c'est le CORPS qui part en biais, du meme angle.
-- Tant que tout etait ancre, rien ne redressait la root : le defaut ne se voyait pas.
--
-- CE QU'IL FAIT
-- Sur chaque Motor6D partant de la HumanoidRootPart, il ne garde du C0 que la rotation AUTOUR DE LA VERTICALE
-- (le sens dans lequel le personnage regarde) et jette l'inclinaison avant / arriere et le roulis.
-- La position n'est pas touchee : le corps ne se deplace pas, il se redresse.
--
-- MODE D'EMPLOI
-- 1. Mets NOM_DU_PNJ au nom de ton Model.
-- 2. Colle dans la barre de commandes en mode EDITION.
-- 3. Regarde le resultat. Ctrl+Z annule tout si ca ne va pas.
-- 4. Sauvegarde.

local NOM_DU_PNJ = "OldManIdle"

local model = workspace:FindFirstChild(NOM_DU_PNJ, true)
if not model or not model:IsA("Model") then
	warn(`[RedresserPnj] Model "{NOM_DU_PNJ}" introuvable dans le Workspace.`)
	return
end

local root = model:FindFirstChild("HumanoidRootPart")
if not root or not root:IsA("BasePart") then
	warn(`[RedresserPnj] "{NOM_DU_PNJ}" n'a pas de part nommee "HumanoidRootPart".`)
	return
end

-- ETAT AVANT, pour pouvoir comparer au lieu de croire.
local rx, ry, rz = root.CFrame:ToEulerAnglesYXZ()
print(
	`[RedresserPnj] HumanoidRootPart inclinee de {math.floor(math.deg(rx))} deg (avant/arriere) `
		.. `et {math.floor(math.deg(rz))} deg (roulis). Cap : {math.floor(math.deg(ry))} deg.`
)

local corriges = 0
for _, descendant in ipairs(model:GetDescendants()) do
	if descendant:IsA("Motor6D") and descendant.Part0 == root then
		local x, y, z = descendant.C0:ToEulerAnglesYXZ()
		if math.abs(x) > 0.001 or math.abs(z) > 0.001 then
			print(
				`[RedresserPnj] {descendant.Name} ({descendant.Part1 and descendant.Part1.Name}) : `
					.. `inclinaison {math.floor(math.deg(x))} / roulis {math.floor(math.deg(z))} -> remis a plat.`
			)
			-- On ne garde que le CAP (rotation autour de la verticale). La position reste intacte.
			descendant.C0 = CFrame.new(descendant.C0.Position) * CFrame.fromEulerAnglesYXZ(0, y, 0)
			corriges += 1
		end
	end
end

if corriges == 0 then
	-- Anormal ET actionnable : si rien n'etait de travers ici, l'inclinaison vient d'ailleurs. Les deux suspects
	-- suivants sont la HumanoidRootPart elle-meme (a redresser dans Studio) et l'ANIMATION (si elle cle le RootJoint,
	-- elle incline tout le corps a chaque lecture).
	warn(
		"[RedresserPnj] Aucun Motor6D de travers sous la HumanoidRootPart. "
			.. "Regarde alors l'orientation de la HumanoidRootPart elle-meme, puis l'animation (un RootJoint cle "
			.. "incline le corps a chaque lecture)."
	)
else
	print(`[RedresserPnj] {corriges} joint(s) redresse(s). Verifie a l'oeil, Ctrl+Z annule.`)
end
