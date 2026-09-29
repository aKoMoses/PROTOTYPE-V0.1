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

Cette première version synchronise les positions, PV, dégâts, effets et scores.
L'adversaire utilise provisoirement l'apparence du robot d'arène existant ; ses
animations d'attaque exactes ne sont pas encore reproduites à distance. Deux
instances Godot sur le PC de Romain ont réussi, via les serveurs GD-Sync, la
création et découverte du salon, le lancement, les dégâts et le score. Un essai
sur les deux appareils, depuis les deux logements, reste à faire.
