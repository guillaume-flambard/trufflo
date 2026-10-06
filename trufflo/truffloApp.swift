import Foundation
import SwiftUI
import SwiftData

@main
@MainActor
struct TruffloApp: App {
    private let boot: Result<ModelContainer, Error>

    init() {
        let forest = UIColor(Color.truffloForest)
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: forest]
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: forest]
        #if DEBUG
        let inMemory = ProcessInfo.processInfo.arguments.contains("--uitesting")
        #else
        let inMemory = false
        #endif
        boot = Result {
            let container = try PersistenceFactory.make(inMemory: inMemory)
            try? JournalRepository(context: ModelContext(container)).recoverInterruptedSessions()
            return container
        }
    }

    var body: some Scene {
        WindowGroup {
            switch boot {
            case .success(let container):
                StarterRootView()
                    .modelContainer(container)
                    // The palette ships light values only; until adaptive colours
                    // exist, dark mode would put forest text on a dark system
                    // background on half the screens.
                    .preferredColorScheme(.light)
            case .failure:
                // Never replace a failed persistent store with a silent, empty memory store.
                TruffloNotice(
                    systemImage: "externaldrive",
                    title: "Le journal ne s'ouvre pas",
                    message: "Le stockage de l'iPhone n'a pas répondu. Vos balades ne sont pas effacées. Fermez Trufflo puis rouvrez-le.",
                    footnote: "Si le problème revient, gardez l'app installée : la supprimer effacerait le journal."
                )
                .preferredColorScheme(.light)
            }
        }
    }
}