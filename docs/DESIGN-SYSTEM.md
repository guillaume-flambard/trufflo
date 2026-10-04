# Design, UX et mouvement

## Intention

Un carnet de plein air agréable à ouvrir, centré sur la prochaine balade. Pas de tableau de performance, de feed infini ou de catalogue de personnes. La photographie du chien porte l’identité ; les décorations répétées de pattes et les badges de distance ne sont pas nécessaires.

Nom affiché : Trufflo. Signature : « À son rythme. Ensemble. ». Ton calme, concret et non culpabilisant. Code en anglais ; interface française dans le starter et catalogue de chaînes préparé pour l’anglais. Les exemples ne doivent pas être chargés en production.

## Navigation

Trois destinations initiales : Aujourd’hui, Journal, Mon chien/Mes chiens. Compagnons apparaît uniquement dans une zone pilote ouverte. Une session active reste accessible par une bande persistante sur les autres écrans. Préférer les composants de navigation iOS ; pas de panneau latéral conçu pour ordinateur.

## Écrans cibles

| Écran | Contenu principal | Action | États indispensables |
|---|---|---|---|
| Accueil initial | Promesse et création simple du profil. | Ajouter mon chien. | Nom absent, race inconnue, erreur de sauvegarde. |
| Aujourd’hui | Chien, dernière sortie et résumé. | Partir en balade en M1. | Aucun chien, aucune sortie, session active. |
| Enregistrement | Temps confirmé, qualité, carte secondaire. | Pause / Terminer. | Acquisition du signal, perte de GPS, stockage en échec. |
| Bilan | Durée, parcours, qualité, note. | Enregistrer puis partager séparément. | GPS partiel, aucune distance, sauvegarde en cours. |
| Journal | Liste, filtre et bilan simple. | Ouvrir une sortie / ajout manuel. | Vide, données partielles, suppression. |
| Profil | Race, âge, routine, membres autorisés. | Modifier. | Race inconnue, âge approximatif, droits limités. |
| Compagnons | Créneaux réels et points publics. | Demander à participer. | Zone vide, capacité atteinte, sortie annulée. |

M0 ne fait pas semblant de proposer le suivi GPS : l’action est « Ajouter une balade passée ». Le texte de développement expliquant cette limite doit disparaître seulement quand le vrai parcours M1 est livré.

## Palette proposée

Les valeurs sont une direction de marque, pas une validation de contraste : tester chaque couple texte/fond avant livraison.

| Jeton | Clair | Sombre | Usage |
|---|---|---|---|
| `background` | `#F7F8F3` | `#151B18` | Fond principal. |
| `surface` | `#FFFFFF` | `#202A24` | Cartes sobres. |
| `textPrimary` | `#18261E` | `#EDF3EE` | Texte principal. |
| `textSecondary` | `#526158` | `#B1BFB4` | Explications. |
| `brand` | `#286344` | `#8BD0A2` | Action et sélection. |
| `warmAccent` | `#E7B56D` | `#D2A15C` | Accent discret, jamais seul pour porter un statut. |

En M0, les couleurs système suffisent. Introduire les couleurs adaptatives via Assets, pas une multiplication de valeurs codées dans les vues. Le rouge d’erreur doit accompagner un texte explicite.

## Typographie et composition

Police système et styles dynamiques. Titre d’écran natif ; grand indicateur de durée seulement pendant l’enregistrement. Espacement sur base 4/8 points, marges de 16–20 points comme hypothèse de départ. Cibles tactiles de 48 points visées. Aucun texte tronqué dans les tailles d’accessibilité retenues.

Éviter les cadres de carte trop dominants : la commande d’arrêt doit rester facile à atteindre. Le fond cartographique ne doit pas être une condition à l’usage hors réseau.

## Composants à construire progressivement

`DogSwitcher`, `PrimaryWalkButton`, `RecordingStatus`, `MeasurementQualityBadge`, `WalkSummaryCard`, `RoutineSummary`, `EmptyState`, `PrivacyPreview`, puis `OutingCard` à M3. Chaque composant documente ses données, actions, états et identifiants d’accessibilité. Ne pas créer un système de composants abstrait avant ses premiers usages.

## Micro-interactions

| Interaction | Mouvement proposé | Condition |
|---|---|---|
| Démarrage | Transition d’état 160–200 ms et retour haptique discret. | Après création réussie de la session. |
| Pause / reprise | Changement de libellé et état, 120–160 ms. | L’action ne dépend pas de la fin de l’animation. |
| Sauvegarde | Confirmation légère, sans confettis. | Seulement après écriture confirmée. |
| Ouverture d’un bilan | Transition système ou 180–220 ms. | Respecter Reduce Motion. |
| Mise à jour du temps | Chiffres stables ; transition limitée. | Pas de défilement qui distrait de la promenade. |
| Carte | Recentrage explicite. | Ne pas recentrer automatiquement après déplacement manuel. |

Pas d’animation permanente du bouton principal, de vibration répétée, de récompense pour distance accrue ou de héros animé masquant une erreur. Avec réduction des animations, préférer une mise à jour immédiate ou une opacité très brève.

## Microcopie canonique

« Aucune balade enregistrée » plutôt que « Votre chien n’est pas sorti ». « Parcours enregistré » plutôt que « Distance exacte de votre chien ». « Une partie du parcours n’a pas été mesurée » plutôt que « Tout est sauvegardé » après un trou. « Routine choisie » plutôt que « Objectif santé ».

« Reprendre à partir de maintenant » et « Terminer avec les données enregistrées » doivent être des choix séparés après interruption. Un bouton de sortie ne vaut pas consentement à publier.

## Recette visuelle

Captures clair/sombre, grand texte, VoiceOver, petites et grandes tailles d’iPhone, états vides et erreurs. Vérifier une main, doigts mouillés/saisie difficile uniquement par observation prudente d’usage réel, pas par une épreuve risquée. Une interface agréable ne prouve pas la précision GPS ni la sécurité d’un lieu.
