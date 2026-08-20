--!strict
-- ANIMATIONS D'AMBIANCE de la map : tout ce qui bouge en boucle sans qu'on l'ait demande.
-- Aujourd'hui les plantes (buissons, arbres) et les PNJ qui respirent sur place (Papi). Meme mecanique pour les deux :
-- un modele pose dans la map, avec son Humanoid et son Animator, qui joue une boucle et ne fait rien d'autre.
--
-- Les IDs vivent ICI, dans du CODE, et PAS dans des Instances Animation rangees en ReplicatedStorage : Rojo
-- synchronise le code dans TOUTES les places, les Instances non (elles sont en $ignoreUnknownInstances et se
-- recopient a la main, place par place). Une nouvelle chose animee = UNE ligne dans ANIMATIONS, et elle vit partout.

-- NOM DU MODELE -> animation jouee en boucle. Le nom du modele dans Studio EST la cle : poser dix "Bush1" dans la map
-- les anime tous les dix, sans rien taguer ni rien brancher a la main.
-- Le modele doit contenir un Humanoid avec son Animator, et ses parts NE DOIVENT PAS etre ancrees : une part ancree
-- ignore son Motor6D, donc l'animation joue sans que rien ne bouge. Pour un PNJ qui doit rester plante au meme
-- endroit, ancrer UNIQUEMENT la RootPart : le reste suit l'animation et le personnage ne derive pas.
local ANIMATIONS: { [string]: string } = {
	Bush1 = "rbxassetid://78047203094778",
	Tree1 = "rbxassetid://130136106070231",
	-- Papi n'est PLUS ici : il se promene, donc NpcWanderService pilote ses deux animations (idle ET marche).
	-- Deux services sur le meme Animator finiraient par se battre pour la meme piste.
}

local AmbientAnimConfigs = {
	ANIMATIONS = ANIMATIONS,

	-- Ou chercher, sous Workspace. VIDE = tout le Workspace, et c'est VOULU : les plantes sont dans Assets.Foliages,
	-- les PNJ sont poses directement dans la map ou a la racine, et la prochaine chose sera encore ailleurs. Obliger a
	-- ranger un modele au bon endroit pour qu'il s'anime est un piege qui a deja coute deux diagnostics.
	-- Le cout est nul : tout ce qui naît dans le Workspace (des milliers de carreaux de haie, les debris de coupe) est
	-- ecarte par un `IsA("Model")` avant meme le test de nom, et un Model porte toujours un nom a comparer.
	-- Remettre un chemin ici (ex { "Worlds", "Maps" }) si un jour il faut restreindre.
	ROOT = {},

	-- DESYNCHRONISATION. Sans elle, dix buissons jouent la MEME boucle a la MEME image : ils ondulent tous ensemble,
	-- au meme instant, et l'oeil lit ca comme du faux immediatement. Vaut aussi pour deux PNJ cote a cote.
	-- Mettre SPEED_VARIATION a 0 et RANDOM_START a false pour retrouver un mouvement parfaitement synchronise.
	SPEED_VARIATION = 0.15, -- ecart de vitesse maxi, en fraction (0.15 = chacun entre 0.85x et 1.15x)
	RANDOM_START = true, -- demarrer chacun a un point au hasard de sa boucle

	-- L'Animator peut arriver quelques frames apres le modele (meme piege qu'a CharacterAdded). Au-dela, on abandonne
	-- ce modele plutot que d'attendre pour toujours.
	ANIMATOR_TIMEOUT = 5,

	-- Delai TOTAL pour trouver le dossier au demarrage (un seul delai pour tout le chemin, pas un par segment).
	-- Au-dela : on previent, et cette place n'a pas d'animation d'ambiance.
	ROOT_TIMEOUT = 10,
}

return AmbientAnimConfigs
