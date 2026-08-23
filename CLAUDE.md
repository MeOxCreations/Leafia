# Leafia — Conventions & comportement assistant

## Le jeu en une phrase

Le joueur est **paysagiste**. Il va chez des clients, **tond leur pelouse**, taille leurs haies, repart avec un
cheque, et fait grandir son entreprise — seul ou en CO-OP.

## LA REGLE D'OR DE CE PROJET

**Le geste de TONDRE doit etre jouissif AVANT qu'on code quoi que ce soit d'autre.**

La TONTE est le geste central du jeu. C'est par elle que le joueur commence, c'est elle qu'il repetera le plus, et
c'est elle qui doit donner envie de faire un deuxieme jardin. La taille de haie reste dans le jeu, mais comme
**chantier SECONDAIRE** : un autre outil, une autre mission, pas le coeur.

Pas d'UI, pas de tycoon, pas de coop, pas de monetisation, pas de sauvegarde tant que passer la tondeuse et voir la
pelouse devenir nette ne donne pas envie d'en tondre une deuxieme.

Cette regle vient de deux echecs reels (Bird Game, League Of BattleCar). Dans les deux cas le meme motif : un
probleme au coeur du jeu, recouvert par des interfaces de plus en plus soignees, et une retention au sol. Les
interfaces etaient belles. Elles n'ont jamais rien repare.

**Si l'assistant voit qu'on ajoute une feature alors que le coeur n'est pas valide, il doit le dire.**

Corollaire : le test n'est pas "est-ce que ca marche" mais "est-ce que trois personnes reelles en tondent une
deuxieme sans qu'on leur demande". Tant que la reponse est non, on ne construit pas par-dessus.

Note de bascule (20/08/2026) : la regle visait la TAILLE jusqu'ici. Le joueur a tranche que la tonte passe devant.
Consequence directe : le systeme d'herbe de zone (touffes qui s'ecrasent et RESTENT couchees) n'est plus de
l'habillage, c'est le substrat du geste central.

## Comportement assistant

- Je suis francais.
- Je vis aux Sables-d'Olonne (Vendee, France) : **toujours raisonner sur mon heure locale** (fuseau France,
  UTC+2 en ete / UTC+1 en hiver), jamais sur l'heure du systeme ou celle des logs. Ne pas supposer qu'il fait
  nuit / que je vais dormir. Dans le doute, demander plutot que deviner.
- Tutoyer, ton decontracte (pote), utiliser « mec » quand ca sonne naturel.
- Reponses directes : si une idee est mauvaise ou risquee, le dire sans tourner autour du pot.
- **Ne jamais me flatter pour me faire plaisir.** Si un chiffre est mauvais, le dire. Si une feature ne sert a
  rien, le dire. Sur le projet precedent, les encouragements ont coute des mois.
- Pas d'emojis dans le code ni dans les commentaires proposes.
- Phrases courtes, simples et precises. Pas de tournures complexes.
- Expliquer comme a un eleve debutant : fluide, etape par etape, sans jargon inutile (ou definir le mot en une
  phrase).
- Priorite au pratique : exemples concrets a copier-coller, puis une mini-variante a tester.

## Workflow

- Avant un gros changement : plan court (3+ etapes). Si ca part en vrille : stop, re-planifier.
- Decoupage : 1 ModuleScript = 1 responsabilite claire.
- Apres un bug : noter en une phrase le pattern d'erreur (pour ne pas le refaire).
- Tests : Play Solo **et** serveur local avec **au moins 2 joueurs** quand la logique est reseau / UI joueur.
- Corrections **ciblees** : cause racine, pas pansement de surface. Eviter de reecrire un module entier sans
  necessite.
- Avant de modifier : **identifier les modules lies** et les consulter en priorite.
- Toujours donner le **chemin exact** du fichier a toucher.
- Fournir le **code complet du fichier** (ou du bloc coherent) pret a coller quand le projet n'est pas ouvert.
- Nouveau fichier ou dossier : **proposer l'emplacement** dans l'arborescence et **justifier** le choix.
- API Roblox / Luau : en cas de doute (depreciation, nouveau service, comportement edge), **le signaler** et
  renvoyer vers la doc officielle (create.roblox.com/docs). Ne jamais inventer une API.
- **Verifier avant d'affirmer.** Ne pas dire "cette fonction n'est pas utilisee" sans avoir grep le projet
  entier. Une affirmation fausse coute plus cher qu'une verification lente.

## Git & collaboration

Le projet est partage : un collaborateur tire le code depuis GitHub. Il doit toujours pouvoir recuperer une
version qui TOURNE, sans avoir a demander.

- **Des qu'un bloc coherent est fini, je commit ET je push sur `main`, sans qu'on me le demande.**
- « Fini » = la feature ou le fix est complet et le jeu se lance. Pas un fichier a moitie modifie, pas un
  module qui appelle une fonction pas encore ecrite.
- **Jamais de push au milieu d'un chantier.** Un etat intermediaire casse coute plus cher au collaborateur que
  pas de push du tout : il debug un travail en cours au lieu du sien.
- Ordre exact : **commit -> `git pull --rebase origin main` -> push**. Le rebase REFUSE de tourner avec des
  fichiers non commites (« cannot pull with rebase: You have unstaged changes ») : rebaser d'abord ne marche
  pas. En cas de conflit ou de push refuse : **stop, me le dire**. Jamais de `--force`.
- Message de commit court, en francais, qui dit ce que ca change **pour le joueur**, pas quels fichiers ont
  bouge.
- Mise a jour du `CHANGELOG.md` dans le **meme** commit que la feature.
- **Un push ne transporte QUE le code de `src/`.** Rojo ne synchronise ni le Workspace/map, ni les assets en
  `$ignoreUnknownInstances` (Assets, Animations, ScreenGui de StarterGui). Quand un changement depend d'un
  asset ou d'un objet pose dans Studio, le DIRE dans le message de commit et me le rappeler : sinon le
  collaborateur croit avoir la bonne version et il ne l'a pas.

### Rojo ECRASE Studio avec le disque LOCAL

Rojo ne fusionne rien. Quand quelqu'un connecte son `rojo serve`, Studio recoit SA version de `src/`, celle de
son disque, et elle REMPLACE ce qui etait la. Le dernier qui connecte gagne. Si son depot est en retard, tout
le code recent disparait de la session Studio, sans erreur et sans avertissement : le bouton « Accepter » du
plugin est exactement ce qui l'applique.

- **Ordre obligatoire, pour tout le monde : `git pull --rebase origin main` PUIS `rojo serve`.** Jamais
  l'inverse.
- **Lire le diff que le plugin affiche avant d'accepter.** S'il propose de SUPPRIMER des fichiers recents,
  c'est le signal qu'on est en retard : refuser, pull, reconnecter.
- **Ne jamais publier la place juste apres avoir connecte Rojo sans avoir pull.** Tant que ca reste une
  session Studio, une reconnexion a jour repare tout. Publie, l'ancien code part chez les joueurs et il faut
  republier.
- Seul `src/` est touche : la map, les Assets et les Animations ne bougent pas (voir la regle du push
  ci-dessus). Symptome typique : le CODE revient en arriere alors que la MAP reste bonne.

### Deux personnes sur le projet

Par defaut, l'assistant parle a **Meox**, le proprietaire du depot. Le collaborateur se declare en ecrivant une
ligne dans un fichier que son assistant lit au demarrage -- soit `CLAUDE.local.md` a la racine du depot (ignore
par git, donc personnel a sa machine), soit sa memoire perso `~/.claude/CLAUDE.md` :

    Je suis LE COLLABORATEUR de Leafia, pas Meox.

Si rien ne se charge chez lui, qu'il le dise simplement en une phrase au debut de sa session : le but est que
son assistant sache quel role suivre, pas qu'un fichier precis existe.

Ce que ca change pour son assistant :

- **Commencer chaque session par `git pull --rebase origin main`**, avant de lire du code et avant de lancer
  Rojo. La reference est ce qui est sur GitHub, pas ce qui traine sur son disque.
- **Ne jamais raisonner sur un fichier local sans avoir pull d'abord.** Un fichier en retard se lit comme du
  code valide : rien ne signale qu'il est perime.
- Meme regle de push que Meox : commit -> `git pull --rebase origin main` -> push, jamais de `--force`.
- Meme `CHANGELOG.md` : lire le dernier numero REEL **apres** le pull et prendre le suivant. En cas de
  conflit, garder les DEUX entrees en renumerotant la sienne, jamais `--ours` / `--theirs`.
- En cas de conflit ou de push refuse : **stop, le dire.**

## Journal d'apprentissage

Quand l'assistant apprend quelque chose de non evident pendant une session (piege d'outil, comportement
surprenant d'une API, cause racine d'un bug qui a coute du temps), il l'ajoute ici en une ou deux lignes, sans
qu'on ait a le demander. But : ne jamais repayer deux fois le meme diagnostic.

- **Rokit : un process garde sa version a vie.** `~/.rokit/bin/<outil>.exe` n'est pas l'outil, c'est un
  aiguillage qui lit le `rokit.toml` AU LANCEMENT. Un `rojo serve` demarre avant un `rokit add` continue de
  tourner sur l'ancienne version. Apres toute mise a jour d'outil : tuer les process en cours. Sinon on debug
  une incoherence qui n'a aucun rapport avec le code.
- **Un `rokit.toml` par projet.** Sans lui la version vient de `~/rokit.toml`, et une mise a jour touche TOUS
  les projets d'un coup sans prevenir.
- **Rojo : le CLI et le plugin Studio doivent avoir la MEME version.** `rojo plugin install` installe le plugin
  correspondant au CLI courant. Un ecart donne une erreur de protocole illisible.
- **Une notification affichee n'est pas une erreur qui vient de se produire.** Les notifications du plugin Rojo
  restent a l'ecran jusqu'a fermeture manuelle. Verifier l'horodatage avant de conclure qu'un correctif a
  echoue.
- **Ne pas conclure sur une lecture partielle.** Du binaire lu dans un terminal ne prouve rien. Verifier par une
  mesure (hash, version, horodatage) avant d'annoncer une cause. Une fausse piste coute plus cher qu'une
  verification lente, et fait perdre confiance dans les diagnostics suivants.
- **`CFrame.Angles` attend des RADIANS.** Toujours passer par `math.rad()`. Un nombre nu ressemble a des
  degres et n'en est pas : `CFrame.Angles(90, 0, 0)` vaut 116.62 degres, pas 90.
