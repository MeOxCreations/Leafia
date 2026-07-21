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
