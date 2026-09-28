# PROTOTYPE 0 — AimPose et recul du blaster

Passe du 27 septembre 2026. Projet modifié : `C:\Users\Ben\Documents\Codex\2026-09-23\j-ai-x20\outputs\PROTOTYPE-0`.

Le blaster est désormais tenu dans une pose de visée persistante. Le tir applique une impulsion au squelette, puis revient à cette même pose. Le socket, la racine de l’arme et ses wrappers ne fabriquent aucun mouvement indépendant sur le rig animé.

## 1–3. Source, frame et différence de pose

Le GLB contient 65 os et neuf animations : `bow`, `warm_up`, `run`, `fall`, `fire`, `idle`, `box_01`, `afraid`, `walk`. Aucune animation `aim`. `fire` dure 1,5 s.

Le runtime inspecte treize os du haut du corps à 60 Hz. Chaque candidat est évalué sur une fenêtre centrée de 100 ms ; le critère est la vitesse angulaire locale RMS. Les extrémités sont exclues pour comparer des fenêtres de même durée. Le minimum du clip importé par Godot est **1,433333 s, frame 86 à 60 Hz**, RMS **0,391469 °/s**. L’analyse indépendante du GLB brut trouve le minimum voisin à 1,45 s ; l’optimisation des pistes à l’import explique que le minimum du clip effectivement exécuté puisse différer légèrement. Aucun frame n’est imposé arbitrairement.

Mesures du GLB brut, comparées à `idle` au temps 0 :

| Os | Idle → frame 86 | Variation maximale dans fire |
|---|---:|---:|
| Spine | 2,503° | 0,690° |
| Spine1 | 26,792° | 0,249° |
| Spine2 | 14,839° | 0,244° |
| RightShoulder | 53,068° | 1,789° |
| RightArm | 92,977° | 3,578° |
| RightForeArm | 73,089° | 3,455° |
| RightHand | 34,439° | 5,951° |

Ces valeurs confirment une posture de tir très différente de l’idle, avec peu de mouvement interne. Les translations locales des treize os examinés sont constantes dans `fire`. Diagnostic reproductible : `tools/analyze_aim_pose.mjs --sample=1.4333333333333333 --json-output=exports/aim-source-analysis.json` avec Node.js.

## 4–5. AnimationTree et visée persistante

Avant : BasePose + locomotion filtrée sur les jambes + `fire` en OneShot upper-body, accéléré pour suivre le cooldown, puis retour vers idle.

Après : BasePose + locomotion filtrée sur les jambes + `runtime/AimPose` en Blend2 upper-body persistant. AimPose contient **43 pistes de rotation constantes**, sans translation, échelle, hanches, jambes ou root motion. Le clip source n’est pas réécrit dans le GLB.

Après l’AnimationTree, le modifier existant oriente les jambes, puis `PlayerAimModifier` stabilise l’orientation globale de Spine dans l’espace du squelette. Les hanches conservent leur locomotion et leur translation verticale, sans transmettre leur tangage au canon. Le facing visuel suit exactement `aim_direction` en visée précise, y compris pendant la récupération. Aucun `look_at()` ou facing autonome n’est appliqué à l’arme.

La visée est suspendue pendant les actions full-body ou lorsque le gameplay est désactivé. Le démarrage du combat interrompt explicitement le verrou de l’échauffement de 18 s ; la première frame de combat peut donc déjà viser. La reprise ne recalcule jamais le socket.

## 6–8. ShotKick, WeaponRecoil et WeaponSway

Le modifier du squelette traite **50 ms d’impulsion + 120 ms de récupération** avec une enveloppe smoothstep, indépendante du cooldown de 450 ms. Il repart de l’animation évaluée par Godot ; les deltas ne s’accumulent pas.

Le recul tire principalement RightShoulder vers l’arrière de 0,020 unité modèle, soit environ 3,52 cm avec l’échelle du personnage. Les faibles rotations distribuées sont : Spine2 +0,25°, RightShoulder +0,20°, RightArm +0,55°, RightForeArm −0,30°, RightHand −0,15°. La charge multiplie l’amplitude au maximum par 1,35. Le pitch résultant est légèrement descendant, jamais une montée du canon.

Sur le rig animé, `WeaponRoot`, `WeaponSway` et `WeaponRecoil` restent à l’identité. Aucun tween de recul ne les anime. Le sway indépendant du blaster est neutralisé pendant toute la visée, y compris charge, shot et recovery. Le robot procédural de secours conserve son animation d’arme, puisqu’il ne possède pas de squelette ; son sway attend la fin des tweens de recul.

## 9. Calibration du socket

AimPose est évaluée synchroniquement, puis les transforms des os sont forcés à jour. La pose canonique de RightHand est mémorisée. Le socket est calculé une fois par équipement : inverse de la main en AimPose × transform souhaité de l’arme. Le transform local reste ensuite fixe, même lors d’un tir, d’une rotation ou d’un changement de locomotion.

Le blaster est placé près de la vraie main de visée, avec un décalage local `(0, 0.08, -0.08)` ; l’ancien placement au niveau de la taille ne pouvait pas produire une prise cohérente. La racine de l’arme reste `Transform3D.IDENTITY`. Le wrapper du modèle conserve sa correction de pivot et d’axes.

Chaîne : Skeleton3D → RightHand → BoneAttachment3D → WeaponSocket → WeaponRoot → wrappers fixes → Muzzle.

## 10–15. Alignement et accumulation

Mesures 3D du rig de production, pas de projection horizontale. Les traces contiennent le vecteur muzzle, le vecteur aim, le dot 3D, le pitch et l’angle total. Le test direct du rig alterne dix tirs normaux/chargés avec changements de déplacement et de visée pendant recovery.

