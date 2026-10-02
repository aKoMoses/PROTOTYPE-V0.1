# Forge : garage officiel 3D

Garage officiel issu du concept 1, accessible par **GARAGE** dans le menu principal.
**DUEL SOLO** utilise le dernier build sauvegardé et passe par l'écran de pré-combat.
Le fonctionnement des brouillons, des builds nommés et de leur sauvegarde est décrit dans [garage-builds.md](garage-builds.md).

## Ce qui fonctionne

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
- Le clic change le brouillon et son aperçu. **SAUVEGARDER** transmet le build au combat après le travail du bras ; **TESTER** ouvre le terrain d'entraînement sans enregistrer le brouillon.
- Pyroboots et Bio Injector ont des accessoires 3D légers sur le vrai squelette, avec zoom et trois secondes de travail ciblé au clic. Voir [robot-module-visuals.md](robot-module-visuals.md).
- Fiches d'information des armes accessibles sans modifier l'équipement sélectionné.
- Choix d'arène exposé quand la variante d'arène est disponible dans le projet.
- Bras industriel à quatre articulations : approche, scanner, retrait et repos.
  La sauvegarde anime le bras durant cinq secondes. La sélection d'un accessoire physique compte trois secondes de travail après son approche.
  Les changements d'équipement et la rotation annulent proprement l'intervention ciblée.
- Monde 3D séparé de l'arène. Le rendu et les animations sont suspendus quand le garage est caché.
- Éclairage chaud, contre-éclairage froid, poussière discrète et profondeur de champ sur le décor.

## Sources et organisation

`scripts/forge_garage.gd` construit l'interface et émet les choix d'équipement.
`scripts/forge_garage_stage.gd` gère le monde, la caméra, le robot et ses armes.
`scripts/forge_service_arm.gd` pilote le clip Blender et les étincelles.
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

## Vérification du jalon

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

Les prochaines passes peuvent ajouter une mise en scène de remplacement des armes, une pose spécifique du robot pendant
l'intervention, des mouvements de caméra et des effets audio. Le clip actuel suit une trajectoire préparée ; il n'emploie
pas de cinématique inverse adaptative pour toucher toutes les pièces ou accompagner un robot tournant librement.
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
