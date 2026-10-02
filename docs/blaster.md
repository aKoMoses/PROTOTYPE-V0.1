# Blaster surpuissant

Le Blaster privilégie désormais une puissance immédiate et une charge nerveuse.
Les valeurs communes s'appliquent au joueur, aux bots et au combat réseau.
La Survie conserve ses multiplicateurs de puissance et ses évolutions.

| Paramètre | Avant | Maintenant |
| --- | ---: | ---: |
| Dégâts simples | 20 | 100 |
| Dégâts à pleine charge | 50 | 360 |
| Récupération après tir | 0,45 s | 0,20 s |
| Pleine charge | 1 s | 0,45 s |
| Portée | 14 m | 24 m |
| Vitesse simple / chargée | 40 / 72 m/s | 57,6 / 115,2 m/s |
| Taille visuelle à pleine charge | ×2,6 | ×3,2 |
| Mobilité pendant la charge | 80 % | 100 % |

Le débit théorique des tirs simples passe de 44,4 à 500 dégâts/s, hors gestes
d'entrée. Trois tirs pleinement chargés retirent 1 080 PV avant protections.
Le maintien conserve le tir au relâchement, avec interpolation des dégâts.
La collision reste une trajectoire précise et les murs arrêtent les tirs.
La taille du plasma chargé est visuelle ; elle ne remplace pas la collision
existante par une explosion ou une recherche automatique de cible.

Le dernier ajustement réduit la vitesse des tirs simples et chargés de 10 %.
Le plasma gagne environ 23 % de largeur visuelle et adopte une forme plus
courte, aux extrémités arrondies, pour le joueur et les bots.
Cet ajustement a été vérifié avec les tests du Blaster, des équipements des
bots et du combat réseau, ainsi qu'une comparaison visuelle dans Godot 4.7.2.

Les bots calculent maintenant leur charge comme une fraction du temps partagé,
pour conserver des tirs courts et longs avec le nouveau délai. La description
et les statistiques de la Forge utilisent les données communes.

Validation Godot 4.7.2 : tests du Blaster (PC/tactile, charge partielle et complète,
cadence, annulations, esquive, tirs simples et chargés à 20 m, arrêt au mur et
expiration à portée maximale), équipements des bots, verrouillage des actions,
contrôles tactiles, Survie, aspects de Survie, équipement sauvegardé et combat
réseau : huit suites réussies. Le ressenti en partie reste à apprécier en jeu.
