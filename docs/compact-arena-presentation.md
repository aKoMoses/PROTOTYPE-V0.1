# Finitions et familles d'objets des maps 4 à 6

Héliostat, Serre engloutie et Cœur d'horloge partagent des familles d'objets et disposent chacune d'une recette artistique sous `art/environment/arena_recipes/`. La troisième passe reprend les vraies textures de béton, peinture et acier utilisées par la map 1, enrichit les gros obstacles et compose des machines et plantes proches de la caméra. Les deux premières avaient installé les finitions et les premières familles d'objets.

Le stage et les mécanismes gardent la propriété des collisions, des déplacements et du gameplay. `CompactArenaPresentation` attend leur construction, applique les matériaux, puis attache les habillages aux vrais corps et pivots. Aucune animation dupliquée, aucune collision supplémentaire.

## Composants réutilisables

| Fichier sous `scripts/environment/` | Rôle |
| --- | --- |
| `arena_art_recipe.gd` | Resource éditable : palette, textures couleur et normales, famille de couvert, échelle de grain, patine, usure et lumière. |
| `arena_scenery_materials.gd` | Partage les matériaux texturés de pierre, métal, peinture et céramique ; feuillage nervuré distinct. |
| `arena_visual_kit.gd` | Habillages de couverts, radiateurs, irrigation, jauges, grilles, plaques, engrenages, miroirs, fougères, palmes, stations de service et pendule. |
| `arena_set_dressing.gd` | Compose les stations et bouquets de premier plan hors du parcours, avec plaques de maintenance au ras du sol. |
| `arena_detail_batch.gd` | Primitives regroupées par matériau et ensemble ; UV explicites disponibles pour les feuilles. |
| `arena_architectural_props.gd` | Socles, colliers, jardinières, feuillage, conduites et cadrans de la première passe. |
| `arena_floor_finish.gd` | Clone les matériaux de sol et conserve les motifs ; ajoute grain, relief, fissures, joints abîmés et usure autour des objets. |
| `arena_mesh_finish.gd` | Corrige les faces de prismes visuels retournés, sur une copie du mesh. |
| `arena_contact_shadows.gd` | Composant issu de la map 1 : contacts à partir de collisions Box ou d'empreintes explicites, dont les jardinières convexes. |
| `compact_arena_presentation.gd` | Adaptateur de ces trois maps : recettes, habillages, placements, éclairage et qualité. |

`ArenaLightingProfile`, `ArenaSurfaceFinish` et les exclusions de `ArenaMaterialLibrary`, extraits de la map 1, sont aussi réutilisés. Le shader `arena_scenery_surface.gdshader` utilise les coordonnées locales : sa patine tourne avec l'objet. Les sols conservent les coordonnées et les dessins de la map.

Le grain du sol précédent multipliait des texels en espace linéaire puis les écrêtait presque tous à la même valeur : la texture perdait sa variation. La lecture est désormais normalisée par les valeurs moyennes du béton existant. Les fractures minérales traversent les dalles avec des trajectoires irrégulières. Les coordonnées de feuillage suivent chaque feuille pour afficher les nervures et colorer ses bords ; les silhouettes projettent des ombres.

Exemple indépendant de `main.gd`, attaché au corps physique existant :

```gdscript
var recipe := preload("res://art/environment/arena_recipes/heliostat.tres")
var materials := preload("res://scripts/environment/arena_scenery_materials.gd").new(recipe)
var kit := preload("res://scripts/environment/arena_visual_kit.gd").new(materials.palette())
kit.cover(collision.shape.size, recipe.cover_style, 3)
var result := kit.flush(body)
result.root.position = collision.position
# Le corps possède déjà son déplacement, sa collision et son contrôleur.
```

Pour une future map, créer sa recette, choisir ses familles d'objets et composer leurs placements dans son adaptateur de présentation. Enregistrer la recette et l'adaptateur dans le constructeur de map. Les composants donnent une base plus riche dès le départ ; la composition, les dimensions et la lisibilité à la caméra demandent encore un travail artistique propre à la map.

## Changements visibles

- **Héliostat** : trois batteries avec radiateurs à ailettes, collecteurs de cuivre, récepteurs et jauges ; deux miroirs avec cadres et socles assemblés. Six stations sur les terrasses, pierre et bronze texturés, dalles fissurées et usure autour des obstacles.
- **Serre engloutie** : trois jardinières fixes et deux barges flottantes avec irrigation, fougères et palmes nervurées, céramiques à joints et dépôts humides. Bouquets périphériques recomposés et quatre stations de pompage. Le bassin, ses rampes et sa marée restent pilotés par leurs mécanismes.
- **Cœur d'horloge** : deux couverts avec engrenages couplés et lampes d'avertissement segmentées, pendule en acier cerclé, moyeu détaillé et quatre stations d'entraînement sur le cadran extérieur. Acier et laiton texturés et fissures sur le cadran.

