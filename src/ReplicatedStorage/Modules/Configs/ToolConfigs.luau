--!strict
-- Data pure des outils. Aucune logique ici : ToolService lit cette table, elle ne fait rien toute seule.
--
-- VOLONTAIREMENT MINIMAL. La sequence de demarrage du moteur a ete retiree : elle marchait, mais elle avait
-- pris trop d'avance sur le reste. On la remettra couche par couche, une fois celle-ci solide.

export type ToolConfig = {
	-- Nom du modele dans ReplicatedStorage.Assets.Tools
	assetName: string,
	-- Part du personnage qui tient l'outil. R15 uniquement.
	handPart: string,
	-- Main qui prend l'outil pendant le demarrage : on cale le carter d'une main et on tire la corde de
	-- l'autre. Le passage se fait sur un MARQUEUR d'animation, jamais sur un delai.
	offHandPart: string,
	offHandAttachment: string,
	offHandGripOffset: CFrame,
	offHandDelay: number,
	-- Part de l'outil accrochee a la main.
	handleName: string,
	-- Poignee du lanceur. Pendant le demarrage elle quitte l'outil pour suivre la main qui tire, et le Beam
	-- tendu entre A0Launcher et A1Launcher s'etire tout seul : on ne dessine pas la corde, on deplace ses deux
	-- bouts. nil = l'outil n'a pas de lanceur (une cisaille, par exemple).
	-- Le Motor6D qui la pilote porte le MEME nom que la part, et vit dans le Handle.
	launcherPartName: string?,
	launcherAttachment: string,
	launcherGripOffset: CFrame,
	-- Attachment posee dans le Handle, qui definit OU et COMMENT la main tient l'outil.
	-- Un Motor6D place la piece ainsi : Handle.CFrame = Hand.CFrame * C0 * C1:Inverse()
	-- Avec C1 = cette Attachment, elle vient se coller sur le point de prise de la main, axes alignes.
	-- Autrement dit l'orientation de l'outil dans la main EST celle de l'Attachment.
	gripAttachment: string,
	-- Correction d'orientation appliquee par-dessus. CFrame.Angles attend des RADIANS : toujours math.rad.
	gripOffset: CFrame,
	-- Effet joue a l'apparition, dans ReplicatedStorage.Assets.Effects. nil = pas d'effet.
	spawnEffect: string?,
	-- Nombre de particules emises. Surchargeable emetteur par emetteur avec un attribut "EmitCount" pose
	-- directement sur le ParticleEmitter dans Studio : une onde de choc veut 1, des braises en veulent 20.
	emitCount: number,
	-- Dossier dans ReplicatedStorage.Animations.Player.Tools.
	animationFolder: string,
	-- Pose tenue tant que l'outil est en main, moteur ETEINT. nil = le joueur garde son idle normal.
	holdAnimation: string?,
	-- Pose tenue moteur ALLUME. Remplace holdAnimation au demarrage : on ne tient pas un outil qui vibre comme
	-- un outil mort. nil = on garde holdAnimation.
	runHoldAnimation: string?,
	-- MISE EN POSITION, jouee en entier au clic : le joueur cale l'outil et saisit la corde.
	prepareAnimation: string?,
	-- Animation de tirage. Elle sert a DEUX choses avec la meme piste :
	--   figee a sa premiere frame -> la posture "pret a tirer"
	--   jouee a vitesse normale    -> le tirage lui-meme
	-- C'est la meme piste du cache, on ne fait que changer sa vitesse. Le joueur passe donc de la posture au
	-- geste sans aucune transition a fondre : il repart exactement d'ou il etait.
	pullAnimation: string?,
	-- Animations jouees sur l'Animator de l'OUTIL, pas sur celui du joueur : ce sont ses propres Motor6D
	-- (Lame1, Lame2, Motor) qu'elles bougent. Elles servent a l'a-coup du moteur pendant un tirage, et plus
	-- tard au fonctionnement continu.
	toolRunAnimations: { string },
	-- Duree de l'a-coup. C'est ce qui fait qu'on VOIT la machine essayer : sans consequence a l'ecran, un
	-- tirage n'est qu'un clic. Trop long, ca ressemble a un demarrage reussi puis un calage.
	sputterDuration: number,
	-- Secousse camera a la butee de la corde. En studs : c'est un DEPLACEMENT, pas un pourcentage.
	-- Tres leger volontairement. Une secousse qu'on remarque est une secousse trop forte : elle doit se sentir
	-- sans se voir, sinon elle fatigue au bout de trois tirages.
	pullShakeIntensity: number,
	pullShakeDuration: number,
	-- Pincement de champ de vision, en degres. Negatif = la vue se resserre, ce qui donne une impression de
	-- concentration et d'effort. Positif ferait l'inverse, un elargissement de soulagement.
	pullFovPunch: number,
	-- Chemin du dossier de sons DANS SoundService. En liste plutot qu'en chaine : un outil sans moteur n'ira
	-- pas se ranger dans "Engins", et ce champ suit sans qu'on touche au code.
	soundFolder: { string },
	-- Son du tirage. Joue depuis le Handle, donc spatialise : les autres joueurs l'entendent d'ou tu es.
	pullSound: string?,
	-- Son du moteur qui part enfin.
	startSound: string?,
	-- Ronronnement du moteur en marche, joue en BOUCLE. Il demarre apres le son de lancement, qui continue de
	-- jouer par-dessus : le "vroum" se superpose au regime etabli, comme dans la realite.
	runSound: string?,
	-- Accelerateur des lames, une fois le moteur en marche. La vitesse de l'animation monte quand le joueur
	-- maintient le clic, redescend au relachement. C'est le debut de la coupe : lame lente = ralenti, lame
	-- rapide = ca taille.
	bladeIdleSpeed: number, -- vitesse au repos, moteur allume mais joueur passif
	bladeMaxSpeed: number, -- vitesse a fond, clic maintenu
	bladeAccel: number, -- gain de vitesse par seconde en montee (progressif = petit)
	bladeDecel: number, -- perte de vitesse par seconde au relachement
	-- Nombre de tirages avant que le moteur demarre. C'est une CARACTERISTIQUE de l'outil, pas une constante
	-- du jeu : un outil pourri en demandera 4, un outil pro partira au premier. Le joueur ressentira son
	-- upgrade dans ses mains au lieu de le lire dans un menu.
	pullsToStart: number,
	-- Roblox joue la marche en "Movement" : en dessous, la pose disparait des que le joueur avance.
	-- En "Action" elle passe au-dessus. Attention, elle ecrase aussi les jambes si elle les cle : une pose de
	-- maintien ne doit cler que les bras et le torse.
	holdPriority: Enum.AnimationPriority,
}

