--!strict
-- Formatage des nombres pour l'affichage joueur (dollars, jetons, compteurs).
-- 1010 -> "1.01K" | 45310 -> "45.31K" | 999999 -> "1M" | 1454000 -> "1.45M" | 349530000 -> "349.53M"
-- Sous 1000 on garde le nombre entier brut.

local FormatUtils = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local MAX_TIER = #SUFFIXES - 1

-- Enleve les zeros de fin inutiles : "5.00" -> "5", "5.50" -> "5.5", "5.01" -> "5.01".
local function trimZeros(s: string): string
	return (s:gsub("%.?0+$", ""))
end

function FormatUtils.Abbreviate(n: number): string
	if math.abs(n) < 1000 then
		return tostring(math.floor(n))
	end

	-- Division successive plutot que math.log(abs, 1000). Le logarithme passe par une division de flottants :
	-- aux puissances exactes (1e6, 1e9) un ecart d'un ulp suffit a retomber d'un cran et a afficher "1000K"
	-- au lieu de "1M". La boucle fait 11 tours au pire et ne peut pas se tromper.
	local tier = 0
	local scaled = n
	while math.abs(scaled) >= 1000 and tier < MAX_TIER do
		scaled /= 1000
		tier += 1
	end

	local s = string.format("%.2f", scaled)

	-- L'arrondi du formatage peut faire franchir le palier APRES coup : 999999 donne 999.999, que %.2f ecrit
	-- "1000.00". Sans ce rattrapage on affiche "1000K" au lieu de "1M".
	local rounded = tonumber(s)
	if rounded and math.abs(rounded) >= 1000 and tier < MAX_TIER then
		tier += 1
		s = string.format("%.2f", scaled / 1000)
	end

	return trimZeros(s) .. SUFFIXES[tier + 1]
end

return FormatUtils
