--!strict
-- Joue un son PONCTUEL clone depuis SoundService, a un endroit donne (spatial si un host est fourni).
--
-- POURQUOI CLONER plutot que rejouer l'instance. Rejouer la meme instance coupe le son en cours a chaque appel :
-- deux pas rapproches ne s'entendraient qu'une fois. Un clone par declenchement se superpose proprement. Le clone
-- garde les proprietes reglees en Studio (volume, PlaybackSpeed) : la source de verite reste le Sound de l'editeur.

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local SoundUtils = {}

-- Retrouve un Sound par chemin sous SoundService (ex : { "Sounds", "Engins", "Ladder", "LadderTakeSound" }).
local function resolve(path: { string }): Sound?
	local node: Instance? = SoundService
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return if node and node:IsA("Sound") then node else nil
end

-- Clone le son du chemin donne et le joue. host = la part ou le poser (son spatial) ; nil = son global (2D).
-- Le clone se nettoie tout seul (Debris), garde-fou si Ended ne tire pas (ID absent). Rend le clone, ou nil si
-- le son est introuvable.
function SoundUtils.play(path: { string }, host: BasePart?): Sound?
	local template = resolve(path)
	if not template then
		warn(`[SoundUtils] Son introuvable : SoundService.{table.concat(path, ".")}`)
		return nil
	end
	local sound = template:Clone()
	sound.Parent = host or SoundService
	sound:Play()
	Debris:AddItem(sound, 5)
	return sound
end

-- Joue un son par ASSET ID (quand on n'a PAS de Sound pre-regle dans SoundService). Cree un Sound transitoire, le joue,
-- et le nettoie tout seul. host = part ou le poser (son spatial) ; nil = global (2D).
function SoundUtils.playId(soundId: string, volume: number?, host: BasePart?): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.5
	sound.Parent = host or SoundService
	sound:Play()
	Debris:AddItem(sound, 5)
	return sound
end

return SoundUtils
