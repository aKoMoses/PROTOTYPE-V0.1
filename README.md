# Prototype 0

Premier essai technique du jeu d'arène 1 contre 1 en vue 2,5D.

## Version actuelle

La passe V0.2 ajoute la boucle de match locale complète : décompte de 3 secondes,
manches successives, score premier à 3, égalité sans point, pause pendant les états
de manche, bot désactivé hors combat et écran de résultat final. Le détail vérifié est
conservé dans [V02_PROGRESS.md](V02_PROGRESS.md).

- arène 3D plus grande que l'écran ;
- caméra inclinée suivant le joueur avec anticipation de la visée ;
- déplacement clavier AZERTY/QWERTY et flèches ;
- Blaster (tir normal ou chargé) et Shotgun à six plombs à la barre d'espace (clic souris conservé comme raccourci PC) ;
- icône « Gravure » du Blaster dans l'équipement et le HUD, avec charge sonore et tirs normal/chargé distincts ;
- obstacles bloquant le joueur et les projectiles ;
- cible d'entraînement à 1 000 PV avec affichage des dégâts, ralentissement et stun ;
- arène industrielle de récupération : sol en grandes plaques réparées, couverts blindés,
  enceinte assemblée, acier sombre, panneaux crème/rouille et signalétique rouge usée ;
  le décor mobile conserve des zones de combat calmes et lisibles.

Le lot Blaster sert à valider la perspective, la caméra, les déplacements, les hitboxes
et les sensations de combat avec le Shotgun et les modules. Les kits de vie
ne sont pas encore activés ; les bushs disposent maintenant d'une première règle de
visibilité, avant leur passe de carte jouable.

## Robots de la forge

La forge s'ouvre sur l'onglet **ROBOT**, avec les portraits de face du personnage
principal en versions Agile, Polyvalent et Puissant. Les cartes affichent les PV,
la vitesse et le robot équipé. Le choix est sauvegardé dès la sélection et repris
en duel, en entraînement et en survie. Une ancienne sauvegarde reçoit le Polyvalent
sans modifier ses armes ou modules.

| Robot | PV de base | Vitesse de base |
| --- | ---: | ---: |
| Agile | 800 | 6 m/s |
| Polyvalent | 1 000 | 5 m/s |
| Puissant | 1 200 | 4 m/s |

Les valeurs sont centralisées dans `scripts/combat_data.gd`. Les ralentissements
et le Bio Injector s'appliquent à cette vitesse ; les bonus de PV de survie
s'ajoutent aux PV du châssis. Les resets de manche gardent le robot choisi.
Les portraits sont propres à chaque châssis ; le modèle 3D animé en combat reste
le modèle actuel partagé, sans modification de ses collisions ni de ses dégâts.

Validation : `tools/test_robot_forge.gd` couvre les cartes, la sauvegarde, la
migration, les PV/vitesse, les resets et la transmission aux trois modes.
Les tests existants loadout, game flow, mobilité, passifs, entraînement et survie
passent également. Captures : `captures/robot_forge.png` et
`captures/robot_forge_mobile.png` (fenêtre paysage 2340 × 1080 sur PC ; tactile
réel non vérifié). Certains tests existants signalent des ressources audio
encore actives à la fermeture ; le test spécifique des robots se termine sans
erreur. L'équilibrage reste une première base à éprouver en jeu.

## Musique du menu

Le menu utilise « Poussière et cambouis », le troisième essai validé par l'utilisateur,
dans `art/audio/menu_poussiere_et_cambouis.wav` (Stable Audio 3 Medium, instrumental,
30 secondes, stéréo 44,1 kHz). La piste continue dans l'équipement et les réglages,
puis s'efface en 0,45 seconde au lancement du duel. Elle reprend au retour au menu.
Le raccord de 0,75 seconde ramène la boucle à 4,75 secondes pour conserver la montée
initiale seulement au démarrage. Niveau du lecteur : -10 dB.

## Musique du duel

Le match joue aussi « Poussière et cambouis » depuis
`art/audio/menu_poussiere_et_cambouis.wav`. Le fichier source choisi est conservé dans
`son-musique/musiques/03_poussiere_et_cambouis_30s.wav` ; la version du jeu possède
un raccord de fin qui ramène la boucle à 4,75 secondes.

La musique
démarre avec le premier décompte, continue entre les manches, se met en pause avec le jeu
et s'arrête au résultat final ou au retour au menu. Le niveau est réglé sous les effets sonores.

## Sons de résultat

