# Signatures des actions réussies

Les quatre réussites de combat ont désormais un pictogramme, une couleur, un bref accent sonore et une petite impulsion de caméra propres. Une seule carte apparaît sous le score, pendant environ une seconde. Un symbole marque aussi le point de réussite pendant environ 300 ms.

| Action | Confirmation | Condition |
| --- | --- | --- |
| Shotgun | **PLEIN IMPACT**, doré | Les six plombs de la même salve infligent des dégâts à la même cible. |
| Counter | **PARADE**, violet | Le Counter intercepte réellement une attaque et ouvre la riposte. |
| Fulguro Punch | **ÉCRASEMENT**, orange | La projection inflige les dégâts de collision contre un mur. |
| Longshot | **EXÉCUTION**, cyan | Le tir renforcé inflige des dégâts à un adversaire. Un tir normal, bloqué ou provenant d'une ancienne génération de l'arme ne confirme rien. |

Ces confirmations suivent les résultats du combat. Elles ne changent ni dégâts, ni cadence, ni protection, ni durée des effets. Les sons d'armes et modules existants sont conservés ; les nouveaux accents sont courts et discrets. L'impulsion respecte le réglage des secousses de caméra.

Une cible cachée ou hors écran ne déclenche pas de présentation. Le symbole garde le point initial de l'impact et ne suit jamais la victime. Les événements identiques sont dédoublonnés, avec une mémoire limitée à 128 identifiants par manche. Une seule carte et quatre voix audio réutilisées limitent le coût ; les accents ont un espacement minimum de 160 ms.

La pause fige les animations et les sons. Le changement de manche, d'acteur ou le retour au menu nettoie les confirmations. Le coup gagnant peut rester visible pendant la présentation du vainqueur. Désactiver les confirmations visuelles conserve les observations nécessaires aux défis guidés.

En réseau, l'hôte confirme les réussites sur son combat autoritaire et transmet l'événement par le canal fiable existant. Le client affiche seulement les confirmations de son propre joueur ; les projectiles visuels et les demandes du client ne peuvent pas inventer une réussite. Le retour au solo reconnecte les observations au joueur d'origine.

## Vérification

`tools/test_combat_signatures.gd` exerce la scène de jeu réelle : salve complète et partielle, Longshot normal et renforcé, protection Static Shield, interception Counter, projection Fulguro contre un mur, dédoublonnage, visibilité, pause, nettoyage, audio, passage réseau/solo, coup gagnant et projectile d'une ancienne manche.

- Capture avec rendu OpenGL sous Godot 4.7.2 : **45 contrôles réussis**, sans échec.
- Défis guidés et navigation : **54 contrôles réussis**.
- Régressions Shotgun, Longshot (**219 contrôles**), Counter (**55 contrôles**) et combat réseau : réussies.
- Tests d'intégration Fulguro Punch et sons du jeu : réussis. Le test Fulguro émet des diagnostics de matériau nul au nettoyage du rendu sans affichage ; la capture avec rendu ne les émet pas.
- Captures vérifiées en 1280 × 720 et en petit écran paysage 844 × 390 : `outputs/combat-signatures/`.

Les captures et les quatre accents WAV peuvent être reproduits en lançant le test avec `-- --capture` dans une session disposant d'un affichage. Le petit format a été vérifié sur PC ; aucun essai sur un téléphone réel ou entre deux appareils réseau n'a été effectué pour cette modification.
