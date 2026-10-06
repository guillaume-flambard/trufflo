# Lot A : première impression et cohérence

Exigences du PRD couvertes : F01 (profil), F12 (accessibilité et états), F13 (confidentialité),
F14 (qualité de livraison).

## Objectif

Une personne qui installe Trufflo ajoute son chien en moins d'une minute, reconnaît son univers
sur Aujourd'hui, et comprend ce qui reste sur l'iPhone et ce qui part. L'app est aussi soignée
sans photo et sans historique qu'avec.

Le lot est fini quand : A-AC-01 à A-AC-16 ont chacun une preuve, et les captures du même build
couvrent la matrice de la section 6.

## 1. État de départ vérifié (code à `d51dbac`)

| Constat | Où | Vérifié |
|---|---|---|
| L'introduction dit « Tout reste sur cet iPhone. Pas de compte, rien de publié. », faux dès qu'on rejoint un foyer. | `OnboardingView.swift:23-24` | Oui |
| Elle dit aussi « Aucun objectif », alors que les routines existent. | `OnboardingView.swift:19` | Oui |
| Le dernier bouton s'appelle « Ajouter mon chien » mais ferme l'introduction sans ouvrir le formulaire. | `OnboardingView.swift:86`, `StarterRootView.swift:212-215` | Oui |
| La race est un choix Connue / Croisé / Inconnue puis un champ texte libre. Aucune recherche. | `DogFormView.swift:54-57` | Oui |
| La CI accepte « Test run with 0 tests ... passed ». | `.github/workflows/ci.yml:54` | Oui |
| `docs/BACKLOG.md` présente tous les tickets comme initiaux. | `docs/BACKLOG.md:3` | Oui |
| Aujourd'hui (variante A) : portrait plein cadre, phrase de semaine, bouton ancré. | commit `d51dbac` | Oui |
| Journal (variante A, fil vertical, point plein ou creux) et Profil (variante A) : faits, non commités. | arbre de travail | Oui |

## 2. Exigences

**A-REQ-00, réconcilier le suivi.** `docs/BACKLOG.md` marque ce qui est fait (avec la preuve ou le
commit), ce qui reste, et renvoie vers ces specs. Aucune fonction existante n'y reste listée à
refaire.

**A-REQ-01, introduction exacte (F13).** Le texte de confidentialité décrit le comportement réel :
carnet local, partage des seuls résumés si la personne crée ou rejoint un foyer, compte Apple
uniquement pour le foyer. Formulation exacte : décision D3. « Aucun objectif » devient une phrase
vraie sur les routines (choisies, suspendables, jamais imposées).

**A-REQ-02, l'introduction mène au premier chien.** Le dernier bouton fait ce qu'il dit. Sans chien,
il ferme l'introduction et ouvre le formulaire d'ajout. Avec au moins un chien (introduction revue
depuis les réglages), le bouton s'appelle « Terminer » et ne crée rien.

**A-REQ-03, race par recherche (F01).** Une entrée « Race » ouvre une recherche locale dans un
catalogue (source : décision D1). La recherche tolère accents, casse et alias (« berger allemand »,
« BA », « malinois » trouvent la bonne entrée). Trois choix restent toujours visibles sans
chercher : « Croisé », « Je ne sais pas », « Autre race » (qui ouvre le champ libre actuel).

**A-REQ-04, données de race.** Une entrée du catalogue a un identifiant stable, un nom français et
des alias ; le catalogue vit dans le code (`BreedCatalog`). Le profil enregistre une race choisie
comme aujourd'hui : `breedKind = "known"` et le nom affiché dans `breedLabel`. Aucune colonne
ajoutée.

Révisé le 2026-10-06 avant implémentation : la première version demandait de stocker l'identifiant
et la version du catalogue. Cela exigeait une migration SwiftData (V7) et une migration serveur
(`breed_kind`, `breed_label` partent déjà au foyer), pour une donnée qu'aucune fonction n'utilise,
puisque A-REQ-05 interdit d'en déduire quoi que ce soit. Conséquence acceptée : si une entrée du
catalogue est renommée plus tard, les profils gardent l'ancien nom, affiché comme une race saisie.
Les races déjà saisies en texte libre ne sont pas converties : elles restent telles quelles, et la
personne peut choisir une entrée du catalogue.

