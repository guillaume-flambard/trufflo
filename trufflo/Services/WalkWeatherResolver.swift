import CoreLocation
import WeatherKit

/// The weather of a balade suivie, from WeatherKit (Apple Weather): the hour
/// closest to its end, at the middle of its tracé. 500 000 calls a month are
/// included in the developer membership (developer.apple.com/weatherkit,
/// read 2026-10-08). Nil when the service refuses (capability not enabled on
/// the App ID, offline) or has no hour that close: no weather rather than a
/// guessed one.
enum WalkWeatherResolver {
    static func weather(at point: TrackCoordinate, endedAt: Date) async -> (WalkWeather, Double)? {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let hours: Forecast<HourWeather>
        do {
            hours = try await WeatherService.shared.weather(
                for: location,
                including: .hourly(startDate: endedAt.addingTimeInterval(-3600), endDate: endedAt.addingTimeInterval(3600)))
        } catch {
            return nil
        }
        guard let hour = hours.min(by: { abs($0.date.timeIntervalSince(endedAt)) < abs($1.date.timeIntervalSince(endedAt)) }),
              abs(hour.date.timeIntervalSince(endedAt)) <= 3600,
              let kind = WalkWeather(conditionName: caseName(hour.condition)) else { return nil }
        return (kind, hour.temperature.converted(to: .celsius).value)
    }

    /// The case's own name, which `WalkWeather(conditionName:)` maps. Not
    /// `description`: WeatherCondition's is a display text, not the case name.
    static func caseName(_ condition: WeatherCondition) -> String {
        switch condition {
        case .blizzard: "blizzard"
        case .blowingDust: "blowingDust"
        case .blowingSnow: "blowingSnow"
        case .breezy: "breezy"
        case .clear: "clear"
        case .cloudy: "cloudy"
        case .drizzle: "drizzle"
        case .flurries: "flurries"
        case .foggy: "foggy"
        case .freezingDrizzle: "freezingDrizzle"
        case .freezingRain: "freezingRain"
        case .frigid: "frigid"
        case .hail: "hail"
        case .haze: "haze"
        case .heavyRain: "heavyRain"
        case .heavySnow: "heavySnow"
        case .hot: "hot"
        case .hurricane: "hurricane"
        case .isolatedThunderstorms: "isolatedThunderstorms"
        case .mostlyClear: "mostlyClear"
        case .mostlyCloudy: "mostlyCloudy"
        case .partlyCloudy: "partlyCloudy"
        case .rain: "rain"
        case .scatteredThunderstorms: "scatteredThunderstorms"
        case .sleet: "sleet"
        case .smoky: "smoky"
        case .snow: "snow"
        case .strongStorms: "strongStorms"
        case .sunFlurries: "sunFlurries"
        case .sunShowers: "sunShowers"
        case .thunderstorms: "thunderstorms"
        case .tropicalStorm: "tropicalStorm"
        case .windy: "windy"
        case .wintryMix: "wintryMix"
        @unknown default: ""
        }
    }

    /// Apple Weather's mark and legal link, which must be shown wherever its
    /// data is (WeatherKit attribution requirements).
    static func attribution() async -> (mark: URL, legal: URL)? {
        guard let attribution = try? await WeatherService.shared.attribution else { return nil }
        return (attribution.combinedMarkLightURL, attribution.legalPageURL)
    }
}
