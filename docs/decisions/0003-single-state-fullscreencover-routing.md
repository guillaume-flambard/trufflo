# 0003. Routage du couvert plein écran par une source d'état unique

Status: Accepted

Contexte

Le parcours UI « fermeture forcée puis relance » (T29) créait une session GPS
parasite à chaque ouverture depuis le bandeau. Le bouton « Afficher » écrivait
`activeWalkIDToResume` puis `showActiveWalkSheet`, deux `@State` distincts
pilotant un même `fullScreenCover(isPresented:)`. La première évaluation du
contenu du couvert lisait l'identifiant encore `nil`, présentait la branche
« nouvelle balade », lançait `startSession()` par le `.task` de
`ActiveWalkView`, puis une seconde évaluation présentait la branche reprise.
Journal horodaté à l'appui (E-027) : `EVT afficher` puis `EVAL cover id=nil`
puis `task branch=start`, ensuite `EVAL cover id=resume-...` puis
`task branch=resume`.

Décision

Le couvert est piloté par un seul `@State` de type `ActiveWalkCover`
(`.resume(UUID)` ou `.start`), présentation et branche comprises, via
`.fullScreenCover(item:)`. La branche dérive du paramètre que SwiftUI passe
à la fermeture de construction, jamais d'une variable capturée : une lecture
périmée ne peut plus sélectionner la mauvaise branche.

Conséquences

- Un `nil` périmé ne provoque plus de présentation : présentation et
  contenu lisent la même valeur.
- Ajouter un état de la balade = ajouter un cas à `ActiveWalkCover`, pas une
  variable d'état de plus.
- La session parasite n'était pas un doublon d'appui mais un défaut
  d'évaluation du couvert ; tout retour à un couple booléen plus identifiant
  séparés doit être refusé en revue.
