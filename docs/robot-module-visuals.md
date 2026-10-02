# Modules 3D intégrés à l'armure

Les cinq accessoires sont conçus comme de petits inserts épousant les pièces du robot. Leur taille et leur faible épaisseur doivent préserver les proportions du mecha équipé, avec un visage et un cœur de poitrine entièrement dégagés. La validation visuelle porte sur le robot entier et ses animations, en comparaison avec le même robot sans accessoires.

## Formes et fixations

- **Pyroboots** : carénages d'environ 15 cm intégrés derrière les chevilles. La tuyère est creuse et orientée vers l'arrière; la coque suit le talon plutôt que d'ajouter un boîtier latéral.
- **Bio Injector** : petit insert d'environ 18 cm sur le côté du plastron, avec deux cartouches, une pompe et un conduit en retrait.
- **Panier Roquettes** : insert de faible épaisseur sur la protection du bras gauche, sous le niveau de la tête. Les ouvertures et leurs rebords donnent le détail mécanique.
- **Magnetic Field** : disque compact fixé à l'avant-bras gauche, dont l'orientation suit la plaque du bras.
- **Réacteur auxiliaire** : insert tourné vers l'arrière, placé sur la protection métallique du haut du bras gauche, derrière l'épaule.

Les Pyroboots suivent les os des pieds; l'injecteur suit le torse; le lanceur et le réacteur suivent le haut du bras gauche; le champ suit l'avant-bras gauche. Position et orientation des coques sont réglées sur les surfaces animées de l'armure, avec un léger engagement de leur partie arrière dans la plaque support. Le propulseur droit a une symétrie intégrée à sa géométrie, avec normales et orientation des triangles corrigées. Les sockets gardent une échelle positive et les accessoires suivent rotation, animation et châssis sans traitement supplémentaire par frame.

Réglages de fixation dans [robot_module_visuals.gd](../scripts/robot_module_visuals.gd), exprimés dans le repère du robot de référence de 3,05 m :

| Pièce | Os | Décalage XYZ (m) | Rotation XYZ (rad) |
| --- | --- | --- | --- |
| Pyro gauche | `leftfoot` | `(0,04; 0,04; −0,25)` | `(0; π; 0)` |
| Pyro droit | `rightfoot` | `(−0,04; 0,04; −0,25)` | `(0; π; 0)` |
| Bio | `spine1` | `(0,2776; −0,0803; 0,1871)` | `(0,3320; 0,6739; 0,0192)` |
| Roquettes | `leftarm` | `(0,1447; 0,0876; 0,1795)` | `(−0,4721; 0,7048; 1,0034)` |
| Champ | `leftforearm` | `(0,18; −0,005; 0,230)` | `(0; 0; −π/2)` |
| Réacteur | `leftarm` | `(0,2169; −0,0284; −0,1132)` | `(0,0938; −3,0804; 1,5765)` |

Les quatre catégories du loadout déterminent indépendamment les pièces visibles. Pyroboots et Bio Injector restent exclusifs dans la mobilité. L'un ou l'autre peut être équipé avec Panier Roquettes, Magnetic Field et Réacteur auxiliaire. La visibilité est propre à chaque robot; le camouflage emploie des copies locales de matériaux, puis restaure les références opaques d'origine.

## Sources et matériaux

Les modèles et textures sont créés localement avec [build_mobility_module_models.py](../tools/build_mobility_module_models.py), [build_additional_module_models.py](../tools/build_additional_module_models.py) et les outils communs de [module_modeling.py](../tools/module_modeling.py). Aucun modèle ou texture externe n'est utilisé. Les sources Blender éditables sont dans `art/modules/source/*.blend`; les rendus de présentation dans `art/modules/previews/`. Ces dossiers ont un `.gdignore`.

Chaque GLB dans `art/modules/` est accompagné d'un `.asset.json` indiquant provenance, source, dimensions, triangles, lots de matériaux, octets et SHA-256. Les maillages ont des UV et des normales; les textures PBR 256 × 256 de couleur, rugosité et normales sont intégrées. Les émissions sont limitées et les matériaux opaques. Les caches de maillage et matériau sont partagés par les robots, les rangements et les pièces transportées par le bras de la forge.

