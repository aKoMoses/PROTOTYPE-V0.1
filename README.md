# Prototype 0

Premier essai technique du jeu d'arène 1 contre 1 en vue 2,5D.

## Version actuelle

- arène 3D plus grande que l'écran ;
- caméra inclinée suivant le joueur avec anticipation de la visée ;
- déplacement clavier AZERTY/QWERTY et flèches ;
- Electro Axe provisoire en combo de trois coups et Shotgun à six plombs à la barre d'espace (clic souris conservé comme raccourci PC) ;
- obstacles bloquant le joueur et les projectiles ;
- cible d'entraînement à 1 000 PV avec affichage des dégâts, ralentissement et stun ;
- première passe visuelle de l'arène : sol sableux peint, murs de ferraille modulaires,
  plaques crème/rouille, acier sombre, pneus, caisses, barils, bannières rouges,
  hautes herbes décoratives, poussière, lampes et gradins de spectateurs.

Le lot Electro Axe sert à valider la perspective, la caméra, les déplacements, les hitboxes
et les sensations de combat avant l'intégration du Shotgun et des modules. Les kits de vie
ne sont pas encore activés ; les bushs disposent maintenant d'une première règle de
visibilité, avant leur passe de carte jouable.

## Rendu et ressources visuelles

- Renderer conservé : **Mobile** (Godot 4.7.2).
- Ressources réutilisables dans `art/` : `sand_dust.svg`, `metal_cream.svg`,
  `metal_rust.svg`, `steel_dark.svg` et `banner_red.svg`.
- Les collisions des couverts restent séparées de leurs modules décoratifs : les petits
  débris, herbes et accessoires n'ajoutent pas de formes de collision individuelles.
- L'éclairage exécuté combine une direction chaude, un remplissage froid discret, des
  lampes locales, des écrans cyan et une brume simple compatible Mobile.

## Suivi systèmes — 24 septembre 2026

- **P0-100 — vérifié :** dépôt, scène d'entrée, version Godot 4.7.2, renderer Mobile,
  commande de lancement, caméra, déplacements, attaque provisoire, collisions et cible
  d'entraînement inspectés sans réécriture de la caméra.
- **P0-101 — implémenté, à tester manuellement :** `combat_data.gd` centralise les
  paramètres ; `combat_state.gd` gère PV décimaux, dégâts effectifs, soins plafonnés,
  doublons d'attaque et reset indépendant par acteur.
- **P0-102 — implémenté, à tester manuellement :** BURN, SLOW, STUN et SPOTTED sont
  appliqués par le même état et visibles sur le mannequin. F1/F2/F3/F4 les appliquent,
  F5 réinitialise l'essai ; ce sont des raccourcis PC de validation temporaires. La
  lisibilité de la validation a été renforcée : barre de PV large, flammes et lumière
  animées pour BURN, anneau et motes cyan pour SLOW, halo STUN et œil SPOTTED émissif.
