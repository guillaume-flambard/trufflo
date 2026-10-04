import Foundation

public enum DogError: Error, Equatable, Sendable {
    case invalidName
    case invalidBreedLabel
}

/// The fields a person can actually edit. Validation lives here so a form and a
/// test agree on what is acceptable, with no SwiftUI and no SwiftData in the domain.
///
/// The kind is the picker's tag. A kind that carries no label must not keep a
/// stale one, otherwise the stored profile shows a breed the picker no longer selects.
public struct DogInput: Equatable, Sendable {
    public static let knownBreedKinds = ["unknown", "mixed", "known"]

    public let name: String
    public let breedKind: String
    public let breedLabel: String

    public init(name: String, breedKind: String, breedLabel: String = "") throws {
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
        self.name = cleanName
        self.breedKind = kind
        self.breedLabel = kind == "known" ? cleanLabel : ""
    }
}
