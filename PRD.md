# PRD — Trufflo, iPhone natif

**Version 0.2 — 4 octobre 2026**  
**Signature : À son rythme. Ensemble.**  
**Statut : proposition à construire et à tester.**

## 1. Décision et promesse

Trufflo est le journal de balades du chien, partagé avec ses proches puis ouvert à une communauté locale volontaire. On documente les sorties, on comprend sa routine et on trouve des compagnons de promenade sans transformer le chien en compétiteur.

Cette version remplace le démarrage React Native/Expo par **SwiftUI, Swift, SwiftData, Core Location et MapKit sur iPhone**. Android reste une extension future nécessitant son propre client ou un nouvel arbitrage ; le choix natif ne le prend pas en charge automatiquement. Les modèles d’échange doivent néanmoins éviter une dépendance aux identifiants internes SwiftData.

Trufflo reste un nom de travail. Domaine, boutiques et antériorités de marque n’ont pas été validés. L’application dite « Gasson » n’est toujours pas identifiée avec certitude ; son prix ne doit pas être inventé.

## 2. Problème et différence à prouver

Hypothèses : un propriétaire veut retrouver les promenades sans appareil supplémentaire ; un foyer veut mieux se répartir les sorties ; certains utilisateurs apprécient de rejoindre un petit groupe local. Le retour « une autre app est trop chère » ne prouve ni une demande générale ni un prix acceptable.

Pawmi et PlayDogs annoncent déjà du suivi et des fonctions communautaires. Le produit n’est donc pas fondé sur une combinaison supposée inédite. Le pari à tester est la simplicité, la qualité du journal, la confidentialité et la présence réelle de compagnons dans une zone donnée. Les fonctionnalités annoncées ne constituent pas une mesure de qualité ou de rentabilité des concurrents. [S12, S13]

## 3. Cibles et scénarios

Cible principale du pilote : propriétaires adultes d’un ou plusieurs chiens en France. Le suivi individuel ne dépend pas d’un compte ni d’un réseau social. Le pilote de rencontres communautaires est réservé aux adultes, comme décision produit ; ce n’est pas une qualification juridique universelle de l’app.

Scénarios fictifs de référence : Camille suit les promenades d’Oslo ; Sam et Alex consultent le journal partagé de Nala ; Lou recherche pour Tao une balade calme en petit groupe. Les noms sont des exemples, pas des clients rencontrés.

Le travail principal à accomplir : « Je retrouve ce qui a été enregistré pour mon chien et je prépare la prochaine sortie, seul, avec mes proches ou avec des compagnons choisis. »

## 4. Périmètre par livraison

**M0 : socle natif et journal manuel.** Le starter fourni couvre un profil nom/race, une saisie manuelle, un journal et l’effacement global local. C’est une base d’intégration, pas la V1 terminée.

**M1 : alpha individuelle.** Profil enrichi, enregistrement GPS fiable, récupération, bilan, routines choisies, export, suppression et interface soignée.

**M2 : V1 privée/familiale.** Plusieurs contributeurs autorisés partagent les synthèses, avec synchronisation contrôlée et sans divulgation automatique des trajets précis.

**M3 : V1.1 communautaire.** Créneaux, demandes de participation et discussion liée à la sortie dans une seule zone, avec modération opérationnelle préalable.

**M4 : économie.** Offre payante après mesure de l’usage et des coûts.

Hors périmètre : rencontres amoureuses, carte de personnes en direct, classement de chiens, diagnostic, objectifs vétérinaires automatiques, faux pas canins, collier propriétaire, marketplace, publicité comportementale et agent IA. App Intents, widgets, Apple Watch et Live Activities restent des extensions à autoriser, pas des prérequis de M1.

## 5. Exigences fonctionnelles

### F01 — Profil canin

Nom requis ; photo, âge et race facultatifs. États connus : race renseignée, croisé, race inconnue. Accepter un âge approximatif sans forcer une date fictive. Ajouter des préférences déclarées de sortie, pas une certification de comportement.

M0 permet le nom et une race saisie librement. M1 ajoute âge/photo, édition et suppression contrôlée. Le changement de race ne modifie jamais un objectif sans choix de l’utilisateur. Les profils incomplets ne perdent pas les fonctions essentielles.

### F02 — Enregistrement réel

Démarrer, mettre en pause, reprendre et terminer une balade. Une seule session active par appareil. Les états sont persistés ; l’écran ne doit pas être la source de vérité. Un double appui ne crée pas deux sessions.

Après accueil et permissions, démarrer en deux actions au maximum. Afficher immédiatement l’état « Recherche du signal » sans attendre le réseau. Le fond de carte est facultatif pour enregistrer. Le GPS ne démarre pas au simple lancement de l’application.

Recette : simulation de coupure réseau, écran verrouillé, permission révoquée, arrêt/reprise et fermeture forcée. La reprise propose les dernières données persistées sans inventer le trajet manquant.

