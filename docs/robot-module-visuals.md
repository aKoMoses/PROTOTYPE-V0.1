# Modules 3D intégrés à l'armure

Les dix-huit accessoires préservent les proportions du mecha équipé, avec un visage et un cœur de poitrine dégagés. La plupart sont de petits inserts épousant les pièces du robot; le Traqueur adopte désormais l'œil sphérique sur épaule de sa maquette approuvée. La validation visuelle porte sur le robot entier et ses animations. Les quatre offensifs, les quatre défensifs, les quatre mobilités et les six passifs ont un modèle.

## Formes et fixations

- **Pyroboots** : carénages d'environ 15 cm intégrés derrière les chevilles. La tuyère est creuse et orientée vers l'arrière; la coque suit le talon plutôt que d'ajouter un boîtier latéral.
- **Bio Injector** : petit insert d'environ 18 cm sur le côté du plastron, avec deux cartouches, une pompe et un conduit en retrait.
- **Panier Roquettes** : insert de faible épaisseur sur la protection du bras gauche, sous le niveau de la tête. Les ouvertures et leurs rebords donnent le détail mécanique.
- **Magnetic Field** : disque compact fixé à l'avant-bras gauche, dont l'orientation suit la plaque du bras.
- **Réacteur auxiliaire** : insert tourné vers l'arrière, placé sur la protection métallique du haut du bras gauche, derrière l'épaule.
- **Fulguro Punch** : accélérateur compact sur l'avant-bras droit. Trois patins d'impact, deux tiges de pistons dégagées, sept ailettes de cuivre et des ouvertures ambrées en retrait, dans un carénage ivoire de 14,4 × 21,6 × 6,1 cm.
- **Static Shield** : émetteur de stase sur l'avant-bras gauche, exclusif avec Magnetic Field. Trois capots de céramique protègent un anneau usiné, ses contacts cuivre et un iris cyan opaque; dimensions de 14,9 × 19,1 × 5,1 cm.
- **Javelin** : cassette de lancement sur le haut du bras gauche, exclusive avec Panier Roquettes et Fulguro Punch. Trois rails de cuivre, des isolateurs creux et des électrodes cyan dans un carénage ivoire de 15,7 × 20,9 × 5,4 cm.
- **Projector** : émetteur de répulsion sur l'avant-bras gauche, exclusif avec les autres modules défensifs. Une membrane métallique concave, trois pistes concentriques et une grille ouverte entre deux capots de céramique; dimensions de 16,0 × 20,6 × 6,2 cm.
- **Pelto Smash** : percuteur sismique sur l'avant-bras droit. Trois patins céramiques reliés à deux vérins, un collecteur à ailettes, des joints cuivre creux et des conduites protégées; dimensions de 16,9 × 20,5 × 6,3 cm.
- **Counter** : condensateur de riposte sur l'avant-bras gauche. Trois plaques de garde angulaires et séparées, un cylindre cuivre central, des contacts usinés et des voyants cyan en retrait; dimensions de 15,7 × 20,6 × 5,9 cm.
- **Permutation** : échangeur de phase sur le côté du plastron, dans la catégorie mobilité. Deux vraies bobines de cuivre en sens opposés, des sièges de céramique creux et un pont à deux ports; dimensions de 10,5 × 17,7 × 4,9 cm.
- **Éclipse** : émetteur d'occultation sur le même support de plastron, exclusif avec les autres mobilités. Huit pales opaques, une lentille sombre, un demi-anneau ambré et un croissant de céramique; dimensions de 10,4 × 17,7 × 5,0 cm.


