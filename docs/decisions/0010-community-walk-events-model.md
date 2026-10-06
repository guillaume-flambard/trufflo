# 0010 : le modèle des sorties collectives (lot C)

Statut : **accepté le 2026-10-07** (recommandations retenues par Guillaume, qui écrit le serveur ; le client est construit contre ce contrat). Noms à fournir : zone pilote (D5), modérateur (D6), organisateurs. Point de rendez-vous en texte seul retenu. (spec
`docs/specs/C-premiere-sortie.md`, C-REQ-01). Rien de ce document n'existe en base.

Exigences du PRD couvertes : F09 (proposer une balade locale), F10 (participation), F11
(modération), F13 (confidentialité).

## Sources lues

- Apple, App Review Guidelines §1.2 (lue le 2026-10-07) : une app à contenus d'utilisateurs doit
  avoir un moyen de **filtrer** les contenus inacceptables, un moyen de **signaler** avec une
  réponse rapide, la possibilité de **bloquer** un utilisateur, et un **contact publié**. Les
  guidelines ne contiennent pas de règle propre aux rencontres en personne. Aucune approbation
  n'est garantie.
- Le schéma du foyer (`20261006170603_household_sharing.sql`) : ses conventions sont reprises
  telles quelles (schéma `private` non exposé, fonctions `security definer` qui ne répondent que
  pour `auth.uid()`, enveloppes `security invoker` exposées, révocation des droits puis octroi
  exact, tests pgTAP qui figent la liste des droits).
- PostgreSQL, verrous de ligne (`SELECT ... FOR UPDATE`) : la base de la vérification de capacité
  ci-dessous. Comportement standard de PostgreSQL, pas une fonction propre à Supabase.

## Principes

1. **Une sortie n'est pas une balade.** `walk_events` décrit un rendez-vous futur. Une balade
   enregistrée pendant une sortie reste un `WalkRecord` personnel ; la sortie ne fusionne,
   n'expose ni ne lit aucun tracé.
