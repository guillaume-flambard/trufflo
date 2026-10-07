import MapKit
import SwiftUI

/// The recorded path on a MapKit map. Display only: it draws the segments the
/// accumulator already accepted and never computes distance or duration.
///
/// The map is interactive and can follow the growing path, but it never yanks
/// itself back after the user has panned or zoomed. The recentre control makes
/// following explicit and recoverable, which is the rule the design system asks
/// for: the camera moves when the user says so, not on every new fix.
struct TruffloTrackMap: View {
    let points: [TrackCoordinate]
    /// True while the walk is live and the path is still growing.
    var isLive: Bool = false
    /// Show the start and the live position, which only make sense mid-walk.
    var showsMarkers: Bool = false
    /// Owned by the caller so the recentre control can live outside the map, on a
    /// surface with a readable background rather than floating over the tiles.
    @Binding var isFollowing: Bool
    /// The walking route to a planned place, drawn ahead of the walker.
    var guideRoute: [CLLocationCoordinate2D] = []
    var destination: CLLocationCoordinate2D? = nil
    /// A dog of the foyer close by (`Proximity`), drawn as the board's red paw.
    var nearbyDog: CLLocationCoordinate2D? = nil

    @State private var camera: MapCameraPosition = .automatic
    /// The region this view last asked for. MapKit adjusts whatever region it is
    /// handed and also emits camera changes of its own on first layout, so a
    /// change cannot be attributed by a flag: the flag is consumed by a change
    /// that is not the one it was set for. Comparing where the camera actually is
    /// against where it was asked to go is what survives that.
    @State private var lastRequestedRegion: MKCoordinateRegion?

    private var segments: [TrackSegmentShape] { TrackGeometry.drawableSegments(from: points) }
    private var lastPoint: TrackCoordinate? { points.last }
    private var firstPoint: TrackCoordinate? { points.first }

    var body: some View {
        Map(position: $camera) {
            ForEach(segments, id: \.segment) { segment in
                MapPolyline(coordinates: segment.coordinates.map(Self.coordinate))
                    .stroke(Color.truffloForest, lineWidth: 5)
            }

            if guideRoute.count > 1 {
                MapPolyline(coordinates: guideRoute)
                    .stroke(Color.truffloForest.opacity(0.55),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [2, 9]))
            }
            if let destination {
                Annotation("", coordinate: destination, anchor: .bottom) {
                    Image(systemName: "mappin")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                        .accessibilityHidden(true)
                }
            }
            if let nearbyDog {
                Annotation("", coordinate: nearbyDog, anchor: .center) {
                    ZStack {
                        Circle().fill(Color.red.opacity(0.14)).frame(width: 150, height: 150)
                        Circle().fill(Color.red.opacity(0.18)).frame(width: 80, height: 80)
                        Circle().fill(Color(red: 0.93, green: 0.3, blue: 0.18)).frame(width: 46, height: 46)
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                        Image(systemName: "pawprint.fill").font(.system(size: 19)).foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)
                }
            }

            if showsMarkers, let firstPoint {
                Annotation("", coordinate: Self.coordinate(firstPoint), anchor: .center) {
                    Circle()
                        .fill(Color.truffloForest)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .accessibilityHidden(true)
                }
            }

            if showsMarkers, let lastPoint {
                // Unlabelled, as on the board: a dark dot where it began, the blue
                // dot of "you are here" where it is now.
                Annotation("", coordinate: Self.coordinate(lastPoint), anchor: .center) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.5, blue: 0.95).opacity(0.22))
                            .frame(width: 34, height: 34)
                        Circle()
                            .fill(Color(red: 0.16, green: 0.5, blue: 0.95))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        // Muted, parks only: the same quiet map as the route pictures of Today and
        // the journal (`TruffloRouteMap`, `.mutedStandard`), so the walk screen does
        // not switch to a different, louder map. Parks stay because that is where a
        // dog walk goes; shops and restaurants are noise under a leash.
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted,
                            pointsOfInterest: .including([.park])))
        .mapControlVisibility(.hidden)
        .accessibilityHidden(true)
        .onChange(of: points.count) { _, _ in followIfNeeded() }
        .onMapCameraChange(frequency: .onEnd) { context in
            // A camera change that landed where this view asked for is not the
            // person moving the map, however many MapKit emits on its own during
            // layout. Anything else is, and following stops so the map is not
            // dragged back mid-pan.
            guard let requested = lastRequestedRegion,
                  !Self.isCentredOn(requested, context.region) else { return }
            isFollowing = false
        }
        .task {
            requestFrame()
            isFollowing = true
        }
    }

    // MARK: - Camera

    private func followIfNeeded() {
        guard !points.isEmpty else { return }
        // A finished walk's points arrive after the first layout, from a query:
        // framing once on an empty list left the map on the default city. Frame
        // again whenever the stored track changes, unless the person has moved it.
        if !isLive {
            if lastRequestedRegion == nil || isFollowing { requestFrame() }
            return
        }
        guard isFollowing else { return }
        requestFrame()
    }

    private func requestFrame() {
        let region = framingRegion
        lastRequestedRegion = region
        camera = .region(region)
    }

    /// True when the camera is still centred where this view put it.
    ///
    /// Only the centre is compared, because only the centre comes back unchanged.
    /// Measured on the simulator, MapKit reports a span of 0.0284 for a requested
    /// 0.02: it widens the span to fit the viewport and re-derives the latitude
    /// delta, while the centre matches to floating-point noise. Comparing spans
    /// therefore reads MapKit's own adjustment as a person panning, and following
    /// silently switches off one layout after the walk starts.
    ///
    /// The tolerance is 2% of the visible span, floored at a couple of metres, so
    /// it scales with zoom while staying well below any drag a person performs.
    private static func isCentredOn(_ requested: MKCoordinateRegion, _ actual: MKCoordinateRegion) -> Bool {
        let span = max(max(requested.span.latitudeDelta, requested.span.longitudeDelta), 0.0005)
        let tolerance = max(span * 0.02, 0.00002)
        return abs(requested.center.latitude - actual.center.latitude) <= tolerance
            && abs(requested.center.longitude - actual.center.longitude) <= tolerance
    }

    private var framingRegion: MKCoordinateRegion {
        guard let box = TrackGeometry.boundingBox(of: points) else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (box.minLat + box.maxLat) / 2,
                longitude: (box.minLon + box.maxLon) / 2
            ),
            // A margin around the route, and a floor of a few hundred metres,
            // so a short walk is framed as a walk and not as a dot.
            span: MKCoordinateSpan(latitudeDelta: max((box.maxLat - box.minLat) * 1.6, 0.0018),
                                   longitudeDelta: max((box.maxLon - box.minLon) * 1.6, 0.0018))
        )
    }

    private static func coordinate(_ point: TrackCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }
}
