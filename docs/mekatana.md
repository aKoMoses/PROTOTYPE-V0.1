# MEKATANA

Le Mekatana utilise la commande d'attaque habituelle : clic/espace sur PC et joystick de visée sur mobile. Maintenir enchaîne les coups après chaque récupération ; relâcher laisse finir le coup engagé. Le combo avance même dans le vide. La fenêtre de 2,5 s commence à la fin du slash actif et inclut la récupération ; elle sert à engager le prochain coup.

## Réglages

Les valeurs partagées joueur/bots se trouvent dans `CombatData.WEAPON_DEFINITIONS.mekatana`, dans `scripts/combat_data.gd`.

| Réglage | Coup 1 | Coup 2 | Coup 3 |
|---|---:|---:|---:|
| Dégâts de base | 65 | 75 | 100 |
| Préparation avec dash | 0,12 s | 0,14 s | 0,18 s |
| Slash actif | 0,10 s | 0,10 s | 0,13 s |
| Récupération | 0,20 s | 0,23 s | 0,48 s |
| Distance de dash | 1,30 m | 1,90 m | 2,60 m |
| Largeur du cleave | 2,30 m | 2,30 m | 2,50 m |

La lame frappe à 2 m depuis la position réellement atteinte ; les dashes augmentent progressivement l'engagement, jusqu'à 4,6 m au troisième coup. Les trois distances de dash ont été doublées. La hauteur du cleave est de 1,8 m. Le troisième mouvement vertical conserve une zone large.

Le coup 2 inflige ×1,20 uniquement à une cible touchée au coup 1. Le coup 3 inflige ×1,25 à une cible touchée au coup 2, ou ×1,60 si les deux premiers l'ont touchée. Les deux bonus du troisième sont exclusifs. Un combo intégral inflige 65 + 90 + 160 = 315 dégâts, soit 31,5 % des 1 000 PV du robot polyvalent. Le cycle complet prend 1,68 s hors interruptions et reste exposé pendant ses préparations et récupérations.

L'historique appartient à chaque cible et séquence. Seuls des dégâts acceptés par le combat le remplissent ; annulation, expiration, changement d'arme, mort et reset le vident. Aucun effet STUN, SLOW, BURN ni projectile n'est ajouté.

## Intégration

Le modèle fourni est copié dans `art/weapons/mekatana.glb` ; son SHA256 est identique à celui du fichier original conservé dans Downloads. La scène `scenes/weapons/mekatana.tscn` corrige l'échelle et le pivot sans modifier le GLB. Celui-ci ne contient aucune animation : les gestes accompagnent la lame par le buste, les épaules et les bras du rig existant. Le premier slash va de gauche à droite du combattant, le deuxième revient, le troisième abat la lame de haut en bas.

`scripts/mekatana_visual.gd` pilote le courant au repos, la montée électrique, les traînées échantillonnées sur la vraie lame, les arcs d'impact et les sons synthétisés courts. `STEP_PRESENTATION` distingue le premier slash compact (±48°), le retour plus ample du deuxième (±88°) et le troisième levé haut puis abattu, avec des sons plus graves et des impacts plus marqués. Les traînées durent respectivement 55, 80 et 100 ms. La préparation, la phase active et la récupération restent pilotées par le combat. Les sockets maintiennent la prise pendant les déplacements et les changements de direction.

Les fichiers concernés sont regroupés ainsi :

- Combat et réglages : `scripts/combat_data.gd`, `mekatana_attack.gd`, `player.gd`.
- Modèle et présentation : `art/weapons/mekatana*`, `scenes/weapons/mekatana.tscn`, `scripts/mekatana_visual.gd`, `player_visual_rig.gd`, `player_aim_modifier.gd`, `enemy_droid_visual.gd`, `enemy_droid_pose.gd`, `art/ui/icons/mekatana.svg`.
- Équipement, forge et HUD : `scripts/loadout_state.gd`, `equipment_icons.gd`, `equipment_forge_preview.gd`, `hud_vitals.gd`, `survival.gd`.
- Bots et réseau : `scripts/training_bot.gd`, `duel_bot_equipment.gd`, `target_dummy.gd`, `bot_build_presets.gd`, `duel_bot_builds.gd`, `network_player.gd`, `network_match.gd`.
- Vérification : les scripts `tools/test_mekatana*.gd` et `tools/capture_mekatana_rigs.gd`.