- **Baroud d’honneur** : réserve de secours rouge sur l’arrière du bras gauche, avec trois fenêtres ambrées, un coupe-circuit en retrait, des rails de céramique et des loquets de retenue.
- **Omnivamp** : deux réservoirs verts de récupération sur le même support, avec indicateurs de niveau, circuit de retour cuivre, collecteur et volant de réglage creux.
- **Traqueur** : œil sphérique sur le dessus de l'épaulière gauche. Coque ivoire usée, casquette ocre avec sourcil incurvé, iris cyan à pupille sombre, pivot latéral, fourche, pied ovale et câble épais; dimensions de 29,3 × 35,4 × 26,2 cm, pivot compris.
- **Alternateur** : commutateur à huit contacts radiaux en cuivre, deux secteurs cyan/ambré, axe claveté, porte-balais et relais de changement de canal.
- **Inertie** : gyroscope à trois cardans creux dans des plans différents, volant plein, pivots latéraux et deux amortisseurs, protégé par des fourches céramiques.

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
| Fulguro | `rightforearm` | `(−0,23; −0,005; 0,230)` | `(0; 0; π/2)` |
| Static | `leftforearm` | `(0,18; −0,005; 0,230)` | `(0; 0; −π/2)` |
| Javelin | `leftarm` | `(0,1447; 0,0876; 0,1795)` | `(−0,4721; 0,7048; 1,0034)` |
| Projector | `leftforearm` | `(0,18; −0,005; 0,230)` | `(0; 0; −π/2)` |
| Pelto | `rightforearm` | `(−0,23; −0,005; 0,230)` | `(0; 0; π/2)` |
| Counter | `leftforearm` | `(0,18; −0,005; 0,230)` | `(0; 0; −π/2)` |
| Permutation | `spine1` | `(0,2776; −0,0803; 0,1871)` | `(0,3320; 0,6739; 0,0192)` |
| Éclipse | `spine1` | `(0,2776; −0,0803; 0,1871)` | `(0,3320; 0,6739; 0,0192)` |
| Baroud, Omnivamp, Alternateur, Inertie | `leftarm` | `(0,2169; −0,0284; −0,1132)` | `(0,0938; −3,0804; 1,5765)` |
| Traqueur | `leftarm` | Pied au-dessus de l'épaulière; repère de repos calibré depuis `idle` | Regard vers l'avant, avec 0,25 rad de rotation locale |

Sur le châssis Puissant, la fixation de Javelin avance de 28 cm dans la normale locale du support pour rejoindre la surface de sa grosse épaulière. Cette correction est calculée une fois à la création des sockets, à partir du modèle importé; le garage et le vrai Player utilisent le même réglage. Les châssis Polyvalent et Agile conservent la fixation de référence.

Le Puissant utilise également une profondeur de 0,300 m pour Pelto et Counter, soit 7 cm supplémentaires dans l'axe Z de référence. Permutation et Éclipse avancent de 14 cm dans la normale de leur support pour rejoindre le plastron renforcé. Ces réglages ont été contrôlés en comparant les rendus de face et de profil; les modèles restent de même taille et utilisent les mêmes fixations dans le garage et le Player.

Les quatre catégories du loadout déterminent indépendamment les pièces visibles. Pyroboots, Bio Injector, Permutation et Éclipse sont exclusifs dans la mobilité; une seule pièce offensive, défensive et passive est également visible à la fois. La visibilité est propre à chaque robot; le camouflage emploie des copies locales de matériaux, puis restaure les références opaques d'origine.

Sur le Puissant, les cinq passifs arrière ont une correction de 25 cm dans l’axe X de référence et de 14 cm dans la normale du support arrière. Elle rejoint la plaque externe du bras au lieu de laisser l’insert masqué par le dos renforcé. Le Traqueur dispose d'une fixation distincte au sommet de l'épaulière, avec une conversion des axes propre au squelette du Puissant. Les trois poses capturées et les mêmes fixations dans le Player sont vérifiées; les modèles et leurs tailles restent partagés entre châssis.

## Sources et matériaux

Les modèles et textures sont créés localement avec [build_mobility_module_models.py](../tools/build_mobility_module_models.py), [build_additional_module_models.py](../tools/build_additional_module_models.py), les constructeurs des ajouts décrits ci-dessous et les outils communs de [module_modeling.py](../tools/module_modeling.py). Aucun modèle ou texture externe n'est utilisé. Les sources Blender éditables sont dans `art/modules/source/`, y compris ses sous-dossiers; les rendus de présentation dans `art/modules/previews/`. Ces dossiers ont un `.gdignore`.

Chaque GLB dans `art/modules/` est accompagné d'un `.asset.json` indiquant provenance, source, dimensions, triangles, lots de matériaux, octets et SHA-256. Les maillages ont des UV et des normales; les textures PBR 256 × 256 de couleur, rugosité et normales sont intégrées. Les émissions sont limitées et les matériaux opaques. Les caches de maillage et matériau sont partagés par les robots, les rangements et les pièces transportées par le bras de la forge.

