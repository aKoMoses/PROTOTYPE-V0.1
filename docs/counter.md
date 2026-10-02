# COUNTER et SURCHARGE

COUNTER est disponible dans l'emplacement défensif habituel, avec son raccourci PC, son bouton tactile et la personnalisation de HUD existante. Le module bloque les autres actions pendant sa préparation, sa garde et sa récupération. Déplacement et visée restent indépendants. Une interception termine immédiatement la protection ; elle ne donne aucune invulnérabilité contre l'attaque suivante.

## Configuration

Les valeurs sont regroupées dans `CombatData.MODULE_DEFINITIONS.counter` :

| Paramètre | Valeur |
|---|---:|
| Préparation sans protection | 0,08 s |
| Garde à 360° | 1,1 s |
| Vitesse pendant préparation et garde | 50 % |
| Récupération réussie / échouée | 0,12 / 0,2 s |
| Recharge, dès l'activation acceptée | 8 s |
| Disponibilité de SURCHARGE | 3 s |
| Rayon de l'explosion | 2,2 m |
| Dégâts secondaires fixes | 80 PV |

Le rayon correspond à deux diamètres de la capsule du joueur (rayon 0,55 m). La [passe de renforcement du 2 octobre](catalogue-renforcement.md) porte la récompense de 10 à 80 PV ; sa configuration reste indépendante des dégâts de l'arme équipée. L'explosion secondaire conserve sa résolution unique, les contrôles d'obstacles et d'équipes, et l'absence de soin Omnivamp.

Le 2 octobre 2026, la garde passe de 0,8 à 1,1 s (+300 ms), après un premier ajustement à 0,95 s. Le contrôle d'interception tardive utilise une attaque à 1,05 s ; l'expiration et le cercle suivent la durée configurée.

## Intégration

- `scripts/counter.gd` : composant par acteur, phases, interception avant dégâts, charge, résolution unique par attaque et explosion avec contrôle des obstacles et des équipes. Les dégâts secondaires passent directement par `take_damage` avec la source `surcharge`, sans effets d'arme ni soin à l'attaquant.
- `scripts/combat_data.gd`, `loadout_state.gd`, `equipment_icons.gd` et `art/icons/counter.svg` : configuration, admissibilité explicite des attaques, choix d'équipement et description.
- `scripts/player.gd`, `mekatana_attack.gd`, `fulguro_punch.gd`, `target_dummy.gd` : verrouillage d'action et raccordement aux impacts réels. Blaster, Shotgun, Longshot et chaque coup de Mekatana utilisent un payload commun à toute l'attaque émise. Fulguro contré ne projette pas. Pelto, burn et les dégâts secondaires contournent la garde. Un contrôle incompatible l'interrompt.
- `scripts/duel_bot_equipment.gd`, `training_bot.gd`, `bot_build_presets.gd` : sélection de COUNTER, menaces observées avec perception retardée et erreur, suspension des prochains tirs face à une garde visible et priorité à l'exploitation de SURCHARGE.
- `scripts/network_player.gd`, `network_match.gd` : autorité hôte, réplication des phases et de la charge, événement visuel d'explosion. Une réplique ne peut pas attribuer une réussite ou appliquer l'explosion.
- `scripts/game_flow.gd`, `player_visual_rig.gd`, `player_aim_modifier.gd`, `enemy_droid_visual.gd`, `enemy_droid_pose.gd`, `game_sfx.gd` : état du HUD, posture de garde progressive et son métallique.
- `scripts/counter_visual.gd` : garde cyan segmentée à 360°, anneau de durée sur fond sombre, onde de blocage et éclat de particules, énergie dorée pulsée autour de l'arme et explosion de Surcharge. Les matériaux non éclairés restent lisibles sans bloom ; les éclats ponctuels utilisent 16 ou 20 particules CPU et sont libérés après 0,4 s.

Une charge est consommée à l'émission, conservée sur l'attaque en vol et résolue une seule fois au premier impact ennemi accepté. Tous les plombs d'une décharge partagent cet état, mais leurs dégâts principaux restent distincts. Le défenseur retient l'identifiant de la décharge interceptée pour neutraliser ses autres plombs sans protéger les autres cibles. Mort, réinitialisation et changement d'équipement effacent les états.

## Lisibilité du Counter (1er octobre 2026)

La posture se met en place pendant les 0,08 s de préparation, puis revient progressivement au repos pendant la récupération. Les panneaux et le compte à rebours circulaire apparaissent uniquement pendant la protection effective. Un blocage les retire immédiatement et affiche brièvement « BLOQUÉ ! / TIR RENFORCÉ », avant « SURCHARGE / TIR RENFORCÉ » avec sa durée restante. Le halo doré suit l'arme et disparaît à l'émission ou à l'expiration. Les mêmes repères sont appliqués aux répliques réseau, sans rejouer l'éclat sur des snapshots identiques.

Les suites Counter (53 contrôles), armes et réplication (52) et `tools/test_counter_visual.gd` (16) passent. Les captures `guard`, `guard-gameplay`, `intercept`, `surcharge` et `explosion` sont vérifiées en OpenGL dans la scène réelle ; la capture de garde utilise aussi la caméra normale de combat. Le coût sur appareil Android reste à mesurer.

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
