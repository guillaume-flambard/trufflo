# 0006. Runner d'intégration continue : `xcode-27`, et seulement lui

Status: Accepted

Contexte

Trufflo doit pouvoir être vérifié ailleurs que sur la machine de Guillaume,
et `.github/workflows/ci.yml` est le premier automate de vérification du dépôt.
La question du runner n'est pas neutre : elle décide si la CI verte prouve
quelque chose.

Deux faits vérifiés avant de décider, l'un contre l'intuition :

- le dépôt est public (`gh repo view guillaume-flambard/trufflo` →
  `visibility: PUBLIC`), donc les runners standards GitHub sont gratuits et
  illimités pour ce dépôt, macOS compris. Les « larger runners » ne sont de
  toute façon réservés qu'aux organisations et entreprises, donc hors de
  portée d'un dépôt personnel. Aucune raison de bricoler un runner
  auto-hébergé, ni d'utiliser le VPS ;
- `IPHONEOS_DEPLOYMENT_TARGET = 27.0` dans `trufflo.xcodeproj/project.pbxproj`.
  L'image `macos-26` embarque Xcode 26.6 et monte au SDK iOS 26.5 : ** elle ne
  peut pas compiler ce projet. ** Seule l'image `xcode-27` fournit le SDK
  iOS 27.

Le coût de ce choix est réel et doit rester visible. `xcode-27` est une
**public preview** qui embarque **Xcode 27.2 bêta** sur macOS 27, et la
documentation GitHub précise que les images beta sont fournies « as-is, with
all faults » et sont exclues du SLA. Une mise à jour de l'image peut donc
faire rougir `main` sans qu'une ligne de code n'ait changé. La Github
Actions est le premier juge externe du projet : le faire reposer sur une
image de préversion crée une classe de panne qui n'est pas la nôtre.

Décision

La CI utilise `xcode-27`, avec deux jobs :

- `unit` : `TruffloFast`, la porte rapide sur chaque PR ;
- `journeys` : `tools/sim/gps-journeys.sh all`, les huit parcours UI.

Aucun job Android, `contracts/` ou backend n'est écrit : `android/`,
`contracts/` et `backend/` n'existent pas encore, et une étape qui ne peut rien
exécuter n'est pas une vérification.

`macos-26` n'est pas proposé en repli tant que la cible de déploiement est
27.0. Baisser la cible à iOS 26 rendrait l'image stable possible, mais cela
change qui peut installer l'application : c'est une décision de produit, pas
une préférence d'outillage.

Conséquences

- La chaîne d'outils de la CI n'est pas celle du poste local (27.2 bêta contre
  27.0). Un écart de comportement est possible et devra être lu comme tel, pas
  comme une régression du code.
- La CI ne valide pas sur appareil physique. Les mesures terrain (T16 : dérive
  à l'arrêt, batterie) restent hors de portée des deux job.
- `macos-latest` n'est pas utilisé, volontairement : c'est une étiquette
  mouvante, et le passage automatique à une image différente casserait la
  comparaison entre exécutions.
- Si l'image `xcode-27` devient stable, ou si la cible de déploiement descend,
  cette décision doit être revue : elle est datée et pas définitive.
- Les cinq parcours GPS ont été vérifiés avec le script, jamais par une
  exécution `TruffloFull` nue. Voir `AGENTS.md`, section « Five journeys need
  host setup, not two ».
