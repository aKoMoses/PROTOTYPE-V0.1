# Fluidité du duel Android et base Performance

## Publication habituelle : build 71

La [release 71](https://github.com/aKoMoses/PROTOTYPE-V0.1/releases/tag/v0.2.0-build.71)
est la publication numérotée de cette base Performance avec le correctif GPU
limité aux duels. Les sources sont enregistrées sur GitHub dans le commit
`943e65eed69411ab8e8d09853949369c9e59513e`, branche
`codex/performance-preserved`, et ne sont pas intégrées à main.
Les 3 218 fichiers de la copie de publication ont été comparés aux sources
locales validées avant le commit ; l'export exclut les captures inutilisées.

Le [workflow 71](https://github.com/aKoMoses/PROTOTYPE-V0.1/actions/runs/38794560306)
réussit l'import, les trois contrôles courts et les exports Android et Windows.
La suite complète reste désactivée. Les signatures v2/v3 passent ; le manifeste
confirme le paquet habituel `com.prototype0.arena`, la version `0.2.0.71` et le
code `10071`. L'APK de 296 654 167 octets est accessible sans authentification
et la release apparaît en tête de la liste habituelle des publications.
SHA-256 fourni par GitHub :
`a896c814c130a0aac429feee2e81c85262f1650f33f9b5c73afe0d8e7975b77e`.

Cette APK met à jour l'application habituelle des builds 69 et 70.
L'APK séparée Performance décrite ci-dessous reste la référence de comparaison.
Les FPS sur XCover doivent encore être mesurés en duel.

## Version à conserver : Prototype 0 Performance

La référence demandée le 15 octobre 2026 est l'APK **Prototype 0 Performance**
du 10 octobre, et non les builds 69 ou 70. Ces deux builds utilisent un autre
état des menus et du jeu. La copie locale de ce dossier conserve les sources
de la version Performance ; ne pas la remplacer par la branche de la build 70.

La [version corrective Performance](https://github.com/aKoMoses/PROTOTYPE-V0.1/releases/tag/android-performance-gpu-2026-10-15)
reprend cette référence. La comparaison des APK confirme **2 653 ressources
du jeu identiques octet pour octet**, dont les scripts des menus, du garage,
des robots, des cartes et des règles de combat. Le nouveau contrôleur GPU et
son autoload sont ajoutés. Les captures de diagnostic inutilisées sous
`outputs/` sont exclues de l'export, ce qui réduit le téléchargement.

`MobileRenderBudget` réduit uniquement le viewport principal des duels à 0,5
et désactive les ombres projetées des lumières de ce monde. Il ne modifie pas
les viewports des aperçus. Les menus gardent le réglage mobile de 0,75 et les
ombres d'origine ; ces réglages sont restaurés dès la sortie du duel.
L'éclairage, les éléments 2D et la cadence physique sont conservés.

Vérifications : import Godot, 14 contrôles du profil GPU et de la restauration
des menus, contrôle du budget VFX, trois contrôles courts de publication.
Le parcours des manches et les 525 contrôles de visuels de modules passent.
Le menu, le garage, le duel et le retour au menu sont également capturés
depuis les ressources compilées de l'APK ; aucun script ne change en dehors
du nouveau contrôleur. Les avertissements de décodage ETC2 sur la carte PC
ne constituent pas une mesure de performance Android.

L'APK utilise le moteur release ARM64 d'origine, le paquet
`com.prototype0.arena.performance`, le **même certificat** que la première
Performance, le code de version `3` et le nom `0.2.0-performance-gpu.1`.
Les signatures v2/v3 et l'alignement 16 Kio passent. Une mise à jour conserve
ainsi l'identité de l'application Performance existante.

Source : base `70155ca6ed650d8dbe5c532875ac28da96b5cfce` avec les travaux locaux
déjà embarqués dans l'APK Performance. La publication de l'APK ne signifie
pas que ces sources sont intégrées à main. Empreinte SHA-256 :
`7f642a7d0aeaec2045fadefacd7c3f651952bb0737eb1f87938db3f882b11b1a`.

Les FPS sur XCover restent à mesurer : même duel et même carte pendant cinq
minutes, avec relevé FPS et GPU. Les mesures PC historiques ci-dessous ont
été faites sur une autre base et ne prouvent pas un gain sur cette APK.
Rapports et captures : `outputs/performance-baseline-restore/`.

## Historique : diagnostic de la build 69

Le XCover6 Pro affiche environ 30 FPS en combat avec les bots sur la build 69.
Cette version vise déjà 60 FPS et contient la réduction du coût du brouillard,
du décor et des recherches de chemin. Les essais PC du 14 octobre 2026 montrent
un rendu encore dense et des pauses pendant les premières actions. Ils désignent
des pistes de correction. La lecture du compteur sur le téléphone confirme
environ 33 ms de GPU et 1 à 2 ms d'IA par tick : le rendu dépasse déjà à lui
seul le budget de 16,7 ms nécessaire aux 60 FPS. L'allègement GPU est prioritaire.

## Mesures de la version publiée

Source exécutée : commit `af416131137fd7073c9a24a3df0fc683c12d6411`, dans le
checkout de la release 69. Godot 4.7.2, Mobile/Vulkan, RTX 3070 Laptop,
fenêtre masquée de 1280 × 720, rendu 3D à 0,75, VFX bas et scheduler mobile.
Les réglages `.mobile` du projet, dont l'atlas d'ombres de 1024, ne sont pas
émulés par l'argument de diagnostic sur PC. Chaque cas dure quatre secondes
après une seconde de préparation et reprend le même build de bot.

| Cas | Appels de dessin moyens | GPU moyen PC | Intervalle médian | Intervalle au 95e percentile |
| --- | ---: | ---: | ---: | ---: |
| Duel initial | 998 | 1,44 ms | 13,73 ms | 26,75 ms |
| Duel répété après préparation | 997 | 1,10 ms | 10,40 ms | 16,96 ms |
| Bot désactivé après préparation | 988 | 1,04 ms | 8,95 ms | 11,85 ms |
| Rendu à 0,50 | 997 | 0,88 ms | 10,20 ms | 16,54 ms |
| Ombres désactivées | 701 | 0,78 ms | 10,11 ms | 16,08 ms |
| Callbacks de décor suspendus | 999 | 1,14 ms | 10,75 ms | 17,64 ms |

La désactivation des ombres retire environ 30 % des appels de dessin dans ce
parcours. Le compteur de primitives passe d'environ 746 000 à 308 000.
Il compte des sommets ou indices sur plusieurs passes, **pas des triangles**.
Le joueur comprend 263 instances de mesh et le bot 131 dans l'inventaire ;
leurs armes et pièces masquées sont également comptées. Les aperçus de
l'interface appartiennent à des viewports séparés et ne doivent pas être
additionnés au rendu visible du combat.

L'IA mesurée consomme environ 0,78 ms par tick à chaud sur ce PC. Supprimer le
bot supprime aussi ses attaques et change le parcours : la différence totale
entre ces cas ne mesure donc pas uniquement son coût d'IA.

## Pauses pendant les premières actions

Le premier essai comporte une pause de 572 ms et une autre de 1 948 ms.
Le deuxième essai comporte une pause de 880 ms pendant le duel initial,
accompagnée de nouvelles compilations de surfaces graphiques. Dans le duel
répété à chaud, le maximum descend à 31 ms. Cela justifie d'examiner les effets
créés au premier usage et la préparation des variantes de matériaux.

Une pause d'environ 110 ms revient également dans le parcours sans bot,
au moment où le joueur apparaît dissimulé dans un buisson, sans changement
immédiat du compteur de compilations au dessin. Cette corrélation ne suffit
pas à attribuer la pause au camouflage, au brouillard ou au moteur.

Les [moniteurs Godot](https://docs.godotengine.org/en/stable/classes/class_performance.html)
peuvent refléter une ancienne image pendant près d'une seconde. Les moyennes
du moniteur physique et les intervalles de fenêtre ne constituent pas une
mesure des scripts seuls. Les échantillons sont courts et séquentiels ;
aucun gain de FPS Android ne peut être calculé à partir de ce tableau.

## Correctif GPU Android

Le profil Android utilise désormais un rendu 3D à 0,50, désactive les ombres
dynamiques et le MSAA 3D, et conserve l'éclairage. Le Canvas 2D, le HUD, les
dimensions des viewports, les collisions et la cadence physique restent les
mêmes. Passer de 0,75 à 0,50 réduit la surface du rendu 3D de 55,6 %.
L'image 3D est moins nette et les grandes ombres projetées disparaissent.

`MobileRenderBudget` s'active sur mobile, ou avec l'argument de diagnostic
`mobile-gpu-budget`. Il suit les lumières et viewports par références faibles
et applique son budget après les contrôleurs de qualité, y compris dans les
nouvelles scènes et les aperçus. Le profil PC reste inactif. Les réglages
plus bas que 0,50 sont conservés.

Une comparaison de quatre échantillons alterne l'ancien rendu et le profil
modifié sur une copie de la build 69, avec le même build de bot et le même
parcours. L'ordre ancien, modifié, modifié, ancien limite l'effet de dérive,
sans supprimer les compilations des premières actions.

| Profil testé sur PC | Appels de dessin moyens | Primitives moyennes | GPU moyen |
| --- | ---: | ---: | ---: |
| Ancien premier passage | 994 | 739 752 | 1,712 ms |
| Modifié premier passage | 696 | 310 041 | 1,283 ms |
| Modifié deuxième passage | 695 | 307 561 | 1,158 ms |
| Ancien deuxième passage | 997 | 735 783 | 1,601 ms |

Le profil enlève environ 30 % des appels de dessin et 58 % des primitives dans
ces échantillons. Le temps GPU moyen PC passe d'environ 1,66 à 1,22 ms.
Les intervalles de fenêtre varient fortement pendant ce test court ; ils ne
permettent pas d'affirmer que les 60 FPS sont atteints sur Android.
Les captures confirment un duel lisible et un HUD qui garde sa résolution.

L'import du worktree passe sans erreur de script. Les 16 contrôles du profil
GPU, le contrôle des budgets de rendu et les trois contrôles rapides de
publication passent. Ces trois derniers sont exécutés avec le profil GPU actif
et couvrent l'équipement, le parcours des manches et 2 132 contrôles des visuels
de modules. La suite complète n'a pas été relancée.

Le correctif du commit `6f6ec41530549b4143fc1d2a5f982e03d433aa1a` est disponible
dans la [release 70](https://github.com/aKoMoses/PROTOTYPE-V0.1/releases/tag/v0.2.0-build.70) :
[télécharger l'APK Android de 319 Mo](https://github.com/aKoMoses/PROTOTYPE-V0.1/releases/download/v0.2.0-build.70/prototype0-android.apk).
Le paquet habituel `com.prototype0.arena`, version `0.2.0.70`, code `10070`,
conserve sa signature de publication. L'import, les trois contrôles rapides
et l'export signé passent dans le workflow 70 ; les signatures v2 et v3 sont
validées. La suite complète reste désactivée.

Cette APK vient de la branche `codex/android-gpu-budget`, basée sur la build 69.
Le correctif n'est pas encore intégré sur main. Le prochain essai doit relever
le GPU et les FPS sur l'APK modifiée, puis après cinq minutes de duel.

Rapport : `outputs/android-gpu-budget/comparison.json`.
Captures : `comparison-gpu-baseline.png` et `comparison-gpu-budget.png` dans
le même dossier.

## Pistes suivantes selon les mesures

1. Si le GPU reste au-dessus de 16,7 ms avec le profil modifié, réduire les
   surfaces des robots. Le regroupement des surfaces, les
   matériaux partagés et les niveaux de détail sont les pistes adaptées aux
   nombreux petits meshes, selon la
   [documentation du rendu Godot](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html).
2. Si l'IA ou la physique consomme la majorité du budget, profiler les calculs
   de perception, les recherches de chemin et les callbacks des acteurs sur
   le XCover. Conserver la cadence de mouvement et de collision à 60 Hz.
3. Pour les pauses, mesurer séparément la première attaque, le premier impact
   et le premier passage dans un buisson, puis leurs répétitions. Préparer
   les ressources responsables avant l'entrée en combat.

Sur le XCover, relever GPU, IA/tick, vision/maj et physique dans le même duel
à 30 FPS, puis après cinq minutes. Ces valeurs distingueront aussi un coût
constant d'une baisse liée à la chauffe.

## Reproduire et vérifier

`tools/profile_combat_frames.gd` accepte un chemin JSON absolu après `--` et
peut être exécuté avec `--script` depuis un autre checkout. Ajouter
`mobile-performance` pour activer le scheduler mobile ; utiliser un vrai
moteur de rendu. Le script retire la limite FPS uniquement dans son processus
de diagnostic et produit une capture du duel ainsi que les quantiles,
compilations et inventaires. Rediriger `APPDATA` vers un dossier de test avant
de le lancer pour isoler les sauvegardes.

Deux exécutions du duel se terminent avec un code 0 et sans erreur Godot.
La capture confirme le combat actif avec le bot. La vérification de syntaxe
de la version finale du script passe également. Les réglages et scripts de
production de la build 69 restent ceux de la release.

Rapport détaillé : `outputs/android-combat-audit/build69-verified.json`.
Capture : `outputs/android-combat-audit/build69-verified-baseline.png`.
