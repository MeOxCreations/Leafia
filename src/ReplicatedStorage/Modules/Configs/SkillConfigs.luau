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

-- Taille de la jauge en pixels a la distance de reference. VERTICALE : plus haute que large.
--
-- POURQUOI VERTICALE. Une jauge horizontale posee a cote d'une tete occupe la largeur de l'ecran au lieu de la
-- hauteur, et c'est la largeur qui est deja prise -- par le personnage, par ce qu'il regarde, par la machine
-- devant lui. Debout, elle tient dans un couloir vide, et une progression qui MONTE se lit plus vite qu'une
-- progression qui va vers la droite.
SkillConfigs.BAR_WIDTH = 16
SkillConfigs.BAR_HEIGHT = 96

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

-- ===== SON ARRIVEE =====
-- ELLE SE DEPLIE. Un simple fondu se lit comme une interface qui s'allume ; un depliement se lit comme quelque
-- chose qui ARRIVE, et c'est ce qui fait remarquer la premiere touffe coupee.
--
-- L'echelle passe par un `UIScale`, donc elle est UNIFORME : la jauge grandit sans jamais se deformer, et son
-- contour garde son epaisseur. Animer la taille aurait etire le dessin et epaissi le trait.
SkillConfigs.BAR_POP_TIME = 0.34
-- De combien elle DEPASSE sa taille avant de se poser. C'est ce depassement qui donne le ressort -- une echelle
-- qui monte tout droit ne se distingue pas d'un fondu.
SkillConfigs.BAR_POP_OVER = 1.18
SkillConfigs.BAR_SETTLE_TIME = 0.16
-- ET ELLE MONTE en arrivant, de quelques studs : elle se pose a sa place au lieu d'y etre deja. Le mouvement est
-- porte par le point VISE dans le monde, donc elle continue de suivre le joueur pendant qu'elle arrive.
SkillConfigs.BAR_POP_RISE = 0.7

-- ===== LES ATTRIBUTS =====
-- Poses sur le joueur. Un attribut se replique tout seul : pas de remote, pas de file a saturer, et n'importe quel
-- module peut lire le niveau sans connaitre celui qui le calcule.
SkillConfigs.MOW_LEVEL_ATTRIBUTE = "LeafiaMowSkill"
SkillConfigs.MOW_FILL_ATTRIBUTE = "LeafiaMowSkillFill"

return SkillConfigs
