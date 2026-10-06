import MapKit
import SwiftUI

/// The recorded path, drawn segment by segment. Display only: it never computes
/// distance or duration, it shows what the accumulator already accepted.
///
/// Non-interactive on purpose. A map that pans under a running walk competes with
/// the controls and with the user's own scrolling, and the PRD keeps the map a
/// background, not a navigation surface.
struct TruffloTrackMap: View {
    let points: [TrackCoordinate]
    /// Live sessions grow while the screen is open, so re-framing on every insert
    /// would fight the user's scroll; a finished walk is framed once.
    var followsNewPoints: Bool = false

    private var segments: [TrackSegmentShape] { TrackGeometry.drawableSegments(from: points) }

    private var box: (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double)? {
        TrackGeometry.boundingBox(of: points)
    }

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: []) {
            ForEach(segments, id: \.segment) { segment in
                MapPolyline(coordinates: segment.coordinates.map(coordinate))
                    .stroke(Color.truffloForest, lineWidth: 4)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func coordinate(_ point: TrackCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    private var region: MKCoordinateRegion {
        guard let box else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (box.minLat + box.maxLat) / 2,
                                           longitude: (box.minLon + box.maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: box.maxLat - box.minLat,
                                   longitudeDelta: box.maxLon - box.minLon)
        )
    }
}
