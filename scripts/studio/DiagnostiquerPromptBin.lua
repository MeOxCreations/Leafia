-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO. Rien a selectionner.
--
-- "Je m'approche du seau et aucun prompt n'apparait." Cette phrase couvre au moins cinq causes differentes,
-- qui se corrigent chacune autrement. Ce script les separe au lieu de les deviner :
--   1. le CODE n'est pas arrive dans Studio (Rojo pas connecte, ou pas accepte)
--   2. aucun seau PRENABLE n'existe (le seul model est sur le rig d'animation, donc hors du monde jouable)
--   3. le seau est marque comme deja PORTE (attribut reste colle apres un test interrompu)
--   4. le seau n'a pas de reference de position (ni PrimaryPart ni RootPart) -> il est ignore
--   5. le joueur porte deja autre chose (echelle), ce qui coupe le prompt du seau expres
--
-- Marche en mode Edit ET en Play. Certaines lignes ne peuvent se verifier qu'en Play : elles le disent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MODEL_PREFIX = "Bin"
local CARRIED_ATTRIBUTE = "LeafiaBinCarriedBy"
local DETECT_RADIUS = 8

local function ok(text)
	print(`[DiagBin] OK   {text}`)
end
local function ko(text)
	warn(`[DiagBin] KO   {text}`)
end

print("[DiagBin] ===== 1. LE CODE EST-IL ARRIVE DANS STUDIO ? =====")

local function findPath(root, path)
	local node = root
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local configs = findPath(ReplicatedStorage, { "Modules", "Configs", "BinConfigs" })
if configs then
	ok("ReplicatedStorage.Modules.Configs.BinConfigs")
else
	ko("BinConfigs ABSENT -> le code n'est pas syncé. Verifie que Rojo est connecte et que tu as ACCEPTE le diff.")
end

local controller = findPath(StarterPlayer, { "StarterPlayerScripts", "Client", "BinCarryController" })
if controller then
	ok("StarterPlayerScripts.Client.BinCarryController")
else
	ko("BinCarryController ABSENT -> le code n'est pas syncé (meme cause que ci-dessus).")
end

local service = findPath(game:GetService("ServerScriptService"), { "Server", "BinCarryService" })
if service then
	ok("ServerScriptService.Server.BinCarryService")
else
	ko("BinCarryService ABSENT -> le code n'est pas syncé.")
end

local remote = findPath(ReplicatedStorage, { "Remotes", "Bin", "SetBinCarry" })
if remote then
	ok("Remote Bin/SetBinCarry")
elseif RunService:IsRunning() then
	ko("Remote Bin/SetBinCarry ABSENT en cours de partie -> RemoteSetup ne l'a pas cree.")
else
	print("[DiagBin] --   Remote absent : NORMAL en mode Edit, il n'est cree qu'au demarrage du serveur.")
end

print("[DiagBin] ===== 2. Y A-T-IL UN SEAU PRENABLE ? =====")

-- Un seau monte sur un RIG n'est pas un seau du monde : il sert a animer. Le jeu le verrait pourtant comme
-- ramassable (la detection est par prefixe), d'ou la distinction explicite ici.
local function rigOf(model)
	local node = model:FindFirstAncestorWhichIsA("Model")
	while node do
		if node:FindFirstChildOfClass("Humanoid") then
			return node
		end
		node = node:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

local takeable, onRig = {}, {}
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("Model") and d.Name:sub(1, #MODEL_PREFIX) == MODEL_PREFIX then
		if rigOf(d) then
			table.insert(onRig, d)
		else
			table.insert(takeable, d)
		end
	end
end

for _, model in ipairs(onRig) do
	local rig = rigOf(model)
	print(`[DiagBin] --   {model:GetFullName()} est sur le rig "{rig.Name}" (sert a animer, pas au jeu)`)
end

if #takeable == 0 then
	ko("AUCUN seau dans le monde jouable.")
	if #onRig > 0 then
		warn("[DiagBin]      Tes seuls seaux sont sur un rig d'animation. C'est la cause la plus probable :")
		warn("[DiagBin]      copie l'un d'eux DANS le Workspace (a la racine), ancre sa PrimaryPart, et reteste.")
	else
		warn("[DiagBin]      Pose un Model dont le nom commence par \"Bin\" dans le Workspace.")
	end
else
	ok(`{#takeable} seau(x) prenable(s) dans le monde`)
end

print("[DiagBin] ===== 3. CHAQUE SEAU EST-IL VALIDE ? =====")

for _, model in ipairs(takeable) do
	print(`[DiagBin] --- {model:GetFullName()} ---`)

	local root = model.PrimaryPart or model:FindFirstChild("RootPart")
	if root and root:IsA("BasePart") then
		ok(`reference de position : "{root.Name}"`)
	else
		ko("ni PrimaryPart ni RootPart -> ce seau est IGNORE par la detection")
	end

	local carrier = model:GetAttribute(CARRIED_ATTRIBUTE)
	if carrier then
		ko(`marque comme PORTE par l'UserId {carrier} -> aucun prompt tant que c'est la`)
		warn(`[DiagBin]      Reste d'un test interrompu. Pour le liberer, dans la barre de commandes :`)
		warn(`[DiagBin]      {model:GetFullName()}:SetAttribute("{CARRIED_ATTRIBUTE}", nil)`)
	else
		ok("libre (aucun porteur)")
	end

	local anchored = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Anchored then
			anchored += 1
		end
	end
	if anchored > 0 then
		ok(`{anchored} part(s) ancree(s)`)
	else
		ko("aucune part ancree -> le seau tombe hors du monde des le lancement, donc plus rien a cote de quoi passer")
	end

	-- DISTANCE REELLE : c'est le seul chiffre qui dit si on est assez pres. Se lit uniquement en Play.
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp and root and root:IsA("BasePart") then
		local flat = (root.Position - hrp.Position) * Vector3.new(1, 0, 1)
		local dist = flat.Magnitude
		if dist <= DETECT_RADIUS then
			ok(`distance joueur : {string.format("%.1f", dist)} studs (rayon {DETECT_RADIUS}) -> DANS la zone`)
		else
			ko(`distance joueur : {string.format("%.1f", dist)} studs (rayon {DETECT_RADIUS}) -> trop loin`)
		end
	end
end

print("[DiagBin] ===== 4. LE JOUEUR PORTE-T-IL DEJA AUTRE CHOSE ? =====")

local character = Players.LocalPlayer and Players.LocalPlayer.Character
if not character then
	print("[DiagBin] --   Pas de personnage : lance le jeu (Play) pour verifier ce point.")
else
	local blocking = { "LeafiaCarryingLadder", "LeafiaCarryingBin" }
	local busy = false
	for _, attribute in ipairs(blocking) do
		if character:GetAttribute(attribute) then
			ko(`{attribute} est pose -> le prompt du seau est coupe expres (on ne porte qu'une chose a la fois)`)
			busy = true
		end
	end
	if not busy then
		ok("le joueur ne porte rien d'autre")
	end
end

print("[DiagBin] ==========")