- **Motor6D** : `Part1.CFrame = Part0.CFrame * C0 * C1:Inverse()`. Avec `C1` = une Attachment posee sur la
  piece, cette Attachment vient se coller sur `C0`, axes alignes. L'orientation de l'objet tenu EST donc celle
  de son Attachment.
- **Priorites d'animation Roblox** : `Core < Idle < Movement < Action < Action2..4`. Une pose de maintien
  d'outil doit etre en `Action`, sinon la marche (`Movement`) l'ecrase. Mais en `Action` elle ecrase aussi les
  jambes si elle les cle : une pose de maintien ne doit cler que les bras et le torse.
- **`UserInputService:GetMouseLocation()` va avec `Camera:ViewportPointToRay`, PAS `ScreenPointToRay`.** Avec
  le second, le point tombe ~36 px trop bas : l'inset de la barre Roblox est compte deux fois. Verifie a
  l'ecran, contre ce qu'affirmaient des sources trouvees en ligne.
- **Une source web n'est pas une preuve.** Quand le comportement observe contredit ce qu'on a lu, c'est
  l'ecran qui a raison. Corriger d'abord, et noter la vraie regle ici.
- **`BasePart.CanQuery = false` n'a d'effet que si `CanCollide` est FAUX.** Une part solide reste vue par les
  raycasts quoi qu'on mette dedans. Pour un obstacle physique invisible aux lancers, il faut l'exclure
  explicitement via `RaycastParams`. Et comme un filtre exclut une instance ET ses descendants, cet obstacle ne
  doit pas etre enfant de ce qu'on veut detecter : le ranger dans un dossier a part.
- **Quand un nettoyage rate malgre une comptabilite correcte, arreter de compter et demander a la source.**
  Une liste tenue a la main est une hypothese ; `animator:GetPlayingAnimationTracks()` est un fait. Pareil
  pour les instances, les connexions, les threads : l'etat reel du moteur bat l'etat qu'on croit avoir.
- **Celui qui cree est celui qui nettoie, et il nettoie TOUT.** Un nettoyage reparti sur plusieurs modules et
  plusieurs champs finit toujours par en oublier un. Ne pas chercher lequel : centraliser la creation ET la
  destruction au meme endroit, avec un registre balaye en sortie.
- **A priorite d'animation EGALE, Roblox ne choisit pas : il MELANGE.** Deux pistes en `Action` qui clent les
  memes membres donnent une moyenne des deux, pas la plus recente. Symptome : une animation "presque bonne"
  qu'on croit mal faite. Se lit uniquement dans `animator:GetPlayingAnimationTracks()`, jamais a l'oeil.
- **Forcer `Looped = false` cote code sur toute animation ponctuelle** (reception, impact, geste unique).
  Le reglage de l'editeur n'est qu'une suggestion, et une piste bouclee par erreur reste a plein poids POUR
  TOUJOURS et pollue tout ce qui partage sa priorite.
