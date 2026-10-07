import UserNotifications

/// The reminder of a planned balade: one local notification fifteen minutes
/// before. Asks permission the first time; nothing happens if it is refused.
enum WalkReminder {
    private static let identifier = "trufflo.plannedWalk"

    static func schedule(at date: Date, placeName: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            let fire = max(date.addingTimeInterval(-15 * 60), .now.addingTimeInterval(5))
            let content = UNMutableNotificationContent()
            content.title = "Balade dans 15 minutes"
            content.body = placeName.isEmpty ? "C'est bientôt l'heure de sortir." : "Direction \(placeName)."
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
