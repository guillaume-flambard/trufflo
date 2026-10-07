import MapKit
import SwiftUI

/// A walk's route on a real map, as a still picture: the thumbnail of the tile.
///
/// A `Map` view would be live, heavy in a scrolling screen, and would show a grey
/// grid with no network. A snapshot is rendered once, cached, and until it exists
/// (or when there is no network at all) the route silhouette stands in, so the tile
/// is never empty and never waits on a server. The journal works offline; its
/// thumbnails must too.
struct TruffloRouteMap: View {
    let points: [TrackCoordinate]
    /// Identifies the walk and what was drawn, so a corrected walk gets a new picture.
    let cacheKey: String
    /// The full-colour map (parks in green), as on the Today card of the mock-up,
    /// rather than the muted one.
    var isVivid = false

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TruffloRouteSilhouette(points: points)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .task(id: "\(cacheKey)-\(Int(proxy.size.width))-\(Int(proxy.size.height))") {
                await load(size: proxy.size)
            }
        }
        .animation(.easeOut(duration: 0.35), value: image != nil)
        .accessibilityHidden(true)
    }

    @MainActor
    private func load(size: CGSize) async {
        guard size.width > 1, size.height > 1, points.count > 1 else { return }
        let key = "\(cacheKey)-\(Int(size.width))x\(Int(size.height))@\(displayScale)-\(isVivid)" as NSString
        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }
        guard let region = Self.region(framing: points, aspect: size.width / size.height) else { return }
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = displayScale
        options.mapType = isVivid ? .standard : .mutedStandard
        options.pointOfInterestFilter = isVivid ? MKPointOfInterestFilter(including: [.park]) : .excludingAll
        // The app is light-only; a snapshot must not follow the system into dark.
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            let drawn = Self.draw(points, on: snapshot)
            Self.cache.setObject(drawn, forKey: key)
            image = drawn
        } catch {
            // Offline or refused: the silhouette stays, which is the honest fallback.
        }
    }

    /// The route centred with room around it, at the frame's aspect ratio so the
    /// snapshot is not stretched.
    private static func region(framing points: [TrackCoordinate], aspect: CGFloat) -> MKCoordinateRegion? {
        guard let box = TrackGeometry.boundingBox(of: points) else { return nil }
        let center = CLLocationCoordinate2D(latitude: (box.minLat + box.maxLat) / 2,
                                            longitude: (box.minLon + box.maxLon) / 2)
        let latSpan = max(box.maxLat - box.minLat, 0.0015)
        let lonSpan = max(box.maxLon - box.minLon, 0.0015)
        // 1.7 leaves a margin; the longitude span is scaled so the frame's ratio holds.
        let height = max(latSpan * 1.7, lonSpan * 1.7 / Double(aspect))
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: height,
                                                         longitudeDelta: height * Double(aspect)))
    }

    private static func draw(_ points: [TrackCoordinate], on snapshot: MKMapSnapshotter.Snapshot) -> UIImage {
        let forest = UIColor(Color.truffloForest)
        // Strokes and dots in proportion to the picture: the widths that suit the
        // 150 pt tile of Today bury the route on the journal's 64 pt thumbnail.
        let side = min(snapshot.image.size.width, snapshot.image.size.height)
        let scale = min(max(side / 150, 0.5), 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size, format: format)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)
            // Segments stay apart: the gap between two is a pause, not a road.
            for segment in TrackGeometry.segments(from: points) where segment.coordinates.count > 1 {
                let path = UIBezierPath()
                for (index, coordinate) in segment.coordinates.enumerated() {
                    let point = snapshot.point(for: CLLocationCoordinate2D(latitude: coordinate.latitude,
                                                                           longitude: coordinate.longitude))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.lineWidth = 4.5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                UIColor.white.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 7.5 * scale
                path.stroke()
                forest.setStroke()
                path.lineWidth = 4.5 * scale
                path.stroke()
            }
            if let first = points.first, let last = points.last {
                // Start in slate blue, end in forest, both ringed in white.
                let startBlue = UIColor(red: 0.20, green: 0.31, blue: 0.47, alpha: 1)
                for (coordinate, fill) in [(first, startBlue), (last, forest)] {
                    let center = snapshot.point(for: CLLocationCoordinate2D(latitude: coordinate.latitude,
                                                                            longitude: coordinate.longitude))
                    let dot = UIBezierPath(arcCenter: center, radius: 7 * scale, startAngle: 0, endAngle: .pi * 2, clockwise: true)
                    fill.setFill()
                    dot.fill()
                    UIColor.white.setStroke()
                    dot.lineWidth = 2.5 * scale
                    dot.stroke()
                }
            }
        }
    }
}
