# Recette du foyer sur deux iPhone

Couvre B-AC-01, B-AC-02, B-AC-03, B-AC-04, B-AC-05, B-AC-06, B-AC-07, B-AC-08, B-AC-09 et B-AC-10
de `B-foyer-utile.md`, ainsi que S19 (AC-22) du chantier 3. C'est la seule preuve de bout en bout de la
connexion Apple et du lien d'invitation : le reste est prouvé par des tests et du HTTP réel sur un
Supabase local.

Durée : environ 45 minutes. Deux personnes, deux iPhone, deux comptes Apple différents.
Dans ce document, **G** est Guillaume (le responsable du foyer) et **N** est Natha.

## 0. Avant de commencer

| Prérequis | Pourquoi | Fait |
|---|---|---|
| Les deux iPhone sont sous **iOS 27 ou plus** | `IPHONEOS_DEPLOYMENT_TARGET = 27.0` : l'app ne s'installe pas en dessous | ☐ |
| Deux comptes Apple **différents** connectés sur les deux iPhone | Avec le même compte, le serveur voit un seul membre : il n'y a pas de foyer à deux | ☐ |
| Le mode développeur est activé sur les deux iPhone (Réglages, Confidentialité et sécurité, Mode développeur) | Sans lui, Xcode n'installe pas l'app | ☐ |
| L'iPhone de N est branché sur le Mac de G et Xcode le voit (Window, Devices and Simulators) | Il rejoint l'équipe de développement de G : c'est la voie la plus simple, N n'a rien à configurer sur son Mac | ☐ |
| La même version de l'app sur les deux iPhone, **commit noté ici** : ______ | Sinon une différence de version se fait passer pour un défaut | ☐ |
| Les deux iPhone ont du réseau (Wi-Fi ou 4G) | La synchro passe par `trufflo-api.memolabs.dev` | ☐ |
| `https://trufflo.memolabs.dev/health` répond `ok` (déployé le 2026-10-07) | Le lien d'invitation | ☐ |

Installer : dans Xcode, choisir l'iPhone comme destination, puis Run. Sur l'iPhone de N, il faudra
peut-être faire confiance au développeur (Réglages, Général, Gestion des appareils) : à confirmer dans
la documentation Apple, **de mémoire seulement**.

**Installer l'app APRÈS le déploiement du lien** : iOS lit le fichier d'association au moment de
l'installation. Une app installée avant n'ouvre pas encore le lien.

## 1. Connexion Apple (B-AC-01)

| # | Qui | Geste | Résultat attendu | OK |
|---|---|---|---|---|
| 1.1 | G | Aujourd'hui, l'engrenage en haut à droite, **Foyer partagé** | Un écran forêt « Un journal, plusieurs promeneurs. » avec le bouton Sign in with Apple | ☐ |
| 1.2 | G | Toucher le bouton, valider avec Face ID | Retour sur « Créer ou rejoindre. » avec deux cartes : **Créer un foyer** et **J'ai un code** | ☐ |
| 1.3 | G | Fermer l'app complètement (balayer), la rouvrir, rouvrir Foyer partagé | La session est conservée : **pas** de nouvelle demande de connexion | ☐ |
| 1.4 | N | Même chose sur son iPhone, avec son compte | Même résultat | ☐ |

## 2. Créer le foyer et inviter

| # | Qui | Geste | Résultat attendu | OK |
|---|---|---|---|---|
| 2.1 | G | **Créer un foyer**, saisir son prénom et un nom de foyer, **Créer et partager mon journal** | L'écran du foyer s'ouvre, G est « Responsable » | ☐ |
| 2.2 | G | Dans « Inviter quelqu'un », laisser **Contributeur**, **Créer un code d'invitation** | Un code de 32 caractères s'affiche en groupes de quatre | ☐ |
| 2.3 | G | Toucher **Envoyer**, envoyer à N par Messages | Le message contient un lien `https://trufflo.memolabs.dev/rejoindre/…` **et**, en dessous, le code | ☐ |
| 2.4 | G | Ouvrir ce lien dans **Safari sur le Mac** (B-AC-03) | Une page « Vous êtes invité dans un foyer Trufflo », qui explique quoi faire et **affiche le code** | ☐ |

