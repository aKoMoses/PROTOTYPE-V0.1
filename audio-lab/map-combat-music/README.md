# Musiques de combat des cartes 4, 5 et 6

Cette série contient neuf propositions Stable Audio et leurs extraits d'écoute
de 30 secondes. Les choix approuvés pour le début du round sont **4C, 5C et 6A**.
Les secondes pistes sont **4A, 5A et 6B**, issues de cette même série de combat.
Elles prennent le relais après 30 secondes de combat actif ; à une minute,
la piste initiale revient. L'alternance continue ensuite toutes les 30 secondes.

La première série, dans `../map-music-previews/`, fournit les thèmes de sélection
4A, 5B et 6A. Les identifiants se répètent entre les deux séries : leurs fichiers
et leurs usages sont distincts. Les neuf fichiers intégrés au jeu sont décrits
dans [la documentation des musiques](../../docs/arena-music.md).

- `raw/` conserve les sources originales de combat.
- `previews/` contient les extraits de comparaison et `preview.html` leur lecteur.
- `manifest.json` consigne les prompts et les réglages de génération.
- `selection.json` associe les pistes retenues aux fichiers du jeu et à leurs empreintes.
- `generate.py` produit les propositions ; `inspect_rhythm.py` décrit leur rythme.
- `prepare_game_audio.py` prépare les neuf fichiers du jeu et leurs raccords de boucle.

Le `.gdignore` du dossier parent exclut tout le laboratoire des imports et
exports Godot. Les sons du jeu se trouvent dans `art/audio/maps/`.
