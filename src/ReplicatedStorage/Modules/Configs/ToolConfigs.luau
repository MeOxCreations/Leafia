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
	-- REACTION DE COUPLE. L'outil s'incline dans la main a mesure que le moteur monte en regime, comme s'il
	-- tirait. Sans ca le moteur monte en puissance sans qu'on le SENTE dans les mains.
	-- Axe de l'inclinaison, dans le repere de l'OUTIL AU REPOS (la prise est deja appliquee, voir setGripTilt).
	--
	-- NE PAS chercher a deviner lequel fait quoi. La prise de coupe tourne le repere de -50 / 162 / 80 degres :
	-- X, Y et Z ne pointent donc plus du tout dans les directions qu'on imagine. Les essayer un par un coute
	-- trois essais, les deduire coute une soiree.
	--   Vector3.xAxis / yAxis / zAxis  -> les trois axes purs
	--   (Vector3.yAxis + Vector3.zAxis).Unit -> une diagonale, si aucun pur ne donne le bon geste
	-- L'axe doit etre UNITAIRE : fromAxisAngle tourne autour de sa direction, une longueur differente de 1
	-- fausserait l'angle.
	tiltAxis: Vector3,
	tiltMaxAngle: number, -- en degres, atteint a plein regime
	-- Vitesse a laquelle l'inclinaison rejoint sa cible, par seconde. Plus haut = coup de poignet plus sec.
	--
	-- L'inclinaison a son PROPRE rythme, plus celui des lames. Les lames montent lentement parce que c'est une
	-- masse qui prend son elan, et le son est cale dessus. La reaction de couple, elle, est immediate : c'est
	-- le poignet qui encaisse, pas un volant d'inertie. Les caler ensemble rendait le geste mou.
	-- Contrepartie assumee : a mi-regime, inclinaison et vitesse de lame ne correspondent plus exactement.
	tiltFollowSpeed: number,
	-- TREMBLEMENT a plein regime : l'outil bat autour de `tiltAxis`, alternativement dans un sens et dans
	-- l'autre. C'est ce qui dit "la machine force" une fois l'accelerateur a fond.
	vibeMaxAngle: number, -- en degres, de part et d'autre de l'inclinaison
	-- En hertz. PLAFOND REEL vers 15 : l'inclinaison est calculee cote serveur puis repliquee, et au-dela la
	-- replication ne suit plus. On n'obtient pas un tremblement plus rapide, on obtient du bruit.
	-- Pour monter vraiment plus haut il faudrait calculer le tremblement chez chaque client.
	vibeFrequency: number,
	-- Part du regime a partir de laquelle le tremblement apparait. Present des le ralenti, il se lirait comme
	-- un defaut d'affichage ; reserve au haut du regime, il se lit comme un effort.
	vibeStart: number,
	-- Vitesse d'ouverture et de fermeture du tremblement, par seconde. Il s'ETEINT au pied d'une haie : la
	-- machine qui force pour rien n'a plus lieu d'etre quand la lame mord dans quelque chose, et un tremblement
	-- pendant un geste de precision brouille la lecture.
	-- En fondu et non net : couper un sinus a 13 Hz laisserait l'outil fige sur un angle quelconque.
	vibeGateSpeed: number,
	-- Part de l'inclinaison conservee AU PIED D'UNE HAIE. 1 = inchangee, 0 = plus d'inclinaison du tout.
	--
	-- Hors chantier, l'inclinaison est une reaction de couple : l'outil tire dans la main, c'est ce qui fait
	-- sentir le moteur. Devant une haie elle devient un probleme : elle fait pivoter la LAME de 10 degres, soit
	-- 0.7 stud au bout, et la lame entre dans la haie. Aucune animation ne peut corriger ca, l'angle de l'outil
	-- dans la main vient du Motor6D.
	-- On la reduit au lieu de la supprimer : a zero, accelerer ne se sentirait plus du tout la ou le joueur
	-- passe le plus de temps.
	-- Passe par le meme fondu que le tremblement, donc pas de saut en arrivant sur la haie.
	tiltWorkingScale: number,
	-- Part qui donne l'EMPRISE de la lame. Posee a la main dans l'outil, solidaire du manche.
	--
	-- Seule sa TAILLE est lue, jamais sa position. Sa position cote serveur est fausse : elle suit les bras,
	-- donc une animation jouee chez le client et que le serveur ne voit pas defiler. Sa taille, elle, ne
	-- s'anime pas : c'est une donnee fiable, et elle evite de recopier a la main des dimensions qu'on a deja
	-- reglees a l'oeil dans Studio.
	hitboxName: string,
	bladeIdleSpeed: number, -- vitesse au repos, moteur allume mais joueur passif
	bladeMaxSpeed: number, -- vitesse a fond, clic maintenu
	bladeAccel: number, -- gain de vitesse par seconde en montee (progressif = petit)
	bladeDecel: number, -- perte de vitesse par seconde au relachement
	-- SON DU MOTEUR : une enveloppe en deux temps, pas un pitch qu'on tire.
	--   accelStartSound : l'ATTAQUE, la montee en regime. Jouee une fois, non bouclee.
	--   accelLoopSound  : le MAINTIEN, enchaine des que l'attaque se termine, en boucle tant qu'on pousse.
	-- Les deux bout a bout dessinent la courbe d'acceleration. C'est le son qui porte la courbe, donc on ne
	-- touche PAS a PlaybackSpeed : ca doublerait l'effet et sonnerait faux.
	accelStartSound: string?,
	accelLoopSound: string?,
	-- Duree du fondu quand on RELACHE. Un moteur ne se coupe pas net : il redescend. Couper sec s'entend comme
	-- un bug, meme quand tout le reste est bon.
	engineReleaseFade: number,
	-- Hauteur atteinte par le son sortant pendant ce fondu. En dessous de 1, on entend le regime RETOMBER au
	-- lieu d'un simple baisser de volume.
	engineWindDownPitch: number,
	-- Fondu du ralenti quand on ACCELERE. Court : l'attaque doit mordre tout de suite.
	engineAccelFade: number,
	-- Nombre de tirages avant que le moteur demarre, TIRE AU HASARD entre ces deux bornes a chaque demarrage.
	--
	-- C'est un vrai moteur deux-temps : il ne part pas toujours au meme coup. Cette incertitude fait le geste,
	-- exactement comme une tondeuse qui tousse une ou deux fois avant de prendre. min == max = nombre fixe.
	--
	-- Reste une CARACTERISTIQUE de l'outil, pas une constante du jeu : un outil pourri aura une fourchette
	-- haute (2 a 4), un outil pro partira souvent au premier (1 a 2). Le joueur sentira son upgrade dans ses
	-- mains au lieu de le lire dans un menu.
	pullsMin: number,
	pullsMax: number,
	-- Roblox joue la marche en "Movement" : en dessous, la pose disparait des que le joueur avance.
	-- En "Action" elle passe au-dessus. Attention, elle ecrase aussi les jambes si elle les cle : une pose de
	-- maintien ne doit cler que les bras et le torse.
	holdPriority: Enum.AnimationPriority,
	-- Orientation de l'outil dans la main une fois le MOTEUR LANCE. Meme main que le demarrage, autre angle.
	--
	-- Tirer une corde et tailler une haie ne sont pas le meme geste : il n'y a aucune raison que l'outil soit
	-- tenu pareil. Sans cet angle dedie, la prise de demarrage restait en place pendant toute la coupe et
	-- l'outil pointait vers le ciel. Aucune animation ne peut corriger ca : l'angle de l'outil DANS la main
	-- vient du Motor6D, pas des bras.
	cutGripOffset: CFrame,
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
		-- Le troisieme essai. X et Y donnaient le mauvais geste, il ne restait que celui-la.
		tiltAxis = Vector3.zAxis,
		tiltMaxAngle = 10,
		tiltFollowSpeed = 14,
		vibeMaxAngle = 1.4,
		vibeFrequency = 13,
		vibeStart = 0.8,
		vibeGateSpeed = 9,
		-- ZERO. Devant une haie l'outil ne bouge plus DU TOUT a l'accelerateur : au moment de tailler, la
		-- position de la lame doit dependre de la visee et de rien d'autre. Un outil qui bouge tout seul pendant
		-- un geste de precision se ressent comme une perte de controle, meme quand c'est joli.
		-- L'inclinaison reste entiere hors chantier, la ou elle sert a faire sentir le moteur.
		tiltWorkingScale = 0,
		hitboxName = "HitBoxRoot",
		bladeIdleSpeed = 0.35,
		bladeMaxSpeed = 1.6,
		bladeAccel = 1.6,
		bladeDecel = 2.8,
		accelStartSound = "SpeedStartMotor",
		accelLoopSound = "SpeedStartMotorInfinite",
		engineReleaseFade = 0.7,
		-- Descend plus bas qu'avant : c'est l'ECART de hauteur qui s'entend comme une deceleration. A 0.7 le
		-- moteur avait surtout l'air de baisser le volume.
		engineWindDownPitch = 0.5,
		engineAccelFade = 0.12,
		pullsMin = 1,
		pullsMax = 3,
		holdPriority = Enum.AnimationPriority.Action,
		-- A REGLER A L'OEIL, comme les autres prises. Part de la prise de demarrage : tant qu'on n'y touche
		-- pas, rien ne change par rapport a avant.
		--   X = bascule avant / arriere    Y = rotation autour du manche    Z = inclinaison laterale
		-- Par pas de 45 degres pour trouver le bon axe, puis par 10 pour affiner.
		cutGripOffset = CFrame.Angles(math.rad(-50), math.rad(162), math.rad(80)),
	},
}

return ToolConfigs
