# Idees — Leafia

Backlog d'idees a NE PAS coder tant que le coeur (le geste de tailler) n'est pas valide par 3 personnes reelles
qui retaillent une deuxieme haie sans qu'on leur demande. Append-only : on n'efface pas, on ajoute.

## Escabeau — grimpe en DEUX animations (haut / bas du corps)

Parquee le 2026-07-24. Statut : PAR-DESSUS, ne pas construire avant validation du coeur.

Idee : separer la grimpe en deux pistes d'animation qui jouent en meme temps.
- Une piste pour le BAS du corps (jambes) : c'est elle qui grimpe les barreaux.
- Une piste pour le HAUT du corps.
Arrive en haut de l'echelle, on STOPPE la piste du haut du corps et on joue celle du TAILLE-HAIE a sa place.
Le joueur taille donc depuis le haut de l'echelle, jambes plantees sur les barreaux.

Pourquoi c'est solide : c'est du layering par priorite d'animation (une piste ne cle que le bas, l'autre que le
haut). Roblox le permet nativement. Voir les lecons du journal dans CLAUDE.md sur les priorites d'animation
(Core < Idle < Movement < Action < Action2..4, et "a priorite egale Roblox MELANGE").

A regler quand on y reviendra : les glitchs deja rencontres sur le prototype precedent (marche dans le vide,
pose bizarre a la sortie, camera qui doit suivre le torse et pas le root). Le prototype
`EscabautTestController.luau` supprime est retrouvable dans l'historique git si besoin.

## BUG connu — feuilles laissees dans le coin en contournant

Note le 2026-07-24. Statut : vrai bug de coupe, mais FINITION d'un cas particulier. A regler APRES la validation
du geste sur une haie droite.

Symptome : en tournant l'arrondi d'un coin, la coupe balaie en eventail et laisse des petits coins de feuilles
non taillees DERRIERE le geste. Le joueur doit reculer pour les rattraper. Pas pratique.

Cause probable : la lame tourne au coin, donc deux passes successives divergent en eventail et un coin de
carreaux passe entre les deux. Le test de coupe (HedgeCutService : `outward = toBlade:Dot(cell.CFrame.ZVector)`
plus la portee) est correct par carreau, c'est la DENSITE du balayage qui manque dans l'arc.

Pistes a explorer (pas tranchees) : elargir un peu la portee de coupe dans l'arrondi ; retenir le joueur au coin
le temps que ca se nettoie ; ou un mouvement de contournement dedie. Le joueur pense "mouvement du joueur", mais
le fond est une couverture de coupe. A diagnostiquer sur du concret avant de coder.
