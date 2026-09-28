# Droïde ennemi — inspection et intégration visuelle

## Source inspectée

Fichier fourni : `C:/Users/Ben/Downloads/humanoid+combat+robot+3d+model (1).glb`, glTF 2.0 produit par Tripo. L'analyse lit les données binaires et échantillonne les poses à 60 Hz ; elle ne modifie pas le GLB. Les mesures exhaustives, la hiérarchie complète et les transformations locales des 65 bones sont dans `enemy_droid_source_audit.json`. L'inspection Godot complémentaire est dans `enemy_droid_godot_audit.json`.

- Racine de scène : `ParentNode`, puis `Armature`.
- Squelette importé : `ParentNode/Armature/Skeleton3D`, 65 bones.
- Racine squelettique : `mixamorig:Hips` dans le GLB, `mixamorig_Hips` dans Godot.
- Main droite : `mixamorig:RightHand` / `mixamorig_RightHand` ; main gauche : `mixamorig:LeftHand` / `mixamorig_LeftHand`.
- Bras droit : `Spine → Spine1 → Spine2 → RightShoulder → RightArm → RightForeArm → RightHand`. Branche symétrique gauche ; cinq chaînes de doigts par main.
- Jambes : `Hips → LeftUpLeg → LeftLeg → LeftFoot → LeftToeBase → LeftToe_End`, et branche droite symétrique.
- Tête : `Spine2 → Neck → Head → HeadTop_End`.
- Lecteur : `AnimationPlayer` à la racine, `root_node = ..`, une `AnimationLibrary` de nom vide.
- 55 meshes, 7 955 sommets. Bornes de repos : X ±0,37183 ; Y 0–0,99951 ; Z ±0,09888, en unités source.

L'avant anatomique est **+Z**, au repos comme dans les clips de marche, course et tir. La rotation locale de `Hips` au repos est environ −90° sur Y, mais elle décrit l'orientation interne du bone : elle ne doit pas servir seule à déduire l'avant du personnage. La correction visuelle retenue est Y = 180°, échelle uniforme = 1,9, pour obtenir l'avant Godot −Z et une taille d'environ 1,9 m.

## Les dix animations réellement présentes

Le format glTF ne définit pas de drapeau standard de boucle. L'import direct Godot inspecté donne `LOOP_NONE` pour les dix clips. Les boucles ci-dessous sont donc une décision d'intégration, appliquée à des copies privées des animations.

| Nom exact | Durée (s) | Observation mesurée | Usage retenu |
| --- | ---: | --- | --- |
| `turn` | 3,833333 | Demi-tour d'environ 176,7°, translation horizontale nette 0,335 | Conservé en prévisualisation ; ne pas superposer sa rotation à la visée gameplay |
| `idle` | 15,333333 | Retour quasi exact à la pose initiale ; balancement latéral jusqu'à 0,185 | Attente normale, boucle ; root horizontal neutralisé |
| `warm_up` | 18,291666 | Longue gestuelle d'échauffement, flexions et déports | Conservé en prévisualisation ; aucune nouvelle capacité de combat |
| `walk` | 2,333333 | Avance +Z de 1,664451 ; pose cyclique à 0,053° près | Locomotion lente, boucle en place, lecture inversée pour recul |
| `wait` | 6,000000 | Très faible déplacement, raccord cyclique à 0,013° près | Variante d'attente hors combat |
| `look_around` | 15,583333 | Observation, petit déport et raccord de pose imparfait (~4,62°) | Variante hors combat, interrompable par fondu |
| `cast_a_spell` | 5,375000 | Geste de bras expressif, forte amplitude, retour à la pose de départ | Conservé en prévisualisation, sans inventer d'attaque magique |
| `run` | 1,250000 | Avance +Z de 3,249670 ; décalage initial Z = 0,570905 | Locomotion rapide, boucle en place, raccord final corrigé |
| `fall` | 3,000000 | Chute complète latérale, rotation de bassin ~88,9° | Mort non bouclée, pose terminale maintenue |
| `fire` | 1,500000 | Posture de tir avec petit recul ; main droite globalement stable | Pose de visée extraite à 1,45 s et tir filtré sur le haut du corps |

Il n'y a aucun clip distinct de strafe, de marche arrière ou de réaction aux dégâts. Le déplacement latéral est obtenu en orientant le bas du corps selon la vitesse réelle tout en gardant le haut du corps orienté vers la cible. Le recul réutilise la locomotion inversée ; la réaction aux dégâts reste une petite correction visuelle procédurale. Les dix clips restent accessibles pour inspection, mais les gestes incompatibles ne sont pas déclenchés artificiellement pendant un combat.

## Déplacement et continuité

Vitesses de référence calculées depuis le déplacement root source :

- Marche : 1,664451 / 2,333333 = **0,713336 unité/s**, soit **1,355338 m/s** à l'échelle 1,9.
- Course : 3,249670 / 1,25 = **2,599736 unités/s**, soit **4,939498 m/s** à l'échelle 1,9.

La cadence dépend de la vitesse horizontale réellement observée, pas d'un simple booléen « déplacement ». La translation horizontale du root est neutralisée pour les animations ordinaires, y compris son décalage initial dans `run` ; la hauteur et les rotations du bassin restent animées. Le personnage visuel ne doit jamais déplacer le corps de collision.

