# 0008. Synchronisation du foyer côté iPhone : client mince, synthèses, registre d'envoi

Statut : accepté le 2026-10-06, chantier 3. Complète l'ADR 0007 (serveur).

## Contexte

Le serveur du foyer tourne (`trufflo-api`, ADR 0007). L'iPhone doit s'y connecter avec Apple, partager les synthèses de la personne, recevoir celles des autres membres et ne jamais faire revenir ce qui a été supprimé. `DATA-CONTRACTS` fixe ce qui part (§5), les états de synchronisation (§3) et la règle des marqueurs de suppression (§8).

## Décisions

### Pas de SDK Supabase, un client mince

Le SDK officiel `supabase-swift` 2.55.3 existe et a été lu (`Package.swift` du tag). Il déclare dix paquets résolus au build, dont OpenTelemetry, secp256k1 et CryptoSwift. L'app n'utilise que quelques appels documentés : l'échange du jeton Apple et le rafraîchissement (GoTrue, `internal/api/token_oidc.go` et README), puis lectures, upserts et marqueurs (PostgREST). Le client est donc écrit sur URLSession : `Services/SupabaseRemote.swift` et `Services/AuthSession.swift`. À réévaluer si l'app a besoin de Realtime, de Storage ou des clés asymétriques.

### Connexion

Flux natif : Apple reçoit le SHA-256 hexadécimal d'un nonce aléatoire, GoTrue reçoit le nonce brut et compare (vérifié dans `token_oidc.go`). La session vit dans le trousseau, `AfterFirstUnlockThisDeviceOnly`. Le jeton est rafraîchi s'il expire dans moins de 60 s. Un refresh refusé efface la session ; un refresh impossible faute de réseau la garde.

### Ce qui part

Les DTO listent leurs champs un par un (`Domain/HouseholdDTO.swift`) : il n'existe pas de propriété « note » ou « latitude » à oublier. Un test encode les DTO et cherche ces mots. Une balade en cours ne part pas.

### Registre d'envoi plutôt qu'état sur la balade

Le schéma V6 n'ajoute que des tables : aucune classe du journal ne change, la V5 garde son identité. `SyncLedgerRecord` garde, par élément local, l'empreinte SHA-256 de ce qui a été envoyé. Même empreinte : aucun appel. Élément disparu localement : un marqueur part, une fois, puis l'entrée porte l'empreinte `deleted` et n'est jamais renvoyée vivante.

### Conflits

Le serveur est l'autorité. Une balade n'est écrite que par son auteur (et par un responsable, que l'app ne propose pas encore). La dernière écriture de l'auteur gagne ; l'état `conflict` n'est pas produit dans cette version. Conséquence acceptée : un renvoi après une réponse perdue fait avancer la révision serveur d'un cran de trop, le contenu reste juste.

### Réception

Les balades des autres arrivent dans `SharedWalkRecord`, en lecture seule, sans tracé ni note. Le curseur est le plus grand `updated_at` reçu, avec 60 s de recouvrement contre les horloges qui divergent. PostgREST plafonne une lecture à 1 000 lignes ; triées par `updated_at`, les suivantes arrivent à la synchronisation d'après.

### Chiens

En rejoignant un foyer, la personne dit pour chaque chien local s'il est déjà un chien du foyer ou s'il y entre. Rien n'est relié par ressemblance de nom. Un chien créé après l'entrée entre comme lui-même. Seuls les chiens apportés par la personne sont envoyés ; un chien relié à celui d'un autre n'écrase pas sa fiche.

### Doublons

Une balade d'un autre membre qui chevauche une des miennes pour un même chien est signalée « peut-être la même sortie », jamais fusionnée (`Domain/SharedJournal.swift`).

### Révocation, départ, effacement

Si le serveur ne montre plus le foyer, l'iPhone oublie tout ce qu'il a reçu et garde le journal propre de la personne. Se déconnecter fait de même. L'effacement global efface aussi les tables du foyer et la session, mais rien côté serveur, et l'écran le dit.

### Reprise après réinstallation ou déconnexion

Le serveur dit à quel foyer la personne appartient (`households` sous RLS). L'app propose « Reprendre ce foyer », qui repasse par l'étape des chiens. Les synthèses de ses propres balades que cet iPhone n'a plus reviennent en lecture seule ; une balade supprimée ici dont le marqueur n'est pas encore parti ne revient pas, le registre l'en empêche.

### Moments de synchronisation

À l'ouverture, au retour au premier plan, à l'ouverture de l'écran du foyer et à la demande. Pas de tâche d'arrière-plan dans cette version.

### Langue

`developmentRegion` passe à `fr` : l'app n'existe qu'en français, et les composants système (bouton Se connecter avec Apple) s'affichaient en anglais.

## Vérifié

- 16 tests unitaires de synchronisation contre un serveur en mémoire qui applique les mêmes règles que la base (RLS, révision, marqueurs, dernier responsable), et 8 sur la session, le nonce et la forme des requêtes.
- Parcours à deux comptes en vrai HTTP contre le Supabase local (`tools/backend/household-integration.sh`) : création, invitation, rapprochement des chiens, échange, correction, suppression sans résurrection, reprise sur un iPhone vide, départ.
- Migration V5 vers V6 testée sur un store écrit en V5, et ouverture réelle d'un store existant sur simulateur.

## Ouvert

1. Connexion Apple sur un vrai compte : demande la capacité Sign in with Apple sur l'App ID `dev.memolabs.trufflo` (compte développeur de Guillaume).
2. Migration serveur `member_profiles` à appliquer en production.
3. Changer le rôle d'un membre ou le retirer depuis l'app ; lien d'invitation cliquable.
4. Synchronisation en arrière-plan.
5. La phrase d'introduction « Tout reste sur cet iPhone » reste vraie tant que la personne ne rejoint pas de foyer ; sa formulation est à trancher par Guillaume.
