# Forge : garage officiel 3D

Garage officiel issu du concept 1, accessible par **GARAGE** dans le menu principal.
**DUEL SOLO** utilise le dernier build sauvegardé et passe par l'écran de pré-combat.
Le fonctionnement des brouillons, des builds nommés et de leur sauvegarde est décrit dans [garage-builds.md](garage-builds.md).

## Ce qui fonctionne

- L'entrée montre l'atelier entier et quatre postes physiques : offensif, défensif, passif et mobilité.
  Cliquer ou toucher directement le rangement ouvre son catalogue avec un travelling de caméra.
  Les grands encadrés flottants sont supprimés ; les plaques physiques et les onglets restent disponibles.
  **ATELIER**, **MODULES** ou Échap depuis un catalogue ramène à la vue générale.
- Les dix-huit modules ont une cartouche provisoire à leur emplacement, avec l'icône du catalogue,
  un boîtier métallique et un repère de couleur par famille. Les assets définitifs peuvent remplacer ces cartouches.
- Atelier 3D local : établi, panneau d'outils, verrière, casiers, câbles et plateforme grillagée.
- Vrai robot du combat, animation d'attente, trois châssis avec leurs couleurs et statistiques.
- Salut et échauffement joués occasionnellement, avec un repos variable de huit à quatorze secondes
  et un retour progressif à l'attente. Les gestes restent sur place, sans répétition immédiate.
  Ils sont interrompus pendant la rotation manuelle, le changement d'équipement ou l'intervention du bras.
- Clic gauche maintenu sur le robot puis déplacement horizontal pour le faire tourner, avec son arme.
  Le relâchement conserve l'angle choisi ; le bras reste au repos pendant la manipulation et tant que le robot est tourné.
  Une inspection manuelle remet le robot dans la position prévue pour l'intervention du bras.
- Blaster, shotgun, Mekatana et Longshot réellement attachés au squelette ; choix des quatre catégories de modules.
  La zone des armes utilise une grille de deux colonnes quand plus de deux armes sont disponibles.
- Le clic sur une carte de module ouvre sa fiche et sa démonstration. **ÉQUIPER** lance la prise sur le rangement,
  le transport par la pince, l'alignement et la fixation sur le squelette du robot. Le brouillon change à la fixation.
  **TERMINER** accélère cette séquence ; Échap avant la fixation annule la pose sans changer le brouillon.
  **SAUVEGARDER** transmet le build au combat après son contrôle ; **TESTER** ouvre l'entraînement sans enregistrer.
- Pyroboots et Bio Injector retrouvent leurs vrais accessoires 3D à la fixation. Les autres modules
  conservent une cartouche provisoire sur leur point d'ancrage dans le garage. Voir [robot-module-visuals.md](robot-module-visuals.md).
- Fiches d'information des armes accessibles sans modifier l'équipement sélectionné.
- Choix d'arène exposé quand la variante d'arène est disponible dans le projet.
- Bras industriel à quatre articulations : approche, scanner, retrait et repos.
  La sauvegarde anime le bras durant cinq secondes. La pose d'un module dure environ sept secondes,
  avec un socle mobile et plusieurs cadrages continus. Le catalogue et la rotation sont suspendus pendant la pose.
  Quitter ou masquer le garage libère le bras, la caméra et la pièce transportée.
- Monde 3D séparé de l'arène. Le rendu et les animations sont suspendus quand le garage est caché.
- Éclairage chaud, contre-éclairage froid, poussière discrète et profondeur de champ sur le décor.

## Sources et organisation

`scripts/forge_garage.gd` construit l'interface et émet les choix d'équipement.
`scripts/forge_garage_stage.gd` gère le monde, la caméra, le robot et ses armes.
`scripts/forge_service_arm.gd` pilote le clip Blender et les étincelles.
`scripts/forge_module_stations.gd` construit les rangements et leurs cartouches partagées.
`scripts/forge_module_installation.gd` pilote les articulations, la prise, le transport, les ancrages et la caméra de pose.
`scripts/game_flow.gd` assure l'entrée, la sauvegarde, le retour et le lancement du duel.

