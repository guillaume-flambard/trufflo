import SwiftUI

/// The head of every screen but Today (2026-10-07 board): the title in forest,
/// heavy and rounded, one line of slate under it, and at most one round glass
/// button on the right. One head, so no two screens open differently.
struct TruffloScreenHeader: View {
    let title: String
    var subtitle: String? = nil
    var action: Action? = nil

    struct Action {
        let systemImage: String
        let label: String
        let identifier: String
        let perform: () -> Void
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.truffloScreenTitle)
                    .foregroundStyle(Color.truffloForest)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.truffloSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if let action {
                TruffloRoundButton(systemImage: action.systemImage, label: action.label,
                                   identifier: action.identifier, action: action.perform)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The round glass button of the screen heads and of the bars over a photo or a
/// map: back, close, add, settings, share. One size, one material.
struct TruffloRoundButton: View {
    let systemImage: String
    let label: String
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.truffloForest)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(Color.white.opacity(0.7)).interactive(), in: Circle())
        }
        .buttonStyle(TruffloPressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// A section title inside a screen: "Dernière balade", "Photos", a day of the
/// Journal. Always forest, always this size.
struct TruffloSectionTitle: View {
    let text: String
    var trailing: (title: String, action: () -> Void)? = nil

    init(_ text: String, trailing: (title: String, action: () -> Void)? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.truffloSectionTitle)
                .foregroundStyle(Color.truffloForest)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing {
                Button(action: trailing.action) {
                    HStack(spacing: 3) {
                        Text(trailing.title)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Color.truffloSlate)
                }
                .buttonStyle(TruffloPressStyle())
            }
        }
    }
}

/// Figures in one white row, separated by hairlines: an icon, the value, its
/// label. The one way a balade's figures are drawn, on every screen.
struct TruffloFigureRow: View {
    struct Figure {
        let systemImage: String
        let value: String
        let label: String
        var identifier: String? = nil
    }

    let figures: [Figure]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(figures.enumerated()), id: \.offset) { index, figure in
                if index > 0 {
                    Rectangle().fill(Color.truffloForest.opacity(0.12)).frame(width: 1, height: 40)
                }
                VStack(spacing: 3) {
                    Image(systemName: figure.systemImage)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.truffloForest)
                    Text(figure.value)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: figure.value)
                        .foregroundStyle(Color.truffloForest)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(figure.label)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.truffloSlate)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(figure.identifier ?? "")
            }
        }
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }
}

extension Font {
    /// The title of a screen head.
    static let truffloScreenTitle = Font.system(size: 30, weight: .heavy, design: .rounded)
    /// A section title inside a screen.
    static let truffloSectionTitle = Font.system(size: 17, weight: .bold, design: .rounded)
}

/// The day and hour of a balade, written the same way on every screen:
/// "Aujourd'hui · 17:48", "Dimanche 4 oct. · 16:02".
extension WalkFormatting {
    static func dayDotTime(_ date: Date) -> String {
        "\(relativeDay(date).capitalizedFirst) · \(time(date))"
    }

    /// "Il y a 5 h": how long ago the last balade ended, on Today and on the dog page.
    static func ago(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated).locale(TruffloLocale.french))
            .capitalizedFirst
    }
}

/// The three tiles' colours, so a figure has the same symbol and ink everywhere.
enum TruffloTileInk {
    static let walks = Color(red: 0.18, green: 0.42, blue: 0.31)
    static let time = Color(red: 0.85, green: 0.58, blue: 0.17)
    static let last = Color(red: 0.23, green: 0.61, blue: 0.44)
}

extension View {
    /// The fade behind a button pinned to the bottom of a screen, so the content
    /// scrolling under it never collides with its label.
    func truffloBottomBarFade() -> some View {
        background(alignment: .bottom) {
            LinearGradient(stops: [.init(color: Color.truffloSand.opacity(0), location: 0),
                                   .init(color: Color.truffloSand.opacity(0.92), location: 0.45),
                                   .init(color: Color.truffloSand, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .padding(.top, -28)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }
}
