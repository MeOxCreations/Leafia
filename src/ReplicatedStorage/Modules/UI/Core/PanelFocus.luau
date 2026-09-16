--!strict
-- QUI A L'ECRAN. Un seul PANNEAU ouvert a la fois, et les HUD s'effacent devant lui.
--
-- LE PROBLEME QU'IL REGLE : la barre du camion, le menu des outils et la liste des taches vivaient chacun leur vie.
-- Devant la benne on voyait les trois d'un coup -- deux interfaces qui parlent des memes outils, et une liste de
-- taches par-dessus. Le joueur ne sait plus ou regarder, et deux panneaux ouverts se cliquent l'un pour l'autre.
--
-- DEUX ROLES, et un meme participant peut tenir les deux :
--   - un PANNEAU s'ouvre pour une decision (`setOpen`). En ouvrir un ferme les autres qui savent se fermer.
--   - un HUD reste a l'ecran en continu, et se RANGE tant qu'un panneau qui n'est pas le sien est ouvert.
-- Le menu des outils est les deux : son bouton est un HUD, son panneau est un panneau. Il ne se range donc pas
-- devant lui-meme.
--
-- CE MODULE NE TOUCHE A AUCUNE INTERFACE. Chacun lui donne ses propres gestes (`tuck`, `close`) : c'est celui qui
-- construit une interface qui sait comment elle se range, et il reste le seul a ecrire ses proprietes.

local PanelFocus = {}

-- LE RETOUR ATTEND UN PEU. Le panneau qui se ferme a sa propre sortie : si les HUD revenaient dans la meme image,
-- les deux mouvements se croiseraient et se liraient comme un seul bloc confus. Un court relais dit "l'un part,
-- les autres reviennent".
local RETURN_DELAY = 0.18

export type Hooks = {
	-- Range (`true`) ou ramene (`false`) le HUD. `instant` : sans animation (a l'enregistrement).
	tuck: ((tucked: boolean, instant: boolean) -> ())?,
	-- Ferme le panneau quand un AUTRE s'ouvre. Absent : ce panneau ne se laisse pas fermer par un autre.
	close: (() -> ())?,
}

type Entry = { hooks: Hooks, tucked: boolean, token: number }

local entries: { [string]: Entry } = {}
local opened: { [string]: boolean } = {}

local function blockedFor(name: string): boolean
	for panel in opened do
		if panel ~= name then
			return true
		end
	end
	return false
end

local function refresh()
	for name, entry in entries do
		local tuck = entry.hooks.tuck
		local want = blockedFor(name)
		if not tuck or want == entry.tucked then
			continue
		end
		entry.tucked = want
		entry.token += 1
		if want then
			tuck(true, false)
		else
			local token = entry.token
			task.delay(RETURN_DELAY, function()
				-- Rouvert entre-temps, ou remplace : ce retour-la n'a plus lieu d'etre.
				if entries[name] == entry and entry.token == token then
					tuck(false, false)
				end
			end)
		end
	end
end

--- Declare un participant. Rappelable : la nouvelle declaration remplace l'ancienne (interface reconstruite).
--- Le HUD prend TOUT DE SUITE l'etat courant, sans animation : construit pendant qu'un panneau est ouvert, il doit
--- naitre deja range.
function PanelFocus.register(name: string, hooks: Hooks)
	local tucked = blockedFor(name)
	entries[name] = { hooks = hooks, tucked = tucked, token = 0 }
	local tuck = hooks.tuck
	if tuck then
		tuck(tucked, true)
	end
end

function PanelFocus.unregister(name: string)
	entries[name] = nil
	if opened[name] then
		opened[name] = nil
		refresh()
	end
end

--- Un panneau s'ouvre ou se ferme. Idempotent : les interfaces l'appellent a chaque rafraichissement.
function PanelFocus.setOpen(name: string, on: boolean)
	if (opened[name] == true) == on then
		return
	end
	if on then
		opened[name] = true
		-- LES AUTRES D'ABORD RETIRES DE LA LISTE, PUIS FERMES. Leur fermeture rappelle `setOpen(x, false)` : retire
		-- avant, cet appel ne fait plus rien, et on ne modifie pas la table pendant qu'on la parcourt.
		local toClose: { () -> () } = {}
		for other in opened do
			local entry = entries[other]
			local close = if entry then entry.hooks.close else nil
			if other ~= name and close then
				table.insert(toClose, close)
				opened[other] = nil
			end
		end
		for _, close in toClose do
			close()
		end
	else
		opened[name] = nil
	end
	refresh()
end

--- Vrai si ce HUD est range en ce moment.
function PanelFocus.isTucked(name: string): boolean
	local entry = entries[name]
	return entry ~= nil and entry.tucked
end

return PanelFocus
