# Surfaces peintes et volumes sculptés — 2 octobre 2026

Passe graphique intégrée au projet local : duel classique, map test à plateformes,
terrain d'entraînement et survie. La palette garde le béton chaud, l'ivoire usé,
l'acier bleu, la rouille et les accents industriels cyan/ambre du jeu.

La référence Battlerite guide la hiérarchie des valeurs, les faces lisibles et le
caractère peint des matières. Stunlock décrit son objectif de couleurs vivantes
avec les personnages au centre de l'image dans son
[billet sur la direction artistique](https://blog.stunlock.com/v-rising-dev-update-3-art-mood/).
Cette passe adapte ces principes à la cour de récupération existante.

## Changements de cette réservation

- Béton : grain et micro relief atténués, grandes variations douces ; les marques,
  réparations métalliques et poussières de l'atlas conservent leur position.
- Décor opaque : grandes masses de lumière continues, faces supérieures chaudes,
  faces latérales plus froides, reflets limités et usure moins contrastée.
- Matières : pigments ivoire, acier bleu et rouille ; les anciens SVG métalliques
  utilisent les textures peintes déjà présentes dans la cour. Les surfaces
  auparavant plates reçoivent un grain discret sans changer leur couleur repère.
- Volumes : les blocs suffisamment épais reçoivent des chanfreins, avec 44 triangles
  par boîte et des maillages partagés par dimensions. Les volumes extérieurs et
  toutes les collisions restent identiques. Les couverts déjà sculptés gardent
  leur géométrie, avec de nouvelles finitions.
- Entraînement et survie : soleil chaud, ambiant froid, ombre directionnelle et
  remplissage léger. La qualité basse coupe les ombres ajoutées ; aucune lumière
  supplémentaire avec ombres. Les directeurs du duel conservent son éclairage.

Les ateliers, néons, végétation, robots, animations, HUD et effets de combat
font l'objet de réservations complémentaires dans d'autres conversations. Cette
livraison les conserve et ne revendique pas leur création.

## Intégration et limites techniques

`StylizedEnvironment` est un autoload qui finit les décors après leur construction.
Les surfaces sont remplacées sur les instances ; les ressources sources restent
intactes. Les matériaux et géométries identiques sont partagés. Les plateformes
créées plus tard héritent de la passe ; les références différées faibles permettent
de supprimer des objets ou de changer de scène sans callback vers un objet détruit.

Le filtrage conserve les acteurs, projectiles, matières transparentes/émissives,
billboards, végétation et marqueurs non éclairés. Aucun effet d'écran, fog global,
physique ou navigation supplémentaire. Les surfaces projetées en coordonnées du
monde s'appuient sur les vraies normales des chanfreins ; les micro normales UV
restent disponibles sur les surfaces qui disposent d'une base tangente.

Ressources : `scripts/environment/stylized_environment.gd`,
`shaders/stylized_salvage.gdshader`, `shaders/stylized_courtyard.gdshader`.
Une seule ligne d'intégration est ajoutée aux autoloads de `project.godot`.

## Vérification

Godot 4.7.2, Vulkan Mobile, RTX 3070 Laptop GPU. Exécutable local vérifié :
`C:\Users\Ben\Desktop\Prototype 0\Godot_v4.7.2-stable_win64_console.exe`.
Les chemins RomainOpen indiqués dans AGENTS.md sont absents sur ce PC.

- `tools/test_stylized_environment.gd` : 164 contrôles réussis, dont enveloppes,
  orientation des triangles, partage des ressources, application idempotente,
  plateformes créées après chargement, bascule des ombres et conservation des
  collisions/caméras/matières des joueurs et mannequins des trois scènes.
- Contrat complet du duel : 48 obstacles, 14 buissons, 4 kits, formes,
  transformations et caméra identiques avec la passe activée ou désactivée.
- Combat réel rendu sur six secondes : joueur et bot au sol, perception active,
  8 tirs, 8 projectiles échantillonnés, aucune assertion en échec.
- Captures examinées : cinq vues du duel avec caméra identique, plateformes,
  entraînement, survie et qualité basse en fenêtre 960×540.

Preuves dans `outputs/stylized-environment/` : `verified.log`, `live.json`,
`contract-baseline.json`, `contract-verified.json`, `final-metrics.json`,
`final-*.png`, `test-map.png`, `training-verified.png`, `survival-verified.png`,
`low-center.png`. Les captures `before-*.png` désactivent uniquement cette passe
avec l'argument de fixture `stylized-baseline`.

L'ancienne référence historique d'arène diffère sur deux réglages du suivi de
caméra modifiés par un autre travail ; le contrat actualisé et la comparaison
des cinq captures confirment que cette passe ne change pas la caméra. Les appels
de rendu des cinq vues restent identiques dans les captures comparées ; les
chanfreins ajoutent quelques triangles. Les captures ne prouvent pas un gain de
FPS soutenu, particulièrement avec plusieurs sessions Godot simultanées.

Android physique et APK non testés. Dans la sandbox, le certificat système,
l'écriture du cache GD-Sync et parfois du cache des shaders restent signalés ;
ces messages étaient présents avant la passe. Aucun échec de compilation des
nouveaux scripts/shaders ni callback vers un objet détruit dans les vérifications
finales. Aucun téléchargement ou nouveau bitmap généré pour cette réservation.

Réservation : `Prototype-Work: 5ab7d6ae-5d22-49c7-bc26-300b07134377`.
Travail local vérifié ; aucune publication GitHub annoncée.
