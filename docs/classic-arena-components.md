# Construction et composants de la cour classique

La map 1 conserve son implantation, ses assets, ses collisions, ses soins, ses
buissons et sa présentation. Sa construction quitte `main.gd`, qui conserve la
gestion de la partie, des acteurs, de la caméra et des changements d'arène.

## Répartition

| Fichier | Responsabilité |
| --- | --- |
| `scripts/arenas/classic_arena_builder.gd` | Construction de la cour, placements, dimensions, extérieur, gradins et choix des positions des buissons. |
| `scripts/environment/arena_prop_factory.gd` | Objets paramétrables : couverts, pneus, caisses, tonneaux, lampes, socles de réparation, végétation, bannières, rochers et silhouettes industrielles. |
| `scripts/environment/arena_material_library.gd` | Recettes et caches de matériaux, conversion des matériaux opaques vers les surfaces peintes. |
| `scripts/environment/arena_surface_finish.gd` | Finition des surfaces peintes et métalliques, du sol et du terrain extérieur. |
| `scripts/environment/arena_contact_shadows.gd` | Ombres de contact regroupées dans un seul MultiMesh, sans collision ni lumière supplémentaire. |
| `scripts/environment/arena_lighting_profile.gd` | Profil configurable de lumière, de ciel, de reflets et de qualité de rendu. |
| `scripts/environment/reference_render_finish.gd` | Adaptateur de la cour : sélection du décor, application différée des composants, détails de bordure et suivi de qualité. |

L'autoload `stylized_environment.gd` utilise la même conversion de matériaux que
la bibliothèque. La finition de surface accepte aussi directement les matériaux
opaques des objets : une nouvelle map peut l'appeler sans dépendre de la liste de
scènes reconnues par cet autoload. Les matériaux émissifs, transparents, spéciaux
et les shaders inconnus conservent leur traitement.

## Créer des objets dans une autre map

Créer une fabrique par instance de map. Son parent doit être un `Node3D` présent
dans l'arbre, à échelle unitaire. Les positions des objets sont locales à ce
parent ; il peut être déplacé ou tourné. Les centres de camouflage sont stockés
en coordonnées mondiales. Déplacer le parent après construction nécessite de
mettre à jour ces centres et de reconstruire les ombres de contact.

```gdscript
const PROPS = preload("res://scripts/environment/arena_prop_factory.gd")
const FINISH = preload("res://scripts/environment/arena_surface_finish.gd")
const CONTACTS = preload("res://scripts/environment/arena_contact_shadows.gd")

var blockers: Array[StaticBody3D] = []
var lamps: Array[OmniLight3D] = []
var props := PROPS.new(self, blockers, lamps)
var cover := props.create_scrap_barrier(
    "WestCover", Vector3(-6, 1, 0), Vector3(4, 2, 1), 25
)
props.create_tire_stack("Tires", Vector3(-7, 0, 2), 3)
props.create_hanging_lamp("Lamp", Vector3(0, 4, -6))
props.create_bush_cluster("Bush", Vector3(4, 0, 0), 1.0, Vector3(4, 0, 0))

var finish := FINISH.new()
# Sélectionner explicitement les objets de décor, puis leurs meshes.
for mesh in cover.find_children("*", "MeshInstance3D", true, false):
    finish.finish_mesh(mesh)
var contact_entries: Array[Node3D] = [cover]
# Hauteur du sol en coordonnées mondiales.
CONTACTS.build(self, contact_entries, global_position.y + 0.012)
```

Les listes fournies à la fabrique lui permettent d'enregistrer les vrais
couverts et les lampes animables. La map garde la responsabilité de leur cycle
de vie, de la navigation et du clignotement. Pneus, lampes et détails décoratifs
n'ajoutent pas de colliders. Les contacts attendent des corps comportant un enfant
`Collision` avec une `BoxShape3D` ; exclure les limites invisibles de cette liste.

Les soins utilisent les scènes existantes `repair_kit.tscn` et
`environment/repair_socket.tscn`. Les couverts conservent leurs meshes et
matériaux d'origine. Les recettes partagent les matériaux dans une fabrique,
sans partager les matériaux créés entre deux fabriques. La finition clone les
matériaux au lieu de modifier les ressources sources et peut être réappliquée.

