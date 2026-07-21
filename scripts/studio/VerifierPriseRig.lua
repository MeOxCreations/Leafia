-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO, avec le rig d'animation SELECTIONNE.
--
-- Ne modifie RIEN. Il repond a une seule question : pourquoi l'outil ne suit pas la main ?
--
-- Quatre causes possibles, et une seule facon de savoir laquelle : demander a Studio plutot que supposer.
-- Un outil qui flotte ressemble a un probleme d'orientation, alors que c'est presque toujours un joint absent
-- ou une part ancree.

local Selection = game:GetService("Selection")

local HAND_NAME = "RightHand"
local HANDLE_NAME = "Handle"
local HAND_ATTACHMENT = "RightGripAttachment"
local GRIP_ATTACHMENT = "GripLeft"
local TOOL_NAME = "HedgeTrimmer"
local GRIP_NAME = "ToolGrip"

local rig = Selection:Get()[1]
if not (rig and rig:IsA("Model")) then
	warn("[Verif] Selectionne d'abord le MODEL du rig, puis relance.")
	return
end

local report = {}
local function line(ok: boolean, text: string)
	table.insert(report, `  {if ok then "OK  " else "NON "} {text}`)
	return ok
end

local hand = rig:FindFirstChild(HAND_NAME, true)
local handOk = line(hand ~= nil, `{HAND_NAME} present dans le rig`)

local tool = rig:FindFirstChild(TOOL_NAME)
line(tool ~= nil, `{TOOL_NAME} enfant du rig`)

local handle = tool and tool:FindFirstChild(HANDLE_NAME, true)
line(handle ~= nil, `{HANDLE_NAME} present dans l'outil`)

-- LA cause numero un. Sans ce joint, l'editeur d'animation ne voit meme pas l'outil.
local motor = hand and hand:FindFirstChild(GRIP_NAME)
local motorOk = line(motor ~= nil and motor:IsA("Motor6D"), `Motor6D "{GRIP_NAME}" dans {HAND_NAME}`)

if motor and motor:IsA("Motor6D") then
	line(motor.Part0 == hand, `{GRIP_NAME}.Part0 = {HAND_NAME}`)
	line(motor.Part1 == handle, `{GRIP_NAME}.Part1 = {HANDLE_NAME}`)
end

-- Cause numero deux. Une part ancree ignore son Motor6D : elle reste plantee dans le decor.
local anchored = {}
if tool then
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") and d.Anchored then
			table.insert(anchored, d.Name)
		end
	end
end
line(#anchored == 0, `aucune part ancree{if #anchored > 0 then ` (ancrees : {table.concat(anchored, ", ")})` else ""}`)

-- Cause numero trois : sans Attachment, la prise se calcule sur identity et l'outil se colle a l'origine.
line(hand ~= nil and hand:FindFirstChild(HAND_ATTACHMENT) ~= nil, `Attachment "{HAND_ATTACHMENT}" dans {HAND_NAME}`)
line(handle ~= nil and handle:FindFirstChild(GRIP_ATTACHMENT) ~= nil, `Attachment "{GRIP_ATTACHMENT}" dans {HANDLE_NAME}`)

print(`[Verif] {rig.Name} :\n` .. table.concat(report, "\n"))

if not motorOk and handOk then
	print(`[Verif] Cause la plus probable : le Motor6D manque. Lance AttacherOutilAuRig.lua.`)
end
