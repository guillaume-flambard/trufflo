# Confidentialité et sécurité du produit

## Principes bloquants

Aucune surveillance permanente, publication de domicile, carte de personnes en direct ou réutilisation publicitaire des déplacements. Le mode local ne demande pas de compte. La future synchronisation de synthèses est explicitement choisie. Le refus de localisation ne supprime pas l’utilité du journal.

La CNIL rappelle la nécessité de définir finalités, minimisation, information et durée, ainsi que la différence entre autorisation système et usages ultérieurs des données. Le projet doit documenter son propre fondement et ne pas considérer un écran de permission comme une conformité complète. [S08]

## Protection locale et sauvegardes

Le starter désactive CloudKit géré par SwiftData, mais n’a pas vérifié les sauvegardes système iOS ni la protection effective des fichiers sur appareil. Ces vérifications sont obligatoires avant de promettre une confidentialité locale donnée. [S04]

Les réglages doivent permettre la protection appropriée des données tout en soutenant une session explicitement active écran verrouillé. Tester le magasin principal, ses fichiers annexes et les exports. Ne pas laisser de coordonnées dans un cache de débogage, un nom de fichier, une capture publicitaire ou un rapport de crash.

La suppression utilisateur est une suppression applicative des données contrôlées. Ne pas promettre d’effacement cryptographique de toutes les sauvegardes ou de toutes les copies déjà consultées.

## Analyse et observabilité

M0 : aucun SDK d’analyse externe. M1 : événements minimaux éventuellement introduits après décision documentée. Autorisés comme catégories : démarrage, fin, interruption, état de qualité, résultat de sauvegarde. Exclus : coordonnées, note libre, photo, adresse, contenu de message, heure quotidienne récurrente liée à une identité publique.

Les logs locaux de diagnostic doivent masquer les données sensibles. Les données de test sont synthétiques, sans trajet réel d’un tiers. Ne pas déposer les exports, bases SwiftData ou captures de trajets réels dans Git.

## Permissions supplémentaires

La photo via sélecteur système ne justifie pas un accès général à la photothèque. Pas de permission de carnet d’adresses pour inviter des proches ; utiliser un mécanisme d’invitation explicite. Pas d’accès HealthKit/Motion pour simuler des pas canins. Les permissions de notifications se limitent ultérieurement aux actions réellement implémentées.

## Bien-être animal

Race, âge et préférences sont des informations déclarées. Aucune inférence médicale, diagnostic ou quantité quotidienne obligatoire. Toute recommandation quantitative future exige une revue vétérinaire préalable ; les besoins ne se résument pas à la race. [S10]

Pas de classement par kilomètres, de récompense pour dépasser une durée, de pénalité de repos ni de comparaison dévalorisante. Une sortie lente peut être une promenade enregistrée complète. Les préférences de groupe ne certifient pas la compatibilité des animaux.

## Social seulement après protections

Le pilote communautaire est réservé aux adultes avec une politique d’âge opérationnelle avant ouverture. Les rencontres amoureuses sont hors de ce pack ; aucun code de matchmaking amoureux, transfert automatique de profil ou accès caché n’est prévu.

Signalement, blocage, retrait serveur, suspension, contact de support et règles de publication sont livrés avant les messages publics. Apple prévoit des protections pour les apps à contenus utilisateurs. [S09]

Un responsable nommé traite les signalements. Objectif exploratoire : examen des signalements ordinaires sous 24 heures dans le pilote, avec procédure prioritaire en cas de risque et horaires de service annoncés. Ne pas présenter l’app comme une assistance d’urgence.

## Contrôles prépublication

Le registre de traitements, les bases légales, les contrats des fournisseurs, les durées, le contact et les réponses aux droits doivent être prêts. Décider, avec une analyse compétente, si une analyse d’impact est nécessaire. Vérifier les déclarations de confidentialité de la boutique contre les flux réellement observés.

Protéger également les photos par retrait des métadonnées géographiques avant publication. Un lieu public proposé affiche sa source et sa date de vérification ; l’app ne garantit jamais sa sûreté permanente. Les rendez-vous ne se déduisent pas des adresses ou trajets privés.
