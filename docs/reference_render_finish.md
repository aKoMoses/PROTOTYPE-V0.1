# Finition lumineuse de la cour — 2 octobre 2026

La cour classique reçoit une finition supplémentaire pour rapprocher son rendu
des deux références : soleil doré, ombres filtrées, réflexions du ciel dans les
métaux, peinture en relief et fractures irrégulières du béton. Cette passe ne
constitue pas une reproduction identique des modèles et détails des images.

`scripts/environment/reference_render_finish.gd` est attaché à
`ArenaPresentation`. Il intervient après les adaptateurs existants et conserve
leurs textures, couleurs, placements et matériaux spéciaux. Les nouveaux
matériaux utilisent l'éclairage physique de Godot et des normales projetées dans
le monde. Les ressources sources sont conservées ; les finitions sont partagées
entre les instances d'une même matière.

Les ombres de contact des 44 couverts visibles sont regroupées en un MultiMesh,
sans collision, navigation ou lumière supplémentaire. La qualité normale utilise
un atlas d'ombres de 4096 px et MSAA 4x ; la qualité basse revient à 1024 px et
désactive MSAA. Les paramètres globaux d'ombres et le MSAA sont restaurés lorsque
la cour est libérée. Le budget existant de six lampes locales reste inchangé.

Le sol conserve son atlas de plaques, marquages, traces et réparations. Un shader
distinct ajoute un réseau de fractures interrompues, antialiasées, et augmente
le relief du béton. Les éléments médicaux, la végétation de camouflage, les acteurs, leurs
animations, les effets de combat et la caméra ne sont pas réécrits par cette passe.

Les contrôles sous Godot 4.7.2 ont réussi :

- Contrat complet : 48 obstacles, 14 volumes de camouflage, 4 soins, formes,
  transformations et caméra identiques au contrat de référence.
- Intégration de la finition : 28 contrôles avec Vulkan Mobile, sur deux
  chargements, changements de qualité et aller-retour classique/test/classique.
  Les ressources des acteurs, soins et buissons restent identiques.
- Présentation des ateliers et soins ; 164 contrôles de l'environnement partagé.
- Combat réel de six secondes : déplacements, sept tirs, perception du bot,
  projectiles et maintien des acteurs au sol, sans assertion en échec.
- Import éditeur et captures des shaders avec Vulkan Mobile.

Les preuves sont dans `outputs/reference-render/` (exclu de l'import Godot) :

- `before-center.png` et `final-center.png` : même caméra et positions ; interface
  masquée pour examiner les matériaux. Le mécha puissant/mekatana est sélectionné
  seulement dans le captureur, sans modifier les préférences enregistrées.
- `final-metrics.json` confirme la conservation du cadrage de comparaison.
- `low-center.png` : petite fenêtre, interface, qualité basse et aspect expansé.
- `map-review.png` : vue complète de contrôle avec une caméra supplémentaire et
  des distances d'ombres/culling adaptées à cette seule capture. Elle n'est pas
  la caméra de gameplay. Le premier `overview.png`, plus distant, n'est pas la
  capture finale de comparaison.
- `integration-rendered.log`, `contract.log`, `workshop.log`, `stylized.log`,
  `courtyard.log`, `combat.json` et `import.log` : résultats des vérifications.

Le binaire vérifié sur ce PC est
`C:\Users\Ben\Desktop\Prototype 0\Godot_v4.7.2-stable_win64_console.exe`.
Les chemins RomainOpen d'AGENTS.md sont absents sur cette machine. Dans la sandbox,
les messages préexistants de certificats, stockage GD-Sync, cache de shaders et
préférences éditeur restent présents ; ils figurent aussi dans la capture initiale.
Les captures courtes ne mesurent pas les FPS soutenus. Android physique n'est pas
vérifié pour cette passe.

Réservation : `Prototype-Work: b20ca109-c23e-4bf2-a561-b74c3104e126`.
Travail local, sans commit ni publication pour cette passe.

## Deuxième passe

La reprise de la même réservation ajoute de la patine et de petits éclats
irréguliers sur la peinture, de la poussière sur les métaux et des fragments
près des bases des ateliers. Les éclats géométriques des rebords sont discrets,
sans modifier les volumes des obstacles. Le béton reçoit des fissures plus
anguleuses, avec un épaulement clair écaillé et un creux sombre en relief.

`art/environment/reference_finish/detail_builder.gd` produit une composition
déterministe de feuilles pliées, petites plantes, cailloux et rochers à facettes.
Les plantes hautes restent au-delà du mur jouable ; les débris intérieurs restent
sous 12 cm. Les anciens rochers décoratifs arrondis sont masqués et remplacés au
même emplacement. Le désert extérieur utilise un shader de sable et de croûtes
rocheuses, avec le grain de béton existant.

Ces ajouts sont répartis en cellules de 32 m, sous la branche de présentation.
Le contrôle d'intégration limite leur coût à 75 000 triangles et 48 lots, vérifie
que les feuilles restent au-delà de 29,8 m du centre sur au moins un axe, et
contrôle la désactivation de leurs ombres en qualité basse. Ils ajoutent zéro
collision, navigation ou lumière. Ils disparaissent dans l'arène test et
reviennent dans la cour classique.

La seconde passe a réussi 116 contrôles d'intégration avec Vulkan Mobile,
le contrat complet des 48 obstacles, 14 buissons et 4 soins, et le contrôle
de présentation des ateliers. Le combat réel de six secondes a produit huit
tirs, des projectiles et des déplacements du bot, avec les acteurs au sol et
aucune assertion en échec. L'import final ne présente pas d'erreur de compilation
de cette passe. Les messages de stockage et cache cités plus haut subsistent.

Captures finales de cette reprise :

- `pass2-finish-center.png` : caméra de gameplay et positions identiques à la
  première passe, confirmées par `pass2-finish-metrics.json`.
- `pass2-map-final.png` : vue complète de contrôle avec la caméra diagnostique.
- `pass2-low-west.png` : bord ouest, interface et qualité basse en fenêtre 960×540.
- `pass2-integration.log`, `pass2-contract.log`, `pass2-workshop.log`,
  `pass2-combat.json` et `pass2-import-final.log` : vérifications de cette reprise.

Les changements simultanés d'ambiance des ateliers appartiennent à l'autre
travail actif et sont conservés. Les captures intermédiaires avaient rencontré
sa ressource en cours d'écriture ; les contrôles et captures finales ont ensuite
été exécutés avec cette ressource chargée. Le rendu reste une approximation 3D
des références. Cette reprise reste locale et non publiée.
