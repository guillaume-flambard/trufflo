import Foundation
import Supabase

/// Reads the daily tips from the server (`daily_tips`, readable without an
/// account) and keeps them on the iPhone.
enum DailyTipsRemote {
    static let cacheKey = "dailyTips.cache"

    /// Refreshes the cache. A failure keeps the previous cache: the card goes on
    /// showing the last tips read, or nothing if none ever was.
    static func refresh(client: SupabaseClient, defaults: UserDefaults = .standard) async {
        do {
            let tips: [DailyTip] = try await client.from("daily_tips")
                .select("position,title,body")
                .order("position")
                .execute()
                .value
            if !tips.isEmpty, let data = DailyTips.encodeCache(tips) {
                defaults.set(data, forKey: cacheKey)
            }
        } catch {
            // Offline or server down: the cached tips stay.
        }
    }
}
