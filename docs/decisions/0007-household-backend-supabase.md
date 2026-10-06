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

Un membre retiré ne lit plus rien dès le retrait. Une balade garde son auteur et son foyer ; chaque correction avance la révision. Les suppressions de chiens et de balades sont des marqueurs (`deleted_at`) pour qu'un élément supprimé ne revienne pas par une synchronisation.

Exposition à l'API : depuis octobre 2026, une table n'est plus exposée par défaut (changelog Supabase, « Tables not exposed to Data and GraphQL API automatically »). Les droits sont donc accordés explicitement au seul rôle `authenticated`, rien pour `anon`. Le code privilégié (appartenance, acceptation d'invitation) vit dans le schéma non exposé `private` ; la seule fonction appelable est une enveloppe `security invoker`.

## Vérifié

- `supabase db advisors --local` : aucune alerte (sécurité et performance).
- `supabase test db --local` : 25 contrôles, tous verts.
- Postgres 17, CLI Supabase 2.119.0, le 2026-10-06.

## Ouvert

1. **Déploiement sur le VPS** : à faire dans `lab-infra`, selon ses conventions (stack, sauvegarde, mise à jour). Supabase auto-hébergé est une douzaine de conteneurs ; depuis juillet 2026 sa passerelle par défaut est Envoy et non plus Kong (changelog Supabase).
2. **Se connecter avec Apple** : demande un identifiant de service et une clé dans le compte développeur Apple, à créer par Guillaume, puis leur report dans la configuration d'authentification.
3. **Synchronisation côté iPhone** : non écrite. Elle demandera un état de synchronisation local (`localOnly`, `pending`, `synced`, `conflict`, `failed`, voir `DATA-CONTRACTS` §3) et des opérations idempotentes.
4. **Rapprochement des chiens** : deux personnes qui créent chacune « Oslo » en local produiront deux chiens. Le rattachement à un chien existant du foyer est à concevoir avant la synchro.
