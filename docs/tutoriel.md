# Tutoriel débutant

Le bouton **Test Tutoriel** de l’accueil ouvre une session dédiée, construite sur les acteurs du terrain d’entraînement. Le build du Garage, les réglages et les défis avancés sont conservés.

Le parcours comporte six étapes : rejoindre un repère, toucher deux fois au Blaster, réussir un impact chargé, effectuer une esquive Pyroboots, toucher au Javelin, puis activer Static Shield et attendre sa fin. Les validations observent les impacts et les états réels du joueur. Le bouton Suivant reste désactivé tant que l’objectif n’est pas rempli.

Le joueur est invulnérable et conserve les temps de recharge normaux. Les touches affichées suivent les réglages ; sur appareil tactile, les consignes décrivent les joysticks et les boutons. Refaire ou F5 recommence l’étape. Pause, Tab et Échap suspendent la session. L’accueil reste accessible pendant la pause.

Le récapitulatif propose l’entraînement libre, un nouveau tutoriel ou le retour à l’accueil. Le terrain libre reprend le build sauvegardé.

Les fichiers principaux sont `scripts/beginner_tutorial.gd` et `scenes/beginner_tutorial.tscn`. `tools/test_beginner_tutorial.gd` vérifie l’accès depuis l’accueil, les projectiles, les modules, la pause, les touches personnalisées, les sauvegardes et les transitions. Son argument `--capture` produit les captures de contrôle dans `captures/tutorial/` avec une fenêtre graphique, y compris une vue paysage de 844 × 390.
