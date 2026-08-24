-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO, avec le RIG SELECTIONNE (pas dans le jeu, pas dans src/).
--
-- Accroche N'IMPORTE QUEL objet a la main d'un rig, pour pouvoir l'ANIMER avec lui.
-- Le rateau, une brouette, un arrosoir : tout ce qu'on veut voir bouger dans l'editeur d'animation.
--
-- ===== QUEL SCRIPT UTILISER, ET QUAND =====
-- Il y en a DEUX, et prendre le mauvais coute une animation entiere a refaire :
--
--   * CE SCRIPT-CI : l'objet n'est PAS encore un outil du jeu (absent de ToolConfigs). La prise n'est calculee
--     par personne, donc le placement fait A LA MAIN est la source de verite. On le fige, point.
--
--   * AttacherOutilAuRig.lua : l'objet EST un outil du jeu, dont la prise est CALCULEE en jeu par
--     ToolService.applyGrip. Poser un tel outil a l'oeil donne des poses justes dans l'editeur et FAUSSES en
--     jeu -- et on cherche ensuite l'erreur dans l'animation alors qu'elle est dans la prise.
--
-- LE JOUR OU CET OBJET DEVIENT UN VRAI OUTIL : il faudra le declarer dans ToolConfigs, puis reprendre les
-- animations avec l'AUTRE script. Les poses faites ici ne seront plus valables. Autant le savoir avant.
--
-- ===== POURQUOI IL FAUT UN SCRIPT =====
-- Parenter un objet a un personnage ne cree AUCUN joint. Sans joint, l'editeur d'animation ne voit meme pas
-- l'objet : il n'a rien a animer. Un Tool Roblox y arrive parce que ROBLOX lui fabrique un Motor6D a
-- l'equipement ; un Model, lui, ne declenche rien.
--
-- ===== MODE D'EMPLOI =====
--   1. Place l'objet dans la main du rig, a l'oeil, comme tu veux qu'il le tienne.
--   2. Selectionne le RIG (le Model du personnage).
--   3. Colle ce script dans la barre de commandes.
--   4. Ouvre l'editeur d'animation : une piste au NOM DE LA PART soudee est apparue.
--
-- LE NOM DE LA PISTE EST CELUI DE LA PART, PAS CELUI DU JOINT. Une animation Roblox retrouve ce qu'elle doit
-- bouger par le nom de la PART1 du joint -- une anim R15 cle "UpperTorso" (une part), jamais "Waist" (le Motor6D
-- qui la tire). Le nom du joint ne sert qu'a le RETROUVER pour le remplacer. Deux versions du portage du seau ont
-- ete construites sur l'idee inverse : c'est le nom de la PART qui doit correspondre entre le rig et le jeu.
--
-- Relancer le script REFAIT le joint depuis la position actuelle : on corrige la prise et on rejoue.
--
-- NE MARCHE QUE SUR UN RIG EN PARTS (R15, R6). Sur un mesh SKINNE les membres sont des `Bone`, qui heritent
-- d'Attachment et pas de BasePart : un Motor6D ne peut pas s'y accrocher. Le script le detecte et le dit.

local Selection = game:GetService("Selection")

-- ===== A REGLER =====
local OBJECT_NAME = "Rateau" -- nom de l'objet a accrocher, tel qu'il apparait dans l'Explorer
local HAND_NAME = "RightHand" -- "LeftHand" pour l'autre main. "Right Arm" / "Left Arm" sur un rig R6.

local selected = Selection:Get()[1]
local rig = if selected and selected:IsA("Model") then selected else nil
if not rig then
	warn("[Objet] Selectionne le RIG (le Model du personnage) avant de lancer ce script.")
	return
end

local hand = rig:FindFirstChild(HAND_NAME, true)
if hand and hand:IsA("Bone") then
	warn(
		`[Objet] "{HAND_NAME}" est un BONE : {rig:GetFullName()} est un mesh SKINNE. Un Motor6D exige deux `
			.. "BasePart, ce script ne peut rien faire ici. Integre l'objet au mesh dans Blender et pese-le sur "
			.. "l'os de la main : il suivra l'animation tout seul."
	)
	return
end
if not (hand and hand:IsA("BasePart")) then
	warn(`[Objet] Part "{HAND_NAME}" introuvable sous {rig:GetFullName()}. Verifie le nom (R15 vs R6).`)
	return
end

-- L'objet peut trainer a la racine du Workspace ou etre deja range sous le rig : on le cherche aux deux endroits.
local object = rig:FindFirstChild(OBJECT_NAME, true) or workspace:FindFirstChild(OBJECT_NAME, true)
if not object then
	warn(`[Objet] "{OBJECT_NAME}" introuvable, ni sous le rig ni dans le Workspace.`)
	return
end

-- Un Model n'a pas de CFrame a souder : il faut UNE part. Sa PrimaryPart, ou la premiere venue.
local part: BasePart? = nil
if object:IsA("BasePart") then
	part = object
elseif object:IsA("Model") then
	part = object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart", true)
end
if not part then
	warn(`[Objet] "{OBJECT_NAME}" n'a aucune BasePart a souder (regler sa PrimaryPart si c'est un Model).`)
	return
end

-- Un joint precedent laisserait DEUX pistes du meme nom, et Roblox melangerait les deux.
local old = hand:FindFirstChild(OBJECT_NAME)
if old and old:IsA("Motor6D") then
	old:Destroy()
end

-- UNE PART ANCREE IGNORE SON MOTOR6D : l'animation jouerait sans que l'objet bouge, et sans la moindre erreur.
-- On desancre TOUT l'objet, pas seulement la part soudee : une seule part ancree suffit a bloquer l'ensemble.
local function unanchor(root: Instance)
	if root:IsA("BasePart") then
		root.Anchored = false
		root.CanCollide = false -- un objet tenu ne doit pas bousculer son porteur ni le decor
		root.Massless = true -- ni l'alourdir
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.Massless = true
		end
	end
end
unanchor(object)

-- On range l'objet SOUS le rig : l'editeur d'animation ne propose que ce qui appartient au personnage.
if object.Parent ~= rig then
	object.Parent = rig
end

local joint = Instance.new("Motor6D")
-- Sert UNIQUEMENT a retrouver ce joint pour le remplacer. La PISTE de l'editeur, elle, prend le nom de la PART.
joint.Name = OBJECT_NAME
joint.Part0 = hand
joint.Part1 = part
-- C0 = la position ACTUELLE de l'objet vue depuis la main. C'est ce qui fige le placement fait a l'oeil.
-- Rappel du calcul : Part1.CFrame = Part0.CFrame * C0 * C1:Inverse(), et C1 reste a l'identite ici.
joint.C0 = hand.CFrame:Inverse() * part.CFrame
joint.Parent = hand

print(`[Objet] Joint "{OBJECT_NAME}" cree : {hand:GetFullName()} -> {part:GetFullName()}`)
print("[Objet] Ouvre l'editeur d'animation sur le rig : la piste apparait sous ce nom.")
print("[Objet] Prise a corriger ? Deplace l'objet a la main et RELANCE ce script.")
