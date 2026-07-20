--!strict
-- Fonctions mathematiques pures : pas d'etat, pas de connexion, aucun effet de bord au require.
-- On n'y met QUE ce que Luau ne sait pas deja faire. math.clamp, math.sign, math.round et math.lerp existent
-- nativement : les reecrire ici ajouterait un appel de fonction Lua par-dessus du code natif, en plus lent, et
-- couperait le projet en deux entre ceux qui utilisent la version native et ceux qui utilisent celle-ci.

local MathUtils = {}

-- Interpolation lineaire entre a et b selon t (0 = a, 1 = b). t n'est PAS borne : passer 1.5 extrapole
-- au-dela de b, ce qui est parfois voulu (depassement d'une animation).
function MathUtils.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Ramene un angle en degres dans l'intervalle ]-180, 180].
-- Version par modulo plutot que par boucle : un angle accumule (une rotation qui tourne depuis dix minutes)
-- peut valoir plusieurs milliers de degres, et une boucle ferait alors des milliers de tours pour rien.
function MathUtils.NormalizeAngle(angle: number): number
	return 180 - (180 - angle) % 360
end

-- Plus petit ecart angulaire (en degres) pour aller de current vers target. Le signe donne le sens.
-- Sert des qu'on fait tourner quelque chose vers une cible : sans ca, aller de 350 vers 10 fait faire un tour
-- complet dans le mauvais sens au lieu de 20 degres.
function MathUtils.ShortestAngle(current: number, target: number): number
	return MathUtils.NormalizeAngle(target - current)
end

return MathUtils