À l'affichage du résultat final du duel, la victoire joue
`son-musique/musiques/01_victoire_rock.wav` (7 s) et la défaite
`son-musique/musiques/02_defaite_forge.wav` (5 s), une seule fois à -6 dB.
La musique du combat et le décompte s'arrêtent avant cette signature. Les manches
intermédiaires restent sans jingle ; rejouer, changer d'équipement ou revenir au menu
coupe le son de résultat en cours.

## Son du Blaster

La direction A du Blaster utilise cinq WAV dans `art/audio/` : montée de charge,
fond discret après charge complète, signal « prêt », tir normal et tir chargé.
Sur PC, le maintien historique commence immédiatement et conserve la charge partielle.
Sur mobile, le joystick droit vise et tire : relâcher avant 0,20 s demande un tir normal,
maintenir au-delà démarre la présentation de charge sans rallonger la durée totale de
1 s, puis relâcher tire une fois. La pleine charge reste armée sans tir automatique.
La charge s'arrête sans projectile en cas d'interruption, de pause, de mort ou de
changement d'arme. Les anciens MP3 restent disponibles comme sources de comparaison.

## Rendu et ressources visuelles

- Renderer conservé : **Mobile** (Godot 4.7.2).
- Ressources réutilisables dans `art/` : `arena_floor.svg`, `metal_cream.svg`,
  `metal_rust.svg`, `steel_dark.svg` et `banner_red.svg`.
- Les collisions des couverts restent séparées de leurs modules décoratifs : les petits
  panneaux, renforts et accessoires n'ajoutent pas de formes de collision individuelles.
- L'éclairage exécuté combine une direction chaude et un remplissage froid sans ombre ;
  les voyants restent émissifs, sans multiplication des lumières locales ni brouillard.

## Passe environment art — 28 septembre 2026

La scène de jeu réelle est `scenes/main.tscn` ; `scripts/main.gd` y construit l'arène à
l'exécution. La passe est donc intégrée à ce générateur, et non à une scène de démonstration
séparée. Elle remplace le grand sol sableux uniforme par un calepinage industriel calme,
habille les volumes de collision existants avec une famille de caissons blindés et de
panneaux réparés, construit la face intérieure de l'enceinte et ajoute trois repères peints
(`YARD 07`, `WEST // 03`, `EAST // 07`). Les obstacles, limites, spawns, zones de soin et
la caméra conservent leurs transformations de référence.

Le contrat automatique `tools/test_arena_contract.gd`, enregistré dans
`docs/arena_gameplay_contract.json`, valide **48 bloqueurs, 4 zones de soin et 14 bushs**.
Les 22 scripts `tools/test_*.gd` passent, dont déplacements du bot, visibilité, commandes
tactiles, Blaster normal/chargé, Shotgun, modules, états de combat et intégration VFX.
Les captures comparables sont `captures/environment_before.png`,
`captures/environment_after.png` et `captures/environment_after_mobile.png`.

Sur le même PC, à 1280×720 avec Forward Mobile/Vulkan, l'audit reproductible
`tools/audit_arena_runtime.gd` passe de 3 923 à 1 584 nœuds, de 3 325 à 1 077 meshes,
de 25 à 4 lumières et de 4 277 à 1 453 draw calls. Les primitives rendues passent de
5 078 969 à 178 381 ; le temps de processus mesuré passe de 19,616 ms à 6,882 ms.
Le compteur FPS de cette session de capture fenêtrée est trop variable pour servir de
benchmark. Ce relevé PC ne constitue donc pas une mesure de performances Android.

L'import, l'exécution Godot 4.7.2 et l'export APK debug sont validés avec la chaîne
portable JDK 17 / Android SDK du projet. À chaque push sur `main`, le workflow GitHub
réexécute toute la suite, signe un APK de release et le publie comme préversion. Le
tactile réel, la lisibilité finale et les 60 FPS doivent encore être vérifiés sur un
téléphone Android.

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
- **P0-103 — historique archivé :** l'ancienne arme de mêlée n'est plus chargée par la
  V0.1 jouable. Les effets génériques et leurs diagnostics restent disponibles.
- **Tests automatisés :** `tools/test_combat_state.gd` et `tools/test_target_dummy.gd` PASS ;
  les valeurs testées incluent BURN isolé à 70 dégâts, non-cumul, slow maximal,
  expiration, STUN/SPOTTED, overkill, overheal, attaque dupliquée, BURN absorbé pendant
  la stase, activation des quatre effets sur le mannequin et reset visuel/HP.
- `tools/test_blaster.gd` PASS : tir normal, cooldown, charge 50 %, charge maximale,
  plafond de charge, ralentissement pendant charge, changement d'arme et mort.
