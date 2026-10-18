# Ambiance du garage — maquettes du 15 octobre 2026

Trois propositions ImageGen réalisées à partir d'une nouvelle capture GPU du garage de ce checkout, puis une correction architecturale approuvée. La direction de la variante 04 est maintenant intégrée dans la vraie scène 3D du jeu, localement et sans publication. Les images ImageGen ci-dessous restent les maquettes ; le [rapport d'intégration](integration-report.json) référence les captures réelles et les contrôles.

- Référence : [garage actuel](reference-garage-actuel.png), 1920 × 1080, moteur Godot 4.7.2, Vulkan Mobile, GTX 1660 SUPER.
- A : [atelier chaleureux](01-atelier-chaleureux.png). Recommandation : renforcer le foyer lumineux autour du robot et de l'établi, réchauffer les métaux, ajouter des traces d'usage mesurées.
- B : [maintenance nocturne](02-maintenance-nocturne.png). Fenêtre bleue sous la pluie, éclairage chaud local, voyants cyan. Ambiance plus intime ; garder une lumière neutre suffisante sur le robot.
- C : [fin de journée](03-fin-de-journee.png). Soleil rasant, ombres de la verrière, poussière et reflets dorés. Ambiance plus accueillante et lumineuse.

Les trois images conservent les principaux repères de la scène et les deux commandes de l'entrée : même robot, plateforme, bras, établi, mezzanine, fenêtre et postes de modules. Les modèles génératifs peuvent modifier des détails et les petites inscriptions : les captures de référence restent la source de vérité pour une réalisation.

## Ce que je retiendrais pour une réalisation

Partir de A. Donner la priorité à la séparation lumineuse entre la baie active et le hangar, aux ombres de contact, aux variations de rugosité et aux détails posés sur l'établi. Les reflets des maquettes sont volontairement appuyés : les atténuer pour garder un béton sec crédible. Emprunter éventuellement à C une lumière solaire modérée.

Pour la vie du lieu, proposer ensuite quelques mouvements discrets : poussière localisée, voyant irrégulier, rotation lente du ventilateur existant et très légère variation d'une lampe. Ces mouvements ne sont pas démontrés par les images fixes et ne sont pas implémentés ici.

## Vérification et provenance

Capture initiale via `capture_reference.gd`, avec chemins de sauvegarde temporaires isolés. Les trois captures ont été enregistrées avec succès, puis les trois maquettes ont été inspectées visuellement. L'intégration ultérieure modifie le décor 3D, ses matériaux, sa lumière et le cadrage PC ; ses vérifications sont détaillées dans `integration-report.json`. Aucune validation de performance ni de rendu Android réel n'est déduite des images.

Outil : ImageGen intégré. [Prompts exacts](prompts.md). Empreintes et dimensions dans [manifest.json](manifest.json).

## Correction de la profondeur après retour visuel

[04 — Atelier adossé au mur extérieur](04-atelier-mur-exterieur.png) corrige l'ambiguïté de la première proposition : la petite baie ressemblait à un décor indépendant au milieu d'un autre hangar, et la fenêtre montrait un extérieur difficile à situer.

Cette révision remplace l'arrière-plan par un mur extérieur continu relié à la charpente et au sol, supprime les cloisons libres qui formaient une petite boîte, rattache la passerelle au mur et donne une épaisseur visible à l'embrasure de la fenêtre. Les équipements et les commandes principaux restent reconnaissables. La fenêtre a été agrandie par le générateur ; ses dimensions exactes resteraient à décider lors d'une réalisation.

Cette correction de maquette ImageGen a été inspectée puis approuvée avant sa réalisation en 3D. [Prompt exact](04-prompt-profondeur.txt) ; [image du retour utilisateur](reference-retour-profondeur.png). Le rendu réel est visible dans [la capture d'entrée](../../captures/forge-workshop-architecture/pc-1920-entry.png).

Réservation : `750222e1-02a2-4fd9-b8c2-177c5392deb1`.

