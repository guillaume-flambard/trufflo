# Trufflo

Le journal des balades d'un chien, tenu par une personne ou par un foyer, et des sorties collectives
dans une ville pilote. Ce fichier fixe le vocabulaire : un mot, un sens, à l'écran comme dans le code.

## Le chien et ses balades

**Chien** :
L'animal suivi par le journal, décrit seulement par ce que la personne déclare (nom, race, âge, sexe, photo facultative). Chiens seulement au lancement.
_Éviter_ : profil, animal, compagnon

**Balade** :
Un moment où un ou plusieurs chiens marchent avec une personne, gardé dans le journal avec sa durée.
_Éviter_ : sortie, promenade, activité, séance

**Balade suivie** :
Une balade enregistrée en direct par le téléphone, qui peut avoir un tracé et une distance. Valeur stockée : `gps`.
_Éviter_ : balade GPS, suivi GPS

**Balade ajoutée** :
Une balade saisie après coup, avec une durée et sans tracé ni distance. Valeur stockée : `manual`, gardée parce qu'elle est écrite sur chaque iPhone et sur le serveur.
_Éviter_ : saisie manuelle, balade déclarée, balade passée

**Balade en cours** :
Une balade suivie qui n'est pas terminée : elle avance, elle est en pause, ou elle est interrompue.
_Éviter_ : session, enregistrement

**Interrompue** :
L'état d'une balade en cours que l'app a dû arrêter de suivre (permission retirée, app fermée) et qui peut encore être reprise ou terminée avec ce qui est gardé.
_Éviter_ : arrêtée, annulée, perdue

**Tracé** :
Le chemin d'une balade suivie, fait de segments séparés par les pauses et les trous de signal.
_Éviter_ : parcours, itinéraire, trace

**Mesure** :
Ce que le téléphone a réellement capté d'une balade : complète, partielle ou aucune. Une distance absente se dit « non mesurée », jamais zéro.
_Éviter_ : qualité, précision

**Bilan** :
Ce qu'on relit d'une balade juste après l'avoir terminée, avant de fermer.
_Éviter_ : résumé, récapitulatif

**Journal** :
L'ensemble des balades gardées pour une personne et, avec un foyer, celles des autres membres.
_Éviter_ : carnet, historique, fil

**Routine** :
Un rythme de balades que la personne choisit pour un chien et peut mettre en pause. Elle décrit, elle ne fixe jamais d'objectif.
_Éviter_ : objectif, programme, progression, série

## Le foyer

**Foyer** :
Les personnes qui partagent le journal des mêmes chiens. Seuls les bilans des balades y circulent, jamais le tracé par défaut.
_Éviter_ : famille, groupe, équipe

**Membre** :
Une personne d'un foyer, avec un rôle.
_Éviter_ : utilisateur, promeneur, participant

**Rôle** :
Ce qu'un membre peut faire : responsable (gère les membres), contributeur (ajoute ses balades), lecteur (consulte).
_Éviter_ : droit, permission, admin

**Auteur** :
Le membre qui a fait une balade partagée.
_Éviter_ : promeneur, propriétaire

## La communauté

**Sortie** :
Un rendez-vous collectif à une date et un lieu public, organisé dans la ville pilote, auquel d'autres personnes participent avec leur chien.
_Éviter_ : événement, balade de groupe, meetup

**Organisateur** :
La personne qui propose une sortie et la tient sur place.
_Éviter_ : hôte, créateur

**Signalement** :
Une alerte envoyée sur une sortie ou une personne, traitée par le modérateur.
_Éviter_ : report, plainte
