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
	-- Part fixe de reference. JAMAIS GetPivot : le pivot d'un Model suit sa bounding box, donc ajouter la
	-- moindre part enfant le decale et tous les calculs partent de travers. On prend la PrimaryPart, sinon
	-- un enfant portant ce nom.
	ROOT_NAME = "RootPart",

	-- ===== PRISE =====
	-- Part du PERSONNAGE a laquelle le seau est soude. MESUREE sur le rig d'animation (VerifierBin.lua), pas
	-- devinee : le jeu doit rejouer EXACTEMENT le joint qui a servi a animer, sinon le seau est de travers en
	-- jeu alors que l'animation est bonne -- et on cherche l'erreur dans l'animation.
	--
	-- UpperTorso et non RightHand : le seau est porte DEVANT LE CORPS, il ne suit donc pas le bras. Pour qu'il
	-- pende au bout du bras, refaire l'attache du rig sur RightHand (AttacherObjetAuRig.lua) et reporter ici
	-- le nouveau C0 -- les deux valeurs vont ENSEMBLE, changer l'une sans l'autre donne n'importe quoi.
	JOINT_PARENT = "UpperTorso",
	-- Position et angle du seau vus depuis JOINT_PARENT. Valeur relevee sur le rig. Z negatif = devant le
	-- torse. Monter Z (vers 0) le rapproche du corps, baisser Y le fait descendre vers les jambes.
	CARRY_C0 = CFrame.new(0, 0, -2.6) * CFrame.Angles(0, math.rad(90), 0),
	-- Nom du joint cree. Sert aussi a le RETROUVER pour le detruire a la repose : un joint orphelin laisserait
	-- le seau colle au joueur pour toujours.
	JOINT_NAME = "BinCarryJoint",
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
	PROMPT_LABEL = "PRENDRE",
	PROMPT_TITLE = "SEAU",
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
	CARRIED_ATTRIBUTE = "LeafiaBinCarriedBy",
	-- Pose sur le PERSONNAGE pendant le portage. Lu par les autres systemes de portage (echelle, tondeuse)
	-- pour ne pas se declencher par-dessus : on ne porte qu'UNE chose a la fois.
	CARRYING_ATTRIBUTE = "LeafiaCarryingBin",

	-- ===== ANIMATIONS =====
	ANIM_FOLDER = { "Animations", "Player", "Tools", "Bin" },
	-- Geste de PRISE, joue une fois. Il cle les jambes, ce qui est acceptable pour un geste ponctuel : le
	-- joueur se fige un court instant. Mettre "TakeTestAnimation" ici pour essayer l'autre version.
	TAKE_ANIM = "TakeAnimation",
	-- Pose de PORTAGE, tenue tant qu'on porte. Elle ne cle QUE les bras et le torse (verifie) : une pose de
	-- maintien qui clerait les jambes ecraserait la marche, et le joueur glisserait au lieu de marcher.
	CARRY_ANIM = "IdleAnimation",
	-- Marqueur dans TAKE_ANIM (a 0.33s) : l'instant ou la main se referme. C'est LA qu'on soude, pas a
	-- l'appui -- sinon le seau saute dans la main avant que la main l'atteigne.
	TAKE_EVENT = "TakeBucketEvent",
	-- FILET DE SECURITE, en secondes depuis le debut de TAKE_ANIM. Le geste de prise avance son temps A LA MAIN
	-- (voir TAKE_ANIM ci-dessus et le controller) pour pouvoir TENIR sa derniere image : rien ne garantit qu'un
	-- marqueur tire encore quand c'est nous qui ecrivons TimePosition. Regle un peu APRES le marqueur, pour que
	-- le marqueur reste le declencheur normal et que ceci ne serve que s'il se tait.
	TAKE_GRAB_FALLBACK = 0.45,
	-- Fondus d'entree. Le geste arrive vite (c'est un geste), la pose de portage prend son temps (c'est un etat).
	TAKE_FADE = 0.1,
	CARRY_FADE = 0.15,
	-- Secondes avant d'abandonner l'attente d'une animation dont la duree reste a zero (asset jamais charge).
	-- Sans ce plafond le joueur resterait sans pose de portage, sans la moindre erreur pour le dire.
	TAKE_LOAD_TIMEOUT = 2,

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

	-- ===== REPOSE =====
	-- Le seau est porte DEVANT le torse, en l'air. Le reposer sur place le laisserait FLOTTER a hauteur de
	-- poitrine : il faut donc chercher le sol. Distance devant le joueur ou on le pose.
	PLACE_DISTANCE = 3,
	-- Le rayon part de cette hauteur au-dessus du point vise et descend de PLACE_RAY_DEPTH. Partir d'en haut
	-- evite de demarrer DANS une marche ou un muret et de le traverser.
	PLACE_RAY_HEIGHT = 6,
	PLACE_RAY_DEPTH = 24,

	-- ===== DIVERS =====
	-- TRACE DE MISE AU POINT. Imprime toutes les DEBUG_INTERVAL secondes ce que la detection VOIT reellement :
	-- combien de seaux, lequel est le plus proche, et ce qui bloque. A remettre a false une fois le portage
	-- regle -- un log par seconde finit par masquer les vrais messages.
	DEBUG = true,
	DEBUG_INTERVAL = 2,
	-- Le Highlight du seau (contour) sert a le reperer AU SOL. Soude au joueur il brillerait en permanence
	-- pendant tout le portage. Mettre false pour le laisser allume.
	HIDE_HIGHLIGHT_WHEN_CARRIED = true,
}
