--!strict
-- Fait passer un personnage en FANTOME, chez celui qui le regarde et nulle part ailleurs.
--
-- Purement client et volontairement generique : ce module ne connait ni la haie ni le taille-haie. L'appelant
-- dit a quel point effacer le corps et a quel point effacer les bras, rien de plus.
--
-- ON PASSE PAR LocalTransparencyModifier, JAMAIS PAR Transparency. Trois raisons, dans l'ordre d'importance :
--   1. Ca ne se replique pas. Les autres joueurs continuent de voir un personnage normal, ce qui compte des
--      qu'on sera en CO-OP : personne n'a envie de travailler a cote d'un fantome.
--   2. Ca s'AJOUTE a la transparence du jeu au lieu de l'ecraser. Une part deja invisible le reste, et il n'y
--      a aucune valeur d'origine a memoriser pour pouvoir la rendre.
--   3. C'est ce que Roblox utilise lui-meme pour effacer le personnage en vue subjective. On ne se bat donc
--      pas contre lui, on parle sa langue.

local CharacterFade = {}

-- Ce qui TIENT l'outil, et rien d'autre. Le reste du bras s'efface avec le corps.
--
-- C'est le point de contact entre le joueur et son outil : l'effacer laisserait un taille-haie qui flotte tout
-- seul, et la scene ne se lirait plus. Les avant-bras, eux, n'apportent rien de plus que le corps.
local HAND_PARTS: { [string]: boolean } = {
	LeftHand = true,
	RightHand = true,
	-- R6 N'A PAS DE MAIN : le bras entier est une seule part, donc c'est elle qui tient l'outil. La sortir de
	-- cette liste ferait flotter le taille-haie devant un fantome sur ce type de personnage.
	["Left Arm"] = true,
	["Right Arm"] = true,
}

-- Dernieres valeurs REELLEMENT ecrites, par personnage.
--
-- Sans ce garde-fou on reecrirait la meme transparence sur une vingtaine de parts a chaque frame, pour aucun
-- changement a l'ecran. Table a cles FAIBLES : un personnage detruit au respawn sort tout seul, il n'y a donc
-- aucun nettoyage a brancher et aucune fuite possible si un appelant oublie de le faire.
local applied: { [Model]: { body: number, hands: number } } =
	(setmetatable({}, { __mode = "k" }) :: any) :: { [Model]: { body: number, hands: number } }

local function write(part: BasePart, value: number)
	part.LocalTransparencyModifier = value
	for _, child in ipairs(part:GetChildren()) do
		-- Les decalques ont leur propre rendu. Sans cette ligne, le VISAGE resterait plein devant une tete
		-- devenue transparente, ce qui est plus laid que de ne rien effacer du tout.
		if child:IsA("Decal") then
			child.LocalTransparencyModifier = value
		end
	end
end

-- `body` et `hands` vont de 0 (rien d'efface) a 1 (invisible).
--
-- `force` IGNORE le garde-fou "meme valeur qu'avant". A n'utiliser que quand QUELQU'UN D'AUTRE ecrit sur les
-- memes parts a chaque image : c'est le cas en vue subjective, ou le controleur de transparence de Roblox repose
-- la sienne sans arret. Sans lui, notre valeur est posee une fois puis plus jamais rafraichie, et Roblox reprend
-- la main des l'image suivante -- les mains disparaissent alors que rien n'a change chez nous.
function CharacterFade.apply(character: Model, body: number, hands: number, force: boolean?)
	local last = applied[character]
	if
		not force
		and last
		and math.abs(last.body - body) < 0.001
		and math.abs(last.hands - hands) < 0.001
	then
		return
	end
	applied[character] = { body = body, hands = hands }

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("BasePart") then
			-- SEULS LES ENFANTS DIRECTS sont le corps. L'outil est un Model pose sur le personnage, donc ses
			-- parts sont plus profondes : elles gardent leur opacite sans qu'on ait a les nommer une par une.
			-- Une liste de noms d'outils serait a tenir a jour a chaque nouvel outil, et personne ne le ferait.
			write(child, if HAND_PARTS[child.Name] then hands else body)
		elseif child:IsA("Accessory") then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				-- Cheveux, chapeaux : ils suivent le corps. Les laisser pleins ferait flotter une chevelure
				-- toute seule au-dessus d'un fantome.
				write(handle, body)
			end
		end
	end
end

-- FORCE LES OUTILS A RESTER VISIBLES, contre Roblox.
--
-- En vue subjective, le controleur de transparence de Roblox efface tout le personnage. Il EPARGNE les parts
-- rangees sous un `Tool`... et nos outils sont des `Model` avec un Motor6D fabrique a la main (un Tool n'a rien
-- de magique, c'est juste Roblox qui lui cree son joint tout seul). Ils ne sont donc pas epargnes, et ils
-- disparaissent avec le corps -- alors que l'outil est precisement ce qu'on veut voir dans les mains.
--
-- A APPELER A CHAQUE IMAGE. Roblox repose sa valeur a chaque image tant que la camera est collee a la tete : une
-- ecriture unique serait effacee juste apres. Pas de cache ici pour la meme raison -- c'est le seul endroit du
-- module ou reecrire la meme valeur est le but, et non du gaspillage.
--
-- Zero sur le MODIFICATEUR, pas sur la transparence : une part volontairement translucide le reste.
function CharacterFade.keepToolsVisible(character: Model)
	for _, child in ipairs(character:GetChildren()) do
		-- Les outils sont les MODELS poses sur le personnage. On ne les nomme pas un par un : une liste serait a
		-- tenir a jour a chaque nouvel outil, et personne ne le ferait.
		if child:IsA("Model") then
			for _, part in ipairs(child:GetDescendants()) do
				if part:IsA("BasePart") then
					part.LocalTransparencyModifier = 0
				end
			end
		end
	end
end

function CharacterFade.clear(character: Model)
	CharacterFade.apply(character, 0, 0)
	applied[character] = nil
end

return CharacterFade
