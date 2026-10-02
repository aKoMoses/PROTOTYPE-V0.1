# Longshot : précision, mobilité et EXÉCUTION

Réservation : `84e1d018-693a-436d-8ad2-ff4d1f1d59ef`. Vérification locale le 2 octobre 2026 ; publication non effectuée dans cette conversation.

## Réglages

| Paramètre | Valeur |
| --- | --- |
| Dégâts normaux | 90 à courte distance ; jusqu’à 202,5 |
| Bonus de distance | Progression linéaire de 6 à 18 m parcourus, plafond ×2,25 |
| EXÉCUTION | ×1,8 : 162 à 364,5 dégâts par cible |
| Intervalle | 0,85 s, dont 0,08 s de préparation |
| Vitesse du projectile | 120 m/s ; EXÉCUTION 150 m/s |
| Rayon physique | 0,09 m ; EXÉCUTION 0,135 m |
| Portée | 32 m |
| Mobilité après une touche | +20 % pendant 0,7 s, sans accumulation |

Deux tirs normaux qui infligent des dégâts à des ennemis préparent EXÉCUTION. Les cibles peuvent être différentes. Les ratés et les murs conservent les impacts acquis ; tirer dans le vide ou détruire une roquette ne remplit pas le compteur. Une attaque bloquée ne donne ni progression ni bonus de vitesse. Les dégâts absorbés par un bouclier de points de vie comptent comme une touche acceptée.

EXÉCUTION est consommée à l’émission, même si elle rate. Elle traverse les robots et leur applique une seule fois les dégâts correspondant à leur distance propre depuis le canon. Elle s’arrête au premier obstacle ou à une attaque bloquée, notamment Counter. Ses victimes donnent la mobilité mais ne préparent pas une nouvelle EXÉCUTION.

Le compteur appartient à l’instance de l’arme : le changement d’arme conserve les impacts et la récupération ; mort, nouvelle manche et remplacement de l’équipement les remettent à zéro. Un ancien projectile ne peut pas créditer la progression ou la vitesse d’une nouvelle instance. La pause conserve la durée du bonus et décale la récupération du Longshot.

## Présentation et réseau

Deux segments et « EXÉCUTION PRÊTE » remplacent le compteur de cinq émissions, dans le HUD et les plaques de combat. Les cœurs de l’arme prennent une couleur dorée quand le tir est prêt. EXÉCUTION utilise un projectile plus long, une traînée dorée persistante, des impacts plus marqués et une variante sonore plus grave. Les descriptions Forge, le profil de bot tireur et le texte d’amélioration Survie sont adaptés.

Le joueur et les bots utilisent le même état et les mêmes réglages. L’hôte possède le compteur d’impacts et le bonus de mobilité ; les snapshots les répliquent. Les effets des répliques ne peuvent ni infliger des dégâts ni faire progresser le compteur. Un événement visuel reçu après un snapshot ne consomme pas le tir une seconde fois.

## Vérification

- `tools/test_longshot_projectile.gd` : **92 contrôles réussis**. Deux robots à plusieurs formes, mur fin derrière eux, distances distinctes et impact bloquant, y compris dans un seul pas de simulation à basse fréquence.
- `tools/test_longshot.gd` : **219 contrôles réussis**. Dégâts réels, série gagnée par les touches, ratés, traversée de deux robots, mur, déplacement physique accéléré, expiration, commandes PC/mobile, interruption, remise à zéro, Survie et huit directions de visée.
- `tools/test_longshot_bot.gd` : **108 contrôles réussis**. EXÉCUTION aux rangs 3/6/9/12/15 quand tous les tirs touchent, dégâts, canon réel, récupération et mobilité.
- `tools/test_longshot_network.gd` : **17 contrôles réussis**. Autorité hôte, requête falsifiée, compteur et mobilité répliqués, événement visuel tardif, changement d’arme et annulation.
- `tools/test_longshot_presentation.gd` : **13 contrôles réussis**, avec rendu OpenGL : prise, visée, retour de recul et dimensions visibles.
- `tools/test_counter_weapons.gd` : **55 contrôles réussis**, dont arrêt du véritable tir EXÉCUTION avant la cible suivante et absence de bonus après parade.
- `tools/test_weapon_aim_guide.gd` : **49 contrôles réussis**. Guide de visée, origine du projectile et routage des commandes.
- `tools/capture_longshot_execution.gd` : rendu réel et dégâts sur deux robots vérifiés ; captures `captures/longshot-execution/ready.png` et `execution.png` inspectées visuellement.

Total des sept suites : **553 contrôles réussis**. Certains harness bots/Counter signalent des ressources restant en mémoire à la fermeture. Le chargement final des scripts ne signale pas d’erreur GDScript ; il a signalé un shader de sol en cours de modification (`mat2(float,float,float,float)`) dans une autre passe. Cette refonte ne modifie pas ce shader. Le chemin Godot indiqué dans AGENTS.md étant absent sur ce poste, les vérifications utilisent le moteur Godot 4.7.2 déjà présent dans `.godot/pass-runtime/` avec un chemin absolu.

Restent à vérifier en parties humaines : confort sur Android physique, lisibilité sur petit écran et équilibre avec les autres armes récemment renforcées. Les tests réseau utilisent des acteurs hôte/réplique locaux, sans deux appareils sous latence réelle.
