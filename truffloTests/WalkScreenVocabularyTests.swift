import Foundation
import Testing
@testable import trufflo

/// The words the walk screen is allowed to show. They are pinned here because the
/// UI journeys and VoiceOver both depend on them, and because the brief forbids
/// "Arrêté": an interruption is a state the person recovers from.
@Suite("Walk screen vocabulary")
struct WalkScreenVocabularyTests {
    @Test("An interrupted walk reads « Interrompue », never « Arrêté »")
    func interruptedReadsInterrompue() {
        #expect(TruffloGPSIndicator.State.interrupted.label == "Interrompue")
        let allLabels = [TruffloGPSIndicator.State.strong, .searching, .weak, .paused, .interrupted]
            .map(\.label)
        #expect(!allLabels.contains("Arrêté"))
        #expect(Set(allLabels).count == allLabels.count, "chaque état a son propre mot")
    }

    @Test("The clock reads mm:ss and grows to hh:mm:ss after an hour")
    func clockFormat() {
        #expect(WalkFormatting.clock(0) == "00:00")
        #expect(WalkFormatting.clock(309) == "05:09")
        #expect(WalkFormatting.clock(3_661) == "01:01:01")
    }

    @Test("An absent distance reads « Non mesurée », never a zero")
    func distanceFormat() {
        #expect(WalkFormatting.distance(nil) == "Non mesurée")
        #expect(WalkFormatting.distance(614) == "614 m")
        #expect(WalkFormatting.distance(1_800) == "1,8 km")
    }
}
