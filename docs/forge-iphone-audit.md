# Garage — audit des formats iPhone sur PC

La scène réelle a été rendue avec Godot 4.7.2, Vulkan Mobile sur GTX 1660 SUPER, dans trois fenêtres paysage représentatives. Aucun script de jeu n'a été modifié pour cet audit.

Chaque pixel de la fenêtre représente ici une unité logique assimilée à un point iOS. Les tailles obtenues sont des estimations de mise en page pour un affichage plein écran standard, sans Zoom de l'écran. La densité Retina, les dimensions physiques du téléphone, le rendu iOS et les performances ne sont pas simulés.

## Résultat

Le décor tient dans les trois formats, les cinq postes restent visibles et les touches précises ouvrent leurs catalogues. L'interface conserve ses proportions PC et devient trop petite pour un usage confortable au doigt.

| Format logique | Descriptions | Navigation, hauteur | Sauver et jouer, hauteur | Titres des choix |
| --- | ---: | ---: | ---: | ---: |
| Compact 667×375 | 8.3 pt | 18.8 pt | 21.9 pt | 7.3 pt |
| Standard 844×390 | 8.7 pt | 19.5 pt | 22.8 pt | 7.6 pt |
| Grand 932×430 | 9.6 pt | 21.5 pt | 25.1 pt | 8.4 pt |

[Apple recommande pour les jeux iOS](<https://developer.apple.com/design/human-interface-guidelines/designing-for-games/>) des textes d'au moins 11 points et des boutons touchables d'au moins 44×44 points. Ce sont les repères utilisés ici, pas une mesure du confort réel d'une personne.

Les lignes du catalogue mesurent environ 33–38 points de haut. La sélection des passifs et de la mobilité est assez grande dans la vue 3D ; les rangements arrière d'armes, offensifs et défensifs demandent davantage de précision, surtout en petit format.

Le volume de sélection du robot occupe environ 76–87 points de haut dans la vue d'ensemble, soit 20 % de l'écran. Cette mesure inclut la boîte du modèle ; ses détails et ses plaques sont encore plus petits. Les vues rapprochées de catalogue sont plus lisibles que la vue générale.

## Bords et geste d'accueil

Le format compact est testé sans réserve de bord. Les deux formats larges utilisent une hypothèse prudente de 59 points de chaque côté et 21 points en bas, pour matérialiser les bords à encoche et la zone du geste d'accueil. Ce ne sont pas des valeurs mesurées sur un modèle d'iPhone.

Les marges latérales actuelles protègent les commandes dans cette hypothèse. Les cinq commandes du pied de page empiètent en revanche sur la bande inférieure de 21 points. Le garage n'utilise pas actuellement la zone sûre de l'appareil ; seul le HUD de combat le fait.

## Contrôles et captures

78 contrôles exécutés, 0 échec : dimensions réelles des fenêtres et images, visibilité des cinq postes, touches directes sur leurs volumes 3D, sélection d'une ligne par le couple touche/souris émulée sur Windows, préservation du build.

Les événements souris émulés des boutons sont injectés explicitement : Window.push_input ne produit pas automatiquement les événements complémentaires du système tactile. Le glissement de la fiche est seulement enregistré, sans validation de la gestuelle iOS.

Dix-huit PNG natifs sont conservés dans `captures/forge-iphone/`, pour l'atelier et les cinq catalogues à chaque format. L'aperçu interactif contient des copies WebP compressées ; les PNG et `audit.json` restent les preuves originales.

```powershell
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path 'C:\Users\BOTTEROOOW\PROTOTYPE-V0.1' --audio-driver Dummy --script tools/capture_forge_iphone.gd
python tools/present_forge_iphone.py
```

## Passe recommandée

1. Donner aux boutons une hauteur tactile indépendante de la mise à l'échelle PC et réserver la zone du geste d'accueil.
2. Agrandir les textes ; simplifier la fiche latérale sur petit écran, avec les détails longs accessibles séparément.
3. Rapprocher modérément le cadrage général et élargir les volumes de sélection des petits postes arrière.

Ces corrections sont proposées à partir de cet audit ; elles ne sont pas appliquées au jeu. La fluidité, les temps de chargement et le comportement réel d'iOS nécessitent une version iPhone.
