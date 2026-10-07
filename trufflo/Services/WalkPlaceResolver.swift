import CoreLocation
import MapKit

/// The name of the place a balade suivie went through, from its tracé.
///
/// MapKit's reverse geocoding (MKReverseGeocodingRequest, iOS 26 and later; read
/// in the iOS 27 SDK headers on 2026-10-07). The middle point of the tracé is
/// asked, so a loop that starts at home is named after where it went, not after
/// the front door. Nil when offline or when MapKit has no name.
enum WalkPlaceResolver {
    static func placeName(for points: [TrackCoordinate]) async -> String? {
        guard !points.isEmpty else { return nil }
        let middle = points[points.count / 2]
        let location = CLLocation(latitude: middle.latitude, longitude: middle.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = TruffloLocale.french
        guard let item = try? await request.mapItems.first else { return nil }
        let city = item.addressRepresentations?.cityName
        switch (item.name, city) {
        case let (name?, city?) where !name.isEmpty && name != city: return "\(name), \(city)"
        case let (name?, _) where !name.isEmpty: return name
        case let (nil, city?), let ("", city?): return city
        default: return nil
        }
    }
}
