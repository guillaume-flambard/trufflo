# Specs de livraison

Statut : rédigé le 2026-10-06 à partir de l'audit produit du même jour (révision `f88233d`) et
du code à `d51dbac`. Les constats de l'audit repris ici ont été revérifiés dans le code ; ceux
qui ne l'ont pas été sont marqués « non vérifié ».

## Ce que contient ce dossier, et ce qu'il ne contient pas

`PRD.md` reste la seule source du **quoi** (exigences F01 à F14). Ces specs disent **comment**,
**dans quel ordre** et **comment on sait que c'est fini**. Une spec ne crée jamais une exigence
absente du PRD : si un lot en a besoin, le PRD est modifié d'abord.

`docs/ART-DIRECTION.md` reste la source visuelle. `docs/decisions/` garde les ADR.

## Les quatre lots

| Lot | Fichier | Objectif | Peut démarrer |
|---|---|---|---|
| A | `A-premiere-impression.md` | La personne reconnaît son chien et comprend le produit dès la première minute. | Maintenant |
| B | `B-foyer-utile.md` | Un proche rejoint et contribue sans explication du développeur. | Maintenant, recette bloquée par un second compte Apple |
| C | `C-premiere-sortie.md` | Une sortie collective réelle, de la proposition à la présence, dans une zone. | Conception maintenant ; ouverture bloquée par les décisions D5 à D7 |
| D | `D-tests-usage.md` | Des personnes extérieures utilisent l'app et leurs retours changent les priorités. | Après A, en parallèle de B |

A et la conception de C avancent en parallèle. B sécurise le compte et le partage que C réutilise.

## Format commun

Chaque spec suit le même gabarit :

- **Exigences** : `<LOT>-REQ-nn`, rattachées à un identifiant du PRD.
- **Critères d'acceptation** : `<LOT>-AC-nn`, en Étant donné / Quand / Alors, avec la méthode de
  preuve (unitaire, intégration, parcours UI, capture, appareil réel, observation).
- **Hors périmètre** : ce qui ne sera pas fait dans ce lot, écrit pour ne pas être fait par erreur.
- **Décisions ouvertes** : renvoi vers le registre ci-dessous.

Une exigence est finie quand chacun de ses critères a une preuve écrite dans le suivi du chantier
(`.agent/project/`). Un parcours réussi par l'agent ne remplace pas un test d'usage (lot D).

## Registre des décisions

Ce qui ne se tranche pas dans le code. Chaque ligne a un responsable. Une spec qui dépend d'une
décision ouverte ne passe pas en implémentation sur ce point.

| ID | Question | Recommandation | Responsable | Statut |
|---|---|---|---|---|
| D1 | Source du catalogue de races | Liste écrite par nous (noms français usuels, alias), pas un import FCI : la nomenclature FCI ne couvre pas les races non reconnues et ses conditions de réutilisation ne sont pas vérifiées. | Guillaume | Ouverte |
| D2 | Aujourd'hui montre-t-il mes balades seules, ou aussi celles du foyer ? | Mes balades pour les chiffres ; la dernière contribution du foyer dans un bloc séparé et attribué. | Guillaume | Ouverte |
| D3 | Texte de l'introduction sur la confidentialité (ADR 0008, point ouvert 5) | « Votre carnet reste sur cet iPhone. Si vous créez ou rejoignez un foyer, seuls les résumés de balade sont partagés. » | Guillaume | Ouverte |
| D4 | Mode sombre en V1 | Non : clair seul, l'app le force déjà. À rouvrir avec le lot D. | Guillaume | Ouverte |
| D5 | Zone du pilote communautaire | Une seule ville, choisie là où un organisateur réel existe. | Guillaume | Ouverte |
| D6 | Responsable de modération nommé (PRD F11) | Sans nom, le lot C ne s'ouvre pas au public. | Guillaume | Ouverte |
| D7 | Répartition avec Natha | Natha prend une tranche autonome serveur (événements, invitations, CI SQL) ; pas Android, backend et modération en même temps. | Guillaume et Natha | Ouverte |
| D8 | Plusieurs chiens sur Aujourd'hui (ART-DIRECTION §8.2) | Portrait du premier chien, noms joints ; choix de qui part au démarrage, comme aujourd'hui. | Guillaume | Ouverte |
| D9 | Espèces | Chiens seulement au lancement. Aucun sélecteur d'espèce, aucun renommage `Dog` vers `Pet`. | Guillaume | Ouverte |

## Ce qui est déjà fait et ne doit pas être refait

Vérifié dans le code à `d51dbac` : suivi GPS avec reprise et bilan, journal en chronologie avec
filtres, routines avec pause, export CSV/GPX, foyer (connexion Apple, création, invitation par
code, rapprochement des chiens, synchronisation et temps réel), migrations serveur appliquées en
production le 2026-10-06, Aujourd'hui en variante A. Journal A et Profil A sont implémentés et en
attente de commit à la date de rédaction.

`docs/BACKLOG.md` présente encore tous les tickets comme initiaux. Il est réconcilié par la tâche
A-REQ-00 du lot A.
