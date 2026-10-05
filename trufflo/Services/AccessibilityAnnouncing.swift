import Foundation
#if canImport(UIKit)
import UIKit
#endif

public protocol AccessibilityAnnouncing: Sendable {
    func announce(_ message: String)
}

public struct SystemAccessibilityAnnouncer: AccessibilityAnnouncing {
    public init() {}

    public func announce(_ message: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }
}
