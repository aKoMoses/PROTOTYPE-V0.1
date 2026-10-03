# Musiques des cartes 4, 5 et 6

Les choix approuvés sont intégrés dans `art/audio/maps/` :

| Carte | Sélection | Combat initial | Combat après 30 secondes |
| --- | --- | --- | --- |
| Héliostat | 4A, première série | 4C, série combat | 4A, série combat |
| Serre engloutie | 5B, première série | 5C, série combat | 5A, série combat |
| Cœur d'horloge | 6A, première série | 6A, série combat | 6B, série combat |

Le thème de sélection continue pendant la préparation et le compte à rebours.
Au début du combat, il disparaît avec un court fondu et la piste de combat
démarre immédiatement. Chaque round repart sur sa piste initiale. Le temps
de combat actif alterne les deux pistes toutes les 30 secondes : initiale,
seconde, initiale à une minute, puis seconde à une minute trente. Une pause
ou l'écran de résultat ne fait pas avancer cette alternance.

`scripts/arena_music.gd` pilote ce parcours depuis `scripts/game_flow.gd`.
Les autres cartes et les matchs en ligne conservent leur musique existante.
Les fichiers de jeu durent 30 secondes, en stéréo PCM 16 bits à 44,1 kHz,
avec raccord de boucle et compression à l'import Godot.

Les deux séries d'audition et leurs sources sont conservées dans
`audio-lab/map-music-previews/` et `audio-lab/map-combat-music/`.
La première série sert au menu ; la seconde contient les propositions de
combat plus rapides. `selection.json` associe chaque fichier intégré à son
choix et à son empreinte. `prepare_game_audio.py` reproduit les extraits,
niveaux et raccords sans changer la vitesse. Le `.gdignore` du laboratoire
garde les sources et les extraits d'audition hors des exports du jeu.

`tools/test_arena_music.gd` vérifie les trois cartes, la continuité de la
sélection, le départ au combat, les pauses, les seuils de 30 et 60 secondes,
la boucle audio, le résultat et la remise à zéro au round suivant. Ces
contrôles techniques complètent les choix d'écoute approuvés par l'utilisateur.
