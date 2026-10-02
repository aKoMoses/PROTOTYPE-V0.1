# Finition de la cour étendue à toutes les maps — 2 octobre 2026

La famille visuelle validée pour la cour est maintenant utilisée sur toutes les
maps jouables : duel classique et piégé, plateformes, entraînement, casse de
survie, passage et usine. Le plan des maps reste celui du jeu ; les ajouts sont
des détails sur les obstacles existants, des équipements en bordure et des
matériaux au sol.

| Map | Décor adapté | Triangles statiques ajoutés | Lots spatiaux | Toiles | Câbles |
| --- | --- | ---: | ---: | ---: | ---: |
| Classique / piégée | Cour détaillée existante, ateliers et enseignes | 479 186 | 221 | 14 | 16 |
| Plateformes | Quatre couverts équipés, protections de pont, ateliers de bordure | 111 592 | 65 | 4 | 4 |
| Entraînement | Caisses et abris équipés, bâches, enseignes, panneaux et câbles des séparateurs | 137 958 | 128 | 14 | 5 |
| Survie, passage et usine | Épaves patinées, machines équipées, bannières, raccords de cuves, ateliers et câbles | 149 412 | 130 | 10 | 7 |

Les nombres excluent les toiles et les petits bouquets d'herbes décoratifs.
Le décor ajouté utilise 369 ressources de géométrie externes, environ 30 Mio.
Les trois scènes de décoration font chacune moins de 90 Ko et réutilisent les
matériaux de la cour. Aucun objet de physique ou de navigation n'est ajouté.

## Sols et rendu

Les cinq nouveaux atlas suivent les coordonnées réelles des maps : 36 × 30 m
pour les plateformes, 88 × 76 m pour l'entraînement, 48 × 48 m pour la casse et
l'usine, 8 × 12 m pour le passage. Béton, joints, fissures, éclats, traces de
pneus, usure fragmentée, marquages jaunes et huile sont précalculés. Les PNG
sont importés avec compression VRAM et mipmaps ; l'entraînement utilise un
atlas de 4096 px, les autres de 2048 px.

Les couleurs des zones d'entraînement restent lisibles sur le béton. La route
de la casse conserve son tracé. Les neuf plaques de service existantes portent
un acier strié, des bordures et des boulons ; leur matériau est partagé. Les
machines de l'usine reprennent les panneaux crème, l'acier bleu, les tuyaux,
les lampes et les bannières de la cour.

Le contrôleur suit la caméra réelle et partage un budget maximal de six lampes
de décor, sans ombres locales. La qualité basse désactive ces lampes et réduit
le vent et les ombres des petites herbes. Les lampes des armes et des effets de
combat gardent leur propre contrôle. Le passage dans l'usine rétablit le soleil
chaud et l'ambiance froide de cette passe après le changement de zone.

## Vérification

Godot 4.7.2, Vulkan Mobile, RTX 3070 Laptop GPU. Résultats dans
`outputs/all-maps-reference/` :

- `test-reference-final.stdout` : **1 260 contrôles réussis**, signatures de
  physique, groupes de jeu et caméras identiques avant/après ; ressources
  chargées intégralement, neuf plaques conservées, budget de lampes et
  transitions vérifiés.
- `test_stylized_environment.stdout` : **164 contrôles réussis**, matériaux des
  acteurs/VFX protégés, préparation répétée sans duplication. Le test attend
  désormais la fin du démarrage différé des acteurs avant sa comparaison.
- `test_test_arena.stdout` : parcours des deux rampes dans les deux sens,
  pont, couverts, navigation du bot, camouflage, soins et changement de map.
- `test_training_ground.stdout` : cibles, projectiles, zones et interface.
- `test_survival_zones.stdout` : ouverture de la porte, traversée, entrée dans
  l'usine et combat dans cette zone.
- `test_arena_hazards.stdout` : sélection, pièges, dégâts neutres, pause et reset.
- `test_workshop_presentation.stdout` : ancienne cour, qualité, suivi de caméra
  et limite des lampes toujours fonctionnels.

Les captures utilisent les caméras de production, avec un champ de vision de
38°. `capture.json` et `capture-low.json` décrivent les vues normales et basses.
Les vues normales masquent l'interface de premier plan pour examiner le décor ;
les vues basses gardent l'interface. Aucun réglage de joueur n'est sauvegardé.
Il s'agit de contrôles de rendu, pas d'un benchmark de FPS ni d'un test sur
appareil Android. Les avertissements de certificat, configuration GD-Sync,
préférences de l'éditeur et cache de shaders sont ceux de la sandbox.

Les travaux d'animations et de finition lumineuse menés dans les autres chats
sont conservés. Les assertions de cette passe ne certifient pas leurs ajouts
ultérieurs.

## Aperçus réels

- [Cour classique](../outputs/all-maps-reference/classic.png)
- [Cour piégée](../outputs/all-maps-reference/hazards.png)
- [Plateformes](../outputs/all-maps-reference/test.png)
- [Entraînement : placement](../outputs/all-maps-reference/training.png)
- [Entraînement : cibles fixes](../outputs/all-maps-reference/training-fixed.png)
- [Entraînement : cible mobile](../outputs/all-maps-reference/training-moving.png)
- [Entraînement : tireur](../outputs/all-maps-reference/training-shooter.png)
- [Casse](../outputs/all-maps-reference/survival.png)
- [Passage](../outputs/all-maps-reference/passage.png)
- [Usine](../outputs/all-maps-reference/factory.png)

Reproduction : `tools/environment/build_map_reference_floors.py`, puis
`tools/environment/build_map_reference_dressing.gd`, import Godot et captures
avec `tools/capture_map_reference.gd`. Le décor de la cour classique n'a pas été
recalculé pendant cette extension.

Réservation : `Prototype-Work: 1c46345a-ede3-40a2-a5c9-358f7d311bde`.
Travail local ; aucune publication annoncée.
