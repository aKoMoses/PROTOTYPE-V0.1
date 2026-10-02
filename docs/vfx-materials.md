# Particules, impacts et signatures des armes

Passe locale du 2 octobre 2026. Réservation : `9bb0da4c-f58a-4134-955c-462acde07ed0`.

## Résultat

- Quatre silhouettes : étincelles effilées alignées sur la vitesse, plaques métalliques irrégulières, poussière douce et fragments d'énergie en losange. Géométrie, courbes et couleurs sont réinitialisées à chaque réutilisation d'un émetteur.
- Impacts en trois temps : flash de contact de 65 à 80 ms, petits débris après 25 ms, puis fumée après 55 à 60 ms. Les effets différés appartiennent au même budget et sont supprimés par le même reset que les effets immédiats.
- Blaster : noyau arrondi existant conservé, traînée de plasma courte qui se forme derrière le projectile. Le tir chargé conserve son multiplicateur de taille.
- Shotgun : silhouette orange et trois couches de bouche conservées, fumée animée plus ample. La taille de la flamme est calculée depuis sa taille initiale à chaque image, évitant l'accumulation des facteurs d'échelle.
- Longshot : bouche plus longue et étroite, queue fine sur le tir normal, éclat de contact à quatre branches. Le tir EXÉCUTION conserve sa traînée dorée existante et son diamètre physique.
- Bouclier : onde locale avec deux fronts et trame hexagonale, accompagnée de fragments d'énergie. Le patch suit la normale du contact ; le shader propre au mur magnétique continue aussi sa propagation sur le champ. Les contacts pendant la stase du joueur et du bot sont classés comme bouclier.
- Fumée et brûlures : trois variantes déterministes de chaque texture en 128 × 128, avec bruit à plusieurs échelles, contours irréguliers et fissures. La fumée se développe, tourne doucement et se déforme au cours de sa vie.
- Lisibilité : plancher de taille projetée de 9 pixels pour le flash principal, avec agrandissement limité à 1,55. Les fumées restent secondaires et cessent d'être ajoutées lorsque le budget d'effets approche de sa limite.

Les ressources sont mises en cache et préparées avant le combat. Les caps existants sont conservés : 48 effets, 24 marques et 14 émetteurs en qualité normale, divisés par deux en qualité basse. Le mode bas garde les informations de contact et l'onde du bouclier, réduit les fragments et retire la fumée. La pression sur le budget évince d'abord les fumées et les étincelles secondaires.

Les traînées du Blaster, du Shotgun et du Longshot normal ne dépassent jamais la distance déjà parcourue. Au contact, elles se figent derrière le projectile et disparaissent en 45 à 65 ms. Aucun effet ne modifie les dégâts, collisions, vitesses ou temporisations de combat.

## Vérification

Godot 4.7.2, moteur graphique Forward Mobile sur Vulkan. Les chemins `C:\RomainOpen` ne sont pas disponibles sur ce poste ; vérifications effectuées avec l'exécutable absolu présent dans `.godot/pass-runtime` et le projet local.

Les autres conversations modifiant le contrôleur pendant les essais, la vérification finale de la scène de production a utilisé une copie figée des scripts et des scènes sous `.godot/vfx-materials-verification`. Les ressources artistiques et imports sont partagés en lecture avec le projet.

| Vérification | Résultat |
| --- | --- |
| `tools/test_vfx_materials.gd` | 51 contrôles réussis : textures distinctes, pool réinitialisé, départ différé, reset, stase, priorités, collisions et caps |
| `tools/test_shotgun_vfx.gd` | 22 contrôles réussis |
| `tools/test_vfx.gd` avec rendu graphique | 71 contrôles réussis, dont dégâts réels, suivi des armes, resets et trois minutes simulées par qualité |
| `tools/test_longshot_presentation.gd` avec rendu graphique | 13 contrôles réussis ; diamètres 0,18 / 0,27 m conservés |
| Import / chargement éditeur de la copie figée | Réussi, sans erreur de script |
| `tools/capture_vfx_materials.gd` | Neuf scénarios, six instants chacun, à 1280 × 720 puis 960 × 540 ; sans erreur de shader ou de script |

Le test général `tools/test_blaster.gd` a une défaillance : le tap clavier bref pendant le cooldown n'enchaîne pas le tir suivant. Le même échec a été reproduit avec le gestionnaire VFX de `HEAD` dans la même copie figée, avant de restaurer le nouveau gestionnaire. Le contrôle des entrées n'a pas été modifié par cette passe.

Logs de vérification locale : `outputs/vfx-materials-test.log`, `outputs/vfx-materials-integration-final.log`, `outputs/vfx-longshot-presentation.log`, `outputs/vfx-materials-editor.log`, `outputs/vfx-materials-capture.log` et `outputs/vfx-materials-capture-small.log`. Comparaison Blaster : `outputs/vfx-blaster-before.log` et `outputs/vfx-blaster-final.log`.

## Captures

- [Plasma du Blaster, petit écran](../captures/vfx-materials/small/blaster-01.png)
- [Bouche du Shotgun](../captures/vfx-materials/desktop/shotgun-10.png)
- [Longshot en vol](../captures/vfx-materials/desktop/longshot-01.png)
- [Onde du bouclier](../captures/vfx-materials/desktop/shield-10.png)
- [Bouclier, petit écran](../captures/vfx-materials/small/shield-05.png)
- [Fumée et débris sur métal](../captures/vfx-materials/desktop/metal-10.png)

Les dossiers `desktop` et `small` contiennent aussi les phases de disparition et les six textures exportées pour inspection.

## Relancer

Depuis le projet Godot, avec l'exécutable console absolu disponible sur le poste :

```powershell
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\RomainOpen\perso\Studio\game-source' --script res://tools/test_vfx_materials.gd
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path 'C:\RomainOpen\perso\Studio\game-source' --fixed-fps 60 --disable-vsync --script res://tools/capture_vfx_materials.gd -- res://captures/vfx-materials/desktop
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path 'C:\RomainOpen\perso\Studio\game-source' --fixed-fps 60 --disable-vsync --script res://tools/capture_vfx_materials.gd -- res://captures/vfx-materials/small small
```

Les signatures de réussite, les sons, les décors et les contrôles conservent leurs travaux séparés. Cette livraison est locale, non publiée.
