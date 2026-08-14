--!strict
-- Data pure des PLOTS (aucune logique). Alimente l'ecran de selection : nom affiche, categorie de taille, nombre
-- de tuiles, et la petite description. Une entree PAR plot, keyee sur le NOM de l'instance (Slot1, Slot2...).
--
-- Un plot absent de la table prend DEFAULT (jamais de trou a l'ecran). A ETOFFER librement : c'est du texte.

export type PlotInfo = {
	name: string, -- nom affiche (TitleNamePlot)
	size: string, -- categorie de taille affichee en majuscules (SMALL / MEDIUM / LARGE...)
	tiles: number, -- nombre de tuiles du plot (PlotMaxMinText)
	description: string, -- ~1 ligne et demie (DescriptionText)
}

local DEFAULT: PlotInfo = {
	name = "Unnamed Plot",
	size = "SMALL",
	tiles = 50,
	description = "A patch of land waiting for a landscaper. Clear it, shape it, and turn it into something the whole street stops to look at.",
}

local PLOTS: { [string]: PlotInfo } = {
	Slot1 = {
		name = "Starter Plot",
		size = "SMALL",
		tiles = 50,
		description = "The starter plot. Forty tiles of flat grass, one leaky tap and a shed that smells of 1998. Every big Leafia company started right here.",
	},
	Slot2 = {
		name = "Corner Lot",
		size = "MEDIUM",
		tiles = 100,
		description = "A wide corner lot with room to breathe. Twice the grass, twice the hedges, and a driveway the neighbours already envy.",
	},
	Slot3 = {
		name = "Garden Estate",
		size = "LARGE",
		tiles = 200,
		description = "A proper estate. Long borders, mature trees and space for a real crew. This is where small companies become names people know.",
	},
	Slot4 = {
		name = "Riverside Grounds",
		size = "LARGE",
		tiles = 260,
		description = "Grounds that run down to the water. Damp soil, big skies and a view that makes every finished job look like a postcard.",
	},
	Slot5 = {
		name = "The Domain",
		size = "HUGE",
		tiles = 400,
		description = "The domain. Acres of it. The kind of contract you take on when the whole town already knows your green vans by heart.",
	},
}

local PlotConfigs = {}

-- Retourne l'info du plot au nom donne, ou DEFAULT s'il n'est pas dans la table.
function PlotConfigs.get(name: string): PlotInfo
	return PLOTS[name] or DEFAULT
end

return PlotConfigs
