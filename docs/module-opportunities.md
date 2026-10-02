# Purification, poursuite et ouvertures offensives

Cette passe rend les choix de modules plus utiles dans leurs situations propres.
Les dégâts directs des quatre offensifs restent inchangés.

| Module | Comportement |
| --- | --- |
| Static Shield | Activable sous STUN, projection, traction ou pendant une action, qu'il interrompt. Annule les permutations en cours et supprime BURN et toutes les sources de SLOW, y compris les cumuls de roquettes. Recharge de 12 s, durée maximale de 2 s et sortie immédiate au second appui, sur PC et tactile. Les améliorations de Survie respectent aussi cette limite. |
| Traqueur | Deux attaques d'arme distinctes sur la même cible révèlent pendant 6 s. Le repère à travers les couverts gagne en contraste, en taille et affiche le temps restant. |
| Javelin | Une téléportation réussie oriente déjà le joueur vers sa cible ; elle prépare désormais la pose de visée et applique SLOW 25 % pendant 0,8 s à la cible pour permettre une attaque manuelle. |
| Fulguro Punch | Une collision murale laisse désormais 1 s d'étourdissement. La projection libre n'étourdit toujours pas. |
| Pelto Smash | Le retour tractant applique SLOW 25 % pendant 1,1 s, afin de garder la cible à portée après la traction. |
| Panier roquettes | Chaque impact applique SLOW 7 % pendant 3 s, jusqu'à 35 % pour cinq impacts. La pression facilite la poursuite et la préparation d'un tir. |

La purification ne soigne pas, ne retire pas SPOTTED ou STUN, ne modifie pas
les boucliers et ne remet pas à zéro les identifiants d'attaques déjà reçues.
Une activation refusée ou une sortie de stase ne déclenche pas de purification.
Elle agit à l'activation, sans ajouter une immunité prolongée aux statuts.

La fenêtre du Javelin n'est accordée qu'après une téléportation réussie ; une
destination bloquée conserve la marque sans ralentir. Elle respecte la stase
de la cible. Les aspects de Survie ayant leur propre rappel sont conservés.
Le retour de Pelto ne prolonge pas son ralentissement sur un contact dupliqué.
Les ralentissements ordinaires gardent la règle du plus fort ; les sources de
roquettes s'additionnent selon leur règle existante et expirent séparément.

Les réglages communs sont partagés par les joueurs et les bots. En réseau,
l'autorité décide la purification et les ralentissements ; les répliques
reçoivent les états par les snapshots existants. Aucune attaque automatique
n'est déclenchée par ces ouvertures.

## Vérification

La suite `tools/test_module_opportunities.gd` vérifie la purification sélective,
les refus et sorties, la durée de poursuite, le Javelin, les bots, le retour
de Pelto, l'écrasement mural réel et la réception des snapshots réseau.
L'option `-- capture-opportunities` en mode graphique capture le repère du
Traqueur dans `.godot/module-opportunities-tracker.png`.

Les attentes des suites existantes Traqueur, roquettes, défense et Fulguro
sont adaptées aux nouvelles durées et intensités sans retirer les contrôles
de collisions, de cadence, de refus et d'expiration.

Validation locale sous Godot 4.7.2 : 41 contrôles de la nouvelle suite passent
en mode headless, et 42 avec la capture graphique, inspectée visuellement.
Les suites existantes passifs (état et combat), roquettes, défense, commandes,
Javelin, Pelto, Fulguro, réseau et aspects de Survie passent également.
Le test Fulguro est relancé avec `--max-fps 60` : son attente de projection
limitée en nombre d'images expire parfois en simulation headless non plafonnée.

Les journaux présentent des avertissements de certificats Windows et de
libération de ressources, ainsi que des erreurs de rappel différé du rendu
`StylizedEnvironment` lors de la suppression de visuels temporaires. Ces
messages ne font échouer aucun des contrôles de comportement ci-dessus.
La vérification réseau utilise les instances et snapshots locaux ; elle ne
remplace pas une partie sur deux machines. Les durées restent à apprécier
en partie pour affiner l'équilibrage.
