# 0009 : l'invitation au foyer passe par un lien universel

Statut : accepté le 2026-10-07 (choix de Guillaume, lot B, B-REQ-02).

## Contexte

Une invitation était un code de 32 caractères à recopier. La spec du lot B demande qu'un proche
rejoigne depuis un lien, sans qu'on lui dicte quoi que ce soit, et qu'un lien ouvert sans l'app
mène à une explication.

Sources lues le 2026-10-07 (pages JSON de developer.apple.com, la documentation livrée avec
Xcode 27.0 ne couvre pas le sujet) :

- « Supporting associated domains » : fichier `apple-app-site-association` sans extension, à
  `https://<domaine>/.well-known/apple-app-site-association`, certificat valide, **aucune
  redirection** ; `appIDs` au format `<Application Identifier Prefix>.<Bundle Identifier>` ;
  entitlement `applinks:<domaine>`, sans chemin ni barre finale. Depuis iOS 14 les appareils
  lisent ce fichier par un CDN d'Apple, qui le récupère dans les 24 heures ; les appareils
  vérifient les mises à jour environ une fois par semaine.
- « Supporting universal links in your app » : un lien universel est un point d'entrée que
  n'importe qui peut fabriquer, valider chaque paramètre et rejeter le reste.
- `View.onOpenURL(perform:)` : SwiftUI remet un lien universel directement sous forme d'URL.

## Décision

1. Le lien est `https://trufflo.memolabs.dev/rejoindre/<code>`. Il ne porte que le code que le
   serveur émet déjà ; l'acceptation passe toujours par `accept_household_invite`, qui vérifie
   validité, usage unique et expiration.
2. `trufflo.memolabs.dev` est servi par la stack `trufflo-links` de `lab-infra` (branche
   `trufflo-links`) : un nginx statique sur le modèle de `stacks/legal`, qui sert le fichier
   d'association et une page de repli. Le DNS joker `*.memolabs.dev` couvre déjà l'hôte.
3. L'app lit le lien dans `InviteLink.code(in:)` : https, hôte exact, chemin `/rejoindre/`, code
   de 32 caractères hexadécimaux, ni requête ni fragment. Tout autre lien est ignoré.
4. Le message de partage contient le lien et, en dessous, le code, pour qui préfère le saisir.
5. Un lien reçu sans session attend la connexion ; reçu dans un foyer, il est écarté avec une
   phrase (un seul foyer par iPhone).

Écarté : un schéma `trufflo://`. Il ne demande aucun serveur, mais un lien ouvert sans l'app ne
mène nulle part, et certaines apps ne le rendent pas cliquable.

## Ce qui reste hors de l'agent

- Déployer `trufflo-links` sur le VPS (écriture en production).
- Vérifier dans Xcode que la capacité Associated Domains apparaît dans Signing & Capabilities
  pour la cible `trufflo`, et donc sur l'App ID, comme pour Sign in with Apple.
- Vérifier sur le portail développeur que le préfixe d'identifiant de l'app est bien
  `Q52VN4UT34` (l'identifiant d'équipe). C'est le cas courant, pas une certitude : un préfixe
  différent rend le fichier d'association muet.

## Conséquences

- Le lien ne fonctionne qu'après publication du fichier et sa lecture par le CDN d'Apple, donc
  jusqu'à 24 heures après le déploiement. Avant, iOS ouvre la page de repli dans Safari, ce qui
  reste correct.
- Tant que l'app n'est pas sur l'App Store, la page de repli ne peut pas proposer de lien
  d'installation : elle renvoie vers la personne qui invite.
- La preuve finale (B-AC-02) se fait sur deux appareils réels, avec le lot B-REQ-01.
