import Foundation

// The data the 2026-10-07 mock-ups show (chantier 8). Everything here is declared
// by the person or measured by the phone; nothing is inferred about the dog
// (product rule 3).

/// A dog's size at the withers, as the person declares it.
public enum DogSize: String, CaseIterable, Sendable {
    case small, medium, large

    public var label: String {
        switch self {
        case .small: "Petit"
        case .medium: "Moyen"
        case .large: "Grand"
        }
    }
}

/// A trait of character the person chooses for their dog. Declared, never read
/// from the walks.
public enum DogTrait: String, CaseIterable, Sendable {
    case sociable, calm, energetic, fearful, playful, other

    public var label: String {
        switch self {
        case .sociable: "Sociable"
        case .calm: "Calme"
        case .energetic: "Énergique"
        case .fearful: "Peureux"
        case .playful: "Joueur"
        case .other: "Autre"
        }
    }

    public var systemImage: String {
        switch self {
        case .sociable: "pawprint.fill"
        case .calm: "leaf"
        case .energetic: "bolt"
        case .fearful: "figure.walk.motion"
        case .playful: "soccerball"
        case .other: "ellipsis"
        }
    }

    static func list(from raw: String) -> [DogTrait] {
        raw.split(separator: ",").compactMap { DogTrait(rawValue: String($0)) }
    }

    static func raw(of traits: [DogTrait]) -> String {
        traits.map(\.rawValue).joined(separator: ",")
    }
}

/// How the person felt the balade went, chosen by them.
public enum WalkMood: String, CaseIterable, Sendable {
    case great, calm, discovery, tough

    public var label: String {
        switch self {
        case .great: "Super balade"
        case .calm: "Balade tranquille"
        case .discovery: "Découverte"
        case .tough: "Balade difficile"
        }
    }

    public var systemImage: String {
        switch self {
        case .great: "face.smiling"
        case .calm: "heart"
        case .discovery: "binoculars"
        case .tough: "cloud.rain"
        }
    }
}

/// The weather at the end of a balade suivie, when the service answered.
public enum WalkWeather: String, CaseIterable, Sendable {
    case sunny, cloudy, rainy, snowy, windy, foggy

    /// The six kinds the journal shows, from the name of a WeatherKit
    /// condition (`WeatherCondition`, iOS 27 SDK). Nil for a condition this
    /// list does not cover, rather than a wrong word.
    public init?(conditionName: String) {
        switch conditionName {
        case "clear", "mostlyClear", "hot", "frigid": self = .sunny
        case "cloudy", "mostlyCloudy", "partlyCloudy": self = .cloudy
        case "rain", "drizzle", "heavyRain", "freezingRain", "freezingDrizzle", "sunShowers",
             "thunderstorms", "isolatedThunderstorms", "scatteredThunderstorms", "strongStorms",
             "tropicalStorm", "hurricane", "hail": self = .rainy
        case "snow", "flurries", "heavySnow", "blizzard", "blowingSnow", "sleet", "sunFlurries",
             "wintryMix": self = .snowy
        case "windy", "breezy": self = .windy
        case "foggy", "haze", "smoky", "blowingDust": self = .foggy
        default: return nil
        }
    }

    public var label: String {
        switch self {
        case .sunny: "Ensoleillé"
        case .cloudy: "Nuageux"
        case .rainy: "Pluvieux"
        case .snowy: "Neigeux"
        case .windy: "Venteux"
        case .foggy: "Brumeux"
        }
    }

    public var systemImage: String {
        switch self {
        case .sunny: "sun.max.fill"
        case .cloudy: "cloud.fill"
        case .rainy: "cloud.rain.fill"
        case .snowy: "cloud.snow.fill"
        case .windy: "wind"
        case .foggy: "cloud.fog.fill"
        }
    }
}

/// The energy a walking dog spends, as an estimate.
///
/// Dogs spend about 0.6 kcal per kg per km when long-legged and about 1.3 when
/// short-legged, walking speed mattering little (veterinary performance-nutrition
/// figures, as summarised by the Association for Pet Obesity Prevention's
/// dog-walking calorie estimator, read 2026-10-07). A large dog takes 0.6, a
/// small one 1.3, a medium or undeclared one the middle. Shown as "Estimation",
/// never as a target (product rule 1).
public enum CalorieEstimate {
    public static func kcal(weightKg: Double?, meters: Double?, size: DogSize?) -> Int? {
        guard let weightKg, let meters, weightKg > 0, meters > 0 else { return nil }
        let perKgPerKm: Double
        switch size {
        case .large: perKgPerKm = 0.6
        case .small: perKgPerKm = 1.3
        case .medium, nil: perKgPerKm = 0.95
        }
        return Int((perKgPerKm * weightKg * meters / 1000).rounded())
    }
}
