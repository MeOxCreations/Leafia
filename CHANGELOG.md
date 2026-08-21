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