## Configurer la lumière

```gdscript
const LIGHTING = preload("res://scripts/environment/arena_lighting_profile.gd")

var profile := LIGHTING.new()
profile.sunlight_energy = 0.9
profile.ambient_energy = 0.35
profile.apply(world_environment.environment, sun, fill)
profile.apply_render_quality(get_viewport(), quality)
```

Le profil conserve la direction du soleil choisie par la map. Ses valeurs par
défaut reproduisent la finition actuelle de la cour. Le constructeur garde les
réglages initiaux de l'environnement ; l'adaptateur applique ensuite le profil
dans le même ordre que les anciennes passes visuelles.

`apply_render_quality` modifie l'anticrénelage du viewport et les réglages
globaux des ombres directionnelles. Le propriétaire doit sauvegarder et
restaurer ces réglages lorsqu'il quitte sa scène, comme le fait
`reference_render_finish.gd`. Les contacts n'ont besoin d'aucun éclairage
supplémentaire. La finition du sol attend le shader `stylized_courtyard` avec
le layout de la map ; elle ne copie pas le layout de la cour sur une autre map.

## Compatibilité et suite

La construction garde les enfants sous la racine `Main`. Cela conserve les
chemins utilisés par la visibilité, les pièges et les adaptateurs artistiques.
Les quelques méthodes de fabrique encore utilisées par la map test restent
accessibles via `main.gd` et délèguent au nouveau constructeur.

Les placements des ateliers et des détails de bordure restent spécifiques à la
cour, dans leurs scènes et recettes existantes. Les maps 4, 5 et 6 ne changent
pas d'apparence dans cette étape. Elles pourront utiliser progressivement les
composants, avec leurs placements, palettes et mécanismes propres.

## Vérification

Le test autonome suivant vérifie la création d'objets sous une autre racine,
leurs collisions, le camouflage, l'indépendance des caches, les ressources
sources et un profil lumineux distinct :

```powershell
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_classic_arena_components.gd
```

Le mode `verify CHEMIN.json` compare également la cour à un instantané créé avec
`record CHEMIN.json` avant extraction : hiérarchie, géométrie, shaders,
collisions, métadonnées, lumières et caméra. Les phases des animations
d'ambiance sont exclues ; leurs recettes et géométries sont comparées.
Le contrôle du transform des instances MultiMesh nécessite un rendu graphique,
car le renderer factice headless ne conserve pas ces transforms.

Les preuves locales de cette migration sont dans
`outputs/classic-arena-components/` : sauvegardes avant extraction, instantané,
captures avec la caméra de production en qualité normale/basse et résultats des
tests. Les captures de revue ne constituent pas un benchmark de performance.

Résultats de la migration :

- 1 259 nœuds de décor comparés ; 2 539 contrôles de conservation/réutilisation
  passent en headless, et 19 contrôles de réutilisation passent avec Vulkan,
  incluant les coordonnées des ombres de contact.
- Les tests d'arène fiable, d'arène test, de combat réel et du cycle des cinq
  arènes compactes passent. Les 48 blockers et les 14 buissons de la cour sont
  conservés.
- Le test de finition stylisée passe ses 167 contrôles, y compris les scènes
  Training et Survival. L'import de l'éditeur ne produit pas d'erreur de script.
- Les captures normale/basse utilisent la même caméra qu'avant. Elles gardent
  respectivement 1 132 et 1 101 appels de dessin sur GTX 1660 SUPER. L'écart
  absolu moyen des pixels RGB est inférieur à un niveau sur 255 ; les animations
  d'ambiance ne sont pas synchronisées entre deux processus.

Le test compact signale aussi des ressources retenues à la fermeture de son
processus ; son résultat fonctionnel est `PASS`, sans échec de scénario.

Deux contrôles anciens échouaient déjà avant l'extraction : le contrat figé de
caméra dans `test_arena_contract.gd`, et le contrat global après aller-retour
dans `test_reference_render_finish.gd`. Les mêmes échecs ont été reproduits
avec les scripts sauvegardés avant modification. Les réglages actuels ne sont
pas changés pour satisfaire ces anciens contrats.
