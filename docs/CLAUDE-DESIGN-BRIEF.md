# Brief pour Claude Design : tous les écrans et parcours de Trufflo

Statut : prompt prêt à coller, plus le dossier de référence qui l'accompagne. Rédigé le 2026-10-06.
Ce fichier ne contient aucun changement de code. Il décrit ce qui existe, ce qui est imposé et ce qui reste à concevoir.

## 1. Mode d'emploi

1. Coller le bloc de la section 2 comme message de départ.
2. Joindre les captures listées en section 6 (à produire sur simulateur iPhone 17e, mode clair).
3. Joindre `docs/DESIGN-SYSTEM.md` et `docs/ART-DIRECTION.md`. Ils font autorité sur les contraintes ci-dessous.
3bis. Joindre une sélection de `docs/design-references/` (écrans App Store de Strava, Nike Run Club, AllTrails, Komoot, Apple Fitness et de trois apps canines), avec son `INDEX.md`. Dire au designer de s'inspirer des structures, jamais des marques, et de ne reprendre aucun classement, segment ou total de kilomètres qu'il y verra.
4. Demander les écrans par lots (section 5), pas tous d'un coup : un parcours à la fois.

Ce qui n'est pas dans le prompt et qu'il faut vérifier en le lisant : l'outil de destination n'est pas précisé ici. Si Claude Design ne sait pas lire une capture ou un fichier joint, coller le texte des sections 3 et 4 dans le message.

## 2. Le prompt

