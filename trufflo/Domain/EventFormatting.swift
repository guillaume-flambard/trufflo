import Foundation

/// The words of a walk event, kept apart from the views so they can be tested.
/// Facts only: dates, places left, what this person asked. No score, no ranking.
public enum EventFormatting {
    private static let french = TruffloLocale.french

    /// "1 h", "45 min", "1 h 30".
    public static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest))"
    }

    /// "10:00 à 11:00".
    public static func timeRange(_ event: WalkEventDTO) -> String {
        let style = Date.FormatStyle().hour().minute().locale(french)
        return "\(event.startsAt.formatted(style)) à \(event.endsAt.formatted(style))"
    }

    /// "Samedi 11 octobre".
    public static func day(_ date: Date) -> String {
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(french))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "Il reste 3 places et 2 places pour chiens." / "Complète."
    public static func places(_ event: WalkEventDTO) -> String {
        let humans = event.humanPlacesLeft, dogs = event.dogPlacesLeft
        if humans == 0 { return "Complète" }
        let people = humans == 1 ? "1 place" : "\(humans) places"
        if dogs == 0 { return "\(people), plus de place pour les chiens" }
        let dogText = dogs == 1 ? "1 place pour un chien" : "\(dogs) places pour des chiens"
        return "\(people), \(dogText)"
    }

    /// What this person's own request says, if there is one.
    public static func myStatus(_ event: WalkEventDTO, organizerIsMe: Bool = false) -> String? {
        if organizerIsMe { return "Vous organisez" }
        if event.status == .cancelled { return "Annulée" }
        switch event.myStatus {
        case .requested: return "Demande envoyée"
        case .accepted: return "Vous venez"
        case .declined: return "Demande refusée"
        case .withdrawn, .none: return nil
        }
    }

    /// Whether this person can still ask: published, to come, not already in.
    public static func canRequest(_ event: WalkEventDTO, now: Date = .now) -> Bool {
        guard event.status == .published, event.startsAt > now else { return false }
        switch event.myStatus {
        case .requested, .accepted: return false
        case .declined, .withdrawn, .none: return event.humanPlacesLeft > 0
        }
    }

    public static func hasEnded(_ event: WalkEventDTO, now: Date = .now) -> Bool { event.endsAt <= now }
}
