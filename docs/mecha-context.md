# Animations contextuelles du mecha

La bibliothèque `art/mecha-context/context.res` extrait 28 clips du modèle à 97 animations. Elle contient seulement les pistes d'animation (2,8 Mo) : les neuf clips de combat, le squelette, les textures et la géométrie actuels restent dans leur GLB d'origine. Tous les clips sélectionnés ont un usage dans le jeu; ils ne sont pas ajoutés indistinctement au graphe de combat.

`tools/bake_mecha_context.gd` permet de la reconstruire avec Godot, à partir du fichier source puis du chemin de sortie passés après `--`. Il peut être exécuté dans le projet isolé `outputs/mecha-animation-review/runtime` sans charger les scripts du jeu. Les durées retenues sont dans `CLIPS`; les pistes sont rééchantillonnées à 30 Hz et sauvegardées en ressource compressée.

## Comportements

- Au repos : mouvements de tête et de buste issus de `standing_relax`, `look_around`, `wait`, `scratch`, après 6 à 11 secondes calmes, sans répétition immédiate. Aucun geste pendant la visée, la recharge, un module, l'échauffement, la stase, la révélation de combat ou à proximité d'un adversaire visible. Déplacement et visée interrompent le geste avec une sortie de 120 ms.
- Impacts : cinq variations de 340 ms, espacées d'au moins 380 ms. Les rotations sont relatives à la pose initiale des clips : la garde de boxe n'est pas importée. Tête et cou participent pendant la visée; le buste seulement lorsqu'il ne perturbe pas une action. Les brûlures continues, les protections sans perte de PV, la surcharge personnelle et les dégâts mortels ne lancent pas de réaction.
- Garage : cinq gestes ambiants espacés de 8 à 14 secondes, quatre salutations alternées à l'ouverture, trois approbations après une sauvegarde réussie, deux déceptions après un échec. Les réactions attendent la fin de l'intervention ou de l'inspection. Salut, pouce levé et ajustement sont transposés sur la main gauche par réflexion dans les repères de repos des articulations; le bras droit conserve sa pose de portage. Rotation, changement d'équipement et fermeture interrompent les gestes.
- Fin de manche : trois variantes de victoire (`cheer`, `greet_04`, `laugh_02`) et trois de défaite debout (`defeat_02`, `frustrated_01`, `frustrated_02`), alternées par acteur. Le bras portant l'arme garde sa pose de portage; le salut se fait de la main libre. Un robot éliminé conserve sa chute. La reprise du combat nettoie la pose de résultat.

## Gestes des douze modules

| Module | Clip source | Usage |
| --- | --- | --- |
| Fulguro Punch | `box_02`, `box_03` | Deux variantes de garde et d'accompagnement du coup, synchronisées à la préparation tenue, à la frappe et au retour. |
| Pelto Smash | `slash` | Accompagnement de la main libre pendant l'armement et l'impact, avec la pose de frappe existante. |
| Javelin | `pitch_baseball` | Geste de lancer transposé à la main libre; charge maintenue tant que le module n'a pas été relâché. |
| Rocket Basket | `basketball_shot` | Armement et geste de projection au départ des roquettes. |
| Projector | `cast_a_spell` | Préparation et relâchement de l'onde énergétique. |
| Magnetic Field | `cast_a_spell` | Commande de déploiement du mur. |
| Permutation | `cast_a_spell` | Accompagnement de l'envoi de la marque. |
| Éclipse | `cast_a_spell` | Sélection de destination et geste bref à l'arrivée; le transit conserve sa disparition. |
| Counter | `box_01` | Réaction de tête en garde, en conservant les deux prises d'arme existantes. |
| Static Shield | `box_03` | Garde de la main libre pendant la protection; sortie immédiate à l'annulation. |
| Pyro Boots | `flee_01` | Accompagnement du haut du corps pendant le dash réel. |
| Bio Injector | `greet_01` | Geste bref d'activation vers le corps, interrompu dès qu'une arme reprend la main. |

