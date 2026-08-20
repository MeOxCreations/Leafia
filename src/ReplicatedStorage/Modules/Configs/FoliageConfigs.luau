--!strict
-- DECOR VEGETAL anime (arbres, buissons, et ce qui viendra).
--
-- Les IDs vivent ICI, dans du CODE, et PAS dans des Instances Animation rangees en ReplicatedStorage : Rojo
-- synchronise le code dans TOUTES les places, les Instances non (elles sont en $ignoreUnknownInstances et se
-- recopient a la main, place par place). Une nouvelle plante = UNE ligne dans ANIMATIONS, et elle vit partout.

-- NOM DU MODELE -> animation jouee en boucle. Le nom du modele dans Studio EST la cle : poser dix "Bush1" dans la
-- map les anime tous les dix, sans rien taguer ni rien brancher a la main.
-- Le modele doit contenir un Humanoid avec son Animator (c'est ce que produit le rig d'animation).
local ANIMATIONS: { [string]: string } = {
	Bush1 = "rbxassetid://78047203094778",
	Tree1 = "rbxassetid://130136106070231",
}

local FoliageConfigs = {
	ANIMATIONS = ANIMATIONS,

	-- Ou chercher, sous Workspace. Volontairement SERRE sur le dossier des plantes : Worlds.Maps contient aussi les
	-- milliers de carreaux de haie, et y brancher DescendantAdded ferait passer chacun d'eux par le test de nom pour
	-- rien. Si tu poses des plantes ailleurs que dans ce dossier, elles ne s'animeront pas : change ce chemin.
	ROOT = { "Worlds", "Maps", "Assets", "Foliages" },

	-- DESYNCHRONISATION. Sans elle, dix buissons jouent la MEME boucle a la MEME image : ils ondulent tous ensemble,
	-- au meme instant, et l'oeil lit ca comme du faux immediatement.
	-- Mettre SPEED_VARIATION a 0 et RANDOM_START a false pour retrouver un mouvement parfaitement synchronise.
	SPEED_VARIATION = 0.15, -- ecart de vitesse maxi, en fraction (0.15 = chaque plante entre 0.85x et 1.15x)
	RANDOM_START = true, -- demarrer chaque plante a un point au hasard de sa boucle

	-- L'Animator peut arriver quelques frames apres le modele (meme piege qu'a CharacterAdded). Au-dela, on abandonne
	-- cette plante plutot que d'attendre pour toujours.
	ANIMATOR_TIMEOUT = 5,

	-- Delai TOTAL pour trouver le dossier des plantes au demarrage (un seul delai pour tout le chemin, pas un par
	-- segment). Au-dela : on previent et cette place n'a pas de decor anime.
	ROOT_TIMEOUT = 10,
}

return FoliageConfigs
