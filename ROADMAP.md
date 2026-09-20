# Leafia — Feuille de route

A quoi sert ce fichier : savoir, a tout moment, **ou on en est, ce qui vient ensuite, et pourquoi**. Ecrit pour
Meox d'abord, et pour quelqu'un qui reprendrait le projet sans nous.

Mis a jour le 20/09/2026 (v0.0.930). A relire et corriger a chaque grosse etape.

---

## 1. La regle qui prime sur tout le reste

**Le geste de TONDRE doit etre jouissif avant qu'on construise par-dessus.** Le test n'est pas "est-ce que ca
marche", c'est : **trois personnes reelles tondent une deuxieme pelouse sans qu'on leur demande.**

Tant que la reponse est non, on ne lance aucun des gros systemes de la section 5. C'est la lecon de Bird Game et de
League Of BattleCar : dans les deux cas, un probleme au coeur, recouvert d'interfaces de plus en plus soignees, et
une retention au sol.

---

## 2. Ou on en est

Chiffres : 155 fichiers, ~59 000 lignes. C'est deja beaucoup pour une personne seule.

### Ce qui marche

- **Tonte** : tondeuse (prise, demarrage a la corde, conduite, roues), herbe de zone qui s'ecrase et reste couchee,
  coupe permanente, poussiere et sons.
- **Taille de haie** : outil, coupe carreau par carreau, feuilles qui tombent, echelle (portage, grimpe, taille du
  dessus), rateau, seau, camion et sa benne.
- **Didacticiel** (place a part) : scene du grand-pere, premiere tonte, premiere haie, cheque, depart vers le hub.
- **Hub** : ecran de choix du plot, 3 saves par joueur (ProfileStore, autorite serveur), pieces et reputation qui
  persistent, XP et niveau, boite aux lettres cablee sur chaque plot.
- **Confort** : console admin (F2 ou la roue sur mobile), compteur FPS, notifications, bandeau d'objectifs.

### Ce qui est fragile ou inacheve

- **Les FPS sur telephone** : 13 a 15 FPS dans le didacticiel. Injouable. C'est le bloquant numero un.
- **Le mode build** : tout le confort est la (murs, objets, grille, suppression, camera), mais **100 % client**.
  Rien n'est valide par le serveur, rien n'est sauvegarde. Ce qu'on construit disparait en quittant.
- **Les chantiers** : la boite aux lettres existe, le cheque de fin de haie existe (~100 pieces), mais **personne
  ne DONNE de chantier**. Pas de client, pas de commande, pas de choix d'accepter ou refuser.
- **Pas de boutique** : rien a acheter avec les pieces. Donc gagner de l'argent ne sert encore a rien.

### Ce qui n'existe pas du tout

PNJ qui se promenent, vehicules, plantations, marche, cooperation entre joueurs, achats en Robux.

---

## 3. L'ordre de travail

### Etape 0 — Les FPS sur telephone (EN COURS, bloquant)

**Pourquoi** : a 13 FPS, le joueur sent que "ca repond mal" et il part. Aucune feature ne repare ca.

**Ce qui est fait** : `PerfStatsController` affiche images par seconde, pire image, ping, le temps de nos grosses
boucles (`PerfProbe`) et le nombre de pieces du monde.

**Comment tester** : republier le didacticiel, jouer sur telephone, faire une capture de la deuxieme ligne du
compteur devant la maison du grand-pere.

**Comment lire** : a 60 FPS une image dure 16.7 ms. Si `lua` en prend l'essentiel, ce sont nos scripts (le nom en
tete de ligne dit lequel). Si `lua` est petit et que ca rame quand meme, c'est le DESSIN : trop de pieces, et c'est
la densite d'herbe / le nombre de feuilles qu'il faut baisser.

### Etape 1 — Valider la tonte sur trois personnes reelles

**Pourquoi** : c'est le feu vert de tout le reste. On ne le remplace pas par une opinion.

**Comment tester** : trois personnes qui ne connaissent pas le jeu, sur telephone ET sur PC. On regarde UNE chose :
est-ce qu'elles en tondent une deuxieme **sans qu'on leur demande**.

**Si non** : on repare la tonte (vitesse, retour visuel, son, avant/apres), on ne fait rien d'autre.

### Etape 2 — La boucle d'argent : un chantier, un cheque, un achat

**Pourquoi** : le fun fait rester, la possession fait revenir. Aujourd'hui l'argent ne sert a rien.

