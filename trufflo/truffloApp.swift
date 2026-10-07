import Foundation
import SwiftUI
import SwiftData

@main
@MainActor
struct TruffloApp: App {
    private let boot: Result<ModelContainer, Error>
    private let household: HouseholdModel?
    /// Nil in production until the community server exists: the tab is absent,
    /// and no event is shown that a server did not send.
    private let community: CommunityModel?

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
            #if DEBUG
            if inMemory && HouseholdDemo.isRequested { try HouseholdDemo.seed(container.mainContext) }
            if inMemory && HouseholdDemo.dogsOnly { try HouseholdDemo.seedDogs(container.mainContext) }
            if inMemory, let name = MatrixDemo.requested { try MatrixDemo.seed(name, in: container.mainContext) }
            if inMemory && MockupDemo.isRequested { try MockupDemo.seed(container.mainContext) }
            #endif
            return container
        }
        // UI tests run with no network and no keychain: the household screen
        // says it is unavailable instead of talking to the real server.
        household = (try? boot.get()).map { container in
            #if DEBUG
            if inMemory && ProcessInfo.processInfo.arguments.contains("--demo-signed-in") {
                return HouseholdModel.demoSignedIn(container: container)
            }
            #endif
            return inMemory ? HouseholdModel.unavailable(container: container) : HouseholdModel.production(container: container)
        }
        community = Self.makeCommunity(household: household)
    }

    /// The Sorties tab exists only when something answers for it: the in-memory
    /// demo in DEBUG, or the real server once it is open. Until then no event is
    /// shown that a server did not send (ADR 0010).
    private static func makeCommunity(household: HouseholdModel?) -> CommunityModel? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let request = InMemoryCommunityServer.DemoRequest(arguments: arguments) {
            return InMemoryCommunityServer.demoModel(request)
        }
        let forced = arguments.contains("--community-server")
        #else
        let forced = false
        #endif
        guard CommunityBackend.isOpen || forced, let client = household?.client else { return nil }
        return CommunityModel(remote: SupabaseCommunityRemote(client: client))
    }

    var body: some Scene {
        WindowGroup {
            switch boot {
            case .success(let container):
                StarterRootView()
                    .modelContainer(container)
                    .environment(household ?? HouseholdModel.unavailable(container: container))
                    .environment(community)
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