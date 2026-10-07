import Foundation

// Guidance to a planned place and the nearby-dog alert of the 2026-10-07 board.
// Pure logic: the route comes from MapKit, the positions from Core Location or
// the foyer, and both are handed in as plain coordinates.

/// One manoeuvre of a walking route: where it starts and what to do there.
public struct GuidanceStep: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let instruction: String

    public init(latitude: Double, longitude: Double, instruction: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.instruction = instruction
    }
}

public enum Guidance {
    /// A manoeuvre counts as reached within this distance of its start.
    public static let reachedWithin = 20.0

    /// The next manoeuvre to announce: moves past every step already reached,
    /// never back, so a GPS jitter cannot replay an instruction.
    public static func advance(from current: Int, steps: [GuidanceStep],
                               latitude: Double, longitude: Double) -> Int {
        var index = current
        while index < steps.count,
              meters(latitude, longitude, steps[index].latitude, steps[index].longitude) < reachedWithin {
            index += 1
        }
        return index
    }

    /// Metres from the position to the start of a step.
    public static func meters(to step: GuidanceStep, latitude: Double, longitude: Double) -> Double {
        meters(latitude, longitude, step.latitude, step.longitude)
    }

    /// "À 200 m", rounded to 10 m under a kilometre, to 100 m above.
    public static func distanceLabel(_ meters: Double) -> String {
        if meters < 1000 {
            return "À \(max(10, Int((meters / 10).rounded()) * 10)) m"
        }
        let km = (meters / 100).rounded() / 10
        return "À \(km.formatted(.number.precision(.fractionLength(1)).locale(TruffloLocale.french))) km"
    }

    /// The arrow of the banner, read from MapKit's written instruction.
    public static func symbol(for instruction: String) -> String {
        let text = instruction.lowercased()
        if text.contains("droite") || text.contains("right") { return "arrow.turn.up.right" }
        if text.contains("gauche") || text.contains("left") { return "arrow.turn.up.left" }
        if text.contains("destination") || text.contains("arriv") { return "mappin.and.ellipse" }
        return "arrow.up"
    }

    static func meters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }
}

/// A dog whose position the walker may see: only a foyer member who chose to
/// share it during their own balade (PRD F09: no standing exposure of anyone's
/// position). Never a stranger.
public struct NearbyDog: Equatable, Sendable {
    public let id: UUID
    public let latitude: Double
    public let longitude: Double

    public init(id: UUID, latitude: Double, longitude: Double) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum Proximity {
    /// Closer than this, the walker is told.
    public static let alertWithin = 50.0

    /// The closest dog within reach that has not been acknowledged yet, with its
    /// distance rounded to 10 m: "~ 30 m", never a precise position.
    public static func alert(for dogs: [NearbyDog], latitude: Double, longitude: Double,
                             acknowledged: Set<UUID>) -> (dog: NearbyDog, roundedMeters: Int)? {
        dogs.filter { !acknowledged.contains($0.id) }
            .map { ($0, Guidance.meters(latitude, longitude, $0.latitude, $0.longitude)) }
            .filter { $0.1 <= alertWithin }
            .min { $0.1 < $1.1 }
            .map { ($0.0, max(10, Int(($0.1 / 10).rounded()) * 10)) }
    }
}
