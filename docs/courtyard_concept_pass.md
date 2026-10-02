# Cour de récupération — adaptation du concept, 2 octobre 2026

L'arène classique reçoit les matériaux et la palette de la référence approuvée :
béton clair patiné, réparations métalliques affleurantes, couvercles épais en acier
bleuté, blindages crème et rouge usés, sable aux pieds des obstacles, végétation
olive/paille et plaques médicales carrées turquoise. Les anciennes tribunes
masquent désormais leur rendu pour révéler le palan, la carcasse, l'abri et le
groupe énergétique existants. Les collisions et la caméra restent identiques.

Le résultat est un rendu temps réel dans Godot, adapté à la géométrie et aux
volumes de camouflage du jeu. Le concept est une référence artistique générée ;
ce document ne prétend pas à une identité pixel par pixel entre les deux images.

## Ressources et fabrication

- `tools/environment/build_courtyard_materials.py` fabrique l'atlas de 60 m en
  4096 px, son relief, les micro normales métalliques et le sable extérieur. Il
  préserve les trois albedos finaux ImageGen et ne s'exécute jamais au lancement.
- `shaders/courtyard_ground.gdshader` combine cet atlas avec la matière de béton
  à deux échelles pour limiter la répétition des fissures. Les réparations et
  marques de service restent localisées dans l'atlas.
- `tools/environment/build_cover_family.gd` précalcule deux maillages dans la
  boîte fonctionnelle originale : 2692 / 2674 triangles, six surfaces et six
  matériaux partagés. Les textures se projettent en coordonnées du monde afin
  de ne pas s'étirer sur les longs couverts.
- `tools/environment/build_courtyard_edges.gd` précalcule 180 petites touffes et
  leurs éclats de sol en huit lots spatiaux. Leur hauteur de 0,25 à 0,62 m les
  distingue des zones de camouflage. Aucune physique ni navigation ajoutée.
- `repair_socket_presentation.gd` adapte uniquement les visuels des kits de
  l'arène : plaque carrée, croix basse, état gris et barre de recharge. Le parent
  conserve le soin, la collecte, le délai et le retour du kit.
- `arena_presentation.gd` applique la lumière chaude, les ombres froides et un
  vent commun. Le niveau bas réduit le vent et désactive les ombres des grandes
  herbes, les particules périphériques et la rotation du ventilateur.

Les nouvelles textures 3D ont des mipmaps et une compression VRAM S3TC / ETC2.
Les meshes de bordure sont sauvegardés dans `art/environment/courtyard_edges_*.res`.

## Images et provenance

Génération avec l'outil ImageGen intégré, sans CLI ni clé API. Images inspectées
puis copiées dans le projet :

- `art/environment/courtyard_concrete_detail.png`
- `art/environment/courtyard_steel_albedo.png`
- `art/environment/courtyard_paint_albedo.png`

Prompts finaux des trois matières :

### Béton

> Use case: stylized-concept. Asset type: a square seamless diffuse ALBEDO MATERIAL TEXTURE for a premium stylized 3D robot salvage courtyard game, a usable PBR base color map. Create only one continuous square flat surface of warm pale weathered industrial concrete, artistically beautiful hand-painted subtle mineral texture: softly mottled aged light gray-beige cement, irregular flaking mineral patches, tiny chipped stone aggregate, fine pores, sparse short hairline cracks, faint dusty pale ochre abrasion. Varied medium and fine detail makes it tactile and realistic yet painterly and restrained. Main average color sRGB RGB 164,155,138, relatively muted and midtone; avoid white and black extremes. No overall large shapes. Absolutely orthographic straight-on top-down flat material scan, zero perspective, zero objects, no metal parts, no tiles, no seams, no edges, no borders, no text, no diagrams, no cast shadows, no specular, no highlights, no baked directional lighting, no vignette, even diffuse illumination. The texture must tile seamlessly on all four edges, continuous color and texture density, texture fills the entire square canvas. Keep detail quiet enough for combat readability. This will be applied to a Godot 3D floor with lighting applied in the game.

### Acier

> Asset type: usable seamless PBR diffuse albedo texture for blue-gray steel on stylized robot salvage arena cover lids. One single square continuous flat surface, absolutely orthographic straight-on material texture, no objects no border no text. Mid-tone desaturated blue-gray steel, average sRGB RGB 102 113 123. Beautiful tactile worn satin rolled steel, restrained broad cloudy abrasion, delicate horizontal directional brush scratches and scuffs, tiny irregular dark gray pits, small sparse localized warm brown oxidation islands covering less than three percent of area, a few softened pale rubbed patches. Premium hand-painted 3D game material with convincing organic wear, restrained readable contrast, absolutely no regular dots, no checkerboard, no seams, no plates, no hinges, no bolts. Uniform diffuse lighting, no directional light, no highlight, no cast shadow, no vignette, no fake bevels or raised parts. Seamlessly tileable on all four edges, consistent density, continuous material fills entire canvas. Not glossy not chrome not shiny foil. This is color-only texture to be shaded by the game engine.

