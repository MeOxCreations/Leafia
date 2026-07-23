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
function CharacterFade.apply(character: Model, body: number, hands: number)
	local last = applied[character]
	if last and math.abs(last.body - body) < 0.001 and math.abs(last.hands - hands) < 0.001 then
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

function CharacterFade.clear(character: Model)
	CharacterFade.apply(character, 0, 0)
	applied[character] = nil
end

return CharacterFade