Le décor et le bras sont produits localement par `tools/build_forge_garage.py`, avec Blender 4.5.13 LTS.
La source éditable est `art/forge-garage/source/forge_garage.blend` ; `.gdignore` évite une réimportation Blender implicite.
Les exports utilisés par Godot sont `workshop.glb` et `service_arm.glb`, accompagnés de leurs textures.
Les modèles de combat et leurs matériaux partagés ne sont pas modifiés : les ajustements du garage portent sur des instances.
Le garage utilise une variante opaque du shader de couleur des châssis, pour conserver leur profondeur avec le flou
d'arrière-plan. Le shader partagé continue de gérer la transparence et la dissimulation pendant le combat.

Le bras emploie une hiérarchie rigide avec des pivots de rotation et une animation exportée en glTF,
plutôt qu'une vidéo ou une image déformée. Son outil suit réellement les articulations dans l'espace.
Godot retire le suffixe `_cycle` à l'import ; le contrôleur reconnaît aussi le clip importé `service`.

## Vérification des postes physiques

`tools/test_forge_module_stations.gd` vérifie les quatre rangements et leurs dix-huit cartouches,
les 54 combinaisons module/châssis, la continuité des articulations et de la pièce transportée,
son maintien rigide dans la pince, le changement du brouillon uniquement à la fixation,
les annulations, le bouton **TERMINER** et la propriété exclusive du bras.
Les vrais clics sur les postes, les cartes et **ÉQUIPER**, leurs cadrages à 960×540, 1280×720
et 2340×1080, la sauvegarde isolée et le lancement de l'essai passent les 1 172 contrôles.
Le mode `-- --runtime` vérifie également la pose complète avec les trames natives du moteur et de vraies entrées GUI.

Les tests du garage, des gros plans, de la sauvegarde, du parcours de jeu, de la navigation
et des démonstrations restent valides avec le nouveau parcours de sélection.
Les tests ne remplacent pas les sauvegardes personnelles par leur brouillon.
Les captures de `tools/capture_forge_module_stations.gd` proviennent du rendu Vulkan Mobile réel
et sont conservées dans `captures/forge-module-stations/`. Son mode `-- --movie`, avec Godot Movie Maker,
enregistre le déplacement vers un poste, la pose et le retour à l'atelier.

Cette vérification concerne le PC. Le rendu, les performances et le confort sur un véritable appareil Android restent à contrôler.

## Armes au mur et recharge des passifs

Les quatre vrais modèles d'armes sont désormais suspendus horizontalement sur des crochets fixés
au mur arrière droit, à côté de la verrière. Ce placement laisse les armes visibles pendant la
sélection sans traverser l'établi ou sa lampe. Le bras les décroche vers l'allée avec une courte
levée, et son socle se rapproche pour atteindre les supports les plus hauts.

Les six passifs restent au poste avant gauche, dans une borne métallique avec tiroir,
plateau incliné à 45 degrés, logements de recharge et repères violets. Le Réacteur auxiliaire
conserve son vrai modèle et sa pose physique ; les autres passifs gardent leurs cartouches
de catalogue et leur application directe au brouillon. Les trois autres postes gardent leurs rangements.

La prise, les volumes cliquables et les cadrages suivent les nouveaux supports.
`tools/test_forge_module_stations.gd` passe ses 1 876 contrôles de transport, d'annulation,
de sélection et de sauvegarde, sur les trois châssis et trois résolutions.
Son mode `-- --runtime --weapon-only` passe 120 contrôles et pose réellement le Longshot
en environ sept secondes avec les trames natives du moteur.
`tools/capture_forge_wall_storage.gd` produit douze captures Vulkan dans
`captures/forge-wall-storage/` : atelier, armes et passifs à 960×540, 1280×720 et 2340×1080,
ainsi que les prises du Blaster, du Longshot et du Réacteur auxiliaire. Le parcours du socle
reste à l'intérieur des murs et évite le poste défensif. Ces vérifications concernent le PC.

## Matériaux communs et éclairage de l'atelier

