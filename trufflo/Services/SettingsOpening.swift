import Foundation
import UIKit

/// Opening the app's own page in Settings is a side effect the view model owns,
/// so it can be asserted in a unit test instead of only being visible on screen.
@MainActor
public protocol SettingsOpening: AnyObject {
    func openAppSettings()
}

@MainActor
public final class SystemSettingsOpener: SettingsOpening {
    public init() {}

    public func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}