# Prototype 0

Premier essai technique du jeu d'arène 1 contre 1 en vue 2,5D.

## Version actuelle

- arène 3D plus grande que l'écran ;
- caméra inclinée suivant le joueur avec anticipation de la visée ;
- déplacement clavier AZERTY/QWERTY et flèches ;
- Electro Axe provisoire en combo de trois coups à la souris ou avec la barre d'espace ;
- obstacles bloquant le joueur et les projectiles ;
- cible d'entraînement à 1 000 PV avec affichage des dégâts, ralentissement et stun ;
- première passe visuelle de l'arène : sol sableux peint, murs de ferraille modulaires,
  plaques crème/rouille, acier sombre, pneus, caisses, barils, bannières rouges,
  hautes herbes décoratives, poussière, lampes et gradins de spectateurs.

Le lot Electro Axe sert à valider la perspective, la caméra, les déplacements, les hitboxes
et les sensations de combat avant l'intégration du Shotgun et des modules. Les règles des
bushs et des kits de vie ne sont pas encore activées : leurs emplacements et leur habillage
restent des repères visuels sans collision supplémentaire.

## Rendu et ressources visuelles

- Renderer conservé : **Mobile** (Godot 4.7.2).
- Ressources réutilisables dans `art/` : `sand_dust.svg`, `metal_cream.svg`,
  `metal_rust.svg`, `steel_dark.svg` et `banner_red.svg`.
- Les collisions des couverts restent séparées de leurs modules décoratifs : les petits
  débris, herbes et accessoires n'ajoutent pas de formes de collision individuelles.
- L'éclairage exécuté combine une direction chaude, un remplissage froid discret, des
  lampes locales, des écrans cyan et une brume simple compatible Mobile.

## Captures de validation

Les captures réellement rendues par Godot sont conservées dans `captures/` :

- `prototype0_before.png` : état de départ, même zone de jeu ;
- `prototype0_after.png` : vue générale après la passe visuelle ;
- `prototype0_gameplay.png` : cadrage au spawn jouable ;
- `prototype0_detail.png` : lecture rapprochée d'un couvert et du sol ;
- `prototype0_spectators.png` : cadrage de validation de la bordure extérieure.

Elles ont été produites avec le renderer Mobile via le pilote D3D12 sur le GPU disponible
(NVIDIA GeForce RTX 3070 Laptop GPU). Aucun nombre de FPS Android n'est déduit de cette
capture : un essai sur appareil Android reste nécessaire.

Pour refaire une capture locale depuis PowerShell :

```powershell
& 'C:\Users\Ben\Desktop\PROTOTYPE 0\Godot_v4.7.2-stable_win64_console.exe' `
  --path 'C:\chemin\vers\PROTOTYPE-0' --display-driver windows `
  --rendering-method mobile --rendering-driver d3d12 `
  --script 'res://tools/capture_scene.gd' -- 'captures\ma_capture.png' 0 0
```

## Lancer le prototype

Ouvrir `project.godot` avec Godot 4.7.2, puis appuyer sur `F6` ou `F5`.

## Commandes

- `ZQSD`, `WASD` ou flèches : déplacement ;
- souris : orienter l'attaque ;
- clic gauche ou espace : enchaîner l'Electro Axe.
