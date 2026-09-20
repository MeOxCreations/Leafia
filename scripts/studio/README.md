# scripts/studio

Outils a coller dans la **barre de commandes de Studio**. Ils ne sont PAS synchronises par Rojo (ce dossier est hors
de `src/`) : ils ne partent jamais dans le jeu.

A quoi ca sert : refaire dans Studio un calcul que le jeu fait en code (placement d'un outil dans la main, zones,
diagnostics). Poser une chose "a peu pres" a la main donne un resultat juste a l'ecran et faux en jeu ; rejouer le
calcul ici coute dix minutes et supprime la classe entiere de bugs.

## Ce qu'il y a dedans

- `RangerWorkspace.lua` — range le Workspace : cree les dossiers attendus et y deplace ce qui traine a la racine.
  **Commence en mode APERCU** : il ecrit ce qu'il ferait sans rien toucher. Passe `PREVIEW = false` pour appliquer.

## Les anciens outils

Les treize outils de diagnostic (rigs, animations, seaux, prompts, export des sons et de l'interface) ont ete
retires le 20/09/2026 : ils avaient fait leur travail. Ils restent dans l'historique git, rien n'est perdu :

    git log --diff-filter=D --name-only -- scripts/studio
    git show <commit>^:scripts/studio/ComparerAnimEtRig.lua