- **P0-103 — implémenté, à tester manuellement :** l'Electro Axe utilise les géométries
  et fenêtres V0.1 (80/90/150 au centre, 80/90/45 avec l'onde), déduplication par
  identifiant, ralentissements et stun distincts, interruptions par STUN, et rayon de
  visibilité physique qui bloque les coups derrière les obstacles. F6 active les volumes
  de diagnostic temporaires.
- **Tests automatisés :** `tools/test_combat_state.gd` et `tools/test_target_dummy.gd` PASS ;
  les valeurs testées incluent BURN isolé à 70 dégâts, non-cumul, slow maximal,
  expiration, STUN/SPOTTED, overkill, overheal, attaque dupliquée, BURN absorbé pendant
  la stase, activation des quatre effets sur le mannequin et reset visuel/HP.
- `tools/test_electro_axe.gd` PASS : combo centre = 320, combo onde = 215, estoc
  bloqué par un obstacle et préparation interrompue par STUN.
- **P0-104 — implémenté, à tester manuellement :** Shotgun avec six plombs indépendants à
  angles fixes (-10/-6/-2/+2/+6/+10°), portée maximale 7 m, vitesse 22 m/s et dégâts
  20 jusqu'à 3 m puis décroissance linéaire jusqu'à 8. Les obstacles absorbent chaque
  plomb. Les six impacts sur la même cible ajoutent le multiplicateur critique 1,5 et
  appliquent BURN ; cinq impacts n'appliquent pas BURN. Cadence 0,10 s de préparation
  + 0,60 s de récupération, chargeur de 3 salves, recharge automatique ou T en 1,80 s.
  G bascule Electro Axe/Shotgun. Les projectiles visuels partent du point d'arme et un
  identifiant unique empêche tout double impact.
- **Tests automatisés :** `tools/test_shotgun.gd` PASS : 6/6 critique + BURN, 5/6 sans
  BURN, absorption par obstacle, chargeur 3 salves et recharge 1,80 s. Les tests
  précédents P0-101/102 et P0-103 restent PASS.
- **P0-105 — implémenté, à tester manuellement :** Modulo Drone (préparation 0,18 s,
  portée 9 m, guidage initial dans un cône de 20°, 100 dégâts + BURN 3,5 s + SPOTTED
  5 s, cooldown 10 s) et Javelin (préparation 0,12 s, portée 8 m, 140 dégâts, marque
  2,5 s, cooldown 12 s). Les deux projectiles sont arrêtés par les obstacles. Le
  second appui Javelin tente une téléportation à 1,4 m derrière la cible avec deux
  variantes à ±30° ; une destination invalide conserve la marque. Le slot offensif A
  lance le module équipé (Drone par défaut dans ce prototype). Les marqueurs et
  cooldowns sont visibles sur le mannequin et les identifiants empêchent les doubles impacts.
- **Tests automatisés :** `tools/test_offensive_modules.gd` PASS : Drone (dégâts,
  BURN/SPOTTED, absorption, cooldown), Javelin (140 dégâts, marque, recast sans
  dégâts ni second cooldown, destination bloquée). Capture Mobile réelle inspectée
  pour `prototype0_drone.png` et `prototype0_javelin.png`.
- **P0-106 — implémenté, à tester manuellement :** slot mobilité R avec Pyro Boots
  (dash 3 m en 0,18 s, arrêt aux obstacles, cooldown 6 s, interruption par STUN) et
  Bio Injector (buff 3 s, +40 % déplacement, +50 % vitesse d'attaque, accélération des
  cooldowns externes, cooldown 18 s). Les attaques mémorisent leur multiplicateur au
  démarrage ; la recharge Shotgun et les durées d'effets restent inchangées.
- **Tests automatisés :** `tools/test_mobility_modules.gd` PASS : dash, obstacle, STUN,
  buff de vitesse, slow multiplicatif, cadence d'attaque et cooldowns accélérés.
- **P0-107 — implémenté, à tester manuellement :** slot défensif E avec Magnetic Field
  par défaut (préparation 0,15 s, mur perpendiculaire de 4 m centré à 2 m, durée 2,5 s,
  cooldown 12 s). Le mur absorbe les projectiles qui le traversent sans bloquer les
  robots, la mêlée, les ondes au sol ni la vision ; un placement obstrué ne consomme pas
  le cooldown. Static Shield est également implémenté comme variante défensive : stase
  immédiate 1,5 s, invulnérabilité, impossibilité d'attaquer/se déplacer/utiliser un
  module ou se soigner, interruption des préparations et dash, et BURN suspendu pendant
  la stase. Le choix se fait par la donnée `_defensive_module_id` en attendant le futur
  écran de build.
- **Tests automatisés :** `tools/test_defensive_modules.gd` PASS : mur et absorption
  Shotgun, durée, placement invalide, déplacement non bloqué, stase, dégâts/soin/BURN
  bloqués et refus d'activation sous STUN.
- **P0-108 — implémenté, à tester manuellement :** les passifs exclusifs Baroud
  d'honneur et Omnivamp sont branchés sur l'état du joueur. Baroud se déclenche une
  seule fois sur le premier coup létal, crée une jauge temporaire de 1 000 PV pendant
  2,5 s, perd 400 PV/s, refuse les soins et reste inchangé par la stase ; sa fin résout
  la mort réelle. Omnivamp rend 15 % des dégâts effectivement retirés, y compris les
  coups critiques et les ticks BURN, avec plafond de soin et sans overkill.
- **Tests automatisés :** `tools/test_passives.gd` PASS : déclenchement/épuisement de
  Baroud, soin interdit et stase non prolongeante, Omnivamp 20 → 3 PV, BURN 70 → 10,5
  PV, et résolution déterministe d'une double mort en manche nulle.
- **P0-109 — implémenté, à tester manuellement :** visibilité et perception partagent
  désormais un état par acteur. Une attaque engagée, un module accepté ou des dégâts
  reçus révèlent pendant 3 s ; une attaque ratée compte, une activation refusée non.
  SPOTTED révèle indépendamment et n'allume pas artificiellement l'état de combat.
  Les hautes herbes et les obstacles masquent les visuels/UI attachés sans supprimer
  les collisions ni les règles physiques de tir. Les volumes d'herbe portent maintenant
  leurs métadonnées de détection pour la prochaine passe de carte.
- **Tests automatisés :** `tools/test_visibility.gd` PASS : délai individuel (t=0 puis
  t=2, sortie à 5), bush hors combat, SPOTTED hors combat, révélation par dégâts,
  occultation par obstacle et activation défensive refusée sans fuite d'information.
- **Raccourcis de test actuels :** Espace = auto-attaque ; A = module offensif équipé ;
  E = module défensif équipé ; R = module mobilité ; G = changement d'arme ;
  T = recharge manuelle du Shotgun. F1–F6 restent les diagnostics du mannequin ; F7
  active/désactive le bot d'entraînement local.
- **P0-110 — passe carte engagée :** le carré jouable est élargi de 54 à 60 unités,
  les bordures et limites sont repoussées sans déplacer les spawns ni les couverts
  internes, et les bushs sont maintenant des touffes de hautes herbes plus larges,
  plus longues et plus denses. Le disque sombre au pied des bushs a été supprimé :
  aucune collision décorative n'a été ajoutée.
- **P0-111 — implémenté, à tester manuellement :** le joueur synchronise maintenant
  son entrée/sortie de hautes herbes (signal `bush_state_changed`, nom du volume actif,
  petite fenêtre de transition) et expose la même règle `is_visible_to` que le mannequin
  pour un futur bot. La détection se resynchronise immédiatement après un déplacement,
  sans modifier les collisions, les attaques ou le suivi caméra. La présentation de
  visibilité ne réactive plus par erreur les visuels BURN/SLOW/STUN/SPOTTED : un mannequin
  neuf reste visuellement neutre jusqu'à un effet réellement appliqué.
- **Tests automatisés :** `tools/test_visibility.gd` PASS pour le joueur et le mannequin :
  entrée, sortie, nom du bush, transition, occultation et SPOTTED.
- **P0-112/P0-114 — bot d'entraînement local implémenté :** activé automatiquement dans
  une partie desktop, désactivé dans les tests headless pour préserver le mannequin neutre.
  F7 active/désactive un déplacement doux dans une zone bornée,
  vérifie la ligne de vue et les bushs, puis annonce chaque frappe par un télégraphe au
  sol avant de résoudre l'impact. Un projectile orange et un flash rendent l'impact
  visible. Il inflige uniquement des dégâts simples et n'applique volontairement aucun
  BURN/SLOW/STUN/SPOTTED automatique. Une barre de PV verte et son compteur sont
  maintenant affichés au-dessus du joueur et suivent dégâts, soins, reset et Baroud.
  Leur ancrage monde est indépendant du yaw, du recul et des animations du robot, comme
  pour l'interface du mannequin. Le bot conserve une portée de combat lisible, se replace
  vers une distance idéale et esquive une attaque engagée avec une direction latérale et
  un cooldown visible par l'API de test, sans modifier les règles de dégâts ou d'effets.
- **Test automatisé :** `tools/test_training_bot.gd` PASS : état initial propre, activation,
  déplacement, maintien de portée, esquive, télégraphe, dégâts reçus, synchronisation de la
  barre PV et absence d'effets de statut injectés par le bot.
- **P0-115 — passe lisibilité et présentation :** le déplacement du bot utilise maintenant
  une vitesse amortie (accélération/décélération continues) au lieu de téléportations par
  interpolation, son mannequin possède une silhouette robotique humanoïde (tête, visière,
  torse, bras, jambes et noyau), et le shotgun dispose d'un modèle visible avec recul et
  muzzle flash. Ses plombs sont des projectiles coniques lumineux avec cœur, traînée,
  pulsation et impact ; le cône de tir est légèrement élargi (angles ±14°/±8°/±3°,
  rayon de hitbox 0,78 m) pour rendre le shotgun plus menaçant. Le projectile du bot suit
  la même grammaire visuelle. Les bushs
  passent à des touffes de hautes herbes denses avec des lames larges, une zone de cachette
  cohérente et davantage de variation de silhouette.
- **À vérifier ensuite :** test manuel du Shotgun avec G/T, du module offensif avec A et
  de la mobilité avec R, puis du défensif avec E, du passif équipé et des hautes herbes.
  Le mannequin reste passif tant que F7 est désactivé. Prochaine tâche : **P0-116 —
  faire une vérification manuelle ciblée du shotgun en jeu et ajuster ses proportions
  après retour visuel, puis ajouter une télégraphie secondaire au bot si nécessaire.

## Captures de validation

Les captures réellement rendues par Godot sont conservées dans `captures/` :

- `prototype0_before.png` : état de départ, même zone de jeu ;
- `prototype0_after.png` : vue générale après la passe visuelle ;
- `prototype0_gameplay.png` : cadrage au spawn jouable ;
- `prototype0_detail.png` : lecture rapprochée d'un couvert et du sol ;
- `prototype0_spectators.png` : cadrage de validation de la bordure extérieure ;
- `prototype0_effects.png` : capture du mannequin avec les quatre états appliqués par le
  harnais de validation (capture Mobile après attente de l'initialisation de la cible).
- `prototype0_axe.png` : capture Mobile du troisième coup Electro Axe et de ses éclairs.
- `prototype0_shotgun.png` : capture Mobile d'une salve Shotgun et de l'impact critique.
- `prototype0_shotgun_new.png` : capture Godot de la nouvelle densité de végétation et du
  mannequin robotique après la passe P0-115.
- `prototype0_shotgun_live.png` : capture Godot pendant le déplacement des projectiles
  coniques et du flash du shotgun (`shotgun_live` conserve la salve visible quelques frames).
- `prototype0_drone.png` et `prototype0_javelin.png` : captures Mobile des deux modules
  offensifs et de leurs impacts sur le mannequin.
- `prototype0_magnetic.png`, `prototype0_stasis.png` et `prototype0_baroud.png` :
  captures Mobile des défenses et de la jauge de dernière chance, générées par Godot.

Elles ont été produites avec le renderer Mobile via le pilote D3D12 sur le GPU disponible
(NVIDIA GeForce RTX 3070 Laptop GPU). Aucun nombre de FPS Android n'est déduit de cette
capture : un essai sur appareil Android reste nécessaire.

Pour refaire une capture locale depuis PowerShell :

```powershell
& 'C:\Users\Ben\Desktop\PROTOTYPE 0\Godot_v4.7.2-stable_win64_console.exe' `
  --path 'C:\chemin\vers\PROTOTYPE-0' --display-driver windows `
  --rendering-method mobile --rendering-driver d3d12 `
  --script 'res://tools/capture_scene.gd' -- 'captures\ma_capture.png' 0 0
```

## Lancer le prototype

Ouvrir `project.godot` avec Godot 4.7.2, puis appuyer sur `F6` ou `F5`.

## Commandes

- `ZQSD`, `WASD` ou flèches : déplacement ;
- souris : orienter l'attaque ;
- clic gauche ou espace : utiliser l'arme active ;
- `Espace` : auto-attaque (clic souris conservé sur PC) ; `G` : basculer Electro Axe / Shotgun ;
- `A` : module offensif équipé ; `E` : module défensif ; `R` : module mobilité ;
- `T` : recharger le Shotgun.
