# Ambiances environnementales — cartes 4, 5 et 6

Création locale du 3 octobre 2026 avec **Stable Audio 3 Small-SFX**, moteur officiel optimisé TFLite déjà installé. Aucune modification du jeu ni intégration des sons. La direction artistique est validée ; les sons générés restent à écouter.

## Écoute

Ouvrir la page servie à `http://127.0.0.1:8774/`. Les trois extraits complets durent 45 secondes ; le fond seul est également disponible. Chaque couche et chaque mécanisme possède son lecteur et son fichier WAV.

- Carte 4, **Héliostat** : vent chaud, collecteurs solaires, métal qui chauffe, miroir et souffle solaire.
- Carte 5, **Serre engloutie** : eau, feuillage, pompe, goutte et barge flottante.
- Carte 6, **Cœur d’horloge** : engrenages, battement grave, cliquet, balancier, abri pivotant et vibration de laiton.

Les événements des maquettes sont illustratifs. Leur déclenchement et leur synchronisation avec les mécanismes visibles restent à vérifier en jeu après l’écoute. Les propositions musicales sont traitées dans le chat séparé « Bandes sonores des cartes 4, 5 et 6 ».

## Livrables et provenance

- `raw/` : 16 sources originales Stable Audio conservées sans transformation.
- `candidates/` : 6 couches bouclables et 10 sons ponctuels, stéréo PCM 16 bits à 44,1 kHz.
- `previews/` : 3 ambiances complètes et 3 écoutes du fond seul.
- `sound-sheet.json` et `design.py` : sources, prompts, graines et réglages de génération.
- `manifest.json` : intervalles extraits, fondus, gains, horaires illustratifs et empreintes SHA-256.
- `semantic-review.md` : feuille d’écoute, décisions en attente ; aucune écoute en image présumée.
- `reports/` : journaux de génération et inspections strictes des sources préparées et des extraits.

Une génération par son, 8 étapes, CFG 1.0. À CFG 1.0, le moteur n’applique pas la branche négative : les exclusions essentielles sont donc aussi décrites dans les prompts positifs. Aucun changement de hauteur ni de vitesse. Les fonds reçoivent un raccord par fondu de 1,25 seconde, les accents un extrait court avec fondus et silence final. Les niveaux des couches et des extraits sont ajustés sans écrêtage.

La présence de `.gdignore` garde ces essais hors de l’import Godot. Aucun fichier audio existant n’est remplacé.

## Vérification

`inspect_sfx.py --strict` : **16/16 candidats** et **6/6 extraits** réussis. Les 22 lecteurs de la page ont chargé leur durée correcte, sans erreur média dans le navigateur Codex. L’ouverture des sons séparés est vérifiée. Ces contrôles ne valent pas une écoute artistique ni une validation du mix pendant un combat.

## Reproduire

Depuis la racine du dépôt, dans PowerShell :

```powershell
& 'C:\Users\BOTTEROOOW\Tools\stable-audio-3\optimized\tflite\.venv\Scripts\python.exe' audio-lab/map-ambiences/generate.py
& 'C:\Users\BOTTEROOOW\Tools\stable-audio-3\optimized\tflite\.venv\Scripts\python.exe' audio-lab/map-ambiences/prepare.py
& 'C:\Users\BOTTEROOOW\Tools\stable-audio-3\optimized\tflite\.venv\Scripts\python.exe' -m http.server 8774 --bind 127.0.0.1 --directory audio-lab/map-ambiences
```

La génération conserve les sources déjà présentes. Les décisions d’écoute restent explicitement en attente ; ne pas intégrer automatiquement les candidats sur la seule base du rapport technique.
