import SwiftUI

// The activity language shared by Today, the journal, the walk detail and the
// post-walk summary. Its structure is borrowed from an activity feed: a small
// label above a heavy figure, figures side by side separated by a hairline, a
// route drawn as a silhouette rather than a map tile. The palette stays
// Trufflo's: forest for figures, slate for labels, sand underneath.

public extension Font {
    /// Figures: heavy and slightly condensed, so a duration reads at a glance
    /// and two figures fit side by side even at large text sizes.
    static func truffloFigure(_ style: Font.TextStyle = .title) -> Font {
        .system(style, design: .default, weight: .heavy).width(.condensed)
    }
}

/// One figure with its label above it, in sentence case. The label is spoken
/// with the value so VoiceOver reads "Durée, 42 min" as one element.
public struct TruffloStat: View {
    private let label: String
    private let value: String
    private let style: Font.TextStyle
    private let dimmed: Bool

    public init(_ label: String, value: String, style: Font.TextStyle = .title, dimmed: Bool = false) {
        self.label = label
        self.value = value
        self.style = style
        self.dimmed = dimmed
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.truffloSlate)
            Text(value)
                .font(.truffloFigure(style))
                .monospacedDigit()
                .foregroundStyle(dimmed ? Color.truffloSlate : Color.truffloForest)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Figures side by side with hairlines between them. At accessibility sizes they
/// stack, so a long value is never truncated.
public struct TruffloStatRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) { content }
        } else {
            HStack(alignment: .top, spacing: TruffloTheme.Spacing.medium) { content }
        }
    }
}

/// The route as a silhouette: the recorded segments drawn in forest on a pale
/// field, start and end marked. No tiles, no network, nothing to load, so it
/// can sit in every card of a list.
public struct TruffloRouteSilhouette: View {
    private let points: [TrackCoordinate]

    public init(points: [TrackCoordinate]) {
        self.points = points
    }

    public var body: some View {
        GeometryReader { proxy in
            // A margin proportional to the frame: a fixed 28 pt left a 64 pt
            // thumbnail an 8 pt drawing, which read as a lone dot.
            let projected = Self.project(points, in: proxy.size.insetBy(min(28, min(proxy.size.width, proxy.size.height) * 0.16)))
            ZStack {
                Color.truffloMint.opacity(0.28)
                Path { path in
                    for segment in projected where segment.count > 1 {
                        path.move(to: segment[0])
                        for point in segment.dropFirst() { path.addLine(to: point) }
                    }
                }
                .stroke(Color.truffloForest,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                if let first = projected.first?.first {
                    Circle().fill(Color.white).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color.truffloForest, lineWidth: 3))
                        .position(first)
                }
                if let last = projected.last?.last {
                    Circle().fill(Color.truffloForest).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                        .position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Equirectangular projection centred in the frame, aspect preserved. At the
    /// scale of a walk the error against a real map projection is invisible.
    static func project(_ points: [TrackCoordinate], in frame: CGRect) -> [[CGPoint]] {
        guard points.count > 1 else { return [] }
        let meanLat = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let k = cos(meanLat * .pi / 180)
        let xs = points.map { $0.longitude * k }
        let ys = points.map(\.latitude)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let spanX = max(maxX - minX, 1e-9), spanY = max(maxY - minY, 1e-9)
        let scale = min(frame.width / spanX, frame.height / spanY)
        let offsetX = frame.minX + (frame.width - spanX * scale) / 2
        let offsetY = frame.minY + (frame.height - spanY * scale) / 2
        var segments: [[CGPoint]] = []
        var current = -1
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: offsetX + (xs[index] - minX) * scale,
                            y: offsetY + (maxY - ys[index]) * scale)
            if point.segment != current {
                segments.append([p])
                current = point.segment
            } else {
                segments[segments.count - 1].append(p)
            }
        }
        return segments
    }
}

private extension CGSize {
    func insetBy(_ inset: CGFloat) -> CGRect {
        CGRect(x: inset, y: inset, width: max(width - inset * 2, 1), height: max(height - inset * 2, 1))
    }
}
