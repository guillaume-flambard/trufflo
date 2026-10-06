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
            description: "Lancez une balade : la durée et le parcours s'enregistrent pendant que vous marchez."
        ),
        OnboardingStep(
            id: 1,
            title: "Un carnet, pas un score.",
            description: "Chaque sortie rejoint son journal. Aucun objectif, aucun classement : ce que vous avez vécu ensemble."
        ),
        OnboardingStep(
            id: 2,
            title: "Tout reste sur cet iPhone.",
            description: "Pas de compte, rien de publié. La position ne sert que pendant une balade que vous avez lancée."
        )
    ]
}

/// Three pages, three compositions: the route on forest, the journal as an
/// object, the device as the place the data lives. The last button leads
/// straight to the next action rather than to a generic "Start".
@MainActor
public struct OnboardingView: View {
    private let steps: [OnboardingStep]
    private let onComplete: () -> Void

    @State private var currentStep = 0

    public init(steps: [OnboardingStep] = OnboardingStep.defaultSteps, onComplete: @escaping () -> Void) {
        self.steps = steps
        self.onComplete = onComplete
    }

    private var isFirst: Bool { currentStep == 0 }
    private var isLast: Bool { currentStep == steps.count - 1 }

    public var body: some View {
        ZStack(alignment: .top) {
            (isFirst ? Color.truffloForest : Color.truffloSand)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: currentStep)

            TabView(selection: $currentStep) {
                ForEach(steps) { step in
                    page(step).tag(step.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack {
                Spacer()
                Button("Passer", action: onComplete)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isFirst ? Color.truffloMint : Color.truffloForest)
                    .frame(minHeight: 44)
                    .padding(.trailing, TruffloTheme.Spacing.large)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: TruffloTheme.Spacing.medium) {
                HStack(spacing: 8) {
                    ForEach(steps) { step in
                        Capsule()
                            .fill(step.id == currentStep
                                  ? (isFirst ? Color.white : Color.truffloForest)
                                  : (isFirst ? Color.white.opacity(0.3) : Color.truffloForest.opacity(0.2)))
                            .frame(width: step.id == currentStep ? 22 : 8, height: 8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(currentStep + 1) sur \(steps.count)")

                Button {
                    if isLast { onComplete() } else { withAnimation { currentStep += 1 } }
                } label: {
                    Text(isLast ? "Ajouter mon chien" : "Suivant")
                        .font(.headline)
                        .foregroundStyle(isFirst ? Color.truffloForest : Color.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(isFirst ? Color.white : Color.truffloForest,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, TruffloTheme.Spacing.large)
            .padding(.bottom, TruffloTheme.Spacing.medium)
        }
        // Light status bar on the forest page, dark on the sand ones.
        .preferredColorScheme(isFirst ? .dark : .light)
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
                .foregroundStyle(step.id == 0 ? Color.white : Color.truffloForest)
                .fixedSize(horizontal: false, vertical: true)
            Text(step.description)
                .font(.body)
                .foregroundStyle(step.id == 0 ? Color.truffloMint : Color.truffloSlate)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: TruffloTheme.Spacing.large)
        }
        .padding(.horizontal, TruffloTheme.Spacing.large)
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
            context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 10)
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
            context.stroke(route, with: .color(.white),
                           style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            context.fill(Path(ellipseIn: CGRect(x: start.x - 10, y: start.y - 10, width: 20, height: 20)),
                         with: .color(Color.truffloForest))
            context.stroke(Path(ellipseIn: CGRect(x: start.x - 10, y: start.y - 10, width: 20, height: 20)),
                           with: .color(.white), lineWidth: 4)
            context.fill(Path(ellipseIn: CGRect(x: end.x - 12, y: end.y - 12, width: 24, height: 24)),
                         with: .color(Color.truffloPeach))
        }
    }

    /// Two real journal cards, laid like pages: the promise is read on the object.
    private var journalStack: some View {
        VStack(spacing: TruffloTheme.Spacing.small) {
            sampleCard(when: "aujourd'hui, 08:15", title: "Balade du matin", detail: "38 min")
                .rotationEffect(.degrees(-2))
            sampleCard(when: "hier, 18:42", title: "Balade du soir", detail: "Il a croisé un labrador.")
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
        .shadow(color: Color.truffloForestDeep.opacity(0.08), radius: 14, y: 8)
    }

    /// The phone as the place the data lives.
    private var deviceMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.truffloMint.opacity(0.45))
            Circle()
                .fill(Color.truffloSand)
                .frame(width: 180, height: 180)
                .overlay(Image(systemName: "iphone.gen3")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color.truffloForest))
        }
    }
}
