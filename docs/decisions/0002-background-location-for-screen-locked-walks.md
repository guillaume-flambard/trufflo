# 0002. Localisation en arrière-plan pour une balade écran verrouillé

Status: Proposed

Contexte

Le PRD place « écran verrouillé » dans la recette de F02 et dans la porte de
M1. Quand l'écran se verrouille, l'application passe en arrière-plan : une
application autorisée en When In Use ne reçoit plus les points sans mode
arrière-plan. La documentation Core Location d'Apple est sans équivoque :

> Setting [`allowsBackgroundLocationUpdates`] to `true` but omitting the
> `UIBackgroundModes` key and `location` value in your app's `Info.plist`
> file is a fatal error that terminates the app.

Côté Xcode, `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` existe parmi
les 94 clés générées supportées ; `INFOPLIST_KEY_UIBackgroundModes` n'y
figure pas (`E-004`).

Décision

Le chantier 2 active la localisation en arrière-plan. Les deux éléments vont
ensemble, dans cet ordre : d'abord `UIBackgroundModes = location`, ensuite
`allowsBackgroundLocationUpdates = true`. Le T20 est une probe explicite de
mécanisme avant tout code de capteur.

Conséquences

- Si le mécanisme par `Info.plist` + `INFOPLIST_FILE` s'avère incompatible
  avec le groupe synchronisé du projet, c'est un blocage à escalader, pas à
  contourner en mettant la propriété seule.
- Aucune permission Always n'est demandée : le mode arrière-plan s'appuie
  sur When In Use, conformément à `LOCATION-ENGINE` §2.
- La valeur reste à confirmer par une lecture du bundle construit avant
  d'écrire la moindre ligne qui positionne la propriété.
