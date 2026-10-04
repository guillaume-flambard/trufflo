# Plan de test et définition de terminé

## Niveaux de preuve

1. **Domaine Swift** : transitions, entrées et géométrie, testables hors iOS.
2. **Intégration native** : SwiftData, migration, isolation et cycle de l’app.
3. **UI iOS** : navigation, formulaires, accessibilité et permissions.
4. **Terrain** : Core Location réel, batterie, écran verrouillé et interruptions.

Seul le premier niveau et une analyse syntaxique des extraits natifs ont été exécutés lors de la génération de ce pack. Voir VERIFICATION.

## Matrice minimale

| Test | Scénario | Attendu | Exigences |
|---|---|---|---|
| Q01 | Nom vide / race inconnue. | Erreur utile pour le nom ; race inconnue valide. | F01 |
| Q02 | Deux chiens dans une saisie. | Une durée de session, deux participations. | F05–F06 |
| Q03 | Durée négative, non finie, date future. | Rejet sans écriture partielle. | F05 |
| Q04 | Relancement normal après sauvegarde. | Journal persistant. | F05–F14 |
| Q05 | Échec d’ouverture/migration du magasin. | Écran d’erreur sans effacement ni base vide cachée. | F07–F14 |
| Q06 | Double appui Démarrer/Pause/Terminer. | Une session et transitions idempotentes. | F02 |
| Q07 | Permission refusée ou approximative. | Dégradation explicite et saisie manuelle. | F02–F03 |
| Q08 | Téléphone verrouillé pendant une balade. | Données confirmées écrites et bilan vérifiable. | F02 |
| Q09 | Fermeture forcée, puis réouverture. | Session interrompue ; pas de durée fantôme. | F02–F03 |
| Q10 | Callback ancien après pause ou changement de session. | Ignoré, aucun lien entre générations. | F02–F03 |
| Q11 | Points invalides, saut, trou, doublon. | Distance partielle, segments séparés. | F03 |
| Q12 | Téléphone immobile avec GPS bruité. | Dérive mesurée et seuil de release décidé. | F03–F14 |
| Q13 | Réseau indisponible. | Enregistrement indépendant du fond de carte. | F02–F03 |
| Q14 | Objectif suspendu / chien sans objectif. | Journal utilisable, aucune culpabilisation. | F04 |
| Q15 | Export et suppression ciblée. | Données cohérentes, aucun tracé inventé ni restant oublié. | F07 |
| Q16 | Taille de texte, VoiceOver, Reduce Motion. | Actions accessibles et statut compréhensible. | F12 |
| Q17 | Flux réseau/logs/sauvegardes. | Pas de publication ou télémétrie de trajets privés. | F13 |
| Q18 | Membre révoqué / invitation expirée. | Nouveaux accès refusés, caches traités. | F08 |
| Q19 | Dernière place demandée simultanément. | Une décision serveur cohérente, pas de surcapacité. | F09–F10 |
| Q20 | Personne bloquée / contenu retiré. | Pas de nouveaux échanges ; retrait dans l’API. | F11 |

## Concurrence et stockage

Tester les écritures échouées, le stockage faible, les suppressions pendant une consultation, les migrations depuis une fixture antérieure et les lots GPS tardifs. Le couple snapshot/points reste cohérent après rollback. Les objets SwiftData ne sont pas passés entre acteurs pour supprimer artificiellement un avertissement de concurrence.

Tester le journal réel après fermeture/réouverture ; un `ModelContainer` en mémoire ne suffit pas. Les tests qui utilisent `--uitesting` sont isolés et ne doivent jamais effacer le journal réel du développeur.

## Commandes

Lire les destinations réelles via XCODE-SETUP. Exécuter `xcodebuild test` sur un simulateur disponible, puis lancer l’app sur iPhone physique. Conserver `.xcresult`, résumé de version et captures utiles, sans trajet privé dans le dépôt.

Le manifeste optionnel du domaine autorise `swift test -j 2` dans un dossier isolé. Il ne doit pas être ajouté à la cible de l’app ni conduire à compiler le même domaine deux fois.

## Matrice appareil minimale proposée

Au moins deux iPhones de générations différentes, petite/grande taille d’écran si disponible, minimum supporté et système courant pertinent. Nommer précisément ce qui a été testé. Ne pas annoncer toutes les versions prises en charge à partir d’un seul simulateur.

Pour chaque essai terrain : version de l’app, appareil/OS, durée, conditions de réseau et de signal, batterie départ/fin et témoin comparable, interruptions provoquées, résultat, défauts. Les parcours de référence synthétiques ou personnels sont privés ; publier les agrégats de test, pas le domicile des testeurs.

## Seuils exploratoires, non acquis

Démarrage après accueil en deux actions ; retour visuel cible inférieur à 200 ms hors dialogue système ; consommation additionnelle médiane cible ≤ 8 points/heure ; erreur médiane de distance cible ≤ 10 % en contexte dégagé. Définir une mesure propre des mètres fictifs à l’arrêt avant libération de M1. Résultats défavorables conservés séparément, pas noyés dans les moyennes.

## Définition de terminé

Une exigence est reliée à une preuve adaptée. Les échecs et conditions non testées restent visibles. L’absence de crash ne prouve pas que les données sont correctes. Une capture ne prouve pas l’arrière-plan. Une syntaxe valide ne prouve pas la compilation avec les frameworks Apple. Aucun pourcentage de fiabilité global n’est déduit du nombre de tests.
