import SwiftUI

/// Trufflo Design System Tokens & Branding
public enum TruffloTheme {
    // MARK: - Color Tokens
    public enum Colors {
        /// Forêt (#1E4D3B) - Primary brand green
        public static let forest = Color("ForestColor", bundle: .main)
        /// Sauge (#4CAF7B) - Secondary action green
        public static let sage = Color("SageColor", bundle: .main)
        /// Menthe (#A7D7C5) - Soft background green
        public static let mint = Color("MintColor", bundle: .main)
        /// Sable (#F7F4ED) - Primary app warm background
        public static let sand = Color("SandColor", bundle: .main)
        /// Pêche (#FFB38A) - Warm accent
        public static let peach = Color("PeachColor", bundle: .main)
        /// Terracotta (#D97656) - Earthy accent
        public static let terracotta = Color("TerracottaColor", bundle: .main)
        /// Ciel (#A7C7E7) - Soft sky blue
        public static let sky = Color("SkyColor", bundle: .main)
        /// Chocolat (#5C4033) - Warm brown text/elements
        public static let chocolate = Color("ChocolateColor", bundle: .main)
        /// Charbon (#2D2D2D) - High contrast dark text
        public static let charcoal = Color("CharcoalColor", bundle: .main)
        /// Terracotta foncée (#A94A2A) - Terminal actions and error text.
        ///
        /// The original terracotta (#D97656) tops out at 2.9:1 on sand and 3.1:1 as
        /// white text, so it works as an accent and nothing else. This darker variant
        /// reaches 5.1:1 on sand and 5.6:1 as white text, which is what a button
        /// label or an error message needs.
        public static let danger = Color("DangerColor", bundle: .main)
        /// Ambre (#B45309) - Weak GPS signal.
        public static let amber = Color("AmberColor", bundle: .main)
        /// Ardoise (#5B6472) - Legends and metadata.
        public static let slate = Color("SlateColor", bundle: .main)
        /// Forest profond (#14382B) - Opaque replacement for glass under
        /// Reduce Transparency, where a blurred surface is not legible.
        public static let forestDeep = Color(red: 20 / 255, green: 56 / 255, blue: 43 / 255)
    }

    // MARK: - Spacing Tokens
    public enum Spacing {
        public static let xxSmall: CGFloat = 4
        public static let xSmall: CGFloat = 8
        public static let small: CGFloat = 12
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 24
        public static let xLarge: CGFloat = 32
        public static let xxLarge: CGFloat = 48
        /// The side gutter of every screen. The system's large titles ("Journal",
        /// "Mes chiens") and the anchored start button sit 16 pt from the edge; content
        /// set at 24 next to them read as a second grid (2026-10-07 review). One gutter,
        /// everywhere a screen lays out its own content.
        public static let screen: CGFloat = 16
    }

    // MARK: - Corner Radius Tokens
    // Three roles, no other value (ART-DIRECTION §3.3, tightened 2026-10-07 after an
    // audit found fourteen different radii in the code):
    //   - controls (buttons, chips): a capsule, never a radius;
    //   - objects (a card, a tile, a panel): `card`;
    //   - what sits inside an object (a thumbnail, a field): `medium`, which is
    //     `card` minus the padding that separates them, so the curves stay concentric.
    public enum Radius {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 12
        public static let large: CGFloat = 16
        public static let card: CGFloat = 24
        public static let pill: CGFloat = 999
    }

    // MARK: - Motion Tokens
    // Spring-based, one curve per intent, so no component hardcodes its own
    // duration (an audit of 2026-10-07 found two components doing exactly that,
    // with two different values for the same "press" feeling). HIG Motion: brief,
    // precise, tied to what changes — never a decorative loop. Every curve takes
    // `reduceMotion` explicitly instead of reading the environment itself, so a
    // component applies it at its own call site.
    public enum Motion {
        /// A tap's feedback: a button, a chip, a clear-field control. Disabled
        /// outright under Reduce Motion since it carries no information.
        public static func press(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7)
        }
        /// How far a pressed control shrinks. 0.98 measured as imperceptible in
        /// practice (2026-10-07 device check): a 358pt button only loses ~7px,
        /// well under what a thumb registers. 0.94 is the first value that reads
        /// as a clear depress without looking like a bounce.
        public static let pressScale: CGFloat = 0.94
        /// A state change that is information, not decoration: a selection that
        /// moves, a signal word that changes, an icon that replaces another.
        /// Reduced to an instant fade rather than removed, because the change
        /// itself still needs to read.
        public static func selection(reduceMotion: Bool) -> Animation? {
            reduceMotion ? .linear(duration: 0.05) : .spring(response: 0.35, dampingFraction: 0.82)
        }
        /// Content arriving for the first time: a photo once it decodes, a
        /// control appearing. Disabled under Reduce Motion; the content is just
        /// there on the next frame.
        public static func appear(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)
        }
    }
}