### Peinture

> Asset type: a seamless PBR diffuse albedo texture of worn industrial ivory cream enamel painted metal for a premium stylized 3D robot salvage courtyard game. One single square continuous flat surface absolutely orthographic straight-on material texture, no objects no border no text no plate edges. Main average color sRGB RGB 192 186 166, desaturated aged light cream ivory paint. Restrained beautifully tactile hand-painted realistic game surface with subtle cloudy painted brush texture, fine short scratches, tiny irregular chips through enamel exposing muted gray steel, a few localized ochre/rust-brown oxidized patches occupying less than 4 percent of area with irregular softened dark-edged flakes and fine rusty runs. Most of surface remains intact cream paint. Organic subtle wear, not uniform dots, no high-contrast speckles. No tile seams no bolts no hinges no holes no geometric forms. Uniform diffuse illumination with zero directional lighting, no cast shadow no specular shine no raised edge no vignette. Texture should seamlessly tile at all four edges with consistent density and fill the entire square canvas. Calm readable texture with physically convincing chipped enamel. Not wall plaster, not concrete, not shiny chrome.

## Vérification

Godot 4.7.2, Vulkan Forward Mobile, RTX 3070 Laptop GPU. Les chemins de l'autre
contributeur indiqués dans AGENTS.md n'existent pas sur ce PC ; l'exécutable
utilisé ici est `C:\Users\Ben\Desktop\Prototype 0\Godot_v4.7.2-stable_win64_console.exe`.

Vérifications réussies : contrat complet de l'arène avant/après (48 obstacles,
14 buissons, 4 kits et caméra), fiabilité des volumes, camouflage, visibilité,
navigation du bot, collecte des soins, visuels des soins, nouveau test des plaques
(soin de 30 %, recharge, désactivation/réactivation) et bascule de qualité.
Le combat réel de six secondes conserve les acteurs au sol, leurs déplacements,
la perception du bot et les projectiles : huit tirs et aucune assertion en échec.

Les captures et rapports sont dans `outputs/arena-concept-match/`. La vue
`reference-match-concept.png` masque uniquement l'interface pour l'examen des
matériaux ; elle utilise la caméra de gameplay. Les cinq vues `final-*.png`
conservent l'interface normale. Le format de la fenêtre et la projection du jeu
ne sont pas modifiés.

Le combat a aussi été exécuté et capturé avec le rendu Vulkan actif : aucune
assertion en échec, huit tirs, bot actif pendant six secondes. La comparaison
des paramètres de la caméra dans `final-metrics.json` est confirmée identique.

Limites : Android physique et APK non testés. Les temps des captures ne constituent
pas une mesure de FPS soutenu. Dans la sandbox, Godot signale des écritures de
préférences/logs et du cache GD-Sync refusées ; le certificat système et les outils
Android sont aussi signalés au démarrage. Ces messages existaient dans le rendu
avant la refonte et n'empêchent pas les assertions ou les captures de réussir.
Les tests historiques de visibilité et de soins signalent des ressources encore
utilisées à leur fermeture. Les autres travaux locaux sont conservés.

Réservation : `Prototype-Work: abc30069-ddbc-41cf-996d-4ed799c49bf2`.
Livraison locale uniquement ; aucune publication GitHub annoncée.

## Deuxième direction : ateliers clandestins, néons et réseau électrique

La référence suivante, validée le 2 octobre, ajoute des ateliers de récupération,
des bâches, des néons cyan/rouge et une installation électrique visible. Elle est
archivée dans `outputs/arena-workshops/reference.png`. L'adaptation est construite
en vraie géométrie 3D ; la référence générée reste une direction artistique.

`tools/environment/build_workshop_dressing.gd` précalcule les ajouts dans
`art/environment/workshops/` et assemble `scenes/environment/workshop_dressing.tscn`.
Les 16 couverts intérieurs reçoivent des coffrets, grilles, tuyaux, attaches,
réservoirs ou pièces de robot, outils et tuyaux enroulés. Les grandes extrémités
deviennent des radiateurs de machine numérotés. Les couvercles portent de petites
caisses, des connecteurs et des réserves de métal. Les éléments sont vissés dans
les volumes déjà bloquants ; seules les petites lèvres et connexions dépassent
légèrement des parois. Aucun nouvel obstacle physique n'est ajouté.

