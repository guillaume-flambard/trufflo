# Lot A2 : Aujourd'hui, direction « Carnet »

Suite de A-REQ-07 (cohérence des trois écrans refaits). Décision de Guillaume du 2026-10-07 :
direction B (« Carnet ») retenue après comparaison avec A (« Plein cadre »). Maquettes : image
envoyée en session, non versionnée (HTML avec la photo d'Oslo).

## Objectif

Aujourd'hui dit la semaine en un coup d'oeil, sans photo plein cadre : un chiffre, sept jours, la
dernière balade. Le chien est présent par un portrait, pas par un décor. L'écran ne fixe aucun
objectif et ne compte aucun manque.

## Sources lues (docs-first)

| Source | Ce qu'elle impose ici |
|---|---|
| Apple, *Adopting Liquid Glass*, developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass | Le verre reste sur la navigation et les contrôles (onglets, bouton). Le chiffre, les ronds et la ligne de balade sont du contenu : pas de verre. Pas de verre empilé. |
| `~/.agents/skills/apple-liquid-glass-design` | Même règle, composants système d'abord, Reduce Motion et Reduce Transparency testés. |
| Apple, `contentTransition(.numericText)`, `sensoryFeedback`, `phaseAnimator` | Transition du chiffre quand il change, haptique légère, animation à phases sobre. |
| `~/.agents/skills/swiftui-specialist` (Apple) | `@Observable`, identité des `ForEach`, pas de closure dans `@Entry`, localisation par `LocalizedStringResource`. |
| `~/.agents/skills/impeccable` (`ios.md`, `craft-floor.md`) | Dynamic Type par styles, pas de tailles fixes ; 44 pt de cible ; pas de gabarit « grand chiffre, petite étiquette, stats, accent » : voir A2-REQ-03. |
| `docs/ART-DIRECTION.md` §3 | Palette marque conservée (forêt, sable, pêche en une seule touche), SF Rounded pour l'identité et les chiffres, pas de carte « statistiques », pas de capitales d'étiquette, pas de point médian. |

Limite : les finitions des grandes apps (Fitness, Strava, Gentler Streak) n'ont pas pu être lues en
détail ; une seconde recherche est consignée dans `.agent/project/07-evidence.md`. Rien ci-dessous
n'est présenté comme « ce que fait Apple Fitness ».

## Exigences

**A2-REQ-01, la semaine est calendaire.** La semaine va du lundi au dimanche (France), pas des sept
dernières 24 h. Le chiffre, la phrase et les ronds disent la même chose.

**A2-REQ-02, un rond par jour.** Plein : au moins une balade terminée ce jour-là, la sienne.
Vide : aucune. Le jour courant est cerné de pêche, qu'il soit plein ou vide. Un jour à venir est
estompé. Aucun rouge, aucun « raté », aucune série, aucun objectif.

**A2-REQ-03, le chiffre porte la phrase.** Le nombre de balades de la semaine est le titre de
l'écran, composé avec la phrase « balades cette semaine » et les sept ronds comme un seul objet
(le chiffre au-dessus, ses jours dessous), pas comme une carte de statistiques ni un chiffre
décoré d'une étiquette. Le temps total vient en une ligne secondaire.

**A2-REQ-04, la semaine vide est dite sans zéro.** Zéro balade cette semaine : pas de « 0 ». La
phrase devient « Pas encore de balade cette semaine. », les ronds restent (vides, jour courant
cerné).

**A2-REQ-05, le chien est un portrait.** Avec photo : portrait rond de 64 pt (le même rond que
le Journal et Mes chiens, pas le carré arrondi de la maquette), recadré sur l'animal (`FocalCrop`),
nom en `title`, race ou « Prêt pour la balade » dessous. Sans photo : pas de visage
inventé, le nom seul et l'invitation « Ajouter une photo de X ». Plusieurs chiens : « N chiens » et
leurs prénoms.

**A2-REQ-06, la dernière balade garde sa ligne et son tracé.** Réutilise `WalkActivityCard`
(fil vertical, tracé réel d'une balade GPS, rien d'inventé pour une balade déclarée).

**A2-REQ-07, un seul moment de mouvement.** Le chiffre roule jusqu'au nombre de la semaine à la
première apparition de l'écran, puis seulement quand il change (`numericText`). Rien ne boucle.
Sous Réduire les animations : mise à jour immédiate. Deux ajouts système, sans composant sur
mesure : la barre d'onglets se réduit quand l'écran défile (`tabBarMinimizeBehavior`), et
« Démarrer une balade » donne une haptique légère (`sensoryFeedback`).

**A2-REQ-08, accessibilité.** Dynamic Type jusqu'aux tailles d'accessibilité : le chiffre suit
`largeTitle` (échelle bornée), les ronds passent sur deux rangées plutôt que de rétrécir. Un seul
élément VoiceOver pour la semaine : « 4 balades cette semaine. Sorties : lundi, mercredi, jeudi,
samedi. Aujourd'hui : dimanche, pas encore de balade. » Cibles de 44 pt là où il y a une action.

**A2-REQ-09, rien n'est cassé.** Identifiants d'accessibilité des parcours UI conservés
(`today.addPhoto`, `walk.manual.add`, `Démarrer une balade`). Les 8 parcours et 250 tests restent
verts.

## Critères d'acceptation

| ID | Exigence | Quand | Alors | Preuve |
|---|---|---|---|---|
| A2-AC-01 | REQ-01 | un mardi, deux balades lundi, une mardi, une dimanche dernier | 3 balades, jours L et M pleins, le dimanche passé exclu | unitaire |
| A2-AC-02 | REQ-01 | un dimanche à 23 h 30, une balade finie à 23 h 10 | elle compte dans la semaine en cours | unitaire |
| A2-AC-03 | REQ-02 | un jour sans balade avant aujourd'hui | rond vide, jamais d'état d'échec | unitaire (le modèle n'a que plein, vide, courant, à venir) |
| A2-AC-04 | REQ-02 | aujourd'hui, avec et sans balade | cerné de pêche dans les deux cas | unitaire + capture |
| A2-AC-05 | REQ-04 | aucune balade cette semaine | pas de « 0 », la phrase vide, sept ronds | unitaire + capture |
| A2-AC-06 | REQ-05 | chien avec photo, sans photo, plusieurs chiens | portrait / invitation / « N chiens » | capture |
| A2-AC-07 | REQ-03, REQ-08 | taille d'accessibilité maximale | rien tronqué ni superposé, ronds sur deux rangées | capture |
| A2-AC-08 | REQ-08 | VoiceOver | un élément, phrase complète | inspection de l'arbre d'accessibilité |
| A2-AC-09 | REQ-07 | Réduire les animations | pas d'animation du chiffre | inspection du code + essai |
| A2-AC-10 | REQ-09 | les parcours UI | verts | `gps-journeys.sh all` + `TruffloFast` |

## Hors périmètre

Mode sombre (D4), onglets Journal et Mes chiens, widgets, refonte de l'écran de balade en direct.
Le titre « Journal » garde son compte sur sept jours glissants jusqu'à une décision séparée : il
faudra l'aligner sur la semaine calendaire (point ouvert, noté ici pour ne pas l'oublier).
