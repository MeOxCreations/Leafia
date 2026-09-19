--!strict
-- POSE LES SONS DE SoundConfigs DANS SoundService, au chemin de leur cle, au demarrage.
--
-- COTE SERVEUR : ce qui est cree dans SoundService par le serveur se replique a tous les clients. Une seule pose,
-- et chaque joueur -- y compris celui qui arrive en retard -- trouve les memes sons.
--
-- LE RESTE DU JEU N'A RIEN A SAVOIR : il cherche toujours ses sons par leur chemin sous SoundService, comme avant.
-- Ce service ne fait que s'assurer qu'ils y sont, avec les valeurs de la config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SoundConfigs = require(ReplicatedStorage.Modules.Configs.SoundConfigs)

local SoundRegistryService = {}

--- Le dossier `name` sous `parent`, cree s'il manque.
local function folderIn(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function SoundRegistryService.init()
	local created, updated = 0, 0
	for key, entry in pairs(SoundConfigs) do
		local parts = string.split(key, "/")
		local name = table.remove(parts)
		if not name or name == "" or entry.id == "" then
			-- ACTIONNABLE : une ligne de config mal ecrite, nommee pour qu'on la retrouve.
			warn(`[SoundRegistry] Entree "{key}" sans nom ou sans id : ignoree.`)
			continue
		end
		local parent: Instance = SoundService
		for _, folderName in parts do
			parent = folderIn(parent, folderName)
		end
		local found = parent:FindFirstChild(name)
		local sound: Sound
		if found and found:IsA("Sound") then
			sound = found
			updated += 1
		else
			sound = Instance.new("Sound")
			sound.Name = name
			created += 1
		end
		sound.SoundId = entry.id
		-- SEULEMENT CE QUE LA CONFIG DIT. Un volume regle a l'oreille dans Studio n'est pas ecrase par un defaut :
		-- la config n'impose une valeur que si elle en donne une.
		local volume, speed, looped = entry.volume, entry.speed, entry.looped
		if volume then
			sound.Volume = volume
		end
		if speed then
			sound.PlaybackSpeed = speed
		end
		if looped ~= nil then
			sound.Looped = looped
		end
		sound.Parent = parent
		-- UNE AMBIANCE JOUE TOUTE SEULE : dans Studio c'etait la case Playing. Pose par le serveur, elle joue chez
		-- tous les joueurs.
		if entry.playing then
			sound.Playing = true
		end
	end
	print(`[SoundRegistry] {created} son(s) pose(s), {updated} son(s) de Studio mis a jour depuis la config.`)
end

return SoundRegistryService
