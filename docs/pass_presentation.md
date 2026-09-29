# Présentation, animation, VFX et audio — passe complète

Référence : `8c05902`, branche `v02-match-pass`. Vérifications Godot 4.7.2 officiel, renderer Mobile/Vulkan, RTX 3070 Laptop. Tests sous APPDATA isolé `.godot/pass-user-presentation*` ; aucune sauvegarde du joueur modifiée.

## Inventaire inspecté et contrat conservé

- Joueur : GLB mécanique à 65 os, neuf clips importés (`idle`, `walk`, `run`, `fire`, `fall`, `warm_up`, `bow`, `box_01`, `afraid`). Correction d'axe unique +Z vers −Z. AnimationTree locomotion, pose basse, pose de visée ; modificateurs de jambes, recul et main gauche. Les ressources originales sont dupliquées avant les adaptations runtime.
- Blaster et Shotgun : arme attachée à la main droite, marqueurs de prise droite/gauche et de bouche. La simulation conserve sa direction autoritaire, ses origines, collisions, dégâts, cadence, cône et projectile. La tenue/transitions restent uniquement visuelles. Le délai préexistant d'un premier tap jusqu'à `skeleton_updated` est couvert par la régression et n'est pas modifié par ce lot.
- Droid : 65 os, dix clips d'origine ; marche/course avant et arrière, strafe, visée, recul, dégâts, mort et reset. Pose résolue après l'AnimationTree manuel, sans événements d'animation appliquant des dégâts.
- VFX : flash de bouche attaché, projectile appartenant à la simulation, tracer, impact métal/environnement/robot/bouclier, étincelles, fumée, decals, flash de dégâts ; budgets et pool existants. Aucun objet de gameplay n'est retiré par le budget visuel.
- Statuts BURN/SLOW/STUN/SPOTTED : particules localisées, anneau froid discontinu, arcs électriques, marqueurs tactiques. L'état fourni par CombatState détermine leur présence ; aucun timer de statut supplémentaire.
- Audio : neuf événements GameSfx avec huit WAV sélectionnés, sons locaux des armes/charges/modules, musique/menu/compte à rebours/résultat. Assets, volumes, polyphonie et intervalles existants conservés.

## Défauts reproduits et changements

**STUN : arcs affichés en continu entre deux impulsions.** `_stun_remaining` atteignait bien zéro mais la visibilité était mise à jour uniquement à l'arrivée de l'impulsion suivante. Le nom `IntermittentArcs`, le timer court existant et l'agrandissement du symbole uniquement pendant l'impulsion établissent la présentation attendue. La visibilité est désormais recalculée à chaque frame. L'indicateur STUN demeure actif dans les intervalles, et la durée/efficacité du contrôle est inchangée. Le test atteint un intervalle calme de manière déterministe : échec avant, succès après.

**Voix GameSfx périmées lors des transitions.** L'autoload survivait à la scène et n'exposait aucun nettoyage. Ajout de `clear()` pour arrêter toutes ses voix au reset/navigation, libérer l'état `stream_paused` et l'historique de throttling de l'ancienne partie. Ajout de `set_paused()` pour préserver les voix en reprise et refuser les demandes de son arrivées pendant la pause. Godot suspend déjà nativement l'audio hérité lorsque SceneTree est en pause : ce comportement natif n'est pas présenté comme un bug corrigé. L'intégration aux écrans, modes et `main.clear_transient_fx()` est réalisée dans le lot principal/modes.

**Captures du premier tir prématurées.** L'outil VFX prenait le screenshot immédiatement après une fonction pouvant attendre la mise à jour de squelette : le flash n'avait pas encore été créé. L'outil attend désormais la présence du flash réellement émis. Il gèle uniquement le manager de présentation pendant la prise d'image pour qu'une latence de capture GPU ne fasse pas disparaître un flash de 65 ms. Les timings et dégâts du jeu livré ne sont pas modifiés.

## Vérifications exécutées

| Vérification | Résultat observé |
| --- | --- |
| `test_presentation_lifecycle.gd` | 14 contrôles PASS ; impulsion/gap/reprise/clear STUN, pause/reprise/refus de demande/clear audio/premier son nouvelle manche |
| `test_player_visual_rig.gd` | 299 contrôles PASS ; sockets, transitions basse/visée/tir, strafe, marche arrière, premiers taps, reset et dix tirs alternés |
| `test_player_aim_core.gd` | PASS ; dix tirs normaux/chargés, changement de mouvement et de direction ; erreur maximale de recul 0,742504°, dérive après récupération 0,000017°, erreur main gauche ≤0,00000013 m |
| `test_enemy_droid_visual.gd` | 510 contrôles PASS ; 216 cas de visée, hauteur/direction/vitesse/strafe ; erreur maximum bouche 0,039565°, sockets sans dérive, ressources originales inchangées |
| `test_vfx.gd` | 73 contrôles PASS ; expiration, statuts combinés, réapplication, nettoyage, normes de contact, projectiles conservant 400 dégâts sous pression du budget |
| Stress VFX qualité normale | 180 s simulées ; pic 34 actifs, 24 decals, 5 émetteurs ; plateau 113 → 113 nœuds |
| Stress VFX qualité basse | 180 s simulées ; pic 20 actifs, 12 decals, 5 émetteurs ; plateau 101 → 101 nœuds |
| `test_game_sfx.gd` | PASS ; événements modules/impact/dégâts/destruction depuis le jeu réel |
| Analyse WAV | 16 sources PCM16 analysées ; zéro échantillon au rail, pics de −24,13 à −1,18 dBFS ; mesures `pass_audio_source_levels.json` |

