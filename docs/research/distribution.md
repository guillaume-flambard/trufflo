# Mettre l'app dans des mains

Lu le 2026-10-07 : Apple, aide App Store Connect, « TestFlight overview »
(developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

## Ce qu'Apple dit

- **Testeurs internes** : jusqu'à 100, et **ce sont forcément des utilisateurs d'App Store
  Connect** ayant accès à votre contenu. Un participant extérieur n'en est donc pas un.
- **Testeurs externes** : jusqu'à 10 000. **Le premier build ajouté à un groupe externe passe en
  revue par Apple**, selon les App Review Guidelines. Les builds suivants n'exigent pas toujours une
  revue complète.
- **Un build reste testable 90 jours.**
- Le testeur installe l'app gratuite TestFlight, puis accepte une invitation par e-mail ou un lien
  public.
- **L'app n'a pas besoin d'être publiée** : une fiche d'app dans App Store Connect suffit.

## Ce que ça veut dire pour chaque étape

| Étape | Comment | Pourquoi |
|---|---|---|
| D-1, cinq séances en personne | **L'iPhone de Guillaume**, ou un iPhone prêté, avec le nom du chien de la personne saisi sur place | Aucune installation chez le participant, aucune revue Apple, aucune donnée du participant sur un appareil qui n'est pas le sien après la séance (on efface avec « Effacer toutes les données ») |
| D-2, une semaine chez deux ou trois foyers | **TestFlight externe** | Il faut que l'app reste sur leur téléphone pendant une semaine |
| D-3, sorties réelles | **TestFlight externe**, après revue | Même raison, plus le serveur communautaire et ses protections |

## Vérifié sur ce dépôt

| Point | État | Comment |
|---|---|---|
| Une version Release compile | Oui | `xcodebuild build -configuration Release` pour le simulateur, 2026-10-07 |
| Le code de démonstration n'est pas dans le binaire Release | Oui | 0 occurrence de `demo-community`, `demo-household`, `TRUFFLO_DEMO_PHOTO`, `InMemoryCommunityServer` dans l'exécutable |
| L'onglet Sorties est absent en Release | Oui | `CommunityBackend.isOpen` est faux, testé ; sans drapeau l'app a trois onglets |
| Le texte de la demande de position est exact | Oui, corrigé | Il disait que rien ne quitte l'appareil ; il dit maintenant que le parcours reste sur l'iPhone et que seules la durée et la distance sont partagées avec un foyer |
| Le schéma de données est versionné avec des migrations testées | Oui | `TruffloSchemas.swift`, `MigrationTests` (ARCHITECTURE.md exige cela avant un TestFlight externe) |
| Numéro de version | 1.0, build 1 | À incrémenter à chaque envoi |

## À vérifier avant d'envoyer un build (non vérifié ici)

- La **fiche d'app** existe-t-elle dans App Store Connect pour `dev.memolabs.trufflo` ? Je n'ai pas
  accès à ton compte.
- Les **informations de test** exigées pour un groupe externe (description, adresse de contact,
  éventuellement une adresse de politique de confidentialité) : à lire dans l'aide Apple avant de
  les rédiger. Je ne les ai pas lues.
- Un **manifeste de confidentialité** (`PrivacyInfo.xcprivacy`) : l'app n'en embarque pas. Apple
  demande d'en déclarer pour certains usages d'API (par exemple `UserDefaults`, que l'app utilise
  via `@AppStorage`). À confirmer dans la documentation Apple, **de mémoire seulement**.
- La clé **`ITSAppUsesNonExemptEncryption`** : absente de l'Info.plist. L'app n'utilise que HTTPS
  vers son propre serveur, mais la déclaration d'export se vérifie dans la documentation, pas de
  tête.
- **Un build d'archive signé** : jamais produit ici (seulement Debug et Release pour simulateur).
  Il demande ton compte développeur dans Xcode.

## Ce qui ne se fait pas sans toi

Créer la fiche d'app, archiver, envoyer à App Store Connect, inviter des testeurs : ce sont des
actions sur ton compte Apple et vis-à-vis de tiers, hors de ce que l'agent fait seul.
