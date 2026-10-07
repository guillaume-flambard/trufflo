import SwiftUI

/// Signal state as the walk screen describes it: a dot and a word.
///
/// The status is never carried by colour alone. Every case has its own wording, so
/// the screen reads correctly in greyscale and to VoiceOver. It draws no surface of
/// its own: it sits inside the walk control surface, and a pill inside a glass
/// panel would be one material too many.
public struct TruffloGPSIndicator: View {
    public enum State: Equatable {
        /// Fixes arriving and accepted.
        case strong
        /// Looking for the first fix.
        case searching
        /// Fixes arriving but of poor quality.
        case weak
        /// The person paused the walk.
        case paused
        /// The walk was cut short and can be resumed or finished. "Interrompue",
        /// never "Arrêté": the state is recoverable, and the word must say so.
        case interrupted

        /// `strong` reads "Actif" rather than "GPS": the word names the state, and the
        /// journeys wait on that exact string to know the signal is live.
        public var label: String {
            switch self {
            case .strong: "Actif"
            case .searching: "Recherche"
            case .weak: "Faible"
            case .paused: "En pause"
            case .interrupted: "Interrompue"
            }
        }

        var dotColor: Color {
            switch self {
            case .strong: return .truffloSage
            case .searching: return .truffloSlate
            case .weak: return .truffloAmber
            case .paused: return .truffloSlate
            case .interrupted: return .truffloDanger
            }
        }
    }

    private let state: State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ state: State) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.dotColor)
                .frame(width: 8, height: 8)
            Text(state.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.truffloForest)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .animation(TruffloTheme.Motion.selection(reduceMotion: reduceMotion), value: state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signal GPS : \(state.label)")
        .accessibilityValue(state.label)
        .accessibilityIdentifier("walk.signal")
        .accessibilityAddTraits(.isStaticText)
    }
}

/// The two measurements of a walk, side by side inside the control surface:
/// elapsed time and recorded distance, nothing else. A third metric needs a
/// deliberate decision backed by user research, not a wider row.
///
/// The spoken label of each value is the value itself. The UI journeys read these
/// labels and parse them, and a screen that shows almost no words must not speak
/// a caption it does not show.
public struct TruffloWalkMetrics: View {
    private let durationText: String
    private let distanceText: String
    private let distanceIsMeasured: Bool

    public init(durationText: String, distanceText: String, distanceIsMeasured: Bool) {
        self.durationText = durationText
        self.distanceText = distanceText
        self.distanceIsMeasured = distanceIsMeasured
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TruffloTheme.Spacing.medium) {
            metric(value: durationText, caption: "Durée", identifier: "walk.timer", dimmed: false)
            Rectangle()
                .fill(Color.truffloForest.opacity(0.18))
                .frame(width: 1, height: 36)
                .accessibilityHidden(true)
            metric(value: distanceText, caption: "Distance", identifier: "walk.distance",
                   dimmed: !distanceIsMeasured)
        }
    }

    private func metric(value: String, caption: String, identifier: String, dimmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.truffloFigure(.largeTitle))
                // Tabular figures, or the row jitters on every tick.
                .monospacedDigit()
                .foregroundStyle(dimmed ? Color.truffloSlate : Color.truffloForest)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                // No `accessibilityElement(children: .ignore)` here: on a Text it
                // turns the element into a generic container, and the journeys
                // query `staticTexts["walk.timer"]`.
                .accessibilityLabel(value)
                .accessibilityIdentifier(identifier)
                .accessibilityAddTraits(.updatesFrequently)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Color.truffloSlate)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
