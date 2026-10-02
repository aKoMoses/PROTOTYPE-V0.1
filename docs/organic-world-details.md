# Réactions organiques du décor

La passe ajoute des détails locaux aux cartes existantes, installés automatiquement par `VFXManager`. Les nouvelles réactions complètent les impacts et la présentation du mecha déjà présents.

- L'herbe s'écarte progressivement autour du joueur et revient doucement après son passage. Les matériaux réellement affichés restent réactifs lorsqu'un autre directeur les duplique.
- Une impulsion directionnelle traverse les touffes, avec propagation, oscillation et amortissement. Les tirs traversant les herbes et les déplacements rapides projettent quelques fragments de feuilles.
- Les tirs sont limités à leur premier obstacle pour ne pas agiter un buisson situé derrière un mur.
- Les bâches et les bannières réagissent au souffle avec un mouvement amorti. Les attaches et les coins cousus restent fixes.
- Les impacts sur les surfaces solides libèrent des éclats avec gravité, rotation, rebond contre les obstacles, repos et disparition progressive.
- Le shotgun éjecte une douille qui tourne, tombe et rebondit. Les armes à énergie n'éjectent pas de douilles.
- Les semelles laissent de petites traces alternées ; les freinages et les changements brusques de direction étirent ces marques. Une poussière basse accompagne les contacts.
- Les traces suivent le sol de chaque carte, les plateformes et les rampes. La cour classique utilise son plan visuel sans ajouter de collision au jeu.
- Les explosions de roquettes soulèvent des débris et une poussière radiale au ras du sol, et bousculent les feuillages et tissus voisins.
- Quelques poussières flottent lentement dans la brise pendant le combat.

## Intégration et budgets

`scripts/environment/organic_world_details.gd` observe trois signaux visuels de `VFXManager` et les effets de roquettes existants. Il n'écrit ni dans les acteurs ni dans les collisions et utilise un générateur aléatoire privé.

Cinq MultiMesh fixes regroupent éclats, feuilles, douilles, marques et poussières. Les limites sont de 72 fragments, 48 traces et 18 poussières en qualité normale ; 28 fragments, 20 traces et aucune poussière ambiante en qualité basse. Les sondes au sol et les balayages des fragments sont également plafonnés par frame.

Le joueur local est le seul acteur à écarter l'herbe. Les réactions des adversaires exigent leur visibilité explicite pour l'observateur. Les contacts masqués par un obstacle sont rejetés. La pause fige la simulation, les téléportations ne créent pas de traces et les menus ou nettoyages de manche retirent les détails transitoires.

## Vérification du 2 octobre 2026

- `tools/test_organic_world_details.gd` : **48 contrôles réussis**, dans le duel, l'entraînement et la survie, avec vérification des sols de l'arène test, de la dissimulation, de la pause, des téléportations et des budgets.
- `tools/test_bush_gameplay.gd` : **PASS**, aucune régression de visibilité.
- `tools/test_vfx.gd` : **71 contrôles réussis**, dont les dommages inchangés et les budgets sur trois minutes simulées dans chaque qualité.
- `tools/test_combat_presence.gd --fixed-fps 60` : **74 contrôles réussis**. La première exécution sans cadence fixe a échoué sur la mesure instantanée de déplacement ; le rejeu à 60 frames/s passe.
- `tools/capture_organic_world_details.gd` : **110 images natives** du renderer Mobile/Vulkan, sans erreur de rendu. La séquence couvre l'entrée et la sortie du feuillage, les tirs et une explosion.

Ces vérifications ont été réalisées sur PC. Les plafonds de qualité basse sont testés ; les performances sur un appareil Android physique ne sont pas mesurées ici.

## Ambiance des ateliers

La seconde passe anime les équipements existants et ajoute de petits boîtiers de service aux façades des ateliers du duel, de l'arène test, de l'entraînement et de la survie.

- Les enseignes alternent entre circuits stables, alimentation affaiblie et pannes occasionnelles. Le rallumage fait deux essais distincts avant de se stabiliser. Les ateliers ont des phases et périodes indépendantes.
- Une lettre peut rester éteinte puis reprendre. Les groupes de lettres et l'orientation de l'enseigne sont retrouvés dans la géométrie des tubes, y compris pour les panneaux tournés ou redimensionnés.
- Le verre éteint reste physiquement visible. Tubes, halos, illumination du métal et lueur au sol utilisent la même alimentation ; la disparition d'une lettre réduit aussi la lumière environnante.
- Les voyants des machines respirent et accélèrent pendant leur cycle de travail.
- Les écrans affichent une courbe qui défile, une jauge mobile et un petit schéma, avec de brèves interférences espacées.
- Les ventilateurs démarrent progressivement, varient légèrement en vitesse et ralentissent avec de l'inertie lorsque la machine s'arrête.
- Les conduites émettent des bouffées de vapeur qui montent et dérivent. Des gouttes de condensation tombent sous la gravité et produisent un petit cercle au sol.
- Un conduit endommagé produit rarement un arc très bref. Il teinte et renforce une lampe existante sans ajouter de nouvelle lumière.
- Les vraies lanternes suspendues oscillent doucement. Leur lumière, leur lueur au sol et une ombre douce projetée suivent le mouvement. Les impacts visibles peuvent bousculer les suspensions et la vapeur voisine.

`workshop_ambience.gd` est installé une fois par branche de décor via `workshop_dressing.gd`. Les meshes sont copiés au niveau de l'instance ; les ressources originales, les triangles du décor, les collisions et la navigation sont conservés. Les matériaux non concernés sont partagés, les sommets restent indexés et les lanternes sont extraites une seule fois. Les équipements supplémentaires n'ajoutent aucun objet physique.

