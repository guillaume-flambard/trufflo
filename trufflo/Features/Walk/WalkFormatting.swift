import Foundation

/// The wording shared by the live walk screen and the post-walk summary. One place,
/// so the two screens cannot drift apart on how a duration or a distance reads.
///
/// An absent distance is written "Non mesurée", never "0": a missing measurement
/// and a measured zero are different facts and the UI must not merge them.
enum WalkFormatting {
    /// `mm:ss`, or `hh:mm:ss` once an hour has passed. The UI journeys parse
    /// this exact shape.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Metres below a kilometre, kilometres with a French decimal separator above:
    /// `%.2f` renders `1.80 km`, which reads as a typo in this app's language.
    static func distance(_ meters: Double?) -> String {
        guard let meters else { return "Non mesurée" }
        if meters >= 1000 {
            let km = (meters / 1000).formatted(.number.precision(.fractionLength(1...2))
                .locale(Locale(identifier: "fr_FR")))
            return "\(km) km"
        }
        return String(format: "%.0f m", meters)
    }

    static func quality(_ quality: WalkQuality) -> String {
        switch quality {
        case .gpsRecorded: "Mesurée par GPS"
        case .gpsPartial: "Mesure partielle"
        case .manual: "Déclarée à la main"
        case .unavailable: "Non mesurée"
        }
    }
}
