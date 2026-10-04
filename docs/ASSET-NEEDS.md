# Besoins en actifs

Inventaire réel de `trufflo/Assets.xcassets` au 4 octobre 2026, relevé par
lecture du catalogue, pas par déclaration d'intention.

Ce document remplace la version précédente qui listait une icône et un
`AccentColor` manquants. Ces deux actifs existent désormais ; documenter leur
absence serait documenter un manque qui n'existe pas.

## Ce qui existe

### Icône d'application

| Élément | État |
|---|---|
| `AppIcon.appiconset/app_icon.png` | 1024 x 1024, format `1024x1024` universel iOS. Seule taille requise par les versions récentes d'iOS. |
| `AccentColor.colorset` | srgb 0.118 / 0.302 / 0.231, soit `#1E4D3B`. Consommé par `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`, pas référencé depuis le code. |

### Jetons de couleur

Neuf jetons utilisés par `trufflo/DesignSystem/Theme.swift`, tous en srgb, tous
avec une seule entrée universelle :

| Jeton | Actif | srgb | Commentaire du code |
|---|---|---|---|
| `forest` | `ForestColor` | 0.118 / 0.302 / 0.231 | `#1E4D3B` |
| `sage` | `SageColor` | 0.298 / 0.686 / 0.482 | `#4CAF7B` |
| `mint` | `MintColor` | 0.655 / 0.843 / 0.773 | `#A7D7C5` |
| `sand` | `SandColor` | 0.969 / 0.957 / 0.929 | `#F7F4ED` |
| `peach` | `PeachColor` | 1.000 / 0.702 / 0.541 | `#FFB38A` |
| `terracotta` | `TerracottaColor` | 0.851 / 0.463 / 0.337 | `#D97656` |
| `sky` | `SkyColor` | 0.655 / 0.780 / 0.906 | `#A7C7E7` |
| `chocolate` | `ChocolateColor` | 0.361 / 0.251 / 0.200 | `#5C4033` |
| `charcoal` | `CharcoalColor` | 0.176 / 0.176 / 0.176 | `#2D2D2D` |

`truffloTests/ThemeTests.swift` vérifie que chaque jeton résout bien à ces
valeurs. Un actif renommé ou modifié fait échouer le test.

### Images

Cinq imagesets, chacun avec un seul fichier 1024 x 1024 déclaré en `1x` :

| Actif | Utilisé par | Poids fichier |
|---|---|---|
| `EmptyDog.imageset/empty_dog.png` | états vides, `StarterRootView` | 741 Ko |
| `EmptyWalk.imageset/empty_walk.png` | état vide du journal, `StarterRootView` | 989 Ko |
| `OnboardingWalk.imageset/onboarding_walk.png` | onboarding, étape 1 | 1.15 Mo |
| `OnboardingRoutine.imageset/onboarding_routine.png` | onboarding, étape 2 | 1.01 Mo |
| `OnboardingCommunity.imageset/onboarding_community.png` | onboarding, étape 3 | 1.09 Mo |

Catalogue complet : 5.7 Mo sur disque.

## Manques constatés

### 1. Aucune variante sombre

Zéro `colorset` ne déclare d'entrée `luminosity`. En apparence sombre, les
neuf jetons et l'accent gardent leurs valeurs claires. `sand` (`#F7F4ED`) reste
le fond d'écran, `charcoal` reste le texte.

Concerne le PRD section 5, F12 : des états d'interface dont la lisibilité
n'est pas conditionnée à un thème unique.

Avant publication, soit déclarer les variantes sombres, soit verrouiller
l'apparence claire et l'écrire explicitement. Sans l'une ni l'autre, le
résultat en apparence sombre est un hasard de rendu, pas une décision.

### 2. Images en `1x` uniquement, sans `2x` ni `3x`

Les cinq images sont déclarées en `1x`, donc iOS les met à l'échelle. Chaque
PNG de 1024 x 1024 occupe environ 4 Mo une fois décodé en mémoire. Trois
images d'onboarding montées ensemble dépassent 12 Mo.

À corriger par une déclaration par échelle aux dimensions voulues en points,
ou par une image plus petite. Aucune des deux n'est faite.

### 3. Aucun actif orphelin en trop, un actif mort

`BackgroundColor.colorset` n'a aucune référence dans le code. Sa valeur est
identique à celle de `SandColor`. À supprimer ou à utiliser, pas à garder en
l'état.

### 4. Photo de profil du chien absente

PRD section 5, F01 : « photo, âge et race facultatifs ». Le profil accepte un
nom et une race, pas une photo. Il manque la sélection, le stockage local et
l'effacement. Relève du code, pas du catalogue, mais c'est un besoin d'actif.

### 5. Aucune capture App Store

Ni captures d'écran, ni aperçu vidéo, ni jeu d'icônes alternatif. Hors
périmètre des chantiers en cours, bloquant pour une soumission.

## Règle

Ce document décrit l'état constaté. Il ne promet rien. Un actif listé comme
manquant est manquant tant qu'un test ou une inspection du catalogue ne dit
pas le contraire.
