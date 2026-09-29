# Passe contrôles et personnalisation HUD — 30 septembre 2026

Base : branche `v02-match-pass`, commit `8c05902`. Les contrôles, le modèle de
sauvegarde, l'éditeur HUD et leurs intégrations Duel/Training Lab/Survie ont été
inspectés. La référence chiffrée générale reste `pass_gameplay_reference.json`.

## Défauts reproduits et corrections

| Défaut observé | Preuve et comportement attendu | Correction intégrée |
| --- | --- | --- |
| Déplacement tactile seul amorçant une charge PC et un tir au relâchement | Godot 4.7.2 a `emulate_mouse_from_touch=true`. Un contact propriétaire du déplacement produit aussi `Input.is_mouse_button_pressed(LEFT)=true`; l'ancien lecteur PC utilise cet état global. Probe avant : doigt déplacement `0`, aucun doigt visée, charge active puis un tir. Le prompt exige l'indépendance des commandes et l'absence de double lecture tactile/souris. | Le lecteur PC mémorise uniquement un appui souris physique arrivé après le GUI. Les événements souris émulés continuent à servir les menus et sont exclus des attaques. Espace conserve son mapping et son chemin de charge existants. |
| Doigts encore propriétaires après désactivation du combat, mort et remplacement de joueur | Le script d'origine ne suspendait que selon visibilité/pause. Un ancien drag après réactivation alimentait de nouveau le déplacement. Le test de transitions exécuté avec le script tactile extrait de HEAD échoue sur six assertions sur 18. | Suspension fondée aussi sur la disponibilité réelle du joueur; nettoyage des contacts lors de la suspension et avant un changement de joueur. |
| FULGURO tactile continuant à charger après perte du contact | Le nettoyage vidait la table des doigts sans annuler la préparation FULGURO qu'elle possédait. La charge pouvait donc atteindre son auto-décharge sans doigt. | Le nettoyage annule uniquement les actions acceptées encore tenues. Pour FULGURO, seule la préparation est annulée : pas de remboursement de cooldown, pas de modification de l'action déjà active/récupération. |
| Charge PC restant liée à une entrée périmée à la pause/perte de focus | L'ancien chemin ne distinguait pas ces interruptions d'un relâchement normal. | `reset_desktop_inputs()` nettoie appui, tampon et charge PC; la charge FULGURO issue de A est suivie séparément. Les transitions de pause Duel/Survie appellent ce nettoyage. Les nouvelles pressions restent immédiates après un véritable relâchement. |
| Souris PC bloquée par les racines GUI lorsque le nouveau routage respecte le GUI | Vérification graphique réelle : un clic envoyé en combat ne parvient pas au joueur quand FlowRoot et CombatHUD sont `STOP`; il y parvient avec `IGNORE`. Le headless ne reproduit pas ce hit-test graphique. | Intégration par la passe principale : CombatHUD ignore la souris; FlowRoot ignore en combat/essai HUD et bloque en navigation. Les boutons conservent leurs propres zones interactives. |
| Copie HUD valide remplacée par un JSON primaire de schéma illisible | Principal `{version:1,families:"corrupted"}` : l'ancien writer remplace la bonne copie de secours; une corruption ultérieure du principal perd la configuration. La première migration version 0 ne sauvegardait pas non plus le document précédent pourtant lisible. | Le writer copie seulement les schémas réellement pris en charge par le loader, versions 0 et 1. Aucune disposition de joueur n'est réinitialisée. |
| Panneau d'éditeur hors écran et dernier choix de barre inaccessible | Avec le texte d'aide existant, le panneau posé à largeur 290 possède une largeur minimale de 393 et dépasse sur les quatre ratios testés. La barre fixe dépasse à 800×600. L'ancien éditeur/modèle, extrait de HEAD, échoue sur sept assertions sur 49. | Textes longs repliés, sélecteur à largeur stable, colonne extensible; barre qui passe à la ligne et panneau placé sous sa hauteur réelle dans la zone sûre, avec défilement vertical. |

## Vérifications exécutées

Godot **4.7.2 stable officiel**, console extraite de l'archive locale dans
`.godot/pass-runtime`. Tous les processus ont un `APPDATA` de test sous
`.godot/pass-user-controls`; les sauvegardes personnelles Windows ne sont pas
utilisées. Les probes de comparaison restent dans `.godot`, sans remplacement
des sources livrées ni modification de l'historique Git.

