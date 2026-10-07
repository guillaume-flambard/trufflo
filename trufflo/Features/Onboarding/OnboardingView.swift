import SwiftUI

/// The three promises of the introduction, kept as data so they can be checked:
/// each one describes something the app does today, nothing it might do later.
public struct OnboardingStep: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let description: String

    public static let defaultSteps: [OnboardingStep] = [
        OnboardingStep(
            id: 0,
            title: "Partez. Le chemin s'écrit tout seul.",
            description: "Lancez une balade : la durée et le tracé s'enregistrent pendant que vous marchez."
        ),
        OnboardingStep(
            id: 1,
            title: "Un journal, pas un score.",
            description: "Chaque balade rejoint son journal. Aucun classement, et une routine seulement si vous la choisissez."
        ),
        OnboardingStep(
            id: 2,
            title: "Votre journal reste sur cet iPhone.",
            description: "Si vous créez ou rejoignez un foyer, seuls les résumés de balade sont partagés. La position ne sert que pendant une balade que vous avez lancée."
        )
    ]
}

/// What the last button of the introduction does. With no dog yet it leads
/// straight to the form, so its label is a promise kept; replayed from the
/// settings with a dog already there, it only closes, and says so.
public enum OnboardingExit: Equatable, Sendable {
    case addFirstDog
    case close

    public init(hasDogs: Bool) { self = hasDogs ? .close : .addFirstDog }

    public var buttonTitle: String {
        switch self {
        case .addFirstDog: "Ajouter mon chien"
        case .close: "Terminer"
        }
    }
}

/// Three pages, three compositions: the route on a street grid, the journal as
/// an object, the device as the place the data lives. All three on the sand and
/// mint aura the app itself opens on: a first page in solid forest made the step
/// into the app feel like going from night to day (2026-10-07 review). The last button leads
/// straight to the next action rather than to a generic "Start".
@MainActor
public struct OnboardingView: View {
    private let steps: [OnboardingStep]
    private let exit: OnboardingExit
    /// `true` when the person pressed the last button, `false` when they skipped:
    /// skipping the introduction is not asking to add a dog.
    private let onComplete: (_ tookFinalAction: Bool) -> Void

    @State private var currentStep = 0

    public init(steps: [OnboardingStep] = OnboardingStep.defaultSteps,
                exit: OnboardingExit = .addFirstDog,
                onComplete: @escaping (_ tookFinalAction: Bool) -> Void) {
        self.steps = steps
        self.exit = exit
        self.onComplete = onComplete
    }

    private var isLast: Bool { currentStep == steps.count - 1 }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.truffloSand.ignoresSafeArea()
            TruffloDogAura(photoData: nil)
                .frame(height: 520)
                .ignoresSafeArea(edges: .top)

