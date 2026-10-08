# Backlog et portes de livraison

## État au 2026-10-08

Mise à jour après les chantiers 8 (maquettes du 2026-10-07) et 9 (plus de statique, front et
back). Détail : `.agent/project/chantier-8-maquettes.md` (local), ADR 0007 et 0010, migrations
`20261007210000` à `20261008100000`.

| Sujet | Statut | Preuve ou manque |
|---|---|---|
| Écrans de la planche (Accueil, live, guidage, proximité, célébration, résumé) | Fait | Captures dans `docs/design-captures/`, 8 parcours UI verts. |
| Cohérence et peaufinage (en-têtes, cartes, Réglages en feuille, micro-animations) | Fait | `TruffloScreenHeader`, `TruffloMotion`, commit du 2026-10-08. |
| Serveur Sorties (M3, T40 à T44 côté serveur) | Fait, en production | 110 contrôles pgTAP dont course réelle sur la dernière place. Onglet fermé tant qu'aucun modérateur n'est inscrit. |
| Détails partagés, balades prévues, conseils en base | Fait, en production | `household_details_test.sql`, test HTTP à deux comptes. |
| Suppression de compte | Fait, en production | `delete_my_account`, réglages. `anon` n'exécute aucune fonction (vérifié en prod). |
| Chiens du foyer à proximité | Fait, en production | Sur accord, foyer seulement, arrondi 10 m, expiration 2 min (décision du 2026-10-08, DATA-CONTRACTS §7). |
| Météo (WeatherKit) | Code fait, service non actif | Le jeton WeatherKit est refusé : cocher WeatherKit dans App Services de l'App ID, puis tester sur iPhone. |
| T16 mesures terrain | Ouvert | Toujours aucune balade sur appareil réel. |
| Ouverture de l'onglet Sorties | Bloqué | Aucun compte en production : Guillaume se connecte une fois, puis inscription comme modérateur (requête en tête de `20261007210000`). |
| Lien de confidentialité et contact, push d'annulation, StoreKit, mode sombre, fichier AASA | Non commencé | Hors des chantiers 8 et 9. |
| Écran Foyer non connecté, introduction pages 2 et 3 | Non revus | Pas capturés pendant le peaufinage. |

Pièges relevés le 2026-10-08 :
- V7 n'est pas livrée et a changé plusieurs fois : un store de simulateur écrit par une version
  intermédiaire ne s'ouvre plus (« unknown model version »). Désinstaller l'app du simulateur
  avant `gps-journeys.sh`. Les journaux V6 réels sont couverts par `MigrationTests`.
- `tools/backend/apply-migration.sh` refuse toute migration qui contient `delete from`, même dans
  le corps d'une fonction : une telle migration s'applique à la main.

## État au 2026-10-06

Le paragraphe « Statuts initiaux » plus bas date du démarrage. Ce tableau le remplace pour l'état.
La suite du travail est décrite dans `docs/specs/` (lots A à D). Un statut « Fait » renvoie à une
preuve ; « Non vérifié » veut dire que personne n'a regardé, pas que c'est absent.

| Ticket | Statut | Preuve ou manque |
|---|---|---|
| T00 à T05 (M0) | Fait | App SwiftUI/SwiftData native, tests unitaires et parcours UI en CI (ADR 0006). |
| T10 profil | Fait | Âge, photo, édition, race inconnue : `DogFormView`, `DogDetailView`. Race par recherche : lot A (A-REQ-03). |
| T11 à T15 moteur de balade | Fait | Chantier 2, `.agent/archive/chantier-2/` ; parcours GPS dans `tools/sim/gps-journeys.sh`. |
| T16 mesures terrain | Ouvert | Aucune mesure sur appareil réel (risque R-09). Demande une vraie balade. |
| T17 routines choisies | Fait en partie | Routines choisies et suspendables (PRD F04). Bilans de période : phrase des 7 jours sur Aujourd'hui, rien de plus. |
| T18 export et suppressions | Fait | Export CSV/GPX (`ExportArchive`), suppression d'une balade et d'un profil, effacement global. |
| T19 sauvegardes et audit des flux | Non vérifié | Seule la session du foyer est exclue des sauvegardes (`AuthSession`). Comportement de la sauvegarde iOS du journal non revu. |
| T20 UX finale et accessibilité | En cours | Lot A : Aujourd'hui, Journal, Profil en variante A ; reste la matrice de captures (A-REQ-06). Mode sombre : décision D4. |
| T30 à T33 (M2, foyer) | Fait, sauf recette réelle | Chantier 3, ADR 0007 et 0008, migrations en prod le 2026-10-06. Deux appareils réels : lot B (B-REQ-01). |
| T40 à T44 (M3) | Non commencé | Spécifié dans `docs/specs/C-premiere-sortie.md`. |
| T50 à T52 (M4) | Non commencé | |

Statuts initiaux : les documents et le noyau testé sont fournis ; **aucun ticket d’intégration dans le projet de l’utilisateur n’est marqué terminé**. Les critères incluent tests et preuve, pas seulement code écrit. Ne pas estimer un calendrier sans examiner le projet local.

## M0 — Démarrage natif