Les plafonds sont de 128 circuits, 16 boîtiers et 16 suspensions par branche. Au plus quatre boîtiers et six suspensions proches sont animés en qualité normale ; deux boîtiers, aucune oscillation de suspension, vapeur, goutte ou arc en qualité basse. Le budget existant de six lumières locales sans shadow maps est conservé. Les ombres mobiles utilisent de petites surfaces projetées.

Les horloges CPU alimentent également les shaders des écrans et voyants : la pause fige toutes ces animations. Une branche de carte cachée suspend son horloge et rejette les impacts. Les impulsions exigent la visibilité locale du contact. Un nettoyage de manche retire immédiatement les effets transitoires, y compris leur contribution aux matériaux et aux lumières.

## Vérification de l'ambiance

- `tools/test_workshop_ambience.gd --fixed-fps 60` : **104 contrôles réussis**, couvrant les cartes, les vraies lettres, les couleurs, l'extinction synchronisée, l'inertie, les condensations, les arcs, les suspensions, la pause, les transitions et les budgets de qualité.
- `tools/test_workshop_presentation.gd` : **PASS**, géométrie et éclairage existants conservés.
- `tools/test_map_reference.gd` : **1 262 contrôles réussis**, dans l'arène test, l'entraînement et la survie.
- `tools/test_reference_render_finish.gd` : **110 contrôles réussis**, finition des matériaux et budgets de rendu conservés.
- `tools/test_organic_world_details.gd` : **48 contrôles réussis** après intégration de l'ambiance.
- `tools/capture_workshop_ambience.gd` : **180 images natives Mobile/Vulkan**, sans erreur de rendu, avec extinction et rallumage d'une enseigne centrale et vue rapprochée de son équipement.

Les fichiers de capture permettent de reproduire l'aperçu sans modifier les paramètres des circuits de production. Les rendus ont été inspectés sur PC ; aucune mesure sur Android physique n'est revendiquée.

## Petits objets et atmosphère locale

La troisième passe ajoute des détails de vie autour des ateliers, dans les quatre variantes de carte.

- Les papiers imprimés frémissent légèrement, se soulèvent dans le sillage du mecha et glissent après un impact ou une explosion. Ils retombent et s'arrêtent avec de la friction.
- De petites boîtes métalliques roulent selon la distance parcourue, rebondissent contre les obstacles existants et se stabilisent près de leur emplacement d'origine.
- Des trousseaux et étiquettes suspendus oscillent doucement. Les impacts visibles leur donnent une impulsion amortie.
- De petites flaques huileuses ont un bord irrégulier et des reflets irisés discrets. Un contact proche produit une ride qui s'élargit puis disparaît.
- Les lampes allumées révèlent un faible volume lumineux et quelques poussières flottantes. Ces effets suivent leur alimentation et disparaissent avec la lumière.
- Une ombre d'oiseau passe brièvement sur le sol, avec des battements d'ailes. Sa trajectoire reste fixée pendant le passage lorsque la caméra suit le joueur.

`scenery_life.gd` est installé une fois par `WorkshopAmbience`. Sept MultiMesh fixes regroupent les objets et l'atmosphère. Le stockage est plafonné à 24 objets au sol, 16 accessoires suspendus et huit flaques. À proximité de la caméra, au plus six objets au sol, quatre accessoires suspendus, quatre flaques, trois volumes lumineux, 24 poussières et une ombre d'oiseau sont affichés. La qualité basse réduit ces limites à trois objets, deux accessoires et deux flaques ; les effets atmosphériques supplémentaires sont désactivés.

Les accessoires sont placés devant les faces accessibles des collisions existantes. Cela couvre notamment les ateliers de survie transplantés derrière les murs de l'arène. Les mouvements suivent les sols et rampes, restent dans un rayon de 1,1 mètre autour de leur origine et disposent de quatre balayages de collision par frame, deux en qualité basse. Aucun corps physique, collider, lumière ou élément de navigation supplémentaire n'est ajouté.

Le sillage utilise seulement le joueur local actif. La visibilité du contact et celle de chaque accessoire doivent être admises par le système de réactions organiques. Les contacts cachés, téléportations et branches masquées ne créent aucune impulsion. Toutes les animations, y compris les shaders, utilisent une horloge qui s'arrête pendant la pause. Le nettoyage de manche remet les objets à leur origine et efface immédiatement les instances GPU. Le générateur aléatoire privé conserve la séquence aléatoire du combat.

## Vérification des petits détails

- `tools/test_scenery_life.gd --fixed-fps 60` : **119 contrôles réussis**, avec contacts et explosions de production dans le duel, l'entraînement et la survie. Les contrôles couvrent le placement devant les murs, les rebonds, les impacts masqués, le sillage local, les téléportations, les sols et rampes, la pause, les changements de carte, les budgets, l'extinction des poussières avec les lampes et le nettoyage de manche.
- `tools/test_workshop_ambience.gd` : **104 contrôles réussis** après intégration.
- `tools/test_workshop_presentation.gd` : **PASS**, présentation et budget des lumières existantes conservés.
- `tools/test_organic_world_details.gd` : **48 contrôles réussis** après intégration.
- `tools/test_map_reference.gd` : **1 262 contrôles réussis** après intégration.
- `tools/capture_scenery_life.gd` : **150 images natives Mobile/Vulkan**, sans erreur de rendu, couvrant un passage du joueur, un impact réel et une explosion. La capture commence pendant un passage d'oiseau sans changer sa période de production de 41 secondes.

Les images natives ont été inspectées sur PC. Les budgets de qualité basse sont testés ; les performances sur un appareil Android physique ne sont pas mesurées dans cette passe.
