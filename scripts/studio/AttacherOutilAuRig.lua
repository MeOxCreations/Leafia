-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO, avec le rig d'animation SELECTIONNE.
--
-- POURQUOI CE SCRIPT PLUTOT QUE DE PLACER L'OUTIL A LA MAIN.
-- En jeu, la prise n'est pas un placement a l'oeil : elle est CALCULEE par ToolService.applyGrip a partir de
-- deux Attachments et d'un offset. Poser l'outil a peu pres dans l'editeur d'animation donnerait des poses
-- justes a l'ecran et fausses en jeu, et on chercherait l'erreur dans l'animation alors qu'elle serait dans
-- le placement.
-- Ce script REPRODUIT le calcul du jeu, a l'identique.
--
-- LA PRISE CHANGE SELON CE QU'ON ANIME. C'est le piege principal, et il y en a TROIS, pas deux :
--   "port"       -> main droite, outil eteint     (IdleAnimation)
--   "demarrage"  -> main gauche, tirage de corde  (PrepareToLaunch, TryLaunch)
--   "coupe"      -> main gauche, moteur lance     (ReadyToCut, UpDown)
--
-- "demarrage" et "coupe" sont la MEME main mais PAS le meme angle : tirer une corde et tailler une haie ne
-- sont pas le meme geste. Animer une pose de coupe avec la prise de demarrage donne un outil qui pointe vers
-- le ciel en jeu, et on croit que c'est l'animation qui est fausse alors que c'est la prise.
--
-- SI CES VALEURS CHANGENT DANS ToolConfigs, LES CHANGER ICI AUSSI. C'est la limite de l'exercice : la barre
-- de commandes ne peut pas require un module du jeu.

local Selection = game:GetService("Selection")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===== A REGLER : quelle prise veut-on animer ? =====
local PRISE = "coupe" -- "coupe" | "demarrage" | "port"

-- ===== Copie de ToolConfigs.HedgeTrimmer =====
local TOOL_PATH = { "Assets", "Tools", "HedgeTrimmer" }
local HANDLE_NAME = "Handle"
local GRIP_NAME = "ToolGrip"

local GRIPS = {
	port = {
		handName = "RightHand",
		-- applyGrip choisit l'Attachment de la main d'apres le cote.
		handAttachment = "RightGripAttachment",
		-- gripAttachment
		toolAttachment = "GripLeft",
		-- gripOffset. En DEGRES, comme dans ToolConfigs.
		offset = CFrame.Angles(math.rad(100), math.rad(0), math.rad(0)),
	},
	demarrage = {
		handName = "LeftHand",
		handAttachment = "LeftGripAttachment",
		-- offHandAttachment
		toolAttachment = "GripStart",
		-- offHandGripOffset
		offset = CFrame.Angles(math.rad(-50), math.rad(162), math.rad(80)),
	},
	coupe = {
		handName = "LeftHand",
		handAttachment = "LeftGripAttachment",
		toolAttachment = "GripStart",
		-- cutGripOffset. MEME main que le demarrage, autre angle : c'est le seul ecart entre les deux.
		offset = CFrame.Angles(math.rad(-50), math.rad(162), math.rad(80)),
	},
}

local grip = GRIPS[PRISE]
if not grip then
	warn(`[Rig] PRISE doit valoir "coupe", "demarrage" ou "port", pas "{PRISE}".`)
	return
end

local rig = Selection:Get()[1]
if not (rig and rig:IsA("Model")) then
	warn("[Rig] Selectionne d'abord le MODEL du rig, puis relance.")
	return
end

local hand = rig:FindFirstChild(grip.handName, true)
if not (hand and hand:IsA("BasePart")) then
	warn(`[Rig] "{grip.handName}" introuvable dans {rig.Name}. Ce rig est-il bien un R15 ?`)
	return
end

local source = ReplicatedStorage
for _, name in ipairs(TOOL_PATH) do
	source = source and source:FindFirstChild(name)
end
if not (source and source:IsA("Model")) then
	warn(`[Rig] Outil introuvable : ReplicatedStorage.{table.concat(TOOL_PATH, ".")}`)
	return
end

-- Relance possible sans nettoyer a la main. On cherche la prise dans LES DEUX mains : changer de MAIN sans
-- enlever l'ancienne laisserait deux joints, et l'outil serait tire des deux cotes.
for _, side in pairs(GRIPS) do
	local otherHand = rig:FindFirstChild(side.handName, true)
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
	warn(`[Rig] "{HANDLE_NAME}" introuvable dans l'outil.`)
	tool:Destroy()
	return
end
tool.PrimaryPart = handle

-- ANCRE = le Motor6D est ignore et l'outil reste plante dans le decor. Il faut TOUT desancrer, y compris les
-- lames et le lanceur, sinon seule la poignee suivra la main.
for _, d in ipairs(tool:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Anchored = false
		-- Sans ca l'outil pousse le personnage pendant l'animation et le rig part de travers.
		d.CanCollide = false
	end
end

local handAttachment = hand:FindFirstChild(grip.handAttachment)
local toolAttachment = handle:FindFirstChild(grip.toolAttachment)
if not (handAttachment and handAttachment:IsA("Attachment")) then
	warn(`[Rig] Attachment "{grip.handAttachment}" absente de {grip.handName}.`)
end
if not (toolAttachment and toolAttachment:IsA("Attachment")) then
	warn(`[Rig] Attachment "{grip.toolAttachment}" absente du {HANDLE_NAME}.`)
end

local c0 = if handAttachment and handAttachment:IsA("Attachment") then handAttachment.CFrame else CFrame.identity
local c1 = if toolAttachment and toolAttachment:IsA("Attachment") then toolAttachment.CFrame else CFrame.identity

-- MEME formule que ToolService.applyGrip :
--   Handle.CFrame = Hand.CFrame * C0 * C1:Inverse()
local motor = Instance.new("Motor6D")
motor.Name = GRIP_NAME
motor.Part0 = hand
motor.Part1 = handle
motor.C0 = c0 * grip.offset
motor.C1 = c1
motor.Parent = hand

tool.Parent = rig

Selection:Set({ rig })
print(`[Rig] {tool.Name} accroche a {grip.handName} (prise "{PRISE}"). Ferme et rouvre l'editeur d'animation.`)
