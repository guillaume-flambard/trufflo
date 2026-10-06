import Foundation

/// The language of every sentence the app shows. Formatted dates, lists and
/// numbers follow it rather than the device, so a phone set to English does not
/// put "Oct 6" inside a French sentence. Changing the app's language starts
/// here and in `Localizable.xcstrings`.
enum TruffloLocale {
    static let french = Locale(identifier: "fr_FR")
}
