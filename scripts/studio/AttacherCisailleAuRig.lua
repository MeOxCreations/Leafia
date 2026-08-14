-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO, avec le rig d'animation SELECTIONNE.
--
-- POURQUOI CE SCRIPT PLUTOT QUE DE POSER LA CISAILLE A LA MAIN.
-- En jeu, la prise n'est pas un placement a l'oeil : elle est CALCULEE par ToolService.applyGrip a partir de
-- deux Attachments et d'un offset. Poser la cisaille a peu pres dans l'editeur d'animation donnerait des poses
-- justes a l'ecran et FAUSSES en jeu, et on chercherait l'erreur dans l'animation alors qu'elle serait dans le
-- placement. Ce script REPRODUIT le calcul du jeu, a l'identique.
--
-- PIEGE CONNU : parenter un Model a la main ne cree AUCUN joint. Sans Motor6D, l'editeur d'animation ne voit
-- meme pas l'outil, et une part Anchored ignore son Motor6D (l'outil resterait plante dans le decor).
--
-- La cisaille est un outil SIMPLE : une seule prise, main droite. (Le taille-haie, lui, en a trois -> voir
-- AttacherOutilAuRig.lua.)
--
-- SI CES VALEURS CHANGENT DANS ToolConfigs.Shear, LES CHANGER ICI AUSSI. C'est la limite de l'exercice : la
-- barre de commandes ne peut pas require un module du jeu.

local Selection = game:GetService("Selection")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===== Copie de ToolConfigs.Shear (outil simple) =====
local TOOL_PATH = { "Assets", "Tools", "Shear" }
local HANDLE_NAME = "Handle" -- handleName
local GRIP_NAME = "ToolGrip" -- meme nom que le Motor6D cree par ToolService

local HAND_NAME = "RightHand" -- handPart
local HAND_ATTACHMENT = "RightGripAttachment" -- attachment de prise de la main droite (R15)
local TOOL_ATTACHMENT = "Grip" -- gripAttachment (dans le Handle)
-- gripOffset. En DEGRES via math.rad, comme dans ToolConfigs. Actuellement identite (a regler si l'outil pointe
-- de travers dans la main). Si tu la changes ici, change AUSSI ToolConfigs.Shear.gripOffset, sinon l'angle
-- anime ne collera pas a l'angle en jeu.
local OFFSET = CFrame.Angles(math.rad(0), math.rad(0), math.rad(0))

local rig = Selection:Get()[1]
if not (rig and rig:IsA("Model")) then
	warn("[Rig] Selectionne d'abord le MODEL du rig, puis relance.")
	return
end

local hand = rig:FindFirstChild(HAND_NAME, true)
if not (hand and hand:IsA("BasePart")) then
	warn(`[Rig] "{HAND_NAME}" introuvable dans {rig.Name}. Ce rig est-il bien un R15 ?`)
	return
end

local source = ReplicatedStorage
for _, name in ipairs(TOOL_PATH) do
	source = source and source:FindFirstChild(name)
end
if not (source and source:IsA("Model")) then
	warn(`[Rig] Cisaille introuvable : ReplicatedStorage.{table.concat(TOOL_PATH, ".")}`)
	return
end

-- Relance possible sans nettoyer a la main : on enleve l'ancien joint et l'ancien clone avant de recommencer.
-- La cisaille est main droite, mais on cherche le joint dans les deux mains au cas ou un autre script l'aurait
-- pose ailleurs : deux joints tireraient l'outil des deux cotes.
for _, handName in ipairs({ "RightHand", "LeftHand" }) do
	local otherHand = rig:FindFirstChild(handName, true)
	local previous = otherHand and otherHand:FindFirstChild(GRIP_NAME)
	if previous then
		previous:Destroy()
	end
end
local previousTool = rig:FindFirstChild(source.Name)
if previousTool then
	previousTool:Destroy()
end

local tool = source:Clone()

local handle = tool:FindFirstChild(HANDLE_NAME, true)
if not (handle and handle:IsA("BasePart")) then
	warn(`[Rig] "{HANDLE_NAME}" introuvable dans la cisaille. Le Handle doit exister (c'est la part tenue).`)
	tool:Destroy()
	return
end
tool.PrimaryPart = handle

-- ANCRE = le Motor6D est ignore et l'outil reste plante dans le decor. Il faut TOUT desancrer (lame comprise),
-- sinon seul le Handle suivrait la main. CanCollide false sinon l'outil pousse le rig pendant l'animation.
for _, d in ipairs(tool:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Anchored = false
		d.CanCollide = false
	end
end

local handAttachment = hand:FindFirstChild(HAND_ATTACHMENT)
local toolAttachment = handle:FindFirstChild(TOOL_ATTACHMENT)
if not (handAttachment and handAttachment:IsA("Attachment")) then
	warn(`[Rig] Attachment "{HAND_ATTACHMENT}" absente de {HAND_NAME}. La prise partira de travers.`)
end
if not (toolAttachment and toolAttachment:IsA("Attachment")) then
	warn(`[Rig] Attachment "{TOOL_ATTACHMENT}" absente du {HANDLE_NAME}. Cree-la : c'est le point de prise.`)
end

local c0 = if handAttachment and handAttachment:IsA("Attachment") then handAttachment.CFrame else CFrame.identity
local c1 = if toolAttachment and toolAttachment:IsA("Attachment") then toolAttachment.CFrame else CFrame.identity

-- MEME formule que ToolService.applyGrip :
--   Handle.CFrame = Hand.CFrame * C0 * C1:Inverse()
local motor = Instance.new("Motor6D")
motor.Name = GRIP_NAME
motor.Part0 = hand
motor.Part1 = handle
motor.C0 = c0 * OFFSET
motor.C1 = c1
motor.Parent = hand

tool.Parent = rig

Selection:Set({ rig })
print(`[Rig] {tool.Name} accroche a {HAND_NAME}. Ferme et rouvre l'editeur d'animation pour qu'il voie le joint.`)
