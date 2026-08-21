-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO (pas dans le jeu, pas dans src/).
--
-- Rend la CANNE animable avec Papi : elle apparaitra comme une PISTE dans l'editeur d'animation.
--
-- POURQUOI IL FAUT CE SCRIPT.
-- Parenter un objet a un personnage ne cree AUCUN joint. Sans joint, l'editeur d'animation ne voit meme pas
-- l'objet : il n'a rien a animer. Un Tool Roblox y arrive parce que ROBLOX lui fabrique un Motor6D a
-- l'equipement ; un Model, lui, ne declenche rien. Il faut donc creer le Motor6D soi-meme.
--
-- POURQUOI ON PLACE LA CANNE A LA MAIN AVANT (contrairement au taille-haie).
-- La prise du taille-haie est CALCULEE en jeu par ToolService : la poser a l'oeil donnerait des poses justes
-- dans l'editeur et fausses en jeu. La canne, elle, n'est calculee par personne -- c'est du decor sur un PNJ.
-- Le placement fait a la main EST donc la source de verite, et ce script se contente de le figer dans le joint.
--
-- MODE D'EMPLOI
--   1. Place la canne dans la main de Papi, a l'oeil, comme tu veux qu'il la tienne.
--   2. Colle ce script dans la barre de commandes.
--   3. Ouvre l'editeur d'animation sur Papi : une piste "Canne" est apparue.
--
-- Relancer le script REFAIT le joint depuis la position actuelle : on peut donc corriger la prise et rejouer.
--
-- ATTENTION : Rojo ne synchronise PAS le Workspace. Ce joint doit etre refait dans CHAQUE place (Leafia ET le
-- tuto), sinon Papi tiendra sa canne dans l'une et pas dans l'autre.

local PAPI_NAME = "Papi"
local CANE_NAME = "Canne"
local HAND_NAME = "RightHand" -- main qui tient la canne. "LeftHand" si tu preferes l'autre.
local JOINT_NAME = "Canne" -- NOM DE LA PISTE dans l'editeur d'animation. C'est ce nom que tu verras.

local papi = workspace:FindFirstChild(PAPI_NAME, true)
if not (papi and papi:IsA("Model")) then
	warn(`[Canne] Modele "{PAPI_NAME}" introuvable dans le Workspace.`)
	return
end

local hand = papi:FindFirstChild(HAND_NAME, true)
if not (hand and hand:IsA("BasePart")) then
	warn(`[Canne] Part "{HAND_NAME}" introuvable sous {papi:GetFullName()}.`)
	return
end

-- La canne peut etre posee a la racine du Workspace ou deja rangee sous Papi : on la cherche aux deux endroits.
local cane: Instance? = papi:FindFirstChild(CANE_NAME, true) or workspace:FindFirstChild(CANE_NAME, true)
if not cane then
	warn(`[Canne] "{CANE_NAME}" introuvable, ni sous Papi ni dans le Workspace.`)
	return
end

-- Un Model n'a pas de CFrame a souder : il faut UNE part. On prend sa PrimaryPart, ou la premiere venue.
local canePart: BasePart? = nil
if cane:IsA("BasePart") then
	canePart = cane
elseif cane:IsA("Model") then
	canePart = cane.PrimaryPart or cane:FindFirstChildWhichIsA("BasePart", true)
end
if not canePart then
	warn(`[Canne] "{CANE_NAME}" n'a aucune BasePart a souder (regler sa PrimaryPart si c'est un Model).`)
	return
end

-- Un joint precedent laisserait DEUX pistes du meme nom, et Roblox melangerait les deux.
local old = hand:FindFirstChild(JOINT_NAME)
if old and old:IsA("Motor6D") then
	old:Destroy()
end

-- UNE PART ANCREE IGNORE SON MOTOR6D : l'animation jouerait sans que la canne bouge, et sans la moindre erreur.
-- On desancre TOUTE la canne, pas seulement la part soudee : une seule part ancree suffit a bloquer l'ensemble.
local function unanchor(root: Instance)
	if root:IsA("BasePart") then
		root.Anchored = false
		root.CanCollide = false -- une canne ne doit pas bousculer Papi ni le decor
		root.Massless = true -- ni alourdir son personnage
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.Massless = true
		end
	end
end
unanchor(cane)

-- On range la canne SOUS Papi : l'editeur d'animation ne propose que ce qui appartient au rig.
if cane.Parent ~= papi then
	cane.Parent = papi
end

local joint = Instance.new("Motor6D")
joint.Name = JOINT_NAME
joint.Part0 = hand
joint.Part1 = canePart
-- C0 = la position ACTUELLE de la canne vue depuis la main. C'est ce qui fige le placement fait a l'oeil.
-- Rappel du calcul : Part1.CFrame = Part0.CFrame * C0 * C1:Inverse(), et C1 reste a l'identite ici.
joint.C0 = hand.CFrame:Inverse() * canePart.CFrame
joint.Parent = hand

print(`[Canne] Joint "{JOINT_NAME}" cree : {hand:GetFullName()} -> {canePart:GetFullName()}`)
print("[Canne] Ouvre l'editeur d'animation sur Papi : la piste apparait sous ce nom.")
print("[Canne] Prise a corriger ? Deplace la canne a la main et RELANCE ce script.")