```
Tu es directeur artistique et designer d'interface iOS. Tu travailles pour Trufflo,
une app iPhone native (SwiftUI, iOS 27, Liquid Glass) qui sert de carnet de
promenades pour chiens.

OBJECTIF
Concevoir, écran par écran et parcours par parcours, une version aboutie de toute
l'app. Pas un polissage des écrans actuels : une direction artistique cohérente,
appliquée partout. Les écrans actuels sont joints en capture pour que tu voies ce
qui existe, pas pour que tu les conserves.

PRODUIT
Un carnet de plein air agréable à ouvrir, centré sur la prochaine balade.
Signature : « À son rythme. Ensemble. » Ton calme, concret, non culpabilisant.
Interface en français. Une personne tient une laisse : un pouce, peu de lecture.
Ce n'est pas : une app de sport, un tableau de bord, un fil de réseau social.

CE QUI EST FIXÉ (ne pas rediscuter)
- Palette : Sable #F7F4ED (fonds), Forêt #1E4D3B (texte d'identité, action
  principale), Pêche #FFB38A (une touche par écran), Sauge #4CAF7B, Menthe #A7D7C5,
  Ardoise #5B6472 (texte secondaire), Danger #A94A2A (erreurs, suppression).
  Clair uniquement pour l'instant.
- Liquid Glass réservé aux contrôles, à la navigation et aux actions contextuelles.
  Jamais au contenu. Le contenu est chaud (sable, photo, carte), les contrôles sont
  en verre.
- Polices système, Dynamic Type obligatoire, SF Rounded pour l'identité et les
  chiffres, SF standard pour les phrases.
- Données autorisées à l'écran : nom, race (connue, croisée, inconnue), âge en
  texte libre, sexe, note de préférences saisie par la personne, photo facultative.
  Pour une balade : date, durée, tracé, distance mesurée, qualité de mesure, chiens
  présents, note.

RÈGLES PRODUIT (non négociables)
1. Métriques descriptives oui, performance non. « 3 balades enregistrées cette
   semaine », « Dernière sortie il y a 6 h » : oui. Objectif de distance, progression,
   pourcentage, comparaison avec une autre semaine ou un autre chien, badge, série
   (streak), culpabilisation : non.
2. Une distance ne se calcule que sur une balade qui l'a mesurée. Jamais de total
   de distances. Une balade saisie à la main n'a pas de distance : on n'écrit pas 0,
   on n'invente pas de tracé, on ne met pas de carte factice.
3. Rien n'est inféré sur le chien. Interdit : « préfère le matin », « aime les
   longues balades », « plutôt calme ». L'historique se décrit, il ne devient pas un
   trait de caractère.
4. La photo du chien est un axe central, mais elle est facultative : chaque écran
   a un état sans photo conçu pour tenir seul (pas un trou). Pas d'empreintes de
   pattes répétées.
5. Une balade en cours ne se termine jamais par accident : Terminer n'apparaît
   qu'en pause, et demande une confirmation.
6. Un état récupérable ne s'appelle jamais « Arrêté ». On dit « Interrompue ».

RÈGLES DE DESIGN
- Chaque écran a UN élément dominant, deux secondaires, le reste discret.
- Une carte (conteneur arrondi) n'existe que si elle représente un objet réel
  (un chien, une balade). Pas de carte « statistiques », « actions », « description ».
- Réduire le nombre de conteneurs d'au moins 40 % par rapport aux captures.
- Varier les formes : image pleine largeur, disque, capsule de contrôle, section
  sans fond. Pas un seul rayon partout.
- Pas de libellés en capitales espacées, pas de métadonnées jointes par des points
  médians, pas de numérotation décorative, pas de mot isolé en couleur dans un
  titre, pas de tiret cadratin ni demi-cadratin dans les textes.
- SF Symbols seulement quand ils aident à comprendre.
- Le mouvement montre ce qui change (insertion, changement d'état, transition de
  photo). Aucune boucle décorative. Respecter « Réduire les animations ».
- Accessibilité : Dynamic Type jusqu'aux plus grandes tailles sans troncature,
  contraste vérifié (texte sur photo : voile garanti), « Réduire la transparence »
  remplace le verre par un aplat forêt, cibles de 56 pt pour l'action principale,
  libellé VoiceOver pour chaque photo et chaque contrôle.

PARCOURS À COUVRIR (voir la liste des écrans jointe)
A. Premier lancement : introduction, création du chien, premier écran Aujourd'hui.
B. Balade GPS : départ, autorisation, enregistrement, pause, reprise, fin avec
   confirmation, bilan, retour au journal.
C. Interruption : permission retirée, relance à froid, reprise ou fin avec les
   données conservées.
D. Permission refusée au départ : alerte, réglages, repli par saisie manuelle.
E. Balade passée saisie à la main, puis sa fiche, puis sa suppression.
F. Profil du chien : voir, modifier (avec ou sans photo), supprimer.
G. Effacement de toutes les données.
H. Ce qui tourne mal : stockage indisponible, échec d'enregistrement, départ
   bloqué (trois causes), interruption (trois causes), élément supprimé
   ailleurs. Ces écrans comptent autant que les écrans heureux : ils sont
   inventoriés dans la liste jointe, section « Erreurs, absences et alertes ».

Couvre CHAQUE ligne de l'inventaire joint (écrans, états, alertes, erreurs,
contrôles système). Si tu en regroupes plusieurs, dis lesquelles et pourquoi.

POUR CHAQUE ÉCRAN ET CHAQUE ÉTAT, LIVRE
1. Pourquoi la version actuelle paraît générique (une phrase, sur la capture).
2. Trois compositions réellement différentes, avec la hiérarchie de chacune.
3. Le contenu exact affiché, texte compris, en français.
4. Ta recommandation, justifiée par la règle qu'elle sert.
5. Ce qui disparaît de l'écran actuel.
6. États : vide, normal, chargement, erreur, sans photo, grand texte.
7. Mouvement et accessibilité.
8. Les composants réutilisables, et ceux qui sont déjà partagés entre écrans.

À LA FIN, DONNE
- Un système de composants commun (liste, rôle, tailles, états).
- Une carte des parcours avec, pour chaque transition, ce qui change à l'écran.
- La liste des incohérences que tu as trouvées entre écrans et comment tu les résous.
- La liste de ce que tu n'as pas pu trancher faute d'information, sous forme de
  questions précises.

Ne code pas. Livre d'abord la direction et les variantes. Quand une information
manque, dis-le au lieu de l'inventer.
```

## 3. Inventaire complet de ce qui existe (à joindre en texte si les captures manquent)

Source : lecture du code au 2026-10-06, commit `a0d6a2d`, recoupée avec les vues, les alertes, les feuilles et les dialogues du dépôt. Chaque ligne indique l'état réel, pas l'intention. Quatre sous-sections : 3.1 écrans principaux, 3.2 variantes d'états, 3.3 erreurs, absences et alertes, 3.4 contrôles système et hors-app. Ce qui est prévu mais n'existe pas est en section 4bis, pas ici.

### 3.1 Écrans principaux

