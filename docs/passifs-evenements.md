# Quatre passifs de combat

Un seul slot passif, sauvegardé dans le format existant. Valeurs de base centralisées dans `scripts/combat_data.gd` ; les descriptions de sélection lisent ces valeurs.

| Passif | Effet et valeurs |
| --- | --- |
| Réacteur auxiliaire | Impact direct hostile d’arme accepté : −0,60 s au cooldown offensif actif. Intervalle interne 0,75 s, une fois par attaque émise, aucun crédit conservé. |
| Traqueur | Deux attaques distinctes sur la même cible, intervalle ≤4 s : SPOTTED 4 s. Changer de cible redémarre à une marque ; aucun cumul ni prolongation pendant sa propre révélation. |
| Alternateur | Impact direct d’un module offensif : prochaine attaque d’arme +30 % de dégâts directs, fenêtre 3 s. Une fois par activation du module. |
| Inertie | Pyro Boots terminé, Bio Injector activé ou arrivée réussie de Permutation/Eclipse : prochaine attaque d’arme applique SLOW 25 % pendant 1,5 s, fenêtre 2,5 s. Les mobilités interrompues, déplacements d’attaque et téléportations Javelin sont exclus. |

Ces valeurs intègrent la [passe de renforcement du 2 octobre](catalogue-renforcement.md).

Alternateur et Inertie sont consommés lors de l’émission réelle, même si l’attaque rate. Une commande refusée ou une préparation annulée conserve le bonus. Chaque projectile conserve les paramètres enregistrés à son émission. Les pellets partagent le contexte d’une salve ; un cleave peut appliquer Inertie à chaque adversaire, une fois par cible.

Les dégâts absorbés par un bouclier comptent ; Counter, invulnérabilité, alliés, décor, roquettes destructibles et dégâts secondaires sont exclus. Le mécanisme ne lance aucune attaque ni aucun cast. Mort réelle, réapparition, changement d’équipement, manche et sortie réinitialisent les déclencheurs. Les états Baroud et Omnivamp restent gérés séparément.

Les bots emploient le même état. Les répliques réseau affichent les snapshots de l’autorité et ne décident aucun dégât ni réduction de cooldown. Le HUD présente disponibilité, progression et timers ; son élément `passive_slot` est personnalisable et ne capture aucune entrée. Traqueur affiche un repère SPOTTED au-dessus de la pile vie/statuts, y compris derrière un couvert. Les effets utilisent un petit mesh emissif et les effets existants de dash/ralentissement.

En Survie, les améliorations de puissance existantes modifient uniquement la grandeur principale du passif : réduction, durée de révélation, bonus de dégâts ou intensité du ralentissement. Les valeurs du tableau correspondent au rang initial.

## Fichiers concernés par cette modification

- État et catalogue : `scripts/passive_state.gd`, `combat_data.gd`, `loadout_state.gd`.
- Joueur, bots et réseau : `player.gd`, `duel_bot_equipment.gd`, `duel_bot_state.gd`, `target_dummy.gd`, `network_player.gd`, `bot_build_presets.gd`.
- Impacts partagés : `mekatana_attack.gd`, `fulguro_punch.gd`, `pelto_smash.gd`, `rocket_basket.gd` ; callbacks Blaster, Shotgun, Longshot et Javelin dans les contrôleurs.
- Présentation : nouveaux `scripts/passive_hud.gd`, `passive_fx.gd`, ainsi que `equipment_icons.gd`, `hud_layout.gd`, `game_flow.gd`, `training_ground.gd`, `survival.gd`, `survival_progression.gd`. Quatre SVG sous `art/icons/`.
- Vérification : `tools/test_new_passive_state.gd`, `test_new_passive_combat.gd`, `capture_new_passives.gd` et captures sous `captures/new-passives/`.

Ces fichiers partagés contiennent aussi des modifications d’autres travaux en cours ; cette liste décrit uniquement les contributions des quatre passifs.

## Vérifications du 1er octobre 2026

Godot 4.7.2, runtime local `.godot/pass-runtime/`, données de test isolées via APPDATA.

- Deux suites dédiées : PASS. États, intervalles exacts, changements de cible, pellets/cleave, annulations, émission réelle Blaster/Longshot/Mekatana, critiques Shotgun, aller/retour Pelto, boucliers absorbants, dash réel, bots, répliques réseau, sauvegarde et HUD.
- Régressions `test_passives`, `test_cast_lock`, `test_touch_controls`, `test_hud_layout`, `test_network_combat`, `test_survival_rewards` : PASS.
- Import de l’éditeur et lancement réel avec captures : réussis. Rendu inspecté à 1280×720 et 960×540 avec contrôles tactiles ; mesure HUD également testée à 2340×1080.
- `test_bot_build_presets` : échec sur Eclipse et Projector absents des presets générés, deux modules issus d’autres travaux. Aucun des quatre nouveaux passifs n’est absent.

Les sorties du runtime signalent un magasin de certificats Windows indisponible. Des passages intermédiaires de la scène synthétique ont signalé des références résiduelles à la fermeture ; le dernier passage en mode verbose réussit sans ce signalement. Aucun APK ni appareil Android physique, et aucune partie entre deux machines, n’ont été vérifiés.

Exécution des suites dédiées : `--headless --path <projet> --script res://tools/test_new_passive_state.gd`, puis `res://tools/test_new_passive_combat.gd`. Captures : `--rendering-method gl_compatibility --script res://tools/capture_new_passives.gd` ; ajouter `-- touch_preview` pour le tactile.