Les meubles, parois et articulations du bras utilisent une même famille d'acier peint anthracite,
de métal exposé et de plaques crème. Le béton et le bois ont leur propre grain, rugosité et relief.
Les treize textures de 512 pixels dans `art/forge-garage/finishes/` sont reproductibles avec
`tools/build_forge_surface_textures.py` (Python, Pillow et NumPy). Leur projection triplanaire
conserve une échelle physique commune sur les modèles importés et les meubles construits en code.
Les matériaux sont appliqués aux instances du garage ; les ressources du combat restent intactes.

La verrière diffuse une lumière chaude locale, l'établi garde sa lampe et le robot reçoit une
lumière principale neutre. Le voile brun et les émissions permanentes des catégories sont réduits.
Le nombre de lumières avec ombres reste à trois ; aucun éclairage global ou brouillard volumétrique
n'est ajouté. Le vitrage est séparé du maillage opaque pour laisser passer sa lumière.

Les encadrés flottants OFFENSIF, DÉFENSIF, PASSIF et MOBILITÉ sont retirés. Le clic ou le toucher
sur les postes physiques ouvre le catalogue ; au survol, le poste s'éclaire et le curseur devient
une main. Les onglets **MODULES** et **ARMES** restent accessibles au clavier et à la souris.

Les captures GPU avec l'anticrénelage normal du jeu sont produites par
`tools/capture_forge_wall_storage.gd -- --finishes` dans `captures/forge-finishes/` :
atelier et cinq postes à 960×540, 1280×720 et 2340×1080, puis trois prises d'équipement.
Les tests des postes vérifient les clics et touches physiques à ces trois résolutions,
les installations sur les trois châssis et la sauvegarde isolée. Les tests du garage et du focus
passent également, ainsi que deux installations en temps réel avec Vulkan Mobile sur PC.
Ces vérifications ne mesurent pas les performances sur un téléphone.

## Hangar autour de l'atelier

Le garage se prolonge maintenant dans un hangar industriel au lieu de flotter sur un fond noir.
Le béton et ses joints continuent autour de la dalle, avec une structure gris bleuté,
une passerelle lointaine, deux ateliers voisins sommaires et quelques lampes ambrées.
Le cadrage, les meubles, les rangements et l'éclairage principal de l'atelier sont conservés.

`scripts/forge_garage_hangar.gd` construit ce décor statique uniquement dans le monde 3D privé
du garage. Il réutilise les textures de finition existantes et regroupe ses volumes dans huit
lots MultiMesh. Ses quatre petites lumières locales ne calculent pas d'ombres ; aucun volume
de brouillard, collision, traitement par frame ou cible de sélection n'est ajouté.
La caméra voit désormais jusqu'à 90 mètres pour conserver la structure distante dans ses vues.

`tools/capture_forge_hangar.gd` produit dix captures natives dans `captures/forge-hangar/` :
les cinq postes, l'atelier à trois résolutions et deux positions du léger arc de caméra.
L'option `-- --overview` limite la capture à la vue générale en 1280×720.
Ces captures utilisent le rendu Vulkan Mobile et l'anticrénelage habituel du jeu.
Le parcours du garage et les 230 contrôles de focus passent ; le test natif du mouvement
de caméra passe ses 107 contrôles, dont les survols, clics et glissements souris et tactiles.
Le rendu et les interactions ont été vérifiés sur PC ; le téléphone reste à vérifier.

## Mouvement discret de la caméra

La vue générale de l'atelier décrit un léger arc latéral : un cycle complet de 18 secondes,
avec une amplitude de 10 cm de chaque côté. La position et l'orientation tournent autour
d'un même point du robot, qui reste stable à l'écran. La hauteur et le champ de vision restent fixes.
Le mouvement commence après le travelling d'arrivée et atteint progressivement sa vitesse en 1,5 seconde.

Le survol d'un poste d'armes ou de modules et la rotation manuelle du robot figent la caméra
à sa position courante. La reprise accélère doucement depuis cette position, sans recentrage.
Le suivi du pointeur continue au-dessus de l'interface ; sortir de la fenêtre libère la pause
de survol. Les vues de catalogue et d'inspection gardent leur cadrage fixe, et les installations
conservent le contrôle exclusif de leurs travellings. Fermer et rouvrir le garage réinitialise le mouvement.