| Instant | Tir normal : angle total | Tir chargé : angle total |
|---|---:|---:|
| Avant | 0,000002° | ≈ 0° |
| Déclenchement, t = 0 | 0,000002° | 0,000001° |
| +50 ms, pic | 0,549980° | 0,742493° |
| +100 ms | 0,343102° | 0,463197° |
| +200 ms | 0,000009° | 0,000002° |
| +350 ms | 0,000014° | 0,000014° |
| +500 ms | 0,000001° | 0,000002° |

Pic maximal observé : **0,742493°**, dot minimal ≈ **0,999916**. À partir de 200 ms, dot ≈ **1** et composante verticale ≈ **0**. Les derniers chiffres sont la précision numérique du calcul, pas une précision physique du modèle.

Après dix tirs, dérive maximale des orientations récupérées : **0,000016°**. Aucun changement local du socket, du root, du sway ou du recoil. Retour complet de l’enveloppe à zéro à 170 ms.

## 16. Main gauche

Un solveur analytique à deux segments est exécuté après l’animation et le recoil. Sa cible est calculée depuis la **nouvelle** pose RightHand et la chaîne locale fixe jusqu’à LeftHandGrip, évitant une frame de retard du BoneAttachment.

Le marqueur du blaster importé est placé sous le côté gauche du receiver : `(-0.10, -0.04, -0.20)`. Longueur disponible du bras : 0,425103 m ; distance épaule–cible au repos : 0,398885 m, soit environ 2,62 cm de marge. Aucun étirement des segments. La direction du coude dérive de la pose de base, sans réutiliser le résultat IK précédent.

Erreur maximale main–grip observée dans le test direct : **0,00000013 m**. Le solveur assure la position du poignet ; la fermeture détaillée des doigts et la forme de la paume restent celles du GLB.

## 17. Fichiers de cette passe

- `scripts/player_visual_rig.gd` : sélection automatique du frame, AimPose constant, layer persistant, calibration et support.
- `scripts/player_aim_modifier.gd` : stabilisation du torse, ShotKick et IK gauche.
- `scripts/player.gd` : intégration du blaster, neutralisation du sway/recoil indépendants, grip, debug et sortie d’échauffement.
- `tools/test_player_visual_rig.gd` : tests 3D temporels, A–G, dix tirs, vraie entrée projectile, charge, changements d’état et contrôles.
- `tools/test_player_aim_core.gd` : vérification indépendante du rig de production, sans dépendance à la scène de combat.
- `tools/analyze_aim_pose.mjs` : inspection indépendante du GLB brut.
- `tools/capture_aim_pose.gd` : captures multi-angles, impulsion, récupération et marqueurs.
- Ce compte rendu. Les fichiers `.uid` associés sont générés par Godot.

Les changements déjà présents et les travaux concurrents sur l’ennemi, le shotgun et les effets de statut ont été conservés. Ils ne sont pas attribués à cette passe.

## 18. Validation

Résultats Godot 4.7.2 :

- `tools/test_player_aim_core.gd` : **PASS**. Dix tirs alternés normaux/chargés, changements de mouvement et de visée pendant la récupération, max 0,742493°, dérive récupérée 0,000016°, erreur main gauche 0,00000013 m, transforms fixes.
- `tools/test_player_visual_rig.gd` : **PASS (238 checks)**. Cas A–G, frame shot, 100/200/350/500 ms, entrée projectile réelle, charge, répétition, actions full-body, changement d’arme, reprise après warmup et contrôles tactiles.
- `tools/test_blaster.gd` : **PASS (127 checks)**.
- `tools/test_touch_controls.gd` : **PASS (121/122)**.
- `tools/test_combat_state.gd` : **PASS (101/102)**.
- `tools/test_game_flow.gd` : **PASS**.
- `tools/test_shotgun.gd` : une vérification existante échoue sur le cas `5/6` (1000 PV au lieu de 900). Cette régression appartient à l’état partagé des scripts de cible/shotgun et ne touche pas le chemin blaster validé ci-dessus ; elle est conservée pour investigation séparée.

L’import éditeur Godot termine sans erreur de parsing. Les avertissements restants concernent le magasin de certificats Windows et les ressources nettoyées à la fermeture des tests.

Le debug F8 affiche aim rouge, muzzle cyan, main droite jaune, arme blanche, ainsi que `Muzzle/Aim angle`. Il est actualisé après les modifiers du squelette.

Captures : `exports/aim-pose-review/aim_front_left.png`, `aim_front_right.png`, `aim_side.png`, `kick_50ms.png`, `recovery_350ms.png`, `aim_debug.png`. Les marqueurs rendent la coïncidence main gauche/grip vérifiable.

## 19. Limites

Le GLB n’a pas de clip aim dédié ni de prise des doigts spécialement sculptée pour ce blaster. L’IK est positionnel et conserve le roll local de la main ; une prise de doigts plus précise demanderait une pose créée pour ce modèle. La visée reste horizontale, conformément au gameplay actuel. Les captures confirment un canon horizontal et une impulsion discrète ; elles ne remplacent pas une appréciation interactive du feeling.

Les contrôles tactiles sont vérifiés automatiquement sur le moteur desktop. Aucun APK ni appareil Android n’a été testé ici : le SDK/build-tools Android n’est pas configuré. Godot 4.7.2 a été extrait de l’archive locale dans `exports/validation-tools/Godot_4.7.2` parce que les chemins `C:\RomainOpen\...` n’existent pas sur cette machine.

La documentation officielle confirme que SkeletonModifier3D est appliqué après l’AnimationMixer et que la lecture des poses modifiées doit se faire pendant le traitement final du squelette : https://docs.godotengine.org/en/stable/classes/class_skeletonmodifier3d.html