2. **Rien ne se déduit, tout se choisit.** La zone est choisie par la personne, jamais tirée du
   GPS. Le point de rendez-vous est un **texte** (« Entrée nord du parc de la Tête d'Or ») : aucune
   coordonnée n'est stockée pour le pilote. Le profil public est une projection volontaire, jamais
   une copie de `DogRecord` ni du foyer.
3. **Le serveur tranche.** Demande, acceptation, capacité, blocage : tout passe par des fonctions
   serveur, sous la RLS, comme `accept_household_invite`. L'app ne fait que demander.
4. **Fermé par défaut.** Une zone n'est visible que si elle est ouverte ; seuls des organisateurs
   inscrits à la main proposent des sorties (PRD F09 : « contrôlées manuellement ») ; un profil
   suspendu ne voit plus rien.

## Tables

| Table | Colonnes principales | Remarques |
|---|---|---|
| `community_zones` | `id text` (slug), `name`, `is_open boolean` | Remplie par migration. Le pilote en ouvre une (décision D5). |
| `community_profiles` | `user_id` (clé), `display_name` 1 à 40, `zone_id`, `adult_declared_at`, `created_at`, `suspended_at` | Créé par la personne. Sans `adult_declared_at`, aucun accès (C-REQ-10). |
| `community_dogs` | `id uuid`, `owner_id`, `name` 1 à 40, `breed_label` 0 à 80, `public_note` 0 à 200, `deleted_at` | Les chiens que la personne choisit de montrer. Aucun lien avec `dogs` du foyer. |
| `community_organizers` | `user_id`, `zone_id`, `added_at`, `added_by` | Écrite par un modérateur seulement. Filtre de §1.2 pour les sorties. |
| `community_moderators` | `user_id`, `added_at` | Écrite à la main en base. Décision D6. |
| `walk_events` | `id`, `organizer_id`, `zone_id`, `starts_at`, `duration_minutes` 15 à 240, `meeting_point` 1 à 120, `rules` 0 à 500, `human_capacity` 1 à 30, `dog_capacity` 1 à 30, `status` (`published`, `cancelled`, `removed`), `created_at`, `updated_at` | `removed` = retiré par la modération. |
| `event_participants` | `event_id`, `user_id`, `status` (`requested`, `accepted`, `declined`, `withdrawn`), `requested_at`, `decided_at`, `attended` (booléen ou nul), `attended_declared_at` | Inscription et présence sont deux colonnes distinctes (PRD F10). |
| `event_dogs` | `event_id`, `user_id`, `dog_id` | Chiens annoncés, pris dans `community_dogs` de la personne. |
| `event_updates` | `id`, `event_id`, `kind` (`time`, `place`, `cancelled`), `previous`, `current`, `created_at` | Ce que voient les inscrits. Pas de messagerie. |
| `reports` | `id`, `reporter_id`, `target_kind` (`event`, `profile`, `dog`), `target_id`, `reason`, `detail` 0 à 500, `created_at`, `handled_at`, `handled_by`, `outcome` | Lisible par les seuls modérateurs. |
| `blocks` | `blocker_id`, `blocked_id`, `created_at` | Effet immédiat, dans les deux sens. |

## Qui voit quoi (RLS)

| Lecteur | Voit |
|---|---|
| Personne sans profil, ou profil suspendu, ou sans déclaration d'âge | Rien de la communauté. |
| Profil de la zone | Les sorties `published` de sa zone, à partir d'hier, sauf celles d'une personne avec qui un blocage existe (dans un sens ou l'autre). Les places restantes via une fonction, **pas** la liste des participants. |
| Participant accepté | En plus : les autres participants acceptés de cette sortie, leur nom public et leurs chiens annoncés, et les `event_updates`. |
| Organisateur | En plus : toutes les demandes de ses sorties, et les présences déclarées. |
| Modérateur | Les signalements, et tout ce qu'il faut pour les traiter. |

Personne ne lit une table de participants « à plat » : les seules lectures passent par la RLS
ci-dessus.

## Fonctions serveur

Chacune suit le modèle du foyer : une fonction `private` en `security definer` qui ne travaille que
pour `auth.uid()`, et une enveloppe `public` en `security invoker`, seule appelable.

| Fonction | Règle |
|---|---|
| `request_to_join(event, dog_ids)` | Profil valide de la zone, sortie publiée et à venir, aucun blocage avec l'organisateur, chiens à soi. Crée ou relance une demande `requested`. |
| `decide_request(event, user, accept)` | Organisateur seulement. **Verrouille la ligne de la sortie (`FOR UPDATE`)**, recompte les personnes et les chiens acceptés, refuse avec « sortie complète » si une capacité serait dépassée. Deux acceptations simultanées de la dernière place : la seconde attend le verrou puis échoue (C-REQ-06). |
| `withdraw(event)` | Le participant se retire, quel que soit l'état ; la place se libère. |
| `update_event(event, starts_at, meeting_point)` | Organisateur. Écrit un `event_updates` ; les inscrits le voient et peuvent se retirer. |
| `cancel_event(event)` | Organisateur. Statut `cancelled`, un `event_updates` de type `cancelled`. |
| `declare_attendance(event, attended)` | Participant accepté, après la fin de la sortie. |
| `report(target_kind, target_id, reason, detail)` | Tout profil valide. |
| `block(user)` / `unblock(user)` | Tout profil valide. |
| `moderate(report, outcome)` | Modérateur : retire une sortie (`removed`), suspend un profil, ou classe le signalement. |

## Couverture de §1.2

| Exigence Apple | Réponse du pilote |
|---|---|
| Filtrer | Les sorties ne viennent que d'organisateurs inscrits à la main. Les textes libres sont courts et bornés en base. Un nom ou une note signalés sont retirés par le modérateur. |
| Signaler, réponse rapide | `report` sur sortie, profil ou chien. Délai de réponse : à fixer avec le responsable nommé (D6), et à écrire dans la page de contact. |
| Bloquer | `blocks`, effet immédiat dans les deux sens, côté serveur. |
| Contact publié | Une page publique (par exemple sur `legal.memolabs.dev`) et un lien dans l'app. |

## Tests prévus (pgTAP, avant tout écran)

- Visibilité : inconnu, profil d'une autre zone, profil suspendu, participant accepté, organisateur,
  modérateur (C-AC-01).
- Dernière place : deux acceptations concurrentes, une seule passe (C-AC-05), par deux sessions
  `dblink` ou deux connexions de test.
- Inscription et présence restent deux états (C-AC-06).
- Blocage : plus aucune sortie ni demande entre les deux personnes (C-AC-08).
- Liste exacte des droits accordés, comme `grants_test.sql`.

## Ce qui n'est pas dans ce modèle, exprès

Coordonnées, carte des personnes, messagerie, fil, likes, abonnés, score de compatibilité,
recommandations, paiement, notifications push. La conversation liée à une sortie (PRD F10) attend
qu'un besoin non couvert par `event_updates` soit constaté (spec C, §5).

## Décisions à prendre à la relecture

1. **D5, la zone pilote** : le slug et le nom à mettre dans la migration.
2. **D6, le modérateur** : la personne, et le délai de réponse promis.
3. **Les organisateurs du pilote** : qui est inscrit au départ.
4. **D7, qui construit le serveur** : la spec propose Natha.
5. **Le point de rendez-vous en texte seul** : suffisant pour le pilote ? L'alternative (une
   coordonnée choisie sur une carte, publique, non liée à la personne) ajoute un risque de
   localisation et une revue de confidentialité.

## Contrat client

Ce que l'app attend du serveur. La source en Swift est `trufflo/Domain/CommunityRemote.swift` ; les
règles sont exécutées par `trufflo/Features/Community/InMemoryCommunityServer.swift` et figées par
`truffloTests/CommunityRulesTests.swift`. Le serveur réel doit tenir les mêmes tests, écrits en
pgTAP.

### Fonctions appelées par le client

| Client (`CommunityRemote`) | Serveur | Forme |
|---|---|---|
| `zones()` | table `community_zones` | lecture, zones ouvertes seulement |
| `myProfile()`, `saveProfile` | `community_profiles` | `saveProfile` refuse sans `adult_declared` vrai ; la date de déclaration ne se réécrit pas |
| `myDogs()`, `saveDog`, `deleteDog` | `community_dogs` | le propriétaire seulement |
| `events(zoneID)` | vue ou fonction `visible_events` | sorties `published` de la zone, à partir d'hier, blocs retirés dans les deux sens ; colonnes de `WalkEventDTO`, dont `organizer_name`, `humans_accepted`, `dogs_accepted`, `my_status` |
| `myEvents()` | idem | sorties organisées ou avec une demande, toutes dates |
| `participants(eventID)` | `list_participants(event)` | organisateur : tous ; participant accepté : les acceptés (sans la colonne `attended`) ; sinon refus |
| `updates(eventID)` | `list_event_updates(event)` | organisateur, demandeur, accepté |
| `requestToJoin` | `request_to_join(event, dog_ids)` | rpc |
| `withdraw`, `declareAttendance` | `withdraw(event)`, `declare_attendance(event, attended)` | rpc |
| `isOrganizer(zoneID)` | table `community_organizers` | booléen pour `auth.uid()` |
| `createEvent`, `updateEvent`, `cancelEvent` | `create_event`, `update_event`, `cancel_event` | rpc, organisateur seulement |
| `decide` | `decide_request(event, user, accept)` | rpc, verrou `FOR UPDATE` sur la sortie |
| `report`, `block`, `unblock` | `report`, `block`, `unblock` | rpc |

Les noms de colonnes JSON sont les `CodingKeys` des DTO (`snake_case`).

### Messages d'erreur que le client reconnaît

Le client lit le texte de l'exception du serveur (`CommunityError(serverMessage:)`) :

| Le message contient | Le client affiche |
|---|---|
| `event full` | « La sortie est complète. » |
| `event gone` | « Cette sortie n'est plus disponible. » |
| `blocked` | « Vous ne pouvez pas rejoindre cette sortie. » |
| `no profile` | l'écran de création de profil |
| `not allowed` | « Action non autorisée. » |
| autre | « Le serveur n'a pas répondu. Réessayez. » |

### Règles que les tests figent (à reprendre en pgTAP)

1. Sans profil valide, ou suspendu, ou sans déclaration d'âge : aucune lecture ni écriture.
2. Une zone ne voit que ses propres sorties ; une zone fermée ne voit rien.
3. Les participants ne sont jamais lisibles à plat : organisateur ou accepté seulement.
4. Dernière place : deux acceptations concurrentes, une seule passe ; capacité humaine et capacité
   canine sont deux contrôles.
5. Inscription et présence sont deux états ; la présence ne se déclare qu'après la fin de la sortie
   et seulement par un accepté.
6. Un blocage retire sorties et demandes dans les deux sens.
7. Seul un organisateur inscrit crée une sortie ; seul son organisateur décide, modifie, annule.
8. Un changement d'heure ou de lieu écrit une mise à jour que voient les inscrits.
9. Se retirer libère la place.
