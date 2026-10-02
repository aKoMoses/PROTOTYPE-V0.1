# Cour de récupération : détails de la référence, 2 octobre 2026

La passe rapproche l'arène classique de l'image de référence : béton écaillé et
fissuré, traces de pneus et d'huile, marquages jaunes usés, acier bleuté, établis
et tiroirs en relief, bidons cerclés, instruments, outils, raccords et câbles.
Les enseignes « ATELIER 07 » et « PIECES » ont des tubes de néon, des fixations,
un compartiment rouge pour le numéro et une clé cyan. Les toiles portent des
plis, un bord poussiéreux et, pour les bannières, un engrenage crème patiné.
Les herbes olive/paille sont plus denses, entourées de pierres, petits éclats et
pneus creux. Les plaques de soin ont une croix blanche et des coins ambrés.

Il s'agit de géométrie et de matériaux rendus dans le jeu. La capture conserve
sa caméra de production. L'éclairage, la silhouette des ateliers et leur niveau
de détail ne constituent pas une reproduction exacte de chaque élément du
concept ; les captures permettent de comparer le résultat réel.

## Intégration et fabrication

- `scenes/environment/arena_presentation.tscn` charge maintenant
  `scenes/environment/reference_workshop_dressing.tscn`.
- `tools/environment/build_workshop_dressing.gd` précalcule le décor dans
  `art/environment/reference_workshops/` : 479 186 triangles statiques, 221 lots
  spatiaux indexés, 14 panneaux de toile et 16 lignes électriques suspendues.
  Les supports des câbles traversant les allées restent au-dessus du combat.
  Le contrôleur existant garde le budget de six lampes locales sans ombres.
- `tools/environment/build_courtyard_materials.py` régénère l'atlas de 4096 px,
  le relief et les normales. Les trois albedos de matière existants sont
  conservés. Les fissures, traces et réparations sont placées à l'échelle du sol.
- `stylized_courtyard.gdshader` conserve les emplacements de l'atlas et renforce
  le détail du béton avec sa couleur moyenne réelle. Le shader de récupération
  garde l'usure des textures, un acier plus clair et le relief des surfaces
  projetées dans le monde. Les paramètres de matière restent partagés.
- `bush_visual.gd` et son shader épaississent les herbes sans modifier les
  volumes de camouflage ni utiliser la position d'un adversaire caché.
- `repair_socket_presentation.gd` adapte seulement les matériaux et la croix.
  Le parent garde collecte, soin, recharge et désactivation.

Les anciens fichiers générés de `art/environment/workshops/` et
`scenes/environment/workshop_dressing.tscn` ont été rétablis à leur contenu
Git après sauvegarde vérifiée. Les copies et leurs sommes SHA256 sont dans
`outputs/reference-fidelity/legacy-generated-backup/` et
`legacy-backup-manifest.json`. Les autres travaux locaux sont conservés.

## Vérification et captures

Godot 4.7.2, Vulkan Mobile, RTX 3070 Laptop GPU. Sur ce PC, le binaire vérifié est
`C:\Users\Ben\Desktop\Prototype 0\Godot_v4.7.2-stable_win64_console.exe` ; les
chemins RomainOpen de l'autre contributeur sont absents.

Les résultats et captures sont dans `outputs/reference-fidelity/` :

- `contract-complete.json` correspond exactement à `baseline-contract.json` :
  48 obstacles, 14 buissons, 4 soins, formes, transformations et caméra.
- `workshop-complete.stdout` : aucun objet de physique/navigation ajouté,
  matériaux et triangles chargés intégralement, budget lumineux, déplacement
  de caméra et transitions arène classique / test / classique vérifiés.
- `stylized-complete.stdout` : 164 contrôles réussis sur duel, entraînement et
  survie ; matériaux spéciaux, acteurs, caméras et physique préservés.
- `combat-complete.stdout`, `test_bush_gameplay.stdout` et
  `courtyard-final.stdout` : finitions de combat, camouflage, soin de 30 %,
  collecte, recharge et changements de qualité vérifiés.
- `live-combat.json` : combat de six secondes avec les commandes du jeu,
  déplacements, perception du bot, tirs, projectiles, acteurs au sol et bornés.
- `final-concept.png` : rendu réel, interface masquée pour examiner le décor,
  équipement existant puissant/mekatana sélectionné uniquement dans le
  captureur ; aucune préférence sauvegardée. `final-metrics.json` confirme une
  caméra identique à la capture initiale.
- `game-*.png` : cinq vues avec l'interface et l'équipement enregistré normal.
  `low-concept.png` : petite fenêtre avec interface, qualité basse et aspect
  expansé comme sur mobile.

L'import de l'éditeur est terminé. Dans la sandbox, les avertissements de
préférences, cache de shader, certificat et configuration GD-Sync existent
également avant cette passe ; ils n'empêchent ni le rendu ni les assertions.
Les captures de contrôle utilisent huit échantillons : leurs temps ne sont pas
un benchmark de FPS soutenu. Aucun appareil Android physique n'a été testé
pour cette passe.

Réservation : `Prototype-Work: 1c46345a-ede3-40a2-a5c9-358f7d311bde`.
Travail local ; aucune publication annoncée.
