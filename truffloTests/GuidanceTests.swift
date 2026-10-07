import Foundation
import Testing
@testable import trufflo

private let steps = [
    GuidanceStep(latitude: 48.8800, longitude: 2.3830, instruction: "Tournez à droite"),
    GuidanceStep(latitude: 48.8810, longitude: 2.3840, instruction: "Prenez l'allée à gauche"),
    GuidanceStep(latitude: 48.8820, longitude: 2.3850, instruction: "Vous êtes arrivé à destination"),
]

@Test func guidanceMovesPastAReachedStepAndNeverBack() {
    // On the first manoeuvre: the next one to announce is the second.
    #expect(Guidance.advance(from: 0, steps: steps, latitude: 48.8800, longitude: 2.3830) == 1)
    // Back near the first one after a jitter: still the second.
    #expect(Guidance.advance(from: 1, steps: steps, latitude: 48.8800, longitude: 2.3830) == 1)
    // Far from every step: nothing moves.
    #expect(Guidance.advance(from: 0, steps: steps, latitude: 48.8700, longitude: 2.3700) == 0)
    // On the last: the route is done.
    #expect(Guidance.advance(from: 2, steps: steps, latitude: 48.8820, longitude: 2.3850) == 3)
}

@Test func guidanceLabelsDistanceAndArrow() {
    #expect(Guidance.distanceLabel(196) == "À 200 m")
    #expect(Guidance.distanceLabel(3) == "À 10 m")
    #expect(Guidance.distanceLabel(1240) == "À 1,2 km")
    #expect(Guidance.symbol(for: "Prenez l'allée à droite") == "arrow.turn.up.right")
    #expect(Guidance.symbol(for: "Tournez à gauche") == "arrow.turn.up.left")
    #expect(Guidance.symbol(for: "Vous êtes arrivé à destination") == "mappin.and.ellipse")
    #expect(Guidance.symbol(for: "Continuez tout droit") == "arrow.up")
}

@Test func proximityAlertsOnlyWithinReachOnceAndRounded() {
    let near = NearbyDog(id: UUID(), latitude: 48.88027, longitude: 2.3830)   // about 30 m north
    let far = NearbyDog(id: UUID(), latitude: 48.8830, longitude: 2.3830)     // about 330 m
    let alert = Proximity.alert(for: [far, near], latitude: 48.8800, longitude: 2.3830, acknowledged: [])
    #expect(alert?.dog == near)
    #expect(alert?.roundedMeters == 30)
    // Acknowledged ("Compris"): not repeated.
    #expect(Proximity.alert(for: [far, near], latitude: 48.8800, longitude: 2.3830, acknowledged: [near.id]) == nil)
    // Nobody in reach: nothing.
    #expect(Proximity.alert(for: [far], latitude: 48.8800, longitude: 2.3830, acknowledged: []) == nil)
}
