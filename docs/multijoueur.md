# Jouer à deux depuis deux logements

Le menu **MULTIJOUEUR** permet de créer un salon visible dans la liste, de le
rejoindre et de lancer un match à deux. La liste se met à jour automatiquement.
Les manches reprennent le format « premier à 3 ». Le trafic passe par le service
hébergé GD-Sync : aucun serveur à lancer sur le PC et aucun port de box à ouvrir.

## Configuration unique du projet

La clé API `PROTOTYPE-V0.1` a été créée sur le compte GD-Sync de Romain. Ses
deux valeurs sont installées dans `addons/GD-Sync/keys.cfg` sur son PC et dans
les secrets GitHub Actions du dépôt. Elles ne sont pas dans Git. Il n'y a rien
à recréer à chaque nouvelle version : exporter le jeu avec cette configuration
et donner **la même version** aux deux joueurs.

Les clés sont à créer une fois pour ce jeu. Les exports suivants les réutilisent
tant que la configuration locale est conservée. Le fichier de clés n'étant pas
dans Git, un autre poste qui lance le projet source doit recevoir la même
configuration par un canal privé ; un joueur qui utilise un export du jeu n'a
pas à la saisir. Voir [les instructions pour le Codex de l'autre joueur](POUR_LE_CODEX_DE_MON_FRERE.md).

Les exports Android et Windows publiés automatiquement utilisent les secrets GitHub Actions
`GDSYNC_PUBLIC_KEY` et `GDSYNC_PRIVATE_KEY`, déjà configurés. Le workflow refuse
la publication s'ils manquent. La release propose un APK Android et un ZIP
Windows contenant le `.exe` et son `.pck`. Pour une copie du projet source sur un autre
PC, Romain doit transmettre la même configuration par un canal privé ; ne pas
mettre la clé privée dans un commit ou un message public.

## Dans le jeu

1. Le premier joueur ouvre **MULTIJOUEUR** et choisit **CRÉER UN SALON**.
2. L'autre ouvre **MULTIJOUEUR** : le salon apparaît dans la liste. Il clique sur
   **REJOINDRE**.
3. Le créateur clique sur **LANCER LE MATCH** lorsque le salon indique 2/2.

Les deux joueurs utilisent le contrôleur du robot joueur et leur équipement de
la forge. Les tirs du Blaster et du Shotgun, la charge, le rechargement, le Javelin,
le Javelin et sa téléportation, les protections, le dash et les effets sont
reproduits chez l'autre joueur. Le HUD habituel conserve les PV, les munitions,
les modules et leurs délais. **QUITTER** ramène au salon ; le match en ligne ne
se met pas en pause avec Échap.

## Résolution du combat

L'hôte simule les deux combattants et leurs projectiles. Il décide des impacts,
des dégâts, des protections, des effets, des soins et des passifs, puis transmet
l'état confirmé et le score. L'autre joueur envoie ses actions ; il ne peut plus
envoyer directement un montant de dégâts, ses PV ou une déclaration de mort.
La charge est calculée à partir du temps observé par l'hôte. Les actions répétées
et les messages d'une ancienne manche ou d'un ancien match sont ignorés.

Une élimination simultanée dans le même pas de simulation produit une égalité
sans point, puis une nouvelle manche. Le mouvement reste immédiat sur l'appareil
du joueur et sa dernière position reçue est utilisée par l'hôte pour les
collisions. Il n'y a pas encore de compensation de latence ni de correction
complète du mouvement : une connexion lente peut donc décaler la perception
d'un impact ou d'une protection.

## Vérification du 29 septembre 2026

`tools/test_network_combat.gd` vérifie les collisions réelles, les protections,
les effets, le Javelin, le dash, les munitions, les doublons et l'autorité des PV
et de Baroud. `tools/test_network_game.tscn` lance un scénario à deux clients,
avec les arguments `host test-id=<identifiant>` et `guest test-id=<identifiant>`
dans deux processus. Ajouter `--network-local-test` aux arguments utilisateur
permet de refaire le même scénario sur le réseau local.

Deux instances Godot sur ce PC ont réussi le scénario via GD-Sync : attaque de
chaque joueur, stase, mur magnétique, Javelin, dash, PV confirmés, résultat, remise
à zéro de la manche suivante, égalité et retour au salon. La capture rendue
`captures/network_multiplayer.png` montre les deux robots et le HUD en ligne.
Les contrôles du duel solo, de l'entraînement et des passifs passent également.
Un essai sur les deux appareils depuis les deux logements reste à faire, ainsi
que la vérification tactile sur Android.
