# Leafia — Conventions & comportement assistant

## Le jeu en une phrase

Le joueur est **paysagiste**. Il va chez des clients, taille des haies et des arbustes, repart avec un cheque,
et fait grandir son entreprise — seul ou en CO-OP.

## LA REGLE D'OR DE CE PROJET

**Le geste de tailler doit etre jouissif AVANT qu'on code quoi que ce soit d'autre.**

Pas d'UI, pas de tycoon, pas de coop, pas de monetisation, pas de sauvegarde tant que tailler une haie et voir
la forme changer ne donne pas envie d'en tailler une deuxieme.

Cette regle vient de deux echecs reels (Bird Game, League Of BattleCar). Dans les deux cas le meme motif : un
probleme au coeur du jeu, recouvert par des interfaces de plus en plus soignees, et une retention au sol. Les
interfaces etaient belles. Elles n'ont jamais rien repare.

**Si l'assistant voit qu'on ajoute une feature alors que le coeur n'est pas valide, il doit le dire.**

Corollaire : le test n'est pas "est-ce que ca marche" mais "est-ce que trois personnes reelles en retaillent
une deuxieme sans qu'on leur demande". Tant que la reponse est non, on ne construit pas par-dessus.

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

- **Ne jamais citer de noms de jeux connus.** Formulations generiques.
- Pas de tiret cadratin en milieu de phrase. Couper en phrases nettes.
- Tenir `CHANGELOG.md` (append-only, ne jamais effacer) a chaque feature.
