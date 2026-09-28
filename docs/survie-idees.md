# Mode Survie — idées à conserver

Date : 28 septembre 2026.

Retour du joueur : le mode est très apprécié, mais jugé trop facile.
Ce document conserve les propositions de conception. Leur enregistrement ne vaut
pas validation d'implémentation. Les chiffres sont des valeurs de départ à tester.

## Quatre pistes pour la difficulté

### 1. Augmenter progressivement la présence ennemie

Tester 3 ennemis au début, 6 au milieu et 8 à 10 en fin de partie. Faire arriver les
renforts en deux groupes légèrement décalés pour maintenir la nécessité de bouger.
Préserver des ennemis rapides à éliminer et des annonces d'arrivée lisibles.

### 2. Composer des vagues complémentaires

Associer des rôles qui mettent le placement à l'épreuve : un chargeur force une
esquive pendant que deux tireurs couvrent une sortie et que des poursuivants arrivent
d'un autre côté. Conserver les annonces au sol pour permettre une réponse du joueur.

### 3. Rendre les dégâts subis plus durables

Tester 100 PV rendus toutes les trois vagues à la place des 150 PV après chaque vague.
Ajouter quelques réparations limitées à récupérer dans l'arène pour donner davantage
de valeur au placement, aux défenses et aux soins.

### 4. Introduire des élites et des paliers

Proposer un élite toutes les trois vagues avec une particularité visible : double
charge, tir en éventail ou bouclier frontal. À mi-vie, le boss final accélérerait
l'enchaînement charge/salve tout en conservant une récupération permettant de riposter.

Priorité proposée : tester d'abord la présence ennemie et la fréquence des soins.

## Quatre propositions supplémentaires, hors hausse de difficulté

### 5. Des synergies entre équipements

Faire interagir deux éléments du build : le Blaster déclenche une petite explosion
sur une cible brûlée par les Pyro Boots ; un Drone traverse le Champ magnétique et
ressort chargé d'électricité. Afficher la synergie sur les choix d'amélioration.
Objectif : créer des combinaisons à découvrir et des styles de partie distincts.

### 6. Une arène qui raconte le combat

Conserver des traces visuelles au fil de la partie : impacts, carcasses de robots,
fumée sur les épaves et éclairage qui évolue entre les vagues. Prévoir une limite
d'effets et préserver la lisibilité des déplacements et des attaques.
Objectif : rendre chaque partie plus vivante sans ajouter de danger.

### 7. Une collection de déblocages cosmétiques

Récompenser des accomplissements simples par des peintures de robot, des couleurs
de projectiles, des bannières ou des variantes visuelles d'équipement. Exemples :
terminer une partie au Shotgun, découvrir plusieurs évolutions, essayer chaque module.
Objectif : donner une raison de revenir et de varier les builds, sans bonus de puissance.

### 8. Un bilan de partie qui met le build en valeur

Présenter le build final avec ses évolutions, la durée, les dégâts par équipement,
les soins et la meilleure vague. Permettre de conserver le build comme favori et
d'enregistrer une carte récapitulative à partager manuellement.
Objectif : comprendre les contributions de chaque équipement et garder une trace
des parties réussies. Le favori sert de référence pour une future partie ; les
équipements restent à acquérir pendant cette partie.

Ces quatre propositions supplémentaires restent à discuter avec le joueur.


## Implémentation approuvée le 28 septembre 2026

Les pistes 1 à 5 et 8 sont intégrées au prototype local. Les valeurs et règles
actuelles sont décrites dans la section Mode Survie du README. Les pistes 6
(traces persistantes dans l'arène) et 7 (cosmétiques) restent des idées à discuter.
Les quatre synergies sont Détonation thermique, Relais électrique, Double détente
et Sillage incandescent. Le bilan inclut le favori de référence et un export PNG.
L'équilibrage doit encore être confronté à une partie humaine complète.
