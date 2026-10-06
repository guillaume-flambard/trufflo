# Documentation

Ce dossier rassemble les documents de référence du pack natif, scindés depuis
`TRUFFLO-NATIVE-STARTER-ALL.md` (version 0.2, 4 octobre 2026), plus deux
documents vivants écrits pour ce dépôt.

## Canon

| Document | Statut |
|---|---|
| [`../PRD.md`](../PRD.md) | Canon du produit. Source unique : le doublon `trufflo/PRD.md` a été supprimé. |
| [`../AGENTS.md`](../AGENTS.md) | Canon technique de l'agent : build, tests, parcours, conventions. |
| [`ASSET-NEEDS.md`](ASSET-NEEDS.md) | Canon des actifs : inventaire réel et manques constatés. |
| Ce dossier | Référence. Ce qui tourne dans le binaire l'emporte sur ce qui est décrit ici. |

Les deux documents du pack qui portent les mêmes noms, `PRD.md` et `AGENTS.md`,
ne sont pas dupliqués ici : la racine a gagné. `README.md` du pack décrivait
l'installation du starter et est obsolète depuis l'intégration.

## Documents de référence

| Document | Contenu |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Couches, découpage, décisions structurantes. |
| [DATA-CONTRACTS.md](DATA-CONTRACTS.md) | Modèles, invariants, contrat d'échange sans dépendre des identifiants SwiftData. |
| [LOCATION-ENGINE.md](LOCATION-ENGINE.md) | Moteur de balade, états GPS, reprise. Base du chantier 2. |
| [PRIVACY-AND-SAFETY.md](PRIVACY-AND-SAFETY.md) | Confidentialité, permissions, sauvegardes. |
| [DESIGN-SYSTEM.md](DESIGN-SYSTEM.md) | Design, UX, mouvement. |
| [BACKLOG.md](BACKLOG.md) | Backlog et portes de livraison. Référencé par le PRD section 10. |
| [TEST-PLAN.md](TEST-PLAN.md) | Plan de test et définition de terminé. Référencé par le PRD section 10. |
| [VERIFICATION.md](VERIFICATION.md) | Critères de vérification. |
| [SOURCES.md](SOURCES.md) | Sources citées par le PRD, notation `[Snn]`. |
| [XCODE-SETUP.md](XCODE-SETUP.md) | Configuration Xcode d'origine. |
| [KICKOFF-PROMPT.md](KICKOFF-PROMPT.md) | Prompt de démarrage d'origine. Preuve de provenance. |
| [specs/README.md](specs/README.md) | Specs de livraison des lots A à D, et le registre des décisions. |
| [decisions/](decisions/) | ADR : les décisions techniques et leurs sources. |
| [research/README.md](research/README.md) | Tests d'usage (lot D) : guide de séance, grille, recrutement, installation. Les notes de séance, elles, vivent hors de ce dépôt public. |

## Archive

| Document | Pourquoi il est archivé |
|---|---|
| [archive/STARTER-CODE.md](archive/STARTER-CODE.md) | Code du starter tel que livré. Non maintenu : les sources vivantes sont dans `trufflo/`. Elles ont divergé. |

## Ce que ce dossier ne contient pas

- Aucun fichier exécutable. Le code est dans `trufflo/`.
- Aucun `Assets.xcassets`. Les actifs sont décrits, pas dupliqués.
- Aucune décision produit. Le PRD tranche.
