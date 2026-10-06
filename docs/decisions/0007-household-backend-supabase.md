# 0007. Le foyer partagé (M2) sur Supabase, synthèses seulement

Statut : accepté le 2026-10-06. Schéma et règles d'accès construits et testés en local. Hébergement : Supabase auto-hébergé sur le VPS du lab. Connexion : « Se connecter avec Apple ». Choix de Guillaume le 2026-10-06.

## Contexte

M2 (PRD F08) partage le journal entre les membres d'un foyer. ADR-007 annonçait PostgreSQL avec une authentification compatible, Supabase à évaluer. `DATA-CONTRACTS` fixe ce qui part et ce qui reste : les synthèses partent, les tracés précis et la note privée restent sur l'iPhone, le serveur est l'autorité des droits.

## Décision

Un projet Supabase dans `backend/supabase`, schéma par migrations (`supabase/migrations`), droits par RLS, tests pgTAP (`supabase/tests`).

Tables : `households`, `household_members` (rôle `owner`, `contributor`, `reader`), `household_invites` (jeton à usage unique, 7 jours), `dogs`, `walks`, `walk_dogs`.

Ce que le serveur ne reçoit jamais, et que les tests vérifient : coordonnées, table de tracé, note de balade, photo du chien. Une balade déclarée ne porte pas de distance (contrainte en base).

Règles d'accès, toutes testées en jouant la personne concernée :

| Action | Responsable | Contributeur | Lecteur | Étranger |
|---|---|---|---|---|
| Lire le foyer, les chiens, les balades | oui | oui | oui | non |
| Ajouter une balade (à son nom seulement) | oui | oui | non | non |
| Corriger sa balade | oui | oui | non | non |
| Corriger la balade d'un autre | oui | non | non | non |
| Inviter, lire les invitations, retirer un membre | oui | non | non | non |
| Quitter le foyer | oui, sauf dernier responsable | oui | oui | sans objet |

Un membre retiré ne lit plus rien dès le retrait.

Créer un foyer se fait sans relire la ligne dans la même requête (PostgREST `return=minimal`, pas de `.select()` côté client), avec un UUID choisi par l'app. Le responsable est inscrit par un trigger après l'insertion et le `RETURNING` est filtré avant : la relecture répond 403. Un test le fige. Une balade garde son auteur et son foyer ; chaque correction avance la révision. Les suppressions de chiens et de balades sont des marqueurs (`deleted_at`) pour qu'un élément supprimé ne revienne pas par une synchronisation.

Exposition à l'API : depuis octobre 2026, une table n'est plus exposée par défaut (changelog Supabase, « Tables not exposed to Data and GraphQL API automatically »). Les droits sont donc accordés explicitement au seul rôle `authenticated`, rien pour `anon`. Le code privilégié (appartenance, acceptation d'invitation) vit dans le schéma non exposé `private` ; la seule fonction appelable est une enveloppe `security invoker`.

## Vérifié

- `supabase db advisors --local` : aucune alerte (sécurité et performance).
- `supabase test db --local` : 26 contrôles, tous verts.
- Postgres 17, CLI Supabase 2.119.0, le 2026-10-06.

## Ouvert

1. **Déploiement sur le VPS** : stack `trufflo-api` écrite dans `lab-infra` (branche `trufflo-api`, commit `85fcbd3`), testée en local de bout en bout, pas encore fusionnée ni déployée. Procédure dans `stacks/trufflo-api/README.md` de ce dépôt-là. Adresse prévue : `https://trufflo-api.memolabs.dev`.
2. **Se connecter avec Apple** : en flux natif (jeton d'identité), il suffit que l'identifiant de l'app `dev.memolabs.trufflo` figure dans les Client IDs ; ni Services ID, ni clé `.p8`, ni rotation (documentation Supabase, « Login with Apple », lue le 2026-10-06). Reste à activer la capacité Sign in with Apple sur l'App ID, dans le compte développeur de Guillaume.
3. **Synchronisation côté iPhone** : non écrite. Elle demandera un état de synchronisation local (`localOnly`, `pending`, `synced`, `conflict`, `failed`, voir `DATA-CONTRACTS` §3) et des opérations idempotentes.
4. **Rapprochement des chiens** : deux personnes qui créent chacune « Oslo » en local produiront deux chiens. Le rattachement à un chien existant du foyer est à concevoir avant la synchro.
