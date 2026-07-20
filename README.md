# Leafia

Jeu Roblox de paysagiste. Le joueur va chez des clients, taille haies et arbustes, repart avec un cheque, et
fait grandir son entreprise — seul ou en co-op.

## Lancer le projet

Rojo doit tourner pour synchroniser le dossier `src/` vers Roblox Studio.

```
rojo serve Leafia.project.json
```

Puis dans Studio : plugin Rojo -> Connect (port 34872 par defaut).

Verifier le lint :

```
selene src
```

## Autocompletion / types dans VS Code

`luau-lsp` ne resout les types entre modules que s'il a un sourcemap. Il est en `autogenerate: false` dans
`.vscode/settings.json`, donc il faut le regenerer a la main apres avoir ajoute ou deplace des fichiers :

```
rojo sourcemap Leafia.project.json --output sourcemap.json
```

## Ou va quoi

`src/` reproduit l'arborescence Studio : ce qu'on voit dans l'Explorer est ce qu'on voit sur le disque.

| Disque | Studio |
|---|---|
| `src/ServerScriptService/Server/` | ServerScriptService.Server (Script) + ses services enfants |
| `src/StarterPlayerScripts/Client/` | StarterPlayerScripts.Client (LocalScript) + ses controllers |
| `src/ReplicatedStorage/Modules/` | Configs, Utils, UI |
| `src/ReplicatedStorage/Shared/` | RemoteSetup, Classes |
| `src/ServerStorage` | ServerStorage |
| `src/ReplicatedFirst` | ReplicatedFirst |

Les ScreenGui et les assets vivent dans Studio (`StarterGui`, `ReplicatedStorage.Assets`) : Rojo les ignore
grace a `$ignoreUnknownInstances`, donc ils ne sont jamais ecrases.

## Nommage

`XxxService` (serveur) · `XxxController` (client) · `XxxHandler` (UI) · `XxxConfigs` · `XxxUtils` · `XxxClass`

## Regle d'or

Le geste de tailler doit etre jouissif avant qu'on code autre chose. Voir `CLAUDE.md`.
