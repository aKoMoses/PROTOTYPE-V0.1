# Renforcement des armes et modules — 2 octobre 2026

Passe approuvée après revue du catalogue. Les valeurs communes sont dans `scripts/combat_data.gd`, et les descriptions de sélection suivent les nouveaux réglages. Les armes et modules déjà efficaces conservent leur identité.

## Armes

| Arme | Résultat |
| --- | --- |
| Mekatana | Bases 90/100/150 ; combo complet sur une cible 90+120+240 = 450. Récupération du troisième coup 0,35 s, cycle total 1,55 s. Dashes et règles de combo conservés. |
| Shotgun | 28 dégâts par plomb au plus près, minimum lointain conservé à 8. Recharge 1,40 s ; six plombs donnent 168 dégâts avant critiques et effets. |
| Longshot | Refonte terminée dans sa réservation dédiée : 90–202,5 dégâts, cadence 0,85 s, deux impacts préparent EXÉCUTION à ×1,8 (jusqu'à 364,5), traversée des ennemis et vitesse +20 % pendant 0,7 s après impact. Voir [Longshot](longshot-execution.md). |
| Blaster | Réglages renforcés déjà intégrés conservés : 100–360 dégâts, charge maximale 0,45 s, cadence 0,20 s et mobilité complète pendant la charge. |

## Modules offensifs

| Module | Résultat |
| --- | --- |
| Rocket Basket | 35 dégâts par missile, 175 pour cinq impacts directs. Vitesse 10 m/s, guidage ajusté à 12 pour éviter l'orbite autour d'une cible proche ; délai et montée du guidage conservés. |
| Javelin | Charge maximale 1,20 s, dégâts 140–280 conservés. Un impact absorbé par un bouclier marque également la cible et permet la téléportation. Les impacts rejetés ne marquent pas. |
| Fulguro Punch | Charge maximale 1,80 s. Dégâts 200–400 et collision murale 150–250 conservés. |
| Pelto Smash | Retour à 18 m/s et traction de 1,5 m. Dégâts aller/retour 160+100 conservés. |

## Modules défensifs

| Module | Résultat |
| --- | --- |
| Counter | SURCHARGE +80 dégâts, garde 1,1 s. Une seule explosion par attaque composée, sans Omnivamp secondaire. |
| Magnetic Field | Durée 3 s. Recherche d'un placement voisin valide si le placement visé est occupé ; ne traverse pas les obstacles et ne consomme pas la recharge si aucun emplacement ne convient. |
| Static Shield | Stase maximale 1,5 s, sortie volontaire par une seconde commande après 0,5 s. Le bouton tactile affiche SORTIR ; l'hôte valide la sortie et la réplique l'affiche. La recharge reste consommée. |
| Projector | Mécanique et valeurs conservées. |

## Mobilité et passifs

| Élément | Résultat |
| --- | --- |
| Pyro Boots | Deux charges conservées, explosion au départ de 60 dégâts dans 2 m. Respecte couverts, équipes, autorité réseau et unicité des victimes. Le soin Omnivamp est crédité une fois. |
| Bio Injector | Durée 4 s, recharge 15 s. Signal visuel et texte à la dernière seconde, puis indication de fin. Les multiplicateurs existants sont conservés. |
| Permutation | Recharge 12 s. Échange, bouclier et vitesse conservés. |
| Eclipse | Valeurs et déplacement conservés. |
| Réacteur auxiliaire | −0,60 s de recharge offensive par attaque d'arme admissible, intervalle interne 0,75 s. |
| Traqueur | Deux attaques distinctes révèlent pendant 4 s ; intervalle entre marques 4 s. |
| Alternateur | Prochaine attaque d'arme +30 %, fenêtre 3 s. |
| Inertie | Ralentissement 25 % pendant 1,5 s, fenêtre 2,5 s. S'arme après Pyro terminé, Bio activé, Permutation ou Eclipse arrivé. Aucun bonus après une mobilité refusée ou interrompue, ni après Javelin ou dash d'arme. |
| Baroud / Omnivamp | Valeurs conservées ; Omnivamp reste à 15 %. |

## Vérification

`tools/test_catalogue_comfort.gd` passe 40 contrôles en scène réelle : stase et sortie PC/tactile/réseau, marque et recast Javelin sur bouclier, explosion Pyro avec couverts/équipes, placement du mur et recharge refusée, quatre mobilités avec Inertie, annulations, absence de dégâts sur réplique et absence de double soin réseau.

Suites de comportement réussies sous Godot 4.7.2 : Mekatana (139), bots, réseau (20) et survie ; Shotgun ; Rocket Basket ; Javelin ; Fulguro ; Pelto ; Counter (55) et armes/réseau (55) ; les deux suites des nouveaux passifs ; modules offensifs, défensifs et mobilité ; Permutation ; commandes et icônes tactiles ; combat réseau ; aspects et récompenses de survie. Le Longshot a ses 553 contrôles dans son travail dédié. Import éditeur sans erreur de script et contrôle des espaces du diff réussis.

Certains passages des suites existantes Mobility, Fulguro, Pelto et Survival Aspects affichent des ressources audio encore utilisées à la fermeture, après PASS. Un contrôle verbose de Mekatana Network a identifié des playbacks WAV du mixeur ; le nettoyage explicite de GameSfx et l'attente du mixeur suppriment ces avertissements dans les suites Mekatana Network, Counter et New Passive Combat. Le runtime signale aussi le magasin de certificats Windows indisponible.

Les attentes des suites existantes sont ajustées aux valeurs approuvées, en conservant leurs contrôles de collisions, interruptions, autorité, équipes et unicité. Les tests réseau exécutent localement les gestionnaires hôte/réplique ; aucune partie entre deux appareils ni mesure de ressenti en parties humaines n'est incluse.
