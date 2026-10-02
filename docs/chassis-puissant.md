# Châssis puissant orange

Le châssis `puissant` utilise maintenant `art/player_mecha_puissant.glb`,
copié depuis le modèle orange fourni le 2 octobre 2026. Le fichier conserve
ses textures, son squelette de 65 os et ses 97 animations.

La sélection du modèle est commune au combat, au Garage, aux aperçus et aux
portraits de duel. L'icône de sélection est un rendu transparent du même modèle.
Agile et Polyvalent utilisent toujours leur modèle et leurs finitions existants.

Les clips de déplacement et de combat sont ceux du modèle sélectionné.
Les gestes contextuels privilégient également ses propres clips, avec les
durées courtes de la banque commune et la suppression du déplacement horizontal
pour les réactions de fin de manche et du Garage. Les autres clips restent
disponibles dans le fichier sans ajouter de transitions au graphe de combat.

Lors d'un changement de modèle, le rig recalcule la pose de visée, la pose de
portage, la vitesse des foulées et les attaches d'armes. Il conserve les nœuds
d'armes, le module équipé, les modificateurs externes et l'autorité réseau des
réactions. La main d'appui du Longshot est adaptée au châssis orange.
Le cadrage du Garage tient compte de sa silhouette.

Les statistiques restent à 1200 PV et 4 m/s. La collision du joueur ne change pas.

Vérifications : `tools/test_chassis_visuals.gd` couvre les changements répétés,
la visée en déplacement et avec recul, les attaches des quatre armes, le Garage,
les portraits, les modules et le personnage distant. Les suites du rig, du Garage,
des modules et des animations contextuelles complètent ces contrôles.

`tools/capture_powerful_chassis.gd` reproduit les captures du Garage dans
`outputs/powerful-chassis/` et régénère l'icône.
