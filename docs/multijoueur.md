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

Un salon dont le protocole ou les règles de combat diffèrent affiche
**Version différente du jeu** et ne peut pas être rejoint. Installez la même
version sur les deux appareils, que ce soit PC–PC ou PC–Android.

Les boutons évitent les doubles créations et doubles entrées. Après une
connexion bloquée, **RÉESSAYER** permet de repartir. Un lancement attend la
confirmation des deux joueurs ; après 25 secondes sans confirmation, il
revient au salon ou propose de le rejoindre à nouveau.

Les deux joueurs utilisent le contrôleur du robot joueur et leur équipement de
la forge. Les tirs du Blaster et du Shotgun, la charge, le rechargement,
le Javelin et sa téléportation, les protections, le dash et les effets sont
reproduits chez l'autre joueur. Le HUD habituel conserve les PV, les munitions,
les modules et leurs délais. Les trois sorts restent visibles pendant le
combat, même si la disposition personnelle les masquait ; cette disposition
est restaurée en quittant. Le passif et les PV suivent le combattant réseau.
La charge du Fulguro Punch et la traction du Pelto Smash sont également
reproduites et résolues par l'hôte.

À la fin du match, **REVANCHE** attend l'accord des deux joueurs, puis remet
à zéro le score, les PV et les délais. **RETOUR AU SALON** ramène les deux
joueurs dans le même salon et permet de relancer le duel. **QUITTER** quitte
le salon ; le match en ligne ne se met pas en pause avec Échap.

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

## Vérification du 2 octobre 2026

`tools/test_network_combat.gd` vérifie les collisions réelles, les protections,
les effets, le Javelin, le dash, les munitions, les doublons et l'autorité des PV
et de Baroud. `tools/test_network_game.tscn` lance un scénario à deux clients,
avec les arguments `host test-id=<identifiant>` et `guest test-id=<identifiant>`
dans deux processus. Ajouter `--network-local-test` aux arguments utilisateur
permet de refaire le même scénario sur le réseau local.

Deux instances Godot sur ce PC ont réussi le scénario via GD-Sync : attaque de
chaque joueur, stase, mur magnétique, Javelin, dash, PV confirmés, match complet,
égalité, revanche acceptée des deux côtés, Fulguro Punch, Pelto Smash et retour
au même salon. Le scénario inclut des dégâts létaux injectés par l'hôte pour
vérifier toutes les transitions de manches et la fin des deux matchs.
Les résultats sont `NETWORK GAME TEST: PASS [host]` (56 contrôles) et
`NETWORK GAME TEST: PASS [guest]` (47 contrôles).

`tools/test_network_reliability.gd` vérifie les appuis répétés, les versions
incompatibles, les relances de chargement, les délais expirés, les anciennes
demandes et le nettoyage. Les tests de combat, Longshot et Mekatana passent.
`tools/test_network_hud.gd` vérifie les trois sorts avec une disposition qui
les masque au départ, les changements de taille, la revanche et la restauration
des panneaux. Les captures PC et aperçu tactile sont dans
`captures/multi-spell-bar-pc.png` et `captures/multi-spell-bar-touch.png`.

Ces vérifications utilisent deux processus locaux connectés au service en
ligne. Un essai PC–PC depuis deux logements et un essai PC–Android sur un vrai
téléphone restent à faire, notamment pour les contrôles tactiles et la latence.
L'aperçu tactile sur PC ne remplace pas cet essai Android. Les modifications
de cette passe sont locales tant qu'une nouvelle version n'est pas publiée.
