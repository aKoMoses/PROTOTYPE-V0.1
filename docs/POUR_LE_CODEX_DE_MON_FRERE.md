# Instructions pour le Codex de mon frère

Objectif : lancer une partie en ligne à deux sur le prototype Godot, depuis deux
logements. Dépôt : `https://github.com/aKoMoses/PROTOTYPE-V0.1`, branche `main`.

## Chemin le plus simple : jouer avec un export du jeu

Le code est sur `main`, mais aucun export multijoueur utilisable sur Internet
n'est encore publié : les clés GD-Sync et le test entre deux logements restent
à faire. Les anciennes releases Android ne contiennent pas ce mode.

1. Quand un nouvel export multijoueur sera fourni, récupérer **la même version**
   que celle utilisée par l'hôte : installer l'APK Android ou décompresser
   l'export Windows et lancer l'exécutable. Le joueur n'a pas besoin de compte
   GD-Sync, de serveur, de VPN ou d'ouvrir un port sur sa box.
2. Dans le jeu, ouvrir **MULTIJOUEUR**. Attendre la connexion ; la liste des
   salons s'actualise automatiquement. Cliquer sur **REJOINDRE** sur le salon
   créé par l'hôte.
3. Attendre que l'hôte clique sur **LANCER LE MATCH**. Vérifier que les deux
   joueurs entrent dans la même manche et que les PV et le score évoluent.

Si la liste indique une configuration GD-Sync manquante, l'export a été produit
sans les clés du projet. Demander un **nouvel export configuré** à l'hôte ; ne
pas chercher à créer un autre projet GD-Sync.

## Si tu dois lancer le projet depuis Godot

1. Mettre à jour le dépôt sur `main`, en préservant les éventuelles modifications
   locales. Ouvrir le dossier contenant `project.godot` dans Godot 4.7.2.
2. Le fichier `addons/GD-Sync/keys.cfg` est volontairement absent du dépôt. Le
   propriétaire du projet doit fournir la configuration de **la même clé API**
   par un canal privé, ou fournir un export déjà configuré. Ne jamais
   ajouter la clé privée à Git, au chat ou à une issue GitHub.
3. Avec la configuration présente, lancer le jeu et suivre le parcours ci-dessus.

## Nouvelles versions

Les clés GD-Sync sont créées **une fois pour ce jeu** et réutilisées dans les
exports suivants. Il n'y a pas de nouveau compte ou de nouveau salon permanent
à créer à chaque publication. Les salons sont recréés quand vous lancez une
session. Pour jouer ensemble après une mise à jour, utilisez tous les deux **la
même version** du jeu. Un ancien client peut voir le salon d'un nouveau client
avec la même clé, mais leurs règles réseau peuvent ne plus correspondre.

Pour les APK Android produits automatiquement par GitHub, le propriétaire du
dépôt doit enregistrer une fois les secrets Actions `GDSYNC_PUBLIC_KEY` et
`GDSYNC_PRIVATE_KEY`. Le workflow refuse de publier un nouvel APK si ces clés
manquent. Un export Windows préparé dans Godot utilise les clés configurées
localement dans le projet.

État de validation : création et découverte de salon, lancement et échange de
dégâts/score vérifiés avec deux instances locales. Le trajet Internet entre les
deux logements doit encore être validé avec les clés du projet. Voir aussi
[`multijoueur.md`](multijoueur.md).
