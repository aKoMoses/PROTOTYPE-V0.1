# Fluidité du combat — 2 octobre 2026

Les commandes d'arme et de module nouvellement pressées peuvent être anticipées
de 140 ms pendant une action, une recharge ou une indisponibilité brève. Une seule
commande est conservée : la dernière intention remplace la précédente. Elle
expire si le blocage dure trop longtemps, sans consommer de munition ni de recharge.
Les touches déjà tenues avant une interruption ne redémarrent pas une attaque.
Le buffer historique des taps PC du Blaster et les sorties défensives de Fulguro
sont conservés.

La commande suivante est exécutée après les mises à jour des actions, dès la
libération du verrou. Les durées de préparation et de récupération restent celles
des armes. Un contact tactile relâché pendant l'attente devient un tap ; un contact
encore tenu démarre sa charge à l'acceptation. Un relâchement de module déjà reçu
est transmis à la charge différée. Pause, perte de focus, changement d'équipement,
reset et stun accepté invalident les commandes concernées. Un stun ignoré ne
coupe pas l'action en cours. Les reprises passent par l'API du joueur réseau.

Pyro Boots glisse sur les impacts obliques avec les couverts, en utilisant
uniquement le mouvement restant après le contact. Les impacts presque frontaux
s'arrêtent ; les coins ne traversent pas les collisions. La distance et la durée
du dash restent inchangées, ainsi que ses charges et ses effets.

Le premier stun conserve sa durée. Les stuns suivants dans les deux secondes
après le dernier prennent 50 %, puis 25 % de leur durée. L'extension d'un stun
continu est plafonnée à 350 ms au-delà de sa fin initiale et sa sortie donne
180 ms de protection contre un nouveau stun. Cette résistance est réinitialisée
entre les manches et incluse dans les snapshots réseau. Les dégâts, les
ralentissements et les déplacements forcés gardent leurs règles existantes.

La caméra suit plus rapidement le corps du robot, avec une anticipation de visée
réduite de 1,6 à 0,9 unité et un déplacement de cette anticipation limité à
1,8 unité/s. Le suivi du corps, la visée et les secousses sont calculés séparément,
pour empêcher les secousses de laisser une dérive dans le suivi.

## Vérification

`tools/test_gameplay_fluidity.gd` vérifie les quatre armes, les appuis PC et
tactiles, les commandes expirées ou annulées, la fin de recharge, la transition
Fulguro/dash, les stuns successifs, le reset, les snapshots et les contacts réseau,
les collisions frontales et obliques ainsi que le suivi et les secousses de caméra.
Le test utilise un état clavier simulé ; les suites existantes des entrées PC et
tactiles vérifient aussi le routage réel de leurs événements.

La suite spécifique compte 47 vérifications. Elle et les quinze suites de
régression passent sous Godot 4.7.2 ; le chargement dans l'éditeur est également
contrôlé. Le runtime Windows signale son magasin de certificats indisponible,
et la fermeture de certains tests réseau conserve des ressources signalées
par Godot ; ces sorties sont conservées dans les journaux de test locaux.

Les suites de régression couvrent CombatState, mobilité, Blaster, Shotgun,
Longshot, Mekatana, verrouillage des actions, contrôles tactiles, transitions
d'entrée, pause des modes, combat réseau, Fulguro, Pelto et guides de visée.
Les sauvegardes des tests sont isolées sous `.godot/fluidity-*`.

Le moteur indiqué dans AGENTS.md est absent de ce poste ; les vérifications
utilisent le Godot 4.7.2 fourni dans `.godot/pass-runtime/`, par chemin absolu.
La validation automatisée vérifie le comportement ; les réglages de sensations
restent à éprouver en partie. Aucun test sur téléphone physique ni nouvelle APK
n'est inclus dans cette passe.

Pour la publication groupée du 2 octobre, le contrat d'arène est actualisé uniquement pour les réglages de caméra de cette passe : suivi à 8,0 et anticipation à 0,9. Les signatures des collisions, buissons, soins, spawns et projection restent inchangées.
