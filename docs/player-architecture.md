# Organisation du joueur

Le script `scripts/player.gd` orchestre l'initialisation, l'arrêt et la boucle
physique. Il conserve les signatures des méthodes utilisées par les scènes,
le HUD, l'entraînement, les captures et `network_player.gd`.

La logique est répartie dans `scripts/player/components/` :

| Fichier | Responsabilité |
| --- | --- |
| `player_state.gd` | Champs partagés, paramètres exportés, signaux et constantes du joueur. |
| `controls.gd` | Déplacement, visée, commandes PC/tactiles, poses de visée et réservation des actions. |
| `combat.gd` | Santé, soins, effets subis, passifs, mort et visibilité dans les buissons. |
| `loadout.gd` | Chargement des définitions, équipement, configuration de la survie et de l'entraînement. |
| `presentation.gd` | Construction du robot, animation, fixation des armes, mouvement visuel et indications au-dessus du joueur. |
| `blaster.gd` | Charge, tir, projectile, recul et annulation du Blaster. |
| `mekatana.gd` | Combo à trois coups, mouvement de dash, dégâts et annulation de Mekatana. |
| `longshot.gd` | Préparation, cycle de cinq tirs, projectile, dégâts et présentation de LONGSHOT. |
| `shotgun.gd` | Salve, dégâts selon la distance, chargeur et rechargement du shotgun. |
| `legacy_axe.gd` | Ancienne hache, combo, formes de frappe, traînée et effets associés. |
| `fulguro.gd` | Charge et frappe de Fulguro, projection et collision contre un mur. |
| `pelto.gd` | Préparation de Pelto, vagues, traction et restauration de l'arme après l'animation. |
| `projectile_modules.gd` | Rocket Basket et Javelin : lancement, charge, impact, marque et téléportation. |
| `utility_modules.gd` | Cooldowns des modules, champ magnétique, stase, dash, injecteur et commandes défensives différées. |
| `defensive_modules.gd` | Counter et Projector : garde, surcharge, cast et onde automatique. |
| `mobility_modules.gd` | Eclipse, Permutation et accès aux charges de Pyro Boots. |
| `effects.gd` | Ciblage et collisions communs, effets partagés et effets secondaires des évolutions de survie. |

## Contrats à préserver

- Les composants sont des enfants du joueur, ajoutés dès sa construction. Leur
  durée de vie suit celle du joueur, y compris les callbacks de timers.
- Ils ne possèdent pas de boucle physique autonome. L'ordre des mises à jour
  reste dans `player.gd`, notamment les verrous de cast et la consommation des
  commandes avant la fin d'une action.
- Les champs restent hérités de `player_state.gd` pour préserver les accès
  existants par `get`, `set`, les paramètres des scènes et le joueur réseau.
- Les appels entre responsabilités passent par les méthodes du joueur. Les
  surcharges de `network_player.gd` continuent donc d'intercepter les actions.
- Les tweens et les timers utilisent le joueur ou ses visuels comme auparavant.
  Les jetons d'annulation, dégâts, durées et réglages de combat sont conservés.
- Les composants préchargent uniquement la base d'état. Celle-ci ne précharge
  aucun composant et ne contient aucune méthode de combat, ce qui évite une
  dépendance circulaire avec le contrôleur.

Pour ajouter une arme, placer son comportement dans un composant dédié et
ajouter au contrôleur les seules entrées nécessaires aux appelants existants.
Mekatana et LONGSHOT sont intégrés dans leurs composants après récupération
des développements distants. Les entrées utilisées par les bots et le réseau
restent disponibles sur le contrôleur.

Le 30 septembre 2026, après intégration des armes distantes, `player.gd` passe
de 5 840 à 1 660 lignes. Les quatorze composants de
comportement comptent chacun entre 113 et 726 lignes ; la base d'état partagé
en compte 362. Les 358 signatures, y compris l'API statique tactile, sont conservées.

## Vérification

Utiliser Godot 4.7.2 avec le dossier réel contenant `project.godot`, puis les tests
de Blaster, shotgun, rechargement/contact, modules, Fulguro, Pelto, passifs,
contrôles tactiles, animation du joueur, visibilité, réseau et survie. Vérifier
les erreurs de script dans les journaux en plus du résultat `PASS` : un test
peut terminer avec le code zéro malgré une erreur Godot indépendante de ses
assertions.

Le test `tools/test_player_components.gd` couvre la destruction avant entrée
en scène et pendant les préparations des armes et modules, notamment Mekatana
et LONGSHOT, puis la capacité d'un nouveau joueur à attaquer avec un cycle neuf.
Les notifications de focus consultent les composants uniquement pour les deux
événements concernés, afin d'éviter un accès après leur destruction.

L'intégration conserve le garage 3D, les dangers du duel et le passage de la
casse à l'usine en survie. La navigation des bots utilise le centre de chaque
zone, y compris pour les grilles partagées, les limites et les objectifs de
recherche. `tools/test_bot_navigation.gd` vérifie aussi un détour avec couvert
et des limites dans une arène décalée.

Les tests de gameplay, bots et réseau de Mekatana et LONGSHOT passent. Le test
de présentation de LONGSHOT doit utiliser un moteur de rendu, sans `--headless`.
Les tests des anciennes armes, modules, passifs, contrôles, visibilité, pause,
rig du joueur, durée de vie, forge, dangers et survie vérifient la fusion.

Après le pull jusqu'à `417bb37`, les 23 tests fonctionnels relancés dans le
projet réel passent sans erreur de script. Neuf exécutions affichent encore
un diagnostic de ressources retenues à la fermeture du moteur (une ou deux
ressources), déjà observé avant le découpage. L'import éditeur charge les
scripts sans erreur ; le rendu de LONGSHOT est également vérifié.

Les modifications locales restent dans le dossier de travail, sans commit de
ce découpage. La sauvegarde Git `codex-player-components-before-pull-01a0f403`
conserve l'état précédant le pull ; ne pas la réappliquer automatiquement sur
le nouveau contrôleur, car ses changements ont déjà été fusionnés.

Le 1er octobre 2026, la synchronisation jusqu'à `6f916d0` conserve ce découpage
et reporte les nouveaux modules, passifs et réglages de combat dans les
composants. Les signatures du contrôleur suivent les nouveaux arguments des
projectiles et du Javelin ; les corrections de position dans l'usine en survie
restent conservées. La sauvegarde `codex-sync-main-before-pull-01a0f871` contient
l'état local complet précédant cette synchronisation et reste disponible.

Les clips locaux du garage sont conservés. Un équipement nouvellement récupéré
sans clip masque la miniature au lieu d'afficher la démonstration précédente.

L'import éditeur final charge les scripts sans erreur et 45 tests fonctionnels
passent, couvrant les nouveaux modules, les armes, les passifs, les contrôles,
le réseau, la survie, les zones décalées et le garage. Le Javelin standard suit
la nouvelle téléportation ; les aspects Harpon et Balise gardent leur rappel
spécifique. Les réglages utilisateur sauvegardés avant les tests sont restaurés.
