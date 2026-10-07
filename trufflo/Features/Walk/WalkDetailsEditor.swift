import PhotosUI
import SwiftData
import SwiftUI

/// What the person writes about a balade after the fact: its title, its mood,
/// its note and its photos (2026-10-07 mock-up, "Modifier" on the walk page).
/// Photos are resized and stripped of their location before they are kept, and
/// they stay on this iPhone.
struct WalkDetailsEditor: View {
    let walk: WalkRecord

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var photos: [WalkPhotoRecord]
    @State private var title: String
    @State private var mood: WalkMood?
    @State private var note: String
    @State private var picked: [PhotosPickerItem] = []
    @State private var errorMessage: String?

    init(walk: WalkRecord) {
        self.walk = walk
        let walkID = walk.id
        _photos = Query(filter: #Predicate<WalkPhotoRecord> { $0.walkID == walkID }, sort: \.createdAt)
        _title = State(initialValue: walk.title)
        _mood = State(initialValue: walk.mood)
        _note = State(initialValue: walk.note)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.medium) {
                    section("Titre") {
                        TextField("Ex. Balade dans le quartier", text: $title)
                            .accessibilityIdentifier("walk.details.title")
                            .modifier(FormFieldStyle())
                    }
                    section("Humeur") { MoodChips(selection: $mood) }
                    section("Note") {
                        TextField("Comment s'est passée la balade ?", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                            .modifier(FormFieldStyle())
                    }
                    section("Photos") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(photos) { photo in
                                TruffloDogThumbnail(name: "", photoData: photo.data, side: 100, bordered: false)
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            try? JournalRepository(context: context).deleteWalkPhoto(photo.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title3)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .black.opacity(0.5))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Retirer la photo")
                                        .padding(4)
                                    }
                            }
                            PhotosPicker(selection: $picked, maxSelectionCount: 10, matching: .images) {
                                Image(systemName: "plus")
                                    .font(.title2)
                                    .foregroundStyle(Color.truffloForest)
                                    .frame(width: 100, height: 100)
                                    .background(Color.white.opacity(0.7),
                                                in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.medium, style: .continuous))
                            }
                            .accessibilityLabel("Ajouter des photos")
                        }
                        Text("Les photos restent sur cet iPhone. Leur lieu de prise de vue est retiré.")
                            .font(.footnote)
                            .foregroundStyle(Color.truffloSlate)
                    }
                    if let errorMessage {
                        Text(errorMessage).truffloErrorText()
                    }
                }
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.vertical, TruffloTheme.Spacing.medium)
            }
            .background(Color.truffloSand.ignoresSafeArea())
            .navigationTitle("Modifier la balade")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.truffloForest)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save).fontWeight(.semibold)
                        .accessibilityIdentifier("walk.details.save")
                }
            }
            .onChange(of: picked) { _, items in
                Task { await importPhotos(items) }
            }
        }
    }

    private func section<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.truffloSlate)
            content()
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let prepared = PhotoImport.prepare(data) {
                try? JournalRepository(context: context).addWalkPhoto(walk.id, data: prepared)
            }
        }
        picked = []
    }

    private func save() {
        do {
            try JournalRepository(context: context).updateWalkDetails(walk.id, title: title, mood: mood, note: note)
            dismiss()
        } catch WalkError.titleTooLong {
            errorMessage = "Le titre doit contenir au maximum 80 caractères."
        } catch WalkError.noteTooLong {
            errorMessage = "La note doit contenir au maximum 500 caractères."
        } catch {
            errorMessage = "Les changements n'ont pas été enregistrés."
        }
    }
}
