# Prototype 0 — suivi V0.2

Dernière vérification : 28 septembre 2026 (IA du duel). Renderer conservé : Godot 4.7.2 Mobile.

## État de la passe

| Lot | État | Preuve / limite |
|---|---|---|
| V02-01 — Blaster/Shotgun | Implémenté | `loadout_state.gd` migre les identifiants inconnus et `electro_axe` vers `blaster`. Les routes jouables n'exposent plus l'ancienne arme. |
| V02-02 — manche locale | Implémenté et testé | Décompte 3 s, actions bloquées, score unique, égalité sans point, arrêt de manche, premier à 3, reset complet. `tools/test_game_flow.gd` PASS. |
| V02-03 — bot | Implémenté et testé | Bot désactivé dans menu/décompte, mémoire de dernière position visible, ligne de vue et esquive simple. `tools/test_training_bot.gd` PASS. |
| V02-04 — interface | Implémenté | Équipement détaillé au toucher, score/phase/PV/états, charge Blaster et cooldowns des modules. Layout tactile existant conservé. |
| V02-05 — vérifications | Implémenté et testé | Tests headless PASS listés ci-dessous ; captures Godot Mobile produites dans `captures/v02_*.png`. |
| V02-06 — Android | APK produit et signé | `exports/prototype0-debug.apk`, package `com.prototype0.arena`, version code 2 / nom 0.2.0, arm64, SHA-256 `C6F3BC144242C90A459FD2F4E33596D0B6F053D18BAC08FC621F2B0EA850019B`. |
| V02-07 — documentation | Implémenté | Ce fichier est le suivi local de référence ; aucune mise à jour Notion requise. |
| V02-08 — kits supplémentaires | Reporté | À commencer après validation de la boucle de manche. |
| V02-09 — décisions du bot en duel | Implémenté et testé en headless | Le bot poursuit la dernière position vue pendant 4 s, cherche un angle praticable autour des couverts, accélère son approche après avoir vu une recharge de Shotgun et attend 0,2 s avant d'esquiver une attaque visible. L'entraînement et la Survie gardent leurs règles propres. `tools/test_duel_bot.gd` PASS ; sensations en jeu à valider. |

## Tests exécutés

- `test_game_flow.gd` — PASS : transition menu → décompte → manche, pause, victoire, score non doublé, manche suivante, égalité, fin à 3.
- `test_loadout_state.gd` — PASS : sauvegarde/fallback et migration `electro_axe` → `blaster`.
- `test_blaster.gd`, `test_shotgun.gd`, `test_combat_state.gd`, `test_target_dummy.gd` — PASS.
- `test_offensive_modules.gd`, `test_defensive_modules.gd`, `test_mobility_modules.gd`, `test_passives.gd` — PASS.
- `test_training_bot.gd`, `test_visibility.gd`, `test_touch_controls.gd`, `test_fx_budget.gd` — PASS.
- `test_duel_bot.gd` — PASS : perte de trace derrière le couvert central, contournement réel, oubli après 4 s, avancée pendant une recharge visible, absence de lecture de la recharge à travers le couvert et délai avant esquive.

Captures réellement inspectées : `captures/v02_menu.png`, `captures/v02_equipment.png`,
`captures/v02_duel_live.png` et `captures/v02_result.png`.

Les avertissements « root certificate », écriture de `user://logs` et Android build-tools viennent de l'environnement headless ; ils ne provoquent pas d'échec des scripts ci-dessus.

## Parcours manuel desktop

1. Lancer `res://scenes/main.tscn` avec Godot.
2. Cliquer `JOUER`, vérifier le décompte 3 secondes : Espace/A/E/R/G ne doivent rien déclencher.
3. Après `COMBAT`, vérifier déplacement, Blaster/Shotgun, modules et bot avec F7 si nécessaire.
4. Mettre en pause pendant le décompte puis pendant la manche : le temps et les actions doivent rester figés.
5. Faire tomber un acteur : le résultat de manche reste affiché, puis la manche suivante repart après environ 2 secondes.
6. Répéter jusqu'à 3 points ; le résultat final revient au menu via le bouton prévu.

## Restant à vérifier

- capture visuelle finale depuis Godot après cette passe ;
- export et signature de l'APK 0.2.0 ;
- installation et framerate sur un téléphone Android réel ;
- nettoyage ultérieur des helpers historiques d'animation de l'ancienne arme, inertes et non référencés par les routes Blaster/Shotgun.
