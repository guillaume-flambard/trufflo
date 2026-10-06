import SwiftData
import SwiftUI

/// Offers the household where it makes sense (B-REQ-07): after a first walk on
/// Today, and on a dog's profile. Quiet, and once per place: dismissed, it does
/// not come back there. Never shown to someone already in a household.
struct HouseholdPrompt: View {
    enum Place: String { case today, profile }

    let place: Place
    let dogName: String
    /// Several dogs named together: « leur journal », not « son journal ».
    var isSeveral = false
    let open: () -> Void

    @Query private var households: [HouseholdRecord]
    @AppStorage private var dismissed: Bool

    init(place: Place, dogName: String, isSeveral: Bool = false, open: @escaping () -> Void) {
        self.place = place
        self.dogName = dogName
        self.isSeveral = isSeveral
        self.open = open
        _dismissed = AppStorage(wrappedValue: false, "householdPrompt.dismissed.\(place.rawValue)")
    }

    var body: some View {
        if households.isEmpty && !dismissed {
            HStack(alignment: .top, spacing: TruffloTheme.Spacing.small) {
                Image(systemName: "person.2")
                    .font(.title3)
                    .foregroundStyle(Color.truffloForest)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xxSmall) {
                    Text("Vous êtes plusieurs à promener \(dogName) ?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.truffloCharcoal)
                    Button(isSeveral ? "Partager leur journal" : "Partager son journal", action: open)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.truffloForest)
                        .accessibilityIdentifier("householdPrompt.open.\(place.rawValue)")
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.truffloSlate)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Ne plus proposer ici")
                .accessibilityIdentifier("householdPrompt.dismiss.\(place.rawValue)")
            }
            .padding(.vertical, TruffloTheme.Spacing.xSmall)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.truffloForest.opacity(0.1)).frame(height: 1)
            }
        }
    }
}
