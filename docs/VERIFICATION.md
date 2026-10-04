# Vérifications réalisées

Date : 4 octobre 2026. Le projet Xcode de l’utilisateur n’a pas été monté ni compilé dans cet environnement.

## Résultats effectifs

| Contrôle | Résultat | Portée |
|---|---|---|
| Noyau métier Swift | 22 tests réussis. | Transitions, durée confirmée, saisie, doublons de chiens, validité et segmentation de points. |
| Compilateur du noyau | Swift 6.2.1, cible x86_64 Linux. | Pas de SDK iOS. |
| Analyse syntaxique des huit extraits natifs | Réussie avec `swiftc -frontend -parse`. | Syntaxe seulement, sans résolution des frameworks Apple ni expansion/type-check complète des macros SwiftData. |
| Build iOS | Non exécuté. | Nécessite le Xcode du Mac. |
| Tests SwiftData et XCTest UI | Fournis, non exécutés. | À lancer après intégration native. |
| GPS réel, batterie, permissions, verrouillage | Non testés. | Ni adaptateur natif branché ni appareil physique dans cet environnement. |
| Validation marché, marque, vétérinaire ou juridique | Non effectuée. | Aucun feu vert externe revendiqué. |

La commande exécutée pour le domaine est `swift test -j 2` dans son package isolé. La sortie rapporte :

```text
Test run with 22 tests in 0 suites passed.
```

Des tests paramétrés couvrent plusieurs valeurs au sein de ces 22 tests. Ce résultat n’est pas un pourcentage de fiabilité global. Il ne couvre ni la dérive GPS stationnaire ni la persistance native après interruption.

## Empreintes des sources incluses dans STARTER-CODE

Les blocs Swift sont les mêmes fichiers que ceux utilisés pour le contrôle de domaine ou l’analyse syntaxique. Empreintes SHA-256 :

| Destination | SHA-256 |
|---|---|
| `trufflo/Domain/WalkDomain.swift` | `38b3dd07a40604a057e99958fe2558395dad920d7a2cb9fa3d33da454bd25597` |
| `trufflo/Data/Models.swift` | `21237a5f53b6e311a505bc5c351e81b78c645c7d6f50055f01233bc41154caba` |
| `trufflo/Data/PersistenceFactory.swift` | `1682ee459b7e49a2825c20fa1cb81635f6a79df457c1f12ead2ea957658d731f` |
| `trufflo/truffloApp.swift` | `e17f4efccd29434fe9083f4042b4ccccfda6457d8cc23698df1fdb5d20712097` |
| `trufflo/Features/StarterRootView.swift` | `32e49fd553bf375d7960a2e3075e71ee6131482de7b7c229863d0a3efe11cfe4` |
| `trufflo/Features/Dogs/DogFormView.swift` | `3a4263ab8d260089a0538038423349ae5a32e0a7c805344b7f250085cfb4726b` |
| `trufflo/Features/Walk/ManualWalkFormView.swift` | `86aa2bdf4d0504892b85178460679e8d9161efe6af89cf131b9d375b9346e7b1` |
| `truffloTests/WalkDomainTests.swift` | `9a904cbe8f90d96474a78a7713682bf856f9f58e8de18d8783dbb3b7723c82f8` |
| `truffloTests/StorageTests.swift` | `3f8258f3bd6020c26fb3cef69099f21055d339f8d180f3fa440c6456736d2a04` |
| `truffloUITests/StarterUITests.swift` | `8073a203440d482bae6ad1c7f677c8a3bfddb4dd555fcff868cb3db1e61b7024` |

Ces empreintes attestent uniquement l’identité des blocs distribués ; elles ne valident pas leur comportement sur iOS.

## Limites connues et prochaine preuve

M0 est un socle manuel. Son UI native reste à compiler et ses tests natifs à exécuter. Le schéma n’a pas de migration native vérifiée. La récupération testée est une transition de valeur décodée, pas une récupération de fichier SwiftData après crash réel.

L’agent doit d’abord intégrer le starter dans le projet existant, compiler, vérifier les cibles de tests et démontrer le journal persistant. Ensuite, implémenter le coordinateur et Core Location selon LOCATION-ENGINE, puis effectuer les essais terrain. Une incertitude restante doit être consignée au lieu d’être convertie en case terminée.
