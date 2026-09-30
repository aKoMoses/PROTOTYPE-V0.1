PROTOTYPE 0 — Refonte visuelle de l’arène, 30 septembre 2026

Modifications réalisées dans le projet existant :
C:\Users\Ben\Documents\Codex\2026-09-23\j-ai-x20\outputs\PROTOTYPE-0

L’arène principale de duel, également utilisée par le menu et les parties locales/réseau, reçoit un sol de sable compacté avec traces de roues, reprises métalliques et poussière aux pieds des obstacles ; deux variantes de blindages crème et acier rouillé ; une lumière solaire chaude, un ambiant plus froid et des ombres mieux ancrées. Les buissons adoptent une palette olive/paille. Les kits conservent leurs indicateurs sur un socle industriel affleurant.

Quatre compositions extérieures donnent un contexte au lieu : palan de maintenance, carcasse à chenilles, abri en toile rouge et groupe énergétique cyan. Toile attachée, végétation, ventilateur et deux petits émetteurs périphériques réagissent à un vent commun. Le niveau bas du système VFX existant conserve les matériaux et les silhouettes, supprime les 24 particules et la rotation du ventilateur et réduit les mouvements.

Ressources principales, dans le projet :
• scripts/main.gd : intégration visuelle localisée sur les volumes existants.
• scenes/environment/arena_presentation.tscn et scripts/environment/arena_presentation.gd : sol, ambiance et qualité.
• scenes/environment/cover_skin*.tscn et art/environment/families/ : maillages partagés, six matériaux opaques, 1 580 / 1 538 triangles par variante.
• scenes/environment/salvage_yard.tscn, service_banner.tscn, ventilation.tscn et art/environment/yard/ : décor extérieur précalculé, 6 528 triangles au total.
• scenes/environment/repair_socket.tscn : support des kits.
• art/environment/arena_sand_atlas.png : atlas 2 048 px, compression VRAM S3TC/ETC2 et mipmaps ; environ 2,8 Mo en ETC2 avec mipmaps.
• art/environment/arena_art_settings.tres : réglages centralisés de vent, lumière et qualité.
• scripts/bush_visual.gd et bush_foliage.gdshader : palette et oscillation ; réponse locale et zones fonctionnelles conservées.
• tools/build_arena_ground.py, tools/environment/build_cover_family.gd et tools/build_salvage_yard_assets.gd : sources de fabrication hors lancement du jeu.

Vérifications : Godot 4.7.2, Vulkan Forward Mobile sur RTX 3070 Laptop GPU. Sept tests passent : contrat de l’arène, cohérence des couverts, buissons, visibilité, navigation du bot, kits et combat actif. Le contrat compare exactement les 48 bloqueurs, 14 buissons, 4 kits, collisions, transformations, points d’apparition et caméra avec l’état initial. Les habillages restent dans les volumes existants ; le nouveau décor et ses enveloppes de particules restent hors des zones jouables et n’ajoutent aucune physique/navigation.

Cinq paires de captures avant/après utilisent exactement le même cadrage de gameplay ; toutes ont été examinées. Le z-fighting des premières couches de blindage a été corrigé, puis les captures finales renouvelées. Le test rendu de six secondes utilise les vrais déplacements, la caméra suiveuse, la visibilité, le bot et huit tirs. Les formats de fenêtre 20:9 et 16:10 conservent le rendu interne 1280×720 conformément au réglage existant ; une capture supplémentaire en expansion 20:9 sert uniquement de vérification visuelle. La vue complète est une caméra de diagnostic.

Mesures sur 60 images par vue, en 1280×720 : appels de rendu au centre 1 314 → 732 (−44,3 %), moyenne des cinq vues 1 221,5 → 737,2 (−39,6 %). Temps de rendu CPU au centre 1,68 → 0,84 ms ; GPU 0,58 → 1,02 ms. Le GPU varie selon la vue (0,64–1,59 ms après) : aucune promesse de gain GPU ou de fréquence d’images. Les primitives moyennes restent proches de 168 000. Les compteurs FPS/process de la fixture sont affectés par le démarrage et les captures synchrones.

Limites : aucun appareil Android ni export APK testé ; les performances mobiles physiques restent à mesurer. Le démarrage signale un problème préexistant de lecture du magasin de certificats, et certains tests headless signalent des ressources à la fermeture malgré leurs assertions réussies. Les arènes distinctes survival/training et les systèmes de combat préexistants sont préservés. Aucune référence visuelle externe n’était accessible : direction fondée sur la description fournie. Les nouvelles ressources sont originales et procédurales, sans téléchargement ni dépendance payante.

Livraison : comparaison-avant-apres.png ; captures arena-before/after/low-*.png ; captures de combat arena-live-frame-*.png ; arena-validation.json et fichiers de mesures ; prototype0-arena-art.zip. Le projet local est déjà modifié. L’archive contient les ressources, outils, preuves et un patch limité aux changements de cette passe, basé sur l’état local au début des travaux ; ne pas l’appliquer une seconde fois au projet courant. Pour réutiliser sur ce même état initial, copier le contenu de resources/ à la racine du projet, puis vérifier avec « git apply --check --ignore-whitespace presentation.patch » avant « git apply --ignore-whitespace presentation.patch ». L’option gère les fins de ligne Windows ; une autre révision du projet nécessite une adaptation du patch.