**A-REQ-05, rien n'est déduit de la race.** Aucun texte, aucune routine, aucune suggestion ne
dépend de la race choisie (PRD F01 et ART-DIRECTION §2.3).

**A-REQ-06, première utilisation composée.** Sans photo et sans balade, Aujourd'hui, le Profil et le
Journal sont des écrans pensés : portrait de repli (sauge, initiale), une action principale, une
invitation à ajouter la photo, et l'emplacement de la première balade qui dit ce qui y apparaîtra.
Aucune image de chien qui ne serait pas le chien de la personne.

**A-REQ-07, cohérence des trois écrans refaits.** Aujourd'hui, Journal et Profil suivent
ART-DIRECTION (variante A partout) : mêmes rôles typographiques (§3.2), pas de carte de
regroupement (§3.3), verre réservé aux contrôles (§3.4). Les identifiants d'accessibilité utilisés
par les parcours UI (§3.8) sont conservés.

**A-REQ-08, la photo est préparée à l'import.** Une photo est redimensionnée à 1600 px sur le côté
long et débarrassée de ses métadonnées de localisation avant d'être enregistrée (ART-DIRECTION §2.4,
PRD F13). Les photos déjà stockées sont traitées à la première lecture ou laissées telles quelles :
à choisir dans l'implémentation, et à écrire dans la preuve.

**A-REQ-09, la CI échoue pour de vrai.** Le contrôle du journal de tests exige un nombre de tests
strictement positif, et le code de sortie de `xcodebuild` traverse les tubes.

**A-REQ-10, le portrait vise le chien (ajoutée le 2026-10-07).** Une photo n'est pas recadrée au
centre : le portrait de Aujourd'hui et du Profil vise l'animal. Trouvé sur une vraie photo : au
recadrage centré, la tête d'un border collie était coupée en haut du cadre. Le point visé vient de la
détection d'animaux de Vision (`VNRecognizeAnimalsRequest`, iOS 13 et plus), dans le haut de la boîte
du chien ; sans détection, on vise le haut du cadre (35 % depuis le haut). Rien ne quitte l'iPhone.

## 3. Critères d'acceptation

| ID | Exigence | Étant donné | Quand | Alors | Preuve |
|---|---|---|---|---|---|
| A-AC-01 | REQ-00 | le backlog | on le relit | chaque ticket M0/M1/M2 a un statut et une preuve ou un manque nommé | relecture |
| A-AC-02 | REQ-01 | une installation neuve | on lit l'introduction | aucune phrase n'est fausse après avoir rejoint un foyer | capture + relecture contre ADR 0008 |
| A-AC-03 | REQ-02 | aucun chien | on touche le dernier bouton | le formulaire d'ajout s'ouvre | parcours UI |
| A-AC-04 | REQ-02 | un chien existe | on revoit l'introduction et on la termine | aucun profil créé, aucun formulaire ouvert | parcours UI |
| A-AC-05 | REQ-03 | le formulaire chien | on tape « berger all » | « Berger allemand » est proposé en premier | unitaire (recherche) + capture |
| A-AC-06 | REQ-03 | le formulaire chien | on tape « berge » sans accent ni majuscule | les bergers sont proposés | unitaire |
| A-AC-07 | REQ-03 | le formulaire chien | on ne cherche rien | « Croisé », « Je ne sais pas », « Autre race » sont visibles | capture |
| A-AC-08 | REQ-04 | un chien avec une race du catalogue | on relance l'app | la même race est affichée | unitaire (persistance) |
| A-AC-09 | REQ-04 | un profil existant avec une race en texte libre | on ouvre son formulaire | le texte est intact et affiché tel quel ; le schéma SwiftData n'a pas changé | test de schéma doré existant + capture |
| A-AC-10 | REQ-05 | deux chiens de races différentes | on compare tous les écrans | aucun texte ne diffère sauf le nom de race | relecture du code (recherche de `breed`) |
| A-AC-11 | REQ-06 | aucun chien, puis un chien sans photo ni balade | on parcourt les trois onglets | aucun écran vide, une seule action principale par écran | captures |
| A-AC-12 | REQ-07 | le build du lot | on lance les parcours UI | `gps-journeys.sh all` : OK | parcours UI |
| A-AC-13 | REQ-08 | une photo de 12 Mo avec position GPS | on l'ajoute au profil | la donnée stockée fait au plus 1600 px de côté et n'a plus de position | unitaire |
| A-AC-14 | REQ-09 | un plan de test qui ne lance aucun test | la CI tourne | le job échoue | essai sur une branche |
| A-AC-15 | REQ-06, F12 | texte en taille d'accessibilité maximale | on parcourt Aujourd'hui, Journal, Profil, formulaire chien | rien de coupé, tout reste atteignable | captures |
| A-AC-16 | REQ-07, F12 | VoiceOver | on parcourt Aujourd'hui et une ligne du journal | la photo, l'origine (GPS ou saisie) et l'action principale sont annoncées | relecture des libellés + essai simulateur |