| Écran | État actuel | Identifiants de test à conserver |
|---|---|---|
| Introduction (plein écran, 3 pages) | Illustration, titre, texte, « Passer ». Texte corrigé le 2026-10-06 (« Partez, on s'occupe du reste », « Un carnet, pas un score », « À son rythme. Ensemble. »), illustrations d'origine. | `Passer` |
| Aujourd'hui, sans chien | Carte blanche avec illustration, « Bienvenue dans Trufflo », « Ajouter mon chien ». | `dog.add` |
| Aujourd'hui, avec chien | Nom en grand, portrait rond (photo ou initiale), bouton « Démarrer une balade GPS », lien « Ajouter une balade passée », « Cette semaine » (nombre de balades et temps enregistré en chiffres, dernière sortie en phrase), dernière balade en carte d'activité. | `walk.manual.add`, `walk.row.<id>`, `walk.live.banner` |
| Aujourd'hui, balade en cours | Bandeau « Balade en cours / interrompue / en pause » dans une carte blanche avec un point d'état et le bouton « Afficher ». | `walk.live.banner` |
| Journal | Fil de cartes d'activité groupées par jour : chien et date, titre selon l'heure (« Balade du soir »), durée et distance en chiffres, silhouette du parcours pour une balade GPS, début de note. Vide : illustration. | `walk.row.<id>`, `Aucune balade enregistrée` |
| Mes chiens | Liste : portrait rond, nom, nombre de balades. | `dog.row.<id>`, `dog.add.secondary` |
| Profil chien | Portrait pleine largeur ou champ sauge avec initiale, nom, race si connue, âge et sexe, « Modifier » en verre, « Balades » et « Temps enregistré » en chiffres, préférences, suppression discrète. | `dog.edit`, `dog.delete` |
| Formulaire chien | Formulaire système : photo, nom, sexe, âge, race, préférences. Non refait. | `dog.name`, `dog.age`, `dog.breedLabel`, `dog.preferences`, `dog.save`, `dog.error` |
| Formulaire balade passée | Formulaire système : chiens présents, date de fin, durée, note. Non refait. | `walk.minutes`, `walk.note`, `walk.save` |
| Balade en direct, enregistrement | Carte plein écran, une surface de verre (titre, état, durée, distance), un bouton Pause, chevron, recentrage. | `walk.pause`, `walk.minimize`, `walk.map.recentre`, `walk.timer`, `walk.distance`, `walk.signal` |
| Balade en direct, pause | Reprendre (principal) et Terminer (discret). | `walk.resume`, `walk.finish` |
| Balade en direct, interrompue | Même surface, état « Interrompue », message temporaire de 8 s, lien « Ouvrir les réglages » si la cause est une permission. | `walk.notice`, `walk.interrupted.settings` |
| Confirmation de fin | Feuille système : « Terminer et enregistrer la balade ? ». | `Continuer`, `Terminer la balade` |
| Départ bloqué | Alerte système : « Ouvrir les réglages » / « Ajouter manuellement ». | `walk.blocked.settings`, `walk.blocked.manual` |
| Bilan de balade | Carte du tracé en héros, « Balade avec … », titre selon l'heure, date, durée et distance en chiffres, note, qualité en une ligne. | `walk.summary.done`, `walk.summary.note`, `walk.summary.map` |
| Fiche d'une balade | Carte (si tracé), chien et date, titre selon l'heure, durée et distance en chiffres, note, « Détails » en lignes (fin, origine, qualité), suppression. | `walk.detail.map`, `walk.delete` |
| Réglages | Menu : « Revoir l'introduction », « Effacer toutes les données ». | `Réglages` |
| Effacement global | Dialogue de confirmation. | `Tout effacer` |
| Navigation | Trois onglets : Aujourd'hui, Journal, Mes chiens. | |

### 3.2 Variantes d'états des écrans principaux

| Écran | Variante | Texte actuel |
|---|---|---|
| Mes chiens | Vide | « Aucun profil créé », « Ajoutez un profil pour personnaliser le journal de votre compagnon. », bouton « Ajouter un chien » |
| Mes chiens | Avec chiens | portrait, nom, nombre de balades, bouton « Ajouter » en barre |
| Journal | Plusieurs jours | titres « Aujourd'hui », « Hier », puis jour complet |
| Aujourd'hui | Plusieurs chiens | noms joints, « N chiens » à la place de la race, portrait du premier |
| Aujourd'hui | Sans balade terminée | pas de phrase d'activité, pas de dernière balade |
| Profil chien | Sans photo, avec photo, sans préférences, sans balade | champ sauge avec initiale, ou photo avec voile |
| Bilan | Avec tracé, sans tracé exploitable (moins de deux points) | carte, ou le chien à la même place |
| Bilan | Qualité partielle, indisponible | « Une partie du parcours n'a pas été mesurée. », « Aucun point n'a été accepté. La durée seule est conservée. » |
| Balade en direct | Recherche du signal, signal faible, actif, en pause, interrompue | mots GPS : « Recherche », « Faible », « Actif », « En pause », « Interrompue » |
| Balade en direct | Reprise après interruption | libellé « Reprendre à partir de maintenant » |
| Confirmation de fin | Normale, après interruption | « Terminer et enregistrer la balade ? » / « Terminer avec les données enregistrées ? » |
| Message d'interruption (8 s) | Trois causes | « La localisation n'est plus autorisée. », « …est restreinte sur cet appareil. », « …est désactivée sur cet appareil. », suivi de « Données conservées jusqu'au dernier point enregistré. » |

### 3.3 Erreurs, absences et alertes

| Écran ou alerte | Quand | Texte actuel |
|---|---|---|
| Journal indisponible (plein écran) | le stockage ne s'ouvre pas au lancement | « Journal indisponible », « Le stockage n'a pas pu être ouvert. Vos données ne sont pas effacées. Fermez puis rouvrez l'application… » |
| Départ bloqué, permission refusée | premier départ après un refus | « La localisation est refusée. Autorisez-la dans les réglages pour lancer une balade. » avec « Ouvrir les réglages », « Ajouter manuellement », « Annuler » |
| Départ bloqué, permission restreinte | contrôle parental ou profil | « La localisation est restreinte sur cet appareil. » avec « Ajouter manuellement », « OK » (pas de réglages : ils ne réparent rien) |
| Départ bloqué, services désactivés | services de localisation coupés | « La localisation est désactivée sur cet appareil. Activez-la pour enregistrer un parcours. » avec « Ajouter manuellement », « OK » |
| Alerte « Erreur » (balade en direct) | échec d'une transition ou d'une écriture | titre « Erreur » et message technique, bouton « OK » |
| Alerte « Enregistrement impossible » | échec d'effacement global | « La modification n'a pas été enregistrée. Les données précédentes ont été conservées. » |
| Alerte « Modification impossible » (profil) | échec de suppression d'un profil | « Ce profil n'existe plus. » ou « Le profil n'a pas été supprimé. Les données précédentes ont été conservées. » |
| Alerte « Modification impossible » (balade) | échec de suppression d'une balade | « Cette balade n'existe plus. » ou « La balade n'a pas été supprimée… » |
| Alerte « Note non enregistrée » (bilan) | note trop longue ou échec d'écriture | « La note doit contenir au maximum 500 caractères. » ou « La note n'a pas été enregistrée. La balade, elle, est bien conservée. » |
| Erreurs de formulaire chien | nom absent, race manquante, âge ou note trop longs | texte sous le formulaire, annoncé à VoiceOver (`dog.error`) |
| Erreur de formulaire balade passée | durée ou date invalide, aucun chien, note trop longue | texte sous le formulaire |
| Profil introuvable | supprimé depuis un autre écran | « Ce profil n'existe plus », « Il a été supprimé de cet appareil. » |
| Balade introuvable (fiche et bilan) | supprimée depuis un autre écran | « Cette balade n'existe plus », « Elle a été retirée de cet appareil. » |
| Confirmation de suppression de profil | tap sur « Supprimer le profil » | « Supprimer ce profil ? », « Supprimer <nom> », « Annuler » |
| Confirmation de suppression de balade | tap sur « Supprimer la balade » | « Supprimer cette balade ? », « Supprimer définitivement », « Annuler » |
| Confirmation d'effacement global | menu Réglages | « Effacer le journal et les profils de cet appareil ? », « Tout effacer » |

Remarque : les alertes « Erreur » et « Modification impossible » reprennent des messages techniques. Leur ton est à revoir avec la microcopie de `DESIGN-SYSTEM.md` : une erreur dit ce qui s'est passé et ce qu'on peut faire, sans s'excuser et sans vague.

### 3.4 Contrôles système et éléments hors de l'app

| Élément | Où | Remarque |
|---|---|---|
| Demande de permission de localisation | premier départ | boîte système, texte de l'app dans `NSLocationWhenInUseUsageDescription` (fichier `Info.plist`). Le texte est de l'app, le cadre est iOS |
| Sélecteur de photo | formulaire chien | `PhotosPicker` système, pas d'accès à la photothèque entière |
| Sélecteur de sexe, de race | formulaire chien | menus système |
| Sélecteur de date et d'heure | formulaire balade passée | `DatePicker` système |
| Clavier, champ de note multiligne | formulaires, bilan | le bouton principal ne doit pas passer sous le clavier |
| Écran de lancement | démarrage à froid | généré automatiquement (blanc), aucun design |
| Icône de l'app | écran d'accueil iOS | `AppIcon`, tête de chien sur fond sombre |
| Barre d'état et bandeau de localisation | pendant une balade | éléments iOS sur la carte plein écran |
| Galerie du design system | outil de développement | `DesignSystemGalleryView`, à exclure de la conception |

## 4. Points d'attention, à trancher avec le designer

A. **Le texte de l'introduction contredit les règles produit.**
   - Page 2, « Comprenez son rythme : Observez les habitudes de votre chien » : promet de l'inférence, que la règle 3 interdit.
   - Page 3, « Rencontrez sa communauté : Trouvez des compagnons de promenade près de chez vous » : la fonction n'existe pas. `DESIGN-SYSTEM.md` limite « Compagnons » à une zone pilote ouverte.
   - Les trois illustrations (`OnboardingWalk`, `OnboardingRoutine`, `OnboardingCommunity`) sont des images générées, trois pages de même composition. À recomposer, texte compris.
B. **Plusieurs chiens.** Aujourd'hui démarre la balade avec tous les chiens. L'écran suppose un chien dominant. Décision produit ouverte : laisser choisir qui part ? Le brief demande au designer de proposer, pas de décider.
C. **Photo.** Le rendu avec une vraie photo n'a jamais été vu. Le stockage garde l'image telle que fournie par le sélecteur, sans redimensionnement. À prévoir avant tout plein cadre.
D. **« Modifier les détails » au bilan.** Aujourd'hui seule la note est modifiable. La correction de la durée n'existe pas. Ne pas la dessiner sans décision.
E. **Aperçu de carte dans le Journal.** Non retenu tant que son coût MapKit n'est pas mesuré sur appareil (`docs/ART-DIRECTION.md` §5.4). Le designer peut le proposer en variante, pas l'imposer.
F. **Dates.** Les captures de simulateur s'affichent parfois en anglais. À produire en français.
G. **Abandon d'une balade sans l'enregistrer.** N'existe pas : terminer enregistre toujours. Un menu « Abandonner » a été évoqué, non décidé.
H. **Mode sombre.** Non géré, l'app est forcée en clair. Palette sans variantes sombres.

## 4bis. Écrans prévus qui n'existent pas encore

Hors périmètre de ce brief : ils ne sont pas à refondre, ils sont à concevoir plus tard. Source : `PRD.md` section 4 et exigences F04 à F11. À ne pas mélanger avec l'inventaire ci-dessus.

| Livraison | Écrans prévus |
|---|---|
| M1 | routine et objectifs choisis (F04), corrections d'une balade (F05), plusieurs chiens : choix et bascule (F06), export (F07) |
| M2 | foyer partagé, contributeurs autorisés (F08) |
| M3 | proposer une balade locale, participer, discussion, modération (F09 à F11) |
| M4 | offre payante |

Le designer peut les évoquer pour garder de la place dans la navigation, sans les dessiner.

## 5. Ordre de travail proposé

1. Introduction et premier lancement (parcours A), car le texte est à corriger.
2. Aujourd'hui dans tous ses états, y compris la balade en cours.
3. Écran de balade et ses états (parcours B, C, D), déjà abouti : lui demander une revue de cohérence, pas une refonte.
4. Formulaires chien et balade passée (parcours E, F), les deux derniers écrans en liste système, avec leurs contrôles système (3.4).
5. Fiche d'une balade et réglages (parcours E, G).
6. Erreurs, absences et alertes (3.3) : une seule passe, pour un ton et une forme cohérents.
7. Système de composants et carte des parcours, une fois les écrans fixés.

## 6. Captures à joindre

À produire sur simulateur iPhone 17e, mode clair, locale française, un fichier par ligne :
introduction (3 pages) ; Aujourd'hui vide ; Aujourd'hui avec chien et une balade ; Aujourd'hui avec balade interrompue ; Journal vide ; Journal avec deux jours ; Mes chiens ; profil sans photo ; profil avec photo (à créer) ; formulaires chien et balade ; balade en direct (enregistrement, pause, interrompue, confirmation) ; bilan ; fiche d'une balade ; menu Réglages.

Ajouter les captures de 3.2 et 3.3 : Mes chiens vide, Aujourd'hui avec plusieurs chiens, les trois départs bloqués, les trois messages d'interruption, « Journal indisponible », « Profil introuvable » et « Balade introuvable », chaque alerte, chaque erreur de formulaire, les trois confirmations de suppression.

Manquantes aujourd'hui : profil avec photo, journal avec une balade GPS, bilan sans tracé, tailles de texte accessibles, et la plupart des états d'erreur (non déclenchés sur simulateur à ce jour).

## 7. Ce que ce brief ne garantit pas

- Aucune variante n'a été produite par l'outil cible : le prompt n'est pas testé.
- Les captures citées n'existent pas toutes encore.
- Les règles viennent de `DESIGN-SYSTEM.md`, `ART-DIRECTION.md` et du code. Elles sont à jour au commit `a0d6a2d`.