| GLB | Largeur × hauteur × profondeur du modèle | Triangles | Lots de matériaux | Octets |
| --- | --- | ---: | ---: | ---: |
| `pyro_boots.glb` | 10,2 × 14,9 × 5,7 cm pour un talon | 3 064 | 7 | 1 176 872 |
| `bio_injector.glb` | 10,8 × 18,0 × 4,5 cm | 5 816 | 6 | 1 140 940 |
| `rocket_basket.glb` | 19,0 × 15,0 × 5,0 cm | 4 004 | 3 | 678 444 |
| `magnetic_field.glb` | 13,3 × 18,2 × 5,3 cm | 3 800 | 6 | 1 025 656 |
| `auxiliary_reactor.glb` | 15,9 × 25,9 × 6,7 cm | 3 100 | 5 | 889 820 |
| `fulguro_punch.glb` | 14,4 × 21,6 × 6,1 cm | 6 964 | 7 | 1 437 528 |
| `static_shield.glb` | 14,9 × 19,1 × 5,1 cm | 8 220 | 7 | 1 512 824 |
| `javelin.glb` | 15,7 × 20,9 × 5,4 cm | 8 368 | 7 | 1 475 784 |
| `projector.glb` | 16,0 × 20,6 × 6,2 cm | 8 212 | 7 | 1 434 860 |
| `pelto_smash.glb` | 16,9 × 20,5 × 6,3 cm | 7 512 | 7 | 1 446 468 |
| `counter.glb` | 15,7 × 20,6 × 5,9 cm | 4 788 | 7 | 1 280 416 |
| `permutation.glb` | 10,5 × 17,7 × 4,9 cm | 7 584 | 7 | 1 360 372 |
| `eclipse.glb` | 10,4 × 17,7 × 5,0 cm | 6 212 | 7 | 1 402 824 |
| `baroud.glb` | 14,7 × 20,8 × 6,0 cm | 3 176 | 8 | 1 392 596 |
| `omnivamp.glb` | 15,2 × 20,7 × 6,1 cm | 4 352 | 7 | 1 245 896 |
| `tracker.glb` | 29,3 × 35,4 × 26,2 cm | 5 468 | 8 | 963 116 |
| `alternator.glb` | 15,9 × 20,4 × 6,5 cm | 3 944 | 8 | 1 265 736 |
| `inertia.glb` | 15,7 × 20,8 × 7,3 cm | 4 516 | 7 | 1 274 068 |

## Traqueur : œil sur épaule, 3 octobre 2026

[build_tracker_eye_model.py](../tools/build_tracker_eye_model.py) remplace la cassette arrière par la sphère et son pied de la [maquette approuvée](../captures/module-identity-concepts/traqueur-sur-vrai-robot-v1.png). La source éditable et les textures embarquées sont dans `art/modules/source/tracker-eye/`. Le constructeur des passifs appelle ce même constructeur pour éviter de rétablir l'ancien modèle lors d'une reconstruction complète. L'ancienne source `source/passives/tracker.blend` est conservée.

Le sourcil ocre, la coque ivoire ouverte, la lunette circulaire en retrait, l'iris cyan texturé et sa pupille sombre sont de vraies pièces. Le pivot latéral, la fourche arrondie, le col de rotation, le pied ovale et le câble relient l'œil à l'épaulière. Les cartes d'usure utilisent des UV continus sur les surfaces sphériques; elles restent opaques et compatibles avec le rendu Mobile. Le modèle n'ajoute aucun traitement par frame. La mécanique du passif reste identique.

Le garage, le rangement, la pièce transportée et le Player partagent ce GLB de **5 468 triangles et huit lots**. Le maximum du kit équipé est maintenant de **29 640 triangles**, sous le budget de 30 000. Le test de taille autorise 40 cm pour cet œil sur pied, afin de suivre les proportions approuvées; la limite de 36 cm reste appliquée aux autres accessoires. L'orientation du pied est calibrée dans la pose `idle`, puis convertie en repère de repos de `leftarm`, avec une correction distincte du Puissant. Il suit ensuite les animations de l'épaulière sans calcul supplémentaire.

Import Godot 4.7.2 et inspection des dix-huit GLB réussis. `test_robot_module_visuals.gd` passe **2 132 contrôles** sur le garage, le Player, les caches, catégories, os, matériaux et camouflage. `test_tracker_eye_model.gd` passe **78 contrôles** dans la boucle native Vulkan Mobile : prise, annulation, transport solidaire, contact avant équipement et installation sur les trois châssis, avec les quatre armes et les quatre offensifs. Les installations finales durent **6,94 à 7,00 secondes**; les sauvegardes sont isolées. Le pilote audio de secours est utilisé après échec de WASAPI; ces vérifications portent sur le rendu et le montage.

