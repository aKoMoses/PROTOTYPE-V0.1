# Passe complète — modes, soins, réseau et décor

État de référence : branche `v02-match-pass`, HEAD `8c05902`. Travail intégré sans commit par cette sous-tâche. Godot 4.7.2 officiel exécuté depuis `.godot/pass-runtime`. Données de vérification isolées sous `.godot/pass-user-modes` en redirigeant APPDATA ; aucun effacement de sauvegarde joueur.

## Périmètre inspecté

- Training Ground : monde procédural, cinq cibles initiales, placement/retrait, reset, mort/réapparition, options, compteur de dégâts, menu, HUD et essai de personnalisation.
- Survie : sélection, douze vagues, renforts, variantes élites/boss, choix de récompense, pause/reprise, essais HUD, soins, musique, statistiques, bilan, favori et export de carte.
- Soins d'arène : états AVAILABLE/RECHARGING/DISABLED, collecte concurrente, pleine vie/mort, occlusion, acteur présent à la réapparition, reset et présentation.
- Réseau : sessions/salons, disponibilité des boutons, lancement, préparation, score, résultat, sortie, callbacks et initialisation GD-Sync. Lecture du serveur local et essai réel de découverte entre deux processus.
- Bots et modules partagés : perception/ligne de vue, mémoire, interruption, action gate, déplacements et collisions, soins, télégraphes, charge de Survie, FULGURO/Pelto et CombatState. Les stratégies et profils d'IA n'ont pas été modifiés.
- Décor : lecture des cartes principale/Training/Survie et des volumes de buissons ; inspection des captures Training vue générale/zone fixe et Survie. Pas de collider, position, couvert, limite, volume de dissimulation ni éclairage changé.

## Défauts reproduits et corrections

| Défaut observé | Attendu et preuve | Correction / résultat |
| --- | --- | --- |
| Ancien timer de préparation d'un match applique `live` au match suivant, environ 0,2 s trop tôt dans la fixture quitter/rejouer. | Chaque match attend ses propres 3,5 s ; durée existante dans `_host_prepare_round`. | Génération de session capturée par les attentes de préparation/résultat ; invalidation lors départ, déconnexion, nouvelle entrée ou nouveau match. Même durée de décompte. |
| Quitter appelle deux fois retour au salon : `leave_room` émet synchroniquement `room_changed`, puis `_leave_match` ferme une seconde fois avant `queue_free`. | Un seul arrêt et une seule ouverture. Fixture comptant les deux callbacks du Flow. | Garde idempotente sur phase `closed` dans `_finish_to_lobby`. |
| SessionController et NodeInstantiator arrêtent leur `_ready` sur `current_scene`/cible null. | Les autoloads se lancent avant la première scène ; les scripts SceneTree de test reproduisent directement les deux SCRIPT ERROR. Le root instantiator a déjà un chemin de secours local dans `instantiate_node`. | Gardes scene null/connexion dupliquée ; chemin de secours vers lui-même pour les métadonnées du root instantiator. Aucun changement de protocoles, transport ou version SDK. |
| Pause Survie retire 0,35 s à la marque Javelin et à la cadence Blaster restantes. | La pause suspend le combat. Training applique déjà le helper `player.shift_pause_timers` aux mêmes échéances absolues. | Survie enregistre la durée de pause et réutilise ce helper à la reprise. Cooldowns en simulation delta, charge/cast, durée de marque et cadence ne changent pas. |
| Animation de retour de kit reprend après `reset_for_round` et porte la croix à 1,14046 à t=0,22 s. | `_apply_state_visuals(false)` remet explicitement l'échelle à 1 ; seule pulsation nominale ±2,5 % reste ensuite. | Tween conservé puis annulé lors changement d'état/reset ; nouvelle mesure 1,01893. Soins et délais identiques. |

`test_network_reliability.gd` : FAIL avec quatre assertions avant corrections, puis PASS sans SCRIPT ERROR. `test_mode_pause_reliability.gd` : FAIL avec les deux échéances Survie avant correction, puis PASS. Ce dernier vérifie aussi suspension/reprise des sons et nettoyage des voix après reset depuis le menu. Godot suspendait déjà les AudioStreamPlayer natifs à la pause ; l'intégration `GameSfx.set_paused` protège les nouveaux événements et `clear` retire les anciennes voix de cet autoload lors reset, résultat, sortie et essais HUD.

