# Améliorations du confort et de la boucle de jeu

## Accès dans le jeu

- **Duel solo** ouvre les profils Facile, Normal et Difficile. Les réglages de présentation rapide et de confirmations visuelles sont sauvegardés séparément de la difficulté.
- **Garage** propose trois builds conseillés : Prise en main, Assaut et Technique. Ils deviennent des brouillons que le joueur peut tester ou sauvegarder.
- **Sauver et jouer** sauvegarde le build avant de démarrer le duel. **Passer** termine l’installation en cours ; le mode rapide le fait automatiquement.
- **Entraînement → Menu → Défis guidés** propose Parade, Marque et repositionnement, Écrasement mural. La réussite utilise une interception réelle, une téléportation après marque au Javelin ou les dégâts d’un écrasement Fulguro contre le mur existant. Le build est temporaire ; quitter restaure l’équipement, les règles et la position. Réinitialiser recommence le défi. Un mannequin temporaire permet de pratiquer même après avoir retiré tous les mannequins fixes.
- **Survie** propose des compositions de vagues différentes et une indication tactique à leur arrivée. Une relance des cartes est disponible pour toute la partie, avec une nouvelle proposition et sans seconde attribution de la même récompense.

## Duel et retours visuels

L’adversaire conserve son build pendant tout le match. **Revanche** garde cet adversaire ; **Nouvel adversaire** tire une nouvelle famille de build. Le précombat conserve un compte à rebours de trois secondes après **Passer la présentation**.

Les impacts sur une cible visible peuvent afficher un repère bref. Les parades, repositionnements et écrasements muraux ont une confirmation dédiée. La présentation ne ralentit pas la simulation et les confirmations peuvent être désactivées.

Le bilan indique les dégâts réellement appliqués, le principal danger de la dernière manche et les réparations de l’adversaire. Le résultat final ajoute les dégâts cumulés du match.

Les bannières sont cosmétiques : Duelliste après un match gagné, Technicien après les trois défis, Survivant après une survie terminée, Maître d’arsenal après quatre survies terminées avec les quatre armes différentes. Le titre choisi apparaît au début du duel. Les nouveaux réglages et la maîtrise sont dans `user://prototype0_experience.cfg`.

## Vérification

Godot 4.7.2 : import du projet, test d’intégration `tools/test_review_fun.gd`, tests existants du match, des builds bots, du Garage, de l’entraînement, de la survie, des récompenses, des évolutions et de la pause. Les contrôles tactiles et le dispatch GUI ont aussi été vérifiés ; le dispatch GUI utilise une fenêtre rendue.

Le test d’intégration utilise de vraies attaques pour les trois défis, vérifie la sauvegarde avant le démarrage, la revanche, la relance limitée et la restauration du laboratoire. Les captures de `captures/review-fun/` couvrent les choix solo, le Garage, l’installation, le résultat, les défis et la survie.

Pour lancer les tests Windows sans modifier les sauvegardes personnelles, isoler APPDATA avant de démarrer Godot :

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/review-fun-user'
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path (Get-Location).Path --script res://tools/test_review_fun.gd
```

Retirer `--headless` et ajouter `-- --capture-review` pour les captures. Sur le poste de cette vérification, le moteur disponible était celui de `.godot/pass-runtime/`, utilisé par chemin absolu.

Les cartes et les modifications d’équilibrage menées dans les autres travaux sont conservées. Cette livraison ne modifie pas leur géométrie ou les valeurs des armes. Validation automatisée et visuelle sur PC ; aucun nouveau paquet Android ou test sur téléphone physique n’est inclus.