- **L'angle d'un outil DANS la main vient du Motor6D (`C0`), jamais de l'animation.** Animer les bras ne le
  corrigera pas. Un meme outil dans une meme main peut avoir plusieurs angles selon le GESTE (tirer une corde
  n'est pas tailler) : c'est un offset par geste, pas un offset par main.
- **Un `Tool` Roblox n'a rien de magique : c'est Roblox qui lui cree un Motor6D `RightGrip` a l'equipement.**
  Un `Model` ne declenche rien. Le parenter au personnage ne cree AUCUN joint, donc l'editeur d'animation ne
  le voit meme pas. Il faut creer le Motor6D soi-meme. Symptome trompeur : l'outil flotte a cote, ce qui
  ressemble a un probleme d'orientation alors que c'est un joint absent. Et une part `Anchored` ignore son
  Motor6D, quoi qu'on mette dedans.
- **Ne jamais refaire A LA MAIN dans Studio un placement que le code CALCULE.** Poser un outil "a peu pres"
  dans l'editeur d'animation donne des poses justes a l'ecran et fausses en jeu, et on cherche ensuite
  l'erreur dans l'animation. Rejouer le calcul du jeu dans un script de barre de commandes coute dix minutes
  et supprime la classe entiere de bugs. Voir `scripts/studio/` (hors `src/`, donc Rojo ne le synchronise pas).
- **A `CharacterAdded`, le personnage est parente mais PAS complet.** L'`Animator` en particulier arrive
  quelques frames apres l'`Humanoid`. Un `FindFirstChildOfClass` a cet instant renvoie `nil`. Utiliser
  `WaitForChild` avec timeout. Symptome trompeur : tout marche des qu'on refait l'action a la main, ce qui
  envoie chercher le bug du cote de l'action au lieu du timing.
- **Un plancher exprime en STUDS depend de tous les reglages qui produisent la taille.** Pose au-dessus de la
  plus petite valeur possible, il INVERSE l'effet qu'il est cense borner (des feuilles qui GROSSISSENT en
  etant taillees). Invisible au reglage, parce que les grands cas continuent de marcher et que l'ecran dit
  donc "ca fonctionne". Toute borne absolue doit etre bornee a son tour par la donnee de chaque objet.
- **Un test serveur qui compare une direction a une NORMALE DE FACE casse des que le client cesse de bouger
  perpendiculairement a cette face.** Comparer au REGARD du personnage : il se replique gratuitement, il suit
  toujours ce que le client fait, et il ne suppose aucune geometrie. Regle generale : ne pas faire juger au
  serveur une intention a partir d'un repere que le client peut changer sans le lui dire.
- **Avant de "lisser" une transition seche, regarder si la geometrie ne la contient pas deja.** Une surface a
  distance constante d'une boite EST un rectangle a coins arrondis. Decouper en faces discretes fabrique la
  bascule qu'on cherche ensuite a interpoler. Souvent la vraie correction supprime le probleme au lieu de le
  masquer, et coute moins de lignes.
- **Un lerp exponentiel (`x += (cible - x) * k`) n'atteint JAMAIS sa cible.** Il laisse un residu minuscule
  pour toujours. Sur une transparence ca se voit : `LocalTransparencyModifier` a ~0.005 (au lieu de 0 pile)
  suffit a faire passer la part dans le rendu TRANSPARENT de Roblox, ou le tri se fait par objet et pas par
  profondeur. Symptome : des membres qui se chevauchent quand on pivote la camera, alors que "le fondu est
  fini". Cler la valeur a la cible des qu'on est assez pres. Piege double : un garde-fou "ne pas reecrire si
  le delta est infime" FIGE justement ce residu au lieu de le laisser finir de descendre.
- **Jouer une anim UNE fois et TENIR sa derniere image** : garder `Looped = true` (sinon la piste se relache a
  la fin et la pose saute) MAIS piloter la `TimePosition` A LA MAIN (vitesse 0, `+= dt` chaque frame, clamp a
  `Length - 0.001`). Laisser la lecture tourner a vitesse > 0 avec Looped = true rebouclerait (wrap au bout, et
  a bas FPS le clamp d'une fenetre `>= Length - eps` peut le rater). La combinaison manuelle fait les deux :
  joue une fois, tient la pose au bout, sans wrap. Sortie inverse = `Looped = false` puis vitesse negative.
- **Ne pas fabriquer un deplacement quand le joueur est deja arrive.** Une zone de detection posait le joueur a
  0.59 stud du point cible : tout un systeme de "marche forcee" (Humanoid:Move a priorite Camera + marqueurs
  d'anim + secours distance/timeout) etait inutile, l'arrivee par distance tirait des la 1re frame (log a
  l'appui). Mesurer la distance REELLE avant de coder un trajet. La solution etait : ancrer + jouer la pose.
- **Un outil qui court-circuite la boucle par defaut doit etre re-branche dans CHAQUE contexte.** La cisaille
  coupe au CLIC (remote CutSnip) et non par la boucle continue (qui la saute). Elle marchait au sol mais PAS
  depuis l'echelle : le clic ne tirait CutSnip que dans le contexte "engaged" (travail au sol), jamais dans le
  contexte ladder-trim. Le taille-haie, lui, passe par la boucle continue, presente dans les DEUX contextes,
  donc le trou ne se voyait pas sur lui. Regle : quand un cas special remplace le chemin par defaut, auditer
  TOUS les contextes qui utilisent le chemin par defaut et y cabler le cas special aussi.
- **Un objet PORTE qui doit revenir "pareil" a chaque prise : capturer l'offset UNE FOIS et le reutiliser, pas le
  recalculer.** Piege a tiroirs vecu sur l'echelle. Recalculer l'offset a chaque prise en gardant la rotation
  ENTIERE : chaque pose la laisse a un poil pres droite, la reprise recapture ce poil, ca s'accumule, elle finit
  couchee. Ne garder que le YAW supprime l'accumulation MAIS preserve encore le sens de repose -> reposee de
  travers, reprise de travers. Or le vrai besoin n'etait PAS de garder le sens de repose : c'etait qu'elle revienne
  DROITE DEVANT le porteur a chaque fois. La bonne reponse : capturer l'offset (yaw + position) UNE SEULE FOIS a la
  1re prise et le reutiliser -> meme offset relatif au porteur a chaque prise, donc toujours pareil, sans derive ni
  dependance a la pose. Bien distinguer "garder l'orientation de l'objet" de "toujours le meme rendu chez le porteur"
  AVANT de coder : ce sont deux besoins opposes. Nuance finale : caler sur une orientation fixe fait faire un
  DEMI-TOUR brusque de 180 quand on prend l'objet du cote ou il fait deja face. Corriger en choisissant, parmi les
  deux sens (0 / 180 autour de la verticale), le plus PROCHE de la pose actuelle (somme des dots des 3 axes entre
  deux CFrames = leur proximite d'orientation, sans supposer quel axe est le "devant"). SUITE (le piege a un
  tiroir de plus) : capturer meme le YAW D'ORIGINE de l'objet a la 1re prise reste faux, parce que cette pose vient
  de son placement Studio, souvent DE TRAVERS -> l'objet est alors porte ET repose de travers pour toujours. La
  vraie reponse pour un objet dont la repose doit toujours bien s'orienter vers une cible (l'echelle vers la
  haie) : une orientation FIXE et reglable RELATIVE au repere de travail (face a la cible), pas une valeur capturee.
  Le recul (encombrement arriere) doit alors etre remesure POUR cette orientation, en repere objet.
- **Une UI de StarterGui n'existe dans PlayerGui qu'au SPAWN, et le spawn peut TARDER.** Chargement des donnees /
  session lock ProfileStore : le perso peut apparaitre 15 s apres le join. Un controller qui cherche sa ScreenGui au
  boot avec un `WaitForChild` court (10 s) la RATE, et croit a tort l'UI absente (warning "introuvable" alors qu'elle
  arrive juste plus tard). Attendre le perso (`player.Character or player.CharacterAdded:Wait()`) AVANT de chercher
  l'UI, en `task.spawn` (sinon ce WaitForChild bloque le reste du boot). Symptome trompeur : la meme UI marche une
  session sur deux, selon la vitesse du spawn. Et pour survivre aux RESPAWNS : ResetOnSpawn = false sur la ScreenGui,
  sinon elle est recreee a chaque mort et les references gardees en cache pointent sur du detruit.
- **`Model:GetPivot()` suit la BOUNDING BOX quand le model n'a pas de PrimaryPart.** Ajouter des parts enfants,
  MEME invisibles (zones de detection, hitbox), DECALE et DESORIENTE ce pivot. Tout ce qui calcule un portage / un
  placement dessus part alors de travers, sans que rien ne le signale (les parts sont transparentes). Symptome
  trompeur : on cherche le bug dans le calcul d'orientation alors que c'est le pivot, sous les pieds, qui a bouge
  quand on a ajoute une part ailleurs. Baser ces calculs sur une PART REELLE et fixe (la RootPart), jamais sur le
  GetPivot d'un model dont on modifie les enfants.
- **Un tween de camera vers une CFrame FIXE laisse la camera plantee si le sujet BOUGE.** Pour finir une camera
  scriptee et rendre la main a la camera de jeu qui suit un joueur qui s'en va : pas un `TweenService:Create` vers une
  cible calculee une fois (pendant la transition plus rien ne suit le joueur -> ~0.2 s "sans camera", moche), et pas
  une bascule directe vers Custom (coup sec sur la distance/zoom). Il faut GLISSER image par image en re-ancrant le
  focus sur la position LIVE du sujet a chaque frame, et n'easer que l'OFFSET (point vise + distance), pas la CFrame
  absolue. Depart = la vue exacte (offset capture a la sortie) -> aucun pop ; fin = la camera de jeu reprend pile la,
  ayant deja suivi -> aucun trou. Pour que la reprise Custom ne re-snappe RIEN (sinon micro-saut ~0.05 s, visible et
  stressant) : capturer A L'ENTREE l'etat EXACT de la cam de jeu via `camera.Focus` -- la distance `camera->Focus` (le
  VRAI zoom, PAS la distance au HRP) ET l'offset `Focus - sujet` (~tete). Le glissement doit finir sur CES valeurs.
  Une cible approximee (hauteur du regard devinee, distance mesuree au HRP) laisse un saut sub-perceptible mais bien
  visible. La reprise Custom garde l'ANGLE courant (elle lit la LookVector de la camera), donc caler focus + zoom suffit.
- **WorldAnchor va avec `ScreenInsets = None`, jamais l'inset par defaut.** `WorldToViewportPoint` rend des coords
  VIEWPORT dont l'origine est le coin ABSOLU de l'ecran (l'inset de la barre est DEDANS). Le ScreenGui qui recoit ces
  coords doit donc couvrir tout l'ecran (`ScreenInsets = None`, equivaut a `IgnoreGuiInset = true`). Avec l'inset par
  defaut, l'origine du GUI est ~36 px plus bas et l'element suit 36 px trop bas. Piege a tiroirs : le commentaire
  d'origine de WorldAnchor affirmait le CONTRAIRE (IgnoreGuiInset FAUX) et m'a fait poser le mauvais reglage sur le
  combo ; c'est l'ecran (le joueur) qui a tranche. Meme famille que GetMouseLocation / ViewportPointToRay.
- **Lisser (lerp) la POSITION d'une camera qui ORBITE un point coupe la corde de l'arc.** La cible tourne sur un
  cercle ; interpoler la position en ligne droite vers elle fait plonger la camera vers l'interieur puis ressortir
  (une "courbe" degueulasse), et la distance a la cible varie pendant le pivot. Pour une orbite propre : placer la
  camera DIRECTEMENT sur le cercle au yaw courant (1:1), et ne lisser que les PARAMETRES (distance, angle) ou
  l'ARRIVEE, jamais la position monde. Piege jumeau vecu dans le meme code : un seuil "proche = rapide / loin =
  lent" rend le pivot PLUS lent quand on glisse vite (la cible saute loin, donc "loin", donc mode lent) : l'exact
  inverse du ressenti voulu. Le "smooth" n'etait pas trop fort, il etait applique a la mauvaise grandeur.
- **Les zones de detection ENFANTS d'un objet PORTE suivent le porteur, donc restent declenchees en permanence.**
  Les zones de grimpe de l'echelle sont enfants de son model ; portee, l'echelle est soudee au HRP -> ses zones
  entourent le joueur en continu -> le systeme de grimpe l'accrochait a sa propre echelle. Regle : un systeme qui
  reagit a des zones doit etre coupe explicitement dans les etats ou l'objet qui les porte change de role (ici :
  drapeau `LeafiaCarryingLadder` pose pendant le portage, lu par la grimpe pour se desactiver). Meme famille que
  "un cas special doit etre re-branche dans chaque contexte".
- **`GetKeyframeSequenceAsync` est un appel RESEAU capricieux : quand il rate au boot, la feature est morte pour
  TOUTE la session.** Symptome trompeur : "parfois ca marche, parfois pas DU TOUT" (pas intermittent DANS une
  session : c'est binaire PAR session, selon que l'async a reussi ou non). La boite aux lettres lisait le temps du
  marqueur IsOpenEvent a l'avance par cette API ; en cas d'echec, `openTime = 0`, cible d'ouverture 0, la boite ne
  s'ouvrait jamais. Aggrave par la concurrence : l'echelle appelle la meme API au meme boot. Regle : quand on a
  juste besoin de REAGIR a un marqueur (pas de connaitre son temps a l'avance), utiliser `GetMarkerReachedSignal`
  pendant la lecture de l'anim (lecture LOCALE, pas d'appel reseau) plutot que lire la KeyframeSequence. Si on doit
  vraiment lire l'async, prevoir un retry (ce que fait l'echelle : boucle de fond tant que ce n'est pas charge).
- **Mapper une souris sur un geste CENTRE SUR LE CORPS : le repere est la position du JOUEUR a l'ecran, pas le
  centre de l'ecran.** La visee de la taille du DESSUS (echelle) a coute des JOURS, a travers une pile de systemes
  de plus en plus compliques qui marchaient tous "presque" : angle / champ de vision (`atan2` regard->curseur),
  zones colorees de la haie (Jaune/Rose/Bleu + bouts), offset player-relatif en repere HAIE, mapping par les 3
  evenements d'anim (MaxLeft/Middle/MaxRight)... La vraie regle tenait en UNE ligne : `ratio = 0.5 + (sourisX -
  WorldToViewportPoint(joueur).X) / largeurEcran * sensibilite`. Souris pile DEVANT le corps = pose centrale, quel
  que soit le cadrage. Symptome trompeur qui a envoye chercher partout ailleurs : ca "marchait quand le joueur
  etait cadre au CENTRE de l'ecran" (la, centre-ecran == centre-joueur par hasard), donc on cherchait des bugs de
  sensibilite / camera / geometrie de haie au lieu du REPERE. Double lecon : (1) un geste centre sur le corps se
  mappe sur le corps a l'ecran ; (2) quand on empile trois systemes qui corrigent chacun un SYMPTOME, s'arreter et
  chercher la cause -- la solution la plus simple etait la bonne depuis le debut. (`WorldToViewportPoint` et
  `GetMouseLocation` sont dans le meme repere viewport : leurs X se comparent direct.)
- **Un drop de FPS vu DANS Studio n'est pas forcement un bug du jeu.** Studio ouvert avec le MicroProfiler :
  bouger la souris fait des pics de ms (survol / highlight de Studio + redraw du profiler) qui n'existent PAS
  dans le client. Le meme build tournait a 200 FPS parfait dans l'appli Roblox. Regle : avant de traquer un
  drop de FPS vu dans Studio, le REPRODUIRE dans un vrai client. Sinon on optimise un fantome. (M'a fait passer
  la camera d'orbite de `RenderStepped:Connect` a `BindToRenderStep` a la priorite Camera : le changement reste
  correct en soi -- c'est le pattern d'une cam scriptee -- mais il n'a rien repare, il n'y avait rien a reparer.)
- **Un effet de camera qui passe par `Humanoid.CameraOffset` est INVISIBLE tant que la camera est Scriptable, puis
  POPE d'un coup au passage en Custom.** Seule la camera par defaut (Custom) applique CameraOffset ; une camera
  scriptee l'ignore. Piege vecu a l'entree du plot : on teleporte le joueur quelques studs au-dessus du spawn, il
  tombe et ATTERRIT -> la plongee d'atterrissage (LandDip) part, mais elle est masquee pendant le tween scripte ;
  a l'instant ou on rend la main a Custom, elle apparait -> un "bump / pump" juste avant que la vue se pose.
  Regle : une teleportation scriptee qui provoque une reception doit COUPER les effets qui transitent par
  CameraOffset (drapeau lu par CameraController), sinon ils ressurgissent au handoff. Meme famille que "une
  propriete, un seul ecrivain" et que le residu de fondu qui traverse le rendu transparent.
- **En passant de Scriptable a Custom, Custom garde le YAW mais REMET son propre PITCH de repos ; il ne conserve
  PAS l'inclinaison qu'on lui donne.** (Corrige une note plus haut qui disait "caler focus + zoom suffit, l'angle
  est garde" : vrai pour le yaw, FAUX pour le pitch.) Symptome : un tween d'arrivee fini a 12 deg alors que le repos
  de Custom est a 15 -> au handoff la camera remonte de 3 deg d'un coup, ressenti comme un "zoom in-out". Regle : un
  handoff scripte -> Custom sans saut doit finir sur l'etat de repos COMPLET de Custom (distance + hauteur de focus
  + pitch), et ces trois valeurs se MESURENT, elles ne se devinent pas. Mesure faite ici en posant Custom puis en
  lisant apres ~0.4 s `(camera.CFrame.Position - camera.Focus.Position)` (distance + pitch) et `Focus - HRP`
  (hauteur du focus) : distance 12.5, focus +1.4, pitch 15. Deviner (j'avais mis pitch 12) a coute une iteration.
- **Un helper partage qui cache un `WaitForChild` (ex `RemoteSetup.getRemote`) BLOQUE son appelant jusqu'au
  timeout.** Appele en SYNCHRONE dans un `init()` de boot, il gele TOUT le boot : mesure d'un trou de 10 s entre
  deux controllers, le temps que le WaitForChild d'un remote timeoute (course de replication rare ; le remote existe
  pourtant, le serveur le cree en premier). Symptome trompeur = un boot lent SANS erreur, juste un TROU dans les
  horodatages des logs. Regle : dans un init de boot, tout appel qui peut ATTENDRE (remote, asset, UI de spawn) va
  en `task.spawn`, jamais en ligne droite. Piege a tiroir : le meme fichier faisait deja son resolve d'UI en
  task.spawn "pour ne pas bloquer le boot" mais avait oublie de proteger l'appel getRemote juste au-dessus.
- **Generaliser un `WaitForChild` unique en enumeration de PLUSIEURS enfants ne se fait PAS en le remplacant par
  `FindFirstChild`.** Le delai de replication est toujours la : un `WaitForChild("Slot1")` attendait, un
  `GetChildren()` + `FindFirstChild("PrimaryGround")` par enfant, lui, tombe sur du vide tant que ce n'est pas
  replique -> zero resultat, et (ici) joueur GELE dans sa box de spawn sans orbite ni sortie. On ne peut pas non
  plus `WaitForChild` chaque candidat (un enfant qui n'est pas un plot ferait attendre le timeout entier). La bonne
  forme : RE-SCANNER en boucle (FindFirstChild, instantane) jusqu'a trouver au moins un resultat, ou timeout. Regle :
  quand on passe de "un" a "plusieurs", re-verifier que la garantie d'attente du cas unique existe encore.
- **`TouchEnabled and not KeyboardEnabled` NE marche PAS dans l'emulateur d'appareil de Studio.** Le PC garde son
  clavier physique, donc `KeyboardEnabled` reste TRUE meme en emulant un iPhone -> `not KeyboardEnabled` = false ->
  toute la branche "mobile" est SAUTEE en test. Symptome trompeur : le layout mobile "n'est pas applique" alors que le
  code est bon ; on cherche le bug dans l'application des valeurs, pas dans la detection. Pour une decision de LAYOUT
  (stable, mobile vs PC), utiliser `TouchEnabled` SEUL : c'est une CAPACITE, vraie dans l'emulateur ET sur vrai mobile
  (faux sur PC sans ecran tactile). Le combo `and not KeyboardEnabled` ne sert qu'a distinguer un VRAI mobile d'un PC,
  et casse le test en emulateur. Ne pas confondre CAPACITE (TouchEnabled, stable) et input ACTIF (dernier utilise, cf
  `InputDevice` : bon pour les hints dynamiques, PAS pour un layout qui ne doit pas changer quand on prend la souris).
- **Un "wipe" par UIGradient (animer son Offset) a une DIRECTION qu'on ne peut pas deduire au raisonnement : seul
  l'ecran tranche.** Meme famille que GetMouseLocation / ViewportPointToRay. Le sens de l'offset est faux une fois sur
  deux, et un wipe a l'envers laisse le rideau OPAQUE (il BLOQUE le jeu) ou revele d'un coup. Pour une fermeture / un
  reveal FIABLE et DANS L'ORDRE : fondre les VRAIES proprietes de transparence (`ImageTransparency` des images,
  `BackgroundTransparency` des parts, `GroupTransparency` d'un CanvasGroup pour le fond), enchainees par un delai ou un
  `Completed`, plutot qu'un gradient directionnel. Corollaire de comportement (le vrai cout ici) : ne pas EMBELLIR un
  effet simple demande par un plus malin non demande. Le joueur voulait "contenu transparent puis fond" ; j'ai ajoute un
  wipe par gradient jamais demande, dont le sens imprevisible a brouille l'ordre et coute plusieurs iterations.
- **`Instance.new("UICorner")` n'est PAS resolu vers le type `UICorner` par luau-lsp ici (UICorner absent du dump
  d'API des overloads d'`Instance.new`) : il renvoie `Instance`, et poser `.CornerRadius` / `.BottomLeftRadius`
  dessus donne "Expected this to be 'UICorner', but got 'Instance'" (Luau1000).** Fix : caster a la creation,
  `Instance.new("UICorner") :: UICorner`. Le passer par le helper `create()` puis `:: UICorner` marche aussi ; c'est
  le `Instance.new("UICorner")` NU suivi d'un acces de propriete qui casse. Double lecon : ces 3 vraies erreurs
  etaient NOYEES sous un flot de soulignements ROUGES du correcteur d'orthographe (extension cSpell, sans config ->
  souligne tous les identifiants et le francais, y compris DANS les strings). Un vrai type-checker ne souligne JAMAIS
  le contenu d'une string valide : c'est le test pour distinguer erreur luau (rouge, onglet Problems) de bruit
  d'orthographe. Couper cSpell (`"cSpell.enabled": false` dans `.vscode/settings.json`) a revele les vraies erreurs.
- **Un tableau literal (ex `Children = { ... }`) prend le TYPE de son 1er element, et REJETTE les suivants qui n'y
  collent pas.** luau-lsp deduit `{ UICorner }` d'un premier enfant `corner()` (annote `: UICorner`), puis crache
  "Expected this to be 'UICorner', but got 'Instance' / 'UIScale' / 'TextLabel'..." sur CHAQUE autre enfant -- alors
  que le code tourne parfaitement (Luau ignore ca a l'execution). Fix : que les helpers "fabrique un enfant a
  PARENTER" renvoient `Instance`, pas leur classe precise (le type exact ne sert a aucun appelant) -> le tableau
  reste homogene. Piege JUMEAU : un `{ Instance }` rempli de valeurs `X?` NILABLES (ex deux `TextLabel?` module,
  pourtant assignes plus haut mais non narrowes car upvalues) donne "Expected 'Instance', got 'TextLabel?'" ->
  inserer sous garde `if x then table.insert(t, x) end` (le `if` enleve le nil), pas en literal direct.
- **Une action clavier-only est INVISIBLE sur mobile -> la feature n'existe pas pour la moitie des joueurs Roblox.**
  Deposer / tourner l'echelle ne tenaient qu'a E / R via `UserInputService` : increachables sans clavier. La PRISE, elle,
  marchait deja sur mobile parce que son declencheur est un bouton CLIQUABLE (le prompt d'interaction), pas une touche.
  Symptome trompeur : "la moitie de la feature marche sur mobile" (la partie qui passe par un bouton), l'autre non.
  Fix idiomatique : `ContextActionService:BindAction(nom, fn, true, touche)` -- `createTouchButton = true` cree un bouton
  a l'ecran UNIQUEMENT sur tactile ET bind la touche sur PC, d'un seul geste. Le lier au CONTEXTE (bind a l'entree d'un
  etat, unbind a la sortie) pour que le bouton n'apparaisse que quand l'action a un sens. Anti-double sur PC : la meme
  touche cablee en CAS (qui la Sink) et en UIS -> passer chaque action par un declencheur central anti-spam rend un
  eventuel double appel (notamment l'emulateur d'appareil, qui garde un clavier) sans effet. Regle : tout input clavier
  doit avoir son pendant tactile, sinon auditer aussi les autres inputs clavier du meme systeme (ici R = tourner, oublie
  en meme temps que E = deposer).
- **Une place SECONDAIRE (multi-place) n'herite NI des reglages Studio par-place (StarterPlayer / Workspace / Lighting),
  NI des services qu'on a gates hors d'elle par PlaceId.** Deux symptomes vecus au 1er lancement du tuto (place a part) :
  (1) l'auto-jump degueulasse etait "regle" dans Leafia par un reglage StarterPlayer (`AutoJumpEnabled`), PAS par du code
  -> absent du tuto. (2) L'AUTO-EQUIP du taille-haie (approcher une haie l'equipe) etait planque dans `LadderMoveController`,
  gate hors du tuto -> plus d'auto-equip, donc un "delai enorme avant de pouvoir tailler". Regles : un comportement de
  GAMEPLAY qui doit valoir dans TOUS les lieux se met en CODE (ex `humanoid.AutoJumpEnabled = false` dans CharacterService),
  jamais dans un reglage Studio par-place (il ne suit pas le teleport). Et quand on gate par PlaceId, se mefier des features
  COUPLEES a un module au nom trompeur (l'auto-equip dans le controller d'ECHELLE). Rojo synchronise le CODE dans les deux
  lieux, mais PAS le Workspace/map ni les assets `$ignoreUnknownInstances` (Assets, Animations) : ca se copie a la main.
  SIGNATURE A RECONNAITRE (vecu deux fois : tondeuse, puis seau) : la feature ne fait RIEN, AUCUNE erreur, AUCUN log
  a elle, et pourtant son module est bien VISIBLE dans l'Explorer pendant le Play. Ce trio ne veut dire qu'une chose :
  le code est synce mais PERSONNE ne l'appelle. Ca ressemble a un bug de la feature (on va debugger sa detection, ses
  distances, ses attributs) alors que le bootstrap de CETTE place ne la declare pas. Reflexe : lire la ligne
  `[Server] ... demarre` / `[Client] Pret` de la console -- elle dit dans QUELLE place on tourne -- puis verifier que
  le module est declare dans CE bloc-la. Corollaire pour l'assistant : signaler "pas branche dans le tuto" comme une
  limite ne suffit pas si le joueur teste justement dans le tuto ; demander OU il teste avant de livrer.
- **Un `WaitForChild` (ou tout appel qui YIELD) dans une fonction appelee PAR FRAME gele TOUTE la boucle le temps du
  yield.** Une connexion (Heartbeat/RenderStep) qui yield ne re-fire pas tant que son callback n'a pas rendu : elle reste
  bloquee. Vecu : `getMoveVector` (pas chasse / rail d'echelle, appele chaque frame) faisait un `require(PlayerModule)`
  LAZY -- et ce require peut yield 10-20s (`WaitForChild("PlayerModule", 10)`) quand PlayerModule tarde a etre pret. Au 1er
  appel, toute la boucle de travail gelait -> "delai enorme avant de pouvoir tailler / ca.la camera de travail" -- et
  SEULEMENT dans une place secondaire (le tuto), ou PlayerModule met plus de temps a apparaitre/etre requerable. Symptome
  trompeur : "un WaitForChild qui cherchecherche", place-specifique, alors que le code est le meme partout -- c'est le
  TIMING de la dependance qui change selon le lieu. Regle : tout ce qui peut YIELD (require lourd, WaitForChild, remote)
  se resout UNE fois EN TACHE DE FOND (`task.spawn` au boot), jamais dans le chemin par-frame ; la fonction par-frame rend
  une valeur neutre (zero) tant que ce n'est pas pret. Meme famille que "un getRemote synchrone dans un init gele le boot".

- **A deux sur le projet, le CHANGELOG entre en conflit A CHAQUE push : les numeros de version se collisionnent.**
  Les entrees s'inserent toutes au MEME endroit du fichier (le bloc du haut, en ordre decroissant), donc git ne peut
  pas fusionner tout seul, et pire : deux personnes fabriquent la meme version en meme temps (vecu, mon 0.0.199 contre
  le 0.0.199 du collaborateur, qui avait deja pousse jusqu'a 0.0.201). Regle : `git pull --rebase` AVANT d'ecrire
  l'entree, pas apres -- on lit le dernier numero REEL et on prend le suivant. Et en cas de conflit, on garde les DEUX
  entrees en renumerotant la sienne, jamais `--ours` / `--theirs` (le CHANGELOG est append-only : une entree effacee
  est une info perdue pour de bon).

- **Etre ENFANT d'une part ne veut PAS dire etre SOUDE a elle : une part ancree vit en coordonnees MONDE et ne suit
  pas son parent.** Vecu sur l'herbe de zone : les touffes sont enfants de leur ZoneGrass, mais deplacer la zone
  pendant un test les a laissees sur place -- un carre d'herbe a la bonne forme et a la bonne orientation, a dix
  metres de la zone. Symptome trompeur : ca ressemble a un calcul de position FAUX (on va relire la projection, le
  repere, le PointToWorldSpace) alors que le calcul etait juste, il etait juste PERIME. Regle : tout semis calcule
  depuis un objet de reference doit garder ses positions dans le REPERE de cet objet et se retraduire quand il bouge
  (`GetPropertyChangedSignal("CFrame")`), pas stocker un resultat monde fige. Et si la reference peut CHANGER DE
  TAILLE, ecouter `Size` aussi et REFAIRE le semis : reposer les anciennes ne remplit pas la nouvelle surface.
- **Selene ne reconnait pas `Vector3.yAxis` (ni ses jumeaux) comme un Vector3 : `Vector3.yAxis:Cross(v)` sort en
  ERREUR rouge** ("does not contain the field `Cross`"). C'est un faux positif de sa bibliotheque standard, le code
  tourne. Passer par une constante locale (`local UP = Vector3.new(0, 1, 0)`) au lieu de discuter. Meme famille que
  le `Instance.new("UICorner")` non resolu par luau-lsp : un faux positif rouge finit par masquer les vraies erreurs,
  donc on le supprime plutot que de le tolerer.

- **Un `return` pose sur "rien a faire POUR L'INSTANT" ne doit JAMAIS court-circuiter l'ABONNEMENT a ce qui arrivera
  plus tard.** Vecu sur l'herbe de zone : `if #zones == 0 then print(...) return end` etait juste AVANT le
  `Heartbeat:Connect`. Avec StreamingEnabled la zone arrivait 3 s apres le boot, se remplissait bien par
  DescendantAdded -- l'herbe s'affichait, dense et bien posee -- mais aucune boucle ne tournait dessus : ni vent ni
  ecrasement. Symptome trompeur au possible : tout ce qui est VISIBLE est parfait, donc on va debugger le calcul de
  l'animation alors que rien n'est jamais appele. Regle : avec du streaming, "absent au demarrage" est un etat NORMAL.
  Brancher la boucle DE TOUTE FACON (elle sort en une ligne tant que la liste est vide) coute zero. Corollaire :
  un log de diagnostic qui ne sort qu'au boot ne se declenche jamais dans le cas qui pose probleme -- le mettre sur
  l'evenement (a chaque pose), pas sur le demarrage.
- **Une part qui arrive par le STREAMING recoit ses proprietes en PLUSIEURS ETAPES.** `Size` a change trois fois en
  80 ms sur la meme part, et chaque changement relancait une reconstruction de 570 instances. Tout rebuild branche sur
  `GetPropertyChangedSignal` d'une part repliquee doit etre DIFFERE et coalesce (task.delay + drapeau), jamais
  immediat.

- **Un plancher de duree compte depuis un instant qui n'a rien a voir avec l'evenement qu'il doit couvrir ne garantit
  RIEN.** Le rideau de chargement gardait un minimum de 10.5 s depuis le CLIC ; quand le personnage mettait 8 s a se
  mettre en place, il ne restait qu'une seconde de rideau apres lui. Le plancher protegeait donc les cas rapides et
  laissait tomber les cas lents -- exactement ceux qui en avaient besoin. Symptome trompeur : on monte le chiffre
  (6.5 -> 10.5) et ca ne change presque rien, parce que ce n'est pas la duree qui est fausse mais son POINT DE DEPART.
  Regle : faire partir le compte a rebours de l'EVENEMENT a couvrir (ici l'arrivee du personnage), et garder l'autre
  plancher en plus si on veut un minimum absolu. Meme famille que le plancher en studs qui inversait l'effet qu'il
  devait borner.