Quatre enseignes intérieures « ATELIER 07 » / « PIECES 02 » sont faites de tubes
de néon et de leurs attaches. Huit dépôts supplémentaires sont installés à
l'extérieur de la limite de jeu, avec des enseignes « RECYCLAGE » / « BATTERIES ».
Douze lignes électriques suspendues terminent sur des poteaux ancrés aux abris
ou au périmètre. Les traversées intérieures passent au-dessus du combat, avec des
lampes suspendues et une courbure visible. Les autres câbles suivent les toits et
les façades. Huit panneaux de toile, leurs supports et coutures habillent quatre
postes de travail ; le shader de vent existant conserve leurs points d'attache.

La toile `workshop_canvas.svg` utilise une couleur de fond et des traits de trame
explicites compatibles avec l'import SVG de Godot. Elle possède des mipmaps et
les formats VRAM S3TC / ETC2. Les matières métalliques réutilisent les textures
du premier passage. Les halos des néons, petites traces d'huile et nappes de
lumière utilisent trois shaders locaux, sans dépendre d'un post-traitement de
glow. Le soleil est atténué, les ombres restent froides et les lampes apportent
des accents chauds. Le MSAA 2× en qualité normale stabilise les fils et les tubes.

Le contrôleur `workshop_dressing.gd` choisit au maximum six lampes proches de la
caméra, sans ombres supplémentaires. Le niveau bas éteint toutes ces lumières,
réduit le mouvement des toiles et désactive le MSAA. Les surfaces lumineuses et
les petites nappes au sol conservent l'ambiance. Le changement vers la map test
masque les ateliers et leurs lumières ; le retour à l'arène classique les rétablit.
La géométrie opaque est indexée et répartie en lots spatiaux pour être éliminée
du rendu hors champ. L'ensemble précalculé contient 246 202 triangles répartis
en 199 lots, plus huit petites toiles ; il n'est pas reconstruit au lancement.

### Validation du deuxième passage

Le premier contrôle complet du passage confirme 48 obstacles, 14 buissons,
quatre soins, mêmes formes, transformations, points d'apparition et caméra.
La géométrie et la projection restent aussi identiques au contrôle final. Une
autre conversation (« Fluidifier les commandes les transitions et les
deplacements du combat ») ajuste entre-temps le suivi de caméra : vitesse de 3,2
à 8 et anticipation de 1,6 à 0,9 m. Le test strict signale uniquement ce changement
de `camera_rig`, conservé dans les captures finales ; ce passage n'édite pas ce
script. Les tests de fiabilité, camouflage, visibilité, navigation, plaques de
soin et changement de qualité réussissent. Le nouveau test d'intégration
`tools/test_workshop_presentation.gd` vérifie l'absence de physique/navigation dans
les décors, le budget des lampes, le déplacement de la caméra et les transitions
classique / map test / classique.

Le test de combat réel utilise les commandes habituelles et huit tirs sur six
secondes. Une manche peut désormais se terminer pendant cette fenêtre : la
désactivation du bot réinitialise alors son horloge privée. La mesure conserve
la durée active observée avant cette remise à zéro, et exige une manche résolue
si le bot s'arrête. Le contrôle des déplacements, perception, projectiles et
limites physiques reste actif. Les modifications des autres conversations sont
conservées, notamment les changements de visuels de robots et de combat en cours.

Les captures et rapports de ce passage sont dans `outputs/arena-workshops/` :
`final-concept.png` emploie la caméra du jeu en masquant l'interface, les cinq vues
`game-*.png` conservent l'interface, et `low-concept.png` montre le niveau bas.
L'option `review` du captureur réduit le nombre d'images d'attente pour l'examen
visuel ; les mesures de ces captures ne sont pas des benchmarks de FPS soutenu.
Le rendu Vulkan PC est vérifié ; un appareil Android physique reste à tester.

Le combat a également réussi avec Vulkan actif : huit tirs, 24 projectiles
créés, bot actif pendant 5,98 s, mouvements et perception exécutés, acteurs au
sol et dans les limites, aucune assertion en échec. Les trois images
`arena-live-frame-*.png` sont prises pendant ce combat. Les nouveaux modules de
finition développés en parallèle restent en cours ; leurs messages de méthodes
différées à la fermeture sont distincts des assertions de ce décor.
