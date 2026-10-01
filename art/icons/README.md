# Icônes de modules

Famille vectorielle transparente : plaques ivoire usées, cuivre, acier sombre
et touches d’énergie. Pelto Smash et Fulguro Punch servent de références
illustrées ; Projector, Éclipse et Permutation conservent leur dessin.

`node tools/build_module_icons.cjs` reconstruit les treize icônes harmonisées et
leurs variantes grises dans `cooldown/`. Ces variantes sont importées à l’avance
pour éviter une conversion d’image pendant une activation sur téléphone.
Les originaux PNG de `ben/` sont conservés.

`scripts/equipment_icons.gd` fournit les textures communes à la forge, au HUD
et aux boutons tactiles. `scripts/touch_module_visual.gd` dessine la recharge
circulaire, le temps restant et le halo de récupération (0,85 seconde).
Pyro Boots affiche ses deux charges : l’icône reste colorée avec une charge
disponible, et chaque récupération produit un halo. Le Javelin conserve son
pictogramme de téléportation pendant la fenêtre de réactivation.

Vérification : `tools/test_touch_module_visual.gd` et
`tools/test_touch_controls.gd`. Captures reproductibles :
`tools/capture_touch_module_visual.gd`, avec le moteur graphique activé ;
résultats dans `captures/module-buttons/`.
