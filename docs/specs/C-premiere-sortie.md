# Lot C : une première sortie collective

Exigences du PRD couvertes : F09 (proposer une balade locale), F10 (participation), F11 (modération),
F13 (confidentialité). Jalon PRD : M3, pilote dans une seule zone.

## Objectif

Dans une zone pilote, une personne trouve une promenade à une date précise, comprend qui
l'organise, demande à venir, reçoit une réponse, et la sortie a lieu. L'objet social est la
**sortie**, pas une carte de personnes ni un fil d'actualité.

Ce lot se conçoit et se construit maintenant. Il **ne s'ouvre au public** qu'avec les décisions
D5 (zone), D6 (responsable de modération) et C-REQ-09 (protections) toutes fermées.

## 1. État de départ vérifié

Aucun écran, modèle ou table de sortie collective dans le dépôt à `d51dbac` (`trufflo/Features/`,
`backend/supabase/migrations/`). Le foyer fournit la connexion Apple et le serveur, réutilisés ici.

## 2. Modèle de données proposé

Propositions, aucune de ces tables n'existe. Le schéma définitif passe par un ADR avant la première
migration.

| Concept | Rôle | Point d'attention |
|---|---|---|
| `community_profiles` | Ce que la personne choisit de montrer : prénom ou pseudo, zone, chiens publiés. | Projection volontaire. Jamais une copie de `DogRecord` ou du foyer. Les notes privées n'y vont pas. |
| `outings` | Une sortie à venir : créneau, durée indicative, point de rendez-vous public, organisateur, capacité humaine et canine, règles. | Distincte d'une balade enregistrée (`WalkRecord`). |
| `outing_participants` | Demande, acceptation, refus, retrait, annulation, présence déclarée. | États distincts (PRD F10). La capacité se vérifie dans une transaction serveur. |
| `outing_dogs` | Les chiens annoncés par un participant. | Choisis parmi les chiens publiés. |
| `outing_updates` | Changement d'heure ou de lieu, annulation. | Structuré, pas une messagerie. Permet de se retirer. |
| `reports`, `blocks` | Signalement et blocage. | Effet immédiat côté serveur (PRD F11). |

Une balade enregistrée pendant une sortie reste personnelle : la sortie ne fusionne ni n'expose les
tracés de ses participants.

## 3. Exigences

**C-REQ-01, contrat de sortie.** ADR + migration + tests pgTAP des tables du §2, avec les droits :
un inconnu voit les sorties publiées de sa zone, pas les participants ; un participant accepté voit
les autres participants acceptés et leurs chiens annoncés ; l'organisateur voit les demandes.

**C-REQ-02, liste des sorties.** Un onglet ou une entrée « Sorties » liste les sorties à venir de la
zone choisie, triées par date, avec date, durée indicative, point de rendez-vous, organisateur et
places restantes. Une liste vide le dit honnêtement et propose de changer de zone ou de signaler
son intérêt. Jamais de sortie ou de participant fictif en production.

**C-REQ-03, détail et demande.** Le détail montre l'organisateur, le rendez-vous public, la durée,
les règles, les places et les chiens annoncés. Une seule action dominante : « Demander à venir »,
avec le choix des chiens qui viennent.

**C-REQ-04, mes sorties.** La personne retrouve ses demandes et leurs états, peut se retirer, et voit
tout changement d'heure ou de lieu avec la possibilité de se retirer.

**C-REQ-05, côté organisateur.** Créer une sortie, accepter ou refuser une demande, modifier
l'heure ou le lieu (les inscrits sont prévenus dans l'app), annuler.

**C-REQ-06, dernière place.** Deux demandes acceptées en même temps pour la dernière place : une
seule passe, l'autre reçoit un refus explicite.

**C-REQ-07, après la sortie.** Présence déclarée (distincte de l'inscription), retour privé à
l'organisateur, et « Reproposer cette sortie » pour l'organisateur.

**C-REQ-08, confidentialité.** Aucune position en direct, aucun domicile déduit, aucun tracé
partagé. La zone est choisie par la personne, pas déduite du GPS.

**C-REQ-09, protections avant ouverture (F11).** Signalement d'une sortie et d'un profil, blocage
immédiat, retrait effectif d'un contenu, contact visible, responsable nommé (D6). Revue des
règles Apple §1.2 sur les contenus utilisateurs, sans garantie d'acceptation.

**C-REQ-10, adultes seulement** pour le pilote (PRD §3), dit à l'inscription.

## 4. Critères d'acceptation

| ID | Exigence | Étant donné | Quand | Alors | Preuve |
|---|---|---|---|---|---|
| C-AC-01 | REQ-01 | un inconnu, un participant accepté, l'organisateur | chacun lit les participants | seuls les deux derniers les voient | pgTAP |
| C-AC-02 | REQ-02 | une zone sans sortie | on ouvre « Sorties » | message honnête, pas de faux contenu | capture |
| C-AC-03 | REQ-03 | une sortie avec places | on demande à venir avec Oslo | la demande est « en attente », Oslo annoncé | intégration + parcours UI |
| C-AC-04 | REQ-04, 05 | une demande acceptée | l'organisateur change l'heure | le participant voit le changement et peut se retirer | intégration |
| C-AC-05 | REQ-06 | une place, deux acceptations simultanées | elles arrivent au serveur | une seule passe | test de concurrence serveur |
| C-AC-06 | REQ-07 | une sortie passée | un participant déclare sa présence | inscription et présence restent deux états distincts | pgTAP |
| C-AC-07 | REQ-08 | toutes les requêtes du lot | on inspecte les corps | aucune coordonnée de personne, aucun tracé | unitaire |
| C-AC-08 | REQ-09 | un profil signalé puis bloqué | la personne bloquante rouvre la liste | plus rien de la personne bloquée | intégration + parcours UI |
| C-AC-09 | REQ-09 | le pilote | on ouvre au public | D5 et D6 fermées, signalement parcouru de bout en bout par le responsable | observation |
| C-AC-10 | toutes | une zone pilote réelle | deux ou trois sorties ont lieu | proposition, demande, réponse, présence enregistrées | observation (lot D) |

## 5. Hors périmètre du premier pilote

Fil d'actualité, likes, abonnés, messagerie privée libre, carte de personnes en direct, score de
compatibilité entre chiens, classement, recommandations géographiques automatiques, paiement.
Une conversation liée à la sortie (PRD F10) ne se construit qu'après avoir constaté un besoin que
les mises à jour structurées ne couvrent pas.

## 6. Ordre de travail

1. ADR du modèle (C-REQ-01), relu ensemble avant toute migration.
2. Serveur : migrations, droits, concurrence (REQ-01, 06), avec la CI SQL du lot A.
3. Client : liste, détail, demande, mes sorties (REQ-02 à 04).
4. Organisateur (REQ-05), après la sortie (REQ-07).
5. Protections (REQ-09) : construites avant l'ouverture, pas après.

## 7. Décisions dont dépend ce lot

D5 (zone), D6 (modération), D7 (répartition avec Natha).