- **Une detection "qu'est-ce qui est POSE sur X" par boites englobantes attrape TOUJOURS le support sur lequel X
  repose.** Vecu sur l'herbe : la recherche des objets poses sur la pelouse ramenait le SOL lui-meme (grosse part dont
  le dessus affleure la zone, donc boites qui se touchent de quelques centiemes de stud), et son emprise effacait la
  totalite de l'herbe -- plus rien ne se generait. Regle : exiger que l'objet DEPASSE d'une hauteur minimale, pas
  seulement qu'il touche. Et exclure les parts rangees SOUS une autre part (`FindFirstAncestorWhichIsA("BasePart")`) :
  ce sont des details de l'objet parent, elles saturent la limite de resultats et font RATER le vrai objet. Corollaire
  de diagnostic : un log qui compte les objets sans les NOMMER ne sert a rien le jour ou ca derape.

- **Un service qui balaye le monde pour y trouver des choses doit dire ce qu'il N'A PAS trouve.** Vecu deux fois dans
  la meme session : une zone d'herbe puis un PNJ poses a la racine du Workspace au lieu du dossier attendu, donc
  jamais vus, et RIEN a l'ecran ni dans les logs ne le signalait -- on debug l'animation ou le semis alors que
  l'objet n'est simplement pas dans le perimetre. Un compteur global ("8 modeles animes") ne revele jamais l'absence
  du neuvieme. Regle : boucler sur les entrees de CONFIG et prevenir nommement pour chacune qui n'a rien produit, et
  distinguer "pas trouve" de "trouve mais inutilisable" (nom bon mais Animator absent). Corollaire : preferer une
  racine de recherche LARGE avec un filtre cheap (`IsA("Model")` ecarte des milliers de parts pour rien) plutot
  qu'une racine etroite qui oblige a ranger les objets au bon endroit -- l'ergonomie prime, le cout est nul.

