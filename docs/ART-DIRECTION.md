# Direction artistique hors carte

Statut : spécification, rien n'est implémenté. Rédigée le 2026-10-06 pour décision.
Périmètre : Aujourd'hui, Journal, Profil chien, Résumé de balade. L'écran de balade en direct et le bilan
de fin de session suivent déjà `DESIGN-SYSTEM.md` et ne sont pas revus ici, sauf le résumé qui est réutilisé.

Sources lues avant d'écrire :
- `docs/DESIGN-SYSTEM.md` (intention, palette, microcopie).
- `PRD.md` section 5 (F01 profil, photo facultative) et `docs/PRIVACY-AND-SAFETY.md` (photo dans le périmètre d'effacement).
- `trufflo/Data/Models.swift` pour les données réellement disponibles.
- Doc Apple livrée avec Xcode 27.0 : `SwiftUI-Implementing-Liquid-Glass-Design.md`.
- Les neuf écrans relus à l'écran le 2026-10-06 (preuves E-043).

## 1. Ce qui rend les écrans actuels génériques

Constat sur captures, pas sur impression :
1. Chaque écran est une `List` : sections grises, cartes blanches de même rayon, même ombre, même poids.
2. Aucun écran n'a d'élément dominant, sauf Aujourd'hui depuis le bouton principal.
3. Le chien est absent. La photo existe dans le modèle (`DogRecord.photoData`) et dans le formulaire, mais aucun écran ne l'affiche.
4. L'identité visuelle vient d'illustrations d'état vide qui disparaissent dès qu'il y a des données.
5. Typographie plate : un seul style rond de taille moyenne partout, texte secondaire gris.

## 2. Contraintes produit (non négociables)

### 2.1 Métriques descriptives, pas de performance

| Autorisé (descriptif) | Interdit (performance) |
|---|---|
| `3 balades enregistrées cette semaine` | objectif de distance, progression vers une cible |
| `Dernière sortie il y a 6 h` | `+18 %`, comparaison avec la semaine précédente |
| `32 min enregistrées` | comparaison avec d'autres chiens |
| date, durée, chien présent | badges, séries (streaks), culpabilisation |

### 2.2 Règles de calcul

- **Cette semaine** : les 7 derniers jours glissants, pas la semaine calendaire. Une semaine calendaire retombe à zéro le lundi et fabrique un sentiment de retard. À valider.
- Seules les balades au statut terminé comptent.
- **Durée** : on additionne `confirmedSeconds`, mesurée ou déclarée. Le mot « enregistrées » couvre les deux.
- **Distance** : jamais additionnée. Une balade manuelle n'a pas de distance (`recordedPathMeters` nul). Une balade GPS partielle peut en avoir une incomplète. Aucun total kilométrique n'est affiché tant que cette ambiguïté existe. Une distance affichée par balade reste sa propre mesure, ou rien.
- Sur une ligne de liste, une distance absente n'affiche rien (pas de « Non mesurée » répété). Le détail dit « Non mesurée ».

### 2.3 Rien d'inféré sur le chien

Le profil contient : nom, race (connue, croisé, inconnue), âge en texte libre, sexe, note de préférences saisie par la personne, photo. Les écrans n'affichent que cela. Interdit : « préfère le matin », « aime les longues balades », « plutôt calme ». L'historique se décrit (« 12 balades enregistrées »), il ne se transforme pas en trait de caractère.

### 2.4 Photo

Facultative (PRD F01). Donc chaque écran a un état sans photo qui est conçu, pas un trou. Repli retenu : un champ teinté (sauge claire) portant l'initiale du nom en grand, pas une empreinte de patte. `DESIGN-SYSTEM.md` écarte déjà les pattes répétées.

À vérifier avant d'afficher en grand : `photoData` est stocké tel que fourni par le sélecteur système. Une photo de 12 Mo décodée dans une liste coûte. Spécifier un redimensionnement à l'import (côté long 1600 px) avant tout écran plein cadre. Les métadonnées de localisation sont à retirer avant toute publication (`PRIVACY-AND-SAFETY.md`).

## 3. Système visuel commun

### 3.1 Jetons (la palette est imposée par la marque)

| Rôle | Valeur | Usage |
|---|---|---|
| Sable | `#F7F4ED` | fond d'écran, jamais de blanc pur derrière du texte long |
| Forêt | `#1E4D3B` | texte d'identité, action principale, rien d'autre en aplat |
| Pêche | `#FFB38A` | une seule touche par écran, jamais porteuse d'un statut |
| Sauge | `#4CAF7B` | nature, succès, champ de repli de la photo en teinte claire |
| Menthe | `#A7D7C5` | lavis de fond ponctuel |
| Ardoise | `#5B6472` | texte secondaire |

Verdict sur le plan : la combinaison fond crème, accent terre cuite et lettrage de titre est un des défauts les plus répandus du design généré. Elle est ici dictée par la marque, donc conservée. Pour qu'elle ne soit pas le défaut : la forêt domine en texte (pas le terre cuite), la pêche reste ponctuelle, et c'est la photo du chien qui apporte la couleur et la singularité. Sans photo, l'écran doit rester sobre, pas se rattraper avec des dégradés.

### 3.2 Typographie

Polices système uniquement (iOS natif, Dynamic Type, aucun fichier à embarquer). Deux rôles distincts :
- **SF Rounded** pour l'identité et les chiffres : nom du chien, durées, titres de jour.
- **SF Texte standard (non arrondi)** pour les phrases : notes, explications, libellés.

| Rôle | Style | Exemple |
|---|---|---|
| Nom du chien | `largeTitle`, rounded, `heavy` | Oslo |
| Titre de section | `title2`, rounded, `semibold` | Dernière balade |
| Chiffre principal | `title`, rounded, `bold`, `monospacedDigit` | 32 min |
| Titre de ligne | `headline` | Balade avec Oslo |
| Corps, note | `body` | Très calme au parc. |
| Secondaire | `subheadline`, ardoise | Hier à 18:42 |

Règles tirées de la revue : pas de libellés en capitales espacées au-dessus des blocs, pas de métadonnées jointes par des points médians (« A · B · C »), pas de numérotation décorative, pas de mot isolé en couleur dans un titre. Les métadonnées passent à la ligne. La dette existante : l'écran de balade en direct et le bilan utilisent encore « DURÉE » et « DISTANCE » en capitales, à revoir à part.

### 3.3 Formes

Quatre rôles, pas un rayon unique :
- Image pleine largeur, sans rayon (photo, carte héros).
- Objet réel (une balade) : carte, rayon 28 pt.
- Contrôle : capsule en verre.
- Section sans fond : texte sur sable, séparée par l'espace ou un filet fin.

Règle : une carte n'existe que si elle représente un objet (un chien, une balade, un événement). Pas de carte « statistiques », « actions » ou « description ».

### 3.4 Verre

Liquid Glass réservé aux contrôles, à la navigation et aux actions contextuelles, jamais au contenu (conforme à la doc Apple installée). API : `glassEffect`, `GlassEffectContainer`, `.glass` et `.glassProminent`. L'action principale d'un écran est un bouton `glassProminent` forêt.

### 3.5 Mouvement

Seulement quand il montre ce qui change :
- insertion de la dernière balade en tête de liste (ressort léger) ;
- le bouton de départ passe de « Partir en balade » à « Recherche du signal » puis ouvre la carte ;
- transition de la photo entre le profil et la barre de navigation (zoom natif) ;
- aucune boucle décorative. Sous « Réduire les animations », mise à jour immédiate ou fondu court.

### 3.6 Accessibilité (valable pour tous les écrans)

- Dynamic Type jusqu'aux tailles d'accessibilité : aucune hauteur fixe sur du texte, retour à la ligne plutôt que troncature.
- Texte sur photo : voile dégradé garanti, contraste vérifié par capture, jamais de texte sur une zone claire non voilée.
- Chaque photo a un libellé (« Photo de Oslo ») ou est masquée à VoiceOver si purement décorative.
- Actions principales à portée du pouce, hauteur de 56 pt minimum.
- « Réduire la transparence » : le verre devient un aplat forêt (repli déjà en place).
- Dates formatées avec la locale de l'appareil (la capture du 2026-10-06 montre « 6 Oct at 14:13 » sur un simulateur en anglais ; à revérifier en français).

### 3.7 Composants à créer ou modifier

`TruffloDogPortrait` (photo ou repli, trois tailles), `TruffloDayHeader`, `TruffloTimelineRow`, `TruffloMetricLine`, `TruffloPlainSection` (section sans fond), `TruffloPhotoScrim`. À retirer à terme de ces écrans : `TruffloCard` en usage de regroupement, `TruffloBadge` d'origine (« Suivi GPS », « Saisie manuelle ») remplacé par une phrase.

### 3.8 Couplage avec les tests UI

Les parcours cherchent des identifiants et libellés. Ils doivent rester : `dog.add`, `dog.add.secondary`, `dog.row.<id>`, `dog.edit`, `dog.delete`, `walk.manual.add`, `walk.row.<id>`, `walk.live.banner`, `walk.delete`, le bouton « Démarrer une balade GPS », les onglets « Journal » et « Aujourd'hui », et `walk.summary.*`. Toute variante retenue conserve ces points d'accès.

## 4. AUJOURD'HUI

Données disponibles : chiens (nom, photo, race, âge), balade en cours éventuelle, dernière balade terminée, nombre de balades terminées sur 7 jours.
Cas particuliers : plusieurs chiens (la balade démarre avec tous, comportement actuel, voir §8), balade en cours ou interrompue, aucun chien (état vide inchangé).

### TODAY A, Portrait

```
+------------------------------+
| photo d'Oslo plein cadre     |  ~45 % de la hauteur, sous la barre d'état
|                              |
| Oslo                         |  nom blanc sur voile
| Golden retriever, 3 ans      |
+------------------------------+
  3 balades enregistrées
  cette semaine

  Dernière balade
  Hier à 18:42, 32 min
  Balade au parc.            >

        [ Partir en balade ]       verre prominent, ancré en bas
```

- Dominant : la photo.
- Contenu exact : nom, race, âge (champ texte libre tel que saisi), phrase de semaine, dernière balade (jour, heure, durée, début de note), bouton.
- Composants : `TruffloDogPortrait` plein cadre, `TruffloPhotoScrim`, `TruffloPlainSection`, bouton `glassProminent`.
- Photo : héros. Repli : champ sauge claire avec l'initiale en 160 pt, moins fort.
- Verre : bouton et barre d'onglets seulement.
- Disparaît : la carte de slogan, le bouton secondaire « Ajouter une balade passée » (déplacé dans un menu du bouton ou sous la dernière balade), la carte blanche de la dernière balade, les badges.
- Avantages : impact immédiat, identité du chien.
- Risques : très dépendant de la photo, l'état sans photo est le plus faible des trois ; photo basse définition ; l'accès à « Ajouter une balade passée » s'éloigne (le parcours UI `walk.manual.add` doit rester joignable) ; plusieurs chiens exigent une composition à part.

### TODAY B, Éditorial asymétrique

```
  Oslo                    ( photo ronde
  Golden retriever         132 pt, décalée
  3 ans                    à droite )

  Dernière sortie il y a 18 h
  3 balades enregistrées cette semaine

  [   Partir en balade   ]        verre prominent, pleine largeur

  Dernière balade
  Hier, 18:42
  32 min                          chiffre en title bold
  Balade au parc.               >
  ----------------------------
  Ajouter une balade passée
```

- Dominant : le nom du chien, très grand, avec le bouton comme second pôle.
- Contenu exact : nom, race, âge, deux phrases descriptives, bouton, dernière balade, lien discret de saisie manuelle.
- Composants : `TruffloDogPortrait` rond, `TruffloMetricLine`, `TruffloPlainSection`, bouton `glassProminent`.
- Photo : disque de 132 pt. Repli : disque sauge avec initiale, aussi fort que la photo, donc l'écran tient sans.
- Verre : bouton et onglets.
- Disparaît : la carte de slogan, les trois cartes empilées, les badges, l'illustration de collier une fois un chien créé.
- Avantages : robuste avec ou sans photo, un seul conteneur ou aucun, proche de l'écran actuel donc risque faible pour les tests.
- Risques : moins spectaculaire que A ; la photo reste petite ; l'asymétrie doit rester lisible en très grand texte (le disque passe alors au-dessus du nom).

### TODAY C, Départ d'abord

```
  Bonjour, Oslo ?                (petite photo ronde 56 pt)

  +--------------------------+
  | panneau forêt, bas d'écran|
  |                          |
  |  Partir en balade        |  texte blanc très grand
  |  Dernière sortie hier    |
  |  [ Démarrer ]            |
  +--------------------------+
```

- Dominant : le panneau d'action.
- Contenu exact : salutation, nom, photo ronde, phrase de dernière sortie, bouton.
- Composants : panneau forêt à coins hauts arrondis, `TruffloDogPortrait` petit.
- Photo : accessoire. Verre : onglets, bouton interne.
- Disparaît : tout ce qui n'est pas le départ ; la dernière balade passe en une phrase.
- Avantages : priorité maximale à l'action principale.
- Risques : repeint l'écran en forêt, contraire à « garder les écrans neutres » ; la salutation (« Bonjour ») est un ton marketing que `DESIGN-SYSTEM.md` ne pose pas ; peu d'identité du chien.

Recommandation AUJOURD'HUI : **B**. Seule variante qui tient sans photo, qui ne dépend d'aucun rendu coûteux et qui garde les identifiants actuels. Elle emprunte à A le voile de texte si la photo est assez grande ; A est réservé au profil, où la photo est le sujet.

## 5. JOURNAL

Données par ligne : chiens (noms figés au moment de la balade), fin, durée confirmée, origine (GPS ou manuelle), qualité, distance si mesurée, note.
La carte miniature n'est retenue qu'après mesure, voir §5.4.

### JOURNAL A, Chronique typographique

```
Journal
3 balades enregistrées cette semaine

Aujourd'hui
  |
  o  18:42   Oslo                32 min
  |          Balade au parc.
  |
Hier
  |
  o  08:15   Oslo                24 min
  |  (anneau creux : saisie manuelle)
  |
Mardi 30 septembre
  ...
```

- Dominant : les titres de jour, grands, en rounded.
- Contenu exact : phrase de semaine, jour, heure, noms, durée, première ligne de note. Distance en fin de ligne uniquement pour une balade GPS dont elle est mesurée. Anneau creux pour une saisie manuelle, point plein pour le GPS.
- Composants : `TruffloDayHeader`, `TruffloTimelineRow`, filet vertical continu.
- Photo : un petit disque du chien seulement s'il y en a plusieurs. Verre : onglets.
- Disparaît : toutes les cartes, tous les badges « Suivi GPS » et « Saisie manuelle », l'icône chronomètre.
- Avantages : zéro coût de rendu, scanne très vite, aucune carte, bon en Dynamic Type.
- Risques : peut paraître austère si le journal est maigre ; peu de matière visuelle ; il faut soigner l'espacement pour que ce ne soit pas une liste simple.

### JOURNAL B, Chronique avec aperçu sélectif

A, plus un aperçu de carte pour certaines balades seulement.
- Règle de sélection : balade GPS avec au moins deux points, dans les 7 derniers jours, au plus trois aperçus visibles en même temps. Le reste reste typographique.
- Composants en plus : instantané de carte en cache disque (clé : identifiant de balade et révision), rayon 28 pt.
- Photo, verre : comme A.
- Avantages : de la matière visuelle exactement où elle a du sens, le gabarit reste léger.
- Risques : dépend de la mesure de coût (§5.4) ; rendu asynchrone donc des lignes qui changent de hauteur ; états de repli à concevoir (instantané absent, échec, hors réseau, tuiles manquantes).

### JOURNAL C, Cartes média

Une carte par balade : en-tête carte ou photo, durée en grand, note citée. Une balade manuelle devient une carte sable avec la note en grande citation.
- Dominant : la carte média de chaque balade.
- Disparaît : la liste plate.
- Avantages : riche, très différenciant.
- Risques : coûte le plus cher à rendre, répète la même carte N fois (retour au défaut du rayon unique), mélange des balades GPS et manuelles de poids visuel très inégal, contraire à « ne pas partir sur une mini-carte pour chaque ligne ».

Recommandation JOURNAL : **A maintenant**, **B si la mesure du coût est bonne**. C est écartée.

### 5.4 Plan de mesure pour l'aperçu de carte

À faire avant de retenir B, sur un appareil réel (le simulateur ne mesure pas un coût de rendu cartographique) :
1. Lire la doc MapKit de la version installée pour l'API d'instantané courante avant de l'utiliser (non vérifiée ici).
2. Temps de rendu d'un instantané 358 x 200 pt avec un tracé de 100, 500 et 2 000 points : médiane et p95.
3. Mémoire pic pour 3 instantanés visibles et défilement rapide sur 50 balades.
4. Comportement hors réseau et avec tuiles absentes (le tracé doit rester lisible).
5. Seuil de décision à fixer avant la mesure, par exemple p95 sous 300 ms hors thread principal et aucun défilement saccadé.

## 6. PROFIL CHIEN

Données : nom, race, âge, sexe, note de préférences, photo, date de création, nombre de balades enregistrées avec ce chien. Rien d'autre.

### PROFIL A, Portrait

```
+------------------------------+
| photo d'Oslo, pleine largeur |  ~50 %
|                              |
| Oslo                         |  nom sur voile
+------------------------------+
  Golden retriever
  3 ans, mâle                       [ Modifier ]  verre

  12 balades enregistrées

  Préférences de sortie
  Tire en laisse près des vélos.    texte saisi par la personne

  Informations
  Race            Golden retriever
  Âge             3 ans
  Sexe            Mâle

                        Supprimer le profil     texte danger, discret
```

- Dominant : la photo et le nom.
- Contenu exact : voir ci-dessus. La note de préférences est affichée telle quelle, attribuée comme saisie de la personne, sans reformulation.
- Composants : `TruffloDogPortrait` plein cadre, `TruffloPhotoScrim`, `TruffloPlainSection`, bouton `glass`.
- Photo : héros ; zoom de transition vers la barre de navigation au défilement. Repli : champ sauge claire avec l'initiale.
- Verre : « Modifier », barre de navigation.
- Disparaît : la carte « Profil », le badge de race, la carte d'actions.
- Avantages : le sujet domine, les informations administratives descendent, très différent des autres écrans.
- Risques : l'effet dépend de la photo ; le repli doit être aussi soigné ; mise à l'échelle de photos très verticales ou horizontales (recadrage à spécifier).

### PROFIL B, Photo carrée en marge

Photo carrée 1:1 avec marge de 20 pt et rayon 28 pt, nom dessous aligné à gauche, puis les informations en liste de définitions.
- Dominant : la photo, contenue.
- Avantages : pas de texte sur photo, donc aucun problème de contraste ; fonctionne même avec une photo moyenne.
- Risques : visuellement plus sage, proche d'une carte ; la photo n'est pas immersive.

### PROFIL C, En-tête compact

Disque de 88 pt à gauche du nom, contenu au-dessus de la ligne de flottaison, informations en premier.
- Dominant : le nom.
- Avantages : sans photo l'écran tient parfaitement, très peu de risque.
- Risques : la photo n'est plus un axe central, ce qui va contre la décision.

Recommandation PROFIL : **A**, avec le repli sauge et initiale. B est la solution de secours si les photos importées sont de qualité insuffisante.

## 7. RÉSUMÉ DE BALADE

Deux familles de contenu, deux compositions, jamais de faux tracé sur une balade manuelle.

### 7.1 Balade GPS

Données : tracé, durée confirmée, distance mesurée, qualité, chiens, note, fin.

#### RÉSUMÉ A, Carte héros

```
+------------------------------+
| carte du tracé plein cadre   |  ~45 %, [<] verre en haut à gauche
+------------------------------+
  Hier à 18:42
  Balade avec Oslo

  32 min            3,8 km          chiffres en title bold, sans libellé en capitales
  durée             distance

  Très calme au parc.               note en corps, sans cadre

  Mesurée par GPS                   une ligne ardoise
                                [ Terminé ]  verre prominent
```

- Dominant : la carte.
- Composants : `TruffloTrackMap` (existant, non vivant), `TruffloMetricLine`, note sans fond, bouton `glassProminent`.
- Photo : disque du chien près du titre, petit.
- Verre : retour et bouton.
- Disparaît : trois cartes (mesures, qualité, note), le chip de chien, le titre « Bilan de la balade » noir.
- Avantages : continuité avec l'écran de balade en direct, la carte est l'objet émotionnel.
- Risques : un tracé court ou absent (balade GPS sans point suffisant) donne un héros vide, donc repli requis (voir 7.2) ; la carte plein cadre demande un cadrage automatique robuste.

#### RÉSUMÉ B, Chiffres d'abord

Durée et distance en très grand sur sable, carte en bandeau 16:9 avec rayon 28 pt dessous, note puis qualité.
- Dominant : les deux chiffres.
- Avantages : lisible même sans carte exploitable, léger.
- Risques : moins immersif, la carte devient accessoire alors qu'elle est le point fort de l'app.

#### RÉSUMÉ C, Une phrase

Un titre-phrase de 34 pt : « 32 minutes avec Oslo, 3,8 km. » La carte au-dessous, bord à bord, détails réduits.
- Avantages : ton éditorial, calme, cohérent avec la microcopie descriptive.
- Risques : une phrase construite varie selon les cas (distance absente, plusieurs chiens, pluriels) et multiplie les chaînes à traduire ; moins scannable que deux chiffres isolés.

### 7.2 Balade manuelle

Commun aux trois variantes, parce que le contenu est le même :
- Aucune carte, aucun placeholder cartographique.
- Héros : la photo du chien (ou le repli) à la place de la carte, même hauteur, pour que le gabarit reste stable.
- Durée en très grand, avec la phrase « Durée déclarée. Aucune distance mesurée. » en ardoise. Pas de « Non mesurée » en gros.
- Note en corps.
- Même bouton principal.

Recommandation RÉSUMÉ : **A** pour une balade GPS dont le tracé a au moins deux points ; **7.2** dans tous les autres cas, y compris une balade GPS sans tracé exploitable (elle ne prétend pas à une carte).

## 8. Questions ouvertes à trancher

1. **Semaine glissante ou calendaire** pour la phrase descriptive (recommandé : glissante).
2. **Plusieurs chiens sur Aujourd'hui.** Aujourd'hui lance la balade avec tous les chiens (`dogs.map(\.id)`). B suppose un seul chien dominant. Pour plusieurs : disques empilés et noms joints, mais il faut décider si on laisse choisir qui part. C'est une décision produit, hors de cette spécification.
3. **Redimensionnement de la photo à l'import**, à spécifier avant l'écran plein cadre (§2.4).
4. **« Modifier les détails » au résumé.** Aujourd'hui seule la note est modifiable. La correction de la durée n'existe pas ; ne pas la dessiner avant de la décider.
5. **Capitales de libellé** (« DURÉE », « DISTANCE ») sur l'écran de balade en direct et le bilan : à retirer pour cohérence avec §3.2, ou à conserver comme exception de lisibilité sur verre.
6. **Mesure MapKit** pour Journal B (§5.4).

## 9. Ce que cette spécification ne contient pas

- Aucune implémentation, aucun changement de code.
- Aucune capture ni maquette rendue : les schémas sont des intentions de composition, pas des mesures.
- Aucune vérification que `glassEffect` ou les transitions de zoom se comportent comme décrit sur appareil réel.
- Pas l'onboarding ni la navigation par onglets, laissés hors périmètre.
