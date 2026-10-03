# Complément des sons de combat

27 candidats Stable Audio 3 Small-SFX, générés localement avec le runtime
officiel optimisé TFLite. Une génération de quatre secondes par geste ; les
grains conservent l’enveloppe de la source avec découpe et fondus courts.
Les trois premières sources rejetées restent dans `raw/`, et les alternatives
utilisent de nouvelles graines et des prompts précisés.

Ouvrir `index.html` pour les séquences des douze familles et chaque son séparé.
Les 27 sons sont intégrés au jeu local à la demande de l’utilisateur.
`sound-sheet.json` conserve les intentions et les graines ; `manifest.json`
conserve les sources, intervalles extraits, niveaux et empreintes SHA-256.
`reports/` contient les contrôles stricts et les journaux de génération.

La correction du terrain d’entraînement place un AudioListener3D sur le robot.
La caméra, distante de 20,73 m après son recalage, atténuait fortement les sons
spatialisés ; les roquettes pouvaient sortir de leur portée audible en vol.
La salve réelle est testée par `tools/test_training_audio.gd`, avec enregistrement
du mix via le pilote WASAPI dans `reports/training-rockets-recorded.wav`.

Les dix sons déjà sélectionnés du Mécakatana et du Longshot sont copiés à
l’identique dans `art/audio/weapon-sfx/` et intégrés. `delivery.json` conserve
la vérification de cette intégration locale. Les nouveaux sons sont dans
`art/audio/combat-sfx/`, déclenchés par les actions, impacts acceptés et fins
d’effets ; les passifs disposent de limites de répétition par robot.
Les charges s’arrêtent lors d’une annulation, et les résultats de combat sont
rejoués depuis l’hôte sur les clients réseau.

Vérification : `python audio-lab/combat-completion/check_runtime.py`, puis
`python audio-lab/combat-completion/verify_delivery.py`. Le test dédié exerce
les 27 événements via les callbacks de jeu, ainsi que l’annulation, le soin à
pleine santé, les contacts multiples et la validation des messages réseau.
L’option Godot `-- --record` avec le pilote WASAPI enregistre le mix réel dans
`reports/combat-completion-recorded.wav`.
Sur cette dernière exécution, WASAPI n’a pas pu ouvrir le périphérique de sortie.
Le test des 27 déclenchements passe ; la capture de secours avec le pilote muet
ne constitue pas une validation audio. `reports/combat-mixer.json` le signale.

`produce.py` reste la recette de génération originale : la relancer prépare
un nouveau lot de candidats et remet leur statut d’écoute à zéro. L’autorisation
d’intégration ne constitue pas une confirmation d’écoute artistique.