Les bots utilisent le même combo, adaptent leur distance au dash du prochain coup et effectuent leurs dashes via leur déplacement à collisions. Leur filtre de cibles conserve celui des autres armes : ils ne blessent pas les autres bots. En réseau, l'hôte possède les touches et les bonus ; les répliques affichent les phases confirmées sans appliquer de dégâts. Les paquets de position et de visée respectent le verrouillage du cast/slash.

En survie, les améliorations Puissance augmentent les dégâts, et Rythme raccourcit la récupération ; la préparation et la durée active restent lisibles. Le Mekatana conserve la progression générique sans évolution spéciale ajoutée.

## Validation

Vérifications réalisées avec Godot **4.7.2.stable.official.ed1daf0bf**, avec un APPDATA de test isolé sous `.godot` pour préserver les sauvegardes personnelles.

| Vérification | Résultat |
|---|---|
| `tools/test_mekatana.gd` | PASS, 139 contrôles |
| `tools/test_mekatana_network.gd` | PASS, 20 contrôles hôte/réplique locaux |
| `tools/test_mekatana_visual.gd` | PASS, 119 contrôles joueur/bot, prises et trajectoires |
| `tools/test_mekatana_bot.gd` | PASS, combo, portée, interruptions, collisions et retours d'impact |
| `tools/test_mekatana_survival.gd` | PASS, sélection, progression, dégâts et Omnivamp |
| Régressions `tools/test_blaster.gd` et `tools/test_shotgun.gd` | PASS |

Le test principal couvre les trois profils de bonus, les ratés et changements de cible, les touches rejetées, les colliders multiples, les trois cleaves, la fenêtre et son expiration, la préparation engagée avant échéance, les dégâts exclusivement actifs, la direction capturée, les murs et les couverts, une cible traversant rapidement le cleave entre deux frames, l'annulation depuis un callback de dégâts, les cibles désactivées et les informations du loadout/HUD. Les cas réels de joueur valident la sélection persistante, le combo de 315 dégâts, le maintien et le relâchement de l'espace PC et du joystick mobile, le relâchement pendant la préparation, les boutons de modules et les annulations par stun, changement d'arme, mort, reset et désactivation.

Les tests réseau confirment le rang choisi par l'hôte, les doublons refusés, le verrouillage des paquets de pose, les dégâts et bonus autoritaires, les événements de présentation sans dégâts, la correction du rang/deadline/phase/direction par snapshot et l'interruption après mort confirmée. Les 119 contrôles visuels vérifient les prises des deux mains, les trois directions de slash et les mouvements avec une visée opposée. Le deuxième balayage mesure 35 à 36 % de plus que le premier sur les deux rigs ; la pointe du troisième reste au-dessus du sol en fin de frappe.

Les cas bots valident le combo 65/90/160, le refus d'attaquer à 8 m, les interruptions et priorités, les trois distances de dash, les arrêts contre les murs et les limites d'arène, le recul avant un dash trop long, l'orientation et les effets d'un impact réellement accepté. Le test Survie vérifie une frappe de 81,25 dégâts au rang Puissance 1, le soin Omnivamp appliqué une seule fois, les valeurs de progression sans cumul et le retour aux bases après la sortie du mode.

Dix captures des vrais acteurs sont produites par `tools/capture_mekatana_rigs.gd` dans `.godot/mekatana-review` ; la garde, les trois mouvements et les positions centrales/finales ont été inspectés. L'import éditeur et les régressions des casts, entrées et combats réseau ont également passé les vérifications de livraison.

Restent à essayer en conditions réelles : l'écoute des sons, les performances et gestes sur un appareil mobile physique, et un match internet entre deux machines. Les tests tactiles injectent les contacts existants ; les tests réseau exécutent localement les contrôleurs hôte/réplique et les mêmes gestionnaires de paquets.
