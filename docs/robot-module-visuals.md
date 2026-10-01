# Pyroboots et Bio Injector visibles sur le robot

Les deux accessoires reprennent les concepts validés : petits propulseurs à boîtier sombre et touches ambre aux chevilles, et deux cartouches vertes sous le bord latéral du plastron. Ils sont montés sur le squelette du GLB existant, sans modifier sa géométrie ou ses animations. Le Garage et le Player de combat utilisent les mêmes maillages.

Le module de mobilité équipé détermine les pièces visibles. Pyroboots et Bio Injector sont exclusifs, comme les choix du loadout. Permutation et Éclipse masquent ces deux accessoires. Les pièces suivent les pieds ou le torse, la rotation et l'échelle du châssis. Les matériaux sont opaques, les maillages et matériaux sont partagés entre instances, et les accessoires n'ont aucun traitement par frame.

Au clic sur Pyroboots ou Bio Injector dans le Garage, la caméra cadre le module installé. Le bras existant rejoint sa surface avec le scanner et ses vraies articulations, puis effectue exactement trois secondes de travail après l'approche. Il se retire et la caméra revient à la vue générale. La portée des chevilles est obtenue en essayant plusieurs orientations du poignet dans les limites existantes. Le déplacement garde les contrôles de dégagement du scanner.

Un autre choix, un changement d'onglet ou de build, une rotation manuelle, une perte de focus ou une fermeture interrompt le travail. « Tester » et « Sauvegarder » libèrent le bras avant leur propre action. L'installation ciblée ne sauvegarde pas le brouillon : la séquence de sauvegarde générale déjà présente reste indépendante.

Vérifications locales :

- `tools/test_robot_module_visuals.gd` : vrai Player et squelette, exclusivité, suivi des os, échelle, camouflage, ressources partagées, matériaux opaques et géométrie intégralement référencée.
- `tools/test_forge_module_installation.gd` : travail sur la surface physique durant trois secondes sur chaque châssis, dégagement du bras, transitions, annulations, sauvegarde et cadrage paysage.
- Avec `-- --runtime`, le même test vérifie les vrais clics GUI et le traitement natif des frames.
- `tools/capture_robot_modules.gd` produit les captures natives du détail, de l'intervention, de la vue générale et du paysage mobile dans `captures/robot-modules/`.
