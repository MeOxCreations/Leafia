--!strict
-- Declaration CENTRALE des remotes. Un seul endroit ou ajouter un remote, range par feature.
-- Le serveur appelle RemoteSetup.init() au boot (cree les instances). Tout le monde lit via getRemote().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = {}
local createdRemotes: { [string]: RemoteEvent | RemoteFunction } = {}

local E, F = "Event", "Function"

-- Format : { nom, E ou F, dossier }
-- Vide au demarrage : on n'ajoute un remote QUE quand une feature en a reellement besoin. Une liste de
-- remotes "au cas ou" finit toujours par contenir des morts qu'on n'ose plus supprimer.
local REMOTES: { { any } } = {
	-- [ TOOL ] --
	-- Le client demande, il n'ordonne pas : il n'envoie AUCUN argument. Le serveur sait deja ce que le joueur
	-- tient, donc il n'y a rien a valider et rien a falsifier.
	{ "ToggleTool", E, "Tool" },
	-- Clic gauche. Aucun argument : le serveur connait deja l'etat de l'outil, donc il n'y a rien a valider et
	-- rien a falsifier.
	{ "ActivateTool", E, "Tool" },
}

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	-- On verifie le TYPE, pas juste la presence : si un jour un objet non-Folder porte ce nom, un cast
	-- silencieux donnerait des erreurs incomprehensibles plus loin.
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function RemoteSetup.init()
	local remotesFolder = getOrCreateFolder(ReplicatedStorage, "Remotes")

	for _, r in ipairs(REMOTES) do
		local name = r[1] :: string
		local rType = r[2] :: string
		local folder = r[3] :: string?

		local parent = folder and getOrCreateFolder(remotesFolder, folder) or remotesFolder

		if not parent:FindFirstChild(name) then
			local remote = Instance.new(rType == F and "RemoteFunction" or "RemoteEvent")
			remote.Name = name
			remote.Parent = parent
		end

		local key = folder and (folder .. "/" .. name) or name
		createdRemotes[key] = parent:FindFirstChild(name) :: RemoteEvent | RemoteFunction
	end
end

function RemoteSetup.getRemote(name: string, folder: string?): (RemoteEvent | RemoteFunction)?
	local key = folder and (folder .. "/" .. name) or name
	if createdRemotes[key] then
		return createdRemotes[key]
	end

	-- Fallback pour le CLIENT : il n'appelle jamais init(), donc son cache est vide. WaitForChild avec
	-- timeout, jamais infini : un remote absent doit renvoyer nil, pas geler le script pour la session.
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		return nil
	end

	if folder then
		local subFolder = remotesFolder:WaitForChild(folder, 10)
		if not subFolder then
			return nil
		end
		return subFolder:WaitForChild(name, 10) :: RemoteEvent | RemoteFunction
	end

	return remotesFolder:WaitForChild(name, 10) :: RemoteEvent | RemoteFunction
end

function RemoteSetup.getFolder(): Folder?
	return ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
end

return RemoteSetup
