# Reprise centrée sur Panier roquettes et Counter

Le lot initial est rejeté. Cette seconde passe contient neuf effets Stable Audio 3 Small-SFX : cinq pour le panier et quatre pour Counter. L'utilisateur les a validés puis a demandé leur intégration, réalisée localement. Les copies installées sont identiques aux fichiers écoutés (SHA256), avec tests de déclenchement, interruption, propulsion, impacts, parade et surcharge. Voir `../../integration.json`. Projector et Permutation sont également validés et intégrés ; Éclipse reste à préparer.

## Intention sonore

- Panier : faire entendre la masse du rack et sa glissière, la poussée des roquettes, leur combustion en vol, puis distinguer une cible frappée d'une carcasse détruite avant l'impact.
- Counter : un geste de fermeture, le choc arrêté, l'énergie absorbée sous forme d'aspiration/crépitement irrégulier, puis cette énergie rendue brutalement au contact.
- L'armement et la surcharge n'emploient pas un signal aigu de notification. L'enveloppe naturelle de chaque source est conservée ; seule une courte protection des bords est appliquée. Aucun son du lot précédent ou des armes validées n'est recyclé ici.

## Écoute et limites

`index.html` présente deux enchaînements et les neuf sons individuels, avec l'action que chacun cherche à transmettre. `previews/*-scenario.wav` rassemble les étapes ; `*-isolated.wav` les espace pour l'écoute.

Les sources complètes restent dans `raw/` ; les gestes préparés dans `candidates/`. `sound-sheet.json` conserve prompts/graines/paramètres. `manifest.json` conserve extraits, gains, provenance, empreintes et séquences. Les accents faibles sont refusés plutôt que fortement amplifiés : RMS source minimal et gain limité à +10 dB. Les inspections et contrôles d'intégrité sont dans `reports/`.

L'utilisateur a accepté cette paire après écoute. Les neuf effets sont intégrés et les tests automatisés des modules passent. L'écoute en situation de jeu avec les animations et un essai réseau sur deux PC restent non effectués.
