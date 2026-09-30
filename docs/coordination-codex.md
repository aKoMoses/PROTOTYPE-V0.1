# Coordination entre Akomoses et morepudding

Le [tableau partagé](https://prototype-zero-site.vercel.app/repartition.html#developpements) affiche les modifications en cours séparément des responsabilités habituelles. Les secteurs partagés restent accessibles aux deux frères.

## Activation sur chaque ordinateur

1. Faire un pull du projet. Node.js et une version récente de Codex avec les hooks sont nécessaires (testé avec Codex 0.155.1).
2. Dans le dossier du jeu, lancer `node tools/coordinate.cjs setup`. Choisir `akomoses` ou `morepudding`, puis entrer le code d’édition de la page Répartition. Ce code et le jeton restent locaux, ignorés par Git. Le jeton expire au bout de six mois ; relancer setup pour le renouveler. Changer le code du site révoque tous les jetons.
3. Ouvrir `/hooks` dans Codex, lire et approuver les quatre hooks du projet. Faire confiance au projet s’il est demandé. Ouvrir ensuite une nouvelle conversation. Une modification du fichier de hooks demandera une nouvelle approbation. Ne pas activer un contournement global de cette vérification.

Codex consulte une liste courte au début du prompt. Pour un développement, il lit les travaux récents et les secteurs, puis réserve la modification avant d’écrire. Une question ou une analyse ne crée rien sur le tableau.

## Cycle d’un développement

```text
node tools/coordinate.cjs context
node tools/coordinate.cjs catalog
node tools/coordinate.cjs claim --title "Corriger les bots bloqués derrière un couvert" --topic "ia-contournement-couverts" --sectors "intelligence-artificielle" --files "scripts/training_bot.gd"
```

Si CODEX_THREAD_ID n’est pas exposé, ajouter `--session IDENTIFIANT` donné par le hook. Une conversation garde une réservation pour le travail en cours. Un sujet identique occupé ou terminé localement est refusé. Un fichier commun ou un titre proche déclenche un avertissement que Codex doit examiner. Cette détection n’est pas une compréhension parfaite des intentions : des titres très différents peuvent encore décrire le même besoin. Utiliser des sujets précis et stables.

Avant chaque écriture couverte, le hook renouvelle et vérifie la réservation. Sans activité pendant 45 minutes, elle apparaît interrompue ; il faut réserver à nouveau. Une interruption ou une fermeture la libère immédiatement lorsque le hook peut joindre le site. Une panne réseau bloque les écritures couvertes et laisse les lectures possibles. Rien n’est effacé automatiquement du disque.

Après vérification du travail, `node tools/coordinate.cjs finish --summary "Les bots contournent les couverts sans rester bloqués. Le comportement a été vérifié."` affiche « Terminé localement, non publié ». Codex fournit ce bref résumé public en français (deux phrases maximum) ; il est repris dans le bilan Discord du lendemain. Sans résumé, le titre sert de description. Ajouter le trailer fourni à chaque commit contenant ce travail :

```text
Prototype-Work: identifiant-fourni-par-la-reservation
```

Le workflow GitHub de la branche main confirme « Publié » seulement pour les réservations citées dans les commits effectivement poussés. `node tools/coordinate.cjs cancel` abandonne un travail ; cela ne supprime pas ses fichiers. Un simple arrêt de réponse de Codex n’est jamais traité comme une livraison.

Après `finish`, `git add`, `git commit` et `git push` restent autorisés pour cette conversation : ils vérifient la réservation existante sans rouvrir le développement. Une suite de ces commandes accompagnée de lectures (par exemple `git diff --cached --check`) est également acceptée. Toute commande mêlant une nouvelle écriture dans les fichiers doit encore disposer d’une réservation active. En cas de commande shell complexe non reconnue, lancer les étapes Git séparément.

## Limites et coût

Aucun modèle supplémentaire, agent PMD ou analyse de l’historique entier à chaque prompt. Le contexte initial est plafonné ; les appels de vérification ne produisent pas de texte lorsqu’ils réussissent. Le site reçoit seulement le titre court, les secteurs, les chemins relatifs et les références Git. Aucun prompt brut, transcript, code ou secret n’est envoyé au tableau.

Les hooks complètent AGENTS.md. Ils couvrent les outils d’écriture et les commandes shell habituels ; ce ne sont pas une sandbox ni une protection contre un outil qui contourne volontairement ce parcours. Les anciennes conversations déjà ouvertes doivent relire les instructions, et les hooks nécessitent leur activation sur chaque machine.

Chaque matin vers 9 h (heure de Paris), le salon Discord affiche les travaux terminés localement ou publiés la veille, regroupés par secteur et par personne. Une modification couvrant plusieurs secteurs apparaît une seule fois avec tous ses secteurs. Les travaux locaux portent la mention « sur le PC, à publier » ; une livraison ultérieure est signalée comme publication. Les heures de fin et de publication sont conservées indépendamment. Si rien n’a été terminé ou publié, le bot le dit simplement. Le message est limité à 1 900 caractères, avec un lien vers l’historique pour le complément éventuel et la répartition permanente.