## Présentation intégrée

Sélection Survie : surface métal opaque (plus de robot traversant visuellement le texte), bord rouille, boutons crème avec hover/pression/focus. Bilan : icônes de l'équipement réel, barres cyan et boutons cohérents avec la forge. Le favori conserve son rôle de référence et la carte exportée conserve les mêmes données.

Captures rendues et inspectées, dimensions vérifiées :

- `captures/pass_complete/after/survival_selection.png` — 1280 × 720.
- `captures/pass_complete/after/survival_result.png` — 1280 × 720.
- `captures/pass_complete/after/survival_selection_tablet.png` — 960 × 720, fixture canvas EXPAND.
- `captures/pass_complete/after/training_menu_1600.png` — 1600 × 720, fixture canvas EXPAND, ratio 20:9.
- `captures/pass_complete/after/survival_card.png` — carte exportée de 1200 × 850.

Les originaux comparables sont dans `captures/pass_complete/before`. `training_menu_desktop_large.png` mesure 1875 × 1055 : le bureau a réduit une demande 2340 × 1080 ; cette capture n'est **pas** une preuve 20:9. Les options `ui_ratio_preview` des outils de capture changent seulement leur canvas de test, jamais les réglages livrés du projet ni la caméra du jeu.

## Vérifications exécutées

`docs/pass_modes_test_report.json` détaille les quinze régressions du lot : toutes exit 0, aucune SCRIPT ERROR. Scénarios : réseau offline, pause modes, training ground/meter, kits fonctionnels/visuels, expansion/musique Survie, bot entraînement/duel/tactique/collisions, CombatState, FULGURO, Pelto. `test_survival.gd` a également passé toute la progression des douze vagues et 76 ennemis, armes, rewards, pause et défaite. Le test pause a été relancé après intégration du nettoyage de contact PC.

Les anciens scripts de test quittant immédiatement après de l'audio actif signalent encore des ObjectDB/resources en cours au shutdown (colonne `otherIssues`). Le lot mesure ce fait et ne le masque pas comme un succès sans réserve. Les deux nouvelles régressions terminent sans cette réserve. L'erreur Windows `Failed to read the root certificate store` est commune à l'état initial et à ces exécutions.

Préservation vérifiée au diff : aucun changement à CombatData, bots/profils, dégâts, soins, munitions, rechargement, durées, portées, projectiles, hitboxes ou géométrie dans ce lot. Kits : 30 % PV maximum, 20 s et rayon 1,45 m conservés ; Survie +80 PV aux vagues 2/5/8/11, +100 PV aux paliers 3/6/9 et 12 vagues conservés. Training : carte 88 × 76, cinq placements initiaux, tailles 0,65/1/1,5, limite 12 et respawn 0,75 s conservés. Réseau premier à trois, préparation 3,5 s et attente résultat 2 s conservés. Seul le temps erronément écoulé pendant pause/ancienne session est neutralisé.

## Limites

Deux processus `test_cloud_lobby.tscn -- --network-local-test host/guest` ont été lancés : chacun se connecte au transport local, l'hôte crée son salon, l'invité ne découvre aucun salon et les deux atteignent le timeout de 20 s. La cause réseau/broadcast de cet environnement n'est pas établie ; test LAN/cloud et duel entre deux appareils **non validés**. Le test offline ne les remplace pas. Aucun service cloud n'a été lancé, clé/secrets exposés ni pare-feu modifié.

Captures PC sur RTX 3070 Laptop, renderer Forward Mobile Vulkan. Pas de matériel Android ni multitouch physique, pas de mesure mobile de performance dans ce lot. Les captures statiques de décor n'établissent pas une absence universelle de défaut d'animation ; la validation temporelle est portée par le lot présentation de la passe principale.

Prochaine action globale : import final, suite complète consolidée, vérification de la référence de gameplay et intégration du rapport principal.
