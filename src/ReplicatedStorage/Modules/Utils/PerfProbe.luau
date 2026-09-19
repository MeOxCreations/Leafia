--!strict
-- SONDE DE TEMPS DES BOUCLES PAR IMAGE. Chaque grosse boucle (herbe, feuilles, papillons...) passe sa fonction par
-- `wrap` ; le temps qu'elle prend est additionne sous son nom, et `PerfStatsController` l'affiche sous le compteur FPS.
--
-- POURQUOI : un jeu a 13 images par seconde sur telephone peut ramer pour deux raisons opposees -- nos scripts qui
-- calculent trop, ou le moteur qui a trop de pieces a DESSINER. Elles se corrigent a des endroits sans rapport, et ne
-- se distinguent pas a l'oeil. Cette sonde repond a la premiere question par une mesure, pas par une supposition.
--
-- ETEINTE, ELLE NE COUTE RIEN : `wrap` rend alors la fonction telle quelle. Seul le compteur (admins) l'allume, et il
-- doit le faire AVANT que les autres modules branchent leurs boucles -- d'ou sa place en tete du bootstrap client.

local PerfProbe = {}

local enabled = false
local totals: { [string]: number } = {}

function PerfProbe.enable()
	enabled = true
end

function PerfProbe.isEnabled(): boolean
	return enabled
end

--- Enveloppe une fonction appelee a chaque image et range son temps (secondes) sous `name`.
function PerfProbe.wrap<A...>(name: string, fn: (A...) -> ()): (A...) -> ()
	if not enabled then
		return fn
	end
	return function(...: A...)
		local t0 = os.clock()
		fn(...)
		totals[name] = (totals[name] or 0) + (os.clock() - t0)
	end
end

--- Rend les temps accumules depuis le dernier appel (secondes, par nom) et repart de zero.
function PerfProbe.take(): { [string]: number }
	local out = totals
	totals = {}
	return out
end

return PerfProbe