### F03 — Mesures et origine

Afficher durée confirmée, parcours enregistré du téléphone et qualité de mesure. Une sortie manuelle n’a pas de distance GPS. Les pas du propriétaire ne sont pas les pas du chien ; sans capteur canin adapté, aucun chiffre de pas canins réellement mesurés n’est produit.

Séparer les états `gpsRecorded`, `gpsPartial`, `manual` et `unavailable`. Aucune donnée n’est équivalente à « zéro activité ». Les coordonnées sont segmentées ; les trous ne sont pas reliés en ligne droite dans le bilan.

Recette : source de mesure conservée dans la fiche, les agrégats et les exports ; distance absente distinguée d’une vraie distance mesurée nulle.

### F04 — Routine

Le journal fonctionne sans objectif. Le propriétaire peut définir ses propres repères de durée ou de créneaux, les suspendre et les modifier. Une bibliothèque de prescriptions chiffrées par race n’est pas livrée. Les besoins dépendent de plusieurs caractéristiques du chien ; la race seule ne suffit pas. [S10]

Une future recommandation quantitative nécessite des règles revues par un vétérinaire, versionnées et testées. La V1 décrit les balades d’une période, sans les comparer à une autre période ni à un autre chien. Aucune hausse automatique, obligation de rattrapage ou notification culpabilisante.

Recette : suspendre une routine n’altère pas l’historique ; une habitude observée ne devient pas une prescription.

### F05 — Journal et corrections

Historique filtrable par chien et par période. Détail : auteur, dates, durée, mesure disponible, note et origine. Ajout manuel accessible même sans permission de localisation. Date future, durée non finie et données incohérentes sont rejetées avec un message utile.

Une journée vide signifie « aucune sortie enregistrée ». Les corrections restent identifiées et recalculent les agrégats. Le changement de fuseau n’allonge pas une promenade ; les durées actives utilisent une horloge monotone pendant l’exécution.

### F06 — Plusieurs chiens

Une session porte plusieurs participations. Deux chiens dans une sortie de 30 minutes donnent deux participations canines de 30 minutes, mais toujours une seule sortie de 30 minutes au niveau du foyer.

Les noms présents au moment de la balade peuvent être conservés comme libellés historiques ; une suppression de données doit les traiter explicitement. Aucun doublon introduit par une relance de synchronisation.

### F07 — Export et effacement

Export local gratuit des synthèses et, lorsqu’ils existent, des vrais tracés. Pas de GPX fabriqué pour une saisie manuelle. Suppression d’une sortie, d’un profil et du journal, avec recalcul cohérent des agrégats.

M0 fournit l’effacement global ; les suppressions ciblées, l’export et la politique de conservation sont des critères bloquants de M1. Les noms historiques et futurs fichiers photo sont inclus dans le périmètre d’effacement.

### F08 — Foyer partagé

Invitation acceptée explicitement ; rôles responsable, contributeur et lecteur. Un contributeur peut corriger sa sortie, pas celle d’un autre sans droit explicite. Les synthèses sont partagées, les tracés précis restent privés par défaut.

Une révocation bloque les nouvelles lectures serveur. Elle ne garantit pas l’effacement instantané d’une copie hors ligne ou d’informations déjà vues. Le client purge les caches au prochain contact. Le serveur reste l’autorité des droits.

### F09 — Proposer une balade locale

Un événement indique un créneau, une durée indicative, un point public, un organisateur, des préférences et des capacités humaines/canines. Découverte dans une zone choisie, sans inférence de domicile. Les premières propositions sont réelles et contrôlées manuellement.

Classement explicable par proximité de la zone, horaire, places et préférences. Pas de score de compatibilité entre chiens, ni d’exposition permanente de la position des personnes.

### F10 — Participation et échange

Demande, acceptation, refus, retrait, annulation et présence déclarée sont des états distincts. La capacité est vérifiée dans une transaction serveur. Une inscription ne vaut pas présence réelle.

Conversation limitée à l’événement ou à un lien réciproque accepté. Aucun message spontané à une personne inconnue hors de ces contextes. Une annulation notifie les inscrits ; un changement de lieu ou d’heure permet de se retirer.

### F11 — Modération

Signalement de profil/message/événement, blocage immédiat, retrait effectif, suspension et procédure de recours. Un responsable nommé assure le pilote. Pas de lancement social avec une file de signalements non surveillée.

Apple prévoit des mécanismes de filtrage, de signalement et de blocage ainsi qu’un contact pour les apps à contenus utilisateurs. La conformité doit être revue avant publication ; aucune approbation App Store n’est garantie. [S09]

### F12 — Accessibilité et état de l’interface

Tailles de texte adaptables, VoiceOver, boutons suffisamment grands, statut non fondé sur la couleur seule, prise en compte de la réduction des animations et usage d’une main. Écrans dédiés aux états vides, erreur de stockage, refus de permission, mode hors ligne et parcours partiel.

