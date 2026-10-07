import Foundation
import Testing
@testable import trufflo

@Test func dailyTipFollowsServerOrderOneStepPerDay() {
    let tips = [DailyTip(position: 2, title: "B", body: "b"), DailyTip(position: 1, title: "A", body: "a")]
    #expect(DailyTips.pick(from: tips, dayNumber: 0)?.title == "A")
    #expect(DailyTips.pick(from: tips, dayNumber: 1)?.title == "B")
    #expect(DailyTips.pick(from: tips, dayNumber: 2)?.title == "A")
    #expect(DailyTips.pick(from: tips, dayNumber: -1)?.title == "B")
}

@Test func noTipIsShownWhenNoneWasEverRead() {
    #expect(DailyTips.pick(from: [], dayNumber: 3) == nil)
    #expect(DailyTips.decodeCache(nil).isEmpty)
    #expect(DailyTips.decodeCache(Data("not json".utf8)).isEmpty)
}

@Test func tipCacheRoundTrips() {
    let tips = [DailyTip(position: 1, title: "Pensez à l'eau.", body: "Une gourde suffit.")]
    #expect(DailyTips.decodeCache(DailyTips.encodeCache(tips)) == tips)
}
