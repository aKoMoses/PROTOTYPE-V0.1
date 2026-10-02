# Lot mechas et décors du 2 octobre 2026

Le lot vérifié ajoute le châssis puissant orange, 28 animations contextuelles pour les mechas et des gestes adaptés aux douze modules. Il comprend également le cadrage de combat réglable, le médaillon des passifs, les nouvelles roquettes, la finition des cartes et les équipements animés des ateliers.

La dernière passe finalisée ajoute les papiers soulevés par le passage du joueur, les boîtes roulantes, les accessoires suspendus, les flaques huileuses, la poussière lumineuse et les ombres d'oiseaux. Les réactions respectent la visibilité locale, la pause, les collisions existantes et les budgets de qualité.

Static Shield dure au maximum deux secondes et accepte une annulation immédiate. Les armes et le guide de visée suivent la direction choisie tant que la commande de tir reste maintenue.

## Validation de la version réunie

Une copie isolée du projet a été contrôlée avec Godot 4.7.2. Les 137 suites initiales et les deux variantes supplémentaires des tests d'animations sur le châssis puissant réussissent. Après l'intégration des derniers détails finalisés, la nouvelle suite des petits objets et les contrôles des cartes, de l'ambiance, des transitions et des finitions sont rejoués, portant le total à 138 suites du projet. L'import des ressources, l'export du pack Windows et la lecture des vidéos de démonstration depuis ce pack sont également vérifiés.

Les sorties rapides de scène ont révélé des démarrages différés de décor sur une branche déjà retirée. Les trois contrôleurs concernés vérifient maintenant leur présence dans l'arbre avant de poursuivre. Le test de finition reproduit une sortie avant et pendant la préparation.

Les régressions du Static Shield vérifient désormais sa sortie immédiate, y compris en réseau. Les contrôles du tactile et de l'audio observent les événements réels et leurs horloges respectives. Le test du scanner utilise une zone d'épaule accessible sur le nouveau châssis et conserve ses vérifications de portée, de collision et de vitesse des articulations. Les vérifications de répétition des finitions attendent la construction différée du décor.

Les changements arrivés sur `main` pendant la préparation sont intégrés : cinq arènes compactes, le râtelier et les nouveaux modules de la forge, le parcours de préparation du duel solo et les corrections réseau. L'ensemble réuni réussit les 141 suites du projet, les deux variantes de châssis, l'import et l'export du pack. Tous les accessoires sont conservés lors d'un remplacement de châssis ; le cadrage d'inspection suit également sa focale.

Les tests de sélection distinguent l'ouverture d'une fiche, la fixation animée et la sauvegarde du build. Le test du parcours solo vérifie le passage par la forge avant le démarrage du combat. Le contrôle des finitions conserve sa comparaison stricte des acteurs, des collisions et de la caméra après avoir placé celle-ci dans sa pose de repos.

Les résultats locaux détaillés et les empreintes des fichiers vérifiés sont conservés dans `exports/publication-mechas-20261002/`. Le workflow `Android test APK` assure ensuite la compilation et la signature de la version Android ainsi que l'export Windows. Les essais locaux ont été réalisés sur PC.
