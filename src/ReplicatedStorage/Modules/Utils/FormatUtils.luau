--!strict
-- Formatage des nombres pour l'affichage joueur (pieces, jetons, compteurs).
-- Toujours UNE decimale des qu'on abrege : 1010 -> "1.0K" | 45310 -> "45.3K" | 999999 -> "1.0M" |
-- 1454000 -> "1.5M" | 349530000 -> "349.5M". Sous 1000 on garde le nombre entier brut : 500 -> "500".

local FormatUtils = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local MAX_TIER = #SUFFIXES - 1

function FormatUtils.Abbreviate(n: number): string
	if math.abs(n) < 1000 then
		return tostring(math.floor(n))
	end

	-- Division successive plutot que math.log(abs, 1000). Le logarithme passe par une division de flottants :
	-- aux puissances exactes (1e6, 1e9) un ecart d'un ulp suffit a retomber d'un cran et a afficher "1000.0K"
	-- au lieu de "1.0M". La boucle fait 11 tours au pire et ne peut pas se tromper.
	local tier = 0
	local scaled = n
	while math.abs(scaled) >= 1000 and tier < MAX_TIER do
		scaled /= 1000
		tier += 1
	end

	local s = string.format("%.1f", scaled)

	-- L'arrondi du formatage peut faire franchir le palier APRES coup : 999999 donne 999.999, que %.1f ecrit
	-- "1000.0". Sans ce rattrapage on afficherait "1000.0K" au lieu de "1.0M".
	local rounded = tonumber(s)
	if rounded and math.abs(rounded) >= 1000 and tier < MAX_TIER then
		tier += 1
		s = string.format("%.1f", scaled / 1000)
	end

	return s .. SUFFIXES[tier + 1]
end

return FormatUtils