Les **50 captures natives** de `capture_tracker_eye_model.gd` couvrent les trois châssis au repos, à l'échauffement et en course, de face, de trois quarts et de profil gauche; la cohabitation avec Rocket et Javelin; le vrai garage à 1600 × 900 et 960 × 540; la prise et la fixation. Le Polyvalent utilise la caméra exacte du robot de référence; la caméra du Puissant est reculée pour conserver son corps dans l'image. La [comparaison maquette/jeu](../captures/tracker-eye/comparaison-maquette-jeu.png), les [poses des trois châssis](../captures/tracker-eye/trois-chassis-animations.png) et la [cohabitation des offensifs](../captures/tracker-eye/rocket-javelin.png) assemblent ces captures, sans remplacement du rendu par une image générée. Elles ont été inspectées. Les captures PC ne mesurent pas les performances sur téléphone.

Ces tests et captures utilisent la mise en page du garage avant sa refonte parallèle. La relance du test général `test_forge_module_stations.gd` a ensuite rencontré le chantier en cours « Simplifier les menus et adapter le garage aux petits ecrans » : `forge_garage.gd` référençait déjà `scripts/ui/forge_garage_layout.gd`, encore absent, et deux méthodes en cours d'extraction. Le processus de test a été arrêté; cette relance ne constitue pas une validation du nouveau parcours de menus. Les fichiers de ce chantier n'ont pas été modifiés par le travail du Traqueur. Une vérification native fraîche, `captures/tracker-eye/verify_stage.gd`, passe ensuite sur les **trois châssis** en instanciant directement la vraie scène 3D partagée, sans dépendre de la mise en page du garage : `TRACKER CURRENT STAGE: PASS`. Les captures `*-stage-current.png` conservent ce contrôle du modèle final pendant la refonte.

## Complétion initiale des six passifs, 3 octobre 2026

[build_passive_module_models.py](../tools/build_passive_module_models.py) produit Baroud d’honneur, Omnivamp, Traqueur, Alternateur et Inertie. Le Réacteur auxiliaire existant conserve sa géométrie et participe aux vérifications des six passifs. Les composants éditables et textures sont isolés dans `art/modules/source/passives/`; les GLB contiennent les mêmes surfaces PBR que les autres modules. Les pièces tournées ont un chanfrein simple et des normales lissées; les grandes protections conservent leurs contours arrondis. Les cardans, joints, conduites, contacts et pales d’iris sont de vrais composants géométriques, avec matériaux opaques.

Les six objets sont visibles dans le rangement passif, transportés par le bras et fixés avant changement de loadout. Une seule pièce passive reste visible à la fois, avec chacune des quatre armes et les trois autres catégories. La correction du Puissant décrite ci-dessus vaut aussi pour le Réacteur, auparavant masqué par le dos renforcé. Les sources du réacteur sont conservées. Le maximum des accessoires équipés parmi les dix-huit modèles est maintenant de **29 124 triangles**, sous le budget de 30 000.

Vérifications : inspection des dix-huit GLB et import Godot 4.7.2 réussis; `test_robot_module_visuals.gd` passe **2 124 contrôles** sur les chemins garage/Player, les catégories, les os, caches, matériaux, camouflage et fixations. `test_passive_module_models.gd` passe **510 contrôles** sur les trois châssis, puis **282 contrôles** dans la boucle native Vulkan Mobile. Les six installations natives se terminent entre **6,86 et 7,04 secondes** chacune, avec transport solidaire, contact de fixation, annulation et restauration des objets du rangement. Les sauvegardes sont isolées. Ce parcours utilise le pilote audio de secours après l’échec de WASAPI; il valide les modèles et leur montage, sans confirmer l’écoute audio.

[capture_passive_module_models.gd](../tools/capture_passive_module_models.gd) produit **276 captures** : robot sans accessoires puis avec chacun des six passifs, sur les trois châssis, au repos, à l’échauffement et en course, de face, de profil gauche, de trois quarts arrière et de dos; cadrages du vrai garage à 1600 × 900 et 960 × 540; prise et fixation des six objets. Des échantillons des trois châssis et animations, les six cadrages d’inspection et les étapes de montage ont été inspectés. Les vues supplémentaires du Puissant confirment la fixation corrigée. La planche `captures/passives/six-passifs.png` réunit les modèles Blender et le garage Godot. Les captures PC à 960 × 540 ne mesurent pas les performances d’un téléphone.

