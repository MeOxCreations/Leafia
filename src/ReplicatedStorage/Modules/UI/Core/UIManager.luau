--!strict
-- GESTIONNAIRE D'ECRANS UI. Garantit qu'UN SEUL "ecran" (un groupe de GuiObjects) est visible a la fois.
--
-- show() cache TOUT puis montre l'ecran demande, de facon SYNCHRONE (aucun yield au milieu). Consequence : meme en
-- spammant les boutons a toute vitesse, on ne peut JAMAIS avoir deux ecrans affiches en meme temps -- chaque appel
-- termine (tout cacher -> montrer un) avant que le clic suivant soit traite. C'est le vrai garde-fou anti-glitch.
--
-- Ce module ne gere QUE les ecrans mutuellement exclusifs (select plot, select save, build mode...). Les HUD
-- toujours affiches (pieces, XP, combo...) ne sont PAS enregistres ici : ils vivent leur vie a cote.

local UIManager = {}

local screens: { [string]: { GuiObject } } = {} -- nom d'ecran -> ses GuiObjects
local everything: { GuiObject } = {} -- tous les objets enregistres, pour tout cacher d'un coup
local current: string? = nil -- ecran actuellement affiche

-- Declare un ecran : un nom + les GuiObjects qui le composent (montres / caches ENSEMBLE). Caches au depart.
function UIManager.register(name: string, objects: { GuiObject })
	screens[name] = objects
	for _, obj in ipairs(objects) do
		table.insert(everything, obj)
		obj.Visible = false
	end
end

-- Affiche UN ecran : cache tout le reste, montre celui-ci. Idempotent (rappeler le meme ecran ne fait rien).
function UIManager.show(name: string)
	if current == name then
		return
	end
	local target = screens[name]
	if not target then
		warn(`[UIManager] Ecran "{name}" inconnu (pas enregistre).`)
		return
	end
	-- SYNCHRONE : on cache TOUT avant de montrer la cible -> jamais deux ecrans visibles, meme en spammant.
	for _, obj in ipairs(everything) do
		obj.Visible = false
	end
	for _, obj in ipairs(target) do
		obj.Visible = true
	end
	current = name
end

-- Cache tous les ecrans (plus rien d'affiche).
function UIManager.hideAll()
	for _, obj in ipairs(everything) do
		obj.Visible = false
	end
	current = nil
end

-- Nom de l'ecran affiche, ou nil.
function UIManager.current(): string?
	return current
end

return UIManager
