# Moteur de balade et localisation

## Statut exact

Le noyau de transitions et de géométrie est fourni et testé hors iOS. **L’adaptateur Core Location, le coordinateur natif, la persistance des tracés, MapKit et les essais terrain restent à réaliser.** Aucun bouton du starter manuel ne simule un vrai suivi GPS.

## 1. Pipeline retenu

```text
Action utilisateur
  → WalkCoordinator : vérifie l’état et la permission
  → CoreLocationClient : traduit les callbacks système en LocationFix
  → WalkProgress / TrackAccumulator : transitions et segmentation
  → TrackWriter : écrit points + snapshot cohérent
  → Synthèse observable pour SwiftUI
  → MapKit : projette les segments, sans recalcul métier
```

Le coordinateur possède une session active unique. Il a un identifiant de génération permettant d’ignorer un callback arrivé après un arrêt ou un changement de session. Une reprise après pause utilise un nouveau segment ; aucun point antérieur à la reprise ne peut servir à la relier.

## 2. Configuration M1 proposée

Créer `CLLocationManager` sur le contexte approprié, avec son délégué et un pont de concurrence explicite. Demander When In Use à l’action utilisateur. Configurer l’activité de marche/fitness, une précision adaptée, un `distanceFilter` initial expérimental et un indicateur visible. Les valeurs sont calibrées sur appareils, pas décrétées optimales.

Pour la continuité en arrière-plan, ajouter le mode `location`, puis utiliser `allowsBackgroundLocationUpdates` pendant la session. Arrêter réellement la collecte à Pause, Terminer et en cas de révocation. Le mode Apple de pause automatique ne doit pas faire passer le chien en pause métier lorsqu’il s’arrête pour renifler. [S06]

Pas de demande Always en M1 sans besoin démontré. Pas de service de relance permanente, de contournement des choix de l’utilisateur ou de prétention à continuer après fermeture forcée. Les APIs modernes de sessions Core Location sont une voie alternative documentée, à décider séparément. [S05]

## 3. Permissions et dégradation

| Situation | Comportement |
|---|---|
| Pas encore demandé | Expliquer puis demander lors de l’action de démarrage. |
| Autorisé précisément | Créer la session et attendre des points exploitables. |
| Autorisé approximativement | Expliquer la limite ; durée/journal utilisables, distance éventuellement indisponible. |
| Refusé / restreint | Proposer l’ajout manuel et les réglages, sans boucle de demande. |
| Révoqué pendant la sortie | Arrêter le flux, sauvegarder le connu et afficher une interruption claire. |
| Service système indisponible | Ne pas afficher un tracé ou une progression fictifs. |

La permission technique n’autorise pas automatiquement d’autres usages des trajets, notamment leur publication. [S08]

## 4. Temps et récupération

Le chronomètre visuel peut afficher une projection depuis un ancrage monotone tant que le processus est vivant. Le domaine reçoit les deltas valides ; le stockage conserve régulièrement le confirmé. Les timers de vue ne sont jamais l’unique mécanisme de mesure.

Au lancement à froid, toute session précédemment active est présentée comme interrompue et aucune durée depuis le dernier checkpoint n’est ajoutée. Proposer « Reprendre à partir de maintenant », « Terminer avec les données enregistrées » ou une correction déclarative. Une session terminée n’est jamais ressuscitée.

La preuve de durabilité porte sur la dernière transaction confirmée. Une fermeture entre deux écritures peut faire perdre la portion non persistée ; l’app ne doit ni la reconstruire sans source ni affirmer qu’aucune donnée n’a été perdue.

## 5. Filtrage fourni et limites

Le noyau vérifie valeurs finies, coordonnées valides, précision déclarée et ordre des points. Il démarre un nouveau segment après une perte de signal, un saut impossible ou une pause. La distance utilise une formule géodésique entre points acceptés d’un même segment.

Paramètres initiaux du code : précision maximale 35 m, intervalle maximal 45 s entre deux points reliés, vitesse maximale de liaison 12 m/s. Ce sont **des hypothèses techniques de filtrage**, pas des seuils vétérinaires ni une garantie de qualité GPS.

Le starter ne supprime pas encore la dérive stationnaire. Un test de points identiques ne couvre pas le bruit d’un téléphone immobile. Avant livraison, mesurer les faux mètres à l’arrêt, calibrer le filtre, tester en rue dense et publier les limites. Conserver la version du filtre avec les mesures afin de pouvoir expliquer un recalcul.

Les mesures hors ordre ou doublonnées sont ignorées. Après une pause, le coordinateur filtre aussi les callbacks d’une ancienne génération. Cette responsabilité ne doit pas être laissée au seul ordre des timestamps.

## 6. Persistance et concurrence

En M1, un acteur de stockage possède son contexte. Enregistrer chaque lot reçu dans une transaction bornée, avec séquence, segments, révision et snapshot de durée. Les changements de phase attendent leur écriture. Ne pas conserver toute la promenade dans un tableau mémoire en attendant Terminer.

Définir et mesurer la taille maximale de file d’attente. Une saturation doit se signaler et préserver ce qui est confirmé ; elle ne devient pas une fuite mémoire. Les valeurs `Sendable` traversent les acteurs, pas les objets gérés SwiftData. Les API exactes et leur isolation sont vérifiées dans le SDK local.

Tester protection de fichiers et accès au magasin SwiftData écran verrouillé, y compris les fichiers annexes. Ne pas diminuer silencieusement la protection pour corriger une erreur sans documenter le compromis. Ne pas invoquer une tâche de fond périodique comme garantie d’exécution continue.

## 7. Carte

MapKit affiche une polyline par segment. Deux segments ne sont jamais joints par une ligne implicite. La carte reste secondaire : un fond non téléchargé n’arrête pas l’écriture des points. Les demandes cartographiques peuvent révéler la zone affichée au fournisseur ; elles doivent être décrites dans l’inventaire de données. [S07]

Réglage de rétention du tracé indépendant du résumé. Un export personnel GPX ne contient que les segments disponibles. Une carte de partage communautaire n’affiche pas le tracé privé dans le pilote.

## 8. Porte terrain

Exiger : marche réelle écran verrouillé ; pause pour renifler ; passage sans réseau ; segment GPS incomplet ; refus/révocation de permission ; fermeture forcée puis récupération ; redémarrage ; batterie mesurée ; dérive à l’arrêt. Chaque résultat indique appareil, version système, conditions, mesures et limites.

Objectifs exploratoires : consommation additionnelle médiane ≤ 8 points de batterie par heure face à un témoin comparable ; erreur médiane de distance ≤ 10 % sur parcours de référence dégagés. Ils ne sont pas acquis. Documenter séparément les rues denses et les mauvaises conditions ; ne pas cacher les cas défavorables dans une moyenne globale.
