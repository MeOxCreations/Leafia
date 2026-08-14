--!strict
-- Les LIEUX (places) de l'experience Leafia. Le joueur arrive TOUJOURS dans MAIN (lieu de depart) ; on le teleporte
-- vers les autres via TeleportService. Tout le code (src) est synce dans CHAQUE lieu : c'est game.PlaceId qui decide
-- du comportement (les bootstraps n'initialisent qu'un sous-ensemble dans le tuto).

local PlacesConfig = {
	MAIN = 84161484719535, -- Leafia (lieu de depart : plots, save, chantiers)
	TUTORIAL = 109440527457437, -- didacticiel (1re haie guidee, single-player)
}

return PlacesConfig
