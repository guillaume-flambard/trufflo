import Foundation

/// The routine a person chooses for their dog (PRD F04): their own reference
/// points, never a prescription. Nothing here is suggested by the app, derived
/// from the breed, or raised automatically.
///
/// Wording rule (DESIGN-SYSTEM): "Routine choisie", never "Objectif". The app
/// states what was recorded next to what was chosen; it never says what is
/// missing, never asks to catch up, never notifies.
public struct DogRoutine: Equatable, Sendable {
    public enum Slot: String, CaseIterable, Sendable, Comparable {
        case morning, midday, afternoon, evening

        public var label: String {
            switch self {
            case .morning: "matin"
            case .midday: "midi"
            case .afternoon: "après-midi"
            case .evening: "soir"
            }
        }

        public static func < (lhs: Slot, rhs: Slot) -> Bool {
            allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
        }
    }

    public enum Invalid: Error, Equatable {
        /// A routine with no reference point at all says nothing; there is
        /// simply no routine.
        case empty
        case outOfRange
    }

    /// Nil when the person did not choose a number of outings.
    public let walksPerDay: Int?
    /// Nil when the person did not choose a duration.
    public let minutesPerWalk: Int?
    public let slots: Set<Slot>

    public init(walksPerDay: Int?, minutesPerWalk: Int?, slots: Set<Slot>) throws {
        guard walksPerDay != nil || minutesPerWalk != nil || !slots.isEmpty else {
            throw Invalid.empty
        }
        // Input sanity limits, not recommendations.
        if let walksPerDay, !(1...8).contains(walksPerDay) { throw Invalid.outOfRange }
        if let minutesPerWalk, !(5...240).contains(minutesPerWalk) { throw Invalid.outOfRange }
        self.walksPerDay = walksPerDay
        self.minutesPerWalk = minutesPerWalk
        self.slots = slots
    }

    /// "2 balades par jour, environ 30 min, matin et soir".
    public var summary: String {
        var parts: [String] = []
        if let walksPerDay {
            parts.append(walksPerDay == 1 ? "1 balade par jour" : "\(walksPerDay) balades par jour")
        }
        if let minutesPerWalk { parts.append("environ \(minutesPerWalk) min") }
        if !slots.isEmpty {
            let names = slots.sorted().map(\.label)
            parts.append(names.formatted(.list(type: .and).locale(TruffloLocale.french)))
        }
        let text = parts.joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// What was recorded today, said next to the chosen routine. A fact, never a
    /// shortfall: "Aujourd'hui, 1 enregistrée" and not "il en manque 1". With no
    /// chosen number there is nothing to set the count against, so it says only
    /// how many were recorded.
    public func today(recordedWalks: Int) -> String {
        let recorded: String
        switch recordedWalks {
        case 0: recorded = "aucune balade enregistrée pour l'instant"
        case 1: recorded = "1 balade enregistrée"
        default: recorded = "\(recordedWalks) balades enregistrées"
        }
        return "Aujourd'hui, \(recorded)."
    }
}