`tools/test_forge_camera_motion.gd` vérifie l'amplitude, la stabilité du robot, la visibilité
des cinq postes, les pauses et les clics/glissements souris et tactiles à trois résolutions.
L'option `-- --runtime` vérifie aussi la progression, la pause et la reprise dans une fenêtre
Godot avec les frames du moteur. Les tests existants du focus et du parcours du garage passent également.

`tools/capture_forge_camera_motion.gd` rend un cycle complet dans `captures/forge-camera-motion/`.
Le robot est figé uniquement pour cet enregistrement afin de rendre le mouvement de caméra lisible.
`tools/encode_forge_camera_motion.py` encode ses 360 images GPU en aperçu animé de 18 secondes :
`captures/forge-camera-motion/garage-camera.gif`. Le rendu et les interactions sont vérifiés sur PC ;
les performances et le confort sur un téléphone restent à vérifier.

## Vérification du jalon initial

La version destinée à `main` a été importée et testée dans un checkout propre, sans les autres chantiers locaux.
Six tests Godot produisent leur résultat PASS : `test_forge_garage`, `test_robot_forge`, `test_weapon_forge`,
`test_navigation_reliability`, `test_game_flow` et `test_mekatana` (dans `tools/`).
Ils couvrent l'entrée directe, le retour au menu, les trois châssis, les quatre armes, leurs fiches,
les modules, la persistance, plusieurs tailles de fenêtre et le lancement du duel.
Les sauvegardes et préférences d'origine ont été restaurées après les tests.
Le chargement de la configuration locale chiffrée GD-Sync signale un diagnostic MD5 dans ce checkout ;
ce diagnostic provient de l'addon inchangé et ne constitue pas une validation du multijoueur.
Les tests historiques du robot et du parcours signalent aussi une ressource audio retenue à la fermeture.
Le test du nouveau garage vérifie notamment les choix, leur sauvegarde, la taille des icônes et des armes,
les déplacements du bras, les étincelles, la suspension hors écran et l'équipement reçu par le joueur.
Il restaure la sauvegarde d'origine après son exécution.
La rotation est vérifiée avec de vraies entrées GUI : clic sur le robot, déplacement, relâchement,
clics sur le décor et les boutons, perte de focus, fermeture et réouverture, arme et inspection du bras.
Le test passe sans affichage et avec le rendu Vulkan en 1280×720 et 1600×900.
L'option `-- --capture-rotation` produit les vues de face et de dos dans `captures/forge-garage/rotation-*.png`.
Le même test vérifie le déclenchement et la fin des gestes, leur espacement, les interruptions,
la suspension hors écran et l'indépendance des animations du combat.
L'option `-- --capture-gestures` produit plusieurs poses rendues du salut et de l'échauffement.

`tools/capture_forge_garage.gd` produit des captures GPU aux différentes phases du bras,
ainsi que le shotgun avec le châssis puissant, le panneau des modules, les deux nouvelles armes et la fiche d’information du Longshot.
Les captures dans `captures/forge-garage/` proviennent du rendu Godot Vulkan Mobile sur GTX 1660 SUPER.
Elles ont été inspectées à 1280×720 et 1920×1080.
La demande de fenêtre 2340×1080 est plafonnée par l'écran du PC : elle ne constitue pas une validation sur téléphone.

L'aperçu `garage-motion.gif` contient le cycle réel enregistré par Godot Movie Maker :
scène `scenes/forge_garage_preview.tscn`, sortie `captures/forge-garage/motion/garage.png`,
12 images/seconde, 152 images, puis encodage Pillow avec `tools/encode_forge_garage_preview.py`.
Le dossier `motion/` est un cache ignoré par Git ; les captures ne sont pas des textures du jeu.

## Suite de la refonte

Ce jalon établit le parcours jouable et l'animation réelle. Le décor reste une première construction géométrique ;
la richesse des surfaces, les accessoires, la composition du bras et la finition des panneaux doivent encore progresser
pour atteindre la maquette. Les trois châssis réutilisent le modèle actuel, avec leurs variations existantes.

