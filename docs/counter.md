# COUNTER et SURCHARGE

COUNTER est disponible dans l'emplacement défensif habituel, avec son raccourci PC, son bouton tactile et la personnalisation de HUD existante. Le module bloque les autres actions pendant sa préparation, sa garde et sa récupération. Déplacement et visée restent indépendants. Une interception termine immédiatement la protection ; elle ne donne aucune invulnérabilité contre l'attaque suivante.

## Configuration

Les valeurs sont regroupées dans `CombatData.MODULE_DEFINITIONS.counter` :

| Paramètre | Valeur |
|---|---:|
| Préparation sans protection | 0,08 s |
| Garde à 360° | 0,8 s |
| Vitesse pendant préparation et garde | 50 % |
| Récupération réussie / échouée | 0,12 / 0,2 s |
| Recharge, dès l'activation acceptée | 8 s |
| Disponibilité de SURCHARGE | 3 s |
| Rayon de l'explosion | 2,2 m |
| Dégâts secondaires fixes | 10 PV |

Le rayon correspond à deux diamètres de la capsule du joueur (rayon 0,55 m). Les 10 PV sont initialisés à 50 % du blaster normal de 20 PV ; leur configuration reste indépendante des dégâts de l'arme équipée.

## Intégration

- `scripts/counter.gd` : composant par acteur, phases, interception avant dégâts, charge, résolution unique par attaque et explosion avec contrôle des obstacles et des équipes. Les dégâts secondaires passent directement par `take_damage` avec la source `surcharge`, sans effets d'arme ni soin à l'attaquant.
- `scripts/combat_data.gd`, `loadout_state.gd`, `equipment_icons.gd` et `art/icons/counter.svg` : configuration, admissibilité explicite des attaques, choix d'équipement et description.
- `scripts/player.gd`, `mekatana_attack.gd`, `fulguro_punch.gd`, `target_dummy.gd` : verrouillage d'action et raccordement aux impacts réels. Blaster, Shotgun, Longshot et chaque coup de Mekatana utilisent un payload commun à toute l'attaque émise. Fulguro contré ne projette pas. Pelto, burn et les dégâts secondaires contournent la garde. Un contrôle incompatible l'interrompt.
- `scripts/duel_bot_equipment.gd`, `training_bot.gd`, `bot_build_presets.gd` : sélection de COUNTER, menaces observées avec perception retardée et erreur, suspension des prochains tirs face à une garde visible et priorité à l'exploitation de SURCHARGE.
- `scripts/network_player.gd`, `network_match.gd` : autorité hôte, réplication des phases et de la charge, événement visuel d'explosion. Une réplique ne peut pas attribuer une réussite ou appliquer l'explosion.
- `scripts/game_flow.gd`, `player_visual_rig.gd`, `player_aim_modifier.gd`, `enemy_droid_visual.gd`, `enemy_droid_pose.gd`, `game_sfx.gd` : état du HUD, posture de garde, énergie sur l'arme, contour et flash courts, son métallique. Aucun système de particules ou éclairage supplémentaire n'est nécessaire.

Une charge est consommée à l'émission, conservée sur l'attaque en vol et résolue une seule fois au premier impact ennemi accepté. Tous les plombs d'une décharge partagent cet état, mais leurs dégâts principaux restent distincts. Le défenseur retient l'identifiant de la décharge interceptée pour neutraliser ses autres plombs sans protéger les autres cibles. Mort, réinitialisation et changement d'équipement effacent les états.

## Vérifications exécutées

Exécution avec Godot 4.7.2, dans la scène réelle du projet :

- `tools/test_counter.gd` : 53 vérifications, réussies. Phases et recharge, dégâts pendant préparation/garde/expiration, décharge entière, attaques suivantes, burn et Pelto, Fulguro sans projection, mêlée, attribution/expiration/consommation, attaque contrée, unicité, obstacles, commandes, bots, interruption et mort.
- `tools/test_counter_weapons.gd` : 52 vérifications, réussies. Projectiles et frappes réellement émis par les quatre armes, tirs ratés, blaster chargé, Longshot amélioré, collision contre un mur, cleave sur deux ennemis avec une seule explosion, trois doigts indépendants, snapshots hôte/réplique, dégâts secondaires sans counter ni Omnivamp et règles d'équipe.
- Régressions réussies : Mekatana (139 vérifications), Longshot (231), verrouillage de cast, commandes tactiles, Pelto Smash, passifs, combat réseau et transitions de commandes (18). Le test des modules défensifs passe après typage de ses exclusions de rayon ; l'adaptateur du test Longshot accepte le payload de passifs utilisé par les impacts.
- Import de l'éditeur sans erreur de script. `git diff --check` réussi.
- `tools/capture_counter.gd` : captures OpenGL de la garde, de SURCHARGE et de l'explosion, inspectées visuellement dans `captures/counter/`.

Les chemins Godot indiqués dans AGENTS.md sont absents de cette machine. Les commandes ont utilisé l'exécutable absolu de la même version disponible dans `.godot/pass-runtime/`. Certains tests de la scène complète signalent des ressources encore utilisées à la fermeture malgré leurs assertions réussies. L'environnement signale également une erreur de lecture du magasin de certificats.

## Limites des vérifications

La suite générale n'est pas entièrement verte : `test_fulguro_punch` conserve quatre échecs sur Dash/Fulguro et le buffer invalide (son scénario attend un dash de 3 m alors que la configuration courante donne 5 m). `test_bot_build_presets` signale l'absence d'Eclipse et Projector parmi les presets générés. Ces scénarios n'utilisent pas COUNTER et concernent les systèmes également modifiés dans d'autres travaux en cours ; leurs changements ont été préservés.

Restent à effectuer sur matériel : ergonomie et coût réel sur Android, sensations en duel humain, puis essai réseau entre deux machines avec latence/pertes. Le réseau a été vérifié avec des acteurs hôte et réplique dans un même processus ; aucun résultat de transport réseau réel n'est revendiqué. La livraison est locale, sans commit ni publication.
