# Menus simplifiés et garage adaptable

Intégration des maquettes approuvées le 3 octobre 2026, dans le projet `PROTOTYPE-V0.1`.

## Parcours

| Écran | Accès |
| --- | --- |
| Accueil | Jouer, Garage, Entraînement ; raccourci des réglages |
| Jouer | Duel solo, Multijoueur, Survie |
| Entraînement | Terrain libre, Tutoriel |
| Atelier | Armes, Modules, Mes Builds ; Tester et Jouer |
| Catalogue | Une famille à la fois ; toutes les armes, tous les modules et les châssis restent accessibles |
| Mes Builds | Sélection, préréglages, nom, création, duplication, sauvegarde, changement de châssis et arène disponible |

Sur PC, le catalogue et la fiche sont côte à côte. Les armes utilisent leur véritable modèle 3D ; les modules se consultent avec le robot en vue. Sur petite fenêtre ou appareil mobile, la carte ouvre une fiche séparée. Retour conserve la famille consultée. Les valeurs détaillées restent accessibles dans le texte défilant sur petit écran.

Consulter une arme ou un module ne l'installe pas. Installer utilise le bras existant ; le brouillon change lors de la fixation. Les démonstrations vidéo ne tournent qu'après une demande et s'arrêtent à leur fermeture. Jouer sauvegarde un brouillon avant de lancer le duel ; un build actif déjà enregistré part directement. Les sauvegardes nommées conservent leur format actuel.

Le cadrage de l'atelier privilégie le robot. Le mouvement discret de caméra se suspend sur les accès de navigation et pendant la rotation manuelle ou l'intervention du bras. Le garage caché suspend son rendu et ses animations.

## Captures du jeu

- [Accueil PC](../captures/responsive-garage/pc-home.png)
- [Garage PC](../captures/responsive-garage/pc-garage.png)
- [Catalogue des armes PC](../captures/responsive-garage/pc-weapon-catalog.png)
- [Gestion des builds PC](../captures/responsive-garage/pc-builds.png)
- [Garage sur petit écran](../captures/responsive-garage/compact-garage.png)
- [Catalogue passif au format iPhone](../captures/responsive-garage/iphone-passive-catalog.png)
- [Fiche passive au format iPhone](../captures/responsive-garage/iphone-passive-detail.png)
- [Gestion des builds au format iPhone](../captures/responsive-garage/iphone-builds.png)

## Vérification

`tools/capture_responsive_garage_menus.gd` utilise la scène principale et un rendu Vulkan Mobile sur PC. Il parcourt l'accueil, les modes, l'entraînement, l'atelier, les six familles, leurs fiches et les builds. Les contrôles vérifient les dimensions des boutons, les limites de l'écran, les marges simulées, la navigation souris/tactile, l'absence de modification lors d'un aperçu, la pose effective, la vidéo sur demande et les sauvegardes avant lancement. Les sauvegardes de test sont isolées ; le contenu des véritables fichiers du joueur est vérifié inchangé.

Formats en paysage : 1280 × 720, 1920 × 1080, 667 × 375, 844 × 390 et 932 × 430. Les deux derniers ajoutent, pour la simulation, des marges latérales de 59 et une marge inférieure de 21. Ces marges sont des hypothèses de test, pas une identification d'un modèle d'iPhone. En production mobile, l'interface consulte la zone sûre fournie par Godot. Le mode réel `canvas_items` est aussi contrôlé à 844 × 390.

- Nouveaux parcours et captures : `tools/test_responsive_garage_menus.gd` et `tools/capture_responsive_garage_menus.gd`.
- Installation, transport, fixation, annulation et sauvegarde : `tools/test_forge_module_installation.gd` et `tools/test_forge_installation_audio.gd`.
- Cadrage, mouvement, arrêt sur interaction et reprise : `tools/test_forge_camera_motion.gd`.

Lors de la synchronisation avec main, le test `tools/test_game_flow.gd` a été adapté à la durée réelle de fin de manche et au délai de lecture de la chute avant le cadrage du vainqueur. Il passe avec la séquence actuelle, ainsi que `tools/test_round_end_feedback.gd`.

Ces captures vérifient la présentation et les interactions sur PC aux dimensions de téléphone. L'exécution iOS, ses événements tactiles natifs et ses performances n'ont pas été testés sur un iPhone réel. Le portrait n'est pas couvert par cette validation.

## Sources

`scripts/ui/menu_navigation.gd` gère les pages de l'accueil. `scripts/ui/forge_garage_layout.gd` gère les dimensions et la zone sûre. `scripts/forge_garage.gd` conserve les actions et la bibliothèque de builds ; `scripts/forge_garage_focus.gd` adapte la caméra. `scripts/game_flow.gd` relie les nouveaux accès aux écrans et modes existants.