Le clip `run` présente un raccord source imparfait : jusqu'à 12,31° sur les jambes et 19,50° sur un bras. Une fermeture douce sur les dernières 100 ms évite un saut de pose à chaque tour. Cette correction et la synchronisation de cadence limitent les glissements ; elles ne constituent pas un système de verrouillage des pieds au sol.

## Visée, arme et ordre d'évaluation

Le modèle de blaster existant `art/player_heavy_blaster.glb` est réutilisé conformément au choix utilisateur. Son canon source +X reçoit une correction de montage de +90° sur Y pour produire un axe d'arme −Z. Le socket est enfant d'un `BoneAttachment3D` lié à la main droite ; son transform local reste fixe après calibration. Le `Muzzle` et le repère de support gauche sont enfants de l'arme.

L'instant **1,45 s** de `fire` est le plus stable selon la vitesse angulaire locale RMS des treize bones du haut du corps, évaluée sur une fenêtre centrée de 100 ms : 0,387°/s. Positions des mains dans l'espace source : droite (−0,072595 ; 0,755797 ; 0,083270), gauche (−0,026403 ; 0,788206 ; 0,157837). Sur tout le clip, la rotation globale de la main droite ne s'éloigne que de 2,688° de son orientation initiale ; son déplacement de recul sur Z est d'environ 0,01455 unité. Le clip fourni ne contient pas de grande levée de bras vers le ciel.

L'architecture retenue évalue un `AnimationTree` manuellement, mélange le bas du corps avec la pose de visée et le tir filtrés, applique ensuite une seule résolution de pose, puis actualise les attaches. Le correcteur de visée oriente le canon vers la cible et la main gauche rejoint le repère de support. Au tir, le transform du muzzle est lu après cette évaluation, dans le même pas de simulation. Les animations ne déclenchent aucun dégât et ne changent pas la cadence gameplay.

## Mort et remise à zéro

`fall` est bien une chute complète : le bassin passe de Y = 0,511135 à 0,172684, avec un déplacement horizontal (0,819534 ; −0,158192). À 2,25 s, la tête est déjà à Y = 0,185 ; à 3 s, les bornes du mesh sont Y = 0,032081–0,268077. La planche `exports/enemy-droid-review/source-clips.png`, inspectée visuellement, confirme la pose allongée. L'absence de plan de sol dans cette planche ne permet pas à elle seule de valider le contact au sol en jeu.

La translation relative de la chute doit être préservée, contrairement à la locomotion. Une lecture à **×3** termine les 3 s source en **1 s**, avant le délai de réapparition existant de 1,25 s. L'état mort doit couper la visée et le tir, refuser de nouvelles réactions visuelles, conserver sa dernière pose, puis revenir explicitement à `idle` lors du reset.

## Architecture finale

Le `StaticBody3D` et le script `TargetDummy` existants restent responsables de la collision, de la santé, des effets et de la mort. `TrainingBot` conserve les décisions de poursuite, de ligne de vue et d'attaque. La nouvelle couche `VisualRoot`, créée par `target_dummy.gd`, ne pilote donc aucun déplacement gameplay.

À l'intérieur de `VisualRoot`, `enemy_droid_visual.gd` instancie le GLB, construit son `AnimationTree`, puis ajoute un `BoneAttachment3D` sur `mixamorig_RightHand`. Celui-ci contient le `WeaponSocket` fixe, le blaster, son `Muzzle` et le repère `LeftHandGrip`. `enemy_droid_pose.gd` effectue la passe finale de visée, de maintien à deux mains, de recul et de réaction aux impacts après l'évaluation des animations.

Au moment de tirer, `TrainingBot` demande d'abord au visuel de préparer la pose. Le projectile part ensuite du transform réellement évalué de `Muzzle`, avec les mêmes dégâts, portée, délai de préparation et temps de trajet qu'avant. La cible visuelle n'est actualisée que lorsque la ligne de vue gameplay est valide, ce qui évite que le modèle suive un joueur caché à travers le décor.

## Validation finale

Le test automatisé `tools/test_enemy_droid_visual.gd` a été exécuté avec Godot 4.7.2 sur l'intégration finale : **510 contrôles réussis, 0 échec**. Il couvre 216 combinaisons de direction, hauteur de cible et vitesse de déplacement, ainsi que sept tirs successifs, la mort, le reset, la pause, l'étourdissement, les dix animations de prévisualisation, deux instances simultanées et l'absence de modification des ressources importées.

- Erreur angulaire maximale du muzzle : **0,027977°**.
- Écart maximal entre la main gauche et son support : **0,016867 m**.
- Écart du point d'attache de la main droite : **0 m**.
- Translation horizontale résiduelle du bassin pendant la locomotion : **0 unité source**.
- Dérive après sept tirs et après un reset en plein recul : **0 m**.

Les régressions ciblées `test_training_bot.gd`, `test_target_dummy.gd`, `test_visibility.gd`, `test_game_flow.gd`, `test_blaster.gd`, `test_player_visual_rig.gd` et `test_combat_state.gd` passent également. Les données détaillées sont enregistrées dans `exports/enemy-droid-review/test-report.json`.

Les captures finales `01_idle.png` à `10_reset.png` montrent la visée de face et de profil, la marche, le strafe, le recul, la course, le tir, la chute et le retour à l'état initial. `arena-bot.png` confirme le remplacement du bot dans la scène principale. La seule erreur visible dans les journaux de capture est l'accès au magasin de certificats racine Windows depuis l'environnement isolé ; elle est extérieure au projet et n'affecte ni l'import, ni l'exécution, ni le rendu.
