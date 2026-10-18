# Équiper le robot dans le garage

La direction retenue est la première des [trois maquettes](../outputs/garage-equipment-concepts-2026-10-15/manifest.json) : le robot devient l'interface, avec le stockage hors champ. La maquette sert de référence de composition ; le jeu conserve ses vrais modèles, matériaux, équipements et effets.

## Parcours

L'entrée conserve « Modifier un build » et « Créer un build ». La modification montre le robot en grand, entouré de cinq points : arme, offensif, défensif, mobilité et passif. Les libellés et les petits repères sur le corps sont cliquables. Un glissement sur le reste du robot permet de le tourner.

Le choix d'une famille ouvre une sélection compacte et une fiche à côté du robot. Cliquer sur une pièce la prévisualise sur son corps, sans modifier le brouillon ni les fichiers sauvegardés. Retour ou changement de famille rétablit l'équipement du brouillon. Tester transmet le brouillon installé, et non une pièce seulement prévisualisée.

## Présentation rapprochée de la maquette

La correction visuelle reprend la [référence approuvée](../captures/forge-robot-equipment/reference-maquette.png) : éventail incliné près du robot, images seules dans les choix sur PC, petits libellés reliés au corps, fiche courte avec un grand visuel et commandes Tester / Sauvegarder centrées. Les noms des choix restent accessibles au survol. Le bouton « ⋯ » ouvre la description complète, les statistiques et la démonstration sans changer le brouillon.

Le cadre est abaissé et rapproché, avec un angle légèrement de côté. Une lumière chaude éclaire le robot, un appoint sans ombre en détache le contour et l'établi est moins lumineux. La profondeur de champ garde le robot net et adoucit le décor ; son plan de netteté est aussi recalculé lors des changements immédiats de cadrage. L'anticrénelage est à 4× sur PC et reste à 2× sur mobile. Une surbrillance temporaire est appliquée aux instances du module sélectionné, sans changer les matériaux partagés avec le combat.

Les formes restent celles des modèles du jeu. La référence ImageGen réinterprétait également le robot et les accessoires : la correction de présentation ne remplace pas ces modèles.

Installer déclenche une pose physique de 3,30 secondes. Le bras récupère la pièce hors du champ, revient avec sa vraie géométrie, l'aligne et la verrouille. La caméra garde le même cadrage. Le robot présente son bras, son épaule ou son pied ; les équipements arrière entraînent une rotation temporaire. Le bouton Terminer traverse les mêmes contacts et signaux en accéléré. Annuler avant la fixation conserve l'ancien équipement ; après fixation, la pièce reste dans le brouillon. Les fichiers ne changent qu'à Sauvegarder.

Les libellés s'effacent après une courte période sans activité. Survoler le robot ou utiliser le clavier les révèle. En format compact, ils restent visibles dans la vue générale ; le catalogue garde le seul repère actif et organise les pièces sur deux colonnes. Les cinq étapes de création, les builds nommés et le retour d'entraînement sont conservés.

Les anciens meubles sont masqués dans le garage. Leurs instances restent les sources internes des modèles transportés par le bras ; elles ne sont plus sélectionnables comme meubles. Le rendu et les points de montage partagés avec le combat ne sont pas modifiés.

## Fichiers

- `scripts/ui/forge_robot_equipment.gd` : repères, sélection, fiche et format compact.
- `scripts/forge_garage.gd` : intégration, aperçu séparé du brouillon, navigation.
- `scripts/forge_garage_focus.gd` : cadrage rapproché stable, indépendant des bras écartés de la pose d'import.
- `scripts/forge_garage_stage.gd` : poses temporaires du squelette et remise en place.
- `scripts/forge_module_installation.gd` : récupération hors champ, durée courte et caméra fixe.

Les modifications de décor et de caméra déjà présentes dans les fichiers partagés sont conservées.

## Vérification locale

Le projet actif est `C:\Users\BOTTEROOOW\PROTOTYPE-V0.1`. L'ancien chemin `C:\RomainOpen\perso\Studio\game-source` indiqué dans les instructions n'existe pas sur ce PC.

`tools/test_forge_robot_equipment.gd` contrôle les clics réels sur les repères et les choix, les trois châssis à trois tailles de fenêtre, 66 montages physiques, l'annulation avec une pièce déjà saisie, l'accélération, la stabilité de la caméra, la création guidée, l'entraînement, la sauvegarde et la disparition des libellés. Ses fichiers utilisateur sont temporaires et isolés.

`tools/test_garage_build_journey.gd` exerce le vrai menu et le contrôleur de jeu, avec la nouvelle sélection. Il conserve les contrôles de création, de sauvegarde, de transmission au combat, de retour d'entraînement, d'entrées tactiles simulées, de zones sûres et de préservation des sauvegardes du joueur.

`tools/capture_forge_robot_equipment.gd` produit les captures natives dans [captures/forge-robot-equipment](../captures/forge-robot-equipment/), avec le rendu Vulkan Mobile sur PC. Les scripts et les journaux de cette passe restent dans le dépôt. Une petite fenêtre et des entrées tactiles simulées ne constituent pas une validation sur un appareil Android.

Résultat de la correction visuelle : import éditeur réussi ; 598 contrôles et 66 montages dans le test d'équipement ; 777 contrôles du parcours de builds ; seize captures natives. Les deux tests se terminent sans échec ni erreur de script.

Exemple de lancement :

```powershell
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --audio-driver Dummy --path 'C:\Users\BOTTEROOOW\PROTOTYPE-V0.1' --script res://tools/test_forge_robot_equipment.gd
```

Travail local ; aucune publication ni génération d'APK n'est effectuée par cette passe.
