# Ambiance sonore du garage

Trois sons Stable Audio 3 Small-SFX, approuvés après l'écoute de la maquette
avec la musique, sont intégrés dans `art/audio/garage-ambience/`.

- `ventilation.wav` : fond doux en boucle, à -49 dBFS RMS.
- `pressure.wav` : petit relâchement de pression, à -42 dBFS RMS.
- `metal.wav` : contact métallique distant, à -43 dBFS RMS.

Les niveaux sont inscrits dans les fichiers : les lecteurs jouent à 0 dB et
l'import ne normalise pas les ressources. La musique existante et son gain
restent inchangés. Les sons ambiants passent par le bus `Effects` et suivent
le réglage « Effets sonores ».

`scripts/forge_ambience_audio.gd` démarre le fond progressivement sur 1,5 seconde
lorsque le garage devient visible. Un accent arrive après un délai aléatoire
de 10 à 18 secondes ; deux accents identiques ne se suivent pas. Pendant les
installations, les accents s'arrêtent et leur prochain délai est repoussé,
tandis que la ventilation très faible reste présente.

Masquer le garage ou son parent arrête immédiatement les lecteurs. La prochaine
ouverture recommence avec une entrée douce et un nouveau délai. Fermer le
garage libère les lecteurs ; aucun lecteur global supplémentaire n'est créé.

Les sources, les graines, les prompts, les extraits approuvés et la sélection
restent dans `audio-lab/garage-ambience/`. Ce répertoire est ignoré par Godot.

Vérification ciblée avec Godot 4.7.2 : import des ressources, test de visibilité,
boucle, délais, suppression pendant les installations, libération des lecteurs,
enregistrement du mixeur et régression des contacts d'installation.
L'acceptation porte sur la maquette écoutée ; aucune vérification Android ni
publication n'est effectuée pour cette intégration locale.
