--!strict
-- COMPETENCES. Une jauge par activite, qui monte pendant qu'on la pratique -- pas une recompense qu'on recoit a
-- la fin. Le joueur VOIT qu'il devient meilleur au moment ou il fait le geste.
--
-- Pour l'instant une seule : la TONTE, le geste central du jeu.

local SkillConfigs = {}

-- ===== LA PROGRESSION =====
-- Combien de "coupe" il faut pour remplir la jauge au niveau 1. L'unite est celle que rend `GrassZoneController
-- .mowAt` : une quantite d'herbe reellement rabattue, pas un temps -- passer la tondeuse sur du beton ne fait donc
-- rien monter. C'est ce qui rend la jauge honnete : elle mesure le travail, pas la presence.
SkillConfigs.MOW_BASE = 60
-- De combien le palier suivant est plus long. Au-dessus de 1 : monter de 1 a 2 est rapide, de 9 a 10 beaucoup
-- moins. Sans ce ralentissement la jauge devient triviale, et une jauge qu'on remplit sans effort ne dit plus rien.
SkillConfigs.MOW_GROWTH = 1.35
-- Palier maximum. Une jauge sans fin n'a pas de fin a viser.
SkillConfigs.MOW_MAX_LEVEL = 10

-- ===== L'AFFICHAGE =====
-- ELLE N'EST PAS TOUJOURS LA. Une jauge affichee en permanence devient du decor : on cesse de la voir, donc elle
-- cesse de recompenser. Elle apparait au premier brin coupe et s'efface quand on s'arrete.
--
-- Combien de temps elle reste apres la derniere coupe, en secondes. Assez long pour couvrir un demi-tour de
-- tondeuse -- sinon elle clignote a chaque manoeuvre, ce qui est pire que de ne pas l'avoir.
SkillConfigs.MOW_LINGER = 2.5

-- A COTE DE LA TETE, pas au-dessus : le dessus est deja pris par les marqueurs et les prompts, et deux choses
-- empilees au meme endroit se genent. Decalage en studs depuis la RootPart -- X sur le cote, Y en hauteur.
SkillConfigs.BAR_SIDE = 2.2
SkillConfigs.BAR_UP = 2.6

-- Taille de la jauge en pixels a la distance de reference.
SkillConfigs.BAR_WIDTH = 90
SkillConfigs.BAR_HEIGHT = 14

-- LE BLEU. Celui de la competence, comme dans les jeux de vie : une couleur froide pour une progression, gardee
-- pour ELLE -- le vert appartient deja au vegetal et le dore a l'argent.
SkillConfigs.BAR_COLOR = Color3.fromRGB(64, 168, 255)
-- Le fond, sous le remplissage. Sombre et pas transparent : sur une pelouse claire, une jauge sans fond ne se lit
-- plus du tout tant qu'elle est presque vide.
SkillConfigs.BAR_BACK = Color3.fromRGB(18, 26, 38)
SkillConfigs.BAR_BACK_TRANSPARENCY = 0.25
-- Le contour, qui la detache du decor quelle que soit la couleur derriere.
SkillConfigs.BAR_STROKE = Color3.fromRGB(255, 255, 255)
SkillConfigs.BAR_STROKE_THICKNESS = 2

-- Duree du remplissage anime. Court : la jauge doit repondre au geste, pas le commenter une seconde plus tard.
SkillConfigs.BAR_FILL_TIME = 0.18
-- Apparition et disparition.
SkillConfigs.BAR_FADE_TIME = 0.25

-- ===== LES ATTRIBUTS =====
-- Poses sur le joueur. Un attribut se replique tout seul : pas de remote, pas de file a saturer, et n'importe quel
-- module peut lire le niveau sans connaitre celui qui le calcule.
SkillConfigs.MOW_LEVEL_ATTRIBUTE = "LeafiaMowSkill"
SkillConfigs.MOW_FILL_ATTRIBUTE = "LeafiaMowSkillFill"

return SkillConfigs