Les régressions passent : `test_forge_garage.gd` sans échec et `test_forge_module_stations.gd` avec **3 703 contrôles, zéro assertion échouée**. Ces tests couvrent désormais le transport réel d’Omnivamp depuis son bouton Équiper; il n’existe plus de choix de module sans modèle. Le test des rangements signale quatre objets et deux ressources encore présents à sa fermeture, avec code de sortie réussi; les tests ciblés et la capture finale ne signalent pas ce diagnostic. Les autres modifications locales sont préservées.

## Ajout de Pelto Smash, Counter, Permutation et Éclipse, 3 octobre 2026

[build_four_active_module_models.py](../tools/build_four_active_module_models.py) produit les quatre accessoires avec la même recette PBR, des contours chanfreinés, des ouvertures mécaniques réelles et des matériaux opaques. Les composants Blender éditables et leurs textures sont isolés dans `art/modules/source/four-active/`. Les patins de Pelto sont reliés aux vérins; les bobines de Permutation ont des sens opposés; les pales d'Éclipse sont modélisées. Aucun asset externe n'est utilisé.

Les quatre vrais objets sont disponibles dans les rangements et passent par le transport du bras, l'annulation et la fixation avant changement de loadout. Les mêmes ressources suivent les os du robot de la forge et du Player, avec les réglages spécifiques au châssis Puissant décrits plus haut. Les modèles de mobilité restent exclusifs. Le kit Pelto + Counter + Permutation + Réacteur ajoute 22 984 triangles; avec Éclipse il ajoute 21 612 triangles. Le maximum parmi les treize modèles est maintenant de 27 272 triangles, sous le budget de 30 000.

Vérifications finales : inspection des octets des treize GLB réussie; import Godot 4.7.2 sans erreur; `test_robot_module_visuals.gd` réussi avec 1 420 contrôles sur les vrais chemins garage/Player, les catégories, caches, matériaux, camouflage et fixations. `test_four_active_module_models.gd` passe 244 contrôles sur les trois châssis, les quatre armes et les deux mobilités, puis 92 contrôles en rendu natif Vulkan Mobile. Les quatre installations natives se terminent réellement entre 6,8 et 7,1 secondes chacune, avec transport solidaire et contact au socket. Ce parcours utilise le pilote audio de secours après échec de WASAPI; il valide le rendu et le montage, sans confirmer l'écoute audio. Les sauvegardes de ces tests sont isolées.

[capture_four_active_module_models.gd](../tools/capture_four_active_module_models.gd) produit 151 captures : comparaisons sans accessoires, avec Permutation et avec Éclipse, sur les trois châssis, en poses `idle`, `warm_up` et `run`, de face, trois quarts et profils gauche/droit; vrais cadrages du garage à 1600 × 900 et 960 × 540 pour les quatre objets; prise et fixation par le bras. Les échantillons de montage, les quatre vues d'inspection et des poses des trois châssis ont été inspectés. La planche `captures/four-active/quatre-modules.png` réunit les rendus Blender et Godot. Les captures à 960 × 540 sont des rendus PC et ne valident pas les performances d'un téléphone.

Les régressions de cet ajout passent : `test_forge_garage.gd` sans échec, et `test_forge_module_stations.gd` avec 3 003 contrôles et zéro assertion échouée. La couverture des choix sans modèle utilisait alors Omnivamp, car Counter et Permutation avaient un vrai modèle. Les autres modifications locales sont préservées.

## Ajout de Javelin et Projector, 3 octobre 2026

[build_javelin_projector_models.py](../tools/build_javelin_projector_models.py) réutilise les matériaux PBR et les outils de profilage des modèles précédents. Les sources éditables et leurs textures sont isolées dans `art/modules/source/javelin-projector/`. Les rails, isolateurs et électrodes de Javelin sont continus et distincts; la membrane de Projector est réellement concave, avec une grille ajourée et des ouvertures cyan limitées.

Les deux pièces utilisent leurs vrais modèles dans les rangements, pendant le transport du bras et sur les os du robot du garage ou du Player. Le cadrage d'inspection et le point de fixation suivent les dimensions réelles. Le kit Javelin + Projector + Réacteur + deux Pyroboots ajoute 25 808 triangles; le maximum des combinaisons avec les neuf modèles de cet ajout était de 25 816, sous le budget de 30 000 pour les accessoires.

Vérifications après la correction de fixation du châssis Puissant : inspection des neuf GLB réussie; import Godot 4.7.2 sans erreur; `test_robot_module_visuals.gd` réussi avec 997 contrôles, dont les fixations identiques dans le garage et le vrai Player. `test_javelin_projector_models.gd` passe 118 contrôles sur les trois châssis et les quatre armes : sélection, annulation, prise, transport, contact avec le socket, installation et cadrage. Le parcours natif passe 42 contrôles avec deux installations réellement terminées dans la boucle Vulkan en environ sept secondes chacune. Les tests et captures de cet ajout utilisent des sauvegardes isolées.

