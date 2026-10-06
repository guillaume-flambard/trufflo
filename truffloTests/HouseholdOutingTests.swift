import Foundation
import Testing
@testable import trufflo

/// B-AC-06, B-AC-07: Today names the household's latest outing only when it
/// is news, and never one that is the same outing as mine.
@Suite("Household outing on Today")
struct HouseholdOutingTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func candidate(_ hours: Double, id: UUID = UUID(), duplicate: Bool = false) -> HouseholdOuting.Candidate {
        .init(id: id, endedAt: t0.addingTimeInterval(hours * 3600), isPossibleDuplicate: duplicate)
    }

    @Test func theNewestOutingAfterMineIsShown() {
        let newest = UUID()
        let result = HouseholdOuting.latest([candidate(1), candidate(3, id: newest), candidate(2)],
                                            myLastEndedAt: t0)
        #expect(result == newest)
    }

    @Test func anOutingOlderThanMineIsNotNews() {
        #expect(HouseholdOuting.latest([candidate(-1)], myLastEndedAt: t0) == nil)
    }

    @Test func aPossibleDuplicateOfMineIsSkipped() {
        let other = UUID()
        let result = HouseholdOuting.latest([candidate(5, duplicate: true), candidate(2, id: other)], myLastEndedAt: t0)
        #expect(result == other)
    }

    @Test func withNoWalkOfMineAnyOutingIsNews() {
        let only = UUID()
        #expect(HouseholdOuting.latest([candidate(-48, id: only)], myLastEndedAt: nil) == only)
    }

    @Test func noOutingNoBlock() {
        #expect(HouseholdOuting.latest([], myLastEndedAt: t0) == nil)
    }
}
