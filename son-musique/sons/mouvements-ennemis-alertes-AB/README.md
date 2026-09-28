# Prototype 0 — mouvements, ennemis et alertes A/B

Génération locale du 28 septembre 2026 avec Stable Audio 3 Small-SFX, CUDA, 8 étapes. Les graines et prompts anglais exacts sont conservés dans `generation_manifest.json` ; les prises originales restent dans `raw/`.

## Contenu à écouter

18 écoutes, soit 9 choix A/B. Chaque version de pas contient quatre générations distinctes, également disponibles individuellement dans `previews/footsteps/`. Les textures de buisson ont une boucle de 2,4 s dans `previews/loops/` et une écoute de deux cycles avec fondus dans `previews/`.

| Événement | Direction A | Direction B | Déclenchement prévu après sélection |
| --- | --- | --- | --- |
| Pas du robot | Appuis métalliques secs | Appuis amortis et hydrauliques | Contact du pied, cadence liée au déplacement, arrêt quand immobile ; alterner les quatre grains |
| Entrée de buisson | Herbes sèches sur le blindage | Feuillage souple | Transition de l’extérieur vers le buisson |
| Sortie du buisson | Feuilles sèches et branche | Balayage doux du feuillage | Transition vers l’extérieur |
| Mouvement dans le buisson | Bruissement sec léger | Friction douce des feuilles | Seulement en mouvement dans le buisson ; fondus courts aux démarrages et arrêts |
| Tir ennemi | Départ pneumatique et culasse | Impulsion électrique grave | Départ effectif du projectile |
| Contact ennemi | Frappe métallique sèche | Piston sourd | Contact de l’attaque, sans doubler inutilement le son de dégâts reçus |
| Charge ennemie | Mécanisme qui se tend | Signal montant et aspiration | Début du télégraphe avant la ruée |
| Vie faible | Alerte aiguë | Impulsion grave de batterie faible | Une seule alerte au franchissement du seuil ; réarmement après remontée de vie |
| Baroud | Moteur de secours | Surcharge de réserve | Activation effective de la dernière chance |

Les directions décrivent l’intention de génération. La sélection sémantique à l’écoute et le réglage en jeu restent à faire avec l’utilisateur ; aucune écoute en situation n’a été validée. Les scripts de jeu n’ont pas été modifiés pour ce lot.

## Préparation et contrôle

`prepare.py` extrait les grains courts de sources d’au moins trois secondes, retire le décalage continu, ajuste le gain avec marge de crête et applique des fondus. Les boucles utilisent un raccord croisé de 300 ms. Les écoutes A/B trop différentes en niveau sont équilibrées par atténuation.

Les 28 WAV préparés passent le contrôle d’intégrité : nombres finis, fichiers non silencieux, aucune saturation, inspection stricte des transitoires et de la densité. Les détails sont dans `preview_manifest.json` et `inspection.json`. Ces contrôles techniques ne valident pas la pertinence à l’écoute.

Les 18 écoutes sont copiées sur le site de choix. Les fichiers `baroud-A/B.wav` y portent le nom `baroud-activation-A/B.wav` pour distinguer le son du choix d’icône existant.
