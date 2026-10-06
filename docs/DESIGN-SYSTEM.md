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
| Enregistrement | Carte plein écran ; une surface : titre chien, état GPS, durée, distance. | Pause (puis Reprendre / Terminer en pause). | Acquisition du signal, interruption, stockage en échec. |
| Bilan | Durée, parcours, qualité, chiens, note éditable. | Terminé (enregistre la note). | GPS partiel, aucune distance, sauvegarde en cours. |
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

Pendant l’enregistrement, la carte est la surface de l’écran, pas un cadre à l’intérieur d’un empilement : les mesures et les commandes restent lisibles au-dessus, sur une seule surface en verre teinté forêt (opaque sous Réduire la transparence), et l’action primaire demeure atteignable d’une main. Le fond cartographique n’est jamais une condition à l’usage hors réseau : une tuile absente laisse les mesures et les contrôles intacts.

## Écran de balade : une surface, une action

Référence structurelle : l’écran Record de Strava (pas une copie visuelle). Cible : simplicité d’enregistrement Strava × Apple Plans × chaleur Trufflo. La personne marche et tient une laisse : l’écran ne demande presque rien à lire ni à décider.

Trois éléments au-dessus de la carte, pas plus : un chevron rond (réduire), un cercle rond (recentrer), et **une seule surface de contrôle** en Liquid Glass en bas. La surface empile : en-tête (titre chien, mot GPS), deux mesures, ligne d’action. Le contenu est chaud (bilan sur sable), les contrôles sont en verre. La carte garde 75-85 % du champ visuel (mesuré 22,5 % de hauteur pour la surface en enregistrement, 27 % en interruption avec le lien Réglages, iPhone 17e).

### Enregistrement

| Contrôle | Pourquoi il existe |
|---|---|
| Carte | C’est l’écran. Le tracé est la seule chose à regarder en marchant. |
| Chevron (haut gauche) | Réduire pour revenir à l’app sans décider de la balade. Icône, pas « Fermer » : rien ne se ferme. |
| Titre « Balade avec Oslo » | Confirmer de qui il s’agit, en un coup d’œil, sans puce ni badge. |
| Mot GPS (Actif / Recherche / Faible) | La seule information d’état utile en marchant. Un point et un mot, jamais la couleur seule. |
| Durée | Mesure primaire 1. |
| Distance | Mesure primaire 2. « Non mesurée » plutôt que 0. Pas d’allure : métrique sportive, hors recherche utilisateur. |
| Recentrer (cercle, bas droite) | La carte ne se recadre jamais seule après un geste. Visible dès qu’un point est tracé. |
| **Pause** | L’unique action primaire. Terminer n’apparaît pas : finir est une décision de l’arrêt, pas de la marche. |

Retirés : champ de note, crayon, « Corriger », menu « … », puce chien, pastilles d’état, bannière. La note se saisit au bilan.

### Pause

Mêmes éléments ; le mot GPS lit « En pause » ; la ligne d’action devient **Reprendre** (primaire, forêt, pleine largeur) + **Terminer** (discret, verre, contour). Poids visuel inégal volontaire : reprendre est fréquent, terminer est terminal. Terminer ouvre toujours une confirmation (« Terminer et enregistrer la balade ? »).

### Interrompue

État récupérable, jamais « Arrêté ». Le mot GPS lit **« Interrompue »**. Un message temporaire (8 s, verre, sous le chevron) dit la cause éventuelle puis « Données conservées jusqu’au dernier point enregistré. » Pas de bannière permanente ni d’alerte modale. Actions : **Reprendre** (accessibilité : « Reprendre à partir de maintenant ») + **Terminer** (« Terminer avec les données enregistrées », confirmé par une feuille du même nom). Un seul contrôle conditionnel : « Ouvrir les réglages », uniquement quand la cause est un refus de permission, seule cause que Réglages répare.

### Bilan

Écran chaud (sable), après la fin confirmée, dans la même couverture. Contenu : carte figée du parcours (si au moins deux points), durée et distance, qualité avec sa phrase canonique (« Une partie du parcours n’a pas été mesurée. »), chiens, champ de note. Une action : **Terminé**, qui enregistre la note (500 caractères max.) puis ferme. C’est ici, et seulement ici, qu’on écrit.

### Libellés d’accessibilité

Visible court, parlé complet : Pause → « Mettre en pause » ; Reprendre → « Reprendre la balade » / « Reprendre à partir de maintenant » ; Terminer → « Terminer la balade » / « Terminer avec les données enregistrées » ; chevron → « Réduire la balade » ; signal → « Signal GPS : Actif ». Les parcours UI s’appuient sur ces libellés et sur les identifiants `walk.*`.

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
| Carte | Recentrage explicite par un contrôle dédié. | Le suivi de la position s’arrête dès que la personne déplace la carte ; elle la reprend quand elle le décide. |

Pas d’animation permanente du bouton principal, de vibration répétée, de récompense pour distance accrue ou de héros animé masquant une erreur. Avec réduction des animations, préférer une mise à jour immédiate ou une opacité très brève.

## Microcopie canonique

« Aucune balade enregistrée » plutôt que « Votre chien n’est pas sorti ». « Parcours enregistré » plutôt que « Distance exacte de votre chien ». « Une partie du parcours n’a pas été mesurée » plutôt que « Tout est sauvegardé » après un trou. « Routine choisie » plutôt que « Objectif santé ».

« Reprendre à partir de maintenant » et « Terminer avec les données enregistrées » doivent être des choix séparés après interruption. Un bouton de sortie ne vaut pas consentement à publier.

## Recette visuelle

Captures clair/sombre, grand texte, VoiceOver, petites et grandes tailles d’iPhone, états vides et erreurs. Vérifier une main, doigts mouillés/saisie difficile uniquement par observation prudente d’usage réel, pas par une épreuve risquée. Une interface agréable ne prouve pas la précision GPS ni la sécurité d’un lieu.
