# Ambiance discrète du garage — proposition à écouter

Trois sources produites avec **Stable Audio 3 Small-SFX**, moteur officiel local
optimisé TFLite, huit étapes, CFG 1. Aucun son de synthèse procédurale.
Les sources brutes, les grains préparés et les extraits sont séparés.

- Ventilation diffuse du hangar, filtrée et préparée pour une boucle douce.
- Bref relâchement de pression pneumatique hors champ.
- Petit contact métallique sur un établi voisin, hors champ.

`previews/garage-musique-et-ambiance.wav` dure 36 secondes. Les six premières
secondes contiennent uniquement la musique existante, puis le fond s'installe
progressivement. Souffles ponctuels à 11 et 31 secondes ; contact à 21 secondes.
La musique garde son gain de jeu de -14 dB. Le fond est à -49 dBFS RMS ; les
deux accents sont à -42 et -43 dBFS RMS. Les niveaux exacts et les empreintes
des fichiers sont dans `reports/preparation.json`.

`previews/ambiance-seule-amplifiee.wav` facilite l'écoute des trois détails,
sans musique, avec un gain supplémentaire de 14 dB destiné seulement à l'audition.

## État après sélection

Les contrôles automatiques des sources vérifient le format, la dynamique et
l'absence de saturation ou de répétition régulière suspecte. Ils ne constituent
pas une acceptation sonore. L'utilisateur a approuvé le dosage proposé avec la
musique et demandé l'intégration. `selection.json` conserve cette sélection et
les empreintes des sons intégrés. Les associations désirées et interdites sont
consignées dans `sound-sheet.json`, qui conserve l'état initial de la proposition.

Les trois candidats sont maintenant intégrés localement dans le garage, sur le
bus Effects, avec arrêt à la fermeture et accents espacés sans concurrence avec
les installations. Voir `docs/garage-ambience.md`. **Aucune publication**.
`reports/preparation.json` décrit la maquette au moment de sa production et
conserve donc son ancien état « non intégré ».

## Reproduction

Exécuter `generate.py`, puis `prepare.py` avec le Python du runtime Stable Audio
local installé. Les générations existantes sont conservées. Le premier programme
consigne prompts et graines ; le second produit les candidats, les extraits et
le rapport de vérification. Le fichier `.gdignore` évite d'importer cette
maquette et ses sources brutes comme ressources de jeu.
