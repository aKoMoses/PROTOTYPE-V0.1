# Candidats sonores des pièges du duel

## Sélection utilisateur

Les choix retenus sont **B / A / B / A** : avertissement de dalle B, décharge A,
armement du canon B, salve A. Le lot prêt pour l’intégration est dans `selected/` ;
`selection.json` donne les sources, durées et empreintes. Les six fichiers sont
identiques aux candidats vérifiés : trois avertissements/activations, un tir
isolé, une salve de deux tirs et une salve de trois tirs. L’aperçu de cet ensemble
est `previews/sequence-selected.wav`. Aucun script de gameplay n’a été modifié.

Production locale uniquement. Aucun fichier de gameplay modifié, aucun son intégré,
aucun commit ou push effectué. Ouvrir `index.html` pour écouter et choisir A/B
indépendamment pour les quatre événements. Les deux séquences de 6,4 s sont dans
`previews/` et restent utilisables directement comme WAV.

| Événement prévu | Candidats A et B | Durée |
| --- | --- | --- |
| `trap_tile_warning` | `candidates/tile-warning-{A,B}.wav` | 0,59 / 0,72 s |
| `trap_tile_discharge` | `candidates/tile-discharge-{A,B}.wav` | 0,58 s |
| `trap_cannon_warning` | `candidates/cannon-warning-{A,B}.wav` | 0,97 / 0,75 s |
| `trap_cannon_salvo` | `candidates/cannon-salvo-{2,3}-{A,B}.wav` | 0,49–0,74 s |

Les tirs isolés `cannon-shot-{A,B}.wav` sont aussi conservés pour une future
intégration précise au moment de chaque projectile. Les salves ont des départs
espacés de 0,24 s. L’aperçu complet utilise trois tirs, avec 1,6 s entre
l’avertissement et l’activation de chaque piège.

Directions : A vise un atelier pneumatique, avec des gestes plus sourds ; B vise
les relais électriques, avec un vibreur bref et des gestes plus secs. Les sources
proviennent de Stable Audio 3 Small SFX, génération CPU locale, 8 étapes,
CFG 1 et graines enregistrées. Aucun timbre musical ajouté.

Les générations de quatre secondes restent dans `raw/`. La première alerte B,
réduite presque à un clic au lieu de la forme attendue, reste dans
`raw/tile-warning-B-v1.wav` ; elle n’est pas proposée. Les grains ont été extraits,
filtrés doucement, fondus et rapprochés en énergie entre A/B pour chaque événement.
Les WAV candidats sont stéréo, PCM 16 bits, 44,1 kHz. Les crêtes restent au plus
à −6,5 dBFS. Il n’y a ni échantillon écrêté ni valeur non finie.

## Vérifications

- `reports/technical-integrity.json` : formats, durées, gains, SHA-256 et intervalles sources.
- `reports/strict-candidates.json` : les douze candidats passent `inspect_sfx.py --kind accent --strict`.
- `reports/strict-previews.json` : contrôle des deux séquences sans répétition parasite.
- `sound-sheet.json` : causes visibles, fonction de chaque son, associations visées et exclusions.

L’intégrité technique ne valide pas l’esthétique, la lisibilité ou la fatigue.
Les choix utilisateur sont enregistrés dans `selection.json` ; l’écoute avec le
combat réel et les visuels reste à faire. Le rapport initial des candidats conserve
son état avant sélection. Le lot choisi porte le statut
`user-selected-awaiting-gameplay-integration`. Les fichiers demeurent hors des
ressources du jeu grâce à `.gdignore`.

Pour reproduire : lancer `generate_candidates.py` avec le Python du runtime TFLite
installé, puis `polish_candidates.py`. Le premier conserve les sources existantes.
Le second réécrit les candidats et les aperçus depuis les grains documentés.
Après une régénération, refaire les deux contrôles stricts avant de présenter les sons.