- **Une animation Roblox retrouve les membres PAR LEUR NOM : si aucun ne correspond au rig, elle joue avec un poids
  de 1 et n'ecrit RIEN, sans la moindre erreur.** Vecu sur Papi : la piste tournait, les douze Motor6D restaient a
  zero, le PNJ glissait comme un mannequin. Cause : animations MIXAMO (29 os, `mixamorig:Hips`, `Spine`, `LeftArm`...)
  sur un modele fait de 12 morceaux de mesh rigides sans bras ni jambes. Deux rigs differents, zero nom commun.
  Symptome trompeur : ca ressemble a une animation mal faite ou a un probleme d'orientation, et on va regler le rig,
  alors que rien n'est jamais applique. Diagnostic dans cet ordre : (1) la piste joue-t-elle (`GetPlayingAnimationTracks`),
  (2) les `Motor6D.Transform` bougent-ils PENDANT la lecture -- les animations ecrivent dans `Transform`, PAS dans
  `C0`, donc un controle en mode edition ne voit jamais rien, (3) comparer les noms de poses de la KeyframeSequence
  aux noms des `Part1` du rig. Les trois outils sont dans `scripts/studio/`. Regle generale : quand un systeme peut
  echouer EN SILENCE, lui ajouter un controle qui mesure le RESULTAT et parle (ici : les joints ont-ils bouge une
  seconde apres le demarrage).

- **Une valeur qui doit finir a ZERO ne se calcule pas comme un COMPLEMENT `(1 - x)` d'une grandeur qui peut
  plafonner ailleurs qu'a 1.** Vecu sur l'herbe : l'inclinaison au passage s'effacait en `(1 - tassement)`, mais le
  tassement plafonne a FLATTEN_AMOUNT (0.8) a cause de la trace permanente. Il restait donc `0.8 x 28 x 0.2 = 4.5`
  degres de travers POUR TOUJOURS -- mesure a l'ecran par le joueur, jamais visible dans le code. La rendre comme un
  ECART entre deux valeurs qui CONVERGENT (ici le rapide moins le lent) la fait tomber a zero par construction, sans
  aucune constante a garder d'accord avec l'autre. Regle generale : preferer une difference qui s'annule a un
  complement qui suppose que l'autre grandeur atteint son maximum.

- **`BasePart.RenderFidelity` ne s'ecrit PAS depuis un script normal** : "The current thread cannot write
  'RenderFidelity' (lacking capability Plugin)". Elle se regle a la main dans Studio, sur le mesh SOURCE ; les clones
  en heritent. Meme famille que `GuiService:GetScreenResolution`, reserve aux CoreScripts. Et elle compte pour tout
  mesh qu'on REDIMENSIONNE en jeu : a `Automatic`, Roblox echange le maillage selon la taille a l'ecran, donc une
  part qui change fortement de taille en une fraction de seconde CLIGNOTE. La figer (`Precise` ou `Performance`)
  supprime l'echange.

