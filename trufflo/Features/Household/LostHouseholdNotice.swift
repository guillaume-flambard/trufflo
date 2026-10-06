import SwiftUI

/// Said once, where the shared walks were: this iPhone was removed from a
/// household and has forgotten what it had received (B-REQ-06, PRD F08).
struct LostHouseholdNotice: View {
    @Environment(HouseholdModel.self) private var model

    var body: some View {
        if let name = model.lostHousehold {
            TruffloNotice(systemImage: "person.2.slash",
                          title: "Vous ne faites plus partie de « \(name) »",
                          message: "Les balades reçues de ce foyer ont été retirées de cet iPhone. Votre propre journal est intact.",
                          actionTitle: "Compris") { model.lostHousehold = nil }
                .accessibilityIdentifier("household.lost")
        }
    }
}
