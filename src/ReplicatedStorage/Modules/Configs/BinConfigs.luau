--!strict
-- Reglages du SEAU porte. Data pure, zero logique. Partage client + serveur.
--
-- PARTAGE DES ROLES
--   SERVEUR (BinCarryService)    : qui porte quoi. Portage par MOTOR6D -> tout le monde le voit. C'est lui
--                                  qui desancre, qui soude, et qui repose le seau AU SOL.
--   CLIENT (BinCarryController)  : detection du prompt, animations du joueur, declenchement. De l'intention.
--
-- PORTAGE LIBRE, contrairement a l'echelle : aucun rail, aucun aimant vers une haie. On se balade ou on veut
-- et on repose ou on veut. Tout le systeme de focus de LadderMoveController est donc absent ici, volontairement.

return {
	-- ===== LE SEAU DANS LE MONDE =====
	-- Prefixe du Model pose dans Studio (Bin, Bin_01...). Toute la detection part de la : pas de tag a maintenir.
	-- ATTENTION : un model de TEST nomme "Bintest" serait vu comme un vrai seau. Les objets de travail (rigs
	-- d'animation) doivent donc vivre hors du Workspace, ou porter un autre nom.
	MODEL_PREFIX = "Bin",
	-- COMBIEN DE FEUILLES IL CONTIENT, pose sur le modele du seau.
	--
	-- UN ATTRIBUT SUR L'OBJET, pas une table par joueur. Il se replique tout seul, il voyage AVEC le seau, et il
	-- survit a la repose : un seau pose au sol garde ce qu'il contient, ce qui est la moindre des choses pour un
	-- seau. Une table cote serveur mentirait des que deux joueurs se passent le meme.
	LEAVES_ATTRIBUTE = "LeafiaBinLeaves",
	-- ===== ON PEUT TENIR UN OUTIL EN PORTANT LE SEAU =====
	-- INTERRUPTEUR, ET IL EST VOLONTAIREMENT ISOLE ICI. La regle du jeu est "on porte a deux mains, donc pas
	-- d'outil en meme temps" -- c'est ce qui evite un taille-haie qui flotte a cote d'un guidon. Le SEAU est le
	-- seul cas ou la question se pose vraiment : ramasser des feuilles demande un rateau ET un seau, et faire des
	-- allers-retours entre les deux pour chaque poignee serait une corvee.
	--
	-- CA NE TOUCHE QUE LE SEAU. L'echelle et la tondeuse restent a deux mains : elles se POUSSENT ou se PORTENT
	-- devant soi, il n'y a pas de main libre a trouver.
	--
	-- A REPASSER A `false` si le rendu ne tient pas la route -- c'est un choix de gameplay, pas une correction, et
	-- il se defait en un mot.
	ALLOW_TOOL_WHILE_CARRIED = true,
	-- ===== CE QU'IL PEUT CONTENIR =====
	-- COMBIEN DE FEUILLES AVANT D'ETRE PLEIN.
	--
	-- UN SEAU SANS LIMITE N'EST PAS UN SEAU, C'EST UN TROU. La contenance cree la seule decision de cette etape :
	-- continuer, ou aller le vider. Sans elle la jauge ne dirait rien, et vider ne serait jamais un choix.
	LEAVES_CAPACITY = 40,
	-- A QUELLE DISTANCE UN TAS TOMBE DEDANS, en studs, mesuree a plat.
	--
	-- GENEREUSE : le joueur POUSSE les feuilles avec un rateau, il ne vise pas. Trop serree, il rate son tas de
	-- quelques centimetres et croit que le seau ne marche pas.
	ABSORB_RADIUS = 6,
	-- Cadence du controle. Serree : le tas nait sous le coup de rateau, et le voir clignoter une fraction de
	-- seconde avant de disparaitre dans le seau se lit comme un rate. A dix par seconde, il n'existe jamais a
	-- l'ecran quand le seau est a cote.
	ABSORB_INTERVAL = 0.1,
	-- Le bruit des feuilles qui tombent dedans, porte par le seau. Facultatif : sans lui le ramassage marche.
	ABSORB_SOUND = { "Sounds", "Game", "GlobalSounds", "DropSound" },

	-- ===== LES FEUILLES QU'ON VOIT DEDANS =====
	-- Le modele a dupliquer DANS le seau des qu'il contient quelque chose. Il vit dans `Assets`, que Rojo ne
	-- synchronise pas : absent d'une place, le compte marche quand meme -- il ne se voit juste pas.
	LEAF_MODEL_PATH = { "Assets", "Contents", "LeafInBinModel" },
	LEAF_MODEL_NAME = "LeafInBinModel",
	-- A QUELLE HAUTEUR ELLES SE POSENT DANS LE SEAU, en studs au-dessus de sa part de reference : vide, puis
	-- plein.
	--
	-- ELLES MONTENT AVEC LE REMPLISSAGE, et ce n'est pas de la coquetterie : c'est la MEME information que la
	-- jauge, dite par l'objet lui-meme. Un joueur qui regarde son seau sait ou il en est sans lire un chiffre, et
	-- de dos, et le son coupe.
	--
	-- DEUX NOMBRES A REGLER A L'OEIL. Aucun calcul ne devine a quelle hauteur des feuilles "ont l'air" posees au
	-- fond d'un seau : ca depend du centre du modele de feuilles ET de celui du seau, tous deux poses a la main.
	LEAF_LOW = 0.9,
	LEAF_HIGH = 1.9,

	-- ===== LA JAUGE AU-DESSUS =====
	-- Taille en pixels, et hauteur au-dessus du seau en studs.
	GAUGE_WIDTH = 120,
	GAUGE_HEIGHT = 26,
	-- BIEN AU-DESSUS DU SEAU MAIS SOUS LA PILULE. Le badge d'interaction flotte plus haut : a 2.6 la jauge lui
	-- rentrait dedans, et deux interfaces qui se chevauchent ne se lisent ni l'une ni l'autre.
	GAUGE_UP = 0.4,
	-- Au-dela, elle ne s'affiche plus : une barre lisible a trente metres encombre la vue pour rien.
	GAUGE_MAX_DISTANCE = 60,
	-- Cadence de rafraichissement. Le compte ne change qu'au coup de rateau : dix fois par seconde est deja large.
	GAUGE_INTERVAL = 0.1,
	-- ELLE GLISSE, elle ne saute pas. Une barre qui change d'un bond ne se lit pas : on voit l'etat d'apres,
	-- jamais le mouvement, donc on ne sent pas qu'on progresse.
	GAUGE_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	GAUGE_BACK = Color3.fromRGB(28, 40, 52),
	GAUGE_FILL = Color3.fromRGB(98, 206, 59),
	-- PLEIN CHANGE DE COULEUR. Le joueur n'a pas a comparer deux nombres pour comprendre qu'il doit aller vider.
	GAUGE_FULL = Color3.fromRGB(255, 158, 44),
	-- EN ANGLAIS, comme tout texte vu par le joueur.
	GAUGE_FULL_TEXT = "FULL",
	-- Part fixe de reference. JAMAIS GetPivot : le pivot d'un Model suit sa bounding box, donc ajouter la
	-- moindre part enfant le decale et tous les calculs partent de travers. On prend la PrimaryPart, sinon
	-- un enfant portant ce nom.
	--
	-- CE NOM EST AUSSI CELUI QUE L'ANIMATION CHERCHE. La part designee ici devient la Part1 du Motor6D de
	-- portage, et une animation retrouve ce qu'elle doit bouger par le nom de la PART1. Pour que la piste du
	-- seau (celle que tu animes dans l'editeur) morde EN JEU, la part du seau doit donc porter ici le MEME nom
	-- que sur le rig d'animation. Si les deux different, la piste ne trouve rien et n'ecrit RIEN, sans la
	-- moindre erreur : le seau reste fige sur CARRY_C0 et on croit a un probleme d'angle.
	ROOT_NAME = "RootPart",

	-- ===== PRISE =====
	-- Part du PERSONNAGE a laquelle le seau est soude. MESUREE sur le rig d'animation (VerifierBin.lua), pas
	-- devinee : le jeu doit rejouer EXACTEMENT le joint qui a servi a animer, sinon le seau est de travers en
	-- jeu alors que l'animation est bonne -- et on cherche l'erreur dans l'animation.
	--
	-- HumanoidRootPart, et surtout PAS UpperTorso. Le torse est LUI-MEME anime : il figure dans les pistes des
	-- deux animations du seau. Un seau accroche a lui recoit donc le mouvement du torse EN PLUS du sien -- deux
	-- mouvements additionnes au lieu d'un, et le geste ne ressemble plus a celui de l'editeur alors que
	-- l'animation, elle, est bonne. La position finale vaut `part porteuse x C0 x ce qu'ecrit l'animation` : les
	-- deux premiers termes doivent etre EXACTEMENT ceux du rig, sinon le troisieme s'applique de travers.
	--
	-- Va ENSEMBLE avec CARRY_C0 : changer l'une sans l'autre donne n'importe quoi.
	JOINT_PARENT = "HumanoidRootPart",
	-- Position et angle du seau vus depuis JOINT_PARENT. RELEVEE sur le rig par VerifierBin.lua, jamais reglee a
	-- l'oeil : c'est le placement fait dans l'editeur qui est la source de verite, et toute retouche a la main
	-- eloigne le jeu de l'animation. Z negatif = devant le corps.
	CARRY_C0 = CFrame.new(0, 0.2, -2.6) * CFrame.Angles(0, math.rad(90), 0),
	-- Nom du Motor6D cree. Sert a le RETROUVER et a le lire dans l'Explorer, RIEN D'AUTRE.
	--
	-- Il ne joue AUCUN role dans l'animation, contrairement a ce que disaient les versions 0.0.430 / 0.0.431. Une
	-- animation Roblox ne cherche pas un joint par le nom DU JOINT : elle cherche par le nom de sa PART1. Ses
	-- poses portent des noms de PARTS. C'est pour ca qu'une anim R15 contient "UpperTorso" et "LeftUpperArm" (des
	-- parts) et jamais "Waist" ni "LeftShoulder" (les Motor6D qui les tirent).
	--
	-- Le nom qui compte pour que l'animation pilote le seau est donc ROOT_NAME (la part soudee, Part1 du joint),
	-- pas celui-ci. Le renommer ne changera jamais rien.
	JOINT_NAME = "BinCarryJoint",
	-- Secondes apres la prise avant de verifier que l'animation a bien bouge le joint. Assez tard pour qu'une
	-- piste ait eu le temps d'ecrire, assez tot pour que le message serve.
	ANIM_CHECK_DELAY = 0.6,
	-- Distance MAX joueur <-> seau acceptee par le serveur a la prise (anti-triche). Large expres : le client
	-- a deja filtre par DETECT_RADIUS, ceci n'est qu'un garde-fou contre un remote falsifie.
	MAX_DIST = 30,

	-- ===== DETECTION / PROMPT =====
	-- Distance HORIZONTALE (studs) sous laquelle le prompt apparait. RADIALE, pas une box : colle a un bout du
	-- seau on tomberait HORS d'une box laterale, et l'agrandir ne bouche pas le trou (elle reste au mauvais
	-- endroit). Un seul rayon, aucun angle mort, independant de l'orientation.
	DETECT_RADIUS = 8,
	-- On ne teste pas la proximite a chaque image : ca ne se voit pas et ca coute (le balayage parcourt les seaux).
	PROMPT_INTERVAL = 0.15,
	-- Le Workspace est re-balaye periodiquement : avec StreamingEnabled un seau lointain peut arriver TARD, et
	-- un scan unique au boot ne le verrait jamais.
	RESCAN_INTERVAL = 2,
	PROMPT_KEY = "E",
	PROMPT_LABEL = "TAKE",
	PROMPT_TITLE = "BUCKET",
	-- Hauteur d'AFFICHAGE du badge au-dessus de la racine. Sans rapport avec DETECT_RADIUS (la distance a
	-- laquelle il apparait) : deux reglages differents, ne pas confondre.
	PROMPT_OFFSET = Vector3.new(0, 4, 0),

	-- ===== INPUT =====
	-- ContextActionService : createTouchButton fait apparaitre un bouton a l'ecran sur tactile ET bind la
	-- touche sur PC, d'un seul geste. Sans lui, prendre le seau serait injouable sans clavier.
	ACTION_NAME = "LeafiaBinCarry",
	-- E, comme la tondeuse (MowController). CONFLIT CONNU : si un seau et une tondeuse sont poses cote a cote,
	-- les deux actions repondent a E. On ne branche donc la notre QUE si le joueur ne porte rien d'autre.
	ACTION_KEY = Enum.KeyCode.E,
	-- Apres une prise OU une repose, on ignore la touche ce court instant. Sans ca un double-tap reposerait le
	-- seau AVANT que le geste de prise (marqueur a 0.33s) ait joue.
	PICKUP_DEBOUNCE = 0.6,

	-- ===== ETAT =====
	-- Pose par le SERVEUR sur le seau : UserId du porteur. Le client le lit pour ne pas proposer un seau
	-- deja pris par quelqu'un d'autre.
	-- LE BRUIT QU'IL FAIT EN TOUCHANT LE SOL. Joue au CONTACT, pas au lacher : entre les deux il y a tout le
	-- glissement, et un choc qui precede l'image se lit comme un autre objet, ailleurs.
	--
	-- La poussiere, elle, part un peu AVANT le contact -- des particules mettent le temps de naitre et de
	-- s'ecarter. Un son n'a pas ce delai, donc les deux ne partent pas au meme instant.
	DROP_SOUND = { "Sounds", "Game", "GlobalSounds", "DropSound" },
	CARRIED_ATTRIBUTE = "LeafiaBinCarriedBy",
	-- Le drapeau "ce joueur porte quelque chose" ne vit PLUS ici. Il etait cense empecher les autres systemes de
	-- portage de se declencher par-dessus, mais personne ne le lisait : on pouvait porter le seau ET prendre
	-- l'echelle, la tondeuse, ou sortir un outil. Une seule reponse pour tout le monde, dans Modules/Utils/CarryUtils.

	-- ===== ANIMATIONS =====
	ANIM_FOLDER = { "Animations", "Tools", "Bin" },
	-- Geste de PRISE, joue une fois. Il cle les jambes, ce qui est acceptable pour un geste ponctuel : le
	-- joueur se fige un court instant.
	TAKE_ANIM = "TakeAnimation",
	-- Pose de PORTAGE, tenue tant qu'on porte. Elle ne cle QUE les bras et le torse (verifie) : une pose de
	-- maintien qui clerait les jambes ecraserait la marche, et le joueur glisserait au lieu de marcher.
	CARRY_ANIM = "IdleAnimation",
	-- Marqueur dans TAKE_ANIM (a 0.33s) : l'instant ou la main se referme. C'est LA qu'on soude, pas a
	-- l'appui -- sinon le seau saute dans la main avant que la main l'atteigne.
	TAKE_EVENT = "TakeBucketEvent",
	-- Marqueur de FIN, pose en bout de TAKE_ANIM : l'instant ou le geste s'efface pour DECOUVRIR la pose de
	-- portage, qui joue deja en dessous de lui.
	--
	-- C'EST L'ANIMATEUR QUI DECIDE : le deplacer dans l'editeur change la bascule, sans toucher au code. S'il se
	-- tait, la piste finit d'elle-meme et decouvre exactement la meme pose, juste un poil plus tard -- son echec
	-- est inoffensif, il n'y a aucun filet a prevoir.
	END_EVENT = "EndTakeEventBin",
	-- FILET, en secondes depuis le debut de TAKE_ANIM : demande la soudure si TAKE_EVENT se tait (asset pas
	-- encore charge a la 1re lecture de la session). Regle APRES le marqueur, donc sans effet tant qu'il parle.
	-- Sans lui, un marqueur muet voudrait dire que le seau ne se prend PAS DU TOUT.
	TAKE_GRAB_FALLBACK = 0.45,
	-- Fondus d'entree. Le geste arrive vite (c'est un geste), la pose de portage prend son temps (c'est un etat).
	TAKE_FADE = 0.1,
	CARRY_FADE = 0.15,

	-- ===== APPROCHE =====
	-- Le joueur MARCHE jusqu'au seau avant de le prendre, au lieu de tendre les bras a huit studs.
	--
	-- Pas de PathfindingService : quelques studs dans un jardin ouvert, `Humanoid:MoveTo` suffit. Un vrai chemin
	-- calcule serait plus fragile (bloque, sol irregulier, autre joueur) pour un gain nul a cette distance. Meme
	-- choix que la tondeuse. A revoir SI un jour un seau se prend derriere un obstacle.
	APPROACH_ENABLED = true,
	-- Distance a laquelle on s'arrete du seau. On s'arrete DU COTE D'OU L'ON VIENT : un seau se prend de
	-- n'importe quel bord, donc aucun contournement a faire -- contrairement au guidon d'une tondeuse, qui est
	-- derriere elle et qu'il faut aller chercher.
	APPROACH_STOP_DIST = 2.5,
	-- Deja a moins de ca du point d'arret : on ne fabrique AUCUN deplacement, on prend. Regle apprise sur
	-- l'echelle, ou tout un systeme de marche forcee avait ete construit pour un joueur deja arrive.
	APPROACH_SKIP_DIST = 1.2,
	-- Au-dela, on prend quand meme : mieux vaut une prise un peu de travers qu'un joueur bloque parce qu'un
	-- caillou lui barre le chemin.
	APPROACH_TIMEOUT = 2.5,

	-- ===== ORIENTATION A LA PRISE =====
	-- ON NE FABRIQUE AUCUN DEPLACEMENT : le joueur PIVOTE face au seau, il n'avance pas d'un stud. Une marche
	-- forcee avait ete codee pour l'echelle (priorite Camera, marqueurs, secours distance) puis SUPPRIMEE : le
	-- joueur etait deja arrive, tout ce systeme ne servait a rien. Meme conclusion ici.
	--
	-- Duree du pivot. Il doit finir AVANT TAKE_GRAB_FALLBACK et avant le marqueur, sinon la main se referme
	-- pendant que le corps tourne encore.
	FACE_TURN_TIME = 0.2,
	-- En dessous de cette distance horizontale, on ne pivote pas : la direction n'a plus de sens quand on est
	-- pile dessus, et le joueur ferait un demi-tour aleatoire.
	FACE_MIN_DIST = 0.5,
	-- Le joueur est FIGE pendant le geste. Sans ca il s'eloigne en plein mouvement et le pivot se bat contre ses
	-- touches. Ignore s'il est EN L'AIR : figer quelqu'un en plein saut se verrait bien plus que le probleme
	-- qu'on corrige.
	ANCHOR_DURING_TAKE = true,

	-- ===== GESTE DE REPOSE =====
	-- La repose joue TAKE_ANIM A L'ENVERS. On part de sa derniere image -- celle que la pose de portage tient
	-- deja, donc le raccord est invisible -- et on remonte le temps jusqu'a la position neutre.
	--
	-- Rejouer le geste A L'ENDROIT montrerait un RAMASSAGE alors qu'on lache : le bras descend vers le sol puis
	-- se referme, exactement le contraire de ce qui se passe.
	--
	-- Vitesse de ce retour. 1 = meme cadence qu'a la prise. Plus haut = on lache plus vite.
	--
	-- 1.8 : reposer a la meme cadence qu'on ramasse rendait la fin de geste molle. Ramasser est un EFFORT (on se
	-- baisse, on empoigne), reposer est un relachement -- ca doit claquer. Le seau quitte les mains en ~0.35 s au
	-- lieu de ~0.65 s, et la marche revient deux fois plus tot.
	--
	-- DEUX REGLAGES DEPENDENT DE CELUI-CI, ne pas le monter sans les redescendre : PLACE_STRAIGHTEN_TIME (le
	-- redressement doit finir AVANT que la main s'ouvre) et PLACE_SLOW_TIME (le bridage doit finir AVEC le geste,
	-- pas apres). Chacun dit ce qu'il attend a sa ligne.
	PLACE_SPEED = 1.8,
	-- On ne teste la fin du retour qu'apres ce delai : au tout premier passage TimePosition peut encore lire
	-- zero, alors qu'on vient tout juste d'y ecrire la derniere image.
	PLACE_SETTLE = 0.08,
	-- LE JOUEUR S'ARRETE PENDANT QU'IL POSE. Sans ca il repose son seau en pleine course et le geste glisse a
	-- cote de lui. Ce n'est pas un blocage : la vitesse DESCEND a zero, puis remonte.
	--
	-- Cadence PROPRE a ce geste, en studs/s par seconde. Les rythmes globaux de CharacterConfigs sont regles
	-- pour le travail de haie (arret en ~1 s) : beaucoup trop mou ici. A 60, l'arret prend moins de 0.2 s.
	PLACE_SLOW_RATE = 60,
	-- Duree du bridage. Volontairement INDEPENDANTE de la duree de l'animation : la vitesse revient toute seule
	-- au bout, meme si le geste a ete interrompu, donc aucun joueur ne peut rester coince au ralenti.
	--
	-- Descendue de 0.45 avec PLACE_SPEED : brider plus longtemps que le geste ne dure, c'est rendre les commandes
	-- a un joueur qu'on a fini de ralentir pour rien -- l'attente qu'on cherche justement a supprimer. Cale sur
	-- l'instant ou le seau quitte les mains (~0.35 s), pas sur la fin du geste : apres le lacher, plus rien ne
	-- justifie de le retenir.
	PLACE_SLOW_TIME = 0.35,
	-- FILET DUR, en secondes. Un marqueur muet laisserait le seau soude au joueur POUR TOUJOURS -- c'est le seul
	-- defaut de ce fichier qu'un joueur ne peut pas rattraper lui-meme. Il tourne sur son PROPRE minuteur, donc
	-- il survit meme si le geste est interrompu par une autre prise.
	PLACE_TIMEOUT = 3,

	-- ===== REPOSE =====
	-- ORIENTATION AU SOL. Le seau se repose EXACTEMENT comme on le tenait : on part du regard du joueur et on y
	-- rajoute le decalage de la prise (le quart de tour de CARRY_C0).
	--
	-- Sans ce rappel, aligner betement l'axe -Z du model sur le regard le ferait PIVOTER d'un coup au moment du
	-- lacher -- de tout l'angle que CARRY_C0 lui donne dans les mains. Rien ne garantit que le -Z d'un model
	-- soit son "devant" : ca vient du rig, pas du bon sens. On ne suppose donc aucun axe, on reprend l'angle
	-- qu'il a REELLEMENT a l'ecran.
	--
	-- Degres a AJOUTER si tu veux qu'il se pose autrement que comme tu le portes. 0 = pas de rotation.
	PLACE_YAW = 0,
	-- Le seau est porte DEVANT le torse, en l'air. Le reposer sur place le laisserait FLOTTER a hauteur de
	-- poitrine : il faut donc chercher le sol. Distance devant le joueur ou on le pose.
	PLACE_DISTANCE = 3,
	-- Le rayon part de cette hauteur au-dessus du point vise et descend de PLACE_RAY_DEPTH. Partir d'en haut
	-- evite de demarrer DANS une marche ou un muret et de le traverser.
	PLACE_RAY_HEIGHT = 6,
	PLACE_RAY_DEPTH = 24,

	-- IL SE REDRESSE DANS LES MAINS, avant meme de partir. Le seau est TENU PENCHE -- c'est CARRY_C0 qui lui
	-- donne cet angle. On l'amene a plat PENDANT le geste de repose, donc il est deja droit quand il quitte les
	-- bras, et il ne lui reste plus qu'a descendre.
	--
	-- Le compte demarre a l'appui (phase "placeStart"). La main s'ouvre au marqueur TakeBucketEvent, place a
	-- 0.57 s dans l'animation et donc atteint en marche arriere au bout de (duree - 0.57) / PLACE_SPEED --
	-- environ 0.35 s a la vitesse actuelle. CETTE VALEUR DOIT RESTER SOUS CE DELAI : au-dela, le seau est encore
	-- penche quand il quitte les mains et se redresse tout seul en l'air, ce qui est exactement l'effet de
	-- correction apres coup qu'on cherchait a supprimer. Elle a donc ete divisee en meme temps que PLACE_SPEED a
	-- ete multipliee. 0 desactive le redressement -- le seau partira penche, comme avant la version 0.0.429.
	PLACE_STRAIGHTEN_TIME = 0.25,

	-- IL GLISSE JUSQU'AU SOL, il ne s'y teleporte pas. On MEMORISE la position et l'orientation qu'il a DANS LES
	-- MAINS -- celles que l'animation lui donne -- et on l'anime jusqu'a sa pose finale au sol.
	--
	-- Sans ce trajet, le seau saute d'un coup a plat pendant que le geste de repose joue encore : le personnage
	-- se penche vers un objet qui n'est deja plus la. Duree en secondes, 0 pour retrouver le saut instantane.
	PLACE_TWEEN_TIME = 0.22,
	-- DUREE SEPAREE POUR LA ROTATION, et il en faut une. Une seule duree pour les deux laisse le seau DE BIAIS
	-- pendant tout le trajet : il ne se redresse qu'a la toute fin, donc on le voit pencher tout du long.
	--
	-- On veut l'inverse : il se REDRESSE TOUT DE SUITE, et il ne lui reste plus qu'a descendre. Garder cette
	-- valeur nettement plus courte que PLACE_TWEEN_TIME.
	--
	-- A 0.001 le redressement tient dans la premiere image : le seau est deja droit quand il commence a
	-- descendre. C'est le reglage voulu -- on ne veut PAS voir la rotation, seulement la descente.
	PLACE_TWEEN_ROT_TIME = 0.001,
	-- DE COMBIEN LA POUSSIERE PREND DE L'AVANCE sur l'arrivee au sol, en secondes.
	--
	-- Elle partait a l'instant EXACT du contact, et ca se voit en retard : une bouffee de particules met le temps
	-- de naitre et de s'ecarter, donc le nuage n'existe vraiment qu'apres. Les faire partir un peu avant les rend
	-- deja ouvertes quand le seau touche -- c'est le nuage qu'on regarde, pas l'instant de l'emission.
	--
	-- Comptee DEPUIS LA FIN du trajet, pas depuis son debut : rallonger PLACE_TWEEN_TIME ne decale donc rien.
	-- Plus grande que le trajet, elle part au tout debut -- jamais avant le lacher.
	PLACE_FX_LEAD = 0.2,

	-- ANCRE UNE FOIS POSE. Le seau est DESANCRE pour etre porte (une part ancree ignore sa soudure). A la
	-- repose, on lui rendait son etat d'origine -- et s'il etait LIBRE dans Studio, la physique reprend la main
	-- juste apres : il glisse, il bascule, il finit DE TRAVERS. Le calcul de pose est pourtant juste, mais on ne
	-- voit que le resultat apres que la physique l'a bouge.
	--
	-- Mettre false pour le laisser libre (il roulera, tombera des pentes) : c'est un choix de gameplay, pas un
	-- reglage a l'aveugle.
	PLACE_ANCHOR = true,

	-- ===== DIVERS =====
	-- TRACE DE MISE AU POINT. Imprime toutes les DEBUG_INTERVAL secondes ce que la detection VOIT reellement :
	-- combien de seaux, lequel est le plus proche, et ce qui bloque. A remettre a false une fois le portage
	-- regle -- un log par seconde finit par masquer les vrais messages.
	DEBUG = false,
	DEBUG_INTERVAL = 2,
	-- Le Highlight du seau (contour) sert a le reperer AU SOL. Soude au joueur il brillerait en permanence
	-- pendant tout le portage. Mettre false pour le laisser allume.
	HIDE_HIGHLIGHT_WHEN_CARRIED = true,
}
