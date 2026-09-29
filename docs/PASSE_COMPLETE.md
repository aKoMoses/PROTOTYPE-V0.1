# Passe complète — livrée le 30 septembre 2026

Mission exécutée d'après `PROTOTYPE-0_Prompt-Codex-6-1_Passe-complete.txt`, corrections intégrées au projet. Référence : branche `v02-match-pass`, commit `8c05902`, arbre initial propre. Archive exacte sous `.godot/pass-baseline/source.zip`, checkout de comparaison sous `.godot/pass-baseline/project`.

## Résultat visible

Menu ajusté dans sa plaque, forge sans texte ni marqueur débordant, icônes FULGURO/Pelto mécaniques en SVG, réglages/pause/résultat utilisant le cadre métallique existant et un focus visible. Panneaux de navigation adaptés au canvas, sans toucher au placement du HUD personnalisé.

Éditeur HUD : barre repliée lorsque nécessaire, panneau dans la zone sûre et commandes accessibles par défilement. Jauges des acteurs : identité et arme séparées des PV, bobine/cartouches sous la barre, statuts au-dessus de la plaque. Sélection et bilan Survie harmonisés, icônes du build et barres de contribution lisibles.

Modèles, animations, matériaux, éclairage, géométrie, fumées et impacts existants inspectés. Les éléments déjà cohérents sont conservés ; aucune refonte ou abstraction spéculative ajoutée.

## Bugs reproduits puis corrigés

| Observation | Correction vérifiée |
| --- | --- |
| Un doigt de déplacement déclenchait une charge PC via la souris émulée, puis un tir au relâchement. | Seuls les appuis souris physiques ayant traversé le GUI alimentent l'attaque PC. Espace et gestes tactiles existants conservés. |
| Contacts tactiles périmés après mort, désactivation ou changement de joueur ; FULGURO continuait sans doigt. | Nettoyage de propriété et annulation de la seule préparation détenue. Focus/pause nettoient aussi les contacts PC. |
| Deux racines GUI plein écran bloquaient les clics de combat avec le lecteur PC respectant le GUI. | FlowRoot/CombatHUD laissent passer combat/essai HUD ; navigation et boutons interactifs bloquent. Vrai hit-test Vulkan vérifié. |
| JSON primaire illisible remplaçant le backup HUD valide. | Backup réservé aux schémas lisibles, migration version 0 incluse. Aucune remise à zéro joueur. |
| Équipement autre que robot non sauvegardé immédiatement ; secousses sauvegardées non appliquées au démarrage. | Persistance de chaque choix et application du réglage chargé dès configuration. |
| Arcs STUN persistants entre impulsions. | Visibilité recalculée avec le timer visuel existant ; effet de contrôle inchangé. |
| Ancien timer réseau appliqué au match suivant, double retour salon, accès GD-Sync à une scène null. | Génération de session, fermeture idempotente, gardes minimales. Attentes 3,5 s / 2 s conservées. |
| Pause Survie consommant les échéances absolues Blaster/Javelin. | Réutilisation du helper de décalage déjà présent dans Training. |
| Tween de retour du kit poursuivi après reset. | Annulation du tween périmé ; collecte, rayon, soin et respawn inchangés. |
| Voix GameSfx conservées après navigation/reset. | Nettoyage aux transitions, suspension des voix/demandes pendant pause. Assets, volumes et budgets conservés. |

Reproductions, attendu et résultats : [contrôles](pass_controls.md), [modes](pass_modes.md), [présentation](pass_presentation.md).

## Validation terminée

Godot **4.7.2.stable.official.ed1daf0bf**, renderer **Mobile/Vulkan**, PC **RTX 3070 Laptop**. Les chemins `C:\RomainOpen\…` d'AGENTS sont absents ici ; le moteur exact existant dans Downloads est extrait sous `.godot/pass-runtime`. APPDATA isolé sous `.godot` pour les tests/captures, sans toucher aux sauvegardes personnelles.

- Import éditeur final : exit 0, aucune erreur de script.
- **47/47 scénarios** : 46 headless et un dispatch GUI en fenêtre Vulkan, exit 0, aucune SCRIPT ERROR. [Résultats](pass_validation_results.json), logs `.godot/pass-logs/final/`.
- Nouvelles régressions : entrées 18, routage 28, GUI 13, HUD 49, navigation 48, présentation 14 assertions. Réseau et pause modes également réussis.
- Armes/modules, passifs, cast locks, interruptions, FULGURO pendant dash, visée/strafe multidirectionnels, mort/reset, soins, bots/obstacles : suites existantes réussies. Survie : 12 vagues / 76 ennemis.
- Rigs : joueur 299, ennemi 510, VFX 73 contrôles. Stress VFX 180 s simulées : plateau 113 nœuds en normal, 101 en basse. Aucun résultat Android revendiqué.
- Paquet compilé : lancement Vulkan et **cinq cycles** forge → duel → pause/reprise → résultat → menu réussis. Captures/docs/outils QA exclus. La démonstration du menu garde ses acteurs actifs comme dans la référence ; l'arrêt du match est vérifié séparément.

Couverture graphique : principaux écrans, quatre statuts, Blaster normal/chargé/Shotgun en déplacement, impacts/expiration, arène aux quatre limites et au coin, Training et Survie. **133 PNG** sous `captures/pass_complete/`, avec originaux exacts avant et images après.

Ratios UI inspectés : 1280×720 (16:9), 1600×720 (20:9), 960×720 (tablette), 800×600 (stress éditeur). `ui_ratio_preview`/`logical_canvas` changent seulement les fixtures. Stretch, caméras et champ tactique livrés inchangés. Les images `readout/*1600*` conservent le letterboxing de production ; leurs dimensions réelles sont qualifiées dans la note présentation et ne prouvent pas un rendu natif 20:9.

