--!strict
-- Joue un son PONCTUEL clone depuis SoundService, a un endroit donne (spatial si un host est fourni).
--
-- POURQUOI CLONER plutot que rejouer l'instance. Rejouer la meme instance coupe le son en cours a chaque appel :
-- deux pas rapproches ne s'entendraient qu'une fois. Un clone par declenchement se superpose proprement. Le clone
-- garde les proprietes reglees en Studio (volume, PlaybackSpeed) : la source de verite reste le Sound de l'editeur.

local SoundService = game:GetService("SoundService")

local SoundUtils = {}

-- COMBIEN DE TEMPS UN CLONE ORPHELIN SURVIT, en secondes.
--
-- Le nettoyage normal se fait sur `Ended` : le clone meurt quand le son est FINI, donc il dure exactement ce
-- qu'il doit durer. Ce delai n'est qu'un FILET, pour le cas ou `Ended` ne tire jamais -- id absent, chargement
-- rate, son mis en boucle par erreur. Sans lui, un clone par declenchement s'accumulerait pour toujours.
--
-- IL EST LARGE EXPRES, et c'est la lecon qui a coute ici : c'etait un `Debris:AddItem(sound, 5)`, donc TOUT son
-- de plus de cinq secondes se coupait EN PLEIN MILIEU. Sans erreur, sans log. Une replique de quinze secondes
-- s'arretait au tiers, et ca ressemble a un fichier abime ou a un scenario qui coupe la scene -- on va donc
-- chercher partout sauf dans l'utilitaire qui joue le son.
--
-- Une borne ne doit jamais etre plus serree que la donnee qu'elle borne. Si un son legitime depasse cette valeur,
-- c'est CETTE valeur qu'on monte, jamais le son qu'on raccourcit.
local SAFETY_LIFE = 180

-- Retrouve un Sound par chemin sous SoundService (ex : { "Sounds", "Engins", "Ladder", "LadderTakeSound" }).
local function resolve(path: { string }): Sound?
	local node: Instance? = SoundService
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return if node and node:IsA("Sound") then node else nil
end

-- Nettoie un clone quand il a fini de jouer. `Ended` d'abord -- il tire a la vraie fin du son, quelle que soit sa
-- duree -- et un delai LARGE derriere, uniquement pour le cas ou `Ended` ne tire jamais.
local function cleanup(sound: Sound)
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(SAFETY_LIFE, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- Clone le son du chemin donne et le joue. host = la part ou le poser (son spatial) ; nil = son global (2D).
-- Le clone se nettoie tout seul a la FIN du son. Rend le clone, ou nil si le son est introuvable.
function SoundUtils.play(path: { string }, host: BasePart?): Sound?
	local template = resolve(path)
	if not template then
		warn(`[SoundUtils] Son introuvable : SoundService.{table.concat(path, ".")}`)
		return nil
	end
	local sound = template:Clone()
	sound.Parent = host or SoundService
	sound:Play()
	cleanup(sound)
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
	cleanup(sound)
	return sound
end

return SoundUtils
