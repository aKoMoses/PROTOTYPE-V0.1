# Lisibilité et sensations de combat

Cette passe s’applique au duel, à l’entraînement et à la survie. Elle complète les animations, les commandes et les effets existants.

## Changements visibles

- **Caméra** : cadrage rapproché à 114 % pendant le combat. Le curseur « Caméra de combat », dans les réglages, va de 100 à 125 % et conserve la préférence. Les anciennes sauvegardes restent compatibles.
- **Silhouettes** : contours des armures renforcés ; plaques de santé plus petites et légèrement abaissées. Le détail du sol et son relief sont atténués pour mieux faire ressortir les robots.
- **Poids du déplacement** : légère inclinaison du bassin selon l’accélération et le freinage. Elle s’efface pendant la visée et les actions spéciales ; les solveurs de mains et les animations de déplacement continuent de fonctionner.
- **Impacts** : étincelles métalliques, éclats et poussière minérale, poussière de sable et réponse des boucliers. Le métal et les surfaces minérales ont aussi des signatures sonores distinctes.
- **Intentions** : une lumière sur le torse accompagne une charge réellement engagée, une garde ou un rechargement. Elle disparaît à l’annulation de l’action et reste masquée pour un adversaire caché.
- **Déplacements et arène** : poussière au départ et à l’arrêt d’un dash, ainsi qu’au freinage rapide ; réaction locale des feuillages et des tissus proches. Le vent normal revient après la rafale et lors du nettoyage de la manche.
- **HUD** : score et confirmation de réussite plus compacts ; anneaux des modules prêts plus discrets. Le passif occupe un petit médaillon à gauche des sorts, avec son icône, le symbole ∞ et la mention « PASSIF ». Ses compteurs et ses marques restent visibles.
- **Audio mécanique** : moteur discret, servos lors des efforts et des changements d’intention, hauteur et poids des pas propres aux trois châssis. Toutes ces couches suivent le volume des effets sonores.

## Intégration

`VFXManager` installe un seul `CombatPresentationPass` dans chaque scène possédant une caméra de jeu. Le directeur suit aussi les ennemis créés et supprimés pendant les vagues. Les réactions du décor utilisent des matériaux propres à chaque élément ; un matériau partagé ne propage donc pas une rafale à toute la carte.

Les couches de présentation ne déplacent pas le corps de collision et ne modifient ni les dégâts ni les délais des armes. La visée est vérifiée sur le Blaster, le Shotgun et le Longshot. Les bruits de pas utilisent un générateur aléatoire privé pour préserver celui du gameplay. Pause, mort, réinitialisation et changement de scène arrêtent les effets et les voix concernés.

Une protection dans `repair_socket_presentation.gd` permet au socle médical de conserver le shader fourni par l’habillage de la cour. Les autres modifications artistiques et les nouvelles animations du projet sont conservées.

## Vérification

État vérifié le 2 octobre 2026, après l’ajustement du passif : **25 suites réussies sur 25**, **75 contrôles** pour la présentation en exécution sans rendu et **84 contrôles** avec les captures PC comme au format mobile, sans échec. L’éditeur de HUD et les six passifs sont inclus dans les vérifications.

Le script `tools/test_combat_presence.gd` vérifie les trois modes, le cadrage et sa sauvegarde, les réglages réels, la visée, les signaux de charge, l’occlusion, la réaction locale du décor, les pas des châssis, la pause, le budget des particules et la suppression des ennemis.

```powershell
node tools/run_combat_presence_checks.cjs
```

Le lanceur utilise un Godot console installé, des sauvegardes isolées et un délai maximum par suite. On peut fournir un autre chemin absolu avec la variable `GODOT_CONSOLE`. Il conserve les résultats des autres suites lors d’une relance ciblée.

Les journaux et le bilan des suites se trouvent dans `outputs/combat-presence/checks/`. Les captures natives sont dans `outputs/combat-presence/`, avec les vues au format 844 × 390 dans son sous-dossier `mobile/`. Ces vues sont rendues sur PC ; elles ne constituent pas une mesure de performances sur téléphone.

Les captures et les échantillons WAV peuvent être régénérés avec le Godot console :

```powershell
$env:GODOT_CONSOLE = 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA = Join-Path (Get-Location) '.godot/combat-presence-user'
& $env:GODOT_CONSOLE --path (Get-Location).Path --script res://tools/test_combat_presence.gd --resolution 1280x720 --max-fps 60 -- capture detail
```

Ajouter `mobile` et utiliser `--resolution 844x390` pour le petit écran. Les tests existants de survie attendent désormais l’émission après la pose du squelette ; le test audio laisse terminer le nettoyage différé avant de quitter.
