# Permutation (nom provisoire)

Module de mobilité équipable dans la forge et sur le terrain d'entraînement,
compatible avec les deux joueurs du duel réseau et les bots de duel.

- Activation : ennemi vivant à 20 m maximum ; préparation de 0,18 s.
- En entraînement avec plusieurs cibles, la visée choisit une cible dans un cône
  de 25°. En duel, le module verrouille l'adversaire.
- Marque : ombre électrique guidée à 65 m/s, traversant tous les obstacles et
  champs magnétiques. Temps de vol minimum : 0,12 s. Après verrouillage, aucune
  limite de distance ni expiration ; la cible peut quitter la portée initiale.
- À l'arrivée : échange atomique des positions actuelles, sans dégâts, stun,
  silence, annulation de cast, changement d'orientation ou remise à zéro du combo.
- Bonus réservé au lanceur : déplacement +35 % pendant 3 s, cumulant normalement
  les ralentissements et la pénalité de charge du Blaster. Aucune accélération
  des attaques ou des cooldowns n'est accordée par ce module.
- Après un échange réussi uniquement, le lanceur reçoit aussi un bouclier de
  150 points pendant 3 s. Les impacts et brûlures consomment cette réserve avant
  les PV et avant Baroud ; seul le dépassement touche les PV. Aucun verrou
  d'action ni invulnérabilité de stase. Le bouclier expire, ne se cumule pas et
  disparaît à la réinitialisation. Son montant est visible et synchronisé par
  l'hôte pour les deux joueurs ; les bots bénéficient de la même protection.
- Recharge : 16 s, débutant à l'activation acceptée. Une cible absente ou hors
  portée ne consomme rien. Une préparation interrompue ou un échange devenu
  impossible conserve la recharge engagée.
- La pause fige préparation, vol et bonus. La mort, la désactivation du combat
  ou la réinitialisation d'un des combattants invalide une marque ancienne.
- Les destinations doivent accueillir les deux collisions ; aucun échange
  partiel ni placement à l'intérieur d'un obstacle. Le trajet est ignoré.

La marque libère le verrou d'action du lanceur après émission. Les actions de
l'adversaire continuent à leur position d'arrivée ; les projectiles déjà émis
gardent leur trajet. Les caches du balayage Mekatana sont recalés pour éviter
une touche fictive sur le segment de téléportation. Le réseau échange sur
l'hôte, publie les deux déplacements et leur révision, et rejette les anciennes
positions du client jusqu'à sa confirmation.

Le module n'est pas ajouté aux récompenses de Survie : cette demande vise
l'échange avec le joueur ennemi, et ses évolutions de Survie ne sont pas définies.

Validation : `tools/test_permutation.gd` couvre les bornes de portée, le délai,
les obstacles, les cibles mobiles, un trajet de 10 km, la pause, la mort et le
respawn, les collisions aux destinations, le maintien des actions, les buffs,
les répliques réseau et l'utilisation par les bots. `tools/capture_permutation.gd`
produit les vues de la marque et de l'arrivée dans le duel.

Vérifié le 1er octobre 2026 sous Godot 4.7.2 : tests Permutation, mobilité,
verrous de cast, combat réseau, sauvegarde des équipements et Mekatana
(139 contrôles) réussis. Les deux captures ont été inspectées visuellement.
Le test global des builds de bots signale encore d'autres modules ajoutés
simultanément mais absents de ses presets ; Permutation est présent et son
utilisation par un bot est validée par le test dédié. Les chemins RomainOpen
étant absents sur cet ordinateur, la validation utilise l'exécutable absolu
existant dans `.godot/pass-runtime` et le projet de cet espace de travail.

Ajout du bouclier vérifié : tests dédiés d'absorption, dépassement, brûlure,
expiration, pause, Baroud, déduplication, réinitialisation et réplication.
Les tests CombatState, combat réseau, passifs et verrous de cast passent.
La capture de l'arrivée montre la protection et les 150 points restants.