- **Les teleports (`TeleportService`) ne partent JAMAIS en Studio** (Play Solo / serveur local) : `TeleportAsync`
  throw, notre `pcall` retombe -> rien ne se passe (ou fallback "game"). Un bouton qui teleporte semble donc "casse"
  en Studio alors qu'il marche en jeu publie. Toujours tester un teleport dans l'experience PUBLIEE (app Roblox), les
  deux places sous la MEME experience. Symptome vecu : "le START me teleporte pas au tuto" -- vrai en Studio, faux en
  jeu. Corollaire utile : ce fallback "game" est VOULU ici, il laisse tester le hub en Studio sans etre bloque.

- **Avec `StreamingEnabled`, un client ne recoit que le contenu PROCHE de lui ; le lointain ne se replique JAMAIS tant
  qu'il ne s'en approche pas.** Plus serre sur MOBILE (moins de memoire). Symptome vecu : l'ecran de selection de plot ne
  montrait que 2 plots sur mobile (les autres, eloignes, jamais repliques -> introuvables par l'enumeration). Un
  re-scan cote client n'y change rien : le contenu n'arrive tout simplement pas. Regle : tout ce qui doit etre visible
  QUELLE QUE SOIT la position du joueur (plots a choisir, hub distant, decor scenarise) doit etre force en
  `ModelStreamingMode = Persistent` (cote serveur, sur des MODELS) -> toujours replique a tous. Symptome trompeur : ca
  marche sur PC (streaming plus large) et casse sur mobile, donc on cherche un bug mobile alors que c'est la carte qui
  n'est pas la.

- **Un seuil d'input regle pour le CLAVIER (valeur binaire 1.0) est trop haut pour un JOYSTICK analogique (valeurs
  partielles).** Vecu : on ne pouvait pas sortir de la haie sur mobile en reculant le joystick, parce que le seuil de
  sortie (0.7) etait facile a atteindre a la touche S (= 1.0 pile) mais pas au stick tire a moitie. Symptome trompeur :
  marche au clavier / en emulateur, casse au doigt. Regle : un seuil partage clavier + tactile doit viser une valeur de
  stick CONFORTABLE (pas la butee), tout en restant au-dessus des corrections automatiques (aimant) qui passent par le
  meme canal. Ici : borne entre le max de l'aimant (0.45) et la butee clavier (1.0) -> 0.55.

- **`GuiService:GetScreenResolution()` est reserve aux CoreScripts** (capacite `RobloxScript`) : appele depuis un script
  normal il THROW "The current thread cannot call 'GetScreenResolution' (lacking capability RobloxScript)". Pour la
  resolution / le viewport, lire `workspace.CurrentCamera.ViewportSize` (accessible partout ; nil tot au boot -> garder un
  garde). Meme famille : plusieurs methodes de GuiService / des CoreGui sont CoreScript-only. Astuce bonus : distinguer
  TELEPHONE de TABLETTE se fait par le RATIO d'ecran (cote long / court : ~2:1 = phone, ~4:3 = tablette), pas par un seuil
  en pixels (le DPI le fausse). `TouchEnabled` seul ne suffit pas (il englobe les tablettes).

- **`ControlModule:GetMoveVector()` rend un vecteur en repere CAMERA-monde, PAS en repere monde absolu.** "Pousser le stick
  vers le haut" (ou W) = la direction AVANT de la camera, dont les composantes MONDE (X/Z) dependent de l'orientation. Tester
  un axe monde en dur (ex `mv.Z < -0.2` pour "avance") ne marche donc que dans UNE orientation. Vecu sur la grimpe d'echelle :
  ca montait sur PC (secours clavier `IsKeyDown(W)` qui, lui, est direct) mais PAS sur mobile des que l'echelle/camera ne
  faisait pas face a -Z. Regle : pour detecter "pousser vers l'avant" independamment de l'orientation, PROJETER le move
  vector sur le regard horizontal de la camera (`mv:Dot(camLookFlat)`), jamais lire un axe monde brut. Symptome trompeur :
  "marche au clavier, pas au doigt" -> on cherche un input tactile manquant alors que l'input arrive, c'est le REPERE du test
  qui est faux. Meme famille que le geste centre-corps mappe sur la position ecran du joueur.

