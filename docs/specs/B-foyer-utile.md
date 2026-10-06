# Lot B : un foyer réellement utile

Exigences du PRD couvertes : F08 (foyer partagé), F13 (confidentialité), F14 (qualité).
Base technique : ADR 0007 (serveur) et ADR 0008 (client), dont ce lot ferme les points ouverts 1 et 3.

## Objectif

Un proche installe Trufflo, rejoint le foyer depuis un lien sans qu'on lui dicte quoi que ce soit,
reconnaît le chien partagé, et voit sur Aujourd'hui la dernière sortie enregistrée par les autres.
Le responsable peut changer un rôle ou retirer quelqu'un depuis l'app.

Le lot est fini quand B-AC-01 à B-AC-12 ont une preuve, dont B-AC-01 et B-AC-02 sur deux appareils
réels avec deux comptes Apple distincts.

## 1. État de départ vérifié

| Constat | Où | Vérifié |
|---|---|---|
| Connexion Apple, création, rejoindre par code, rapprochement des chiens, journal partagé, temps réel : en place, testés en HTTP réel contre Supabase local. | ADR 0008, E-304, E-312 | Oui (documenté) |
| Capacité Sign in with Apple active sur l'App ID ; GoTrue Apple activé en prod avec `dev.memolabs.trufflo`. | Xcode, conteneur `trufflo-auth` | Oui, 2026-10-06 |
| Migrations `member_profiles`, `realtime_walks`, `tighten_grants` en prod, droits conformes à `grants_test.sql`. | E-318 | Oui, 2026-10-06 |
| L'invitation est un code partagé par texte : aucun lien, aucun domaine associé, aucun `onOpenURL`. | `HouseholdView.swift:737`, entitlements | Oui |
| Le serveur sait les rôles (responsable, contributeur, lecteur), la révocation et « toujours un responsable ». L'app ne propose ni changement de rôle ni retrait. | migration `household_sharing`, ADR 0008 point 3 | Oui |
| Aujourd'hui ne compte que les balades locales ; le Journal montre aussi celles du foyer. | `StarterRootView.swift` (`weekSection`, `completedWalks`) | Oui |
| Le chemin vers le foyer est Aujourd'hui, Réglages, Foyer partagé. Rien ne le propose ailleurs. | `StarterRootView.swift` | Oui |

## 2. Exigences

**B-REQ-01, connexion réelle prouvée.** La connexion Apple aboutit sur un appareil réel avec un vrai
compte, et une session survit à la relance de l'app (ADR 0008 point ouvert 1).