Un code ne sert qu'une fois : les essais de la section 3 sont dans l'ordre voulu, **le vrai code est
consommé à l'étape 3.3**.

## 3. Rejoindre par le lien (B-AC-02, B-AC-04)

| # | Qui | Geste | Résultat attendu | OK |
|---|---|---|---|---|
| 3.1 | G | Créer un **code factice** : copier le lien, changer le **dernier caractère** (par exemple `…cdef` devient `…cdee`), l'envoyer à N | Un lien qui a la bonne forme mais que le serveur ne connaît pas | ☐ |
| 3.2 | N | Toucher ce lien factice dans **Messages**, puis **Continuer** | L'app s'ouvre sur « Rejoindre » avec ce code, puis un message dit que le code n'est pas valable. **Rien n'est rejoint**. C'est le remplaçant testable d'un lien expiré ou révoqué (un vrai code expire après sept jours) | ☐ |
| 3.3 | N | Toucher le **vrai** lien dans Messages (pas dans Safari en tapant l'adresse) | **Trufflo s'ouvre** sur « Rejoindre », le code déjà rempli. Passer à la section 4, puis revenir à 3.5 | ☐ |
| 3.4 | N | Si 3.3 ouvre **Safari** au lieu de l'app : **résultat acceptable le premier jour**. Noter l'heure. Rejoindre avec le code : Foyer partagé, **J'ai un code**, coller le code | Le code fonctionne dans tous les cas. Réessayer le lien 6 heures puis 24 heures plus tard | ☐ |
| 3.5 | N | Une fois dans le foyer, toucher à nouveau un lien d'invitation | Un message dit que l'iPhone fait déjà partie d'un foyer. Rien n'est créé | ☐ |

Les étapes 3.2 et 3.5 décrivent le comportement écrit dans le code (`InviteLink`, `applyPendingInvite`)
et testé en unitaire : elles n'ont jamais été vues sur un iPhone. Un écran différent est une information.

## 4. Rapprochement des chiens (B-AC-05)

À préparer avant la section 2 : G et N ont chacun un chien nommé **Oslo** dans l'app, vrai chien ou non.
Cette étape se joue **entre le code collé et la fin de la jointure** (3.3 ou 3.4).

| # | Qui | Geste | Résultat attendu | OK |
|---|---|---|---|---|
| 4.1 | N | Sur « Qui est qui ? », regarder l'état proposé pour son Oslo | **Rien n'est relié d'office** : « Nouveau dans le foyer » est choisi, malgré le nom identique | ☐ |
| 4.2 | N | Choisir **C'est Oslo** (le chien de G), puis **Rejoindre « … »** | N est dans le foyer, son Oslo est relié à celui de G | ☐ |

## 5. Synchro et confidentialité (B-AC-04, B-AC-07, B-AC-12)

| # | Qui | Geste | Résultat attendu | OK |
|---|---|---|---|---|
| 5.1 | G | Enregistrer une balade manuelle de 20 minutes avec Oslo, **avec une note privée** (« note secrète G ») | Elle apparaît dans le Journal de G | ☐ |
| 5.2 | N | Sans relancer l'app, regarder le Journal de N, dans les 30 secondes | La balade de G apparaît, marquée « par … », en lecture seule | ☐ |
| 5.3 | N | Ouvrir cette balade | Elle montre la durée et le chien. **Aucune note, aucun tracé, aucune carte** | ☐ |
| 5.4 | N | Enregistrer une balade de 30 minutes, avec une note (« note secrète N ») | Elle apparaît chez N | ☐ |
| 5.5 | G | Regarder son Journal | Celle de N apparaît, sans la note | ☐ |
| 5.6 | G + N | Chacun enregistre **la même sortie** (même heure, avec l'Oslo relié en 4.2) | Une ligne dit « Peut-être la même sortie qu'une des vôtres ». Les chiffres de la semaine ne comptent pas la balade de l'autre | ☐ |
| 5.7 | N | Mode avion, enregistrer une balade, puis couper le mode avion | Elle part vers G à la reconnexion, sans doublon | ☐ |

## 6. Aujourd'hui (B-AC-06, B-AC-07)

| # | Qui | Geste | Résultat attendu | OK |
|---|---|---|---|---|
| 6.1 | G | N enregistre une balade **après** la dernière de G. Ouvrir Aujourd'hui | Un bloc « Dernière sortie du foyer » montre N, le chien, l'heure, la durée | ☐ |
| 6.2 | G | Lire la phrase en haut | « Vous avez enregistré N balades cette semaine » ne compte que les balades de G | ☐ |

## 7. Gérer les membres (B-AC-08, B-AC-09, B-AC-10)

| # | Qui | Geste | Résultat attendu | OK |
|---|---|---|---|---|
| 7.1 | G | Dans « Membres », toucher la ligne de N, **Passer lecteur** | Le badge de N devient « Lecteur » | ☐ |
| 7.2 | N | Enregistrer une balade | **Elle n'arrive pas chez G** (un lecteur n'envoie rien) | ☐ |
| 7.3 | G | Regarder le bas de l'écran du foyer, seul responsable avec N dedans | « Vous êtes le seul responsable. Pour quitter le foyer, nommez d'abord un autre responsable » à la place de « Quitter » | ☐ |
| 7.4 | G | **Retirer du foyer** pour N, confirmer | N disparaît de la liste des membres | ☐ |
| 7.5 | N | Ouvrir l'app, puis le Journal | Un message « Vous ne faites plus partie de « … » ». Les balades de G ont disparu. **Les balades de N sont intactes** | ☐ |

## 8. Reprise et sortie (optionnel)

| # | Qui | Geste | Résultat attendu | OK |
|---|---|---|---|---|
| 8.1 | G | Créer un nouveau code, l'envoyer à N | Un code frais (le précédent est consommé) | ☐ |
| 8.2 | N | Rejoindre avec ce code, en reliant Oslo | N est de retour dans le foyer | ☐ |
| 8.3 | N | **Supprimer l'app** de son iPhone, la **réinstaller** depuis Xcode, rouvrir Foyer partagé (se reconnecter avec Apple si c'est demandé) | La carte **Reprendre « … »** est proposée : N retrouve son foyer sans nouveau code | ☐ |
| 8.4 | G | Quand G est seul dans le foyer, **Supprimer le foyer** | Le foyer disparaît du serveur, le journal de G reste | ☐ |