| GLB | Largeur × hauteur × profondeur du modèle | Triangles | Lots de matériaux | Octets |
| --- | --- | ---: | ---: | ---: |
| `pyro_boots.glb` | 10,2 × 14,9 × 5,7 cm pour un talon | 3 064 | 7 | 1 176 872 |
| `bio_injector.glb` | 10,8 × 18,0 × 4,5 cm | 5 816 | 6 | 1 140 940 |
| `rocket_basket.glb` | 19,0 × 15,0 × 5,0 cm | 4 004 | 3 | 678 444 |
| `magnetic_field.glb` | 13,3 × 18,2 × 5,3 cm | 3 800 | 6 | 1 025 656 |
| `auxiliary_reactor.glb` | 15,9 × 25,9 × 6,7 cm | 3 100 | 5 | 889 820 |

Le kit ajoute 17 032 triangles avec les deux Pyroboots ou 16 720 avec Bio Injector, sous le budget de 30 000 triangles pour les accessoires. Le robot complet de la forge avec Blaster compte respectivement 32 095 et 31 783 triangles. Après montage, orientation et échelle du châssis puissant, chaque pièce reste sous 30,3 cm sur son axe mondial le plus étendu; la largeur entre les deux talons n'est pas la taille d'un propulseur.

## Vérification de la version compacte du 2 octobre 2026

Les cinq GLB ont été importés avec succès dans Godot 4.7.2. Résultats après les derniers réglages de fixation :

- [inspect_module_assets.py](../tools/inspect_module_assets.py) : `PASS`, octets GLB, UV, normales, indices, images embarquées, opacité, manifests et maximum de 17 032 triangles pour les accessoires du kit.
- [test_robot_module_visuals.gd](../tools/test_robot_module_visuals.gd) : `PASS (511 checks)`, vrai Player, catégories et combinaisons, os, rotation, châssis puissant, accessoires compacts, caches partagés, camouflage et restauration.
- [test_forge_module_stations.gd](../tools/test_forge_module_stations.gd) : `PASS (1172 checks; 0 failures)`, rangements, transport, montage, annulation, persistance isolée et cadrages sur les trois châssis. Le moteur signale trois objets encore présents pendant sa fermeture; les assertions et le code de sortie sont réussis.
- [capture_module_quality.gd](../tools/capture_module_quality.gd) : `PASS (90 fixed-frame comparisons)`, rendu natif Forward Mobile/Vulkan sur GTX 1660 SUPER, sans avancement de l'animation entre les images comparées. Échantillons inspectés de face, trois quarts, côtés et dos, au repos, à l'échauffement et en course.
- [test_forge_module_stations.gd](../tools/test_forge_module_stations.gd), parcours natif : `PASS (103 checks; 0 failures)`, installation réelle terminée en 7,033 s avec la boucle de rendu et les boutons de la forge.

Les captures sont dans `captures/module-fit/` et ne comportent ni interface ni surbrillance. La caméra, le cadrage et la lumière restent identiques entre les trois états. La matrice complète couvre face, trois quarts, côtés et dos, en poses `idle`, `warm_up` et `run`, aux formats 1600 × 900 et 960 × 540. La pose de course neutralise la translation des hanches dans la copie d'animation appartenant à la forge. Le manifest conserve projection, pose, orientation et équipement de chaque image.

Critères visuels : œil, contour de tête et cœur de poitrine visibles; protections d'origine dominantes dans la silhouette; accessoires plaqués à leur point de fixation, sans intersection apparente ni volume flottant; épaules, mains et arme dégagées pendant les poses. La cassette finale reste une petite pièce rapportée sous la protection d'épaule, avec une assise galbée et une profondeur de 5 cm; les vues de profil inspectées ne montrent plus le gros boîtier de la première version. Le réacteur suit une protection métallique derrière le bras et les propulseurs suivent les talons pendant la pose de course.

La vérification technique de taille ne remplace pas cette inspection et ne vaut pas acceptation esthétique par l'utilisateur. Le format 960 × 540 est un rendu paysage sur PC et ne mesure pas les performances d'un téléphone.

```powershell
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\BOTTEROOOW\PROTOTYPE-V0.1' --script res://tools/test_robot_module_visuals.gd
# Première comparaison de neuf images, avant la matrice complète :
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path 'C:\Users\BOTTEROOOW\PROTOTYPE-V0.1' --script res://tools/capture_module_quality.gd -- --quick
# Matrice complète de 90 images :
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path 'C:\Users\BOTTEROOOW\PROTOTYPE-V0.1' --script res://tools/capture_module_quality.gd
```
