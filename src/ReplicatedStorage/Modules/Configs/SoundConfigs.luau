--!strict
-- TOUS LES SONS DU JEU, PAR LEUR ID. Table de donnees pure.
--
-- POURQUOI. Un Sound pose dans Studio n'existe que dans la place ou on l'a pose : Rojo ne synchronise pas
-- SoundService. Il manque alors dans l'autre place SANS RIEN DIRE -- vecu sur la replique devant la haie, presente
-- dans une place et absente du didacticiel, et on cherchait le bug dans la voix. Ici le son part sur GitHub avec
-- le code et arrive dans TOUTES les places d'un coup.
--
-- LE SERVEUR LES POSE AU DEMARRAGE, a ce chemin sous SoundService (voir SoundRegistryService) : tout le code qui
-- cherche un son par son chemin le trouve sans avoir change. Si un Sound existe deja a ce chemin dans Studio, il
-- prend les valeurs d'ici (la config gagne) et garde ses enfants (effets) -- on peut donc migrer petit a petit, puis
-- supprimer les Sound de Studio.
--
-- CLE = le chemin sous SoundService, separe par des "/". `volume` et `speed` : 0.5 et 1 si absents (les defauts
-- de Roblox), `looped` : faux si absent.
--
-- POUR REMPLIR : coller `scripts/studio/ExporterSons.lua` dans la barre de commandes de Studio, il imprime ces
-- lignes a partir des Sound deja poses.

export type Entry = { id: string, volume: number?, speed: number?, looped: boolean? }

local SoundConfigs: { [string]: Entry } = {}

return SoundConfigs