« Se déconnecter » n'existe que sur l'écran sans foyer (« Créer ou rejoindre ») : il ne sert pas à tester la reprise.

## 9. Si quelque chose échoue

Ne pas insister : noter et passer à l'étape suivante. Pour me le transmettre :

- la **capture d'écran** (les deux iPhone si c'est une synchro) ;
- le **numéro de l'étape** de ce tableau et **l'heure exacte** ;
- **quel iPhone**, quel compte, et ce qui s'affichait.

Avec l'heure, je lis les journaux du serveur (lecture seule) : l'authentification, l'API, et si la requête est
arrivée. Un échec de connexion Apple et un échec de synchro n'ont pas les mêmes causes.

## 10. Ce que cette recette ne prouve pas

- La synchro en arrière-plan, volontairement absente de ce lot (ADR 0008 point 4).
- Le suivi GPS : la recette utilise des balades manuelles. Une balade GPS à deux est une recette à part.
- Le comportement du lien au-delà du premier jour : la lecture du fichier par Apple peut prendre
  jusqu'à 24 heures.
- La charge, la sécurité du serveur au-delà des règles testées, ou plus de deux appareils.

## 11. Résultat

| Critère | Résultat | Remarque |
|---|---|---|
| B-AC-01 connexion réelle conservée | | |
| B-AC-02 lien ouvre « Rejoindre » rempli | | |
| B-AC-03 repli sans l'app | | |
| B-AC-04 code invalide : rien n'est rejoint | |
| B-AC-05 aucun chien relié d'office | | |
| B-AC-06 bloc foyer sur Aujourd'hui | | |
| B-AC-07 doublon non compté | | |
| B-AC-08 lecteur n'écrit plus | | |
| B-AC-09 seul responsable | | |
| B-AC-10 retiré, message, journal intact | | |
