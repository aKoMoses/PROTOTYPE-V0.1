# Jouer à deux depuis deux logements

Le menu **MULTIJOUEUR** permet de créer un salon visible dans la liste, de le
rejoindre et de lancer un match à deux. La liste se met à jour automatiquement.
Les manches reprennent le format « premier à 3 ». Le trafic passe par le service
hébergé GD-Sync : aucun serveur à lancer sur le PC et aucun port de box à ouvrir.

## Configuration unique du projet

1. Créer un projet sur [GD-Sync](https://www.gd-sync.com/) et récupérer ses clés
   API publique et privée.
2. Ouvrir ce projet dans Godot, puis **Projet > Outils > GD-Sync** et saisir les
   deux clés. Le plugin les conserve dans `addons/GD-Sync/keys.cfg`, ignoré par Git.
3. Exporter le jeu avec les clés configurées et donner la même version à l'autre
   joueur. Une fois ce réglage fait, le jeu se connecte depuis le menu multijoueur.

Les clés sont à créer une fois pour ce jeu. Les exports suivants les réutilisent
tant que la configuration locale est conservée. Le fichier de clés n'étant pas
dans Git, un autre poste qui lance le projet source doit recevoir la même
configuration par un canal privé ; un joueur qui utilise l'export Windows n'a
pas à la saisir. Voir [les instructions pour le Codex de l'autre joueur](POUR_LE_CODEX_DE_MON_FRERE.md).

## Dans le jeu

1. Le premier joueur ouvre **MULTIJOUEUR** et choisit **CRÉER UN SALON**.
2. L'autre ouvre **MULTIJOUEUR** : le salon apparaît dans la liste. Il clique sur
   **REJOINDRE**.
3. Le créateur clique sur **LANCER LE MATCH** lorsque le salon indique 2/2.

Cette première version synchronise les positions, PV, dégâts, effets et scores.
L'adversaire utilise provisoirement l'apparence du robot d'arène existant ; ses
animations d'attaque exactes ne sont pas encore reproduites à distance. Les tests
avec deux instances locales passent pour le salon, le lancement et la résolution
d'une manche. Une connexion réelle entre les deux logements reste à vérifier une
fois les clés API créées et les deux exemplaires du jeu disponibles.
