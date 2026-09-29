# Instructions pour le Codex de mon frère

Objectif : lancer une partie en ligne à deux sur le prototype Godot, depuis deux
logements. Dépôt : `https://github.com/aKoMoses/PROTOTYPE-V0.1`, branche `main`.

## Chemin le plus simple : jouer avec un export du jeu

Les clés du projet sont configurées chez Romain et dans GitHub Actions. Les
anciennes releases Android ne contiennent pas ce mode. Choisir la dernière
release de test contenant **l'APK Android et le ZIP Windows**, sur la
[page des releases](https://github.com/aKoMoses/PROTOTYPE-V0.1/releases).

1. Récupérer **la même release** que celle utilisée par l'hôte. Sur Android,
   installer `prototype0-android.apk`. Sur PC, décompresser
   `prototype0-windows.zip` et garder le `.exe` et le `.pck` dans le même
   dossier, puis lancer le `.exe`. Le joueur n'a pas besoin de compte GD-Sync,
   de serveur, de VPN ou d'ouvrir un port sur sa box.
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
2. Le fichier `addons/GD-Sync/keys.cfg` est volontairement absent du dépôt.
   Demander à Romain la configuration de **la même clé API** par un canal privé,
   ou utiliser un export déjà configuré. Avec les clés, les saisir dans
   **Projet > Outils > GD-Sync**. Ne jamais ajouter la clé privée à Git, au chat
   ou à une issue GitHub. Cette étape n'est pas nécessaire si le PC utilise le
   ZIP Windows publié.
3. Avec la configuration présente, lancer le jeu et suivre le parcours ci-dessus.

## Nouvelles versions

Les clés GD-Sync sont créées **une fois pour ce jeu** et réutilisées dans les
exports suivants. Il n'y a pas de nouveau compte ou de nouveau salon permanent
à créer à chaque publication. Les salons sont recréés quand vous lancez une
session. Pour jouer ensemble après une mise à jour, utilisez tous les deux **la
même version** du jeu. Un ancien client peut voir le salon d'un nouveau client
avec la même clé, mais leurs règles réseau peuvent ne plus correspondre.

Pour les exports Android et Windows produits automatiquement par GitHub, les secrets Actions
`GDSYNC_PUBLIC_KEY` et `GDSYNC_PRIVATE_KEY` sont déjà enregistrés. Le workflow
refuse de publier une nouvelle release s'ils manquent. Un export préparé
manuellement dans Godot utilise les clés configurées localement dans le projet.

État de validation : deux instances Godot sur le PC de Romain se sont connectées
aux serveurs GD-Sync et ont vérifié le salon, le lancement, les dégâts et le
score. Le trajet entre les deux logements reste à essayer sur vos appareils.
Voir aussi
[`multijoueur.md`](multijoueur.md).
