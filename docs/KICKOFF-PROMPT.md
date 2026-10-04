# Prompt initial pour l’agent

Copier le bloc suivant dans l’agent ouvert à la racine du projet Xcode, après placement du pack dans `docs/` et fusion de `AGENTS.md` à la racine.

```text
Tu travailles sur Trufflo, une app iPhone native : SwiftUI, Swift, SwiftData,
Core Location et MapKit. Lis AGENTS.md puis docs/README.md, PRD.md,
ARCHITECTURE.md, BACKLOG.md, TEST-PLAN.md et VERIFICATION.md.

Le premier PRD envisageait Expo. Cette décision est remplacée : pas d’Expo,
pas de React Native, pas de seconde app Android dans ce jalon.
Conserve le projet Xcode, le module et le bundle déjà créés ; ne régénère pas
le projet et ne détruis aucune modification existante.

Commence par inspecter les fichiers, les cibles, la signature, le SDK et les
destinations disponibles. Vérifie iOS, SwiftUI, Swift, SwiftData, les cibles
Swift Testing et XCTest UI. CloudKit doit rester désactivé.

Ta mission initiale est T00–T05 :
- extraire les blocs pertinents de docs/STARTER-CODE.md dans les bons fichiers ;
- conserver un seul @main et les ressources existantes ;
- compiler sur une destination réelle disponible ;
- obtenir le parcours profil canin → saisie manuelle → journal persistant ;
- exécuter les tests métier, SwiftData et UI ;
- vérifier l’effacement global et l’erreur de stockage sans perte cachée.

Les 22 tests du noyau ont passé dans un environnement Linux séparé.
Cela ne prouve pas que l’app iOS compile. Les tests natifs fournis n’ont pas
encore été exécutés. Vérifie-les réellement et corrige les écarts constatés.
Le starter n’a pas encore de suivi Core Location branché : ne présente pas
un chronomètre ou un tracé simulé comme un vrai enregistrement.

Ensuite, prépare T11–T16 conformément à LOCATION-ENGINE.md : modèle de
session/points, acteur d’écriture, permissions, adaptateur Core Location,
coordinateur unique, MapKit par segments et récupération après interruption.
Découpe le travail et ses preuves avant de commencer cette seconde tranche.

Interdits : faux pas canins, conseils chiffrés par race, feed social, achats,
CloudKit activé automatiquement, surveillance permanente, deux moteurs GPS,
réinstallation qui efface les données pour faire passer une migration.

Pour chaque ticket, rapporte : fichiers modifiés, exigences couvertes,
commandes exécutées, résultats, preuves, limites et prochaine dépendance.
Ne marque pas terminé un test d’arrière-plan ou de batterie sans essai sur
un iPhone physique. Toute incertitude restante doit être écrite.
```