**Ce qui manque** :
- un `JobService` : un client donne un chantier (tondre telle pelouse, tailler telle haie), avec une paie annoncee ;
- l'entree par la boite aux lettres (le courrier existe deja comme decor) ;
- accepter ou refuser (refuser un chantier mal paye, c'est deja un choix de joueur) ;
- une note de fin de chantier (c'est elle qui donne envie d'en refaire un) ;
- une boutique simple, en PIECES uniquement : une meilleure tondeuse, un meilleur taille-haie.

**Regle a tenir** : toujours du rouge a l'ecran (trop cher) et du verrouille. Tout en vert = ennui.

### Etape 3 — Le build : autorite serveur et sauvegarde

**Pourquoi** : c'est ce que le joueur POSSEDE entre deux sessions. Sans sauvegarde, tout le travail deja fait sur
le build ne laisse rien au joueur le lendemain.

**Ce qui manque** :
- le serveur valide chaque pose (objet autorise, sur SON plot, prix debite) ;
- `spendCoins` cote `CurrencyService` ;
- la liste des constructions dans la save (par slot de company), et son rechargement a l'arrivee.

**Comment tester** : construire, quitter, revenir. Tout doit etre la, et un deuxieme joueur ne doit pas pouvoir
construire sur le plot d'un autre.

### Etape 4 — Le didacticiel amene vraiment au jeu

**Pourquoi** : la premiere minute decide de tout. Elle existe, il faut qu'elle finisse sur un vrai premier chantier
dans le hub, pas dans le vide.

**Ce qui manque** : le grand-pere du hub (cle, portail, felicitations), et le premier chantier enchaine tout de
suite apres.

### Etape 5 — Mesurer la retention

**Pourquoi** : avant ca, on ne sait pas si le jeu retient. Et on ne monetise pas un seau perce.

**Comment** : publier, regarder le J1 (combien reviennent le lendemain) et la duree moyenne de session. C'est
seulement apres qu'on parle Robux.

---

## 4. Plus tard, et pourquoi pas maintenant

Ces idees sont bonnes. Elles sont aussi **grosses**, et chacune ajoute du code a maintenir pour toujours.

| Idee | Cout honnete | Condition pour la lancer |
|---|---|---|
| PNJ qui se promenent, vehicules | Gros (navigation, trafic, perf mobile) | Apres l'etape 5 |
| Plantations, recolte, marche | Gros (pousse, stock, prix, save) | Apres l'etape 5 |
| Cooperation entre entreprises | Tres gros (reseau, autorite, teleport, triche) | Apres l'etape 5 |
| Boutique Robux | Moyen | Seulement si le J1 est sain |
| Chantiers chez le client (arrosage, creation de gazon) | Moyen | Pendant l'etape 2, une tache a la fois |

**Regle** : on n'ouvre jamais deux gros systemes en meme temps. Un systeme a moitie fait est ce qui rend un projet
impossible a reprendre.

---

## 5. Reprendre le projet sans assistant

### Les outils

- **Rojo** synchronise `src/` vers Studio. Ordre obligatoire : `git pull --rebase origin main` PUIS `rojo serve`.
  Rojo ECRASE Studio avec le disque local : le dernier qui connecte gagne.
- **selene** verifie le code : `selene src`. C'est le seul vrai controle de syntaxe (`rojo build` ne verifie rien).
- **rokit** installe les deux. Un `rokit.toml` par projet.

### Ce que Rojo NE synchronise PAS

La map (Workspace), les Assets, les Animations, les ScreenGui de Studio. Ca se recopie **a la main** dans chaque
place. C'est la cause la plus frequente de "ca marche dans le hub et pas dans le tuto".

### Ou regler les choses sans coder

Tout ce qui est un nombre ou une couleur vit dans `src/ReplicatedStorage/Modules/Configs/`. Un fichier par sujet
(`MowConfigs`, `GrassZoneConfigs`, `HedgeConfigs`, `TutorialConfigs`...). Les commentaires y expliquent ce que
chaque valeur change a l'ecran. **C'est la qu'on regle le jeu, pas dans le code.**

### Comment lire le projet

- `CLAUDE.md` : les conventions, et surtout le **journal d'apprentissage** — tous les pieges deja payes. A relire
  avant de toucher a un systeme voisin ; plusieurs bugs ont ete repayes faute de l'avoir fait.
- `CHANGELOG.md` : ce qui a change, dans quel ordre, et pourquoi.
- Les points d'entree : `src/ServerScriptService/Server/init.server.luau` et
  `src/StarterPlayerScripts/Client/init.client.luau`. Ils declarent les modules un par un. **Un module qui n'est
  pas declare la ne fait RIEN, sans la moindre erreur.**

### Le piege des places

Tout le code part dans TOUTES les places ; c'est le bootstrap qui trie par `game.PlaceId`. Il y a donc deux listes
a tenir d'accord (tuto / hub). A la troisieme place, passer a une table de profils (un seul endroit qui dit quel
module tourne ou) — sinon les listes divergent en silence.

---

## 6. Ce qu'on ne fait pas

- Pas de monetisation tant que le J1 n'est pas sain.
- Pas de nouvelle interface tant que le geste qu'elle habille n'est pas valide.
- Pas de gain passif, pas de recompense sans participation.
- Dans le doute, donner MOINS : on peut desserrer plus tard, reprendre est vecu comme une punition.
