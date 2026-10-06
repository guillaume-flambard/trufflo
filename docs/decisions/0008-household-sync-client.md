# 0008. Synchronisation du foyer côté iPhone : client mince, synthèses, registre d'envoi

Statut : accepté le 2026-10-06, chantier 3. Complète l'ADR 0007 (serveur).

## Contexte

Le serveur du foyer tourne (`trufflo-api`, ADR 0007). L'iPhone doit s'y connecter avec Apple, partager les synthèses de la personne, recevoir celles des autres membres et ne jamais faire revenir ce qui a été supprimé. `DATA-CONTRACTS` fixe ce qui part (§5), les états de synchronisation (§3) et la règle des marqueurs de suppression (§8).

## Décisions

### Le SDK officiel, épinglé

D'abord écrit à la main sur URLSession, le client passe le soir même au SDK officiel `supabase-swift` 2.55.3 (produit `Supabase`), à la demande de Guillaume. Version exacte dans le projet, `Package.resolved` commité : 8 paquets résolus. Le client est dans `Services/SupabaseRemote.swift`, derrière le protocole `HouseholdRemote` : le moteur de synchronisation et ses tests n'ont pas changé.

Deux réglages du SDK sont corrigés, lus dans son source au tag 2.55.3 :
- `upsert`, `update` et `delete` renvoient la ligne par défaut (`returning: .representation`). Chaque écriture passe `.minimal`, sinon la création d'un foyer retombe dans le piège du `RETURNING` (ADR 0007).
- Son trousseau utilise `kSecAttrAccessibleAfterFirstUnlock`, qui laisse la session voyager avec une sauvegarde chiffrée vers un autre appareil. `DeviceOnlyKeychainStorage` la garde sur cet appareil seulement.

Les erreurs de PostgREST arrivent avec un code SQLSTATE et sans statut HTTP : `42501` devient « refusé pour votre rôle », `PGRST30x` « session expirée ».

### Temps réel

L'app s'abonne aux changements de `walks` du foyer (Realtime, `postgres_changes`) tant qu'elle est au premier plan. L'événement ne sert que de sonnette : il déclenche la synchronisation habituelle, sous les mêmes règles. Un événement manqué coûte un délai, jamais un journal faux. Realtime applique la RLS sauf aux `DELETE` ; les balades ne sont jamais supprimées, seulement marquées, et le rôle n'a plus le droit `DELETE` (test pgTAP). Mesuré : sur un serveur froid, la première souscription crée le slot de réplication et un changement écrit pendant ce temps ne sonne pas ; le test d'intégration réécrit jusqu'à être entendu.

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

À l'ouverture, au retour au premier plan, à l'ouverture de l'écran du foyer, à la demande, et à chaque événement temps réel. Pas de tâche d'arrière-plan dans cette version.

### Langue

`developmentRegion` passe à `fr` : l'app n'existe qu'en français, et les composants système (bouton Se connecter avec Apple) s'affichaient en anglais.

## Vérifié

- 16 tests unitaires de synchronisation contre un serveur en mémoire qui applique les mêmes règles que la base (RLS, révision, marqueurs, dernier responsable), et 4 sur le nonce, le trousseau et la traduction des erreurs du SDK.
- Via le SDK, en vrai HTTP, contre le Supabase local (`tools/backend/household-integration.sh`) et contre la stack auto-hébergée complète lancée en local : temps réel (un membre est prévenu, un étranger abonné au même filtre n'entend rien), et parcours à deux comptes : création, invitation, rapprochement des chiens, échange, correction, suppression sans résurrection, reprise sur un iPhone vide, départ.
- Migration V5 vers V6 testée sur un store écrit en V5, et ouverture réelle d'un store existant sur simulateur.

## Ouvert

1. Connexion Apple sur un vrai compte : demande la capacité Sign in with Apple sur l'App ID `dev.memolabs.trufflo` (compte développeur de Guillaume).
2. Migrations `member_profiles`, `realtime_walks` et `tighten_grants` à appliquer en production, avec la stack complète (lab-infra, branche `trufflo-api-full`).
3. Changer le rôle d'un membre ou le retirer depuis l'app ; lien d'invitation cliquable.
4. Synchronisation en arrière-plan.
5. La phrase d'introduction « Tout reste sur cet iPhone » reste vraie tant que la personne ne rejoint pas de foyer ; sa formulation est à trancher par Guillaume.
