import Foundation
import SwiftUI
import SwiftData

@main
@MainActor
struct TruffloApp: App {
    private let boot: Result<ModelContainer, Error>

    init() {
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
            case .failure:
                // Never replace a failed persistent store with a silent, empty memory store.
                ContentUnavailableView(
                    "Journal indisponible",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Le stockage n'a pas pu être ouvert. Vos données ne sont pas effacées. Fermez puis rouvrez l'application ; si le problème persiste, conservez l'installation pour le diagnostic.")
                )
            }
        }
    }
}