Les commandes dorées des miroirs, les avertissements lumineux, l'eau, les éléments transparents et les kits de réparation gardent leurs matériaux et leurs mises à jour. Héliostat conserve la direction du soleil.

Les surfaces continues de marche reçoivent les ombres sans en projeter sur elles-mêmes, comme le sol de la map 1. Cela supprime la trame diagonale d'auto-ombrage en Vulkan Mobile. Les biais d'ombres des recettes limitent aussi ce défaut sur les îlots et objets. Les silhouettes principales des couverts projettent des ombres ; les petits détails utilisent les contacts et l'éclairage de la scène. L'adaptateur ne change ni l'anticrénelage ni l'atlas d'ombres et restaure ses paramètres de lumière à la sortie.

## Qualité et coût de géométrie

| Map | Lots périphériques | Lots des nouvelles familles | Triangles des composants, trois passes cumulées |
| --- | ---: | ---: | ---: |
| Héliostat | 11 | 62 | 74 900 |
| Serre engloutie | 12 | 79 | 94 376 |
| Cœur d'horloge | 8 | 42 | 81 884 |

Ces nombres comptent les meshes produits par les composants, pas le coût complet de la scène ni un budget FPS. Les anciens habillages remplacés sont masqués. En qualité basse (`VFXManager.quality = 0`), les fixations fines, les ornements périphériques fins et les lumières décoratives existantes sont masqués ; silhouettes, panneaux, plantes et mécanismes restent présents. La qualité normale restaure les détails.

## Vérification locale

Godot 4.7.2 : import éditeur réussi, contrat de présentation **225 contrôles**, comparaison de la map classique **2 539 contrôles**, Héliostat **38 contrôles**, tests Serre et Horloge et suite des cinq maps compactes réussis. Le contrat compare collisions, dimensions, transformations, définitions et FOV au relevé pris avant les passes. Il vérifie aussi les familles dans un parent indépendant, les normales et dimensions des corps chanfreinés, les textures et leurs normales, les UV des plantes, les machines périphériques hors de l'empreinte jouable, les vrais matériaux d'avertissement, la qualité basse, les déplacements réels et la restauration de l'éclairage classique.

Captures en **Vulkan Mobile sur PC**, par le chemin du duel solo et sa caméra, en qualité normale et basse. Des vues supplémentaires montrent un miroir en rotation, la marée haute et les couverts de l'Horloge en rotation. Les comparaisons gardent les mêmes positions de caméra et de joueurs ; leurs modèles peuvent évoluer avec les travaux parallèles sur les équipements. Aucune mesure de FPS ni validation Android.

Preuves actuelles : `outputs/compact-arena-presentation/third-pass/`, avec `before/`, `after/`, `low/`, `reference/` et `comparison.html`. `after/` contient les vues de départ, une autre position de marche, les mécanismes actifs et les vues d'ensemble. Les captures de départ avant/après ont des positions, rotations et FOV identiques. Les anciennes preuves et les sources sauvegardées avant cette passe restent disponibles. Travail local, non publié.

Les captures de départ comptent respectivement 729 → 734, 739 → 751 et 624 → 637 appels de dessin pour Héliostat, Serre et Horloge. Ce sont des relevés ponctuels de scène sur PC, sans mesure de temps ni garantie de FPS Android. Les nouvelles familles sont plafonnées par le contrat à 84 lots et 100 000 triangles, auxquels s'ajoutent les petits ornements périphériques.

`tideglass-test.log` rejoue le test Serre à l'identique avec vidage de `GameSfx` avant fermeture : le script original laisse parfois des lectures WAV à la sortie. Cette adaptation du banc de test est conservée dans `second-pass/test-tideglass-cleanup.gd`. Le contrat de présentation arrête aussi ses lecteurs de musique avant fermeture avec le pilote Dummy ; aucun code audio du jeu n'a été changé.

```powershell
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --audio-driver Dummy --script tools/test_compact_arena_presentation.gd -- verify outputs/compact-arena-presentation/before/gameplay.json
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path . --audio-driver Dummy --resolution 1280x800 --rendering-method mobile --rendering-driver vulkan --script tools/capture_compact_arena_presentation.gd -- outputs/compact-arena-presentation/third-pass/review
```

Ajouter `low` après le dossier de sortie pour la qualité basse, ou un identifiant (`heliostat`, `tideglass`, `clockwork`) pour limiter la capture. L'option `compact-art-baseline` désactive l'adaptateur complet ; `second-pass/before` contient le relevé de la première passe effectué avant cette deuxième intervention.
