import Foundation

/// One "Conseil du jour", as the server's `daily_tips` table holds it: about
/// the outing, never about a dog.
public struct DailyTip: Codable, Equatable, Sendable {
    public let position: Int
    public let title: String
    public let body: String

    public init(position: Int, title: String, body: String) {
        self.position = position
        self.title = title
        self.body = body
    }
}

public enum DailyTips {
    /// The tip of a day: the list in its server order, one step per calendar
    /// day, so everyone reads the same tip on the same day. Nil when the list
    /// is empty: no tip is better than an invented one.
    public static func pick(from tips: [DailyTip], dayNumber: Int) -> DailyTip? {
        guard !tips.isEmpty else { return nil }
        let ordered = tips.sorted { $0.position < $1.position }
        return ordered[((dayNumber % ordered.count) + ordered.count) % ordered.count]
    }

    /// The tips last read from the server, kept on the iPhone so the card shows
    /// offline. Encoded as JSON.
    public static func decodeCache(_ data: Data?) -> [DailyTip] {
        guard let data, let tips = try? JSONDecoder().decode([DailyTip].self, from: data) else { return [] }
        return tips
    }

    public static func encodeCache(_ tips: [DailyTip]) -> Data? {
        try? JSONEncoder().encode(tips)
    }
}
