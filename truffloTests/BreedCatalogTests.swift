import Testing
@testable import trufflo

/// A-AC-05, A-AC-06: the breed search finds what people type.
@Suite("Breed catalogue")
struct BreedCatalogTests {
    @Test func typedStartOfANameComesFirst() {
        #expect(BreedCatalog.search("berger all").first?.name == "Berger allemand")
    }

    @Test func accentsAndCaseAreIgnored() {
        let names = BreedCatalog.search("BERGE").map(\.name)
        #expect(names.contains("Berger allemand"))
        #expect(names.contains("Berger des Pyrénées"))
        #expect(BreedCatalog.search("epagneul").first?.name == "Épagneul breton")
        #expect(BreedCatalog.search("levrier afgh").first?.name == "Lévrier afghan")
    }

    @Test func aliasesFindTheirBreed() {
        #expect(BreedCatalog.search("malinois").first?.name == "Berger belge malinois")
        #expect(BreedCatalog.search("ba").contains { $0.name == "Berger allemand" })
        #expect(BreedCatalog.search("frenchie").first?.name == "Bouledogue français")
        #expect(BreedCatalog.search("labro").first?.name == "Labrador retriever")
    }

    @Test func aWordInsideTheNameMatchesBeforeAContainedString() {
        // "allemand" starts a word of "Berger allemand": it outranks names
        // that only contain the letters elsewhere.
        #expect(BreedCatalog.search("allemand").first?.name == "Berger allemand")
    }

    @Test func emptyOrUnknownQueryGivesNothing() {
        #expect(BreedCatalog.search("   ").isEmpty)
        #expect(BreedCatalog.search("xyzxyz").isEmpty)
    }

    @Test func identifiersAndNamesAreUnique() {
        #expect(Set(BreedCatalog.all.map(\.id)).count == BreedCatalog.all.count)
        #expect(Set(BreedCatalog.all.map { BreedCatalog.normalized($0.name) }).count == BreedCatalog.all.count)
    }

    @Test func aCatalogueNameIsRecognisedAndATypedOneIsNot() {
        #expect(BreedCatalog.entry(named: "berger allemand")?.id == "berger-allemand")
        #expect(BreedCatalog.entry(named: "Golden") == nil, "un texte libre ancien reste un texte libre")
    }
}
