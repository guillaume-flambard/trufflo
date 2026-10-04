import Testing
import SwiftUI
@testable import trufflo

@Suite("Design System Component Tests")
struct ComponentTests {
    @Test("Onboarding steps are properly initialized")
    func testOnboardingSteps() {
        let steps = OnboardingStep.defaultSteps
        #expect(steps.count == 3)
        #expect(steps[0].imageName == "OnboardingWalk")
        #expect(steps[1].imageName == "OnboardingRoutine")
        #expect(steps[2].imageName == "OnboardingCommunity")
    }

    @Test("TruffloBadge styles are initialized without crashing")
    func testBadgeInitialization() {
        let badge = TruffloBadge("Chiens", icon: "pawprint", style: .sage)
        #expect(badge != nil)
    }

    @Test("Form controls initialize correctly")
    @MainActor
    func testFormControls() {
        let textBinding = Binding.constant("Oslo")
        let selectionBinding = Binding.constant("Balades")
        let textField = TruffloTextField("Nom", text: textBinding)
        let segmented = TruffloSegmentedControl(items: ["Balades", "Profil"], selection: selectionBinding, titleKeyPath: \.self)
        #expect(textField != nil)
        #expect(segmented != nil)
    }
}