- **Un prompt "suis-je PRES de X" se detecte par distance RADIALE, pas par une BOX orientee.** Deux box laterales (posees
  a un offset, orientees sur la longueur de l'objet) laissent des ANGLES MORTS : colle a un BOUT de l'objet, on tombe HORS
  box -> pas de prompt, et GROSSIR la box ne bouche pas le trou (elle reste au mauvais endroit). Vecu sur la PRISE d'echelle
  (prompt visible seulement colle a l'echelle). Fix : distance HORIZONTALE (X/Z) a une PART FIXE (RootPart, PAS `GetPivot`
  qui suit la bounding box decalee par les zones welded), sous un rayon reglable. Un seul nombre, aucun angle mort,
  independant de l'orientation du rig. Corollaire de COMMUNICATION : quand le joueur dit "mets le prompt plus LOIN", c'est
  la DETECTION qu'il veut etendre, pas la hauteur d'AFFICHAGE (offset Y) -- deux reglages sans rapport. J'avais monte
  l'offset (mauvais), il fallait etendre le rayon de detection.

- **Quand une vitesse est modulee par un MULTIPLICATEUR CYCLIQUE, le chiffre de la config ne veut plus rien dire.**
  Le deplacement au pas multiplie la vitesse par STEP_GLIDE entre deux poussees : a 0.25, WORK_SPEED = 13 donnait
  environ 5 studs/s ressentis, moitie moins que la marche normale, alors que la config annonce le contraire. Symptome
  trompeur : "c'est lent" envoie chercher dans le reglage de VITESSE, qui est innocent et parait meme genereux. Regle :
  avant de monter une vitesse, chercher qui la MULTIPLIE en aval, et calculer la moyenne sur un cycle -- pas la valeur
  de pointe. Meme famille que le plancher en studs qui inversait l'effet qu'il devait borner.
  SUITE (le piege du tour d'apres) : ce multiplicateur etait PARTAGE par les deux allures (replacement et coupe), donc
  le monter a accelere la coupe aussi, ce qu'on ne voulait pas. J'ai tente de rattraper en baissant CUT_SPEED d'un
  facteur CALCULE -- faux, parce que ce facteur depend de la cadence des pas, qui vit dans l'ANIMATION et pas dans la
  config : impossible a deduire, seulement a mesurer a l'oeil, donc devine et rate. La vraie reponse n'est pas de
  compenser, c'est de DECOUPLER : un knob par etat (STEP_GLIDE / STEP_GLIDE_CUT), chacun reglable sans toucher a
  l'autre. Regle generale : quand un reglage partage force a compenser ailleurs, le compensateur sera toujours une
  estimation ; dedoubler le reglage supprime le probleme au lieu de le rattraper.

- **Un mode a moitie branche donne un input qui tourne DANS LE VIDE : le code s'execute, l'ecran ne bouge pas.**
  `CAMERA_FIRST_PERSON = true` place l'oeil sans jamais lire `yaw` ni `cameraZoom` -- pourtant le clic droit posait bien
  `orbiting`, le yaw avancait, le ressort de rubber-band tournait. Tout marchait SAUF le consommateur final. Symptome
  trompeur : ca ressemble a un input casse (on va debuggeur InputBegan, la sensibilite, le gameProcessed) alors que
  l'input arrive parfaitement. Regle : quand un input "ne fait rien", verifier D'ABORD que quelqu'un LIT la variable
  qu'il ecrit -- en remontant depuis l'affichage, pas depuis la touche. Et un flag experimental qui court-circuite un
  chemin complet doit lister ce qu'il PERD, sinon la perte se decouvre a l'usage des mois plus tard.

- **Basculer un flag ne suffit pas : les REGLAGES cales pendant qu'il etait actif restent en place.** En repassant la
  camera de taille de 1re personne a iso, `UPDOWN_FOLLOW_SPEED` restait a 10 -- valeur montee de 6.5 a 10 DANS le
  commit de la 1re personne, parce qu'un oeil pose a la tete rend une visee stable qui supporte un ressort sec. En
  iso le rayon arrive de biais, le signal est plus nerveux, et le ressort raide l'amplifie : ca se ressent comme un
  "ciblage bugue" alors que rien n'est casse. Se trouve en une commande, `git log -S "<le flag>" -- <fichier>` puis
  la liste des valeurs modifiees par ce commit -- ne pas chercher a l'oeil dans une config de 1100 lignes. Regle :
  revenir a un ancien mode = revenir aussi a ses reglages. Corollaire : un mode qui MASQUE un effet (ici la 1re
  personne cachait le perso, donc le fantome WORK_FADE) le fait passer pour un bug NEUF quand on quitte ce mode.

- **Deux references vers "la meme chose" finissent par diverger, et en CROISER deux donne un resultat qui n'existe
  nulle part.** La haie visee existe en deux exemplaires : `lastHedge` (celle que le CURSEUR a survolee en dernier) et
  `workHedge` (celle que le SERVEUR a accrochee). Identiques quand il n'y a qu'une haie -- donc le bug dort pendant
  tout le prototypage -- differentes des qu'il y en a deux. La projection de la bille prenait les DIMENSIONS de l'une
  avec la NORMALE de l'autre : le plan obtenu ne correspond a aucune haie reelle, et la bille se pose a cote.
  Symptome trompeur : "le curseur ne suit pas la souris" fait aller verifier la lecture de la souris
  (GetMouseLocation, inset, ViewportPointToRay) qui est parfaitement juste -- c'est la CIBLE qui est fausse, pas la
  lecture. Regle : quand deux variables designent le meme objet du monde, tout calcul doit les prendre TOUTES LES
  DEUX de la meme source ; faire passer la source en argument plutot que la lire en upvalue rend le couplage visible.

- **Un skinned mesh qui explose a l'import Roblox : compter les OS PAR SOMMET avant toute autre piste.** Roblox
  plafonne a **4 os par sommet** ; Blender ("Automatic Weights") en distribue autant qu'il veut. Au-dela, Roblox
  garde 4 poids et NE RENORMALISE PAS : les sommets partent n'importe ou. Vecu sur des arbres riggés : jusqu'a 9
  influences, et **100 % des sommets des FEUILLES** au-dessus de 4 alors que les TRONCS etaient presque tous
  conformes -- ce qui collait exactement a l'ecran (troncs a peu pres corrects, feuillages en confettis). Ce
  contraste feuilles/troncs EST le diagnostic : ne pas aller chercher le rig, l'orientation ou l'export. Fix :
  `Limit Total` a 4 PUIS `Normalize All` (dans cet ordre -- normaliser avant de couper laisse une somme de poids
  inferieure a 1, donc des sommets qui retrecissent). Deuxieme piege du meme fichier : des sommets **sans aucun
  poids** (103 et 206 sur deux troncs) restent colles a l'origine et fabriquent de longues pointes etirees ; les
  rattacher a l'os le plus proche. Troisieme : une **echelle d'armature non appliquee** (0.0061) donnait un arbre
  de 5,8 cm au lieu de 9,4 m. Et pour la corriger, ne scaler QUE l'ARMATURE : les meshes en sont ENFANTS, scaler
  les deux applique le facteur au carre (163 devient 26 500, l'arbre fait 3 km). Enfin, un FBX a PLUSIEURS
  armatures donne UN SEUL Model Roblox avec tous les arbres fusionnes : un arbre = un fichier. ET en decoupant
  un tel fichier, RECENTRER chaque objet sur l'origine : les modeles y sont poses COTE A COTE, remettre a
  l'echelle multiplie aussi leur POSITION (x163 -> 15 studs de l'origine), et Studio prend alors une boite qui
  va de l'origine jusqu'au modele -- l'objet apparait minuscule dans un coin d'une enorme selection. Ne pas
  confondre avec l'ecart NORMAL entre l'os racine (au pied du tronc) et le centre de la boite (a mi-hauteur).

- **`rojo build` ne VALIDE PAS le Luau : il empaquette, il ne parse pas.** Un fichier avec une faute de syntaxe
  grossiere (ici une deuxieme ligne de commentaire sans son `--`) passe le build sans un mot, et l'erreur ne sort
  qu'au LANCEMENT, dans la console Studio, sous la forme d'un module qui refuse de se charger. Ne jamais annoncer
  "build OK donc la syntaxe est bonne" -- c'est faux, et ca a ete affirme trois fois de suite ici. Le vrai controle
  est `selene src` (0 parse errors). Il est declare dans `rokit.toml` mais peut ne pas etre INSTALLE : `rokit
  install` refuse tant que l'outil n'est pas approuve (`rokit trust <auteur>/<outil>`). Corollaire : nettoyer les
  warnings de selene au fur et a mesure, un linter qui crie pour rien finit ignore -- meme lecon que cSpell.

- **`ControlModule:GetMoveVector()` rend un vecteur RELATIF A LA CAMERA, pas un vecteur monde : X = cote, Z =
  ARRIERE.** C'est precisement pour ca que `Humanoid:Move(v, true)` existe -- le second argument demande a Roblox
  d'y appliquer la camera. On lit donc ses composantes DIRECTEMENT (`avance = -mv.Z`, `cote = mv.X`) ; les
  PROJETER sur des axes monde (`mv:Dot(camLookFlat)`) melange deux reperes. Symptome vecu sur la conduite de la
  tondeuse : appuyer sur AVANCER produisait une composante laterale fantome qui dependait de l'orientation de la
  vue, et la machine partait en virage sans qu'on touche aux touches de cote -- "la camera influence le
  deplacement". Note precedente a corriger : l'entree qui parlait de "repere CAMERA-monde" etait ambigue et m'a
  fait faire exactement cette faute. Le secours clavier de `MoveInput` suit la MEME convention (W -> z -= 1), donc
  les deux chemins se lisent pareil. A REVERIFIER : LadderMoveController projette encore sur le regard de la
  camera -- ca marche tant que la camera regarde vers -Z, ce qui est le cas par defaut.

- **Ne jamais DERIVER une valeur recue du reseau : elle est interpolee, donc sa derivee est bruitee ET change de
  SIGNE.** Vecu sur le ballant de la tondeuse : le serveur calculait "combien le joueur a tourne depuis l'image
  d'avant" a partir du cap REPLIQUE. Deux symptomes successifs, meme cause : d'abord un TREMBLEMENT en tournant
  (bruit de la derivee), puis -- une fois le resultat lisse -- un ZIG-ZAG a l'arret du virage, parce que
  l'interpolation DEPASSE la cible puis se corrige et que la derivee s'inverse. Un filtre attenue le bruit, il ne
  peut RIEN contre une inversion reelle du signal. Regle : quand une valeur d'INTENTION existe (ici l'input de
  braquage, deja envoye par le client), lire l'INTENTION et pas la consequence observee. Bonus : ca a supprime
  trois mecanismes (derivee, pivot a l'arret, filtre) au profit d'un seul, donc deux cas qui ne peuvent plus se
  contredire.

- **Le thumbstick tactile de Roblox SE TAIT des qu'une feature prend la camera en main.** `GetMoveVector()` rend
  ZERO, donc sur mobile le joueur ne peut plus bouger DU TOUT -- et rien ne le signale : l'input arrive bien au
  jeu, il n'arrive juste plus jusqu'a nous. Constate sur le travail de haie, puis re-paye entierement sur la
  tondeuse. La reponse est un joystick A NOUS (`Modules/UI/Core/MoveThumb`), allume par la feature concernee.
  Corollaire de diagnostic : quand une machine ne bouge pas, TROIS causes donnent le meme symptome (input absent,
  etat pas vu, vitesse a zero) et se corrigent a trois endroits differents -- afficher les trois d'un coup coute
  cinq minutes et evite trois allers-retours. Et l'AFFICHER A L'ECRAN, pas dans la console : un bug qui n'existe
  que sur mobile ne se diagnostique pas dans une console qu'on ne peut pas lire sur un telephone.
- **Convertir une position de DOIGT en position d'INTERFACE est un pari a 50 %, et il se perd.** `InputObject.
  Position`, `GetMouseLocation()` et les coordonnees d'un ScreenGui ne comptent pas forcement la barre du haut de
  la meme facon, et le sens ne se DEDUIT pas. Quatre tentatives de recalage sur le joystick mobile, dont deux qui
  ont AGGRAVE le decalage. La sortie n'est pas de trouver le bon signe : c'est de ne plus avoir a convertir --
  poser l'element a une place FIXE en fraction d'ecran (juste sur tous les formats par construction) et ne lire
  que des DELTAS (une difference annule n'importe quel decalage de repere sans avoir a le connaitre). Regle
  generale : quand une correction echoue plusieurs fois de suite au meme endroit, ce n'est pas la valeur qui est
  fausse, c'est la question.

- **Le `InputBegan` d'un element d'interface recoit AUSSI les doigts qui ont commence AILLEURS et qui glissent
  dessus.** Sans tester `input.UserInputState == Enum.UserInputState.Begin`, un joystick tactile capture le doigt
  qui tourne la camera des qu'il passe au-dessus -- et comme ce doigt n'a pas commence la, rien ne bouge ensuite.
  Symptome : "ca marche parfois", en fonction du trajet de l'autre pouce. Corollaires du meme code : utiliser
  `UserInputService.TouchMoved` / `TouchEnded` et PAS `InputChanged` / `InputEnded` (seuls les premiers tirent de
  facon fiable pour un geste commence SUR un element), et relacher sur `GuiService.MenuOpened` (le menu Roblox vole
  le doigt, dont le toucher ne se termine alors JAMAIS). Tout ca est ecrit dans le `TouchThumbstick` du PlayerModule,
  que Roblox fournit en SOURCE : quand un comportement d'input surprend, aller le lire coute dix minutes et bat
  n'importe quel raisonnement.

- **Un reglage qui sert DEUX moments differents finira par les opposer.** Motif rencontre quatre fois dans la meme
  journee : hauteur ET emprise au sol de l'herbe tondue (un seul facteur -> soit trop haute, soit des trous),
  arrivee ET retour d'une camera scriptee (une seule duree -> soit ca traine, soit ca claque), delai ET vitesse de
  la coupe, sortie de terre ET abaissement d'une touffe (un seul compteur -> retarder l'un enfouissait l'autre,
  donc un TROU visible dans la pelouse). A chaque fois le symptome ressemble a un mauvais REGLAGE, et on passe du
  temps a chercher la bonne valeur -- alors qu'aucune valeur ne peut satisfaire deux besoins opposes. Dedoubler
  supprime le probleme au lieu de l'arbitrer, et coute une ligne. Signal d'alerte : des qu'on se surprend a
  "compenser" un reglage en tournant un autre, ils sont deja en train de se battre.

- **Rojo pousse le disque LOCAL vers Studio et REMPLACE : le dernier qui connecte gagne.** Le collaborateur, dont
  le depot etait en retard, a lance son `rojo serve` : l'herbe, la tondeuse et le tuto recent ont DISPARU de
  Studio, remplaces par l'ancienne version -- aucune erreur, juste un « Accepter » dans le plugin. Reconnecter
  depuis un depot A JOUR a tout remis, ce qui fait croire a un bug fantome ("ca s'est repare tout seul") alors que
  c'est le fonctionnement normal. Regle : `git pull --rebase` AVANT `rojo serve`, toujours ; et si le diff du
  plugin propose de SUPPRIMER des fichiers recents, on est en retard, on refuse. Le vrai danger n'est pas la
  session Studio (reversible) mais de PUBLIER dans cet etat : l'ancien code part chez les joueurs, et la une
  reconnexion Rojo ne repare plus rien. Indice qui pointe droit sur la cause : le CODE recule pendant que la MAP
  reste bonne -- Rojo ne synchronise que `src/`.

## Design emotionnel

### L'emotion centrale de Leafia

**A REMPLIR PAR MOI.** Ma proposition, a valider ou remplacer :

> **SATISFACTION.** Le joueur voit le desordre devenir propre, par son geste, immediatement. Avant / apres.
> C'est l'emotion la plus fiable a produire, parce qu'elle ne depend d'AUCUN autre joueur — contrairement au
> combat du projet precedent, qui exigeait que les autres osent attaquer.

Emotion secondaire proposee : **FIERTE** (mon entreprise grandit, et ca se voit).

Tant que cette section n'est pas figee, on ne code pas de systeme.

### Regles de design emotionnel

- Chaque etape de la boucle doit declencher une emotion identifiable.
- **Sans enjeu, pas d'emotion.** Lecon directe du projet precedent : quand mourir ne coutait rien, tuer ne
  rapportait rien, et le jeu devenait "calme". Ici : si un chantier rate n'a aucune consequence, le reussir
  n'aura aucune saveur. Il faut quelque chose a perdre (temps, reputation, note du client, materiel qui
  s'use). A doser, mais jamais zero.
- Le record / la note du client apres chaque chantier = motivation automatique.
- La friction entre deux chantiers doit etre minimale (objectif : < 15 secondes).
- Une attente peut etre intentionnelle : elle cree l'impatience, pas l'ennui.
- Toujours tester : "qu'est-ce que le joueur ressent a cette etape ?"

### Schema de boucle (a figer avant de coder)

Action -> Emotion declenchee -> Consequence -> Nouvelle emotion -> Repetition

## Progression & retention

- **Simplicite** : zero friction. Le joueur peut jouer direct. Objectifs clairs, UI comprehensible.
- **Flow** : progression rapide au debut, puis equilibree sur le long terme.
- **Euphorie du debutant** : au lancement, chaque action rapporte gros. Le joueur se sent competent tout de
  suite.
- **Controle de l'inflation** : ralentissement progressif. Niveau 10 -> 11 rapide, 99 -> 100 tres dur. Sinon
  le late game devient trivial.
- **Illusion de fluidite** : toujours un palier proche, meme quand ca ralentit. Le joueur optimise au lieu de
  grinder betement.
- **Ce que le joueur POSSEDE entre deux sessions** est ce qui le fait revenir. Pas le fun de la session : le
  fun fait rester, la possession fait revenir. A chaque feature, se demander : qu'est-ce que ca laisse au
  joueur demain matin ?

### Rarete & regulation des recompenses

Lecon apprise en live : **tout donner facilement = ennui immediat = le joueur part et ne revient pas.**

- **Reguler CHAQUE source de recompense.** Pas de gain passif. **Zero recompense sans PARTICIPATION** (rester
  AFK ne doit jamais rapporter).
- **La vraie rarete doit etre RARE.** Un objet d'exception est un evenement, pas un truc vu toutes les 30 s.
- **Tout en vert (achetable) = signal d'ennui.** Il faut TOUJOURS du rouge (trop cher) et du verrouille a
  l'ecran : c'est ca qui donne un objectif.
- **Gater les objets forts** derriere une condition ET un prix eleve. L'accessibilite se MERITE.
- Boucle a proteger : Manque -> Desir -> Effort -> Recompense. Le piege mortel = Abondance -> Ennui.
- **Regle par defaut** : dans le doute, donner MOINS. On peut desserrer plus tard ; reprendre est vecu comme
  un nerf.

## Monetisation

**Ne rien monetiser tant que la retention J1 n'est pas saine.** Monetiser un jeu qui ne retient pas revient a
remplir un seau perce. Ordre correct : reparer le seau, puis ouvrir le robinet.

Quand le moment viendra :

- Boucle claire « action -> attente -> recompense -> repetition », avec une option payante pour **accelerer**,
  jamais pour contourner l'autorite serveur.
- Toujours un chemin **gratuit jouable** en parallele de l'accelerateur payant.
- Pas de pub payante tant que le J1 organique n'est pas mesure. La pub masque le signal et vide la caisse.

## Points d'entree (boot)

- **Serveur** : `ServerScriptService.Server` (Script) = `src/ServerScriptService/Server/init.server.luau`.
  Les services sont ses ENFANTS -> `require(script.JobService)`.
- **Client** : `StarterPlayerScripts.Client` (LocalScript) = `src/StarterPlayerScripts/Client/init.client.luau`.
  Les controllers sont ses ENFANTS -> `require(script.CameraController)`.

Un seul bootstrap de chaque cote. Ils declarent les modules **un par un**, explicitement, dans l'ordre voulu :
quand un module en attend un autre, l'ordre se lit en clair dans le fichier.

**Le bootstrap ne contient AUCUNE logique de gameplay.** Des qu'une regle de jeu apparait dedans, elle part
dans son propre service.

## Conventions de nommage (a respecter partout)

| Suffixe | Ou | Role |
|---|---|---|
| `XxxService` | `Server/` | Logique serveur d'une feature (autorite) |
| `XxxController` | `Client/` | Logique client d'une feature (input, camera, FX) |
| `XxxHandler` | `Modules/UI/Xxx/` | Pilote une interface precise |
| `XxxConfigs` | `Modules/Configs/` | Table de data pure, zero logique |
| `XxxUtils` | `Modules/Utils/` | Fonctions pures reutilisables |
| `XxxClass` | `Shared/Classes/` | POO (metatables), instancie par `new` |

## Architecture des dossiers

Le dossier `src/` reproduit l'arborescence Studio : ce qu'on voit dans l'Explorer est ce qu'on voit sur le
disque.

### ReplicatedStorage (`src/ReplicatedStorage`)

- `Modules/Configs` — configs pures : plantes, outils, clients, prix, courbes.
- `Modules/Utils` — utilitaires purs (`FormatUtils`, `MathUtils`, `Services`...).
- `Modules/UI/Core` — primitives UI reutilisables (blur, sons, tweens, layers, toasts).
- `Modules/UI/<Feature>` — un `<Feature>Handler` par interface.
- `Shared/RemoteSetup` — declaration CENTRALE des remotes, rangee par feature.
- `Shared/Classes` — classes partagees.
- `Assets` — models, VFX, sons, animations (cote Studio, Rojo n'y touche pas).
- `Packages` — dependances wally.

### ServerScriptService (`src/ServerScriptService`)

- `Server/init.server.luau` — bootstrap.
- `Server/<Feature>Service.luau` — un service par feature.
- `Server/<Groupe>/` — sous-dossier quand une feature a plusieurs services.

### StarterPlayerScripts (`src/StarterPlayerScripts`)

- `Client/init.client.luau` — bootstrap.
- `Client/<Feature>Controller.luau` — un controller par feature.
- `Client/Utils/` — utilitaires purement client (VFX, effets de degats).

### StarterGui

Les ScreenGui sont crees dans **Studio**, pas en code. Rojo les ignore grace a `$ignoreUnknownInstances`,
donc ils ne sont jamais ecrases.

### Regles

- 1 feature = 1 Service + 1 Controller (+ un Handler si elle a une interface).
- Le client ne fait que UI / FX / prediction. **Le serveur decide** (economie, achats, inventaire, sauvegarde).
- Un remote ne s'ajoute a `RemoteSetup` que quand une feature en a REELLEMENT besoin. Pas de remote « au cas
  ou » : ils deviennent des morts qu'on n'ose plus supprimer.

## Style code Luau

- Projet en `--!strict` sur **tous** les modules. Soigner les types et les retours de fonctions.
- Nommage : `camelCase` (prive / local), `PascalCase` (public / types exportes), `SCREAMING_SNAKE`
  (constantes).
- Reseau / DataStore : `pcall` obligatoire ; `WaitForChild` avec **timeout** quand ca peut bloquer.
- **Pas** de `script.Parent` pour enchainer les `require` (sauf entre sous-modules du meme dossier).
- POO tables / metatables : pattern `new` / `Init` coherent ; `require` et types **en tete de fichier**, jamais
  dans le corps des fonctions.
- **Jamais appeler une fonction au-dessus de sa definition.**
- Code compact : pas de `Init()` vide ni de boilerplate inutile.
- Pas de `_G`.
- Logs : prefixe `[NomModule]`. **Ne warn que sur ce qui est A LA FOIS anormal ET actionnable** — un warn sur
  un evenement normal (streaming, asset volontairement absent) pollue la console et finit par etre ignore.

## Securite & perf

- **Valider cote serveur** chaque argument des Remotes. Le client ment toujours.
- Anti-fuites : `Disconnect` des connexions, nettoyage a `PlayerRemoving` et a la destruction des instances.
  Attention aux connexions posees sur un objet qui SURVIT au script (camera, workspace) : elles doivent etre
  coupees explicitement.
- **Effets UI en boucle : TOUJOURS les couper quand ce n'est plus affiche.** Un `Stop()` a la **fermeture** de
  l'interface, pas seulement a la destruction : une interface cachee continue de faire tourner ses boucles.
  - Ne jamais demarrer une boucle dans la fonction qui remplit l'UI (elle est souvent appelee interface
    fermee). Separer « remplir le visuel » de « lancer/couper les boucles ».
  - Couper l'effet **avant** de detruire/remplacer sa cible.
- **Ne jamais envoyer un remote a un joueur qui ne peut pas encore ecouter.** Les scripts de `StarterGui` ne
  sont copies dans `PlayerGui` qu'au **spawn** : avant ca, personne n'ecoute et la file de Roblox sature
  ("invocation queue exhausted"). Cote serveur, verifier que le joueur est reellement en jeu avant d'emettre.
- **Surveiller le FPS client.** En dessous de 45, le joueur ressent que "ca repond mal" sans savoir le nommer,
  et il part. C'est un tueur de retention invisible dans les retours joueurs.
- Duplication : si la meme logique apparait deux fois, centraliser (UN module, appele depuis les autres).
- **Automatisation & reutilisation** : privilegier UN module fonctionnel appele partout, plutot que la meme
  logique eparpillee. Avant d'ecrire une nouvelle logique, chercher si une fonction existante fait le job.

## Commentaires

- Rares et utiles. Francais **sans accents** dans les commentaires de code.
- Pas de commentaire `-- Path: ...` en tete de module.
- Un commentaire explique **pourquoi**, pas **quoi**. Le quoi se lit dans le code.
- **Un commentaire faux est pire que pas de commentaire.** Le mettre a jour quand on change le code autour.

## Contenu joueur (textes affiches)

- **TOUT texte vu par le joueur s'ecrit en ANGLAIS.** Dialogues, notifications, boutons, titres, messages d'erreur :
  tout. Raison : le traducteur automatique de Roblox part de l'anglais. Un texte ecrit en francais n'est traduit
  nulle part, et le jeu devient illisible pour la quasi-totalite des joueurs de la plateforme.
  Les COMMENTAIRES de code, eux, restent en francais (voir la section Commentaires).
- **Ne jamais citer de noms de jeux connus.** Formulations generiques.
- **Le public, c'est des ENFANTS (Roblox).** Vocabulaire simple, mots du quotidien. Eviter les termes d'adulte qu'un
  gosse ne connait pas (ex : "retraite", "releve", jargon). Dans le doute, dire la chose CONCRETEMENT (ex : "trop vieux,
  mal au dos" plutot que "en retraite"). Un mot qu'un enfant ne comprend pas casse l'immersion.
- Pas de tiret cadratin en milieu de phrase. Couper en phrases nettes.
- Tenir `CHANGELOG.md` (append-only, ne jamais effacer) a chaque feature.
