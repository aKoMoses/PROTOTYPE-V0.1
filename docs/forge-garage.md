# Forge : garage officiel 3D

Garage officiel issu du concept 1, ouvert directement par **DUEL SOLO** et **MODIFIER L'ÉQUIPEMENT**.
**RETOUR** ramène au menu principal ; aucun écran de forge intermédiaire n'est affiché.

## Ce qui fonctionne

- Atelier 3D local : établi, panneau d'outils, verrière, casiers, câbles et plateforme grillagée.
- Vrai robot du combat, animation d'attente, trois châssis avec leurs couleurs et statistiques.
- Blaster, shotgun, Mekatana et Longshot réellement attachés au squelette ; choix des quatre catégories de modules.
  La zone des armes utilise une grille de deux colonnes quand plus de deux armes sont disponibles.
- Équipement enregistré par le système existant et transmis au duel par **JOUER**.
- Fiches d'information des armes accessibles sans modifier l'équipement sélectionné.
- Choix d'arène exposé quand la variante d'arène est disponible dans le projet.
- Bras industriel à quatre articulations : approche, contrôle avec étincelles, retrait et repos.
  Le cycle dure dix secondes. Il démarre automatiquement après l'arrivée, puis laisse quinze secondes de repos.
  **INSPECTER** permet de le déclencher ; le changement de châssis annule proprement une intervention.
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