L'acceptation du module démarre sa présentation depuis `_start_module_cooldown`, y compris lorsque les recharges sont instantanées en entraînement. Les phases de Fulguro, Pelto, Javelin, Counter, Projector, Pyro et Static Shield viennent de leur état réel. Les casts à minuterie utilisent leur durée de préparation et leur propriétaire d'action; leur émission validée confirme explicitement le geste de relâchement. Une préparation annulée ne peut donc pas simuler un lancer. Le bref accompagnement après émission n'acquiert aucun verrou. Un fondu de 60 ms adoucit les passages entre phases sur la main libre et la tête. Annulation, étourdissement, mort, échauffement et gel de manche nettoient immédiatement le geste. Une entrée d'arme annule immédiatement l'accompagnement d'un buff ou d'un cast terminé.

## Intégration et autres passes visuelles

`mecha_presence_modifier.gd` agit sur les rotations locales de Head, Neck et Spine2, après la direction des jambes et avant la visée/les prises d'armes. `mecha_module_pose.gd` passe après la visée et agit sur la tête et la chaîne du bras gauche libre. Les rotations de buste du clip de lancer sont transférées dans cette épaule pour préserver l'arc du geste sans tourner le buste armé. La main droite, les jambes et les sockets gardent exactement leur transformation évaluée par le rig existant. Counter conserve aussi la prise gauche.

Ces deux modificateurs ne modifient ni le CharacterBody, ni `VisualMotion`, ni les durées/dégâts/cadences ou l'ActionGate. Une passe d'inertie ou de poids peut donc travailler sur `VisualMotion` séparément. Seuls les six résultats de manche ajoutent des états au rig; les gestes de modules sont échantillonnés directement depuis les phases réelles. Leur fin ne bloque pas la commande suivante.

En réseau, l'hôte choisit les gestes et transmet nom, temps et numéro d'événement dans le snapshot existant. Les modules ajoutent leur identifiant, phase, progression, durée et variante à ce même bloc `presence`. Les répliques n'effectuent aucun tirage autonome; les snapshots répétés ne rembobinent pas les réactions et les anciens snapshots ne réactivent pas un geste annulé. La présentation de résultat utilise le signal de manche existant sur chaque machine.

La bibliothèque utilise les noms Mixamo du modèle actuel. `mecha_animation_bank.gd` préfère les animations natives d'un châssis qui les possède, limite leur durée à la fenêtre retenue, remappe les chemins vers le squelette de l'instance et duplique les clips avant adaptation. Pour un autre squelette, vérifier les noms et orientations de repos avant de réutiliser cette bibliothèque; ne pas supposer que des noms identiques garantissent une retargetation correcte. Les états de résultat choisissent explicitement les clips `context/`, même si le GLB contient aussi une version longue du même geste.

## Vérification

Vérifié sous Godot 4.7.2 :

- `tools/test_mecha_presence.gd` : 480 contrôles réussis sur le modèle polyvalent, 500 sur le puissant. Repos, interruptions, limites angulaires, visée en déplacement, dégâts directs/répétés/brûlures/protections/mort, pause, variantes de manche et snapshots de vrais acteurs réseau.
- `tools/test_mecha_modules.gd` : 145 contrôles réussis sur chaque châssis. Activations réelles des douze modules, charges maintenues, émission, annulations (charge tenue et tap avant émission), garde, sortie du bouclier, priorité de l'arme, invariance de la main droite/des jambes/des collisions et snapshots réseau.
- `tools/test_player_visual_rig.gd -- --isolated` : 299 contrôles réussis sur le rig de production et ses armes.
- Régressions réussies : `test_javelin_charge.gd`, `test_fulguro_punch.gd`, `test_pelto_smash.gd`, `test_defensive_modules.gd`, `test_mobility_modules.gd`, `test_counter.gd`, `test_projector.gd`, `test_permutation.gd`, `test_eclipse.gd`, `test_network_combat.gd`.
- `tools/test_forge_garage.gd` : gestes, sauvegarde, inspection, rotation, fermeture et variantes de châssis vérifiés; les sauvegardes préexistantes sont restaurées par le test.
- Import et chargement des scripts du projet complet : réussis. Captures natives OpenGL inspectées dans `outputs/mecha-context/`, reproductibles avec `tools/capture_mecha_context.gd`. Le catalogue des 97 clips et leurs aperçus reste dans `outputs/mecha-animation-review/review.html`.

La réplication a été testée avec des acteurs hôte/réplique dans une même instance Godot; une session entre deux machines et le rendu sur téléphone physique n'ont pas été testés dans cette passe.