            TabView(selection: $currentStep) {
                ForEach(steps) { step in
                    page(step).tag(step.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack {
                Spacer()
                Button("Passer") { onComplete(false) }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.truffloForest)
                    .frame(minHeight: 44)
                    .padding(.trailing, TruffloTheme.Spacing.screen)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: TruffloTheme.Spacing.medium) {
                HStack(spacing: 8) {
                    ForEach(steps) { step in
                        Capsule()
                            .fill(step.id == currentStep ? Color.truffloForest : Color.truffloForest.opacity(0.2))
                            .frame(width: step.id == currentStep ? 22 : 8, height: 8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(currentStep + 1) sur \(steps.count)")

                Button {
                    if isLast { onComplete(true) } else { withAnimation { currentStep += 1 } }
                } label: {
                    // The same anchored capsule as "Démarrer une balade" and "Ajouter
                    // mon chien", so the first button met is the one met every day.
                    Text(isLast ? exit.buttonTitle : "Suivant")
                        .font(.truffloBodyHeavy)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(Color.truffloForest)
                .truffloTap()
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
            .padding(.bottom, TruffloTheme.Spacing.medium)
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private func page(_ step: OnboardingStep) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.medium) {
            illustration(for: step.id)
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .accessibilityHidden(true)
            Spacer(minLength: TruffloTheme.Spacing.medium)
            Text(step.title)
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.truffloForest)
                .fixedSize(horizontal: false, vertical: true)
            Text(step.description)
                .font(.body)
                .foregroundStyle(Color.truffloSlate)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: TruffloTheme.Spacing.large)
        }
        .padding(.horizontal, TruffloTheme.Spacing.screen)
        .padding(.top, 60)
    }

    @ViewBuilder
    private func illustration(for id: Int) -> some View {
        switch id {
        case 0: routeDrawing
        case 1: journalStack
        default: deviceMark
        }
    }

    /// A route drawn over a street grid, the start open, the end in peach.
    private var routeDrawing: some View {
        Canvas { context, size in
            var grid = Path()
            for fraction in [0.25, 0.5, 0.75] {
                grid.move(to: CGPoint(x: 0, y: size.height * fraction))
                grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                grid.move(to: CGPoint(x: size.width * fraction, y: 0))
                grid.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
            }
            context.stroke(grid, with: .color(Color.truffloForest.opacity(0.07)), lineWidth: 10)
            var route = Path()
            let start = CGPoint(x: size.width * 0.18, y: size.height * 0.85)
            let end = CGPoint(x: size.width * 0.78, y: size.height * 0.16)
            route.move(to: start)
            route.addCurve(to: CGPoint(x: size.width * 0.5, y: size.height * 0.55),
                           control1: CGPoint(x: size.width * 0.24, y: size.height * 0.62),
                           control2: CGPoint(x: size.width * 0.38, y: size.height * 0.6))
            route.addCurve(to: end,
                           control1: CGPoint(x: size.width * 0.66, y: size.height * 0.48),
                           control2: CGPoint(x: size.width * 0.52, y: size.height * 0.2))
            // Drawn like the routes of the journal: forest line, open start, filled end.
            context.stroke(route, with: .color(Color.truffloForest),
                           style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            context.fill(Path(ellipseIn: CGRect(x: start.x - 10, y: start.y - 10, width: 20, height: 20)),
                         with: .color(.white))
            context.stroke(Path(ellipseIn: CGRect(x: start.x - 10, y: start.y - 10, width: 20, height: 20)),
                           with: .color(Color.truffloForest), lineWidth: 4)
            context.fill(Path(ellipseIn: CGRect(x: end.x - 12, y: end.y - 12, width: 24, height: 24)),
                         with: .color(Color.truffloPeach))
        }
    }

    /// Two real journal cards, laid like pages: the promise is read on the object.
    private var journalStack: some View {
        VStack(spacing: TruffloTheme.Spacing.small) {
            // Read like the journal reads: the dog is the title, never a name made
            // from the hour ("Balade du matin" left the journal on 2026-10-06).
            sampleCard(when: "aujourd'hui, 08:15", title: "Oslo", detail: "38 min")
                .rotationEffect(.degrees(-2))
            sampleCard(when: "hier, 18:42", title: "Oslo", detail: "Il a croisé un labrador.")
                .rotationEffect(.degrees(1.5))
                .padding(.leading, 24)
        }
        .padding(.top, TruffloTheme.Spacing.large)
    }

    private func sampleCard(when: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(when).font(.footnote).foregroundStyle(Color.truffloSlate)
            Text(title).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(Color.truffloForest)
            Text(detail).font(.subheadline).foregroundStyle(Color.truffloCharcoal)
        }
        .padding(TruffloTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))
        .shadow(color: Color.truffloForest.opacity(0.10), radius: 18, x: 0, y: 8)
    }

    /// The phone as the place the data lives.
    private var deviceMark: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .shadow(color: Color.truffloForest.opacity(0.10), radius: 18, x: 0, y: 8)
                .frame(width: 180, height: 180)
                .overlay(Image(systemName: "iphone.gen3")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color.truffloForest))
        }
    }
}
