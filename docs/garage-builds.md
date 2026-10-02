# Garage et builds sauvegardés

Le menu principal donne accès au Garage. « Duel solo » utilise le dernier build sauvegardé. Le Garage reprend la maquette validée : catalogue illustré à gauche, robot entier au centre, description et vidéo agrandissable à droite, puis « Tester » et « Sauvegarder » en bas.

Les onglets Robot, Armes et Modules préparent les six éléments du loadout : châssis, arme, offensif, défensif, mobilité et passif. Le survol affiche une fiche sans équiper l'option. Le clic met à jour le brouillon et l'aperçu du robot. La rotation du robot à la souris ou au toucher reste disponible.

La liste du bas recharge les builds enregistrés. Le crayon renomme le brouillon, « + » crée un build et le bouton de copie duplique ses choix. Le point à côté du nom indique des changements à sauvegarder. Sélectionner un autre build remplace le brouillon courant ; son activation pour le combat passe par « Sauvegarder ».

## Installation

« Sauvegarder » fige le brouillon et masque toute l'interface pendant cinq secondes. Le bras mécanique existant utilise son scanner, ses articulations, son éclairage et son moteur sur le torse, le bras et les jambes. Avec Bio Injector, la dernière zone est le réacteur. Le bras se retire, la sauvegarde se termine, puis le menu réapparaît. Le bouton Scanner a été retiré.

Les fichiers locaux ne changent qu'à la fin de cette séquence. Les doubles clics et les commandes de retour sont bloqués pendant l'installation. Une fermeture du Garage annule l'installation sans enregistrer. Un échec disque garde le brouillon et permet de réessayer.

`user://prototype0_builds.cfg` contient les builds nommés et l'identifiant actif. `user://prototype0_loadout.cfg` conserve le format utilisé par le duel et les salons. En l'absence de bibliothèque, le loadout existant devient le premier build « DUELLISTE ».

## Tester et vidéos

« Tester » ouvre le terrain d'entraînement avec le brouillon, sans l'enregistrer. Ses modifications reviennent au Garage avec le nom du build ; le build sauvegardé reste celui utilisé en duel. Le sol possède son propre calque de collision, pour que Permutation et Éclipse puissent atteindre une destination libre.

Les vidéos existantes sont conservées. Les neuf équipements récents disposent aussi d'un enregistrement de leur vrai comportement : Panier roquettes, Projector, Counter, Permutation, Éclipse, Réacteur auxiliaire, Traqueur, Alternateur et Inertie. Le scénario vérifie leurs effets de combat pendant l'enregistrement. Les clips sont silencieux, jouent en boucle et s'agrandissent à la souris, au clavier ou au toucher.

## Vérification locale

- `tools/test_forge_build_installation.gd` : brouillon, durée, sauvegarde unique, bibliothèque multiple, annulation, échec disque, scanner sur les trois châssis et mise en page dans quatre résolutions.
- `tools/test_forge_arm_runtime.gd` : vrai menu, traitement des frames, trois zones scannées, absence d'écriture avant la fin, aller-retour de « Tester » et Permutation sur le terrain réel.
- `tools/test_forge_garage.gd` : modèles du combat, armes, shaders, rotation, gestes et transmission du build sauvegardé au duel.
- `tools/test_forge_training_demo.gd` : décodage, agrandissement, boucle, fermeture, souris, clavier, tactile et proportions.
- `tools/test_forge_garage_focus.gd` : cadrage du robot entier, effets sur les pièces, rotation et transitions du contrôleur d'inspection conservé pour les outils.
- `tools/test_forge_manual_scanner.gd` : cinématique, trajectoires, éclairage et entrées du scanner existant, dans un montage de développement distinct de l'interface du Garage.
- `tools/capture_forge_build_installation.gd` : captures natives du menu, du catalogue, des vidéos, de l'installation et du format paysage mobile dans `captures/garage-builds/`.
- `tools/record_forge_build_installation.gd` : vidéo native de la séquence de sauvegarde, avec des fichiers isolés du profil personnel.

Pour enregistrer les démonstrations récentes, `tools/build_forge_training_demos.py --native --only ... --ffmpeg CHEMIN` conserve la vidéo Theora produite par Godot et retire sa piste audio. Chaque fichier est décodé avant d'être copié dans `art/forge-demos/`. Les logs et les empreintes restent dans `captures/forge-demos/`.