local ToolConfigs: { [string]: ToolConfig } = {
	HedgeTrimmer = {
		assetName = "HedgeTrimmer",
		handPart = "RightHand",
		offHandPart = "LeftHand",
		-- Attachment DEDIEE au demarrage, a creer dans le Handle. On ne reutilise pas GripLeft : la prise de
		-- port et la prise de demarrage n'ont aucune raison d'etre la meme, et une Attachment se tourne a la
		-- souris avec un retour visuel immediat, contrairement a trois angles dans un fichier.
		offHandAttachment = "GripStart",
		-- Delai entre le marqueur et le changement de main effectif.
		--
		-- L'animation est jouee cote SERVEUR puis repliquee : le marqueur part quand la lecture du serveur
		-- atteint sa frame, mais le client a quelques frames de retard sur cette lecture. Sans ce decalage, la
		-- main change avant que l'image du joueur ait atteint le geste.
		--
		-- Le marqueur reste ce qui DECLENCHE ; ce delai ne rattrape que la latence de replication. C'est pour
		-- ca qu'il est petit et qu'il n'a pas a suivre les retouches de l'animation.
		offHandDelay = 0.01,
		-- Orientation de l'outil dans la main gauche pendant le demarrage. En DEGRES : math.rad convertit, donc
		-- on tape des degres et on obtient ce qu'on croit taper. Un nombre nu serait interprete en radians.
		--   X = bascule avant / arriere    Y = rotation autour du manche    Z = inclinaison laterale
		-- Par pas de 45 degres au debut pour trouver le bon axe, puis par 10 pour affiner.
		offHandGripOffset = CFrame.Angles(math.rad(-50), math.rad(162), math.rad(80)),
		handleName = "Handle",
		launcherPartName = "Launcher",
		-- Le bout de corde, deja pose sur la poignee : c'est exactement la que la main l'attrape.
		launcherAttachment = "A1Launcher",
		-- A REGLER a l'oeil, meme convention que les autres : en degres, via math.rad.
		launcherGripOffset = CFrame.Angles(math.rad(0), math.rad(0), math.rad(0)),
		gripAttachment = "GripLeft",
		-- Meme convention : en degres, via math.rad.
		gripOffset = CFrame.Angles(math.rad(100), math.rad(0), math.rad(0)),
		spawnEffect = "SpawnToolHand",
		emitCount = 4,
		animationFolder = "HedgeTrimmer",
		holdAnimation = "IdleAnimation",
		runHoldAnimation = "ReadyToCutAnimation",
		prepareAnimation = "PrepareToLaunchAnimation",
		pullAnimation = "TryLaunchAnimation",
		toolRunAnimations = { "MotorActionAnimation", "LameActionAnimation" },
		sputterDuration = 0.35,
		pullShakeIntensity = 0.06,
		pullShakeDuration = 0.2,
		pullFovPunch = -1.5,
		soundFolder = { "Sounds", "Engins", "HedgeTrimmer" },
		pullSound = "TryLaunchSound",
		startSound = "StartFirstSound",
		runSound = "IdleSound",
		bladeIdleSpeed = 0.35,
		bladeMaxSpeed = 1.6,
		bladeAccel = 1.6,
		bladeDecel = 2.8,
		pullsToStart = 3,
		holdPriority = Enum.AnimationPriority.Action,
	},
}

return ToolConfigs