// MARK: - Color Convenience Extensions
public extension Color {
    static var truffloForest: Color { TruffloTheme.Colors.forest }
    static var truffloSage: Color { TruffloTheme.Colors.sage }
    static var truffloMint: Color { TruffloTheme.Colors.mint }
    static var truffloSand: Color { TruffloTheme.Colors.sand }
    static var truffloPeach: Color { TruffloTheme.Colors.peach }
    static var truffloTerracotta: Color { TruffloTheme.Colors.terracotta }
    static var truffloSky: Color { TruffloTheme.Colors.sky }
    static var truffloChocolate: Color { TruffloTheme.Colors.chocolate }
    static var truffloCharcoal: Color { TruffloTheme.Colors.charcoal }
    static var truffloDanger: Color { TruffloTheme.Colors.danger }
    static var truffloAmber: Color { TruffloTheme.Colors.amber }
    static var truffloSlate: Color { TruffloTheme.Colors.slate }
    static var truffloForestDeep: Color { TruffloTheme.Colors.forestDeep }
}

// MARK: - Typography Extensions
// Built on text styles so every size follows Dynamic Type.
public extension Font {
    static var truffloTitle: Font { .system(.title, design: .rounded, weight: .bold) }
    static var truffloHeadline: Font { .system(.title3, design: .rounded, weight: .semibold) }
    static var truffloSubheadline: Font { .system(.body, design: .rounded, weight: .medium) }
    static var truffloBody: Font { .system(.callout, design: .rounded, weight: .regular) }
    static var truffloCaption: Font { .system(.footnote, design: .rounded, weight: .regular) }
}

// MARK: - The type scale of Today
// Four sizes and two weights, no more: the figure, the title, the body and the meta;
// heavy for what names or leads, regular for what explains. A screen with ten sizes has
// no hierarchy, only noise (mobile-app-ui-design skill, step 3; audit of 2026-10-07
// counted ten sizes and five weights on Today). The figure (the week's number) is the
// one size set by its own component, scaled with Dynamic Type.
public extension Font {
    /// A name or a figure that leads: the dog, a walk's duration, the welcome line.
    static var truffloTitleHeavy: Font { .system(.title, design: .rounded, weight: .heavy) }
    /// A heading of a block, a label that names, a button.
    static var truffloBodyHeavy: Font { .system(.body, design: .rounded, weight: .heavy) }
    /// A sentence: a note, an explanation, a secondary line.
    static var truffloBodyRegular: Font { .system(.body) }
    /// A hour, a day, a source: what is read in passing.
    static var truffloMeta: Font { .system(.footnote) }
}

// MARK: - Screen chrome
public extension View {
    /// The one background and tint every list or form screen shares, so that
    /// Today, Journal, Dogs, detail and form screens read as the same app.
    func truffloScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.truffloSand.ignoresSafeArea())
            .tint(Color.truffloForest)
    }

    /// Legends, footers and metadata.
    func truffloSecondaryText() -> some View {
        self.font(.truffloCaption).foregroundStyle(Color.truffloSlate)
    }

    /// Haptic feedback for a tap, without owning the button's visual style.
    ///
    /// For native-styled buttons (`.glassProminent`, `.glass`, `.bordered`…) that
    /// already get the system's own press visuals but no haptic: a
    /// `simultaneousGesture` fires alongside the button's own tap handling
    /// instead of replacing it, so this attaches to any `Button` with no change
    /// to its action closure or appearance.
    func truffloTap(_ feedback: SensoryFeedback = .impact(weight: .light)) -> some View {
        modifier(TruffloTactileTap(feedback: feedback))
    }
}

private struct TruffloTactileTap: ViewModifier {
    let feedback: SensoryFeedback
    @State private var tick = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(TapGesture().onEnded { tick.toggle() })
            .sensoryFeedback(feedback, trigger: tick)
    }
}

public extension View {
    /// Error text: always readable (5:1 on sand) and never colour alone, the
    /// caller supplies the explicit sentence.
    func truffloErrorText() -> some View {
        self.font(.truffloCaption).foregroundStyle(Color.truffloDanger)
    }
}
