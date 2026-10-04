import SwiftUI

public struct OnboardingStep: Identifiable, Sendable {
    public let id: Int
    public let imageName: String
    public let title: String
    public let description: String

    public static let defaultSteps: [OnboardingStep] = [
        OnboardingStep(
            id: 0,
            imageName: "OnboardingWalk",
            title: "Suivez ses balades",
            description: "Enregistrez vos promenades au quotidien, gardez un journal clair de sa durée et de ses sorties."
        ),
        OnboardingStep(
            id: 1,
            imageName: "OnboardingRoutine",
            title: "Comprenez son rythme",
            description: "Observez les habitudes de votre chien et adaptez ses promenades à ses besoins sans pression."
        ),
        OnboardingStep(
            id: 2,
            imageName: "OnboardingCommunity",
            title: "Rencontrez sa communauté",
            description: "Trouvez des compagnons de promenade près de chez vous et organisez des balades en petit groupe."
        )
    ]
}

@MainActor
public struct OnboardingView: View {
    private let steps: [OnboardingStep]
    private let onComplete: () -> Void

    @State private var currentStep = 0

    public init(steps: [OnboardingStep] = OnboardingStep.defaultSteps, onComplete: @escaping () -> Void) {
        self.steps = steps
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: TruffloTheme.Spacing.medium) {
            HStack {
                Spacer()
                Button("Passer") {
                    onComplete()
                }
                .font(.truffloSubheadline)
                .foregroundStyle(Color.truffloForest)
                .padding(.trailing, TruffloTheme.Spacing.medium)
                .padding(.top, TruffloTheme.Spacing.small)
            }

            TabView(selection: $currentStep) {
                ForEach(steps) { step in
                    VStack(spacing: TruffloTheme.Spacing.large) {
                        Image(step.imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280, maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: TruffloTheme.Radius.card, style: .continuous))

                        VStack(spacing: TruffloTheme.Spacing.small) {
                            Text(step.title)
                                .font(.truffloTitle)
                                .foregroundStyle(Color.truffloForest)
                                .multilineTextAlignment(.center)

                            Text(step.description)
                                .font(.truffloBody)
                                .foregroundStyle(Color.truffloCharcoal.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, TruffloTheme.Spacing.medium)
                        }
                    }
                    .tag(step.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            VStack(spacing: TruffloTheme.Spacing.small) {
                Button(currentStep == steps.count - 1 ? "Commencer" : "Suivant") {
                    if currentStep < steps.count - 1 {
                        withAnimation { currentStep += 1 }
                    } else {
                        onComplete()
                    }
                }
                .buttonStyle(.truffloPrimary)
            }
            .padding(.horizontal, TruffloTheme.Spacing.large)
            .padding(.bottom, TruffloTheme.Spacing.large)
        }
        .background(Color.truffloSand.ignoresSafeArea())
    }
}