| Test | Résultat |
| --- | --- |
| `tools/test_input_transition_reliability.gd` | PASS, 18 assertions : propriété des doigts, drag hors zone, ordre de relâchement, focus, interruption système, pause, mort/réapparition, remplacement de joueur, annulation FULGURO tactile et préservation d'une charge PC sans contact tactile. |
| `tools/test_mouse_input_routing.gd` | PASS, 28 assertions : vraie émulation souris via `InputEvent`, mouvements/visée séparés, tir unique, souris physique, Espace, Shotgun, GUI, focus, pause, FULGURO PC et appui tenu avant combat. Les deux stages d'entrée GUI sont explicitement simulés dans ce test headless. |
| `tools/test_gui_input_routing.gd` | PASS, 13 assertions **avec rendu Vulkan Forward Mobile, RTX 3070 Laptop**. Événements injectés par `Input.parse_input_event()` et flush, sans appeler manuellement les callbacks du joueur : clic PC réel, boutons Pause/Reprendre réellement activés, deux doigts, tir unique, pause avec charge et blocage de la navigation. Ce test signale SKIP si exécuté headless. |
| `tools/test_hud_editor_safety.gd` | PASS, 49 assertions : restauration du backup, migration version 0, panneau/chaque bouton de barre dans 1280×720, 1600×720, 960×720 et 800×600, sans chevauchement barre/panneau. Les tailles logiques sont imposées uniquement par la fixture. |
| `tools/test_touch_controls.gd` | PASS : zones tactiles, modules à gauche, multi-touch, contact rejeté FULGURO, priorités de superposition et zone Pause réservée. |
| `tools/test_hud_layout.gd` | PASS : validation/migration, sauvegarde, édition/undo/redo, déplacements, essais temporaires et restauration dans les trois scènes. |
| `tools/test_hud_user_save.gd` | PASS : écriture et relecture dans le répertoire utilisateur isolé. |

Les tests Blaster/Cast Lock et la suite complète sont exécutés par la passe
principale et recensés dans `PASSE_COMPLETE.md`; cette note n'anticipe pas leurs
résultats.

## Captures inspectées

- Avant : `captures/pass_complete/before/hud_editor_1280.png`.
- Après comparable : `captures/pass_complete/after/hud_editor_1280.png`.
- Ratios avec aperçu de canvas étendu : `after/hud_editor_800.png` et `after/hud_editor_1600.png`, dans le même répertoire.
- Stress du véritable canvas logique 800×600 : `captures/pass_complete/after/hud_editor_canvas_800.png`. La barre occupe deux lignes et le panneau reste visible avec ses commandes accessibles par défilement.

`tools/capture_hud_editor.gd` accepte maintenant un chemin PNG puis
`logical_canvas`, uniquement pour cette inspection. La configuration de
stretch, la caméra et le champ tactique du jeu restent inchangés.

## Contrat et limites

Aucune valeur d'arme/module, durée, cadence, dégâts, portée, rayon, déplacement,
collider, caméra ou priorité d'ActionGate n'a changé dans ce lot. Le mapping et
les profils enregistrés sont conservés. Le tap/maintien/relâchement du Blaster
mobile et le geste Shotgun existants sont inchangés. Les différences de
comportement se limitent aux entrées dupliquées, périmées ou appartenant au GUI.

Les contrôles de partage, de chargement de layout et des zones réservées
utilisent déjà les mêmes données pour affichage et contact. Le recentrage de
visée envoie toujours sa dernière valeur valide avant de recentrer l'affichage.
Les exceptions de dash/cast restent régies par ActionGate et les modules
existants. Le contrôle de personnalisation n'a ajouté ni nouveau widget de
combat ni nouvelle ergonomie.

Les tests graphiques restent des simulations sur PC : **aucun téléphone Android
physique, écran à encoche, changement d'orientation réel ou système mobile en
arrière-plan n'a été validé**. Leurs notifications sont injectées en test. La
zone sûre native Android et sa conversion avec letterboxing restent à vérifier
sur matériel cible; elles n'ont pas été modifiées sans reproduction.

Le runtime signale une lecture impossible du magasin de certificats Windows
dans cet environnement. Certains arrêts headless immédiats signalent quelques
ressources audio encore utilisées; le détail verbose montre des AudioStreamWAV/
Playback, aussi présents dans les tests existants. Le test GUI et le test de
routage, qui laissent le serveur audio terminer après libération de la scène,
quittent sans ces alertes. Ce n'est pas une mesure Android ni une preuve
d'accumulation entre parties.
