import Foundation

/// The words of a walk outing, kept apart from the views so they can be tested.
/// Facts only: dates, places left, what this person asked. No score, no ranking.
public enum OutingFormatting {
    private static let french = TruffloLocale.french

    /// "1 h", "45 min", "1 h 30".
    public static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest))"
    }

    /// "10:00 à 11:00".
    public static func timeRange(_ outing: OutingDTO) -> String {
        let style = Date.FormatStyle().hour().minute().locale(french)
        return "\(outing.startsAt.formatted(style)) à \(outing.endsAt.formatted(style))"
    }

    /// "Samedi 11 octobre".
    public static func day(_ date: Date) -> String {
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(french))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "Il reste 3 places et 2 places pour chiens." / "Complète."
    public static func places(_ outing: OutingDTO) -> String {
        let humans = outing.humanPlacesLeft, dogs = outing.dogPlacesLeft
        if humans == 0 { return "Complète" }
        let people = humans == 1 ? "1 place" : "\(humans) places"
        if dogs == 0 { return "\(people), plus de place pour les chiens" }
        let dogText = dogs == 1 ? "1 place pour un chien" : "\(dogs) places pour des chiens"
        return "\(people), \(dogText)"
    }

    /// What this person's own request says, if there is one. Once the walk is
    /// over the tense changes: « Vous venez » would be false.
    public static func myStatus(_ outing: OutingDTO, organizerIsMe: Bool = false, now: Date = .now) -> String? {
        let over = hasEnded(outing, now: now)
        if organizerIsMe { return over ? "Vous organisiez" : "Vous organisez" }
        if outing.status == .cancelled { return "Annulée" }
        switch outing.myStatus {
        case .requested: return over ? "Demande restée sans réponse" : "Demande envoyée"
        case .accepted:
            guard over else { return "Vous venez" }
            switch outing.myAttended {
            case .some(true): return "Vous y étiez"
            case .some(false): return "Vous n'y étiez pas"
            case .none: return "Vous y étiez inscrit"
            }
        case .declined: return "Demande refusée"
        case .withdrawn, .none: return nil
        }
    }

    /// Whether this person can still ask: published, to come, not already in.
    public static func canRequest(_ outing: OutingDTO, now: Date = .now) -> Bool {
        guard outing.status == .published, outing.startsAt > now else { return false }
        switch outing.myStatus {
        case .requested, .accepted: return false
        case .declined, .withdrawn, .none: return outing.humanPlacesLeft > 0
        }
    }

    public static func hasEnded(_ outing: OutingDTO, now: Date = .now) -> Bool { outing.endsAt <= now }
}