Animation : **131 frames à 60 FPS**, `exports/pass_complete/weapon_locomotion.avi`. Séquence de 24 images extraites et inspectées : `captures/pass_complete/after/animation_sequence.png`, plus sept poses détaillées. Fixture de rig, pas mesure de performance en jeu.

## Contrat de gameplay

[Référence](pass_gameplay_reference.json) / [livraison](pass_gameplay_delivered.json) : CombatData, physique/rendu et contrat d'arène **strictement identiques**. 15/16 fichiers de simulation identiques par SHA-256 normalisé. Seule exception `target_dummy.gd` : une ligne d'alignement vertical de Label3D, sans changement de statut, visibilité ou simulation. [Comparaison explicite](pass_gameplay_verification.json).

Arène : **48 bloqueurs, 4 zones de soin, 14 buissons**. Mêmes colliders, positions, dissimulation, passages et bordures. Bots/profils, progression/synergies, projectiles et CameraRig identiques. Aucun ajout d'arme, module, progression, aide à la visée, hache ou mapping.

Diffs sensibles relus : inputs/ownership, physique, dégâts, horloges, caméra, animations, IA et transitions. Différences de comportement limitées aux bugs documentés : entrées dupliquées/périmées, sauvegardes, ancienne session et temps écoulé à tort pendant pause. ActionGate/priorités intacts ; aucun délai de commande ajouté.

## Mesures avant/après

Scène de jeu 1280×720, bot arrêté, 30 frames de chauffe + 120 échantillons, processus avant/après séquentiels. [Mesures complètes](pass_performance.json).

| Mesure PC | Avant | Après |
| --- | ---: | ---: |
| Nœuds / meshes | 1869 / 1206 | 1872 / 1206 |
| Matériaux / lumières / ombres | 255 / 4 / 1 | 255 / 4 / 1 |
| Particules / colliders | 10 / 54 | 10 / 54 |
| Draw calls | 1553 | 1555 |
| Mémoire moteur statique / pic MiB | 126,94 / 127,03 | 141,54 / 141,63 |
| Orphan nodes | 0 | 0 |
| Rendu viewport CPU / GPU ms | 1,836 / 0,590 | 2,843 / 0,672 |
| FPS / process / physique ms | 38,6 / 30,410 / 4,161 | 36,4 / 10,015 / 1,406 |

Trois nœuds supplémentaires : habillage et deux sous-titres d'acteurs. Échantillons courts avec variations de démarrage/compositeur : aucun gain de FPS établi. Mémoire statique hors GPU/driver. Pas de pooling, cache, changement de physique/fréquence IA ni réduction d'informations pour optimiser.

## Limites explicites

- Aucun Android physique, multitouch matériel, encoche, orientation réelle ou arrière-plan mobile vérifié. Notifications/contacts simulés sur PC. Pas de promesse 60 FPS mobile.
- Découverte locale tentée entre deux processus : transport connecté, salon hôte créé, invité en timeout. Cause réseau/broadcast non établie. LAN/cloud et duel entre appareils non validés ; offline ne les remplace pas.
- Audio : événements/volumes et 16 WAV sans échantillon saturé vérifiés ; écoute subjective mobile non effectuée. 24 scénarios, dont deux nouvelles fixtures, signalent des ressources audio référencées à l'arrêt ; diagnostic verbose : mixer WAV. Les régressions GUI, routage, présentation, réseau et pause, qui nettoient les voix avant arrêt, quittent proprement. Pas d'accumulation de nœuds observée entre parties.
- Message Windows `Failed to read the root certificate store` présent avant/après. Les deux erreurs de script GD-Sync initiales sont corrigées ; le message système demeure.

## Build et utilisation

Paquet réel : `exports/pass_complete/prototype0-pass-complete.pck`, **118 239 648 octets**, SHA-256 `57d046a7f199c73de9139a911bc6661ceb3a6eec1abc381bdce760b0e9957abe`. Preset Windows Desktop, joué avec Godot exact. Nécessite Godot 4.7.2 ; ce n'est ni un EXE autonome ni un APK.

Lancement : `& '.\tools\play_pass_complete.ps1'`. Le lanceur utilise les chemins absolus connus et le pack livré. `captures/pass_complete/after/packed_forge.png` provient de ce paquet compilé.

Android bloqué : SDK configuré `C:\Users\Ben\AppData\Local\Android\Sdk` absent, build-tools absents, chemin JDK vide et `java` introuvable. Templates Android présents, template Windows EXE absent. Identifiant `com.prototype0.arena`, versions et signature inchangés ; aucune clé remplacée. Export sans clés API GD-Sync : connexion cloud indisponible dans ce pack local.

Logs : `.godot/pass-logs/export_pack.log`, `packed_graphics_smoke.log`, `packed_cycles.log`. Outils : `run_validation_pass.py`, `audit_gameplay_reference.gd`, `audit_arena_runtime.gd`, `verify_packed_game.gd`, helpers de capture. QA exclue des presets et captures de passe exclues de l'import.

## État de reprise

Domaines présents inspectés, défauts prioritaires accessibles traités, suite et paquet vérifiés. Aucun travail de gameplay restant identifié par la revue finale. Android matériel, écoute mobile et réseau réel nécessitent leur environnement cible.

Commits locaux de corrections : `b83ae00` (commandes/HUD), `91b3e01` (modes/réseau/audio), `2ca157f` (interface/jauges). Les preuves et outils sont enregistrés dans le lot de validation suivant. [Manifest du paquet](pass_build_manifest.json). Aucun push, fusion ou publication.
