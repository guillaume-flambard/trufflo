# Données et invariants

## 1. Le schéma de démarrage n’est pas le schéma final

M0 comprend `DogRecord`, `WalkRecord` et `WalkDogRecord`. Les liens utilisent des UUID métier et la référence nominale du chien au moment de la promenade. Le code M0 maintient ces liens lors de la création et de l’effacement global ; les futures commandes de suppression ciblée doivent préserver ou effacer explicitement les références. Aucun cascade implicite n’est supposé.

## 2. Modèles cibles M1/M2

| Entité | Champs de responsabilité | Règles |
|---|---|---|
| DogProfile | UUID, nom, statut de race, race facultative, âge exact/approximatif, photo facultative. | Race inconnue autorisée ; pas de prescription implicite. |
| WalkSession | UUID, dates, phase, durée confirmée, pauses, source, qualité, révision. | Une session n’est pas multipliée par le nombre de chiens. |
| WalkDog | UUID, walkID, dogID, libellé historique. | Un couple walkID/dogID unique au niveau métier. |
| TrackPoint | walkID, séquence, segmentID, coordonnées, précision, heure. | Privé, local, hors DTO publics. |
| RoutineGoal | dogID, type, valeur choisie, dates d’effet, état. | Suspendable et versionné ; provenance utilisateur explicite. |
| Household / Membership | Identité externe et rôles. | Autorisations vérifiées côté serveur à M2. |
| SyncOperation | operationID, aggregateID, version, type, payload minimal. | Idempotence et gestion des tombstones. |

La migration exacte est écrite avant d’ajouter les modèles M1. Un champ requis nouveau reçoit une stratégie de migration, pas une réinstallation des appareils des testeurs.

## 3. Axes d’état indépendants

Phase métier : `recording`, `paused`, `interrupted`, `completed`, `discarded`. État de synchronisation futur : `localOnly`, `pending`, `synced`, `conflict`, `failed`. Qualité : `gpsRecorded`, `gpsPartial`, `manual`, `unavailable`.

Une balade terminée et non synchronisée reste terminée. Une session interrompue ne redevient pas automatiquement active. Un tracé partiel peut être sauvegardé honnêtement. Aucun champ `dogStepsMeasured` sans mesure canine adaptée.

## 4. Contrats de commandes

`createDog` valide nom/race. `startWalk` exige un ensemble non vide de chiens et l’absence de session active. `pauseWalk` et `resumeWalk` sont idempotents pour éviter l’effet des doubles appuis. `appendFixBatch` reçoit des valeurs, jamais un `CLLocationManager`. `finishWalk` attend la sauvegarde finale. `addManualWalk` ne crée ni points ni distance. `deleteWalk` supprime liens, points et dérivés concernés. `exportJournal` exclut les données d’autrui.

Une commande produisant une erreur n’écrit pas une moitié d’agrégat. Toute opération rejouable possède un identifiant stable. Les UUID de persistance SwiftData ne deviennent pas les identifiants réseau.

## 5. Exemple de DTO de synthèse futur

```json
{
  "schemaVersion": 1,
  "walkID": "<UUID>",
  "dogIDs": ["<UUID>"],
  "revision": 1,
  "source": "manual",
  "quality": "manual",
  "startedAt": "<ISO-8601 UTC>",
  "endedAt": "<ISO-8601 UTC>",
  "confirmedDurationSeconds": 900,
  "recordedPathMeters": null
}
```

Les exemples sont synthétiques. Le DTO ne contient pas de latitude, longitude, chemin de fichier local, note privée ou identifiant de publicité. Les futures notes partagées ont un contrat distinct, choisi explicitement.

## 6. Cohérence et calcul

Durée de foyer = somme des sessions distinctes ; durée par chien = somme de ses participations. Deux appareils qui ont enregistré le même événement produisent un doublon potentiel à rapprocher, pas une fusion silencieuse par similarité GPS.

Horodatages en UTC pour échange et affichage dans le fuseau choisi. Durées actives calculées avec une horloge monotone vivante. Une date système modifiée ne doit pas transformer une sortie de quelques minutes en plusieurs heures.

Les corrections conservent l’origine et la révision. Les objectifs passés ne sont pas réécrits pour rendre le présent plus flatteur. Les périodes sans données restent inconnues, pas nulles.

## 7. Droits futurs

Le propriétaire du tracé voit ses coordonnées. Les membres autorisés voient les synthèses partagées. Les participants communautaires voient seulement l’événement et le profil publié. Le modérateur voit les données strictement utiles au signalement, pas l’historique GPS local.

Une révocation n’est pas contournable par un rôle mis en cache. Purger à la reconnexion et interdire les lectures serveur immédiatement. Un client hors ligne peut créer un journal local mais ne peut pas confirmer une place dans un événement dont la capacité serveur est inconnue.

## 8. Conservation et effacement

Proposition à valider : tracés locaux 90 jours par défaut avec choix et export ; synthèses conservées pour le journal demandé jusqu’à suppression ou politique d’inactivité publiée ; messages communautaires 90 jours après événement hors dossier de signalement justifié. Ces durées sont des choix proposés et non des délais légaux universels.

L’effacement couvre points, agrégats, liens, noms historiques, photos et copies contrôlées. Un marqueur de suppression évite la réapparition à la synchronisation. La politique des sauvegardes système est traitée séparément : ne pas promettre une suppression à distance de copies hors contrôle de l’application.
