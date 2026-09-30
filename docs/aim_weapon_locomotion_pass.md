# PROTOTYPE 0 — Aiming, weapon direction et locomotion

Passe du 28 septembre 2026, corrigée pour le duel le 30 septembre 2026.

## Direction unique et trajectoire

`Player.aim_direction` est la source de vérité horizontale commune au joystick droit, au facing de combat, à la direction centrale du blaster/shotgun, au muzzle flash et aux projectiles. Les directions de tir ne sont plus recalculées depuis la rotation visuelle momentanée du squelette. Le recul reste donc un delta visuel et ne peut pas devenir la nouvelle direction logique.

La souris est projetée sur le plan de combat à hauteur du corps (`MOUSE_AIM_HEIGHT`, 1,35 m), plutôt que sur le sol. Avec la caméra inclinée, une projection au sol décalait le tir lorsque le curseur était posé sur le torse d’un robot placé sur le côté.

Chaque arme possède un `Marker3D` `Muzzle` et déclare son axe local avant via la métadonnée `weapon_forward_axis` (`-Z` Godot). Les rotations `±90°` restantes ne concernent que les wrappers des meshes GLB importés ; elles ne participent ni à la visée ni au calcul des projectiles.

Le shotgun échantillonne la pose finale du squelette au moment réel de l’émission, après ses 100 ms de préparation. Ses six projectiles forment un cône symétrique autour de la visée, sans convergence artificielle vers un point situé devant le joueur. Le blaster conserve sa trajectoire sur l’axe logique, sans redirection vers le centre d’une cible proche.

Un tap de blaster trop court pour terminer la montée et chaque salve de shotgun attendent le prochain `skeleton_updated` avant de lire `Muzzle.global_position`. Les projectiles partent ainsi de la pose de tir à jour. Si le canon traverse un obstacle, l’origine de sécurité reste au niveau du corps pour éviter de tirer à travers un mur.

Les contrôles de l’origine et du déplacement des projectiles acceptent les collisions dont le point de départ est déjà à l’intérieur du volume. Au contact, un canon dépassant le bot ne permet donc plus aux plombs de naître derrière lui. Les mêmes règles s’appliquent aux tirs du bot et aux obstacles ; aucun dégât n’est accordé à une trajectoire qui manque réellement la cible.

## Machine d’états

La machine logique est :

- `IDLE` : aucune vitesse, arme basse ;
- `LOCOMOTION` : walk/run corps entier, arme portée naturellement ;
- `AIM` : préparation/charge, corps orienté vers `aim_direction` ;
- `FIRE` : émission et recul du squelette ;
- `AIM_HOLD` : maintien configurable avant retour à la locomotion.

Un nouveau tir remet intégralement le timer `AIM_HOLD` à sa valeur configurée. À l’expiration, le rig baisse l’arme et le facing revient progressivement à la direction de déplacement. Le déplacement et la visée restent indépendants ; aucun état de tir ne bloque `CharacterBody3D`.

## Blending et attachments

Les clips `idle`, `walk` et `run` conservent la locomotion des jambes. Hors combat, `runtime/ReadyPose` maintient les bras dans une prise à deux mains abaissée, dérivée du frame stable du clip `fire`. La pose `runtime/AimPose` remplace le haut du corps pendant la visée, tandis que les jambes conservent sans redémarrage leur phase de locomotion.

La montée et la descente sont interpolées. À l’émission, le facing est exact ; le recul `ShotKick` reste appliqué après l’AnimationTree et revient à zéro en 170 ms. Les wrappers `WeaponRoot`, `WeaponSway` et `WeaponRecoil` restent fixes sur le rig animé.

Blaster et Shotgun restent sous la chaîne `Skeleton3D -> RightHand -> BoneAttachment3D -> WeaponSocket -> WeaponRoot`. Les sockets de port et de visée sont calibrés séparément contre leur pose de main. La main gauche suit `LeftHandGrip` pendant le port, la montée, la visée et le recul ; les actions de modules gardent leur propre animation.

## Paramètres inspecteur

