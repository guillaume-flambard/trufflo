# 0005. Core Location classique maintenu, sessions modernes reportées

Status: Accepted

Contexte

`docs/decisions/0001-classic-cllocationmanager-for-m1.md` a retenu
`CLLocationManager` pour M1 et a laissé la question `CLServiceSession`
ouverte, à trancher après les mesures de terrain (T35). Depuis, le
chantier 2 a livré la boucle complète : adaptateur `CoreLocationProvider`
derrière le seam `LocationProviding`, sept parcours verts dont la
continuité en arrière-plan (E-028), la révocation en cours de session
(E-029) et la relance à froid (E-027). Les mesures de terrain (T16 :
dérive et batterie) restent explicitement hors périmètre de ce chantier
(`00-intent.md`, périmètre sortant) : aucune donnée comparative entre les
deux voies n'existe.

La documentation Apple [S05] décrit la voie moderne comme un triplet :
`CLLocationUpdate` pour le flux de positions, `CLBackgroundActivitySession`
pour la réception en arrière-plan, et `CLServiceSession` qui porte la
déclaration d'autorisation, recréée dès un lancement en arrière-plan
après une terminaison, plus un accès aux diagnostics de session.

Décision

M1 garde `CLLocationManager`. La migration vers le triplet moderne est
reportée, avec quatre conditions de réveil explicites :

- une mesure de terrain (T16) montre que la voie classique coûte
  significativement plus en batterie, ou dérive davantage à l'arrêt
  (R-09), que la voie moderne sur le même parcours ;
- la voie classique est dépréciée, ou la cible de déploiement minimale
  rend `CLLocationUpdate` obligatoire ;
- un défaut apparaît dans la voie classique que seule l'API moderne
  corrige, par exemple un besoin réel sur les diagnostics de session
  pour R-08 ou R-11 ;
- le chantier 3 refond le pipeline de localisation pour la carte.

Conséquences

- Une seule voie est validée à la fois : la recette, les sept parcours et
  les décisions D1 à D4 de `01-system-map.md` restent la référence.
  Migrer maintenant invaliderait E-023 à E-030 sans bénéfice mesuré.
- L'obligation moderne de recréer une session en arrière-plan après une
  terminaison n'est pas en adéquation avec `docs/LOCATION-ENGINE.md` §2,
  qui interdit toute prétention à continuer après fermeture forcée. La
  migration n'est pas un simple échange d'adaptateur.
- R-11, le contexte du manager et de son délégataire, reste le chemin de
  correction prioritaire ; elle se fait sur la voie classique.
