# 0004. Bouton « Continuer » sans rôle cancel dans la feuille de fin

Status: Accepted

Contexte

Le risque R-13 : dans la feuille de confirmation de fin, le bouton
« Continuer » était coupé en bas de la capture et absent du dump
d'accessibilité (E-025). Vérifié de nouveau sur iOS 27 : avec
`Button("Continuer", role: .cancel) {}`, l'arbre d'accessibilité de la
feuille ne contient qu'un seul bouton, « Terminer la balade » (dumps
`/tmp/trufflo-continuer-hierarchy.txt` des parcours `ui17` et `ui18`, qui
échouent sur `app.buttons["Continuer"]`). Depuis iOS 26, SwiftUI masque le
bouton portant le rôle `.cancel` dans les `confirmationDialog` : la
fermeture par appui à l'extérieur ou glissement le remplace, et l'action du
cancel n'est exécutée qu'au dismiss. Un utilisateur VoiceOver ou un écran
petit ne dispose donc d'aucune sortie labellisée, seulement de l'option
destructrice.

Décision

Le rôle `.cancel` est retiré : `Button("Continuer") {}`. Un bouton sans
rôle est rendu normalement sur toutes les versions, et toutes les actions
d'un `confirmationDialog` ferment le dialogue après exécution, y compris une
action vide. La feuille présente alors deux boutons labellisés, « Continuer »
et « Terminer la balade », et le parcours UI 4 asserting
`app.buttons["Continuer"]` verrouille le comportement.

Conséquences

- La sortie sûre est visible, exposée à l'accessibilité et cliquable sur
  iOS 26 et ultérieur, sans conditionnel de version dans la vue.
- Le rôle `.cancel` ne doit pas être réintroduit dans cette feuille : la
  régression silencieuse est un bouton absent, pas une erreur de build.
- R-13 se ferme sur le vert du parcours 4 (E-032).
