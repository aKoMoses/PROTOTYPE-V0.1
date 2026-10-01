# Sons des cinq modules — Stable Audio

**Lot initial rejeté par l'utilisateur.** Panier roquettes et Counter (`revisions/rocket-counter-v2/`) ont été validés puis intégrés localement : neuf fichiers identiques aux candidats écoutés. Résultat et vérifications : `integration.json`.

**Projector et Permutation sont également validés et intégrés** : huit effets Stable Audio dans `revisions/projector-permutation-v2/`. Les quatre modules représentent dix-sept sons approuvés, avec vérification des copies et des déclenchements. Aucun effet du lot initial n'est approuvé. Retour structuré : `review-feedback.json`.

**Éclipse : une seule proposition à écouter**, à la demande de l'utilisateur, dans `revisions/eclipse-v2/`. Explosion à l'arrivée, nouvelle source Stable Audio ; aucune intégration à ce stade.

L'archive du premier lot conserve 22 candidats produits avec **Stable Audio 3 Small-SFX local**. Les paragraphes suivants décrivent cette archive, pas les paires révisées.

| Module | Effets |
| --- | --- |
| Panier roquettes | Ouverture/armement, salve, propulsion, impact, destruction en vol |
| Counter | Garde, interception, surcharge obtenue, décharge à l'impact |
| Projector | Charge, départ de l'onde, répulsion, déclenchement automatique |
| Permutation | Envoi, déplacement de l'ombre, échange, bouclier |
| Éclipse | Préparation de la sélection, disparition, trajet, explosion à l'arrivée, bouclier après touche |

`index.html` propose cinq écoutes avec effets séparés, cinq enchaînements et un lecteur individuel pour chaque effet. `previews/*-isolated.wav` espace les effets dans l'ordre du tableau ; `*-scenario.wav` illustre leur enchaînement. Ce ne sont pas des enregistrements de gameplay.

`raw/` conserve les générations intactes de quatre secondes. `candidates/` contient les gestes utiles extraits, filtrés, fondus et ajustés en niveau. La propulsion des roquettes est une boucle discrète de 1,20 s avec raccord préparé ; les autres effets sont des gestes courts. L'écoute isolée ne répète cette boucle qu'une fois.

`sound-sheet.json` conserve les prompts, graines, paramètres et durées cibles. `manifest.json` conserve la provenance, les empreintes SHA-256, les intervalles extraits, les chronologies d'écoute et l'état de validation. Les durées sont calées sur les données actuelles : préparation roquettes 0,30 s ; garde Counter après 0,08 s ; cast Projector 0,18 s ; déplacement Éclipse 0,25 s. Le signal automatique Projector est proposé comme effet complet instantané.

`reports/` contient les logs de génération, les inspections strictes des accents, de la boucle et des aperçus, puis les contrôles d'intégrité. Ces contrôles ne remplacent pas ton écoute. Le contenu sonore et la synchronisation avec les animations en partie restent à valider.

Reproduction : lancer `generate.py`, `prepare.py`, puis `verify.py` avec `C:\Users\BOTTEROOOW\Tools\stable-audio-3\optimized\tflite\.venv\Scripts\python.exe`. Modèle et dépendances restent hors du dépôt. Aucun appel d'API payante.