**B-REQ-02, invitation par lien.** Créer une invitation produit un lien. Ouvert sur un iPhone où
Trufflo est installé, il ouvre l'écran « Rejoindre » pré-rempli. Le code reste affiché comme
solution de repli. Pas installé : le lien mène à une page qui explique quoi faire (installation
puis code). Mécanisme technique (lien universel avec domaine associé, ou schéma d'URL) : à choisir
après lecture de la doc Apple de la version installée, et à écrire dans un ADR.

**B-REQ-03, rapprochement sans devinette.** À l'arrivée dans un foyer, chaque chien local est relié
à un chien du foyer par un choix explicite de la personne, ou ajouté comme nouveau chien. Jamais
par simple égalité de nom.

**B-REQ-04, la dernière contribution du foyer sur Aujourd'hui.** Si le foyer a une balade plus
récente que la mienne, Aujourd'hui l'affiche dans un bloc à part : qui, quel chien, quand, durée.
Les chiffres de la semaine restent les miens et le disent (décision D2). Deux enregistrements de la
même sortie ne sont jamais additionnés.

**B-REQ-05, gérer les membres.** Le responsable change le rôle d'un membre et le retire. Un membre
quitte le foyer. Le dernier responsable ne peut ni partir ni être rétrogradé ; l'app l'explique au
lieu de laisser le serveur refuser en silence.

**B-REQ-06, révocation visible.** Un membre retiré ne lit plus rien de nouveau. Au prochain contact
avec le serveur, son iPhone purge les copies du foyer et l'écrit à l'écran (PRD F08).

**B-REQ-07, découvrir le foyer au bon moment.** Après la première balade enregistrée, et depuis le
Profil du chien, une invitation discrète : « Vous êtes plusieurs à promener Oslo ? Partager son
journal ». Une seule fois par emplacement si elle est écartée.

**B-REQ-08, rien de privé ne part.** Ni note, ni tracé, ni position n'est ajouté aux données
partagées par ce lot (ADR 0008, AC-02 du chantier 3).

## 3. Critères d'acceptation

| ID | Exigence | Étant donné | Quand | Alors | Preuve |
|---|---|---|---|---|---|
| B-AC-01 | REQ-01 | un iPhone réel, un compte Apple | on se connecte puis on relance l'app | la session est toujours là | appareil réel |
| B-AC-02 | REQ-02, 03 | deux appareils, deux comptes Apple distincts | A invite, B ouvre le lien | B arrive sur « Rejoindre » pré-rempli, rejoint, relie Oslo par un choix | appareil réel (iPhone + simulateur ou deux iPhones) |
| B-AC-03 | REQ-02 | Trufflo absent | on ouvre le lien | une page explique l'installation et le code | navigateur |
| B-AC-04 | REQ-02 | un lien expiré ou révoqué | on l'ouvre | l'app dit pourquoi il ne marche plus, rien n'est créé | intégration + parcours UI |
| B-AC-05 | REQ-03 | un chien local « Oslo » et un chien du foyer « Oslo » | on rejoint | rien n'est relié tant que la personne n'a pas choisi | unitaire |
| B-AC-06 | REQ-04 | Bruno a enregistré une balade après la mienne | on ouvre Aujourd'hui | le bloc « Dernière sortie du foyer » montre Bruno, le chien, l'heure, la durée | capture (mode démo) + unitaire |
| B-AC-07 | REQ-04 | une balade de Bruno marquée doublon de la mienne | on ouvre Aujourd'hui | les chiffres de la semaine ne la comptent pas | unitaire |
| B-AC-08 | REQ-05 | un responsable et un contributeur | le responsable passe le contributeur en lecteur | le lecteur ne peut plus écrire de balade | intégration HTTP |
| B-AC-09 | REQ-05 | un seul responsable | il essaie de partir | l'app explique qu'il faut d'abord nommer un autre responsable ou supprimer le foyer | parcours UI |
| B-AC-10 | REQ-06 | un membre retiré, hors ligne | il revient en ligne | les balades du foyer disparaissent de son journal, un message le dit | intégration + capture |
| B-AC-11 | REQ-07 | une première balade terminée, pas de foyer | on revient sur Aujourd'hui | l'invitation au foyer est visible ; écartée, elle ne revient pas | parcours UI |
| B-AC-12 | REQ-08 | le corps des requêtes d'envoi | on inspecte le JSON | aucun champ note, tracé ou position | unitaire (existant, étendu) |

## 4. Ordre de travail

1. B-REQ-01 : la recette réelle, dès qu'un second compte Apple est disponible (S19 du chantier 3).
2. B-REQ-05 et B-REQ-06 : le serveur sait déjà faire, il manque l'interface.
3. B-REQ-02 : ADR sur le mécanisme de lien, puis implémentation.
4. B-REQ-04 : dès que D2 est tranchée.
5. B-REQ-07 en dernier.

## 5. Hors périmètre

- Synchronisation en arrière-plan (ADR 0008 point 4) : la synchro à l'ouverture, au retour au
  premier plan et en temps réel suffit pour ce lot.
- Partage des tracés ou des notes.
- Notifications push.
- Android.

## 6. Décisions dont dépend ce lot

D2 (périmètre d'Aujourd'hui), D7 (qui fait la tranche serveur).
