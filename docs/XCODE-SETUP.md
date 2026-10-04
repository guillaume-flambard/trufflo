# Configuration Xcode

## 1. L’écran montré

| Champ | Valeur recommandée | Motif |
|---|---|---|
| Modèle à l’écran précédent | `iOS → App` | Le produit est d’abord une app de promenade sur iPhone. |
| Product Name | `trufflo` | Conserver le module et le bundle de la capture. |
| Team | Team déjà sélectionnée | Ne pas inventer un identifiant de team ni modifier la signature. |
| Organization Identifier | `dev.memolabs` | Conserver le préfixe choisi par l’utilisateur. |
| Bundle Identifier | `dev.memolabs.trufflo` | Vérifier sa présence exacte après création. |
| Interface | `SwiftUI` | Interface native retenue. |
| Language | `Swift` | Code natif et domaine testable. |
| Testing System | `Swift Testing with XCTest UI Tests` | Tests métier en Swift Testing, parcours UI en XCTest. |
| Storage | `SwiftData` | Persistance locale du journal. |
| Host in CloudKit | Décoché | Aucune synchronisation automatique des données du pilote. |

Le choix du modèle iOS n’est pas visible dans la capture fournie : le vérifier avec Previous au besoin. La disponibilité effective d’un identifiant de bundle dépend du compte Apple ; aucune réservation n’a été effectuée ici. Références Xcode/tests/SwiftData : [S01–S04].

## 2. Après Next

Créer le projet dans un dossier de travail dédié. Activer Git seulement si ce dossier n’appartient pas déjà à un dépôt existant. Conserver le `.xcodeproj` généré : ne pas le remplacer par un générateur ou une autre architecture pour ce starter.

Dans la cible de l’app, définir le nom affiché à **Trufflo**, via `CFBundleDisplayName`. Garder `PRODUCT_BUNDLE_IDENTIFIER=dev.memolabs.trufflo`. Le code et les imports des tests supposent un module nommé `trufflo` ; adapter les imports uniquement si le nom réel est différent.

Décisions du starter : minimum de déploiement **iOS 18.0**, interface iPhone en premier, Swift 6, **Default Actor Isolation = Nonisolated** ; les frontières UI et SwiftData concernées sont explicitement marquées `@MainActor`. Ce minimum est un choix de support, pas une affirmation sur la dernière version d’iOS. Utiliser le SDK installé avec Xcode et consigner sa version.

Ne pas élargir simultanément à macOS, watchOS, visionOS ou Android. L’adaptation iPad éventuelle n’est pas un jalon de lancement.

## 3. Remplacer le template sans doublon

Remplacer le contenu du fichier généré `truffloApp.swift` par celui du starter. Retirer les exemples `Item.swift` et `ContentView.swift` de la cible lorsqu’ils ne sont plus référencés. Ne jamais garder deux types `@main`. Conserver `Assets.xcassets`.

Créer les dossiers et fichiers décrits dans `STARTER-CODE.md`. Ajouter les sources de l’app à la cible `trufflo`, les tests unitaires à `truffloTests` et les tests UI à `truffloUITests`. Les noms réels des cibles doivent être lus dans le projet, pas supposés si celui-ci existait déjà.

Le schéma M0 contient `DogRecord`, `WalkRecord` et `WalkDogRecord`. Les trois doivent appartenir au même `ModelContainer`. Les identifiants ont une contrainte d’unicité locale. Ce schéma n’est pas déclaré compatible avec la synchronisation CloudKit automatique. [S11]

## 4. Stockage local explicite

Le starter utilise `ModelConfiguration(..., cloudKitDatabase: .none)`. La documentation décrit cette valeur comme désactivant la synchronisation CloudKit gérée par SwiftData. [S04]

Le paramètre `--uitesting` active un stockage en mémoire seulement dans un build Debug. En usage normal, une erreur d’ouverture de la base affiche un écran d’erreur et ne remplace jamais silencieusement le journal par une base vide. Ne jamais supprimer la base pour faire disparaître une erreur de migration.

Avant collecte de tracés réels, vérifier les sauvegardes système, les fichiers annexes SQLite et la protection des fichiers quand le téléphone est verrouillé. « CloudKit désactivé » ne prouve ni l’absence de sauvegarde cloud système ni la possibilité d’écrire des données écran verrouillé.

## 5. Activer le GPS au jalon M1 seulement

M0 ne demande aucune permission de localisation. Avant de brancher le service M1, ajouter **Signing & Capabilities → Background Modes → Location updates** et uniquement le mode réellement nécessaire. Ajouter la clé `NSLocationWhenInUseUsageDescription` dans les propriétés Info de la cible, sans créer un second Info.plist concurrent.

Texte proposé :

> Trufflo utilise votre localisation pendant une balade que vous démarrez pour enregistrer votre parcours, y compris lorsque l’écran est verrouillé. Vous pouvez arrêter l’enregistrement à tout moment.

Lancer la demande au clic sur « Partir en balade », pas à l’ouverture de l’app. Ne pas ajouter « Always » comme réflexe ni activer HealthKit, Motion, iCloud, notifications distantes, microphone ou contacts. Refus et localisation approximative doivent rester des cas utilisables, avec saisie manuelle accessible.

Pour la voie `CLLocationManager` retenue, configurer `allowsBackgroundLocationUpdates` après ajout du mode `location`. Apple précise que l’activer sans la configuration Info correspondante provoque une erreur fatale. Ne pas confondre la continuité d’une session commencée au premier plan avec une surveillance permanente. [S05, S06]

## 6. Vérifier les outils et destinations réels

À exécuter dans le dossier du projet, en adaptant le nom du projet uniquement s’il diffère :

```bash
xcodebuild -version
xcodebuild -list -project trufflo.xcodeproj
xcrun simctl list devices available
xcodebuild -showdestinations -project trufflo.xcodeproj -scheme trufflo
```

Puis renseigner un UDID réellement présent :

```bash
SIMULATOR_UDID="UDID_REEL_DU_SIMULATEUR"
xcodebuild test \
  -project trufflo.xcodeproj \
  -scheme trufflo \
  -destination "platform=iOS Simulator,id=${SIMULATOR_UDID}" \
  -resultBundlePath ./TestResults/M0.xcresult
```

Ne pas réutiliser un chemin de résultat existant sans le déplacer ou choisir un autre nom. Le schéma doit inclure les cibles de tests et être partagé avant une exécution CI.

Pour M1, sélectionner un iPhone physique et vérifier la signature sur cet appareil. Un résultat simulateur n’est pas une preuve d’arrière-plan, de précision GPS, de consommation de batterie ou de comportement après fermeture forcée.
