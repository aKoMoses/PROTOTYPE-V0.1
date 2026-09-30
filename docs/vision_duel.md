# Brouillard de guerre, halo et dernière observation

La vision comporte deux rayons autour du combattant, sur le plan du sol :

- jusqu'à 14 unités, la carte et l'adversaire restent pleinement lisibles ;
- entre 14 et 22 unités, le brouillard assombrit progressivement la carte et
  l'adversaire devient une silhouette sombre, désaturée et translucide ;
- hors du rayon extérieur ou derrière un mur, la carte reste sombre et la
  position actuelle de l'adversaire est cachée.

Le halo conserve suffisamment d'opacité pour reconnaître la silhouette. Les
PV, statuts et nombres de dégâts s'effacent plus vite que le corps. Les deux
dernières unités atténuent ensuite la silhouette jusqu'à zéro, sans saut à la
limite. Les transitions en mouvement sont lissées dans le temps. La hauteur
d'un saut ne réduit pas le rayon.

À la perte de vue, une silhouette figée de la dernière observation s'efface
pendant 0,55 seconde. Sa position et sa pose restent celles réellement vues :
elle ne suit jamais un adversaire qui se déplace derrière un mur ou hors du
rayon. Ce bref écho apporte une transition visuelle sans révéler son mouvement.
Une nouvelle observation ou une remise à zéro de l'adversaire efface l'écho.

Les murs et les buissons conservent leurs règles de dissimulation. EN COMBAT
et SPOTTED révèlent dans les buissons, mais ne permettent pas de voir derrière
un mur ou au-delà de 22 unités. L'IA et le suivi utilisent la visibilité réelle,
indépendamment du lissage et de l'écho. Les collisions et les projectiles
continuent de fonctionner hors de vue. Le brouillard est actif pendant une
manche de duel local ou en ligne.

En duel, la petite carte en haut à droite montre le joueur en cyan, son rayon
de vision et l'adversaire observé en rouge. Après une perte de vue, la dernière
position observée devient un repère orange creux : son halo s'élargit et son
opacité diminue pendant sept secondes. Il reste immobile même si l'adversaire
caché se déplace. Un adversaire jamais observé n'apparaît pas sur la carte.
Une nouvelle manche, un retour au menu ou une mort effacent cette mémoire ;
une pause la suspend.

## Réglages

Les propriétés `vision_radius` et `vision_fade_width` sont exposées dans la
catégorie **Vision** des scripts `player.gd` et `target_dummy.gd`. Le rayon
extérieur vaut 22 unités et la largeur du halo 8 unités. Le rayon intérieur
est calculé par `vision_radius - vision_fade_width`. Les valeurs par défaut
et les courbes de présentation sont centralisées dans `visibility_state.gd`.
La portée appartient à l'observateur et peut être ajustée par combattant.

`get_visibility_weight(observer)` fournit la visibilité réelle : 1 à 14 unités,
0,5 à 18 unités et 0 à 22 unités. Un mur ou un buisson dissimulant la cible
la ramène immédiatement à zéro. `get_presentation_visibility_weight()` fournit
l'opacité du corps après lissage. `VisibilityFade` assombrit les matériaux et
compose le fondu des détails avec les animations des effets et des dégâts,
sans modifier les matériaux partagés. `VisibilityEcho` conserve le dernier
modèle observé. `FogOfWar` utilise les rayons du joueur et les murs pour rendre
le masque de vision dans la caméra active.

Les ombres des couverts sont converties en opacité sur une grille fixe du
monde avant le fondu. La transition mélange les opacités, sans allonger les
rayons entre le bord d'un mur et le fond de la carte. Un filtrage dans les deux
directions arrondit les contours ; une faible irrégularité ancrée au décor
leur donne un aspect plus organique. Le mouvement de la caméra ne déplace
pas ce motif. Les règles de visibilité des acteurs restent indépendantes
de cet adoucissement visuel.

## Vérification

`tools/test_sight_range.gd` couvre la portée, les murs, les buissons, le halo,
la frange extérieure, le lissage, l'écho figé (squelette et arme), son expiration
et sa suspension pendant une pause du SceneTree, les matériaux
des effets, l'IA et la mémoire du suivi. Il vérifie aussi le masque physique du
brouillard et son activation en duel local et en ligne, ainsi que l'absence
d'écho hérité du menu ou du compte à rebours. Les fixtures de gameplay
conservent des vérifications indépendantes des seules couleurs de présentation.

Validation du 30 septembre 2026 : les 100 vérifications du script dédié
réussissent avec Godot 4.7.2 en mode headless. Sept scripts de régression
réussissent également (visibilité, buissons, duel, présentation, pause, réseau
et survie). Les captures de `captures/fog_of_war/` ont été inspectées avec
Vulkan / Forward Mobile. Le relevé est conservé dans
`docs/fog_of_war_validation.json`.

La passe visuelle suivante ajoute 17 contrôles du brouillard : continuité
autour d'un coin, absence de scintillement à l'arrêt, fondu fixé au décor et
remises à zéro de l'historique. Les comparaisons animées, réalisées sur le
même trajet avec une caméra fixe puis la caméra de jeu, se trouvent dans
`captures/fog_organic/`. Le relevé de cette passe est conservé dans
`docs/fog_organic_validation.json`.

`tools/capture_sight_range.gd` produit les états suivants dans l'arène réelle,
avec une caméra de vue d'ensemble et le brouillard activé :

- `full` : adversaire entièrement visible à 14 unités ;
- `halo` : silhouette atténuée à 18 unités ;
- `fringe` : fin du fondu à 21 unités ;
- `lost` : adversaire hors de portée, bref écho et dernière position mémorisée ;
- `wall_echo` : adversaire derrière NorthWestBlock, écho figé dans sa dernière
  position visible.

Les anciens noms `visible` et `fade` restent acceptés pour les captures.
L'argument `mobile` conserve la simulation du format tactile sur PC ; cette
simulation ne constitue pas un test sur téléphone.

Lancer les vérifications avec les chemins absolus du projet et de Godot :

```powershell
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\RomainOpen\perso\Studio\game-source' --script res://tools/test_sight_range.gd
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path 'C:\RomainOpen\perso\Studio\game-source' --script res://tools/capture_sight_range.gd -- 'res://captures/sight_range/halo.png' halo
```