| ID | Travail | Critère de sortie | Dépend de |
|---|---|---|---|
| T00 | Lire le dépôt, vérifier cible iOS, module, signature et tests. | Inventaire écrit, aucun fichier utile écrasé. | — |
| T01 | Installer les documents et l’app SwiftUI/SwiftData locale. | Build natif réussi, un seul `@main`, CloudKit désactivé. | T00 |
| T02 | Extraire le noyau et ses tests. | 22 tests du domaine passent dans le contexte prévu. | T01 |
| T03 | Brancher profils et journal manuel. | Création chien → saisie → journal → relancement, sans perte. | T01–T02 |
| T04 | Exécuter tests SwiftData et XCTest UI. | Résultats natifs enregistrés ; échecs non masqués. | T03 |
| T05 | Préparer schéma/migrations et erreur de stockage. | Pas de fallback vide, fixture de migration prévue avant pilote. | T03 |

Porte M0 : un utilisateur retrouve une vraie saisie après fermeture/réouverture. L’app indique honnêtement que le GPS n’est pas encore branché. Les validations de l’environnement de génération ne sont pas réutilisées comme preuve Xcode.

## M1 — Alpha individuelle réelle

| ID | Travail | Critère de sortie | Dépend de |
|---|---|---|---|
| T10 | Compléter âge, photo, édition et race inconnue. | Profil incomplet pleinement utilisable ; aucune prescription par race. | M0 |
| T11 | Ajouter modèles de session/points et acteur d’écriture. | Transactions, rollback, ordre et migrations testés. | T05 |
| T12 | Adaptateur Core Location et permissions. | Refus/précision réduite gérés ; collecte arrêtée hors session. | T11 |
| T13 | Coordinateur unique et chronomètre monotone. | Doubles appuis, pause/reprise, callbacks tardifs et erreurs couverts. | T12 |
| T14 | Récupération après interruption. | Aucun temps/tracé inventé après fermeture forcée. | T13 |
| T15 | MapKit par segments et bilans de qualité. | Pas de pont entre trous ; distance absente distincte de zéro. | T13 |
| T16 | Calibrer dérive, précision et batterie. | Mesures terrain avec conditions et défauts documentés. | T14–T15 |
| T17 | Routines choisies et bilans de période. | Suspendables, sans compétition, sans rattrapage automatique. | T10–T15 |
| T18 | Export et suppressions ciblées. | Tracés, liens, noms historiques et agrégats traités. | T11 |
| T19 | Sauvegardes/protection locale et audit des flux. | Limites du local explicites ; pas de coordonnées dans télémétrie. | T16–T18 |
| T20 | UX finale des trois tabs et accessibilité. | États normaux/vides/erreur + captures clair/sombre/grand texte. | T10–T19 |

Porte M1 : vraie promenade sur iPhone, écran verrouillé, pause et interruption testées, export et suppression fonctionnels. La CI verte ne remplace pas cette preuve.

## M2 — Foyer privé

| ID | Travail | Critère de sortie | Dépend de |
|---|---|---|---|
| T30 | Décider et provisionner backend minimal. | Coût, schéma, règles d’accès et secrets documentés. | M1 + justification utilisateur |
| T31 | Invitations et rôles. | Autorisation serveur, expiration et révocation testées. | T30 |
| T32 | Synchroniser seulement les synthèses autorisées. | Idempotence, conflits et effacement sans résurrection. | T31 |
| T33 | Doublons et agrégats familiaux. | Deux comptes ne doublent pas une balade partagée. | T32 |

Porte M2 : deux appareils et deux comptes coopèrent sans divulguer les trajets précis par défaut.

## M3 — Communauté locale

| ID | Travail | Critère de sortie | Dépend de |
|---|---|---|---|
| T40 | Politique d’âge, règles, support et modération. | Responsable nommé ; protections testées avant ouverture. | M2 + décision pilote |
| T41 | Événements réels et points publics. | Aucun domicile inféré, aucun faux événement. | T40 |
| T42 | Participation et capacités transactionnelles. | Dernière place concurrente, annulation et retrait couverts. | T41 |
| T43 | Conversation liée à la sortie et blocage. | Pas de messages non autorisés ; retrait effectif serveur. | T40–T42 |
| T44 | Pilote dans une seule zone. | Présences déclarées, retours et charge de modération mesurés. | T43 |

Porte M3 : sorties réellement organisées et dispositifs de sécurité opérationnels. Sans responsable de modération, cette étape reste bloquée.

## M4 — Prix et extensions

T50 : analyser activation/rétention et coûts avec effectifs réels. T51 : tester l’intérêt pour Plus sans cacher les fonctions de base. T52 : intégrer les achats uniquement après validation du périmètre et des règles de boutique applicables. Aucun jalon n’autorise implicitement Android, Watch, rencontres amoureuses ou IA.

## Format d’un ticket livré

```markdown
## Txx — Intitulé
Statut : À faire / En cours / Bloqué / Vérifié
Exigences PRD : Fxx
Fichiers touchés : ...
Décision : ...
Tests exécutés et résultat : ...
Preuve native/terrain : ...
Limites restantes : ...
Prochaine dépendance : ...
```

Une dépendance externe non résolue produit « Bloqué », jamais une validation fictive. Les modifications du `.xcodeproj` ont un seul propriétaire à la fois.
