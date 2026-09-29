# Éditeur de l'interface en jeu

## Accès

- Menu principal → Réglages → Interface → Personnaliser l'interface.
- Pause du duel ou de la Survie → Personnaliser l'interface.
- Menu de l'Entraînement → Personnaliser l'interface.

Touchez un élément ou choisissez-le dans **Éléments**. Glissez pour le déplacer ; le décalage initial du doigt est conservé. La jauge et les boutons `−` / `+` changent sa taille. Le panneau passe d'un côté à l'autre avec `↔`. **Tester** utilise un joueur et une cible temporaires ; **Retour à l'édition** retrouve le brouillon. **Enregistrer** écrit le profil local ; **Quitter** demande quoi faire si le brouillon a changé. Échap et le bouton Retour Android suivent le même chemin.

Le quadrillage, l'aimantation et les trois pas sont indépendants. La sélection affiche le rectangle de contact tactile ; les zones qui se chevauchent sont signalées. **Devant / Derrière** règle la priorité des touches dans ces zones. Les touches restent attribuées à leur doigt jusqu'à son relâchement ou une annulation explicite. Une commande masquée n'accepte aucune touche. Le bouton Pause du duel et de la Survie, ainsi que le menu de l'Entraînement, restent visibles et leur zone a priorité sur les commandes tactiles même en cas de superposition. Le menu principal fournit aussi un accès de secours.

## Éléments couverts

| Identifiants stables | Présence |
| --- | --- |
| `move`, `aim`, `offensive_button`, `defensive_button`, `mobility_button`, `weapon_button` | Commandes tactiles ; le changement d'arme n'existe pas en Survie |
| `match_summary`, `pause` | Duel |
| `player_vitals` | Duel, Survie et Entraînement ; le bloc Vie et arme affiche les valeurs réelles en partie |
| `spell_bar`, `offensive_slot`, `defensive_slot`, `mobility_slot` | Duel, Survie et Entraînement ; la barre porte les trois emplacements, chacun garde sa propre taille, opacité et position relative |
| `wave`, `arrival`, `pause` | Survie ; l'annonce conserve sa règle d'affichage contextuelle |
| `training_status`, `training_reset`, `training_menu`, `training_meter`, `training_meter_chip` | Entraînement ; les deux présentations des mesures gardent leurs règles d'affichage |

Les barres au-dessus des acteurs et les marqueurs de monde restent attachés aux acteurs. Les panneaux de choix, de résultat et de pause, ainsi que l'animation de décompte, sont des écrans de navigation ou des effets temporaires : ils ne font pas partie du HUD déplaçable. Aucun bouton de soins ou d'interaction distinct n'existe dans le gameplay actuel ; l'injecteur est un module de mobilité.

## Données et coordonnées

`scripts/hud_layout.gd` contient la liste des identifiants et la disposition Standard, fondée sur les positions du HUD antérieur. Gaucher échange les commandes tactiles sans retourner les textes ou les icônes. Deux emplacements personnels sont disponibles. Les familles mobile et ordinateur possèdent des données séparées ; le choix suit la plateforme et la présence d'un écran tactile, sans déduire le mode d'une largeur de fenêtre.

Le fichier versionné `user://prototype0_hud_layout.json` contient, par famille, la dernière disposition enregistrée et les emplacements personnels. L'écriture passe par un fichier temporaire et une copie de secours. En cas de fichier principal illisible, la copie valide est utilisée ; des champs absents ou hors limites reviennent à leurs valeurs d'usine. Un identifiant inconnu est conservé pour une version future.

Chaque centre est enregistré comme **ancre de zone sûre** (`a`, coordonnées 0 à 1) plus **décalage en hauteurs de zone sûre** (`d`). Cette règle maintient les commandes de bord près du bord et les éléments centraux au centre lorsque le ratio change. `s` est le facteur de taille, `o` l'opacité, `v` la visibilité, `l` le verrouillage et `z` la priorité. Le rendu et les entrées tactiles passent par ces mêmes données. Les corrections nécessaires sur un petit écran restent temporaires et ne modifient pas le fichier enregistré. Les emplacements de modules stockent leur décalage local sous la barre ; le déplacement ou la taille de la barre emporte ses enfants.

## Ajouter un widget

1. Créez un identifiant stable indépendant du nom traduit et du chemin de scène.
2. Ajoutez son nom et sa valeur initiale dans `PrototypeHudLayout.names()` et `standard()` ; adaptez `size_limits()` et `is_required()` si nécessaire.
3. Si c'est un `Control`, donnez-lui une racine à taille explicite qui contient son icône, son texte, ses compteurs et sa zone tactile. Enregistrez-la avec `HudLayoutController.register(id, control)`. Passez `true` en troisième argument si la scène commande sa visibilité selon le contexte ; dans ce cas, combinez cette condition avec `controller.layout[id].v`.
4. Si l'élément est dessiné et testé dans `touch_controls.gd`, utilisez le même identifiant pour `_widget_center`, `_widget_radius`, `_widget_visible` et la priorité de `_begin_touch`. Ajoutez-le à `TOUCH_IDS`.
5. Gardez les conteneurs qui organisent les sous-éléments **à l'intérieur** de la racine personnalisable. Ne laissez pas un parent `Container` repositionner cette racine.
6. Étendez `tools/test_hud_layout.gd` pour contrôler sa présence, son placement, sa sauvegarde et ses entrées.

Le projet cible Godot 4.7.2. La passe automatisée couvre le modèle, le parcours de base, les trois scènes et le routage tactile. Le multitouch, les encoches et l'ergonomie doivent encore être éprouvés sur un téléphone Android physique.
