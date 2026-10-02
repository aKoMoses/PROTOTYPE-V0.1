# Passe visuelle en combat

La cour gagne une lumière principale chaude, un remplissage froid et des surfaces plus distinctes : acier satiné, peinture plus mate et toile sans reflet métallique. Les robots conservent leurs textures et leur géométrie, avec un léger reflet de bord sur les pièces rigides et une ombre de contact douce sous leurs pieds.

Les herbes ont des hauteurs, des courbures et des couleurs variées. Leur nombre et le rayon utilisé par le camouflage restent identiques. Les bordures des plaques de vie sont plus fines ; l'anneau du joueur est discret et circulaire. Les réactions visuelles au tir et à l'impact sont accentuées sans déplacer les sockets des armes.

Le directeur `scripts/environment/combat_visual_polish.gd` est installé dans le duel, l'entraînement et la survie. Il traite également les éléments ajoutés après le chargement et accepte les matières StandardMaterial3D ainsi que le shader peint `stylized_salvage`. Cette passe s'intègre aux travaux simultanés sur le décor, les particules et les signatures des armes ; les dernières captures montrent leur résultat combiné.

## Protection du gameplay

- L'ombre appartient à la racine de visibilité du robot : elle disparaît avec un adversaire caché et suit ses transitions de visibilité.
- Les flashs de dégâts ignorent cette ombre pour éviter un rectangle lumineux au sol.
- Les collisions, les valeurs de santé, les rayons de camouflage et les points de soins ne sont pas modifiés par cette passe.
- Les matières sont dupliquées par instance ; les imports GLB et les textures d'origine restent disponibles.

## Vérification

Exécution avec Godot 4.7.2, Vulkan et le renderer Mobile sur PC. Les journaux et les captures se trouvent dans `outputs/combat-polish/`.

- `test_combat_polish.gd` : ombres, flashs critiques, transitions de camouflage, changements de châssis, matières tardives et installation dans les trois modes.
- Régressions des rigs du joueur et du droïde, du camouflage, de la visibilité, des châssis et des soins de l'arène.
- Le rig joueur termine ses 299 vérifications ; le test de l'arène à plateformes termine également ses déplacements réels sur les rampes, ses tirs entre niveaux et ses points de soins. L'import dans l'éditeur se termine sans erreur de script.
- Captures des trois armes dans la cour classique, la carte à plateformes, l'entraînement et la survie ; contrôle supplémentaire en qualité réduite et cadrage mobile.

`before-center.png` et `after-center.png` utilisent la même caméra, confirmée par `after-metrics.json`. Cette paire a été prise pendant la passe : les captures `classic-ready.png` et `test-*-impact.png` montrent l'état final intégré. Les captures d'impacts déclenchent les effets en scène pour les examiner ; elles ne constituent pas une mesure des dégâts d'une arme. Les mesures de FPS issues de ces captures ne sont pas un benchmark soutenu. Aucun APK ni téléphone Android n'a été testé.

## Reproduire

```powershell
& 'C:\Users\Ben\Desktop\Prototype 0\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_combat_polish.gd
& 'C:\Users\Ben\Desktop\Prototype 0\Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tools/capture_combat_polish.gd -- outputs/combat-polish test
& 'C:\Users\Ben\Desktop\Prototype 0\Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tools/capture_combat_polish.gd -- outputs/combat-polish test low mobile
```

Le chemin de l'exécutable ci-dessus est celui vérifié sur cette machine ; le dossier Godot indiqué dans les instructions générales du projet n'y existe pas.
