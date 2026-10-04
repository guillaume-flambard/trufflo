import Foundation
import Testing
@testable import trufflo

@MainActor
@Test func trimmedNameIsAcceptedAndStoredClean() throws {
    let input = try DogInput(name: "  Oslo  ", breedKind: "unknown")
    #expect(input.name == "Oslo")
    #expect(input.breedKind == "unknown")
    #expect(input.breedLabel.isEmpty)
}

@MainActor
@Test func emptyNameIsRejected() {
    #expect(throws: DogError.invalidName) {
        try DogInput(name: "   ", breedKind: "unknown")
    }
}

@MainActor
@Test func nameOverEightyCharactersIsRejected() {
    let tooLong = String(repeating: "o", count: 81)
    #expect(throws: DogError.invalidName) {
        try DogInput(name: tooLong, breedKind: "mixed")
    }
}

@MainActor
@Test func knownBreedWithoutLabelIsRejected() {
    #expect(throws: DogError.invalidBreedLabel) {
        try DogInput(name: "Oslo", breedKind: "known", breedLabel: "  ")
    }
}

@MainActor
@Test func knownBreedLabelOverOneHundredCharactersIsRejected() {
    let tooLong = String(repeating: "b", count: 101)
    #expect(throws: DogError.invalidBreedLabel) {
        try DogInput(name: "Oslo", breedKind: "known", breedLabel: tooLong)
    }
}

@MainActor
@Test func knownBreedWithLabelKeepsBoth() throws {
    let input = try DogInput(name: "Oslo", breedKind: "known", breedLabel: "Berger australien")
    #expect(input.breedKind == "known")
    #expect(input.breedLabel == "Berger australien")
}

/// Switching away from "Race connue" must not leave a breed stored that the
/// picker no longer selects: the form would then show a race nobody chose.
@MainActor
@Test func kindWithoutLabelDropsStaleLabel() throws {
    let input = try DogInput(name: "Oslo", breedKind: "mixed", breedLabel: "Berger australien")
    #expect(input.breedKind == "mixed")
    #expect(input.breedLabel.isEmpty)
}

@MainActor
@Test func unknownKindValueFallsBackToUnknown() throws {
    let input = try DogInput(name: "Oslo", breedKind: "golden", breedLabel: "")
    #expect(input.breedKind == "unknown")
    #expect(input.breedLabel.isEmpty)
}