## 4. Ordre de travail

1. A-REQ-09 (CI) et A-REQ-00 (backlog) : petits, ils rendent le reste vérifiable.
2. Commit de Journal A et Profil A, avec leurs captures.
3. A-REQ-01 et A-REQ-02 (introduction), dès que D3 est tranchée.
4. A-REQ-03 et A-REQ-04 (race), dès que D1 est tranchée. Le plus gros morceau du lot.
5. A-REQ-08 (photo), avant de demander à quiconque d'importer de vraies photos.
6. A-REQ-06 et la matrice de captures (section 6), en dernier, sur le build final.

## 5. Hors périmètre

- Sélecteur d'espèce, renommage `Dog` en `Pet` (décision D9).
- Photo par race, illustration par race.
- Mode sombre (décision D4).
- Résumé de balade et écran de balade en direct : ils suivent déjà DESIGN-SYSTEM, revus plus tard.
- Toute suggestion ou routine dépendant de la race.

| A-AC-17 | REQ-10 | une photo de chien portrait où le chien est haut dans le cadre | on ouvre Aujourd'hui | la tête est visible, pas coupée | unitaire (géométrie) + capture. **Détection Vision : vérifiée sur Mac seulement** (les trois photos y donnent un chien, boîte et point visé cohérents) ; **non exercée sur simulateur** (Vision y échoue : « Could not create inference context ») **ni sur iPhone**. Sur simulateur, c'est le repli qui recadre. |

## 6. Matrice de captures de fin de lot

Même build, simulateur iPhone 17e, mode clair. Pour chaque cas : Aujourd'hui, Journal, Profil.

| Cas | Données |
|---|---|
| Installation neuve | aucun chien |
| Premier chien | un chien, sans photo, sans balade |
| Usage normal | un chien avec photo, balades GPS et manuelles |
| Nom long | « Pépite de la Vallée Verte » |
| Plusieurs chiens | trois chiens, dont un sans photo |
| Foyer | balades d'un autre membre et doublon signalé |
| Grand texte | taille d'accessibilité maximale |

Les photos de test ne sont jamais livrées dans l'app. Le réglage `TRUFFLO_DEMO_PHOTO` (DEBUG
seulement) les injecte dans le mode démo. Trois photos libres de droits (Wikimedia Commons, licence
relue au moment du téléchargement, le 2026-10-07) :

| Fichier Commons | Licence | Auteur | Sert à |
|---|---|---|---|
| `Blue merle border collie.jpg` | CC0 | Hehehefein | portrait 3:4, chien haut dans le cadre |
| `Mixed-breed dog black lying.jpg` | domaine public | Schapenlover (Wikipédia néerlandaise) | paysage, chien noir, croisé |
| `Sunny the German Shepherd puppy (2009).jpg` | domaine public | Duró Sándor | portrait 3:4, visage qui remplit le cadre |

Ce sont des photos d'animaux de particuliers : on les utilise pour des captures, pas comme des
photos de chiens de l'app. Les vraies photos de chien de Guillaume restent à faire pour la dernière
passe, parce qu'une photo de téléphone du quotidien se comporte autrement.

## 7. Décisions dont dépend ce lot

D1 (catalogue), D3 (texte de l'introduction), D4 (mode sombre), D8 (plusieurs chiens), D9 (espèces).