- **P0-104 — implémenté, à tester manuellement :** Shotgun avec six plombs indépendants à
  angles fixes (-10/-6/-2/+2/+6/+10°), portée maximale 7 m, vitesse 22 m/s et dégâts
  20 jusqu'à 3 m puis décroissance linéaire jusqu'à 8. Les obstacles absorbent chaque
  plomb. Les six impacts sur la même cible ajoutent le multiplicateur critique 1,5 et
  appliquent BURN ; cinq impacts n'appliquent pas BURN. Cadence 0,10 s de préparation
  + 0,60 s de récupération, chargeur de 3 salves, recharge automatique ou T en 1,80 s.
  G bascule Blaster/Shotgun. Les projectiles visuels partent du point d'arme et un
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
- **P0-116 — passe animation :** les deux robots disposent maintenant d'une locomotion
  mécanique légère (balancement du corps, tête et membres alternés) pilotée par leur vitesse
  réelle, sans modifier leurs collisions. Les armes ont une respiration en attente ; le
  shotgun ajoute recul du robot, recul du canon, rotation de pompage, flash et secousse
  caméra, tandis que le Blaster conserve un feedback de charge et de recul avec un
  mouvement d'attente cohérent. Les bushs ont été réduits en volume pour rouvrir les lignes
  de combat tout en gardant une couverture visuelle dense.
- **P0-117 — télégraphie secondaire du bot :** pendant son wind-up, le bot affiche désormais
  son anneau de préparation, une ligne de trajectoire au sol et une cible pulsante qui suit
  le joueur. Un marqueur vertical émissif renforce la lecture de la zone visée depuis la
  caméra oblique. Ces éléments sont visuels uniquement : ils ne créent ni dégâts, ni
  collision, ni révélation à travers un obstacle ; ils disparaissent dès que la préparation
  se termine ou si la cible n'est plus visible.
- **P0-118 — passe projectiles, impacts et états :** les familles Blaster, Shotgun,
  Modulo Drone, Javelin et projectile du bot disposent maintenant d'un départ visuel au
  point d'arme, d'un cœur/traînée lisible, d'une pulsation légère et d'un impact distinct
  sur cible ou obstacle. Les impacts hors cible déclenchent une gerbe directionnelle et
  de poussière ; les impacts de cible déclenchent flash, étincelles, réaction de corps et
  secousse caméra modérée. Le bot résout désormais son dégât à l'arrivée de son projectile,
  au même moment que son flash et son anneau d'impact. Les états BURN/STUN gagnent des
  braises et étincelles discrètes ; SPOTTED possède un œil cyan plus lisible avec anneau
  et pupille animés. Les paramètres de dégâts, cadence, portée, munitions, durées et
  collisions n'ont pas été modifiés.
- **Vérifications automatisées après P0-118 :** en mode `--headless`,
  `tools/test_blaster.gd`, `tools/test_shotgun.gd`, `tools/test_offensive_modules.gd`,
  `tools/test_target_dummy.gd`, `tools/test_training_bot.gd` et `tools/test_visibility.gd`
  PASS. Le test Blaster neutralise explicitement le bot mobile pendant ses assertions
  à positions fixes ; la partie jouable conserve le bot desktop activable par F7.
- **Validation Godot réelle :** captures exécutées avec Godot 4.7.2, renderer Mobile,
  Vulkan Forward Mobile sur la GeForce RTX 3070 Laptop. Les captures P0-118 sont
  `prototype0_fx_pass_shotgun_live.png`, `prototype0_fx_pass_shotgun.png`,
  `prototype0_fx_pass_axe.png`, `prototype0_fx_pass_drone.png`,
  `prototype0_fx_pass_effects.png` et `prototype0_fx_pass_bot.png`. Elles servent à
  contrôler la composition, les projectiles, les trois coups de l'axe, les modules et la
  lisibilité des états ; le test de framerate Android reste à faire sur appareil réel.
- **P0-119 — budget d'effets implémenté :** la scène suit les nœuds temporaires de type
  `particle`, `burst` et `projectile`, avec plafonds respectifs de 24, 42 et 14 éléments.
  Les plus anciens sont supprimés lorsque le plafond est dépassé ; les durées normales
  et les collisions ne changent pas. Le budget est utilisé par les projectiles, flashs,
  anneaux, arcs électriques, impacts et particules des armes, du mannequin et du bot.
  `tools/test_fx_budget.gd` vérifie le plafonnement à 42 bursts actifs.
- **À vérifier ensuite :** test manuel prolongé en mouvement (Espace, A, E, R, G/T),
  observation du projectile du bot avec F7 dans une ligne de vue dégagée, et mesure du
  framerate sur appareil mobile réel.
