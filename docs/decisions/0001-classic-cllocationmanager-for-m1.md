# 0001. Core Location classique pour M1

Status: Accepted

Contexte

`docs/LOCATION-ENGINE.md` décrit deux voies pour la localisation en
arrière-plan : le `CLLocationManager` historique avec
`allowsBackgroundLocationUpdates`, et les sessions modernes
`CLServiceSession` / `CLBackgroundActivitySession`, explicitement rangées en
« voie alternative documentée, à décider séparément » [S05]. Le code livré
au chantier 1 ne contient aucun appel Core Location (`E-007`), donc rien ne
pousse vers l'une ou l'autre.

Décision

M1 utilise `CLLocationManager` : un `LocationProviding` le cache derrière un
seam, avec un adaptateur en production et un faux en test.

Conséquences

- La voie choisie est celle qui a une recette écrite et des hypothèses de
  filtrage déjà posées ; on ne valide qu'une approche à la fois.
- `pausesLocationUpdatesAutomatically` est réglé à `false` pendant la
  session, ce qui supprime l'arbitrage entre pause matérielle et pause
  métier.
- La question `CLServiceSession` reste ouverte en T35 et peut encore être
  tranchée après les mesures de terrain.
