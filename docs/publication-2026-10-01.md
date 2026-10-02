# Travaux du 1 octobre 2026

Les changements du jeu sont publiés dans [4bf2ff8](https://github.com/aKoMoses/PROTOTYPE-V0.1/commit/4bf2ff8d51d870d73d938f677cb207d8b43bb805), vérifié sur la branche distante `main`.

- Garage avec brouillons, builds nommés, vidéos de combat et sauvegarde après cinq secondes de travail du bras.
- Pyroboots et Bio Injector modélisés sur le squelette réel du robot, dans le Garage et en combat. Leur sélection cadre leur accessoire et déclenche trois secondes de travail après l'approche du bras.
- Réglages, salons et pré-combat avec les interfaces industrielles validées.
- Dix-sept sons validés pour Counter, Panier roquettes, Projector et Permutation. Les propositions audio restent dans `audio-lab/`, hors des exports du jeu ; la proposition Éclipse attend sa validation.
- Refactorisation du Player, variante d'arène à pièges et zones de Survie conservées avec leurs dépendances locales.

Les 112 scripts de test du projet ont passé leurs contrôles locaux. Les fixtures ont été adaptées au fonctionnement des brouillons, à la révélation du Javelin, à sa charge et à l'arrivée physique des projectiles. Le chargement de l'éditeur Godot est passé sans erreur de script. Les vidéos ont également été vérifiées dans un pack exporté.

Les captures natives des nouveaux accessoires et de leur intervention sont disponibles dans [`captures/robot-modules/`](../captures/robot-modules/). Le détail des modèles et de la séquence se trouve dans [robot-module-visuals.md](robot-module-visuals.md), celui des builds dans [garage-builds.md](garage-builds.md).