### F13 — Confidentialité

Le suivi est actif uniquement durant une session autorisée. Aucun tracé dans les données d’analyse, les logs publics, les profils communautaires ou les cartes partagées du pilote. Aucun SDK publicitaire. Revoir le comportement des sauvegardes iOS et des demandes de tuiles cartographiques avant une promesse « tout reste sur l’appareil ».

Le registre des traitements, les bases légales et les durées doivent refléter les usages réels. Les recommandations CNIL soulignent la finalité, la minimisation et la distinction entre permission technique et usages ultérieurs. [S08]

### F14 — Qualité de livraison

Une fonction n’est terminée qu’avec preuve appropriée : test métier, intégration native, parcours UI ou essai terrain. Le contrôle syntaxique n’est pas une compilation iOS. Les tests simulés de position ne valident pas le suivi écran verrouillé.

## 6. Parcours et navigation

Aujourd’hui : dernier enregistrement, sélection du chien, action principale. Pendant la balade : durée, état de mesure, pause et fin ; la session reste accessible depuis les autres écrans. Bilan : données mesurées, lacunes éventuelles, note facultative et sauvegarde privée. Journal : liste et bilans. Mon chien/Mes chiens : profil, routine et membres autorisés.

Compagnons apparaît uniquement lorsque le pilote existe pour l’utilisateur. Ne pas lancer une tab vide « bientôt disponible ». En M0, l’action principale honnête est « Ajouter une balade passée » ; elle est remplacée par « Partir en balade » quand le suivi est réellement branché.

## 7. Données, technique et risques

SwiftData gère le journal local. Les modèles métier et DTO n’importent pas SwiftUI ou SwiftData. Core Location est derrière un adaptateur. MapKit affiche les segments mais ne calcule pas la durée ni la distance métier. L’orchestrateur de session possède les transitions et attend la persistance avant les confirmations critiques.

Le choix backend de M2 est proposé, non provisionné : PostgreSQL/Supabase peut gérer identité, synthèses et autorisations. Le périmètre doit rester un monolithe modulaire. Aucune clé serveur privilégiée dans l’application.

Risques majeurs : perte de données, mauvaise compréhension des mesures, GPS imprécis à l’arrêt, batterie, communauté vide, coût de modération et faible disposition à payer. La solution n’est pas d’ajouter de nouveaux onglets avant de mesurer ces problèmes.

## 8. Validation produit

D’abord une dizaine d’entretiens décrivant les habitudes réelles et l’outil existant. Identifier la référence appelée « Gasson » avant d’en tirer un benchmark. Tester les tâches « enregistrer », « retrouver », « partager avec un proche », puis comparer avec les outils effectivement utilisés.

Pilote individuel proposé : 30 à 50 foyers. Pilote social ultérieur : une zone, un relais local, environ six événements réels pour observer les premiers usages. Ces nombres sont des plans d’expérimentation, pas des utilisateurs recrutés.

Seuils exploratoires, non sectoriels : activation dans les 48 h ≥ 60 % ; réutilisation entre J7 et J13 ≥ 40 % ; entre J28 et J34 ≥ 25 % des activés observables ; nouvelle participation dans les 30 jours ≥ 30 % des premiers participants ayant une fenêtre complète. Afficher les effectifs et les incertitudes.

Indicateur principal : foyers qui enregistrent une sortie sur au moins trois jours distincts dans la semaine. C’est une mesure d’usage, pas une norme de promenade canine. Aucun suivi clandestin pour prouver une présence.

## 9. Économie proposée

Gratuit : suivi, historique, saisie manuelle, routine choisie, export/suppression, partage avec un deuxième membre et protections sociales. Plus : statistiques longues périodes et outils d’organisation/foyer étendu lorsqu’ils sont demandés.

Prix de test : **2,99 €/mois ou 19,99 €/an**. Pilote gratuit. Aucune conversion prévue ni rentabilité revendiquée. Mesurer le coût des cartes, du support, des messages et de la modération avant de fixer le modèle.

Les achats, lorsqu’ils sont autorisés, passent par une intégration conforme aux règles alors applicables, avec restauration et tests d’expiration des droits. Ne pas développer cette intégration au détriment du journal fiable.

## 10. Portes de sortie

M0 : projet iOS compilé, tests natifs lancés, journal manuel vérifié après redémarrage. M1 : vraie balade écran verrouillé, interruption récupérée sans fiction, export/suppression et tests de vie privée. M2 : deux comptes coopèrent sans fuite ni double comptage. M3 : protections sociales et modération disponibles avant ouverture. M4 : rétention et coûts mesurés.

Les détails de recette et les responsabilités sont dans BACKLOG, TEST-PLAN et AGENTS. Une case non vérifiée reste ouverte ; on ne remplace jamais une preuve manquante par le mot « terminé ».