Ces suites ne changent pas les règles d'action. Les budgets restent ceux du dépôt. Aucun pooling, cache, simplification de physique ou changement de fréquence d'IA n'est ajouté.

## Inspection graphique exécutée

Captures réelles Vulkan, 1280×720 :

- `captures/pass_complete/before/stun/` et `after/stun/` : même seed et script, frames à 10 ms, intervalle calme, impulsion suivante, clear. La capture `02_quiet_gap_detail.png` montre nettement les arcs persistants avant et leur absence après. Les images sans suffixe `_detail` emploient la caméra de jeu inchangée ; les images `_detail` sont des gros plans de contrôle.
- `captures/pass_complete/after/vfx/` : 27 images de blaster normal/chargé, shotgun, tir en déplacement, impact/decal sur trois surfaces, quatre statuts séparés/associés puis expiration. Inspection native du flash chargé, de BURN et des statuts associés : palettes cyan/orange cohérentes, effets localisés qui gardent les cibles et couverts lisibles.
- `captures/pass_complete/after/animation/` : sept étapes ready/locomotion/visée opposée/tir/hold/shotgun/retour. Inspection native des prises en main et des jambes/torse en visée opposée : attachements fixes et clip de locomotion conservé. Les images sont des échantillons ; la continuité temporelle est contrôlée par les suites de poses ci-dessus et par la séquence vidéo du lot principal.

Le chevauchement du long nom du bot avec son arme/PV a été corrigé dans `combat_readout.gd` avec le lot interface/HUD. Les noms complets `HARCELEUR · BLASTER` et `ASSAILLANT · SHOTGUN` occupaient auparavant 214/231 px dans une zone de 170 px et recouvraient la bobine/les cartouches puis les PV. Le nom et l'arme sont maintenant deux labels séparés dans le bandeau de 34 px ; la bobine/les cartouches occupent le logement inférieur existant. Un premier essai de Label à deux lignes a été rejeté visuellement : son minimum de 43 px masquait la ligne d'arme derrière la barre de vie. Le résultat final sépare les baselines, garde tous les textes et ne déplace ni l'acteur ni la caméra.

`tools/capture_combat_readout.gd` produit la comparaison déterministe `captures/pass_complete/before/readout/` et `after/readout/` : deux identités longues et les quatre statuts simultanés, fenêtres demandées 1280×720, 1600×720 et 960×720, stretch de production conservé. Chaque image de jeu dispose d'un `_detail.png` natif du SubViewport 300×108, sans changement de caméra. Les détails montrent le nom/arme/PV complets et les deux cartouches pleines sur trois du Shotgun. L'alignement bas du label de statuts du lot principal maintient ses quatre lignes au-dessus de la plaque, sans recouvrement. Les textes de statut restent petits à la plus faible résolution ; les marqueurs STUN/SPOTTED et l'anneau SLOW restent distincts.

La séquence d'animation réelle de 131 frames à 60 FPS du lot principal est disponible dans `exports/pass_complete/weapon_locomotion.avi`, en complément des sept étapes inspectées.

## Limites et diagnostic de sortie

- Les performances mesurées ici sont des nombres d'objets et un stress de durée simulée sur PC ; aucun résultat CPU/GPU Android n'est revendiqué.
- Vérification des niveaux WAV et des événements audio, sans écoute humaine sur haut-parleurs mobiles. Les niveaux de plusieurs sons superposés et l'écoute subjective restent à vérifier sur appareil.
- Certains anciens tests quittent le moteur immédiatement après `AudioStreamPlayer.stop()` et signalent des `AudioStreamPlaybackWAV`/`AudioStreamWAV` encore référencés. Le diagnostic `--verbose` établit leur nature. Une attente de 100 ms dans le harness après nettoyage laisse passer le mixer et supprime entièrement ces messages dans la nouvelle régression ; aucun délai n'est ajouté au gameplay.
- Avertissement système CA store de cet environnement Windows : le moteur charge ses certificats embarqués. Les erreurs SDK GD-Sync des anciens harness sans scène synchrone sont traitées par le lot réseau.
- Aucun original GLB, profil de combat, hitbox, collider, objet tactique, portée audio, volume enregistré, mapping, cadence ou timer de simulation modifié dans ce lot.
