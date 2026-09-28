# PROTOTYPE 0 — Aiming, weapon direction et locomotion

Passe du 28 septembre 2026.

## Direction unique et trajectoire

`Player.aim_direction` est la source de vérité horizontale commune au joystick droit, au facing de combat, à la direction centrale du blaster/shotgun, au muzzle flash et aux projectiles. Les directions de tir ne sont plus recalculées depuis la rotation visuelle momentanée du squelette. Le recul reste donc un delta visuel et ne peut pas devenir la nouvelle direction logique.

Chaque arme possède un `Marker3D` `Muzzle` et déclare son axe local avant via la métadonnée `weapon_forward_axis` (`-Z` Godot). Les rotations `±90°` restantes ne concernent que les wrappers des meshes GLB importés ; elles ne participent ni à la visée ni au calcul des projectiles.

Le shotgun échantillonne toujours la position et `aim_direction` courantes au moment réel de l’émission, après ses 100 ms de préparation. Ses six directions visuelles sont maintenant le cône logique central tourné autour de `Vector3.UP`, y compris lorsqu’un hit assisté est validé. Le blaster conserve de même sa trajectoire visuelle sur l’axe logique, sans snap visuel vers le centre d’une cible assistée.

Un tap de blaster trop court pour terminer la montée attend le prochain `skeleton_updated` avant de lire `Muzzle.global_position`. Ce délai maximal d’une frame garantit que le projectile ne part jamais de l’ancienne pose basse.

## Machine d’états

La machine logique est :

- `IDLE` : aucune vitesse, arme basse ;
- `LOCOMOTION` : walk/run corps entier, arme portée naturellement ;
- `AIM` : préparation/charge, corps orienté vers `aim_direction` ;
- `FIRE` : émission et recul du squelette ;
- `AIM_HOLD` : maintien configurable avant retour à la locomotion.

Un nouveau tir remet intégralement le timer `AIM_HOLD` à sa valeur configurée. À l’expiration, le rig baisse l’arme et le facing revient progressivement à la direction de déplacement. Le déplacement et la visée restent indépendants ; aucun état de tir ne bloque `CharacterBody3D`.

## Blending et attachments

Hors combat, les clips `idle`, `walk` et `run` sont utilisés en corps entier. La pose `runtime/AimPose`, dérivée du frame stable du clip `fire`, est un layer filtré sur le haut du corps. En combat, elle remplace donc torse et bras tandis que les jambes conservent sans redémarrage la phase de locomotion.

La montée et la descente sont interpolées. À l’émission, le facing est exact ; le recul `ShotKick` reste appliqué après l’AnimationTree et revient à zéro en 170 ms. Les wrappers `WeaponRoot`, `WeaponSway` et `WeaponRecoil` restent fixes sur le rig animé.

Blaster et Shotgun restent sous la chaîne `Skeleton3D -> RightHand -> BoneAttachment3D -> WeaponSocket -> WeaponRoot`. La main gauche est résolue vers `LeftHandGrip` uniquement dans la posture de combat ; hors combat, l’animation de locomotion récupère naturellement les bras.

## Paramètres inspecteur

Sur `Player` :

- `aim_hold_time` : 0,35 s par défaut, plage 0,25–0,50 s ;
- `aim_raise_time` : 0,10 s ;
- `aim_lower_time` : 0,18 s ;
- `enable_direction_debug` : active le diagnostic dès le lancement.

F8 bascule aussi le diagnostic en jeu. Couleurs : déplacement bleu, aim rouge, facing vert, arme blanche, main jaune, muzzle cyan, projectile magenta. Le label affiche l’état et les angles Muzzle/Aim et Projectile/Aim.

## Limites de l’asset

Le GLB contient `idle`, `walk`, `run` et `fire`, mais aucun clip dédié `aim`, `aim_walk` ou `weapon_ready`. La montée/descente est donc un blend vers une pose constante extraite de `fire`, complété par le solveur de main gauche. La tenue basse est celle des clips de locomotion existants ; une animation spécifiquement authorée améliorerait encore la prise à deux mains hors combat.

La visée reste plane, conformément au gameplay actuel. Le contrôle tactile est testé dans le moteur desktop ; aucun appareil Android ni APK n’a été validé pendant cette passe, faute de SDK/build-tools Android disponible.
