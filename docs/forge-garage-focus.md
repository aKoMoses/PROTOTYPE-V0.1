# Inspection des équipements dans le garage

Le garage existant propose maintenant une caméra d'inspection et des effets courts sur les pièces du robot. Le contrôleur est isolé dans `scripts/forge_garage_focus.gd` ; `forge_garage.gd` lui transmet les sélections et `forge_garage_stage.gd` suspend les interventions et gestes automatiques pendant un gros plan.

## Utilisation

- Les catalogues gardent la vue générale du robot. Les armes et les modules sans accessoire physique déclenchent un effet local pendant 1,65 seconde.
- Choisir Pyroboots ou Bio Injector rapproche la caméra de l'accessoire réel et lance trois secondes de travail du bras après son approche. La caméra revient ensuite à la vue générale. Le détail est décrit dans `robot-module-visuals.md`.
- ROBOT, ainsi qu'un changement de châssis, ramène à la vue générale.
- Le glisser sur le robot conserve la rotation existante ; la caméra et les effets suivent les pièces.
- Les changements de cadrage durent 0,52 seconde, avec accélération et ralentissement progressifs. Le panneau de choix et le redimensionnement déclenchent aussi cette transition.

| Équipement | Pièce cadrée | Indication visuelle |
| --- | --- | --- |
| Armes | Main et modèle équipé | Anneau cyan et points en orbite |
| Modulo-Drone | Épaule droite | Satellites orange |
| Javelin, Fulguro-Punch, Pelto-Smash | Bras droit | Charge orange autour du poignet |
| Magnetic Field | Torse | Plan bleu, lignes et montants |
| Static Shield | Torse | Coque bleue translucide |
| Pyro-Boots | Boîtiers aux chevilles | Accessoires physiques et scanner du bras |
| Bio-Injector | Cartouches sur le plastron | Accessoire physique et scanner du bras |
| Baroud | Réacteur | Impulsion rouge |
| Omnivamp | Réacteur | Impulsion violette et points convergents |

Les ancrages proviennent du vrai squelette. Les effets ont leurs propres matériaux et leur géométrie suit la taille du châssis. Le cadrage tient compte des dimensions de l'arme, de la rotation, du format d'écran et de l'espace occupé par le panneau de choix.

La démo vidéo et ses survols gardent leur fonctionnement. Consulter les informations d'une autre arme n'équipe pas cette arme. Le scanner manuel reste accessible aux outils de vérification ; le Garage présente l'installation des accessoires et la sauvegarde animée du build.

Quitter la forge efface l'inspection, remet la caméra au repos et suspend son traitement. Après l'impulsion, les effets sont cachés et leurs ancrages et matériaux cessent d'être recalculés.

## Vérification

`tools/test_forge_garage_focus.gd` vérifie les transitions, les quatre armes et les modules du catalogue, les différents châssis, le cadrage à 800×600, 1280×720 et 2340×1080, la vraie entrée GUI de rotation pendant un gros plan, l'absence de sauvegarde au clic, la sortie et la réouverture. Le test de l'installation ciblée vérifie les trois secondes de travail du bras.

Les tests existants du garage, des démos d'entraînement et du scanner servent à vérifier leur intégration. Les captures de `tools/capture_forge_garage_focus.gd` sont produites par le vrai rendu Vulkan, à 1280×720 et 2340×1080, dans `captures/forge-garage-focus/`.

Le rendu sur une machine Windows a été contrôlé. Le confort tactile et les performances sur un appareil Android restent à vérifier sur cet appareil.