Sur `Player` :

- `aim_hold_time` : 0,35 s par défaut, plage 0,25–0,50 s ;
- `aim_raise_time` : 0,10 s ;
- `aim_lower_time` : 0,18 s ;
- `enable_direction_debug` : active le diagnostic dès le lancement.

F8 bascule aussi le diagnostic en jeu. Couleurs : déplacement bleu, aim rouge, facing vert, arme blanche, main jaune, muzzle cyan, projectile magenta. Le label affiche l’état et les angles Muzzle/Aim et Projectile/Aim.

## Limites de l’asset

Le GLB contient `idle`, `walk`, `run` et `fire`, mais aucun clip dédié `aim`, `aim_walk` ou `weapon_ready`. La montée/descente reste un blend entre deux poses dérivées de `fire`, complété par le solveur de main gauche.

La visée reste plane, conformément au gameplay actuel. Le contrôle tactile est testé dans le moteur desktop ; aucun appareil Android ni APK n’a été validé pendant cette passe, faute de SDK/build-tools Android disponible.

## Duel contre le bot

Le bot affiche le blaster ou le shotgun correspondant à son équipement. Sa visée résout la rotation autour de l’épaule avant l’émission ; ses projectiles utilisent ensuite l’axe final du canon, y compris à deux mètres du joueur.

Le HUD standard masque le bloc de vie/munitions en double, conserve les informations au-dessus des robots et aligne le score, la pause et les trois modules compacts. Les détails des modules sont accessibles dans les infobulles.

Validation : tests de poses joueur (299 contrôles), poses bot (510 contrôles), blaster, shotgun, équipements du duel, déroulement du match, HUD, verrouillage des actions et contrôles tactiles. `tools/test_duel_presentation.gd` vérifie les tirs réels des deux armes à 2 et 5 mètres, les origines des projectiles et l’alignement du HUD à 1280×720, 1600×720 et 1024×600. Les captures du duel et des poses ont été inspectées ; le ressenti pendant un duel joué manuellement reste à retester.

La régression de tirs traversants est couverte par `tools/test_shotgun_contact.gd` : 136 cas avec le vrai rig, les vraies collisions et les dégâts, de 0,65 à 6,5 mètres, huit directions, des poses de déplacement et le curseur sur trois hauteurs du torse. Avant correction, 12 des 88 premiers cas échouaient ; après correction, les 136 passent. Les tests shotgun (mur, esquive, critique, munitions/recharge), blaster, équipements du duel et effets visuels passent également. `captures/shotgun-cursor-fixed.png` montre le tir à 2,5 mètres sur le bot placé à gauche et les dégâts obtenus.

## Rechargement après plusieurs tirs

Le contrôle précédent réinitialisait le joueur entre chaque salve et ne couvrait pas le rechargement automatique après la troisième cartouche. L'ancien visuel de recharge appliquait des coordonnées de corps à `WeaponRoot`, maintenant exprimé dans le repère de la main. Le shotgun s'écartait alors de 1,32 m de la main droite et conservait ce décalage après la recharge ; les plombs suivants passaient au-dessus du bot.

`WeaponRoot` conserve désormais son transform de montage sur le rig squelettique pendant et après le rechargement. Le reset et le changement d'arme rétablissent aussi ce transform. Le fallback procédural garde son animation relative au montage initial, puis revient exactement à ce montage.

`tools/test_shotgun_reload.gd` charge le duel complet, conserve la boucle physique réelle du joueur et enchaîne neuf tirs sans jamais réinitialiser le joueur. Avant correction, les trois premiers tirs blessent le bot et les six suivants font zéro dégât ; après correction, les neuf touchent, les trois rechargements se terminent et la prise reste sur la main. Les 32 contrôles couvrent les cartouches, les six projectiles de chaque salve, les dégâts, la prise pendant environ 800 poses dont 345 de recharge, et le changement d'arme pendant une recharge. `captures/shotgun-after-reload.png` montre le quatrième tir après la première recharge, arme en main et dégâts affichés.