- **P0-120 — première couche tactile :** `touch_controls.gd` ajoute un joystick de
  déplacement, un joystick de visée et cinq boutons (attaque, A, E, R, G). Le panneau est
  automatiquement visible sur une cible tactile/mobile et reste masqué sur PC ; les
  raccourcis clavier/souris et les règles de combat ne changent pas. Les actions tactiles
  passent par les mêmes fonctions que les commandes desktop afin de conserver les
  cooldowns, hitboxes, collisions et effets existants. Le build Android et le framerate
  sur appareil réel restent à valider dès qu'un environnement d'export et un téléphone
  seront disponibles.
- **P0-121 — layout tactile responsive :** les zones de contrôle utilisent maintenant la
  safe area renvoyée par Godot, une échelle dérivée du plus petit côté de l'écran et des
  marges adaptées aux formats portrait/paysage. Les joysticks, boutons et libellés restent
  dans la zone sûre ; la disposition desktop et le rendu de jeu PC ne changent pas.
  `tools/test_touch_controls.gd` confirme l'initialisation et le câblage des actions.
- **P0-122 — prévisualisation mobile Godot :** le paramètre utilisateur `touch_preview`
  force l'affichage des contrôles sur PC pour inspecter leur disposition sans appareil.
  Une capture réelle en renderer Mobile a été vérifiée en 1280×720 : joystick, visée et
  boutons restent lisibles et dans la fenêtre. Ce mode est désactivé par défaut et n'a
  aucun effet sur le build desktop ou mobile normal.
- **P0-123 — preset Android :** `export_presets.cfg` contient maintenant un preset
  Android nommé `Android`, en paysage, package `com.prototype0.arena`, version `0.2.0`
  et architecture ARM64. La sortie debug prévue est `exports/prototype0-debug.apk`.
  Le preset a d'abord été préparé avant l'installation locale des dépendances ; l'export
  fonctionnel et sa vérification sont documentés en P0-124 puis P0-130.
- **Limite de validation :** aucune capture tactile réelle ni export Android n'a été
  exécuté dans cet environnement ; la validation finale sur téléphone reste nécessaire.
- **Prochaine tâche historique :** P0-125 — installer l'APK sur un téléphone réel, puis
  mesurer le framerate et la lisibilité pendant le parcours de test manuel. Cette tâche
  reste ouverte après les lots interface et manche ci-dessous.
- **P0-124 — APK debug produit :** l'export Godot 4.7.2 a réussi avec la commande
  `godot --headless --path . --export-debug Android exports/prototype0-debug.apk`.
  L'APK se trouve dans `exports/prototype0-debug.apk` (35 707 755 octets). `aapt` a
  confirmé le package `com.prototype0.arena`, `versionCode=1`, `versionName=0.1.0`,
  et l'archive ne contient que `lib/arm64-v8a`. `apksigner verify --verbose` confirme
  les signatures APK v2 et v3. La compression ETC2/ASTC est activée dans le projet
  pour satisfaire l'export Mobile.
- **Installation/lancement physique :** aucun appareil Android autorisé n'a été
  détecté. ADB ne peut pas initialiser son dossier utilisateur dans cet environnement ;
  l'APK est donc produit et vérifié, mais ni installé ni lancé sur téléphone. Il reste
  à transférer l'APK sur le téléphone, autoriser l'installation depuis cette source,
  puis ouvrir `Prototype 0` pour le parcours de test manuel.

## Passe V0.2 — 26 septembre 2026

- **V02-01 :** routes jouables limitées au Blaster et au Shotgun ; les anciens
  identifiants d'arme sont migrés vers le Blaster sans modifier les valeurs de combat.
- **V02-02 :** `PrototypeGameFlow` est l'autorité unique du score et des transitions.
  Le décompte verrouille les commandes, chaque mort ne résout qu'une fois la manche,
  l'égalité ne donne aucun point et le match se termine au premier score de 3.
- **V02-03 :** le bot mémorise la dernière position visible, respecte obstacles/bushs,
  est désactivé hors manche et repart proprement au reset.
- **V02-04 :** écran équipement détaillé, HUD score/phase, charge du Blaster,
  munitions/recharge Shotgun, PV et états des deux acteurs.
- **V02-05 :** `tools/test_game_flow.gd` couvre les transitions, pause, score unique,
  égalité, reset et fin de match ; l'ensemble des tests précédents reste PASS.
- **V02-06 :** preset Android passé au version code 2 / nom 0.2.0 ; l'APK sera
  régénéré et vérifié après cette passe.

