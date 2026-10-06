# Lot D : tests d'usage

Exigence du PRD couverte : §8 (validation produit).

## Objectif

Des personnes extérieures à l'équipe utilisent Trufflo, et ce qu'on observe change les priorités
écrites. Ces effectifs servent à **trouver des problèmes**, pas à prouver une adéquation au marché.

## 1. Protocole

| Étape | Qui | Quand |
|---|---|---|
| D-1 | Cinq personnes avec un chien, extérieures à l'équipe | Fin du lot A |
| D-2 | Deux ou trois foyers, pendant une semaine | Fin du lot B |
| D-3 | Deux ou trois sorties réelles dans la zone pilote | Ouverture du lot C |

Chaque séance : on donne une tâche, on observe sans aider, on note. Pas de démonstration avant.

Le matériel est dans `docs/research/` : guide de séance, fiche d'observation, message de
recrutement, marche à suivre pour installer l'app (`distribution.md`, qui dit ce qui est vérifié et
ce qui ne l'est pas), modèle de synthèse.

**État des prérequis au 2026-10-07 :** D-1 attend la fin du lot A (matrice de captures, photos
réelles de chien) mais n'a besoin d'aucun envoi à Apple : les séances se font sur l'iPhone de
Guillaume. D-2 et D-3 demandent TestFlight externe, donc une fiche d'app et une revue Apple.

## 2. Tâches observées

| Tâche | Question | Signal d'échec |
|---|---|---|
| Ajouter son chien et sa race | Trouve-t-elle la bonne option sans aide ? | Demande d'aide, race laissée vide faute de la trouver |
| Lire Aujourd'hui | Peut-elle dire la prochaine action et d'où viennent les chiffres ? | Confusion entre ses balades et celles du foyer |
| Inviter un proche | Le parcours aboutit-il sans code dicté ? | Le proche abandonne ou demande de l'aide |
| Retrouver la sortie d'un proche | Comprend-elle qui a enregistré quoi, et ce qui n'est pas partagé ? | Croit que les notes ou tracés sont partagés |
| Demander à rejoindre une sortie | Comprend-elle « en attente » et « confirmé » ? | Se présente sans confirmation |
| Revenir quelques jours après | Revient-elle pour une raison précise, ou seulement parce qu'on le lui a demandé ? | Aucun retour spontané |

## 3. Ce qu'on note

Temps par tâche, erreurs, demandes d'aide, retours spontanés, raisons d'abandon, problèmes de
confiance (« où partent mes données ? »). « C'est joli » ne vaut ni usage ni disposition à payer.

## 4. Ce qui sort de chaque étape

Une synthèse datée (`docs/research/modele-synthese.md`) : ce qui a été observé, ce qui change dans
les specs, les décisions prises. Une observation qui ne change rien est quand même écrite.

**Où elle vit : dans le Vault, pas dans ce dépôt.** Le dépôt est public (vérifié le 2026-10-07 avec
`gh repo view`). Une fiche remplie contient des citations et des habitudes de vraies personnes,
même sans nom. Seule une décision, avec son motif et sans citation identifiable, peut être reportée
dans une ADR ou dans une spec.