[capture_javelin_projector_models.gd](../tools/capture_javelin_projector_models.gd) produit 62 captures Vulkan : robot sans accessoires et équipé, sur les trois châssis, au repos, à l'échauffement et en course, de face, trois quarts et profil; vrais cadrages du garage à 1600 × 900 et 960 × 540; prise et fixation par le bras. Les échantillons des trois châssis, des animations et du montage sont inspectés, dont la grosse épaulière du Puissant. La planche `captures/javelin-projector/deux-modules.png` réunit les rendus Blender et les captures Godot. Le format 960 × 540 sur PC ne mesure pas les performances d'un téléphone.

Les régressions du garage passent : `test_forge_garage.gd` sans échec et `test_forge_module_stations.gd` avec 2 447 contrôles et zéro assertion échouée. Le dernier test général des rangements signale à sa fermeture neuf instances et trois ressources encore présentes, avec un code de sortie réussi. Le dernier parcours natif utilise le pilote audio de secours, après échec de WASAPI; il valide le rendu et le montage, sans confirmer l'écoute audio. Les autres modifications locales du garage sont préservées.

## Ajout de Fulguro Punch et Static Shield, 3 octobre 2026

[build_fulguro_static_models.py](../tools/build_fulguro_static_models.py) réutilise les matériaux PBR des cinq modèles précédents. Les sources éditables et leurs textures sont isolées dans `art/modules/source/fulguro-static/`; les GLB, manifests et aperçus suivent le même format que les autres accessoires. Les ouvertures mécaniques sont modélisées, les contours chanfreinés et les cartes PBR embarquées; aucun fournisseur ou asset externe n'est utilisé.

Les rangements utilisent automatiquement les nouveaux modèles. La sélection passe par le transport physique du bras, avec montage sur leur vrai socket et annulation avant fixation. Les mêmes maillages et matériaux suivent les os dans le garage et le vrai Player; le zoom d'inspection utilise leurs dimensions réelles. Le kit Fulguro + Static + Réacteur + deux Pyroboots ajoute 24 412 triangles, sous le budget de 30 000 pour les accessoires.

Vérifications de cet ajout : inspection des octets des deux GLB réussie; import final Godot 4.7.2 sans erreur; `test_robot_module_visuals.gd` réussi avec 752 contrôles, y compris caches partagés, matériaux, camouflage, équipement et châssis puissant. `test_fulguro_static_models.gd` passe 118 contrôles sur les trois châssis et les quatre armes, puis 42 contrôles en rendu Vulkan Mobile avec deux poses réellement terminées dans la boucle native en environ sept secondes chacune. Les tests utilisent des sauvegardes isolées.

[capture_fulguro_static_models.gd](../tools/capture_fulguro_static_models.gd) a produit 62 captures Vulkan : comparaisons du robot sans accessoires et équipé, sur les châssis Polyvalent, Agile et Puissant, au repos, à l'échauffement et en course, de face, trois quarts et profil; vues du vrai garage à 1600 × 900 et 960 × 540; étapes de prise et de fixation. Des échantillons des trois châssis, des animations et du montage ont été inspectés. La planche `captures/fulguro-static/deux-modules.png` assemble les rendus Blender et les captures du moteur. Le rendu à 960 × 540 sur PC ne valide pas les performances d'un téléphone.

Les régressions du garage passent aussi : `test_forge_garage.gd` sans échec et `test_forge_module_stations.gd` avec 2 169 contrôles et zéro assertion échouée, y compris les deux nouveaux objets. Le test général des rangements signale à sa fermeture neuf instances et trois ressources encore présentes; son code de sortie est réussi. Son inventaire dynamique est fourni par le chantier de finition du garage, préservé pendant cet ajout.

Le kit initial du 2 octobre ajoute 17 032 triangles avec les deux Pyroboots ou 16 720 avec Bio Injector, sous le budget de 30 000 triangles pour les accessoires. Le robot complet de la forge avec Blaster compte respectivement 32 095 et 31 783 triangles. Après montage, orientation et échelle du châssis puissant, chaque pièce initiale reste sous 30,3 cm sur son axe mondial le plus étendu; la largeur entre les deux talons n'est pas la taille d'un propulseur.

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
