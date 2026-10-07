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
                .locale(TruffloLocale.french))
            return "\(km) km"
        }
        return String(format: "%.0f m", meters)
    }

    static func quality(_ quality: WalkQuality) -> String {
        switch quality {
        case .gpsRecorded: "Tracé complet"
        case .gpsPartial: "Tracé en partie mesuré"
        case .manual: "Balade ajoutée, sans mesure"
        case .unavailable: "Aucun point de tracé retenu"
        }
    }

    private static let french = TruffloLocale.french

    /// "18:42". The journal's margin: the hour is where a walk sits in the
    /// day, not a name invented for it ("Balade du soir" was removed on
    /// 2026-10-06: repeated down a feed, it read as a template).
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(french))
    }

    /// "aujourd'hui", "hier", then "mardi 6 oct.".
    static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "aujourd'hui" }
        if calendar.isDateInYesterday(date) { return "hier" }
        return date.formatted(.dateTime.weekday(.wide).day().month().locale(french))
    }

    /// "42 min" under an hour, "1 h 08" above. Rounded to the minute, which is
    /// what a person reads; the live screen keeps the second-accurate clock.
    static func minutes(_ seconds: TimeInterval) -> String {
        // Under a minute, "0 min" would erase a real outing: give the seconds.
        if seconds < 60 { return "\(Int(seconds)) s" }
        let total = Int((seconds / 60).rounded())
        if total < 60 { return "\(total) min" }
        return String(format: "%d h %02d", total / 60, total % 60)
    }

    /// "mardi 6 oct., 14:48".
    static func dayAndTime(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month().hour().minute().locale(french))
    }

    /// "aujourd'hui, 08:15", "hier, 18:42", then "mardi 6 oct., 18:42".
    static func relativeDayAndTime(_ date: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute().locale(french))
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "aujourd'hui, \(time)" }
        if calendar.isDateInYesterday(date) { return "hier, \(time)" }
        return date.formatted(.dateTime.weekday(.wide).day().month().locale(french)) + ", \(time)"
    }

    /// "07:37 à 08:15".
    static func timeRange(_ start: Date, _ end: Date) -> String {
        let style = Date.FormatStyle.dateTime.hour().minute().locale(french)
        return "\(start.formatted(style)) à \(end.formatted(style))"
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
