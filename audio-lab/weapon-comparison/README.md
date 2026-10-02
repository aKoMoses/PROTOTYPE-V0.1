# Comparaison Mekatana / Longshot

## Choix validé le 1er octobre 2026

**B / Stable Audio retenu pour le Mekatana et le Longshot.** Tous les prochains effets sonores doivent être produits avec Stable Audio, conformément à la préférence enregistrée de l'utilisateur.

`selection.json` conserve ce choix et les empreintes des dix effets retenus. `selected/` contient leurs copies intactes et les deux aperçus B. Ces fichiers sont sélectionnés, sans intégration au jeu à ce stade.

A = création originale par Codex, par synthèse et montage procéduraux. Aucun son du Blaster, Shotgun ou Mekatana existant n'est réutilisé.
B = Stable Audio 3 Small-SFX, runtime officiel optimisé TFLite local. Dix sources originales de quatre secondes ; prompts, graines et paramètres dans `stable-requests.json`.

## Écoute

- `previews/mekatana-A.wav` / `mekatana-B.wav` : trois coups à vide, puis trois avec impacts.
- `previews/longshot-A.wav` / `longshot-B.wav` : quatre tirs normaux, disponibilité, cinquième tir renforcé.
- `index.html` : comparaison avec lecteurs et écoute individuelle des 20 effets.

Durées de préparation Mekatana : 0,12 / 0,14 / 0,18 s. La séquence d'audition espace volontairement les coups pour les distinguer ; ce n'est pas une capture sonore de partie.
Cadence Longshot : 1,05 s. Le signal de disponibilité est une proposition nouvelle, pas un branchement existant.

## Conservation et vérification

- `raw/local` : sources originales de la version A.
- `raw/stable` : générations B intactes.
- `candidates/A-codex` / `candidates/B-stable` : gestes courts, filtrage, fondus et niveau RMS A/B équilibré par événement, avec marge avant saturation.
- `manifest.json` : provenance, intervalles extraits, chronologie des aperçus et empreintes SHA-256.
- `reports/strict-final.json` : contrôle des 20 effets et des quatre aperçus avec `inspect_sfx.py --kind accent --strict`.
- `reports/package-verification.json` : durée, niveaux comparables, début audible et intégrité des fichiers.

Ces contrôles vérifient les fichiers et leur préparation, pas leur qualité esthétique. L'utilisateur a écouté et retenu B pour les deux armes ; la synchronisation avec les animations en partie reste à valider. Aucun fichier de gameplay ou son intégré n'a été modifié.

Reproduction du comparatif historique : `generate_stable.py`, puis `build_comparison.py`, puis `verify_package.py`. Les deux premiers scripts utilisent le Python du runtime TFLite local ; l'inspection utilise le runtime PyTorch déjà installé. La sélection B/B reste conservée séparément dans `selection.json` ; les nouvelles productions suivent la préférence Stable Audio.
