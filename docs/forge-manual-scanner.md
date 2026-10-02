# Scanner manuel du garage

Le bouton **SCANNER**, au-dessus de la zone centrale, active le pilotage du bras de maintenance déjà présent dans la Forge. Déplacer la souris sur le torse ou l'épaule proche du socle guide l'outil ; maintenir le clic lance un balayage une fois l'outil arrivé. Relâcher ramène le bras au repos. Sur un écran tactile, le doigt maintenu guide et scanne ; son relâchement ou son annulation arrête l'intervention.

Le bouton **QUITTER SCANNER** et Échap sortent du mode. Échap ne ferme pas immédiatement le garage pendant une inspection. La perte de focus, la fermeture du garage, un changement d'équipement ou l'ouverture d'un panneau d'équipement coupent aussi l'inspection. L'orientation manuelle précédente du robot est conservée à la sortie du mode.

## Mouvement et rendu

`forge_manual_scanner.gd` calcule une pose à quatre articulations sur les nœuds `BaseYaw`, `Shoulder`, `Elbow` et `Wrist` du GLB existant. Les longueurs des segments sont lues sur ses pivots. La cinématique inverse analytique inclut l'extension de l'outil ; les rotations respectent des butées et une vitesse maximale. La lecture du cycle Blender est suspendue pendant le contrôle manuel et redevient disponible après sa sortie.

Les cibles sont des enveloppes ellipsoïdales attachées aux os du torse et des épaules, adaptées à la taille du châssis. Le bras garde une distance de travail et ses segments sont contrôlés contre ces enveloppes avec une marge. Il ne s'agit pas d'une simulation physique de tous les polygones du robot ou de l'atelier. L'épaule éloignée et les points dépassant la portée des segments sont signalés en orange et refusés.

Une lampe éclaire le métal à proximité. Le clic maintenu active un faisceau, une mire et un balayage local, avec un léger tremblement du poignet. Le retour coupe les effets immédiatement et ramène les articulations progressivement au repos. Un servo discret est synthétisé une fois en mémoire et passe par le bus **Effects**, donc par le réglage de volume existant. L'inspection ne modifie aucune statistique ni aucun équipement.

`forge_manual_scanner_ui.gd` gère la commande, la souris, le doigt principal et les annulations. Le mode explicite évite de concurrencer le glissement qui fait tourner le robot. Il retrouve la vue générale avant le pilotage et laisse les zooms et les démos reprendre lors d'une sélection. Les effets du scanner appartiennent uniquement au monde 3D du garage ; leur traitement, leur lumière et leur son s'arrêtent hors de cet écran.

## Vérification

- `tools/test_forge_manual_scanner.gd` : **102 contrôles réussis**. Cinématique du vrai GLB, trajectoires et vitesses, torse et épaule proche sur les trois châssis, refus des cibles éloignées, relâchement, tactile et annulation, souris émulée, perte de focus, Échap, rotation restaurée, panneaux, zooms, démos et trois formats de fenêtre. Les événements souris et Échap sont aussi injectés dans le routage réel du viewport ; le suivi est contrôlé pendant l'animation idle.
- Import et chargement de l'éditeur Godot 4.7.2 réussis.
- Tests existants `test_forge_garage`, `test_forge_garage_focus` (135 contrôles sur la dernière version concurrente) et `test_forge_training_demo` réussis.
- Captures réelles Vulkan Mobile / GTX 1660 SUPER : `captures/forge-manual-scanner/`. Le dossier est exclu des imports et exports du jeu.

Les gestes tactiles sont vérifiés par événements simulés sur PC. Aucun essai sur téléphone ni nouvel export APK n'a été réalisé pour cette modification. Le son est présent et respecte le bus des effets ; son confort d'écoute reste à apprécier en jeu.

Pour reproduire les images, lancer `tools/capture_forge_manual_scanner.gd` avec le moteur en affichage réel. Ajouter `-- --motion` enregistre une séquence de vrais rendus dans le sous-dossier `motion`.
