import CoreLocation
import MapKit

/// The walking route from where the walker is to a planned place, from MapKit
/// (`MKDirections`, transport `.walking`). Returns nothing when MapKit has no
/// route: the walk goes on without guidance, it never blocks.
enum WalkRouteGuide {
    struct Route {
        let steps: [GuidanceStep]
        let path: [CLLocationCoordinate2D]
    }

    static func route(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async -> Route? {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: end.latitude, longitude: end.longitude), address: nil)
        request.transportType = .walking
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }
        // The first step of a MapKit route is the start, with no instruction.
        let steps = route.steps.compactMap { step -> GuidanceStep? in
            guard !step.instructions.isEmpty, step.polyline.pointCount > 0 else { return nil }
            let first = step.polyline.points()[0].coordinate
            return GuidanceStep(latitude: first.latitude, longitude: first.longitude, instruction: step.instructions)
        }
        let polyline = route.polyline
        let path = (0..<polyline.pointCount).map { polyline.points()[$0].coordinate }
        return Route(steps: steps, path: path)
    }
}
