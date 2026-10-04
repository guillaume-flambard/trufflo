# Architecture et décisions

## ADR-001 — iPhone natif, pas de double client initial

Choix : SwiftUI et Swift, cible iOS. Conséquence : intégrations Apple directes, mais pas d’application Android fournie par ce choix. Le préfixe `dev.memolabs.trufflo` et le nom de module `trufflo` restent ceux du projet montré. Ne pas recréer un projet Expo derrière cette décision.

## ADR-002 — Une app, deux cibles de test, pas de microframeworks

Le dépôt initial contient la cible app, les tests unitaires Swift Testing et les tests UI XCTest. Le domaine Swift peut être exercé séparément ; le package fourni pour contrôle n’est pas une dépendance supplémentaire obligatoire de l’app.

Structure cible, à créer progressivement :

```text
trufflo/
  truffloApp.swift
  App/
    AppState.swift
    AppDependencies.swift
  Domain/
    WalkDomain.swift
    DogProfile.swift
    RoutineGoal.swift
  Data/
    Models.swift
    PersistenceFactory.swift
    WalkRepository.swift
    TrackWriter.swift
    ExportService.swift
  Services/
    LocationClient.swift
    CoreLocationClient.swift
    WalkCoordinator.swift
  Features/
    Today/
    Walk/
    Journal/
    Dogs/
    Settings/
  DesignSystem/
  Resources/
    Assets.xcassets
    Localizable.xcstrings
truffloTests/
truffloUITests/
docs/
AGENTS.md
```

Le code M0 regroupe temporairement la navigation dans `StarterRootView`. Ne pas précréer des dizaines de fichiers vides. Extraire chaque feature lorsque son comportement apparaît. Les scripts de génération ne doivent pas écraser le projet Xcode existant.

## ADR-003 — Persistance locale SwiftData

Choix : un `ModelContainer`, schéma explicite, CloudKit désactivé. `@Query` suffit au petit journal manuel M0. À M1, les écritures GPS passent par un acteur de stockage et des transactions bornées. Les vues ne reçoivent jamais l’ensemble des points à chaque mise à jour.

La cible utilise une isolation par défaut non isolée et des annotations explicites. UI, état observable de l’interface et points d’entrée de coordination sont sur MainActor. `TrackWriter` utilise `@ModelActor` ou un acteur propriétaire de son contexte après vérification du SDK. Les modèles SwiftData ne passent pas d’un acteur à l’autre ; transmettre UUID, valeurs `Sendable` et DTO. [S03, S14]

Un seul auteur modifie les points et la révision d’une session. Sauvegarder les points et leur agrégat cohérent ensemble. Aucun `try?` sur une sauvegarde critique, aucun effacement « de réparation », aucun fallback silencieux en mémoire.

## ADR-004 — Une seule voie Core Location au premier jalon

M1 emploie `CLLocationManager`, un adaptateur de callbacks, l’autorisation When In Use demandée au démarrage et `allowsBackgroundLocationUpdates` avec le mode de fond adéquat. Cette voie est documentée par Apple. [S06]

Les APIs `CLLocationUpdate`, `CLBackgroundActivitySession` et `CLServiceSession` sont une alternative documentée, pas une seconde source à superposer. Une éventuelle migration doit être décidée et testée ; ne pas lancer deux flux GPS ou deux moteurs de durée. [S05]

## ADR-005 — Le domaine ne connaît pas l’interface

`WalkProgress` gère phases et durée confirmée. `TrackAccumulator` filtre des valeurs et crée des segments. `ManualWalkInput` vérifie l’entrée. Aucune de ces règles ne dépend d’une vue, d’un serveur, de MapKit ou d’une race de chien.

Le service de localisation transforme les données système en `LocationFix`. Le coordinateur vérifie la phase et les permissions, ordonne l’écriture, puis publie une synthèse UI. MapKit est une projection de segments déjà validés, jamais une source métier.

## ADR-006 — Durée confirmée, pas chronomètre magique

Horloge monotone pendant un processus vivant. Le stockage conserve la durée confirmée et l’heure de la dernière écriture. Après lancement à froid, retrouver une session active la rend interrompue ; elle n’accumule pas rétroactivement le temps depuis la veille. Une correction utilisateur reste déclarative.

Le petit moteur fourni vérifie les transitions ; il ne contient pas encore le driver d’horloge natif, la restauration de base ou l’adaptateur Core Location.

## ADR-007 — Identifiants portables et futur cloud explicite

UUID métier stables, DTO versionnés et clés d’idempotence. Ne pas envoyer `PersistentIdentifier` comme identifiant public. La future synchro de M2 concerne les synthèses autorisées, pas les tracés privés par défaut.

Candidat backend : PostgreSQL et authentification compatible, Supabase à évaluer à M2. Le choix n’est pas une dépendance de M0/M1. Ne pas activer CloudKit pour contourner la conception des rôles de foyer : son activation aurait ses propres contraintes et migrations. [S11]

## ADR-008 — Migrations avant données externes

Le schéma M0 est expérimental. Avant TestFlight externe, figer un schéma versionné et créer une fixture issue d’une ancienne version. Tester ouverture, migration et restauration non destructive. Une modification de modèle ne se valide pas par une simple réinstallation effaçant la base.

## ADR-009 — Aucune infrastructure IA dans le produit initial

Pas de génération de conseils, de score de santé, de classificateur de race, d’agent conversationnel ou de microservice de recommandation. Le projet peut être construit avec des agents ; cela ne justifie pas d’en mettre un dans le produit.
