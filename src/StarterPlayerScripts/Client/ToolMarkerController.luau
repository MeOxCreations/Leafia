--!strict
-- LES PASTILLES DES OUTILS POSES SUR LE TERRAIN : seaux, tondeuses, echelles. Le joueur ne cherche plus ses outils.
--
-- UNE ICONE, PAS LE " ! ". Le point d'exclamation dit "va la, maintenant" (la porte, le grand-pere) ; une icone
-- dit "ton outil est ici". Deux messages differents, deux dessins differents.
--
-- QUAND : l'outil est AU SOL (personne ne le porte, pas range dans le camion) et le joueur est LOIN. De pres,
-- l'outil est sous ses yeux.
--
-- PAS TANT QUE LES ACTIONS SONT VERROUILLEES. Au debut du didacticiel, le joueur doit aller toquer chez le
-- grand-pere : des pastilles sur la tondeuse et le seau l'enverraient au mauvais endroit.
--
-- ET PAS PAR-DESSUS UN AUTRE MARQUEUR. Quand le didacticiel pose deja son " ! " sur la tondeuse, deux pastilles
-- sur le meme objet se liraient comme deux choses a faire.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ActionGate = require(ReplicatedStorage.Modules.UI.Core.ActionGate)
local BinUtils = require(ReplicatedStorage.Modules.Utils.BinUtils)
local LadderFoldUtils = require(ReplicatedStorage.Modules.Utils.LadderFoldUtils)
local MowConfigs = require(ReplicatedStorage.Modules.Configs.MowConfigs)
local ToolMarkerConfigs = require(ReplicatedStorage.Modules.Configs.ToolMarkerConfigs)
local TruckConfigs = require(ReplicatedStorage.Modules.Configs.TruckConfigs)
local WorldMarker = require(ReplicatedStorage.Modules.UI.Core.WorldMarker)

local ToolMarkerController = {}

type Shown = { frame: Frame, part: BasePart }

-- Le nom de la part de reference des trois outils (seau, tondeuse et echelle l'appellent pareil).
local ROOT_NAME = MowConfigs.ROOT_NAME

local player = Players.LocalPlayer

local tools: { [Model]: string } = {}
local shown: { [Model]: Shown } = {}
-- NOS marqueurs, a ignorer quand on demande si un objet est deja marque : sinon chaque pastille se cacherait
-- elle-meme a l'image suivante.
local own: { [Frame]: boolean } = {}

--- QUEL OUTIL EST-CE, ou nil. On demande a chaque outil sa propre regle d'identite -- elle sait deja exclure les
--- rigs d'animation et ce qui est range dans le camion.
local function kindOf(inst: Instance): string?
	if not inst:IsA("Model") then
		return nil
	end
	if BinUtils.isBin(inst) then
		return "Bin"
	end
	if LadderFoldUtils.isLadder(inst) then
		return "Ladder"
	end
	if inst.Name == MowConfigs.MODEL_NAME and not inst:FindFirstAncestor(TruckConfigs.MODEL_NAME) then
		return "Mower"
	end
	return nil
end

local function rootOf(model: Model): BasePart?
	local root = model.PrimaryPart or model:FindFirstChild(ROOT_NAME)
	if root and root:IsA("BasePart") then
		return root
	end
	return model:FindFirstChildWhichIsA("BasePart")
end

--- PORTE PAR UN JOUEUR. Les trois outils se portent soudes au personnage : leur assemblage a donc pour racine une
--- part du PERSONNAGE. Une seule question pour les trois, sans attribut propre a chaque outil.
local function carried(part: BasePart): boolean
	local assembly = part.AssemblyRootPart
	if not assembly or assembly == part then
		return false
	end
	local model = assembly:FindFirstAncestorOfClass("Model")
	return model ~= nil and Players:GetPlayerFromCharacter(model) ~= nil
end

local function clear(model: Model)
	local s = shown[model]
	if s then
		own[s.frame] = nil
		WorldMarker.remove(s.frame)
		shown[model] = nil
	end
end

function ToolMarkerController.init()
	-- ANORMAL ET ACTIONNABLE : une icone manquante donne un " ! ", qui dit autre chose. Dit une fois.
	local missing: { string } = {}
	for kind, icon in ToolMarkerConfigs.ICONS do
		if icon == "" then
			table.insert(missing, kind)
		end
	end
	if #missing > 0 then
		warn(
			`[ToolMarkerController] Pas d'icone pour : {table.concat(missing, ", ")}. Le " ! " s'affiche a la place `
				.. "(ToolMarkerConfigs.ICONS)."
		)
	end

	local nextScan, nextCheck = 0, 0
	local seen: { [Model]: boolean } = {}
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now >= nextScan then
			nextScan = now + ToolMarkerConfigs.RESCAN_INTERVAL
			table.clear(tools)
			for _, d in Workspace:GetDescendants() do
				-- Filtre bon marche d'abord : `IsA("Model")` ecarte des milliers de parts (l'herbe) avant tout le reste.
				if d:IsA("Model") then
					local kind = kindOf(d)
					if kind then
						tools[d] = kind
					end
				end
			end
		end
		if now < nextCheck then
			return
		end
		nextCheck = now + ToolMarkerConfigs.CHECK_INTERVAL

		local character = player.Character
		local me = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local from = if me and me:IsA("BasePart") then me.Position else nil
		table.clear(seen)
		if from and not ActionGate.isLocked() then
			for model, kind in tools do
				local part = rootOf(model)
				-- L'IDENTITE EST RETESTEE : un outil range dans le camion depuis le dernier balayage n'en est plus un.
				if part and model.Parent and kindOf(model) == kind and not carried(part) then
					local delta = part.Position - (from :: Vector3)
					local far = math.sqrt(delta.X * delta.X + delta.Z * delta.Z) > ToolMarkerConfigs.NEAR_DISTANCE
					if far and not WorldMarker.isMarked(model, own) then
						seen[model] = true
						local s = shown[model]
						if not s or s.part ~= part then
							clear(model)
							local icon = ToolMarkerConfigs.ICONS[kind] or ""
							local frame = WorldMarker.show(
								part,
								Vector3.new(0, ToolMarkerConfigs.UP[kind] or 3, 0),
								if icon ~= "" then icon else nil
							)
							own[frame] = true
							shown[model] = { frame = frame, part = part }
						end
					end
				end
			end
		end
		for model in shown do
			if not seen[model] then
				clear(model)
			end
		end
	end)

	print("[ToolMarkerController] Pret : une pastille sur les outils au sol, quand on est loin.")
end

return ToolMarkerController