## Captures de validation

Les captures réellement rendues par Godot sont conservées dans `captures/` :

- `prototype0_before.png` : état de départ, même zone de jeu ;
- `prototype0_after.png` : vue générale après la passe visuelle ;
- `prototype0_gameplay.png` : cadrage au spawn jouable ;
- `prototype0_detail.png` : lecture rapprochée d'un couvert et du sol ;
- `prototype0_spectators.png` : cadrage de validation de la bordure extérieure ;
- `prototype0_effects.png` : capture du mannequin avec les quatre états appliqués par le
  harnais de validation (capture Mobile après attente de l'initialisation de la cible).
- `prototype0_axe.png` : capture historique de l'ancienne arme, non chargée en V0.1.
- `prototype0_shotgun.png` : capture Mobile d'une salve Shotgun et de l'impact critique.
- `prototype0_shotgun_new.png` : capture Godot de la nouvelle densité de végétation et du
  mannequin robotique après la passe P0-115.
- `prototype0_shotgun_live.png` : capture Godot pendant le déplacement des projectiles
  coniques et du flash du shotgun (`shotgun_live` conserve la salve visible quelques frames).
- `prototype0_bot_telegraph.png` : capture Godot pendant le wind-up du bot, avec sa ligne de
  danger, sa cible pulsante et son marqueur visuel.
- `prototype0_fx_pass_bot.png` : capture Godot du bot et de son télégraphe après la passe
  d'impact synchronisé.
- `prototype0_fx_pass_shotgun_live.png` et `prototype0_fx_pass_shotgun.png` : captures
  Godot de la bouche du shotgun, des plombs coniques, des impacts et de la réaction cible.
- `prototype0_fx_pass_axe.png` : capture historique de l'ancienne arme, non chargée en V0.1.
  d'onde/éclairs.
- `prototype0_fx_pass_drone.png` : capture Godot du projectile Drone et de sa traînée cyan.
- `prototype0_fx_pass_effects.png` : capture Godot de BURN, SLOW, STUN et SPOTTED renforcés.
- `prototype0_drone.png` et `prototype0_javelin.png` : captures Mobile des deux modules
  offensifs et de leurs impacts sur le mannequin.
- `prototype0_magnetic.png`, `prototype0_stasis.png` et `prototype0_baroud.png` :
  captures Mobile des défenses et de la jauge de dernière chance, générées par Godot.

Elles ont été produites avec le renderer Mobile via le pilote D3D12 sur le GPU disponible
(NVIDIA GeForce RTX 3070 Laptop GPU). Aucun nombre de FPS Android n'est déduit de cette
capture : un essai sur appareil Android reste nécessaire.

Pour refaire une capture locale depuis PowerShell :

```powershell
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' `
  --path 'C:\RomainOpen\perso\Studio\game-source' --display-driver windows `
  --rendering-method mobile --rendering-driver d3d12 `
  --script 'res://tools/capture_scene.gd' -- 'C:\RomainOpen\perso\Studio\game-source\captures\ma_capture.png'
```

## Lancer le prototype

### Tester chaque version sur Android depuis le telephone

Chaque push sur `main` lance `.github/workflows/android-test-release.yml` : import Godot
4.7.2, tests, export Android signe, puis publication d'une preversion avec l'APK dans
[les Releases](https://github.com/aKoMoses/PROTOTYPE-V0.1/releases). En cas d'echec,
aucune nouvelle APK n'est publiee. L'historique des builds se trouve dans l'onglet
[Actions](https://github.com/aKoMoses/PROTOTYPE-V0.1/actions).

Configuration unique, sur le PC qui possede Godot/Java et le projet Git :

1. Installer [GitHub CLI](https://cli.github.com/) et lancer `gh auth login`.
2. Dans PowerShell, depuis la racine du depot, lancer
   `powershell -ExecutionPolicy Bypass -File .\tools\setup-android-signing.ps1`.
   Le script cree une cle de test stable, puis renseigne les deux secrets du depot.
3. Sauvegarder le dossier `.android-signing` hors du depot (cle et mot de passe).
   Il est ignore par Git. Une cle perdue empeche de mettre a jour l'application
   deja installee sans la desinstaller.
4. Depuis GitHub, dans **Actions > Android test APK**, lancer **Run workflow** pour
   produire la premiere APK. Verifier la publication dans **Releases**.
5. Sur Android, installer [Obtainium](https://github.com/ImranR98/Obtainium/releases),
   ajouter `https://github.com/aKoMoses/PROTOTYPE-V0.1`, activer la prise en compte
   des **prereleases**, puis installer `prototype0-android.apk` depuis Obtainium.

Pour les versions suivantes, un push sur `main` suffit. Obtainium detecte la nouvelle
Release et propose l'installation ; Android peut demander de la confirmer. Si une
ancienne APK Prototype 0 a ete signee avec une autre cle, la desinstaller **une fois**
avant d'installer la premiere APK issue de cette chaine (la desinstallation efface
les donnees locales de l'application).

La cle est reservee aux builds de test. Conserver une cle differente si une version
est publiee un jour sur une boutique. Les APK des Releases de ce depot public sont
accessibles publiquement.

Ouvrir `project.godot` avec Godot 4.7.2, puis appuyer sur `F6` ou `F5`.

### Menu principal

Le bouton **TRAINING GROUND** ouvre une carte dédiée d'entraînement. Elle contient
trois mannequins fixes de tailles et de zones de touche différentes, un mannequin
mobile et un tireur fixe qui lance un tir simple toutes les 1,5 secondes lorsqu'il
voit le joueur. La carte sépare les trois couloirs de cibles fixes, la piste de la
cible mobile, la zone de tir reçu et un espace de placement libre. Des repères au
sol, des passages entre les secteurs, quelques caisses et balises indiquent où
s'entraîner ; les cinq mannequins de départ sont espacés d'au moins 8 m. Le
placement reste possible sur les surfaces libres de toute la carte.
Le sous-menu Tab regroupe le build, les mannequins et les règles d'essai. Changer un
équipement l'applique et le sauvegarde immédiatement. On peut placer jusqu'à 12
mannequins fixes, en supprimer un par clic ou tous les retirer. Le placement montre
un aperçu vert ou rouge ; clic droit ou Échap annule l'outil. Après un KO, chaque
mannequin revient avec ses PV après 0,75 s pour permettre les essais longs.
Le reset restaure les PV, munitions, cooldowns, effets et positions des mannequins
mobiles sans retirer les mannequins placés.

Sur le terrain : **Tab** ouvre ou ferme le sous-menu, **F5** réinitialise l'essai,
**F6** bascule l'invulnérabilité, **F7** les cooldowns instantanés, **F8** les
munitions illimitées, **F9** soigne le joueur et **F10** le met à 50 % de ses PV.
**K** masque ou ouvre le kikimètre. Il affiche les dégâts effectivement infligés,
le DPS des 5 dernières secondes, la durée depuis le premier coup et la répartition
par arme, module et brûlure ; on peut filtrer par cible. Le temps se fige avec le
menu Tab et F5 vide aussi la mesure. Ces commandes sont également disponibles en
boutons dans le sous-menu ; le kikimètre a un bouton tactile compact sur mobile.

Le menu utilise les textures de plaque et de boutons dans `art/ui/menu/`, ainsi que
la police Russo One dans `art/ui/fonts/`. Son fond
simule en boucle trois mini-clips de combat de 3 secondes, joués en direct avec les
robots et l'arène du jeu. Le cadrage et l'arme changent d'un clip à l'autre ; aucun
fichier vidéo n'est lu.
Les trois captures Godot sont conservées dans `captures/menu-redesign-preview.png`,
`captures/menu-redesign-clip-2.png` et `captures/menu-redesign-clip-3.png`.

### Mode Survie

Le bouton **MODE SURVIE** ouvre une partie indépendante du duel et du Training Ground.
On choisit le Blaster ou le Shotgun au départ. Cette arme est moins puissante qu'en duel
et reste la seule arme de la partie (`G` est désactivé). Les emplacements de modules et
le passif commencent vides.

Le mode comprend 12 vagues. Terminer chaque vague de 1 à 11 donne un niveau et un choix
entre deux récompenses ; le jeu se fige pendant ce choix. Les quatre premières
récompenses font choisir, dans cet ordre, un module offensif, défensif, de mobilité,
puis un passif. Les suivantes proposent une évolution propre à l'objet avec gain de puissance, ou du rythme ;
une fois l'évolution prise, elles proposent puissance ou rythme. Le passif peut aussi
gagner des PV maximum. Les équipements démarrent affaiblis puis
peuvent dépasser leurs valeurs de duel. Le joueur récupère 150 PV après chaque choix,
sans réinitialisation complète entre les vagues. La douzième vague ajoute un ennemi
plus résistant ; la partie s'achève sur une victoire ou à la mort du joueur.

La musique de Survie change avec les vagues : variation retenue aux vagues 1 à 4,
« La forge s'emballe » aux vagues 5 à 8, puis variation plus dense aux vagues 9 à 12.
Chaque piste dure une minute et boucle depuis la vingtième seconde pour ne jouer sa
montée initiale qu'une fois. Un fond plus calme accompagne le choix des améliorations.
Les changements de piste se font en fondu ; la pause suspend la musique et le résultat
l'arrête.

L'arène est une casse automobile avec trois épaves servant de couverts, des carcasses
et des tas de ferraille sur le pourtour. Avant chaque vague, un compte à rebours et des
cercles colorés annoncent les points d'arrivée. Les ennemis ont trois rôles : poursuivant
au contact, tireur fragile qui garde ses distances et chargeur dont la trajectoire est
annoncée au sol. Le broyeur final alterne charge et salve de trois projectiles.

Chaque équipement possède une évolution distincte : percée du Blaster, gerbe élargie
du Shotgun, rebond du Drone, explosion du Javelin, décharges du Champ magnétique,
onde du Bouclier statique, traînée des Pyro Boots, onde du Bio Injector, riposte de
Baroud ou soin à l'élimination d'Omnivamp. Les choix affichent les valeurs de l'effet
ou de la recharge avant et après amélioration.

Les commandes `A`, `E` et `R` deviennent utilisables à mesure que leurs modules sont
obtenus. Le HUD montre la vague et les cooldowns. Échap ou le bouton PAUSE ouvre
le build complet avec ses améliorations ; le résultat permet de recommencer ou de revenir au menu.
Le test de parcours est `tools/test_survival.gd`.

## Commandes

- `ZQSD`, `WASD` ou flèches : déplacement ;
- souris : orienter l'attaque ;
- clic gauche ou espace : utiliser l'arme active ;
- `Espace` : auto-attaque (clic souris conservé sur PC) ; `G` : basculer Blaster / Shotgun ;
- `A` : module offensif équipé ; `E` : module défensif ; `R` : module mobilité ;
- `T` : recharger le Shotgun.

Sur mobile paysage, le joystick gauche déplace le personnage et les trois modules sont
regroupés en arc autour de celui-ci. Le joystick droit, placé dans l'angle inférieur
droit de la zone sûre, vise et tire au relâchement : geste bref pour un tir normal,
maintien pour charger, changement de direction possible pendant toute la charge.

## Suivi systèmes — 26 septembre 2026

- **P0-126 — navigation et équipement :** le lancement desktop ouvre désormais un menu
  principal, puis un écran d’équipement avec les deux armes et les deux variantes de
  chaque catégorie. Les identifiants sont validés et sauvegardés dans
  `user://prototype0_loadout.cfg` ; une valeur invalide retombe sur le build par défaut.
  `scripts/loadout_state.gd` lit les noms et statistiques depuis `combat_data.gd`.
- **P0-127 — HUD, tactile et réglages :** l'ancien bloc de diagnostic permanent est
  remplacé en combat par un HUD compact (PV, états, arme, munitions, cooldowns réels,
  passif et pause). Les contrôles tactiles restent sur la même couche et peuvent être
  redimensionnés entre 85 % et 115 %. Les réglages de secousse caméra et de taille tactile
  sont persistants dans `user://prototype0_settings.cfg`.
- **P0-128 — manche locale :** Jouer initialise le build sélectionné, active le bot,
  désactive les commandes derrière les menus, puis mène à une manche Victoire/Défaite/
  Égalité. La pause suspend l'arbre de jeu et décale les horloges absolues de combo et de
  marque. Rejouer nettoie les FX temporaires et réinitialise PV, munitions, cooldowns et
  passifs. Le mannequin ne se réinitialise plus automatiquement en mode duel ; son
  comportement de laboratoire est conservé hors duel.

## Remplacement d'arme — 26 septembre 2026

- **P0-129 — Blaster :** la V0.1 jouable contient maintenant uniquement `blaster` et
  `shotgun`. Le Blaster tire 20 dégâts, portée 14 m, projectile 24 m/s et cooldown 0,45 s.
  Un maintien de tir charge pendant 1 s jusqu'à 50 dégâts ; la vitesse de déplacement est
  réduite à 80 % pendant la charge, puis restaurée au relâchement, au changement d'arme ou
  à la mort. Aucun effet BURN/SLOW/STUN/SPOTTED n'est appliqué par le Blaster de base.
- **Tests :** `tools/test_blaster.gd` couvre tir normal, cooldown, charge 50 %, charge
  maximale et prolongée, vitesse, annulation et régression. Tous les tests `tools/test_*.gd`
  disponibles passent dans Godot 4.7.2 en mode headless.
- **Compatibilité Android :** le bouton tactile d'attaque séparé est supprimé. Le doigt du
  joystick droit possède seul le cycle viser/maintenir/relâcher ; son dernier vecteur valide
  est capturé avant recentrage. Le Shotgun conserve sa cadence et son chemin de tir existants.
- **P0-129 — bot :** le déplacement vérifie maintenant les obstacles et applique SLOW/STUN
  à son comportement. Le projectile revalide sa trajectoire et sa proximité à l'impact,
  y compris l'absorption par un Magnetic Field ; un tir interrompu ne cause aucun dégât.
- **Tests ajoutés :** `tools/test_game_flow.gd` et `tools/test_loadout_state.gd`. Le premier
  vérifie menu → duel → pause → mort réelle → résultat → rejouer ; le second vérifie la
  validation et la persistance (l'écriture `user://` est indisponible dans le sandbox de
  vérification actuel, mais le chemin de production est actif dans l'application).
  Les tests de combat existants restent PASS après cette intégration.

### Captures de cette étape

- `captures/menu_current.png` : menu principal Godot en 1280×720 ;
- `captures/equipment_current.png` : écran d'équipement et choix actifs ;
- `captures/duel_current.png` : HUD compact en manche jouable.
- `captures/result_current.png` : écran Victoire après résolution d'une mort réelle.

La validation visuelle ci-dessus a été faite avec Godot 4.7.2, renderer Mobile et Vulkan
sur le GPU disponible. Le parcours Android tactile et le framerate sur appareil réel
restent à vérifier séparément.

- **P0-130 — APK V0.2 après intégration :** export debug réussi dans
  `exports/prototype0-debug.apk` (37 725 703 octets, SHA-256
  `C6F3BC144242C90A459FD2F4E33596D0B6F053D18BAC08FC621F2B0EA850019B`). `aapt` confirme
  le package `com.prototype0.arena`, `versionCode=2`, `versionName=0.2.0`, min/target
  SDK 24/36 et ARM64 ; `apksigner` confirme les schémas v2 et v3. Aucun téléphone
  n'est connecté ici : installation, tactile réel et FPS Android restent à mesurer
  sur appareil.

### Captures V0.2 réellement produites

`captures/v02_menu.png`, `captures/v02_equipment.png`, `captures/v02_duel_live.png` et
`captures/v02_result.png` ont été rendues par la scène Godot avec le renderer Mobile.
La capture résultat montre une victoire de manche 1–0 ; le bouton de manche suivante
est volontairement masqué pendant le délai automatique de deux secondes.

## Animation du robot joueur — 27 septembre 2026

- **P0-131 — contrôleur GLB intégré :** le modèle animé est isolé sous `VisualRoot` ;
  la correction d'axe +Z → -Z n'agit que sur son wrapper. Le root motion horizontal
  des clips `walk` et `run` est neutralisé dans des bibliothèques dupliquées à l'exécution,
  en recalant les clés Hips sur la pose de repos. Le `CharacterBody3D` garde seul la
  position et l'orientation gameplay ; l'orientation visuelle suit la visée et un
  modificateur sépare l'orientation des jambes de celle du torse.
- `AnimationTree` sépare maintenant `BasePose` (idle/actions complètes), locomotion
  (walk/run filtrés sur le bassin et les jambes) et `UpperBodyFire` (OneShot filtré sur
  43 pistes du torse, des bras et de la tête). Le clip `fire` d'origine contient 53 pistes,
  dont les hanches et les jambes ; il ne remplace donc plus la course et ne peut plus
  réinitialiser son cycle. `walk` et `run` ont leur machine d'état dédiée.
- Les armes suivent `Skeleton3D → mixamorig_RightHand → BoneAttachment3D → WeaponSocket →
  WeaponRoot`. Les offsets de socket sont calibrés une fois après la pose idle ; le sway
  et le recul sont limités à des pivots locaux sous l'arme. Le projectile et le flash
  partent du `Muzzle` porté par cette chaîne, sans transform monde concurrente. Blaster
  et shotgun exposent aussi un `LeftHandGrip` local pour une future IK, non activée tant
  que son résultat n'a pas été validé visuellement.
- Les API `set_move_input(Vector2)` / `set_aim_input(Vector2)` alimentent le même contrôleur
  que les joysticks tactiles. F8 affiche les vecteurs diagnostic déplacement (bleu), visée
  (rouge) et orientation du modèle (vert).
- **Vérification :** `tools/test_player_visual_rig.gd` — 47 contrôles réussis ; suite
  `tools/test_*.gd` — 15/15 réussis avec Godot 4.7.2 en mode headless. Le rendu en fenêtre
  et l'essai sur appareil Android restent à contrôler par le testeur.
