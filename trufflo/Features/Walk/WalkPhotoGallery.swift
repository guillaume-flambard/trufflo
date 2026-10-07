import SwiftData
import SwiftUI

/// A balade's photos full screen, one at a time, swiped. Each can be removed
/// (the photo only; the balade stays). The photos never leave the iPhone.
struct WalkPhotoGallery: View {
    /// Read live, so a deleted photo leaves the pages at once.
    @Query private var photos: [WalkPhotoRecord]
    @State private var selection: UUID

    init(walkID: UUID, startAt photoID: UUID) {
        _photos = Query(filter: #Predicate<WalkPhotoRecord> { $0.walkID == walkID }, sort: \.createdAt)
        _selection = State(initialValue: photoID)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var deleteError = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    PhotoPage(data: photo.data)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .ignoresSafeArea()

            HStack {
                TruffloRoundButton(systemImage: "xmark", label: "Fermer") { dismiss() }
                Spacer()
                if let index = photos.firstIndex(where: { $0.id == selection }) {
                    Text("\(index + 1) sur \(photos.count)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                TruffloRoundButton(systemImage: "trash", label: "Supprimer cette photo",
                                   identifier: "walk.photo.delete") { confirmDelete = true }
            }
            .padding(.horizontal, TruffloTheme.Spacing.screen)
        }
        .confirmationDialog("Supprimer cette photo ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer la photo", role: .destructive, action: deleteCurrent)
        } message: {
            Text("La balade reste, seule la photo est retirée de cet iPhone.")
        }
        .alert("Suppression impossible", isPresented: $deleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("La photo n'a pas été supprimée.")
        }
    }

    private func deleteCurrent() {
        guard let index = photos.firstIndex(where: { $0.id == selection }) else { return }
        let remaining = photos.filter { $0.id != selection }
        do {
            try JournalRepository(context: context).deleteWalkPhoto(selection)
        } catch {
            deleteError = true
            return
        }
        if remaining.isEmpty {
            dismiss()
        } else {
            selection = remaining[min(index, remaining.count - 1)].id
        }
    }
}

/// One photo, fitted, decoded off the main thread.
private struct PhotoPage: View {
    let data: Data
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Photo de la balade")
        .task(id: data) {
            let source = data
            image = await Task.detached(priority: .userInitiated) {
                TruffloDogPortrait.downsampled(source, to: 2400)
            }.value
        }
    }
}
