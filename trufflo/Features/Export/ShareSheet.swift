import SwiftUI
import UIKit

/// The system share sheet for files the app has just written. Wrapped because
/// SwiftUI's `ShareLink` needs its item before the tap, while an export is only
/// built once the person asks for it.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// An identifiable wrapper so a URL can drive `.sheet(item:)`.
struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}