La pose des modules utilise maintenant les articulations du bras et un socle mobile pour rejoindre chaque rangement,
avec des déplacements de caméra. Les modèles définitifs des modules et une mise en scène du remplacement des armes
restent des passes distinctes.
Les performances sur Android et le confort tactile restent à vérifier sur un véritable appareil.

## Démonstrations en entraînement

La zone en bas à gauche affiche une vidéo silencieuse en boucle de l'arme ou du module consulté.
Les trois châssis sont directement accessibles à l'ancien emplacement d'**INSPECTER**.
Le bras conserve son cycle automatique. La sélection d'une arme, l'ouverture de sa fiche,
l'ouverture d'une catégorie de modules et le survol ou le focus d'une option actualisent la démonstration.
Consulter une fiche ou survoler un module ne modifie pas l'équipement ; cliquer garde la sélection habituelle.
La lecture s'arrête lorsque la forge est cachée et reprend à son ouverture.
Cliquer ou toucher la vignette agrandit la vidéo sur un fond sombre, sans interrompre sa lecture.
La vue conserve les proportions 16:9 et s'adapte à la fenêtre. **FERMER**, **Échap** ou un clic
hors du cadre ramènent à la vignette ; les entrées ne traversent pas la vue vers les boutons du garage.
La vignette s'ouvre également au clavier avec Entrée lorsqu'elle a le focus.

`scripts/forge_training_demo.gd` contient les références explicites aux quatorze vidéos Ogg Theora
de `art/forge-demos/`, afin de les inclure dans les exports. Elles couvrent les quatre armes,
les huit modules actifs et les deux passifs disponibles dans ce checkout.
Les clips montrent les vrais modèles, animations, projectiles, collisions, dégâts et effets du combat
dans le décor du TrainingGround. Le katana enchaîne ses trois coups avec repositionnement,
le shotgun ses trois salves et sa recharge, le Longshot son cinquième tir amélioré,
le Javelin son recast, les défenses des tirs entrants et les passifs leur déclenchement ou leur soin.

`tools/record_forge_training_demo.gd` automatise les commandes dans le terrain d'entraînement.
Ses adaptateurs désactivent seulement la lecture des entrées humaines et la sauvegarde du build.
Le contrôleur et les règles du combat restent ceux du jeu. Exemple de réenregistrement :

```powershell
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path 'C:\Users\BOTTEROOOW\PROTOTYPE-V0.1' --fixed-fps 30 --disable-vsync --write-movie 'art/forge-demos/mekatana.ogv' --script tools/record_forge_training_demo.gd -- --demo mekatana
```

Les vidéos doivent être régénérées après un changement de comportement de l'équipement montré.
`tools/build_forge_training_demos.py --ffmpeg <chemin de ffmpeg.exe>` reconstruit tout le catalogue,
retire l'image d'initialisation, encode en 640×360 sans piste audio et vérifie le décodage complet
avant de remplacer chaque vidéo. `--only mekatana` limite une reprise à un équipement.
`tools/test_forge_training_demo.gd` vérifie la couverture du catalogue, le décodage des quatorze clips,
les choix et consultations, la boucle, l'arrêt hors écran et la disposition à trois tailles de fenêtre.
Il vérifie aussi l'ouverture agrandie par les entrées GUI souris, clavier et toucher simulé,
la continuité de lecture, les fermetures sans activer les contrôles derrière et la fermeture avec la forge.
`tools/capture_forge_training_demo.gd` capture la forge avec les vidéos en lecture, en vignette et agrandies.

Le contrôle local passe en mode headless et avec Vulkan Mobile, ainsi que le test d'intégration du garage.
Les captures sont inspectées à 1280×720 et 960×540. Les quatorze clips sont entièrement décodés lors
de leur génération, puis relus depuis le pack du preset Android avec `tools/test_forge_training_demo_pack.gd`.
Le pack final compile sans erreur et contient les mêmes vidéos que les clips vérifiés, contrôlés par SHA-256.
Ce contrôle ne valide pas encore le rendu, les performances ou les interactions sur un véritable téléphone.
