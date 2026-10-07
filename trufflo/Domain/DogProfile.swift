import Foundation

public enum DogError: Error, Equatable, Sendable {
    case invalidName
    case invalidBreedLabel
    case preferencesNoteTooLong
    case ageDescriptionTooLong
    case invalidWeight
}

/// The fields a person can actually edit. Validation lives here so a form and a
/// test agree on what is acceptable, with no SwiftUI and no SwiftData in the domain.
public struct DogInput: Equatable, Sendable {
    public static let knownBreedKinds = ["unknown", "mixed", "known"]
    public static let validGenders = ["unspecified", "male", "female"]

    public let name: String
    public let breedKind: String
    public let breedLabel: String
    public let ageDescription: String
    public let gender: String
    public let preferencesNote: String
    public let photoData: Data?
    public let size: DogSize?
    public let weightKg: Double?
    public let traits: [DogTrait]

    public init(
        name: String,
        breedKind: String,
        breedLabel: String = "",
        ageDescription: String = "",
        gender: String = "unspecified",
        preferencesNote: String = "",
        photoData: Data? = nil,
        size: DogSize? = nil,
        weightKg: Double? = nil,
        traits: [DogTrait] = []
    ) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 80 else {
            throw DogError.invalidName
        }
        let kind = Self.knownBreedKinds.contains(breedKind) ? breedKind : "unknown"
        let cleanLabel = breedLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == "known" {
            guard !cleanLabel.isEmpty, cleanLabel.count <= 100 else {
                throw DogError.invalidBreedLabel
            }
        }
        let cleanAge = ageDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanAge.count <= 50 else {
            throw DogError.ageDescriptionTooLong
        }
        let cleanNote = preferencesNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanNote.count <= 500 else {
            throw DogError.preferencesNoteTooLong
        }
        let validGender = Self.validGenders.contains(gender) ? gender : "unspecified"

        self.name = cleanName
        self.breedKind = kind
        self.breedLabel = kind == "known" ? cleanLabel : ""
        self.ageDescription = cleanAge
        self.gender = validGender
        self.preferencesNote = cleanNote
        self.photoData = photoData
        if let weightKg, !(0.5...100).contains(weightKg) { throw DogError.invalidWeight }
        self.size = size
        self.weightKg = weightKg
        self.traits = traits
    }
}
