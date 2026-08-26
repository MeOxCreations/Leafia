# Changelog — Leafia

Append-only. On n'efface jamais une entree, on ajoute par-dessus.

## 0.0.1 — Base du projet

- Arborescence Rojo (`Leafia.project.json`), selene, wally.
- Bootstraps serveur et client (chargement auto de `Services/` et `Modules/`).
- `Services.luau` (raccourcis vers les services Roblox).
- `CLAUDE.md` : conventions, regle d'or (valider le geste avant tout le reste), lecons des projets precedents.

### Prochaine etape

Prototype du geste de taille. Aucune UI, aucun tycoon, aucune sauvegarde tant qu'il n'est pas valide par trois
joueurs reels.

## 0.0.2 — Ecran de chargement

- `src/ReplicatedFirst/LoadingScreenClient.client.luau` : intro de Leafia (logo en slime, onde de choc,
  4 points qui rebondissent en vague, reflet sur le logo, skip clavier + bouton).
- Adapte depuis le projet precedent. Change par rapport a la source :
  - Aucun require vers `ReplicatedStorage`. `ReplicatedFirst` se replique en premier ; attendre un module de
    `ReplicatedStorage` reviendrait a bloquer sur ce qu'on masque. Le fichier est autonome.
  - Sons entierement optionnels (rien dans `SoundService` pour l'instant), sans warn : un asset volontairement
    absent qui gueule dans la console finit par masquer les vrais warns.
  - Noms d'instances alignes sur l'arbre Studio de Leafia (`FontTile`, `CopyRightText`).
  - `--!strict`, types explicites.
  - Les deux connexions `Heartbeat` sont maintenant coupees a la sortie. Elles vivent sur `RunService`, pas sur
    le GUI : le `Destroy` ne les touchait pas et elles tournaient toute la session.
  - Sortie : boucles coupees avant le fondu de leurs cibles, fondu sonore de la musique.
  - Tips reecrits pour Leafia, aucun nom de jeu connu cite.
- Chat et liste des joueurs masques pendant le chargement (CoreGui + `TextChatService`). Etat d'origine
  memorise et rendu a la sortie, jamais force. Filet de securite a 60 s : si le script meurt, le chat revient
  quand meme.
- `.vscode/settings.json` : `luau-lsp.sourcemap.autogenerate` passe a `true` (le sourcemap n'etait genere par
  personne, le LSP cherchait un fichier absent).

## 0.0.3 — Outils

- `rokit.toml` a la racine : Rojo epingle en 7.7.0 pour Leafia uniquement (avant, la version venait de
  `~/rokit.toml` et une mise a jour aurait touche tous les projets).
- `CLAUDE.md` : nouvelle section "Journal d'apprentissage".
- `Modules/Utility/MathUtils.luau` : `lerp`, `normalizeAngle`, `shortestAngle`.
  - Reprises du projet precedent mais NON portees : `clamp` et `sign` (doublons de `math.clamp` / `math.sign`),
    `mphToStudsPerSecond` (specifique aux vehicules, sans objet ici).
  - `normalizeAngle` passe de la boucle `while` au modulo : un angle accumule peut valoir des milliers de
    degres, la boucle faisait alors des milliers de tours.
  - `shortestAngle` appelle `normalizeAngle` au lieu de redupliquer le meme corps de boucle.

## 0.0.4 — Renommage Utility -> Utils

- `Modules/Utility/` devient `Modules/Utils/`. Le chemin cite dans l'entree 0.0.3 est donc caduc.
- `CLAUDE.md` et `README.md` mis a jour. Aucun `require` ne pointait encore dessus, renommage sans risque.
- Au passage : `Utilitary` (utilise sur le projet precedent) n'existe pas en anglais. A ne pas reintroduire.

## 0.0.5 — FormatUtils

- `Modules/Utils/FormatUtils.luau` : `Abbreviate` (1010 -> "1.01K", 1454000 -> "1.45M").
  Repris de `FormatNumbers` du projet precedent, renomme pour suivre la convention `XxxUtils`.
- **Bug corrige** : `999999` affichait "1000K" au lieu de "1M". `999999 / 1000 = 999.999`, que `%.2f` arrondit
  a "1000.00". Rattrapage ajoute apres le formatage. Meme cas pour `999999999` -> "1B".
- Calcul du palier : division successive au lieu de `math.log(abs, 1000)`. Le logarithme passe par une
  division de flottants ; aux puissances exactes (1e6, 1e9) un ecart d'un ulp fait retomber d'un cran.
- `MathUtils` passe en PascalCase (`Lerp`, `NormalizeAngle`, `ShortestAngle`). L'entree 0.0.3 citait des noms
  en camelCase : c'etait une erreur, `CLAUDE.md` impose PascalCase pour le public.

## 0.0.6 — Outil en main + effet de spawn

Premier morceau de gameplay. Prerequis au test du geste de coupe : on ne peut rien tailler sans outil.

- `Modules/Configs/ToolConfigs.luau` — data pure d'un outil (asset, main, handle, effet, nombre de
  particules, nombre de tirages au demarrage).
- `Server/ToolService.luau` — autorite : clone l'outil, cree le `Motor6D`, nettoie. Donne le taille-haie a
  l'apparition (temporaire, il n'y a pas encore d'inventaire).
- `Client/ToolController.luau` — joue l'effet d'apparition. Generique : il lit le nom de l'effet dans la
  config, il ne connait aucun outil en particulier.

### Choix a retenir

- **Aucun remote.** Le serveur pose un attribut `LeafiaTool` sur le modele ; le client reagit a son apparition.
  Un remote envoye au spawn arriverait avant que les scripts du joueur ecoutent (cf `CLAUDE.md`). Le modele se
  replique tout seul, l'attribut suit, il n'y a rien a transmettre en plus.
- **Le client balaye les enfants existants en plus d'ecouter `ChildAdded`.** Sans ca le tout premier
  equipement de la session n'aurait jamais d'effet, puisqu'il a lieu avant que le controller demarre.
- **Point de prise par Attachment**, pas par CFrame codee en dur : `RightGripAttachment` cote main (livree par
  Roblox sur tout R15) et une Attachment `Grip` a poser dans le Handle. Se regle a la souris dans Studio.
- **`EmitCount` surchargeable par emetteur** via un attribut pose dans Studio. Une onde de choc veut 1
  particule la ou des braises en veulent 20 ; un chiffre unique pour tous donne un resultat rate d'un cote ou
  de l'autre.
- **`pullsToStart` est une caracteristique de l'OUTIL**, pas une constante du jeu. Un outil pourri demande 4
  tirages, un outil pro demarre au premier : le joueur ressent son upgrade dans ses mains. Valeur presente
  mais pas encore utilisee.

### Prochaine etape

La haie et le fait de la couper. C'est la seule question qui decide si le jeu existe.

## 0.0.7 — Touche d'equipement + pose de maintien

- Touche **1** pour ranger / sortir l'outil. Remote `Tool/ToggleTool`, premier remote du projet.
- `IdleAnimation` jouee tant que l'outil est en main (`holdAnimation` dans `ToolConfigs`).
- `ToolConfigs` gagne `animationFolder` et `holdAnimation`.

### Choix a retenir

- **Le client n'envoie AUCUN argument.** Il dit "j'ai appuye", rien d'autre. Le serveur sait deja ce que le
  joueur tient : il n'y a rien a valider parce qu'il n'y a rien a falsifier.
- **Animation jouee cote serveur.** Elle se replique alors a tout le monde depuis une source unique. Jouee
  par le client, elle ne partirait que pour le personnage dont il a l'autorite reseau.
- **Cooldown de 0.35 s sur le toggle.** Touche maintenue = clone et destruction chaque frame, effet de spawn
  en stroboscope.
- **`gameProcessed` teste sur l'input.** Sans ca, taper "1" dans le chat range l'outil.
- **`held[player]` remis a nil a chaque respawn.** La mort detruit le personnage donc l'outil, mais la table
  gardait une entree pointant sur un modele mort, et le toggle suivant croyait ranger un outil deja disparu.
- **La piste d'animation est coupee AVANT la destruction du modele**, sinon le joueur reste fige dans une pose
  de porteur les mains vides.

## 0.0.8 — Vitesse de marche + orientation de l'outil

- `Modules/Configs/CharacterConfigs.luau` + `Server/CharacterService.luau` : `WalkSpeed` a 10 au lieu des 16
  par defaut de Roblox, qui sont une course. Applique cote serveur : le client peut ecrire dans son propre
  Humanoid, une valeur posee la-bas ne serait qu'une suggestion.
- `ToolConfigs.gripOffset` : correction d'orientation appliquee apres l'Attachment `Grip`.

### La regle du Motor6D, pour ne plus la rechercher

`Handle.CFrame = Hand.CFrame * C0 * C1:Inverse()`

Avec `C1` = l'Attachment `Grip`, ce Grip vient se coller pile sur le point de prise de la main, axes alignes.
Donc **l'orientation de l'outil dans la main EST celle de l'Attachment `Grip`**. Si la lame pend, c'est
l'Attachment qui est mal tournee. `gripOffset` corrige sans avoir a la tourner a la souris dans Studio.

`CharacterService` est separe de `ToolService` : la vitesse de marche n'a rien a voir avec ce que le joueur
tient dans les mains.

## 0.0.9 — Priorite de la pose de maintien

- `ToolConfigs.holdPriority` : la pose passe de `Idle` a `Action`. Roblox joue la marche en `Movement`, donc
  toute pose en dessous disparait des que le joueur avance.
- `gripOffset` reecrit en `math.rad(116.62)`. La valeur ecrite etait `CFrame.Angles(90, 0, 0)`, ce qui se lit
  comme 90 degres mais vaut 90 RADIANS, soit 14 tours plus 116.62 degres. Le rendu etait bon par hasard ;
  la ligne dit maintenant ce qu'elle fait.

### Piege a retenir

**`CFrame.Angles` attend des radians.** Toujours passer par `math.rad()`. Un nombre nu ressemble a des degres
et n'en est pas.

**Une pose en priorite `Action` ecrase aussi les jambes** si l'animation les cle. Une pose de maintien ne doit
cler que les bras et le torse, sinon le joueur glisse sans bouger les pieds.

## 0.0.10 — Correction : pose absente au premier equipement

Symptome : l'animation de maintien ne partait pas a l'apparition, mais fonctionnait apres un rangement/sortie
manuel a la touche 1.

Cause : **l'`Animator` n'existe pas encore a `CharacterAdded`**, Roblox le cree quelques frames plus tard.
`playHoldAnimation` faisait un `FindFirstChildOfClass("Animator")`, recevait `nil`, et abandonnait **en
silence**. Au toggle manuel, l'Animator etait la depuis longtemps, donc ca marchait.

Correction : `WaitForChild("Animator", 5)` en repli, et un `warn` si l'attente echoue.

### Piege a retenir

**Ne pas supposer qu'un enfant existe a `CharacterAdded`.** Le modele est parente avant que ses enfants soient
tous la. Le symptome est trompeur : ca marche des qu'on refait l'action a la main, donc on cherche du cote de
l'action au lieu du timing.

**Un echec silencieux coute plus cher qu'un warn.** Ce bug a ete trouve par le joueur, pas par la console,
parce que le code renvoyait `nil` sans rien dire. Un abandon ANORMAL et ACTIONNABLE doit toujours warn.

## 0.0.11 — Plus d'equipement automatique

`AUTO_EQUIP_ON_SPAWN = false`. Le joueur sort son outil a la touche 1, rien ne lui est donne a l'apparition.

Deux raisons :

1. **Design.** Sortir son outil est un geste du joueur. Il decide quand il commence a travailler.
2. **Technique.** Ca supprime la course au lieu d'essayer de la gagner. A l'apparition, ni l'`Animator` ni la
   replication du personnage ne sont prets : la pose de maintien partait dans le vide. Le correctif 0.0.10
   (`WaitForChild` sur l'Animator) reste en place et reste juste, mais il ne suffisait pas — l'animation
   jouee cote serveur a l'instant meme du spawn n'atteint pas toujours le client.

`lastToggle` est aussi remis a nil au respawn, sinon le cooldown d'un ancien appui pouvait manger le premier
appui apres une mort.

### Piege a retenir

**Ne pas courir vaut mieux que courir vite.** Face a une course au demarrage, se demander d'abord si l'action
doit vraiment avoir lieu a cet instant. Supprimer le besoin bat toujours la synchronisation.

## 0.0.12 — Demarrage du moteur

Clic gauche = tirer le lanceur. Il faut `pullsToStart` tirages (4) avant que le moteur parte.

- `Server/ToolStateService.luau` — machine a etats `Holding -> Starting -> Running`.
- `ToolService` refactore : il ne gere plus que l'objet tenu (clone, prise, animations). Il expose
  `getHeld`, `setHand`, `playCharacterAnimation`, `playToolAnimation`, `onUnequip`.
- `ToolConfigs` gagne `offHandPart`, `startAnimation`, `readyAnimation`, `toolRunAnimations`.
- Remote `Tool/ActivateTool`, sans argument lui aussi.

### Choix a retenir

- **Le changement de main se fait sur un MARQUEUR d'animation, pas sur un delai.** Un `task.wait(0.4)` se
  decale des qu'on retouche l'animation ; un marqueur reste colle a sa frame. Et pose a l'instant ou les deux
  mains se rejoignent, le passage est invisible : aucune distance a parcourir.
  Marqueurs a poser dans Studio : `SwapToLeft` et `SwapToRight`.
- **`setHand` repointe `Part0` du Motor6D existant** au lieu de le detruire et le recreer. Recreer casserait
  toute animation en cours sur cette chaine.
- **La reussite est decidee AVANT de jouer l'animation.** Sinon il faudrait enchainer un echec puis une
  reussite, et le joueur verrait deux gestes au lieu d'un.
- **Filet a la fin de chaque tirage** : `setHand(handPart)` est rappele meme si le marqueur de retour manque.
  Sans ca, une animation sans marqueur laisserait l'outil coince dans la mauvaise main.
- **Un clic pendant `Starting` est ignore, pas empile.** Deux gestes superposes donnent un bras qui tremble au
  lieu d'un joueur qui insiste.
- **Avertissement des marqueurs emis UNE SEULE FOIS** par animation. A chaque tirage, il noierait la console
  et reviendrait a ne rien dire.
- **Ranger l'outil remet le compteur a zero.** Volontaire : relancer le moteur fait partie du rituel.

### A faire dans Studio

Poser les marqueurs `SwapToLeft` et `SwapToRight` dans `TryLaunchAnimation` et `IsReadyAnimation`, a la frame
ou les deux mains se rejoignent. Sans eux tout fonctionne, mais l'outil reste dans la main droite.

## 0.0.13 — Le moteur part sur le marqueur, pas a la fin

Troisieme marqueur cable : `TryLaunchEvent`, pose a la butee de la corde.

Avant, le moteur demarrait a la FIN de l'animation du dernier tirage. Ca se lisait comme "je tire, je range
mon bras, et le moteur se souvient de demarrer". Maintenant il part a l'instant du marqueur, et le retour du
bras se joue moteur allume.

**La cause et l'effet doivent tomber sur la meme frame.** Un delai entre le geste et sa consequence, meme
court, casse le lien entre les deux. Ce n'est pas un detail de finition : c'est ce qui fait qu'un geste se
ressent comme la cause de ce qui suit.

Deux filets conserves : si `TryLaunchEvent` manque, le moteur part quand meme a la fin de l'animation. Si
`SwapToRight` manque, la main droite est reprise a la fin.

## 0.0.14 — Posture de tirage entre deux essais

Nouvel etat `Ready`. Apres un tirage rate, le joueur ne revient plus a l'idle : il GARDE la posture de
tirage, corde en main. S'il n'insiste pas pendant `stanceTimeout` (2.5 s), il relache et l'idle revient.

Sans ca, les 4 tirages se lisaient comme quatre gestes separes par un retour au repos. Maintenant c'est un
seul geste, tenu, avec de l'insistance dedans.

### Comment c'est fait

La posture est la MEME `TryLaunchAnimation`, jouee a **vitesse 0** sur sa premiere frame :

```lua
track:AdjustSpeed(0)
track.TimePosition = 0
```

- On rejoue la piste au lieu de figer la precedente : une piste terminee est a sa DERNIERE frame, pas a sa
  premiere.
- `Looped = true` sur la posture, pour qu'elle ne s'arrete jamais d'elle-meme.
- **Quitter la posture ne demande aucune animation de retour.** La pose de maintien tourne toujours en
  dessous en priorite `Action` ; couper la posture (`Action2`) fait reapparaitre l'idle tout seul.
- **La posture est coupee juste AVANT de lancer le tirage.** Les deux sont en `Action2` et se disputeraient le
  squelette : la posture figee tirerait le bras en arriere pendant que le geste avance.

### Le minuteur

Un minuteur `task.delay` ne s'annule pas. On lui donne un **jeton** (`stanceToken`) incremente a chaque
changement de posture : au reveil il compare, et se tait si le jeton a change. Sans ca, un minuteur lance
avant un nouveau tirage viendrait couper la posture en plein milieu du geste suivant.

## 0.0.15 — L'outil reste dans la main gauche pendant tout le demarrage

Bug : l'outil passait a gauche puis revenait a droite a la fin de CHAQUE tirage rate. Le joueur changeait
donc de main quatre fois pour un seul geste.

Pendant toute la sequence, il tient le carter de la main gauche et tire la corde de la droite. La main droite
ne doit reprendre l'outil qu'a la sortie.

- `bindHandSwap` prend un parametre `releaseToMainHand`. Le marqueur `SwapToRight` n'est branche que sur le
  DERNIER tirage (`IsReadyAnimation`).
- Le filet `setHand(handPart)` dans `Stopped` ne s'applique plus qu'en cas de reussite.
- Nouvelle fonction `releaseToIdle` : seul chemin de sortie vers le repos. Elle coupe la posture, rend la main
  droite et repasse en `Holding`. Tous les retours a l'idle passent par elle, y compris les cas d'erreur
  (animation introuvable).

### Piege a retenir

**Quand un etat modifie quelque chose de persistant (ici la main qui tient l'outil), il faut UN SEUL chemin de
sortie** qui le remet en place. Quatre `setState("Holding")` disperses, c'etaient quatre occasions d'oublier
de rendre la main droite.

## 0.0.16 — Orientation propre a la main gauche

- `ToolConfigs.offHandGripOffset` : orientation de l'outil quand il est dans la main de renfort. La
  `LeftGripAttachment` de Roblox est le MIROIR de la droite, donc reutiliser `gripOffset` donne un outil de
  travers. Et de toute facon on ne tient pas un taille-haie pareil selon qu'on le porte ou qu'on le cale pour
  tirer la corde.
- `resolveGrip` choisit l'offset selon la main, en comparant a `config.offHandPart`.
- `stanceTimeout` passe de 2.5 a 30 s. Le joueur relachait bien trop vite.

## 0.0.17 — Attachment `GripLeft`

En main de renfort, `resolveGrip` cherche d'abord une Attachment nommee **`GripLeft`** dans le Handle. Si
elle existe, c'est elle qui donne la prise ; sinon on retombe sur `Grip` et `offHandGripOffset` fait tout.

Raison : une Attachment se place et se tourne A LA SOURIS dans Studio, avec un retour visuel immediat. Trois
angles en radians dans un fichier, ca se devine par essais-erreurs a 15 secondes l'essai.

Regle generale du projet : **quand un reglage est spatial, l'exposer comme une Attachment, pas comme un
nombre.** Le nombre reste disponible en correction fine.

## 0.0.18 — La poignee du lanceur suit la main qui tire

`ToolService.setLauncherHand(player, handPartName?)`. Pendant le demarrage, la part `Launcher` quitte l'outil
pour se coller a la main droite. Le `Beam` tendu entre `A0Launcher` et `A1Launcher` s'etire tout seul : on ne
dessine pas la corde, on deplace ses deux bouts.

C'est l'option B evoquee en 0.0.12 : une seule animation a faire, et la corde reste physiquement correcte quoi
qu'il arrive, au lieu de synchroniser a la main une animation d'outil avec une animation de joueur.

- `ToolConfigs` gagne `launcherPartName` (nil = l'outil n'a pas de lanceur) et `launcherGripOffset`.
- L'etat de repos du Motor6D (`Part0`, `Parent`, `C0`, `C1`) est memorise a l'equipement. Sans ces valeurs,
  rendre la poignee a l'outil demanderait de les recalculer, et la moindre erreur laisserait la corde tendue
  de travers pour toujours.
- Le Motor6D est reparente sur `Part1` quand il part dans la main : laisse sur le Handle, il ne serait enfant
  ni de `Part0` ni de `Part1`, ce que Roblox ne garantit pas de faire fonctionner. Et sur `Part1` il meurt avec
  l'outil.
- **Ordre au retour** : la poignee revient sur l'outil AVANT que la main droite reprenne le carter. Dans
  l'autre ordre, elle reste une frame accrochee a une main qui tient deja l'outil, et la corde se plie.

### Fuite corrigee au passage

Le `Motor6D` de prise (`ToolGrip`) vit sur la MAIN du joueur, pas dans l'outil : detruire l'outil ne le
supprimait pas. Il en restait un de plus a chaque equipement, tous inertes, tous invisibles.

**Un joint pose hors de l'objet qu'on detruit ne se nettoie pas tout seul.** Meme famille de piege que les
connexions posees sur la camera ou sur workspace.

## 0.0.19 — Le moteur tousse sur les tirages rates

Sur le marqueur `TryLaunchEvent` d'un tirage RATE, les animations de l'outil partent une fraction de seconde
puis se coupent en fondu. Les lames font un a-coup et retombent.

Sans ca, trois tirages sur quatre n'avaient **aucune consequence a l'ecran**. Le geste devenait une formalite :
on clique quatre fois, il ne se passe rien, puis ca marche. Maintenant on VOIT la machine essayer, et le
quatrieme tirage paie ce qu'on a vu echouer trois fois.

- `ToolConfigs.sputterDuration` (0.35 s).
- `session.sputterTracks`, separees de `runTracks` : ce sont les memes animations, mais leur duree de vie n'a
  rien a voir. Les melanger ferait couper le moteur en marche par le minuteur d'un ancien ratage.
- `startRunning` coupe les pistes d'a-coup avant de lancer les vraies. Sinon les memes animations tournent en
  double sur les memes Motor6D : tremblement au lieu d'un moteur qui tourne rond.
- Arret en `Stop(0.15)` et non `Stop()` : les lames ralentissent au lieu de se figer, ce qui se lit comme un
  moteur qui retombe et non comme une animation coupee.

### Le principe

**Le marqueur de butee porte la consequence, reussite comme echec.** Un echec sans retour visible n'est pas un
echec, c'est un vide. Et c'est le contraste entre les trois echecs et la reussite qui donne sa valeur a la
reussite.

## 0.0.20 — Pose de maintien differente moteur allume

`ToolConfigs.runHoldAnimation` (`IsReadyAnimation`). Des que le moteur part, elle remplace `holdAnimation`.
Avant, la pose de repos revenait par-dessous des que l'animation du dernier tirage se terminait : le joueur
tenait un outil qui vibre comme un outil mort.

- `ToolService.setHoldAnimation(player, animName?)`. `nil` remet celle de la config.
- L'ancienne piste sort en fondu (`HOLD_FADE`, 0.25 s) et n'est detruite qu'APRES. Un `Destroy` immediat coupe
  le fondu et le joueur saute d'une pose a l'autre en une frame.

L'outil a donc deux etats de maintien, et c'est le service d'etat qui decide lequel s'applique. Le service
d'objet ne fait qu'executer.

## 0.0.21 — `IsReadyAnimation` devient la mise en position

Correction d'un contresens : `IsReadyAnimation` n'est pas le tirage reussi, c'est la **mise en position**. Le
joueur cale le carter dans la main gauche et saisit la corde.

Nouvelle sequence :

```
1er clic  -> IsReadyAnimation (mise en position) -> TryLaunchAnimation (tirage 1) enchaine AUSSITOT
clic 2..N -> TryLaunchAnimation
Nieme     -> TryLaunchAnimation + le moteur part au marqueur
```

- `session.prepared` : la mise en position n'est jouee qu'une fois par sequence. Elle est remise a `false` par
  `releaseToIdle`, donc lacher l'outil oblige a se repositionner.
- **La mise en position enchaine le tirage toute seule.** Le joueur ne clique pas deux fois pour son premier
  essai : c'est un seul mouvement.
- Tous les tirages jouent desormais la MEME animation. Ce qui change sur le dernier, c'est ce que fait le
  marqueur de butee : le moteur part au lieu de tousser, et la main droite reprend l'outil.
- `SwapToLeft` est branche sur la mise en position (c'est la que l'outil change de main), pas sur chaque
  tirage.

## 0.0.22 — `ReadyToCutAnimation`

`runHoldAnimation = "ReadyToCutAnimation"`. Nouvelle animation dediee : le joueur tient le taille-haie en
marche, pret a couper. Elle boucle tant que le moteur tourne.

Une seule ligne de config a changer, la mecanique existait deja depuis 0.0.20.

### Pourquoi ca marche sans code en plus

Question de PRIORITES, pas de minutage :

- `ReadyToCutAnimation` est posee en `Action` des que le moteur part (au marqueur, a 0.17 s).
- `TryLaunchAnimation` tourne en `Action2`, donc elle la MASQUE jusqu'a sa derniere frame.
- Quand le tirage se termine, il n'y a plus rien au-dessus : la pose de travail apparait toute seule.

Aucun `task.wait`, aucun `Stopped` a ecouter pour ca. **Poser la couche du dessous a l'avance et laisser celle
du dessus s'effacer** vaut mieux qu'enchainer deux animations a la main : il n'y a pas d'instant ou aucune des
deux ne joue, donc pas de frame ou le joueur retombe en T-pose ou en idle.

## 0.0.23 — Une Attachment de prise par main

`GripRight` (poignee arriere) pour la main principale, `GripLeft` (manche) pour la main de renfort. `Grip`
reste le repli commun si l'une des deux manque.

**La prise depend de l'ETAT, pas de la main.** C'est toujours la main droite qui tient l'outil, mais elle se
pose a un endroit different selon ce qu'on fait :

| Etat | Main | Attachment |
|---|---|---|
| Moteur eteint, l'outil est porte | droite | `GripLeft` (le manche) |
| Demarrage, la droite tire la corde | gauche | `GripLeft` (le manche) |
| Moteur allume, position de travail | droite | `GripRight` (la poignee arriere) |

`resolveGrip` et `setHand` prennent donc un `attachmentName` en parametre. C'est l'APPELANT qui choisit :
`ToolService` gere l'objet et ne connait pas les etats, `ToolStateService` connait les etats et dit ou poser
la main. Chacun son travail.

### La limite a connaitre pour plus tard : on ne soude qu'UNE main

Un `Motor6D` construit un ARBRE de joints. Les deux bras d'un personnage sont deja relies entre eux par le
torse ; souder l'outil aux deux mains fermerait une boucle, ce que le solveur de Roblox ne sait pas resoudre.

Une prise a deux mains est donc toujours une **illusion produite par l'animation** : une seule main porte le
joint, l'autre est posee a l'oeil dans l'editeur. C'est ainsi que tous les jeux font.

## 0.0.24 — Passage de main a la FIN de la mise en position

Le passage dans la main gauche ne se fait plus sur un marqueur au milieu de `IsReadyAnimation`, mais a sa
derniere frame, dans `track.Stopped`.

Le geste montre le joueur qui attrape l'outil : tant qu'il n'a pas fini de l'attraper, il ne l'a pas.

Ordre sur cette meme frame : l'outil passe a gauche, la corde part a droite, le tirage s'enchaine. Aucun temps
mort visible.

`bindHandSwap` n'est plus appele du tout sur la mise en position. Le marqueur `SwapToLeft` peut rester dans
`IsReadyAnimation`, il n'est simplement plus ecoute pour cette animation.

## 0.0.25 — La mise en position se fige, elle n'enchaine plus

Nouveau marqueur `IsReadyEvent` (0.53 s dans `IsReadyAnimation`). L'animation s'y ARRETE au lieu d'aller
jusqu'au bout et de lancer le tirage.

```
1er clic  -> IsReadyAnimation, figee sur IsReadyEvent, outil dans la main gauche
2e clic   -> TryLaunchAnimation (tirage 1)
3e, 4e... -> TryLaunchAnimation
```

Le joueur decide quand il tire. Deux gestes voulus au lieu d'un enchainement subi.

### Factorisation

`holdStance(player, session, track, timeout)` : fige une piste EN COURS et la garde comme posture d'attente.
Deux chemins y menent maintenant, et ils partagent le meme code :

1. la mise en position atteint `IsReadyEvent`
2. un tirage rate se termine (`enterReady` rejoue le tirage fige a sa frame 0)

### Detail qui evite un double `Destroy`

`holdStance` met `session.startTrack` a `nil` en prenant la piste. Sans ca, `stopStartTrack` et `stopStance`
detruiraient tous les deux le meme objet au tirage suivant.

### Filet

`settle` est branche sur le marqueur ET sur `Stopped`, avec un drapeau `settled` pour ne s'executer qu'une
fois. Sans marqueur, la posture se fige a la fin de l'animation : moins precis, mais le joueur n'est jamais
bloque dans un etat sans sortie.

## 0.0.26 — Registre des pistes du personnage

Symptome : apres un rangement d'outil, le joueur continuait de jouer une animation de taille-haie les mains
vides.

Le nettoyage etait disperse entre `ToolService` (`holdTrack`) et `ToolStateService` (`startTrack`,
`stanceTrack`, `runTracks`, `sputterTracks`), soit **cinq champs sur deux modules**. Chaque transition devait
penser a arreter la bonne, et il suffisait d'un chemin oublie.

`ToolService` tient maintenant un registre de TOUTES les pistes qu'il joue sur un personnage.
`stopAllCharacterTracks` les balaie a l'unequip, apres les auditeurs.

Les arrets cibles de `ToolStateService` restent : ils servent aux transitions de gameplay (couper la posture
avant un tirage). Le balayage est le filet, pas le chemin principal. D'ou le `pcall` : une piste peut avoir
deja ete detruite par une transition normale.

### Piege a retenir

**Celui qui cree est celui qui nettoie, et il nettoie TOUT.** Un nettoyage reparti sur plusieurs modules et
plusieurs champs finit toujours par en oublier un. Le bon reflexe n'est pas de chercher lequel : c'est de
rendre l'oubli impossible en centralisant la creation ET la destruction au meme endroit.

## 0.0.27 — Renommage `PrepareToLaunchAnimation`

`IsReadyAnimation` devient `PrepareToLaunchAnimation` cote Studio. Le champ de config `readyAnimation` devient
`prepareAnimation` : l'ancien nom prêtait a confusion avec `ReadyToCutAnimation`, qui est la posture APRES
demarrage. Deux choses opposees portaient presque le meme nom.

Le marqueur reste `IsReadyEvent` a l'interieur de l'animation.

## 0.0.28 — On demande a l'Animator, on ne fait plus confiance aux listes

Le registre de 0.0.26 ne suffisait pas : le joueur gardait encore une animation de taille-haie les mains vides.

Normal, c'etait encore de la comptabilite. Une piste creee dans un chemin oublie, une reference perdue, un
ordre d'appel inattendu, et elle echappe au registre donc au nettoyage.

`stopAllCharacterTracks` interroge maintenant `animator:GetPlayingAnimationTracks()` et coupe **tout ce dont
l'Animation est un descendant de `ReplicatedStorage.Animations`**.

- Ca ne depend plus d'aucune bookkeeping : la source de verite est l'Animator, pas notre table.
- Les animations par defaut de Roblox (marche, saut, idle) vivent dans le script `Animate` du personnage, pas
  dans `ReplicatedStorage` : le test ne les touche jamais.
- Un `warn` liste les pistes orphelines trouvees. S'il s'affiche, il nomme le chemin fautif au lieu de nous
  laisser deviner.

### Piege a retenir

**Quand un nettoyage rate malgre une comptabilite correcte, arreter de compter et demander a la source.**
L'etat reel du moteur bat toujours l'etat qu'on croit avoir. Une liste qu'on tient a la main est une
hypothese ; `GetPlayingAnimationTracks` est un fait.

## 0.0.29 — Remise a plat du systeme d'outil

Le diagnostic de 0.0.28 a parle : `Pistes orphelines coupees au rangement : ReadyToCutAnimation (x2)`. Deux
pistes de la meme animation tournaient en parallele.

Decision : **on repart d'une base minimale.** La sequence de demarrage fonctionnait, mais elle empilait quatre
etats, cinq pistes d'animation, deux Motor6D mobiles et trois marqueurs sur un socle pas encore sur. Chaque
ajout demandait de corriger le precedent.

### Ce qui reste

- `1` sort / range le taille-haie
- Effet de spawn dans la main
- `IdleAnimation` en boucle tant que l'outil est tenu

### Ce qui est retire

- `ToolStateService` (machine a etats, tirages, a-coups, posture)
- Remote `Tool/ActivateTool`
- `setHand`, `setLauncherHand`, `setHoldAnimation`, `playToolAnimation`, `onUnequip`
- Tous les champs de config lies au demarrage

**Sauvegarde** dans le scratchpad de session, dossier `archive_v1` (le projet n'est pas sous git : effacer un
fichier ici est definitif).

### Ce que je garde de l'ancienne version

Le nettoyage par `GetPlayingAnimationTracks` est conserve, et il est maintenant le SEUL mecanisme : plus
aucune liste de pistes n'est tenue a la main. Il n'y a donc plus rien a oublier de ranger.

### La lecon

**Une couche par validation.** On a ajoute mise en position, tirages, a-coups, changements de main, poignee
mobile et poses multiples sans jamais s'arreter pour verifier que la couche precedente tenait. Le resultat
marchait a l'ecran mais accumulait des etats invisibles.

Ce n'est pas la meme erreur que sur les projets precedents (soigner l'interface au lieu du coeur) : c'est de
la profondeur ajoutee trop vite sur une meme feature. Le remede est le meme, ralentir et valider.

## 0.0.30 — Prechauffage et cache des animations

Les pistes d'animation sont chargees UNE FOIS au spawn, en arriere-plan, et gardees en cache.

### Les deux moities du prechargement

1. **Telecharger l'asset** : deja fait par `LoadingScreenClient`, qui collecte les `Animation` de
   `ReplicatedStorage` (`LOADABLE.Animation = true`) et les passe a `ContentProvider:PreloadAsync`.
2. **Preparer la piste** : `Animator:LoadAnimation`. `PreloadAsync` ne le fait PAS, c'est un manque connu
   (voir devforum.roblox.com/t/how-to-preload-animations/853322). C'est cette moitie qu'on ajoute ici.

### Le cache resout aussi les fuites

On ne peut pas accumuler des pistes si on n'en cree jamais plus d'une par animation. La version precedente en
creait une a chaque lecture, puis devait les pourchasser sur cinq champs dans deux modules.

- Cache indexe par **personnage**, pas par joueur : a la mort l'Animator meurt avec, et les pistes deviennent
  des references vers du vide. On compare donc le personnage avant de servir le cache.
- `stopToolAnimations` fait `Stop` **sans** `Destroy` : les pistes appartiennent au cache et seront rejouees.
  Les detruire obligerait a recharger, donc a repayer le temps mort qu'on vient d'eliminer.
- `getTrack` a un repli : si le prechauffage n'a pas eu lieu, il charge a la demande. Mieux vaut un temps mort
  qu'une animation absente.
- Le prechauffage tourne dans un `task.spawn` : il attend l'Animator et charge plusieurs assets, il n'a aucune
  raison de retarder l'apparition du personnage.

Tout le dossier d'animations de l'outil est prechauffe, pas seulement `holdAnimation` : les autres reviendront
et il n'y a aucune raison de payer leur chargement plus tard.

## 0.0.31 — Demarrage, couche 1 : mise en position

`Server/ToolStartService.luau`, 129 lignes. Volontairement minimal.

```
Idle --(clic)--> Preparing --(fin de l'anim)--> Ready

Preparing : PrepareToLaunchAnimation jouee en entier
Ready     : TryLaunchAnimation FIGEE a sa premiere frame
```

Le tirage, les a-coups du moteur et les changements de main viendront **apres validation de celle-ci**. La
version precedente avait empile six couches d'un coup, et il a fallu tout jeter.

### API ouverte par `ToolService`

- `getHeld(player)` : l'outil tenu et sa config
- `getTrack(player, animName)` : une piste PRETE mais non jouee, sortie du cache
- `onUnequip(callback)` : pour remettre a zero un etat lie a l'outil

`ToolService` gere l'objet, `ToolStartService` gere la sequence. Le second ne cree jamais de piste : il
demande, configure, joue.

### Deux details

- **`Stopped:Once` et non `Connect`.** La piste vient du cache et sera rejouee ; un `Connect` s'accumulerait a
  chaque lecture et `enterReady` partirait autant de fois qu'on a demarre depuis le debut de la session.
- **`TimePosition` APRES `Play`.** Sur une piste a l'arret, la valeur est ignoree.

## 0.0.32 — Demarrage, couche 2 : passage dans la main gauche

Marqueur `PassageOtherHandEvent` dans `PrepareToLaunchAnimation`. L'outil y passe dans la main gauche.

- `ToolConfigs` gagne `offHandPart`, `offHandAttachment`, `offHandGripOffset`.
- `ToolService.setHand(player, handPartName)`. L'offset suit la main : la `LeftGripAttachment` de Roblox est
  le miroir de la droite, donc la meme correction y donnerait un outil de travers.
- `applyGrip` factorise le calcul de prise. `equip` et `setHand` passent par le meme code : **un seul endroit
  calcule une prise, donc un seul endroit a corriger.** Avant, `equip` avait sa copie inline.
- `setHand` repointe `Part0` du Motor6D EXISTANT au lieu de le detruire et le recreer. Recreer casserait toute
  animation en cours sur cette chaine.

### Detail

`GetMarkerReachedSignal(...):Once` et non `:Connect`, pour la meme raison que `Stopped:Once` en 0.0.31 : la
piste vient du cache et sera rejouee. Un `Connect` s'accumulerait, et au dixieme demarrage de la session le
passage de main partirait dix fois.

L'etat est revalide dans le callback : le joueur a pu ranger l'outil ou mourir pendant l'animation.

### Limite assumee de cette couche

Rien ne ramene l'outil dans la main droite : il y reste jusqu'au rangement. C'est normal, le retour arrivera
avec le tirage reussi et le relachement.

## 0.0.33 — Attachment dediee au demarrage

`offHandAttachment = "GripStart"`, une Attachment a creer dans le Handle. On ne reutilise plus `GripLeft` : la
prise de PORT et la prise de DEMARRAGE n'ont aucune raison d'etre la meme.

`offHandGripOffset` repasse a `CFrame.identity`. C'est l'Attachment qui porte toute l'orientation ; le champ
ne sert plus qu'a une correction fine.

### Repli si l'Attachment manque

`applyGrip` retombe sur `gripAttachment` et emet un warn. Sans ce repli, `C1` vaudrait `identity` et l'outil
se collerait a l'origine du Handle : le joueur le tiendrait par le vide, et on chercherait l'erreur du cote de
l'orientation alors que c'est un NOM qui manque.

### Le principe, deja note en 0.0.17 et confirme ici

**Quand un reglage est spatial, l'exposer comme une Attachment, pas comme un nombre.** Trois angles en radians
se devinent par essais-erreurs a quinze secondes l'essai ; une Attachment se tourne a la souris avec un retour
visuel immediat. Le nombre reste disponible pour la correction fine, jamais pour le reglage principal.

## 0.0.34 — Delai de replication sur le changement de main

`ToolConfigs.offHandDelay` (0.15 s). Le changement de main arrive apres le marqueur, pas dessus.

### Pourquoi, et pourquoi ca ne contredit pas la regle des marqueurs

L'animation est jouee **cote serveur** puis repliquee. Le marqueur part quand la lecture DU SERVEUR atteint sa
frame, mais le client a quelques frames de retard sur cette lecture. Sans decalage, la main change avant que
l'image du joueur ait atteint le geste : l'outil passe a gauche alors que le bras n'y est pas encore.

Le marqueur reste ce qui **declenche**. Le delai ne rattrape que la latence de replication, il ne remplace pas
le minutage de l'animation. C'est pour ca qu'il est petit et qu'il n'aura pas a suivre les retouches de
l'animation.

### Detail

La revalidation se fait APRES le delai, pas avant. Et elle accepte `Ready` en plus de `Preparing` : si
l'animation se termine pendant l'attente, le changement de main doit quand meme avoir lieu.

Orientation de la prise de demarrage trouvee : `CFrame.Angles(math.rad(123), math.rad(-20), math.rad(-25))`.

## 0.0.35 — Demarrage, couche 3 : le tirage

```
Idle --(clic)--> Preparing --(fin)--> Ready --(clic)--> Pulling
                                        ^                  |
                                        +------------------+
```

Un clic depuis `Ready` joue `TryLaunchAnimation` en entier, puis on revient a la posture.

### Une seule piste pour la posture ET le geste

`Ready` et `Pulling` utilisent la MEME piste : on ne fait que changer sa vitesse.

| Etat | Vitesse | Looped |
|---|---|---|
| `Ready` | 0 | oui, pour qu'elle ne se termine jamais seule |
| `Pulling` | 1 | non, sa fin naturelle ramene a la posture |

Le joueur passe donc de la posture au geste **sans transition a fondre** : il repart exactement d'ou il etait
fige. Deux pistes distinctes auraient demande un fondu entre deux poses identiques, ce qui se voit toujours un
peu.

### Details

- `if not track.IsPlaying then track:Play() end` : la piste est deja en cours quand elle est figee. Rappeler
  `Play` la relancerait avec un fondu, donc un a-coup visible.
- `enterReady` accepte `Preparing` **et** `Pulling` : deux chemins y menent, la fin de la mise en position et
  la fin d'un tirage. Sans ca il aurait fallu mentir sur l'etat pour passer sa garde.
- Un clic pendant `Preparing` ou `Pulling` est ignore. Empiler deux gestes donne un bras qui tremble au lieu
  d'un joueur qui insiste.

### Pas encore la

Compteur de tirages, a-coup du moteur sur echec, demarrage reussi, retour dans la main droite. Une couche a
la fois.

## 0.0.36 — Demarrage, couche 4 : la poignee du lanceur suit la main qui tire

Au meme instant que le changement de main, la part `Launcher` quitte l'outil pour se coller a la main droite.

**Le `Beam` tendu entre `A0Launcher` et `A1Launcher` s'etire tout seul.** On ne dessine pas la corde, on
deplace ses deux bouts : le moteur de rendu fait le reste. Aucune animation d'outil a synchroniser.

- `ToolConfigs` gagne `launcherPartName`, `launcherAttachment` (`A1Launcher`, le bout de corde deja pose sur
  la poignee) et `launcherGripOffset`.
- `ToolService.setLauncherHand(player, handPartName?)`. `nil` rend la poignee a l'outil.
- L'etat de repos du Motor6D (`Part0`, `Parent`, `C0`, `C1`) est memorise a l'equipement. Sans ces valeurs,
  rendre la poignee demanderait de les recalculer, et la moindre erreur laisserait la corde de travers pour
  toujours.
- Le Motor6D est reparente sur `Part1` quand il part dans la main : il vit ainsi DANS l'outil et meurt avec
  lui. Laisse sur le Handle, il ne serait enfant ni de `Part0` ni de `Part1`, ce que Roblox ne garantit pas de
  faire fonctionner.

### Les deux mains se separent au meme instant

`setHand` et `setLauncherHand` sont appeles dans le meme callback, apres le meme delai. Les separer donnerait
une corde qui se tend toute seule pendant une fraction de seconde.

## 0.0.37 — La corde n'existe que tiree

Le `Beam` est **eteint a l'equipement** et ne s'allume qu'avec la poignee du lanceur.

Au repos, ses deux Attachment sont au meme endroit : ca donne un trait ecrase sur l'outil, visible et sale.
Une corde n'a de sens que tendue.

- `Held.launcherBeam`, trouve par `handle:FindFirstChildWhichIsA("Beam", true)`. Recherche RECURSIVE : le Beam
  vit dans une Attachment du Handle, pas directement sous lui.
- `Enabled = false` a l'equipement, puis pilote par `setLauncherHand` : `Enabled = handPartName ~= nil`.

Un seul endroit decide de l'etat de la corde, et c'est le meme que celui qui deplace sa poignee. Les deux ne
peuvent donc pas se desynchroniser.

## 0.0.38 — La mise en position part a l'equipement

```
Idle --(EQUIPEMENT)--> Preparing --(fin)--> Ready --(clic)--> Pulling
                                              ^                  |
                                              +------------------+
```

Le premier clic disparait. Sortir l'outil met directement le joueur en position ; le clic ne sert plus qu'a
tirer.

**Une manipulation qui n'offre aucun choix au joueur n'est pas du gameplay, c'est un peage.** Ce premier clic
ne decidait de rien : sortir l'outil, c'est deja dire qu'on veut s'en servir.

- `ToolService.onEquip(callback)`, symetrique de `onUnequip`. Emis EN DERNIER dans `equip`, quand le modele est
  parente, la prise appliquee et la pose de maintien lancee : un auditeur peut donc jouer par-dessus sans
  risque.
- `activate` garde `Idle -> prepare` en repli, au cas ou la mise en position aurait echoue (animation
  introuvable, personnage remplace au mauvais moment). Le joueur n'est jamais sans recours.

## 0.0.39 — Demarrage, couche 5 : le moteur tousse

Sur le marqueur `TryLaunchEvent`, les animations de l'outil partent 0.35 s puis se coupent en fondu. Les lames
font un a-coup et retombent.

Sans ca, un tirage n'avait **aucune consequence a l'ecran** : le joueur cliquait, un bras bougeait, rien ne
repondait. Maintenant on VOIT la machine essayer.

- `ToolConfigs.toolRunAnimations` et `sputterDuration`.
- `ToolService.setToolAnimationsPlaying(player, playing, fadeOut?)`.
- Les pistes sont chargees a l'equipement, sur l'Animator de **l'outil**. Le modele est un clone neuf a chaque
  fois, donc son Animator aussi : rien a mettre en cache entre deux equipements, et rien a nettoyer au
  rangement puisqu'elles meurent avec lui.

### La cause et l'effet sur la meme frame

L'a-coup tombe sur le marqueur, pas au debut ni a la fin du tirage. Un decalage, meme court, casse le lien
entre le geste et sa consequence : le joueur ne se dit plus "j'ai fait tousser le moteur" mais "le moteur a
tousse". C'est la difference entre agir et assister.

### Arret en fondu

`Stop(0.15)` et non `Stop()`. Les lames RALENTISSENT au lieu de se figer d'un coup, ce qui se lit comme un
moteur qui retombe et non comme une animation coupee.

### Diagnostic

Si `TryLaunchEvent` est absent de l'animation, un `warn` le dit **une fois**. Anormal et actionnable : sans ce
marqueur le moteur ne toussera jamais, et on chercherait du cote du code.

## 0.0.40 — Demarrage, couche 6 : retour camera

Secousse et pincement de champ de vision a la butee de la corde. Tres legers.

- `Client/Utils/CameraEffects.luau` — `Shake(intensity, duration)` et `PunchFov(amount, duration)`.
  Generique : ce module ne connait ni le taille-haie ni le demarrage, il saura secouer pour la coupe ou un choc.
- `ToolConfigs` gagne `pullShakeIntensity` (0.15 stud), `pullShakeDuration` (0.25 s), `pullFovPunch` (-1.5 deg).

### La secousse passe par `Humanoid.CameraOffset`, pas par `Camera.CFrame`

Ecrire dans la CFrame revient a se battre chaque frame contre les scripts de camera de Roblox : ca produit des
saccades des que le joueur bouge la souris. `CameraOffset` est prevu pour ca, Roblox l'applique par-dessus sa
propre camera.

### Le signal : un COMPTEUR, pas un booleen

Le serveur incremente `LeafiaPullTick` sur le modele de l'outil. Un booleen ne marcherait pas : deux tirages
d'affilee ecriraient la meme valeur, l'attribut ne changerait pas, et le client raterait le second.

Toujours aucun remote. Le modele et son attribut se repliquent ensemble.

### Trois details de dosage

- **Amortissement.** La secousse est forte au debut et eteinte a la fin. Une amplitude constante se lit comme
  une panne de moteur de jeu, pas comme un impact.
- **Remise a zero EXACTE** en fin de secousse. Un falloff s'approche de zero sans l'atteindre : la camera
  resterait decalee d'un cheveu pour toujours.
- **Le retour du champ de vision est plus lent que l'aller** (70 / 30). L'inverse donne un effet de ressort
  mecanique ; la, ca respire.

### Deux pieges evites

- **Jetons sur les deux effets.** Une nouvelle secousse annule la precedente. Sans ca, deux effets qui se
  chevauchent additionnent leurs offsets et le premier a finir remet zero alors que l'autre tourne encore.
- **La valeur de repos du champ de vision est lue AVANT de bouger.** Si un pincement est deja en cours, on la
  lirait sur une camera deja pincee et le decalage s'accumulerait a chaque tirage.

Les FX ne se declenchent que pour le PORTEUR : chaque client n'ecoute que son propre outil.

## 0.0.41 — Demarrage, couche 7 : le son du tirage

`TryLaunchSound` joue au debut du tirage.

- `ToolConfigs.soundFolder` (chemin DANS SoundService, en liste) et `pullSound`.
- `ToolService.playSound(player, soundName)`.

### Clones dans le Handle, pas dans SoundService

Les sons du dossier sont clones **dans le Handle** a l'equipement. Trois consequences :

1. **Spatialises.** Les autres joueurs entendent le moteur d'ou tu es, pas dans leur tete.
2. **Un jeu par joueur.** Deux joueurs qui tirent en meme temps ne se coupent pas le son, ce qui arriverait
   avec une instance partagee.
3. **Rien a nettoyer.** Ils meurent avec l'outil.

Clones UNE FOIS a l'equipement et non a chaque tirage : pas d'allocation au milieu du geste.

### Le son part avec le GESTE, pas avec la butee

C'est le seul element de la sequence qui commence avant le marqueur. On entend la corde se derouler pendant
que le bras recule ; le son se termine sur le "pfff" du moteur qui ne prend pas.

### Prechargement corrige

`LoadingScreenClient` collectait `ReplicatedStorage` et `StarterGui`, mais pas `SoundService` — ou vivent tous
les sons du jeu. Sans ca, le premier son de chaque type se telecharge au moment ou on le joue, et il manque.

Une ligne ajoutee a la collecte. Le probleme aurait ete invisible en Studio, ou tout est deja en cache local.

## 0.0.42 — Demarrage, couche 8 : le moteur part

```
Idle --(EQUIPEMENT)--> Preparing --(fin)--> Ready --(clic)--> Pulling
                                              ^                  |
                             tirage rate      +------------------+
                                                                 |
                                               Nieme tirage --> Running
```

- `ToolConfigs.pullsToStart` (3) et `startSound` (`StartFirstSound`).
- Au tirage reussi : le son de demarrage part sur le marqueur, les animations de l'outil **ne sont pas
  coupees** (elles passent d'un soubresaut a un regime continu sans rupture), la corde rentre, l'outil revient
  dans la main droite, etat `Running`.

### La reussite est decidee AVANT de jouer

Sinon il faudrait enchainer un echec puis une reussite, et le joueur verrait deux gestes la ou il n'en a fait
qu'un.

### `pullsToStart` est une caracteristique de l'OUTIL

Pas une constante du jeu. Un outil pourri en demandera 4, un outil pro partira au premier tirage. Le joueur
ressentira son upgrade **dans ses mains** au lieu de le lire dans un menu : il n'achete pas "+12% de vitesse",
il arrete d'avoir mal aux doigts.

### Ordre au retour

`setLauncherHand(nil)` **avant** `setHand(handPart)`. Dans l'autre ordre, la poignee reste une frame accrochee
a une main qui tient deja l'outil, et la corde se plie.

### Ranger remet le compteur a zero

Volontaire : relancer le moteur fait partie du rituel.

## 0.0.43 — Ronronnement du moteur en marche

`ToolConfigs.runSound` (`IdleSound`), joue en boucle au passage en `Running`.

- `playSound` prend un parametre `looped`.
- Un son en boucle **deja en cours ne se relance pas** : ca produirait un hoquet au milieu du ronronnement.
- `ToolService.stopSound` ajoute, pour le jour ou le moteur s'eteindra.

### Il demarre au passage en `Running`, pas au marqueur

Le son de lancement a ainsi le temps de poser son "vroum" seul, puis il continue de jouer PAR-DESSUS le regime
etabli. Les deux se superposent, comme dans la realite : un moteur qui demarre ne passe pas du silence au
ralenti d'un coup.

Rien a nettoyer au rangement : les sons sont clones dans le Handle et meurent avec l'outil.

## 0.0.44 — Pose de maintien moteur allume

`ToolConfigs.runHoldAnimation` (`ReadyToCutAnimation`). Au passage en `Running`, elle remplace `IdleAnimation` :
en marche, le joueur ne tient plus l'outil comme un objet mort.

- `Held.holdTrack` memorise la pose en cours, pour pouvoir la couper quand on la remplace.
- `ToolService.setHoldAnimation(player, animName?)`, appelee a l'equipement (idle) et au demarrage (pose de
  travail). L'equipement passe desormais par elle aussi : un seul chemin pose la pose de maintien.
- Fondu `HOLD_FADE` (0.25 s) a l'entree ET a la sortie. L'ancienne piste n'est detruite qu'apres le fondu, un
  Destroy immediat le couperait.

### Pourquoi c'est propre sans code en plus

`ReadyToCutAnimation` est en `Action`, le tirage reussi (`TryLaunchAnimation`) en `Action2`. La pose de travail
est donc posee SOUS le tirage qui finit sa course, et apparait toute seule quand celui-ci s'efface. Aucune
frame ou le joueur retombe en idle.

## 0.0.45 — L'outil reste dans la main gauche apres demarrage

Correction : au demarrage reussi, l'outil revenait dans la main droite. Il doit RESTER a gauche.

Une fois le moteur lance, on tient le taille-haie a deux mains pour couper. Le `setHand(handPart)` du succes
est supprime ; seule la corde (`setLauncherHand(nil)`) rentre. C'est `ReadyToCutAnimation` qui place le bras
droit sur l'outil, comme toute prise a deux mains (illusion d'animation, cf 0.0.23).

## 0.0.46 — Fix : trou d'animation au demarrage

Symptome : au demarrage reussi, ~0.3 s sans animation avant que `ReadyToCutAnimation` apparaisse.

Cause : la pose de travail etait lancee dans le callback `Stopped` du tirage, donc APRES sa disparition, avec
un fondu de 0.25 s. Pendant ce fondu elle montait de zero, et la pose par defaut de Roblox passait a travers.
Le commentaire de 0.0.44 decrivait le bon comportement ("posee sous le tirage") mais le code ne le faisait
pas : il la posait apres, pas dessous.

Correction : `setHoldAnimation(runHold)` deplace de `Stopped` vers le marqueur `TryLaunchEvent`. La le tirage
(Action2) masque encore la pose (Action), qui monte a plein poids DERRIERE. Quand le tirage s'efface a sa fin
naturelle, elle est deja la. Le `Stopped` ne fait plus qu'acter l'etat `Running` et rentrer la corde.

Lecon : **poser la couche du dessous A L'AVANCE, pas au moment ou celle du dessus s'en va.** Un fondu qui part
de zero laisse toujours voir ce qu'il y a en dessous. La regle etait juste ; c'est le MOMENT de l'appel qui
etait faux.

## 0.0.47 — Accelerateur des lames (debut de la coupe)

Moteur en marche, les lames tournent lentement. Clic MAINTENU = elles accelerent progressivement ; relachement
= elles ralentissent. C'est le premier morceau du geste de coupe : lame lente = ralenti, lame rapide = ca
taille.

- `ToolConfigs` : `bladeIdleSpeed` (0.35), `bladeMaxSpeed` (1.6), `bladeAccel` (1.6/s), `bladeDecel` (2.8/s).
- Remote `Tool/SetThrottle`, un booleen valide cote serveur.
- `ToolService.setToolAnimationSpeed(player, speed)` : `AdjustSpeed` sur les pistes de l'outil.

### La vitesse est pilotee cote SERVEUR

Les animations de l'outil tournent sur son Animator serveur, donc `AdjustSpeed` s'y replique a tout le monde.
Le client ne fait qu'envoyer son intention (clic tenu ou non) ; c'est le serveur qui traduit en vitesse.

### Une rampe, pas un interrupteur

`throttle` (intention) et `bladeSpeed` (vitesse reelle) sont deux choses distinctes. Une seule boucle
`Heartbeat` fait suivre la seconde a la premiere, un cran par frame. **C'est la MONTEE progressive qui fait
l'effet, pas la vitesse finale** : un interrupteur on/off n'aurait aucune sensation de moteur qui monte en
regime.

- Montee (`bladeAccel`) plus lente que descente (`bladeDecel`) : la lame prend son elan doucement mais retombe
  franc au relachement.
- UNE boucle pour tous les joueurs, pas une connexion par personne. Elle ne touche qu'aux joueurs en `Running`,
  donc elle ne coute rien quand personne ne taille.

### Le clic sert a deux choses, le client ne tranche pas

Le client ne connait pas l'etat de l'outil. Au clic il envoie les DEUX signaux (`ActivateTool` pour les
tirages, `SetThrottle(true)` pour l'accelerateur) et le serveur ignore celui qui ne s'applique pas a son etat
courant. Le client ne decide jamais, il rapporte.

## 0.0.48 — Saut plus court, animation d'atterrissage, FOV au mouvement

Trois reglages independants.

### Saut

`CharacterConfigs.JUMP_HEIGHT` : 7.2 -> 4.5. Le saut par defaut de Roblox est trop haut pour un jeu au sol.

### Animation d'atterrissage

`CharacterConfigs.LANDING_ANIMATION_ID`. Jouee cote serveur (donc repliquee) sur `Humanoid.StateChanged` ==
`Landed`. On utilise l'etat que Roblox connait deja plutot que de redeviner le contact au sol par la vitesse
verticale.

Elle ne cle que les jambes et les pieds : en priorite `Action`, elle passe au-dessus de la marche mais laisse
les bras a la pose de l'outil (elle aussi en `Action`, sur d'autres os). Deux animations `Action` sur des os
DIFFERENTS se composent au lieu de se battre.

### FOV au mouvement

La vue s'elargit doucement quand le joueur marche (`70 -> 76`), revient au repos a l'arret.

- `Client/CameraController.luau` decide la cible selon la vitesse HORIZONTALE (un saut ou une chute n'elargit
  pas la vue). Il ne touche jamais `FieldOfView`, il passe par `CameraEffects`.
- **`CameraEffects` refondu : un SEUL ecrivain de `FieldOfView`.** Deux sources l'influencent, le fond (repos
  vs mouvement) et l'a-coup du tirage. Chacune alimente une variable, une seule boucle `RenderStepped` compose
  `FieldOfView = fond + a-coup`. Sans ca, les deux se battraient chaque frame.
- Lerp exponentiel avec `dt` dans le facteur : meme douceur a 30 et a 60 FPS. C'est ce lerp lent qui fait le
  "recule lentement".
- `PunchFov` ne prend plus de duree : l'a-coup est un impact qui revient a zero tout seul dans la boucle.

## 0.0.49 — Sprint (Shift) + plongee d'atterrissage

### Sprint

Shift maintenu : le personnage accelere (`SPRINT_SPEED` 17), le FOV s'elargit un cran de plus (`76 -> 80`), et
la camera prend un LEGER bob vertical, cadence des foulees.

- Vitesse cote SERVEUR : remote `Character/SetSprint`, booleen valide. Le client rapporte l'input, le serveur
  fixe le `WalkSpeed`. On relit la config a chaque fois, aucun etat a resynchroniser au respawn.
- FOV et bob cote client, decides dans `CameraController` selon la vitesse reelle : le sprint n'agit que si le
  joueur BOUGE (Shift a l'arret ne fait rien).

### Plongee d'atterrissage

A la reception au sol, la camera descend puis remonte en douceur, comme des genoux qui encaissent. Detectee
sur `Humanoid.StateChanged == Landed`, cote client (effet local).

### CameraEffects : un seul ecrivain, deux proprietes composees

Le module compose maintenant les DEUX proprietes de camera dans sa boucle unique :

```
FieldOfView  = fond + a-coup
CameraOffset = secousse + bob + plongee
```

Chaque source (mouvement, tirage, sprint, atterrissage) alimente une variable ; la boucle additionne. C'est ce
qui permet d'empiler quatre effets sans qu'ils se battent : au demarrage moteur en sprintant, un tirage peut
secouer la camera pendant que le bob tourne et que le FOV est deja elargi, tout se cumule proprement.

- `SetBob(amplitude, frequency)` : oscillation continue, amplitude lerpee pour un fondu doux a l'allumage et a
  l'extinction. `math.abs(sin)` pour une foulee (rebond vers le haut) et non un roulis de bateau.
- `LandDip(depth)` : impulsion vers le bas qui remonte vers zero. Remplace au lieu d'additionner, deux
  receptions rapprochees ne cumulent pas.

### Reglages (tous TRES legers, comme demande)

`SPRINT_BOB_AMPLITUDE` 0.12 stud, `LAND_DIP_DEPTH` 0.6 stud, `SPRINT_FOV` 80. Dans `CameraController`.

## 0.0.50 — Plongee d'atterrissage en ressort

La plongee posait un decalage instantane puis remontait en douceur : la descente etait donc un "TAC" sec.

Remplacee par un **ressort amorti** : a la reception on donne une impulsion de VITESSE vers le bas, le ressort
ramene la position a zero. La camera descend en douceur, freine, remonte, avec un leger depassement.

`F = -raideur * position - amortissement * vitesse`, integre en Euler. Amortissement (13) volontairement SOUS
l'amortissement critique (~22) : c'est ce depassement qui donne le cote souple au lieu d'un a-coup.

Verifie par simulation : profondeur ~0.24 stud, rebond de 0.019 stud au-dessus de zero, stabilise en 0.68 s.

`LandDip(strength)` prend desormais une VITESSE, pas une profondeur.

## 0.0.51 — Son du moteur : enveloppe en deux temps

Le pitch dynamique (`PlaybackSpeed` suivant la rampe des lames) est **abandonne**. Deux sons dedies le
remplacent :

```
ralenti        IdleSound                 (boucle)
  |  clic maintenu
attaque        SpeedStartMotor           (une fois)
  |  a sa fin, si le clic est toujours tenu
maintien       SpeedStartMotorInfinite   (boucle)
  |  relachement
ralenti        IdleSound
```

**Ce sont les sons qui portent la courbe d'acceleration, pas le code.** Tirer sur `PlaybackSpeed` par-dessus
doublerait l'effet et sonnerait faux. Le code ne fait qu'enchainer au bon moment.

### Details

- L'enchainement se fait sur `Sound.Ended`, la fin REELLE du fichier, jamais sur une duree codee en dur : une
  duree se decale des que le son est remplace.
- Le ralenti s'ARRETE pendant l'acceleration au lieu de se superposer. Deux regimes moteur en meme temps
  donnent une bouillie.
- La connexion a `Ended` est gardee et coupee a chaque transition. Un `Connect` qui survit a son geste se
  rebrancherait au suivant et l'enchainement partirait en double.
- `setThrottle` ignore une valeur identique a la precedente : sans ca, un client bavard relancerait l'attaque
  en boucle.
- Le son change par PALIERS (a chaque changement de throttle), contrairement a la vitesse des lames qui suit
  une rampe continue dans la boucle. Deux mecaniques differentes pour deux natures differentes.

## 0.0.52 — Le moteur redescend au lieu de se couper

Relacher pendant `SpeedStartMotor` coupait le son NET. Un moteur ne fait pas ca : il retombe.

Fondu croise au relachement. L'acceleration s'efface pendant que le ralenti remonte, les deux se croisent,
il n'y a aucun trou.

- `ToolService.fadeInSound` / `fadeOutSound`, par tween sur `Volume`.
- `ToolConfigs` : `engineReleaseFade` (0.45 s), `engineWindDownPitch` (0.7), `engineAccelFade` (0.12 s).

### La hauteur tombe pendant le fondu

`fadeOutSound` fait aussi descendre `PlaybackSpeed` vers `engineWindDownPitch`. On entend le REGIME retomber,
pas juste un volume qu'on baisse. C'est la difference entre "le son s'arrete" et "le moteur redescend".

### L'attaque part a plein volume, elle

Seul le son SORTANT est fondu. `SpeedStartMotor` demarre net : la faire monter en fondu lui enleverait son
mordant, et c'est ce mordant qui fait la sensation de coup d'accelerateur. On fond ce qui part, jamais ce qui
attaque.

### Trois pieges d'etat

- **Volume d'origine memorise a l'equipement** (`soundVolumes`). Un fondu ecrase `Volume` ; sans cette copie on
  ne saurait plus a quelle valeur revenir, et chaque fondu laisserait le son un peu plus faible que le
  precedent.
- **Un seul fondu par son a la fois** (`soundTweens`), annule des que le son repart. Sinon un fondu sortant
  continuerait de baisser le volume d'un son qu'on vient de relancer.
- **La connexion a `Ended` est coupee AVANT le fondu.** L'attaque qui s'eteint doit ecrire sa fin dans le vide,
  pas declencher le maintien qu'on est justement en train d'annuler.

`playSound` et `stopSound` annulent aussi le fondu en cours et restaurent volume et hauteur : quel que soit le
chemin, un son repart toujours dans un etat propre.

## 0.0.53 — Perte de vitesse a l'atterrissage

A la reception, la vitesse tombe a `LANDING_SPEED` (4) puis remonte progressivement. Sans ca le personnage
touchait le sol et repartait comme s'il n'avait rien senti : le saut n'avait aucun poids.

Mesure : ~0.43 s pour retrouver la marche, ~0.93 s pour le sprint.

### Chute brutale, reprise progressive

La vitesse tombe **d'un coup** et remonte **doucement**. C'est l'asymetrie qui fait l'impact : des jambes qui
absorbent puis repoussent. L'inverse (chute douce, reprise seche) ne se ressentirait pas comme un choc.

Meme principe que la descente du moteur en 0.0.52 et que le ressort de camera en 0.0.50 : dans un retour de
game feel, les deux sens n'ont presque jamais la meme vitesse.

### Le serveur retient maintenant l'etat du sprint

`sprinting[player]` est necessaire : la reprise doit savoir vers quelle vitesse remonter. Un joueur qui
retombe en tenant Shift doit retrouver le SPRINT, pas la marche.

### Un seul pilote a la fois

Pendant une recuperation, `onSetSprint` **n'ecrit pas** dans `WalkSpeed` : la boucle est seule aux commandes et
lira la nouvelle cible d'elle-meme. Sans cette regle, appuyer sur Shift en plein atterrissage remettrait
instantanement la pleine vitesse et annulerait l'impact.

C'est encore la meme regle que pour la camera : **une propriete, un seul ecrivain a un instant donne.**

### Details

- Vitesse EXACTE a l'arrivee, pas approchee : sinon un ecart minime resterait pour toujours et deux joueurs
  cote a cote finiraient par se decaler.
- `recovering` et `sprinting` remis a zero au respawn : la recuperation en cours portait sur l'ancien
  personnage.
- L'animation d'atterrissage ne bloque plus le ralentissement si elle echoue a charger : les deux effets sont
  independants.

## 0.0.54 — L'animation d'atterrissage laisse la marche reprendre

Symptome : en repartant juste apres une reception, les jambes restaient figees un instant avant que la marche
de Roblox apparaisse d'un coup.

Cause : l'animation d'atterrissage est en priorite `Action`, la marche de Roblox en `Movement`. Tant que la
premiere joue, elle MASQUE la seconde. Le joueur avancait donc avec des jambes immobiles jusqu'a la fin de la
piste.

Correction : la piste est coupee des que le joueur se remet a avancer, en fondu (`LANDING_CANCEL_FADE`, 0.15 s).

- Immobile a la reception -> l'animation joue en entier.
- Repart tout de suite -> elle est coupee, la marche reprend la main sans attendre.

### On teste `MoveDirection`, pas la vitesse

`MoveDirection` est l'INTENTION du joueur. Au moment ou il touche le sol il glisse encore : sa vitesse reelle
n'est donc pas un signal fiable, elle declencherait la coupure alors qu'il ne fait que finir sa chute.
`MoveDirection` ne bouge que s'il pousse vraiment sur ses touches.

### Regle generale

**Une animation en priorite haute doit savoir s'effacer.** Elle est prioritaire parce qu'elle raconte un
moment precis ; passe ce moment, elle n'a plus de raison de bloquer ce qui est en dessous. Poser la priorite ne
suffit pas, il faut aussi decider quand la rendre.

## 0.0.55 — Haie, couche 1 : approche et ecart

Debut du systeme de taille. Le joueur qui se presente devant une haie ralentit ; il retrouve son allure en
s'ecartant.

- `Modules/Configs/HedgeConfigs.luau`
- `Server/HedgeService.luau` : detecte la haie la plus proche, la FACE concernee, et l'etat entrer / sortir.
- Attributs poses sur le personnage : `LeafiaAtHedge` (booleen) et `LeafiaHedgeNormal` (Vector3). Contrat
  serveur -> client pour la camera et l'UI a venir, sans remote.

### Tag pose AUTOMATIQUEMENT par le serveur

Le jeu interroge le tag `Hedge` : une seule question a poser, quelle que soit la facon dont la haie a ete
marquee. Mais c'est le SERVEUR qui pose ce tag, sur toute part de `Workspace.Worlds.Maps` dont le nom commence
par `hedge_`.

Premiere version : taguer a la main dans Studio. Mauvais choix. Cinquante haies a taguer, c'est du travail pour
rien, et une haie oubliee ne reagit pas sans qu'on comprenne pourquoi.

- Balayage au demarrage, puis `DescendantAdded` sur ce seul dossier. On ne branche PAS
  `Workspace.DescendantAdded` : chaque part de personnage, chaque outil clone et chaque debris passerait par le
  test de nom, des centaines de fois pour rien.
- Le tag manuel reste possible pour une haie qui ne suit pas la convention de nom.
- Plusieurs haies peuvent porter le MEME nom : Roblox n'exige pas de noms uniques et le service boucle sur
  toutes les instances taguees.

### Detection par RAYCAST devant le joueur, pas par distance

Premiere version : distance a la face la plus proche. Mauvais choix. Le joueur ralentissait des qu'il LONGEAIT
une haie, sans meme la regarder. Penible.

Un rayon lance devant lui detecte une **intention** : on ralentit parce qu'on va vers la haie, pas parce qu'on
est a cote. `RAY_LENGTH` 4 studs, court expres, il faut vraiment se planter devant.

- Origine a `RAY_HEIGHT` au-dessus du centre : hauteur de poitrine, la ou l'outil travaille.
- `LookVector` du `HumanoidRootPart` : il ne s'incline jamais, le rayon reste horizontal meme en pente.
- Le personnage est EXCLU du filtre, sinon le rayon taperait dans l'outil qu'il tient, a zero stud.
- Hysteresis conservee : `RAY_LENGTH_ENGAGED` (5.5) une fois accroche, sinon l'etat clignoterait a la limite.

### La normale de face est recalculee, pas prise du raycast

`result.Normal` vient du TRIANGLE touche : sur un MeshPart de haie, elle part dans tous les sens selon la
feuille visee. Pour orienter le joueur et la camera il faut une direction propre.

On projette donc le point d'impact dans le repere de la haie (`PointToObjectSpace`) et on retient le cote dont
le plan est le plus proche. Une haie tournee de 37 degres se traite comme une haie droite.

Seuls les quatre COTES sont candidats, jamais le dessus : on ne taille pas une haie en marchant dessus.

La normale finale passe par `VectorToWorldSpace` et non `PointToWorldSpace` : une direction ne doit pas subir
la translation de la haie.

### Debug visuel, cote CLIENT

`Client/HedgeController.luau`. Barre Neon le long du rayon : verte quand une haie est visee, orange sinon,
longueur arretee au point d'impact.

Premiere version dessinee par le SERVEUR : elle trainait derriere le personnage. Le client possede son
personnage et le bouge instantanement ; une part creee par le serveur, elle, arrive avec la latence et
l'interpolation de replication. D'ou le decalage lisse, tres visible en tournant.

**Repartition retenue** : le client dessine la GEOMETRIE, le serveur donne le VERDICT via l'attribut
`LeafiaAtHedge`. Aucune regle de jeu n'est dupliquee, et la couleur reflete toujours la vraie decision serveur.

- `RenderStepped` et non `Heartbeat` : on dessine juste avant le rendu, donc sur la MEME position que celle qui
  sera affichee. Sur `Heartbeat` la barre aurait une frame de retard.
- Parentee a `workspace.CurrentCamera` : rien de ce qui vit la n'est replique ni sauvegarde, c'est l'endroit des
  objets purement visuels et locaux.

Le rayon part desormais du CENTRE du `HumanoidRootPart`, sans decalage vertical.

**`DEBUG_RAY` a passer a `false` avant toute publication.**

## 0.0.56 — Detection par VOLUME et non par ligne

Symptome : une haie clairement devant le joueur n'etait pas detectee. Grossir la barre de debug n'y changeait
rien.

Cause : un `Raycast` teste une LIGNE infiniment fine, partie du centre du `HumanoidRootPart`. Une haie plus
basse ou plus haute que ce niveau passait dessous ou dessus sans jamais etre vue. La barre de debug, elle,
avait une taille cosmetique reglable a part : elle touchait visuellement la haie alors que la ligne centrale
passait a cote. **Un debug qui ne montre pas ce qui est reellement teste est pire que pas de debug.**

Correction : `WorldRoot:Blockcast(cframe, size, direction, params)` — un lancer de volume.

- `DETECT_WIDTH` (1.5), `DETECT_HEIGHT` (4), `DETECT_THICKNESS` (0.2). Ces valeurs sont REELLES, plus
  cosmetiques : elles definissent ce qui est teste.
- `DEBUG_RAY_WIDTH` / `DEBUG_RAY_HEIGHT` supprimees. La boite de debug reprend exactement `DETECT_WIDTH` et
  `DETECT_HEIGHT` : **ce qu'on voit EST ce qui est teste.**
- La boite part orientee comme le regard (`CFrame.lookAt`), sa profondeur suit la direction du lancer.

Regle a retenir : **un outil de debug doit partager ses valeurs avec le code qu'il illustre, jamais les
siennes.** Deux jeux de constantes finissent toujours par diverger, et le debug se met a mentir au pire
moment.

## 0.0.57 — Haie, couche 2 : orientation forcee et camera de travail

Devant une haie, le personnage pivote pour lui faire face et la camera passe en vue de travail. En reculant,
tout se relache.

### Cote CLIENT, pas serveur

Le client possede son personnage et sa camera. Forcer l'orientation depuis le serveur se battrait contre la
simulation locale et donnerait du rubber-banding. **Le serveur DECIDE** (il pose `LeafiaAtHedge` et
`LeafiaHedgeNormal`), **le client OBEIT**.

### Orientation

- `Humanoid.AutoRotate = false` pendant l'accroche. Sans ca Roblox tourne le personnage dans la direction ou
  il MARCHE : le joueur qui longe la haie se retrouverait de profil, impossible de tailler.
- Le joueur garde le controle de son DEPLACEMENT (il longe la haie en marchant sur le cote), il perd celui de
  son orientation. C'est le but : elle est toujours bonne pour travailler.
- La normale sort de la haie, donc on regarde dans le sens INVERSE.
- Lerp exponentiel avec `dt` dans le facteur : meme vitesse de pivot a 30 et a 60 FPS.

### Camera

`Scriptable` pendant l'accroche, `Custom` au relachement. Position calculee a partir de la NORMALE et non du
regard du joueur : elle reste donc stable pendant que le personnage pivote.

`CAMERA_SIDE` (4) donne l'angle 3/4 isometrique. `CAMERA_LERP_SPEED` volontairement lent : une camera qui
claque en place donne la nausee meme quand la position finale est bonne.

### Le piege regle au passage : CameraOffset ignore en Scriptable

`Humanoid.CameraOffset` n'est applique que par les scripts de camera PAR DEFAUT de Roblox. Des qu'une feature
passe la camera en `Scriptable`, il est ignore.

Sans correction, secousse, bob et plongee d'atterrissage auraient disparu **exactement au pied d'une haie**,
donc precisement la ou le futur retour de coupe devra se voir. Le genre de bug qu'on decouvre trois semaines
plus tard en cherchant du cote du mauvais module.

`CameraEffects.GetOffset()` expose le decalage compose ; la camera scriptee l'applique elle-meme, apres son
lerp et en repere local (un impact doit claquer, pas se fondre).

`HedgeController` s'initialise EN DERNIER : l'ordre des connexions `RenderStepped` suit l'ordre des `init`, et
il lui faut le decalage deja calcule cette frame.

### Decrochage automatique

Reculer eloigne le joueur, le volume de detection ne touche plus, le serveur passe l'attribut a `false`, tout
se relache. Aucun code de sortie a ecrire.

### Point a evaluer au test

Le retour en `CameraType.Custom` rend la main a la camera par defaut, qui reprend a SA position : il peut y
avoir un petit saut. A voir si ca se remarque avant d'ecrire une transition de sortie.

## 0.0.58 — Hysteresis de face, camera plus haute, espace vital

### La camera oscillait dans les angles

Dans un coin de haie, deux faces sont a EGALITE. La face retenue basculait a chaque frame au moindre
tremblement du joueur, la normale sautait, la camera partait en gauche-droite.

`FACE_SWITCH_MARGIN` (1.2 stud) : une face gardee tant qu'une autre ne la bat pas nettement. Verifie par
simulation sur un joueur qui tremble dans un coin : **4 basculements sans, 0 avec.**

L'hysteresis ne vaut que sur la MEME haie : en changeant de haie, la face repart de zero.

C'est le TROISIEME endroit ou l'hysteresis nous sauve (distance d'accrochage, longueur du volume, choix de
face). **Des qu'un etat est choisi par comparaison, il lui faut de l'hysteresis** : deux candidats a egalite
font clignoter le systeme. A retenir pour la selection de tranche quand viendra la coupe.

`CAMERA_HEIGHT` 7 -> 9.5. Le point vise ne bouge pas, donc monter la camera la fait plonger davantage.

### Espace vital autour des haies

Le joueur pouvait se coller a la haie. Une boite invisible, plus large de `BUFFER_MARGIN` (1.2) sur les cotes,
l'en empeche.

- **La PHYSIQUE fait le travail**, pas un repoussement en code. Elle gere le glissement le long de la haie, les
  sauts et les collisions entre joueurs, gratuitement. Un repoussement code aurait fait vibrer le personnage a
  chaque frame en se battant avec la simulation locale du client.
- Elargie sur les COTES seulement. En hauteur, son toit depasserait celui de la haie et le joueur marcherait
  sur du vide au-dessus.
- Nommee `HedgeBuffer`, distinct du prefixe `hedge_`, sinon l'auto-tag la prendrait pour une haie.

## 0.0.59 — Correction : la boite d'espace vital bloquait la detection

Erreur de ma part en 0.0.58 : j'avais affirme que `CanQuery = false` rendait la boite invisible aux raycasts
tout en gardant sa collision.

**Faux.** `CanQuery` n'a d'effet que si `CanCollide` est FAUX. Une part solide est toujours vue par les
raycasts, quoi qu'on mette dans `CanQuery`. La boite bloquait donc bel et bien la detection : plus aucune haie
n'aurait ete trouvee.

Correction : les boites vivent dans un dossier `Workspace.HedgeBuffers` et sont exclues explicitement du
filtre de lancer.

### Pourquoi un dossier et non un enfant de la haie

Un filtre de raycast exclut une instance **et tous ses descendants**. Rangee dans la haie, exclure la boite
aurait exclu la haie elle-meme : le probleme inverse, tout aussi bloquant.

Un dossier commun permet de tout exclure d'un coup, avec une seule entree dans le filtre.

Contrepartie : la boite ne meurt plus avec sa haie. Le lien est refait a la main via `hedge.Destroying`.

### Le meme filtre des deux cotes

Le debug client reprend exactement le filtre du serveur. L'oublier ferait s'arreter la barre AVANT la haie
alors que le serveur la detecte : le debug mentirait, encore.

### Les deux `CanQuery = false` restants sont valides

Parts d'outil et barre de debug ont `CanCollide = false` : la propriete y fonctionne normalement.

### `GetDebugId` est reserve aux plugins

Utilise d'abord pour donner un nom unique a chaque boite, il leve `lacking capability Plugin` dans un script
serveur normal.

Remplace par une table `haie -> boite`. Plus simple, et surtout plus juste : plusieurs haies portent le MEME
nom et le dossier leur est commun, donc identifier par le nom etait bancal des le depart.

## 0.0.60 — Pivot horizontal de la camera + curseur sur la haie

### Pivot au clic droit

La camera fixe etait etouffante. Clic DROIT maintenu + souris horizontale = la camera pivote autour du joueur.

- Le bouton gauche reste a l'outil, le curseur reste libre pour viser : le droit est le seul disponible.
- **Le personnage ne tourne pas.** Seule la camera pivote : on regarde son travail sous un autre angle sans
  jamais perdre le bon placement pour tailler.
- Uniquement l'axe horizontal. La hauteur de vue reste celle du reglage : on ne veut pas que le joueur se
  retrouve a regarder ses pieds ou le ciel en plein travail.
- Butee a `CAMERA_YAW_LIMIT` (70 deg) de chaque cote, sinon on passe derriere la haie et on travaille a
  l'aveugle.
- `MouseBehavior = LockCurrentPosition` pendant le glissement : sans ca le curseur sortirait de l'ecran au
  bout de deux pivots, et la bille de visee avec lui.
- Remis a zero au decrochage : on repart toujours d'une vue de face.

### Curseur sur la haie

Bille rose fluo posee la ou le curseur touche la haie. C'est **le point qui deviendra l'endroit ou l'on
taille** : le construire maintenant sert d'abord a voir ou on vise.

- **`ScreenPointToRay` et non `ViewportPointToRay`.** `GetMouseLocation` rend une position ECRAN, qui inclut
  le decalage de la barre du haut ; `ViewportPointToRay` l'ignore et la bille serait decalee verticalement.
- Calculee APRES la camera dans la meme frame : sinon elle viserait depuis l'image precedente et flotterait
  en arriere pendant les pivots.
- `CanQuery = false` fonctionne ici (la bille n'a pas de collision). Sans ca elle se trouverait elle-meme au
  lancer suivant et resterait collee devant la camera.

### Nouvel attribut `LeafiaHedge` sur chaque haie

Le client doit savoir si son curseur est sur une haie. Il lit un ATTRIBUT plutot que le tag CollectionService :
un attribut se replique de facon certaine, inutile de parier sur autre chose.

## 0.0.61 — Curseur recale, detection de biais

### La bille tombait sous le curseur

`ScreenPointToRay` etait le mauvais choix : la bille apparaissait ~36 px trop bas, pile la hauteur de la barre
Roblox. `GetMouseLocation` rend deja des coordonnees VIEWPORT, `ScreenPointToRay` ajoutait donc l'inset une
seconde fois.

Corrige en `ViewportPointToRay`.

**Une source web n'est pas une preuve.** Les pages consultees affirmaient l'inverse ; c'est l'ecran qui a
tranche. Regle notee dans `CLAUDE.md` : quand l'observe contredit le lu, corriger d'abord.

### Detection en eventail

Un seul lancer droit devant ratait la haie des que le joueur se presentait de biais, alors qu'il etait
manifestement en train de travailler dessus.

`DETECT_ANGLES = { 0, -40, 40 }` : trois Blockcast, le contact le PLUS PROCHE gagne. Chaque angle coute un
lancer par joueur et par frame ; trois suffisent largement.

Le debug dessine **les trois** barres. N'en montrer qu'une masquerait les lancers de biais, et on ne
comprendrait pas pourquoi une haie sur le cote est detectee. Encore la meme regle : le debug doit montrer tout
ce qui est teste, sinon il ment.

## 0.0.62 — Zone de chantier au sol, debug eteint

`DEBUG_RAY = false`. Les barres de detection ne s'affichent plus.

### Zone posee automatiquement

Chaque haie recoit son rectangle de beams au sol, clone de
`ReplicatedStorage.Assets.Zones.area_color_action`, dimensionne a l'emprise de la haie plus `ZONE_MARGIN`.

Le dossier `Assets/Zones` regroupera les autres marqueurs de ce type (depot, client), a cote de `Tools` et
`Effects`.

### Le piege : redimensionner une part ne deplace pas ses Attachment

L'outil Echelle de STUDIO les deplace, mais `part.Size = ...` en script ne les touche pas. Les beams seraient
restes a la taille du modele d'origine, quelle que soit la haie.

On remet donc les attachments a l'echelle nous-memes, proportionnellement au rapport des tailles. Ca marche
quelle que soit la facon dont ils ont ete disposes dans le modele : aucune supposition sur quel attachment est
a quel coin.

Verifie par calcul : un modele 4x1x4 sur une haie 3x3x15 donne une zone 8 x 20, avec les quatre coins pile aux
bords.

### Details

- Seul le LACET de la haie est repris. Si elle est legerement inclinee, la zone reste a plat au sol.
- Posee a la base de la haie, avec `ZONE_LIFT` (0.05) de soulevement : deux surfaces exactement au meme niveau
  se disputent l'affichage pixel par pixel et clignotent.
- `CanCollide = false` puis `CanQuery = false` : sans ca la dalle serait touchee par la detection, et le
  curseur se poserait dessus au lieu de la haie.

## 0.0.63 — Haie, couche 3 : le rail de travail

Decision de game design. Pendant l'accroche :

| Touche | Effet |
|---|---|
| Q / D | glisse le long de la haie, a distance constante |
| Z | rien. Le joueur est deja a sa place de travail |
| S | decroche et sort immediatement |

### Pourquoi PAS remapper Z/S en lateral

C'etait l'autre option envisagee. Elle casse la memoire musculaire : un joueur qui appuie sur Z attend
d'avancer. Si son personnage part sur le cote, il ne trouve pas ca ingenieux, il trouve les controles bizarres.

**Une commande qui ment sur ce qu'elle fait coute toujours plus cher qu'elle ne rapporte.** Ici les touches
gardent leur sens : c'est le MONDE qui restreint. Le joueur ne subit pas un remapping, il decouvre une
contrainte, et ca se comprend sans tutoriel.

### La distance constante n'est pas du confort

C'est ce qui rend la taille APPRENABLE. Si le joueur derive d'un stud vers l'avant ou l'arriere :

- le cadrage camera change
- la correspondance entre la souris et la hauteur de coupe change
- le meme geste ne coupe plus au meme endroit

Le joueur ne peut developper aucune precision parce que les regles bougent sous ses pieds. A distance fixe, le
meme mouvement de souris tape toujours au meme endroit.

`WORK_DISTANCE` (2.6) avec une zone morte de 0.25 : sans elle l'aimant pousserait en permanence et le joueur
sentirait une main dans son dos.

### Trois pieges techniques

**1. On ne lit PAS `humanoid.MoveDirection`.** Des qu'on contraint le deplacement avec `humanoid:Move()`,
`MoveDirection` devient notre propre valeur contrainte : on lirait notre sortie, et l'intention de reculer
serait invisible.

On passe par `ControlModule:GetMoveVector()`, l'input tel qu'il a ete saisi. Bonus : il ne depend pas du
clavier, AZERTY ou QWERTY sont geres par Roblox.

**2. `BindToRenderStep` a la priorite `Camera` (200), pas un `RenderStepped` simple.** Le module de controle
tourne a la priorite `Input` (100) et appelle `Move` avec l'input brut. Notre contrainte doit passer APRES,
sinon il ecrase la notre et le joueur avance librement. Un `RenderStepped` ne garantit pas cet ordre.

**3. La sortie passe par une direction NON contrainte.** Quand le joueur pousse vers l'arriere, le client
appelle `Move` avec sa direction brute. C'est cette direction que le serveur lit dans `MoveDirection` pour
decrocher tout de suite. Sans ca il faudrait reculer plusieurs studs a vitesse de travail avant d'etre libere,
et la sortie serait molle.

`EXIT_DOT` (0.5) vaut environ 60 degres de tolerance : assez large pour sortir en diagonale, assez strict pour
qu'un pas de cote ne decroche pas par accident.

## 0.0.64 — Deux corrections du rail

### Le deplacement suivait la camera

Q/D partaient en diagonale : l'input etait transforme par la CFrame de la CAMERA, tres decalee sur le cote
(`CAMERA_SIDE = -10`).

Les axes de travail sont desormais ceux de la FACE. Le joueur regarde la haie : sa droite la longe, son avant
y va. `right = (-normal):Cross(Y)`, et l'input s'y projette directement.

### Le personnage avancait et reculait tout seul

Cause trouvee apres avoir elimine deux fausses pistes (la force constante de l'aimant, puis la latence de
replication : ni l'une ni l'autre ne reproduisait le probleme en simulation).

**L'aimant se faisait passer pour le joueur.** Trop pres de la haie, il poussait vers l'arriere ; le client
transmettait cette poussee via `humanoid:Move`, donc elle atterrissait dans `MoveDirection` ; le serveur y
lisait une intention de sortir et decrochait. Ca raccrochait, l'aimant repoussait, ca redecrochait. Boucle
infinie, clavier au repos.

Deux corrections, l'une suffirait mais les deux se completent :

1. **L'aimant ne tire QUE vers la haie**, jamais vers l'arriere. Le trop-pres n'a pas besoin de lui : l'espace
   vital l'empeche physiquement. Une poussee vers l'avant ne peut jamais ressembler a une sortie.
2. **`EXIT_MIN_INPUT` (0.7)** cote serveur. Une correction d'aimant vaut au plus 0.45, une vraie poussee au
   clavier vaut 1. Les deux arrivent par le MEME canal ; seule leur ampleur les distingue.

Verifie : aimant a fond -> ne decroche pas. S -> decroche. Q/D -> ne decroche pas. Sortie en diagonale ->
decroche.

### Lecon

**Quand un systeme automatique ecrit dans le meme canal que le joueur, le recepteur ne peut plus distinguer
les deux.** Soit on separe les canaux, soit on rend l'automatique reconnaissable (ici : plus faible, et jamais
dans la direction ambigue). Le probleme n'etait ni dans l'aimant ni dans la detection de sortie, mais dans le
fait qu'ils partagent `MoveDirection`.

L'attribut `LeafiaHedgeDistance` est supprime : le client mesure sa distance LUI-MEME par un lancer local.
Deux sources de verite pour la meme grandeur, c'est exactement ce qu'on evite partout ailleurs.

## 0.0.65 — Temps mort de sortie

Sortir avec S faisait trembler la camera.

Le serveur decrochait, mais la frame suivante la haie etait TOUJOURS a portee (le joueur est a 2.6 studs, la
detection porte a 4) : ca raccrochait, la sortie etait redetectee, ca redecrochait. Soixante bascules par
seconde, et la camera passait de `Scriptable` a `Custom` a chaque fois.

`EXIT_COOLDOWN` (0.5 s) : aucune nouvelle accroche possible pendant ce delai. Il ne bloque QUE la nouvelle
accroche, jamais le travail en cours.

Simule : **21 bascules sans, 1 avec.**

Troisieme fois aujourd'hui que le meme motif mord (accroche, choix de face, sortie). **Tout etat booleen qui
depend d'une mesure a besoin d'une marge ou d'un temps mort.**

## 0.0.66 — L'acceleration se voit et se sent

Trois retours branches sur la MEME rampe de regime que les lames et le son. Une seule source de verite : rien
ne peut se desynchroniser.

### Camera qui se rapproche

`CAMERA_DISTANCE_THROTTLE` (9.5 au lieu de 13) pendant l'acceleration. Le lerp de camera existant fait la
transition, aucun code de plus.

### Champ de vision qui se resserre

`THROTTLE_FOV` (-5), applique comme un DECALAGE sur la valeur courante et non comme une valeur absolue : il
s'additionne au sprint et a la marche au lieu de les remplacer.

S'applique meme hors chantier : c'est une reaction a l'OUTIL, pas au lieu.

### Reaction de couple sur l'outil

`ToolService.setGripTilt(player, ratio)`. L'outil s'incline dans la main a mesure que le regime monte, comme
s'il tirait. Sans ca le moteur montait en puissance sans qu'on le SENTE dans les mains.

`ToolConfigs.tiltAxis` et `tiltMaxAngle` (10 degres a plein regime).

**Piege evite** : on repart TOUJOURS de `Held.baseC0`, la prise de repos memorisee. Multiplier la `C0` courante
ferait s'accumuler l'inclinaison frame apres frame, et l'outil finirait par tourner sur lui-meme.

### Nouvel attribut `LeafiaThrottle`

Pose sur le PERSONNAGE et non sur l'outil : deux controllers clients en ont besoin, et le personnage est le
seul objet que les deux tiennent deja.

Remis a `false` au rangement, sinon ranger l'outil en pleine acceleration laisserait la camera zoomee pour
toujours.

## 0.0.67 — La touche AVANT glisse aussi

Devant la haie il n'y a nulle part ou avancer : la touche avant ne faisait donc rien, ce qui se sentait comme
un blocage. Elle glisse maintenant dans le meme sens que la touche gauche.

| Touche | Effet |
|---|---|
| gauche | glisse a gauche |
| droite | glisse a droite |
| avant | glisse a gauche |
| arriere | SORT du chantier |

**`math.min(Z, 0)`** : seule la part AVANT de l'axe alimente le glissement. La part arriere est traitee juste
avant comme une sortie ; la laisser passer aurait fait glisser au lieu de sortir, et la touche arriere aurait
cesse de fonctionner.

Le total est clampe : avant + gauche ensemble ne doivent pas donner une vitesse double.

Verifie par table de verite, y compris les combinaisons contradictoires (avant + droite s'annulent).

## 0.0.68 — Le zoom d'acceleration se limite au chantier

Le rapprochement de camera etait deja limite a la zone (tout le code de camera de travail ne tourne que la),
mais le resserrement du CHAMP DE VISION s'appliquait partout.

Un resserrement dit "je me concentre sur ce travail". Il n'a de sens que s'il y a un travail devant : accelerer
dans le vide en traversant le jardin ne doit rien changer.

Il exige desormais les DEUX conditions : outil en main **et** accroche a une haie.

### Bug attrape au passage

`setThrottle` ne verifiait pas que le joueur tenait un outil. Cliquer les mains vides posait quand meme
l'attribut et resserrait la vue.

Verifie : mains vides -> non. Outil mais loin -> non. Pres mais sans clic -> non. Les trois reunis -> oui.

## 0.0.69 — Pas chasses le long de la haie

Devant une haie le joueur ne marche plus, il se deplace en pas chasses.

**UNE seule piste pour les deux sens.** Vers la droite elle est jouee A L'ENVERS (vitesse negative). Le miroir
est donc exact par construction, et il n'y a qu'une animation a maintenir au lieu de deux qu'il faudrait garder
synchronisees a la main.

| Touche | Sens | Lecture |
|---|---|---|
| gauche | gauche | endroit |
| droite | droite | ENVERS |
| avant | gauche | endroit |
| avant + gauche | gauche | endroit |
| avant + droite | immobile | arret |
| arriere | sortie | marche normale |

### Trois pieges evites

**`Play` remet la vitesse a 1.** Sans troisieme argument, regler la vitesse AVANT `Play` ne sert a rien : la
premiere image partirait a l'endroit avant d'etre corrigee. La vitesse est donc passee a `Play` directement.

**Demarrer a l'envers depuis le debut n'a nulle part ou reculer.** On place la lecture a la fin, et APRES
`Play` : `TimePosition` ne tient que sur une piste deja lancee.

**Changer de sens ne relance pas la piste.** `AdjustSpeed` sur une piste qui joue deja fait repartir la lecture
d'ou elle en est, dans l'autre sens. Relancer ferait sauter les jambes a la premiere image a chaque
changement de direction.

### Priorite

`Action`, pas `Movement` : a egalite avec la marche de Roblox les deux se melangeraient et les jambes
hesiteraient. La piste ne cle que les JAMBES ; la pose de maintien de l'outil est elle aussi en `Action` mais
ne cle que les bras et le torse. Les deux jouent ensemble sans se disputer un seul membre.

Cote CLIENT et non serveur, contrairement aux animations d'outil : le sens est calcule frame par frame depuis
l'input brut. Passer par le serveur ajouterait un aller-retour reseau a chaque changement de direction. Une
animation jouee sur son propre personnage se replique de toute facon aux autres joueurs.

Arret au decrochage, a la sortie, et a la disparition du personnage (la piste appartient a l'Animator qui part
avec lui).

## 0.0.70 — Le joueur avance quand son pied touche le sol

Le deplacement n'est plus continu. Un marqueur `WalkEvent1` pose dans l'animation declenche une POUSSEE au
moment exact ou le pied touche le sol ; entre deux pas le joueur glisse sur son elan.

Cause et effet sur la meme image. C'est ce qui supprime le patinage des pieds, et aucune minuterie ne peut
deriver par rapport a l'animation puisque c'est l'animation elle-meme qui donne le tempo.

`STEP_GLIDE` ne vaut pas zero volontairement : un arret NET entre chaque pas se sentirait comme des a-coups,
pas comme une marche.

### Filet de securite

Une piste jouee A L'ENVERS ne declenche pas forcement ses marqueurs. Sans repli, le glissement d'un cote
serait bloque net et rien a l'ecran ne dirait pourquoi.

Sans marqueur recu pendant `STEP_TIMEOUT`, on repasse en deplacement continu. Le debug affiche lequel des deux
modes est actif : c'est LA ligne a lire pour savoir si le pas chasse fonctionne vraiment.

### Reglage

`STEP_DECAY` decide de la duree de la poussee : `(STEP_PUSH - STEP_GLIDE) / STEP_DECAY` secondes.
2 -> 0.38 s, 4 -> 0.19 s, 6 -> 0.12 s. Trop haut, le joueur avance par a-coups ; trop bas, on retrouve le
deplacement continu.

### A L'ESSAI

Le pas chasse n'est pas valide. Tout ce qui le concerne est regroupe (`SLIDE_*` et `STEP_*` dans les configs,
`setSlide` cote client) : il n'y a qu'un bloc a enlever si l'effet ne convainc pas.

## 0.0.71 — Hauteur de coupe pilotee par la visee

`UpDownAnimation` n'est jamais JOUEE. Elle est lancee a vitesse ZERO puis parcourue a la main : sa premiere
image est la coupe basse, sa derniere la coupe haute. La piste sert de regle graduee que la hauteur visee
promene.

Deux images suffisent donc a couvrir toutes les hauteurs intermediaires. C'est la visee qui interpole, pas
l'animation.

La hauteur est ramenee sur la HAIE et non sur le joueur : le pied de la haie donne la pose basse quelle que
soit la taille du personnage ou la hauteur du terrain sous lui.

### Lissage

`UPDOWN_FOLLOW_SPEED` : les bras REJOIGNENT la hauteur visee au lieu d'y sauter. Le curseur bouge par pixels,
sans lissage les bras claqueraient a chaque secousse de souris. Temps de rattrapage mesure : 6 -> ~0.4 s
(lourd), 12 -> ~0.15 s (actuel), 25 -> ~0.08 s (nerveux).

Priorite `Action2`, au-dessus de la pose de maintien qui est en `Action` et qui cle les MEMES bras. A egalite
les deux se melangeraient et la hauteur visee ne serait jamais atteinte.

### Nouvel attribut `LeafiaEngine`

Le client ne pouvait pas savoir si le moteur tourne. Different de `LeafiaThrottle` : celui-ci dit "le moteur
tourne", l'autre "le joueur appuie sur le clic". On peut avoir le moteur en marche sans accelerer, et c'est
justement l'etat ou le joueur vise sa hauteur.

**Six endroits ecrivaient l'etat.** Poser l'attribut a cote de chacun etait la garantie d'en oublier un, et de
chercher ensuite pourquoi le client croit le moteur eteint alors qu'il tourne. Les six passent desormais par
une seule fonction `setState`, qui tient la table ET l'attribut du meme geste.

## 0.0.72 — Outils Studio : accrocher l'outil au rig d'animation

Deux scripts de barre de commandes, dans `scripts/studio/` (hors `src/`, donc Rojo ne les synchronise pas
dans le jeu).

`AttacherOutilAuRig.lua` cree le Motor6D `ToolGrip` sur le rig d'animation, avec la prise EXACTE du jeu :

```
C0 = RightGripAttachment.CFrame * gripOffset
C1 = Handle.GripLeft.CFrame
```

`VerifierPriseRig.lua` ne modifie rien : il repond OK / NON sur les quatre causes possibles (joint absent,
part ancree, Attachment manquante, Part0/Part1 mal branches).

### Pourquoi

Un `Tool` Roblox recoit un Motor6D `RightGrip` cree par le moteur a l'equipement. Un `Model` ne declenche
rien : sans joint, l'editeur d'animation ne voit meme pas l'outil.

Et poser l'outil A LA MAIN dans l'editeur donnerait des poses justes a l'ecran et fausses en jeu, avec une
recherche d'erreur du cote de l'animation alors qu'elle serait dans le placement.

### Limite assumee

La barre de commandes ne peut pas `require` un module du jeu : les valeurs sont RECOPIEES depuis
`ToolConfigs`. Changer `gripOffset` la-bas oblige a le changer ici. C'est ecrit en tete des deux fichiers.

### Regle d'animation

Ne JAMAIS cler la piste de l'outil. `setGripTilt` ecrit dans ce joint a chaque frame pour l'incliner avec le
regime moteur : une animation qui ecrit dedans aussi ferait deux ecrivains sur la meme propriete. On anime les
bras, l'outil suit.

## 0.0.73 — Prise de COUPE, distincte de la prise de demarrage

L'outil pointait vers le ciel pendant toute la taille. Ce n'etait pas l'animation : l'angle de l'outil DANS la
main vient du Motor6D, jamais des bras. Aucune animation ne peut le corriger.

Il gardait `offHandGripOffset`, l'angle regle pour TIRER LA CORDE. Tirer une corde et tailler une haie ne sont
pas le meme geste : il n'y a aucune raison que l'outil soit tenu pareil.

Nouveau `cutGripOffset`, applique a l'entree en `Running` via `ToolService.setGripOffset`. MEME main (gauche),
autre angle. Part de la valeur de demarrage : tant qu'on n'y touche pas, rien ne change par rapport a avant.

`setGripOffset` lit la main courante sur `motor.Part0` et non sur un etat garde de son cote : l'etat reel du
joint bat toujours celui qu'on croit avoir.

### Trois prises, pas deux

Le script Studio expose maintenant `PRISE = "coupe" | "demarrage" | "port"`. Animer une pose de coupe avec la
prise de demarrage donne un outil faux en jeu, et on cherche l'erreur dans l'animation.

## 0.0.74 — L'animation d'atterrissage tournait en boucle pour toujours

Trouve dans la console, pas a l'oeil :

```
Animation           | Action | poids 1.00 | vitesse 1
PasChasserAnimation | Action | poids 1.00 | vitesse 1
```

La reception restait a plein poids en permanence (bouclee dans l'editeur). Elle est en `Action`, comme le pas
chasse. **A priorite EGALE, Roblox ne choisit pas : il MELANGE.** Les jambes recevaient donc en permanence une
moyenne entre une reception et un pas chasse.

`track.Looped = false` force cote code, quoi qu'en dise l'editeur : une reception se termine par definition.

Ce genre de bug ne se voit pas a l'oeil. Il se lit dans la liste des pistes reellement jouees.

## 0.0.75 — Pas de chantier les mains vides

S'accrocher a une haie sans outil n'avait aucun sens : camera de travail imposee, orientation bloquee, vitesse
reduite. Que des contraintes, aucune contrepartie, et rien a l'ecran pour expliquer au joueur pourquoi il ne
peut plus avancer normalement.

Le test est fait AVANT tout le reste dans `updatePlayer`, et a CHAQUE frame, pas seulement a l'accroche :
ranger l'outil en plein chantier relache donc le joueur immediatement, au lieu de le laisser coince jusqu'a ce
qu'il pense a reculer.

Cout nul quand il n'y a rien a faire : `leaveHedge` sort tout de suite si le joueur n'etait pas accroche.

`DEBUG_SLIDE` repasse a `false`. Il avait fait son travail : c'est lui qui a montre la reception bouclee.

## 0.0.76 — La visee suit le PLAN de la face, plus la surface touchee

Viser le pied de la haie pour le balayer proprement faisait glisser le curseur SOUS la haie. Il tombait sur le
sol, la visee devenait nulle, et la pose sautait. Le lacher arrivait donc exactement la ou le joueur
travaillait.

La cause : on lisait l'endroit ou le rayon TOMBE. Rater la haie d'un pixel suffisait a tout perdre.

Desormais le rayon est projete sur le PLAN de la face. Un plan est infini : deborder ne le rate jamais. Le
lancer ne sert plus qu'a savoir QUELLE haie on vise, et cette haie reste memorisee tant qu'on est au chantier.

`VectorToObjectSpace` pour trouver la profondeur de la face : ca marche aussi sur une haie tournee.

### Marge

`AIM_MARGIN` = 3 studs de debordement accepte, en haut comme en bas. Au-dela, le joueur ne vise plus la haie
et on rend la main.

### Zones mortes

`AIM_DEADZONE` = 0.6 stud a chaque extremite. On remappe `[deadzone, hauteur - deadzone]` sur `[0, 1]` : plus
bas vaut le bas franc, plus haut vaut le haut franc.

Sans elle, tenir la pose la plus basse demanderait une visee au pixel. Le joueur n'atteindrait jamais vraiment
le bas, il tournerait autour. **Les extremites doivent etre les positions les plus FACILES a tenir**, ce sont
elles qu'on utilise le plus.

Mesure sur une haie de 8 studs :

| Hauteur visee | Pose |
|---|---|
| -4 studs | visee lachee |
| -3 a +0.6 | 0.00 (bas franc) |
| 4 | 0.50 |
| 7.4 a 11 | 1.00 (haut franc) |
| 12 | visee lachee |

## 0.0.77 — Contourner la haie devient possible

Impossible de passer de l'autre cote d'une haie. Pas un reglage trop serre : une erreur de conception.

La face travaillee etait choisie d'apres le POINT D'IMPACT. Or ce point est toujours SUR la haie : sur une
haie de 2 studs d'epaisseur, la face avant et le bout se retrouvent a moins d'un stud l'un de l'autre.
`FACE_SWITCH_MARGIN` valant 1.2, **la face avant ne pouvait mathematiquement jamais perdre**. Aucune valeur de
marge n'aurait repare ca : elle aurait ramene l'oscillation dans les angles avant de debloquer le contournement.

Le critere mesure desormais de combien le JOUEUR a depasse le plan de chaque face. Le joueur, lui, s'ecarte
franchement quand il contourne : les valeurs se separent, et la marge redevient ce qu'elle doit etre, une
simple zone de calme.

Trajet simule (haie 20 x 8 x 2, joueur a 2.6 studs) :

| Critere | Resultat |
|---|---|
| Ancien (point d'impact) | avant -> avant -> ... -> avant (bloque) |
| Nouveau (position joueur) | avant -> bout -> arriere |

Non-regression verifiee sur 300 frames avec bruit :

| Trajet | Changements de face |
|---|---|
| Longe la face avant sans depasser les bouts | 0 |
| Pietine PILE dans l'angle | 0 |
| Depasse les deux bouts | 2, tous legitimes |

L'oscillation gauche-droite de la camera dans les angles, corrigee en son temps par la marge, ne revient pas.

## 0.0.78 — On reste accroche par PROXIMITE, plus par le regard

Le critere de face corrige ne suffisait pas : il restait un second verrou.

L'orientation du joueur est bloquee face a la haie. En glissant vers le bout, son eventail de detection finit
donc par pointer DANS LE VIDE. Le contact tombait AVANT qu'il ait avance assez pour que la face du bout
l'emporte, il se raccrochait aussitot sur la face avant, et il tournait en rond.

**Le REGARD sert a s'accrocher, c'est une intention. La PROXIMITE sert a rester, c'est un chantier.** Deux
questions differentes, elles n'ont pas a avoir la meme reponse.

Une fois accroche, on ne verifie plus que la distance a la BOITE de la haie (`HOLD_RANGE` = 6 studs). Distance
a la boite et non au centre : une haie de 20 studs de long ne doit pas compter comme "loin" parce qu'on se
tient a son extremite. Calcul a la main en bornant le point sur chaque axe, donc valable aussi sur une haie
tournee.

Sortir volontairement reste possible a tout moment : la detection de sortie passe AVANT ce test.

### Verification

Le joueur maintient UNE SEULE touche pendant 9 secondes, aucune autre entree :

| Temps | Face |
|---|---|
| 0.00 s | avant |
| 1.72 s | bout |
| 2.82 s | arriere |
| 6.20 s | bout |
| 7.33 s | avant |

Tour complet de la haie, sans jamais decrocher, et retour au point de depart.

## 0.0.79 — Tourner le coin n'est plus lu comme une sortie

Le joueur etait ejecte du chantier sans avoir touche a la touche de sortie, au moment precis ou il contournait.

En tournant le coin, la normale pivote de 90 degres. Le glissement lateral d'avant se retrouve donc ALIGNE
avec la nouvelle normale, et le test de sortie le lisait comme une fuite.

`FACE_CHANGE_GRACE` = 0.35 s pendant lesquelles on ne juge plus l'intention de sortir apres un pivot de face.
Assez long pour couvrir la latence de replication de la nouvelle normale vers le client, assez court pour
qu'une vraie sortie juste apres un coin reste immediate.

Le pivot est detecte par `Dot < 0.99` et non par egalite : deux normales cardinales identiques peuvent
differer d'un epsilon apres les allers-retours de repere, et le delai se rouvrirait a chaque frame.

### La simulation ne suffisait pas

Le premier modele ne reproduisait PAS le bug : il recalculait la direction depuis la nouvelle face
instantanement. Il a fallu modeliser la LATENCE (le client continue de glisser sur l'ancien axe le temps que
la normale lui parvienne) pour que le bug apparaisse.

Une simulation qui ne reproduit pas le bug rapporte ne prouve rien : elle dit seulement que le modele est
incomplet.

`HOLD_RANGE` passe de 6 a 8 pour la meme raison : le joueur s'ecarte pendant ce delai.

| Latence | HOLD = 6 | HOLD = 8 |
|---|---|---|
| 50 ms | tour complet | tour complet |
| 100 ms | tour complet | tour complet |
| 150 ms | decroche | tour complet |
| 300 ms | decroche | tour complet (ecart max 7.2 studs) |

## 0.0.80 — Debug lisible

Les barres gardent leur TAILLE REELLE, celle qui est testee : les retrecir pour mieux voir ferait mentir le
debug, ce qui a deja coute une soiree. C'est la TRANSPARENCE qui monte (0.82).

Chaque barre porte un BillboardGui avec la part de portee CONSOMMEE avant de toucher (`72%`, ou `vide`). De
face, une barre courte et une barre longue se ressemblent alors qu'elles ne disent pas du tout la meme chose.
Les etiquettes sont decalees verticalement les unes des autres, sinon elles se superposent.

La couleur est desormais decidee LANCER PAR LANCER. Trois barres toutes vertes disaient "une haie est
detectee", ce qui n'apprend rien : on veut savoir LEQUEL des trois la voit, et a quelle distance.

## 0.0.81 — Le champ de vision suit l'INTENTION, plus la vitesse

Le champ de vision tremblait en marchant au pied d'une haie.

Cause : il se decidait sur la vitesse MESUREE contre un seuil unique. Depuis le deplacement au pas, cette
vitesse pulse entre la poussee et le glissement, et elle traversait le seuil a CHAQUE PAS.

Un effet ne doit pas se brancher sur une grandeur qui oscille par construction. Il se branche desormais sur
`MoveDirection`, l'INTENTION du joueur : elle ne retombe jamais a zero tant qu'il pousse sur ses touches.
Elle est deja horizontale, donc un saut ne l'elargit pas non plus : le filtre vertical d'avant devient inutile.

Deux protections en plus : un lissage du signal, et DEUX seuils (`0.30` a l'entree, `0.15` a la sortie).

| | Basculements en 6 s |
|---|---|
| Vitesse mesuree, seuil unique | 13 |
| Intention lissee, deux seuils | 1 |

### Couplage a connaitre

`MOVING_EXIT` (0.15) doit rester SOUS `STEP_GLIDE` (0.25). Le signal lisse ne descend jamais sous la plus
petite valeur brute, et au pied d'une haie cette valeur EST `STEP_GLIDE`. Baisser `STEP_GLIDE` sous 0.15
ramenerait le tremblement.

Note ecrite des DEUX cotes : dans le controller et dans la config. Un couplage entre deux fichiers qu'un seul
des deux mentionne est un piege a retardement.

Marge mesuree en regime etabli, toutes cadences de pas confondues : le signal oscille entre 0.25 et 0.54.
Arret complet : retour au repos en 0.12 s.

## 0.0.82 — La reaction de couple a son propre rythme

L'inclinaison de l'outit suivait la rampe des lames : 0.72 s pour arriver a fond. Trop mou.

Les lames montent lentement parce que c'est une MASSE qui prend son elan, et le son est cale dessus. La
reaction de couple, elle, est immediate : c'est le poignet qui encaisse, pas un volant d'inertie. Les caler
ensemble etait une erreur de modele, pas un reglage trop bas.

`tiltFollowSpeed` = 14, et l'inclinaison vise directement l'ACCELERATEUR au lieu de la vitesse de lame
atteinte.

| Reglage | 90 % atteint en |
|---|---|
| Ancien, cale sur les lames | 0.72 s |
| 8 | 0.28 s |
| **14** | **0.15 s** |
| 22 | 0.10 s |
| 30 | 0.07 s |

Contrepartie assumee : a mi-regime, inclinaison et vitesse de lame ne correspondent plus exactement. C'est
voulu, ce sont deux phenomenes physiques differents.

## 0.1.0 — LE GESTE DE TAILLER EXISTE

C'est le commit qui compte. Depuis 0.0.1, tout etait de l'habillage pose avant le coeur. La, on taille une haie
et la forme change sous le geste. Ce que la regle d'or exige de valider AVANT tout le reste existe enfin, et une
vraie personne peut le prendre en main. Ce qui suit a ete construit par-dessus les carreaux de 0.0.91.

### La coupe (HedgeCutService)

Le client envoie le SEGMENT de la lame (base + pointe, le long du plus grand axe de l'outil), pas un point. Le
serveur teste la distance de chaque carreau a ce segment : la coupe est une CAPSULE, pas une sphere. C'est ce
qui fait couper TOUTE la lame, le bout compris. Une sphere autour d'un seul point ratait la pointe, ce qui se
lisait a l'ecran comme un bout de taille-haie inerte.

`SetAim` (client -> serveur) valide deux Vector3 et borne la longueur de lame ; le serveur garde l'autorite sur
la vitesse de coupe, la haie concernee et la portee. `CUT_RADIUS` est un chiffre UNIQUE : il pilote la coupe ET
le cylindre d'aide, ils ne peuvent donc pas se contredire (le guide ne ment jamais sur ce qui tombe).

### Les feuilles (HedgeLeafController)

Rendu, balancement et couleur calcules CHEZ CHAQUE CLIENT : une part que le serveur bouge replique sa CFrame a
tout le monde, mille feuilles animees videraient la bande passante pour du decor. Le serveur possede la DONNEE
(la pousse, dans un attribut), le client en deduit le RENDU. Aucun des deux ne se dispute la meme CFrame.

- Balancement par bulle : seules les feuilles a portee du joueur remuent, mesure depuis le carreau, sans racine.
- Couleur en deux etages : vert frais -> vert taille a mesure de la pousse, puis rouge d'acharnement par-dessus
  une fois passe un seuil de degats. La marge silencieuse rend la regle apprenable au lieu de punitive.
- Retrecissement a la taille, plancher borne a la taille de depart de CHAQUE feuille (sinon un plancher trop
  haut fait GROSSIR les petites feuilles en les taillant).
- Peignage (`LEAF_TRIM_SPIN`) : la feuille pivote a mesure qu'elle est taillee. Les feuilles poussues partent
  dans tous les sens, les taillees s'alignent. Le desordre pousse, le propre est peigne.

### Habillage des haies

- `HedgeBranchService` : la couche de branches vue a travers les trous. Volume defini en STUDS (marges laterale
  et haute), jamais en pourcentage : un pourcentage baille aux extremites des grandes haies et depasse par le
  dessus des petites.
- `HedgeGroundService` : une plaque de terre au pied de chaque haie.
- `HedgeStockService` : quatre zones de depot au sol, une par cote, ou les feuilles coupees s'entasseront.
- Zone de chantier : un rectangle marque au sol autour de la haie, pour montrer ou se situe le travail.
- Dessus de haie : carreaux du bord biseautes et descendus (une vraie haie n'a pas d'arete vive, et le dessus
  plat faisait un chapeau), plus un basculement des feuilles reserve a cette face (`LEAF_TILT_TOP`) pour lui
  rendre du volume sans decoller celles des cotes.

### Le personnage fantome au travail (CharacterFade)

Au travail, le corps du joueur devient semi-transparent, sauf les mains qui tiennent l'outil. Par
`LocalTransparencyModifier` et non `Transparency` : ca ne se replique pas (les autres voient un perso normal en
CO-OP) et ca s'ajoute a la transparence du jeu au lieu de l'ecraser. Le fondu se cle a 0 pile en sortie de haie,
sinon un residu de transparence fait chevaucher les membres au rendu.

### Notifications (Toast)

Primitive UI reutilisable, `Modules/UI/Core/Toast`. Ecoute le remote `UI/Notify` (serveur -> client), quatre
types d'accent. Sens unique : le client affiche ce que le serveur demande, aucune autorite en jeu.

### Polish du loading

- Rebond slime du logo prolonge.
- Onde de choc retiree.
- Zoom de reveal qui SUIT le joueur : une boucle par frame recalcule la cible depuis la position COURANTE du
  joueur au lieu de viser un point fige. On peut courir pendant le reveal, la camera reste collee.

### Note — la regle d'or, maintenant

Le coeur existe. La prochaine etape N'EST PAS une feature. C'est le test des trois personnes reelles : est-ce
qu'elles retaillent une deuxieme haie sans qu'on leur demande ? Tant que la reponse n'est pas oui, on ne
construit rien par-dessus (ni jauge d'XP, ni combos, ni escabeau, ni tycoon). C'est ce qui a manque aux deux
projets d'avant : l'emballage a recouvert un coeur jamais valide.

## 0.0.107 — Tailler remplit la jauge d'XP (runtime, sans sauvegarde)

Tailler une haie fait maintenant gagner de l'XP et monter de niveau. Nouveau ExperienceService (autorite serveur) :
chaque CARREAU amene au ras rapporte de l'XP, via biteAt (le point UNIQUE par ou passent le taille-haie continu ET
la cisaille au clic, donc un seul branchement couvre tous les outils et contextes). Il pose XpFill (0-1) + XpLevel
sur le joueur, que la jauge affiche. Courbe geometrique (genereux tot, plus long ensuite), reglee dans
ExperienceConfigs (XP_PER_CELL, LEVEL_BASE, LEVEL_GROWTH). Au level up, la barre tient PLEINE un court instant avant
de repartir au nouveau niveau : le gain se LIT, pas de reflux qui ressemblerait a une perte.

RUNTIME SEULEMENT (demande du joueur) : l'etat vit en memoire, remis a zero a chaque session, AUCUNE ecriture
DataStore. On valide d'abord que gagner de l'XP en taillant est satisfaisant ; le branchement sur
DataTemplate.Skills.Trimming (persistance) viendra apres. Noms d'attributs partages client / serveur via
ExperienceConfigs, pour qu'ils ne divergent jamais.

Petit plus : a chaque level up, le texte de niveau fait un PUNCH (grossit d'un coup puis se pose, via un UIScale
dedie). Simple pour l'instant, les effets viendront par-dessus.

## 0.0.370 — L'herbe tondue reprend la taille de l'herbe normale

Les touffes tondues etaient reduites a 40 %, ce qui laissait des TROUS entre elles : on voyait le sol.

`MOWN_SCALE` passe a 1. La touffe ne change plus de taille du tout -- c'est le MAILLAGE qui dit "coupe", pas les
dimensions.

### Deux essais, la meme idee fausse

- Ecraser la HAUTEUR (l'ancien `MOW_CUT`) : deformait le maillage d'herbe rase, comprime dans une boite trop
  basse.
- Reduire sur les TROIS axes (0.4) : ne deformait plus, mais retrecissait aussi l'EMPRISE AU SOL. La pelouse
  tondue se clairsemait -- des trous, pas un gazon.

Les deux partaient de la meme idee fausse : que la TAILLE devait porter l'information "coupe". Elle ne le doit
pas. Une forme d'herbe rase ressemble a de l'herbe rase, quelle que soit la boite dans laquelle on la met.

Bonus : le facteur etant constant, la taille des touffes tondues n'est plus reecrite a chaque image.

## 0.0.513 — L'herbe coupee ne remonte plus du tout : elle DESCEND, un point c'est tout

Le mouvement en cloche disparait. La touffe est ecrasee par la lame, on remplace son maillage pendant qu'elle est
basse, et elle se reduit ensuite a sa hauteur tondue. Un seul mouvement, vers le bas.

### La sortie de terre ne servait plus a rien

Elle existait pour CACHER le remplacement du maillage. Mais ce remplacement se fait deja a MI-COUPE
(`MOW_SWAP_AT`), quand la touffe est tassee sous la machine : il etait donc cache DEUX FOIS.

Et le desordre venait de la : la sortie de terre partait TOUT DE SUITE, alors que la reduction de hauteur
attendait `CUT_RISE_DELAY`. La touffe remontait donc a pleine hauteur avant de redescendre.

La correction de 0.0.494 (le plafond de hauteur) empechait deja de DEPASSER l'herbe intacte, mais elle ne pouvait
rien contre l'ordre des deux mouvements -- elle bornait le symptome.

`CUT_RISE_DEPTH` et `CUT_RISE_UP_TIME` partent, avec le compteur d'emergence et sa ligne de cache.

### La descente est adoucie aux deux bouts

`e * e * (3 - 2e)` : elle part de zero, accelere, puis se repose.

En lineaire, la descente demarre a PLEINE vitesse. Sur une seule touffe ca ne se remarque pas ; sur une bande
entiere qui part en meme temps derriere la machine, ce depart sec se lit comme un clignotement au passage.

### La regle generale

Quand deux mouvements se contredisent, supprimer celui qui ne sert plus coute moins cher que de les mettre
d'accord.

## 0.0.512 — La fleche orbite autour de la tondeuse et DEVANCE le virage

On braque, elle part tout de suite -- et la machine la rattrape. C'est ce decalage qui la rend utile : une fleche
calee sur le cap ne dirait rien de plus que le nez de la machine, qu'on voit deja.

Elle ne se contente pas de pivoter, elle TOURNE AUTOUR de la tondeuse : elle sort du cote ou l'on va.

### On lisse l'ANGLE, jamais la position

Interpoler la position d'un objet qui ORBITE coupe la corde de l'arc : il plonge vers le centre puis ressort, et
sa distance varie pendant le virage. En lissant l'angle puis en le posant SUR le cercle, la fleche reste a son
rayon du debut a la fin.

Le projet a deja paye ce piege sur la camera d'orbite.

### On lui donne l'INTENTION, pas le cap obtenu

Le meme produit que la rotation reelle -- braquage, sens de reglage, marche arriere -- sans le taux ni le temps.
Une fleche calee sur le cap SUIT la machine au lieu de la devancer, ce qui est exactement l'inverse du but.

C'est aussi pour ca que l'appel est descendu dans la fonction : c'est le premier endroit ou le SENS du virage est
connu.

### Reglages

- `MARKER_LEAD_ANGLE = 55` (negatif pour partir de l'autre cote)
- `MARKER_LEAD_SPEED = 8` -- haut expres : une intention est immediate. Trop bas, la fleche arrive APRES la
  machine et l'effet s'inverse.
- `MARKER_RADIUS = 2.5` -- a zero elle pivote sur place, ce qui permet de regler l'angle seul.
- `MARKER_OFFSET` descend a -3.5.

## 0.0.511 — La fleche est retournee, descendue et grossie

Trois reglages, tous dans `MowConfigs` :

- `MARKER_YAW = 180` -- elle pointait a l'envers. Le sens depend de la facon dont le mesh a ete modelise, pas
  d'un calcul : ca ne se deduit pas, ca se voit a l'ecran.
- `MARKER_OFFSET` descend de 1.5 stud. Le milieu mesure tombe a mi-hauteur du carter, bien trop haut pour une
  fleche au sol.
- `MARKER_SCALE = 1.8`.

### Deux details qui evitent des bugs plus tard

La ROTATION vient en dernier dans le calcul, apres le deplacement : posee ainsi, elle fait pivoter le marqueur
SUR PLACE. Avant le deplacement, elle aurait fait tourner le decalage avec lui et la fleche serait partie
ailleurs -- on aurait alors regle la position pour compenser une erreur d'ordre.

La TAILLE est posee UNE FOIS a la creation, jamais par frame. Un mesh redimensionne en jeu CLIGNOTE quand sa
`RenderFidelity` est `Automatic` : Roblox echange le maillage selon la taille a l'ecran. Fixe, il ne clignote
pas.

## 0.0.510 — Un marqueur de direction posee sur la tondeuse

`Assets/Contents/MarkerDirection` suit la machine tant qu'elle tourne. Premiere etape : il se place au milieu.

### Il n'est PAS enfant de la tondeuse

Un enfant de plus deplace la bounding box du modele, donc son pivot, donc tout ce qui se calcule dessus -- et
rien ne le signale, puisque le coupable est un objet decoratif ajoute ailleurs. Le projet a deja paye ce piege
sur l'echelle.

Il vit donc dans le Workspace et se contente de suivre.

### Le milieu est MESURE, pas devine

La `RootPart` est a l'AVANT-BAS du carter, pas au centre : y coller le marqueur l'aurait pose devant la machine
et sous elle. On prend le centre de la boite englobante, ramene en repere machine.

Mesure UNE FOIS puis gardee : la refaire a chaque image couterait un `GetBoundingBox` par frame et la ferait
trembler quand les roues tournent.

### Purement local

Un repere de conduite aide CELUI QUI PILOTE. Le garder cote client evite de le repliquer chez des joueurs a qui
il ne sert a rien.

`CanQuery = false` avec `CanCollide = false` : sans le second le premier n'a aucun effet, et les raycasts de la
coupe verraient ce decor comme un obstacle.

### A FAIRE DANS STUDIO

Le mesh doit exister dans CETTE place : Rojo ne synchronise pas les Assets. S'il manque, un avertissement le dit
UNE fois -- le chemin est relu a chaque image, un warn par frame noierait la console.

`MARKER_OFFSET` decale le marqueur a partir du milieu, dans le repere de la machine.

## 0.0.509 — Le moteur redescend vraiment au ralenti

A l'arret, la boucle du moteur tournait a sa hauteur NORMALE. Le regime montait bien en accelerant, mais il ne
descendait jamais en dessous : on n'entendait donc pas la machine attendre.

### Le plancher etait cache dans la formule

`PlaybackSpeed = 1 + ratio * RUN_PITCH`. Ce `1` est le ralenti, et il n'apparaissait nulle part dans la config :
rien ne montrait qu'il existait, rien ne permettait de le baisser.

Les deux bouts sont nommes maintenant -- `RUN_PITCH_IDLE = 0.78`, `RUN_PITCH_FULL = 1.35`. Le haut ne bouge pas,
le bas descend. Egaliser les deux redonne une hauteur constante.

C'est le meme motif que les reglages dedoubles : une valeur qu'on ne peut pas regler parce qu'elle est ecrite en
dur au milieu d'un calcul.

## 0.0.508 — La pose "embarque" repond tout de suite, et au bon rythme

Trois symptomes, deux causes.

### Le retard : on mesurait la CONSEQUENCE au lieu de l'INTENTION

La pose partait sur la vitesse REELLE de la machine. Cette vitesse arrive en retard -- le temps que la tondeuse
prenne son elan -- donc on appuyait, et le personnage se penchait un instant plus tard.

Le client envoie desormais l'avance DEMANDEE, dans le meme message que le braquage : c'est la meme donnee, la
conduite, au meme rythme. Aucun remote de plus.

C'etait un choix explicite de la version precedente, et il etait faux : j'avais ecarte l'intention en pensant au
cas du mur (pousser contre un obstacle ne doit pas montrer une machine qui file). Le retard coute bien plus cher
que ce cas.

Le regard arriere, lui, GARDE la mesure. Il repond a "ou va la machine", une question sur le MONDE. Celle-ci
repond a "que demande le joueur", une question sur l'INTENTION. Deux questions differentes, deux sources.

### Le geste trop sec et trop rapide : un lerp ne peut pas jouer un timing

La position dans l'animation etait lissee par un lerp exponentiel. Un lerp part VITE et finit LENT : il
traversait les trois quarts du geste en quelques images puis rampait sur le reste. Le mouvement arrivait d'un
bloc, et les poses intermediaires passaient trop vite pour se voir -- d'ou "ce n'est pas ce que j'ai mis dans
l'editeur".

Lecture LINEAIRE maintenant : la position avance de `dt * vitesse` a chaque image, dans un sens ou dans l'autre.
L'animation se joue au rythme ou elle a ete faite, ses temps respectes image pour image.

`PUSH_PLAY_SPEED = 1` : exactement le rythme de l'editeur. Le monter accelere, le baisser ralentit.

### Le meme seuil que le client

`STEER_MOVE_EPSILON`, deja utilise cote client pour "le joueur demande d'avancer". Une seule question, une seule
reponse.

## 0.0.507 — La porte s'ouvre PAR LE CODE, et les eclairs des coups partent

Deux changements dans le meme fichier.

### La porte tourne par un angle, plus par une animation

`Scene1_opendoor` n'est plus lue. La porte pivote sur son gond par un angle qu'on ecrit, en deux temps comme
avant : elle s'entrebaille d'un coup, se fige, puis s'ouvre en grand lentement.

CE N'EST PAS UN CAPRICE DE STYLE. Une pose d'animation doit etre DEFENDUE : une piste qui se relache, un `Stop`
venu d'ailleurs, un rebouclage rate d'une image, et la porte se referme sans qu'on sache lequel des trois. D'ou
l'epinglage a la derniere image, sa re-affirmation a chaque frame, la garde contre une pause en retard, le
gardien qui verifie que personne n'a repris la main.

Un CFrame pose par le code RESTE pose. Il n'y a plus rien a defendre, donc plus rien qui puisse lacher :
**101 lignes remplacees par 17**.

Et chaque temps se regle maintenant a la seconde, dans la config. Le meme reglage dans une animation demandait
de rouvrir Blender, reexporter, recharger -- a chaque essai.

Trois pieges connus, traites d'avance :

- La base est relevee UNE FOIS. Le gond fait partie du modele, donc il tourne avec lui : relire le pivot a
  chaque etape ferait repartir la rotation d'une base deja tournee, et l'angle s'accumulerait.
- Un avertissement si le modele n'a pas de PrimaryPart. `GetPivot` suit alors la BOUNDING BOX, et la porte
  tournerait autour de son MILIEU comme une porte de saloon -- on chercherait la cause dans l'angle, pas dans un
  champ vide.
- Un jeton annule le mouvement precedent, et `onDone` ne part que si le mouvement va au bout : un mouvement
  annule ne doit pas declencher la suite d'une sequence qui n'existe plus.

La porte se referme a l'arret de la scene, comme avant (l'animation, en s'arretant, rendait sa pose de repos).

### Les eclairs des coups partent

Il ne reste que les particules de `Mid` et la gerbe d'etoiles. Les Beams, leur fondu, le releve de leur
transparence de repos et le nettoyage de fin s'en vont -- 90 lignes.

`END_WINDOW` part aussi : il ne servait qu'a l'epinglage de la porte.

## 0.0.506 — Le personnage se fait embarquer par la tondeuse

Quand la machine avance, il se penche en arriere, bras tendus -- comme si elle allait trop vite pour lui. C'est
une blague, pas une pose realiste, et c'est voulu.

La pose de VIRAGE part : les bras n'accompagnent plus le braquage. `PushLawnMowerAnimation` prend sa place et sa
priorite.

### "Jouer a l'envers quand on s'arrete" ne demande AUCUN code en plus

L'animation n'est pas jouee, elle est POSEE -- meme mecanique que le levier d'accelerateur et le regard arriere.
Une seule valeur monte vers 1 quand la machine avance et redescend vers 0 quand elle s'arrete, et la
`TimePosition` suit.

Deux sens, une valeur. Repartir en plein retour ne demande aucun cas particulier : elle change juste de
direction. Une version qui JOUE la piste puis la rejoue a l'envers aurait eu besoin d'un etat, d'une annulation,
et d'un cas pour le redemarrage a mi-chemin.

### On mesure l'avance REELLE, pas l'intention

Comme le regard arriere. L'animation raconte que la machine VA VITE : pousser contre un mur ne doit donc rien
declencher, alors que l'input de marche avant est a fond dans ce cas.

### Le meme seuil que le regime moteur

`SPEED_MOVE_EPSILON`, deja la. "Est-ce que la machine avance" est UNE question, elle ne peut pas avoir deux
reponses : un second seuil finirait par le contredire, et on verrait le personnage se pencher pendant que le
moteur redescend au ralenti.

### Deux pieges de piste posee, repris tels quels

- `Looped = true` malgre la vitesse zero : une piste non bouclee se RELACHE en arrivant a sa derniere image, et
  la pose sauterait au moment precis ou l'on veut la tenir.
- On s'arrete a `Length - epsilon` : sur la derniere image PILE, une piste bouclee est deja repartie a zero.

### A FAIRE DANS STUDIO

`PushLawnMowerAnimation` doit exister dans `Animations/Tools/LawnMower`. Son ID est en CODE (Rojo ne synchronise
pas les Instances Animation vers la place tuto), donc rien a recopier a la main cette fois.

## 0.0.505 — La gerbe d'etoiles part plus loin, plus petite et plus discrete

`TRAVEL` 0.30 -> 0.5, `SIZE` 0.20 -> 0.12 et `START_TRANSPARENCY` 0.25 -> 0.65. Reglages seuls.

Une gerbe discrete ACCOMPAGNE le coup au lieu de le remplacer. Trop visible, elle devient le sujet -- et ce
qu'on doit regarder a cet instant, c'est la porte.

Les deux vont ensemble : en partant plus loin, les etoiles balayent une plus grande part de l'ecran, donc la
meme opacite y pese davantage. Allonger la course sans les affaiblir aurait rendu la gerbe plus envahissante,
pas plus ample.

## 0.0.504 — Les feuilles du chargement ne rebondissent plus

Il ne reste qu'un mouvement : la feuille grossit a sa place, et elle y reste.

Le saut et le rebond partent. Sur SIX feuilles qui s'allument coup sur coup, ils faisaient six gestes qui se
recouvrent -- l'oeil ne suivait plus la vague, il voyait une agitation. Un indicateur de chargement doit se lire
d'un coup d'oeil, pas se regarder.

### Ce qui disparait avec

Huit reglages (hauteur et durees du saut, etirement en l'air, ecrasement au contact, redressement) et les trois
fonctions enchainees qui les jouaient. `LEAF_SEQUENCE` se reduit a la seule duree d'apparition -- et comme elle
etait CALCULEE, la pause entre deux tours s'est ajustee toute seule.

### Un commentaire mort emporte au passage

`-- Hauteur de CHUTE d'une feuille qui s'allume...`, coupe en plein milieu, decrivait une chute retiree il y a
plusieurs versions. Un commentaire faux coute plus cher que pas de commentaire : celui-la annoncait un reglage
qui n'existait plus.

## 0.0.503 — Une gerbe d'etoiles filantes a chaque coup

Huit etoiles jaillissent du point d'impact et filent vers les bords de l'ecran.

Elles ne remplacent pas les deux effets du monde, elles les DEBORDENT : particules et eclairs restent au point
d'impact, la gerbe part au-dela du cadre. C'est ce qui donne son echelle au coup.

### Nouveau primitif : `Modules/UI/Core/StarBurst`

Un seul argument, un point du MONDE. Pas de reglage par appelant : il doit pouvoir servir a la tondeuse ou a
n'importe quel impact sans etre retouche.

### Les noms des images PORTENT la direction

`MidUp`, `RightUp`, `RightMid`, `RightDown`, `MidDown`, `LeftDown`, `LeftMid`, `LeftTop` : chaque image est
DESSINEE pour sa branche. Les tirer au hasard les montrerait de travers. Chacune part donc dans son sens, et les
huit forment une etoile.

### Tout en fraction de la HAUTEUR d'ecran

Jamais en pixels : la gerbe garde la meme allure sur un telephone et sur un grand ecran. La hauteur et pas la
largeur, parce que c'est elle qui varie le moins d'un format a l'autre -- en largeur, la meme valeur donnerait
une gerbe ecrasee en 16:9 et enorme en 4:3.

### Trois pieges connus, evites d'avance

- `ScreenInsets = None`. `WorldToViewportPoint` rend des coordonnees dont l'origine est le coin ABSOLU de
  l'ecran ; avec l'inset par defaut toute la gerbe suivrait ~36 px trop bas.
- Chaque gerbe emporte SON lot. Balayer les enfants du ScreenGui a la fin ramasserait les etoiles d'une gerbe
  precedente encore en vol : deux coups rapproches se couperaient l'un l'autre.
- La duree de vie est CALCULEE depuis les durees d'animation, pas ecrite a la main. Le jour ou l'on allonge le
  fondu, la gerbe serait detruite avant de l'avoir fini.

### Rien a faire dans Studio

Les huit images sont des assets, pas des objets a poser. C'est le premier effet de la scene qui ne depend de
rien dans le Workspace.

## 0.0.502 — Les eclairs s'estompent au lieu de s'eteindre

Ils ne pouvaient pas durer plus longtemps : au-dela de ~0.35 s -- l'ecart entre deux coups -- un eclair est
encore allume quand le suivant part. L'etoile ne s'eteint alors plus jamais et devient un eclairage permanent.

Un FONDU n'a pas ce probleme. Deux fondus qui se recouvrent ne se lisent pas comme une lumiere fixe mais comme
des ECHOS : le nouveau coup part a pleine force pendant que l'ancien finit de s'eteindre. Duree portee a 0.45 s.

### On anime la TRANSPARENCE, pas `Brightness`

C'est la vraie raison pour laquelle le premier fondu (0.0.492) ne se voyait pas : les Beams ont `LightEmission`
a 0, donc leur eclat ne change rien de visible. J'avais anime la seule propriete sans effet, puis conclu que le
fondu ne valait pas ses garde-fous. Il les valait -- je m'etais trompe de propriete.

La transparence d'un Beam est une NumberSequence, mais celles-ci sont UNIFORMES ici (une seule valeur reglee
dans Studio). On retient donc ce nombre : l'animer a plat ne detruit aucun degrade.

### Une seule boucle, et un jeton

Une boucle pour tout le lot : ils s'allument dans la meme image, ils doivent s'estomper dans la meme.

Le jeton fait qu'un nouveau coup ANNULE le fondu precedent. Sans lui, deux boucles ecriraient sur les memes
Beams a chaque image et la valeur finale serait celle de la derniere a FINIR, pas de la derniere demandee. Et
l'ancienne boucle, en se terminant, eteindrait l'eclair que le nouveau coup vient d'allumer.

### L'etat de repos est RELEVE et RENDU

A la fin du fondu comme a l'arret du controller. Coupe en plein fondu, un eclair resterait allume ET transparent
-- l'effet ne marcherait plus jamais, sans que rien ne le signale.

## 0.0.501 — Les eclairs durent plus longtemps

`KNOCK_BEAM_TIME` 0.12 -> 0.25. Reglage seul.

### La borne haute, notee dans la config

Les coups s'enchainent toutes les ~0.35 s -- c'est l'ecart entre les marqueurs de l'animation. Au-dela de cette
valeur, un eclair est encore allume quand le suivant part : l'etoile ne s'eteint plus jamais entre deux coups,
et elle cesse de MARQUER l'impact pour devenir un eclairage permanent.

C'est le genre de limite qui ne se voit qu'a l'usage, et seulement sur le troisieme coup. Autant l'ecrire a cote
du reglage.

## 0.0.500 — Les eclairs partent TOUS ENSEMBLE

Ils sont disposes en etoile autour du point d'impact. En allumer trois au hasard ne dessinait qu'un fragment,
different a chaque coup : ca se lisait comme un scintillement, pas comme une frappe.

Tous d'un coup DESSINENT le point d'impact. Le tirage au sort disparait, et `KNOCK_BEAM_COUNT` avec lui.

### Un seul minuteur pour tout le lot

Ils s'allument dans la meme image, ils doivent s'eteindre dans la meme. Un minuteur par eclair derive -- et
l'etoile se defait par morceaux au lieu de disparaitre d'un bloc.

## 0.0.499 — Les eclairs reviennent, a cote des particules

Ils avaient ete retires parce qu'on ne les voyait pas. Ils marchaient : la part qui les porte n'etait pas
ANCREE, elle avait glisse, et les effets jouaient a un endroit qu'on ne regardait pas.

Ils reviennent donc, en plus des particules de `Mid`. Les deux ne font pas le meme travail : les particules
donnent la MATIERE qui gicle, les eclairs donnent le CHOC. L'un sans l'autre se remarque a peine.

### En version SIMPLE cette fois

Allume/eteint, sans fondu d'eclat.

La version precedente animait `Brightness` jusqu'a zero, ce qui obligeait a le RENDRE a chaque sortie possible
-- fin de fondu, arret du controller, mort du joueur -- sous peine de laisser les Beams a zero POUR TOUJOURS.
Trois garde-fous pour trois images d'effet, et aucun ne servait a rendre l'effet plus beau.

Reste le seul qui compte : l'extinction vit dans un `task.delay` que personne ne rattrape si la scene finit
avant lui. L'arret du controller les eteint tous.

### Meme conteneur, meme regle

Les Beams sont cherches sous `KNOCK_EMIT_PARENT`, comme les emetteurs : on prend TOUT ce qu'il contient sans
nommer quoi que ce soit. En ajouter un dans Studio suffit a l'inclure.

### A FAIRE DANS STUDIO

ANCRER `KnockEffect1`. C'est ce qui manquait depuis le debut -- une part non ancree tombe, et ses effets vont
jouer ailleurs.

## 0.0.498 — Le joueur disparait completement quand la porte s'ouvre

A 0.7 il restait une silhouette. Suffisant tant qu'on regarde une porte fermee -- mais un GRAND avatar masque le
grand-pere au moment precis ou l'on doit le voir.

Le personnage ne porte plus aucune information a cet instant : on sait ou l'on est, c'est LUI qu'on regarde.
Autant liberer le cadre.

### En fondu, pas d'un coup

Passer de 0.7 a 1 d'un claquement se voit : une forme qui disparait brusquement attire justement l'oeil sur
elle, au moment ou l'on veut qu'il aille ailleurs. 0.45 s.

### Une seule demande a la fois

Toute nouvelle demande annule la precedente. Deux fondus en cours ecriraient sur les memes parts a chaque image,
et la valeur finale serait celle du dernier a FINIR, pas du dernier demande -- le meme piege que deux tweens sur
une propriete.

Le fondu sort aussi de lui-meme si le personnage change en cours de route : mort ou respawn, il ne le concerne
plus.

### Deux valeurs, deux moments

`SCENE_PLAYER_FADE` (0.7) au debut de la scene, `REVEAL_PLAYER_FADE` (1) a l'ouverture. Une seule valeur aurait
force a choisir : soit on se voit pendant qu'on toque, soit on ne masque pas le grand-pere.

## 0.0.497 — Le jeu dit COMBIEN d'emetteurs d'impact il a trouves

"Aucun effet" couvre TROIS causes qui se ressemblent a l'ecran :

- le conteneur est introuvable ;
- il est trouve mais ne contient aucun emetteur ;
- les emetteurs sont bien trouves, et c'est leur bouffee qui ne se voit pas.

Les deux premieres etaient deja nommees. La troisieme ne l'etait pas -- et c'est la seule qui se corrige dans
STUDIO, sur les emetteurs eux-memes, pas dans le code.

Une ligne a la premiere frappe, une fois par session :

    [Tutorial] 2 emetteur(s) d'impact : Mid/Flare, Mid/Wave

Si elle sort, le code fait son travail et le reglage est a chercher sur les emetteurs (nombre de particules,
taille, duree de vie, transparence). Si elle ne sort pas, c'est l'un des deux autres cas, et l'avertissement le
dit.

## 0.0.496 — L'impact des coups passe des Beams a des particules

Les Beams sont remplaces par les ParticleEmitter poses dans l'attachment `Mid` de `KnockEffect1`. Chaque coup
les fait cracher d'un coup.

### `Emit` n'a AUCUN etat a rendre

C'est le vrai gain, au-dela du rendu. Une bouffee ponctuelle est finie a la seconde ou elle part : rien a
eteindre a l'arret de la scene, rien a restaurer a la mort du joueur.

La version a Beams demandait l'inverse. Il fallait relever leur eclat d'origine pour ne pas les laisser a zero
apres un fondu interrompu -- sinon l'effet ne marchait plus JAMAIS, sans que rien ne le signale. Trois
garde-fous pour un effet de trois images.

### On prend TOUT ce que le conteneur contient

Sans nommer les emetteurs. Ajouter un effet dans Studio suffit a l'inclure : le code n'a pas a savoir combien il
y en a ni comment ils s'appellent.

Le reste du reglage -- taille, duree de vie, vitesse, couleur -- vit sur l'emetteur, dans Studio. C'est la qu'on
le voit, donc c'est la qu'il se regle.

### Ce qui reste

Le message qui nomme ce qu'on n'a pas trouve, et la distinction entre conteneur ABSENT et conteneur VIDE : deux
causes qui se ressemblent a l'ecran et se corrigent a deux endroits opposes.

`TweenService` part du fichier : plus personne ne l'y utilisait.

### A FAIRE DANS STUDIO

`KnockEffect1` doit contenir l'attachment `Mid` avec ses ParticleEmitter. Rojo ne synchronise pas le Workspace.

## 0.0.495 — On verifie l'amont AVANT de travailler, plus seulement avant de pousser

Les regles de `CLAUDE.md` decrivaient l'ordre du PUSH -- commit, pull --rebase, push. Elles ne disaient rien du
DEBUT du travail.

Une ligne ajoutee : `git fetch` puis `git log HEAD..origin/main` avant d'ecrire quoi que ce soit.

Deux raisons, et la seconde coute plus cher que la premiere :

- un travail commence sur une base perimee se fusionne mal, et le conflit arrive au pire moment -- a la fin,
  quand on croyait avoir fini ;
- on peut REFAIRE ce que l'autre vient de faire. Un fichier local en retard se lit comme du code valide : rien
  ne signale qu'il est perime.

La regle vaut pour l'assistant comme pour les deux personnes du projet.

## 0.0.494 — L'herbe coupee ne repasse plus au-dessus de l'herbe intacte

La transition de coupe etait moche : la touffe remontait, et on la voyait DEPASSER l'herbe non coupee avant de
se reduire.

### Ce n'etait pas la sortie de terre

C'etait l'ECRASEMENT DE LA TONDEUSE QUI SE RELACHE.

La machine ecrase la touffe en passant, et c'est pendant qu'elle est basse qu'on remplace son maillage --
silhouette petite, changement invisible. Puis la machine s'eloigne, l'ecrasement se relache, et la touffe
REMONTE a pleine hauteur, avec le maillage coupe. Sa reduction de hauteur, elle, n'arrive qu'apres
`CUT_RISE_DELAY`.

Entre les deux, de l'herbe COUPEE depassait de l'herbe intacte.

Le trajet hors du sol (`CUT_RISE_DEPTH`, `CUT_RISE_UP_TIME`) etait innocent -- c'est le premier endroit ou on
serait alle regarder.

### Un PLAFOND, pas une animation de plus

La touffe garde la hauteur la plus BASSE atteinte depuis le debut de la coupe : elle reste couchee sous la lame,
puis se reduit. Elle ne repasse jamais par le haut.

Un plafond n'a rien a synchroniser avec `CUT_RISE_DELAY` -- donc rien qui puisse s'en desaccorder le jour ou on
retouche l'un des deux. Une animation de plus aurait ajoute une troisieme duree a garder d'accord avec les
autres.

### Il ne vaut QUE pendant la transition

Le garder ensuite figerait la pelouse tondue : un pas ne pourrait plus la coucher, et elle ne se releverait
jamais.

## 0.0.493 — Le rateau ramasse les feuilles, et la tondeuse ne derape plus

Une session de corrections, plus un nouvel outil.

### LE RATEAU (touche 3)

Il ramasse les petits tas que la taille laisse au sol et les rassemble en GROS tas. Le joueur TIRE A LUI : au
marqueur de l'animation, les tas d'une bande devant lui (7 studs de portee, 5.2 de large) glissent en arc vers
un point devant ses pieds et fusionnent. Quatre par coup au plus -- il faut VOIR le tas grossir, pas tout
aspirer d'un coup. Un coup a moins de 5 studs d'un gros tas existant le rejoint au lieu d'en creer un deuxieme.

Trois fichiers neufs : `RakeConfigs`, `RakeService` (toute la logique), `RakeController` (envoie le clic, rien
d'autre). Le service est cote SERVEUR parce que les tas sont des objets du MONDE : si le client les ramassait,
chaque joueur verrait une pelouse differente et le co-op serait faux des la premiere haie.

`HedgeStockService` POSE les tas, `RakeService` les RAMASSE. Deux moments du cycle, deux fichiers -- l'entete de
`HedgeStockService` l'avait deja prevu. Les gros tas vivent dans leur propre dossier (`workspace.LeafPiles`) et
portent leur compte en attribut : ils n'appartiennent plus a aucune haie, parce qu'ils iront un jour dans la Bin.

Effet de bord repare au passage : la liste de tas de `HedgeStockService` plafonne a 30 par zone et supprimait le
plus ancien. Elle gardait des references vers des tas que le rateau venait de ramasser, donc elle comptait des
morts -- et les NOUVEAUX tas s'effacaient tout seuls. Elle balaie maintenant les morts avant de mesurer.

### L'aimant de haie ne s'active plus que pour un outil de taille

Nouveau champ `cutsHedge` dans `ToolConfigs`. `HedgeService` n'accroche le chantier que si l'outil en main le
declare. Le serveur avait deja la bonne regle -- "mains vides = pas de chantier, sinon c'est une contrainte sans
contrepartie" -- elle est simplement generalisee : le rateau travaille le SOL, et l'aimant l'empechait de faire
son travail (impossible de s'ecarter pour ramasser).

Un champ EXPLICITE, jamais "cet outil a-t-il une lame ?". Deduire une intention d'un detail de fabrication rate
tout outil bati autrement -- le rateau n'a pas de lame et n'en aura jamais.

C'est exactement la faute qui RETIRAIT le rateau des mains du joueur pres d'une haie : l'auto-equip cherchait
`HitBoxRoot`, ne la trouvait pas, croyait les mains vides et tirait `ToggleTool` -- qui est une BASCULE, donc les
mains pleines il RANGE. Corrige des deux cotes (auto-equip et prise d'echelle) en lisant l'attribut `LeafiaTool`.

### La cisaille figeait le personnage, et le coupable etait un cache

`ToolService` indexait ses pistes d'animation par NOM COURT. Or la cisaille ET le taille-haie ont chacun leur
`IdleAnimation` dans LEUR dossier : le premier charge gagnait et servait sa pose A L'AUTRE.

Ca dormait depuis toujours. Ce qui l'a reveille : le prechauffage boucle avec `pairs(ToolConfigs)`, dont l'ordre
n'est PAS defini et CHANGE quand on insere une cle. Ajouter le rateau -- qui n'a meme pas d'animation homonyme --
a suffi a inverser le gagnant. La cisaille s'est mise a recevoir la pose du taille-haie, qui cle les jambes en
priorite Action : plus d'animation de marche.

La cle du cache est maintenant `dossier/nom`. La collision n'existe plus, quel que soit le nombre d'outils.

### La tondeuse ne derape plus en sortie de virage

Deux correctifs rates avant de mesurer : la trajectoire n'y etait pour RIEN. Un affichage temporaire a donne
0.6 degre de glissade reelle -- droit. Le coupable etait le BALLANT (`state.swing`), qui revient a zero par un
lerp exponentiel : il trainait encore 5 degres une seconde apres le virage et mettait plus de 3 secondes a
passer sous 1. En ligne droite, la machine roulait EN CRABE, ce qui se lit exactement comme un derapage.

Nouveau `SWING_SETTLE` (180 deg/s) : une vitesse de retour MINIMALE. Le lerp garde son elan au depart, le
plancher termine la fin au lieu de la laisser trainer. Retour a droit en 0.15 s au lieu de 3.4 s.

### La conduite repond mieux

- `TURN_SLOWDOWN` passe a 0. Le geste central est d'enchainer les virages en tondant : un frein a chaque
  braquage etait un frein permanent.
- L'input passe du DISQUE au CARRE. `GetMoveVector` rend un vecteur NORMALISE : avant + cote donnait
  (0.707, 0.707), donc braquer a fond en avancant coutait 29 % de vitesse ET 29 % de braquage. Ca n'a de sens
  que pour un personnage, qui se DEPLACE dans les deux axes ; ici ils sont DECOUPLES, le cote ne fait que
  braquer. La norme est preservee, donc le dosage analogique du joystick reste intact.
- `STEER_RADIUS` 8 -> 6 et `STEER_CRAWL` 2 -> 4 : virages plus courts, reorientation sur place moins molle.

### L'echelle ne se plante plus dans la haie

Le joueur etait tenu a 3.5 studs de la haie, un chiffre regle a la main. Or le bord AVANT de l'echelle tombe a
`CARRY_CLEARANCE + profondeur` devant lui : des qu'elle depasse 2.5 studs de profondeur, elle entre DANS la haie.

En cascade : l'echelle plantee dans la haie y plante AUSSI ses zones de grimpe, donc on ne peut plus jamais
monter dessus. Ce n'est pas la grimpe qui etait cassee, elle etait devenue inatteignable.

La distance de travail est maintenant CALCULEE depuis la profondeur reelle de l'echelle, mesuree au yaw de
portage (`ladderExtentsForYaw` rend le bord AVANT en plus du bord arriere -- c'est cette moitie qui manquait).
Le knob devient `LADDER_HEDGE_GAP` : l'ecart voulu, valable pour n'importe quelle taille d'echelle.

### L'aimant de portage ne colle plus au buisson

`nearestHedge` classait les haies par distance au CENTRE, alors que l'aimant, la normale et la portee du focus
travaillent tous sur la BOITE. Un petit buisson (`hedge_size_type_1`, donc une haie pour le jeu) battait la
longue haie qu'on longe : le joueur se retrouvait aimante et oriente vers le buisson, avec l'echelle soudee
devant lui qui rentrait dedans. Le classement utilise maintenant la meme mesure que le reste.

### Le prompt PRENDRE s'affiche enfin tout le temps

`InteractionPrompt` est un SINGLETON partage par six controllers. La PRISE d'echelle (radiale, 8 studs) et la
MONTEE (zone laterale, ENTIEREMENT incluse dans ces 8 studs) se doublaient a tour de role, et chacune gardait un
verrou "mon prompt est affiche" qu'elle ne rouvrait jamais : celle qui perdait ne revenait PLUS.

Trompeur au carre : les deux pilules ont le meme TITRE ("LADDER"), la meme hauteur, et seule la touche change --
on ne voit pas un prompt manquant, on voit le sien remplace sans le remarquer. Et la TOUCHE marchait toujours,
donc ca ressemblait a un bug d'AFFICHAGE alors que c'est un bug de PROPRIETE.

`show()` prend maintenant une PRIORITE et rend true/false ; une demande de priorite inferieure est refusee sans
toucher l'affichage. Meme idee que `CarryUtils` pour les mains : une seule question, une seule reponse, et les
deux features n'ont pas a se connaitre. La montee gagne dans sa zone, la prise partout ailleurs -- et F reste
actif quoi qu'il soit affiche. Les controllers ne cachent plus que SI la pilule est la leur (avant, s'eloigner
d'une echelle effacait le prompt du seau ou de la boite aux lettres).

### A faire dans Studio

Rojo ne synchronise ni les Assets ni les Animations : tout ce bloc se fait a la main.

- `Assets.Tools.RateauFeuilleMesh` : une part `Handle`, une Attachment `Grip` dedans (c'est elle qui donne
  l'orientation dans la main), un Humanoid + Animator (sinon `RatissageAnimation` ne joue pas), et des Motor6D
  dont les **Part1** portent les noms des poses (une anim retrouve un joint par le nom de sa Part1, jamais par
  celui du Motor6D).
- Regler `gripOffset` du rateau a l'oeil dans `ToolConfigs` : il est a 0/0/0, l'outil sera de travers au premier
  essai.
- `RatissageHumanAnimation` : le marqueur `RattissageEvent` (deux T) doit etre dans l'asset PUBLIE. L'editeur le
  garde en memoire, mais l'objet `Animation` pointe sur un ID -- republier apres l'avoir ajoute. Sans lui le
  rateau ramasse quand meme en fin de geste, et le serveur dit dans la console ce qui manque.
- `Shear/IdleAnimation` : si le personnage n'a toujours pas son animation de marche, cette pose cle les JAMBES.
  En priorite Action elle passe au-dessus de la marche. Une pose de maintien ne doit cler que les bras et le
  torse. Aucun reglage de code ne peut le corriger.
- Son optionnel : `SoundService.Sounds.Tools.Rake.RakeSweepSound`. Absent, tout marche et le service le dit une
  fois au boot.

### Limite connue

Les touches 1/2/3 n'existent pas au doigt : AUCUN outil n'est equipable sur mobile. Leur UTILISATION (le clic)
marche deja. C'etait vrai avant le rateau, ce n'est pas aggrave -- mais ca demande une barre d'outils a l'ecran,
un vrai chantier d'UI.

### Dette signalee

Le calcul de distance a la boite d'une haie existe maintenant en QUATRE exemplaires prives (`HedgeService`,
`HedgeCellService`, `LadderMoveController`, `RakeService`). Il merite un `HedgeGeomUtils` partage, a faire quand
on y retouchera.

## 0.0.492 — Les eclairs des coups deviennent lisibles

Ils partaient, mais on ne voyait rien. Trois causes, trois corrections.

### Un clignotement binaire est INVISIBLE

Allumer puis eteindre en 0.07 s ne laisse aucune trace : l'oeil ne retient qu'un changement qui DURE un peu.
L'eclair s'allume donc d'un coup et S'ETEINT EN FONDU -- attaque seche, extinction douce, comme une etincelle.

La duree passe a 0.28 s, mais elle ne se lit pas comme "plus long" : c'est la DECROISSANCE qui la rend visible,
pas la duree seule.

### On anime `Brightness`, pas `Transparency`

La transparence d'un Beam est une NumberSequence : elle porte le degrade dessine dans Studio, et l'ecraser par
une valeur plate le detruirait. L'eclat, lui, est un simple nombre.

### Trois d'un coup

Un seul Beam fin parmi neuf se perd, meme en le laissant plus longtemps. Trois font un impact, sans jamais tout
allumer -- le hasard garde son interet.

### L'eclat d'origine est RELEVE et RENDU

On l'anime jusqu'a zero. Coupe en plein fondu -- rideau, mort, sortie de scene -- il resterait a zero et l'effet
ne marcherait PLUS JAMAIS, sans que rien ne le signale. Il est rendu a la fin du fondu comme a l'arret du
controller.

## 0.0.491 — Les eclairs ne partaient pas : le filtre etait plus strict que la realite

La recherche du conteneur n'acceptait qu'un `Model` ou un `Folder`. `KnockEffect1` est une PART. Elle ne
trouvait donc rien -- et ne disait rien.

Elle cherche desormais par NOM, sans condition de classe.

Regle : quand on cherche un objet POSE PAR QUELQU'UN dans Studio, on cherche par son nom. Sa classe est un
detail de rangement, pas une garantie -- exactement comme le chemin fixe de la porte, qui a casse le jour ou
elle a demenage.

### Et le silence est corrige aussi

Aucun eclair ne partait, aucun message ne le disait. Deux causes se ressemblent a l'ecran -- conteneur ABSENT ou
conteneur VIDE -- et se corrigent a deux endroits opposes. Elles sont maintenant nommees separement.

C'etait la vraie faute : le filtre trop strict n'aurait coute qu'une minute s'il avait parle.

## 0.0.490 — Un eclair claque a chaque coup frappe

Un Beam AU HASARD parmi ceux de `KnockEffect1` s'allume une fraction de seconde a chaque `TocEvent`.

Au hasard, et c'est le point : trois coups identiques se lisent comme une BOUCLE, trois coups qui claquent
ailleurs se lisent comme trois VRAIS chocs. La meme raison qui fait varier un son de pas.

### Tres court

0.07 s. Au-dela de ~0.15 on a le temps de regarder ce que c'est, et l'illusion tombe. C'est un flash, pas un
eclairage.

### Ils sont ETEINTS au premier passage

Leur etat de repos est INVISIBLE. S'ils arrivent allumes depuis Studio, ils resteraient allumes toute la scene
-- et on chercherait pourquoi un effet de coup est permanent.

### La liste VIDE est gardee en cache

Si le conteneur est introuvable, on garde quand meme le resultat : sans ca on re-balayerait tout le Workspace a
chaque coup pour ne rien trouver.

### Un eclair coupe en plein flash reste allume

Il n'a personne pour l'eteindre une fois la scene finie. L'arret du controller les eteint tous.

### `findModelOrFolder`

Un conteneur d'effets n'est PAS un Model. Exiger l'un ou l'autre obligerait a ranger les objets d'une certaine
facon dans Studio -- et c'est le code qui doit s'adapter au rangement, pas l'inverse.

## 0.0.489 — Le grand-pere respire de nouveau

`AmbientAnimConfigs` attendait un Model nomme `GrandFather`. Il s'appelle `OldmanOriginal` depuis qu'il a ete
remodele. La cle passe donc a `OldmanOriginal`.

La cle EST le nom du Model dans le Workspace, pas une etiquette libre. Renommer un objet dans Studio sans la
changer ici coupe son animation -- et c'est le genre de panne qui ne casse rien : le PNJ est la, immobile,
comme un decor qu'on aurait voulu fixe.

C'est justement pour ca que le service NOMME ce qu'il n'a pas trouve. Le message tournait a chaque demarrage
depuis plusieurs jours :

    "GrandFather" est dans la config mais RIEN n'a ete anime sous ce nom.

Un service qui balaye le monde doit dire ce qu'il n'a PAS trouve : un compteur global ("15 modeles animes") ne
revele jamais l'absence du seizieme.

### Le commentaire de TutorialConfigs suivait la mauvaise version

Il signalait l'ecart comme une limite connue. Les deux configs designent le MEME objet -- il dit maintenant
qu'elles doivent rester d'accord.

## 0.0.488 — La camera avance vers le grand-pere quand la porte s'ouvre

Le resserrement du champ de vision ne DEPLACE rien : l'image se serre, mais le cadre reste ou il est. Le moment
le plus fort de la scene se jouait donc sans que la camera bouge.

Elle avance maintenant vers lui, lentement, pendant que la porte s'ouvre.

### `SceneCamera.moveTo`

La camera de scene savait entrer et sortir, pas se DEPLACER en cours de route. Elle repart de la CIBLE en cours,
jamais de la CFrame affichee : celle-ci porte le flottement de la respiration, et le glissement se figerait donc
sur un ecart aleatoire, different a chaque partie.

Sans effet si aucune scene ne tourne : deplacer une camera qu'on ne possede pas la volerait au joueur.

### Elle AVANCE sur son axe, elle ne saute pas

Pas de nouveau point de vue : elle se rapproche depuis la ou elle est deja. Le raccord ne se voit donc pas,
contrairement a une coupe vers un autre angle.

Lent (1.4 s) : un mouvement lent se lit comme de l'attention, un mouvement rapide comme une alerte -- et ici on
DECOUVRE quelqu'un, on ne le fuit pas.

### Deux garde-fous

- Elle vise le GRAND-PERE s'il est trouvable, sinon le centre de la porte. C'est par la qu'il arrive de toute
  facon, donc le cadrage reste juste meme si le Model change de nom.
- Elle ne franchit JAMAIS `REVEAL_MIN_DIST`. Sans cette borne, un grand-pere pose plus pres que prevu ferait
  traverser la camera au travers de lui -- et on ne verrait plus que l'interieur de sa tete.

## 0.0.487 — Le reflet devient une large nappe

`SHINE_WIDTH` 0.07 -> 0.7, soit dix fois plus epais.

### Le trajet s'elargit AVEC la bande

Il allait de -1 a 1, ce qui suffisait a une bande fine. Une bande epaisse, elle, serait deja au milieu de
l'ecran a la premiere image : elle doit partir de plus loin pour entrer par un bord et sortir par l'autre.

Le trajet se DEDUIT donc de la largeur (`1 + SHINE_WIDTH`) au lieu d'etre ecrit : deux valeurs qui doivent
rester d'accord ne s'ecrivent pas deux fois.

### Ce que ca change au rendu

Au-dela de 0.5, la bande est plus large que l'espace du degrade : ses bords sont ROGNES, et le profil devient
une grande rampe douce plutot qu'une barre nette. Ce n'est plus un eclat qui passe, c'est une nappe qui balaie.

C'est un choix, pas un defaut -- mais il vaut mieux le savoir avant de chercher pourquoi la barre n'a plus de
bord.

## 0.0.486 — Le reflet sur la maison devient discret

`SHINE_STRENGTH` 0.72 -> 0.9 (1 = invisible). Reglage seul.

Un reflet doit se remarquer une demi-seconde sans qu'on sache dire ce qui a bouge. Des qu'on peut le montrer du
doigt, il est trop fort -- meme regle que le vignettage.

Il y a un second interet a le baisser : le reflet ne connait pas le fondu de la maison, donc il passe aussi la
ou le dessin est deja efface. Plus il est faible, moins cette zone se rallume.

## 0.0.485 — L'apparition de la feuille devient franchement douce

`Quad Out` partait encore a PLEINE VITESSE : seule la fin etait adoucie. Un depart sec se ressent comme un tic
meme quand l'arrivee est propre -- c'est le premier instant du mouvement qu'on remarque, pas le dernier.

`Sine InOut` est la courbe la plus douce des deux cotes : elle demarre sans a-coup et s'arrete sans a-coup.
Duree 0.22 -> 0.3.

## 0.0.484 — L'apparition de la feuille se calme

Elle grossissait avec un `Back`, qui DEPASSE la taille de repos avant d'y revenir. Ce sursaut se lit comme un
tic -- et surtout il vole la vedette au saut qui suit, alors que c'est le saut qui porte le mouvement.

`Quad Out` : elle grossit, un point c'est tout. La matiere molle s'exprime a l'ATTERRISSAGE, la ou elle a un
sens -- une feuille qui apparait ne rebondit sur rien.

Duree 0.18 -> 0.22, pour la meme raison : moins pressee, moins de tic.

## 0.0.483 — Les six feuilles se rapprochent

Un seul reglage faisait la TAILLE et l'ESPACEMENT : `LEAF_FILL`, la part de sa case occupee par une feuille. Le
monter les rapprochait mais les grossissait, le baisser faisait l'inverse. Aucune valeur ne pouvait donner des
feuilles serrees ET de la meme taille.

Les deux sont separes.

### La LARGEUR de la jauge commande l'ecart

Les feuilles sont en `Fit` : leur taille est bornee par la HAUTEUR de leur case, pas par sa largeur. Elargir la
jauge ne les grossit donc pas, ca les ECARTE -- et la retrecir les rapproche sans les rapetisser, jusqu'au point
ou la case devient plus etroite que haute.

Jauge 0.26 -> 0.2, et `LEAF_FILL` monte a 0.95 : la case ne sert presque plus de marge.

### Effet de bord voulu

La largeur de la jauge borne aussi le texte des conseils, qui s'arrete juste avant. La retrecir donne donc plus
de place au texte, sans rien avoir a regler d'autre -- c'est tout l'interet d'avoir calcule cette largeur au
lieu de l'ecrire.

## 0.0.482 — La feuille grossit d'abord, PUIS elle saute

C'etait un seul geste : elle tombait de nulle part et rebondissait. Ce sont DEUX mouvements.

    1. elle GROSSIT a sa place, depuis rien
    2. un court instant plus tard, elle SAUTE -- montee, retombee, ecrasement, redressement

Le temps mort entre les deux est ce qui les SEPARE. Sans lui ils se chevauchent et on n'en lit plus qu'un seul --
c'est exactement ce que faisait la version precedente, ou l'apparition etait noyee dans la chute.

### Le saut a un poids

La montee RALENTIT (elle perd son elan), la retombee ACCELERE. L'inverse n'aurait aucun poids. La feuille
s'ETIRE en l'air -- plus fine, plus haute -- et s'ECRASE en touchant.

### Le temps mort du cycle est CALCULE

Il doit laisser la DERNIERE feuille finir son geste, sinon elle est coupee en plein saut. Il se deduit donc de
la somme des durees, moins l'ecart entre deux crans -- et non d'un nombre pose a la main, qui deviendrait faux
des qu'on touche a l'une des six durees.

C'est le meme principe que la largeur du texte des conseils, calculee depuis la jauge : deux valeurs qui doivent
rester d'accord ne s'ecrivent pas deux fois.

## 0.0.481 — Un vrai rebond de balle molle, et les feuilles noires disparaissent

### Le rebond etait faux

Il ne faisait que de la POSITION : la feuille descendait et remontait, sans jamais changer de forme. Ca se lit
comme un objet RIGIDE qui saute, pas comme une balle molle.

Une balle molle fait TROIS choses, et il faut les trois : elle S'ETIRE en tombant, elle S'ECRASE en touchant,
puis elle SE REDRESSE en depassant un peu.

### La deformation se fait sur la TAILLE, pas sur un UIScale

Une echelle est UNIFORME : elle ne sait que grossir, elle ne peut ni etirer ni ecraser. C'est pour ca que la
version precedente ne pouvait pas marcher, quels que soient les reglages.

### L'ancrage EN BAS AU MILIEU est ce qui rend l'ecrasement possible

Avec une ancre au centre, une feuille qu'on ecrase s'enfonce dans le sol autant qu'elle s'etale. Ancree par le
BAS, elle s'ecrase SUR le sol : le point d'ancrage EST le point de contact.

### Les trois temps s'enchainent sur la FIN du precedent

Jamais sur des delais poses cote a cote : des delais deriveraient des que le jeu rame, et l'ecrasement partirait
avant que la feuille ait touche.

### Les six feuilles noires sont retirees

Elles servaient a montrer combien il en restait -- ce qui avait un sens tant que c'etait une jauge de
progression. Depuis que le cycle tourne en boucle, elles ne disent plus rien : six formes noires posees en
permanence qui n'informent de rien.

Un decor qui a perdu sa fonction ne devient pas neutre, il devient du bruit.

Une feuille eteinte est desormais INVISIBLE, pas de taille nulle : une taille nulle ne peut pas etre etiree, il
faudrait la rendre a sa taille avant de commencer et ce saut se verrait.

## 0.0.480 — Les six feuilles tournent en boucle, et rebondissent

Elles s'arretaient : c'etait une JAUGE DE PROGRESSION, six crans repartis sur une duree devinee. Une fois les
six allumes, l'ecran se figeait alors que le chargement, lui, continuait.

C'est devenu un INDICATEUR QUI TOURNE. Un mouvement qui ne s'arrete pas dit "ca travaille" sans mentir sur le
temps qu'il reste -- ce qu'une jauge calee sur une duree devinee finissait toujours par faire.

`FILL_DURATION` disparait avec : plus rien ne pretend savoir combien de temps ca prendra.

### Chaque feuille TOMBE et REBONDIT

Elle arrive de plus haut et rebondit en touchant sa place, comme une balle sur le sol. `Bounce` en sortie fait
exactement ce rebond amorti.

L'echelle, elle, monte tout droit et vite : deux rebonds a la fois se marcheraient dessus et on ne lirait plus
ni l'un ni l'autre.

### La chute est en FRACTION, pas en pixels

Une valeur en pixels serait un saut de puce sur un grand ecran et un plongeon sur un telephone.

### Elles s'eteignent toutes a la fois

Les eteindre une par une se lirait comme un second passage, en sens inverse, et on ne saurait plus ou commence
le cycle. Un temps mort les separe : sans lui, le sixieme et le premier s'enchainent et le tour n'a plus de
debut visible.

## 0.0.479 — Un reflet balaie la maison du client

Une bande claire traverse le dessin en diagonale, de temps en temps.

### Le dessin sert de MASQUE a son propre reflet

C'est une COPIE BLANCHE de la maison, posee par-dessus, dont seule une bande etroite est visible -- et cette
bande glisse. Le reflet epouse donc la forme du dessin, sans un pixel qui deborde.

Une frame rectangulaire posee de travers ferait le meme trajet, mais elle deborderait sur les bords transparents
du dessin, et il faudrait un CanvasGroup rien que pour la decouper. Deux objets et un masque, la ou une copie de
l'image suffit.

### C'est l'OFFSET qui promene la bande

Elle est posee au centre une fois pour toutes. Reconstruire la NumberSequence a chaque image couterait bien plus
cher pour le meme trajet.

Elle demarre HORS CADRE : sans ca, le premier reflet serait deja au milieu de l'ecran a la premiere image.

### Il s'arrete entre deux passages

Un reflet qui ne s'arrete jamais devient un clignotant : l'oeil finit par le suivre au lieu de lire le reste de
l'ecran. Un passage court (0.9 s), puis un temps mort (2.6 s).

### Le compromis assume

Le reflet ne connait pas le fondu de la maison : il passe donc aussi la ou le dessin est deja efface. C'est
pour ca qu'il est FAIBLE (`SHINE_STRENGTH` a 0.72) -- assez pour se remarquer une demi-seconde, pas assez pour
rallumer une zone qu'on avait volontairement eteinte.

## 0.0.478 — Les crans de la jauge poussent depuis rien

Un cran s'allumait par un changement de COULEUR, avec un leger sursaut. Ca passait inapercu dans un coin de
l'ecran. Il POUSSE maintenant : la feuille verte part d'une taille NULLE, depasse sa cible, puis y revient.

C'est le depassement qui fait le rebond. Une echelle qui monte tout droit se lit comme un fondu, pas comme une
arrivee. Et quelque chose qui pousse se voit du coin de l'oeil, la ou une couleur qui change ne se voit pas.

### Deux couches par cran

La sombre reste en place et tient la forme ; la verte pousse par-dessus. Une seule feuille qui grandirait depuis
rien laisserait un TROU dans la jauge tant qu'elle n'est pas atteinte -- et on ne verrait plus combien il en
reste, ce qui est exactement ce que la jauge sert a dire.

L'echelle vit donc sur la feuille VERTE seule.

### Plus court

0.42 s. Au-dela de ~0.5 le rebond traine et la jauge a l'air molle.

## 0.0.477 — Le bas du mot TIPS fonce un peu

Dernier point du degrade de l'etiquette : 214 -> `#b4b4b4` (180). L'ecart avec le haut se creuse, donc la lumiere
posee sur le mot se voit davantage.

### Une difference de structure a savoir

La sequence du code a QUATRE points, avec un ressaut net vers 0.47 : blanc, blanc, 229, puis la fin. Le graphe
de reference n'en a que TROIS. "Point 3" a donc ete lu comme le point de FIN, le seul que les deux versions ont
en commun.

Si c'est la courbe a trois points qu'il faut, c'est la sequence entiere qu'on remplace -- pas une couleur.

## 0.0.476 — Le bandeau garde la meme densite sous le texte

Sa transparence montait tout droit de 0 a 1 : il palissait donc regulierement sur toute sa largeur, et le texte
pose dessus devenait moins lisible a droite qu'a gauche.

La courbe est maintenant PLATE sur presque toute sa longueur (0.319) puis monte SEC dans son dernier dixieme.
Le bandeau garde la meme densite partout ou il y a quelque chose a lire, et ne s'efface qu'a son extremite.

`BANNER_FADE_AT` disparait au profit de la sequence complete : un seul nombre ne pouvait pas decrire un palier.

### Valeurs lues sur un graphe

Le point (0.897 / 0.319) est le seul dont la valeur exacte etait affichee. Les trois autres sont lus au pixel :
(0, 0), (0.25, 0.319) et (1, 1). A corriger si l'ecran dit autre chose.

## 0.0.475 — Les deux degrades du rideau prennent leurs vraies valeurs

Reglages, plus un correctif qui n'en est pas un.

### La tuile passe en BLANC PUR

Elle etait en gris 38. Un UIGradient MULTIPLIE la couleur de l'objet : sur un gris, les valeurs du degrade sont
rabotees en silence, et on regle une courbe dont on ne voit jamais le vrai rendu.

C'est la meme regle que le bandeau et que l'etiquette TIPS, tous deux deja en blanc pur pour cette raison. La
tuile etait la derniere a ne pas la suivre.

### Sa courbe s'inverse, et tourne de 50 degres

Elle partait pleine et s'effacait ; elle part maintenant INVISIBLE et se termine pleine. Le motif n'existe donc
que d'un cote de l'ecran. Le long palier du debut evite qu'il commence a poindre des le premier pixel, ce qui
donnerait l'air d'une erreur.

### Le fondu de la maison prend ses cinq points

Il descend plus tot et plus fort : le dessin ne concurrence plus le bandeau ni le texte.

### Le point de depart, corrige au passage

La courbe de la tuile etait donnee avec son premier point a l'instant 1 -- et son dernier aussi. Une
NumberSequence DOIT commencer a 0, finir a 1, en temps strictement croissant : Roblox refuse la sequence entiere
sinon, et le degrade disparait sans le moindre message. Lu comme un 0.

## 0.0.474 — La maison du client apparait derriere le rideau

Le dessin de la maison ou l'on va, en plein cadre. C'est ce qui fait qu'un chargement ressemble a un DEPART chez
quelqu'un plutot qu'a une barre qui avance.

### Entre le degrade et la tuile

La tuile passe DESSUS : le motif s'inscrit sur le dessin au lieu de passer dessous, donc la maison appartient au
decor au lieu de flotter comme une vignette collee.

Les plans ont ete renumerotes en consequence -- maison, tuile, bandeau, puis tout ce qui se LIT au-dessus.

### `Crop`, pas `Fit`

Elle remplit l'ecran et deborde. Un `Fit` laisserait le degrade nu sur les cotes en 21/9, et le cadrage
changerait avec le format.

### Le degrade ne touche QUE la transparence

La couleur du dessin reste la sienne. Une teinte ici raboterait ses couleurs en silence, et on reglerait un
dessin qu'on ne voit jamais vraiment -- meme piege que le bandeau, qui doit etre en blanc pur pour que son
degrade rende ce qu'il annonce.

Le fondu est en DIAGONALE : la maison reste lisible d'un cote et s'efface de l'autre, sinon elle concurrence le
bandeau et le texte poses dessus.

### Le sens ne se deduit pas

L'orientation d'un UIGradient est une de ces choses que seul l'ecran tranche. Si le fondu part du mauvais coin,
`HOUSE_FADE_ROTATION` + 180 est la premiere chose a essayer.

## 0.0.473 — Les feuilles de la jauge s'allument en silence

Chaque cran jouait `PopSound_1`. Six sons pendant un chargement, ce n'est plus un retour, c'est un compte a
rebours qu'on subit.

Le SURSAUT reste, et il fait le travail mieux qu'un son : il se remarque si on regarde l'ecran, et il se tait si
on regarde ailleurs. Un son ne sait pas faire cette difference.

Reglages et recherche du son retires avec, pas seulement l'appel : une constante qui ne sert plus finit par
faire croire qu'un effet existe encore.

## 0.0.472 — Un conseil trop long se replie sur deux lignes, et retrecit

Il etait seulement RETRECI. Deux lignes se lisent ; un texte rapetisse, non -- et un conseil qu'on doit lire
deux fois n'aide personne pendant un chargement.

### Le repli se fait AUX ESPACES

On avance mot par mot, et on ne change de ligne que si le mot ENTIER ne rentre pas. Couper "hedge" en "hed /
ge" ne se lit plus. Un mot plus large que la ligne entiere reste quand meme place -- sinon la boucle tournerait
sans jamais le poser -- et c'est le retrecissement qui traite ce cas.

Les espaces restent sur la ligne du mot qu'ils suivent : les reporter au debut de la suivante la decalerait d'un
cran vers la droite.

### Le bloc reste centre sur le bandeau

Deux lignes montent d'une demi-hauteur au lieu de descendre sous lui.

### Deux lignes retrecissent AUSSI

Elles prennent une hauteur que le bandeau n'a pas : a taille pleine elles deborderaient dessus.

### Le piege evite : l'oscillation

Retrecir un conseil peut le faire rentrer sur UNE ligne, donc il n'aurait plus besoin d'etre retreci, donc il
regrossirait, donc il repasserait sur deux lignes -- indefiniment, a chaque image.

Tout se decide donc sur la largeur qu'il occuperait A LA TAILLE DE BASE, jamais sur la taille courante. Une
grandeur qui ne depend pas de la reduction en cours rend la decision stable des la premiere image.

## 0.0.471 — Le conseil ne passe plus sous les feuilles

Le texte des conseils courait jusque sous la jauge : deux choses lisibles au meme endroit, donc aucune des deux.

### Le cadre du conseil CALCULE sa largeur

Il s'arrete juste avant la jauge, a partir de la position et de la taille de celle-ci. Deux valeurs ecrites a la
main auraient fini par se chevaucher des que l'une des deux bouge -- et le texte serait repasse dessous sans
prevenir. Deplacer la jauge deplace maintenant la fin du texte, sans y penser.

### Mais le cadre ne suffisait pas

Les lettres sont posees UNE PAR UNE, a la main : le cadre ne les contraint pas. Un conseil long depassait
tranquillement, quelle que soit la largeur qu'on lui donne.

La taille du texte vient donc toujours de la HAUTEUR de la ligne, mais elle est CORRIGEE par la largeur : on
mesure ce que le conseil occupe vraiment et on retrecit ce qu'il faut. Relu a chaque image, donc ca converge en
une ou deux images et ca se recorrige tout seul si la fenetre change de taille.

### Un nom qui en masquait un autre

La variable de largeur s'appelait d'abord `total` -- nom deja pris, plus bas, par la DUREE de l'animation. Le
`local` interne masquait celui du dessus SANS aucun avertissement de Luau : le code lisait une duree en croyant
lire des pixels. Seul le linter l'a vu, en signalant l'autre comme inutilisee.

## 0.0.470 — Le rideau de changement de map change de tete

### La feuille centrale devient une jauge de six feuilles, en bas a droite

Une jauge CONTINUE dit "ca avance" ; une jauge A CRANS dit "il en reste trois". Le joueur COMPTE au lieu
d'estimer, et chaque cran qui s'allume est un evenement -- avec son bruit et son sursaut -- au lieu d'un
mouvement qu'on finit par ne plus voir.

Deux details qui evitent des bugs discrets :

- Les feuilles sont placees A LA MAIN, pas par un `UIListLayout` : un layout REPOSE ses enfants a chaque image,
  donc il ecraserait le sursaut qu'on leur donne.
- L'allumage tourne dans une BOUCLE, pas en un pas. A bas FPS on peut franchir deux crans entre deux images, et
  une feuille sautee resterait eteinte jusqu'a la fin sans que rien ne le signale.

### Un fond en degrade

Rotation 88, du bleu ardoise vers un eclat vert puis du noir. Pose sur un CADRE dedie, PAS sur le CanvasGroup :
sur le groupe il teinterait tout son contenu -- le texte blanc virerait au bleu, les feuilles perdraient leur
vert.

### La destination s'affiche en haut a droite

"TUTORIAL" aujourd'hui, le nom du client demain. Le joueur sait ce qu'il attend, pas seulement QU'il attend.

Ancree a DROITE : le texte grandit vers la gauche, donc un nom long garde son bord aligne sur le reste de
l'ecran au lieu de deborder des deux cotes.

Les identifiants de lieu sont EN DUR ici, comme `MAIN_PLACE_ID` : ce fichier tourne dans `ReplicatedFirst` et ne
peut pas require `PlacesConfig`. A tenir d'accord a la main -- c'est le prix de tourner aussi tot.

### Le bandeau passe en noir uni, et la tuile change

`BANNER_COLOR` perd son vert. Nouvelle image de tuile, et une cellule deux fois plus fine.

### A FAIRE ENCORE

L'image de la maison du client, avec son degrade de transparence : il manque son asset ID.

## 0.0.469 — Le remplissage de la feuille a un bord NET

`FILL_SOFT` 0.14 -> 0.

Le bord adouci brouillait la limite : on ne savait plus ou en etait le remplissage, donc la jauge ne mesurait
plus rien. Net, c'est un niveau qui monte -- et un niveau, ca se lit d'un coup d'oeil.

Le commentaire d'origine defendait l'inverse ("une coupure franche se lit comme un masque"). Il avait tort, et
c'est l'ecran qui tranche. Il est corrige plutot que laisse a contredire le code.

L'ecart minimal entre les deux points du bord reste force : les temps d'une NumberSequence doivent croitre
STRICTEMENT, sinon Roblox refuse la sequence entiere des que le remplissage arrive contre un bord -- et il se
figerait la, sans erreur, juste avant d'etre fini.

## 0.0.468 — La feuille du rideau retrecit

`LEAF_IMAGE_SIZE` (0.675 / 0.673) sur les images, pas sur leur contenant.

Le contenant garde sa taille et sa forme carree : c'est lui qui porte la position, l'inclinaison et l'echelle
d'apparition. Retrecir les images ne deplace donc rien -- la feuille maigrit SUR PLACE au lieu de glisser vers un
coin, et le rebond reste centre sur elle.

Les images sont ancrees en leur centre pour la meme raison : avec une ancre en coin, changer leur taille les
aurait decalees.

## 0.0.467 — La feuille du fond passe en noir pur

`LEAF_BACK_TINT` 18/24/15 -> 0/0/0. Reglage seul.

J'avais choisi un noir legerement verdi en pensant l'accorder a la feuille du dessus. C'est le contraire de ce
qu'on veut d'un contenant : plus il est neutre, plus le remplissage ressort. Le noir pur donne le contraste
maximal avec le vert, donc la jauge se lit de plus loin.

## 0.0.466 — L'apparition de la feuille se voit, et on l'entend

Deux defauts, deux causes differentes.

### Le son ne partait jamais

Ce fichier tourne depuis `ReplicatedFirst`, au tout premier instant. `findByPath` utilise `FindFirstChild`,
qui est INSTANTANE : a ce moment-la `SoundService` n'est pas encore replique, donc la recherche rendait toujours
nil et le son ne partait pas. Silencieusement, evidemment.

Le son de feuilles du meme fichier avait deja sa boucle de reessai, pour cette raison exacte. Celui-ci l'a
maintenant aussi.

### L'apparition passait inapercue

Deux choses : elle durait 0.55 s, et surtout elle partait dans la MEME IMAGE que le rideau. Elle se jouait donc
pendant que l'ecran etait encore en train de se poser -- il n'y avait rien a rater, il n'y avait rien a voir.

`LEAF_POP_DELAY` (0.4 s) la laisse arriver une fois le rideau en place, et `LEAF_POP_TIME` passe a 0.9 s.

### L'image ATTEND le son

Elles partent ensemble, et c'est l'image qui patiente. Un son cale a cote de son image se ressent comme un
decalage meme quand on ne sait pas dire lequel des deux est en retard.

Si le son n'arrive jamais (3 s), la feuille apparait quand meme : un asset absent ne doit pas supprimer un
element de l'ecran.

## 0.0.465 — Le rideau de changement de map : deux feuilles, une arrivee qui claque

### Deux feuilles au lieu d'une

Celle du dessous est SOMBRE et complete : c'est le contenant. Elle dit tout de suite quelle forme va se remplir.

Avec une seule feuille, la partie pas encore remplie etait simplement TRANSPARENTE : on voyait le fond a
travers, la jauge n'avait pas de bord, et le joueur ne lisait plus "combien il reste" mais "quelque chose
apparait". Une jauge sans contenant n'est pas une jauge.

### Un seul contenant pour les deux

Il porte la position, l'inclinaison et l'echelle ; les deux images ne portent que leur couleur. Les animer
separement les desynchroniserait d'une image, et le contour se decollerait de son remplissage.

### L'oscillation disparait

La feuille se balancait et flottait en permanence. Ce mouvement attirait l'oeil en continu alors que la seule
chose a suivre est le REMPLISSAGE : deux mouvements se disputaient l'attention, et le plus visible n'etait pas
celui qui portait l'information.

### L'arrivee claque

Echelle de 0 a 1 avec un `Back` en sortie : elle depasse sa taille puis revient. C'est ce depassement qui donne
le rebond -- une echelle qui monte tout droit se lit comme un fondu, pas comme une arrivee.

`PopSound_1` part avec elle. Le son et l'image arrivent ENSEMBLE : un son cale a cote de son image se ressent
comme un decalage meme quand on ne sait pas dire lequel des deux est en retard.

### Rien a changer pour la sortie

Le rideau est un `CanvasGroup` : son fondu porte sur le groupe, donc les deux feuilles s'effacent ensemble sans
une ligne de plus.

## 0.0.464 — Le joueur s'efface, et l'image se resserre sur le grand-pere

### Le personnage passe en fantome pendant la scene

On regarde le grand-pere, pas son propre dos. A 0.7 le personnage reste LISIBLE -- on sait qu'on est la -- sans
manger le cadre.

`CharacterFade` existait deja et fait exactement ca. Il passe par `LocalTransparencyModifier`, jamais par
`Transparency` : ca ne se replique pas, donc en co-op les autres continuent de voir un personnage normal. Et ca
s'AJOUTE a la transparence du jeu au lieu de l'ecraser -- il n'y a aucune valeur d'origine a memoriser pour
pouvoir la rendre.

Rendu par tous les chemins de sortie : fin de scene, arret du controller, mort en pleine scene.

### Un second resserrement, sur lui

Quand la porte finit de s'ouvrir et qu'il apparait, l'image se resserre une seconde fois. Il S'AJOUTE au premier
-- une fois sur la porte qui bouge, une fois sur lui. Volontairement petit : c'est un accent, pas un gros plan.

### La cadence du zoom devient reglable par appelant

`CameraEffects.SetFovOffset(amount, speed?)`.

L'allure par defaut (1.1) est faite pour des resserrements de FOND : elle mettrait deux secondes, et l'accent
serait fini apres le moment qu'il souligne. Un resserrement qui doit claquer a l'ouverture d'une porte n'a rien a
voir avec elle.

On ne l'a PAS changee pour autant : deux moments differents, deux cadences, sinon regler l'un derangerait
l'autre. La cadence exceptionnelle est OUBLIEE au prochain appel qui n'en demande pas d'autre -- un effet
ponctuel n'impose pas son allure a la suite.

## 0.0.463 — La grande ouverture se fait trois fois plus lentement

Apres la pause, la porte finissait de s'ouvrir beaucoup trop vite : le mouvement etait termine avant qu'on ait
le temps de regarder. `DOOR_FULL_OPEN_SPEED = 1/3`.

### Seule la SECONDE moitie ralentit

Le debut garde sa vitesse. La porte qui s'entrebaille d'un coup est un mouvement SEC -- c'est la surprise, et la
ralentir l'enleverait. La fin, elle, est le moment ou l'on decouvre le grand-pere : elle a besoin de durer.

Deux moments differents, deux vitesses. Une seule valeur pour les deux aurait force a choisir lequel sacrifier.

### Le gel a la derniere image n'est pas touche

La detection de fin se fait sur `TimePosition`, pas sur le temps ecoule : elle marche a n'importe quelle vitesse
de lecture.

## 0.0.462 — La porte s'epingle a la DERNIERE IMAGE de son animation

Elle se refermait encore, et la cause etait en amont de tout ce qu'on avait corrige : on epinglait la piste sur
`EndOpenDoorEvent`, a 0.53 s d'une animation qui en dure 1.

On figeait donc une pose INTERMEDIAIRE, et la fin du mouvement ne jouait jamais. La porte restait a moitie --
puis n'importe quel accroc la ramenait a sa pose de repos.

Elle est desormais epinglee a `Length - 0.001`. La porte est grande ouverte AU BOUT de l'animation : c'est la
qu'il faut rester.

### `EndOpenDoorEvent` n'est plus lu

Il existe toujours dans l'animation, le code ne s'en sert simplement plus. La fin d'une animation se mesure sur
sa DUREE, qui suit toute retouche ; un marqueur, lui, reste ou on l'a pose.

### La fin se detecte de DEUX facons, et il faut les deux

La fenetre "assez proche de la fin" attrape le cas normal, mais un FPS bas peut la SAUTER : entre deux images la
piste passe par-dessus et reboucle. Le retour en arriere, lui, est un fait qu'on ne peut pas rater.

Les deux menent au meme endroit -- epingle a la derniere image -- donc rater la premiere ne coute qu'une image de
plus. La marge est de 0.05 s : une image a 30 FPS en fait 0.033.

### Ce qui reste de 0.0.461

Le maintien image par image : la piste joue, vitesse zero, temps epingle, et on la relance si quelque chose
l'arrete. C'etait juste, ca defendait simplement la mauvaise pose.

## 0.0.461 — La porte est TENUE ouverte, plus seulement gelee

Elle se refermait. Le defaut : on gelait la piste UNE FOIS, puis on lachait la surveillance. Apres ca, plus rien
ne defendait la pose.

Trois choses peuvent alors la reprendre -- une piste voisine qui se relache sur le meme Animator, un `Stop` venu
d'ailleurs, un rebouclage rate d'une image -- et rien ne dit laquelle. Une pose qu'on pose et qu'on abandonne
n'est pas une pose tenue.

### On re-affirme l'etat a chaque image

Tant que la scene dure : la piste joue, sa vitesse est zero, son temps est celui qu'on a epingle. Et si quelque
chose l'a ARRETEE, on la relance -- une piste arretee ne dessine plus rien, donc la porte revient a sa pose de
repos, c'est-a-dire fermee.

Deux ecritures par image sur un seul objet : ca ne se mesure pas.

### Jamais `Stop` pour figer

Un `Stop` fait rendre a la piste sa pose de repos : la porte CLAQUE en position fermee. C'est `AdjustSpeed(0)`
plus un temps epingle, jamais autre chose.

Et jamais epingle PILE a `Length` : la piste est bouclee, donc le tout dernier instant repart a zero. On epingle
juste avant.

### La pause ne peut plus rallumer une porte deja tenue

La reprise d'apres la mi-course tirait sans regarder. Une pause encore en attente pouvait donc faire repartir
une piste qu'on venait d'epingler -- et la porte se refermait avec un retard qui rendait la cause introuvable.

## 0.0.460 — Le coup de camera s'encaisse au lieu de claquer

Le recul partait D'UN COUP et redescendait doucement. Un depart instantane se lit comme un a-coup, pas comme un
choc encaisse -- c'est ce qui le rendait sec.

Deux valeurs maintenant : l'IMPULSION retombe d'un cote, et la camera la SUIT AVEC DU RETARD de l'autre. Ce
retard est tout l'effet. Il arrondit le depart sans rien enlever a la force du coup.

Deux reglages separes plutot qu'un, parce qu'ils servent deux moments opposes : `KICK_RISE` (11) adoucit le
DEPART, `KICK_DECAY` (5.5) regle le RETOUR. Une seule valeur pour les deux aurait force a choisir entre un
depart mou et un retour lent.

Les deux compteurs sont cales a zero des qu'ils sont negligeables : une exponentielle n'atteint jamais sa cible,
et les coups suivants accumuleraient ce reste.

## 0.0.459 — Les secousses des coups sont plus discretes

`KNOCK_KICK` 0.8 -> 0.3. Reglage seul.

A 0.8 le recul se VOYAIT ; a 0.3 il se sent. C'est le but d'un choc de camera : accompagner le coup, pas le
commenter. Et comme les trois coups s'additionnent, une valeur trop haute se cumulait en plus.

## 0.0.458 — La camera encaisse chaque coup frappe

A chaque `TocEvent`, la camera part en arriere d'un coup sec et revient toute seule. L'image encaisse le choc en
meme temps que la porte : les coups se SENTENT au lieu de s'entendre.

### Le depart est instantane, le retour progressif

L'inverse donnerait une poussee, pas un choc. Le retour est exponentiel -- franc au debut, de plus en plus doux.

Et il est CALE A ZERO des qu'il devient negligeable : une exponentielle n'atteint jamais sa cible, donc sans ce
clamp la camera garderait un recul minuscule pour toujours, et trois coups d'affilee l'accumuleraient. Piege
deja paye sur le fondu du personnage, ou un residu de transparence faisait passer les membres dans le rendu
transparent.

### Les coups s'additionnent, et c'est voulu

Trois coups rapproches reculent plus que trois coups espaces. C'est exactement ce que fait une vraie camera
qu'on bouscule.

### Le recul est en repere CAMERA

Sur son +Z, c'est-a-dire son arriere. Pas en repere monde : le coup doit reculer quel que soit l'endroit ou elle
regarde, sans qu'on ait a connaitre son orientation.

### Le cadrage recule aussi

`SCENE_CAM_BACK` 6 -> 8.5. A ne pas confondre avec `KNOCK_KICK` : celui-la est ponctuel, celui-ci ne bouge pas
de toute la scene.

## 0.0.457 — La porte reste ouverte pour de bon, et elle grince

### Elle se fige, definitivement

`AdjustSpeed(0)` et jamais `Stop` : un Stop ferait rendre a la piste sa pose de repos, donc la porte se
refermerait d'un coup.

### Et un filet, parce que la piste est BOUCLEE

Elle l'est expres -- une piste non bouclee se relache a sa derniere image, et la porte se refermerait la aussi.
Mais du coup, si `EndOpenDoorEvent` se tait, elle repart a zero : la porte s'ouvrirait et se refermerait EN
BOUCLE, pour toujours.

Le garde surveille le TEMPS QUI RECULE, pas une fenetre "assez proche de la fin". Une fenetre peut etre SAUTEE
par un FPS bas ; un retour en arriere est un fait qu'on ne peut pas rater. Meme recette que le geste de prise du
seau.

Le marqueur et le filet peuvent tirer tous les deux : le gel est idempotent, et il coupe sa propre surveillance.

### Le grincement

`OpenDoorSound`, au niveau de la porte. Il part AVEC le mouvement, pas au marqueur de mi-course : c'est
l'ouverture elle-meme qu'il accompagne, et un bruit qui arrive une fois la porte deja entrebaillee sonne en
retard.

### A voir a l'oreille

La porte bouge DEUX fois : elle s'entrebaille, puis elle finit de s'ouvrir apres la pause. Le grincement ne joue
que sur la premiere -- celle demandee. Si le second mouvement parait muet, c'est une ligne a ajouter.

## 0.0.456 — Le geste de poignee joue sur la PORTE, et le son va au bout

La sonde du commit precedent avait vu juste : `Scene1_oldman_TryOpenDoor` anime la PORTE, pas le grand-pere.

Logique, une fois dit : a cet instant la porte est encore fermee et le vieux est derriere -- on ne le verrait pas
de toute facon. Le nom de l'animation raconte l'histoire ("oldman"), il ne dit pas sur quoi elle joue.

`TRY_OPEN_MODEL = "Door"`. Une ligne, comme annonce.

### Trois animations se partagent l'Animator de la porte

Le tremblement des coups, le geste de poignee, puis l'ouverture. A priorite EGALE, Roblox ne choisit pas : il
MELANGE. Deux poses actives donnent leur moyenne, et la porte s'ouvrirait a moitie de travers.

Les deux precedentes sont donc effacees avant que l'ouverture commence. C'est la reponse a "il faut superposer
des animations ?" : non, il faut au contraire s'assurer qu'elles ne se superposent PAS.

### Le son de poignee va jusqu'au bout

Il etait coupe a la fin du geste, au motif qu'il ferait grincer une poignee que plus personne ne touche. A
l'oreille c'est l'inverse : un bruit coupe net s'entend comme un bug, alors qu'il deborde sur l'ouverture sans
deranger personne. `SoundUtils` detruit le clone tout seul quand il finit.

## 0.0.455 — Une animation qui tourne sans rien bouger le DIT

`Scene1_oldman_TryOpenDoor` ne se voyait pas, alors que son SON partait. Or le son est joue APRES le chargement
de la piste : elle etait donc bien chargee, et `Play()` bien appele.

Elle tourne. Elle n'ecrit simplement rien.

C'est le piege des PNJ, puis du seau porte, une troisieme fois : une animation retrouve ses cibles PAR LEUR NOM.
Si aucune ne correspond au rig sur lequel on la joue, elle joue a plein poids et n'ecrit RIEN -- sans la moindre
erreur. La piste tourne, le son part, l'ecran ne bouge pas, et on cherche le bug dans le declenchement, qui est
parfait.

### On mesure le resultat, sur les TROIS animations

Les animations ecrivent dans `Transform`, jamais dans `C0` : un `Transform` reste a l'identite = personne n'a
ecrit dedans. Une seconde apres chaque lancement, le jeu regarde si un joint a bouge, et le dit sinon :

    "Scene1_oldman_TryOpenDoor" tourne mais n'a RIEN bouge sur "OldmanOriginal" : aucune de ses pistes ne porte
    le nom d'une part de ce rig. Elle anime probablement un AUTRE model...

### La cible passe dans la config

`TRY_OPEN_MODEL`. Le NOM d'une animation ne dit pas sur quoi elle joue : "oldman_TryOpenDoor" peut tres bien
animer la POIGNEE de la porte plutot que le vieux -- et c'est l'hypothese la plus probable ici, puisque la porte
est encore fermee a ce moment et que le grand-pere serait de toute facon invisible derriere.

Si la sonde confirme, la correction est UNE ligne : `TRY_OPEN_MODEL = "Door"`.

## 0.0.454 — L'image se resserre quand la porte s'ouvre

A `OuvertureDoorEvent` -- l'instant precis ou la main du grand-pere pousse la porte -- le champ de vision perd
12 degres. L'image se resserre sur la porte pile quand elle bouge, donc l'oeil y va sans qu'on lui dise.

### On ne bouge PAS la camera pour zoomer

L'avancer risquerait de la faire traverser le perron ou la rambarde, et il faudrait alors regler un trajet par
decor. Le champ de vision, lui, ne rentre dans rien.

### Et on ne l'ecrit pas nous-memes

`CameraEffects` est declare SEUL ECRIVAIN de `FieldOfView`, et sa boucle tourne meme pendant la scene. Ecrire
dessus en parallele donnerait un champ de vision qui vibre entre deux valeurs -- et on chercherait la cause dans
le zoom, pas dans le deuxieme ecrivain.

`SetFovOffset` fait le travail, avec son propre lissage.

### Rendu par tous les chemins de sortie

Fin de scene, arret du controller, mort en pleine scene. Un zoom qu'on oublie de rendre, c'est un joueur qui
garde un champ de vision serre pour le reste de la partie, sans que rien ne rappelle pourquoi.

### Le reglage

`SCENE_ZOOM = 12`. Un resserrement qu'on sent sans le voir ; au-dela de ~20 ca commence a deformer les bords.

## 0.0.453 — Une etape de scene qui saute le DIT

Le geste de poignee pouvait etre saute EN SILENCE. La scene s'enchainait normalement, rien ne cassait -- et on
en concluait que le code ne jouait pas l'animation, alors qu'il ne trouvait pas de quoi la jouer.

`loadSceneTrack` parlait deja quand c'est l'Animation qui manque. Les DEUX autres causes -- Model du grand-pere
introuvable, pas d'Animator dessus -- ne disaient rien. Elles le disent maintenant, nommement.

C'est la meme regle que partout ailleurs dans ce projet : un systeme qui peut echouer en silence doit mesurer
son resultat et parler. Une etape absente est un etat NORMAL (l'asset n'existe pas encore) ; une etape absente
et muette est un piege.

## 0.0.452 — Le grand-pere se bat avec sa poignee, et le dialogue ne coupe plus les coups

### La narration d'intro ne se declenche plus toute seule

Un bloc marque TEMP dans le bootstrap jouait la narration ~3 s apres le spawn, "pour regler le visuel avec le
joueur". Son propre commentaire disait de le retirer quand le tuto la declencherait pour de vrai.

C'est le cas, et surtout elle tombait EN PLEIN pendant les coups a la porte : une bulle ouverte en bas de
l'ecran, pile ou les barres noires arrivent, qui parle par-dessus le geste. Bloc retire (49 lignes).

La boite est aussi effacee au demarrage de la scene, au cas ou autre chose l'aurait ouverte. Elle reviendra
quand la SCENE la demandera -- reste a dire ou.

### Une etape de plus entre les coups et l'ouverture

    ... coups a la porte
      -> Scene1_oldman_TryOpenDoor : il s'acharne sur la poignee
         + TryUnlockDoorSound, au niveau de la porte
      -> Scene1_oldman_OpenDoor : il ouvre
      -> ...

Chaque etape enchaine sur la FIN de son animation. Aucun delai pose a cote : un delai se decale a la premiere
retouche, une animation non.

### Le son de poignee s'arrete avec le geste

`TryUnlockDoorSound` dure 5.2 s. Le laisser courir ferait grincer une poignee que plus personne ne touche,
pendant que la porte s'ouvre. Il est coupe a la fin de l'animation, et au nettoyage du controller.

### Chaque etape peut manquer sans bloquer

Animation de coups absente -> on passe a la poignee. Poignee absente -> on passe a l'ouverture. Un asset qui
manque fait sauter SON etape, jamais la scene entiere.

## 0.0.451 — Le son du jeu baisse pendant la scene, et les animations portent leur vrai nom

### Les deux noms d'animation etaient faux

`Scene1_grandpa` et `Scene1_door` n'existent pas. Les vrais sont `Scene1_oldman_OpenDoor` (le grand-pere) et
`Scene1_opendoor` (la porte). La console le disait deja nommement -- c'est pour ca qu'elle le dit.

### Le jeu BAISSE, il ne se tait pas

Nouveau module `Modules/UI/Core/SoundDuck`. Pendant la scene, le reste du jeu tombe a un quart de son volume.

Pas a zero : un silence total s'entend comme une COUPURE, et le monde a l'air de s'eteindre. On veut que
l'oreille se tourne vers la scene, pas que le jeu disparaisse.

### Un SoundGroup, pas les volumes un par un

Baisser le GROUPE baisse tout d'un coup, sans jamais toucher au `Volume` de chaque son -- celui-la reste ce qui a
ete regle dans Studio. Un module qui reecrirait les volumes un par un devrait les memoriser pour les rendre, et
il finirait par en perdre un.

Et LES CLONES EN HERITENT, ce qui rend l'affaire simple : `SoundUtils` joue chaque son ponctuel en clonant celui
de SoundService, et un clone copie son SoundGroup. Les bruits declenches PENDANT la scene sont donc baisses
aussi, sans une ligne de plus.

On n'adopte que les sons SANS groupe : voler ceux qui en ont deja un ecraserait un reglage de Studio.

Ce que ca ne couvre pas : les Sound poses sur des parts du Workspace, qui vivent hors de SoundService. A traiter
le jour ou il y en aura un qui gene, pas avant.

### Le volume est rendu par TOUS les chemins de sortie

Fin normale, arret du controller, mort en pleine scene. Un son baisse qu'on oublie de rendre laisse le jeu a un
quart de volume pour toujours, et plus personne ne fait le lien avec une scene finie depuis longtemps.

### La camera descend encore

`SCENE_CAM_UP` 1.2 -> 0.7. Juste sous la hauteur d'yeux : l'oeil arrive sur la porte de face, plus d'en haut.

## 0.0.450 — La camera de scene descend a hauteur d'yeux

`SCENE_CAM_UP` 2.5 -> 1.2. Le repere est la RootPart du joueur, deja a hauteur de torse : a 2.5 la camera
plongeait sur lui de haut, ce qui ecrase le decor et rapetisse le personnage.

A 1.2 elle est a peu pres a hauteur d'yeux, donc a la hauteur de ce qu'elle doit montrer -- la porte, puis le
visage du grand-pere. Reglage seul, aucun code touche.

## 0.0.449 — Le joueur toque trois fois, et la porte tremble

La scene commence maintenant par le geste : le joueur toque. `Scene1_TocToc_Animation` porte trois marqueurs, et
chacun donne un coup -- son au niveau de la porte, et la porte qui tremble.

    toque (E)
      -> barres + camera
      -> animation du JOUEUR
         -> Toc1Event / Toc2Event / Toc3Event : son + tremblement de la porte
      -> fin des coups : le grand-pere prend la suite
      -> ... (0.0.448)

### C'est l'animation qui dit QUAND, pas un minuteur

Trois coups cadences par un `task.wait` finiraient toujours par se decaler de l'animation, et il faudrait les
re-synchroniser a chaque retouche. Les marqueurs, eux, suivent.

Et c'est une LISTE dans la config, pas trois constantes : ajouter un quatrieme coup dans l'editeur ne demandera
qu'une ligne, et le code n'a pas a savoir combien il y en a.

### Le tremblement se REMBOBINE, il ne se rejoue pas

Trois coups rapproches : un `Stop` coupe en fondu, donc le deuxieme partirait par-dessus la fin du premier et le
tremblement s'aplatirait. On remet `TimePosition` a zero quand la piste tourne encore.

Le son, lui, est CLONE a chaque coup (`SoundUtils`) : rejouer la meme instance couperait le son en cours, et
deux coups rapproches ne s'entendraient qu'une fois.

### Spatial, pas global

Le son sort de la PORTE. Un bruit de porte qui vient du centre de la tete se decolle de l'image -- surtout avec
une camera posee a six studs de la.

### Le piege evite de justesse

Le nettoyage des quatre pistes etait ecrit `for _, t in ipairs({ a, b, c, d })`. `ipairs` S'ARRETE AU PREMIER
NIL : une seule piste absente et la boucle ne tourne pas du tout, les trois autres restent en place. Exactement
le bug qui laissait l'animation de recul de la tondeuse tourner pour toujours. Chaque piste est coupee
separement.

### Note

Cette entree est ecrite APRES son commit (f24f913) : l'ancre du script d'insertion visait le titre du commit et
non celui de l'entree, et l'ecriture a echoue sans empecher le push. Le CHANGELOG doit partir dans le MEME commit
que la feature -- ici il a fallu un rattrapage.

### A FAIRE DANS STUDIO

Rien de neuf. `Scene1_TocToc_Animation`, `DoorShakeAnimation` et `KnockDoorSound` existent deja. Restent les deux
instances de 0.0.448 : `Scene1_grandpa` et `Scene1_door`.

## 0.0.448 — La porte s'ouvre a moitie, le grand-pere parle, puis elle s'ouvre en grand

L'enchainement complet de la scene est branche.

    toque -> barres + camera
      -> animation du grand-pere
         -> OuvertureDoorEvent : la porte demarre
            -> MidAnimationEventDoor : elle se FIGE entrebaillee
            -> (pause) le grand-pere parle
            -> elle repart
            -> EndOpenDoorEvent : grande ouverte, elle TIENT
      -> fin de l'animation du grand-pere : la scene rend la main

### C'est l'animation qui decide de la duree, plus une constante

`SCENE_HOLD` n'est plus le minuteur de la scene : c'est un FILET, qui ne sert que si l'animation est introuvable
ou ne demarre pas. Une duree en dur et une animation finissent toujours par se contredire, et c'est la duree qui
a tort -- elle ne suit pas quand on retouche l'animation.

Sans ce filet, une animation absente laisserait le joueur coince en camera scriptee derriere des barres noires,
sans aucun moyen d'en sortir. Un asset manquant ne doit jamais devenir une partie bloquee.

### La porte se fige par la VITESSE, jamais par un Stop

Arreter une piste lui fait rendre sa pose de repos : la porte se refermerait d'un coup au milieu de la scene.
`AdjustSpeed(0)` la tient exactement ou elle est.

Elle reste BOUCLEE pour la meme raison -- une piste non bouclee se relache a sa derniere image. Le gel a
`EndOpenDoorEvent` l'empeche de reboucler, et la porte reste ouverte.

### Deux animations, deux noms

`Scene1_grandpa` et `Scene1_door`. Les deux ont deja porte le meme nom (`Scene1_opendoor`), et l'animation du
grand-pere a disparu de la reference quand celle de la porte a pris sa place : un nom qui designe deux choses
finit toujours par en perdre une.

### Le nettoyage emporte les pistes

La scene SURVIT au controller : la camera et les barres vivent dans la PlayerGui, et les pistes tournent sur des
Animator du Workspace. `stop()` coupe les quatre.

### A FAIRE DANS STUDIO

Creer DEUX instances Animation dans `ReplicatedStorage/Animations/Scenes/Scenes1` :

- **`Scene1_grandpa`** -> l'animation du grand-pere. Son ancien AnimationId etait `91299186233914`.
- **`Scene1_door`** -> l'animation de la porte, `110159708902875`.

Tant que ces deux noms n'existent pas, la console le DIT et la scene se joue a vide, sans bloquer le joueur.

## 0.0.447 — La scene part quand on toque : barres, camera, retour

Toquer a la porte declenche maintenant une vraie scene. Les barres glissent, la camera se pose devant la porte
et RESPIRE, puis tout revient.

### La camera de scene devient une primitive

`Client/Utils/SceneCamera`. Cinq controllers de ce projet ont chacun leur camera scriptee et leur propre retour
vers la camera de jeu ; celui-ci existe pour que la SIXIEME soit la derniere ecrite.

Elle porte les deux pieges deja payes ailleurs :

- **Le retour re-ancre sur la position VIVE du joueur** a chaque image. Un tween vers une CFrame fixe planterait
  la camera s'il repart pendant la transition.
- **L'etat de repos de la camera de jeu est MESURE a l'entree** -- distance, hauteur du focus, inclinaison. En
  repassant en Custom, Custom garde le yaw mais REMET son pitch de repos : finir sur une valeur devinee laisse un
  saut sub-perceptible et pourtant bien visible.

Le retour interpole la position et le point vise SEPAREMENT, jamais la CFrame entiere : lerper une CFrame fait
passer la camera par des orientations qui n'existent sur aucun des deux plans, et elle plonge en chemin.

### La respiration

Trois sinusoides sans rapport entre elles. Une seule se lit comme un balancier de metronome ; trois qui ne
retombent jamais ensemble donnent un mouvement qui ne se repete jamais a l'oeil. Elle s'arrete en sortie : un
tremblement a l'instant precis ou la camera de jeu reprend, c'est pile la ou un saut se remarque.

### Le cadrage se calcule depuis le JOUEUR

Il fait deja face a la porte quand il toque : ce repere est donc juste par construction. Se placer "devant la
porte" supposerait de savoir quel axe du Model est son devant, et rien ne le garantit -- ca vient du rig.

Une part nommee `SceneCam1` posee dans Studio prend le dessus si elle existe. C'est un moyen de reprendre la
main sur le cadrage, pas une obligation.

### Le filet qui evite un joueur coince

Mourir en pleine scene ressusciterait le joueur avec une camera scriptee et des barres noires, sans aucun moyen
d'en sortir : la scene attendrait une fin qui ne viendrait jamais. `CharacterRemoving` coupe les deux.

### PROVISOIRE, et il faut le savoir

La scene tient `SCENE_HOLD` (3 s) puis rend la main. Des que l'animation du grand-pere existe, c'est ELLE qui
doit decider de la fin : une duree en dur et une animation finissent toujours par se contredire, et c'est la
duree qui a tort.

Le compte part QUAND LA CAMERA EST ARRIVEE, pas a l'appui -- sinon le temps de trajet mangerait la scene, et il
changerait avec `SCENE_CAM_IN` sans qu'on y pense.

### A FAIRE DANS STUDIO

Rien. Une part `SceneCam1` est possible si le cadrage automatique ne convient pas.

## 0.0.446 — Les barres noires de cinema

Premiere brique des scenes scriptees. Deux bandes qui glissent depuis le haut et le bas de l'ecran.

Elles ne decorent pas : elles DISENT au joueur que la main lui est retiree. Tant qu'elles sont la, il regarde ;
quand elles partent, il rejoue. C'est la convention la plus lisible qui existe, et elle ne demande aucune
traduction.

### Une primitive, pas un morceau de scene

`Modules/UI/Core/Letterbox` ne connait ni le grand-pere, ni la porte, ni aucune scene. On l'allume, on l'eteint.
Toute scene future passera par la, sinon la meme paire de Frames serait recopiee a chaque fois.

### Les details qui evitent des bugs discrets

- **Aucun inset** : les bandes touchent les bords ABSOLUS de l'ecran, barre Roblox comprise. Sans ca, une bande
  de jeu resterait visible au-dessus de la barre du haut.
- **`DisplayOrder` tres haut** : une barre de cinema qui passe SOUS une interface de jeu ne veut plus rien dire,
  puisque c'est justement l'interface qu'elle remplace le temps de la scene.
- **Elles n'avalent aucun clic** : deux bandes actives rendraient le haut et le bas de l'ecran morts, et on
  chercherait le probleme dans les boutons.
- **Hauteur en FRACTION d'ecran**, pas en pixels : une valeur en pixels mangerait la moitie d'un telephone et ne
  se verrait pas sur un grand ecran.
- **Ancrees sur leur bord** : on n'anime QUE la hauteur. Animer aussi la position se decalerait a coup sur.
- **Les tweens en cours sont coupes** avant d'en lancer d'autres : deux tweens sur la meme propriete se disputent
  la bande, et la valeur finale devient celle du dernier a FINIR, pas du dernier demande.

### `show` rend la main quand les bandes sont EN PLACE

Son rappel se declenche a la fin du glissement, pas au debut : c'est la que la scene peut commencer. Demarrer
avant ferait jouer le premier plan pendant que le rideau descend encore.

### Ce qui suit

La camera de scene et l'enchainement (animation du grand-pere, marqueur `OuvertureDoorEvent`, ouverture de la
porte, dialogue). Rien n'est encore branche sur `startMission()`.

## 0.0.445 — La trace du didacticiel se tait

Le parcours complet a ete valide a l'ecran : 134 studs -> 114 -> 80 -> 48 -> 15.8 -> 5.0, la touche se branche,
la mission demarre. `DEBUG` repasse a false.

Un log toutes les deux secondes finit par noyer les vrais messages, et un journal qu'on n'ose plus lire ne sert
plus a rien. Le reglage reste : le remettre a true le jour ou la detection redevient suspecte.

## 0.0.444 — Le prompt se pose au milieu de la porte

Il sortait SUR LE COTE. La PrimaryPart de la porte est le "Handle" -- la CHARNIERE -- et c'est elle qui servait
de point d'accroche. Le badge s'affichait donc au bord, et la distance se comptait depuis ce bord.

Le prompt vise maintenant le CENTRE de la boite englobante du Model. Ce centre ne depend d'aucun choix de
PrimaryPart : changer celle-ci dans Studio ne deplacera plus le badge.

La distance de detection part du meme point, ce qui la rend juste aussi -- avant, on mesurait depuis un bord.

### Recalcule a chaque test

Deplacer la porte pendant une partie doit suivre. Une boite englobante sur une poignee de parts ne coute rien,
et la valeur est IDENTIQUE tant que la porte ne bouge pas : le prompt n'est donc pas re-affiche pour rien.

### PROMPT_OFFSET passe a zero

Il valait 3 studs de haut, pour compenser une accroche au sol. Au centre de la porte, il n'y a plus rien a
compenser : a zero le badge est pile au milieu. Le reglage reste, pour le remonter ou le descendre a l'oeil.

## 0.0.443 — Le prompt de la porte sort enfin

La trace du commit precedent a nomme le coupable en une ligne :

    [Tutorial] porte trouvee mais AUCUNE BasePart dedans : rien ou accrocher le prompt

Avec StreamingEnabled, le Model `Door` est replique AVANT ses parts. Au boot, `PrimaryPart` et
`FindFirstChildWhichIsA("BasePart")` rendaient donc `nil`.

Et le code ne re-resolvait l'ancre que si le MODEL disparaissait. Il gardait la porte en cache avec une ancre
VIDE, pour toute la session : le prompt ne pouvait plus jamais sortir.

Symptome trompeur au possible : la porte EST trouvee. On va donc chercher du cote de la distance, du rayon ou du
prompt lui-meme, alors que le trou est dans la replication.

### Ce qu'on garde en cache, c'est le RESULTAT COMPLET

Tant qu'une piece manque -- le Model, l'ancre, le Highlight -- on re-resout a chaque balayage. Le Highlight a
droit au meme traitement : il peut arriver apres les parts.

### Une recherche ne rend que ce qui est UTILISABLE

`findDoor` ne rend plus un Model nu mais un couple (Model, part). Un Model sans aucune part est ignore et la
recherche CONTINUE -- ce qui regle du meme coup l'autre cas : un autre Model du meme nom, vide, qui aurait
capture la recherche pour toujours.

### A FAIRE DANS STUDIO

Rien. Mais le message d'avertissement de `AmbientAnimService` reste vrai : le Model du grand-pere s'appelle
`OldmanOriginal` alors que la config attend `GrandFather`. Il ne respire donc pas, et il ne se promene pas.

## 0.0.442 — La porte se trouve par son NOM, ou qu'elle soit rangee

Le didacticiel cherchait la porte a un chemin fixe (`Worlds/Maps/Assets/House/Door`). Elle vient de demenager
dans `HouseModel`, et elle redemenagera : un chemin en dur transforme chaque rangement dans l'editeur en panne
SILENCIEUSE -- ni halo, ni prompt, ni erreur.

Recherche par NOM dans tout le Workspace. Le balayage ne tourne QUE tant que la porte n'est pas trouvee, donc il
ne coute rien une fois qu'elle est la. C'est le code qui s'adapte au rangement, pas l'inverse.

Meme regle que pour les zones d'herbe et les PNJ : racine LARGE avec un filtre cheap, plutot qu'une racine
etroite qui oblige a ranger les objets au bon endroit.

### Une trace pour ne plus deviner

"Aucun prompt" couvre plusieurs causes qui se ressemblent a l'ecran : porte introuvable, porte sans BasePart,
personnage pas encore la, ou simplement trop loin. La console les separe maintenant, et donne la DISTANCE reelle
a cote du rayon demande :

    [Tutorial] porte "Door" | ancre "Handle" a 14.2 studs (rayon 10) | halo true | mission lancee false...

`DEBUG` a remettre a false une fois le didacticiel regle.

## 0.0.441 — Un prompt sur la porte pour lancer la mission

Le halo dit OU aller ; le prompt dit QUOI faire une fois arrive. Il apparait a moins de 10 studs de la porte,
affiche "KNOCK", et lance la mission.

### Le prompt partage, pas un deuxieme

`InteractionPrompt` sert deja a l'echelle, la tondeuse, le seau et la boite aux lettres. On le REUTILISE. C'est
un SINGLETON, donc on ne cache que le NOTRE : appeler `hide()` sans regarder ferait disparaitre celui d'une
autre feature en plein milieu.

### Detection RADIALE, pas une box

Colle a un bout de la porte, une box laterale laisserait tomber dehors -- et l'agrandir ne bouche pas le trou,
elle reste au mauvais endroit. Un seul nombre, aucun angle mort, independant de l'orientation. Mesuree depuis la
PrimaryPart et jamais depuis `GetPivot`, qui suit la bounding box.

### Jouable sans clavier

`ContextActionService` avec `createTouchButton` : bouton a l'ecran sur tactile, touche sur PC, d'un seul geste.
Une action clavier-only rendrait le didacticiel infranchissable pour la moitie des joueurs Roblox.

L'action est en `Pass` et pas en `Sink` : E est partagee avec le seau et la tondeuse, avaler l'input les
casserait. Conflit connu, note dans la config : un seau pose devant la porte repondrait en meme temps.

### Un drapeau par avertissement

Porte introuvable et Highlight introuvable ont chacun le leur. Partage, le premier masquerait le second -- et on
chercherait le probleme du halo alors que c'est la porte qui manque. Meme bug que les sons de la tondeuse, ou un
seul drapeau global ne signalait que le premier son absent.

### Ce que l'appui fait aujourd'hui

Il eteint le guidage -- halo, prompt et touche -- et le marque demarre. `startMission()` est idempotent : un
double appui ne relancera pas une scene deja en cours.

Rien de plus pour l'instant : l'animation de la porte, la sonnette et la scene cinematique se brancheront la,
quand les animations du grand-pere existeront.

### A FAIRE DANS STUDIO

Rien de neuf. Toujours le `Highlight` sous le Model "Door", et la porte doit exister dans la place testee.

## 0.0.440 — La porte du grand-pere respire pour dire ou aller

Premiere brique du didacticiel guide. En arrivant dans le tuto, le joueur voit un halo battre doucement sur la
porte du grand-pere.

On le lui MONTRE au lieu de le lui ECRIRE. Un halo qui respire se lit sans lire, il ne demande aucune traduction
et il ne pose aucune interface par-dessus le monde.

### Le Highlight vient de Studio, pas du code

Le code ne touche QU'A UNE propriete : `FillTransparency`. La couleur du contour, sa transparence, le mode
d'affichage restent exactement ce qui a ete choisi dans l'editeur. Creer le Highlight en code aurait oblige a
refaire ce reglage a l'aveugle, et Rojo ne synchronise pas le Workspace de toute facon.

### Un sinus, pas un aller-retour

Une respiration n'a ni depart ni arrivee. Le cosinus repart de lui-meme, donc aucune saccade au bouclage -- un
lerp aller-retour casse a chaque extremite.

### La boucle part meme sans porte

Avec StreamingEnabled, la porte arrive souvent APRES le spawn. Sortir au demarrage laisserait le halo mort pour
toute la session, sans la moindre erreur : le piege deja paye sur l'herbe de zone. Elle coute une comparaison de
date tant qu'il n'y a rien a animer, et re-cherche toutes les 2 s.

Et si la porte n'est toujours pas la au bout de 12 s, elle le DIT, en nommant ce qu'elle cherchait.

### Un interrupteur, prevu pour la suite

`TutorialController.setDoorHint(false)` eteint le halo. Un halo qui continue de respirer pendant une cinematique
tirerait l'oeil hors du plan. Il ecrit la valeur eteinte au lieu de sortir en silence : coupe en plein
battement, le halo resterait sinon fige a moitie visible.

### A FAIRE DANS STUDIO

Poser un `Highlight` nomme "Highlight" sous le Model "Door", avec `FillTransparency = 1` au repos. Rojo ne
synchronise pas le Workspace : ce Highlight se pose A LA MAIN dans CHAQUE place ou la porte existe.

### Suite prevue

Toquer (prompt + `DoorShakeAnimation` + `SonnetteAnimation`), puis la scene cinematique avec ses barres noires.
Les deux attendent les animations du grand-pere.

## 0.0.439 — Les scripts d'attache ne mentent plus sur le nom de la piste

`AttacherCanneAuPapi.lua` et `AttacherObjetAuRig.lua` annonçaient tous les deux que le nom du Motor6D devenait
le nom de la PISTE dans l'editeur d'animation. C'est faux, et c'est exactement l'erreur qui a coute deux
versions entieres sur le portage du seau (0.0.432).

Une animation retrouve ce qu'elle doit bouger par le nom de la PART1 du joint. Une anim R15 cle "UpperTorso"
(une part), jamais "Waist" (le Motor6D qui la tire). Le nom du joint ne sert qu'a le RETROUVER pour le
remplacer.

Les deux scripts le disent maintenant en tete, avec la consequence : c'est le nom de la PART qui doit
correspondre entre le rig d'animation et le jeu.

### Pourquoi ca valait un commit a soi seul

Ces scripts sont ce qu'on relit AVANT d'animer. Une regle deja notee dans le journal ne protege que si elle est
la ou l'on travaille -- le projet la connaissait a deux endroits et l'a quand meme repayee.

## 0.0.438 — L'outil revient en haut de l'echelle, et on n'y monte plus les bras pleins

Deux corrections sur la meme famille, dont une REGRESSION introduite la veille.

### Ranger l'outil a la prise de l'echelle cassait la taille en hauteur

La version 0.0.435 ajoutait un `ToolService.unequip` a la prise de l'echelle, "par coherence avec la tondeuse et
le seau". Personne ne l'avait demande, et ca cassait la boucle de travail -- de facon indirecte, donc invisible a
la relecture.

`HedgeService.syncLadderTool` range l'outil pendant la grimpe en MEMORISANT SON NOM, puis le rend a l'identique
une fois en haut. Ce souvenir se prend sur l'outil EN MAIN au debut de la montee. Les mains deja vides a la prise
de l'echelle, il n'y a rien a memoriser, donc rien a rendre : le joueur arrive en haut sans outil, devant la haie
qu'il venait tailler, et rien ne lui dit pourquoi.

L'echelle n'est pas une tache en soi : c'est le MOYEN d'atteindre le haut d'une haie. Elle ne vide donc plus les
mains. Le seau et la tondeuse, eux, gardent ce rangement : ce sont des taches a part entiere.

Lecon : ajouter une regle "par coherence" sur un systeme qu'on n'a pas suivi jusqu'au bout coute plus cher que
l'incoherence qu'elle voulait supprimer. Trois systemes qui se ressemblent ne servent pas le meme but.

### Un souvenir efface avant d'etre rendu

Trouve en relisant le chemin ci-dessus. `syncLadderTool` vidait `ladderStash` AVANT de savoir si l'equipement
avait reussi. Tant que `equip` ne refusait jamais, ca ne se voyait pas. Il refuse maintenant quand les mains sont
prises (0.0.435) : un joueur qui redescend en ayant ramasse un seau perdait le nom de son outil POUR DE BON,
sans la moindre erreur. Le souvenir n'est efface que si l'outil est vraiment revenu.

### On ne monte plus a une echelle avec un seau dans les bras

La montee ne verifiait qu'une chose : "est-ce que je porte une echelle ?" -- pour ne pas grimper la sienne, dont
les zones nous suivent. Elle verifie maintenant que les mains sont LIBRES, ce qui couvre aussi le seau et la
tondeuse.

L'OUTIL, lui, ne compte pas : il n'occupe pas les mains au sens de CarryUtils, et c'est justement pour couper en
haut qu'on monte. La question laissee ouverte en 0.0.437 est donc tranchee : monter avec un seau est refuse.

La meme regle tourne aussi EN CONTINU, pas seulement a la montee : si les mains se remplissent pendant qu'on est
accroche, on redescend au lieu de rester perche les bras pleins.

## 0.0.437 — Plus de geste qui part dans le vide

En portant un seau, le badge "F PRENDRE" de l'echelle restait affiche. On appuyait : le personnage jouait tout le
geste de prise, le son partait... et rien. Le seau restait dans les mains, l'echelle par terre.

La version precedente avait pose le refus cote SERVEUR, ce qui empeche bien la triche. Mais le CLIENT, lui,
n'avait pas ete prevenu : il proposait toujours l'action et jouait le geste entier avant que le serveur ne dise
non, en silence.

**Un refus serveur silencieux n'est pas un refus vu par le joueur.** Il ne suffit pas d'empecher : il faut que
rien ne se joue. Sinon le jeu a l'air casse, ce qui est pire qu'une action interdite -- le joueur voit son perso
attraper une echelle qu'il n'attrape pas, et il ne peut pas savoir pourquoi.

### Les deux endroits, sur les deux systemes

L'echelle ET la tondeuse avaient le meme trou, aux memes deux endroits :

- **Le badge.** Il ne s'affiche plus quand les mains sont prises par autre chose. On ne propose pas ce qu'on ne
  pourra pas prendre.
- **Le geste.** Bloque a son point de passage unique (`pickUp` pour l'echelle, `toggleCarry` pour la tondeuse),
  et pas seulement sur le chemin du badge : la touche et le bouton tactile passent ailleurs. Sur la tondeuse, le
  test est pose APRES la repose (on peut toujours reposer SA machine) et AVANT la marche d'approche -- sinon le
  joueur partait marcher vers une tondeuse qu'il ne pouvait pas prendre.

La tondeuse debranche en plus sa touche : E est partage avec le seau, la laisser branchee ferait repondre deux
actions au meme appui.

Le seau, lui, avait deja ces deux gardes : c'est le seul des trois qui filtrait son prompt.

### Reste ouvert

Grimper a une echelle en portant un seau reste possible. C'est de la meme famille, mais c'est une question de
DESIGN et pas un bug : monter avec son seau est un geste de jardinier credible. A trancher, pas a corriger en
passant.

## 0.0.436 — Reposer le seau claque au lieu de trainer

Ramasser est un EFFORT : on se baisse, on empoigne. Reposer est un relachement. Les deux jouaient a la meme
cadence, donc la fin du geste trainait et le joueur attendait de recuperer ses commandes.

    PLACE_SPEED   1  ->  1.8

Le seau quitte les mains en ~0.35 s au lieu de ~0.65 s.

### Deux reglages en dependent, et ils ont bouge avec

C'est le piege deja paye quatre fois ici (un reglage qu'on monte, un autre qu'on oublie). Les deux sont
explicitement lies a `PLACE_SPEED` dans la config, avec ce qu'ils attendent :

- `PLACE_STRAIGHTEN_TIME` 0.5 -> 0.25. Le redressement doit finir AVANT que la main s'ouvre. La main s'ouvre au
  marqueur, atteint en marche arriere au bout de `(duree - 0.57) / PLACE_SPEED`. Laisse a 0.5, le seau serait
  encore penche au lacher et se redresserait EN L'AIR -- exactement la correction apres coup que 0.0.429 avait
  supprimee.
- `PLACE_SLOW_TIME` 0.45 -> 0.35. Le bridage de vitesse durait plus longtemps que le geste : on ralentissait un
  joueur qui avait deja fini de poser. Cale sur l'instant du lacher, pas sur la fin du geste.

## 0.0.435 — On ne porte plus qu'une seule chose a la fois, pour de bon

Un joueur pouvait porter le seau ET prendre l'echelle, ET la tondeuse, ET sortir un taille-haie.

### Ce qui n'allait pas

Chaque objet posait SON drapeau et gardait SA liste de ceux qui le bloquent. Trois drapeaux, deux porteurs
differents, deux autorites differentes :

    LeafiaCarryingBin      sur le PERSONNAGE   ecrit par le serveur
    LeafiaCarryingLadder   sur le PERSONNAGE   ecrit par le CLIENT
    LeafiaCarryingMower    sur le JOUEUR       ecrit par le serveur

Sur les 12 paires a tenir d'accord, 7 manquaient. `LeafiaCarryingBin` etait meme ecrit sans que PERSONNE ne le
lise : le seau ne bloquait rien du tout. La tondeuse, elle, ne verifiait personne.

Un piege dormait en plus dans le seau : sa garde lisait ses drapeaux sur le PERSONNAGE, alors que celui de la
tondeuse est sur le JOUEUR. Ajouter la tondeuse a sa liste pour boucher le trou n'aurait donc rien donne, sans
la moindre erreur pour le dire.

Et le drapeau de l'echelle etait pose par le CLIENT : un client modifie ne le posait pas et portait tout a la fois.

### Une seule question, une seule reponse

`Modules/Utils/CarryUtils` detient l'etat "les mains de ce joueur tiennent quoi". Un attribut, sur le joueur,
ecrit par le serveur seul.

    CarryUtils.isFree(player)          -- puis-je prendre ?
    CarryUtils.claim(player, "Bin")    -- je prends (false si deja pris par autre chose)
    CarryUtils.release(player, "Bin")  -- je rends (et seulement ce que je tiens)
    CarryUtils.holds(player, "Ladder") -- tient-il precisement ca ?

Les quatre systemes y sont branches : seau, echelle, tondeuse, outils. Le refus est applique cote SERVEUR dans
les trois `grab` et dans `ToolService.equip`, la seule porte d'entree de l'equipement. Le client ne fait plus que
masquer le prompt, ce qui est du confort d'affichage et non une regle.

Avec N objets, l'ancien modele demandait N x (N-1) verifications a maintenir a la main, et chaque nouvel objet
obligeait a modifier tous les autres -- ce que personne ne fait, parce que rien ne le rappelle. Ajouter un
cinquieme objet ne touche desormais aucun des quatre autres.

Au passage : prendre le seau ou l'echelle RANGE l'outil en main, comme le faisait deja la tondeuse. On range au
lieu de refuser -- refuser laisserait le joueur appuyer sur E sans que rien ne se passe et sans savoir pourquoi.

### Un trou trouve en chemin

L'echelle ne se relachait qu'au DEPART du joueur, jamais a sa MORT. Invisible tant que "on porte" vivait sur le
personnage, detruit avec lui. Maintenant que cet etat vit sur le joueur et survit au respawn, l'oubli aurait
bloque ses mains POUR TOUTE LA SESSION. `CharacterRemoving` ajoute, comme sur le seau et la tondeuse.

## 0.0.434 — Le seau bouge enfin comme dans l'editeur

Il etait anime depuis le debut. Mal, mais anime. On croyait qu'il ne l'etait pas du tout.

### La mesure qui a tout retourne

`VerifierBin.lua` sur le rig d'animation :

    Workspace.Bin   PrimaryPart (propriete) = "PrimaryPart" -> OK
    joint "Bin"     HumanoidRootPart -> PrimaryPart
    C0              CFrame.new(0.0000, 0.2000, -2.6000) * CFrame.Angles(0, math.rad(90), 0)

Le nom correspondait DEJA des deux cotes (`PrimaryPart`). Il n'y avait donc aucun renommage a faire -- ni du joint
(0.0.431), ni de la part (0.0.432). Ces deux versions cherchaient au bon endroit une erreur qui n'y etait pas.

Ce qui ne correspondait pas, c'est la PART PORTEUSE et le C0.

### La position d'un objet anime tient en trois termes

    position du seau = part porteuse x C0 x ce qu'ecrit l'animation

L'animation n'ecrit QUE le troisieme. Les deux premiers viennent du code. Si l'un des deux differe du rig, le
meme mouvement s'applique depuis une base differente et donne autre chose a l'ecran.

Le jeu accrochait le seau a `UpperTorso`. Or le torse est LUI-MEME anime : il figure dans les pistes des deux
animations. Le seau recevait donc le mouvement du torse EN PLUS du sien -- deux mouvements additionnes au lieu
d'un. D'ou un geste qui bougeait bien, mais qui ne ressemblait pas a l'editeur.

    JOINT_PARENT   "UpperTorso"              ->  "HumanoidRootPart"
    CARRY_C0       CFrame.new(0, 0,   -2.6)  ->  CFrame.new(0, 0.2, -2.6)

Verifie en jeu : le geste ressemble maintenant a l'animation.

### Le message d'erreur d'a cote devenait faux

Il accusait un « rig R6 au lieu de R15 » quand la part porteuse manque. C'etait vrai pour `UpperTorso`, absent en
R6. `HumanoidRootPart` existe sur les deux : absent, il ne dit rien du rig, il dit un personnage pas fini de
charger. Un diagnostic qui nomme la mauvaise cause coute plus cher que pas de diagnostic -- c'est exactement ce
qui a fait tourner en rond les versions 0.0.430 et 0.0.431.

### Ce qui reste, et qui n'est PAS fait ici

- **La soudure arrive trop tard.** La piste du seau a des cles des t=0, mais le joint n'est cree qu'a 0.45 s : le
  debut du geste ne s'applique jamais. Pire, le marqueur `TakeBucketEvent` est a 0.57 s alors que le filet de
  secours `TAKE_GRAB_FALLBACK` est a 0.45 s. Le filet gagne donc A TOUS LES COUPS, et le commentaire qui dit
  « sans effet tant que le marqueur parle » est faux. Le commentaire annonce aussi le marqueur « a 0.33s » : il a
  bouge depuis.
- **La repose ecrase l'animation.** `straightenInHands` reecrit le `C0` du joint a chaque image. Le code et
  l'animation ecrivent alors sur le meme seau en meme temps. Ce code compensait l'absence d'animation : il n'a
  plus de raison d'etre.
- **La sonde d'animation mesure du mauvais cote.** Elle lit `Transform` cote SERVEUR alors que l'animation est
  calculee cote CLIENT : elle lira l'identite quoi qu'il arrive, et continuera d'affirmer que l'animation ne
  pilote pas le seau alors qu'on le voit bouger. A deplacer cote client ou a retirer.

## 0.0.433 — Le jeu parle anglais partout, donc il se traduit

Des textes vus par le joueur etaient restes en francais. Le traducteur automatique de Roblox part de l'ANGLAIS :
un texte ecrit en francais n'est traduit nulle part, et reste illisible pour la quasi-totalite des joueurs de la
plateforme. Ce n'est donc pas un detail de forme, c'est de l'audience perdue.

### Ce qui etait en francais

Le plus visible en premier -- l'ecran de chargement, vu par CHAQUE joueur a CHAQUE lancement :

    "Generation des terrains"  -> "Shaping the ground"
    "Creation des massifs"     -> "Planting flower beds"
    "Plantation des haies"     -> "Planting the hedges"
    "Preparation des outils"   -> "Getting the tools ready"
    "Ouverture des chantiers"  -> "Opening the job sites"
    "C'est pret !"             -> "Ready!"

Puis les badges d'interaction, poses au-dessus des objets :

    seau     "PRENDRE" / "SEAU"  -> "TAKE" / "BUCKET"
    echelle  "MONTER"            -> "CLIMB"
    echelle  "PRENDRE"           -> "TAKE"

Le texte par defaut d'`InteractionPrompt` disait "PRENDRE" lui aussi : une feature qui oublie de passer son label
affichait donc du francais sans que personne le remarque.

Et la notification de montee de niveau :

    "NIVEAU 4" / "Bravo ! Ton entreprise grandit."  ->  "LEVEL 4" / "Nice! Your business is growing."

La tondeuse, elle, etait deja en anglais ("TAKE" / "MOWER") : c'est le seau et l'echelle qui ont derive.

### Ce qui reste en francais, volontairement

Les commandes d'admin (`AdminCommandConfigs`, la barre de saisie) : aucun joueur ne les voit, seuls les
developpeurs les lisent. Les traduire ne rapporterait rien et rendrait l'outil moins pratique a utiliser.

Les COMMENTAIRES de code restent en francais, comme le veut la convention du projet. Les trois qui citaient un
texte joueur ont ete remis d'accord avec ce que le code affiche vraiment : un commentaire faux coute plus cher
qu'un commentaire absent.

## 0.0.432 — Le seau : on cherchait le bon nom au mauvais endroit

Les deux versions precedentes ont conclu, mesure a l'appui, que l'animation ne pilote pas le seau. La mesure est
bonne. La CAUSE annoncee est fausse, et la correction demandee (« relever le nom de la piste et le reporter dans
`JOINT_NAME` ») n'aurait rien change.

### Une animation ne cherche pas un joint par le nom DU JOINT

Elle cherche par le nom de sa **Part1**. Ses poses portent des noms de PARTS. C'est pour ca qu'une animation R15
contient `UpperTorso` et `LeftUpperArm` -- des parts -- et jamais `Waist` ni `LeftShoulder`, les Motor6D qui les
tirent.

Le nom qui compte pour le seau est donc celui de sa **part racine** (`ROOT_NAME`, la Part1 du joint de portage),
pas `JOINT_NAME`. Ce dernier ne sert qu'a retrouver le Motor6D dans l'Explorer, et le renommer n'aura jamais le
moindre effet sur l'animation.

Le projet le savait deja a deux endroits : `ComparerAnimEtRig.lua` construit la liste des noms acceptes a partir
des `Part1`, et le journal de `CLAUDE.md` (piege des animations Mixamo sur Papi) dit noir sur blanc « comparer les
noms de poses de la KeyframeSequence aux noms des `Part1` du rig ». Le code du seau, ecrit plus tard, a pose la
regle a l'envers -- et deux versions ont ete construites par-dessus.

### Le diagnostic accusait le mauvais reglage

Le message de la sonde envoyait renommer `JOINT_NAME`. Il nomme maintenant la vraie cause, et la part concernee :

    l'animation NE pilote PAS le seau : la part "RootPart" (soudee a "UpperTorso") n'a jamais bouge...
    Cause : l'animation ne contient AUCUNE piste portant ce nom de part.

Un diagnostic qui designe le mauvais coupable coute plus cher que pas de diagnostic du tout : il envoie travailler
avec confiance dans la mauvaise direction. C'est exactement ce qui s'est passe ici.

### La mesure devient automatique

Il fallait ouvrir l'editeur d'animation et lire un nom de piste a la main. `VerifierBin.lua` le fait maintenant :
il liste les pistes de chaque animation du seau, ISOLE celle qui n'est pas un membre de personnage (c'est celle du
seau), et la compare au nom de la part racine des seaux du Workspace. Il dit alors l'un des deux :

    piste du seau = "X", et une part racine porte ce nom -> l'animation pilotera bien le seau
    MANQUE : ... cle "X", mais la part racine des seaux s'appelle "RootPart". Les deux doivent porter le MEME nom

Plus de nom a relever a l'oeil, plus de nom a recopier : la comparaison est faite et le verdict est rendu.

### A faire dans Studio

Lancer `VerifierBin.lua`. S'il signale un ecart, renommer la part racine du seau avec le nom de la piste, puis
reporter ce nom dans `BinConfigs.ROOT_NAME` -- les deux valeurs vont ENSEMBLE.

## 0.0.431 — Un seau monte sur un rig d'animation n'est plus un seau du jeu

Mesure du commit precedent, en jeu :

    l'animation NE pilote PAS le seau : le joint "BinCarryJoint" sur "UpperTorso" n'a jamais bouge.

C'est donc confirme : la piste du seau de l'animation n'est JAMAIS appliquee. Le nom du Motor6D cree en jeu ne
correspond pas a celui du joint pose sur le rig d'animation, et une animation retrouve un joint PAR SON NOM.
Tout le travail d'angle des versions precedentes compensait ca sans le savoir.

### Le rig polluait la detection

Les logs montraient aussi `Workspace.Rig.Bintest` compte comme un 3e seau. Les rigs d'ANIMATION vivent dans le
Workspace avec leur seau accroche dans la main : le jeu proposait donc de "prendre" un objet soude a un
mannequin.

Un model est desormais ignore s'il vit sous un rig, reconnu a son `Humanoid` -- pas a son nom, qui ne se devine
pas. Filtre pose des DEUX cotes : le client ne le propose plus, et le serveur le refuse meme si on le lui
demande.

Le garde-fou annonce dans `BinConfigs` ("un model de test nomme Bintest serait vu comme un vrai seau") devient
donc inutile : le cas est traite, plus seulement documente.

### A faire dans Studio

Relever le nom de la PISTE du seau dans l'editeur d'animation, et le reporter dans `JOINT_NAME`. C'est la seule
chose qui manque pour que l'animation reprenne la main sur l'angle du seau.

## 0.0.430 — Le jeu dit si l'animation pilote vraiment le seau

L'animation du seau anime le SEAU LUI-MEME : sa piste existe dans l'editeur, elle le pose a plat de 0 a 0.5 s
puis le fait lever a 0.57 s. Si elle etait appliquee en jeu, tout le travail d'angle des versions precedentes
serait inutile -- c'est l'animation qui commanderait, pas la config.

Or une animation Roblox retrouve un joint PAR SON NOM. Si `JOINT_NAME` ne correspond pas au nom du Motor6D pose
sur le rig d'animation, la piste du seau ne trouve rien et n'ecrit RIEN. Sans la moindre erreur. Le seau reste
fige sur `CARRY_C0`, et on croit a un probleme d'angle alors que l'animation n'est jamais appliquee.

C'est exactement le piege deja paye sur les PNJ (animations Mixamo sur un rig sans os correspondants) : la piste
tourne, les joints restent a zero, rien ne signale l'echec.

### On mesure le resultat, pas l'intention

A la prise, le jeu regarde 0.6 s plus tard si le `Transform` du joint a bouge. Les animations ecrivent dans
`Transform`, jamais dans `C0` : reste a l'identite = personne n'a ecrit dedans.

La console dit alors l'un des deux :

    l'animation pilote bien le seau (joint "X" anime).
    l'animation NE pilote PAS le seau : le joint "X" sur "Y" n'a jamais bouge...

Le second message nomme les deux causes possibles (`JOINT_NAME`, `JOINT_PARENT`) au lieu de laisser chercher.

### Ce que ca decide pour la suite

Si l'animation pilote le seau, tout le reglage d'angle devient inutile : `PLACE_STRAIGHTEN_TIME` et l'orientation
composee a la repose sont a retirer, l'animation fait deja le travail. Si elle ne le pilote pas, il n'y a qu'un
nom a corriger. Deux chemins opposes, une seule mesure pour trancher.

### A faire dans Studio

Rien pour ce commit. Mais le nom de la piste du seau dans l'editeur d'animation est la valeur a reporter dans
`JOINT_NAME` si le message dit que rien ne bouge.

## 0.0.429 — Le seau se redresse DANS LES MAINS, pendant le geste

Il etait tenu PENCHE jusqu'au dernier instant, puis se remettait droit une fois lache. Le redressement se
lisait donc comme une correction apres coup, pas comme une partie du geste.

Il se redresse maintenant DANS LES BRAS, en 0.5 s, a partir de l'appui sur la touche. Le geste de repose dure
environ 0.8 s avant que la main s'ouvre : le seau est donc deja a plat quand il quitte les mains, et il ne lui
reste plus qu'a descendre. Le mouvement se cale sur l'animation.

### Ce qu'on modifie, et ce qu'on ne touche pas

Seule la ROTATION du joint change, jamais sa position : le seau reste au meme endroit dans les bras.

Et on n'enleve que le TANGAGE et le ROULIS. Le LACET est ce qui fait suivre le joueur, on le garde -- sans quoi
le seau tournerait sur lui-meme pendant qu'on le repose, et l'orientation de pose ne correspondrait plus a celle
qu'on visait.

### Aucun calcul en repere monde

L'UpperTorso d'un personnage debout est DROIT. Retirer tangage et roulis du C0 suffit donc a mettre le seau a
plat DANS LE MONDE -- pas besoin de recalculer une orientation monde a chaque image pendant que le joueur bouge.

### Le compte s'arrete si le seau n'est plus a nous

Lache, repris par un autre, personnage detruit : la boucle sort. Et `grab` remet `CARRY_C0` d'origine, donc une
reprise redonne bien le seau penche dans les bras.

### Le reglage

`PLACE_STRAIGHTEN_TIME` (0.5 s). Le monter au-dela de ~0.8 s rendrait le redressement visible APRES le lacher,
ce qui annulerait tout l'interet. A 0, le seau part penche comme avant.

## 0.0.428 — Le seau est deja droit quand il commence a descendre

`PLACE_TWEEN_ROT_TIME` 0.08 -> 0.001. Le redressement tient dans la premiere image : on ne voit plus la
rotation du tout, seulement la descente. Reglage seul, aucun code touche.

## 0.0.427 — Le seau se redresse tout de suite, puis descend

Il restait DE BIAIS pendant tout le trajet vers le sol et ne se remettait droit qu'a l'arrivee. On le voyait donc
pencher tout du long.

Cause : UNE SEULE duree pilotait la position ET la rotation. Le motif deja rencontre quatre fois dans ce projet
-- un reglage qui sert deux moments differents finit par les opposer. Aucune valeur ne pouvait convenir aux deux :
courte, le seau claquait a sa place ; longue, il penchait pendant un quart de seconde.

Deux durees maintenant. `PLACE_TWEEN_ROT_TIME` (0.08 s) le redresse presque tout de suite ; `PLACE_TWEEN_TIME`
(0.22 s) lui laisse le temps de descendre. Il se met a plat, et il ne lui reste plus qu'a se poser.

### Pourquoi on n'utilise plus `CFrame:Lerp`

Il interpole position et rotation ENSEMBLE, sans moyen de les separer -- c'est justement ce qu'on ne veut plus.
On decompose donc a la main, position d'un cote et rotation de l'autre, et on recompose.

### Le reglage

Garder `PLACE_TWEEN_ROT_TIME` nettement plus court que `PLACE_TWEEN_TIME` : c'est tout l'interet. A 0, le seau
se redresse d'un coup a l'image du lacher.

## 0.0.426 — L'ecrasement du seau est retire

Il brouillait la repose au lieu de l'appuyer.

Cause probable, notee pour le jour ou on le refera : l'effet DEMARRAIT d'un coup a 55 % de la hauteur, sans la
moindre entree en douceur. Les parts sautaient a leur taille ecrasee en une image, et un objet qui change de
taille ET de position d'un coup se lit comme une TELEPORTATION, pas comme un choc.

`BuildPlaceController` fait le meme effet correctement : il monte de 1 vers la valeur ecrasee sur le premier
tiers du temps, PUIS revient en depassant. C'est la reference si on y revient.

Code et reglages supprimes, pas desactives : un effet eteint derriere un reglage devient du code mort qu'on
n'ose plus toucher. Il est dans l'historique, un revert le ramene.

Le jeton qui protegeait l'animation reste, mais il ne parle plus que du TRAJET vers le sol -- renomme en
consequence. Un nom qui ment vaut moins que pas de nom.

### Ce qui ne change pas

Le trajet glisse de 0.0.425, l'ancrage a la pose et la mesure de tangage/roulis restent en place.

## 0.0.425 — Le seau glisse jusqu'au sol au lieu d'y sauter

Il se TELEPORTAIT a plat a l'instant du lacher, pendant que le geste de repose jouait encore : le personnage se
penchait vers un objet qui n'etait deja plus la. C'est ca, le saut qu'on voyait.

On MEMORISE maintenant la position ET l'orientation qu'il a DANS LES MAINS -- celles que l'animation lui donne
-- et il GLISSE de la jusqu'a sa pose finale au sol. Les deux mouvements se recouvrent, le geste se lit en
entier.

`CFrame:Lerp` interpole position et rotation d'un coup : c'est ce qui redresse le seau progressivement au lieu
de le claquer droit. Easing Quad Out -- il part vite et se pose doucement, comme un objet qu'on depose.

### On pose pour mesurer, puis on remet

Le point le plus bas depend de l'orientation finale : il faut donc l'appliquer pour le connaitre. Tout se passe
dans la MEME image, avant la moindre replication -- personne ne voit ce va-et-vient, et le trajet part bien de
la pose des mains.

### Un seul jeton pour le trajet ET l'ecrasement

Reprendre le seau en plein trajet ou en plein ecrasement doit couper les DEUX d'un coup : sinon une boucle
continuerait d'ecrire les positions des parts par-dessus la soudure, et le seau partirait en vrille dans les
mains. Chaque sortie rend le jeton, y compris les sorties d'erreur -- un jeton oublie laisserait le seau marque
"en cours d'animation" pour toujours.

L'ecrasement part maintenant A L'ARRIVEE, plus au lacher : c'est le contact avec le sol qu'il represente.

### Le reglage

`PLACE_TWEEN_TIME` (0.22 s). A 0 on retrouve le saut instantane.

### A faire dans Studio

Rien.

## 0.0.424 — Le seau reste a plat une fois pose

Il se posait de travers. Le weld n'y etait pour rien : il est detruit des le debut de la repose (`detach`).
C'est ce qui se passe APRES qui le penchait.

Pour etre porte, le seau doit etre DESANCRE -- une part ancree ignore sa soudure. A la repose, on lui rendait
son etat d'origine. S'il etait LIBRE dans Studio, la physique reprenait donc la main dans la meme image : il
glisse, il bascule, et on le retrouve penche alors que le calcul de pose etait juste.

Symptome trompeur : on ne voit que le resultat, jamais le mouvement qui l'a produit. On va donc relire le calcul
d'angle, qui est innocent.

`PLACE_ANCHOR` (vrai par defaut) l'ancre une fois pose, vitesses remises a zero. Le mettre a faux le laisse
libre -- il roulera, il tombera des pentes : c'est un choix de gameplay, pas un reglage a l'aveugle.

### Une mesure, pour ne plus deviner

La console dit maintenant a chaque pose : y a-t-il une PrimaryPart, un sol a-t-il ete trouve, et surtout le
TANGAGE et le ROULIS reels de la racine.

S'ils sont a zero et que le seau parait quand meme penche, l'angle est DANS le model (racine a plat, mesh
penche dedans) : aucun script ne corrigera ca, ca se regle dans Studio. S'ils ne sont pas a zero, c'est la pose.
Deux causes qui se ressemblent a l'ecran et se corrigent a deux endroits opposes.

### A faire dans Studio

Rien. Mais si le seau reste penche, la ligne `[BinCarryService] pose | ...` de la console dit ou chercher.

## 0.0.423 — L'ecrasement du seau est plus franc

Reglage seul, aucun code touche. `SQUASH_Y` 0.78 -> 0.55 (il tombe a un peu plus de la moitie de sa hauteur au
lieu des trois quarts), `SQUASH_SPREAD` 0.6 -> 0.9 (il s'elargit presque autant qu'il s'aplatit),
`SQUASH_TIME` 0.28 -> 0.34 (le rebond a le temps de se lire).

En dessous de ~0.35 sur `SQUASH_Y`, le seau se lit comme une galette et non plus comme un choc : c'est la
limite utile, pas une limite technique.

## 0.0.422 — Le seau s'ecrase en touchant le sol

Il s'aplatit une fraction de seconde au contact, puis reprend sa forme en depassant un peu -- c'est ce
depassement qui fait le rebond. Pur habillage : rien ne depend de sa taille.

### Pourquoi ce n'est pas un `ScaleTo`

`Model:ScaleTo` est UNIFORME : il retrecirait le seau au lieu de l'aplatir. Et il travaille autour du PIVOT, qui
suit la bounding box -- l'objet s'enfoncerait puis flotterait.

Chaque part est donc animee a la main, autour d'un repere pose AU SOL, sous le seau. La base reste collee par
terre pendant que le haut descend, ce qui est exactement ce qu'on veut voir.

### Cote serveur

En co-op, un effet local ne serait vu que de celui qui pose. Le seau est deja une affaire de serveur (soudure,
recherche du sol), l'ecrasement y reste.

### Il finit TOUJOURS a ses dimensions d'origine

Valeurs exactes a l'arrivee, pas approchees : une interpolation laisse toujours un residu, et un seau repris
puis repose garderait un ecart de taille qui s'accumulerait a chaque fois.

Et s'il est repris EN PLEIN ECRASEMENT, on rend les tailles mais PAS les positions : la soudure en est
proprietaire a cet instant, lui ecrire dessus la ferait sauter. `grab` coupe l'effet avant de souder, pour la
meme raison.

L'etalement en largeur est exprime comme un ECART de la hauteur perdue, pas comme une valeur absolue : il tombe
donc a zero pile en meme temps que l'ecrasement, sans qu'aucune constante n'ait a rester d'accord avec l'autre.

### Rien ne s'ecrase dans le vide

L'effet ne part que si le seau a REELLEMENT touche un sol. Repose au bord d'une plateforme sans sol trouve : pas
d'ecrasement, plutot qu'un rebond sur rien.

### A FAIRE DANS STUDIO

Regler `RenderFidelity` du mesh du seau sur **Precise** ou **Performance**. A `Automatic`, Roblox echange le
maillage selon la taille a l'ecran : une part qui change fortement de taille en une fraction de seconde
CLIGNOTE. Cette propriete ne s'ecrit PAS depuis un script (capacite Plugin), et Rojo ne la synchronise pas.

## 0.0.421 — Le joueur marche jusqu'au seau au lieu de tendre les bras

Le prompt apparait a huit studs, et le geste partait sur place : les bras se refermaient dans le vide pendant
que le seau se soudait au torse depuis l'autre bout. Le joueur MARCHE maintenant jusqu'a lui, comme il marche
deja jusqu'au guidon de la tondeuse.

En 0.0.415 il ne faisait que PIVOTER. C'etait le choix de l'epoque, pris sur une lecture fausse : j'avais
affirme que la tondeuse n'avait pas de marche d'approche, alors qu'elle en a une (`MowController`,
`approachThenGrab`). La marche remplace le pivot des que la distance le justifie ; le pivot reste pour le reste
du geste.

### On s'arrete du cote d'ou l'on vient

Aucun contournement a faire : un seau se prend de n'importe quel bord. C'est ce qui le distingue du guidon d'une
tondeuse, qui est DERRIERE elle et qu'il faut aller chercher -- d'ou le detour que fait `MowController` et qu'on
n'a pas ici.

### Pas de PathfindingService

Quelques studs dans un jardin ouvert : `Humanoid:MoveTo` suffit. Un vrai chemin calcule serait plus fragile
(bloque, sol irregulier, autre joueur) pour un gain nul a cette distance. Meme choix que la tondeuse, a revoir
si un seau se prend un jour derriere un obstacle.

### Trois garde-fous

- **Deja sur place** (`APPROACH_SKIP_DIST`) : aucun deplacement n'est fabrique, on prend. Regle apprise sur
  l'echelle, ou tout un systeme de marche forcee avait ete construit pour un joueur qui etait deja arrive.
- **Plafond de temps** (`APPROACH_TIMEOUT`) : `MoveTo` n'abandonne jamais tout seul. Mieux vaut une prise un peu
  de travers qu'un joueur bloque parce qu'un caillou lui barre le chemin.
- **Le seau peut disparaitre pendant le trajet** : un autre joueur le prend, le streaming l'enleve. On revalide
  a l'arrivee au lieu de prendre le vide.

Un drapeau empeche de lancer une seconde marche en appuyant pendant la premiere, et il est remis a zero a la
mort comme a l'arret du controller.

### A faire dans Studio

Rien.

## 0.0.420 — Le seau se repose exactement comme on le tenait

Au lacher, le seau PIVOTAIT d'un quart de tour. La repose alignait l'axe -Z du model sur le regard du joueur --
mais le seau est porte avec un quart de tour dans les mains (`CARRY_C0` contient `math.rad(90)`). Les deux
orientations differaient donc de cet angle, et l'ecart se voyait d'un coup a l'instant precis ou il quittait les
mains.

Rien ne garantit que le -Z d'un model soit son "devant" : ca vient du rig, pas du bon sens. On ne suppose donc
plus aucun axe. On compose le regard du joueur avec la rotation de la prise, ce qui redonne l'angle REEL qu'il a
a l'ecran, et on le repose la-dessus.

### Remis a plat

Un seau se pose droit. On ne garde que la direction HORIZONTALE de cette orientation, ce qui efface le tangage
et le roulis que la pose de portage peut lui donner. Repli sur le regard du joueur si cette direction n'existe
pas (objet pointant droit vers le haut).

### Le reglage

`PLACE_YAW` (degres) s'ajoute a cet angle. A 0, le seau se pose exactement comme on le porte. Le mettre a -90
alignerait le -Z du model sur le regard du joueur, c'est-a-dire le comportement d'avant -- avec le pivot sec
qui allait avec.

### A faire dans Studio

Rien.

## 0.0.419 — Plus de soubresaut entre le geste de prise et le portage

On voyait le personnage s'arreter une fraction de seconde puis reprendre, au moment ou la prise laisse la place
a la pose de portage.

Cause : les deux animations se RELAYAIENT. La pose de portage etait chargee et lancee a l'instant precis ou le
geste s'effaçait. Il suffisait d'une milliseconde de retard -- chargement de l'asset, signal differe d'une image
-- pour qu'il existe un instant SANS AUCUNE POSE. Le corps y repassait par la position neutre.

Rien ne pouvait combler ce trou, puisqu'il n'y avait rien en dessous.

### Elles se superposent maintenant, elles ne se relaient plus

La pose de portage demarre EN MEME TEMPS que le geste et joue EN DESSOUS de lui, masquee. La fin du geste ne
fait plus que la DECOUVRIR. Il n'y a plus d'instant a combler.

Priorites : geste en `Action3`, portage en `Action2`. Elles doivent DIFFERER -- a priorite egale Roblox ne
choisit pas, il moyenne les deux poses, et on verrait des bras a mi-chemin pendant tout le fondu.

### Le relachement de fin devient le mecanisme, plus le bug

En 0.0.416 la piste etait bouclee expres : non bouclee, elle se relache a sa derniere image et les bras
retombaient. Avec une pose en dessous, ce meme relachement REVELE le portage. `Looped = false` redevient donc le
bon reglage -- et une piste non bouclee ne peut plus reboucler d'une image au mauvais moment, ce qui supprime
l'autre moitie du soubresaut.

### Le filet de fin disparait

Il surveillait un rebouclage qui ne peut plus arriver. Et si `EndTakeEventBin` se tait, la piste finit
d'elle-meme et decouvre exactement la meme pose, juste un poil plus tard : son echec est devenu inoffensif.

`TAKE_LOAD_TIMEOUT` part avec, plus personne ne le lit.

### Note

Le rayon de prise est de 8 studs et le prompt n'apparait donc pas avant. Les traces envoyees montrent un seau a
9.2 puis 10.1 studs sans prompt : c'est le reglage qui parle, pas un bug. `DETECT_RADIUS` si tu veux le voir de
plus loin.

## 0.0.418 — Le joueur s'arrete en douceur pour poser son seau

On reposait son seau en pleine course : le geste glissait a cote du personnage. La vitesse DESCEND maintenant a
zero des l'appui, puis remonte. Ce n'est pas un blocage, c'est un freinage.

### C'est le serveur qui pilote, comme partout ailleurs

`WalkSpeed` a UN SEUL ecrivain, `CharacterService`. Le seau declare une intention
(`setSpeedOverride(player, 0)`), il ne touche pas a la valeur -- ecrire dedans se battrait avec la rampe
d'atterrissage, qui tourne sur la meme propriete.

L'elan est coupe DES L'APPUI, pas a la fin du geste : nouvelle phase `placeStart` sur le remote du seau. A cet
instant le seau est toujours en main ; il ne se detache que plus tard, quand la main s'ouvre.

### La cadence de rampe devient reglable par appelant

`CharacterService.setSpeedOverride(player, speed, rate?)` accepte un rythme.

Les rythmes globaux de `CharacterConfigs` sont regles pour le travail de haie : un arret prend environ une
seconde. Beaucoup trop mou pour un geste d'une seconde -- le joueur serait deja en train de reposer son seau que
sa vitesse baisserait encore.

On ne les a PAS changes pour autant : un reglage qui sert deux moments differents finit toujours par les
opposer. Le seau demande donc sa propre cadence (`PLACE_SLOW_RATE = 60`, arret en moins de 0.2 s), et le rythme
est OUBLIE des que la cible est atteinte : un geste ponctuel n'impose pas sa cadence au reste du jeu.

Les appelants existants (`HedgeService`, `MowService`) ne passent pas de rythme et gardent exactement le
comportement d'avant.

### La vitesse revient toute seule

`PLACE_SLOW_TIME` est volontairement INDEPENDANTE de la duree de l'animation. Elle rend la vitesse au bout du
compte a rebours, meme si le geste a ete interrompu par une autre prise ou un respawn : aucun joueur ne peut
rester coince au ralenti.

Un jeton par joueur evite l'autre bord : reposer deux fois de suite ne doit pas laisser le premier minuteur
rendre la vitesse en plein milieu du second geste.

### A faire dans Studio

Rien.

## 0.0.417 — Reposer le seau rejoue le geste a l'envers

La repose coupait tout d'un coup : le seau disparaissait des mains et le joueur revenait a sa pose neutre en une
image. `TakeAnimation` est maintenant rejouee A L'ENVERS.

On part de sa DERNIERE image -- celle que la pose de portage tient deja, donc le raccord ne se voit pas -- et on
remonte le temps jusqu'a la position neutre. La pose de portage s'efface en fondu croise pendant que le geste
inverse monte.

`Looped = false` ici, contrairement a la prise : arrivee a zero, la piste DOIT se relacher, puisque la pose
d'arrivee est justement la position neutre. C'est la recette du journal de CLAUDE.md, sortie inverse comprise.

### Le seau quitte les mains quand la MAIN S'OUVRE

Pas a l'appui. En marche arriere, c'est le MEME marqueur qu'a la prise (`TakeBucketEvent`), repasse dans l'autre
sens. Aucun marqueur a poser : celui de la prise sert deux fois.

Rejouer le geste A L'ENDROIT aurait montre un RAMASSAGE alors qu'on lache -- le bras qui descend vers le sol
puis se referme, exactement le contraire de ce qui se passe.

### Un filet sur son propre minuteur

C'est le seul defaut de ce fichier qu'un joueur ne peut PAS rattraper lui-meme : si le marqueur se tait, le seau
reste soude au personnage pour toujours.

Le filet ne vit donc pas dans la boucle du geste -- elle, une nouvelle prise ou un respawn peut la couper. Il
tourne sur un `task.delay` independant : quoi qu'il arrive au geste, la repose part.

`PLACE_SETTLE` couvre l'autre bord : au tout premier passage, `TimePosition` peut encore lire zero alors qu'on
vient d'y ecrire la derniere image. Sans ce delai, le seau serait lache dans l'image qui suit l'appui.

### A faire dans Studio

Rien. Le geste inverse n'utilise que ce qui existe deja.

## 0.0.416 — Le marqueur de fin decide quand le seau passe en portage

`TakeAnimation` a maintenant un marqueur `EndTakeEventBin` en bout de geste. C'est lui qui declenche
`IdleAnimation`, la pose de portage.

### Ce que ce marqueur repare vraiment

La version precedente tenait la pose en avancant le temps de l'animation A LA MAIN (vitesse zero, TimePosition
ecrite image par image). Ca marchait, mais avec un doute signale a l'epoque : rien ne garantit qu'un marqueur
tire encore quand c'est nous qui ecrivons le temps.

La lecture redevient donc NORMALE, et les marqueurs tirent pour de vrai. La piste reste bouclee -- une piste non
bouclee se relache a sa derniere image, les bras retombent -- et c'est le marqueur qui la coupe avant qu'elle ne
reboucle.

A la fin : gel sur l'image courante, puis la pose de portage monte par-dessus en fondu croise.

### C'est l'animateur qui decide, plus une constante

Deplacer `EndTakeEventBin` dans l'editeur change la bascule sans toucher au code.

### Le filet de fin ne guette plus une fenetre

Un test "assez proche de la fin" peut etre SAUTE par un FPS bas : la piste reboucle au lieu de tenir. On
surveille donc le TEMPS RECULER. La piste etant bouclee, un marqueur muet la fait repartir a zero -- ce retour
en arriere est un fait, pas une fenetre a rater.

Meme famille que les autres filets du fichier : chaque marqueur en a un, parce qu'un marqueur muet voudrait dire
soit un seau qui ne se prend pas, soit un joueur fige sans pose de portage.

### Nettoyage

`TakeTestAnimation` a ete supprimee des assets. La ligne de `BinConfigs` qui proposait de la mettre a la place
de `TAKE_ANIM` part avec : un commentaire faux est pire que pas de commentaire.

### A faire dans Studio

Le marqueur `EndTakeEventBin` doit exister dans `TakeAnimation`. Rojo ne synchronise pas les animations : si le
nom differe d'un caractere, le filet prend le relais et la pose arrivera au rebouclage, donc plus tard que voulu.

## 0.0.415 — Le geste de prise du seau tient sa pose, et se joue face a l'objet

Deux defauts du portage precedent, tous deux visibles a l'ecran.

### Les bras retombaient a la fin du geste

`TakeAnimation` etait jouee avec `Looped = false`. Une piste non bouclee SE RELACHE a sa derniere image : les
bras revenaient vers la pose neutre, PUIS la pose de portage arrivait en fondu. Un aller-retour parasite, juste
au moment ou le seau se pose dans les mains.

La piste est maintenant bouclee -- et on lui retire tout moyen de reboucler : vitesse ZERO, et c'est le jeu qui
avance son temps image par image, avec un plafond a `Length - 0.001`. Elle joue une fois et elle TIENT. C'est la
recette deja notee dans le journal de CLAUDE.md, appliquee ici.

La pose de portage monte alors en FONDU CROISE pendant que le geste descend : a aucun instant les bras ne
repassent par la position neutre.

### Le marqueur n'est plus le seul declencheur

Quand c'est nous qui ecrivons `TimePosition`, rien ne garantit qu'un marqueur d'animation tire encore.
`TAKE_GRAB_FALLBACK` (0.45 s) demande la soudure si `TakeBucketEvent` se tait. Regle APRES le marqueur, donc
sans effet tant que celui-ci parle.

`TAKE_LOAD_TIMEOUT` couvre l'autre cas : une animation dont la duree reste a zero (asset jamais charge)
laissait le joueur sans pose de portage, sans la moindre erreur pour le dire.

### Le geste partait dos au seau

On pouvait appuyer sur `E` a 8 studs. Le joueur jouait sa prise sur place, bras dans le vide, pendant que le
seau lui sautait au torse depuis l'autre bout de la pelouse.

Le joueur PIVOTE maintenant face au seau en `FACE_TURN_TIME` (0.2 s), soit avant que la main se referme. Il est
fige pendant le geste, sinon il s'eloigne en plein mouvement et le pivot se bat contre ses touches.

AUCUN DEPLACEMENT N'EST FABRIQUE. Une marche forcee avait ete codee pour l'echelle -- priorite Camera, marqueurs
d'animation, secours par distance et par delai -- puis SUPPRIMEE : le joueur etait deja arrive, tout ce systeme
ne servait a rien. Meme conclusion ici.

Trois details qui evitent des bugs discrets :

- Seule la ROTATION est pilotee, la position reste vive. Lerper la CFrame entiere figerait aussi les
  coordonnees, et le joueur resterait colle en l'air s'il saute au meme instant.
- Fraction du temps ecoule, pas un lerp exponentiel : celui-ci n'atteindrait jamais sa cible et laisserait le
  joueur legerement de travers pour toujours.
- On ne fige JAMAIS quelqu'un en l'air (`FloorMaterial`) : ca se verrait bien plus que le probleme corrige. Et
  la part ancree est retenue nommement, pour etre rendue a son etat quoi qu'il arrive ensuite.

### A faire dans Studio

Rien de neuf. Le seau demande toujours un model prefixe `Bin` dans la MAP et le dossier
`Assets/Animations/Player/Tools/Bin` -- Rojo ne synchronise ni l'un ni l'autre.

### Note

L'entree 0.0.414 annonce le seau comme "pas branche dans la place TUTORIAL". C'est PERIME : le commit suivant
l'a branche, serveur et client. La ligne est laissee telle quelle (le CHANGELOG ne s'efface pas).

## 0.0.414 — On peut prendre et deplacer le seau

PORTAGE LIBRE, contrairement a l'echelle : aucun rail, aucun aimant vers une haie. On prend le seau, on se
balade ou on veut, on le repose ou on veut. Tout le systeme de focus de `LadderMoveController` est absent
ici, volontairement.

Nouveaux fichiers :

- `src/ReplicatedStorage/Modules/Configs/BinConfigs.luau` — data pure : prefixe du model, prise, detection,
  animations, repose.
- `src/ServerScriptService/Server/BinCarryService.luau` — autorite : desancre, soude, repose au sol.
- `src/StarterPlayerScripts/Client/BinCarryController.luau` — prompt, animations, declenchement.
- Remote `Bin/SetBinCarry` (phases `grab` / `place` / `release`).

SOUDURE AU MARQUEUR, pas a l'appui. L'echelle soude des l'appui : elle est enorme et le geste est rapide, le
saut ne se voit pas. Un seau pose par terre se teleporterait dans la main avant que la main l'atteigne. On
attend donc `TakeBucketEvent` (0.33 s). FILET : si le marqueur ne tire pas (asset pas charge a la 1re lecture
de la session), l'arret de la piste declenche quand meme la soudure, sinon le seau ne se prendrait pas DU TOUT.

LA REPOSE CHERCHE LE SOL. Le seau est porte DEVANT LE TORSE, donc en l'air. Le re-ancrer sur place, comme
fait l'echelle (portee au ras du sol), le laisserait FLOTTER a hauteur de poitrine. Le serveur lance donc un
rayon vers le bas devant le joueur et descend le seau jusqu'a ce que son point le plus bas touche. Ce point
est mesure APRES orientation, en projetant les trois axes de chaque part sur la verticale : une simple moitie
de `Size.Y` serait fausse des que le seau est pose de biais. Replis en cascade : sol devant, sinon sol sous le
joueur (bord de plateforme), sinon pose sans correction.

LA PRISE VIENT DU RIG, PAS D'UN REGLAGE A L'OEIL. `CARRY_C0` est la valeur relevee sur le rig d'animation par
`scripts/studio/VerifierBin.lua`. Le seau n'etant pas un outil de `ToolConfigs`, sa prise n'est calculee par
personne : c'est le placement fait dans l'editeur qui fait foi, et le jeu doit rejouer EXACTEMENT ce joint.
`JOINT_PARENT` et `CARRY_C0` vont ENSEMBLE : changer l'un sans l'autre donne n'importe quoi.

Limites connues :

- **La touche `E` est partagee avec la tondeuse.** Chacun ne branche la sienne que quand elle a un sens, mais
  un seau et une tondeuse poses cote a cote repondraient tous les deux. A trancher quand le cas se presentera.
- Le seau est soude au TORSE (`UpperTorso`), pas a la main : il ne suit donc pas le bras. Pour qu'il pende au
  bout du bras, refaire l'attache sur `RightHand` et reporter le nouveau `C0`.
- Pas branche dans la place TUTORIAL : une place secondaire n'herite de rien, il faudrait l'ajouter au bloc
  `PlaceId == PlacesConfig.TUTORIAL` ET copier le model dans sa map a la main.
- Un model de test nomme `Bintest` serait vu comme un vrai seau (la detection est par prefixe).

## 0.0.413 — Connecter Rojo en retard efface le code recent de Studio

Le collaborateur a connecte son `rojo serve` alors que son depot etait en retard. Studio a perdu l'herbe, la
tondeuse et le tuto recent, et repris l'ancienne version. Aucune erreur : juste un « Accepter » dans le plugin.

Rojo ne fusionne rien. Il pousse le disque LOCAL vers Studio et REMPLACE. Le dernier qui connecte gagne, avec sa
version a lui.

Reconnecter depuis un depot a jour a tout remis -- ce qui donne l'impression d'un bug fantome qui s'est repare
seul, alors que c'est le fonctionnement normal vu deux fois de suite.

### Ce qui est ecrit dans CLAUDE.md

- Ordre obligatoire pour tout le monde : `git pull --rebase origin main` PUIS `rojo serve`.
- Lire le diff du plugin avant d'accepter. S'il propose de SUPPRIMER des fichiers recents, on est en retard.
- Ne jamais publier la place juste apres avoir connecte Rojo sans avoir pull.

### Le vrai danger n'est pas la session Studio

Elle est reversible : une reconnexion a jour repare tout. PUBLIER dans cet etat, non -- l'ancien code part chez
les joueurs, et la aucune reconnexion Rojo n'y change quoi que ce soit. Il faut republier.

### Indice qui pointe droit sur la cause

Le CODE recule pendant que la MAP reste bonne. Rojo ne synchronise que `src/` : c'est sa signature.

### Deux personnes, deux roles

CLAUDE.md decrit maintenant le role du COLLABORATEUR, en plus de celui de Meox : pull en debut de session avant
meme de lire du code, jamais de raisonnement sur un fichier local non actualise, meme regle de push et de
numerotation du CHANGELOG. Il se declare par une ligne dans `CLAUDE.local.md` (ajoute au `.gitignore`) ou dans
sa memoire perso.

## 0.0.412 — Un script pour accrocher n'importe quel objet a un rig

Entree ecrite apres coup : le script etait pousse (commit 08951ef) sans sa ligne de CHANGELOG.

`scripts/studio/AttacherObjetAuRig.lua` accroche n'importe quel objet a la main d'un rig pour pouvoir l'ANIMER
avec lui. Le rateau, une brouette, un arrosoir.

### Pourquoi un deuxieme script

`AttacherOutilAuRig.lua` REPRODUIT un calcul du jeu : il rejoue la prise que `ToolService.applyGrip` fabrique a
partir de `ToolConfigs`. Il ne vaut donc que pour un objet DECLARE la-dedans -- aujourd'hui le taille-haie, et
lui seul.

Pour un objet qui n'est pas encore un outil, personne ne calcule la prise : le placement fait a la main EST la
source de verite. Le nouveau script la fige, point.

Prendre le mauvais coute une animation entiere : poser a l'oeil un outil dont le jeu calcule la prise donne des
poses justes dans l'editeur et fausses en jeu. C'est ecrit en tete des deux fichiers.

### Ce qu'il fait

- Cree un Motor6D nomme comme l'objet, donc visible en piste dans l'editeur d'animation.
- Desancre TOUT l'objet : une part ancree ignore son Motor6D, en silence.
- Detruit un joint precedent du meme nom, sinon Roblox melange deux pistes identiques.
- Detecte un rig SKINNE (`Bone`) et explique pourquoi un Motor6D ne peut pas s'y accrocher.

### A savoir avant d'animer

Le jour ou le rateau devient un vrai outil declare dans `ToolConfigs`, les animations faites ici seront a
refaire avec l'autre script.

## 0.0.411 — Un nom d'effet peut designer l'EMETTEUR ou CE QUI LE CONTIENT

L'avertissement du commit precedent a repondu tout seul :

    Emetteur(s) introuvable(s) : Wind. Presents : Smoke2, Leafs, Debris, debris, ParticleEmitter.

`Wind`, `LeafCutEffectsLeft` et `LeafCutEffectsRight` sont des PARTS, pas des emetteurs. C'est ainsi qu'on
construit un effet dans Studio : une part posee au bon endroit, une Attachment dedans, et les ParticleEmitter au
fond. Ce sont la part et l'attachment qui portent un nom parlant ; les emetteurs s'appellent "Leafs" ou
"ParticleEmitter".

Chercher un emetteur DU NOM demande ne trouvait donc rien, alors que tout etait deja en place.

### Chaque emetteur est indexe sous SON nom et sous celui de ses parents

Demander `Wind` rend tout ce qui souffle dans la part `Wind`, sans avoir a connaitre le nom des emetteurs.

C'est aussi le bon reflexe pour la suite : nommer le CONTENEUR fait suivre automatiquement tout emetteur qu'on
ajoutera dedans. Nommer les emetteurs un par un aurait oblige a revenir toucher la config a chaque ajout.

### L'avertissement se pose PAR NOM

Il etait pose une seule fois pour toutes : le premier manquant masquait les autres. C'est d'ailleurs pour ca que
le message ne parlait que de `Wind` alors que les trois manquaient.

## 0.0.410 — L'herbe coupee remonte de beaucoup moins loin

`CUT_RISE_DEPTH` : 1 -> 0.35. La touffe partait ENTIEREMENT sous la surface, donc le trajet etait long et on
voyait clairement quelque chose sortir du sol.

C'est un contresens sur le role de cet effet : le but n'est PAS de montrer une pousse, c'est de CACHER un
remplacement de maillage. Plus le trajet est court, mieux il fait son travail.

A zero il ne cacherait plus rien -- mais entre les deux, il n'y a rien a admirer : ce mouvement doit passer
inapercu, pas etre reussi.

## 0.0.409 — Les emetteurs introuvables se signalent, et listent ce qui EXISTE

Le code qui allume les particules etait bien en place depuis le 0.0.397. Mais un nom d'emetteur qui ne correspond
a rien donnait exactement le meme resultat qu'un effet coupe : RIEN. On cherche alors le probleme dans le code,
dans les conditions, dans les particules elles-memes -- partout sauf dans le nom.

L'avertissement dit maintenant :

- les noms attendus qui n'ont PAS ete trouves ;
- et la liste des emetteurs REELLEMENT presents dans le modele.

C'est ce deuxieme point qui compte. Un message qui dit seulement "introuvable" oblige a aller comparer a la main
dans Studio ; celui-ci contient la reponse. S'il affiche "Presents : AUCUN", c'est que les emetteurs ne sont pas
sous le modele de la tondeuse -- une autre question, mais une question NETTE.

Meme regle que les zones d'herbe et les animations d'ambiance : un systeme qui balaye doit dire ce qu'il n'a pas
trouve, et NOMMER plutot que compter.

## 0.0.408 — Le degrade de l'etiquette TIPS passe a la verticale

`TIPS_LABEL_SHADE_ROTATION` : 0 -> 90.

Le ressaut de la sequence tombe donc a mi-HAUTEUR des lettres : le mot s'eclaircit du haut vers le bas, ce qui se
lit comme une lumiere posee dessus plutot que comme un balayage lateral.

## 0.0.407 — La touffe sort de terre TOUT DE SUITE, et se couche apres

Un defaut introduit par le temps mort du 0.0.405, et il etait pire qu'il n'en avait l'air.

### La touffe restait ENFOUIE pendant l'attente

La sortie de terre et l'abaissement partageaient le meme compteur. En retardant ce compteur, on a retarde les DEUX :
pendant les 0.35 s de temps mort, la touffe restait donc sous la surface -- invisible.

Le joueur voyait un TROU dans la pelouse derriere la machine, puis l'herbe remonter. L'inverse exact de l'effet
cherche, qui etait justement de ne PAS voir le remplacement.

### Deux compteurs, deux moments

Ils n'ont rien a voir l'un avec l'autre :

- **Sortir de terre** doit etre immediat et bref (`CUT_RISE_UP_TIME`, 0.15 s). C'est le remplacement du maillage :
  il ne doit PAS se voir.
- **Se coucher** doit venir apres le temps mort et prendre son temps. C'est la coupe : elle, doit se voir.

Quatrieme fois aujourd'hui qu'un reglage partage forcait a sacrifier un besoin pour l'autre -- apres la hauteur et
l'emprise de l'herbe tondue, l'arrivee et le retour de la camera, le delai et la vitesse de la coupe.

Le motif est assez net pour en faire une regle : quand un reglage sert DEUX moments differents, il finira par les
opposer.

## 0.0.406 — La touffe tombe plus tard, mais tombe plus vite

- `CUT_RISE_DELAY` : 0.18 -> **0.35**. Elle tient plus longtemps apres le passage de la lame.
- `CUT_RISE_TIME` : 0.9 -> **0.45**. Une fois lancee, elle descend et sort du sol deux fois plus vite.

Les deux vont dans des sens opposes, et c'est exactement ce qu'il fallait : l'un dit QUAND ca commence, l'autre a
quelle VITESSE ca se fait. "Ca se couche trop tot" se regle avec le DELAI ; "ca se couche trop lentement" avec la
duree. Les confondre aurait force a sacrifier l'un pour l'autre.

C'est pour ca qu'ils ont ete separes des le depart -- meme raison que la hauteur et l'emprise de l'herbe tondue,
ou que les deux allures de la tondeuse.

### On approche de la limite du delai

Au-dela d'une demi-seconde, on voit la machine passer et l'herbe tomber loin DERRIERE elle. Ca cesse de se lire
comme une coupe et ca ressemble a un retard d'affichage.

## 0.0.405 — L'herbe tient un instant avant de se coucher

`CUT_RISE_DELAY` (0.18 s) : la lame passe, la touffe tient encore, puis elle descend.

C'est ce court retard qui fait la difference entre "l'herbe s'eteint sous la machine" et "la machine coupe
l'herbe". Sans lui la coupe est SIMULTANEE au passage, donc elle se lit comme un interrupteur.

Il doit rester court : au-dela d'une demi-seconde, on voit la machine passer et l'herbe tomber APRES elle, ce qui
ressemble a un retard d'affichage.

### Le piege du temps mort

Pendant l'attente, RIEN ne change sur la touffe. Le pave se serait donc declare au repos, aurait cesse d'etre mis a
jour, et le compte a rebours ne se serait jamais ecoule : la touffe serait restee debout POUR TOUJOURS.

Le temps mort compte donc comme du MOUVEMENT. Meme piege qu'un `return` pose sur "rien a faire pour l'instant" --
ce n'est pas parce qu'il n'y a rien a dessiner qu'il n'y a rien a faire.

## 0.0.404 — On n'entre plus en vue subjective tout seul

Le joueur arrive en vue de dos, et bascule avec `C` s'il le veut.

Demarrer en vue subjective etait le comportement d'origine. Retire : c'est un CONFORT, pas une regle du jeu.
L'imposer a l'arrivee decide a la place du joueur sur une preference tres personnelle -- et celui qui ne la
supporte pas doit d'abord DEVINER qu'une touche existe pour en sortir.

Une preference ne s'impose pas, elle s'offre.

`START_IN_FIRST_PERSON` permet de retrouver l'ancien comportement. L'attente du rideau de chargement reste
attachee a ce chemin-la : elle n'a de sens que si l'on prend la souris automatiquement.

## 0.0.403 — L'axe de rotation des roues se DEDUIT de leur forme

Les roues ne tournaient toujours pas visiblement. Les joints etaient bien trouves depuis le 0.0.332 -- restait
l'AXE, qui etait ecrit en dur ("X") et qu'il fallait tatonner entre trois valeurs.

### Une roue a une forme de roue

LARGE x LARGE x MINCE. Son axe de rotation est donc forcement le cote le plus MINCE -- c'est ce qui en fait une
roue et pas un disque qu'on ferait tourner a plat.

`WHEEL_AXIS = "AUTO"` le deduit de la taille de la part. Deux avantages sur les trois essais a l'ecran :

- On ne tatonne plus, et on ne se trompe pas de piste : une roue qui tourne sur le mauvais axe RESSEMBLE a une
  roue qui ne tourne pas.
- Ca survit a un re-export : si le rig change d'orientation dans Blender, la deduction suit toute seule.

L'axe reste imposable ("X", "Y", "Z") pour une piece qui n'aurait pas des proportions de roue.

Meme famille que le rayon, deja MESURE sur la part plutot que regle a la main : tout ce qu'on peut lire sur le
modele n'a pas a etre recopie dans une config, ou il finira par diverger.

## 0.0.402 — Le son de reussite s'entend enfin, et le moteur s'y enchaine

`SucessTryLaunchSound` semblait ne pas jouer. Il jouait -- la boucle moteur partait a l'instant meme ou le moteur
prend, c'est-a-dire par-dessus lui.

### La boucle attend la FIN du son de reussite

Elle la rejoint en CHEVAUCHANT, `RUN_SOUND_OVERLAP` (0.4 s) avant la fin.

Avant la fin et pas apres, et c'est le point : deux sons colles bout a bout laissent un silence d'une image ou
deux, et ce silence s'entend PLUS que la transition elle-meme. En se recouvrant, ils ne laissent aucune couture.

L'attente est CALCULEE sur le son lui-meme (`TimeLength - TimePosition`), pas devinee : changer le fichier dans
Studio ne demande donc pas de revenir regler un delai -- meme raison que le marqueur d'animation qui a remplace le
delai du cabrage.

### Ce qui ne bouge PAS

L'attribut "moteur en marche" est pose IMMEDIATEMENT. Le deplacement et la coupe ne doivent pas attendre un son :
seule la BOUCLE est retardee.

Et le delai verifie que le joueur porte ENCORE la machine a l'echeance -- il a pu la reposer entre-temps, et une
boucle moteur sur une tondeuse posee au sol tournerait toute seule.

## 0.0.401 — Les sons sont precharges dans les lieux qui affichent le rideau

Ils ne l'etaient pas. Le premier son d'une session partait donc en retard, ou pas du tout.

### Un trou ouvert par un `return`

L'ecran de chargement PRINCIPAL precharge deja tout : il balaye ReplicatedStorage, StarterGui et SoundService.
Mais le RIDEAU -- celui des lieux qui ne sont pas le hub -- sort par un `return` bien avant ce code.

Le tuto, et demain les jardins de clients, n'avaient donc AUCUN son precharge. C'est exactement la ou vit la
tondeuse.

Symptome : le PREMIER coup de corde sonne creux. Le moment ou il ne faut surtout pas -- c'est lui qui doit donner
l'impression d'avoir demarre la machine soi-meme.

### Le rideau a dix secondes a ne rien faire

Autant s'en servir. Le prechargement tourne en tache de fond pendant que le rideau s'anime, et on le laisse FINIR
meme si le rideau part avant : un son precharge trop tard reste precharge.

Il annonce son compte dans la console -- un prechargement muet ne se distingue pas d'un prechargement absent.

### Ce que ca ne couvre pas

Le serveur, lui, ne prechargeait que les ANIMATIONS de la tondeuse, et c'est normal : le prechargement vaut par
MACHINE. Un son charge sur le serveur n'aide aucun joueur a l'entendre a l'heure.

## 0.0.400 — La camera revient derriere le joueur en douceur

`PULL_CAM_OUT_TIME` : 0.2 -> 0.6. L'arrivee, elle, ne bouge pas.

### Les deux ne font pas le meme travail

On ARRIVE parce qu'on veut y etre : tout ce qui traine avant de pouvoir agir se subit -- c'est pour ca que
l'arrivee a ete raccourcie trois fois.

On REPART parce qu'on rend la main au joueur. Une vue qui claque derriere lui donne l'impression d'avoir rate
quelque chose, alors qu'il ne s'est rien passe. A 0.2 s la camera SAUTAIT derriere lui au lieu d'y revenir.

Meme asymetrie que le volet du rideau de chargement : couvrir vite (ca cache), decouvrir lentement (ca montre).
Une duree unique pour les deux sens aurait force a choisir lequel sacrifier.

## 0.0.399 — Le coup de corde qui REUSSIT sonne different, et il sonne AU MOMENT du geste

Trois sons, et une sequence :

- `TryLaunchSound` a chaque coup qui RATE ;
- `SucessTryLaunchSound` sur le coup qui VA reussir, a sa place ;
- `IdleLawnMowerSound` en boucle ensuite. (L'ancien nom cherche, `IdleSound`, n'existait pas -- c'est ce que
  l'avertissement du commit precedent a permis de voir tout de suite.)

### Pourquoi il sonne PENDANT le tirage et pas apres

C'est toute la difference entre "le moteur a demarre" et "JE l'ai demarre". L'oreille entend la prise pendant que
le bras tire encore, donc elle l'attribue au GESTE. Le meme son une seconde plus tard en ferait une consequence du
hasard -- et le joueur n'aurait plus l'impression d'y etre pour quelque chose.

C'est le meme principe que la secousse posee a l'instant de l'appui plutot qu'au retour du serveur : un retour qui
arrive apres coup ne se ressent plus comme la consequence de son propre geste.

### Rien a deviner

Le serveur sait depuis le depart combien de coups il faut, et il compte ceux qui sont termines. Le coup en cours
est donc le suivant : une comparaison suffit a savoir s'il est le bon.

## 0.0.398 — Les sons de la tondeuse remplacent ceux du taille-haie

`SOUND_FOLDER` pointe sur `Sounds/Engins/LawnMower`. Le code ne connait que des NOMS, donc changer de sons ne
demande de toucher qu'a ce bloc -- c'etait prevu depuis l'emprunt.

### Et il DIT ce qu'il n'a pas trouve

L'avertissement existait deja, mais avec un seul drapeau global : un dossier correct et un NOM de son faux ne se
signalaient qu'une fois. On corrigeait le premier, et le deuxieme restait muet.

Il est maintenant pose PAR NOM manquant. Chaque son absent se signale une fois, avec le nom ET le dossier exacts
qu'il a cherches -- il n'y a donc rien a deviner, il suffit de comparer a l'arborescence de Studio.

Une fois par PRISE, en revanche, remplirait la console : c'est le juste milieu entre "muet" et "illisible".

### Ce qui reste a faire

Le joueur veut des sons qui se CHEVAUCHENT (le demarrage qui se fond dans le regime, la coupe par-dessus le
moteur). Aujourd'hui il n'y a que deux sons, joues l'un apres l'autre : un pour le tirage, une boucle pour le
moteur dont la hauteur suit le regime. Le melange viendra apres.

## 0.0.397 — Du VENT quand on avance, des BRINS D'HERBE quand on coupe

Deux groupes de ParticleEmitter poses dans Studio, pilotes par ce que la machine fait vraiment.

- `Wind` : souffle tant que la machine AVANCE, moteur en marche. Une tondeuse a l'arret ne souffle pas, une
  tondeuse eteinte encore moins.
- `LeafCutEffectsRight` / `LeafCutEffectsLeft` : ne partent que quand on coupe VRAIMENT.

### La coupe est mesuree, pas supposee

`mowAt` rend deja le nombre de touffes REELLEMENT coupees cette image. On s'en sert : passer une tondeuse allumee
sur du beton ne projette rien. C'est cette exactitude qui fait qu'on croit a l'effet -- des brins qui volent au
mauvais moment se remarquent immediatement.

### Un delai, sinon ca clignote

La coupe est intermittente d'une image a l'autre : un trou dans l'herbe, une touffe deja tondue, et le compte
retombe a zero. Sans `CUT_EMITTER_HOLD` (0.25 s), l'emetteur s'allumerait et s'eteindrait plusieurs fois par
seconde.

### Deux precautions

- **Les emetteurs sont cherches une fois et memorises.** Parcourir les descendants du modele a chaque image
  couterait pour rien, et on n'ecrit que sur CHANGEMENT d'etat.
- **Ils sont ETEINTS a la repose.** Ils vivent sur le MODELE, pas sur le portage : une machine reposee aurait garde
  son vent et ses brins en vol pour toujours.

### Cote Studio

Les emetteurs doivent porter ces noms exacts et vivre sous le modele de la tondeuse. Rojo ne synchronise pas le
Workspace : a recopier dans chaque lieu. Un nom introuvable n'est pas une erreur -- c'est une facon valable de
couper l'effet.

## 0.0.396 — Le joystick redevient DYNAMIQUE, et tombe enfin sous le doigt

Il se pose exactement la ou le doigt touche. Le repli en position fixe est annule : ce n'etait qu'un contournement
du vrai probleme.

### Le repere, apres cinq tentatives

`InputObject.Position` est exprimee dans le repere d'un ScreenGui ORDINAIRE -- celui dont l'origine est SOUS la
barre Roblox du haut.

Notre interface ignorait l'inset (`IgnoreGuiInset = true`), donc son origine etait au coin ABSOLU de l'ecran. Tout
se retrouvait decale de la hauteur de cette barre. Et la "correction" ajoutee au 0.0.390 allait dans le mauvais
sens, ce qui a double l'ecart.

Le correctif tient en une suppression : on ne touche plus a l'inset.

### La preuve etait lisible depuis le debut

Le `TouchThumbstick` de Roblox est fourni en SOURCE, et il est forke dans l'autre projet du joueur. Son TouchGui ne
touche pas a l'inset, et il utilise `inputObject.Position` DIRECTEMENT comme offset. C'est la preuve du repere.

Quatre tentatives de le DEDUIRE ont echoue. Dix minutes de lecture auraient suffi.

La regle est desormais au journal : quand un comportement d'input surprend, lire le PlayerModule bat n'importe quel
raisonnement.

## 0.0.395 — Le joystick ne marchait "que parfois" : trois erreurs d'evenement tactile

Reponses trouvees en lisant le thumbstick de Roblox lui-meme, forke dans l'autre projet du joueur. C'est la
reference : autant partir de ce qui marche deja plutot que de re-deriver.

### 1. Un autre doigt volait le joystick

Le code de Roblox porte ce commentaire :

> *A touch that starts elsewhere on the screen will be sent to a frame's InputBegan event if it moves over the
> frame.*

L'`InputBegan` d'un element recoit donc AUSSI les doigts qui ont commence AILLEURS et qui glissent dessus. Le doigt
qui tourne la camera etait pris pour le joystick des qu'il passait au-dessus de la zone -- et comme il n'avait pas
commence la, le bouton restait plante au centre.

C'est CA, le "parfois ca marche pas" : ca dependait entierement du trajet de l'autre pouce.

Le test `UserInputState == Begin` regle la question.

### 2. `TouchMoved` et pas `InputChanged`

C'est l'evenement dedie au tactile, et le seul qui tire de facon fiable pour un doigt dont le geste a commence SUR
un element d'interface -- exactement notre cas, puisque la zone est un bouton.

Meme chose pour la fin : `TouchEnded`.

### 3. Le menu Roblox vole le doigt

Quand il s'ouvre, le toucher en cours ne se termine JAMAIS. Sans filet, on ressort du menu avec le joystick colle a
fond et le personnage qui part tout seul. `GuiService.MenuOpened` le relache.

### La lecon

Roblox fournit son PlayerModule en source. Quand un comportement d'input surprend, la reponse y est ecrite -- et
elle est plus fiable que n'importe quel raisonnement. Trois des quatre echecs de la veille auraient ete evites en
allant le lire d'abord.

## 0.0.394 — Le panneau de diagnostic s'eteint, et deux lecons entrent au journal

`STEER_DEBUG_INPUT` repasse a false : la question est tranchee, le panneau n'a plus rien a montrer. Il reste en
place, eteint -- c'est un outil de mesure, il resservira.

Deux entrees ajoutees au journal de CLAUDE.md, parce que les deux ont coute cher :

- **Le thumbstick tactile de Roblox se tait des qu'une feature prend la camera.** Constate sur la haie, re-paye
  entierement sur la tondeuse alors que la reponse etait deja ecrite dans un fichier voisin.
- **Convertir une position de doigt en position d'interface est un pari a 50 %.** Quatre tentatives, dont deux qui
  ont aggrave le decalage. La sortie n'est pas de trouver le bon signe, c'est de ne plus avoir a convertir.

## 0.0.393 — Le joystick devient FIXE : on supprime le probleme au lieu de le corriger

Il se posait a cote du pouce sur tous les ecrans. QUATRE tentatives de recaler les coordonnees ont echoue, dont
deux qui ont AGGRAVE le decalage.

### Le probleme n'etait pas le reglage, c'etait l'APPROCHE

Convertir une position de doigt en position d'interface demande de savoir laquelle des deux compte la barre du
haut -- et ca ne se deduit pas. Chaque tentative etait un pari a 50 %, et j'en ai perdu plusieurs de suite.

En posant le joystick a une place FIXE, exprimee en fraction d'ecran, il n'y a plus AUCUNE conversion. La place est
juste sur tous les formats par construction, sans une ligne de calcul.

Et le bouton ne suit que le DELTA du doigt. Une DIFFERENCE annule n'importe quel decalage de repere sans avoir a le
connaitre : peu importe d'ou l'on compte, l'ecart entre deux points du meme repere est le meme.

### Ce que ca change pour le joueur

Il pose son pouce n'importe ou dans la zone du bas ; c'est le MOUVEMENT qui compte, pas l'endroit. Le dessin, lui,
reste toujours au meme endroit -- ce que font d'ailleurs la plupart des jeux mobiles, et qui a l'avantage de
s'apprendre en une seconde.

Le rayon, lui, reste proportionnel a la hauteur d'ecran : sur une tablette un rayon en pixels serait minuscule,
sur un petit telephone il sortirait de l'ecran.

### La lecon

Quand une correction echoue plusieurs fois de suite sur le meme point, ce n'est pas la valeur qui est fausse,
c'est la question. Ici la bonne question n'etait pas "de combien recaler" mais "comment ne plus avoir a recaler".

## 0.0.392 — L'ecart entre reperes d'ecran est MESURE, plus deduit

Le joystick apparaissait loin du pouce. Deux tentatives de le recaler au raisonnement ont echoue, dont une qui a
AGGRAVE le decalage.

### On arrete de raisonner

`InputObject.Position` et `UserInputService:GetMouseLocation()` ne partent pas forcement du meme coin de l'ecran,
et le sens de la difference ne se DEDUIT pas. Ce projet l'a paye trois fois : `GetMouseLocation`, `WorldAnchor`,
et ici.

Au moment ou le doigt se pose, les deux valeurs designent le MEME point physique. Leur difference EST donc le
decalage, quel qu'il soit. On la mesure une fois, a la prise, et on l'applique.

Le resultat est juste sur n'importe quel appareil, sans rien a regler et sans savoir laquelle des deux valeurs
inclut la barre du haut.

### Pourquoi viser le repere de GetMouseLocation

C'est celui du CURSEUR CUSTOM du jeu, qui tombe au bon endroit depuis toujours -- c'est d'ailleurs a lui que le
joueur a compare pour montrer l'ecart. On se cale sur ce qui est deja prouve a l'ecran plutot que sur ce qui
devrait marcher.

### L'ecart est celui du BON doigt

Il est mesure a la prise et GARDE, au lieu d'etre relu pendant le glissement : sinon un deuxieme doigt pose sur
l'ecran (pour tourner la camera) changerait la reference en plein mouvement, et le joystick sauterait.

## 0.0.391 — Retour en arriere : la correction d'inset DEPLACAIT le joystick

L'ajout du 0.0.390 est retire. Il ne recalait rien : il decalait.

`InputObject.Position` est deja dans le repere ABSOLU de l'ecran -- le meme que `GetMouseLocation`, et le meme que
cette interface, qui ignore l'inset. Il n'y avait donc RIEN a convertir, et ajouter la hauteur de la barre a
introduit l'ecart au lieu de le corriger.

L'`AnchorPoint` des deux cercles etait deja a 0.5, 0.5 : ce n'etait pas la non plus.

### La lecon, pour la troisieme fois

Le sens de ces conversions ne se DEDUIT pas, il se VERIFIE a l'ecran. Ce projet l'a paye sur `GetMouseLocation`,
puis sur `WorldAnchor`, et maintenant ici. J'ai raisonne au lieu de mesurer, et j'ai ajoute un bug a un bug.

La marche a suivre est ecrite sur place : si le joystick reste decale, le signe est l'autre -- il faut RETRANCHER
l'inset, des DEUX cotes. Jamais d'un seul : un delta calcule entre deux reperes differents part deja incline.

## 0.0.390 — Le joystick apparait pile sous le pouce

Il se posait a cote du doigt, decale vers le haut.

### L'inset de la barre Roblox, encore

`InputObject.Position` est mesuree SOUS la barre du haut. L'interface du joystick, elle, IGNORE l'inset : son coin
(0, 0) est le coin ABSOLU de l'ecran. Les deux ne partent donc pas du meme endroit, et l'ecart vaut exactement la
hauteur de la barre -- assez pour que le joystick ne tombe pas sous le pouce.

Meme famille que le piege `GetMouseLocation` / `ScreenPointToRay` deja au journal, et que celui de `WorldAnchor`.
Ce projet l'a maintenant paye trois fois.

### Relu a CHAQUE prise

Et pas mesure une fois au demarrage : la barre change de hauteur (rotation d'ecran, encoche, interface Roblox qui
s'adapte), et une valeur figee au boot se retrouverait fausse sans que rien ne le dise.

La meme correction est appliquee des DEUX cotes -- a la prise et pendant le glissement. Un delta calcule entre
deux reperes differents serait faux d'un decalage constant, donc le joystick partirait deja incline.

## 0.0.389 — Un JOYSTICK a nous, partage, pour toutes les features qui prennent la camera

Nouveau `Modules/UI/Core/MoveThumb`. La tondeuse l'allume tant qu'on la pousse.

### La cause etait deja documentee dans le projet

Le travail de la haie avait rencontre EXACTEMENT ce probleme, et son commentaire le dit :

> "Dans l'etat de travail la camera passe en Scriptable ; le thumbstick tactile PAR DEFAUT cesse alors de remonter
> un move vector (GetMoveVector rend 0)"

Le thumbstick de Roblox se tait des qu'une feature prend la camera en main. Sur mobile le joueur ne peut alors
plus bouger du tout -- et rien ne le signale : l'input arrive bien au jeu, il n'arrive juste plus jusqu'a nous.

La tondeuse prend la camera. Deux corrections ont ete tentees a cote avant qu'on remonte a la cause -- le
verrouillage de souris, la detection d'appareil -- alors que la reponse etait ecrite dans un fichier voisin.

### Un MODULE, pas une deuxieme copie

La meme logique a deux endroits finit toujours par diverger sur l'un des deux. Le joystick est donc sorti en
module partage : la prochaine feature qui prend la camera n'aura qu'a l'allumer.

Il est DYNAMIQUE (il apparait la ou le doigt se pose) et ne mesure que le DELTA depuis le point de contact, ce qui
le rend insensible a l'inset de la barre Roblox -- le decalage se simplifie.

Trois details qui evitent des bugs :

- **La zone d'ecoute est invisible et large, les cercles ne sont QUE du dessin.** Si le dessin avalait l'input, un
  doigt pose pile dessus serait ignore par la zone et le joystick ne partirait jamais.
- **La fin du toucher s'ecoute au niveau du SERVICE, pas du bouton.** Un doigt qui glisse hors de la zone avant de
  se lever ne declencherait jamais l'evenement du bouton, et le joystick resterait colle a fond pour toujours.
- **Le rayon est en fraction de la hauteur d'ecran**, pas en pixels : sur une tablette un rayon en pixels serait
  minuscule, sur un petit telephone il sortirait de l'ecran.

### Reste a faire

`HedgeController` garde sa propre copie. Elle marche, et la migrer maintenant risquerait de casser une feature qui
va bien pour reparer une autre. A faire quand la tondeuse sera validee -- c'est note ici pour que la duplication ne
devienne pas invisible.

## 0.0.388 — L'input de deplacement a une deuxieme source

`ControlModule:GetMoveVector()` rend ZERO sur l'appareil tactile teste -- mesure a l'ecran, joystick pousse a
fond. Le deplacement avec la tondeuse etait donc impossible.

### On arrete de chercher POURQUOI

Deux corrections ont deja ete tentees a cote (le verrouillage de souris, la detection d'appareil). La bonne
question n'est pas "pourquoi cette source est vide" mais "existe-t-il une autre source de la meme information".

Oui : `humanoid.MoveDirection`. Roblox le remplit lui-meme quel que soit le controleur -- doigt, clavier,
manette. Il devient le premier secours, avant le secours clavier qui existait deja.

### Deux precautions

- **Repere.** `MoveDirection` est en repere MONDE, alors que tout le reste attend du repere CAMERA (la convention
  de `GetMoveVector`). On le ramene donc dans le repere de la camera, a plat -- melanger deux reperes est un piege
  deja paye sur la conduite de cette meme tondeuse.
- **Instant de lecture.** L'en-tete de ce fichier dit que `MoveDirection` ne reflete plus l'intention du joueur des
  qu'on contraint le deplacement. C'est vrai APRES notre appel a `Move` ; on le lit AVANT, sur la meme image. A cet
  instant il porte encore la demande du module de controle de Roblox.

Le risque theorique -- si Roblox cessait d'appeler `Move`, la valeur resterait la NOTRE et la machine partirait
toute seule -- est ecarte par l'observation : le joueur marche normalement sans la tondeuse, donc le controleur
tourne bien.

## 0.0.387 — On ne verrouille plus une souris qui n'existe pas

Le joystick tactile ne remontait RIEN : impossible de bouger avec la tondeuse sur mobile.

### Ce que la mesure a donne

    input 0.00 , 0.00   |  vitesse 6.0  |  moteur ON  |  tactile oui

Trois valeurs sur quatre etaient bonnes. Le serveur autorisait le deplacement, le moteur tournait, l'appareil
etait bien reconnu -- seul l'input etait mort. Sans ce panneau, les trois corrections auraient ete tentees une par
une.

### La cause

La vue subjective forcait `MouseBehavior = LockCenter` A CHAQUE IMAGE, y compris sur un telephone. Verrouiller
une souris qui n'existe pas casse les controles TACTILES de Roblox : le joystick cesse de remonter quoi que ce
soit.

C'est un defaut introduit avec la vue subjective, qui n'a jamais ete testee sur mobile -- et elle est active
partout HORS du hub, donc exactement la ou se trouve la tondeuse.

### Le test : `MouseEnabled`, pas `TouchEnabled`

C'est la question exacte qu'on se pose : y a-t-il une souris a verrouiller ?

Un PC a ecran tactile a les DEUX, et sa souris doit rester verrouillee. Un telephone n'a que le tactile. Tester la
presence du TACTILE aurait donc casse la vue subjective sur les PC tactiles -- on aurait echange un bug contre un
autre.

Sans souris, le controller ne touche plus ni au curseur, ni au verrouillage, ni a l'ecart de camera. Il n'y a rien
a y faire.

## 0.0.386 — Le diagnostic de la tondeuse passe A L'ECRAN

Le probleme n'existe QUE sur mobile, et sur un telephone la console n'est pas lisible. Un diagnostic qu'on ne peut
pas lire la ou le bug se produit ne sert a rien -- c'est pour ca que le precedent n'a rien donne.

Un panneau en haut de l'ecran affiche donc les quatre valeurs qui separent les trois causes possibles :

- **input** : ce que la conduite recoit du joystick. A `0.00 , 0.00` alors qu'on pousse, l'input n'arrive pas.
- **vitesse** : la WalkSpeed reelle. A `0.0`, le serveur bloque le deplacement.
- **moteur** : ON ou OFF, tel que le CLIENT le voit. A OFF alors que la machine tourne, l'attribut ne remonte pas.
- **tactile** : confirme qu'on est bien reconnu comme mobile.

Ces trois causes donnent exactement le meme symptome a l'ecran et se corrigent a trois endroits differents. Les
essayer une par une couterait trois allers-retours ; les mesurer en coute zero.

Le panneau n'avale AUCUN input : pose par-dessus le joystick tactile, il empecherait justement de bouger, et on
croirait avoir aggrave le bug qu'on mesure.

A retirer avec `STEER_DEBUG_INPUT` une fois la question tranchee.

## 0.0.385 — L'herbe lointaine disparait sur mobile, et un diagnostic pour la tondeuse

### L'herbe lointaine est RETIREE (mobile uniquement)

Au-dela de 90 studs du bord d'une zone, toute son herbe sort de l'affichage. En dessous, elle revient.

**On retire, on ne DETRUIT pas.** Un seul changement de parent sur le dossier fait disparaitre des milliers de
parts d'un coup, et les rend tout aussi vite. Detruire obligerait a REFAIRE le semis en revenant -- des milliers
de creations etalees sur plusieurs secondes, exactement l'a-coup qu'on cherche a eviter. La memoire n'est de
toute facon pas le probleme (866 Mo mesures sur 1300 disponibles) : c'est le CPU.

Mobile SEULEMENT : sur PC la pelouse lointaine ne coute presque rien et fait partie du decor. Voir un jardin
entier de loin, c'est ce qui donne envie d'y aller.

90 studs, c'est bien au-dela du rayon d'animation (14 sur mobile) : l'herbe est deja immobile depuis longtemps
quand elle disparait, donc on ne voit jamais le basculement.

### Le piege que ca ouvrait

Le nettoyage et le re-semis cherchaient le dossier PAR SON NOM sous la zone. Deparente, il devenait introuvable :
un re-semis aurait laisse l'ancien jeu de touffes derriere lui, et l'arret aurait laisse des milliers de parts
vivre hors du monde pour le reste de la session. Les deux passent maintenant par la reference gardee sur la zone.

### Diagnostic d'input pour la tondeuse

La machine ne bouge pas sur mobile. TROIS causes possibles donnent exactement le meme symptome, et se corrigent a
trois endroits differents : l'input n'arrive pas, le moteur n'est pas vu comme demarre, ou la vitesse est a zero.

`STEER_DEBUG_INPUT` affiche les trois, deux fois par seconde. On mesure au lieu de parier -- trois corrections a
l'aveugle couteraient plus cher qu'une mesure.

A REPASSER A FALSE une fois la question reglee : ca imprime en continu.

## 0.0.384 — On n'anime plus l'herbe qui est dans le dos du joueur

Mesures apres le profil mobile : 37 ms par image, avec des pics a 82. C'est du CPU -- la memoire et le reseau
vont bien. A 37 ms on est a 26 images par seconde, sous le seuil des 45 ou le joueur sent que "ca repond mal"
sans savoir le nommer.

### La nuance qui compte

Roblox ne DESSINE deja pas ce qui est derriere la camera. L'idee de cacher l'herbe n'aurait donc rien gagne cote
rendu.

Ce qui coutait, c'est NOTRE boucle : elle calculait le vent, l'ecrasement et la couleur de touffes situees dans
le dos du joueur, pour un resultat que personne ne verra jamais.

### Le test se fait par PAVE, pas par touffe

Un produit scalaire pour six studs de cote, contre un par touffe. C'est ce qui rend l'economie gratuite -- un
test par touffe aurait coute presque aussi cher que ce qu'il economise.

Deux exceptions, et elles sont necessaires :

- **Les paves ENCORE EN MOUVEMENT** sont epargnes. Une touffe qui se releve doit finir son geste, sinon elle se
  fige a mi-chemin et on la retrouve comme ca en se retournant.
- **Ce qui est SOUS LES PIEDS** aussi (`CULL_BEHIND_KEEP`, 10 studs). Ces touffes-la, le joueur les voit
  forcement, quoi qu'il regarde.

Le regard est pris A PLAT : une pelouse est horizontale, donc lever les yeux ne doit rien cacher. Sans ca,
regarder le ciel figerait toute l'herbe autour de soi.

### Aucun risque en CO-OP

L'herbe est 100 % client : chaque joueur construit et anime la sienne, rien ne transite. Cacher la sienne ne peut
donc rien changer chez les autres. C'est aussi pour ca qu'on ECARTE au lieu de DETRUIRE : detruire et recreer des
parts coute cher et provoque des a-coups, alors que sauter un calcul ne coute rien.

## 0.0.383 — PROFIL MOBILE pour l'herbe : le jeu etait injouable sur telephone

Regarder la pelouse ou marcher dessus faisait tomber le jeu a genoux sur mobile.

Ce n'est pas une surprise : la limite etait connue et notee depuis la bascule vers la tonte -- une part par touffe
ne tient pas sur une carte entiere (18 546 mesurees a pleine densite sur quatre pelouses). Elle vient d'etre
atteinte.

### Trois valeurs changent sur un appareil tactile

- `MOBILE_DENSITY` (0.12 au lieu de 0.35) : trois fois moins de parts. La pelouse ne se troue PAS pour autant --
  `AUTO_SCALE_WITH_DENSITY` grossit les touffes d'autant, donc la couverture reste.
- `MOBILE_WIND_VIEW_DISTANCE` (14 au lieu de 26) : c'est l'AUTRE moitie du cout. Moins de touffes ANIMEES par
  image, pas seulement moins de touffes. Au-dela, elles sont posees et immobiles -- ce qui ne se voit pas de loin.
- `MOBILE_CREATE_BUDGET` (120 au lieu de 500) : le semis s'etale sur plus d'images, donc arriver dans un jardin ne
  fait plus tomber le jeu pendant une seconde.

Ce ne sont pas "les valeurs degradees". C'est la version qui TOURNE, et c'est la seule qui compte pour la moitie
des joueurs de la plateforme.

### On lit la CAPACITE, pas l'input actif

`UserInputService.TouchEnabled`, et surtout pas `InputDevice` :

- C'est une decision STABLE, prise une fois au demarrage. Elle ne doit pas changer parce que le joueur a pose son
  doigt sur l'ecran -- re-semer une pelouse en pleine partie serait pire que le probleme.
- `InputDevice` suit le DERNIER input utilise et demarre sur "clavier". Il aurait donne le profil PC a tout le
  monde au boot : exactement le cas qu'on veut eviter.

Et PAS de `and not KeyboardEnabled` : l'emulateur d'appareil de Studio garde le clavier du PC, donc ce combo
rendrait le profil mobile intestable (deja au journal).

### Le semis DIT ce qu'il a fait

Chaque zone annonce maintenant son nombre de touffes, son profil, sa densite et son rayon d'animation. Une pelouse
qui rame se diagnostique avec un NOMBRE, pas avec une impression : sans ce compte, on ne sait pas si le probleme
vient de la densite, du rayon ou d'autre chose, et on regle des boutons au hasard.

### Ce que ca ne resout PAS

C'est une reduction, pas un changement d'echelle. Le vrai plafond reste : une part par touffe. Le jour ou il
faudra couvrir une carte entiere, il faudra un POOL de touffes qui suit le joueur -- creees et recyclees autour de
lui au lieu d'exister toutes en meme temps. C'est note depuis longtemps, et ca reste a faire.

## 0.0.382 — Plus de secousse de camera au coup de corde

Retiree, avec ses trois reglages.

Elle attirait l'attention sur la CAMERA au lieu du geste. La machine qui se cabre et le moteur qui tousse
racontent deja le tirage -- et eux sont DANS la scene. Une camera qui tremble est un commentaire sur ce qui se
passe, pas un evenement qui se passe.

Le code est supprime, pas desactive : un effet qu'on garde "au cas ou" finit par etre un mort qu'on n'ose plus
toucher. Il est dans l'historique si le besoin revient.

La secousse du taille-haie, elle, est un autre systeme et n'est pas concernee.

## 0.0.381 — Marcher sur l'herbe tondue l'eclaircit, sans effacer la bande

`MOWN_CRUSH_LIGHTEN` (0.18) remplace `MOW_CRUSH_DAMP`.

### Le probleme etait le mecanisme, pas le dosage

L'ecrasement fondait vers une teinte claire FIXE -- celle des brins d'herbe haute couches. Sur de l'herbe tondue,
cette teinte REMPLACAIT la couleur de la touffe, donc elle effacait sa bande. Et le joueur marche exactement sur
la bande qu'il vient de couper.

On avait donc attenue l'effet de plus en plus (0.55, puis 0.7, puis 0.92) pour sauver les bandes -- jusqu'a rendre
l'herbe tondue inerte sous le pied. Deux besoins qui se battaient pour le meme reglage, et aucun des deux
satisfait.

### La correction

Sur l'herbe tondue, l'ecrasement ECLAIRCIT sa propre couleur au lieu d'en changer. Comme cette couleur porte deja
sa bande, la bande survit sous le pas.

Le dosage devient alors libre : plus rien a sacrifier. 18 % au maximum de l'ecrasement -- ca doit rester discret,
c'est un retour de pas, pas une information de jeu.

L'herbe HAUTE, elle, garde sa teinte claire franche : chez elle, ce sont vraiment des brins couches qui renvoient
la lumiere.

## 0.0.380 — La bande claire prend la couleur demandee, et rien ne la multiplie

`MOWN_COLOR` : 159, 197, 97 -> **123, 148, 74**.

### Les bandes n'ECLAIRCISSENT plus, elles ne font qu'assombrir

Avant, la couleur de config etait une teinte MOYENNE : une bande sur deux montait au-dessus, l'autre descendait
en dessous. Ce qui etait ecrit dans le fichier n'etait donc la couleur d'AUCUNE des deux bandes -- on la reglait
a l'aveugle, en corrigeant un resultat qu'on ne pouvait pas prevoir.

Maintenant `MOWN_COLOR` EST la bande claire. Ce qui est ecrit est exactement ce qu'on voit, et
`MOWN_BAND_STRENGTH` (0.22) dit seulement de combien l'autre descend.

Meme famille que la regle apprise sur les UIGradient : quand deux reglages se multiplient dans le dos l'un de
l'autre, on en corrige un en croyant corriger l'autre.

## 0.0.379 — L'herbe haute ne s'ecrase plus autant sous le pied

- `CRUSH_SQUASH` : 0.98 -> **0.65**. Sous le pied, la touffe descend a 35 % de sa hauteur au lieu de 2 %.
- `FLATTEN_AMOUNT` : 0.9 -> **0.5**. La trainee derriere le joueur garde la moitie de cet ecrasement au lieu de
  presque tout.

### Pourquoi c'etait devenu faux

A 0.98, un pas ne couchait pas l'herbe : il la RASAIT. Ca ressemblait davantage a un passage de tondeuse qu'a un
pas -- et ca brouille justement l'information qu'on veut donner, maintenant que la tonte a sa propre hauteur
(`MOWN_SCALE_Y`). Deux gestes tres differents produisaient le meme resultat a l'ecran.

Meme chose pour la trainee : a 0.9, une pelouse simplement TRAVERSEE ressemblait a une pelouse TONDUE.

### Les deux reglages ne disent pas la meme chose

`CRUSH_SQUASH` dit a quel point l'herbe se couche SOUS le pied. `FLATTEN_AMOUNT` dit combien elle en garde
APRES. Ils se multiplient, donc baisser l'un allege deja l'autre -- utile a savoir avant de les regler tous les
deux a l'aveugle.

L'herbe deja tondue n'est pas concernee : elle ne s'ecrase plus du tout depuis le 0.0.369.

## 0.0.378 — Les bandes de tonte se voient enfin

Elles existaient bien, mais deux choses les rendaient invisibles.

### Le joueur effacait ses propres bandes en marchant dessus

Il marche EXACTEMENT sur la bande qu'il vient de couper -- c'est la position d'un pousseur de tondeuse. Or la
teinte de pietinement est bien plus CLAIRE que l'ecart entre deux bandes : elle les lavait derriere lui au fur et
a mesure qu'il avancait. Il ne voyait donc jamais son propre travail.

`MOW_CRUSH_DAMP` : 0.7 -> 0.92. Il en reste un soupcon, assez pour que l'herbe ne soit pas inerte sous le pied,
pas assez pour concurrencer les bandes.

### Et l'ecart entre bandes etait trop faible

`MOWN_BAND_STRENGTH` : 0.09 -> 0.22.

Un ecart faible se perd des que QUOI QUE CE SOIT d'autre teinte la touffe -- le pas du joueur, une rafale de vent.
Une bande doit gagner ces concours-la, sinon elle n'existe que dans le code.

## 0.0.377 — La conduite braque comme une VOITURE, et les bandes deviennent un motif du terrain

Deux changements demandes le meme soir, tous les deux sur le coeur du jeu.

### Le braquage se regle par un RAYON, plus par une vitesse

Le joueur decrivait la conduite comme "trop vite, trop sec, stressant", et sa reference comme "une voiture : elle
braque en roulant".

Avec une vitesse de rotation fixe, la machine tourne AUTANT par seconde qu'elle roule vite ou lentement. Au pas,
le moindre appui la fait donc pivoter beaucoup trop : on sur-corrige, on zigzague, on n'arrive pas a viser une
bande droite.

`STEER_RADIUS` (8 studs) remplace `STEER_TURN_RATE` et `STEER_CRAWL_TURN_RATE`. La rotation devient
proportionnelle a la DISTANCE parcourue : a fond de braquage la machine decrit toujours le meme cercle, qu'elle
aille vite ou doucement. Elle devient PREVISIBLE -- on sait ou elle va avant d'y aller, et c'est ca qui enleve le
stress.

Un reglage de moins, aussi : la manoeuvre a l'arret n'a plus besoin de sa propre vitesse de rotation. En braquant
sur place la machine avance de `STEER_CRAWL`, donc elle tourne d'autant -- lentement, puisqu'elle roule
lentement. Deux cas qui ne peuvent plus se contredire.

Et le test "est-ce qu'il avance ?" disparait : s'il ne roule pas, la rotation vaut zero toute seule. Une tondeuse
a l'arret ne pivote pas sur elle-meme.

### Les bandes sont un motif du TERRAIN, pas la trace du trajet

Elles dependaient du SENS dans lequel on avait coupe, avec un axe appris de la premiere passe. Techniquement ca
marchait -- mais ca demandait au joueur de rouler droit et regulier pour meriter un beau resultat, et il roule
comme il veut.

Une pelouse doit recompenser le fait d'avoir TOUT coupe, pas la discipline du trajet.

La bande est donc decidee A LA POSE, d'apres la position de chaque touffe, et se revele des qu'on coupe. Elle
reutilise le damier des rayures decoratives (`STRIPE_WIDTH`, `STRIPE_HEADING`) : le meme motif, revele au lieu
d'etre peint.

Ce que ca supprime : l'axe appris, le sens de deplacement passe a `mowAt`, la reecriture de la bande a chaque
passage, et trois reglages. La bande ne changeant plus jamais, elle sort aussi des tests de redessin.

## 0.0.376 — L'herbe se rabaisse plus doucement

Elle tombait d'un coup, ce qui se lit comme un interrupteur et pas comme une coupe.

### Deux vitesses a ne pas confondre

- `CUT_RISE_TIME` : 0.35 -> **0.9**. Ce qu'on VOIT. La touffe descend et prend sa couleur sur ce temps-la. C'est
  celui qu'il faut monter quand "l'herbe descend trop vite".
- `MOW_RATE` : 8 -> **5**. Si la touffe compte comme coupee. A 5, il faut 0.2 s de contact, ce qu'un passage de
  tondeuse donne largement.

`MOW_RATE` ne doit PAS descendre plus bas : une passe rapide laisserait alors des touffes a moitie coupees
derriere elle, et rien n'est plus penible que devoir repasser sur ce qu'on croit avoir fait.

C'est la meme separation que partout ailleurs dans ce fichier : ce qui DECIDE et ce qui se MONTRE ne se reglent
pas ensemble.

## 0.0.375 — L'herbe tondue retrouve son ecrasement d'origine

`MOWN_SCALE_Y` : 0.35 -> 0.25. C'est la valeur du tout debut, retrouvee apres avoir essaye 1, puis 0.6, puis
0.35.

On la croyait trop ecrasante. Elle ne l'est pas : a l'ecran, un brin franchement comprime se lit comme de l'herbe
RASE, alors qu'un brin a peine raccourci se lit comme de l'herbe MAL COUPEE.

### Ce que le detour aura servi

La valeur est la meme qu'au depart, mais rien d'autre ne l'est, et c'est le detour qui l'a permis :

- l'EMPRISE AU SOL est un reglage a part, donc l'ecrasement ne fait plus de trous dans la pelouse ;
- le PIED reste au sol quelle que soit la hauteur, donc l'herbe ne flotte plus ;
- l'herbe deja tondue ne s'ecrase plus sous le pied ;
- le maillage d'herbe rase, lui, est arrive en cours de route.

### La lecon

Une deformation de maillage n'est un probleme que si elle SE VOIT en tant que deformation. Sur des brins d'herbe,
tous verticaux, l'ecrasement se lit comme une COUPE -- pas comme un defaut. C'est pour ca qu'on est revenu ici
apres avoir cherche ailleurs pendant plusieurs versions.

## 0.0.374 — L'herbe tondue descend encore

`MOWN_SCALE_Y` : 0.6 -> 0.35. L'emprise au sol ne bouge pas, donc toujours aucun trou.

On approche de la limite de ce reglage. Plus bas, on ne raccourcit plus les brins, on les ECRASE : le maillage
d'herbe rase se comprime et cesse de ressembler a de l'herbe.

Si c'est encore trop haut, la suite ne se joue plus dans le code mais dans BLENDER -- il faut modeler `GrassCut`
plus court et remettre ce chiffre vers 1. Le code peut raccourcir une forme, il ne peut pas en inventer une autre.

## 0.0.373 — Hauteur et emprise de l'herbe tondue deviennent deux reglages

L'herbe tondue etait trop haute. Mais la baisser avec le reglage unique reintroduisait les TROUS entre les
touffes -- on tournait en rond entre deux defauts.

### Un seul chiffre forcait a choisir entre deux defauts

`MOWN_SCALE` s'appliquait aux trois axes :

- le baisser raccourcissait l'herbe, mais retrecissait aussi son EMPRISE AU SOL -> la pelouse se clairsemait ;
- le laisser a 1 gardait la pelouse pleine, mais l'herbe tondue restait aussi haute que l'herbe brute.

Ces deux grandeurs n'ont rien a voir l'une avec l'autre. Les separer supprime le compromis au lieu de l'arbitrer
-- c'est la meme lecon que les deux allures de la tondeuse, ou un reglage partage forcait a compenser ailleurs.

### Les deux reglages

- `MOWN_SCALE_Y` (0.6) : la HAUTEUR. C'est ce qui fait qu'une pelouse a l'air tondue. Ne pas descendre sous ~0.4,
  ou les brins ne sont plus raccourcis mais ECRASES, et le maillage se voit deforme.
- `MOWN_SCALE_XZ` (1) : l'EMPRISE AU SOL. A 1, la touffe couvre exactement la meme surface qu'avant la coupe :
  aucun trou ne peut apparaitre. Il n'y a aucune raison d'en bouger, sauf a vouloir un gazon clairseme.

Le calage du PIED au sol suit la nouvelle hauteur, donc l'herbe tondue reste posee au sol quel que soit le
reglage.

## 0.0.372 — Le premier conseil sortait plus PETIT, et il a fallu trois essais

Deux captures cote a cote l'ont montre sans discussion : meme police, taille differente. Le premier conseil est
plus petit que les suivants.

### Pourquoi les deux correctifs precedents ont echoue

La taille du texte se deduit de la hauteur de la ligne, qui vaut 4.5 % de l'ecran. Mais le rideau s'affiche AVANT
que le viewport ait sa taille definitive : on lisait donc une hauteur trop petite.

- Le premier essai a cherche du cote de la POLICE. Faux : `rbxasset://` est livre avec le client.
- Le second attendait "hauteur > 0". Insuffisant : la valeur intermediaire est NON NULLE et FAUSSE, donc
  l'attente sortait immediatement.

Le defaut commun aux deux : chercher L'INSTANT ou la valeur devient bonne. Il n'y en a pas.

### On corrige en continu

La taille est relue A CHAQUE IMAGE et reappliquee si elle a bouge. Meme principe que les largeurs de lettres,
corrigees juste en dessous, et meme boucle -- donc aucun mecanisme de plus.

Ca couvre au passage un cas qu'aucune attente n'aurait couvert : le joueur qui redimensionne sa fenetre pendant
le chargement.

Regle a retenir : quand une valeur d'affichage se stabilise SANS prevenir, ne pas chercher le bon moment pour la
lire. La relire.

## 0.0.371 — Les lettres du conseil n'ont plus qu'un seul ecrivain

Suite du premier conseil mal rendu. Ni la police ni la taille cette fois : les POSITIONS.

Une police se charge PARESSEUSEMENT. Le premier conseil peut etre dessine avec une police de secours puis
redessine avec la bonne : Roblox echange le rendu tout seul, mais pas nos positions, calculees a la main sur les
largeurs de l'ancienne. Les lettres restaient donc mal espacees, et le mot entier avait l'air d'etre dans une
autre police.

### On cesse de deviner QUAND la police arrive

Aucune API ne le dit, et deux tentatives de le deviner se sont revelees fausses -- dont une qui attendait qu'une
largeur cesse de changer, alors que la largeur d'une police de secours est stable elle aussi.

On RE-MESURE donc a chaque image et on replace. La mise en page se corrige toute seule, quel que soit le moment
ou la vraie police arrive.

### Ce qui a oblige a reecrire le rebond

Avec des tweens sur `Position`, ce replacement se serait battu avec l'animation en cours : le tween aurait
continue vers sa cible, calculee sur les anciennes largeurs. Deux ecrivains sur la meme propriete, exactement ce
que la regle du projet interdit.

Le rebond est donc ecrit A LA MAIN, dans la meme boucle que le placement : un seul ecrivain pour le X ET le Y. La
courbe est empruntee a `TweenService:GetValue`, donc on garde le rebond sans le coder.

Un jeton coupe la boucle du conseil precedent : sans lui, deux boucles ecriraient les memes lettres et la plus
vieille gagnerait une image sur deux.

## 0.0.369 — On ne peut plus ecraser l'herbe deja tondue

Marcher sur une pelouse tondue l'aplatissait encore. Elle est deja rase : un pied n'a plus rien a y coucher, et
la voir s'aplatir contredit ce qu'on vient de faire -- on a coupe, ce n'est pas un paillasson.

`MOWN_CRUSH_DAMP` (1) supprime l'ecrasement sur une touffe tondue. La HAUTEUR et l'INCLINAISON, les deux :
une touffe qui ne s'aplatit plus mais qui penche encore aurait l'air de GLISSER sous le pied, ce qui est pire que
les deux ensemble.

L'amortissement suit l'avancement de la coupe, il ne bascule pas : une touffe a moitie tondue s'ecrase a moitie.

### La couleur, elle, bouge encore -- a peine

`MOW_CRUSH_DAMP` : 0.55 -> 0.7. Historique : 0.9 (marcher sur du tondu ne changeait plus rien), 0.55 (trop
marque), 0.7.

Il doit rester JUSTE ASSEZ pour qu'on devine ou l'on est passe, sans laver la bande de tonte ni concurrencer le
contraste tondu / pas tondu -- qui est l'information importante.

## 0.0.368 — Le premier conseil sortait a huit pixels

Ce n'etait PAS la police. Correction d'un diagnostic rate au 0.0.366.

### La vraie cause

La taille du texte se deduit de la hauteur de la ligne :

    local size = math.max(math.floor(tipsRow.AbsoluteSize.Y), 8)

`AbsoluteSize` n'existe qu'apres le passage de la mise en page. Or le tout premier conseil est ecrit AVANT la
premiere image du rideau : on lisait donc ZERO, et la taille retombait sur son plancher de huit pixels.

Le premier conseil sortait minuscule -- ce qui ressemble a une autre police -- alors que les suivants, ecrits des
secondes plus tard, tombaient juste. D'ou l'impression que seul le premier etait casse.

On attend maintenant que la ligne ait une hauteur avant de lire quoi que ce soit.

### Le diagnostic precedent etait faux

L'attente de POLICE ajoutee au 0.0.366 est supprimee. Elle ne servait a rien, pour deux raisons :

- `rbxasset://` designe un fichier livre AVEC le client. Il n'y a rien a telecharger.
- Sa detection etait fausse de toute facon : elle attendait que la largeur d'un temoin CESSE de changer, or la
  largeur d'une police de secours est stable elle aussi. La boucle sortait donc a la deuxieme image, sans rien
  garantir.

Lecon : "ca ressemble a un probleme de police" n'est pas un diagnostic. Une taille de texte fausse, une mise en
page pas encore calculee et une police absente donnent le meme symptome a l'ecran.

## 0.0.367 — L'herbe coupee flottait au-dessus du sol

Un ecart visible entre le sol et l'herbe tondue.

### Une part est posee par son CENTRE

Quand la touffe raccourcit -- ecrasee par un pied, ou tondue et reduite a 40 % -- son centre ne bouge pas. C'est
donc son PIED qui remonte, de la moitie de la hauteur perdue. A 40 %, ca fait 30 % de la hauteur d'origine en
l'air : impossible a rater.

Le defaut existait deja pour le pietinement, mais il etait trop petit pour se voir. C'est le passage a une
reduction UNIFORME (0.0.365) qui l'a rendu evident -- et la aussi, le vrai probleme etait plus vieux que le
changement qui l'a revele.

### Une ligne qui couvre les deux causes

On descend le centre de la MOITIE de la hauteur perdue. Le pied retrouve exactement sa place, que la touffe soit
ecrasee, tondue, ou les deux -- sans avoir a traiter les cas separement.

`GROUND_SINK` reste a cote et garde son role a lui : compenser la marge vide que le MESH laisse sous ses brins.
Deux causes differentes, deux corrections distinctes.

## 0.0.366 — Le premier conseil s'ecrivait dans la mauvaise police

Une police custom se TELECHARGE. Tant qu'elle n'est pas arrivee, Roblox rend le texte avec une police de SECOURS.

Le rideau s'affiche dans les toutes premieres millisecondes de la session, donc le premier conseil partait avant
Montserrat. Les suivants, eux, tombaient juste -- d'ou l'impression que seul le premier etait casse.

### Le vrai degat n'etait pas la police, c'etait la MESURE

Chaque lettre est un objet, place a la main d'apres sa largeur mesuree. Cette largeur etait donc celle de la
police de SECOURS : meme une fois Montserrat arrivee et le texte redessine correctement, l'espacement restait
faux, calcule sur des largeurs qui n'etaient plus les bonnes.

### Comment on attend une police

Il n'existe pas d'evenement "police chargee". On mesure donc une chaine TEMOIN jusqu'a ce que sa largeur CESSE DE
CHANGER : deux mesures identiques signifient que la vraie police a remplace la secours et que plus rien ne
bougera.

Le temoin est cree des la construction du rideau, pour que le telechargement demarre le plus tot possible, et il
SURVIT au menage entre deux conseils -- le detruire relancerait l'attente a chaque fois.

Plafond de 5 secondes : un conseil dans la mauvaise police vaut mieux qu'un bandeau vide. Ce n'est pas un blocage,
c'est une politesse.

## 0.0.365 — L'herbe tondue RETRECIT au lieu d'etre aplatie

Elle montait beaucoup trop haut. Correction d'une hypothese fausse posee au 0.0.363.

### Ce qui n'allait pas

J'avais deduit la hauteur de l'herbe coupee du RAPPORT entre les deux meshes. L'idee se tenait -- regler une
hauteur d'herbe en modelant de l'herbe -- mais elle supposait que le mesh d'herbe coupee etait modele COURT.

Il ne l'est pas : sa boite fait a peu pres la meme hauteur que celle de l'herbe haute. Le rapport valait donc 1,
et la coupe ne raccourcissait plus rien.

### La vraie reponse : reduire sur les TROIS axes

`MOWN_SCALE` (0.4) remplace `MOW_CUT`. La touffe RETRECIT au lieu d'etre APLATIE, donc le maillage d'herbe rase
garde exactement la forme modelee -- ce qui etait la demande de depart.

La coupe ne passe donc plus du tout par `squash`. Celui-ci n'ecrase que la HAUTEUR : c'est bon pour un pied qui
appuie, mauvais pour une coupe.

Le retrecissement suit l'EMERGENCE et non l'avancement de la coupe : la touffe sort du sol a sa nouvelle taille,
en un seul mouvement.

### Contrepartie a surveiller

Reduire sur trois axes retrecit aussi l'EMPRISE au sol. Trop bas, la pelouse tondue se clairseme et on voit le
sol entre les touffes. Si ca arrive, c'est `MOWN_SCALE` qu'il faut remonter -- pas la densite du semis.

## 0.0.364 — L'herbe de base fonce

`BASE_COLOR` : 138, 154, 85 -> 90, 107, 49. Meme teinte, plus sombre.

Elle laisse toute la place au contraste avec l'herbe TONDUE, qui est claire : c'est cet ecart qui fait voir le
travail fait, et c'est le coeur du geste.

L'historique complet des valeurs reste dans la config, avec ce que chacune corrigeait.

## 0.0.363 — L'herbe coupee n'est plus ecrasee, l'herbe normale ne levite plus, et le regard arriere se coupe

### La touffe coupee gardait 25 % de sa hauteur

Elle etait ecrasee a un pourcentage ecrit en config (`MOW_CUT`). Ca se tenait tant que la coupe n'etait qu'un
aplatissement -- mais depuis que l'herbe coupee a son PROPRE MAILLAGE, ecraser en plus DEFORMAIT ce maillage : il
etait comprime dans une boite au quart de sa taille.

La hauteur vient maintenant du RAPPORT entre les deux meshes, releve au demarrage. La touffe coupee fait donc
exactement la taille modelee dans Blender.

Le reglage passe du code au MODELE, la ou il a un sens : on regle une hauteur d'herbe en modelant de l'herbe.
`MOW_CUT` ne sert plus que de secours, quand il n'y a pas de mesh d'herbe rase.

### L'herbe levitait

Une touffe est posee par son CENTRE sur la surface de la zone, mais la geometrie du mesh n'occupe pas forcement
toute sa boite : selon la marge laissee sous les brins, elle a l'air de flotter. `GROUND_SINK` (0.08) l'enfonce.

En fraction de sa hauteur et pas en studs : cette marge suit la taille du mesh, donc une valeur absolue
enterrerait les petites touffes et laisserait les grandes en l'air.

### Le regard arriere restait joue apres avoir lache la machine

Le joueur gardait la tete tournee en arriere, pour toujours.

Cause : les poses tenues etaient coupees par un `ipairs` sur un tableau construit a la volee.

    for _, t in ipairs({ state.start, state.turn, state.reverse }) do

**`ipairs` S'ARRETE AU PREMIER NIL.** Or `state.start` passe a nil des que le moteur a pris : la boucle ne
tournait donc ZERO fois. C'est le genre de trou qui ne se voit jamais a la lecture -- le code a l'air de couvrir
les trois cas.

Les quatre poses (guidon, virage, regard arriere, tirage) sont maintenant coupees UNE PAR UNE, par un helper qui
accepte nil. Plus de liste, donc plus de trou possible.

## 0.0.362 — Le conseil s'ecrit lettre par lettre, chacune avec son rebond

### Une etiquette par caractere, et il n'y a pas d'autre moyen

Un TextLabel est un BLOC. `MaxVisibleGraphemes` -- ce qu'utilise deja le dialogue du jeu -- revele bien les
lettres une a une, mais il ne peut pas les faire BOUGER separement : elles appartiennent toutes au meme objet.
Pour un rebond par lettre, il faut un objet par lettre.

Le cout est acceptable ICI et nulle part ailleurs : une soixantaine d'etiquettes par conseil, sur un ecran qui ne
fait rien d'autre. Dans une interface de jeu, ce serait a proscrire.

### Place a la main, pas par un UIListLayout

Un layout REPOSE ses enfants a chaque image : il ecraserait le decalage vertical du rebond. Et animer autre chose
(l'echelle) changerait la largeur des lettres, donc ferait sautiller toute la ligne. En posant les X une fois pour
toutes, le Y reste a nous.

Trois pieges le long du chemin :

- **Une image d'attente avant de mesurer.** `AbsoluteSize` n'est calcule qu'apres le passage de la mise en page :
  le lire tout de suite rend zero partout, et toutes les lettres se posent l'une sur l'autre.
- **Une espace ne mesure RIEN.** Roblox rogne les blancs de bord, donc sa largeur revient a zero et les mots se
  colleraient. Elle recoit une avance fixe (`TIP_SPACE_WIDTH`).
- **La transparence ne rebondit pas.** Un easing `Back` sur une transparence la ferait passer sous zero, donc
  clignoter. Seule la position rebondit.

### La sortie, elle, reste d'un bloc

L'apparition merite d'etre detaillee, la disparition non : personne ne regarde partir un texte qu'il a fini de
lire, et soixante fondus decales feraient trainer la sortie pour rien.

`TIP_LETTER_STAGGER` (0.02) est LE reglage du rythme : trop court, tout arrive ensemble et on perd l'effet ; trop
long, on lit la phrase plus vite qu'elle ne s'affiche.

## 0.0.361 — La tondeuse ne traverse plus les haies ni les cloture

Une part `Hitbox` posee dans Studio garde ses collisions une fois la machine portee. C'est la SEULE.

### Pourquoi une seule boite, et pas la machine entiere

La prise met `CanCollide = false` sur toutes les parts, et il le faut : une machine pleine de parts solides
soudee au joueur se coince dans le decor et le fait sauter -- une forme compliquee accrochee a un personnage est
ingerable pour le moteur physique. Mais sans collision du tout, la machine n'existe pas pour la physique et
traverse tout.

Une seule boite simple, posee a la main, resout les deux : la physique sait la gerer, et elle borne le passage.

Elle est mise en `Massless` : elle borne, elle n'alourdit pas. Sans ca, elle change la masse de l'assemblage du
joueur, donc sa facon de marcher, de tomber et de monter une pente.

`CanTouch` a false : rien n'ecoute cet evenement, et une boite qui frotte le decor en tirerait des centaines par
seconde.

### Ecartee de tous les balayages de parts

Comme la zone de coupe, c'est un volume LOGIQUE et pas une piece de la machine. La compter fausserait la hauteur
et le recul du portage (cote serveur) et deplacerait le badge d'interaction vers un point qui n'existe sur rien de
visible (cote client). Les trois endroits qui balayaient les parts l'ecartent maintenant par son nom.

### A savoir

`CanQuery = false` n'a AUCUN effet tant que `CanCollide` est vrai -- deja au journal. Cette boite reste donc vue
par les raycasts, a garder en tete si un systeme se met un jour a lancer des rayons depuis le joueur vers l'avant.

### Cote Studio

La part doit s'appeler `Hitbox` et vivre sous le modele de la tondeuse. Rojo ne synchronise pas le Workspace : a
recopier dans chaque lieu, sinon la machine continuera de traverser les cloture chez le collaborateur.

## 0.0.360 — La camera du demarrage recule un peu : vue d'ensemble

`PULL_CAM_FORWARD` : 10 -> 13. Assez loin pour tenir le joueur ET la machine dans le cadre. C'est une vue
d'ensemble -- on regarde quelqu'un demarrer une tondeuse, pas un gros plan sur une main.

Historique note dans la config pour ne pas refaire le tour : 9 (trop pres, on ne voyait pas la scene), 20 (trop
loin, le joueur devenait une silhouette), 10, puis 13.

## 0.0.359 — Le volet du rideau ralentit

`WIPE_COVER_TIME` : 0.3 -> 0.55. `WIPE_REVEAL_TIME` : 0.45 -> 0.85. `WIPE_HOLD` : 0.06 -> 0.12.

Le retrait reste plus LENT que l'arrivee, et c'est voulu : les deux moities n'ont pas le meme role. On couvre
pour CACHER -- autant que ce soit vite fait. On decouvre pour MONTRER le jeu -- autant que ca se savoure.

## 0.0.358 — Le rideau s'en va derriere un VOLET BLANC

Le fondu de sortie etait moche : chaque element du rideau -- la tuile, la feuille, les textes -- s'effacait en
meme temps mais pas au meme rythme, et ca se lisait comme un bug.

Un aplat BLANC balaie maintenant l'ecran, le rideau est DETRUIT pendant qu'il couvre, puis le blanc s'en va en
balayant dans l'autre sens et le jeu apparait. On ne voit donc plus rien partir : il n'y a plus rien a voir.

### On construit la sequence, on n'anime pas l'Offset

Le sens d'un `UIGradient.Offset` est imprevisible -- deja au journal, et deja paye sur cet ecran. Les TEMPS d'une
NumberSequence, eux, sont deterministes : 0 est le debut du degrade, 1 sa fin. En posant les points soi-meme, on
sait exactement ce qu'on fabrique.

Une valeur `edge` decrit jusqu'ou le blanc s'etend. Le MEME constructeur sert aux deux moities du mouvement : on
la fait monter pour couvrir, puis redescendre pour decouvrir -- et cette descente EST le balayage inverse, sans
une ligne de plus.

### Le volet est CONDAMNE D'AVANCE

Un aplat blanc plein cadre est la pire chose a laisser derriere soi : il cache le jeu entier et le joueur n'a
aucun moyen de s'en debarrasser. Sa destruction est donc programmee AVANT meme qu'il soit anime. Si une seule
ligne du balayage echoue -- ou si le sens est faux -- il part quand meme.

C'est ce qui rend l'idee sans danger : le pire cas devient "le balayage part du mauvais cote", pas "le jeu est
masque pour toute la session".

Le sens reste un reglage (`WIPE_ROTATION`, 0 ou 180) parce qu'il ne se devine pas.

## 0.0.357 — Le coup de corde part de l'ANIMATION, plus d'un delai devine

Le son du tirage arrivait en retard. Cause : il partait du CLIC, alors que le bras ne part en arriere qu'un
demi-tiers de seconde plus tard.

L'animation de tirage porte un evenement, `TryLaunchEvent`, pose a l'image exacte du coup de corde. C'est lui qui
declenche maintenant les TROIS retours d'un coup : la machine qui se cabre, la toux du moteur, et le son.

### Ce que ca supprime

`PULL_LIFT_DELAY` (0.35 s) disparait. Un delai en secondes suppose qu'on connait la cadence du geste, alors
qu'elle vit dans l'animation : la retoucher decalait tout, en silence. Le marqueur, lui, suit l'animation quoi
qu'on lui fasse.

Et les trois retours restent d'accord entre eux PAR CONSTRUCTION, au lieu d'etre recales un par un.

### Deux precautions

- **Branche une seule fois**, a la creation de la piste, et surtout pas au clic. La piste se REARME apres un
  tirage rate : une connexion posee a chaque clic s'empilerait, et la machine se cabrerait deux fois, puis trois.
- **`GetMarkerReachedSignal` et jamais `GetKeyframeSequenceAsync`.** Le second est un appel RESEAU qui, s'il rate
  au boot, tue la feature pour TOUTE la session -- deja paye sur la boite aux lettres.

`pullStarter` ne fait donc plus qu'une chose : relancer la piste figee.

## 0.0.356 — La camera du demarrage arrete de bouger toute seule

Deux mouvements retires. Le plan se pose, et c'est tout.

### Le recul continu

La camera derivait lentement de 7 a 11 studs pendant toute la scene, cense lui donner de l'ampleur. Retire.

Une camera qui derive en permanence pendant qu'on attend de pouvoir agir est PENIBLE, et ca se remarque bien plus
qu'un plan fixe. Le mouvement ici, c'est le GESTE du joueur -- pas la camera. `PULL_CAM_FORWARD` devient une
distance fixe (10 studs), et `PULL_CAM_FORWARD_START` / `PULL_CAM_DRIFT_TIME` disparaissent.

### Le rebond elastique

`PULL_CAM_EASING` passe de `Back` a `Quad`.

`Back` depasse la cible puis revient : c'est ce qui donne le rebond du reste de l'interface. Mais un rebond va
bien a un BOUTON qu'on presse -- c'est une reponse a un appui. Sur une camera, le depassement se lit comme une
erreur de visee, et l'oeil le suit au lieu de suivre la scene.

Ce qui reste : l'arrivee en 0.22 s, franche et posee, et la secousse a chaque coup de corde. Un mouvement qui
REPOND a une action du joueur, et rien qui bouge tout seul.

## 0.0.355 — Retrait du systeme d'accessoire sur os

`PropFollowController` et `PropAttachConfigs` sont supprimes, ainsi que leurs declarations dans le bootstrap.

Le 0.0.354 reste dans ce fichier : il explique POURQUOI un Motor6D ne peut pas s'accrocher a un `Bone`, et ce
que fait `TransformedWorldCFrame`. C'est de l'information qui resservira le jour ou un accessoire devra vraiment
etre detachable.

Pour un objet qui ne se lache jamais -- une canne sur un PNJ -- la bonne reponse reste de l'integrer au mesh dans
Blender et de le peser sur l'os de la main. Zero code, zero cout a l'execution, et rien a rebrancher.

Le code retire est recuperable dans l'historique si le besoin revient.

## 0.0.354 — La canne suit enfin la main du grand-pere

Nouveau `PropFollowController` + `PropAttachConfigs`. Un objet de decor suit un OS d'un personnage skinne.

### Pourquoi un systeme a part, et pas un Motor6D

Un Motor6D exige DEUX BasePart. Sur un mesh skinne, les membres sont des `Bone`, qui heritent d'Attachment :
aucun joint ne peut s'y accrocher. C'est pour ca que le script de la barre de commandes disait "RightHand
introuvable" -- il cherchait une part la ou il y a un os.

`Bone.TransformedWorldCFrame` est la seule propriete qui donne la position ANIMEE d'un os, et elle se LIT. On la
recopie donc a chaque image.

### Cote CLIENT, et c'est mieux que le serveur

C'est du decor : rien ne depend de la position exacte de la canne. Chaque client fait le calcul chez lui, donc
c'est fluide a son propre framerate et ca ne coute pas un octet de reseau. Cote serveur, il aurait fallu repliquer
une CFrame soixante fois par seconde pour un resultat MOINS bon -- la replication est plus lente que l'affichage,
l'objet aurait saccade.

L'ecriture tient parce que le serveur ne touche jamais a cet objet : une part ancree n'est repliquee que quand
elle CHANGE cote serveur.

### L'ecart est CAPTURE, pas regle

On releve ou l'objet est POSE par rapport a l'os, une seule fois. Le placement fait a l'oeil dans Studio est donc
la source de verite, exactement comme pour un Motor6D : deplacer la canne dans l'editeur et relancer suffit a
corriger la prise. Aucun reglage a tatonner.

Un accessoire en PLUSIEURS morceaux suit entier : chaque part garde son ecart a la part maitresse.

### Deux details qui evitent des heures

- **Apres la camera** dans l'image. Les os sont mis a jour par l'animation pendant l'image : les lire trop tot
  donnerait l'etat de l'image PRECEDENTE, et l'accessoire trainerait d'une image derriere la main.
- **On NOMME ce qu'on n'a pas trouve.** Un compteur global ne revele jamais l'absence du troisieme accessoire :
  on chercherait le probleme dans l'animation alors que l'objet n'a simplement pas ete vu.

### Ca reste le deuxieme meilleur choix

Pour un accessoire qui ne se lache JAMAIS, l'integrer au mesh dans Blender et le peser sur l'os reste superieur :
il devient une partie du personnage, il suit tout seul, et ca ne coute rien a l'execution. Ce module est fait pour
les objets qu'on veut pouvoir deplacer, echanger ou retirer sans reexporter le personnage.

## 0.0.353 — La camera arrive devant la tondeuse deux fois plus vite

`PULL_CAM_IN_TIME` : 0.42 -> **0.22**. `PULL_CAM_OUT_TIME` : 0.32 -> **0.2**.

Historique note dans la config pour ne pas refaire le tour : 0.7, puis 0.42, puis 0.22. A chaque fois le meme
retour -- "c'est lent, c'est stressant".

La raison est simple une fois dite : une camera qui SE DEPLACE pendant qu'on attend de pouvoir agir se SUBIT. Le
joueur veut arriver, pas voyager. Le rebond elastique fait le reste du travail -- meme tres court, il ne claque
pas.

## 0.0.352 — Le curseur reste libre pendant le chargement

Pendant le rideau, la souris etait verrouillee au centre et le curseur efface. Le joueur se retrouvait devant un
ecran qu'il ne peut de toute facon pas viser, sans pouvoir bouger sa souris : ca ressemble a un jeu fige, pas a un
chargement.

Le coupable n'etait pas l'ecran de chargement mais la VUE SUBJECTIVE : elle s'activait des l'arrivee du
personnage, or le rideau tient dix secondes APRES cette arrivee. Elle attend maintenant que le rideau soit parti
(`LeafiaLoadingDone`, l'attribut que l'ecran de chargement pose deja en s'en allant).

Rien a ajouter cote curseur : hors vue subjective, il est libre et visible tout seul.

### Deux details qui evitent des pieges

- **Sondage et non ecoute d'evenement.** L'attribut peut deja etre pose quand on arrive la (chargement rapide,
  ou lieu sans rideau), et une ecoute seule attendrait alors un changement qui n'aura jamais lieu.
- **Un garde-fou de 40 secondes.** Si l'ecran de chargement disparaissait un jour sans poser son attribut, la vue
  subjective ne s'activerait plus JAMAIS et on chercherait longtemps pourquoi.

## 0.0.351 — La feuille du rideau passe au vert

`#8eff5d`, le meme vert que le debut du bandeau. La feuille et le bandeau se repondent : l'ecran a une seule
couleur d'accent, au lieu de deux elements gris qui se ressemblent sans se parler.

Le degrade pose sur la feuille ne touche QUE sa transparence -- c'est lui qui la remplit comme une jauge. Sa
couleur reste neutre, donc ce vert s'affiche tel quel.

## 0.0.350 — Le bandeau passe du vert vif au noir

`BANNER_COLOR` : `#8eff5d` a gauche, `#000000` a droite.

Le meme UIGradient porte donc DEUX choses -- la couleur et la transparence -- et c'est voulu : elles decrivent le
meme voyage le long du bandeau. Les separer sur deux objets obligerait a les garder d'accord a la main.

L'`ImageColor3` du bandeau est ecrit EXPLICITEMENT en blanc pur. C'est deja la valeur par defaut, mais l'ecrire
noir sur blanc evite qu'on la teinte un jour sans voir qu'on rabote la sequence en silence -- exactement le piege
qui vient d'etre corrige sur l'etiquette TIPS.

## 0.0.349 — TIPS passe en blanc pur pour que son degrade dise la verite

Un UIGradient MULTIPLIE la couleur du texte. Sur le gris 97 d'avant, les valeurs du degrade ne rendaient pas ce
qu'elles annoncent : `#ffffff` sortait a 97 et `#d6d6d6` a 81. On reglait donc un degrade dont on ne voyait
jamais les vraies couleurs.

En blanc pur, la multiplication devient NEUTRE : ce qui est ecrit dans la sequence est exactement ce qui
s'affiche.

Regle a retenir : des qu'un UIGradient decide de la teinte, la couleur de base doit etre le blanc. Sinon les deux
reglages se multiplient dans le dos l'un de l'autre, et on en corrige un en croyant corriger l'autre.

## 0.0.348 — Une nuance sur l'etiquette TIPS

Un UIGradient de couleur sur le mot "TIPS" : franc sur la premiere moitie, puis tres legerement eteint.

La cassure nette entre 0.463 et 0.483 fait un petit RESSAUT plutot qu'un degrade continu -- c'est ce qui donne
l'impression d'un relief, la ou un fondu lisse aurait juste l'air sale.

Un UIGradient MULTIPLIE la couleur du texte. Ces valeurs presque blanches ne le repeignent donc pas, elles
l'assombrissent d'au plus 16 % : la teinte de base reste celle du label.

Le SENS est un reglage a part (`TIPS_LABEL_SHADE_ROTATION`, 0 = de gauche a droite). Il ne se deduit pas, comme
tous les degrades de ce fichier : c'est l'ecran qui tranche.

## 0.0.347 — Reglages du rideau : tuile plus fine, fondue, et etiquette TIPS centree

Valeurs relevees dans l'editeur et reportees en constantes.

- `TileSize` : 0.06 x 0.11 -> **0.01 x 0.017**. Un motif beaucoup plus fin.
- `ImageColor3` de la tuile : 83 -> **38**. Elle passe au second plan.
- **Un UIGradient sur la tuile.** Le motif ne doit pas etre present partout avec la meme force : plein cadre et
  uniforme, il se lit comme un papier peint et entre en concurrence avec la feuille du milieu. Il reste dense
  d'un cote et disparait de l'autre.
  La courbe part a PLAT, monte vite, puis s'aplatit vers l'invisible. C'est le palier de depart qui evite que le
  fondu commence des le premier pixel, ce qui aurait l'air d'une erreur.
  Il ne s'anime pas : c'est la tuile qui defile dessous, et comme elle ne se deplace que d'une case a la fois, le
  fondu reste ou il est.
- **Etiquette TIPS** ancree en son CENTRE, position et taille fixees, texte centre. L'ancre au centre garde
  l'etiquette sur son axe quelle que soit sa taille -- avec une ancre en coin, changer la taille la deplace.

Le conseil, lui, reste cale a GAUCHE : c'est lui qui varie en longueur, donc c'est lui qui doit avoir de la
place. L'etiquette, elle, ne bouge jamais.

## 0.0.346 — Le grand-pere s'appelle GrandFather

Le modele a ete renomme dans Studio. Une seule chose cassait vraiment : la cle de `AmbientAnimConfigs` est le NOM
DU MODELE dans le Workspace, pas une etiquette libre. Renomme d'un cote et pas de l'autre, plus rien ne le trouve
et son animation d'attente s'arrete EN SILENCE -- aucune erreur, il cesse simplement de cligner des yeux.

Le commentaire le dit maintenant sur place, pour que le prochain renommage ne coute pas un diagnostic.

`scripts/studio/AttacherCanneAuPapi.lua` suit aussi.

`NpcWanderConfigs` n'est pas concerne : son entree vise `OldManIdle`, un autre modele, et elle est desactivee.

### Ce qui n'a PAS ete touche

Le nom AFFICHE dans les dialogues reste "Papi". C'est du texte vu par le joueur, pas une cle : le changer est une
decision d'ecriture, pas une consequence du renommage.

A noter quand meme : la regle du projet veut que TOUT texte vu par le joueur soit en anglais, parce que le
traducteur de Roblox part de l'anglais. "Papi" n'y est pas, donc il ne sera traduit nulle part. "Grandpa" serait
le mot naturel -- mais c'est un choix a faire, pas a subir.

## 0.0.345 — Le vignettage ne sert QUE le demarrage, et la camera devient elastique

### Le vignettage etait permanent, il ne devait pas l'etre

Il s'allumait au spawn et ne s'eteignait jamais. Un vignettage permanent finit par ne plus rien dire : l'oeil s'y
habitue en une minute, et il ne reste qu'une image plus sombre. Il ne vaut que s'il ARRIVE -- c'est le CHANGEMENT
qui resserre l'attention, pas la valeur.

Il est donc eteint par defaut, et la scene de demarrage l'allume puis l'eteint (`PULL_CAM_VIGNETTE`).

### L'a-coup devient une SECOUSSE

Rapprocher la camera d'un coup puis la faire repartir donnait un "TAC" sec, deux fois de suite, qu'on remarquait
plus que le geste. Une secousse AMORTIE oscille et s'eteint toute seule : on la ressent sans pouvoir dire ce qui
a bouge.

Trois details qui font la difference entre une secousse et un defaut d'affichage :

- **Trois frequences differentes, une par axe.** A frequence egale les trois montent et descendent ensemble, et
  la camera vibre le long d'une DROITE.
- **Seule la POSITION de l'oeil tremble**, pas le point vise : la camera reste braquee sur le joueur. Secouer la
  cible aussi ferait tanguer toute l'image.
- **Elle est calee a zero** quand elle devient minuscule. Un amortissement exponentiel n'atteint jamais sa cible,
  et la camera tremblerait d'un millieme de stud pour toujours.

Le plan memorise pour le retour est le plan NON SECOUE : sinon le retour partirait d'une position de tremblement
attrapee au hasard.

### La transition : plus pres, plus vive, elastique

- `PULL_CAM_FORWARD_START` / `PULL_CAM_FORWARD` : 10 -> 20 devient 7 -> 11. A vingt studs le joueur devenait une
  silhouette et on ne voyait plus la corde.
- `PULL_CAM_DRIFT_TIME` : 7 -> 4. A sept secondes, le recul etait encore en cours quand le moteur partait.
- `PULL_CAM_IN_TIME` : 0.7 -> 0.42, `PULL_CAM_OUT_TIME` : 0.55 -> 0.32. Une glissade lente se lit comme un
  ralenti, pas comme un mouvement de camera.
- `PULL_CAM_EASING` : `Back`. La courbe DEPASSE legerement la cible puis revient -- c'est ce depassement qui
  donne le rebond du reste de l'interface.

La courbe est empruntee a `TweenService:GetValue` au lieu d'etre ecrite a la main : on obtient un rebond sans le
coder, et on en change depuis la config.

Le recul de fond, lui, garde une courbe SAGE. C'est l'arrivee qui a le droit d'etre elastique, pas le mouvement
de fond : un recul qui depasse puis revient se verrait immediatement.

## 0.0.344 — Le rideau de chargement revient en CODE

Le modele Studio du 0.0.339 est abandonne. Raison : Rojo ne synchronise pas StarterGui, donc la ScreenGui
n'existait que dans le lieu ou elle avait ete dessinee. Le tuto tombait sur le rideau de secours, avec le message
"Modele introuvable" -- ce qui etait le comportement voulu, mais pas le resultat voulu.

Le code, lui, arrive dans TOUS les lieux sans rien a recopier. Pour une piece qui doit exister partout, c'est le
seul endroit ou elle est sure d'etre.

Le dessin fait dans l'editeur est repris tel quel : fond tuile teinte, bandeau du bas avec son degrade, feuille
centrale, etiquette TIPS et son conseil.

### Ce qui bouge

- La tuile defile en diagonale. Horizontal ou vertical, ca se lit comme un decor qui glisse ; en diagonale,
  comme un mouvement propre.
- La feuille oscille, flotte, et SE REMPLIT comme une jauge : le joueur voit combien il reste, pas seulement que
  ca charge.
- Les conseils tournent en fondu, le premier tire au hasard.
- Le bandeau, lui, ne bouge PAS. Son degrade est un fondu fixe : le promener pousserait sa rampe de transparence
  hors du bandeau, qui redeviendrait completement opaque.

### Les polices par leur FAMILLE

`Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Bold)` et non `Enum.Font.Montserrat` :
les enums de police sont en cours de depreciation (celui-ci renvoie deja vers Gotham), alors que le chemin de
famille reste stable et porte le poids separement. C'est la forme deja utilisee partout ailleurs dans ce fichier.

## 0.0.343 — VIGNETTAGE : les bords s'assombrissent, l'oeil revient au milieu

Nouveau `Modules/UI/Core/Vignette`. Un voile plein cadre, sombre sur les bords, transparent au centre.

L'oeil va spontanement vers la zone la plus lumineuse. Assombrir la peripherie ramene donc le regard sur le
joueur sans rien lui demander et sans rien ecrire a l'ecran. C'est le moyen le moins cher de dire "regarde ici".

### Une PRIMITIVE, pas un bout de controller

Rangee dans `UI/Core` a cote de `Toast` et `InteractionPrompt`, avec un `setStrength` fondu. La camera du
demarrage pourra donc le renforcer pendant la scene sans avoir a le reecrire, ni meme a connaitre sa valeur de
repos.

### Trois details qui le font tenir sur tous les ecrans

- **Etire, et c'est voulu.** Le voile doit toucher les QUATRE bords quel que soit le format : c'est sa seule
  obligation. Garder ses proportions laisserait des bandes claires sur les cotes en 21/9 -- exactement ce qu'il
  est cense supprimer. La deformation d'un degrade doux ne se voit pas ; un bord manquant, si.
- **Aucun inset.** Sinon une bande claire de la hauteur de la barre Roblox reste en haut.
- **DisplayOrder negatif.** Le voile passe SOUS toute l'interface : assombrir ses propres boutons n'aurait aucun
  sens.

Et il ne mange aucun clic. Un voile plein cadre qui absorbe l'input rendrait le jeu entier incliquable, et on
chercherait le probleme dans les boutons.

### L'init ne bloque pas

L'attente de PlayerGui se fait en tache de fond. Un `WaitForChild` en ligne droite dans un init de boot gele
toute la sequence le temps du timeout -- piege deja paye ailleurs dans ce projet.

Reglage principal : `BASE_TRANSPARENCY` (0.45). Un vignettage se SENT, il ne se voit pas -- des qu'on peut le
montrer du doigt, il est trop fort.

## 0.0.342 — La camera du demarrage devient VIVANTE

Un plan fixe pendant qu'on tire une corde est MORT : rien ne bouge a l'ecran sauf le personnage, et l'oeil
decroche. Deux mouvements, qui ne font pas la meme chose.

### Un recul CONTINU

La camera part a 10 studs (le geste se lit) et glisse jusqu'a 20 (la scene existe), sur 7 secondes. En ease out :
le gros du recul se fait tot, puis ca se pose -- en lineaire on sentirait la camera "tirer" jusqu'au bout, ce qui
se remarque.

Volontairement LENT. Le recul ne doit jamais se voir bouger, il doit juste AVOIR bouge. Plus court, ca se lit
comme un zoom et l'attention se porte sur la camera au lieu du geste.

Rien de neuf a brancher : le plan etant recalcule a chaque image, il suffit de faire dependre la distance du
temps ecoule depuis le debut de la scene.

### Un A-COUP a chaque coup de corde

La camera se jette de 3 studs vers le joueur, puis repart. C'est la SEULE facon de faire sentir le tirage ici :
les secousses de `CameraEffects` passent par `Humanoid.CameraOffset`, que Roblox ignore purement et simplement
quand la camera est Scriptable (deja au journal).

L'a-coup est pose a l'INSTANT DE L'APPUI, pas en attendant la reponse du serveur. Un retour qui arrive apres un
aller-retour reseau ne se ressent plus comme la consequence de son propre geste.

Il s'amortit dans la BOUCLE et non dans le calcul du plan : un amortissement range dans une fonction de calcul
depend du nombre de fois qu'on l'appelle, pas du temps -- et le jour ou un deuxieme appelant arrive, l'effet fond
deux fois plus vite sans qu'on comprenne pourquoi.

## 0.0.341 — La camera du demarrage recule et descend

- `PULL_CAM_FORWARD` : 9 -> 14. A 9 studs on voyait le joueur, mais pas la SCENE.
- `PULL_CAM_HEIGHT` : 3.2 -> 1.6. Une camera au-dessus du joueur regarde le sol et ecrase la silhouette.

L'oeil passe donc SOUS le point vise (2.2) : la camera regarde legerement vers le haut. C'est ce qui rend un
personnage imposant, et un demarrage de moteur merite ce cadrage-la.

## 0.0.340 — On ne touche plus au bandeau du rideau

Son `UIGradient` n'est pas un reflet a promener : c'est un FONDU dessine dans Studio, dont la transparence monte
de 0 a 1 le long du bandeau pour qu'il ne soit pas plein d'un bout a l'autre.

Le balayage ajoute au 0.0.339 deplacait son `Offset`, ce qui poussait cette rampe HORS du bandeau -- lequel
redevenait donc completement opaque. L'exact contraire de l'intention.

Regle generale, et c'est la deuxieme fois qu'elle se paie sur cet ecran : ne pas EMBELLIR d'un effet non demande.
Un degrade pose a la main porte une intention, et l'animer la detruit sans que rien ne le signale a la lecture du
code.

## 0.0.339 — Le rideau de chargement se DESSINE DANS STUDIO

Le rideau de changement de map n'est plus construit en code. Il CLONE une ScreenGui modele et se contente
d'ANIMER ce qu'il y trouve. Le dessin appartient a l'editeur, le mouvement au code : changer une couleur, une
image ou une police ne demande plus de toucher a ce fichier.

### Ce qui est anime, s'il est trouve

| Nom dans le modele | Ce que le code en fait |
|---|---|
| `Tile` | defile en diagonale, en lisant la taille de tuile POSEE dans Studio |
| `Frame` > premiere `ImageLabel` | oscille, flotte, et SE REMPLIT comme une jauge |
| `Banner` > son `UIGradient` | un reflet le balaie, avec une pause entre deux passages |
| `TipsDescription` | les conseils defilent, en fondu |
| `CanvasGroup` | c'est lui qui fond a la sortie, contenu compris |

Chaque piece est FACULTATIVE. Le modele appartient a l'editeur : renommer ou supprimer un element doit eteindre
son animation, pas casser le rideau.

La taille de tuile est LUE et non reecrite : c'est un choix de dessin, il n'appartient pas au code.

### Ou ranger le modele : ReplicatedFirst

C'est le service replique AVANT tout le reste -- c'est sa raison d'etre -- et rien n'y est recopie
automatiquement dans PlayerGui.

StarterGui est TOLERE, mais Roblox y recopie tout dans PlayerGui A CHAQUE SPAWN. Un deuxieme rideau se collerait
donc par-dessus le notre et resterait affiche pour toujours apres le respawn. Quand le modele est trouve la, le
code desactive la copie locale pour que celle du spawn arrive invisible, et previent qu'il faut le deplacer.

Notre clone est aussi RENOMME : deux instances du meme nom dans PlayerGui, et on ne sait plus laquelle on tient.

### Le piege qu'il a fallu desamorcer

Ce fichier DETRUISAIT `ReplicatedFirst.LoadingScreen` au demarrage -- un reste de l'epoque ou l'ancien ecran
n'etait plus lu. C'est devenu exactement l'endroit ou doit vivre le modele : on supprimait le decor juste avant
de s'en servir.

### Modele introuvable = rideau de secours

Un ecran opaque, sans decor, et un avertissement nomme. Le rideau sert d'abord a CACHER : un rideau laid vaut
mieux qu'un joueur qui voit la map se construire.

### Les conseils

Six conseils EN ANGLAIS (le traducteur de Roblox part de l'anglais ; un texte francais n'est traduit nulle part).
Ils tournent toutes les cinq secondes, en fondu -- un texte qui change d'un coup attire l'oeil comme une erreur.

Le premier est tire AU HASARD : commencer toujours par le meme en ferait le seul que les joueurs connaissent,
puisque beaucoup ne verront qu'un ou deux chargements.

### Cote Studio

Ranger la ScreenGui `LoadingScreen` dans **ReplicatedFirst**. Rojo ne synchronise ni StarterGui ni ReplicatedFirst
autrement que par le code : ce modele est a recopier a la main dans CHAQUE lieu, sinon le collaborateur aura le
rideau de secours.

## 0.0.338 — C rend la souris et le curseur pour de bon

En repassant en vue de dos, la souris restait collee au centre et le curseur custom invisible.

Cause : la boucle de vue subjective reste branchee pendant le glissement de SORTIE -- c'est voulu, elle finit de
faire reapparaitre le corps au rythme de la camera. Mais elle reposait AUSSI la souris et le curseur a chaque
image, juste apres que la bascule les ait rendus au joueur. La derniere de ces ecritures survivait au
debranchement : souris verrouillee et curseur cache, en pleine troisieme personne.

Elle ne touche plus a la souris, au curseur ni au reticule des que la vue subjective n'est plus voulue. Elle ne
s'occupe alors que du corps, la seule chose qui ait besoin de glisser.

Meme famille que la regle du projet sur les proprietes a un seul ecrivain : ici il n'y en avait qu'un, mais il
ecrivait encore apres avoir cesse d'etre legitime.

## 0.0.337 — Alt rend vraiment la souris : on recule d'un cheveu

Maintenir Alt ne rendait ni la souris ni le curseur. C'etait UN seul defaut, pas deux : le curseur custom
REVENAIT bien, mais il suit la position de la souris -- et la souris etant verrouillee au centre, il restait
plante sous le point de visee, indiscernable d'un curseur absent.

### Ecrire MouseBehavior apres Roblox ne suffit pas

C'etait le pari du 0.0.334, et l'ecran l'a tranche : tant que la camera est COLLEE a la tete, Roblox repose son
verrouillage a chaque image et gagne, meme en ecrivant apres lui.

La seule facon de recuperer la souris sans quitter la vue subjective est donc de ne plus y etre TOUT A FAIT.
`CameraEffects.SetFirstPersonGap` laisse un ecart de 1.5 stud entre l'oeil et la tete tant que la touche est
tenue : Roblox renonce, la souris redevient libre, et la vue ne bouge pratiquement pas.

L'ecart ne peut jamais faire RECULER la camera plus que le glissement en cours : au debut du voyage la distance
est encore grande, il ne doit pas s'y ajouter.

### A verifier a l'ecran

1.5 est un pari raisonnable, pas une certitude : le seuil exact a partir duquel Roblox cesse de considerer qu'on
est en vue subjective lui appartient et n'est pas documente. Si la souris reste collee au centre, c'est
`FREE_CURSOR_GAP` qu'il faut monter.

## 0.0.336 — On ne sort plus un taille-haie en poussant la tondeuse

On pouvait tenir les deux a la fois : un outil qui flotte a cote d'un guidon.

### Refuse a l'ALLER, range au RETOUR

Les deux sens ne se traitent pas pareil, et ce n'est pas une incoherence :

- **Sortir un outil pendant qu'on pousse** est REFUSE. Rien a resoudre, l'action n'a pas de sens.
- **Prendre la tondeuse avec un outil en main** RANGE l'outil. Refuser laisserait le joueur appuyer sur E devant
  sa tondeuse sans que rien ne se passe et sans savoir pourquoi : un cul-de-sac. Ranger est ce qu'il aurait fait
  lui-meme.

### Un drapeau sur le JOUEUR, pas sur la machine

`LeafiaCarryingMower`, pose par MowService, meme convention que `LeafiaCarryingLadder`. Sur le joueur parce que
c'est LUI qu'on interroge quand on veut savoir s'il peut sortir un outil -- interroger la machine obligerait a
balayer le monde pour la trouver. Et un attribut de joueur se replique, donc le client le lit aussi sans qu'on
ait a fabriquer un remote.

Le refus est pose dans `ToolService.equip`, la SEULE porte d'entree de l'equipement : la bascule et la selection y
passent toutes les deux, donc il tient quel que soit le chemin. Le client ment toujours, c'est donc bien la que
ca se decide.

### Et cote client aussi, pour ne pas parler dans le vide

L'auto-equip du taille-haie (approcher une haie l'equipe) aurait tire le remote toutes les 0.2 secondes pour
rien : l'outil ne s'equipant jamais, sa condition "pas encore equipe" serait restee vraie pour toujours. Il lit
donc le meme drapeau et se tait.

## 0.0.335 — Le curseur custom disparait, les outils restent, et la bascule GLISSE

Trois corrections sur la vue subjective posee juste avant.

### Le curseur custom restait a l'ecran

Le jeu n'affiche pas le curseur systeme : il en dessine un a lui, une ImageLabel qui suit la souris. Couper
`MouseIconEnabled` ne l'effacait donc pas -- il restait plante au centre, par-dessus le point de visee.

Pire, `CursorController` dit en tete de fichier qu'il est le SEUL ecrivain de `MouseIconEnabled` et du curseur.
Ecrire par-dessus lui n'aurait pas tenu : la derniere des deux boucles a s'executer aurait gagne, une image sur
deux. La vue subjective DECLARE donc son intention (`CursorController.setSuppressed`), et lui seul ecrit.

### On ne voyait pas ses outils

Ce n'est pas `CharacterFade` : il ne touche que les enfants DIRECTS du personnage, et les parts d'un outil sont
plus profondes.

C'est ROBLOX. Son controleur de transparence efface tout le personnage en vue subjective, et il n'EPARGNE que les
parts rangees sous un `Tool`. Nos outils sont des `Model` avec un Motor6D fabrique a la main -- un `Tool` n'a rien
de magique, c'est simplement Roblox qui lui cree son joint tout seul. Ils n'etaient donc pas epargnes.

`CharacterFade.keepToolsVisible` remet leur modificateur a zero A CHAQUE IMAGE, parce que Roblox repose le sien a
chaque image.

Meme piege, une marche plus loin : le garde-fou "ne pas reecrire la meme valeur" de `CharacterFade` faisait que
nos MAINS n'etaient posees qu'une fois -- et Roblox reprenait la main juste apres. D'ou le nouveau parametre
`force`, a n'utiliser que quand quelqu'un d'autre ecrit sur les memes parts en continu.

### La bascule glisse au lieu de couper

Passer d'un coup de la distance du joueur a zero etait un COUP SEC : on se retrouvait dans sa tete sans avoir vu
le chemin, et le retour etait pire. La distance VOYAGE maintenant (`FP_LERP_SPEED`, environ une demi-seconde).

Le corps revient AU MEME RYTHME : l'effacer d'un bloc pendant que la vue glisse encore montrerait un trou a la
place du personnage pendant le voyage. La souris, le curseur et le reticule, eux, sont rendus tout de suite --
ils n'ont rien a interpoler, et garder la souris verrouillee pendant que la vue recule serait desagreable.

La boucle reste donc branchee jusqu'a la fin du glissement, et c'est elle qui se debranche et nettoie. Elle
verifie au passage qu'on n'a pas rebascule en vue subjective entre-temps.

Piege evite au passage : un lerp exponentiel n'atteint JAMAIS sa cible. Sans le calage sur zero, on n'aurait
JAMAIS rendu ses bornes de zoom au joueur -- il n'aurait plus pu zoomer, sans que rien ne l'explique.

## 0.0.334 — VUE SUBJECTIVE chez le client, avec bascule et point de visee

Nouveau `FirstPersonController`. Chez un client on demarre DANS LES YEUX ; `C` bascule vers la vue de dos et
retour. Point de visee au centre, curseur cache, corps efface mais mains et outil visibles.

### Hors du hub, et la regle est negative

`game.PlaceId ~= PlacesConfig.MAIN`. Le hub sert a choisir son plot, construire, lire des interfaces : on y a
besoin de voir son personnage et de cliquer partout. Chez un client, on TRAVAILLE, et le travail se regarde de
pres.

La regle est ecrite comme "tout ce qui n'est pas le hub" et pas comme une liste de lieux : un futur jardin de
client demarrera en vue subjective sans qu'on ait rien a ajouter. Le controller est donc declare dans LES DEUX
branches du bootstrap et se coupe tout seul la ou il n'a pas lieu d'etre.

### On ne fabrique pas de camera

La camera Custom sait deja faire la vue subjective : il suffit de coller ses bornes de zoom a zero. Ecrire
nous-memes sa CFrame reviendrait a nous battre contre les scripts de camera de Roblox, ce qui saccade des que le
joueur bouge la souris.

Ces bornes n'avaient deja qu'UN ecrivain, `CameraEffects` (le recul de camera passe par lui). La vue subjective y
devient donc une DEUXIEME raison via `SetFirstPerson`, et elle PRIME sur le recul -- reculer la vue n'a aucun sens
quand on est dans les yeux. La mise de cote des bornes du joueur est desormais faite a la premiere raison qui se
presente et rendue quand plus aucune ne tient, au lieu d'etre capturee par le recul seul.

### Le corps s'efface, les mains restent

En vue subjective Roblox efface TOUT le personnage, outil compris -- or l'outil est justement ce qu'on veut voir.
`CharacterFade` existait deja et fait exactement ca : corps a 1, mains a 0. Nos outils sont soudes a la main par
un Motor6D, ils restent donc visibles avec elle.

### Ce qui doit etre repose A CHAQUE IMAGE

Roblox reecrit la transparence du personnage ET le comportement de la souris a chaque image quand la camera est
collee a la tete. Une valeur posee une seule fois a la bascule serait effacee a l'image suivante. Le controller
passe donc APRES lui (priorite Camera + 1) et repose la sienne.

### A VERIFIER A L'ECRAN : le curseur rendu par Alt

Maintenir Alt rend le curseur pour cliquer une interface, et efface le reticule pendant ce temps (un point de
visee ET une fleche a l'ecran, on ne saurait plus lequel compte).

C'est le point FRAGILE de ce commit : Roblox re-verrouille la souris au centre a chaque image en vue subjective,
et plusieurs retours signalent qu'une ecriture unique ne tient pas. L'ecriture par image apres lui devrait gagner,
mais ca se verifie a l'ecran et pas au raisonnement. Si le curseur reste colle au centre, il faudra passer par
l'autre approche : figer la vue et rendre la souris.

Pas de bouton tactile pour cette action-la, et c'est voulu : sans souris il n'y a rien a liberer. C'est la seule
exception a la regle "tout input clavier a son pendant tactile" -- la bascule `C`, elle, passe par
ContextActionService et cree bien son bouton sur mobile.

### Le reticule est cree en CODE

Contrairement au reste des interfaces, posees dans Studio. C'est un point de six pixels qui n'a rien a regler a la
main, et le poser dans Studio obligerait a le recopier dans CHAQUE lieu (Rojo ne synchronise pas StarterGui).
Meme raison que l'ecran de chargement, qui se construit aussi tout seul.

Aucun inset sur son ScreenGui : le point doit tomber au centre exact de l'ECRAN, pas au centre de la zone sous la
barre Roblox, sinon il vise dix-huit pixels trop bas.

## 0.0.333 — L'herbe se rechauffe : elle tirait sur le bleu

`BASE_COLOR` : 72, 90, 45 -> 138, 154, 85.

### Saturation et temperature ne sont pas le meme reglage

C'est l'erreur commise au 0.0.327, et elle valait une iteration :

- La SATURATION est l'ecart entre le vert et le bleu.
- La TEMPERATURE est l'ecart entre le rouge et le bleu.

Pour desaturer, j'avais monte le bleu. Ca marche -- mais ca refroidit la couleur du meme coup, et l'herbe a vire
au bleu-vert. La regle juste : pour desaturer sans refroidir, il faut monter le ROUGE autant que le bleu.

Elle est ecrite dans la config, avec les trois valeurs successives et ce que chacune a change.

## 0.0.332 — Les roues tournent enfin, la camera filme le demarrage, et les bandes marchent dans tous les sens

### Les roues ne tournaient pas du tout

Deux erreurs cumulees, et aucune ne disait rien :

1. Le code cherchait des joints nommes `BackWheel` / `FrontWheel`. Ils s'appellent `WheelBackMotor6D` et
   `WheelFrontMotor6D`.
2. Il les cherchait sous la seule RootPart. Dans le rig, chaque joint est range SOUS SA ROUE.

La recherche balaie maintenant tout le modele, et les joints trouves sont memorises (une entree : on ne porte
qu'une machine a la fois, donc rien a nettoyer, et on ne parcourt pas les descendants a chaque image).

Surtout, elle PARLE quand elle ne trouve rien. Une liste renseignee et aucun joint qui porte ces noms, c'est
anormal et actionnable -- sans ce message on regarde une tondeuse qui glisse sans savoir ou chercher.

### La camera passe devant pour le tirage de corde

Pendant qu'on tire la corde, la camera vient DEVANT la machine, un peu de cote, et regarde le joueur. Le
demarrage est le seul moment ou le joueur ne fait qu'une chose : autant la montrer. En vue de conduite on est
derriere lui et on ne voit rien du geste.

Le champ de vision s'ELARGIT lentement pendant ce temps (`PULL_CAM_FOV`), ce qui donne le recul demande.

Tout est en OFFSETS RELATIFS AU JOUEUR, jamais en positions monde, et le focus est re-ancre sur sa position VIVE
a chaque image. L'arrivee part de l'etat EXACT de la camera de jeu (mesure, pas devine : la distance camera ->
Focus est le vrai zoom) et le retour y revient, donc aucun saut ni au debut ni a la fin. Le retour part du plan
COURANT, pas de la cible theorique : on peut lacher la machine en pleine arrivee.

Le champ de vision avait deja un ecrivain (le recul de la revelation). Les deux raisons s'ADDITIONNENT maintenant
dans une seule ecriture, dans `applyCameraRig` -- deux ecrivains se seraient ecrases a tour de role.

Le pilotage est lu AU-DESSUS de la sortie anticipee de la boucle : sinon lacher la machine n'aurait jamais
relache la camera, et elle serait restee plantee sur un plan sans rien a filmer.

### Les bandes ne marchaient que dans un sens

La bande vient de `direction de tonte . axe appris` : parallele donne 1, sens inverse -1, et PERPENDICULAIRE
donne ZERO -- donc aucune bande. Rouler en travers de sa premiere passe ne marquait rien.

`MOW_STRIPE_SHARPNESS` (3) multiplie avant de borner : tout ce qui s'ecarte de plus d'environ 20 degres de la
perpendiculaire sature a fond. On obtient donc une bande FRANCHE dans presque toutes les directions, et le
degrade ne subsiste que dans l'etroit couloir ou l'on roule vraiment en travers.

`MOW_STRIPE_STRENGTH` monte aussi, 0.22 -> 0.32.

## 0.0.331 — L'herbe coupee SORT DU SOL au lieu d'apparaitre par-dessus

On voyait qu'on AJOUTAIT une herbe, pas qu'on en coupait une. Deux causes, toutes les deux corrigees.

### 1. Tout arrivait en meme temps, en un huitieme de seconde

La coupe dure 0.125 s (`MOW_RATE`), et la couleur etait branchee dessus. A l'instant ou le maillage changeait, la
touffe etait donc DEJA a mi-chemin de la teinte tondue : le nouveau mesh apparaissait deja colore.

L'emergence a maintenant son PROPRE temps (`CUT_RISE_TIME`, 0.35 s), independant de l'avancement de la coupe. La
touffe sort avec la couleur de l'herbe HAUTE et devient tondue en montant.

### 2. Elle apparaissait par-dessus

Au moment de l'echange, la touffe coupee est desormais ENFONCEE sous la surface, et elle remonte a sa place. Elle
a l'air d'avoir toujours ete la, dessous, cachee par l'herbe haute -- ce qui est d'ailleurs la verite d'une
pelouse.

L'enfoncement est RELATIF a la hauteur de la touffe (`CUT_RISE_DEPTH`, 1 = entierement sous la surface) et pas en
studs : l'herbe n'a pas la meme taille partout, et une valeur absolue laisserait les grandes depasser en
enterrant les petites trop profond.

### Le piege de la porte de redessin

`mown` atteint 1 en 0.125 s et ne bouge plus. Une touffe n'etant redessinee que lorsqu'une de ses valeurs change,
l'emergence se serait arretee net : la touffe serait restee ENFOUIE et de la couleur de l'herbe haute pour
toujours, sauf coup de vent. Il a donc fallu ajouter l'avancement de l'emergence aux deux portes (celle qui
compte les touffes en mouvement, et celle qui decide de redessiner).

### Marcher sur l'herbe deja tondue se voit a nouveau

`MOW_CRUSH_DAMP` : 0.9 -> 0.55. A 0.9, marcher sur une pelouse deja tondue ne changeait plus RIEN, et on perdait
le retour du pas sur toute la partie du jardin qu'on venait de finir. A 0.55 il en reste assez pour voir ou l'on
est passe, sans laver la bande de tonte.

## 0.0.330 — L'herbe tondue devient nettement plus claire

`MOWN_COLOR` : 73, 91, 45 -> 159, 197, 97. Le passage de la tondeuse se voit enfin sans avoir a chercher.

### Pourquoi ce revirement se tient

Une version claire avait deja ete essayee, puis REJETEE : la pelouse tondue avait l'air ECLAIREE, comme un
projecteur pose dessus, au lieu d'avoir l'air rase. On etait donc revenu a une teinte quasi identique a l'herbe
haute -- lisible dans le code, invisible a l'ecran.

Ce qui a change entre-temps, c'est le 0.0.329 : l'herbe coupee a maintenant son PROPRE MAILLAGE. C'est la FORME
qui dit "coupe" desormais, la couleur n'a plus a porter ce sens toute seule. Elle peut donc etre claire sans se
lire comme de la lumiere.

L'historique est ecrit dans la config, pour ne pas refaire le tour une troisieme fois.

## 0.0.329 — L'herbe tondue CHANGE DE FORME, elle ne fait plus que raccourcir

Le mesh `GrassCut` (range a cote de `GrassMesh` sous `Assets/Contents/Foliages`) remplace le maillage de la touffe
quand elle est coupee. Une herbe rase n'a pas la forme d'une herbe haute qu'on aurait tassee, et l'oeil le sait :
raccourcir seulement, ca fait de l'herbe haute ecrasee, pas de l'herbe tondue.

### Comment on change un mesh a l'execution

Verifie dans la doc, pas suppose : `MeshId` et `MeshContent` sont marques "Not Accessible Security" et ne
s'ecrivent PAS depuis un script normal. La seule voie est `MeshPart:ApplyMesh(autreMeshPart)`, qui remplace le
maillage SUR PLACE -- donc sans creer ni detruire une seule instance, ce qui compte quand la pelouse en aligne des
milliers.

En contrepartie elle exige un MeshPart DEJA present en jeu portant le bon maillage : c'est le role du template
garde en ReplicatedStorage, comme pour l'herbe haute et les fleurs.

### L'echange a MI-COUPE

`MOW_SWAP_AT` (0.5) : la touffe est alors deja bien tassee, sa silhouette est petite, donc le changement de forme
passe inapercu. Echanger des le premier contact la ferait sauter a pleine hauteur, et on verrait le remplacement
au lieu de la coupe.

### Ce qu'on ne suppose pas

On ignore ce qu'`ApplyMesh` reecrit au juste (taille ? texture ? materiau ?). Plutot que de parier, les caches de
taille et de couleur sont invalides pour que nos valeurs soient reposees dans la foulee. Le materiau, qui n'a pas
de cache numerique a invalider, est remis directement dans l'etat que son cache DECRIT -- sinon tondre en
maintenant G aurait laisse un materiau incoherent.

### Absent = degrade, pas casse

Sans le mesh, la touffe raccourcit comme avant. Le message d'avertissement ne sort que si `CUT_MESH_NAME` est
renseigne ET introuvable : la, c'est actionnable, et sans lui on chercherait le probleme dans la tonte.

### Cote Studio

Le mesh `GrassCut` doit exister sous `ReplicatedStorage/Assets/Contents/Foliages`. Rojo ne synchronise PAS les
Assets : le collaborateur doit l'ajouter a la main, sinon l'herbe tondue gardera l'ancienne forme chez lui.

## 0.0.328 — Le ciel arrete de s'empiler sur une seule bande

Les nuages se chevauchaient, s'alignaient, et laissaient le reste du ciel vide. Ce n'etaient pas trois defauts
mais UN SEUL, dans le recyclage.

### Le bug

Un nuage sorti du champ etait remis en amont du vent a cette position :

    -vent * rayon + cote * lateral

Sa distance au centre valait donc `racine(rayon^2 + lateral^2)`, c'est-a-dire **deja hors du rayon**. Le test de
sortie le reprenait a l'image SUIVANTE, et encore, et encore : il ne derivait jamais, il sautait au hasard le long
d'une droite.

Seuls les nuages tires PILE dans l'axe du vent (ecart lateral proche de zero) tombaient dans le champ et
survivaient. D'ou un ciel ou tout finissait aligne et empile sur une bande, avec du vide autour.

### Le correctif

Le nuage revient maintenant sur l'ARC amont : au meme ecart lateral, mais a la distance qui le pose exactement
sur le cercle (un cheveu en dedans, parce que pile sur le bord l'arrondi des flottants peut refaire passer le
test). Il ENTRE dans le disque au lieu d'en etre deja sorti.

### Anti-chevauchement

Chaque pose essaie jusqu'a `SEPARATION_TRIES` (6) positions et garde celle qui laisse le plus de place, en visant
`MIN_SEPARATION` (130 studs, un peu plus qu'un gros nuage). Ce n'est PAS une garantie : sur un ciel dense il
n'existe pas toujours de trou, et boucler jusqu'a en trouver un figerait le jeu. On garde donc le meilleur des
essais. Le calcul n'a lieu qu'A LA POSE, jamais par image.

### Couverture

`COUNT` : 28 -> 55, et `FADE_START` : 0.5 -> 0.62 (les nuages restent nets plus loin avant de se fondre). A
surveiller cote FPS : le cout d'un nuage est un CFrame par image, mais le RENDU de 55 gros meshes translucides
qui se superposent, lui, se paie. Si ca descend, `COUNT` est le bouton.

## 0.0.327 — L'herbe perd son vert de peinture

La pelouse etait trop saturee : un vert de pot, pas un vert de jardin.

| Couleur | Avant | Apres |
|---|---|---|
| `BASE_COLOR` (repos) | 66, 94, 30 | 72, 90, 45 |
| `MOWN_COLOR` (tondue) | 67, 95, 30 | 73, 91, 45 |
| `CRUSHED_COLOR` (trace) | 186, 219, 128 | 184, 205, 147 |

### La regle, pour ne plus tatonner

La saturation, c'est l'ECART entre le canal le plus fort (le vert) et le plus faible (le bleu). Pour un vert moins
criard on MONTE le bleu et on BAISSE le vert. La luminosite ne bouge pas : elle suit la moyenne des trois.

L'ecart passe de 64 a 45 sur la couleur de repos. Pour aller plus loin vers l'olive, continuer a rapprocher les
deux.

### Les trois bougent ENSEMBLE

N'en desaturer qu'une aurait rendu les deux autres plus vives PAR COMPARAISON. La trace du joueur, la plus criarde
des trois, serait devenue un trait fluo sur une pelouse redevenue calme -- et ca se serait lu comme un bug
d'affichage, pas comme un reglage.

## 0.0.326 — Le vent ralentit

Deux vitesses baissent, et il faut savoir laquelle fait quoi -- elles sont souvent confondues :

- `WIND_SPEED` : 1.7 -> 1.1. Le rythme auquel CHAQUE touffe va et vient sur elle-meme.
- `GUST_SPEED` : 9 -> 5.5. La vitesse a laquelle la VAGUE traverse la pelouse, en studs par seconde.

Une herbe qui vibre vite sous une vague lente donne du frisson. L'inverse donne une houle molle. Les deux se
reglent separement, et c'est voulu.

A 9 studs/s, la vague balayait la pelouse plus vite qu'on ne marche dessus : ca se lisait comme un balayage
d'effet, pas comme du vent. A 5.5 elle avance a peu pres a l'allure d'un promeneur.

## 0.0.325 — Le vent se devine au lieu de s'annoncer

La crete Shamrock se lisait comme de la peinture verte etalee sur la pelouse. Deux reglages baissent ensemble
dans `GrassZoneConfigs` :

- `GUST_TINT` : 0.55 -> 0.22. Quelle part de la couleur de crete arrive sur la touffe.
- `GUST_TINT_SHARPNESS` : 2.2 -> 3.4. A quel point l'effet se CONCENTRE sur le haut de la vague.

### Pourquoi les deux et pas seulement le premier

Baisser la teinte SEULE aurait rendu l'effet fade PARTOUT au lieu de le rendre discret : la rafale est un champ
doux, donc un teintage faible mais large se lit comme un aplat un peu delave sur toute la pelouse.

Resserrer la crete en meme temps concentre le peu qui reste la ou la vague passe vraiment. On la voit encore --
mais seulement la, et une seconde a la fois. C'est ce qui la fait passer pour du vent plutot que pour un effet.

Les deux vont donc ensemble : remonter l'un sans toucher l'autre ramenera le probleme.

## 0.0.324 — La fleur FOND sous le carter avant de disparaitre

Elle sautait des le premier contact : ca se lisait comme un bug, pas comme une coupe. Maintenant elle retrecit
pendant qu'elle passe SOUS la machine, puis disparait quand il n'en reste presque rien.

Deux reglages, dans `GrassZoneConfigs` :

- `FLOWER_MOW_RATE` (2.5) : 0.4 s sous le carter, au lieu des 0.125 s de l'herbe. C'est le temps de la VOIR
  passer dessous. A la vitesse de l'herbe, la fonte serait invisible et on retomberait sur le saut.
- `FLOWER_MOW_SHRINK` (0.9) : il n'en reste qu'un dixieme au moment ou elle est detruite, donc le saut final ne
  se voit pas.

### Sur les TROIS axes, et elle descend

Retrecir seulement en HAUTEUR aurait fait une crepe posee au sol. En la faisant fondre sur les trois axes, elle a
l'air avalee par la machine.

Le meme facteur s'applique a sa TIGE : sans ca elle retrecissait en restant perchee, et on la voyait disparaitre
en l'air au lieu de passer sous le carter.

L'herbe ne change pas d'un poil : ce facteur vaut 1 pour elle.

## 0.0.323 — La tondeuse FAUCHE les fleurs au lieu de les raccourcir

Jusqu'ici une fleur tondue se contentait de rapetisser. Maintenant la lame passe dessus et il n'en reste rien.

Ca ne fait pas que coller a la realite : c'est ce qui rend le passage LISIBLE dans un coin fleuri. L'avant /
apres se voit d'un coup d'oeil, au lieu de demander au joueur de comparer deux verts.

### La touffe est marquee, pas retiree des listes

Le nettoyage d'une zone d'herbe se fait en detruisant le DOSSIER entier, jamais touffe par touffe. Retirer la
fleur d'une liste et pas de l'autre n'aurait donc fabrique qu'une reference morte a moitie oubliee -- typiquement
le nettoyage reparti qui finit par en oublier un.

Elle porte donc un drapeau `gone`, sa part est detruite, et les deux boucles qui la parcouraient (l'animation par
image et la coupe) la sautent en une comparaison. Le champ `flower` devient explicite sur la touffe, au lieu de se
deduire de sa hauteur de tige.

Une fleur n'est fauchee que par la TONTE. Marcher dessus continue de la coucher sans l'abimer, comme avant.

## 0.0.322 — On ne promene plus une tondeuse eteinte, et elle tourne trois fois plus

### Moteur arrete, on ne bouge pas

On pouvait prendre la tondeuse et partir avec sans jamais tirer la corde. Le demarrage n'etait alors qu'une
animation qu'on pouvait ignorer, et la coupe -- deja bloquee, elle -- semblait cassee plutot que voulue.

Maintenant c'est un poids mort : ni avance, ni braquage tant que le moteur n'a pas pris. Les deux consequences du
demarrage (on avance, on coupe) se lisent donc au meme endroit et dependent du meme attribut.

Bloque des DEUX cotes. Le client se coupe tout seul pour que ca reponde tout de suite, et il ECRIT zero au lieu
de simplement sortir : son bind passe APRES le module de controle de Roblox, donc ne rien faire laisserait la
demande de deplacement de Roblox s'appliquer. Le serveur, lui, met la vitesse cible a zero -- c'est lui
l'autorite, le client ment toujours.

La vitesse de depart passe de `SPEED_MIN` a zero : sans ca, la machine avancait une demi-seconde avant que la
rampe ne la freine.

### Trois fois plus de braquage en pleine avance

`STEER_TURN_RATE` passe de 60 a 180 degres par seconde, soit un demi-tour par seconde.

Historique note dans la config pour ne pas refaire l'aller-retour : 120 au depart, descendu a 60 parce que ca
tournait trop vite, remonte a 180 parce que ca ne tournait plus assez. On est donc AU-DESSUS du point de depart.
Si ca redevient trop vif, la valeur juste est entre 120 et 180, pas en dessous.

## 0.0.321 — Le rideau retrouve le fond TUILE de l'ecran principal, et la feuille se remplit dans le bon sens

Les trente feuilles individuelles qui derivaient sont supprimees. A la place, le MEME fond que l'ecran de
chargement principal : la meme image, tuilee, qui defile en diagonale.

Les reglages de taille et de vitesse (`TILE_SCALE_X`, `TILE_SCALE_Y`, `TILE_SPEED`) sont remontes en tete de
fichier et servent maintenant aux DEUX ecrans. En changer un change les deux, et c'est exactement ce qu'on veut
puisque le rideau doit ressembler au principal.

Cout au passage : trente instances et une boucle par image en moins, pour un resultat qu'on ne voyait meme pas.

### La transparence, elle, ne peut pas etre la meme

Les deux fonds n'ont rien a voir : l'intro pose sa tuile sur un ciel CLAIR, le rideau sur du gris SOMBRE (31).
`CURTAIN_TILE_TRANSPARENCY` est donc un reglage a part, calcule et non devine :

    couleur RENDUE = fond + (teinte - fond) x (1 - transparence)
    31 + (255 - 31) x 0.1 = 53, soit 22 points au-dessus du fond

Une note precedente de ce fichier affirmait qu'il fallait ASSOMBRIR sur un fond deja sombre. Elle etait FAUSSE :
sur un fond a 31, eclaircir dispose de 224 points d'ecart, assombrir de 31 seulement. Le raisonnement ne valait
qu'a transparence zero. Corrige sur place.

### Sens du remplissage

`FILL_ROTATION` passe de 90 a 270. Le 90 avait ete pose au juge et c'etait l'envers -- comme prevu, seul l'ecran
pouvait trancher.

## 0.0.320 — Un bruit de feuille accompagne le rideau de chargement

Joue une fois, au moment ou la feuille apparait. Tire AU HASARD dans `SoundService/Sounds/Environnement/Leafs` --
le dossier ou la haie pioche deja a chaque coupe. Deux chargements de suite ne sonnent donc pas pareil, et
deposer un echantillon de plus dans Studio suffit a varier, sans toucher au code.

### Le son est CHERCHE en boucle, pas une seule fois

Ce rideau vit dans ReplicatedFirst : quand il s'affiche, SoundService n'a pas forcement encore recu ses dossiers.
Un `FindFirstChild` unique a cet instant aurait rendu nil, et le son ne serait JAMAIS parti -- sans la moindre
erreur a l'ecran ni dans la console. On re-scanne donc pendant six secondes, en tache de fond pour ne rien
bloquer. "Absent au demarrage" est un etat normal, pas une panne.

### Rangement

`findSound` est REMONTEE au-dessus du rideau : le rideau se termine par un `return`, donc une fonction definie
plus bas ne pouvait pas etre atteinte depuis ce chemin. Elle se decompose maintenant en `findByPath` (descend le
chemin), `findSound` (exige un Sound) et `findAnySound` (accepte un dossier et tire au hasard). La musique
continue de passer par `findSound`, inchangee.

Volume dans `LEAF_SOUND_VOLUME` (0.35), a regler a l'oreille.

### Cote Studio

Aucun asset a ajouter : le dossier existe deja. Si tu le renommes ou le deplaces, le son se tait sans rien dire.

## 0.0.319 — La feuille du rideau se REMPLIT au lieu de briller

Elle part invisible et se revele petit a petit, comme une jauge en forme de feuille. Le joueur ne voit plus
seulement "ca charge", il voit COMBIEN il reste. Une attente qu'on peut mesurer est toujours plus courte qu'une
attente muette -- c'est la difference entre l'impatience et l'ennui.

Remplace le reflet qui balayait, ajoute juste avant : deux animations qui disent la meme chose se volent
l'attention, et celle-ci en dit plus.

### Par la TRANSPARENCE, pas par la couleur

La partie pas encore remplie est transparente : on voit le fond a travers, donc la feuille se confond avec lui
exactement la ou elle n'est pas encore arrivee. Peindre la feuille couleur du fond aurait donne le meme debut,
mais rien n'aurait pu la faire APPARAITRE ensuite -- une couleur ne se retire pas, une transparence si.

Le bord est ADOUCI (`FILL_SOFT`) : une coupure franche se lit comme un masque, un degrade comme un liquide qui
monte.

Duree calee sur celle du rideau (10 s) : une jauge qui se remplit avant la fin ment sur ce qu'il reste.

### A verifier a l'ecran

Le SENS d'un UIGradient ne se deduit pas -- deja au journal, au meme titre que `GetMouseLocation`. Si la feuille
se VIDE au lieu de se remplir, ajouter 180 a `FILL_ROTATION`.

## 0.0.318 — Un reflet balaie la feuille du rideau de chargement

Meme motif que le logo de l'ecran d'intro : un UIGradient avec une bande claire au milieu, dont l'`Offset` glisse
d'un bord a l'autre, avec une PAUSE entre deux passages. Un reflet continu se lit comme un clignotement -- c'est
le silence entre deux passages qui le rend precieux.

### Le piege du multiplicateur

Un UIGradient MULTIPLIE l'`ImageColor3`. Il ne peut donc qu'ASSOMBRIR : on ne depasse pas le blanc. Pour obtenir
une bande PLUS CLAIRE que la feuille, on monte sa teinte jusqu'a la valeur du reflet, et le degrade la RAMENE a sa
valeur normale partout ailleurs.

Le ratio est calcule depuis les deux couleurs plutot qu'ecrit a la main : changer l'une garde l'autre juste.

Legere inclinaison (20 degres) : un reflet parfaitement vertical se lit comme une barre, pas comme une lumiere.

La boucle meurt avec le rideau (`while sg.Parent`), comme la derive des feuilles du fond -- un `while true`
tournerait toute la session sur une instance detruite.

## 0.0.317 — La tondeuse ne claque plus dans l'axe quand on lache le virage

Un seul reglage servait a la fois la mise en travers et le retour droit. En lachant la touche, la machine se
realignait derriere le joueur en 0.17 seconde : elle CLAQUAIT dans l'axe de la marche, et rien ne ressemble moins
a une machine lancee.

`SWING_RECOVER` (6) garde la mise en travers rapide -- la machine repond au braquage. `SWING_RETURN` (1.6) rend le
retour lent : elle revient droite toute seule, portee par son elan.

C'est l'ECART entre les deux qui fait l'effet, pas leur valeur. Meme regle que le ballant lui-meme : ecraser vite
et se relever lentement, c'est ce qui fait lire le poids.

Encore un reglage partage qu'il fallait dedoubler. C'est le quatrieme sur cette feature seule.

## 0.0.316 — Les feuilles du rideau deviennent NOIRES, et existent vraiment

Toujours invisibles. Deux causes, et la premiere est une erreur repetee.

### La meme faute d'arithmetique, deux fois

La teinte avait ete montee a 78 au 0.0.312... puis la transparence remise a 0.82 en passant aux feuilles
individuelles. Rendu : 31 + (78 - 31) x 0.18 = 39. Huit points d'ecart sur un fond a 31. Invisible, comme la
premiere fois.

La formule etait deja ecrite dans le fichier, elle n'a pas ete refaite en changeant l'autre valeur. Elle est
maintenant posee juste au-dessus des DEUX reglages, avec le calcul concret : on ne peut plus toucher a l'un sans
lire l'autre.

Les feuilles passent au NOIR, comme le proposait le joueur. Sur un fond deja sombre, eclaircir laisse peu de
marge -- assombrir en donne 31 d'un coup. Rendu : 31 + (0 - 31) x 0.65 = 11, soit 20 points SOUS le fond.

### Une largeur a zero

La taille etait donnee en Y seulement (`fromScale(0, size)`), en comptant sur l'`UIAspectRatioConstraint` pour
recalculer la largeur. C'est un pari : si la contrainte ne s'applique pas comme prevu, la feuille fait zero pixel
de large et on ne voit RIEN -- sans la moindre erreur en console.

Les deux axes sont desormais donnes ; la contrainte ne fait plus que rendre la feuille carree. Elle CORRIGE au
lieu de FABRIQUER.

Tailles reduites encore : 0.014 a 0.038 de la hauteur d'ecran.

## 0.0.315 — La bande de tonte ne s'efface plus derriere le joueur

Diagnostic du joueur, et il etait juste : la couleur de la bande apparaissait puis disparaissait aussitot. Deux
effets passaient PAR-DESSUS elle dans la chaine de couleurs.

### L'ecrasement, et c'etait systematique

L'ordre des melanges est : repos, tondue (+ bande), ECRASEMENT, rafale, revelation. L'ecrasement fond vers une
couleur FIXE, donc il lavait la bande.

Et ca arrivait a chaque fois, pas de temps en temps : le joueur marche JUSTE DERRIERE la tondeuse, et son rayon
d'ecrasement (4.5) couvre exactement ce qu'il vient de couper. Il effacait sa propre bande a chaque pas.

`MOW_CRUSH_DAMP` retire 90 % de la teinte d'ecrasement sur une touffe tondue. C'est aussi le bon sens : on
n'ecrase pas de l'herbe deja rase. L'APLATISSEMENT continue, lui -- il est geometrique, pas colorimetrique.

### Le teintage de rafale

Il gardait 15 % de son effet sur l'herbe tondue (le meme facteur que le balancement). Il passe a ZERO : un gazon
ras ne vague pas, donc il ne change pas de couleur.

Le BALANCEMENT, lui, garde sa part : un reste de fremissement est joli, un reste de couleur efface le travail du
joueur. Les deux avaient ete branches sur le meme facteur -- c'etait une erreur, ils ne racontent pas la meme
chose.

### Ce que ca dit

Quand plusieurs effets ecrivent la meme propriete, le dernier gagne. Il ne suffit pas que chacun soit juste : il
faut decider ce qui doit SURVIVRE aux autres. Ici c'est le travail du joueur -- tout le reste est du decor.

## 0.0.314 — Le fond du rideau devient un semis de feuilles qui derivent

La tuile est remplacee par des feuilles INDIVIDUELLES. Une image tuilee repete le MEME motif a la MEME taille :
elle ne peut pas varier, par construction. Trente instances coutent trois fois rien et donnent la taille, la
rotation et la transparence au hasard -- c'est ce desordre qui empeche l'oeil de lire une grille.

- Trois fois PLUS PETITES qu'avant.
- Bien plus TRANSPARENTES (0.82, avec un ecart au hasard par feuille).
- Elles DERIVENT en diagonale et se recyclent en boucle.

La diagonale n'est pas un caprice : un defilement purement horizontal ou vertical se lit comme un decor qui
glisse, alors qu'une diagonale se lit comme un mouvement propre. L'ecran d'intro fait deja ce choix.

### Deux details qui evitent des defauts classiques

La taille est donnee en Y seulement, avec un `UIAspectRatioConstraint` en `DominantAxis.Height` : exprimee en X,
elle changerait avec le format de l'ecran et les feuilles seraient ovales sur un ultra-large.

Le recyclage se fait par MODULO avec une marge de 0.2 : la feuille disparait avant de reapparaitre de l'autre
cote. Sans cette marge, on la verrait sauter au bord.

### La boucle est COUPEE a la sortie

Elle vit sur `RunService`, pas sur le GUI : detruire le rideau ne la couperait pas, elle tournerait sur des
instances mortes toute la session. Regle deja au journal, et deja payee sur l'ecran d'intro.

## 0.0.313 — La bande de tonte suit vraiment le sens ou l'on est passe

Deux bugs, et le premier expliquait tout.

### Une touffe deja coupee ne changeait plus jamais de bande

`mowAt` sautait toute touffe deja tondue a fond -- une optimisation raisonnable pour la COUPE, catastrophique pour
la BANDE : elle restait figee sur la premiere passe, et repasser dans l'autre sens ne changeait plus rien. Or
c'est tout l'interet de l'effet. Une vraie tondeuse reecrit la bande a chaque passage.

La coupe garde son raccourci (elle ne s'incremente que tant qu'il reste a couper), la bande se reecrit toujours.
Et elle reveille le pave quand elle change, sinon la nouvelle valeur ne serait pas dessinee.

### On lisait le CAP, pas le DEPLACEMENT

Le sens transmis etait celui de la machine. En marche arriere les deux sont opposes -- et c'est bien le passage du
CARTER qui couche les brins, donc la bande doit s'inverser quand on recule.

On envoie desormais le deplacement REEL, mesure entre deux images. A l'arret on garde le cap : il n'y a rien a
coucher, autant ne pas ecrire n'importe quoi.

### Le cabrage devient un RESSORT

Trois fois moins fort (12 degres -> 4), et surtout : la premiere version POSAIT l'angle d'un coup, en une image.
La montee etait instantanee, donc brutale -- c'etait ca le vrai defaut, pas l'amplitude.

C'est maintenant un ressort amorti : la machine se souleve, freine, revient, avec un leger depassement. Meme
mecanique que la plongee d'atterrissage de `CameraEffects`, et pour la meme raison, qui y est deja ecrite : "un
simple decalage qui revient a zero donnait un TAC".

On pousse la VITESSE du ressort, pas sa position. Les deux valeurs sont clees a zero : un ressort tend vers zero
sans jamais l'atteindre, et une vitesse residuelle relancerait le calcul a vie pour un angle invisible.

## 0.0.312 — Le fond tuile du rideau se voit vraiment

Il etait invisible, et le calcul le disait deja : teinte 48 a 55 % de transparence sur un fond a 31 rend 39 --
8 points d'ecart sur 255. Sous ~20 points, l'oeil ne voit rien.

Formule a garder : `couleur RENDUE = fond + (teinte - fond) x (1 - transparence)`. Elle se fait de tete et evite
de livrer un effet qui n'existe pas.

Nouvelles valeurs : 78 a 25 % de transparence, soit 66 a l'ecran -- 35 points d'ecart. Visible, et ca reste une
texture.

L'ordre des calques est maintenant EXPLICITE des deux cotes (fond a 1, feuille a 2) au lieu de reposer sur la
valeur par defaut de l'un des deux.

### Un masquage de nom evite

Les reglages du rideau prennent le prefixe `CURTAIN_`. L'ecran d'INTRO a deja ses propres `TILE_TINT`,
`TILE_TRANSPARENCY` et `TILE_SCALE_*` en haut du fichier : des locaux du meme nom les MASQUAIENT dans le bloc du
rideau. Ca marchait, mais on aurait fini par croire regler l'un en reglant l'autre.

## 0.0.311 — Un fond tuile derriere le rideau de chargement

Le rideau gris (celui de tous les lieux sauf le 1er lancement) avait un aplat uni. Il tient DIX secondes, et un
aplat pendant dix secondes se lit comme un ecran fige : on croit que le jeu a plante. Une texture dit que la page
est vivante meme quand rien ne bouge.

Tuile avec la MEME feuille que celle du milieu, teintee A PEINE au-dessus du fond. C'est une TEXTURE, pas un
motif : la feuille centrale doit rester la seule chose qu'on regarde. Deux elements qui reclament l'attention se
la volent, et on ne voit plus ni l'un ni l'autre.

Enfant du CanvasGroup, donc il s'efface AVEC le rideau -- rien de plus a fondre.

`TileSize` en SCALE (fraction de l'ecran) pour suivre toutes les resolutions, avec X et Y SEPARES : un ecran n'est
pas carre, a valeur egale la feuille serait etiree. Ces deux valeurs se reglent a l'oeil, il n'y a rien de
calculable.

Pas d'animation dessus, et c'est un choix : la feuille du milieu oscille deja, et le commentaire du fichier note
justement qu'on a retire les boules qui rebondissaient parce que deux animations qui disent la meme chose se
volent l'attention.

## 0.0.310 — Les bandes de tonte se voient enfin : l'axe s'APPREND

Le joueur ne voyait aucune difference entre un aller et un retour. Deux causes.

### L'axe etait FIGE dans la config

Les bandes etaient donc franches en tondant LE LONG de cet axe, et strictement INVISIBLES en tondant
perpendiculairement -- les deux sens y donnaient la meme valeur. La limite avait ete annoncee au 0.0.305, mais
elle rendait l'effet inutilisable en pratique : personne ne tond en verifiant d'abord l'orientation d'une config.

L'axe est desormais APPRIS de la PREMIERE passe. Il faut une reference pour distinguer un aller d'un retour, et
comme on tond en aller-retour, la premiere passe est la meilleure reference possible : tout le reste s'y aligne ou
s'y oppose, quelle que soit l'orientation du jardin.

`MOW_STRIPE_AXIS` reste, mais a `Vector3.zero` : un vecteur non nul le fige a nouveau, pour un decor ou l'on veut
des bandes dans une direction imposee.

### Le contraste etait trop faible

`MOW_STRIPE_STRENGTH` passe de 0.13 a 0.22. Ne pas depasser ~0.3 : au-dela ca se lit comme des rayures PEINTES, et
on retombe exactement dans ce que l'ancien systeme faisait de faux.

## 0.0.309 — On braque MOINS en roulant, PLUS a l'arret

`STEER_TURN_RATE` tombe de 120 a 60 degres/s : un quart de tour prend 1.5 s au lieu de 0.75. Une machine LANCEE a
de l'inertie, elle ne pivote pas.

`STEER_CRAWL_TURN_RATE` monte de 18 a 30 : a l'arret il n'y a pas d'inertie a vaincre, on repositionne librement.

C'est l'INVERSE de l'intuition -- on croit qu'aller vite doit tourner vite -- mais c'est ce qui se ressent juste,
machine en main. Le joueur l'a senti a l'ecran avant qu'on le raisonne.

Aucun code touche : les deux taux avaient ete separes des le depart, precisement pour que regler l'un ne force pas
a compenser l'autre. C'est ce qui rend ce genre d'ajustement gratuit.

## 0.0.308 — Le moteur ne prend qu'au deuxieme ou troisieme coup

Un moteur qui demarre du premier coup a chaque fois se lit comme un interrupteur. Il faut maintenant 2 ou 3
tirages, tires au sort A LA PRISE -- et c'est ce qui rend le demarrage reussi satisfaisant.

Tire a la prise et non a chaque tirage : sinon le compte changerait en cours de sequence, et le moteur pourrait ne
jamais prendre (ou prendre au premier coup). `PULL_TRIES_MIN == PULL_TRIES_MAX` donne un nombre fixe.

Sur un tirage RATE, la piste se REARME : le joueur revient en position, corde en main, et peut retirer tout de
suite. La poignee ne retourne PAS sur la machine -- il ne l'a jamais lachee.

Deux details qui ont demande de l'attention :
- On relance la piste avant de la figer. Une piste terminee ne repart pas en ecrivant sa `TimePosition`.
- `Stopped` passe de `Once` a `Connect` : la piste se rearme, donc elle re-signalera sa fin.

Generateur aleatoire PROPRE au service plutot que `math.random`, partage par tout le jeu : deux features qui le
consomment se decalent mutuellement sans qu'on comprenne pourquoi.

### Le cabrage est retarde

Il partait au CLIC, alors que le geste ne tire pas la corde a la premiere image. La machine bronchait donc avant
que le bras ne parte en arriere. `PULL_LIFT_DELAY` (0.35 s) le recale -- a regler en regardant l'animation.

Le delai verifie que le joueur porte ENCORE la tondeuse a l'echeance : cabrer une machine qu'on ne tient plus la
laisserait de travers.

Note pour plus tard : le jour ou l'animation portera un MARQUEUR, s'y brancher plutot que de compter un delai. Un
delai fige se desynchronise des qu'on retouche l'animation -- meme raison que pour la boite aux lettres.

## 0.0.307 — La machine se cabre et le moteur tousse quand on tire la corde

Deux details qui donnent de la FORCE au geste. Sans eux, tirer la corde n'agissait que sur le personnage : la
machine, elle, ne bronchait pas.

### L'avant se leve

Un a-coup au moment du tirage, qui retombe vite (`PULL_LIFT_DECAY` haut : un a-coup doit etre sec, pas une
houle).

Le pivot est l'ARRIERE de la machine, pas sa racine. La racine est a l'avant-bas du carter : pivoter autour d'elle
aurait souleve l'ARRIERE, soit l'inverse exact de l'effet voulu. On reutilise le recul deja mesure pour le
portage.

Le calcul se fait dans le repere ALIGNE (apres `baseC0`), ou l'avant de la machine est sur -Z quel que soit le
montage du rig -- donc l'axe lateral est sur X, et le cabrage est un simple angle autour de lui.

`PULL_LIFT` accepte une valeur NEGATIVE si c'est l'arriere qui se leve : le sens depend du rig, il ne se deduit
pas.

### Le moteur tousse

Sa boucle est jouee UNE fois, non bouclee, pendant le tirage. Il tourne, il ne PREND pas. C'est ce qui fait
comprendre qu'on ESSAIE de le lancer -- et ca ouvre la porte a un tirage qui echoue, si on veut un jour que la
tondeuse demarre au deuxieme ou troisieme coup.

`Looped = false` ecrit en code : le reglage de l'editeur n'est qu'une suggestion, et une piste ponctuelle bouclee
par erreur reste a plein poids pour toujours.

### Menage

`swingShown` disparait : plus utilise depuis que le ballant vient de l'input et non d'une derivee bruitee.

## 0.0.306 — La tondeuse va encore moins vite

`SPEED_MIN` passe de 8 a 6, `SPEED_MAX` de 13 a 10.

Le plafond est desormais cale sur la MARCHE du jeu (10) et non au-dessus : pousser une tondeuse ne doit jamais
aller plus vite que marcher les mains vides. C'est ce qui donne le poids, et ca garde la marche libre comme
reference lisible.

L'ecart passe de 5 a 4, donc la montee en regime tombe a environ 2.7 s sans toucher a `SPEED_RAMP_UP` : reduire
l'ecart raccourcit la duree. Le commentaire de la config le dit maintenant, parce que c'est le genre de couplage
qu'on oublie au reglage suivant.

## 0.0.305 — Les bandes de tonte naissent enfin de la TONTE

Promesse tenue. La config l'annoncait depuis le debut, dans le bloc "Rayures de tonte" :

> "Sur un vrai terrain, les bandes claires et sombres ne sont pas peintes : elles viennent du SENS dans lequel la
> tondeuse a couche les brins. Les dessiner d'avance donnerait un motif fixe, identique quoi que fasse le joueur.
> Elles naitront donc de la TONTE elle-meme."

Chaque touffe retient desormais le SENS dans lequel la tondeuse est passee dessus, et s'eclaircit ou s'assombrit
selon. Repasser dans l'autre sens REECRIT la bande -- exactement ce que fait une vraie tondeuse.

Une donnee a part de `tiltDir`, qui suit les PAS du joueur : marcher sur une bande ne doit pas la reecrire.

On multiplie les canaux plutot que de fondre vers une couleur fixe, donc chaque touffe garde sa tache de Perlin :
les bandes se posent SUR le relief du terrain au lieu de l'effacer.

Le sens est calcule UNE fois par passe et non par touffe -- il est le meme pour toutes celles de l'image. Et il
vient du MEME `forwardOf` que les roues, donc les deux ne peuvent pas raconter des sens differents.

### La limite, assumee

Le sens est compare a un AXE FIXE (`MOW_STRIPE_AXIS`). Les bandes sont donc franches quand on tond LE LONG de cet
axe -- un aller clair, un retour sombre -- et invisibles quand on tond perpendiculairement, les deux sens y
donnant la meme valeur.

Un effet juste dans toutes les directions devrait comparer au REGARD du joueur (c'est d'ailleurs physiquement
exact : de vraies bandes changent d'aspect quand on se deplace). Mais il faudrait alors repeindre toute la pelouse
des que la camera tourne. On prend le pas cher, et on regle l'axe sur la direction dans laquelle on tond le plus.

L'ancien systeme de rayures dessinees d'avance reste COUPE, et son commentaire pointe maintenant vers celui-ci.
Prefixe `MOW_STRIPE_` pour qu'on ne confonde jamais les deux.

## 0.0.304 — La poignee du lanceur passe dans la main du joueur

Elle restait sur la machine pendant le demarrage. Elle QUITTE maintenant la tondeuse des la posture "pret a
tirer", et y revient a la fin du geste. Le Beam tendu entre `A0Launcher` (sur la machine) et `A1Launcher` (sur la
poignee) s'etire alors tout seul : on ne dessine pas la corde, on deplace ses deux bouts. Meme montage que le
taille-haie.

### Le placement est CALCULE, pas regle a l'oeil

L'attachment de la poignee va en `C1`, celui de la main en `C0`. Rappel du montage, deja au journal :
`Part1.CFrame = Part0.CFrame * C0 * C1:Inverse()` -- l'attachment de la piece vient donc se coller EXACTEMENT sur
celui de la main, axes alignes. C'est l'attachment pose dans Studio qui decide de l'angle, pas un offset devine
dans la config.

### Trois filets

Tout joint qui tenait deja la poignee est DETRUIT avant d'en poser un : deux joints sur la meme piece donnent une
pose qui n'est ni l'une ni l'autre, et on chercherait l'erreur dans les attachments.

Sa place sur la machine est RELEVEE a la prise, et elle y revient exactement -- pas approximativement.

Elle est RE-SOUDEE au retour et pas seulement reposee : la tondeuse est desancree pendant le portage, une piece
libre tomberait.

Le retour a lieu a la fin du geste ET a la repose : lacher la tondeuse en plein tirage ne laisse pas la poignee
dans la main.

## 0.0.303 — C'est le JOUEUR qui tire la corde, pas le jeu

L'animation de demarrage se jouait toute seule a la prise. Elle est desormais FIGEE a sa premiere image : le
personnage TIENT la corde, pret a tirer. Le CLIC du joueur la relance a vitesse normale.

Meme mecanique que le lanceur du taille-haie, et le service le documentait deja : "Ready et Pulling partagent la
meme piste, on ne fait que changer sa vitesse". La posture etant deja la bonne, il n'y a aucune transition a
fondre entre les deux.

Nouveau remote `PullMowStarter`, sans aucun argument : le serveur sait deja ce que le joueur porte et dans quel
etat. Rien a valider, rien a falsifier. Il ignore le message si la machine est deja lancee.

Le bouton n'est branche QUE tant qu'il y a une corde a tirer. Une tondeuse lancee ne laisse donc pas un bouton a
l'ecran, et un clic sans effet n'apprend pas au joueur a ne plus cliquer.

### Une machine a l'arret ne coupe rien

Consequence directe, et elle n'a pas ete demandee : tant que la corde n'a pas ete tiree, on POUSSE un objet -- on
ne tond pas. Nouvel attribut `LeafiaMowerRunning`, pose par le serveur au demarrage du moteur et lu par le client
avant de couper.

C'est aussi ce qui donne du SENS au demarrage. Sans ca, tirer la corde ne serait qu'une animation de plus : jolie,
et sans consequence.

## 0.0.302 — On TIRE LA CORDE avant de pousser, et le moteur s'entend

Nouvelle animation de demarrage, jouee UNE fois a la prise. La pose du guidon prend le relais quand elle se
termine.

`Looped = false` et c'est voulu : c'est un geste PONCTUEL, il doit se relacher pour laisser la place a la pose de
maintien -- l'inverse exact du guidon, qui doit TENIR sa derniere image et reste donc boucle. Ecrit en code et pas
laisse au reglage de l'editeur : une piste bouclee par erreur resterait a plein poids pour toujours et
polluerait tout ce qui partage sa priorite.

`Stopped` couvre la fin NORMALE comme un arret force (le joueur repose la tondeuse pendant le geste) : on verifie
donc qu'il la porte ENCORE avant d'enchainer.

### Le moteur ne demarre plus avant qu'on ait tire

Il se lancait a la prise. Il tournait donc avant meme le geste, ce qui n'a de sens ni a l'oeil ni a l'oreille. Il
demarre maintenant a la FIN du tirage, avec la pose du guidon.

### Sons, empruntes au taille-haie

En attendant ceux de la tondeuse : `TryLaunchSound` sur le tirage, `IdleSound` en boucle moteur. Le jour ou les
vrais sons existent, seul le bloc SONS de la config change -- le code ne connait que des noms.

Ils sont CLONES sur la MACHINE, pas joues depuis l'original : le son sort donc de la tondeuse, se spatialise, tout
le monde l'entend, et deux joueurs qui tondent en meme temps ont chacun le sien. Le son ponctuel se detruit a la
fin, la boucle a la repose.

La hauteur du son monte avec le REGIME, comme le levier -- et depuis le MEME ratio. Deux calculs separes
auraient fini par se decaler, et on aurait entendu un moteur qui ne correspond plus a ce qu'on voit.

### Menage

`getAnimator` factorise : le demarrage et la pose du guidon le cherchaient chacun de leur cote, avec le meme
timeout recopie.

## 0.0.301 — Les roues tournent juste, et a l'envers en marche arriere

Les deux roues PARTAGEAIENT un seul compteur d'angle. Dans la boucle, la premiere avancait l'angle et la seconde
repartait de la : l'angle progressait DEUX fois par image (les roues tournaient deux fois trop vite) et les deux
n'etaient jamais au meme endroit.

Chaque roue a maintenant son angle, cle par son Motor6D -- donc deux tondeuses posees dans la map ne se marchent
pas dessus non plus.

La marche arriere, elle, etait deja correcte depuis le 0.0.279 : la distance est PROJETEE sur l'avant de la
machine, donc negative en reculant, et `spinWheels` ne rejette que zero. Mais le doublement d'angle rendait le
resultat illisible -- on ne pouvait pas voir que le sens etait bon.

Lecon : une variable d'etat partagee par plusieurs objets dans une boucle est un accumulateur qui compte pour tout
le monde. Ca se voit d'autant moins que le symptome (trop vite) ressemble a un mauvais reglage.

## 0.0.300 — L'herbe tondue descend plus bas

`MOW_CUT` passe de 0.55 a 0.75 : il reste 25 % du brin au lieu de 45. A l'ecran l'herbe tondue restait trop haute
et le contraste avec l'herbe brute ne sautait pas aux yeux.

On garde une marge avant 1, et pour une raison qui n'a pas change : c'est ce qui RESTE qui donne l'avant/apres. A
0.98 (la valeur du pietinement) il n'y a plus de matiere a voir, donc plus rien a admirer.

## 0.0.299 — La camera d'epaule est retiree

Le joueur ne l'aime pas. Retiree entierement : le reglage, les appels et la primitive `SetShoulder` de
`CameraEffects`.

Pas mise a zero, pas laissee derriere un drapeau : une config qui ne fait rien et une fonction que personne
n'appelle sont du code mort, et le code mort finit toujours par etre lu comme actif. Git garde tout si l'envie
revient.

Le recul de camera lie a la vitesse, lui, reste : c'est un effet different, et il n'a pas ete remis en cause.

## 0.0.298 — La tondeuse se met franchement en travers quand on tourne en roulant

Un seul angle servait les deux cas. En pleine avance, 10 degres de travers ne racontaient rien : une machine
lancee qu'on braque doit se mettre EN TRAVERS, c'est de la que viennent le poids et l'inertie.

Deux amplitudes, une par etat : 26 degres en roulant, 10 en manoeuvre. Un reglage par etat et jamais une fraction
de l'autre -- sinon regler l'un force a compenser l'autre, et le compensateur est toujours une estimation.

Le passage d'un angle a l'autre n'a demande AUCUN lissage supplementaire : c'est la CIBLE qui change, et
l'approche vers elle (`SWING_RECOVER`) faisait deja tout le travail. Poser un second lissage par-dessus aurait
ajoute du retard sans rien gagner.

`SWING_MAX` monte de 28 a 40 : a 28 il aurait ecrete les 26 degres au moindre depassement et les regler n'aurait
plus rien change. Un plafond doit rester un FILET, pas devenir la valeur qui decide.

## 0.0.297 — La tondeuse ne bouge plus a la prise : c'est le joueur qui va a elle

En appuyant sur E, la machine sautait devant le joueur. Deux causes distinctes, toutes deux corrigees.

### Le pivot etait saute quand on etait deja sur place

L'approche pivote le joueur vers la machine avant de prendre. Mais quand il etait DEJA assez pres, on sautait la
marche -- et le pivot avec. Il prenait donc la tondeuse en regardant ailleurs, et la soudure la reposait devant
son regard. On croyait que la MACHINE avait saute ; c'est le joueur qui n'etait pas oriente.

Le pivot a maintenant lieu dans les DEUX cas. Sauter un deplacement inutile est une chose, sauter l'orientation en
est une autre.

### La soudure alignait la mauvaise chose

Elle alignait les axes de la RootPart sur ceux du joueur. Or rien ne garantit que le -Z local de la racine soit
l'avant de la tondeuse : il vient du rig, pas du bon sens. La machine PIVOTAIT donc a la prise.

On aligne desormais son AVANT REEL (mesure comme partout ailleurs : RootPart -> CutZone) sur le regard du joueur.
La machine garde son orientation, elle ne fait que se retrouver devant lui.

### Contournement

Un joueur qui arrive PAR DEVANT marchait droit dans la machine pour rejoindre le guidon, qui est derriere. Il
passe maintenant par un point de COTE d'abord -- du cote ou il se trouve deja, donc le chemin le plus court -- ce
qui decrit un arc naturel autour d'elle.

Pas de PathfindingService pour autant : deux points suffisent dans un jardin ouvert, et un chemin calcule serait
plus fragile pour un gain nul a cette distance.

`walkTo` et `turnTo` deviennent deux fonctions distinctes, appelees par les deux chemins. Le pivot etait duplique
dans l'un des deux, et c'est exactement comme ca qu'un des deux finit par diverger.

## 0.0.296 — On ralentit pour tourner, et la camera passe a l'epaule

### Avancer en braquant etait trop vif

Le joueur filait ET pivotait a pleine vitesse, ce qui ne ressemble a aucune machine reelle. On perd maintenant
jusqu'a 45 % de vitesse a fond de braquage (`TURN_SLOWDOWN`) : on ralentit pour tourner.

Ne s'applique qu'a l'avance REELLE. La manoeuvre (braquer sans avancer) est deja lente a 2 studs/s -- la ralentir
encore la figerait.

### Camera d'epaule

La vue se decale sur le cote pendant le portage, au lieu d'etre pile dans le dos. Le personnage et la tondeuse ne
masquent plus la bande a tondre.

`CameraOffset` est en repere CAMERA (le module le documentait deja) : un X positif reste donc a DROITE DE L'ECRAN
quel que soit l'angle de vue. C'est ce qui fait TENIR un cadrage d'epaule, au lieu de le faire tourner autour du
personnage.

Nouveau `SetShoulder` dans `CameraEffects`, seul ecrivain de `CameraOffset`. C'est un decalage TENU, distinct de
la secousse, du bob et de la plongee qui, eux, reviennent a zero : il s'ADDITIONNE a eux au lieu de les remplacer.

Le decalage n'existe QUE pendant le portage, et il est rendu a l'arret du controller -- sinon la vue serait restee
reculee et decalee pour toujours.

`applyCameraZoom` devient `applyCameraRig` : elle ne fait plus que le zoom, et un nom qui ment coute plus cher
qu'un renommage.

## 0.0.295 — Reculer en braquant part du bon cote

S + D recule maintenant a DROITE, S + Q a gauche.

En marche arriere on se deplace le long de -cap : tourner le cap a droite envoyait donc la machine a GAUCHE. Le
braquage est desormais inverse quand on recule -- comme au volant d'une vraie machine.

Ce n'est pas un detail de confort : la marche arriere est justement le moment ou le joueur a le moins de reperes,
et ou un braquage inverse est le plus difficile a rattraper.

Le braquage de MANOEUVRE (braquer sans avancer) garde le sens normal : on ne recule pas, on repositionne.

La courbe de debug applique la meme inversion -- sinon elle montrerait un arc et la machine en suivrait un autre,
ce qui est pire que pas de debug du tout.

## 0.0.294 — Fin du zig-zag : on cesse de DERIVER un signal recu du reseau

En relachant la touche de virage, la machine faisait un aller-retour rapide avant de se remettre droite.

Le ballant derivait le CAP OBSERVE : combien le joueur avait tourne depuis l'image d'avant. Mais le serveur recoit
ce cap REPLIQUE et INTERPOLE. Quand le joueur arrete de tourner net, l'interpolation DEPASSE puis se corrige : la
derivee change de SIGNE, et la machine repart de l'autre cote.

Le lissage du 0.0.293 attenuait le bruit, il ne pouvait rien contre une inversion REELLE du signal. Il fallait
cesser de deriver, pas mieux filtrer.

Le ballant est desormais pilote par l'INPUT de braquage, que le client envoie deja : propre, signe, sans bruit et
sans depassement. L'angle vise vaut `steerInput x SWING_ANGLE`, et la machine s'en approche a `SWING_RECOVER`.

### Trois mecanismes deviennent un

`SWING_GAIN` (derivee du cap), `PIVOT_GAIN` (braquage a l'arret) et `SWING_SMOOTH` (filtre ajoute la veille)
disparaissent. Un seul chemin sert maintenant les deux cas -- en roulant ET a l'arret -- donc ils ne peuvent plus
se contredire, et il ne reste que deux boutons : l'ANGLE et la VITESSE d'approche.

`lastYaw` disparait aussi : plus personne ne mesure de variation de cap.

### Regle a garder

Deriver une valeur RECUE DU RESEAU produit du bruit ET des inversions de signe. Quand une valeur d'INTENTION
existe deja (ici l'input du joueur), c'est elle qu'il faut lire -- pas la consequence observee de cette intention.

## 0.0.293 — La tondeuse ne tremble plus en tournant (bruit de derivee)

Le ballant se calcule sur la DIFFERENCE de cap entre deux images. Or le serveur ne voit pas le cap du joueur en
direct : il le recoit REPLIQUE, par paquets et interpole. Prendre la derivee d'un signal comme ca AMPLIFIE son
bruit -- d'ou une machine qui tremble pile au moment ou on tourne.

L'angle est toujours calcule pareil, mais on n'AFFICHE plus qu'une version lissee (`SWING_SMOOTH`). Assez rapide
pour qu'aucun retard ne se sente, assez lente pour absorber le bruit de replication. Tout ce qui AFFICHE (la
soudure et la pose des bras) lit cette version ; le brut reste la valeur de travail.

Regle generale a garder : deriver une valeur RECUE du reseau donne toujours du bruit. Soit on lisse le resultat,
soit on ne derive pas.

### Si ca tremble encore

Deux autres causes possibles, dans cet ordre :
1. La `C0` de la soudure est ecrite cote SERVEUR a chaque image, donc elle se replique par paquets : le client
   verrait des marches meme avec un angle parfaitement lisse. Le remede serait de faire le ballant en VISUEL cote
   client (les autres joueurs ne le verraient plus).
2. Le `hrp.CFrame` ecrit a chaque image pendant la conduite peut se battre avec le solveur physique.

Test pour trancher : `SWING_GAIN = 0`. Si le tremblement disparait, c'est le chemin du ballant (cause 1) ; s'il
reste, c'est la conduite (cause 2).

## 0.0.292 — La pose des bras partait du mauvais cote

`TURN_POSE_INVERT` passe a true. Le sens depend de la convention d'angle de Roblox ET du sens dans lequel
l'animation a ete faite : il ne se deduit pas, il se voit. Le reglage etait la pour ca.

## 0.0.291 — Les bras reagissent tout de suite quand on braque sur place

Ils suivaient le BALLANT de la machine. Or le ballant met du temps a s'installer quand on manoeuvre lentement :
on braquait, et les bras ne bougeaient presque pas.

Ils suivent maintenant l'INPUT en priorite, et ne retombent sur le ballant que le reste du temps. En manoeuvre,
ce qu'on montre c'est l'EFFORT -- et l'effort est immediat, il n'attend pas que la machine ait tourne.

`TURN_POSE_SPEED` (9) donne la vitesse a laquelle les bras rejoignent la pose. Haute expres.

Le signe du braquage est desormais commun au pivot ET a la pose des bras : les deux DOIVENT partir du meme cote,
et deux calculs separes auraient fini par ne plus etre d'accord.

La valeur est CLEE a sa cible : un lerp exponentiel ne l'atteint jamais, et les bras seraient restes decentres a
vie -- meme piege que le ballant au 0.0.290, corrige du meme coup.

Le calcul vit HORS du bloc d'animation : l'etat reste coherent meme si la piste n'a pas pu charger, ce qui evite
un saut de pose le jour ou elle arrive en retard.

## 0.0.290 — La pose des bras revient VRAIMENT au milieu quand on lache tout

Question du joueur : "quand j'appuie plus sur rien, tu remets bien l'animation a 0.5 ?" Elle a fait tomber DEUX
bugs, dont un permanent.

### Un reste de braquage qui ne partait jamais

Le braquage n'est envoye au serveur que lorsqu'il CHANGE assez (seuil 0.08), pour ne pas remplir le reseau. Mais
relacher la touche apres une poussee LEGERE -- 0.05, un stick a peine effleure -- ne franchissait pas ce seuil.
Le serveur gardait donc ce reste et poussait la machine de travers POUR TOUJOURS.

Le retour a ZERO part maintenant systematiquement, seuil ou pas. Un cas particulier assume : "arreter" n'est pas
un changement comme les autres.

### Un demi-degre de travers, a vie

Le ballant revient a zero par un lerp exponentiel, qui n'atteint JAMAIS sa cible. La machine gardait donc une
fraction de degre de travers indefiniment -- et la pose des bras, qui se calcule sur cette meme valeur, restait
un poil decentree au lieu de revenir a 0.5.

On cle la valeur a zero des qu'elle passe sous un seuil et que plus rien ne pousse. Meme piege que le residu de
fondu qui traversait le rendu transparent, meme remede, deja au journal.

## 0.0.289 — Braquer seul INFLECHIT la trajectoire au lieu de la faire pivoter

L'avance de manoeuvre du 0.0.288 tournait au taux PLEIN (120 degres/s), alors que la machine avance a peine. Ca se
lisait comme un pivot sur place, pas comme une tondeuse qu'on repositionne.

`STEER_CRAWL_TURN_RATE` (18 degres/s) est un taux A PART, applique quand on braque SANS avancer. La trajectoire
part alors surtout vers l'avant, avec juste un soupcon de courbe.

Un reglage separe et non une fraction de `STEER_TURN_RATE` : regler l'un ne doit pas forcer a compenser l'autre.
Meme regle que STEP_GLIDE / STEP_GLIDE_CUT sur la taille, ou que la vitesse du FOV tenu face au FOV de fond.

La courbe de debug utilise le taux REELLEMENT applique : dessinee avec l'autre, elle mentirait sur le trajet, et
on reglerait a l'aveugle en croyant regler a l'oeil.

## 0.0.288 — Braquer fait rouler : la tondeuse avance doucement pendant qu'elle tourne

Appuyer sur une seule touche de cote fait maintenant AVANCER la machine, tout doucement, et le corps tourne avec.
On ne fait pas pivoter une tondeuse sur un point : on la fait rouler juste assez pour qu'elle tourne.

C'est ce petit roulement qui rend le mouvement credible. Sans lui, le personnage pivotait sur ses talons comme une
tourelle.

`STEER_CRAWL` = 2 studs/s. Repere de conversion : la marche du jeu est a 10 studs/s, soit environ 10 km/h -- donc
2 studs/s font a peu pres 2 km/h. C'est une avance de MANOEUVRE, pas un deplacement.

### Une fraction, pas une vitesse

`Humanoid:Move` prend une FRACTION de la WalkSpeed, pas une vitesse en studs. On divise donc l'avance voulue par la
vitesse COURANTE : la manoeuvre reste a 2 studs/s meme quand la tondeuse est montee en regime, ou la fraction
serait sinon deux fois trop grande.

`STEER_CRAWL = 0` rend exactement le comportement precedent (corps fige, seule la machine pivote), et le code le
respecte : le corps ne tourne que s'il roule VRAIMENT -- soit parce que le joueur avance, soit a cause de la
manoeuvre. Une config qui promet un comportement doit le tenir.

## 0.0.287 — Le braquage sur place devient discret

`PIVOT_GAIN` passe de 2.6 a 0.8, soit environ 8 degres au lieu de 25. Un coup de reins pour repositionner la
machine, pas un demi-tour.

L'angle atteint vaut `PIVOT_GAIN / SWING_RECOVER`, en RADIANS -- ce chiffre ne veut rien dire seul, comme la rampe
de vitesse. La config donne maintenant la formule inverse pour viser un angle : `PIVOT_GAIN = rad(angle) x
SWING_RECOVER`.

## 0.0.286 — Le braquage sur place partait du mauvais cote

Pousser a gauche envoyait la tondeuse a droite. Sens retourne.

Rien a comprendre ici : le sens d'un braquage depend de la convention d'angle de Roblox ET de la facon dont le
ballant est signe. Il ne se DEDUIT pas, il se voit -- c'est le joueur qui a tranche, comme pour le sens du wipe de
gradient et l'axe des roues.

`PIVOT_GAIN` accepte une valeur NEGATIVE pour le retourner a nouveau, sans toucher au code.

Le braquage EN ROULANT n'a pas ete touche : il passe par un autre chemin (le cap du personnage, puis le ballant
derive de sa rotation), et rien n'indique qu'il soit faux. On ne retourne pas a l'aveugle ce qui n'a pas ete
signale.

## 0.0.285 — Avancer ne fait plus tourner tout seul : deux reperes melanges

En appuyant SEULEMENT sur avancer, la tondeuse partait parfois en virage. Le joueur avait raison de soupconner la
camera : elle influencait bien le deplacement, et c'etait une faute de repere.

`ControlModule:GetMoveVector()` rend un vecteur RELATIF A LA CAMERA (X = cote, Z = arriere). C'est precisement
pour ca que `Humanoid:Move(v, true)` existe -- le second argument demande a Roblox d'y appliquer la camera.

On le PROJETAIT sur des axes MONDE (`mv:Dot(camLookFlat)`), ce qui melange deux reperes : un simple "avance"
produisait une composante laterale FANTOME, dont la valeur dependait de l'orientation de la vue. D'ou un virage
sans toucher aux touches de cote, et un comportement qui changeait selon l'angle de la camera -- donc impossible a
reproduire de facon fiable, donc stressant.

Les composantes se lisent maintenant DIRECTEMENT : `avance = -mv.Z`, `cote = mv.X`. Le secours clavier de
`MoveInput` suit la meme convention (W -> z -= 1), donc les deux chemins se lisent pareil.

Note au journal, avec une correction : l'entree existante parlait de "repere CAMERA-monde", formulation ambigue
qui a directement produit cette faute. Elle est precisee. Et `LadderMoveController` projette ENCORE sur le regard
de la camera : ca marche tant que la camera regarde vers -Z (le cas par defaut), mais c'est a reverifier -- non
touche ici, on ne corrige pas a l'aveugle un systeme qui marche.

## 0.0.284 — A L'ARRET, c'est la MACHINE qui se braque, pas le corps

Comprehension du joueur, et elle est physiquement juste : on ne fait pas pivoter une tondeuse sur un point sans
rouler. On l'ORIENTE, et le corps reste face au travail -- ce sont les BRAS qui montrent l'effort, et ils sont
deja animes pour ca.

Deux comportements distincts, donc :

- **En roulant** : le cap du personnage tourne, la trajectoire s'arrondit (inchange).
- **A l'arret** : le corps ne bouge PLUS. Seule la machine pivote, jusqu'a un angle stable.

L'angle est STABLE et non infini : la poussee du braquage est rappelee par `SWING_RECOVER`, et les deux
s'equilibrent. Tenir la touche amene donc la tondeuse a `PIVOT_GAIN / SWING_RECOVER` radians et l'y laisse ; la
relacher la ramene droite. Aucun compteur a borner, c'est le ressort qui fait le travail.

La pose des bras suit gratuitement : elle se calcule deja sur cette meme valeur de ballant.

### Un remote, et pourquoi il fallait bien un remote

Le serveur tient la soudure, donc c'est lui qui fait pivoter la machine -- mais il ne voit pas l'input du joueur.
`SetMowSteer` porte UN nombre dans [-1, 1].

Il n'est PAS envoye a chaque image : seulement quand la valeur change assez. Tenir une touche n'envoie donc qu'un
seul message, pas soixante par seconde.

Le serveur borne la valeur ET refuse les NaN : un NaN se propagerait dans l'angle et figerait la machine de
travers pour toujours. Et de toute facon l'angle final reste clampe par `SWING_MAX` -- un client qui enverrait 50
n'obtiendrait pas plus d'angle qu'un client honnete.

## 0.0.283 — Le personnage regarde derriere lui en marche arriere

Nouvelle pose : la tete se tourne pour voir ou on recule. Comme dans la vraie vie, et ca DIT au joueur qu'il
recule sans avoir a lire un indicateur.

POSEE et non jouee, comme le levier : sa `TimePosition` va de 0 (tete droite) a sa derniere image (tete tournee),
et on la deplace. Une piste laissee libre rejouerait le mouvement de tete en boucle. C'est aussi le motif qui
n'a jamais produit de course au chargement, contrairement au gel sur marqueur.

Le mouvement est LISSE (`REVERSE_TURN_SPEED`) : une tete qui claque d'un cote a l'autre se lit comme un bug.

### Le recul est MESURE, pas suppose

On projette la vitesse REELLE sur le cap plutot que de lire l'intention du joueur. Une bosse, une pente ou un
autre joueur qui pousse ne doivent pas faire tourner la tete ; et un vrai recul doit la tourner meme si la
poussee vient d'ailleurs. `REVERSE_EPSILON` ecarte les micro-reculs de la physique.

Priorite `Action3` : au-dessus de la pose de virage (Action2), elle-meme au-dessus du guidon (Action). Trois poses
sur le meme corps -- a priorite EGALE, Roblox en ferait une MOYENNE au lieu de choisir.

Garde-fou pose au passage : `.Unit` sur un vecteur nul rend du NaN, et un NaN ecrit dans une `TimePosition`
empoisonne la piste pour de bon. Le cas est rare, il ne coute rien a ecarter.

## 0.0.282 — La conduite se battait avec Roblox : corrige, et une courbe pour la regler

Le personnage partait DANS TOUS LES SENS des qu'on avancait. Ce n'etait pas un reglage : c'etait un conflit
d'ecriture, et il etait entierement de mon fait.

Le module de controle de Roblox appelle `humanoid:Move` a chaque image, AVANT la physique. La conduite, elle,
tournait sur `Heartbeat` -- donc APRES. Une image sur deux partait dans la direction demandee par la conduite,
l'autre dans celle du module de controle. D'ou un personnage qui se contredit dix fois par seconde.

Elle passe en `BindToRenderStep`, juste APRES le personnage (`RenderPriority.Character + 1`) : on ecrase la
demande du module de controle dans la MEME image, avant que la physique ne la lise. Un seul ecrivain a l'instant
qui compte.

Regle a retenir : contraindre le deplacement d'un personnage ne se fait pas depuis Heartbeat. La question n'est
pas "est-ce que j'ecris", c'est "est-ce que j'ecris APRES celui que je veux remplacer, et AVANT celui qui lit".

### Debug de trajectoire

Des points dessinent la courbe QUE LA MACHINE VA SUIVRE avec le braquage courant. Ils utilisent exactement la
meme formule que la conduite : si la courbe affichee ne correspond pas au trajet reel, c'est que la formule a
change d'un cote et pas de l'autre.

Ils retrecissent avec la distance (on lit le SENS d'un coup d'oeil), s'affichent MEME A L'ARRET (sinon on ne
pourrait pas regler le braquage sans rouler), et utilisent la vitesse MESUREE et non supposee.

Instances creees UNE fois puis reutilisees, et detruites des qu'on lache la tondeuse. `STEER_DEBUG` a false les
coupe -- a faire une fois la conduite validee.

## 0.0.281 — La camera s'ecarte a mesure qu'on prend du regime

La vue recule quand la tondeuse accelere. On voit venir la bande a tondre, et l'acceleration se RESSENT au lieu de
se deviner au chiffre.

La vitesse est MESUREE sur le deplacement reel du joueur plutot que recopiee depuis la valeur du serveur : c'est
ce que le joueur voit, et ca reste juste meme si un autre systeme le ralentit.

### Une seule valeur pour deux raisons

Le recul de camera a maintenant DEUX sources : la revelation (touche G) et la vitesse. Elles ecrivaient chacune
dans `SetZoomBoost`, donc le dernier appel de l'image ecrasait l'autre et le recul aurait clignote des qu'on tond
en maintenant G.

Elles passent desormais par un seul calcul qui les ADDITIONNE, appele une fois par image. Meme regle que celle qui
gouverne deja `WalkSpeed`, `FieldOfView` et la couleur des touffes : une grandeur, un seul ecrivain, les autres
declarent.

`DRIVE_ZOOM` = 4 studs a plein regime, a 0 pour couper l'effet.

## 0.0.280 — Conduite facon VEHICULE : les touches de cote BRAQUENT, elles n'avancent plus

Le 0.0.279 avait mal compris la demande. Il tournait le cap lentement, mais il faisait toujours AVANCER le joueur
des qu'il appuyait sur une touche de cote : on partait donc en avant en braquant, ce qui n'est pas ce qu'on fait
avec une tondeuse.

Les deux commandes sont maintenant SEPAREES :

- avant / arriere -> on AVANCE le long du cap (negatif = marche arriere, les roues suivent) ;
- gauche / droite -> on BRAQUE, et RIEN d'autre. Appuyer sur la seule touche de cote ne fait pas avancer la
  machine d'un pouce -- on la redresse, comme une vraie tondeuse a l'arret.

C'est ce decouplage qui donne l'arc, et non le bridage de la rotation : puisqu'on ne se deplace JAMAIS
lateralement, la trajectoire ne peut que se courber.

Le braquage est PROPORTIONNEL a la poussee : un joystick a moitie tire braque a moitie, une touche braque a fond.
Un seuil ecarte le bruit d'un stick au repos, qui ferait tourner la tondeuse toute seule.

### L'input est projete sur la CAMERA, jamais lu en axes monde

"Avancer" veut dire la direction avant de la CAMERA, dont les composantes monde changent des qu'on tourne la vue.
Lire un axe brut ne marcherait que dans une seule orientation -- piege deja paye sur la grimpe d'echelle, ou ca
montait au clavier mais pas au doigt des que la camera ne regardait plus vers -Z.

`STEER_INVERT` existe pour le sens du braquage : il depend de la convention d'angle de Roblox, il ne se deduit
pas. Si appuyer a droite fait tourner a gauche, c'est ce reglage et rien d'autre.

## 0.0.279 — La tondeuse decrit un ARC au lieu de pivoter sur place

Appuyer sur D faisait tourner le personnage INSTANTANEMENT : un demi-tour sec sur un point, avec une machine
censee peser. Borner le ballant ne suffisait pas -- le poids devait etre dans la ROTATION elle-meme.

Pendant le portage, `AutoRotate` est coupe et le cap tourne a vitesse BORNEE (`STEER_TURN_RATE`, 120 degres par
seconde : un quart de tour en 0.75 s).

**Et surtout, le deplacement suit le CAP, pas l'input.** C'est ce second point qui fait l'arc. Borner la rotation
SEULE aurait fait glisser le personnage de cote pendant qu'il pivote : deja parti a droite alors que son corps
regarde encore devant. En le faisant avancer LA OU IL REGARDE, la trajectoire se courbe.

Le ballant de la machine et la pose des bras suivent gratuitement : ils se calculent deja sur le cap.

`AutoRotate` est RENDU a la repose, au respawn et a l'arret du controller. Sans ca, un joueur qui lache sa tondeuse
resterait incapable de se tourner, et il chercherait longtemps pourquoi.

### Les roues tournent aussi en marche arriere

La distance servant a les faire rouler etait une MAGNITUDE, donc toujours positive : elles tournaient a l'endroit
meme en reculant. Elle est maintenant PROJETEE sur l'avant de la machine, donc signee. Et `spinWheels` rejetait
`distance <= 0`, ce qui figeait les roues des qu'on recule : il ne rejette plus que zero.

### Menage : `MoveInput`, un seul lecteur d'input brut

Le portage d'echelle et la conduite de la tondeuse ont le meme besoin : lire l'intention du joueur A LA SOURCE,
parce que `humanoid.MoveDirection` ne la reflete plus des qu'on contraint le deplacement avec `Move`.

La logique (resolution de PlayerModule en tache de fond avec retry, secours clavier, zero yield par frame) vit
maintenant dans `Client/Utils/MoveInput.luau`, et l'echelle y a ete migree. Deux copies d'un helper aussi subtil
auraient fini par diverger sur l'une des deux.

Nouveau `forwardOf` cote MowController, pour la meme raison : le point de prise ET le sens des roues dependent de
l'avant de la machine, et deux calculs separes auraient fini par ne plus dire la meme chose.

## 0.0.278 — Les bras accompagnent le virage

Nouvelle pose : les bras redressent la tondeuse quand on tourne, comme dans la vraie vie. L'animation n'est pas
JOUEE, elle est POSEE -- son milieu est la pose droite, un bout le virage a gauche, l'autre a droite. Meme
mecanique que le levier : on ecrit une IMAGE, jamais un defilement.

### Elle est pilotee par le BALLANT, pas par un nouveau calcul

`state.swing` etait deja signe, deja proportionnel au virage, et il revient tout seul a zero quand le joueur roule
droit. Il suffisait de le ramener sur la timeline. Rien de nouveau a lisser, et surtout : la pose des bras et le
balancement de la machine viennent de la MEME valeur, donc ils ne peuvent pas se desynchroniser.

Chaque moitie de la timeline est mise a l'echelle de SA propre portee, donc `TURN_POSE_MIDDLE` peut etre ailleurs
qu'a 0.5 sans que la pose deborde d'un cote.

### Priorite Action2, et c'est indispensable

La pose du guidon est en `Action` et cle les MEMES bras. A priorite EGALE, Roblox ne choisit pas : il MELANGE. On
aurait obtenu une pose "presque bonne" qu'on aurait crue mal animee, et qui ne se lit que dans
`GetPlayingAnimationTracks` -- jamais a l'oeil. La pose de virage passe donc AU-DESSUS.

### Le sens ne se devine pas

`TURN_POSE_INVERT` existe parce que le sens depend de la convention d'angle de Roblox ET du sens dans lequel
l'animation a ete faite. Si les bras partent du mauvais cote, c'est ce reglage -- pas le ballant. Meme famille que
le sens du wipe de gradient et l'axe des roues : c'est l'ecran qui tranche.

## 0.0.277 — La tondeuse traine dans les virages au lieu d'etre trimballee

Soudee RIGIDE, elle pivotait a l'instant meme ou le joueur tournait. Ca se lit comme un objet TENU a bout de bras,
pas comme une machine qu'on POUSSE -- "trimballee comme une poupee", dixit le joueur.

Elle prend maintenant du RETARD quand on tourne, puis rattrape. C'est l'ecart entre la prise de retard (immediate)
et le rattrapage (progressif) qui se lit comme du poids. Un objet sans inertie n'a pas de masse a l'oeil.

### Trois details qui font toute la difference

**La rotation passe A GAUCHE de l'offset de portage.** La machine pivote donc AUTOUR DU JOUEUR -- le guidon reste
dans les mains, le carter part de cote. A droite, elle tournerait sur elle-meme, ce qui est le mouvement d'un objet
PORTE et pas POUSSE. Un seul cote de multiplication separe les deux lectures.

**Le repli sur [-pi, pi].** Sans lui, passer de +179 a -179 degres compte comme un demi-tour complet, et la
tondeuse part en toupie une fois par tour de joueur.

**Le plafond (`SWING_MAX`).** Sans lui, une pirouette envoie la machine a 180 degres et elle repasse devant le
joueur par l'autre cote.

Calcule cote SERVEUR, sur le C0 de la soudure : le ballant se replique donc a tout le monde, comme la rotation de
l'echelle. `SWING_GAIN` a 0 rend exactement la soudure rigide d'avant.

## 0.0.276 — On POUSSE la tondeuse, on ne court plus avec

Les vitesses de la tondeuse n'etaient calees sur RIEN : 13 au demarrage, 20 a plein regime, alors que la marche du
jeu est a 10 et le SPRINT a 17. Le joueur poussait donc sa tondeuse plus vite qu'il ne court. Ca se lisait comme
une course, pas comme un travail.

Recalees sur les vraies valeurs de `CharacterConfigs` : 8 au demarrage (SOUS la marche -- la machine resiste), 13
a plein regime (au-dessus de la marche, bien en dessous du sprint).

`SPEED_RAMP_UP` passe de 3.5 a 1.5. Ce chiffre ne veut rien dire seul : ce qu'on ressent, c'est la DUREE, et elle
depend de l'ECART. Sur l'ancien ecart de 7 studs, 3.5 donnait 2 s ; sur le nouvel ecart de 5, il aurait donne 1.4 s
et la montee en regime aurait disparu. A 1.5, on retrouve environ 3.3 s.

Regle a retenir : une vitesse de rampe se regle AVEC l'ecart qu'elle parcourt, jamais isolement.

## 0.0.275 — Le moteur tourne et le levier suit le regime

Les deux IDs manquants sont poses. Le mecanisme etait ecrit depuis le 0.0.262 et attendait juste ces numeros :
le code ignorait proprement les animations tant que la config etait vide, sans une erreur.

- MOTEUR : boucle en priorite `Idle`, sur l'Animator de la TONDEUSE, cote serveur donc entendue par tous.
- LEVIER : priorite `Action`, vitesse ZERO, `TimePosition` ecrite a chaque image -- image 0 au ralenti, derniere
  image a plein regime. On ne lit qu'une IMAGE, jamais le defilement. Meme mecanique que la visee haut/bas du
  taille-haie.

Le levier passe AU-DESSUS du moteur (`Action` > `Idle`) : si les deux animations clent le meme joint, c'est le
levier qui gagne au lieu que Roblox fasse une moyenne des deux.

Les deux sont prechargees au boot avec la pose du guidon, donc le premier demarrage de la session ne part pas de
travers.

## 0.0.274 — L'herbe redevient verte PARTOUT quand on lache G

En lachant la touche, seule l'herbe autour du joueur reprenait sa couleur. Tout le reste restait bleu, pour de bon.

La condition qui decide de redessiner une touffe testait encore un BOOLEEN ("allume ou non") herite d'avant le
fondu, compare au drapeau du materiau Neon -- lui-meme toujours faux depuis que Neon est coupe. Un fondu passe par
des valeurs INTERMEDIAIRES : une comparaison binaire ne les voit pas.

D'ou un comportement asymetrique trompeur : a l'ALLUMAGE ca marchait par accident (l'etat changeait a la premiere
image), a l'EXTINCTION plus rien ne se redessinait hors de la portee du vent.

La condition teste maintenant `fading` -- exactement "la revelation est en train de changer". Meme drapeau que
celui qui reveille deja les paves et les zones : une seule notion, un seul test, aux trois endroits.

Lecon : quand un etat passe de BINAIRE a CONTINU, il faut relire TOUS ses tests. Il en restait un, et il etait a
l'etage du dessus.

## 0.0.273 — La pose du guidon ne se fige plus a l'image ZERO

Le joueur restait parfois droit comme un R15 sans animation, la piste bloquee a `TimePosition` 0.

C'etait le FILET du 0.0.261 qui se declenchait a tort. Sa condition, `TimePosition >= Length - epsilon`, devient
VRAIE des l'image zero quand `Length` vaut presque rien -- et c'est exactement ce qu'annonce une piste ENCORE EN
COURS DE CHARGEMENT. Le filet cle alors la pose au tout debut, met la vitesse a zero, se debranche, et plus rien
ne bouge. Intermittent, parce que c'est une course entre le chargement de l'asset et la premiere image.

Un garde-fou pose pour rattraper une race en a donc cree une autre. Trois corrections :

- Le filet exige maintenant `IsPlaying` ET une duree CREDIBLE (`HOLD_MIN_LENGTH` = 0.05 s). Une piste qui ment sur
  sa duree n'est plus prise au serieux.
- Il ne se debranche sur "vitesse nulle" que si la piste a REELLEMENT avance (`TimePosition > 0`). Une piste
  fraichement lancee peut annoncer une vitesse nulle avant que `Play` ne prenne effet ; lacher le filet a cet
  instant le rendait inutile pile quand il sert.
- Et surtout, on s'attaque a la CAUSE : les trois animations (pose, moteur, levier) sont PRECHARGEES au boot via
  `ContentProvider:PreloadAsync`, en tache de fond. La course disparait quand l'asset est deja la. Meme mesure que
  celle deja prise sur le repli de l'echelle.

## 0.0.272 — Toute l'herbe s'allume, et ca n'eblouit plus

### L'herbe lointaine restait verte

Le drapeau `fading` reveillait les PAVES endormis, mais une ZONE entiere trop loin du joueur est sautee bien avant
qu'on descende aux paves. Le fondu n'atteignait donc jamais son herbe : elle restait verte pendant que le reste
passait au bleu.

Le meme drapeau passe maintenant AUSSI au niveau des zones. Correction en une ligne, mais elle valait un
diagnostic : le premier `fading` etait au bon endroit pour la moitie du probleme seulement, et rien ne le disait.

### Le Neon eblouissait

Neon ignore l'eclairage et rend a pleine intensite. Sur une pelouse ENTIERE ca ne se lit plus comme un surlignage,
ca fait mal aux yeux -- constate a l'ecran.

`HIGHLIGHT_MATERIAL_ON` passe a false : la touffe garde son materiau, seule sa COULEUR change. Le reglage reste,
a remettre a true le jour ou la revelation ne concernera qu'une petite surface.

Si le bleu lui-meme reste trop fort une fois le Neon coupe, c'est `HIGHLIGHT_COLOR` qu'il faut adoucir -- pas le
materiau.

## 0.0.271 — La revelation FOND vers le bleu au lieu d'y sauter

La bascule etait BINAIRE : l'herbe passait au bleu d'une image a l'autre. Ca se lisait comme un bug d'affichage,
pas comme un mode qu'on active.

Une valeur GLOBALE (`reveal`) rejoint maintenant l'intention en douceur, et la couleur de chaque touffe glisse
vers le bleu par un fondu. Globale et non par touffe : elles s'allument toutes ensemble, il n'y a rien a stocker
mille fois.

La revelation passe EN DERNIER dans la chaine de couleurs (repos, coupe, ecrasement, crete de rafale, puis
revelation) : elle recouvre tout le reste, et a fondu plein on est exactement sur la couleur cible.

### Trois pieges du fondu

**Le materiau ne se fond pas.** Neon est un etat, pas un degrade. On le bascule donc TOT (`HIGHLIGHT_MATERIAL_AT`
= 0.02), quand la couleur est encore presque normale : ca se lit comme un allumage. C'est le fondu de COULEUR qui
porte la douceur.

**Les paves endormis auraient fige la transition.** La boucle saute les paves sans vent et sans joueur proche --
soit la majorite de la pelouse, soit exactement ce qu'on veut voir s'allumer. Un drapeau `fading` les garde
eveilles TANT QUE dure le fondu. `setHighlight` ne les reveillait qu'une image, ce qui ne suffisait plus.

**Un lerp exponentiel n'atteint jamais sa cible.** Sans clic sur la valeur exacte, on redessinerait toute la
pelouse a vie pour un residu invisible. Meme piege que l'ecrasement, meme remede.

`HIGHLIGHT_FADE_SPEED` = 2.5, environ une demi-seconde. Plus bas = plus lent.

## 0.0.270 — Le vent fait des LAMELLES, plus une grosse masse

Le champ de rafales etait echantillonne en X/Z du monde, a la MEME frequence dans les deux directions. Un bruit
isotrope ne peut produire que des taches RONDES : ca respirait comme une masse, ca ne roulait pas comme du vent.

Il est desormais echantillonne dans le REPERE DU VENT : fin le long du souffle, etire en travers. Les rafales
deviennent des lamelles qui traversent la pelouse.

`GUST_SCALE` passe de 0.035 a 0.09 : c'est l'EPAISSEUR d'une lamelle dans le sens du vent (environ 11 studs au
lieu de 30). C'est ce chiffre qui decide entre "vagues qui roulent" et "masse qui respire".

`GUST_STRETCH` (nouveau, 6) est l'etirement en travers. A 1 on retrouve exactement l'ancien comportement -- des
taches rondes. Plus haut = lamelles plus longues et plus franches.

Le defilement ne s'applique qu'a l'axe du vent, comme avant : c'est par la que la vague avance. Et les deux axes
sont derives de WIND_DIR (rotation de 90 degres), donc changer la direction du vent les emmene tous les deux.

## 0.0.269 — Plus de coup de frein a l'atterrissage

Le personnage tombait a 4 studs/s en touchant le sol, puis remontait. Ca donnait du POIDS au saut, mais ca rendait
le jeu COLLANT : on retombe sans arret dans un jardin, et chaque reception coutait une demi-seconde de marche
molle. Retire.

L'ANIMATION d'atterrissage reste : elle raconte l'impact sans le facturer. C'est elle qui portait le ressenti, pas
le ralentissement.

`LANDING_SPEED` disparait. `LANDING_RECOVERY_RATE` devient `SPEED_SPEEDUP_RATE` : plus rien ne "recupere" d'un
atterrissage, cette rampe ne sert plus qu'a rejoindre une allure imposee par une feature ou a la quitter. Un nom
qui ment coute plus cher qu'un renommage.

### Bug d'architecture corrige au passage (introduit au 0.0.262)

`MowService` ecrivait dans `humanoid.WalkSpeed` DIRECTEMENT pour sa montee en regime. Or `CharacterService` porte
la regle, en tete de son fichier : "Un seul module possede WalkSpeed ; les autres declarent ce qu'ils veulent, il
tranche." Les deux se battaient donc a chaque image, et le sprint aurait ecrase la tondeuse (ou l'inverse) sans
qu'on comprenne pourquoi.

La tondeuse DECLARE maintenant son allure via `setSpeedOverride`. Sa propre rampe (3.5 studs/s) est plus lente que
celle de CharacterService (14), donc c'est bien la montee en regime de la tondeuse qu'on ressent. A la descente en
revanche, c'est la rampe de CharacterService (9) qui borne : le retour au ralenti est un peu plus doux que les 14
demandes par `SPEED_RAMP_DOWN`. A regler la si ca compte.

`walkSpeedWas` disparait : c'est CharacterService qui ramene le joueur a sa marche quand on retire l'allure
imposee. Reposer une valeur nous-memes reviendrait a redevenir un deuxieme ecrivain.

## 0.0.268 — La crete de la vague passe en Shamrock

L'eclaircissement du 0.0.265 ne se voyait PAS. Cause : quelques pour cent de luminosite sur un vert deja vif se
noient. Il fallait une couleur FRANCHE pour que la vague se detache, pas une nuance de la meme.

La crete fond donc vers `GUST_COLOR` (Shamrock) au lieu d'etre eclaircie. Le fondu reste PARTIEL (`GUST_TINT`),
donc la nuance propre de chaque touffe et sa tache de Perlin survivent dessous : la vague passe SUR le terrain,
elle ne le repeint pas.

`GUST_TINT_SHARPNESS` concentre l'effet sur le HAUT de la vague. Sans lui, le champ de bruit etant doux, le
teintage bave sur toute la pelouse et se lit comme un aplat au lieu d'une vague qui passe. Plus haut = bande plus
fine et plus nette.

Seule la moitie POSITIVE du bruit teinte : le creux d'une vague ne doit rien changer.

### Piege a connaitre

`BrickColor.new()` retombe SILENCIEUSEMENT sur "Medium stone grey" quand le nom n'existe pas. Si la crete vire au
GRIS, ce n'est pas le reglage qui est faux, c'est le NOM de la couleur. Le commentaire de la config le dit.

## 0.0.267 — Le recul de camera devient LENT

Il etait agressif : la vue sautait en arriere au lieu de s'installer. Recul et resserrement passent de 4 et 3 a
1.1 -- environ deux secondes pour se poser, au lieu d'un quart de seconde.

### Le reglage a ete DEDOUBLE, pas baisse

Le FOV tenu partageait `FOV_LERP_SPEED` avec le FOND (repos <-> mouvement), que le joueur avait deja regle. Le
ralentir aurait ralenti les transitions de course avec, et il aurait fallu compenser ailleurs -- or un
compensateur est toujours une estimation. Regle deja au journal, payee sur la vitesse de coupe.

`FOV_OFFSET_LERP_SPEED` est donc une valeur A PART. Le fond reste vif (il change en permanence), l'effet tenu
s'installe lentement. Chacun se regle sans toucher a l'autre.

Recul et resserrement gardent la MEME allure, et ce n'est pas un hasard : ce sont les deux moities du meme geste.
A vitesses differentes on verrait l'un arriver avant l'autre, et le mouvement se lirait comme deux effets colles
au lieu d'un seul.

## 0.0.266 — La camera prend du recul pendant la revelation

Maintenir G ne fait plus qu'allumer l'herbe : la camera RECULE et se RESSERRE, en douceur. C'est le geste de
quelqu'un qui prend du recul pour evaluer son travail.

Les deux ensemble, et c'est le point : reculer seul ne fait qu'eloigner, resserrer seul montre MOINS. Combines,
on voit plus de pelouse ET la perspective s'aplatit -- ce qui rend justement les bandes oubliees lisibles.

### Deux nouveaux termes dans le SEUL ecrivain de la camera

`CameraEffects` porte la regle "chaque propriete de camera a un seul ecrivain". On ne pouvait donc pas ecrire dans
`FieldOfView` depuis la tondeuse, ni meme appeler `SetFovBase` : ce fond est pilote par CameraController selon
repos / mouvement, les deux se seraient battus.

`SetFovOffset` : un TROISIEME terme de FOV, additif et TENU, a cote du fond et de l'a-coup. Il ne se bat avec
personne, et le lissage vient de la boucle qui existait deja.

`SetZoomBoost` : le recul. La camera Custom de Roblox ne se recule pas -- c'est le JOUEUR qui possede sa distance
de zoom. On deplace donc ses BORNES, progressivement (min et max sur la meme valeur qui glisse), et on les lui
rend a la fin. Poser le clamp d'un coup aurait fait un a-coup sec.

La distance de depart est capturee UNE FOIS au demarrage du recul, jamais relue en continu : la lire pendant
qu'on la modifie ferait fuir la camera toujours plus loin. Et c'est la distance camera -> Focus qui est lue, pas
camera -> personnage : c'est elle, le vrai zoom (deja au journal).

Pendant le recul le joueur ne peut plus zoomer. C'est assume : l'effet dure le temps d'une touche maintenue.

### Un seul point d'entree

`setReveal(on)` dans MowController allume l'herbe ET la camera. Les appeler separement aurait fini par laisser la
camera reculee alors que l'herbe est deja eteinte -- au respawn, a la sortie de contexte, a l'arret.

## 0.0.265 — On VOIT le vent traverser la pelouse

Les rafales ECLAIRCISSENT l'herbe en plus de la coucher. Idee du joueur, et elle est physiquement juste : un brin
qui se couche ne renvoie pas la lumiere de la meme facon. C'est ce contraste qui rend le vent visible dans un vrai
champ -- le mouvement seul se lit a peine, surtout de loin.

C'est le MEME champ de bruit que le tassement, donc la vague qu'on voit est exactement celle qui couche l'herbe.
Pas deux effets cote a cote : un seul, montre de deux facons.

On ECLAIRCIT les canaux de la couleur au lieu de fondre vers une teinte fixe. Chaque touffe garde ainsi sa nuance
et sa tache de Perlin, et il n'y a AUCUNE couleur de plus a stocker par touffe.

Une touffe deja couchee (un pied) ou TONDUE ne scintille pas : elle ne bouge plus, elle n'a pas a briller. La
valeur decroit aussi avec `windScale`, donc rien ne reste eclairci quand une touffe sort de portee du vent.

### Perf

La rafale bouge en permanence : sans precaution, on reecrirait la couleur de chaque touffe a CHAQUE image, pour
des ecarts que l'oeil ne voit pas. L'eclaircissement est donc quantifie, avec son propre pas (`GUST_LIGHT_STEP`,
50 niveaux). Monter ce pas = moins d'ecritures et une vague qui avance par marches.

`GUST_LIGHTEN = 0.1`, volontairement discret : au-dela de ~0.2 la vague se lit comme un projecteur qui balaie la
pelouse, pas comme du vent. A regler a l'oeil, et a surveiller au FPS -- c'est le premier effet du systeme qui
ecrit une couleur en continu.

### Note d'outil

`selene` ne detecte PAS un argument manquant : `apply` a gagne un 7e parametre, et l'appel de la pose initiale
serait passe a `nil` sans un mot, pour lever au premier semis. Verifier les sites d'appel A LA MAIN quand une
signature change -- 0 parse error ne veut pas dire 0 probleme.

## 0.0.264 — Papi cligne des yeux

Son idle (pour l'instant : juste les yeux) est jouee en boucle par `AmbientAnimService`. Une ligne dans
`AmbientAnimConfigs`, comme Bush1, Tree1 et CommonTree_3.

Il n'etait anime par PERSONNE. Le commentaire de la config affirmait le contraire -- "Papi n'est plus ici, il se
promene, NpcWanderService pilote ses deux animations" -- mais l'entree de `NpcWanderConfigs` est DESACTIVEE
depuis qu'on a constate que l'ancien rig "OldManIdle" n'a ni bras ni jambes. Le commentaire etait devenu faux, et
un commentaire faux coute plus cher que pas de commentaire : corrige, avec la condition de sortie ecrite noir sur
blanc (retirer la ligne le jour ou il se promenera, sinon deux services se battront pour le meme Animator).

Le corps viendra quand l'animation sera faite. En attendant, un PNJ qui cligne des yeux est deja vivant -- et
c'est exactement le genre de detail qui se voit sans qu'on sache le nommer.

## 0.0.263 — La canne de Papi devient animable

`scripts/studio/AttacherCanneAuPapi.lua` : cree le Motor6D entre la main de Papi et sa canne, d'ou une PISTE
"Canne" dans l'editeur d'animation.

Rappel de la regle, deja au journal : parenter un objet a un personnage ne cree AUCUN joint, et sans joint
l'editeur d'animation ne voit meme pas l'objet. Un Tool y arrive parce que ROBLOX lui fabrique un Motor6D a
l'equipement ; un Model ne declenche rien.

Difference avec `AttacherOutilAuRig` : la prise du taille-haie est CALCULEE en jeu par ToolService, donc la poser
a l'oeil donnerait des poses justes dans l'editeur et fausses en jeu. La canne n'est calculee par personne --
c'est du decor sur un PNJ. Le placement fait a la main EST la source de verite, et le script se contente de le
figer dans le C0. On peut donc corriger la prise et relancer.

Le script desancre TOUTE la canne, pas seulement la part soudee : une part ancree ignore son Motor6D, et une
seule suffit a bloquer l'ensemble -- l'animation jouerait alors sans que rien ne bouge, sans erreur.

### Cote Studio (ne se synchronise PAS par Rojo)

Le joint vit dans le Workspace. Il doit etre refait dans CHAQUE place (Leafia ET le tuto), sinon Papi tiendra sa
canne dans l'une et pas dans l'autre.

## 0.0.262 — La tondeuse monte en regime, et le levier le raconte

### Le joueur gagne sa vitesse

Il ne part plus a fond. Il pousse a `SPEED_MIN` (13), et tant qu'il AVANCE il monte vers `SPEED_MAX` (20). S'il
s'arrete, ca retombe. C'est ce qui fait sentir le poids de la machine : une vitesse constante ne raconte rien.

Montee LENTE (`SPEED_RAMP_UP`), descente VIVE (`SPEED_RAMP_DOWN`) : on GAGNE sa vitesse, on ne la garde pas
gratuitement.

La vitesse se mesure sur le deplacement REEL (`AssemblyLinearVelocity`), pas sur l'intention : pousser contre un
mur ne doit pas faire monter le regime.

La `WalkSpeed` d'avant la prise est relue et RENDUE telle quelle a la repose, jamais remplacee par `SPEED_MIN` :
un autre systeme a pu la changer. Meme regle que pour le saut.

### Le levier n'est pas "joue", il est POSE

Sa position raconte le REGIME, pas le temps qui passe. On le charge donc a vitesse ZERO et on ecrit sa
`TimePosition` a chaque image selon la vitesse du moment : ratio 0 au ralenti, 1 a plein regime.

Meme mecanique que la visee haut/bas du taille-haie -- une animation dont on ne lit qu'une IMAGE, jamais le
defilement. `Looped = true` pour que la piste ne se relache jamais, et on s'arrete a `Length - epsilon` : sur la
derniere image pile, une piste bouclee est deja repartie a zero.

### Le moteur

Boucle simple en priorite `Idle`, sur l'Animator de la TONDEUSE (pas celui du joueur), cote serveur donc vue par
tous. L'Animator de la machine est CREE s'il manque -- un mesh rigge importe par le 3D Importer arrive avec un
AnimationController vide, meme piege que sur les arbres d'ambiance.

Les IDs vivent dans `MowConfigs` et pas dans des Instances : Rojo ne synchronise pas `ReplicatedStorage.Animations`
vers la place tuto.

### A REMPLIR

`MOTOR_ANIM_ID` et `LEVER_ANIM_ID` sont VIDES : les deux animations existent dans Studio mais leurs IDs n'ont pas
ete communiques. Le code les ignore proprement tant qu'ils le sont (aucune erreur, aucune piste chargee), et la
montee en vitesse fonctionne deja sans elles.

## 0.0.261 — La pose du guidon ne repart plus au debut de temps en temps

Symptome signale par le joueur, et le pire genre : ca marche la plupart du temps, et parfois non.

Cause exacte, deja au journal : la pose est figee au marqueur `ReadyToLaunch` (`AdjustSpeed(0)`), mais avec
`Looped = true` la piste continue de tourner tant que le marqueur n'a pas fait son travail. Une seule image
perdue et la tete de lecture DEPASSE le marqueur : la piste boucle, et la pose repart du debut. Le journal le
disait dans ces termes -- "a bas FPS le clamp d'une fenetre >= Length - eps peut le rater".

On garde le marqueur (c'est lui qui gele au bon endroit dans le cas normal) et on ajoute le FILET que le journal
prescrit : une surveillance de la `TimePosition` qui cle la piste juste avant sa derniere image. Celui des deux
qui arrive en premier gagne ; le filet se debranche des qu'il voit la vitesse a zero, donc il ne coute rien une
fois la pose tenue.

On cle a `Length - 0.001`, jamais sur la derniere image pile : a la derniere image, une piste bouclee est deja
repartie au debut.

La surveillance est coupee a la repose, a la mort et au depart, comme la piste elle-meme -- une connexion posee
sur `RunService` survit a la destruction de ce qu'elle regarde.

## 0.0.260 — Correction : le menage de config annonce au 0.0.259 n'avait PAS ete applique

Le 0.0.259 annonce la disparition de `PROMPT_PART_NAME` et un `PROMPT_OFFSET` a 0.8. Les deux etaient FAUX :
le script d'edition a echoue a mi-parcours (le joueur avait entre-temps regle `PROMPT_OFFSET` a la main) et rien
n'a ete ecrit dans la config -- alors que le commit, lui, est parti. Une entree de changelog qui decrit une
intention au lieu de l'etat reel vaut moins que pas d'entree du tout. C'est fait pour de bon ici.

`PROMPT_PART_NAME` disparait : plus personne ne s'en sert depuis que l'ancrage est un point calcule.

`PROMPT_OFFSET` redevient PUREMENT VERTICAL (0, 1.5, 0). Il avait ete regle a (0, 5, 3) pour rattraper le badge a
la main, et cette composante Z ne pouvait pas marcher : l'offset est exprime en repere MONDE, pas dans celui de la
tondeuse. Un Z pousse donc le badge toujours vers le meme point cardinal, et il se decale par rapport a la machine
des qu'elle n'est pas posee dans le bon sens -- soit exactement le "ca depend de l'angle" qu'on cherchait a
corriger. Le commentaire le dit maintenant, dans la config.

### Note de methode

Un script d'edition qui echoue APRES avoir modifie sa chaine en memoire mais AVANT d'ecrire le fichier ne laisse
aucune trace : le code reste correct, seul le changelog ment. Verifier l'etat REEL du fichier apres coup, pas la
sortie du script.

## 0.0.259 — Le badge se pose sur le capot, quel que soit l'angle de la tondeuse

Il flottait devant la machine, et il se DEPLACAIT autour d'elle selon son orientation dans la map.

Ce n'etait pas un probleme d'angle : `WorldAnchor` accroche le badge sur `part.Position`, soit le CENTRE de la
part visee. On visait `Handle` -- une part heritee du rig du taille-haie, dont le centre n'a aucune raison d'etre
la ou l'oeil l'attend. Quand la tondeuse tournait, ce centre tournait avec elle. Le point etait faux, pas l'angle.

`WorldAnchor.Target` accepte aussi un `Vector3` : on lui donne desormais un point CALCULE -- milieu en X/Z,
sommet en Y, sur les parts VISIBLES uniquement (la CutZone et les zones logiques ne sont pas des pieces de la
machine). Le badge se pose donc sur le capot, centre, quelle que soit l'orientation. Par construction.

Le point est GARDE tel quel plutot que recalcule a chaque test : le prompt est un singleton, et on compare ce
point a celui qu'il affiche pour savoir s'il est encore a nous. Le recalculer ferait echouer la comparaison sur
une virgule et le badge clignoterait.

`PROMPT_PART_NAME` disparait (plus personne ne s'en sert) et `PROMPT_OFFSET` retombe a 0.8 : il ne sert plus qu'a
decoller le badge du capot, l'ancrage etant deja au sommet.

## 0.0.258 — Le joueur va A la tondeuse, au lieu que la tondeuse lui saute dessus

### Le joueur ne se plante plus au milieu de la machine

La distance de portage se calait sur `RootPart -> Handle`. Quand la part `Handle` est juste au-dessus de la
racine, cette distance est quasi nulle : le personnage se retrouvait DANS la tondeuse.

On mesure maintenant le RECUL REEL de la machine -- de combien elle depasse derriere sa racine -- et le joueur se
tient derriere ce point-la. L'axe d'avancee n'est plus devine : c'est la direction `RootPart -> CutZone`, et la
CutZone est par definition posee a l'avant, sous le carter. Une donnee qui existe deja, plutot qu'une hypothese.

`HANDLE_NAME` disparait (il ne servait plus qu'a mentir) et laisse place a `CARRY_FALLBACK_BACK`, utilise
uniquement quand la CutZone est absente -- sans elle on ne sait pas de quel cote regarde la machine.

### L'approche

Sur E, le joueur MARCHE jusqu'au point de prise, pivote vers la machine, puis prend. C'est lui qui va a la
tondeuse.

Le pivot n'est pas un ornement : un joueur venu par l'avant arrive DOS a la machine, et la soudure la reposerait
alors de l'autre cote.

Pas de `PathfindingService` : quelques studs dans un jardin ouvert, `Humanoid:MoveTo` suffit. Un chemin calcule
serait plus fragile (bloque, sol irregulier, autre joueur) pour un gain nul a cette distance. A revoir le jour ou
la tondeuse se rangera derriere un obstacle.

Deux garde-fous :
- **Deja arrive = aucun deplacement fabrique.** Sous `APPROACH_SKIP_DIST`, on prend, point. C'est la lecon de
  l'echelle, ou tout un systeme de marche forcee avait ete construit pour un joueur qui arrivait des la premiere
  image.
- **Timeout** a `APPROACH_TIMEOUT` : mieux vaut une prise un peu de travers qu'un joueur bloque par un caillou.

Le drapeau d'approche n'est relache qu'a la toute fin, pivot compris : un second appui pendant la rotation
relancerait une marche par-dessus celle qui vient de finir.

## 0.0.257 — Le saut est vraiment coupe, et la tondeuse se pose enfin au sol

### La tondeuse ne flotte plus

C'etaient bien les parts INVISIBLES. `lowestPoint` ignorait la CutZone mais pas les autres (zones logiques, aides
d'edition) : une seule posee bas faussait toute la hauteur. Elle ne compte plus que les parts visibles, et le
carter se pose pile sur le sol. Le calcul etait juste, c'est ce qu'on lui donnait a mesurer qui ne l'etait pas.

### Le saut se coupe par les PROPRIETES, pas par l'etat

`SetStateEnabled(Jumping, false)` cote serveur ne changeait rien : cette methode n'agit que sur la machine qui
l'appelle, or c'est le CLIENT qui simule le personnage. Le serveur s'interdisait donc de sauter tout seul, dans
son coin, pendant que le joueur sautait tres bien.

Ce sont `JumpHeight` et `JumpPower` qui font le travail : ce sont des PROPRIETES, elles se repliquent. Les deux
sont mises a zero, parce que laquelle compte depend de `UseJumpPower` et que ce reglage peut changer sans nous.
`SetStateEnabled` reste EN PLUS (il coupe aussi un saut demande cote serveur), pas a la place.

`blockJump` et `restoreJump` sont deux fonctions distinctes, et non un booleen : les deux gestes ne sont PAS
symetriques. Rendre doit toujours remettre les valeurs d'ORIGINE, meme si le saut etait deja interdit avant la
prise -- sinon prendre la tondeuse pendant un dialogue laissait `JumpHeight` a zero pour toujours. Et on relit
les vraies valeurs a la prise plutot que de reposer les defauts Roblox : un autre systeme a pu les changer.

### Note d'outil

Ce commit contenait une deuxieme faute de syntaxe (un bout d'ancienne fonction laisse en place par une reecriture
mal decoupee). `selene` l'a attrapee avant le lancement, la ou `rojo build` l'aurait laissee passer -- exactement
ce pourquoi il vient d'etre installe.

## 0.0.256 — Plus de saut avec la tondeuse, et des MESURES pour la faire redescendre

### Le saut est coupe pendant le portage

On pousse une tondeuse, on ne saute pas avec. `SetStateEnabled(Jumping, false)` a la prise.

On MEMORISE l'etat d'avant et on le RESTAURE a la repose, au lieu de forcer `true` : un autre systeme peut avoir
de bonnes raisons d'avoir deja coupe le saut (cinematique, dialogue), et le lui rendre de force casserait le sien.

### La tondeuse flotte : on arrete de deviner

Elle flotte ET elle est de travers. Une seule cause explique les deux : si l'orientation de la RootPart n'est pas
celle de "la tondeuse est droite", la souder au HRP la fait pivoter -- et le point le plus bas mesure DANS LA POSE
DE REPOS ne correspond alors plus au dessous du carter une fois pivotee.

Deux valeurs devinees, deux echecs. On passe donc aux mesures : `CARRY_DEBUG` (a true) affiche a chaque prise la
hauteur des pieds, de combien la racine surplombe le bas, la descente, l'avance, et l'ORIENTATION de la racine.
C'est cette derniere qui devrait trancher.

Corrige au passage, et c'est peut-etre deja suffisant : `lowestPoint` ignorait la CutZone mais PAS les autres
parts invisibles (zones logiques, aides d'edition). Une seule d'entre elles posee bas fausse toute la hauteur.
Elle ne compte plus que les parts VISIBLES.

`CARRY_DEBUG` est a couper une fois le placement valide : un print par prise finit par noyer les vrais messages.

## 0.0.255 — Le serveur repart : faute de syntaxe dans MowService

`MowService` ne se chargeait plus ("Incomplete statement", ligne 214), donc le bootstrap serveur tombait avec lui.
Cause : un commentaire ecrit sur deux lignes dont la seconde avait perdu son `--`. Corrige.

### La vraie lecon : `rojo build` ne valide PAS le Luau

Il empaquette, il ne parse pas. Le fichier casse passait le build sans un mot, et l'erreur ne sortait qu'au
LANCEMENT. "Build OK donc la syntaxe est bonne" a ete affirme trois fois ici, et c'etait faux les trois fois.

`selene` etait declare dans `rokit.toml` mais jamais INSTALLE (`rokit install` refuse tant que l'outil n'est pas
approuve : `rokit trust Kampfkarren/selene`). Il l'est maintenant, et `selene src` rend 0 erreur, 0 warning,
0 parse error. C'est LUI le controle avant de dire qu'un fichier est bon.

Au passage, `WIND_VIEW_SQ` disparait de `GrassZoneController` : plus utilisee depuis que le tri se fait par paves.
Un linter qui crie pour rien finit ignore -- meme lecon que cSpell.

## 0.0.254 — Le joueur attrape le guidon quand il prend la tondeuse

Nouvelle pose de maintien (`holdingTheHandleAnimation`), jouee des la prise et TENUE tant qu'on pousse. Coupee en
fondu a la repose.

Jouee cote SERVEUR, donc repliquee a tous : les autres joueurs voient les mains sur le guidon, comme pour les
animations de l'echelle.

### Les trois pieges du maintien de pose, tous deja au journal

**Priorite `Action`.** En dessous (`Movement`), la marche ecraserait la pose. L'animation ne cle QUE le torse, la
tete et les bras -- si elle clait aussi les jambes, `Action` les figerait et le joueur glisserait sans marcher.
Elle est bien faite de ce cote-la.

**`Looped = true`, pas false.** Une piste non bouclee se RELACHE en arrivant au bout, et la pose saute. On la fige
donc au marqueur (`AdjustSpeed(0)`) AVANT la fin : elle n'avance plus, donc elle ne boucle jamais non plus.

**Le marqueur se lit par `GetMarkerReachedSignal` pendant la lecture**, jamais par `GetKeyframeSequenceAsync` :
cet appel reseau rate parfois au boot et tue la feature pour TOUTE la session. Meme motif que la boite aux
lettres.

Detail de sortie : on rend la vitesse a 1 AVANT d'arreter. Une piste figee a 0 ne fond pas, elle disparait d'un
coup. Et l'arret passe par un `pcall` : mourir en poussant detruit l'Animator, et couper une piste morte leve --
ce n'est pas un cas anormal, donc on nettoie sans warn.

### L'ID de l'animation vit dans la CONFIG, pas dans une Instance

`HOLD_ANIM_ID` dans `MowConfigs`. Rojo synchronise le CODE dans toutes les places, mais PAS les Instances de
`ReplicatedStorage.Animations` (`$ignoreUnknownInstances`, recopiees a la main place par place). Pointer vers
l'Instance aurait donc marche dans Leafia et casse dans le tuto -- soit exactement le bug du 0.0.249. Meme choix
que `AmbientAnimConfigs`.

`HOLD_READY_EVENT` reste nomme d'apres le marqueur du joueur ("ReadyToLaunch") : c'est de la que partira le
demarrage moteur, tirer la corde. Le nom sera bon le jour ou cette suite existera.

## 0.0.253 — La tondeuse se pose sur le sol, et la distance ne se regle plus a l'oeil

Deux defauts du portage, une seule cause : les deux distances etaient des CHIFFRES DEVINES, ignorant la geometrie
reelle du modele. 3.2 puis 4.6 studs devant, 2.6 studs dessous -- et la tondeuse flottait tout en etant collee au
personnage. On ne devine plus, on MESURE. C'est la regle deja au journal : ne jamais refaire a la main un
placement que le code peut calculer.

### La hauteur : on vise le SOL, pas une distance sous le HRP

Le HRP d'un personnage est TOUJOURS a `HipHeight + demi-hauteur` au-dessus de ses pieds. Cette distance est donc
connue, sans un seul raycast. On mesure ensuite de combien la RootPart de la tondeuse surplombe le point le plus
BAS de la machine, et on descend d'autant : le carter se pose sur le sol ou le joueur se tient.

Bonus gratuit : le HRP monte avec les pentes, donc la tondeuse les suit toute seule.

Le point le plus bas se calcule sur les 8 COINS de chaque part, pas sur (position - demi-hauteur) : une part
inclinee descend plus bas que son centre, et le carter d'une tondeuse est rarement d'aplomb. La `CutZone` est
EXCLUE du calcul -- c'est une zone logique posee sous le carter, pas une piece de la machine ; la compter ferait
poser la tondeuse trop haut, soit exactement le defaut qu'on corrige.

(Le joueur proposait de se caler sur la part d'herbe. Le sol sous ses PIEDS est meilleur : ca marche partout,
y compris hors d'une zone d'herbe, sur une allee ou sur une pente.)

### La distance : c'est le GUIDON qui compte, pas la racine

Le joueur doit se retrouver derriere le GUIDON, pas derriere la RootPart -- et la RootPart est a l'avant-bas du
carter, d'ou un personnage plante au milieu de la machine. On mesure donc la distance horizontale RootPart ->
Handle et on l'ajoute. Le guidon tombe alors toujours a `CARRY_GAP` du joueur, quelle que soit la longueur du
modele.

`CARRY_FORWARD` et `CARRY_DOWN` disparaissent. Restent deux boutons qui sont du CONFORT et non de la geometrie :
`CARRY_GAP` (l'espace joueur / guidon) et `CARRY_CLEARANCE` (de combien elle effleure le sol).

Nouveau `HANDLE_NAME`, separe de `PROMPT_PART_NAME` bien que la part soit la meme aujourd'hui : l'un dit ou
AFFICHER le badge, l'autre ou se tient la MAIN. Les confondre marcherait maintenant et mentirait le jour ou l'un
des deux bouge.

L'offset est mesure AVANT de desancrer la tondeuse : une fois libre, la physique peut l'avoir deja fait bouger
d'un poil, et on calculerait sur une pose qui n'existe plus.

## 0.0.252 — La tondeuse n'est plus collee au ventre du joueur

`CARRY_FORWARD` passe de 3.2 a 4.6 studs. A 3.2 le guidon arrivait DANS le personnage : on pousse une tondeuse a
bout de bras, pas contre soi. Valeur a l'oeil, et elle le restera -- elle depend de la longueur du modele, que le
code ne peut pas deviner.

## 0.0.251 — Maintenir G montre ce qu'il reste a tondre, et l'herbe coupee s'assombrit

Deux choses demandees par le joueur, dans la meme passe.

### La revelation (touche G maintenue)

Tout ce qui n'est PAS encore coupe s'allume en neon cyan. Le but est de rendre le PROGRES lisible : on finit un
jardin quand on voit ce qu'il reste, on l'abandonne quand on ne sait plus ou on en est.

MAINTENUE et non une bascule, expres. Un mode qu'on peut laisser allume deviendrait le mode NORMAL, et la pelouse
ne serait plus jamais regardee pour elle-meme -- or c'est ELLE le sujet du jeu.

C'est un CONFORT, pas une bequille : si on la garde appuyee en permanence, ce n'est pas la revelation qu'il faut
ameliorer, c'est le contraste tondu / pas tondu (MOW_CUT et MOWN_COLOR).

Le seuil (`HIGHLIGHT_THRESHOLD` = 0.5) allume aussi ce qui est a MOITIE coupe : on voit donc les bandes baclees,
pas seulement ce qu'on n'a jamais touche.

Trois pieges evites :
- Le rendu passe par `apply`, la meme fonction que tout le reste. Peindre les touffes depuis un autre module
  aurait ete efface a l'image suivante : la couleur a deja un ecrivain, et un seul.
- La porte de reecriture teste maintenant la revelation. Sans ca, une touffe immobile et loin du joueur n'aurait
  jamais ete repeinte -- et c'est justement le LOIN qu'on veut voir s'allumer.
- `setHighlight` remet tous les paves en `settling` pour forcer un passage, y compris ceux que la boucle saute
  faute de vent et de joueur a proximite.

La touche est branchee au meme CONTEXTE que la prise (pres d'une tondeuse, ou en train d'en pousser une) : pas de
bouton tactile qui traine a l'ecran en permanence. Elle s'eteint a la sortie du contexte, au respawn et a `stop`,
sinon s'eloigner touche enfoncee laisserait la pelouse allumee pour de bon.

### L'herbe coupee etait trop claire

`MOWN_COLOR` passe de (150, 210, 95) a (67, 95, 30). L'ancienne valeur donnait une pelouse tondue qui avait l'air
ECLAIREE, comme un projecteur pose dessus, au lieu d'avoir l'air rase. C'est l'OMBRE entre les brins courts qui se
lit comme "coupe", pas la lumiere. Le commentaire qui affirmait le contraire ("plus CLAIRE que l'herbe haute") est
corrige : il etait devenu faux, et un commentaire faux coute plus cher que pas de commentaire.

## 0.0.250 — Le badge de la tondeuse se pose sur le guidon

Il flottait devant la machine, dans le vide. Il etait accroche a la RootPart, qui se trouve a l'avant-bas du
carter : bon point pour MESURER, mauvais point pour AFFICHER.

Nouveau reglage `PROMPT_PART_NAME` (defaut "Handle", le guidon, qui existe deja sur le modele : rien a renommer
dans Studio). Introuvable, on retombe sur la RootPart sans rien casser.

L'ANCRAGE change, la DETECTION non. Elle reste radiale autour de la RootPart, parce qu'il lui faut une part FIXE :
le pivot d'un Model suit sa bounding box, donc ajouter la CutZone le decalerait. Deux besoins differents, deux
parts -- et deux reglages qu'il ne faut pas confondre (deja au journal, dans l'autre sens : monter la hauteur du
badge ne fait pas detecter plus loin).

`PROMPT_OFFSET` retombe de 4 a 1.2 : le guidon est deja a bonne hauteur, il n'y a plus rien a rattraper.

## 0.0.249 — La tondeuse existe AUSSI dans le tuto

Elle etait injouable dans la seule place ou on l'enseigne. `MowService` et `MowController` n'etaient branches que
dans la sequence PRINCIPALE, apres le `return` qui coupe la branche TUTORIAL. Le code etait bien synce par Rojo,
la tondeuse etait bien posee dans la map, et rien ne tournait dessus : aucun prompt, aucune coupe.

C'est le piege deja au journal ("une place SECONDAIRE n'herite pas des services gates hors d'elle par PlaceId"),
et il vient de couter une deuxieme fois. Rappel de la regle : un comportement de GAMEPLAY qui doit valoir PARTOUT
se branche dans les DEUX listes -- et la tonte est le geste central, donc elle vaut partout par definition.

### Le prompt est un SINGLETON, et on ne le respectait pas

`InteractionPrompt` n'affiche qu'une chose a la fois, et il est partage : dialogue de Papi, echelle, boite aux
lettres, tondeuse. Deux defauts corriges d'un coup.

`InteractionPrompt.currentTarget()` : nouvel accesseur, il dit ce qui est affiche en ce moment (nil si rien).

- La tondeuse ne re-montrait son prompt qu'au CHANGEMENT de cible. Si un dialogue prenait le singleton pendant
  qu'on etait a cote, le prompt disparaissait POUR DE BON : de son point de vue rien n'avait change. Elle teste
  maintenant aussi que le prompt affiche est bien le sien.
- Elle appelait `hide()` sans regarder a qui appartenait le prompt : elle pouvait donc effacer celui d'un autre
  en plein milieu. Elle ne cache plus que le sien.

L'echelle a le meme defaut latent, mais elle n'a pas ete touchee : on ne corrige pas a l'aveugle un systeme qui
marche, et l'accesseur est la quand on voudra le faire.

## 0.0.248 — L'Animator manquant se cree tout seul, et l'ancrage se dit tout haut

Suite directe du 0.0.247, qui ne suffisait pas : `CommonTree_3` etait bien trouve, son AnimationController etait
bien la, mais il etait VIDE. Le 3D Importer de Roblox cree un AnimationController SANS Animator dedans. Le service
attendait donc 5 secondes puis abandonnait.

Il le CREE maintenant au lieu de l'attendre. Et s'il n'y a aucun porteur, il pose un AnimationController (pas un
Humanoid : bien moins cher au serveur, et suffisant pour une boucle d'ambiance). Un modele nomme dans la config
est CENSE s'animer -- autant lui donner ce qui lui manque plutot que de refuser.

Plus aucun yield au passage : cote serveur, un modele pose dans Studio est complet des le boot, il n'y a rien a
attendre. (Un personnage JOUEUR, lui, a bien son Animator qui arrive apres l'Humanoid -- CharacterService et
ToolService gardent donc leur attente, c'est un cas different.)

`ANIMATOR_TIMEOUT` disparait de la config : plus personne ne l'utilise, et une config morte finit par mentir.

### Le piege suivant, dit tout haut

Une part ANCREE ignore son Motor6D : l'animation joue, les os bougent, et rien ne se deplace a l'ecran -- sans la
moindre erreur. C'est l'echec silencieux type de cette feature, et on ne le voit qu'a l'oeil.

Le service compte donc les parts ancrees hors RootPart au demarrage de chaque boucle, et le DIT nommement. La
RootPart, elle, doit rester ancree : c'est ce qui empeche l'objet de deriver.

Regle generale (deja au journal) : quand un systeme peut echouer en silence, lui ajouter un controle qui mesure le
resultat et parle.

## 0.0.247 — Les arbres riggés respirent, et pas seulement ceux a Humanoid

`CommonTree_3` joue sa boucle de balancement (une ligne dans `AmbientAnimConfigs`, comme Bush1 et Tree1 : le NOM
du modele est la cle, donc en poser dix dans la map les anime tous les dix).

`AmbientAnimService` cherchait un Humanoid pour trouver l'Animator. Or un mesh RIGGE importe par le 3D Importer
arrive avec un AnimationController, pas un Humanoid : l'arbre etait donc trouve, mais rien n'etait joue dessus.
Il accepte maintenant les deux, et l'AnimationController EN PREMIER -- c'est le cas normal pour un mesh rigge, et
il coute bien moins cher au serveur qu'un Humanoid.

Le warn qui prevenait "il faut un Humanoid" disait donc quelque chose de faux : corrige.

### Cote Studio (ne se synchronise PAS par Rojo)

Le modele anime ne doit PAS avoir toutes ses parts ancrees : une part ancree ignore son Motor6D, donc l'animation
joue et RIEN ne bouge, sans la moindre erreur. Pour un arbre qui doit rester plante au meme endroit, ancrer
UNIQUEMENT la RootPart.

Attention : cocher "Ancre" dans le 3D Importer ancre TOUT, donc tue l'animation. C'est le reglage a ne pas prendre
pour un modele anime.

## 0.0.246 — On peut pousser la tondeuse, et l'herbe RESTE tondue

Premier increment du geste central. Le joueur s'approche de la tondeuse, un prompt `[E] TAKE` apparait, il la
prend, elle se pose devant lui et le suit. Sur son passage l'herbe est COUPEE : elle raccourcit, elle change de
couleur, et elle ne se releve plus jamais. L'avant / apres existe.

Le demarrage moteur (corde du lanceur) et les animations n'y sont pas encore : on valide d'abord que pousser la
tondeuse et voir la pelouse changer donne envie d'en tondre une deuxieme.

### L'herbe sait etre tondue

`GrassZoneConfigs` : bloc TONTE. La tonte n'est PAS un ecrasement -- une touffe pietinee se releve, une touffe
tondue est coupee. Elle a donc sa propre valeur, qui ne descend JAMAIS (`mown` sur chaque touffe), la ou le
pietinement, lui, remonte (`FLATTEN_RECOVER`). C'est l'autre mecanisme que la config annoncait deja.

Les deux cohabitent sans se disputer la touffe : on garde la plus COURTE des deux raisons (`math.min`) plutot que
de les additionner. Marcher sur du tondu le couche encore un peu, puis ca remonte JUSQU'A la coupe, pas au-dessus.
Additionner les deux effets serait passe sous zero et la touffe aurait disparu.

La couleur empile deux melanges, et l'ordre compte : la COUPE d'abord (permanente, elle change la couleur de repos
de la touffe), l'ECRASEMENT par-dessus (temporaire). Dans cet ordre, une touffe tondue puis pietinee revient a sa
couleur de tondue quand le pied repart, pas a celle de l'herbe haute.

Une touffe tondue n'ondule presque plus (`MOW_WIND`) : un gazon ras qui vague comme de l'herbe haute effacerait
l'avant / apres qu'on vient de produire.

`GrassZoneController.mowAt(position, rayon, dt)` : nouvelle fonction publique, appelee par la tondeuse. Elle
ecarte d'abord la zone entiere, puis les paves, avant de descendre aux touffes -- sans ca on parcourrait toute
l'herbe de la carte a chaque image. Elle marque les paves touches `settling`, sinon la coupe qu'on vient de poser
ne serait jamais dessinee (les paves sans vent ni joueur proche sont sautes).

### La tondeuse

`MowService` (serveur) : autorite sur QUI pousse quoi. Portage par SOUDURE au HRP, exactement comme l'echelle --
la position se replique alors a tous sans flot de remotes. Il valide la tondeuse, sa disponibilite et la
proximite. L'offset de portage est une CONSTANTE de config et non une valeur envoyee par le client : il n'y a
donc rien a falsifier. Il ne coupe RIEN.

Offset FIXE et non capture a la prise. Le besoin n'est pas de garder la pose du sol, c'est que la tondeuse
revienne toujours pareil devant le joueur -- capturer l'offset ferait porter de travers une tondeuse posee de
travers (piege deja paye sur l'echelle).

`MowController` (client) : le prompt, la coupe, les roues.
- Detection RADIALE sur la RootPart, jamais `GetPivot` (que la CutZone soudee decalerait) et jamais une box
  (colle a un bout de la tondeuse, une box laisse un angle mort et le prompt ne sort pas).
- La coupe se fait sous la part `CutZone`, dont la POSITION donne le point et la LARGEUR le rayon. Absente, on
  retombe devant la racine et la console le DIT une fois, au lieu d'echouer en silence.
- La coupe tourne MEME A L'ARRET : rester sur place finit la touffe sous le carter au lieu de laisser un rond a
  moitie coupe.
- Prise ET repose sur le MEME declencheur, avec anti-spam : la touche et le bouton tactile peuvent tirer ensemble.
  Le bind passe par `ContextActionService` avec `createTouchButton`, et il n'est branche QUE quand l'action a un
  sens -- sans ca, deposer la tondeuse serait injouable sans clavier.

### Les roues tournent EN CODE, pas par animation

Une animation joue a vitesse fixe : la roue tournerait pareil que le joueur avance, coure ou soit a l'arret, donc
elle PATINE. L'angle vient ici de la distance REELLEMENT parcourue (horizontale : une pente ou un saut ne doivent
rien changer), et le rayon est MESURE sur la roue au lieu d'etre devine.

Corollaire a respecter dans Studio : `BackWheel` et `FrontWheel` ne doivent etre cles dans AUCUNE animation. Deux
ecrivains sur le meme joint donnent un resultat qui n'est ni l'un ni l'autre.

### Menage

`MowConfigs` decrivait un systeme de CELLULES calque sur les haies (`LawnCellService`) qui n'a jamais ete ecrit,
et que personne n'utilisait. On ne le suit plus : l'herbe de zone existe deja, elle est deja cliente, elle sait
deja s'ecraser. Le fichier decrit maintenant la vraie tondeuse. Un commentaire faux coute plus cher que pas de
commentaire.

### Cote Studio (ne se synchronise PAS par Rojo)

- Un Model `Tondeuse` doit exister dans le Workspace, avec sa `PrimaryPart` reglee sur `RootPart`.
- La part `CutZone` se cree avec `scripts/studio/CreerZoneDeCoupeTondeuse.lua`, a coller dans la barre de
  commandes. Elle est CALCULEE depuis la geometrie du modele (largeur du carter, sens de l'avant deduit du
  Handle), pas posee a l'oeil.

## 0.0.245 — REGLE : tout texte vu par le joueur s'ecrit en ANGLAIS

Regle posee par le joueur, et elle vaut pour tout le projet : dialogues, notifications, boutons, titres, messages
d'erreur. Raison : le traducteur automatique de Roblox part de l'ANGLAIS. Un texte ecrit en francais n'est traduit
nulle part -- il reste en francais pour la quasi-totalite des joueurs de la plateforme.

Ecrite dans CLAUDE.md, section Contenu joueur. Les COMMENTAIRES de code, eux, restent en francais.

Appliquee tout de suite aux deux textes que la regle invalidait : le message d'escabeau ("Too high! You need a
stepladder to trim the top.") et le dialogue d'ouverture de Papi, traduit en entier. Vocabulaire garde volontairement
simple : le public est jeune, et un mot qu'on ne comprend pas casse l'immersion aussi surement qu'une faute.

Deux autres corrections du meme passage :
- le repere de coupe devient nettement plus discret (transparences 0.8 -> 0.92 en visee, 0.7 -> 0.85 en coupe). Il
  doit indiquer, pas masquer ce qu'on taille ;
- la notification d'escabeau passe en "Warning" (rouge). Elle utilisait "warn", qui ne correspond a AUCUNE cle de
  KIND_COLORS : le toast s'affichait donc sans sa couleur, en silence. Un nom de cle inexistant ne leve rien, il
  retombe sur le defaut -- c'est le genre de faute qui ne se voit qu'a l'oeil.

## 0.0.244 — Deplacer une haie refait le semis d'herbe sous elle

L'herbe poussait au travers d'une haie qu'on venait de redimensionner. L'emprise des objets poses fonctionnait bien
-- le log l'attestait -- mais elle se calcule AU SEMIS, une seule fois. Bouger l'obstacle apres coup ne prevenait
personne.

Le semis se refait donc quand un obstacle change de position ou de taille. On n'ecoute que les obstacles DEJA trouves
(une poignee par zone), pas toute la map : une haie posee AILLEURS pendant la partie demande encore un relancement,
mais la retailler ou la deplacer se voit tout de suite -- et c'est le geste qu'on fait cent fois en reglant un jardin.

La reconstruction passe par un chemin UNIQUE et differe (`queueRebuild`), partage avec le redimensionnement de la
zone elle-meme. Necessaire : tirer une poignee a la souris emet des dizaines de changements par seconde, et chacun
relancerait sinon un semis complet de plusieurs milliers de touffes.

Les ecoutes sont reposees a chaque semis, sur la NOUVELLE liste d'obstacles : sans ca elles s'empileraient a chaque
reconstruction, et une haie retiree resterait surveillee pour rien.

## 0.0.243 — Le repere lachait le curseur sur le DESSUS, et un mot quand il faut un escabeau

Trois choses, dont une regression de la veille.

REGRESSION. Le repere cessait de suivre le curseur des qu'on visait le dessus de la haie. Le curseur se pose a TROIS
endroits differents dans updateCursor -- le dessus atteignable, le dessus trop haut, et le repli sur le plan -- et je
n'avais enregistre le point visé qu'au troisieme. Les deux autres laissaient le repere sur la lame.
Lecon : quand on ajoute un effet de bord a une valeur, chercher TOUS ses points d'ecriture avant de croire avoir fini.
Un `grep` sur `getCursorPart().Position` le disait en une ligne.

REPERE A PLAT SUR LE DESSUS, meme hors d'atteinte. Sur une haie trop haute, le code renvoie deliberement "pas sur le
dessus" pour garder la pose bras leves -- mais le repere heritait de ce choix et se dressait a la verticale sur une
surface horizontale, ce qui se lit comme un bug de visee. Le VISUEL suit maintenant la surface reellement visee, la
POSE garde sa regle. Deux besoins distincts, deux valeurs (TOP_VISUAL_ALWAYS_FLAT).

UN MOT AU CLIC. Le joueur voit son repere bien pose et clique : sans explication, il conclut que la coupe est cassee.
Un toast le dit maintenant -- "Trop haut ! Il te faut un escabeau pour tailler le dessus." -- avec un delai mini de
3 secondes pour que trois clics ne fassent pas trois messages.

C'est plus qu'un confort : ca transforme une panne apparente en OBJECTIF. Le joueur apprend l'existence de l'escabeau
au moment exact ou il en a besoin, ce qu'aucun tutoriel ne fera aussi bien.

## 0.0.242 — Le repere de coupe suit le CURSEUR

Demande du joueur : le cercle blanc doit se poser la ou l'on pointe sur la haie, pas sur la lame.

Nouveau reglage VISUAL_CUT_FOLLOWS_CURSOR (vrai par defaut). Le cercle garde toujours la LONGUEUR et l'ORIENTATION
du segment de lame -- c'est elle qui lui donne sa taille et son inclinaison -- il est seulement TRANSLATE sous le
point vise. On ne fabrique donc pas un repere d'une autre forme, on deplace le meme.

### Ce que ce choix coute, et pourquoi c'est un reglage

Les deux reperes ne coincident pas, et c'etait DELIBERE. Le serveur coupe sur le segment de LAME, et rien ne garantit
qu'a 80 % de visee le bras place la lame a 80 % de la hauteur de la haie -- surtout lateralement, ou le curseur peut
etre loin des mains. A `true`, le cercle designe donc parfois un endroit qui ne sera pas coupe.

C'est un arbitrage entre LISIBILITE (on regarde ou on vise) et HONNETETE (le repere montre ce qui sera coupe), pas un
bug d'un cote ou de l'autre. D'ou le reglage plutot qu'un remplacement : un seul mot pour revenir.

Le dernier point vise est oublie quand le curseur quitte la haie, sinon le repere resterait plante a l'endroit ou
l'on est sorti.

## 0.0.241 — Les fleurs ne levitent plus : leur tige suit l'herbe voisine

Certaines fleurs flottaient nettement au-dessus du gazon, d'autres restaient invisibles dedans.

Cause : je les surelevais d'une hauteur FIXE en studs. Or la hauteur de l'herbe VARIE par zones (le bruit de Perlin
pose en 0.0.238). Un chiffre absolu ne peut donc convenir nulle part : trop haut la ou l'herbe est courte, trop bas
la ou elle est haute. Le reglage etait condamne quelle que soit sa valeur.

L'elevation devient une FRACTION de la hauteur qu'aurait l'herbe a cet endroit precis (FLOWER_LIFT_RATIO, 0.75) :
la corolle se pose aux trois quarts de l'herbe locale, donc elle emerge pareil PARTOUT.

Regle a garder : un decalage absolu pose sur une grandeur qui varie ne peut jamais etre juste. Il faut l'exprimer
dans l'unite de ce qu'il accompagne. Meme famille que la taille des nuages et des fleurs reglee en studs plutot
qu'en multiplicateur d'un mesh inconnu, et que le plancher en studs qui inversait l'effet qu'il devait borner.

Reorganisation qui va avec : la position AU SOL est calculee d'abord, sans elevation. C'est elle qui sert a lire les
deux bruits de Perlin (couleur et hauteur), qui ne regardent que X et Z. Sans ca une fleur surelevee lisait un point
different de l'herbe qui l'entoure, et n'appartenait pas a la meme tache qu'elle.

Fleurs au passage : trois fois plus nombreuses (FLOWER_CHANCE 0.025 -> 0.09) et deux fois plus petites
(0.55 a 1.0 stud de large). Les deux vont ensemble : c'est parce qu'elles sont discretes que la frequence peut
monter sans que la pelouse disparaisse dessous.

## 0.0.240 — Le changement de couleur devient un PASSAGE

La teinte d'herbe ecrasee ne revenait jamais. Elle suivait l'ecrasement commun, qui a pour plancher la trace
PERMANENTE (FLATTEN_AMOUNT) : ce plancher ne redescend pas, donc la couleur restait changee pour toujours.

Demande du joueur, et elle est juste : le changement de teinte est un effet de PASSAGE, pas une trace. L'herbe reste
couchee derriere lui -- ca, c'est la trace -- mais elle reprend sa couleur des qu'il n'est plus dessus.

La couleur suit donc une TROISIEME valeur lissee, qui vise le CONTACT SEUL au lieu de la cible commune, avec sa
propre vitesse de retour (COLOR_RECOVER_SPEED, 7 : rapide).

Trois grandeurs maintenant, une par ressenti, et c'est le decoupage qui rend chacun reglable seul :
- `crush` : rapide, donne l'INCLINAISON (par son ecart avec la suivante) ;
- `squashCrush` : lent, donne le TASSEMENT, et garde la trace permanente ;
- `colorCrush` : contact seul, donne la COULEUR, et revient vite.

Meme raisonnement qu'a chaque fois cette semaine : quand une valeur unique doit produire des comportements qui
divergent, on la dedouble plutot que de chercher un compromis. Ici la divergence etait totale -- l'un doit RESTER,
l'autre doit PARTIR.

## 0.0.239 — Des fleurs poussent parmi l'herbe

Idee du joueur. Trois meshes de fleurs (Petal_2, Petal_4, Petal_5) apparaissent ca et la dans les pelouses.

Presque aucun code : une fleur est une TOUFFE comme les autres, avec un autre mesh. Elle herite donc du vent, de
l'ecrasement au passage, du fondu au loin et de tous les tris de performance, sans une ligne de plus. Le systeme
etait deja bon pour ca sans qu'on l'ait prevu.

Trois differences seulement, chacune pour une raison precise :
- une fleur garde EXACTEMENT sa couleur : ni teinte d'herbe, ni tache de Perlin, ni virage au vert en s'ecrasant.
  Implemente en donnant la MEME couleur aux deux etats, ce qui rend le melange sans effet -- pas un seul test
  ajoute dans la boucle par-image ;
- pas de compensation de densite sur sa taille : une fleur n'a aucune raison de grossir parce que l'herbe autour est
  plus clairsemee ;
- pas de zone de hauteur non plus : elle a sa propre echelle.

FLOWER_CHANCE (0.025) reste volontairement BASSE. Une fleur qu'on voit partout n'est plus une fleur, c'est un tapis.
Au-dela de 0.06 la pelouse devient un pre.

Le tirage qui decide fleur-ou-herbe est fait AVEC les autres tirages, en tete de boucle : la suite du hasard reste
donc identique, et changer FLOWER_CHANCE ne redistribue pas toute la pelouse.

Une fleur introuvable est signalee par son nom et n'empeche rien -- une place peut ne pas les avoir.

## 0.0.238 — L'herbe pousse plus haut par endroits

Idee du joueur. Des zones ou l'herbe monte, d'autres ou elle reste rase, en bruit de Perlin -- comme les taches de
couleur, mais sur la hauteur. Une pelouse d'une seule hauteur se lit comme une moquette ; c'est le relief qui fait
la matiere.

Champ de bruit SEPARE de celui des couleurs (troisieme argument de `math.noise` decale), et c'est voulu : partage,
les zones hautes tomberaient exactement sur les zones sombres et l'oeil y verrait un motif au lieu d'un terrain.

Plancher a 0.2 sur le facteur : une touffe de hauteur nulle serait invisible, une hauteur negative la retournerait.

Calcule UNE fois a la pose, aucun cout en jeu. Et comme la taille de repos sert de reference a l'ecrasement, une
touffe haute s'ecrase de plus haut sans qu'on ait rien a brancher.

Interet au-dela du decor : c'est le socle de la TONTE. Une pelouse a hauteur variable donne au joueur quelque chose
a EGALISER, ce qu'une moquette uniforme ne peut pas offrir.

## 0.0.237 — L'herbe ecrasee restait de travers de 4.5 degres

Le joueur a mesure une touffe pietinee : orientation -5.8 / 0.15 / -3.3 au lieu de zero. Elle restait penchee pour
toujours.

Le chiffre s'explique exactement. L'inclinaison s'effacait par `(1 - tassement)`. Or le tassement PLAFONNE a
FLATTEN_AMOUNT (0.8), a cause de la trace permanente : il n'atteint jamais 1. Il restait donc
`0.8 x 28 x 0.2 = 4.5 degres`, indefiniment.

Formulation corrigee : l'inclinaison est l'ECART entre l'ecrasement rapide et le tassement lent, ramene sur la cible.
Au moment du pas l'ecart est maximal (le rapide a saute, le lent n'a pas suivi) ; une fois le lent arrive, l'ecart
est NUL. Zero garanti, quel que soit le plafond, et sans constante a accorder avec FLATTEN_AMOUNT.

Regle : une valeur qui doit finir a ZERO ne doit pas etre calculee comme un COMPLEMENT (1 - x) d'une grandeur qui
peut plafonner ailleurs qu'a 1. La rendre comme un ECART entre deux valeurs qui convergent la fait tomber a zero par
construction. Meme famille que le residu du lerp exponentiel de 0.0.229, mais l'inverse : ici ce n'etait pas la
convergence qui manquait, c'etait la CIBLE qui n'etait pas atteignable.

SQUASH_SPEED monte de 4 a 8 (le tassement s'installait trop lentement) et CRUSHED_COLOR passe a (140, 179, 98).

Rappel au passage, verifie a cette occasion : le vent souffle DEJA moins fort sur une touffe ecrasee -- son amplitude
est multipliee par (1 - ecrasement), donc une touffe a plat ne garde qu'une fraction du mouvement. C'etait en place
depuis 0.0.208.

## 0.0.236 — L'herbe change de COULEUR quand on marche dessus

L'assombrissement en pourcentage laisse place a DEUX couleurs choisies : BASE_COLOR au repos, CRUSHED_COLOR une fois
ecrasee, et un glissement doux entre les deux.

Meilleur sur deux points. On regle ce qu'on VOIT au lieu d'un facteur dont le resultat depend de la teinte de depart.
Et rien n'oblige la trace a etre plus SOMBRE : la valeur choisie ici (88, 125, 39) est plus claire que l'herbe (66,
94, 30), ce qui est d'ailleurs ce que fait une vraie pelouse -- les brins couches renvoient plus de lumiere.

Detail qui evite un aplat : les TACHES de Perlin s'appliquent AUSSI a la couleur d'ecrasement, avec exactement la
meme valeur de bruit. Sans ca, tout le chemin parcouru virerait a l'uniforme et effacerait le relief que les taches
viennent de donner -- le joueur laisserait une trace plus plate que l'herbe autour.

Meme quantification que la taille pour les ecritures : un pour cent d'ecart de couleur ne se voit pas, mais ecrire
une teinte par image sur des centaines de touffes coute pour rien.

## 0.0.235 — L'herbe penche D'ABORD, elle se tasse ENSUITE

Le joueur a voulu retrouver l'inclinaison au passage, sans perdre l'aplatissement. Les deux ensemble arrivaient
pourtant en bloc, et l'inclinaison disparaissait sous le tassement -- on ne voyait plus qu'un ecrasement.

Triche assumee, et efficace : les deux effets partent de la MEME cible mais ne la rejoignent pas a la meme vitesse.
L'inclinaison claque (CRUSH_SPEED 18), le tassement traine (SQUASH_SPEED 4). On lit donc l'herbe pencher, PUIS se
tasser. L'inclinaison a le temps d'exister avant d'etre recouverte.

Deux valeurs lissees au lieu d'une, comme le plancher de glisse dedouble par allure en 0.0.201 : quand un seul
reglage doit produire deux ressentis differents, on ne cherche pas le compromis, on dedouble.

La MONTEE reste commune (RECOVER_SPEED) : rien ne gagne a ce que la touffe se redresse en deux temps.

CRUSH_TILT_ANGLE remis a 28 (il valait 78 du temps ou l'inclinaison etait le seul effet, ce qui couchait la plaque
sur le flanc ; a zero depuis, ce qui la supprimait). Couleur de base passee a (133, 195, 95), et taches un peu plus
marquees (PATCH_AMOUNT 0.14 -> 0.18).

## 0.0.234 — L'herbe retrouve sa couleur, et se couvre de taches

Regression de 0.0.232 : en coupant les rayures, j'ai coupe LA SEULE CHOSE qui donnait sa couleur a l'herbe. Elle
retombait sur la teinte grise du mesh source -- une pelouse blanche.

La teinte de base est desormais un reglage a part (BASE_COLOR), independant des rayures. Ces dernieres, quand elles
sont actives, la remplacent ; quand elles ne le sont pas, elle s'applique seule. Faire porter une couleur de base par
une feature optionnelle etait le vrai defaut : couper l'option ne devait pas repeindre la pelouse.

TACHES. Des zones un peu plus claires et un peu plus sombres, en bruit de Perlin (PATCH_SCALE, PATCH_AMOUNT). Sans
elles la pelouse est un aplat parfaitement uniforme, et ca se lit comme du carton peint.

Deux choix :
- du bruit de PERLIN, pas un tirage au hasard par touffe. Le hasard pur donne du poivre et sel, ce qui est pire que
  rien ; Perlin donne de vraies ZONES, ce que l'oeil lit comme de la matiere ;
- le bruit se lit sur la position MONDE, pas sur la case de la grille. Deux touffes voisines tombent donc dans la
  meme tache, et les zones traversent les bords des zones d'herbe sans qu'on voie la couture.

Calcule UNE fois a la pose : aucun cout en jeu. L'assombrissement au passage du joueur s'applique par-dessus, sur la
couleur tachee, donc la trace garde la nuance locale.

## 0.0.233 — Le joueur spawn FACE a la maison du grand-pere

Le didacticiel posait le joueur au bon endroit mais dans un sens quelconque : il pouvait tres bien arriver dos a la
maison, et rater la premiere chose qu'il devrait voir.

L'orientation de la part de spawn etait ignoree VOLONTAIREMENT, pour ne pas coucher le joueur si elle etait posee de
travers. La correction ne consiste donc pas a reprendre la CFrame entiere -- ce qui aurait exactement produit ce
degat -- mais a n'en garder que le CAP, la rotation autour de la verticale, et a jeter l'inclinaison.

Meme operation que pour redresser un PNJ penche (`scripts/studio/RedresserPnj`). Elle revient assez souvent pour
etre notee : quand on veut le SENS d'une reference sans son assiette, on projette sur la verticale, on ne copie pas.

### A faire dans Studio

Tourner la part `RootSpawnPlayer` pour que sa FACE AVANT regarde la maison. C'est elle qui donne desormais la
direction du regard au spawn, y compris apres une mort.

## 0.0.232 — Les rayures peintes disparaissent, elles naitront de la TONTE

Deux reglages, dont un qui est une decision de conception.

STRIPE_ENABLED passe a false. Ce n'est pas un abandon : sur un vrai terrain, les bandes claires et sombres ne sont
pas peintes, elles viennent du SENS dans lequel la tondeuse a couche les brins. Les dessiner d'avance donnait un
motif FIXE, identique quoi que fasse le joueur, et qui aurait contredit sa propre tonte des qu'il coupe en travers.

Elles naitront donc de la tonte elle-meme. Et la donnee necessaire EXISTE DEJA : chaque touffe garde `tiltDir`, la
direction de son dernier passage, devenue inutilisee depuis que la bascule est passee a zero en 0.0.229. Le jour ou
on branchera la couleur par sens de tonte, ce sera quelques lignes, pas un systeme.

HEIGHT_SCALE remonte de 0.65 a 1.0 : l'herbe reprend la hauteur native de son mesh.

## 0.0.231 — L'herbe FONCE la ou on a marche

L'herbe ecrasee s'assombrit. Un chemin apparait derriere le joueur, en plus du creux.

Le point qui compte : la teinte assombrie part de la COULEUR DE LA TOUFFE, pas d'un gris impose. Chaque touffe
garde donc la nuance de SA bande de tonte, juste plus sombre -- le motif raye reste lisible SOUS la trace, au lieu
d'etre efface par un chemin d'une seule couleur.

La couleur de base est relevee APRES la pose des rayures, sinon on assombrirait la teinte du mesh d'origine et
toutes les traces sortiraient identiques.

Pilote par le meme ecrasement que l'aplatissement (CRUSH_DARKEN, 0.25). Trois effets maintenant tires de la meme
grandeur -- hauteur, couleur, extinction du vent -- donc aucun ne peut se desynchroniser des autres, et la trace
permanente reste sombre exactement la ou elle reste basse.

Ecritures quantifiees comme celles de la taille : un pour cent de clarte ne se voit pas, mais ecrire une couleur par
image sur des centaines de touffes coute pour rien.

## 0.0.230 — Des nuages traversent le ciel

Nouveau CloudController (client) + CloudConfigs. Un troupeau de nuages derive au-dessus de la carte, en boucle et
sans fin.

Deux choix portent tout l'effet :

Les nuages derivent en coordonnees MONDE et NE SUIVENT PAS le joueur. Coller le ciel au joueur serait plus simple,
mais donnerait des nuages qui avancent avec lui : plus aucune parallaxe, donc plus aucune impression de distance.
Ils vivent leur vie, on les traverse.

Le RECYCLAGE est cache par le FONDU. Quand un nuage s'eloigne trop, il est remis en amont du vent, a une place tiree
au hasard. Mais sa transparence monte bien avant cette limite : il s'efface, il revient ailleurs, deja efface. On ne
voit jamais ni la disparition ni la reapparition. Sans ce fondu, le meme systeme ferait clignoter des nuages aux
bords de l'ecran.

Details qui evitent des defauts visibles :
- vitesse propre a chaque nuage (SPEED_VARIATION) : sans elle le ciel derive d'un bloc, comme une image qu'on
  ferait glisser ;
- altitude dispersee (ALTITUDE_SPREAD) : sans elle les nuages forment une nappe plate ;
- au recyclage, un ecart lateral au hasard sur le bord amont : sinon ils arrivent tous par le meme point ;
- a la premiere mise en place, la distance est tiree en RACINE du hasard, ce qui repartit egalement sur le disque.
  Un tirage direct entasserait les nuages au centre, au-dessus du joueur ;
- rotation au hasard autour de la VERTICALE seulement : un nuage reste a plat.

100 % client, comme l'herbe : c'est du ciel, ca ne change aucune regle du jeu et rien ne transite.

Premier bouton a regler : ALTITUDE (250), qui depend entierement de l'echelle de la carte. Puis COUNT et
FIELD_RADIUS ensemble -- agrandir le rayon sans monter le nombre donne un ciel vide.

## 0.0.229 — L'herbe s'ECRASE en hauteur au lieu de basculer sur le cote

Le joueur voyait ses touffes pencher de travers en marchant dessus. Raison, donnee par lui : **le mesh d'herbe est un
RECTANGLE de brins, pas un brin isole.** Un brin qui se couche est joli ; une plaque entiere qui bascule se lit comme
un decor pose de travers, pas comme un creux dans la pelouse.

L'ecrasement devient donc PUREMENT vertical. CRUSH_TILT_ANGLE tombe a 0 (la bascule reste dans le code, elle
n'aurait de sens que sur un mesh d'un seul brin), CRUSH_SQUASH monte de 0.45 a 0.8 : la touffe descend a 20 % de sa
hauteur sous le pied. RECOVER_SPEED ralentit de 3.5 a 1.8, parce que c'est la REMONTEE qu'on regarde -- une herbe
qui rebondit en un quart de seconde ne se lit pas.

### Le renversement qui rendait ca possible

Mettre l'angle a zero ne suffisait PAS : tout l'effet en decoulait. L'aplatissement etait calcule a partir de
l'inclinaison, donc un angle nul donnait un aplatissement nul. Le reglage evident aurait supprime l'effet entier.

La valeur maitresse devient donc l'ECRASEMENT lui-meme, une fraction de 0 a 1. L'aplatissement, l'extinction du
vent et l'inclinaison eventuelle en decoulent tous les trois. Une seule grandeur lissee : rien ne peut se
desynchroniser, et chaque effet herite gratuitement du ressort.

Regle : quand un reglage a zero doit desactiver UN effet et qu'il en tue trois, c'est que la grandeur d'etat n'est
pas la bonne. Ce n'est pas le reglage qu'il faut contourner, c'est la dependance qu'il faut retourner.

Pas d'EditableMesh dans l'affaire, ni de bones : ecraser en hauteur, c'est changer la taille de la part. Meme
conclusion qu'en 0.0.205, verifiee cette fois par l'usage.

REST_TILT disparait (l'inclinaison de repos au hasard) : elle faisait double emploi avec le desordre deja modele
dans le mesh. Son tirage aleatoire est CONSERVE a vide, pour que la disposition de la pelouse ne change pas.

## 0.0.228 — L'animation de Papi jouait DANS LE VIDE : deux rigs differents

Papi glissait sur la pelouse sans remuer un membre. La mesure a tranche en deux etapes.

D'abord, en pleine partie : la piste de marche tournait avec un poids de 1, et les DOUZE Motor6D restaient a zero.
Une animation qui joue et n'ecrit rien.

Ensuite, en comparant les noms :

```
RIG  "OldManIdle" (12) : Body, Chaussure, ClotheUp1, Eyes, Hairs, Head, Lunette, Moustache, Nez, Pantalon, Sourcil
ANIM "Idle"       (29) : RootPart, mixamorig:Hips, mixamorig:Spine, mixamorig:LeftArm, mixamorig:RightFoot, ...
```

Zero nom en commun. Les animations viennent de MIXAMO et parlent a un squelette complet de 29 os ; le modele pose
dans la map est un assemblage de 12 morceaux de mesh, SANS bras ni jambes. Deux personnages differents.

Une animation Roblox retrouve les membres PAR LEUR NOM. Quand aucun ne correspond, elle joue normalement, avec un
poids de 1, et n'ecrit rien -- sans la moindre erreur nulle part. C'est le silence qui a coute l'enquete, pas la
panne.

### Ce qui change dans le code

Le PNJ passe a `enabled = false` : il glissait comme un mannequin, c'est pire que de le laisser immobile. A repasser
a true quand Papi sera exporte de Blender AVEC son squelette.

Et surtout, un CONTROLE APRES DEMARRAGE : le service releve l'etat des joints, attend, et compare. Si rien n'a bouge
alors que la piste tourne, il le DIT, en nommant l'animation et en renvoyant vers l'outil de comparaison. Cette
famille de panne ne coutera plus une enquete.

### Trois outils d'atelier nes de ce bug (scripts/studio/)

- `RedresserPnj` : redresse un corps penche en nettoyant l'inclinaison des Motor6D (a lu le C0, la pose de repos).
- `LirePenchePnj` : mesure `Transform` PENDANT une partie -- c'est la que les animations ecrivent, pas dans C0.
  C'est lui qui a montre que rien ne bougeait.
- `ComparerAnimEtRig` : telecharge l'animation, liste ses noms, liste ceux du rig, dit lesquels ne collent pas.
  C'est lui qui a donne la reponse.

Chacun repond a une question DIFFERENTE, et les trois ensemble couvrent la chaine : pose de repos, pose animee,
correspondance des noms.

## 0.0.227 — La cadence de marche de Papi suit sa vitesse reelle

Papi marchait trop vite : sa vitesse de reference passe de 5 a 3.

Mais baisser la vitesse seule aurait cree un defaut plus visible que celui qu'on corrige : une animation de marche
gardee a sa cadence d'origine sur un personnage ralenti donne l'impression qu'il PATINE. Les pieds avancent plus vite
que le corps. L'oeil le voit immediatement, meme sans savoir le nommer.

La cadence de l'animation suit donc la vitesse. WALK_ANIM_REFERENCE (3.5) est la vitesse a laquelle l'animation est
juste a sa cadence d'origine ; en dessous elle ralentit, au-dessus elle accelere, proportionnellement.

Deux choix qui comptent :
- la cadence suit la vitesse MESUREE (`AssemblyLinearVelocity`), pas la vitesse demandee. Au demarrage et a l'arret le
  personnage n'est pas encore, ou plus, a son allure : la cadence monte et redescend avec lui au lieu de claquer ;
- elle est LISSEE (WALK_ANIM_SMOOTH), et bornee (WALK_ANIM_MIN / MAX) pour qu'un a-coup de physique ne la fasse
  jamais partir en vrille.

UNE seule boucle Heartbeat accorde tous les PNJ, pas une par PNJ : elle ne fait rien tant qu'aucun ne marche.

Reglage a l'oeil : si les pieds glissent en avant, BAISSER WALK_ANIM_REFERENCE ; s'ils pietinent, la MONTER.

## 0.0.226 — Papi se promene autour de sa maison

Nouveau NpcWanderService + NpcWanderConfigs. Papi choisit un point au hasard dans sa zone (ZoneWalking), calcule un
chemin, y va en contournant la maison, les arbres et les haies, puis s'arrete un moment avant de repartir.

### Pas de pathfinding maison

Demande initiale : "un pathfinding custom stylé de ouf naturel". Refusee, et voila pourquoi. PathfindingService
(Roblox) connait deja tous les obstacles de la map et gere le contournement ; le reecrire couterait des jours pour un
resultat moins bon.

Surtout, le "naturel" ne vient PAS du calcul de chemin. Un PNJ qui suit un chemin parfait a l'air d'un robot, custom
ou pas. Ce qui donne la vie est au-dessus, et c'est la que sont les reglages :
- une PAUSE de duree variable entre deux trajets (PAUSE_MIN / PAUSE_MAX). C'est le reglage le plus important du lot :
  arriver puis repartir aussitot, toujours au meme rythme, se lit immediatement comme une machine ;
- une VITESSE differente a chaque trajet (SPEED_VARIATION) ;
- une distance MINIMALE de trajet (MIN_TRAVEL), sans quoi un tirage tombe parfois a deux pas et le PNJ fait des
  micro-deplacements qui n'ont l'air de rien.

### Details qui evitent des pannes muettes

- Le point d'arrivee est trouve par un RAYON vers le bas depuis le dessus de la zone : viser le centre en hauteur
  d'une zone volumineuse donnerait un point flottant, et aucun chemin.
- Une seule des deux animations tourne a la fois. A priorite EGALE Roblox MELANGE deux pistes au lieu de choisir,
  d'ou des priorites distinctes (Idle pour l'arret, Movement pour la marche) qui tranchent pendant les fondus.
- Un seul objet Path, reutilise a chaque trajet.
- Papi SORT de AmbientAnimConfigs : ce service possede maintenant ses deux animations. Deux services sur le meme
  Animator finiraient par se battre pour la meme piste (une propriete, un seul ecrivain).

### Ce que le service DIT quand ca ne marche pas

Chaque panne possible a son message nomme, parce qu'aucune ne se devine depuis le symptome ("il ne bouge pas") :
model introuvable, zone introuvable, zone AVEC collision (elle bloque alors tous les chemins), pas de Humanoid, pas
d'Animator, animations non chargeables, et surtout **pas de part nommee `HumanoidRootPart`** -- Roblox cherche ce nom
EXACT pour deplacer un personnage, et sans elle l'animation joue pendant que MoveTo ne fait rien.

### A faire dans Studio

- Renommer la `RootPart` de Papi en `HumanoidRootPart`, et la mettre en PrimaryPart du Model.
- Aucune part ancree sur lui (l'inverse de ce qu'il fallait pour un PNJ statique).
- `ZoneWalking` sans collision : sinon elle devient un obstacle et aucun chemin ne passe a l'interieur.

Reste a faire : qu'il REMARQUE le joueur (venir vers lui, le regarder, puis reprendre sa balade).

## 0.0.225 — Papi ne s'animait pas : il n'etait pas SOUS la racine cherchee

L'animation de Papi ne partait pas. Le modele OldManIdle est pose en enfant DIRECT du Workspace, pas sous
`Worlds.Maps` ou la recherche s'arretait. Il n'etait donc jamais vu.

Deuxieme fois de suite (la ZoneGrassHandle avait exactement le meme souci). Obliger a ranger un modele au bon endroit
pour qu'il s'anime est un piege : rien a l'ecran ne dit pourquoi ca ne marche pas, et le code a l'air juste.

La racine passe donc a tout le WORKSPACE. Le cout est nul : tout ce qui y naît -- des milliers de carreaux de haie,
les debris de coupe -- est ecarte par un `IsA("Model")` avant meme le test de nom.

### Le vrai correctif est le DIAGNOSTIC

Elargir la racine ne repare que ce cas-la. Ce qui manquait vraiment, c'est que le service se taisait quand il ne
trouvait rien. Deux avertissements ajoutes :

- une entree de config sous laquelle RIEN n'a ete anime le dit en clair, avec son nom ;
- un modele trouve au bon nom mais SANS Animator le dit aussi -- sinon on cherche du cote de l'animation alors que
  c'est le rig qui manque.

Et le log de demarrage detaille ce qui a ete anime, par nom et par nombre : `Bush1 x5, Tree1 x3, OldManIdle x1`.

Regle : un service qui parcourt le monde pour y trouver des choses doit dire ce qu'il N'A PAS trouve. Un compteur
global ("8 modeles animes") ne revele jamais l'absence de la neuvieme.

## 0.0.224 — Papi respire, et FoliageService devient AmbientAnimService

Papi (le modele OldManIdle pose dans la map) joue son animation d'attente en boucle.

AUCUN code nouveau : FoliageService faisait deja exactement ce travail -- un modele avec Humanoid et Animator dans la
map, une boucle qui tourne. Un buisson qui se balance et un grand-pere qui respire, c'est le meme besoin. Il a suffi
d'une ligne dans la config.

Mais un service appele "Foliage" qui anime un grand-pere est un nom qui MENT, et le journal a deja paye ce piege une
fois (l'auto-equip du taille-haie planque dans le controller d'ECHELLE, introuvable pendant des heures). Renommage
donc : FoliageService -> AmbientAnimService, FoliageConfigs -> AmbientAnimConfigs.

La racine de recherche s'elargit de `Worlds.Maps.Assets.Foliages` a `Worlds.Maps` : les plantes sont rangees dans un
dossier, les PNJ sont poses directement dans la map, et d'autres viendront ailleurs. Le cout est nul -- les milliers
de carreaux de haie qui naissent sous cette racine sont ecartes par un `IsA("Model")` avant meme le test de nom.

### A faire dans Studio

Les parts du modele NE DOIVENT PAS etre ancrees : une part ancree ignore son Motor6D, donc l'animation joue sans que
rien ne bouge (piege deja au journal). Pour un PNJ qui doit rester plante au meme endroit, ancrer UNIQUEMENT la
RootPart : le reste suit l'animation et le personnage ne derive pas.

## 0.0.223 — L'herbe RESTE couchee la ou on a marche

Un chemin se dessine derriere le joueur. C'est la premiere fois que le monde GARDE la trace d'un geste : jusqu'ici
tout revenait a son etat d'avant.

Deux effets SEPARES, et c'est la separation qui fait tout marcher :
- l'ecrasement ELASTIQUE, inchange, garde son coup sec sous le pied ;
- par-dessus, un couchage PERMANENT (`flattened`, 0 a 1) qui ne fait que MONTER.

La cible d'inclinaison devient le plus couche des trois : le pied en cours, la trace deja laissee, l'inclinaison de
repos. Quand le pied repart, l'herbe remonte donc jusqu'a la TRACE et s'y arrete, au lieu de revenir droite. On garde
le ressort ou il sert (le contact) sans qu'il efface ce qu'on veut retenir.

Le niveau ne descend jamais tout seul : repasser au meme endroit ne releve rien, s'eloigner ne l'efface pas. La
direction gardee est celle du DERNIER passage, donc la trace suit le sens du pas.

FLATTEN_AMOUNT (0.8) regle a quel point la trace reste couchee ; 0 rend l'ancien comportement sans trace.
FLATTEN_RECOVER (0) permet de la faire disparaitre lentement si on prefere -- 0.02 l'efface en une cinquantaine de
secondes.

Cout : nul. Une touffe couchee atteint sa cible et cesse d'etre reecrite, exactement comme une touffe au repos. Le
tassement vertical et l'extinction du vent suivent d'eux-memes, puisqu'ils sont deja tires de l'angle d'ecrasement.

A savoir : la trace est LOCALE, comme tout ce systeme. Un chemin trace pendant qu'un autre joueur etait loin
n'existera pas chez lui. Sans importance pour du decor ; a revoir le jour ou la tonte devra etre partagee.

## 0.0.222 — L'herbe ne grandit plus quand on baisse la densite

Personnage completement noye dans l'herbe apres le passage a DENSITY 0.2.

Le grossissement de compensation pose en 0.0.219 s'appliquait a la taille ENTIERE, hauteur comprise : a densite 0.2,
les touffes devenaient 2.24 fois plus grosses, donc 2.24 fois plus HAUTES. Le joueur disparaissait dedans.

Erreur de raisonnement simple une fois vue : couvrir le sol est une affaire HORIZONTALE. Une touffe plus large cache
plus de terre ; une touffe plus haute ne cache rien de plus et mange le personnage. Le facteur ne touche donc plus
que X et Z, jamais Y. La hauteur de l'herbe ne depend plus du tout du nombre de touffes -- ce sont deux reglages
independants, comme ils auraient toujours du l'etre.

STRIPE_ON_SURFACE passe a false : VERIFIE A L'ECRAN, sur ce mesh c'est le Color de la MeshPart qui donne la bonne
teinte. Ecrire sur le SurfaceAppearance rendait l'herbe BLEUE quelles que soient les couleurs demandees -- le
TintMask ne se combine pas comme on l'imagine. Le doute etait signale dans la config en 0.0.215 faute d'avoir pu
tester ; l'ecran a tranche, la config dit maintenant la reponse au lieu de la question.

## 0.0.221 — Le SOL passait pour un objet pose et effacait toute l'herbe

Regression introduite juste avant : plus une seule touffe ne se generait.

La recherche des objets poses se fait dans une boite posee SUR le dessus de la zone. Or `GetPartBoundsInBox` teste
des BOITES ENGLOBANTES, et le sol de la carte (la grosse part verte sous la pelouse) a son dessus qui AFFLEURE la
zone : sa boite touchait la mienne de quelques centiemes de stud. Il etait donc compte comme un objet pose, et son
emprise couvre la totalite de la pelouse -> toute l'herbe effacee.

Il manquait une condition evidente une fois vue : un objet doit DEPASSER de la pelouse, pas seulement la toucher.
Nouveau CLEAR_MIN_HEIGHT (0.5 stud). Le depassement se mesure en projetant la demi-taille de l'objet sur la verticale
de la zone, ce qui reste juste meme pose de travers.

Second garde-fou ajoute dans la foulee : une part rangee SOUS une autre part (les carreaux d'une haie, les touffes
sous leur propre zone) n'est plus prise comme objet. C'est l'objet parent qui porte l'emprise. Sans ca, les milliers
de carreaux de haie saturaient la limite de la recherche et faisaient RATER la haie elle-meme -- un bug qui serait
apparu plus tard, et bien plus difficile a lire.

Le log NOMME desormais les objets qui ont chasse de l'herbe, pas seulement leur nombre. Le jour ou une pelouse se vide
encore, la ligne dira qui l'a mangee au lieu de laisser deviner. C'est ce qui manquait ici.

Lecon : un test de proximite base sur des boites englobantes attrape TOUJOURS le support sur lequel la chose repose.
Toute detection "qu'est-ce qui est POSE sur X" doit exclure X et tout ce qui affleure X, sinon le sol se designe
lui-meme.

## 0.0.220 — L'herbe s'enleve sous les objets poses, et le semis cesse de geler le client

Trois choses, dont deux dictees par une MESURE en jeu.

### L'herbe s'enleve sous ce qu'on pose dessus

Une part posee sur la zone (une haie, plus tard un objet de construction) chasse l'herbe sous elle : sans ca, des
brins traversent le pied de l'objet et ca se voit immediatement.

Automatique, rien a taguer : tout ce qui touche le dessus de la zone compte, sauf trois familles -- l'herbe
elle-meme, les autres zones (ce sont des marqueurs), et les PERSONNAGES. Ce dernier point n'est pas un detail : un
joueur qui traverse la pelouse pendant le semis y creuserait sinon un trou definitif.

Le test se fait en repere OBJET (`PointToObjectSpace`), pas en boite alignee sur le monde : une haie posee de travers
chasse l'herbe sous ELLE. Et tous les tirages au sort sont faits AVANT le test d'emprise, pour que la disposition
reste identique chez tous les joueurs meme si l'un d'eux n'a pas encore recu l'objet par le streaming -- il verra une
touffe de plus, jamais un semis different.

### La mesure qui change tout

Log d'une vraie carte, quatre pelouses (133x50, 133x52, 81x53, 32x7) : **18 546 touffes**. Injouable, et la creation
gelait le client environ 600 ms par zone.

DENSITY passe de 1.0 a 0.2 -> environ 3 700 parts, avec des touffes 2.2x plus grosses (AUTO_SCALE_WITH_DENSITY pose
en 0.0.219 sert exactement a ca) donc une couverture visuelle equivalente. Le decouplage densite / taille rend cet
arbitrage gratuit a l'ecran.

### Le semis s'etale sur plusieurs images

Fabriquer des milliers de parts d'un coup gele le client. La creation cede la main toutes les CREATE_BUDGET touffes
(500), et le dossier est parente des la premiere pause : l'herbe se remplit en une fraction de seconde au lieu de
surgir apres un a-coup.

Deux pieges que ca ouvre, et qui sont bouches :
- Un semis qui demarre pendant qu'un autre tourne remplirait la meme zone A DEUX. Un compteur de generation par zone
  fait abandonner proprement l'ancien.
- `populate` peut desormais YIELD, donc tous ses appelants doivent etre dans un thread a part. `consider` est branche
  sur DescendantAdded : y attendre bloquerait ce signal pour toute la map. Il passe en task.spawn.

### Ce que la mesure ne resout pas

Meme a 3 700 parts, une part par touffe ne passera pas a l'echelle d'une carte entiere. Le sujet reste ouvert : soit
un pool de touffes qui SUIT le joueur (cout constant, surface illimitee), soit l'herbe du moteur (Terrain.Decoration),
qui est gratuite mais ne s'ecrase pas sous les pieds.

## 0.0.219 — Densite CONSTANTE quelle que soit la taille de la zone

Demande du joueur, et elle vise juste : redimensionner une zone ne doit JAMAIS obliger a revenir toucher une config.
Deux fois de suite (0.0.210, 0.0.218) le plafond de touffes a rabote la densite dans le dos du joueur, qui voyait
son herbe se clairsemer en agrandissant son terrain -- l'inverse de ce que la config annoncait.

MAX_CLUMPS cesse d'etre un reglage. Il passe a 20000, volontairement hors de portee de toute zone reelle, et redevient
ce qu'il aurait toujours du etre : un filet contre une part posee par erreur a 500x500, qui ferait tomber le client.
S'il se declenche, ce n'est pas un bouton a tourner, c'est le signe que la zone est anormale -- le message le dit
maintenant dans ces termes.

### Le vrai correctif ergonomique : la taille des touffes compense la densite

Le probleme de fond, c'est que DENSITY etait a la fois le bouton de PERFORMANCE et le bouton de "trous dans l'herbe".
Impossible d'alleger un grand terrain sans le degarnir.

Les touffes grandissent donc dans le rapport exact de l'espacement (AUTO_SCALE_WITH_DENSITY). A DENSITY 0.25, elles
sont deux fois plus grosses : meme couverture a l'ecran, quatre fois moins de parts. DENSITY devient un bouton de
performance PUR, qu'on peut baisser sur un grand terrain sans que ca se voie.

A DENSITY = 1 le facteur vaut exactement 1 : le rendu actuel ne bouge pas.

Le facteur se calcule sur l'espacement REEL, apres le filet de securite, pas sur celui demande. Si le filet devait un
jour espacer la grille, les touffes compenseraient aussi -- sinon ce cas rare rouvrirait exactement les trous qu'on
vient de fermer.

Lecon generale : quand un seul reglage porte deux responsabilites opposees (ici la qualite visuelle ET le cout), on
ne l'equilibre pas, on les DECOUPLE. Meme raisonnement que le plancher de glisse dedouble par allure en 0.0.201.

## 0.0.218 — Le plafond rabotait encore la densite des grandes zones

Herbe clairsemee sur un grand terrain. Meme cause qu'en 0.0.210, un cran plus haut : MAX_CLUMPS (1500) mordait de
nouveau. Une zone de 70x70 demande 4900 touffes a une par stud carre ; le plafond en autorisait 1500, donc la grille
etait espacee pour couvrir quand meme toute la surface -- et la densite tombait autour de 0.3 au lieu de 1.0.

MAX_CLUMPS passe a 4000. Mais le vrai correctif est dans le MESSAGE : il annonce desormais la DENSITE REELLEMENT
obtenue, pas seulement la taille de la grille. C'est ce chiffre-la qui explique une herbe clairsemee. Sans lui, on
tourne le bouton DENSITY sans que rien ne change, et on cherche le probleme dans le semis alors qu'il est dans le
plafond.

Note ajoutee dans la config, parce que la question va revenir a la prochaine grande zone : monter MAX_CLUMPS
indefiniment n'est pas la reponse. Le nombre de parts suit la surface, il n'y a pas de repas gratuit. Le vrai levier
pour un grand terrain, c'est des touffes PLUS GROSSES (SCALE_MIN / SCALE_MAX) avec une DENSITY plus basse : meme
couverture a l'ecran, deux a trois fois moins de parts.

Lecon generale : un garde-fou qui, lorsqu'il mord, DEGRADE silencieusement la qualite au lieu de refuser, doit dire
en clair ce qu'il a degrade et de combien. Sinon il se fait passer pour un reglage mal tourne.

## 0.0.217 — Plus de trous dans l'herbe : semis en QUINCONCE

Des trous apparaissaient par endroits dans l'herbe. Le quadrillage etait pourtant parfaitement regulier : une case,
une touffe, cases identiques. Le coupable etait le JITTER, l'ecart au hasard applique DANS chaque case. A 0.8, deux
voisines pouvaient s'ecarter de 80 % d'une case -- et cet ecart-la se voit.

Baisser simplement le jitter aurait ramene un alignement visible en damier. La vraie correction porte sur la FORME du
quadrillage : les rangees passent en QUINCONCE, une sur deux decalee d'une demi-case par rapport a l'autre. C'est
l'empilement qui couvre le mieux un plan a nombre egal de points ; une grille carree, elle, laisse un losange vide au
milieu de chaque groupe de quatre voisines.

Le decalage est SYMETRIQUE (un quart de case a droite sur une rangee, un quart a gauche sur la suivante) plutot qu'une
demi-case sur une rangee sur deux : l'ecart entre rangees est le meme, mais aucune touffe ne deborde de la zone.

Le quinconce cassant deja la regularite a lui seul, le JITTER redescend a 0.45 : on garde le desordre sans rouvrir de
trou.

Regle a retenir : quand un semis laisse des trous, regarder la MAILLE avant de tripoter la quantite d'aleatoire. Ici
la bonne correction ne coute aucune touffe de plus.

## 0.0.216 — Le vent souffle par RAFALES (Perlin), et la rafale tasse l'herbe

Le vent etait une seule sinusoide : toutes les touffes recevaient exactement le meme souffle au meme moment, decale
par leur position. Ca bougeait, mais ca se lisait comme un ventilateur, pas comme du vent.

RAFALES. Un champ de bruit de Perlin (`math.noise`, integre a Roblox) qui DERIVE dans la direction du vent : des
zones de vent fort et des zones calmes roulent sur le champ. L'oscillation rapide reste PAR-DESSUS -- elle donne le
fremissement de chaque touffe, la rafale donne la respiration large du champ. Deux echelles superposees, c'est ce
qui distingue un mouvement organique d'un mouvement periodique.

GUST_SCALE (taille des zones, plus bas = plus larges), GUST_SPEED (vitesse de deplacement des rafales), GUST_FLOOR
(force du vent dans les zones les plus calmes -- a 0 le champ s'arrete completement entre deux rafales).

TASSEMENT. La rafale ecrase legerement l'herbe au passage, puis la laisse remonter (GUST_SQUASH, 0.12). Seule la
partie FORTE de la rafale tasse : une zone calme ne doit pas maintenir l'herbe basse en permanence. Le tassement se
multiplie avec celui de l'ecrasement au pied, et s'efface quand la touffe est deja couchee sous un joueur.

### Le cout, et ce qui a ete fait pour le tenir

Le tassement fait varier la HAUTEUR en continu sur toutes les touffes visibles, alors qu'avant seules celles sous un
pied changeaient de taille. Redimensionner une part coute plus cher que la deplacer : c'etait le risque du
changement.

L'aplatissement est donc arrondi a un pas de 1 % (SQUASH_STEP). Un pour cent de hauteur est invisible a l'oeil
(0.05 stud sur une touffe de 5) mais divise le nombre d'ecritures de Size par dix. Le pas divise 1 exactement, donc
au repos l'aplatissement retombe sur 1 PILE : pas de residu fige. C'est la difference avec un garde-fou "ne pas
reecrire si le delta est infime", qui lui figerait justement ce residu.

Rayures remises droites (STRIPE_HEADING 45 -> 0).

## 0.0.215 — Rayures de tonte dans l'herbe, facon terrain de foot

Demande du joueur, pour le plaisir. Une bande sur deux prend une teinte differente : (212, 179, 152) et
(212, 203, 157).

La grille du semis rendait ca presque gratuit : chaque touffe connait deja sa case, il suffit de projeter le centre
de cette case sur la direction des rayures et de regarder si on tombe sur une bande paire ou impaire. Decide UNE
fois a la pose, aucun cout par image.

Detail qui compte : la bande se calcule sur le CENTRE DE CASE, pas sur la position finale de la touffe. L'ecart au
hasard du semis (JITTER) ferait sinon baver les bandes l'une dans l'autre, et on perdrait la ligne nette qui fait
tout l'effet d'un terrain tondu.

STRIPE_HEADING donne l'orientation des bandes dans le repere de la ZONE, en degres : 0 pour des rayures droites, 45
pour des diagonales. STRIPE_WIDTH leur largeur en studs.

Point a verifier a l'ecran : la couleur est ecrite sur le SurfaceAppearance de chaque touffe, parce que c'est la que
la couleur de base est reglee dans Studio. Avec AlphaMode = TintMask, la teinte peut aussi venir du Color de la part
selon la configuration du mesh -- STRIPE_ON_SURFACE bascule entre les deux si les rayures n'apparaissent pas.

## 0.0.214 — Le rideau de chargement attend le PERSONNAGE avant de compter

Le rideau paraissait beaucoup trop court, malgre un LOADING_MIN deja monte a 10.5 s. La raison : ce plancher etait
compte depuis le CLIC, pas depuis l'arrivee du personnage. Quand celui-ci met plusieurs secondes a se mettre en place
(chargement des donnees, session lock ProfileStore, teleportation sur le plot), le plancher est deja presque ecoule
quand il apparait -- le rideau se leve dans la seconde qui suit, et la transition est brutale.

Un plancher compte depuis un instant qui n'a rien a voir avec l'evenement qu'il doit couvrir ne garantit rien : il
protege les cas rapides et laisse tomber les cas lents, c'est-a-dire exactement ceux qui en avaient besoin.

`finishLoading` attend maintenant le personnage (et sa RootPart, via WaitForChild avec timeout -- a CharacterAdded le
personnage est parente mais pas complet), PUIS lance un compte a rebours de LOADING_AFTER_CHARACTER (5 s). Le plancher
depuis le clic est conserve : les deux se cumulent, on part au plus tard des deux. Le rideau couvre donc toujours la
mise en place du personnage, quelle que soit sa duree.

Commentaire de LOADING_MIN remis a jour au passage : il annoncait "~6-7 s" pour une valeur passee a 10.5.

## 0.0.213 — Le champ d'action du vent est centre sur MON PERSONNAGE

Le tri du vent se mesurait depuis la CAMERA. Il se mesure maintenant depuis le personnage du joueur local.

La camera peut balayer loin, dezoomer, ou etre scriptee (chantier, arrivee sur le plot, cinematique) : elle ne dit
pas ou est le joueur. Ce qui definit "autour de moi" c'est ou JE suis. En prime, l'ecrasement etait deja ancre sur
les personnages : les deux tris regardent enfin la meme chose.

Repli sur la camera tant que le personnage n'a pas spawn. Sans lui, le champ serait centre sur l'origine du monde et
toute l'herbe resterait figee pendant le chargement -- exactement le genre de detail qui se decouvre en jeu publie et
pas en Studio.

Champ resserre : WIND_FADE_START 30 -> 25, WIND_VIEW_DISTANCE 60 -> 40. Le fondu s'etalait de 30 a 60 studs, donc
l'herbe bougeait encore un peu a 45 studs et ca se voyait. Hors des 40 studs, elle est maintenant STATIQUE au sens
strict : plus un calcul, plus une ecriture. Les 15 studs de fondu restants suffisent a ce que la limite ne se voie
pas ; en dessous de cet ecart, l'anneau reapparait.

## 0.0.212 — Le vent s'ETEINT avec la distance au lieu d'etre coupe net

Retour du joueur : l'herbe lointaine ondule encore. Ce n'etait pas un oubli mais le REGLAGE : WIND_VIEW_DISTANCE
valait 80, plus le rayon du pave, soit une coupure vers 90 studs -- alors que la zone de test fait 44 studs de long.
On ne sortait jamais du rayon, donc on ne voyait jamais la coupure.

Baisser simplement le chiffre aurait fabrique un ANNEAU autour du joueur, ou l'herbe se fige d'un coup quand il
avance. Un tri de perf ne doit pas devenir un artefact visible.

Le vent est donc a pleine amplitude jusqu'a WIND_FADE_START (30), puis s'eteint progressivement pour atteindre ZERO
pile a WIND_VIEW_DISTANCE (60), ou l'on cesse tout calcul. La coupure tombe la ou l'amplitude est deja nulle :
invisible a l'ecran, et l'economie est exactement la meme.

L'echelle de vent se calcule PAR PAVE, pas par touffe (a 6 studs de cote, elles sont toutes a la meme distance de la
camera) : une division par pave, pas 1500. Et un pave a vent nul retombe sur le regime economique deja en place --
plus aucune ecriture tant que l'ecrasement ne bouge pas.

Regle a garder : quand un tri par distance devient visible, ce n'est pas le seuil qu'il faut deplacer, c'est la
transition qu'il faut fondre. Meme famille que la surface a distance constante d'une boite qui EST deja un rectangle
arrondi : la bonne correction supprime la bascule au lieu de l'interpoler apres coup.

## 0.0.211 — L'herbe se trie par PAVES au lieu d'etre parcourue en entier

Demande du joueur : "une zone d'action pour animer l'herbe, comme la haie". Le defaut etait reel. La boucle
parcourait TOUTES les touffes de toute zone visible -- jusqu'a 1500 -- et faisait tourner pour CHACUNE la recherche
du joueur le plus proche, alors qu'au plus une vingtaine peut etre ecrasee a un instant donne.

Les touffes sont desormais regroupees en PAVES (BUCKET_SIZE, 6 studs de cote), et c'est le pave qui est teste, pas
la touffe. Deux gains, de natures differentes :

- Un pave hors de vue est saute EN BLOC. Avant, chaque touffe payait sa propre mesure de distance a la camera. A
  6 studs de cote, toutes les touffes d'un pave sont a la meme distance : une mesure par pave suffit.
- Surtout : pour chaque pave on etablit d'abord la liste des joueurs capables de l'atteindre. Cette liste est VIDE
  pour la quasi-totalite des paves, donc la boucle d'ecrasement de leurs touffes ne s'execute pas du tout. C'est le
  vrai gain : le cout de l'ecrasement suit le nombre de touffes REELLEMENT sous un pied, plus le nombre total.

Details qui evitent des bugs silencieux :
- Le rayon d'un pave vient des bornes REELLES de ses touffes, pas de la case theorique. L'ecart au hasard du semis
  peut pousser une touffe hors de sa case ; un rayon trop court la ferait disparaitre des tests sans rien signaler.
- Ce rayon inclut la HAUTEUR de la plus grande touffe : le tri doit englober ce qu'on VOIT, pas seulement les pieds.
- Il est retranche des deux tests de distance, sinon un pave a cheval sur la limite serait ecarte alors qu'une
  partie de ses touffes est visible.
- Le `settling` descend au niveau du pave : un pave dont des touffes se relevent garde la main meme hors de vue,
  sinon elles se figeraient couchees des qu'on tourne la camera.
- `refresh` (zone deplacee) recalcule AUSSI les centres de paves. Les oublier trierait sur l'ancienne position et
  l'herbe cesserait de reagir sans qu'on voie pourquoi.

Le log de pose annonce maintenant le nombre de paves.

Note d'honnetete : ce changement est fait parce que c'est la bonne structure, pas parce qu'une mesure a montre un
probleme. Le dernier chiffre connu est 6.37 ms avec 570 touffes, avant le vent, l'aplatissement et le passage a 1500.
A mesurer avant / apres plutot qu'a supposer.

## 0.0.210 — L'herbe s'APLATIT sous le pied, et la densite ne depend plus de la taille de la zone

APLATISSEMENT. La touffe ne fait plus que se coucher : elle s'ECRASE aussi en hauteur sous le pied, puis remonte.
CRUSH_SQUASH (0.45) = la fraction de hauteur perdue au maximum de l'ecrasement.

Le point de conception : l'aplatissement est tire du MEME angle d'ecrasement que la bascule, pas d'un second
lissage. Une seule valeur (`crushed`, 0 a 1) qui sert deux fois -- elle efface le vent et elle rabote la hauteur.
Consequences gratuites : les deux ne peuvent pas se desynchroniser, et l'aplatissement herite du ressort deja regle
(sec a la descente, lent a la remontee) sans avoir ses propres boutons. Meme raisonnement que le knob par allure de
0.0.201 pris a l'envers : ici il n'y a qu'UNE cause, donc UNE valeur, et surtout pas deux a maintenir d'accord.

La demi-hauteur suit l'aplatissement dans le calcul du CFrame, sinon une touffe ecrasee flotterait au-dessus de son
pied. Et la taille ne s'ECRIT que si elle a change : redimensionner une part coute plus cher que la deplacer, donc
une touffe debout ne paye rien. Pas de garde-fou "delta infime" sur cette comparaison : l'angle se cle exactement sur
sa cible, donc l'aplatissement retombe exactement a 1 ; un seuil figerait le residu au lieu de le laisser remonter.

DENSITE. MAX_CLUMPS passe de 600 a 1500. Ce n'etait pas un reglage de densite mais un garde-fou, et il etait trop
bas : la zone de test voulait 792 touffes (44x18 studs a une touffe par stud carre) et n'en recevait que 570. Donc
plus une zone etait grande, plus son herbe devenait CLAIRSEMEE -- l'inverse de ce qu'on veut. La densite est portee
par DENSITY seule, identique partout ; le nombre de touffes suit la surface. Le plafond ne sert plus qu'a empecher
qu'une part posee par erreur a 500x500 fabrique 250 000 instances.

A surveiller : une grande zone peut maintenant monter a 1500 parts. Repere d'avant : 6.37 ms de moyenne avec 570
touffes (4.71 ms a vide). Si le FPS tombe, baisser WIND_VIEW_DISTANCE avant DENSITY -- on perd du mouvement au loin,
pas de l'herbe.

## 0.0.209 — L'herbe ne bougeait pas : la boucle n'etait jamais branchee

Ni vent ni ecrasement sur l'herbe de zone. Le log a donne la reponse en deux lignes :

```
15:49:49.855  [GrassZone] Aucune zone "ZoneGrass..." dans cette place.
15:49:52.802  [GrassZone] "ZoneGrassHandle" plafonne : grille ramenee a 38x15
```

La zone n'existe PAS au demarrage : elle arrive 3 secondes plus tard par le STREAMING. Or `init` faisait un `return`
sur "aucune zone au demarrage", et ce `return` etait pose JUSTE AVANT le `Heartbeat:Connect`. La zone arrivait
ensuite par DescendantAdded, se remplissait correctement -- l'herbe s'affichait, bien posee, bien dense -- mais plus
aucune boucle ne tournait dessus.

Symptome trompeur au possible : tout ce qui est VISIBLE est parfait, donc on cherche le bug du cote de l'animation
(le calcul du vent, la composition des rotations, le seuil d'ecrasement) alors que rien n'est jamais appele. Et ca
explique retroactivement le tas de touffes empilees de 0.0.207 : a l'epoque la pose initiale venait de cette meme
boucle jamais branchee.

Regle : un `return` pose sur "rien a faire POUR L'INSTANT" ne doit jamais court-circuiter l'ABONNEMENT a ce qui
arrivera plus tard. Avec du streaming, "absent au demarrage" est un etat NORMAL, pas une fin de non-recevoir. La
boucle se branche maintenant dans tous les cas ; `update` sort immediatement tant que la liste est vide, donc ne pas
la brancher n'economisait rien.

### Deux corollaires du meme log

Le semis se refaisait TROIS fois en 80 ms (38x15, 39x15, 30x19). Une part qui arrive par le streaming recoit ses
proprietes en plusieurs etapes, donc `Size` change plusieurs fois de suite, et chaque changement reconstruisait 570
touffes. La reconstruction passe en DIFFERE (0.25 s, coalescee) : une seule, sur la taille finale.

Le log detaille ne sortait qu'au boot, donc jamais pour une zone arrivee apres. Il sort maintenant a CHAQUE pose. Un
diagnostic qui ne se declenche pas dans le cas qui pose probleme ne sert a rien.

## 0.0.208 — Le vent passe dans l'herbe

L'herbe de zone ondule. Le vent souffle dans une direction reglable (WIND_HEADING) et chaque touffe oscille autour
d'une inclinaison moyenne.

Le point qui fait tout : le decalage de l'oscillation depend de la POSITION de la touffe le long du vent. Des VAGUES
traversent donc le champ, les touffes en amont bougent avant celles en aval. Sans ce decalage, tout le champ respire
en bloc au meme instant, et l'oeil lit ca comme du faux immediatement -- meme famille que les buissons qui se
balancaient a l'unisson en 0.0.204. Un decalage propre a chaque touffe (windPhase) casse ce qui resterait d'identique
entre deux voisines exactement alignees.

Vent et ecrasement se COMPOSENT au lieu de se disputer la meme valeur : deux rotations enchainees sur le meme CFrame,
l'ecrasement d'abord (fort, direction variable), le vent ensuite (faible, direction fixe). Et le vent s'EFFACE a
mesure que la touffe est ecrasee : une touffe couchee sous un pied ne doit plus onduler.

### Le tri qui rend ca abordable

Le vent oblige a reecrire chaque touffe VISIBLE a chaque image, alors que l'ecrasement ne touchait qu'une vingtaine
de touffes autour du joueur. Sans tri, un grand champ deviendrait cher.

Tri par distance a la CAMERA (WIND_VIEW_DISTANCE, 80 studs), a deux etages : une zone entierement hors de vue est
ecartee d'un bloc, et dans une zone visible, une touffe trop lointaine ne calcule pas son vent. Mieux : une touffe
lointaine ET immobile n'est plus reecrite du tout (`lastTilt` remplace le drapeau `resting`, qui ne voulait plus rien
dire une fois que le vent bouge tout en permanence). Le mouvement d'un brin ne se voit pas a 80 studs mais il coute
exactement le meme prix a calculer : WIND_VIEW_DISTANCE est donc le premier bouton a baisser si le FPS tombe.

Mesure d'avant, pour comparer apres : 6.37 ms de moyenne avec le semis seul (contre 4.71 ms a vide et 6.92 ms avec le
systeme de taille). L'herbe ne coutait rien de mesurable ; a verifier maintenant que tout bouge.

## 0.0.207 — Le semis passe en GRILLE, et la touffe est posee des sa creation

Deux changements sur l'herbe de zone, apres un retour ou toutes les touffes etaient empilees au meme point, loin de
la zone.

POSE IMMEDIATE. Chaque touffe recoit son CFrame dans `populate`, a l'instant ou elle est creee. Avant, la pose
initiale etait laissee a la 1re passe de la boucle Heartbeat : si cette passe ne tombait pas (zone ecartee, ordre de
boot, quoi que ce soit), les touffes restaient a la position du CLONE, c'est-a-dire la ou dort GrassMesh dans
ReplicatedStorage -- toutes au meme endroit, ce qui est exactement le symptome observe. Regle : ne jamais dependre
d'une passe ULTERIEURE pour un placement INITIAL. Ce qui doit etre pose l'est a la creation ; la boucle ne fait plus
que l'animation.

SEMIS EN GRILLE. Le tirage etait purement aleatoire sur la surface : ca laisse des trous a un endroit et des paquets
a un autre, et sur une surface qu'on veut COUVERTE ca se voit immediatement. Desormais une case par touffe sur toute
la face du dessus, plus un ecart au hasard DANS la case (JITTER 0.8) pour casser l'alignement en damier. Couverture
garantie jusqu'aux bords, sans regularite visible.

Au plafond (MAX_CLUMPS), on ESPACE la grille au lieu de couper la liste. Couper aurait laisse une moitie de zone
chauve -- le contraire du but. La zone reste couverte, juste moins dense.

Reglages revus pour une vraie couverture : DENSITY 0.5 -> 1.0 (une touffe par stud carre), MAX_CLUMPS 400 -> 600.

Le log de demarrage devient bavard EXPRES : taille de la zone, centre de la zone, position de la 1re touffe. Quand
l'herbe atterrit au mauvais endroit, ces trois nombres disent tout de suite si c'est le semis ou la zone qui est en
cause, au lieu de raisonner sur une capture d'ecran.

## 0.0.206 — L'herbe suit sa zone quand on la deplace

Suite directe de 0.0.205. En bougeant ZoneGrassHandle PENDANT un test, l'herbe est restee sur place : un carre de
touffes a la bonne forme et a la bonne orientation, mais a dix metres de la zone.

Cause : etre ENFANT d'une part ne veut pas dire etre SOUDE a elle. Les touffes sont ancrees et posees en coordonnees
MONDE ; deplacer leur parent ne les emmene pas. Le semis etait calcule une fois au demarrage et jamais retraduit.

Correction : la position de chaque touffe est desormais gardee dans le repere de la ZONE (localPos), et sa traduction
en monde est recalculee quand la zone bouge. Deux ecoutes sur la part :
- `CFrame` change -> on retraduit les pieds et on reveille les touffes (elles se reposent au bon endroit).
- `Size` change -> on REFAIT le semis : une autre surface veut un autre nombre de touffes, reposer les anciennes ne
  suffirait pas.

Le cache monde est garde : la multiplication CFrame ne se refait QUE quand la zone bouge, pas a chaque image.

Au passage, `stop()` coupe maintenant aussi ces ecoutes (elles vivent sur des parts de la map, qui survivent au
script), pas seulement la boucle Heartbeat.

Detail d'outil : `Vector3.yAxis` remplace par une constante `UP`. Selene ne reconnait pas `Vector3.yAxis` comme un
Vector3 et refuse `:Cross()` dessus -- faux positif, mais un faux positif rouge dans l'editeur finit par masquer les
vraies erreurs.

## 0.0.205 — L'herbe se couche sous les pieds

Nouveau GrassZoneController (client) + GrassZoneConfigs. Toute part de la map dont le nom commence par "ZoneGrass"
se remplit de touffes d'herbe (le mesh ReplicatedStorage.Assets.Contents.Foliages.GrassMesh), et ces touffes se
couchent quand un joueur marche dessus, puis se relevent.

TOUT EST LOCAL, et c'est le point important. Les touffes sont creees par CHAQUE client dans SA copie du Workspace :
rien ne transite, ni a la creation ni a l'ecrasement. C'est l'INVERSE du choix fait la veille pour le decor vegetal
(FoliageService, serveur) et les deux sont justes : le balancement d'un arbre est le meme pour tout le monde et se
replique une fois, l'ecrasement de l'herbe depend de qui marche ou, a chaque image. La regle a retenir : ce qui est
IDENTIQUE pour tous et rare va au serveur, ce qui depend de la POSITION de chacun et change chaque image reste chez
le client.

Pour que la disposition reste la meme chez tout le monde sans envoyer un octet, le tirage au sort part d'une GRAINE
calculee sur la position de la zone. Deux joueurs cote a cote voient exactement la meme herbe.

### Pourquoi pas EditableMesh (la question posee)

EditableMesh existe et fait bien ce qu'on croit : bouger les sommets d'un mesh en direct. Mais une touffe fait
plusieurs centaines de sommets, une zone en contient des centaines, et il faudrait bouger tous ceux du rayon d'ecrasement
A CHAQUE IMAGE, en Lua, sur le processeur. Des dizaines de milliers d'appels par frame, quand on dispose de 16 ms pour
faire tourner tout le jeu.

En basculant la TOUFFE ENTIERE, on ecrit UN CFrame par touffe, et seule une vingtaine est pres du joueur a un instant
donne. Mille fois moins cher, et a l'ecran ca se lit pareil. Regle generale : avant d'aller chercher un outil qui
donne un controle fin, verifier que le controle fin est vraiment necessaire pour l'effet voulu.

Corollaire pour la tonte, quand elle viendra : elle n'aura pas besoin d'EditableMesh non plus. Passer du mesh long au
mesh court (ou ecraser la touffe en hauteur) est une modification unique et permanente, donc gratuite.

### Details

- La bascule se recompose a chaque image depuis le PIED et la rotation propre de la touffe, jamais depuis le CFrame
  precedent : sinon l'inclinaison s'accumulerait et les touffes finiraient couchees pour toujours (meme piege que
  l'offset de l'echelle recapture a chaque prise).
- La cible de repos n'est PAS zero mais une petite inclinaison tiree au sort : une herbe parfaitement droite se lit
  comme du faux, et un joueur qui passe laisserait derriere lui un couloir trop propre.
- Ecraser est brutal (CRUSH_SPEED 18), se relever est lent (RECOVER_SPEED 3.5). Deux boutons SEPARES : un reglage
  partage forcerait a compenser dans l'autre, et le compensateur serait toujours une estimation.
- L'angle se CLE sur sa cible sous SNAP_EPSILON. Un lerp exponentiel n'atteint jamais sa cible : sans ce clic, chaque
  touffe garderait un residu minuscule et on reecrirait son CFrame a vie, pour rien.
- Culling a deux etages : une zone dont aucun joueur n'approche est ecartee d'un bloc, et une touffe au repos ne se
  reecrit pas du tout. Une zone garde la main tant que des touffes se relevent, sinon elles se figeraient couchees des
  que le joueur s'eloigne.
- Le joueur le PLUS PROCHE gagne, on ne moyenne pas : deux joueurs de part et d'autre d'une touffe la redresseraient.
- Distance mesuree a l'HORIZONTALE : sauter ne doit pas relever l'herbe.
- Les touffes sont enfants de leur zone. Si le streaming retire la zone, elles partent avec, sans nettoyage a ecrire.
- CastShadow a faux sur les touffes : des centaines d'ombres de brins coutent cher et ne se voient pas.

### A faire dans Studio

Poser des parts nommees "ZoneGrass..." DANS `Workspace.Worlds.Maps` (la racine est reglable dans GrassZoneConfigs.ROOT).
Une part posee a la racine du Workspace ne sera PAS trouvee. Elles peuvent rester invisibles, sans collision : seules
leur taille, leur position et leur orientation comptent. Le client affiche au demarrage combien de zones et de touffes
il a posees.

## 0.0.204 — Les arbres et les buissons bougent

Nouveau FoliageService (serveur) + FoliageConfigs. Chaque modele de la map dont le nom est liste dans la config
recoit sa boucle d'animation. Aujourd'hui : Bush1 et Tree1. Poser dix "Bush1" dans la map les anime tous les dix,
sans rien taguer et sans rien brancher a la main -- le NOM du modele est la cle.

Les IDs vivent dans du CODE, pas dans des Instances Animation rangees en ReplicatedStorage. Raison : Rojo synchronise
le code dans TOUTES les places, les Instances non (elles sont en $ignoreUnknownInstances et se recopient a la main,
place par place). Le tuto recoit donc le meme decor anime sans qu'on y importe quoi que ce soit. Une nouvelle plante
= UNE ligne dans FoliageConfigs.ANIMATIONS.

Joue COTE SERVEUR : la boucle se replique a tous, y compris aux joueurs qui arrivent apres, et le serveur voit toute
la map quoi que fasse le streaming chez le client. A savoir pour plus tard : chaque plante animee est un Humanoid de
plus au serveur. Sur une dizaine c'est gratuit, a plusieurs centaines il faudra passer ces boucles cote client.

DESYNCHRONISATION (SPEED_VARIATION 0.15, RANDOM_START). Dix buissons qui jouent la meme boucle a la meme image
ondulent tous ensemble, et l'oeil lit ca comme du faux immediatement. Chaque plante demarre donc a un point au hasard
de sa boucle et a une vitesse legerement differente. Les deux knobs se coupent (0 / false) si le mouvement synchrone
est voulu.

Deux pieges evites en ecrivant, deja connus du journal :
- `AnimationTrack.Length` vaut 0 tant que l'asset n'est pas telecharge. Tirer le point de depart au hasard tout de
  suite aurait donne 0 pour tout le monde, donc un demarrage synchrone -- exactement ce qu'on cherchait a eviter. Le
  tirage attend la vraie longueur dans un thread a part, borne dans le temps.
- Le dossier se resout par RE-SCAN en boucle sous UN seul delai, pas par une chaine de quatre `WaitForChild` : avec
  un WaitForChild par segment, un chemin absent ferait attendre le timeout quatre fois avant de prevenir.

Racine de recherche volontairement SERREE (`Worlds.Maps.Assets.Foliages`) et pas `Worlds.Maps` : ce dernier contient
les milliers de carreaux de haie, et y brancher DescendantAdded ferait passer chacun d'eux par le test de nom pour
rien. Consequence a connaitre : une plante posee HORS de ce dossier ne s'animera pas.

### A faire dans Studio

Rien cote code. Il faut juste que les plantes vivent dans `Workspace.Worlds.Maps.Assets.Foliages`, gardent leur nom
exact (Bush1, Tree1) et contiennent leur Humanoid + Animator. Le serveur affiche au demarrage combien il en a animees.

## 0.0.203 — C'est PAPI qui parle, plus un inconnu

Le tuto faisait parler un personnage ("Finn") qui n'existe nulle part ailleurs dans le jeu, et qui racontait
l'histoire du grand-pere A LA PLACE du grand-pere. Un narrateur inconnu qui resume l'emotion, c'est exactement ce
qu'il ne faut pas : le joueur doit ENTENDRE Papi, pas un intermediaire.

Les 8 portraits de Finn sont remplaces par les 6 dessins de Papi (normal, happy, sad, angry, shocked, wink), et les
repliques du tuto sont reecrites A LA PREMIERE PERSONNE : Papi tend ses outils, dit que son dos l'empeche de
travailler, que ses clients sont partis, et donne son entreprise. Derniere ligne en clin d'oeil : "fais pas honte a
mon nom, petit !".

Vocabulaire volontairement enfantin (public Roblox) : pas de "retraite", pas de "parts d'entreprise". "Mon dos me
fait trop mal", "je te donne mon entreprise".

Le texte reste NEUTRE sur le decor : aucune mention de porte, de maison ou de camion. La cinematique d'arrivee
(camion -> toquer -> Papi ouvre) n'existe pas encore ; ecrire "j'ouvre ma porte" maintenant donnerait un dialogue
qui ment sur ce qui est a l'ecran. A reecrire quand la scene existera.

Table EMOTIONS toujours PLATE (un seul personnage). Elle devra passer en table par speaker quand les PNJ clients
arriveront -- pas avant : aujourd'hui elle n'aurait qu'une entree.

## 0.0.202 — La pose tient hors visee, haie invisible en jeu, reglages du tuto

Cinq retouches accumulees, poussees ensemble.

TAILLE. La pose UpDown ne retombe PLUS en Idle quand le curseur quitte la surface de la haie : tant que le moteur
tourne, on TIENT la derniere hauteur et le dernier cote reellement vises (lastPoseRatio / lastPoseOnTop). Avant, sortir
la souris d'un poil faisait replonger les bras en position neutre, puis remonter -- un a-coup permanent en bord de haie.
La COUPE, elle, reste gatee sur une vraie cible (aimActive) : cliquer dans le vide ne declenche toujours rien. Les deux
etats sont maintenant distincts, ils etaient confondus. Relacher le chantier (release) remet la pose a zero, sinon on
reprendrait la hauteur du chantier precedent.

HAIE. La boite taguee `hedge_` passe en `Transparency = 1` cote serveur a la construction : en Studio on la laisse
semi-transparente pour la voir en editant, en jeu elle disparait (le visuel vient des carreaux / feuilles). Ecrit cote
serveur donc repliquee a tous. On ne touche PAS a `CanQuery` : le Blockcast de detection doit continuer a la voir.

TUTO. Musique de fond ajoutee (MusicBuild3 clonee, bouclee, volume 0.15, resolue en `task.spawn` -- le Sound peut
arriver apres le boot). Bandeau de dialogue plus large et moins haut (680x180 -> 800x120). Duree mini du rideau de
chargement montee de 6.5 a 10.5 s.

## 0.0.201 — Un plancher de glisse PAR ALLURE, et la bille visait la mauvaise haie

**La compensation de 0.0.200 etait fausse, et elle ne pouvait pas etre juste.** Baisser CUT_SPEED (5 -> 3.5) pour
rattraper la hausse de STEP_GLIDE demandait de connaitre la cadence reelle des pas, qui vit dans l'ANIMATION et non
dans la config : le facteur a ete estime, donc rate, et la coupe restait trop rapide. Correction sans aucune
estimation : CUT_SPEED revient a 5, et le plancher du pas devient PROPRE A CHAQUE ALLURE. Nouveau STEP_GLIDE_CUT
(0.25, la valeur historique) s'applique gachette pressee, STEP_GLIDE (0.5) au replacement. La coupe retrouve donc
exactement son rythme d'avant, au reglage pres, et le replacement garde son gain.

Le fond du probleme : ce plancher MULTIPLIE la vitesse. Partage entre deux allures, il rend impossible d'en
accelerer une sans accelerer l'autre. Un knob par allure supprime le couplage au lieu de le compenser.

**La bille de visee se projetait sur la mauvaise haie.** `updateCursor` construisait son plan de repli a partir de
`lastHedge` (la derniere haie que le CURSEUR a survolee) alors que la normale, elle, vient de `workHedge` (celle que
le SERVEUR a accrochee). Des qu'il y a plus d'une haie dans le jardin les deux different, et croiser les dimensions
de l'une avec la normale de l'autre donne un plan qui n'existe nulle part : la bille se pose a cote, parfois de
plusieurs studs. Le joueur voit un curseur qui ne suit plus sa souris alors que la souris est lue correctement --
c'est la CIBLE qui etait fausse, pas la lecture. `updateCursor` recoit maintenant `workHedge` et projette dessus.

### Note — le cercle blanc n'est pas le curseur

Deux reperes distincts a l'ecran, faciles a confondre : la BILLE rose se pose la ou vise la souris, le CERCLE blanc
est le guide de coupe et suit la LAME. Le cercle ne sera donc jamais sous le curseur : il montre ce que l'outil va
couper, pas ce qu'on designe.

## 0.0.200 — Retour du chantier : la coupe retrouve sa lenteur, la visee son ressort

Suites directes de 0.0.199, deux reglages qui trainaient derriere les changements de la veille.

**CUT_SPEED 5 -> 3.5.** Monter STEP_GLIDE avait accelere les DEUX allures, alors qu'on ne voulait accelerer que le
replacement : tailler doit rester un geste de precision, c'est tout l'interet d'avoir un cout a la gachette. Le
multiplicateur moyen du pas passant d'environ 0.39 a 0.56 (rapport 0.69), 5 * 0.69 = 3.5 rend a la coupe sa vitesse
RESSENTIE d'avant. Effet de bord souhaitable : l'ecart replacement / coupe passe de 2.6x a 3.7x, donc relacher la
gachette se sent encore mieux qu'avant.

**UPDOWN_FOLLOW_SPEED 10 -> 6.5.** Reglage cale sur une camera qui n'existe plus. Le commit de la 1re personne
l'avait monte de 6.5 a 10 : l'oeil etant a la tete, le curseur tombe presque a la verticale sur la haie, la hauteur
visee est stable et le ressort peut etre sec. En vue iso le rayon arrive DE BIAIS, le meme pixel de souris couvre
bien plus de hauteur de haie, et un ressort raide AMPLIFIE ce bruit au lieu de l'absorber -- la visee parait sauter
toute seule, ce qui se lit comme un bug de ciblage alors que rien n'est casse. Retrouve par git : c'est le seul
reglage de visee touche par ce commit.

### Note — le personnage transparent n'est pas une regression

Question du joueur au meme moment. C'est WORK_FADE (WORK_FADE_BODY 0.85), le personnage fantome au travail, en
place depuis 0.1.0 : le corps s'efface pour laisser voir la haie qu'on taille, les mains restent nettes parce
qu'elles tiennent l'outil. Il ne se voyait plus parce que la 1re personne CACHAIT le personnage entierement en
local ; en revenant a l'iso, le fantome redevient visible. Rien a corriger, mais a retenir : un mode qui masque un
effet le fait passer pour neuf quand on quitte ce mode.

## 0.0.199 — Chantier : deplacement plus rapide, l'avant ne glisse plus, retour a la camera iso

Trois retours du joueur sur le travail au pied d'une haie, trois causes distinctes.

**Le replacement se trainait.** Le coupable n'etait pas WORK_SPEED (13, deja au-dessus de la marche normale) mais
le deplacement au pas : entre deux poussees, la vitesse est multipliee par STEP_GLIDE. A 0.25, avec une poussee qui
ne dure que 0.19 s, la vitesse moyenne reelle tombait autour de 5 studs/s, soit MOITIE MOINS que la marche normale
pendant que la config annoncait 13. STEP_GLIDE passe a 0.5. Lecon a retenir : quand une vitesse est modulee par un
multiplicateur cyclique, le chiffre affiche dans la config n'est pas celui que le joueur ressent.

**Pousser en AVANT deplacait le personnage sur le cote.** L'axe avant etait recycle en glissement vers la GAUCHE
(`math.min(moveVector.Z, 0)` ajoute au lateral), au motif que la touche ne servait a rien devant une haie. Ca
trompait le joueur : il pousse en avant, son perso part a gauche, et il ne peut plus relier ce qu'il appuie a ce
qu'il voit. Asymetrie aggravante : reculer, lui, ne partait PAS a droite (l'arriere est capte plus haut comme
sortie de chantier). Desormais seul le pas de cote deplace. L'avant ne fait rien, et c'est la verite du chantier.

**La camera etait figee.** CAMERA_FIRST_PERSON repasse a false. Dans ce mode la branche 1re personne de
HedgeController ne lit NI le pivot (yaw) NI le zoom : le clic droit, le glissement du doigt et la molette ne
faisaient rien a l'ecran, alors que tout le code d'orbite tournait quand meme dessous (yaw bougeait, le ressort de
rubber-band aussi). On taillait sous un angle impose sans pouvoir aller voir ce qu'on coupe. La vue iso 3/4 a deja
l'orbite, le zoom, le rubber-band de butee et le rapproche a l'acceleration. Le remettre a true demandera d'abord
de brancher yaw et cameraZoom sur le placement de l'oeil.

Fichiers : `HedgeConfigs.luau` (STEP_GLIDE, CAMERA_FIRST_PERSON), `HedgeController.luau` (calcul de `lateral`).

## 0.0.198 — Nav bar : forme des pilules, feuille verte, et OUVERTURE PAR GESTE (clic-glisse haut)

Retouches nav bar. Les deux pilules (LeftGroup / RightGroup) prennent des coins ASYMETRIQUES par cote (haut exterieur
tres rond, bas interieur demi-rond, les deux autres carres) et passent en BLANC. Egalisation des largeurs deja en place
(0.0.197) -> nav symetrique. La feuille centrale devient vert fonce (63, 99, 52), icone agrandie a 45 px.

Nouveau (idee du joueur) : la feuille ne s'ouvre PLUS au clic simple. Elle s'ETIRE vers le haut au survol (comme une
etiquette qu'on tire), et on OUVRE son interface par un GESTE -- clic MAINTENU + glissement vers le HAUT au-dela d'un
seuil (LEAF_DRAG_OPEN 55 px). Pendant le tir, la hauteur SUIT le curseur / doigt (retour direct) ; au franchissement du
seuil ca ouvre (hook onSelect "skilltree"), une fois par geste. Marche souris ET tactile (ancree en bas -> grandit vers
le haut sans bouger le layout ; le suivi du glissement passe par UserInputService en global). Knobs : LEAF_EXTEND_HOVER /
_MAX, LEAF_DRAG_OPEN. NB : l'interface de l'arbre n'existe pas encore -> le geste appelle le hook, rien ne s'affiche pour
l'instant. Ouverture au FRANCHISSEMENT du seuil (pas au relachement) ; a basculer si le ressenti demande l'inverse.

## 0.0.197 — Feuille de chargement = barre de progression + sons sur la nav bar

Deux touches UI.

Feuille du LoadingOverlay (ecran de changement de lieu) : le vert ne BALAIE plus en boucle, il REMPLIT la feuille du bas
vers le haut comme une barre de progression, et arrive EN HAUT (feuille pleine) PILE quand le chargement est fini (hide).
La montee est estimee (on ne connait pas la duree : elle grimpe vite puis rampe jusqu'a un plafond HOLD 0.9) puis se
COMPLETE d'un coup jusqu'au sommet a la fin reelle. Pilotee par une NumberValue tweenee qui redessine la ColorSequence du
gradient (frontiere vert/gris qui monte) ; le gradient etant enfant de la feuille, le remplissage suit l'oscillation.
Knobs : LEAF_PROGRESS_CLIMB / HOLD / FINISH, LEAF_FILL_SOFT ; sens via LEAF_GRADIENT_ROTATION (90, passer a 270 si ca
remplit a l'envers -- seul l'ecran tranche).

Nav bar : sons au CLIC et au SURVOL des onglets (et de la feuille centrale), reutilisant les memes assets UI que
ButtonSlime (SoundService.Sounds.UI.PressButtonSound / HoverButtonSound) via SoundUtils.play. La nav opte-out du slime
(LeafiaNoSlime) et avait donc perdu ces sons avec le mouvement : on rebranche juste le SON, pas le gonflement. Survol =
PC seulement (pas de hover au doigt). NB : ces sons doivent EXISTER dans SoundService (assets Studio) ; sinon SoundUtils
warn "Son introuvable" et reste muet.

## 0.0.196 — La boucle est fermee : tailler une haie PAIE (cheque de fin)

Le gain de coins est ENFIN branche en jeu. Finir une haie (100%, auto-completion incluse) verse un CHEQUE au joueur :
payout = HEDGE_BASE_PAYOUT + floor(carreaux de la haie * HEDGE_PER_CELL_PAYOUT) (~100 pour une haie moyenne, a regler a
la console admin). Branche dans HedgeCutService.cutWith au passage de ratio a 1, UNE fois par haie (garde
PAID_ATTRIBUTE pose sur la haie -> repasser la lame sur une haie deja finie ne re-paie pas). Tout le reste etait deja
pret : grantCoins persiste dans la company active (DataTemplate), et l'UI (CurrencyController) anime deja le compteur +
un "+X" vert flottant.

Aucun nouveau remote (les coins passent par attribut joueur). L'XP reste branchee PAR CARREAU (goutte-a-goutte de
progression) ; le cheque est un GAIN distinct a la FIN (le payday). Config : CurrencyConfigs.HEDGE_BASE_PAYOUT /
HEDGE_PER_CELL_PAYOUT. Garde : HedgeConfigs.PAID_ATTRIBUTE ("LeafiaPaid").

Limites assumees (le systeme de chantiers viendra encadrer tout ca) : TOUTE haie du monde paie (pas encore de haie
"assignee" par un client) ; en co-op c'est le joueur qui amene la haie a 100% qui touche le cheque ; sur la place tuto
l'economie est no-op (le cheque scripte du didacticiel sera un branchement a part). Persistance reelle entre sessions =
jeu publie (le DataStore est coupe en Studio).

## 0.0.195 — Boutons TURN / DROP du portage : diagonale + style (fini les ronds CAS colles)

Les boutons tactiles TURN et DROP (portage d'echelle, mobile) etaient deux ronds plats ContextActionService, auto-alignes
COTE A COTE contre le bouton de saut : moche et ca l'encombrait. Refaits en ScreenGui CUSTOM (LeafiaLadderCarry) : deux
ronds verts stylises (contour blanc), poses en DIAGONALE a gauche du bouton de saut, sans le chevaucher. On maitrise la
position (knobs DROP_BTN_POS / TURN_BTN_POS) et la taille (CARRY_BTN_SIZE). Gate tactile (rien sur PC), montres au
portage, caches sinon, ResetOnSpawn = false. Le clavier (F reposer / R tourner) reste gere par UserInputService cote PC ;
comme il n'y a plus de CAS pour Sink la touche, plus de double possible. Import ContextActionService retire (plus utilise).

## 0.0.194 — Prompt PRENDRE de l'echelle : detection RADIALE (fini l'angle mort)

Le prompt "[F] PRENDRE" n'apparaissait qu'une fois COLLE a l'echelle. La detection reposait sur DEUX box posees sur les
COTES (offset lateral 3), orientees sur la longueur de l'echelle : selon d'ou on arrivait (un bout de l'echelle, une
RootPart decalee), on tombait dans un ANGLE MORT -> pas de prompt meme au contact. Grossir les box ne supprimait pas le
trou. Passe en detection RADIALE : distance HORIZONTALE (X/Z) a la RootPart de l'echelle, sous DETECT_RADIUS (8 studs) ;
on rend la plus proche. Un seul rayon, aucun angle mort, independant de l'orientation du rig. Knob : DETECT_RADIUS dans
LadderMoveController. Les box box_detecte_For_Move restent (marquage au sol) mais ne pilotent plus la detection ;
ZONE_SIZE remis a l'origine.

Aussi : les offsets d'AFFICHAGE des prompts (E MONTER / F PRENDRE) remis a 5. Ils avaient ete montes a 9 par erreur --
"plus loin" avait ete compris comme "plus haut", alors que c'etait la DETECTION qu'il fallait etendre, pas la hauteur.

Reste : la detection MONTER (touche E, box_detecte_A/_B) utilise encore la meme logique de box, posee dans le rig
Studio -- meme angle mort possible. A passer en radial aussi si besoin (le montage s'appuie sur la zone pour poser le
joueur au pied, donc un peu plus de travail).

## 0.0.193 — Le rideau couvre AVANT la transition d'entree (Start plus propre)

Au clic START (ecran Load a company), le rideau de chargement secondaire s'affiche D'ABORD, puis TOUT le reste
(fermeture du menu, transition camera vers le joueur) se joue DERRIERE lui. Avant, le menu se cachait et la camera
bougeait a decouvert, PUIS le rideau arrivait : on voyait toute la mecanique, pas pro. Maintenant : presse Start ->
l'ecran se couvre -> on arrive. On attend que le rideau soit OPAQUE (LoadingOverlay.showTime, la duree de son fondu
d'entree, exposee pour ca) avant de bouger quoi que ce soit derriere.

Consequence : l'ancien "exit slide" facon Sims (LoadCompanyController.playExit + goToPlayer cote PlotSelect + les
refs cardListFrame / titleLabel / rightGroupRef + EXIT_TWEEN) devient inutile et est retire -- le curtain-first le
remplace, pas de code mort laisse derriere.

Polish du LoadingOverlay (ecran d'arrivee / changement de lieu) au passage :
- Les 4 boules qui rebondissaient sont retirees. Il ne reste que le fond gris + la feuille (logo) qui oscille.
- La feuille fait un POP slime a l'apparition : elle grossit de 0 a sa taille avec un rebond elastique (LEAF_POP),
  rejoue a chaque show().

Mode build : le pan au doigt (clic-glisse pour se deplacer dans l'espace) est plus rapide sur tablette / mobile
(CAM_PAN_TOUCH 0.0016 -> 0.003), plus confortable a manier. Le pan souris (PC) n'est pas touche.

## 0.0.192 — Mode suppression : rebond slime + son a chaque marquage

Quand une structure devient jaune (marquee "a supprimer"), elle fait un petit REBOND slime (saut + ecrasement, retour a
sa pose d'origine) et un SON "appear" (rbxassetid://138424352985426) joue -- un par instance, donc la selection multiple
fait une salve de pops. Nouveau helper reutilisable BuildFx.slimeBounce(inst) : marche pour Model (PivotTo + ScaleTo) et
BasePart (CFrame + Size), auto-protege (s'arrete si l'instance est detruite en plein rebond). SoundUtils.playId(id, volume,
host) ajoute pour jouer un son par ASSET ID (pas besoin d'un Sound pre-regle dans SoundService). Reglages : BOUNCE_HOP /
BOUNCE_SQUISH / BOUNCE_TIME (BuildFx), APPEAR_VOLUME (BuildDeleteController). Limites : l'ecrasement scale autour du pivot
(pas ancre au sol) ; retracer dans les 0.32 s laisse le rebond finir sur l'instance demarquee -- a affiner si ca gene.

## 0.0.191 — Mode suppression : demarquer en revenant sur ses pas (retrace)

Complete la previsu : pendant le balayage (clic maintenu), revenir en arriere DEMARQUE. On garde l'ORDRE du balayage
(markedOrder, le "stroke") ; quand le curseur repasse sur une structure marquee plus TOT dans le stroke, on restaure tout
ce qui a ete ajoute APRES elle (le trait se retracte jusqu'au curseur). Le joueur peut donc balayer trop loin, reculer
pour deselectionner, et relacher pile sur la bonne selection. markStructure devient markOne (empile) + restoreOne
(depile) + sweepTo (decide marquer / retracter selon table.find dans le stroke).

## 0.0.190 — Mode suppression : PREVISU avant de supprimer + grille coloree par mode

La suppression ne detruit plus instantanement (trop brutal, aucune marche arriere). Nouveau flux : clic MAINTENU + slide
-> chaque structure balayee est MARQUEE (l'asset passe en jaune neon semi-transparent, on retient son etat d'origine), et
la vraie suppression n'a lieu qu'au RELACHEMENT. Le joueur voit ce qu'il va effacer avant que ca parte, et peut s'ajuster.
Echappatoire : appuyer sur X (sortie du mode) pendant qu'on tient encore ANNULE la selection -> tout est restaure, rien
supprime (clearMarks(false) au setEnabled). Les murs marques nettoient toujours leurs poteaux orphelins au commit.

La grille change de couleur selon le mode, comme repere visuel : CYAN en construction (objet / mur), ROUGE en suppression
(GRID_COLOR_BUILD / GRID_COLOR_DELETE). BuildController garde la liste des Frames de cases pour les recolorer au setMode.

## 0.0.189 — Mode suppression : balayage (clic maintenu + slide)

Le mode SUPPRIMER gagne le balayage : clic MAINTENU + on glisse le curseur -> tout ce qui passe dessous s'efface, frame
par frame, tant qu'on tient (objets ET murs, poteaux d'angle orphelins nettoyes au passage). Le clic simple efface
toujours une structure. Etat `deleting` pose a l'appui / leve au relachement (relachement toujours traite, sinon le
balayage resterait coince). Suppression centralisee dans deleteTarget (nettoyage des coins + destroy). CLIENT-only.
Limites connues : un slide TRES rapide peut sauter un segment entre deux frames (raycast par frame) ; sur mobile le
glissement 1 doigt se battra avec le pan camera -- a regler quand l'UI mobile du build arrivera.

## 0.0.188 — Mode mur : plusieurs types de mur (hauteurs) + glissement de la poignee

Le mode mur gere maintenant PLUSIEURS meshes de mur au lieu d'un seul. On enumere au start tous les BaseParts sous
Assets.Contents.Build (les objets, eux, sont des Models avec Hitbox -> naturellement exclus), tries par nom. TEMP :
touches 1 / 2 / 3... pour choisir le type (le catalogue d'UI viendra dans Studio). Exemple pose par le joueur :
metal_wall_type_1 (haut 9), type_2 (12), type_3 (16). La HAUTEUR n'est plus une constante figee : c'est le Size.Y du
mesh choisi (wallHeight runtime). Tout suit -- segments, poteaux d'angle, etiquette de cout, ET la poignee fantome dont
le cylindre est rebati a la bonne hauteur quand on change de type (on voit la hauteur du mur avant de le poser). Fallback
box + valeurs du config si aucun mesh.

La poignee (LeafiaWallHandle) GLISSE maintenant vers le coin sous le curseur au lieu de sauter de coin en coin (lerp de
position ; la cible reste snappee sur la grille). Reglage HANDLE_SLIDE. Meme traitement pose au passage sur le fantome
d'OBJET (GHOST_SLIDE) pour un feeling coherent entre les deux modes.

## 0.0.187 — Fix : supprimer un mur enleve aussi ses poteaux d'angle orphelins

Supprimer un mur laissait ses poteaux d'angle (WallCorner) plantes tout seuls. Maintenant, effacer un mur enleve les
poteaux a ses bouts QUI NE SERVENT PLUS a aucun autre mur : deux murs qui se rejoignent partagent un poteau, donc on ne
l'enleve que s'il devient orphelin (l'autre mur le garde). Logique dans BuildWallController.cleanupCornersFor (elle seule
connait les noms Wall / WallCorner et la geometrie), appelee par le mode suppression avant de detruire la part. Un poteau
deja orphelin (laisse par une suppression d'avant ce fix) reste cliquable et s'efface a la main.

## 0.0.186 — Mode build : mode SUPPRIMER + spawn face au plot + fondu musique de sortie

Troisieme mode de build : SUPPRIMER (touche X pour entrer / sortir). On survole une structure posee (objet ou mur) ->
elle se surligne en ROUGE ; clic -> elle disparait. La cible = le descendant DIRECT du dossier Build sous le curseur : un
Model d'objet entier, ou une part Wall / WallCorner (les murs s'effacent segment par segment pour l'instant, faute d'etre
groupes en ligne). Nouveau BuildDeleteController, sur le meme moule que les autres (start / stop / setEnabled / init) ;
X memorise le mode d'avant et y revient en sortant. Les trois modes (objet / mur / suppression) sont maintenant geres par
un setMode unique : un seul controller actif, les deux autres en veille. CLIENT-only (la suppression est locale) ; autorite
serveur + save : avec le reste du build.

Presentation : en arrivant sur son plot (apres la selection), le joueur est maintenant tourne FACE a son plot (regard vers
le centre du PrimaryGround), au lieu de suivre l'orientation "au hasard" de la part RootSpawnPlayer. Bonus gratuit : la camera
de jeu se cale derriere lui (elle lit son regard), donc elle cadre le plot toute seule.

Confort : le fondu de SORTIE de la musique de build passe de 0.6 s a 2.5 s (lineaire) -> la musique s'eteint en douceur au
lieu d'etre coupee net (c'etait trop sec). Le fondu d'entree reste court (0.6 s).

## 0.0.185 — Mode build : grille en carres pleins + vague d'initialisation

La grille de build change de nature. Avant : une image de LIGNES fines tuilee. Probleme : de loin une ligne fait moins d'1
pixel a l'ecran et DISPARAIT (minification) -> la grille s'effacait au fond du plot. Maintenant : un CARRE PLEIN par case
(un Frame centre, avec un joint autour regle par GRID_CELL_GAP). Un carre plein n'a pas de resampling -> il reste visible
de loin, juste plus petit. Regle le fade de distance ET donne un meilleur look.

A l'ouverture du build, la grille ne pope plus d'un coup : une VAGUE d'initialisation (UNE seule fois) la revele. Un front
diagonal traverse le plot ; au passage sur chaque case, elle FLASHE (transparence file vers REVEAL_FLASH_T, elle glowe avec
le Brightness du SurfaceGui) et GROSSIT depuis son centre avec un rebond (easeOutBack), puis retombe a l'etat de repos
(GRID_TRANSPARENCY, taille pleine). Un petit bruit de Perlin casse a peine le front pour qu'il ne soit pas mecanique. Une
fois toutes les cases posees, la connexion se coupe : COUT SCRIPT NUL au repos (la grille ne bouge plus).

Tout est regle par des constantes en tete de la section (BuildController) : vitesse de la vague, duree du pop, intensite du
flash, bruit ; et cote config la transparence de repos, la couleur, le Brightness, le joint entre carres. Cote perf : un
Frame par case (~3000 sur un grand plot), crees d'un coup a l'entree (micro-hitch possible sur mobile, a surveiller), mais
STATIQUES ensuite. Si besoin plus tard : creation etalee ou cull par distance camera.

## 0.0.184 — Mode build : murs facon Sims (drag, diagonales, angles, cout) + volume musique

Le mode mur prend forme. On CLIC-DRAG sur la grille pour tirer un mur qui grandit le long des lignes : horizontal,
vertical OU diagonale (l'angle du geste se snappe au multiple de 45 deg). Le mur est fait de morceaux de mesh a leur
taille NATIVE (une "case" chacun), pas d'un mesh etire : la taule garde son echelle, sinon le motif s'ecarterait.
A chaque bout, un poteau cylindrique (couleur du mesh) masque l'angle moche des jointures, avec DEDUP : deux murs
qui se rejoignent partagent le coin, un seul poteau. Le fantome = une bille + un cylindre fin en Neon, groupes, qui
se penchent dans le sens du curseur (meme effet que le fantome d'objet). Son + poof de fumee a la pose (BuildFx
partage avec le placement d'objet).

Deux murs ne peuvent plus se CHEVAUCHER : pendant le drag, si le trace recouvre un mur deja pose (test par segment
sur le dossier Build), la poignee ET l'apercu passent ROUGE, et au clic une notification rouge sort sans rien poser
(anti-spam). Deux murs qui se touchent juste a un coin restent OK (boite de test un peu retrecie).

COUT visible : pendant qu'on tire le mur, une etiquette doree "-X" flotte au bout (le coin qui suit le curseur),
X = nombre de segments * WALL_PRICE (BuildConfigs). C'est le VISUEL du prix ; la vraie deduction des coins viendra
avec l'autorite serveur (spendCoins), sinon le client pourrait mentir sur son argent.

Volume des musiques du mode build baisse de 0.5 a 0.15 (0.5 explosait les oreilles).

CLIENT seulement pour l'instant (prediction, hauteur de mur fixe). Autorite serveur + sauvegarde + poignee de
hauteur reglable + chainage : ensuite. Nouveaux fichiers : BuildWallController, Utils/BuildFx.

## 0.0.183 — Mode build : brique 1 (entrer / sortir + quadrillage au sol)

Debut du systeme d'amenagement du plot (facon Sims), en increments. Premiere brique, testable : entrer / sortir du mode
build affiche un quadrillage au sol sur PrimaryGround (le sol du plot). La texture (creee par le joueur) est posee cote
CLIENT -> locale, seul le joueur qui construit la voit. Elle tuile a BuildConfigs.TILE_SIZE : la MEME maille que le futur
snap de placement, sinon la grille ne collerait pas aux cases ou les objets s'aimantent. Config PARTAGEE BuildConfigs
(client + serveur, source unique de la maille). Raccourci TEMP (touche B) pour entrer / sortir tant que l'UI (barre
d'outils + catalogue, faite dans Studio) n'existe pas ; le controller expose enter / exit / toggle pour qu'un bouton
d'UI les appelle plus tard. Repartition : UI dans Studio par le joueur, backend + placement par l'assistant. Nouveaux
fichiers : BuildConfigs, BuildController. A venir : fantome, poser, tourner, vendre, et sauvegarde (recettes serialisees
dans Company.Builds, deja prevues dans DataTemplate).

## 0.0.182 — Chargement secondaire : la feuille passe du gris au vert (anime)

La feuille du rideau de chargement secondaire (LoadingOverlay) prend vie : un degrade gris -> vert la balaye en boucle
(le vert monte puis revient), via l'Offset d'un UIGradient. ImageColor3 passe en BLANC pour que le degrade sorte propre
(sinon le gris multiplierait le vert et le salirait). Le gradient est enfant de la feuille : il tourne AVEC elle (sway),
le sens reste cale. Reglages en tete de fichier (vitesse, sens du balayage, couleurs) : le sens d'un Offset de gradient
ne se devine pas au raisonnement, il se confirme a l'ecran.

## 0.0.181 — Fix : se deplacer autour de la haie au joystick sur mobile

Sur mobile, dans l'etat de travail (focus sur la haie), impossible de se DEPLACER : la camera passe en Scriptable, et le
thumbstick tactile par defaut (PlayerModule custom) cesse alors de remonter un move vector -> GetMoveVector rend 0 (donc
ni glisser ni sortir). On pose NOTRE propre joystick tactile, actif seulement pendant le travail : dynamique (apparait
sous le doigt en bas a gauche), glisser sur le cote = pas de cote le long de la haie, tirer vers le bas = sortir. Son
toucher est gameProcessed (bouton Active) -> la visee l'ignore : un doigt bouge, l'autre vise / taille. Independant du
PlayerModule ET de la camera Scriptable. La marche normale (camera Custom) n'est pas touchee.

## 0.0.180 — Fix : sortir de la haie au joystick sur mobile

Sur mobile on ne pouvait pas quitter l'etat de travail sur la haie en reculant le joystick : le seuil de sortie
`EXIT_MIN_INPUT` valait 0.7, atteint facilement par la touche S (1.0 pile) mais PAS par un stick analogique tire en
arriere (valeur partielle). Baisse a 0.55 : un recul modere du joystick sort maintenant. Reste au-dessus du max de la
correction d'aimant (0.45) pour ne pas confondre une correction avec une intention de sortie (le serveur lit le meme
seuil, HedgeService). Aucun changement sur PC (S = 1.0 > 0.55).

## 0.0.179 — Fix : tous les plots visibles a la selection (streaming, surtout mobile)

Sur mobile (streaming plus serre), l'ecran de selection ne montrait que 2 plots au lieu de tous : avec StreamingEnabled,
un client ne recoit que les plots proches de lui, et les plots eloignes ne se repliquaient jamais (donc introuvables par
l'enumeration). PlotService force maintenant chaque plot en `ModelStreamingMode = Persistent` a l'init (cote serveur) :
ils sont TOUJOURS repliques a tous, quelle que soit la position. Necessite que les plots soient des MODELS (sinon un warn
le dit) ; si ce sont des Folders, les convertir en Models ou poser Persistent en Studio.

## 0.0.178 — Dialogue du tuto : apparait apres chargement + 3s, style BLANC, plus petit

- TIMING : le dialogue d'intro attend maintenant que le jeu soit CHARGE (`game.Loaded`) ET le joueur SPAWN, puis 3
  secondes, avant de s'afficher (au lieu de 1.5s apres le spawn).
- STYLE : le bandeau passe en BLANC facon Sims (fond clair 248/250/248, texte fonce, bord gris clair discret au lieu du
  fond sombre / texte clair). Le chip du nom reste jaune (accent). Reduit : REF_WIDTH 820->680, HEIGHT 220->180,
  portrait 200x250->165x210, texte 25->22. Tout reglable en haut de Dialogue.luau. (Style approche a l'oeil facon
  "DescriptionHolder" du menu ; a affiner avec les vraies couleurs de ce panneau Studio si besoin.)

## 0.0.177 — Menu : boutons de droite beaucoup plus petits sur MOBILE

Sur mobile, les 3 boutons (CONTINUE / EDIT / CHANGE PLOT) + leurs libelles etaient en pixels FIXES (410x104) -> ils
prenaient tout l'ecran. Les tailles du groupe sont maintenant CONDITIONNELLES au tactile (`IS_TOUCH`) : bien plus
petites sur mobile (colonne 190px, boutons 54px de haut, libelles reduits), grosses sur PC (410x104, inchange). Le groupe
reste colle en bas a droite. Les boutons restent tappables (54px > ~44px mini). Reglable : `BTN_COL_W`, `BTN_HEIGHT`,
`LABELS_W`, `LABEL_MODE_H` (chacun a sa branche mobile / PC). Detection = `TouchEnabled` (vraie aussi dans l'emulateur
d'appareil de Studio, donc testable la).

## 0.0.176 — Fix : DeleteDialog borne sur grand ecran

Le modal "hold to delete" (suppression d'une save) etait en scale pur -> son panneau s'etirait enorme sur ultrawide
(~1445px de large sur 3440). Ajout d'un UISizeConstraint (MaxSize 720x620) : il reste centre et net quelle que soit la
largeur d'ecran. Meme correctif que le NameDialog.

## 0.0.175 — Menu : diamant qui pivote + hover des cartes plus discret

- Le DIAMANT du compteur (CurrencyImageIcon) pivote doucement gauche-droite en boucle (pendule Sine, +/-10 deg, 1.8s).
  Reglable : `DIAMOND_ROT` (amplitude), `DIAMOND_ROT_TWEEN` (vitesse).
- Au SURVOL du compteur (ClickArea), le diamant fait la MEME anim que le badge des cartes (un tour complet + resize slime
  prolonge). Le pendule est coupe le temps du tour puis relance ; un garde-fou empeche d'enchainer les tours.
- Le HOVER slime des 3 cartes de save est plus discret : gonflement `CARD_HOVER = 0.02` au lieu du defaut 0.05 (les
  cartes sont grosses, +5% faisait trop). On bind la carte explicitement avant l'auto-bind global (bind idempotent), donc
  seul le hover des cartes change, les autres boutons gardent le defaut.

## 0.0.174 — Fix : la corbeille de save ne flotte plus seule a l'ouverture du menu

A la 1re ouverture de "Load a company", `selectSlot` sortait la corbeille (bouton delete) AVANT que les cartes aient fini
leur slide d'entree -> on la voyait seule, hors carte, un court instant. Maintenant un flag `suppressTrashSlide` la garde
rentree pendant l'anim d'entree ; elle sort seulement une fois toutes les cartes arrivees (delai = stagger + duree du
slide), sur la carte selectionnee. Pendant l'entree, cliquer une carte ne sort pas non plus la corbeille prematurement.

## 0.0.173 — Boite de dialogue : son de frappe ("tap tap tap")

Le texte qui s'ecrit lettre par lettre joue maintenant un petit SON DE FRAPPE toutes les `TYPE_SOUND_EVERY` lettres (2
par defaut), avec un pitch legerement varie (`math.random`) pour ne pas sonner robotique. Le son est un Sound pose dans
`SoundService.Sounds.UI.DialogueType` (a deposer en Studio, comme les autres sons) ; s'il est ABSENT on ne joue rien et
on ne spamme pas de warn (existence verifiee UNE fois). Regler `TYPE_SOUND_EVERY` (moins/plus de taps) en haut de
Dialogue.luau. Le tap ne joue que pendant l'ecriture : sauter la ligne (tap sur le bandeau) coupe le son sans rafale.

## 0.0.172 — Menu : NameDialog PC, chat coupe, top bar, libelles a gauche des boutons

Lot de finitions sur les ecrans d'avant-jeu (surtout grand ecran / PC).

- NAMEDIALOG (nommer une company) : sur PC on CACHE le clavier a l'ecran (custom), la box devient editable (vrai clavier,
  focus auto a l'ouverture, Entree = valider), et le panneau est CENTRE (0.5, 0.5). Sur tactile : inchange (clavier custom,
  panneau en haut). Le CONFIRM lit la box sur PC, le buffer du clavier sur tactile. Panneau reduit + borne (UISizeConstraint)
  pour ne plus etre enorme sur ultrawide. Detection par `TouchEnabled` (capacite stable, cf journal).
- CHAT Roblox coupe pendant chargement + menu (comme le playerlist), rallume a l'entree en jeu (PlotSelectController).
- BARRE DU HAUT (STEP x OF 2 + compteur diamant / +SHOP) : plus petite et remontee en HAUT A DROITE (le playerlist etant
  coupe, l'espace est libre).
- LIBELLES "CONTINUE IN SLOT x / nom" : remis a GAUCHE des boutons (en gros), via un GROUPE HORIZONTAL [libelles][colonne
  de boutons] colle en bas a droite -> ils restent adjacents quel que soit l'ecran. Boutons EDIT / CHANGE PLOT / CONTINUE
  un peu plus gros. Tailles reglables en haut du fichier (`BTN_COL_W`, `BTN_HEIGHT`, `LABELS_W`, `GROUP_GAP`).

## 0.0.171 — Menu "Load a company" : adaptable sur grand ecran (fini l'etirement ultrawide)

Sur grand ecran (ex 3440x1440) tout le menu etait en scale -> cartes ~1070px de large, boutons CHANGE PLOT / EDIT ~890px,
panneau CONTINUE ~2200px (libelles etales, texte "CONTINUE" coupe). La MISE EN PAGE est gardee (cartes a GAUCHE, boutons
a DROITE) mais on borne les tailles :

- GAUCHE (cartes + titre) : UISizeConstraint plafonne la largeur (`CARD_LIST_MAX_W`, `TITLE_MAX_W`), colle a gauche.
- DROITE (les 3 boutons) : refonte en COLONNE VERTICALE unique (UIListLayout) au lieu de 3 positions hardcodees. Les
  libelles (CONTINUE IN SLOT x / nom) + EDIT + CHANGE PLOT + CONTINUE sont empiles, MEME largeur, alignes a droite,
  espaces regulierement (`BTN_HEIGHT`, `BTN_GAP`), la colonne bornee en largeur (`BTN_COL_WIDTH` / `_MIN_W` / `_MAX_W`).
  Plus de bouton geant ni de texte coupe ; la colonne glisse en BLOC a l'exit. Tout reglable en haut du fichier.

En dessous de ces tailles, tout scale normalement. (Une 1re tentative en safe-area 16:9 centree groupait tout au centre
avec des marges laterales -> abandonnee : le joueur veut les elements colles aux bords, juste plus petits.) Note : ne
touche que l'ecran "Load a company" (code) ; l'ecran de selection de plot (Studio) reste a ajuster si besoin.

## 0.0.170 — Polish menu / chargement + badge qui tourne au clic

Lot de finitions sur les ecrans d'avant-jeu.

- BADGE DES CARTES DE SAVE : cliquer une des 3 cartes fait faire au badge (hexagone + niveau) un TOUR COMPLET (revient a
  l'endroit) + un pop de taille elastique. Purement visuel, reglable (BADGE_CLICK_SPIN / _POP / _POP_FROM). Le badge est
  desormais une reference (badgeFrame + un UIScale) au lieu d'etre inline.
- PLAYERLIST coupe pendant tout le MENU, pas juste le chargement : l'ecran de chargement ne rallume plus le playerlist en
  fin de chargement dans la place principale (le menu de selection suit) ; c'est PlotSelectController (entree en jeu) qui
  le rallume, une fois le rideau leve pour ne pas le faire flasher. En place secondaire, il revient normalement.
- StatusPill de l'ecran de chargement : fond transparent (on ne garde que le texte de statut).
- FontGradient (voile de fond du menu) : UIAspectRatioConstraint RETIRE (il deformait le voile sur ultrawide).

## 0.0.169 — Emplacements d'outils clavier : 1 = cisaille, 2 = taille-haie

La touche 1 basculait le seul outil par defaut (ToggleTool). Maintenant 1 et 2 sont de vrais EMPLACEMENTS : 1 equipe la
cisaille (Shear, outil de depart), 2 equipe le taille-haie (HedgeTrimmer). Rappuyer sur la touche de l'outil deja en
main le RANGE (toggle). Nouveau remote `SelectTool` (le client envoie le NOM de l'outil, le serveur valide et
`ToolService.selectTool` equipe / range ; equip range l'outil courant avant, donc changer d'outil est propre). Le
ToggleTool reste pour l'auto-equip / le rangement de l'echelle. ATTENTION (a faire) : aucune POSSESSION d'outil n'existe
encore -> n'importe qui peut sortir le taille-haie avec 2 ; quand il deviendra un upgrade PAYANT, gater selectTool sur la
possession avant d'equiper. Ok en dev, PAS en live.

## 0.0.168 — Auto-completion de la haie a 95%

Les derniers % d'une haie (le dessus, les recoins) sont chiants a aller chercher : le joueur impatient les abandonne
alors qu'il a fait le gros du travail. Des qu'une haie franchit `AUTO_COMPLETE_THRESHOLD` (0.95, dans HedgeConfigs, a
regler), le reste se finit TOUT SEUL : `HedgeCellService.finishRemaining` met les carreaux restants au ras (feuille des
aretes retiree comme en coupe normale), et ces carreaux comptent comme tailles a la main -> le joueur touche l'XP, le
combo et les debris pour EUX AUSSI (il a fait le gros, il recoit tout). Equilibre patient / impatient. L'echelle reste
necessaire : sur une haie HAUTE, le dessus fait plus de 5%, donc atteindre 95% exige deja d'y monter -> l'auto-completion
ne mange que la derniere frange, elle ne trivialise pas la grimpe. Pour l'instant c'est un snap instantane (les feuilles
restantes passent au ras d'un coup) ; un effet de "balayage" plus flatteur pourra venir plus tard.

## 0.0.167 — START : une nouvelle save part au didacticiel (teleport tuto)

Le bouton START ne posait le joueur que sur son plot dans la MEME place (il ne teleportait jamais). Maintenant le
SERVEUR decide via un flag `TutorialDone` porte par chaque company : save neuve (tuto pas fini) -> `StartGame` (nouveau
RemoteFunction Company) teleporte vers la place Tutorial et renvoie "teleport" ; save qui a fini le tuto -> "game", le
client entre dans le jeu comme avant (transition camera). En STUDIO le teleport echoue toujours (limite Roblox : pcall
cote TeleportService) -> on retombe sur "game", donc le hub reste testable en Studio. `CompanyService.markTutorialDone`
pose le flag (a brancher a la fin du tuto). Commande admin `tutodone` ajoutee pour marquer le tuto fini a la main et
tester le chemin du joueur qui revient. Rappel : le teleport ne se teste QUE dans l'experience publiee, pas en Studio.

## 0.0.166 — Boite de dialogue avec portrait + emotions (narration du tuto)

Premiere brique de la mise en scene du tuto. `Modules/UI/Core/Dialogue.luau` : un bandeau en bas d'ecran, le PORTRAIT
dessine du personnage a gauche (il "sort" de la boite, sa tete depasse) et sa replique ecrite lettre par lettre a droite,
un chip jaune pour son nom, une fleche qui pulse quand la ligne est finie. Chaque replique choisit une EMOTION par NOM
(hello / sad / happy / angry / shocked / intrigued / why / embarrassed) : le dessin swappe avec un petit pop, donc le
perso "reagit". Le dessin est affiche en Fit (jamais deforme, quel que soit son ratio). Primitive REUTILISABLE (narration
maintenant, PNJ plus tard), construite 100% en code comme InteractionPrompt / Toast (rien a preparer dans Studio). API :
`Dialogue.play(lignes, onDone)`, `Dialogue.hide()`, `Dialogue.isOpen()` ; une ligne = `{ speaker, text, emotion }`. On
avance en TAPANT le bandeau (souris ET tactile) : 1er tap = finir la ligne d'un coup, tap suivant = replique d'apres, et a
la fin ca ferme + appelle onDone. Singleton (un dialogue a la fois). Pose sur la place Tutorial un declencheur de TEST
temporaire (joue la narration d'intro une fois au spawn), a retirer quand le tuto la lancera pour de vrai (mission /
TutorialService). Nom du locuteur + textes d'intro = PLACEHOLDER a remplacer.

## 0.0.165 — Echelle : prompt E "MONTER", prise sur F, grimpe au joystick (mobile)

Trois patchs sur l'echelle, dans l'esprit de la boite aux lettres (un prompt clair et informatif).

- MONTER (LadderController) : entrer dans une zone de grimpe (box_detecte_A / _B) ne colle plus le joueur a l'echelle
  automatiquement. Ca affiche un prompt "[E] MONTER" avec le titre "LADDER" au-dessus (comme "MAILBOX"). On monte sur E
  au clavier, ou en TAPANT le prompt sur mobile (InteractionPrompt cree le bouton tactile). Sortie de la zone = prompt
  cache.
- PRENDRE (LadderMoveController) : la prise passe de E a F (l'ancienne touche entrait en collision avec la nouvelle
  montee sur E) et gagne le meme titre "LADDER". Le bouton tactile de prise suit la touche F.
- GRIMPE AU JOYSTICK (mobile) : monter / descendre lisait W/S EN DUR -> increachable au joystick. Ca lit maintenant
  l'input de DEPLACEMENT (avant = monte, arriere = descend) via le ControlModule, avec secours clavier W/S sur PC. Meme
  correctif que la marche autour de la haie. Limite connue : dans la place Tutorial, le PlayerModule custom rend un
  input vide -> sur VRAI mobile la grimpe y reste bloquee tant que ce module n'est pas repare (le secours clavier ne
  depanne que PC / emulateur).

## 0.0.164 — Ecran de chargement gris + boules pour les changements de lieu

Les teleports (tuto, chantiers) ne montrent plus le ciel Roblox vide ni le gros ecran herbe/badge : transition ET
arrivee en rideau GRIS FONCE + la feuille + boules. L'ecran de TRANSITION (TeleportController, pendant le voyage) est
FIGE (contrainte Roblox : aucun script ne tourne dedans) -> feuille + 4 boules statiques. L'ecran d'ARRIVEE
(ReplicatedFirst) detecte "on vient d'un teleport" via les donnees de teleport et affiche le rideau gris + 4 boules qui
REBONDISSENT (anime), court (~1.4s). Le gros ecran herbe/badge reste reserve au 1er LANCEMENT de Leafia (join direct,
sans donnees de teleport). TeleportService marque desormais tout teleport (`leafiaTeleport = true`) pour la detection.

## 0.0.163 — Multi-place : gating par PlaceId + place Tutorial (setup)

Le code (src) est synce dans CHAQUE lieu de l'experience (meme projet Rojo) ; c'est `game.PlaceId` qui decide du
comportement. Nouveau `PlacesConfig` (MAIN = Leafia, TUTORIAL). Les deux bootstraps (serveur + client) gatent par
PlaceId : dans la place Tutorial, seul le sous-ensemble TAILLE (+ console admin) s'initialise -- pas de save / plot /
mailbox / economie persistante (dont les ScreenGui n'existent pas la-bas). La sequence de la place principale (Leafia)
est INCHANGEE (la branche tuto `return` avant elle, et ne se declenche que si PlaceId == TUTORIAL). Commandes admin de
test : `tuto` (vers le didacticiel) et `hub` (retour Leafia). Prochaine etape : la map du tuto (Studio) + la 1re haie
guidee + brancher CreateCompany -> teleport tuto.

## 0.0.162 — Stats live synchronisees sur la company active (source de verite)

La company ACTIVE devient la SOURCE DE VERITE de l'economie du joueur. A l'entree dans une company (create / select), ses
stats sont chargees dans l'economie live (CompanyService.activate -> CurrencyService.setWallet + ExperienceService.setState).
A chaque gain, l'economie REECRIT dans la company active (writeToCompany) : ca persiste et alimente la carte de save.
Nouveaux champs company : Xp (progression fine dans le niveau, preservee entre sessions) + HedgesTrimmed (carreaux amenes
au ras -> chip HEDGES). Concretement : tailler fait monter le NIVEAU et les CARREAUX de la company active, qui persistent
et s'affichent sur la carte, et se rechargent au CONTINUE. Coins / Reputation sont persistes de la meme facon mais restent
a 0 tant que le systeme de chantiers (le cheque) ne branche pas leur gain. Les deux services d'economie ne sont donc plus
"runtime only" : ils sont la vue live de la company active (dependent de DataService, pas de CompanyService -> aucun cycle).

## 0.0.161 — Suppression d'une save : poubelle par carte + confirmation "hold to delete"

Chaque carte REMPLIE a une icone poubelle cachee DERRIERE elle (ImageButton, ZIndex 0, au centre). Quand la carte est
selectionnee, la poubelle glisse sur le cote droit et devient cliquable. Clic -> un modal de confirmation : "DELETE SAVE?",
le nom de la company, et un bouton MAINTENIR dont un remplissage rouge grandit tant qu'on appuie. Arrive au bout (~1 s) ->
DeleteCompany (serveur : la case repasse a vide et persiste) -> la carte se reconstruit EN PLACE en slot vide, sans reload.
Relacher avant la fin annule. Bouton KEEP IT pour renoncer. Refactor au passage : la construction d'une carte (+ son tag
NEW / ACTIVE + sa poubelle) est extraite en spawnCard, reutilisee pour reconstruire une carte apres suppression.

## 0.0.160 — NameDialog : boutons CANCEL / CREATE stylises + touches en gras

Les deux rectangles plats CANCEL / CREATE du modal de nommage deviennent des clones du TemplateButton (le meme bouton
stylise que START / CHANGE PLOT) : CREATE garde le vert du template, CANCEL est recolore en ROUGE (degrade, texte blanc,
contour rouge fonce). Les touches du clavier custom passent en gras (GothamSSm Bold) pour mieux se lire. Positions et
tailles des boutons / TextBox / panneau reglees a l'oeil. Plus ergonomique, plus coherent.

## 0.0.159 — Echelle jouable au tactile : boutons DROP / TURN sur mobile

Sur mobile, deposer (E) et tourner (R) l'echelle etaient impossibles : ces deux actions n'existaient qu'au clavier (la
PRISE marchait deja, via le tap du prompt d'interaction). Ajout de deux boutons tactiles (ContextActionService,
createTouchButton) crees UNIQUEMENT pendant le portage : DROP (repose l'echelle) et TURN (la tourne 180). Sur PC rien
ne change : ces boutons ne s'affichent que sur ecran tactile, E / R restent geres au clavier. Les 3 actions passent
maintenant par des declencheurs centraux anti-spam, tapes indifferemment par le clavier ou le tactile.

## 0.0.158 — Bouton EDIT : renommer une company (violet / rose, sur slot rempli)

Un bouton EDIT (degrade violet clair -> rose) apparait au-dessus de CHANGE PLOT, mais SEULEMENT quand un slot rempli est
selectionne (cache sur un slot vide, pas de raccourci clavier). Clic -> le modal de nommage s'ouvre PRE-REMPLI avec le
nom actuel -> le nouveau nom passe le filtre puis RenameCompany (serveur, persiste) -> la carte ET le libelle du bas se
mettent a jour EN PLACE, sans reload. Premiere MAJ de carte en direct (le create, lui, se voit encore au reload).

A venir : bouton DELETE + dialogue de confirmation ("hold to delete").

## 0.0.157 — Save system : companies persistees (fondation serveur + client branche)

Les 3 slots de "Load a company" ne sont plus du mock : le client lit les VRAIES saves du serveur (remote ListCompanies)
a l'ouverture. CREATE cree la company cote serveur (CreateCompany : persiste nom + stats dans le profil ProfileStore et
refiltre le nom) ; CONTINUE la selectionne (SelectCompany : ActiveSlot + LastPlayed). Nouveau CompanyService (autorite
serveur : list / create / rename / delete / select) + `Companies` dans le template (3 cases, false = vide, tableau PLEIN
pour ne pas casser la serialisation) + `ActiveSlot`. Remotes Company/... . Le nom cree SURVIT au reload (API access actif).

A venir : reconstruction des cartes en direct (sans reload), boutons EDIT (renommer) + DELETE (+ dialogue de
confirmation facon "hold to delete"), et sync des stats live (level / cash) vers la company active.

## 0.0.156 — Nommer sa company : modal + clavier custom en jeu + filtre serveur

Creer une nouvelle save (CREATE sur un slot vide) ouvre un modal "NAME YOUR COMPANY" AVANT le loading. Le clavier NATIF
est coupe (champ en lecture seule) au profit d'un clavier CUSTOM en jeu (lettres QWERTY + espace / effacer / OK), saisie
affichee en Title Case. L'ecran de save disparait derriere pour que le modal soit net.

Filtrage du nom en DEUX temps : (1) pre-check CLIENT instantane (petite liste noire) -> secousse ROUGE immediate du champ
sur les cas evidents ; (2) vrai filtre SERVEUR via TextService:FilterStringAsync (Roblox) -> attrape toutes les langues,
le leetspeak (NIC7AMAIRE), les variantes et les infos perso, SANS liste a maintenir. Un nom refuse secoue en rouge et ne
valide pas. Fail-safe : filtre indisponible -> REFUS en jeu publie, ACCEPTE en Studio (le filtre exige "Enable Studio
Access to API Services"). Nouveau NameFilterService (serveur) + remote Name/FilterName. Le nom est capture mais PAS encore
persiste (pas de save serveur) -> a brancher quand la save existera.

## 0.0.155 — Rideau de chargement : version FIGEE (logo gris + contour tournant, fermeture en 2 temps, destruction)

Etat final du rideau (apres iterations). Fond gris fonce (31,31,31). Logo = 2 images carrees empilees : Icon1
(remplissage gris) + Outline (contour blanc) qui porte un UIGradient de transparence TOURNANT vite (le fondu du
chargement). Loader = 4 boules qui rebondissent (decalees). FERMETURE dans l'ordre : d'abord le CONTENU devient
transparent (ImageTransparency des 2 images + BackgroundTransparency des 4 boules), PUIS le fond (Curtain, via
GroupTransparency), puis DESTRUCTION de LeafiaLoadingOverlay (+ arret des tweens). Aucun gradient tween pour fermer.

Remplace les essais 0.0.151-154 (fond bleu, wipe directionnel par gradient) : le wipe avait une direction impossible a
verifier sans lancer le jeu et brouillait l'ordre. On fond les vraies proprietes de transparence, pas un gradient.

## 0.0.154 — Rideau de chargement : loader 4 boules rebondissantes + fermeture en wipe

Le loader n'est plus un cercle de points qui tourne mais 4 BOULES alignees qui sautent et retombent a leur base, en
decale (l'onde), facon balles rebondissantes (Quad Out + reverses = un vrai rebond de gravite). Descendu plus bas sous
le logo.

A la FERMETURE : au lieu d'un fondu uniforme, un UIGradient balaie la transparence du rideau (wipe smooth) pour reveler
le jeu en douceur. Filet de securite : Enabled = false a la fin garantit que le jeu s'affiche meme si l'effet ne rend
pas comme prevu.

## 0.0.153 — Rideau de chargement : fondu d'entree + logo monochrome a fondu tournant

Le rideau APPARAIT maintenant en fondu (0.35 s) au lieu d'une coupe seche. Le logo passe en MONOCHROME (une seule
couleur, blanc par defaut, reglable) : les 4 calques sont tous tintes pareil, dans un CanvasGroup, pour qu'UN seul
UIGradient blanc qui TOURNE a l'infini balaie tout le logo d'un coup (le meme fondu tournant que l'ecran de chargement).

## 0.0.152 — Rideau de chargement : exit qui glisse, logo du jeu, fond bleu fonce

Raffinement du rideau (0.0.151). Au clic CREATE, les interfaces de selection GLISSENT d'abord hors ecran (cartes +
titre a gauche, boutons a droite, top bar en haut, ~0.55 s, acceleration), PUIS le rideau les couvre. Ca donne un exit
propre au lieu d'une coupe seche.

Le rideau lui-meme : fond BLEU TRES FONCE, et a la place du texte "LEAFIA", le vrai LOGO du jeu (le meme que l'ecran de
chargement, 4 calques d'images empiles) au centre, spinner en dessous. Duree portee a ~6.5 s (LOADING_MIN) pour poser un
vrai temps de chargement facon Sims (le plot est deja pret derriere, c'est un temps ressenti volontaire).

## 0.0.151 — Rideau de chargement a l'entree du jeu (clic CREATE)

Quand on valide sa boite (bouton CREATE) et qu'on entre dans le jeu, un rideau de chargement SIMPLE (style Sims) couvre
la transition : fond plein, logo blanc au centre, un spinner qui tourne a l'infini. Fini le glissement de camera visible
(orbite -> perso) : le joueur voit "chargement" puis un fondu sur le jeu deja en place derriere.

Nouveau module reutilisable LoadingOverlay (Modules/UI/Core) : show() / hide(). Le spinner est fait EN CODE (un cercle
de points a trainee de comete, aucun asset requis), le rideau est un CanvasGroup (un seul GroupTransparency fond tout
d'un coup). Reste affiche au moins 1.3 s (LOADING_MIN, cale sur la duree du glissement camera) pour ne pas flasher si la
transition est instantanee.

Le logo par defaut = le nom "LEAFIA" en texte blanc. Poser un vrai logo image = renseigner LOGO_IMAGE dans le module.

## 0.0.150 — Juice : diamant "SHOP" clignotant (plus de "0") + pump des tags

Le compteur de diamants a 0 n'affiche plus "0" (un solde mort ne donne envie de rien) mais un appel a l'action "SHOP"
qui PULSE en couleur (bleu diamant <-> violet premium), en boucle. Le compteur est deja cliquable (ClickArea) : le but
est de donner envie d'aller voir la boutique. Mot reglable (DIAMOND_CTA_TEXT) ; quand un vrai solde > 0 existera, on
affichera le nombre a la place.

Les tags NEW / ACTIVE des cartes "pompent" de temps en temps : un coup de zoom rapide qui rebondit (slime), a
intervalle un peu aleatoire (1.4 a 3.2 s) pour attirer l'oeil sans fatiguer. Ne tourne que quand l'ecran est affiche
(garde-fou root.Visible, comme l'effet slash).

## 0.0.149 — Console admin (F2) : commandes serveur avec predicteur

Une console admin codee, ouverte avec F2 (admin auto en Studio, ou UserId dans AdminCommandConfigs.ADMIN_USER_IDS en
jeu publie). Une TextBox, un bouton Execute, et un PREDICTEUR qui filtre les commandes au fur et a mesure qu'on tape
(clic sur une suggestion = remplit la ligne). Le resultat s'affiche dans la console.

Autorite SERVEUR : le client envoie juste la ligne tapee (RemoteFunction Admin/AdminCommand), le serveur re-verifie
l'admin, parse et execute. Le client n'ordonne rien. Commandes de depart : help, coins <montant> [joueur], reputation
<montant> [joueur], xp <carreaux> [joueur], level <niveau> [joueur], resetdata [joueur] (soi-meme si aucun nom).
Nouvelles fonctions serveur : CurrencyService.resetPlayer, ExperienceService.setLevel / resetPlayer,
DataService.resetData (vide le profil puis le Reconcile au template).

Pas de commande diamants : il n'existe pas encore de monnaie premium cote serveur (le compteur affiche un mock). A
ajouter quand le systeme diamant existera.

## 0.0.148 — Save : tous les slots vides par defaut

Un nouveau joueur a 0 save : les 3 slots de l'ecran "Load a company" sont donc tous VIDES au depart (avant, des data
mock remplissaient deux slots). Le premier slot est selectionne d'office, bouton CREATE. Les vraies data viendront du
save serveur.

## 0.0.147 — Ecran de chargement : plus de barre de %, un texte de generation qui defile

La barre de progression en pourcentage est RETIREE. Une barre qui rampe fait COMPTER le temps au joueur ("putain c'est
long"). A la place, juste un texte qui defile (Generation des terrains, Creation des massifs, Plantation des haies,
Preparation des outils, Ouverture des chantiers) puis "C'est pret !". Ca donne l'impression que le monde se construit,
au lieu d'un compte a rebours.

Le timing de sortie ne change pas : toujours gate sur le prechargement fini ET la duree minimale (15 s). Toute la
machinerie de la barre (progress, bump, boucle d'affichage) est supprimee.

## 0.0.146 — Top bar de selection partage (StepBadge + diamant) + entree qui slide du haut

Les deux ecrans de selection (plot puis save) partagent maintenant UN seul top bar : le StepBadge ("STEP 1 OF 2" sur le
plot, "STEP 2 OF 2" sur les saves) et le compteur de diamants. Cree une fois dans LoadSaveUI (ensureTopBar), au-dessus
de tout (ZIndex 50), toujours visible ; seul le numero d'etape change. Fini les doublons a maintenir de chaque cote.

Petit plus : quand l'ecran de chargement s'enleve, le StepBadge et le diamant DEBOULENT du haut (slide Back Out). Ils
attendent un signal (attribut LeafiaLoadingDone pose par le loading a sa fin) avant de slider, sinon l'animation se
jouerait derriere l'ecran de chargement, invisible.

## 0.0.145 — Mise en page MOBILE de l'ecran de selection (et du bas du chargement)

Sur PETIT ECRAN tactile, l'ecran de plot debordait : la carte de description coupee aux bords, les fleches Next/Prev
et les barres de page mal placees. On FORCE par code une mise en page mobile (valeurs tunees dans l'emulateur
telephone) : positions/tailles de DescriptionHolder, SubHolder, ClaimButton, DescriptionText, Icon, Next/Previous,
PointPageVisualHolder, et on RETIRE le UICorner du DescriptionHolder (ses coins arrondis se faisaient couper au bord).
Table MOBILE_LAYOUT dans PlotSelectController, une entree par element (scope + anchor/position/size), reglable.

Bas de l'ecran de chargement : sur mobile, Tycoon et Version etaient trop dans les coins, on rapproche leur X du centre
(TYCOON_MOBILE_X / VERSION_MOBILE_X).

Regle assumee : le code ne touche a ces elements QUE sur tactile. Sur PC ils gardent leurs valeurs Studio, qui restent
donc la reference de la mise en page PC. Applique a tout appareil tactile (telephone ET tablette) pour l'instant.

## 0.0.144 — Flou de profondeur sur l'ecran de selection de plot

Un depth of field (flou du lointain) pendant qu'on choisit son plot et sa save : le plot ressort, le fond fond. L'effet
vit dans Lighting (DepthOfFieldEffect, pose dans Studio). PlotSelectController en est le SEUL pilote : il l'ALLUME a
l'ouverture de l'ecran (avec les valeurs voulues) et l'ETEINT au clic Start.

Pourquoi eteindre AU CLIC et pas a la fin : la camera finit a ~12 studs du joueur, bien avant la zone nette
(FocusDistance ~117), donc DOF allume = joueur FLOUTE. On coupe des le Start : le monde se defloute pendant que la
camera plonge sur le joueur. Valeurs reglables dans le controller (DOF_FOCUS_DISTANCE, DOF_IN_FOCUS_RADIUS,
DOF_FAR_INTENSITY, DOF_NEAR_INTENSITY).

## 0.0.143 — Notification laterale : son a l'apparition + adaptation mobile (telephone / tablette)

La notif laterale joue un petit son quand elle apparait (SoundUtils, Sounds/UI/NotificationSound).

Sur ECRAN TACTILE elle etait trop petite au doigt et tombait sous le bouton de saut (coin bas-droit). On grossit la
pile (UIScale sur HolderList) et on la repositionne. On DISTINGUE telephone et tablette : le cote COURT du viewport
en dessous de PHONE_MAX_SHORT_SIDE (600) = telephone (petit ecran), au-dessus = tablette. Chacun a son scale et sa
position (TABLET_SCALE / PHONE_SCALE, TABLET_POSITION / PHONE_POSITION), reglables a l'oeil.

La NotificationUI passe en ScreenInsets = None (pose en code au boot) : coords plein ecran, l'origine devient le coin
absolu de l'ecran (l'inset de la barre Roblox est ignore). Le placement de la pile est alors coherent entre appareils.
Meme famille que WorldAnchor / GetMouseLocation.

## 0.0.142 — Fond en tuiles a trou central (essai) + silence a l'entree dans le jeu

Fond en tuiles (ESSAI, sur l'ecran de plot). Pas de gradient radial natif en UI Roblox : on le fait A LA MAIN, par
tuile (idee du joueur). Une GRILLE de tuiles individuelles (rbxassetid://78626050824347) defile en diagonale
par-dessus le monde 3D ; chaque frame, la transparence de CHAQUE tuile est recalculee selon la distance de son centre
au centre de l'ecran -> trou clair au milieu (bord doux), tuiles visibles autour. ScreenGui a part (DisplayOrder -5 :
devant le monde 3D, derriere l'UI de plot), detruit au Start. Reglages : TILE_FRAC (finesse du cercle et nombre de
tuiles), TILE_BASE_TRANSPARENCY, TILE_SPEED, TILE_HOLE_INNER / OUTER.

Silence a l'entree : au Start (camera qui se pose sur le joueur), la musique de jeu FOND a 0 sur 1.6 s. L'ecran de
chargement nomme desormais son clone "GameMusic" pour que PlotSelect le retrouve sous SoundService. Effet voulu : un
blanc sonore, une bascule d'etat quand on entre vraiment dans le jeu.

## 0.0.141 — Ecran de plot vivant : nom, description, taille, step, cadre claimable, barres de page

L'ecran de selection de plot s'habille. Nouveau `Modules/Configs/PlotConfigs.luau` (data pure, une entree par Slot :
nom, categorie de taille, nombre de tuiles, description ~1 ligne et demie ; DEFAULT pour un plot non liste). Au
changement de plot (goToPlotIndex), PlotSelectController remplit depuis ce config :
- TitleNamePlot = le nom du plot.
- DescriptionText = la description.
- PlotMaxMinText = "PLOT x / y - SIZE - N TILES" (x = index courant, y = nombre de plots).

AmountStep suit l'ecran : "STEP : 1 / 2" sur la selection de plot, "STEP : 2 / 2" sur la selection de save. Tous les
changements d'ecran passent desormais par un showScreen() unique (UIManager + step + pulse).

AvailablePlotLabel PULSE entre deux verts (41,172,26 <-> 93,220,34) tant que le plot est claimable (pour l'instant :
toujours). Tween en reverse infini, COUPE quand on quitte l'ecran de plot (regle : pas d'effet en boucle sur une UI
cachee), relance au retour.

Barres de page (PointPageVisualHolder) : une barre par plot, clonee de Templates.PointSelectiveFrameTemplate. Celle
du plot courant est jaune (255,204,52) et large, les autres blanches et etroites ; transition douce au Next/Prev.

A ETOFFER : PlotConfigs contient des placeholders (vrais noms / descriptions a mettre). PAS ENCORE FAIT : AmountDiamond
(devise PERSISTANTE a creer cote data) et l'essai de fond en tuiles animees (le "cercle clair au milieu" n'est pas
natif en UI Roblox, cf discussion).

## 0.0.140 — Selection de plot : Next / Previous font defiler les plots

Les boutons PreviousButton / NextButton de l'ecran de selection font CHANGER de plot. La camera d'orbite GLISSE vers
le nouveau plot (elle continue de tourner sans coupure : le centre d'orbite est lisse vers la cible via
ORBIT_CENTER_LERP, l'angle reste continu) et un swoosh (SoundService.Sounds.UI.PassingSound) accompagne chaque
changement. `currentPlot` suit, donc Claim et Start portent sur le plot AFFICHE. Le parcours BOUCLE (Next sur le
dernier -> le premier, Prev sur le premier -> le dernier ; wrap par modulo dans goToPlotIndex).

Enumeration : au demarrage on liste tous les enfants de Workspace.Worlds.Plots qui ont un PrimaryGround (le marqueur
"c'est un plot") et on pre-calcule leur centre UNE fois -> Next/Prev lit ce cache, sans re-attendre. Les plots sont
tries par nom (Slot1, Slot2...). `PLOT_NAME` (le plot unique code en dur) disparait. plotCenter passe de WaitForChild
a FindFirstChild : on n'arrive la qu'apres game.Loaded et apres avoir attendu le dossier Plots.

PAS FAIT (UI, laissee au joueur) : le nom du plot (TitleNamePlot), la description et les points de page
(PointPageVisualHolder) ne sont pas encore mis a jour au changement -- la source de la donnee d'affichage
(attribut sur le plot ? config ?) reste a definir. A cabler quand elle sera connue.

## 0.0.139 — Musique du jeu au reveal + sons de clic separes (curseur / bouton)

Musique de fond : `SoundService.Sounds.Game.Musics.Music3` demarre a la SORTIE du loading (pendant le reveal /
fondu de l'ecran), a volume bas (force a GAME_MUSIC_VOLUME = 0.1 dans le code, reglable). Elle boucle et vit sur SoundService,
donc elle survit a la destruction de l'ecran de chargement. Jouee dans LoadingScreenClient, qui gere deja sa propre
musique : le fichier reste autonome (clone / play direct depuis SoundService, aucun require de ReplicatedStorage).
Absente -> rien (findSound, aucun warn). Quand on voudra un vrai systeme (playlist Music1/2/3, crossfade), ca
deviendra un MusicController ; pour l'instant une boucle simple suffit.

Sons de clic separes (suite du 0.0.138) : deux Sounds dedies cote Studio. PressCursorSound = clic DANS LE MONDE
(hors UI) ; PressButtonSound = clic SUR un bouton. Mutuellement exclusifs : ClickSoundController filtre desormais
gameProcessed (un clic pris par l'UI ne joue plus le son curseur), et ButtonSlime joue PressButtonSound sur
MouseButton1Down. Un clic = un seul son.

Son de survol fiabilise : il partait du curseur sur la transition "aucun bouton -> un bouton", donc survoler des
boutons COLLES ne sonnait qu'une fois (jamais de frame "aucun bouton" entre eux). Deplace dans ButtonSlime, par
bouton (MouseEnter) : chaque bouton fait "pop", meme colles.

Dosage : slime des boutons adouci (gonflement +10 -> +5 %, respiration et enfoncement baisses aussi). Curseur
reduit d'un cran (CURSOR_SCALE 0.022 -> 0.020).

## 0.0.138 — Juice des boutons : slime au survol + clic (curseur ET boutons), son au survol

Retour d'interface "vivant". Trois choses.

CURSEUR (CursorController). Au SURVOL d'un bouton il GONFLE et RESPIRE doucement (effet prolonge, il vit tant
qu'on reste dessus), et un SON se joue une fois a l'entree. Ca se compose avec le creux du clic sur le meme
ressort : survoler gonfle, cliquer enfonce, relacher rebondit. Le survol est detecte UNE fois par frame via
`playerGui:GetGuiObjectsAtPosition(m.X, m.Y)` (pas par event de souris : agiter la souris ne doit pas flooder le
hit-test). m.X/m.Y sont dans le meme repere absolu que l'AbsolutePosition des boutons, donc ca marche quel que
soit l'IgnoreGuiInset du GUI. Curseur aussi reduit d'un cran (CURSOR_SCALE 0.022 -> 0.020).

BOUTONS (nouveau `Modules/UI/Core/ButtonSlime.luau` + `Client/ButtonSlimeController.luau`). Le bouton LUI-MEME
gonfle / respire au survol et s'enfonce au clic, via un `UIScale` dedie ajoute au bouton (nomme `SlimeScale`) : on
ne touche jamais a la Size reglee dans Studio, et ce UIScale se compose avec un UIScale deja present. Une seule
boucle RenderStepped anime tous les boutons ; les boutons au repos sont cales a 1 et sautes (pas de relayout pour
rien). Le controller auto-branche TOUS les GuiButton de PlayerGui + les nouveaux (DescendantAdded), donc un bouton
ajoute dans Studio est slime sans cablage. Filet anti-blocage : un relachement n'importe ou relache le clic de
tous les boutons (si le bouton disparait au clic, son MouseButton1Up ne tirerait pas et l'enfoncement resterait
fige). Un bouton cache relache aussi son etat (il ne revient pas gonfle).

ORBITE du plot-select (PlotSelectController) : passe de `RenderStepped:Connect` a `BindToRenderStep` a la priorite
Camera. C'est le pattern correct d'une camera scriptee (ecrire la CFrame au bon moment du pipeline). Note : le
"drop de FPS" soupconne etait un FANTOME de Studio (MicroProfiler ouvert + survol Studio) ; le meme build tourne a
200 FPS parfait dans l'appli Roblox. Ce changement ne repare donc rien cote perf, mais reste juste en soi.

A faire dans Studio :
- Creer un `Sound` nomme `HoverButtonSound` dans `SoundService.Sounds.UI` (a cote de `PressButtonSound` du clic),
  avec un SoundId et un volume bas. Sans lui, un warn "Son introuvable" sort a chaque survol.
- Pour un POP centre, les boutons doivent avoir AnchorPoint (0.5, 0.5) ; sinon ils grandissent depuis leur coin
  d'ancrage (le slime marche quand meme).

Reglages : `SLIME_HOVER` / `SLIME_HOVER_PULSE` (curseur), `HOVER` / `HOVER_PULSE` / `PRESSED` / `STIFFNESS` /
`DAMPING` (boutons).

Ecart assume avec la regle d'or : c'est de l'habillage / du juice, pose apres validation du geste. A doser, pas a
etendre a l'infini.

## 0.0.137 — Taille du dessus (echelle) : retour a la SIMPLICITE (curseur -> anim, point)

Apres un long detour (visee par ANGLE facon champ de vision, ZONES colorees de la haie qui changeaient le
comportement, EVENEMENTS d'anim lus en async) qui a coute cher et marchait "quand ca voulait", on tranche : UNE
seule regle pour la lame du dessus. La position du curseur LE LONG de la haie pilote la RightLeftAnimation, du debut
a la fin (bord a bord). Pas d'angle, pas de zones, pas d'appel reseau. Reglages restants : TOP_SENSITIVITY (extremes
atteints avant les bords si > 1) et CUT_TOP_INVERT (sens gauche/droite).

Supprime : le champ de vision (TOP_FOV_HALF_DEGREES), la lecture des evenements MaxLeft/Middle/MaxRight
(GetKeyframeSequenceAsync, la source du "parfois ca marche"), et TOUT le systeme de zones : HedgeSectionService
(les parts colorees Jaune/Rose/Bleu/Marron/Violet + la detection de position) et ses configs HEDGE_SECTION_*.
topTrimTime est desormais LINEAIRE (ratio * duree). Lecon notee : une visee par angle depend du repere (camera,
corps, position) et se paie en allers-retours ; le curseur projete SUR la haie, lui, est direct et stable.

Regression du 0.0.135 : E ouvrait la boite, elle se refermait TOUTE SEULE dans la foulee, et ensuite plus rien
(E mort, aucune anim). Cause : la piste etait en Looped = false ; arrivee au marqueur IsOpenEvent (le dernier
evenement de l'anim), elle se RELACHAIT au bout, et un garde-fou "si la piste s'est stoppee, relance-la" faisait
Play(0,1,0) qui REMET TimePosition a 0 -> la boite claquait fermee, et le drapeau atOpen restait a true -> la
boucle la figeait fermee pour toujours. C'est le piege deja note dans CLAUDE.md (tenir la derniere image d'une
anim = Looped = true, sinon la pose saute).

Fix (MailboxService) : Looped = true (la pose tient au bout, rien ne se relache), suppression du garde-fou qui
remettait a 0, et CLAMP a un frame de chaque borne (0 et Length) pour que la lecture ne wrappe jamais a l'autre
extremite. Resultat : ouvrir / fermer / re-ouvrir marche indefiniment.

## 0.0.135 — Boite aux lettres : E marche a TOUS les coups (fini "parfois ca ouvre, parfois non")

Bug : E ouvrait la boite une session sur deux, et quand ca ratait, ca ne marchait plus de TOUTE la session. Cause :
le temps du marqueur IsOpenEvent etait lu au boot via GetKeyframeSequenceAsync, une API reseau CAPRICIEUSE cote
serveur (rate-limit, et l'echelle l'appelle au meme boot). Quand elle ratait, openTime restait a 0 -> la cible
d'ouverture etait 0 -> la boite ne s'ouvrait jamais.

Fix (MailboxService) : on ne lit PLUS le temps a l'avance. On joue l'anim et on la FIGE quand elle ATTEINT le
marqueur IsOpenEvent (GetMarkerReachedSignal en avancant, Speed > 0 -> AdjustSpeed 0 + drapeau atOpen). C'est une
lecture LOCALE pendant la lecture de l'anim, sans appel reseau : fiable a chaque session. La fermeture (recul
jusqu'a 0 quand l'ouvreur part) est inchangee. Plus de dependance a GetKeyframeSequenceAsync ni de champ openTime.

## 0.0.134 — Boite aux lettres : ouvre a l'approche (E), se referme quand on part

Avant : E jouait tout le clip (ouvre PUIS ferme) d'un coup. Maintenant : E OUVRE la boite (l'anim va de 0 jusqu'au
marqueur IsOpenEvent, ou la porte est ouverte, et s'y TIENT). Quand l'ouvreur s'ELOIGNE (au-dela de CLOSE_DISTANCE),
l'anim repart EN ARRIERE jusqu'a 0 : la boite se referme.

Technique (MailboxService) : le temps du marqueur IsOpenEvent est lu une fois au boot (GetKeyframeSequenceAsync).
Une boucle Heartbeat pilote la VITESSE de lecture (AdjustSpeed +ANIM_SPEED pour ouvrir, -ANIM_SPEED pour fermer,
0 pour tenir la pose) selon la cible (ouvert si l'ouvreur est pres, ferme sinon). On pilote la VITESSE plutot que
la TimePosition a la main : "jouer a telle vitesse" se replique proprement a tous les clients. Reglages :
ANIM_SPEED (vitesse), CLOSE_DISTANCE (distance de fermeture). NOTE : il faut le marqueur IsOpenEvent dans l'anim
(sinon warn + la boite reste fermee).

SONS : au marqueur OuvertureEvenement (GetMarkerReachedSignal), franchi dans les DEUX sens -> son d'OUVERTURE si on
avance (Speed > 0), son de FERMETURE si on recule (Speed < 0). Spatial et a PORTEE LIMITEE (InverseTapered,
RollOffMaxDistance = SOUND_MAX_DISTANCE) : seuls les joueurs PRES de la boite l'entendent, pas tout le serveur
(sinon le son par defaut porte a ~10000 studs). Sons : SoundService.Sounds.Game.GlobalSounds.OpenMailboxSound /
CloseMailboxSound.

## 0.0.133 — Boite aux lettres : prompt stylise (le meme que l'echelle), fini le prompt Roblox moche

Le ProximityPrompt affichait l'UI Roblox par defaut (moche). On passe son Style en Custom (plus d'UI par defaut)
et on dessine notre InteractionPrompt a la place (le MEME prompt que l'echelle : pilule rose qui pulse, badge de
touche, apparition slime, son). Cohérence visuelle totale.

- `Server/MailboxService.luau` : le prompt passe en Style = Custom, nomme "MailboxPrompt". Il garde tout son
  travail (proximite, input E, Triggered qui joue l'anim cote serveur) ; seul l'affichage change.
- `Client/MailboxController.luau` (nouveau) : ecoute ProximityPromptService.PromptShown / PromptHidden ; quand
  c'est le prompt de la boite, montre / cache l'InteractionPrompt qui suit la boite (WorldAnchor). Sur mobile, le
  tap declenche le prompt (prompt:InputHoldBegin, HoldDuration 0). Branche dans le bootstrap client.
- FIX : on ne pouvait cliquer qu'UNE fois. InputHoldBegin laissait le prompt "maintenu" -> les clics suivants
  tombaient dans le vide. On appelle InputHoldEnd juste apres pour le liberer.
- InteractionPrompt (partage avec l'echelle) : SQUISH slime au clic / tap. On ecrase d'un coup puis rebond Elastic
  (gelee prolongee) a chaque appui. Reglages PRESS_SQUISH / PRESS_TWEEN.
- TITRE de l'objet AU-DESSUS de la pilule du prompt (comme l'ObjectText d'un ProximityPrompt) : InteractionPrompt
  enveloppe desormais la pilule dans un conteneur vertical (titre en haut, pilule en bas), et show() prend un
  argument `title` optionnel (blanc + contour, cache si vide -> l'echelle, sans titre, ne change pas). Le titre
  apparait / disparait AVEC le prompt et pop / squishe avec lui. Cote boite : PROMPT_OBJECT = "MAILBOX" (le client
  le lit via prompt.ObjectText et le passe en titre).
- Le prompt de la boite se place du cote OPPOSE au joueur (le long de la droite de l'ecran), pour ne pas tomber
  SUR le perso. Quand le joueur passe de l'autre cote, le prompt GLISSE (lerp) vers l'autre bord (avec hysteresis
  pour ne pas sauter quand on est aligne). Offset RELATIF A LA CAMERA (nouvel argument cameraRelative de
  InteractionPrompt.show ; nouvelle fonction InteractionPrompt.setOffset pour l'animer). Reglages dans
  MailboxController : PROMPT_HEIGHT (hauteur), PROMPT_SIDE (ecart lateral), SIDE_LERP, SIDE_HYSTERESIS. Titre en
  LuckiestGuy (TITLE_FONT dans InteractionPrompt).

## 0.0.132 — Taille du dessus : visee RELATIVE AU JOUEUR (le corps ne part plus trop loin selon la position)

Vrai probleme derriere le 0.0.130/131 : le corps partait trop loin (a gauche surtout) quand l'echelle etait posee
au BOUT de la haie. Cause : le ratio de visee etait relatif a la HAIE (0 = bord gauche de la haie), donc au bout
gauche, viser le bord gauche envoyait quand meme le corps a fond a gauche, dans le vide.

Fix : le ratio est desormais RELATIF AU JOUEUR (position laterale du curseur par rapport a OU on se tient, le long
de la droite de l'ecran : 0.5 = pile devant, 0 = a REACH a gauche, 1 = a REACH a droite). Comme le curseur est
clampe a la haie, quand l'echelle est au BOUT GAUCHE on ne peut viser que vers la droite -> le corps ne tourne
jamais trop a gauche, TOUT SEUL. La plage utile de l'anim se limite d'elle-meme selon ou l'echelle est posee
(bord gauche -> plage haute, milieu -> plage complete, bord droit -> plage basse). Exactement le comportement voulu.

Reglage : TOP_PLAYER_REACH (studs, distance laterale du curseur pour un corps a fond tourne). Remplace
TOP_SWEEP_REFERENCE_WIDTH / topSweepSpan du 0.0.130 (supprimes). Le mapping par evenements (0.0.131) est conserve :
si l'anim a ses 3 evenements, la pose se cale dessus ; sinon secours LINEAIRE (le ratio etant deja relatif au
joueur, 0.5 = centre). NOTE : les evenements ne s'appliquent que si l'anim de l'outil est bien trouvee (cf le
souci du dossier Shear).

## 0.0.131 — Taille du dessus : la pose se cale sur des EVENEMENTS d'anim (bord a bord propre)

Suite du 0.0.130. Le joueur a pose 3 evenements dans la RightLeftAnimation (editeur d'anim) qui reperent les
poses du CORPS : CompletLeftEvent (a fond a gauche), MiddleAnimationEvent (centre), CompletRightEvent (a fond a
droite). On cale desormais la lame sur CES temps au lieu de balayer toute l'anim :
- bord gauche de la haie -> CompletLeft, centre -> Middle, bord droit -> CompletRight (interpolation par morceaux).
- La lame balaie donc EXACTEMENT de bord a bord ; le corps ne part jamais trop loin a gauche / droite.
- Comme le curseur du dessus est deja clampe aux bords, au bord gauche de la haie on ne peut viser que vers la
  droite -> le corps ne tourne pas trop a gauche, tout seul.

Technique (LadderController) : les temps des 3 evenements sont lus UNE fois par outil, en tache de fond
(KeyframeSequenceProvider:GetKeyframeSequenceAsync -> temps du Keyframe qui porte chaque KeyframeMarker), et mis en
cache par id d'anim. Chaque outil a sa propre RightLeftAnimation (Shear fait ; HedgeTrimmer a faire). SECOURS : si
une anim n'a pas les 3 evenements (ou si la lecture echoue), on retombe sur la compression du 0.0.130 (aucun crash,
juste un warn). Les evenements remplacent le reglage TOP_SWEEP_REFERENCE_WIDTH des qu'ils sont presents.

## 0.0.130 — Taille du dessus (echelle) : la lame suit le curseur jusqu'aux bords

Bug : en taillant le dessus depuis l'echelle, plus le curseur approchait d'un BORD de la haie, plus la lame partait
a cote (la coupe ne suivait plus la visee). Cause : le curseur du dessus est CLAMPE aux bords de la haie (0 = bord
gauche, 1 = bord droit), mais la lame suit l'anim RightLeft dont le balayage a une AMPLITUDE FIXE (reglee dans
Studio). Sur une haie plus etroite que ce balayage, la lame debordait : nul au centre (ca colle), pire aux bords.

Fix (LadderController, phase "top") : on COMPRESSE le balayage de la lame a la largeur reelle du dessus, centre sur
le milieu (comme la pose up/down au sol suit deja la HAUTEUR de la haie). La lame reste donc sous le curseur d'un
bord a l'autre. Reglages : TOP_SWEEP_REFERENCE_WIDTH (largeur ou l'anim balaie pile bord a bord) et TOP_SWEEP_MIN_SPAN.

A REGLER a l'oeil : si la lame DEBORDE encore aux bords, MONTER TOP_SWEEP_REFERENCE_WIDTH ; si elle N'ATTEINT PAS
les bords, la baisser. NOTE : ce fix concerne la taille du dessus DEPUIS L'ECHELLE. Si le meme decalage arrive au
SOL (dessus d'une haie basse, sans grimper), c'est un autre chemin (HedgeController onTop) a corriger a part.

## 0.0.129 — L'echelle portee garde une orientation FIXE (fini "de travers")

Bug : en prenant l'echelle, elle se tournait face au joueur, et se reposait donc mal par rapport a la haie. Cause :
a la 1re prise on CAPTURAIT le yaw d'origine de l'echelle (sa pose Studio) et on le reutilisait a vie. Si cette
pose etait de travers, l'echelle etait portee ET reposee de travers pour toujours.

Fix : on ne capture plus le yaw d'origine. L'echelle se cale a une ORIENTATION FIXE reglable (CARRY_YAW_DEGREES,
en degres autour de la verticale) RELATIVE au repere carre "face a la haie". Le portage, donc la repose, est donc
toujours le meme et bien oriente vers la haie. On garde le choix du SENS (0 / 180) le plus proche de la pose
actuelle pour eviter le demi-tour brusque dans les mains. Le recul (bord arriere a CARRY_CLEARANCE) est recalcule
pour l'orientation choisie (nouvelle mesure `ladderBackOffsetForYaw`, en repere echelle). Supprime : la capture
`carryOffset` et `ladderBackEdgeZ`.

A REGLER a l'oeil : CARRY_YAW_DEGREES (0 par defaut). Prendre l'echelle ; si elle fait face de travers, essayer
90 / 180 / 270 jusqu'a ce que le cote de grimpe pointe bien vers la haie.

SUITE : le flip 0/180 "sens le plus proche de la pose plantee" a ete RETIRE. L'echelle REPLIEE est ~symetrique :
le flip choisissait parfois l'oppose sans que ca se voie a la prise, et au DEPLI (repose) l'echelle se retrouvait
a 180 de travers. Sens DETERMINISTE maintenant (toujours CARRY_YAW_DEGREES) : la repose est toujours bien orientee.
Fonction rotAlign supprimee (plus utilisee).

## 0.0.128 — Prendre l'echelle ne fait plus grimper dessus

Bug : prendre l'echelle (E pour la porter, LadderMoveController) faisait aussi GRIMPER dessus. Cause : les zones
de grimpe (box_detecte_A / B) sont ENFANTS du modele d'echelle. Une echelle portee est soudee au HRP du joueur,
donc ses zones le suivent : LadderController croyait le joueur en permanence "dans la zone" et l'accrochait a sa
propre echelle portee.

Fix : un attribut client LeafiaCarryingLadder pose sur le perso pendant qu'on porte (grabCarry / endCarry dans
LadderMoveController). LadderController le lit en tete de sa boucle : tant qu'on porte, pas de grimpe (dismount
idempotent, qui sort proprement si on avait deja accroche avant de prendre). Aucun changement serveur.

## 0.0.127 — Boite aux lettres : E l'ouvre (point d'entree des futurs chantiers)

Premiere brique du systeme de chantiers : une boite aux lettres (MailboxModel, posee en Studio) qu'on ouvre en
appuyant sur E. Pour l'instant ca ne fait QUE jouer l'animation ; le courrier / l'interface des chantiers se
brancheront dessus ensuite.

- `Server/MailboxService.luau` (nouveau) : retrouve MailboxModel dans le Workspace, charge son anim
  ReplicatedStorage.Animations.Props.Mailbox.OpenCloseAnimation sur son Animator, et lui colle un ProximityPrompt
  ("Ouvrir" / "Boite aux lettres", touche E). Au Triggered, joue l'anim UNE fois (debounce via track.IsPlaying,
  l'etat reel du moteur, pas un drapeau maison).
- Anim jouee cote SERVEUR : tous les joueurs voient la boite s'ouvrir (comme l'echelle en co-op).
- ProximityPrompt plutot qu'une detection E maison : Roblox gere la proximite, l'invite clavier ET un bouton
  tactile automatiquement (mobile gratuit). Aucun controller client necessaire.
- Le Humanoid du modele est passe en DisplayDistanceType = None (pas de nom / barre de vie sur une boite).
- Branche dans le bootstrap serveur.

RESTE A FAIRE : ouvrir l'interface des chantiers du joueur au bon moment (hook laisse dans onTriggered, ou via
l'evenement d'anim OuvertureEvenement). C'est le debut de la boucle boite -> courrier -> chantier -> cheque.

## 0.0.126 — Coins / aretes plus faciles a finir (portee bonus sur les bordures)

Probleme signale : certains feuillus dans les coins et les aretes restaient impossibles a amener au ras, il
fallait se battre. Contraire a la regle d'or (tailler doit rester jouissif).

Cause : la coupe cale la lame sur la face travaillee. Aux coutures entre deux faces (arete verticale, coin), la
lame arrive DE BIAIS sur les cellules de la face d'a cote : le test "la lame est-elle du bon cote" (outward) et la
portee ne les attrapaient pas tout a fait, donc une derniere frange de feuillus restait.

Fix : les cellules de BORDURE (deja marquees EDGE_ATTRIBUTE a la construction) recoivent deux bonus, uniquement
elles : plus de PORTEE (CUT_EDGE_REACH_BONUS) et une TOLERANCE de surface plus large (CUT_EDGE_SURFACE_BONUS, lame
plus rasante acceptee). En balayant pres d'un coin, les coutures se finissent sans combat. La coupe en pleine face
est INCHANGEE (les bonus ne touchent que les bordures). Le ramassage des cellules (gather) suit la portee elargie.

Suite (meme session) : la FRANGE DU BAS restait, tout le pourtour au ras du sol. Cause distincte : la rangee du
sol des cotes n'est PAS marquee Edge (voulu : detruire ses feuilles ouvrirait la haie par en dessous), donc elle
n'avait pas le bonus ; et surtout la pose la plus BASSE des bras (frame 0 de l'anim, fixe quelle que soit la haie)
arrive AU-DESSUS de cette rangee, hors de portee du geste. Fix : nouvel attribut BASE_ATTRIBUTE sur la rangee du
sol des cotes (marque a la construction), avec un bonus de portee GENEREUX (CUT_BASE_REACH_BONUS, plus large que
les aretes) et une tolerance elargie, MAIS sans destruction de feuille (la base reste fermee). Le geste bas
attrape enfin la frange. Priorite base > edge (un coin bas est les deux). NOTE : les haies sont bati au demarrage
du serveur, donc il faut RELANCER le playtest pour que les cellules recoivent le nouvel attribut.

A noter, non concerne par ces fix : le DESSUS des haies hautes reste non taillable depuis le sol (voulu,
TOP_CUT_MAX_HEIGHT) ; l'escabeau le levera. Et la visee reste calee sur la face travaillee : pour tailler une
autre face on marche jusqu'a elle (la camera ne sert qu'a regarder). Une refonte "ce que je vois je le taille"
reste une option si le besoin revient.

## 0.0.125 — Orbite de la camera de travail : 1:1, fini la "courbe" et le smear

Probleme signale : quand on tourne la camera (clic maintenu + glisse) en taillant, elle suivait une COURBE au lieu
de tourner net, et plus on glissait vite plus ca trainait (smooth "degueulasse").

Cause : la camera de travail est placee sur un CERCLE autour de la haie (angle = yaw, bouge au glisse). Chaque
frame le code lissait la POSITION vers la cible en ligne droite. Or la cible tourne sur un ARC : lisser en ligne
droite coupe la corde, la camera plonge vers l'interieur du cercle puis ressort -> la "courbe", et la distance a la
haie qui varie pendant le pivot. En plus, un seuil "settled" repassait en mode LENT des que la cible sautait loin :
donc plus on glissait vite, plus la camera trainait (a l'envers).

Fix : on ne lisse PLUS la position pendant le travail. La camera est placee DIRECTEMENT sur son cercle au yaw
courant -> orbite 1:1 avec le doigt / la souris, rayon constant, zero corde coupee. On garde le lissage seulement
pour l'ARRIVEE a l'engage (le glisse depuis la cam de jeu, une fois, via un drapeau camArrived) et pour la
DISTANCE de recul a l'acceleration (lissee en parametre : currentDistance / CAMERA_DISTANCE_LERP), qui ne deforme
pas l'orbite. Reglage mort supprime : CAMERA_LERP_SPEED_WORK.

RUBBER-BAND sur la butee d'orbite (avant, elle etait SECHE) : on peut ETIRER la camera de quelques degres au-dela
de la limite, avec une resistance croissante (marge elastique), et au relachement un ressort SOUS-AMORTI la ramene
a la limite avec un petit rebond (slime). Un helper applyOrbitDrag remplace le clamp dur des deux entrees (souris +
tactile) ; le retour est un ressort dans update, actif seulement quand on ne pilote plus l'orbite et que yaw a
deborde. Reglages : CAMERA_YAW_MARGIN (etirement max), CAMERA_YAW_SNAP_STIFFNESS / CAMERA_YAW_SNAP_DAMPING (le rebond).

## 0.0.124 — Interface economie (CurrencyUI) : pieces + reputation, pilotees par le serveur

Le joueur a monte a la main une ScreenGui CurrencyUI (pieces + reputation). On lui donne sa plomberie : le
serveur pose les valeurs, le client les affiche. Meme schema que l'XP et le combo (attributs sur le joueur, zero
remote), donc rien de nouveau a apprendre.

- `Modules/Configs/CurrencyConfigs.luau` (nouveau) : noms d'attributs partages `LeafiaCoins` / `LeafiaReputation`.
- `Server/CurrencyService.luau` (nouveau) : autorite, RUNTIME (pas de sauvegarde tant que le gain n'est pas
  branche, meme regle que l'XP). Pose les attributs a 0 des le join pour que l'UI soit vivante. Expose
  `grantCoins(player, montant)` et `grantReputation(player, montant)` : point d'entree UNIQUE du futur gain.
- `Client/CurrencyController.luau` (nouveau) : HUD fixe, remplit `CoinsText` / `ReputationText` (formatage via
  FormatUtils : 1250 -> "1.25K"), avec un petit POP a la hausse (gain). Attend le perso avant de chercher l'UI.
- Branches dans les deux bootstraps.
- OUTIL DE TEST (dev) : dans Studio, cliquer l'icone piece (CoinsImage) donne +1000. Remote `Dev/DevGrantCoins`,
  double garde `RunService:IsStudio()` (client ET serveur) : mort sur un vrai serveur, le serveur decide du
  montant (le client n'envoie rien). Aucun exploit possible, rien a retirer au lancement.
- `FormatUtils.Abbreviate` : passe a UNE decimale TOUJOURS affichee (80000 -> "80.0K" au lieu de "80K"). Format
  partage, donc harmonise aussi les notifications laterales. Sous 1000 : nombre entier brut (500 -> "500").
- CoinsText / ReputationText colores selon le SIGNE : blanc-vert pale si > 0 (benefique), blanc pur a 0 (neutre),
  rouge franc si negatif (dette). Robuste a un UIGradient sur le texte (force la teinte unie, sinon le degrade
  ecraserait la couleur). Prepare l'enjeu a venir (bacler / casser du materiel pourra passer le solde sous zero) :
  le rouge ne sort que si une source retire des pieces, tant qu'aucune n'existe tout reste blanc / vert pale.
- Compteur qui DEFILE : quand la valeur change, le nombre affiche glisse jusqu'a la nouvelle (3.0K -> 3.1K ->
  ... -> 4.0K) au lieu de sauter. Rend le gain gourmand. CurrencyController refactore : coins et reputation
  partagent une seule structure Counter (defile + pop + couleur), fini la duplication.
- SHINE a chaque gain : une bande blanche diagonale balaye le texte, vite (une passe). Portee par le meme
  UIGradient que la couleur (un element n'a qu'un gradient) : le shine prend la main pendant le balayage puis
  rend la teinte unie. UIScale et UIGradient crees en code si absents (pas a poser dans Studio).
- TEXTE FLOTTANT "+X" a chaque gain de pieces (facon GTA / Sims) : le montant ajoute apparait SOUS le bloc pieces
  (le HolderCoins), descend un peu et s'efface. Dore, police LuckiestGuy. Vit dans une ScreenGui a part
  (CurrencyFly, ScreenInsets None) pour se placer aux pixels absolus sans se faire rogner par le HUD. Pas de fly
  sur la reputation (un "+X" dore prendrait pour de la piece).

Choix de design (valides avec le joueur) :
- La REPUTATION reste un RANG qui se MERITE, jamais achetable : le bouton d'achat a ete retire de HolderReputation.
- Le GAIN de pieces n'est PAS branche : il tombera comme un CHEQUE de fin de chantier, via le futur systeme de
  quetes/clients (boite aux lettres -> courrier d'un client -> chantier -> paye). Ce systeme n'existe pas encore.
  Le tuyau est pret : QuestService appellera `CurrencyService.grantCoins`. En attendant, pieces + repu affichent 0
  (honnete) mais l'UI reagit des qu'une valeur bouge.

RESTE A FAIRE : systeme de quetes/chantiers (le gain), puis persistance (DataTemplate.Coins/Reputation existent
deja), depense (boutique/outils), et adaptation mobile de ce HUD si besoin.

## 0.0.123 — Support MOBILE de la taille + refonte du repere de coupe

Gros chantier : rendre la taille au sol JOUABLE sur tactile (90% du public Roblox), sans casser le PC.

INPUT
- Nouveau module leger `Modules/Utils/InputDevice` : `isTouch()`, `kind()`, signal `changed`. Suit le dernier input
  UTILISE (un mobile avec clavier reste detecte tactile quand on touche l'ecran). Passif, auto-init a la 1re require.
- VISEE AU DOIGT (HedgeController) : la visee ne lit plus la souris en dur, `aimScreenPoint()` rend `GetMouseLocation`
  (qui suit le doigt, bon repere) et nil si aucun doigt pose. Poser+glisser = viser+couper. `aimTouch` = juste "un
  doigt vise". Le point vient TOUJOURS de GetMouseLocation (utiliser InputObject.Position mettait la bille a cote).
- CISAILLE AU DOIGT : le tap seul ne coupe jamais (aimActive faux a l'instant du contact) -> repete-au-glissement
  rate-limite par `CUT_TOUCH_SNIP_INTERVAL` (0.3, cadence DELIBEREE, pas le plancher anti-triche 0.08 qui la rendait
  x12/s = trop vite).
- CURSEUR custom cache sur tactile (CursorController lit InputDevice).
- HOLOGRAMME "Taille %" : UIScale `HOLOGRAM_TOUCH_SCALE` (0.55) sur tactile (il etait en pixels fixes -> enorme).
- JUMP bloque pendant la taille (engage) : `SetStateEnabled(Jumping, false)`, rendu a la sortie. Cause du saut auto =
  `AutoJumpEnabled` vrai par defaut sur mobile (le perso saute des qu'il bute sur le bas de la haie).

CAMERA DE TRAVAIL (mobile)
- Depart plus DE FACE : `CAMERA_SIDE_TOUCH` (-5 vs -10 PC).
- ORBITE au doigt, geste CONTEXTUEL a un doigt : doigt SUR la haie -> taille ; doigt A COTE (ciel/sol) -> tourne la
  camera (`orbitTouch`, un raycast a la pose du doigt decide). Sensibilite `CAMERA_YAW_TOUCH_SENSITIVITY`.
- Orbite/suivi RAPIDES une fois la camera posee (`CAMERA_LERP_SPEED_WORK` 18 sous `CAMERA_SETTLE_DIST`), arrivee
  toujours DOUCE (`CAMERA_LERP_SPEED` 5) : le smooth du pivot etait stressant.
- Deplacement : le SENS suit la camera (`cameraSign` = signe de right.Dot(cam.RightVector)). Sans ca, camera pivotee
  de l'autre cote, "droite input" partait a gauche de l'ecran (inversion). L'axe reste celui de la haie (pas de diagonale).

REPERE DE COUPE (le cercle, PC + mobile)
- Remplace le cylindre procedural par le CLONE du template Studio `Assets.Effects.VisualRootTarget` (Part fine +
  SurfaceGui = cercle). Preserve les reglages non-scriptables (UIStroke ScaledSize). Config `VISUAL_CUT_TEMPLATE`.
- A PLAT sur la surface : la face du HAUT du slab (+Y, le cercle) suit la NORMALE. Face verticale -> plaque contre ;
  DESSUS -> a plat (on passe une normale verticale quand `onTop`). Reglait le bug "vertical sur le dessus".
- Taille reglable (`VISUAL_CUT_SIZE_SCALE` 0.55). Slab invisible (Transparency 1), seul le cercle se voit.
- SLIME : ressort amorti sur l'echelle. Jaillit de 0 a l'apparition, se PRESSE en coupe (`VISUAL_CUT_PRESS_SCALE`
  0.9), et POP a chaque coup (`VISUAL_CUT_CLICK_KICK`). Knobs `VISUAL_CUT_SLIME_STIFFNESS/DAMPING`.
- COULEUR selon la matiere : BLANC s'il reste a couper, ORANGE si nu. Approximation client : tailler sans mordre
  pendant `VISUAL_CUT_DRY_TIME` -> orange (marche pendant la coupe ; la visee seule reste blanche).
- Ancienne bille rose neon (cursorPart) rendue invisible (le cercle la remplace).

POSE UP/DOWN reactive PAR OUTIL (`poseFollowSpeed` dans ToolConfigs) : cisaille = 0 (aucun smooth, colle a la visee,
outil leger) ; taille-haie = 7 (smooth, le poids de la machine). `setPose` : 0 = snap, sinon ressort au critique.

ECRAN DE CHARGEMENT : le zoom de reveal finit maintenant TOUJOURS derriere le joueur (avant : parfois face a lui, car
il finissait sur la camera de jeu capturee, parfois heritee devant). On force le derriere via le LookVector, en gardant
la distance de la camera de jeu (Custom reprend au meme endroit, sans saut).

RESTE A FAIRE (mobile) : echelle (monter/descendre = W/S clavier, visee du dessus = souris, reposer/tourner = E/R),
equiper l'outil (touche 1) -> a passer en ContextActionService (bouton tactile auto). Voir la carte d'input dans la
session. A verifier aussi : le cercle "loin du curseur" (design : il est a la LAME, pas au curseur ; a retester).

## 0.0.122 — Retrait de l'effet de feuilles volantes (FlyDebrisTrail)

Retire entierement l'effet client "feuilles qui volent vers la zone de depot" (une trainee FlyDebrisTrail qui partait
de la lame et retombait en arc dans la bande de depot). Rendu juge insatisfaisant par le joueur, et pas la direction
voulue : on l'enleve avant d'aller plus loin plutot que de le trainer.

Supprime dans HedgeController : le type Flyer, flyTemplate, la liste flyers, les fonctions dropPoint / flyDebris /
stepFlyers, l'appel dans la boucle de coupe, le chargement du template et la connexion Heartbeat. Supprime dans
HedgeConfigs : FLY_ASSET, FLY_TIME, FLY_ARC, FLY_MAX, FLY_SPIN. Le tas au sol n'est PAS touche : il est pose par le
serveur (HedgeStockService), seul le visuel de trajet disparait. Zero reference restante, le reste de la coupe (contact,
visee, particules emitCut, secousse) est intact. L'asset Studio Assets.Contents.FlyDebrisTrail peut etre supprime a la
main, plus rien ne le lit.

## 0.0.121 — Feuillages qui encadrent l'ecran de chargement (test d'un effet)

Des feuillages cartoon (dessins du joueur) JAILLISSENT depuis les bords pour encadrer l'ecran de chargement, arrivent
en eventail (stagger + Back), puis flottent doucement. La position POSEE (dans la data) est la finale ; le depart est
CALCULE en la projetant vers l'exterieur du centre, donc chacun sort de son bon cote. Boucle de flottement coupee a la
sortie (avec les autres connexions, avant destruction) : rien ne tourne apres le fondu.

Fait INLINE dans LoadingScreenClient (le fichier reste AUTONOME : il tourne dans ReplicatedFirst, avant que le reste du
jeu soit replique, donc il ne require aucun module de ReplicatedStorage). Data + reglages (SPREAD, STAGGER, AMPLITUDE)
en tete du bloc ; pour deplacer / ajouter un feuillage, une ligne dans FOLIAGE_DATA.

C'est un TEST d'effet, pose sciemment comme habillage. L'idee vise a terme les vraies interfaces (Daily Rewards, Season
Pass...) : quand l'une existera, on ressortira une version reutilisable (elle, pourra require normalement). D'abord un
essai en situation, dans le seul ecran deja code.

## 0.0.120 — Le niveau se MERITE : courbe d'XP durcie (forme logarithme neperien)

Avant, on montait de niveau BEAUCOUP trop vite : le 1er niveau coutait 10 carreaux (LEVEL_BASE 100 / XP_PER_CELL 10),
donc une seule haie (150-300 carreaux taillables) faisait sauter 10-15 niveaux d'un coup. Le niveau ne voulait plus
rien dire.

Recalibrage dans ExperienceConfigs : LEVEL_BASE 100 -> 250, LEVEL_GROWTH 1.3 -> 1.4 (XP_PER_CELL reste a 10). Le cout
par niveau est exponentiel, ce qui donne un niveau(XP) en LOGARITHME NEPERIEN (niveau ~ 1 + ln(1 + XP / 625) / ln(1.4)) :
rapide au debut (euphorie du debutant preservee), ralentissement DOUX et continu ensuite, sans mur artificiel. En
travail reel : L1->2 = 25 carreaux, L5->6 = 96, L10->11 = 516, L20->21 = ~15000. Une premiere haie fait monter ~2-3
niveaux, puis chaque niveau se gagne. Deux boutons : LEVEL_BASE durcit le DEBUT, LEVEL_GROWTH durcit le HAUT niveau.
Runtime toujours (rien de sauvegarde) : on regle le ressenti avant de brancher la persistance.

Au passage, un oubli du combo (0.0.119) corrige : sa ScreenGui passe en ScreenInsets = None, OBLIGATOIRE avec
WorldAnchor. WorldToViewportPoint rend en coords viewport (origine au coin absolu de l'ecran) ; avec l'inset par
defaut, le compteur etait decale de ~36 px vers le bas. Le commentaire de WorldAnchor qui affirmait l'inverse est
corrige (et note au journal de CLAUDE.md). L'ecran de chargement (0.0.118) passe aussi en ScreenInsets = None (bord a
bord) : le legacy IgnoreGuiInset ne se traduisait plus en None dans les versions recentes (il restait en
DeviceSafeInsets, un bandeau non couvert en haut). On pose donc la propriete moderne directement.

## 0.0.119 — Combo de coupe : un compteur qui monte tant qu'on taille

Un petit compteur "xN" surmonte de la legende "COMBOS" (police Luckiest Guy) apparait a DROITE du joueur, vers le
corps, et monte a chaque carreau amene au ras : x1, x2, x3... a l'infini. Des qu'il ARRETE de tailler (rien d'amene au
ras pendant RESET_TIMEOUT), il retombe a zero. C'est un ENJEU au sens de CLAUDE.md : le joueur a quelque chose a PERDRE
en s'arretant, donc a gagner en enchainant.

Autorite SERVEUR (nouveau ComboService) : le compteur vit en memoire (runtime, rien de sauvegarde). Il se branche sur
le MEME signal honnete que l'XP, dans biteAt, quand un carreau est REELLEMENT amene au ras (pas quand on abime du vieux
bois, pas quand on brasse du vide). Point unique : taille-haie continu ET cisaille au clic passent par la. Deux
reglages dans ComboConfigs : MIN_INTERVAL (plancher entre deux montees, sinon le combo sauterait a x60 en une seconde,
illisible) et RESET_TIMEOUT (delai d'oubli). L'etat se replique par un simple attribut (LeafiaCombo) : pas de remote,
le client lit la valeur des qu'il est pret.

Client (nouveau ComboController) : interface construite EN CODE (pas de ScreenGui Studio a maintenir pour un petit
widget), accrochee au joueur via WorldAnchor en repere CAMERA (a droite de l'ecran, quel que soit l'angle). Le nombre
et la legende jaillissent a l'apparition, POPent ENSEMBLE a chaque montee (d'autant plus fort que le combo grimpe, via
un UIScale sur un Frame interne pour qu'ils ne se chevauchent pas), et se retirent en fondu quand ca retombe. Le nombre
"chauffe" en couleur : blanc, puis dore a partir de x10.

Purement VISUEL pour l'instant : aucun bonus (XP, argent) n'est encore branche dessus. Sa valeur restera limitee tant
qu'il ne recompense rien de concret ; c'est le prochain palier, une fois le ressenti valide. A REGLER a l'oeil :
RESET_TIMEOUT / MIN_INTERVAL (rythme), HEAD_OFFSET (hauteur), le palier de couleur.

## 0.0.118 — Refonte de l'ecran de chargement (look "jardin")

Reconstruit ENTIEREMENT en code (avant : monte dans Studio) d'apres la maquette : ciel en degrade + formes flottantes,
pelouse en bas avec un bord tondu en pointilles, badge hexagone (lueur qui vacille + entree slime) et mot LEAFIA au
centre, pilule d'etat + barre DOREE qui suit le VRAI chargement (collecte + preload mappes sur la barre, % reel), tip
jardinier qui defile, bas de page "LANDSCAPING TYCOON" + version. Tout est reglable par des constantes (couleurs,
polices via FontFace Luckiest Guy / Gotham, textes, tips). La logique eprouvee est conservee : prechargement asservi au
FPS, skip (Echap), masquage chat / liste joueurs, et le ZOOM DE REVEAL a la fin (plan large qui se resserre sur le
joueur, cale sur la camera de jeu pour ne pas sauter). L'ancien ecran Studio est lu (logo + version) puis remplace.
Duree : en Studio tout charge en un clin d'oeil, donc la barre sautait a 100% et l'ecran partait trop vite. Corrige
par MIN_DURATION (temps minimum a l'ecran depuis l'apparition, 6 s) ET une barre bornee par le temps ecoule : elle se
remplit sur MIN_DURATION au minimum au lieu de sauter, et suit le vrai chargement s'il est plus lent. Skip toujours
dispo. A REGLER : MIN_DURATION (si trop long / court) ; LOGO_FALLBACK si le badge n'est pas ton hexagone ; couleurs /
proportions a l'oeil.

## 0.0.117 — Quitter l'echelle ne re-agrippe plus au sol aussitot

Bug : en descendant de l'echelle, un instant ou la camera "bloque" (le joueur bouge, la vue ne suit pas). Cause reelle
(trouvee en tracant le serveur) : la base de l'echelle est dans la zone de detection d'une haie. Sur l'echelle, le
serveur force LeafiaAtHedge = false ; mais des qu'on quitte (onLadder efface), updatePlayer reevalue et RE-ENGAGE tout
le systeme sol d'un coup -> aimant qui tire + orientation forcee + camera iso, pile quand le joueur veut s'en aller.
Fix : a la sortie d'echelle, le serveur pose le meme temps mort qu'une sortie volontaire (exitUntil = LADDER_EXIT_GRACE,
0.9 s) -> le sol ne raccroche qu'apres, le joueur descend avec sa camera NORMALE et a le temps de s'eloigner. Aucun code
camera ajoute : on empeche juste le systeme sol de mordre au mauvais moment. LADDER_EXIT_GRACE est le knob (a monter si
la base des echelles est plus pres des haies). NB : si un blocage subsiste, c'est l'AUTRE cause (le HRP ancre pendant la
grimpe, la grimpe fausse) et il faudra le vrai fix (faire monter le perso pour de vrai).

## 0.0.116 — Retour DOUX de la camera en quittant une haie (au sol)

Au sol, quitter une haie (S / on recule) rendait la main a la camera de jeu D'UN COUP : un cut sec, desagreable.
Desormais la camera GLISSE de la vue iso vers la camera normale sur RELEASE_TIME (0.55 s, ease out), en SUIVANT le
joueur qui recule. Meme technique eprouvee que la sortie d'echelle : a l'ENGAGE on capture, via camera.Focus, l'etat
EXACT ou la cam de jeu reprendra (focus offset / HRP + offset camera = angle + zoom) ; a la sortie on ease l'offset de
la vue iso vers cet etat, ancre sur le HRP VIVANT (donc ca suit), puis Custom reprend PILE la -> aucun saut, aucun
trou. Un retour deja en cours est coupe si on se raccroche a une haie (re-engage). UNIQUEMENT le retour AU SOL : cote
echelle rien n'est touche. L'ENTREE (accroche) etait deja lissee par la boucle de travail, on n'y touche pas.
RELEASE_TIME est le knob (monter = plus lent / plus doux).

## 0.0.115 — La camera MONTE avec la grimpe (sans reprendre la camera)

Suite directe de 0.0.114 : comme le HRP reste ancre en bas pendant la grimpe (c'est l'anim UpDownAnimation qui monte le
corps), avec la camera normale le perso grimpait hors du cadre. Corrige via Humanoid.CameraOffset : on monte le POINT
VISE de la camera proportionnellement a la progression de la grimpe (climb.TimePosition / climb.Length) -> 0 au sol,
CLIMB_CAM_RISE en haut, et la descente est suivie aussi. La camera du joueur GARDE son angle et son zoom : on ne touche
QUE le point vise, le joueur reste maitre de sa vue (pas de reprise de camera). Remis a 0 hors grimpe (ready / exiting)
et a la sortie (dismount, sinon l'offset resterait fige en haut). CLIMB_CAM_RISE (6 par defaut) est a REGLER a l'oeil
pour bien cadrer le perso qui grimpe.

## 0.0.114 — L'echelle garde la camera NORMALE du joueur (plus de vue iso)

Choix de design : sur l'echelle, on ne bascule PLUS sur la camera iso de travail. Le joueur garde SA camera de jeu
(son angle, son zoom), comme il l'a reglee, pendant toute l'interaction (montee, sommet, sortie). UNIQUEMENT pour
l'echelle : la camera de travail AU SOL (HedgeController, autre fichier) n'est pas touchee.

Retire de LadderController (~230 lignes) : la bascule iso, l'orbite clic-droit + le zoom molette, l'entree en douceur,
ET tout le glissement de sortie de 0.0.113 (il n'a plus lieu d'etre puisqu'on ne quitte jamais la camera du joueur).
Detail : constantes CAM_*, etat (camTracking, camSubject, camOutward, orbit, exit-glide), boucle LadderCamAim, inputs
clic-droit / molette, fonctions getTrackPoint / outwardSide / stepCameraExit. La visee du DESSUS (topAim) est
CONSERVEE : elle n'utilisait deja pas la camera iso (elle projette le curseur via la camera COURANTE, quelle qu'elle
soit, et mesure sur l'axe de l'ECRAN) ; le vieux commentaire qui pretendait que topAim se servait de camOutward etait
faux (camOutward n'etait plus lu nulle part, l'IDE le signalait).

A TESTER : la taille du DESSUS depuis l'echelle. Le rayon du curseur doit DESCENDRE sur le plan du dessus, donc il
faut regarder la haie vers le bas ; avec la camera normale c'est au joueur d'orienter sa vue (sur un escabeau court ca
tombe naturel). Note : le HRP reste ancre en bas pendant la grimpe (c'est l'anim qui monte le corps), donc le perso
monte un peu dans le cadre.

## 0.0.113 — Quitter l'echelle : glissement DOUX qui suit le joueur

A la sortie de l'echelle, la camera PIVOTAIT derriere le joueur (calcul depuis l'orientation du JOUEUR) : ca reframait
la vue a chaque sortie. Corrige en trois passes : (1) garder l'angle qu'on avait ; (2) un tween vers ce cadrage, mais
comme il visait un point FIXE, la camera restait plantee ~0.2 s pendant que le joueur s'en allait (aucune camera qui
suit, moche) ; (3) remplace par un GLISSEMENT image par image qui SUIT le joueur (stepCameraExit dans la boucle camera,
drapeau camExiting). Chaque frame : le point vise = HRP du joueur (donc ca suit), et on ease l'offset de la vue echelle
vers la vue de jeu. La CIBLE est l'etat EXACT ou la cam de jeu reprend, capture a l'accroche via camera.Focus : point
vise (savedFocusOffset = Focus - HRP, ~tete) et zoom (savedCamDist = distance camera -> Focus, le VRAI zoom, pas la
distance au HRP), dans la direction courante (angle garde). Depart = vue echelle EXACTE (aucun pop), fin = PILE l'etat
de la cam de jeu -> Custom reprend sans le moindre saut. (4e passe : une cible approximee -- hauteur du regard devinee a
1.5, distance mesuree au HRP -- laissait un micro-saut de ~0.05 s au relais, visible et stressant ; caler focus + zoom
sur camera.Focus le supprime.) Plus aucun trou "sans camera" non plus. Duree CAM_TWEEN_OUT (0.35 s, ease out).
Nettoyage : plus de TweenService ni de camTween dans ce module. camExiting coupe au respawn et a une nouvelle accroche.

## 0.0.112 — La montee a l'echelle coule sans point d'arret

Friction viree. Au pied de l'echelle (box_detecte_A), il fallait RELACHER la touche avant puis la RAPPUYER pour passer
de l'idle (IdleDownAnimation) a la grimpe (UpDownAnimation). Un mecanisme d'armement (climbArmed) ignorait la touche
avant tant qu'elle n'avait pas ete relachee une fois depuis l'accroche. Retire : touche avant maintenue = on enchaine
tout seul, ca coule sans point d'arret. MAIS l'anim d'accroche (IdleDownAnimation, ~1 s) se joue toujours EN ENTIER,
de 0 a sa fin, AVANT la grimpe (garde idleDone) : sans ca, la touche tenue des la 1re frame la coupait a ~0 s et on ne
la voyait plus. Une fois l'accroche jouee, touche tenue = grimpe direct. Le raccrochage juste apres une sortie en bas
reste empeche par canMount (il faut quitter la zone une fois avant de se raccrocher) : pas de rebond au pied. La
descente (S) et la sortie ne dependaient pas de l'armement, pas touchees.

## 0.0.111 — Les notifs laterales se ferment toutes seules (compte a rebours)

On avait oublie l'auto-fermeture : les notifs restaient a l'ecran indefiniment. Chaque notif a maintenant une duree de
vie (LIFETIME, 6 s par defaut, surchargeable par notif via NotifData.duration) au bout de laquelle elle se replie
seule. Le temps restant s'affiche dans CooldownClearNotification, un compte a rebours ("6.4s" -> "0.0s") pilote par la
meme boucle Heartbeat que le degrade des gains (une seule boucle globale). Le rebours est visible dans les DEUX
etats : place + couleur differentes (blanc 255,255,255 ouvert, gris 184,184,184 ferme), anime avec le meme tween que
les autres enfants a l'ouverture / fermeture. Nettoyage centralise dans un dismiss() idempotent (drapeau Dismissed) :
le retrait par minuteur et le retrait par plafond MAX_VISIBLE passent par le meme chemin, plus de double repli
possible. Note : le rebours ne se met PAS en pause a l'ouverture (il tourne meme notif ouverte, comme le montre son
affichage dans cet etat) ; a changer en une ligne si on veut qu'ouvrir laisse le temps de lire.

## 0.0.110 — Le level up declenche une vraie notification

Premier VRAI declencheur du systeme de notifs laterales : quand le joueur monte de niveau (en taillant des haies),
ExperienceService envoie une notif via un nouveau remote SideNotify (serveur -> client, dans RemoteSetup). Le
SideNotificationHandler l'ecoute et spawn la notif (kind Success, titre "NIVEAU X", message motivant). Le joueur
taille donc il est spawne, il ecoute : envoi sur. Le generateur de TEST (les 4 notifs d'exemple + la boucle) est
retire : les notifs viennent maintenant d'evenements reels. spawn(data) reste public pour tester a la main depuis la
barre de commandes. (Le "+X point de competence" en gain n'est pas encore mis : il viendra quand le systeme de
points de competence existera.)

## 0.0.109 — Fiabilite : les UI se trouvent meme quand le spawn tarde

Bug de timing intermittent : les ScreenGui de StarterGui ne sont copiees dans PlayerGui qu'au SPAWN du perso, qui
peut tarder (chargement des donnees ProfileStore, ~10 s+). Les controllers cherchaient leur UI au boot avec un
WaitForChild de 10 s qui expirait avant -> "ExperiencesUI introuvable", "NotificationUI introuvable", et la jauge
d'XP ne se branchait pas (une session sur deux, selon la vitesse du spawn).

Fix : ExperiencesController, SideNotificationHandler et Toast attendent maintenant le PERSO (CharacterAdded) AVANT de
chercher leur UI, en tache de fond (task.spawn, pas de blocage du boot). Le Toast se rattrapait deja tout seul (il
re-resout a chaque show), c'etait juste un faux warning au demarrage. A FAIRE cote Studio : passer ResetOnSpawn a
false sur ExperiencesUI et NotificationUI, sinon elles sont recreees a chaque respawn et les references se perdent.

## 0.0.108 — Notifications laterales : anim d'ouverture / fermeture (step 1)

Debut d'un systeme de notifications en bas a droite (NotificationUI, faite en Studio). Step 1 : chaque notification
s'OUVRE / se FERME au clic (SelectButton) avec une anim CONJOINTE de la taille (fermee {0.982, 0.076} <-> ouverte
{0.982, 0.356}), de l'arrondi (UICorner 0.2 <-> 0.08) et du contour (UIStroke 0.03 <-> 0.01) : sinon les coins et le
contour seraient disproportionnes sur la grande frame. Nouveau SideNotificationHandler : le template (range dans
NotificationUI.Templates, un blueprint) est CLONE dans HolderList via spawn(), et cable (fermee + clic). Quelques
notifs de test sont spawnees au demarrage (temporaire) pour voir le rendu et le reflow de la liste. Le vrai
declencheur (evenement) + le slide-in d'entree viendront ensuite, par-dessus spawn() / apply(). Note : contour a
0.03 / 0.01 px = quasi invisible, a remonter si besoin.

Ouverture / fermeture passees en RAPIDE + rebond slime (Back Out, 0.22 s). Ajout d'un effet de SURVOL : la notif
grossit d'un poil avec un mini rebond, retour au depart a la sortie ; et le degrade du contour (UIGradientRotate)
fait UN tour complet a chaque survol (0 -> 360, one-shot, LENT : 0.8 s, ease in / out). Ce tour ne se voit que si le
UIStroke est assez epais (contour actuel 0.03 / 0.01 = tres fin).

PILE qui MONTE : les nouvelles notifs arrivent EN BAS, les autres remontent (UIListLayout passe en VerticalAlignment
Bottom + LayoutOrder croissant). Au-dela de MAX_VISIBLE, la plus VIEILLE (en haut) se REPLIE en Y (hauteur -> 0, par
le bas grace a l'AnchorPoint 0.5,1) et disparait ; la liste se compacte. Un generateur infini (TEMPORAIRE) remplit la
pile ; le vrai declencheur appellera spawn(). Chaque effet sur SA propriete, sans conflit : ENTREE en LARGEUR (Size X,
0 -> pleine, la notif se deplie horizontalement, le UIListLayout gere la position), RETRAIT + ouverture-fermeture sur
la Size en Y, survol sur un UIScale, tour du degrade sur la Rotation du gradient.
(Le retrecissement progressif de toutes les notifs, teste avant, a ete abandonne : juste le repli de la plus vieille.)
L'Image (icone) ET le texte (NameNotificationType) suivent l'etat (Position + Size tweenes avec le reste) : l'icone
petite en haut-droite quand ouvert / plus grande a droite quand ferme ; le texte reduit + descendu quand ferme. Les
deux passent par un helper moveChild commun. L'icone a besoin de sa contrainte d'aspect en FitWithinMaxSize (sinon
ScaleWithParentSize ignore la Size et le resize ne se voit pas). Valeurs de largeur arrondies (0.982 -> 0.98).
COULEUR par TYPE (comme les toasts) : spawn(kind) teinte le degrade de fond (UIGradientNotificationColor, de la
couleur vers une version sombre) + le contour, selon NOTIF_COLORS (Info / Success / Warning / Reward). Le generateur
de test pioche un type au hasard pour montrer les couleurs.
OUVERTURE = DETAILS : DescriptionText (long texte) et AdditionalEarnText (+X points de competence)
apparaissent quand la notif est ouverte (caches a taille 0 quand fermee, ils grandissent sur place a l'ouverture,
via le meme helper moveChild). Le degrade de l'AdditionalEarnText DEFILE en boucle entre quelques couleurs
(palette RAINBOW cyclee sur un seul Heartbeat global, no-op quand aucune notif).
Contenu DATA-DRIVEN : spawn(data) prend { kind, title, description, earn } et remplit NameNotificationType (le titre),
DescriptionText (le texte) et AdditionalEarnText (`earn` = ce qui a ete GAGNE, texte libre : points de competence,
tunes / pourboire...). Le vrai declencheur passera ces donnees ; le test envoie 4 notifs d'exemple (niveau, recompense
avec pourboire, astuce, avertissement). Champ `icon` en plus : pour une recompense en monnaie, le code GENERE un
ImageLabel (IconCurrency, carre) a droite du gain et decale le texte a gauche pour lui faire la place ; sans icone,
le texte garde la pleine largeur. Positions reglables dans le handler. Et le montant en monnaie DEFILE de +0 a sa
valeur A L'OUVERTURE (champ `amount` : compteur tweene, effet satisfaisant, format abrege via FormatUtils : +12.75K,
+10.42B...) ; `earn` (texte) reste pour les gains non chiffres (points de competence). Le helper d'icone est
generalise (addIcon nom + position) : en plus de IconCurrency, une IconWarning s'affiche sur les notifs de type
Warning. Extensible a d'autres icones de type.

## 0.0.106 — Jauge d'experience qui suit le joueur (1re brique de la progression)

Debut du systeme d'experience (vers l'arbre de competences). La jauge ExperiencesUI (faite en Studio) SUIT le joueur
AU-DESSUS de sa tete et grossit / retrecit avec la distance camera. Elle n'APPARAIT que quand le joueur est a une
haie (attribut serveur LeafiaAtHedge) avec une anim SLIME : elle sort du milieu de la tete en grossissant + montant
jusqu'a sa place (rebond Elastic), et se retire pareil a l'inverse. Trois affichages pilotes par le serveur : la
barre (SlideBar) se remplit selon XpFill (0-1, avec un fondu), le texte LevelDataCompetenceText montre XpLevel, et le
degrade UIGradientRotate tourne, UNIQUEMENT tant que la jauge est affichee (coupe hors ecran / cachee).

Pas encore d'XP reelle : le serveur (ExperienceService) qui lit Skills.Trimming (deja dans le DataTemplate : Xp +
Level par competence) et pose XpFill / XpLevel vient apres. Pour tester tout de suite dans la barre de commandes :
`game.Players.<toi>:SetAttribute("XpFill", 0.6)` et `:SetAttribute("XpLevel", 3)` (et s'approcher d'une haie pour
declencher l'apparition).

WorldAnchor gagne : un scale { ref, min, max } (grossissement billboard-like, taille ~ 1/distance, bornee, via un
UIScale cree a la demande), un offset repere CAMERA (reste du meme cote de l'ecran quand on tourne), et setOffset /
setScaleMul (bouger le point vise + multiplier la taille en direct, pour animer une apparition / disparition).

## 0.0.105 — Plus de son de marche

Le joueur ne veut aucun son de pas. On retire GroundStepSound (le son de foulee custom ajoute plus tot). On GARDE le
mute du son "Running" par defaut de Roblox, sinon il reviendrait : resultat, silence au sol. FootstepController ne
fait plus que couper le defaut, et reste le point unique ou rebrancher un son de pas plus tard si besoin.

## 0.0.104 — La cisaille sonne a CHAQUE clic (LeafCutSound)

Le son de coupe (LeafCutSound) sautait des clics de cisaille. Cause : playCut bornait le rythme des sons
(CUT_SOUND_INTERVAL), un garde-fou pense pour la coupe CONTINUE du taille-haie. La cisaille coupe au CLIC (jusqu'a
~12/s via l'anti-spam serveur) : deux clics rapproches tombaient dans l'intervalle et n'en jouaient qu'un seul.

Fix : le clic-par-clic (heldPerClick) contourne cette borne -> chaque clic qui mord une haie joue son son. Le
taille-haie garde le garde-fou (sa coupe continue empilerait trop de sons sinon). Le son ne joue toujours QUE si le
clic coupe reellement des feuilles (viser du vide ou du deja-taille ne sonne pas).

## 0.0.103 — La cisaille a son propre geste de coupe du dessus (RightLeftAnimation)

La cisaille a maintenant sa RightLeftAnimation (pose des bras pour tailler un DESSUS), differente de celle du
taille-haie (l'outil se tient autrement). Deux contextes la jouent, les deux passent maintenant par l'outil equipe :

- Au SOL (viser un dessus horizontal) : deja automatique. La resolution de pose (resolvePosePath) prend d'abord le
  dossier de l'outil equipe. Des que la cisaille a l'anim dans son dossier, elle l'utilise, sans code.
- Depuis l'ECHELLE (tailler le dessus, en haut) : etait code en dur sur le taille-haie. Desormais la pose est
  chargee (ensureTrimTrack) selon l'outil equipe, lu a la PRISE de l'echelle (avant qu'il soit range pour la
  montee). Rechargee si on change d'outil. Retombe sur le taille-haie si un outil n'a pas cette pose.

## 0.0.102 — L'echelle revient TOUJOURS droite devant le joueur a la prise

A la prise (E) pour la deplacer, l'echelle partait de travers : la 1re prise etait nickel, mais apres l'avoir
reposee dans une orientation quelconque, la reprise la laissait de travers, pas droite devant le joueur.

Deux causes empilees, corrigees :

1. Le portage se calait sur `ladder:GetPivot()`, qui suit la BOUNDING BOX du model. Les zones de detection generees
   (box_detecte_For_Move, soudees a la racine, decalees sur les cotes + au sol) decalaient et desorientaient cette
   bounding box -> l'echelle partait carrement de travers. On se base desormais sur la ROOTPART, une part reelle
   et fixe que les zones ne touchent pas.

2. On voulait a tort GARDER le sens de repose. Le vrai besoin : l'echelle doit revenir droite devant le joueur a
   CHAQUE prise, comme la 1re fois, peu importe comment elle a ete reposee. On CAPTURE donc l'offset de portage UNE
   SEULE FOIS (1re prise, echelle droite) et on le REUTILISE : meme offset relatif au porteur a chaque prise ->
   toujours droite devant. Yaw seul (tangage / roulis a zero) pour rester droite. R (rotation 180 volontaire)
   fonctionne toujours par-dessus.

3. A la prise, on choisit le SENS (flip 0 ou 180 autour de la verticale) le plus proche de comment l'echelle est
   PLANTEE. Elle reste droite devant, mais ne fait plus de demi-tour brusque de 180 dans les mains quand on la
   prend du cote ou elle nous fait deja face.

## 0.0.101 — La montee sur l'echelle se voit DROITE chez les autres (co-op)

En co-op, un joueur qui grimpe se voyait parfaitement chez LUI (face a l'echelle, main dessus) mais les AUTRES
le voyaient de travers (a son orientation d'avant la montee), parfois carrement a cote de l'echelle.

**Cause.** Le client ANCRAIT son HRP et le posait face a l'echelle EN LOCAL. Ancrer + poser sa propre part ne se
replique pas : les autres restaient sur la derniere position repliquee (le pas d'approche, de travers). Meme
famille que le portage de l'echelle (regle par un weld serveur).

**Fix.** L'ancrage + la pose passent COTE SERVEUR. Nouveau remote `Ladder/SetLadderClimb` : a la montee, le client
envoie l'echelle + le CFrame de montage ; le serveur (`LadderMoveService.climbMount`) ancre le HRP et le tween a
ce CFrame -> ca se replique a TOUS. A la descente, il desancre. Le serveur valide (vraie echelle, montage pres de
l'echelle). L'anim de grimpe (jouee par le client) se replique deja par-dessus. Cote client : l'aimant local
(lerp de root.CFrame) est retire, le serveur s'en charge ; le root reste ancre en local pour un freeze immediat.

## 0.0.100 — Plus de marche parasite sur l'echelle + son de pas au sol

Deux corrections autour de la MARCHE.

- **Aucune anim par defaut sur l'echelle.** Le garde-fou qui coupe les anims Roblox par defaut (idle / marche /
  course, sous priorite Action) ne tournait qu'en grimpe/sommet, PAS en phase "ready" au pied de l'echelle : les
  membres non-cles (le bras gauche) y "marchaient dans le vide". Il tourne maintenant dans TOUTES les phases des
  qu'on est sur l'echelle. Les membres qu'aucune piste d'echelle ne cle restent a leur pose de repos.
- **Son de pas au sol.** Nouveau `FootstepController` : coupe le "vieux" son de marche par defaut de Roblox
  (volume du son "Running" a 0) et joue `GroundStepSound` (SoundService.Sounds.Environnement.FootSteps) tous les
  `STEP_LENGTH` studs REELLEMENT parcourus au sol. En l'air ou sur l'echelle (perso ancre, distance nulle), rien.
- **Outil range pendant la grimpe.** L'anim de grimpe cle desormais tous les membres (mains comprises) : un outil
  dans la main flaillerait. Le serveur (`HedgeService.syncLadderTool`) DESEQUIPE l'outil en montant et le REND en
  haut (pour tailler) et a la sortie, en memorisant son nom. Fait cote serveur -> vu par tous. L'auto-equip du
  taille-haie est bloque sur l'echelle (attribut client `LeafiaOnLadder`) pour ne pas se battre avec ce rangement.
  NOTE : le re-equip remet l'outil a zero (nickel pour la cisaille, prete a l'equip ; le taille-haie perdrait son
  moteur en haut -> a revoir si on veut le garder allume la-haut).
- **Plus besoin d'un outil pour monter.** L'ancienne condition "taille-haie obligatoire pour monter" + le toast
  "Equipe ton taille-haie pour monter" sont supprimes. On monte les mains vides ; si on avait un outil, il est
  rendu en haut pour tailler (sinon on monte juste, sans tailler).

## 0.0.99 — Prompt d'interaction "[E] PRENDRE" (module reutilisable)

Nouveau module UI `Modules/UI/Core/InteractionPrompt` : un badge "[touche] LIBELLE" qui flotte au-dessus d'un
objet quand une action est possible. Reutilisable (E, F, ...), construit EN CODE (pas de template Studio), il
SUIT sa cible a l'ecran via `WorldAnchor` (ScreenGui projete : pixels constants, lisible a toute distance).

- API : `InteractionPrompt.show(target, key, label, offset, onActivate)` / `.hide()`. Un seul prompt a la fois.
- APPARITION "slime" : le prompt part de 0 et rebondit en Elastic (overshoot + oscillations amorties), avec le
  son `SoundService.Sounds.UI.PopSound_1` (clone via SoundUtils). Disparition : un pop-out court.
- MOBILE (tactile sans clavier) : pas de touche a afficher -> le badge est cache, le prompt devient un BOUTON a
  taper. `onActivate` gere le tap (et le clic, partout, en bonus) ; au clavier c'est la feature qui ecoute sa
  touche, le prompt n'est qu'un indicateur. Responsive via UIScale sur la hauteur d'ecran.
- Branche sur l'echelle (`LadderMoveController`) : quand on entre dans une zone de prise (et qu'on ne porte pas),
  "[E] PRENDRE" s'affiche au-dessus de l'echelle ; il disparait en sortant. Le tap mobile prend l'echelle.
- Perf : la detection de zone tourne desormais EN CONTINU (throttle 0.2 s), donc `ladderAt` passe par un CACHE
  des echelles (invalide a l'ajout / retrait d'une echelle) au lieu de balayer tous les descendants du workspace.

## 0.0.98 — Zones de detection de l'echelle generees par code (2 cotes lateraux)

La zone "prise d'echelle" (`box_detecte_For_Move`) etait posee a la main dans Studio, sur UN seul cote. Nouveau
service `LadderZoneService` (serveur) qui GENERE deux box, sur les cotes LATERAUX (gauche / droite) de chaque
echelle. Cote serveur -> repliquees, detectees et vues par tous (co-op). Construit en step-by-step : ici juste
les deux box (visibles pour valider le placement) ; le marquage au sol (attachments + beams) et l'invisibilite
viendront ensuite.

- Chaque box est soudee a la RootPart (WeldConstraint) : elle suit l'echelle au portage / a la repose, sans
  tomber. Placee le long de l'axe X local (lateral), a `LATERAL_OFFSET` de chaque cote.
- La HAUTEUR n'est pas devinee : un raycast vers le bas trouve le vrai SOL sous chaque zone et l'y pose a plat
  (au 1er jet, une hauteur en dur envoyait les box sous la map).
- Detection (`LadderMoveController.ladderAt`) : cherche les zones par PREFIXE `box_detecte_For_Move`, donc les
  deux (`_A` / `_B`) comptent. E prend l'echelle depuis l'un OU l'autre cote.
- A FAIRE cote Studio : SUPPRIMER la box `box_detecte_For_Move` posee a la main (sinon elle s'ajoute aux generees).

## 0.0.97 — Sons de l'echelle (prise, repose, pas de montee)

Du son pour la satisfaction. Sons ranges dans `SoundService.Sounds.Engins.Ladder`, CLONES au declenchement
(volume / pitch se reglent donc dans Studio, pas en code).

- **Prise / repose** : `LadderTakeSound` a la prise (E), `LadderDeposeSound` a la repose. Le cablage existait
  deja (`playLadderSound`) mais pointait sur un SoundId vide ; il clone maintenant le Sound par NOM.
- **Pas de montee** : un pas tous les X de PROGRESSION de la grimpe (montee ET descente), qui tire
  `LadderClimbStepOne` / `LadderClimbStepTwo` AU HASARD. Base sur la progression et non sur des marqueurs d'anim
  (fragiles : nom exact + ne tirent pas fiablement sur une anim pilotee a la main) -> se declenche a coup sur.
  Reglable : `CLIMB_STEP_COUNT` (~ nombre de marches).
- Nouveau module partage `Modules/Utils/SoundUtils` : `SoundUtils.play(chemin, host)` clone un Sound de
  SoundService et le joue (spatial si un host est donne), avec nettoyage Debris. Utilise par les deux controllers
  d'echelle ; reutilisable ailleurs.

## 0.0.96 — Tourner l'echelle portee (R)

En portant l'echelle, la touche **R** la fait pivoter de 180 degres (pour l'aborder ou la poser dans l'autre
sens). Toggle : R rebascule a l'orientation de depart.

- Cote SERVEUR (`LadderMoveService`) : l'echelle est soudee au HRP (weld). Un nouveau cas `"rotate"` tween le
  `C0` du weld entre l'orientation de base (`baseC0`, memorisee a la prise) et une rotation de 180 degres autour
  de la verticale. Comme le weld est serveur, la rotation se REPLIQUE a tous (co-op). Le tween est annule a la
  repose / mort, et a chaque nouveau R (on repart de la position courante, sans a-coup). Pas d'accumulation :
  on repart toujours de `baseC0`, donc pas de derive.
- Cote CLIENT (`LadderMoveController`) : R (en portant seulement) joue `RotateLadderAnimation` sur le PERSO
  (geste de main), en Action3 par-dessus la pose de portage (Action2). La rotation est demandee au serveur AU
  MARQUEUR `RotateAnimEvent` (l'echelle tourne pile quand la main la tourne), avec un secours a l'arret de la
  piste si le marqueur ne tire pas (1re lecture, asset pas charge). Anti-spam a la duree du tween.
- Axe de rotation reglable dans `LadderMoveService` (`ROTATE_FLIP`) si l'echelle tourne autour du mauvais axe.

## 0.0.95 — Le repere de coupe devient un disque plaque, plus une masse blanche

L'ancien repere de zone de coupe (`HedgeCutZoneDebug`) etait un cylindre-capsule en Neon + Highlight
always-on-top, dessine le long de la lame. Avec la cisaille (lame qui pointe vers la haie), il faisait face a la
camera : une grosse masse blanche qui bouffait la vue et empechait de voir ce qu'on taille.

Remplace par un `VisualCutCylinder` : un disque FIN et translucide (transparence 0.8), plaque a plat CONTRE la
surface visee (son axe suit la normale de la haie), pose juste sur les feuilles. Materiau SmoothPlastic (le Neon
rebrillait meme transparent), plus de Highlight always-on-top. Le disque garde les trois etats (guide / coupe /
hors haie) par couleur + transparence, et son diametre couvre la coupe (longueur de lame + largeur taillee).

Concerne LES DEUX outils (meme code de repere). Sur l'echelle (coupe du dessus), le disque se pose a plat sur le
haut de la haie (normale = verticale).

## 0.0.94 — La cisaille coupe CLIC-PAR-CLIC, avec sa propre gestuelle

La cisaille est l'outil de DEPART (avant l'achat du taille-haie). Elle taillait deja, mais en reprenant tout
du taille-haie : meme pose de bras, et coupe en maintenu. Deux corrections pour qu'elle SOIT un autre outil.

**Pose de hauteur propre a l'outil.** La pose up/down (les bras qui montent avec la visee) etait chargee depuis
un chemin fige (`HedgeTrimmer/UpDownAnimation`), donc la cisaille prenait la pose du taille-haie. Elle se charge
maintenant depuis le dossier de l'outil TENU (`Shear/UpDownAnimation` pour la cisaille), et se recharge au
changement d'outil. Un outil qui n'a pas telle pose (la cisaille n'a pas de pose du DESSUS) retombe sur celle du
taille-haie, sans warn. Cote code : `HedgeController` lit l'outil tenu (attribut `LeafiaTool` + `ToolConfigs`)
et ne charge plus les poses en dur.

**Coupe clic-par-clic.** Le taille-haie coupe en CONTINU tant qu'on maintient la gachette. La cisaille, elle,
coupe un COUP par clic, et ses LAMES claquent a chaque clic. C'est ca la difference d'outil : l'un ronronne,
l'autre claque coup par coup.

- Nouveau champ config `cutPerClick` (nombre) : nil = maintenu (taille-haie), un nombre = clic-par-clic ET
  taille de la bouchee retiree par clic. Cisaille = 0.4 (a regler pour la sensation "outil de merde").
- Nouveau remote `Hedge/CutSnip` : le client dit "j'ai clique", le serveur decide (outil clic-par-clic ? pret ?
  en contact ? portee ?) et applique une bouchee fixe. Anti-spam borne cote serveur (12 clics/s max).
- `cutWith` ne calcule plus la coupe depuis le temps : il recoit un montant. La boucle continue lui passe
  `taux * dt`, le clic une bouchee fixe. Meme geometrie, deux cadences.
- `setThrottle` ignore les outils clic-par-clic : pas de gachette maintenue, donc pas de camera qui se resserre
  a chaque clic.

**Le geste des lames.** `CutLamesAnimation` anime le MODEL de la cisaille (les lames Lame / LameB), PAS les bras
du joueur : c'est le meme principe que les lames du taille-haie. Elle se charge donc sur l'animator du MODEL
(nouveau champ config `cutAnimation` + `toolRunAnimations`) et se joue une fois par clic, cote SERVEUR
(`ToolService.playToolAnimationOnce`) -> elle se replique a tous, comme le repli de l'echelle. Le taille-haie n'a
pas de `cutAnimation` : ses lames TOURNENT en continu, elles ne claquent pas.

Pose de bras : la cisaille garde sa pose de hauteur (`Shear/UpDownAnimation`) et son idle (`IdleAnimation`) sur
le PERSO, comme avant. Les lames (model) et les bras (perso) sont deux animateurs distincts.

## 0.0.93 — Le repli / depli de l'echelle se voit aussi en co-op

Suite du 0.0.92. La POSITION de l'echelle se repliquait (weld), mais son REPLI / DEPLI restait invisible aux
autres : joueur1 prend l'echelle, joueur2 ne la voit pas se replier.

**Cause.** L'anim `ActionLadderAnimation` etait jouee par le CLIENT sur l'Animator de l'echelle. Une anim jouee
par un client sur un objet qui n'est pas SON perso ne se replique pas aux autres.

**Fix.** On la joue cote SERVEUR (comme un NPC) : le client ne fait plus que DECLENCHER par phase via le remote
`SetLadderCarry` :

- `"grab"` (prise) : soude l'echelle au HRP + CHARGE la piste de repli (sans la jouer).
- `"close"` (marqueur `TakeLadderEvent`) : le serveur joue le repli, fige a `FermerEvenement`.
- `"place"` (repose) : retire le weld, re-ancre sur place, joue le depli (jusqu'a `LadderOpenEndEvent`).
- `"release"` (mort / depart) : retire le weld sans depli.

C'est possible SANS conflit maintenant parce que le weld gere deja la position : le repli serveur ne se bat
plus contre une prediction client (c'est ce qui echouait avant le weld, cf 0.0.92).

Cote client : tout le repli local (`foldTracks`, `getModelAnimator`, le pin de repose) est SUPPRIME. Le client
ne fait plus que le rail JOUEUR, les anims JOUEUR, et le declenchement serveur.

### Le bug de la PREMIERE prise, et sa parade

A la toute premiere prise d'une session, le repli jouait EN ENTIER au lieu de se figer a `FermerEvenement`.

**Cause.** L'asset de l'anim n'est pas encore charge cote serveur a la premiere lecture : ses MARQUEURS ne
tirent pas pour cette lecture-la. Les fois d'apres, l'asset est en cache, donc ca marche. Symptome classique
et trompeur : "ca marche sauf la premiere fois".

**Deux parades.**

1. `ContentProvider:PreloadAsync` de l'anim au demarrage du serveur (dans un thread a part, PreloadAsync yield).
2. La piste est chargee des la PRISE (`"grab"`), pas au moment du repli : elle a ~0.23 s pour etre prete avant
   le `"close"`.

### Piege a retenir

**Un marqueur d'animation ne tire pas sur une piste dont l'asset n'est pas encore charge.** Precharger cote
serveur (pas seulement client) ce dont on lit les marqueurs, ou charger la piste EN AVANCE du moment ou on
compte sur elle. Meme famille que 0.0.41 (les sons manquaient au premier jeu faute d'etre dans la collecte de
prechargement).

## 0.0.92 — L'echelle se DEPLACE, et les autres la voient (co-op)

Le joueur prend l'escabeau (E dans `box_detecte_For_Move`), le porte le long de la haie, et le repose ou il
veut. `Client/LadderMoveController.luau` + `Server/LadderMoveService.luau`. Ecart assume avec la regle d'or
(habillage avant validation du geste) : pose, ne pas etendre.

### Le portage cote porteur (client)

- **Rail comme la taille.** En portage FOCUS, le joueur glisse le long de la haie a distance constante, face a
  elle. La normale de travail est la VRAIE (point le plus proche de la boite -> arc de cercle aux coins,
  gratuit), pas une face discrete qu'on lisse : le lieu a distance constante d'une boite EST un rectangle a
  coins arrondis.
- **Deux modes** : FOCUS (rail) et LIBRE (detache, on pose ou on veut). S pousse au detachement ; on re-focus
  en revenant pres d'une haie (garde de temps, pas de distance, pour re-accrocher de n'importe quel cote).
- **Repli / depli** : une seule anim d'echelle (`ActionLadderAnimation`) porte les deux temps, balises par
  `FermerEvenement` (replie, on fige) et `LadderOpenEndEvent` (deplie, on stoppe). Pilotee a la main (vitesse 0
  + `AdjustSpeed`), jamais laissee se relacher.

### Co-op : le WELD, apres deux culs-de-sac

Pour que les AUTRES voient l'echelle suivre le porteur, deux approches ont ECHOUE avant la bonne :

1. **Sync position en continu (serveur PivotTo repete).** Se battait avec la prediction locale du porteur ->
   l'echelle se rendait depliee et "bouffait" le joueur.
2. **Propriete reseau (SetNetworkOwner sur l'echelle desancree).** Les meshparts, mal tenus, tombaient a
   travers le sol (CanCollide off) et se faisaient DETRUIRE a `FallenPartsDestroyHeight` (-500) : l'echelle
   "disparaissait". Meme en corrigeant l'owner (chaque `AssemblyRootPart`) et en figeant le Humanoid, la
   repose renvoyait l'echelle sous / au-dessus de la map (vitesse residuelle + anti-teleport qui se basait sur
   la position envolee).

**La bonne solution (idee du joueur) : un WELD.** A la prise, le serveur desancre l'echelle et SOUDE sa
RootPart au HumanoidRootPart du porteur. L'echelle devient solidaire du perso -> elle le suit et se replique
NATIVEMENT a tous (le perso se replique deja), sans flot de remotes, et **elle ne peut pas tomber** (le weld
la tient). A la repose : on retire le weld et on re-ancre sur place. C'est plus simple ET plus robuste que
tout le reseau qu'on avait tente.

### Deux pieges du weld, resolus

- **L'offset c0 se calcule dans le REPERE CARRE (face haie), pas dans le HRP de la prise.** Le weld fige
  l'echelle relative au HRP ; or le HRP se tourne vers la haie APRES la prise (le rail l'y amene). Cale sur le
  HRP de depart, l'echelle finissait de travers une fois le joueur retourne. Cale sur le repere carre, elle
  est alignee des que le joueur l'est.
- **Le repli / depli se replique tant que l'echelle est soudee.** A la repose, on relache seulement a la FIN
  du depli (`OPEN_EVENT`), pas avant : sinon l'echelle re-ancree ne s'anime plus et le depli ne se verrait que
  chez le porteur.

### Recul du joueur : mesure, plus de reglage au pif

`CARRY_CLEARANCE` (1 stud). Le joueur n'est plus "dans" l'echelle : on MESURE le bord arriere reel de l'echelle
(coins de ses parts structurelles, zones de detection exclues) et on la pousse devant de sorte que ce bord
tombe a `CARRY_CLEARANCE` du joueur. Quelle que soit la taille de l'echelle, le perso reste juste derriere.
Fini le `CARRY_FORWARD` magique regle par tatonnement (avance / recule / avance).

### Filets

- Mort / respawn en plein portage, ou porteur qui quitte le serveur : on retire le weld + re-ancre, sinon on
  laisserait une echelle soudee a un perso disparu.
- Detection de l'echelle en RECURSIF (`GetDescendants`) : elle reste trouvee meme rangee dans un dossier. La
  grimpe (`LadderController`) cache le resultat, invalide seulement quand un `Escabaut*` apparait / disparait
  (pas de scan des milliers de carreaux chaque frame).
- Anti-spam de E (0.6 s) : un double-tap posait l'echelle avant que le repli ait joue.

### A tester

2 joueurs OBLIGATOIRE (Start > 2 players) : l'observateur doit voir l'echelle suivre le porteur, se replier a
la prise, se deplier a la repose, et rester posee au bon endroit.

## 0.0.91 — PRE-SYSTEME : les carreaux de pousse

`HedgeCellService` pave la surface taillable des haies avec une grille de carreaux.

**Rien ne les taille encore.** Cette etape repond a UNE question avant qu'un seul pixel de feuille soit
dessine : combien ca coute ? Baseline a comparer : 4.71 ms, mesuree avant tout gameplay.

### La grille s'ajuste a la face

On DEDUIT la taille des carreaux du nombre qui tient, au lieu de decouper a taille fixe et de laisser une
bande incomplete au bord. Ils pavent donc exactement la face, sans trou ni depassement, et leur cote s'ecarte
au maximum de moitie de `CELL_SIZE`.

Tout est construit dans le repere de la HAIE puis ramene en monde : une haie tournee se traite comme une haie
droite, sans un seul cas particulier.

| CELL_SIZE | 1 face (20x8) | 4 cotes + dessus | x10 haies |
|---|---|---|---|
| 2 | 40 | 98 | 980 |
| **1** | **160** | 392 | 3920 |
| 0.5 | 640 | 1568 | 15680 |

`CELL_FACES` ne contient qu'UNE face au depart, volontairement. Ajouter les autres est une ligne ; decouvrir
apres coup que cinq faces ne tiennent pas coute une semaine d'art.

`CELL_BUDGET` = 4000, verifie AVANT de parenter : rien n'entre dans le monde tant qu'il n'y a pas la place.

### Trois reglages obligatoires sur chaque carreau

`CanCollide = false`, `CanQuery = false`, `CastShadow = false`. Le dernier est le plus important a ce volume.
Le second ne prend effet que parce que le premier est deja faux.

### Piege evite

Les carreaux se posent DEVANT la haie : sans exclusion ils seraient touches avant elle et plus aucune haie ne
serait jamais detectee. Meme piege que les boites d'espace vital, et meme solution : un dossier a part, exclu
d'un coup, jamais range dans la haie (un filtre exclut une instance ET ses descendants).

Cote client, les trois copies du filtre de lancer sont remplacees par `hedgeRayParams`. Trois copies, c'etait
la garantie d'oublier la prochaine exclusion dans une seule des trois, et de chercher longtemps.

## 0.0.90 — On entend vraiment le moteur DECELERER

La retombee etait trop courte, mais la rallonger seule n'aurait rien donne.

`TweenInfo.new(duration)` sans style utilise **Quad Out** : le volume s'ecroule tout de suite puis traine. A
mi-parcours il ne restait qu'un quart du volume, donc la descente de hauteur se produisait quand on n'entendait
presque plus rien. Le moteur avait l'air de se COUPER, pas de ralentir.

Trois changements ensemble :

| | Avant | Apres |
|---|---|---|
| Duree | 0.45 s | 1.0 s |
| Courbe | Quad Out | Lineaire |
| Hauteur finale | 0.70 | 0.50 |

Mesure de ce qui est reellement audible (volume > 0.3) :

| | Duree audible | Hauteur atteinte pendant ce temps |
|---|---|---|
| Avant | 0.20 s | 0.79 |
| Apres | 0.70 s | 0.65 |

Le lineaire n'est applique que lorsqu'une descente de hauteur est demandee : les autres fondus gardent la
courbe par defaut.

## 0.0.89 — Plus aucun mouvement de l'outil pendant la taille

`tiltWorkingScale` = 0. Au pied d'une haie, ni l'inclinaison ni le tremblement ne bougent l'outil.

| | Hors chantier | Devant une haie |
|---|---|---|
| Inclinaison | 10 deg | 0 |
| Tremblement | 1.4 deg | 0 |
| Deplacement du bout de lame | 0.79 stud | 0.00 |

La position de la lame ne depend plus que de la VISEE. Hors chantier les deux effets restent entiers, la ou ils
servent a faire sentir le moteur sans gener personne.

**Regle a appliquer a la coupe** : un effet qui bouge l'outil pendant un geste de precision se ressent comme
une perte de controle, meme quand il est joli. Chaque retour visuel ajoute devra passer ce test -- informe-t-il
le joueur, ou le fait-il douter de ce qu'il vise ?

## 0.0.88 — La distance de travail devient reproductible

En revenant sur une face deja travaillee apres avoir contourne la haie, la distance n'etait plus la meme
qu'avant.

`WORK_DISTANCE_TOLERANCE` n'est pas seulement une zone de calme : c'est EXACTEMENT l'incertitude sur la
distance finale. Le joueur cesse d'etre corrige des qu'il y entre, donc il se fige n'importe ou dedans, et
l'endroit depend de la direction d'ou il arrive.

| Tolerance | Ecart entre une arrivee de loin et de pres |
|---|---|
| 0.25 (avant) | 0.486 stud |
| 0.12 | 0.234 |
| **0.05** | **0.098** |
| 0.00 | 0.001 |

Passe a 0.05. Une zone morte large etait censee eviter de sentir une main dans le dos : c'est le caractere
PROPORTIONNEL du rappel qui evite ca, pas sa largeur. La force faiblit toute seule en approchant.

Verifie : amplitude residuelle 0.00000 stud, aucune oscillation, quelle que soit la distance de depart.

## 0.0.87 — La visee etait bornee en hauteur mais pas en largeur

La pose de coupe se declenchait meme curseur hors de la haie.

Trou laisse par 0.0.76 : viser le PLAN de la face regle le probleme des bords, mais un plan est INFINI. On
bornait le point en hauteur, jamais lateralement. Pointer vingt studs a cote de la haie donnait donc une visee
parfaitement valide.

Le point est desormais borne dans les DEUX directions, dans le repere de la haie (donc valable aussi sur une
haie tournee). L'axe lateral se deduit de la normale : c'est celui des deux axes horizontaux qui n'est pas
celui de la face.

Meme marge partout (`AIM_MARGIN` = 3) : deborder d'un cheveu en balayant un bord ne lache pas la visee, viser
franchement a cote rend la main.

| Curseur | Resultat |
|---|---|
| Plein centre | pose 0.50 |
| 1 stud sous la haie | pose 0.00 |
| 3 studs sous (limite) | pose 0.00 |
| 4 studs sous | LACHEE |
| 2 studs a cote du bout | pose 0.50 |
| 5 studs a cote | LACHEE |
| 20 studs a cote | LACHEE |
| Dans le ciel | LACHEE |

**Lecon** : elargir une zone de tolerance dans une direction oblige a verifier les autres. Le plan infini
reglait un bord et en ouvrait trois.

## 0.0.86 — Le tremblement s'arrete au pied d'une haie

Le tremblement dit "la machine tourne dans le vide, elle force pour rien". En pleine taille il dit donc le
CONTRAIRE de ce qu'on veut montrer, et il brouille un geste de precision.

Il s'eteint des que le joueur est accroche a une haie, et revient quand il la quitte.

En FONDU et non net : couper un sinus a 13 Hz laisserait l'outil fige sur un angle quelconque, et le saut se
verrait. `vibeGateSpeed` = 9.

| | Temps |
|---|---|
| Extinction en arrivant sur la haie | 0.003 deg restant apres 0.6 s |
| Retour en quittant la haie | 90 % en 0.25 s |

`ToolStartService` lit l'ATTRIBUT pose sur le personnage plutot que d'appeler `HedgeService`. Une config
partagee ne cree pas de dependance : les deux services continuent de s'ignorer, et restent retouchables
separement.

## 0.0.85 — L'aimant decide de la distance, la boite ne fait plus que bloquer

Trois symptomes, une seule cause : **l'aimant ne tirait que VERS la haie, jamais en arriere.**

Rien ne ramenait donc un joueur arrive trop pres : il restait colle a la boite d'espace vital, et sa distance
de travail dependait de la BOITE au lieu du reglage. Le long d'un grand cote il mangeait la haie ; dans un
coin, la diagonale de la boite le tenait trop loin.

C'est aussi pour ca que passer `WORK_DISTANCE` a 3.3 n'avait rien change : ce reglage ne servait qu'a tirer
vers la haie.

### Ce qui bloquait la poussee arriere

Elle avait ete supprimee parce que le serveur la confondait avec l'intention de sortir : il decrochait, ca
raccrochait, l'aimant repoussait, ca redecrochait. Le personnage avancait et reculait tout seul.

Les deux signaux arrivent par le meme canal ET dans la meme direction : **impossible de les distinguer une
fois melanges.** Alors on ne cherche plus a les distinguer, on choisit QUAND poser la question.

Tant que la distance de travail n'est pas retablie, le serveur NE JUGE PLUS l'intention de sortir. Le joueur
qui pousse vraiment vers l'arriere sort des qu'il a repris sa distance, environ 0.13 s plus tard.

### Repartition des roles

| | Role |
|---|---|
| Aimant | decide de la distance, dans les DEUX sens |
| Boite d'espace vital | empeche de traverser la haie, rien d'autre |

`BUFFER_MARGIN` passe de 1.2 a 0.8, volontairement SOUS `WORK_DISTANCE` : les deux ne doivent plus se disputer
le placement.

`MAGNET_PUSH_STRENGTH` = 0.35, plus faible que l'attraction (0.45) : etre repousse doit se sentir comme un
recadrage, pas comme une main dans le dos.

### Convergence

| Depart | Arrivee | Temps |
|---|---|---|
| 1.5 (dans la haie) | 3.06 | 1.07 s |
| 2.5 | 3.05 | 0.62 s |
| 6.0 | 3.55 | 1.07 s |

Amplitude residuelle mesuree sur les 3 dernieres secondes : 0.0000 stud. Le rappel est proportionnel a l'ecart
dans les deux sens, il faiblit donc en approchant et ne depasse jamais la cible.

## 0.0.84 — La lame ne doit plus rentrer dans la haie

`WORK_DISTANCE` passe de 2.6 a 3.3.

Cette distance etait reglee sur l'outil AU REPOS. Or trois choses le font avancer, et elles s'ADDITIONNENT :

| Source | Debattement au bout de lame |
|---|---|
| Hauteur visee (pose des bras) | variable |
| Inclinaison de couple, 10 deg | 0.69 stud |
| Tremblement, 1.4 deg | 0.10 stud |

C'est pour ca que passer la souris de haut en bas ne rentrait pas alors qu'accelerer rentrait : l'animation
bouge les BRAS, l'inclinaison fait pivoter l'OUTIL. Et c'est pour ca que ca "dependait" meme sans accelerer :
la pose des bras change avec la hauteur visee.

Reculer le joueur seulement pendant l'acceleration est impossible : l'aimant ne pousse jamais vers l'arriere,
une poussee arriere se confondrait avec l'intention de sortir. Donc UNE distance, reglee sur le cas le pire.

**3.3 est une premiere estimation**, calculee sur une lame supposee de 4 studs. A regler a l'oeil en visant le
BAS de la haie a plein regime : c'est la que la marge est la plus faible.

### A garder en tete pour la coupe

Quand la coupe existera, une lame qui EFFLEURE la haie sera souhaitable : c'est ce qui donnera l'impression de
mordre dedans. Ne pas trop reculer maintenant, sinon il faudra tout rapprocher a ce moment-la.

## 0.0.83 — Tremblement a plein regime

A fond d'accelerateur, l'outil bat de part et d'autre de sa position inclinee, sur le meme axe. Un sinus donne
naturellement l'alternance dans un sens puis dans l'autre.

Il n'apparait que dans le HAUT du regime (`vibeStart` = 0.8). Present des le ralenti, il se lirait comme un
defaut d'affichage ; reserve a plein regime, il se lit comme une machine qui force, et il recompense le joueur
qui tient l'accelerateur.

L'intensite monte progressivement entre 80 % et 100 % du regime : pas d'apparition brutale.

### Plafond de frequence, a connaitre

`vibeFrequency` = 13 Hz. **Plafond reel vers 15.** L'inclinaison est calculee cote serveur puis repliquee : a
13 Hz sur un serveur a 60 Hz, il reste 4.6 echantillons par cycle. Au-dela on n'obtient pas un tremblement plus
rapide, on obtient du bruit.

Pour monter vraiment plus haut il faudrait calculer le tremblement chez chaque client, a partir de
`LeafiaThrottle` qui se replique deja. Pas fait : le besoin n'est pas prouve.

`setGripTilt` prend un `extraDegrees` NON borne, pour que le tremblement puisse passer au-dessus de
l'inclinaison maximale. Le borner ecraserait une alternance sur deux.

`tiltAxis` passe a `zAxis` apres essai des trois. Aucun raisonnement possible : `cutGripOffset` tourne le
repere de -50 / 162 / 80 degres, donc X, Y et Z ne pointent plus dans les directions qu'on imagine. Trois
essais coutent moins cher qu'une deduction.

### CharacterService devient le seul proprietaire de WalkSpeed

`CharacterService.setSpeedOverride(player, speed?)`. `HedgeService` **ne touche jamais** a `WalkSpeed` : il
declare une intention.

Sans cette regle, la haie mettrait 5, le sprint remettrait 17 la frame d'apres, et la reprise d'atterrissage
ferait sa rampe par-dessus. C'est la meme regle que pour la camera en 0.0.49 : **une propriete, un seul
ecrivain.** Elle revient partout.

La rampe de vitesse devient BIDIRECTIONNELLE : `LANDING_RECOVERY_RATE` (14) pour remonter,
`SPEED_SLOWDOWN_RATE` (9) pour descendre. On est aspire vers le travail, on n'y est pas jete.

### A faire dans Studio

Rien. Il suffit que les haies vivent dans `Workspace.Worlds.Maps` et que leur nom commence par `hedge_`.
Le serveur affiche au demarrage combien il en a trouve.

### Note

Ecart assume avec la regle d'or : c'est de l'habillage, pose avant validation du geste de taille. A ne pas
etendre. La prochaine tache reste le prototype de taille.
