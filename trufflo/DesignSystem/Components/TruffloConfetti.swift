import SwiftUI

/// A short burst of confetti at the end of a balade (2026-10-07 board): drawn
/// once, about two seconds, then still. Never a loop; off under Reduce Motion
/// (the caller passes `isOn: false`).
struct TruffloConfetti: View {
    let isOn: Bool
    @State private var start: Date?
    @State private var done = false

    private struct Piece {
        let x: CGFloat, angle: Double, speed: CGFloat, spin: Double, color: Color, size: CGFloat, round: Bool
    }

    private static let colors: [Color] = [.truffloPeach, .truffloSage, .truffloForest,
                                          Color(red: 0.98, green: 0.78, blue: 0.3), .truffloSky]
    private let pieces: [Piece] = (0..<36).map { index in
        let t = Double(index) / 36
        return Piece(x: CGFloat((t * 7.3).truncatingRemainder(dividingBy: 1)),
                     angle: -.pi / 2 + (t - 0.5) * 2.2,
                     speed: 120 + CGFloat((index * 37) % 90),
                     spin: Double((index * 53) % 360),
                     color: colors[index % colors.count],
                     size: 4 + CGFloat(index % 4),
                     round: index % 3 == 0)
    }

    var body: some View {
        TimelineView(.animation(paused: start == nil || done)) { timeline in
            Canvas { context, size in
                guard let start, !done else { return }
                let t = min(timeline.date.timeIntervalSince(start), 2.2)
                let fade = max(0, 1 - t / 2.2)
                for piece in pieces {
                    let origin = CGPoint(x: size.width * (0.2 + piece.x * 0.6), y: size.height * 0.75)
                    let vx = cos(piece.angle) * piece.speed, vy = sin(piece.angle) * piece.speed
                    let point = CGPoint(x: origin.x + vx * t, y: origin.y + vy * t + 90 * t * t)
                    var item = context
                    item.opacity = fade
                    item.translateBy(x: point.x, y: point.y)
                    item.rotate(by: .degrees(piece.spin + t * 300))
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 2, width: piece.size, height: piece.size * (piece.round ? 1 : 1.8))
                    item.fill(piece.round ? Path(ellipseIn: rect) : Path(rect), with: .color(piece.color))
                }
            }
        }
        .accessibilityHidden(true)
        .onChange(of: isOn, initial: true) { _, on in
            guard on, start == nil else { return }
            start = .now
            Task { try? await Task.sleep(for: .seconds(2.3)); done = true }
        }
    }
}
