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
    /// Photos being read and resized: the "+" tile shows it, the grid waits.
    @State private var importing = 0

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
                VStack(alignment: .leading, spacing: 12) {
                    TruffloScreenHeader(title: "Modifier la balade",
                                        subtitle: "Ce que vous en gardez : un titre, une humeur, une note, des photos.")
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
                                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            withAnimation(.snappy) {
                                                _ = try? JournalRepository(context: context).deleteWalkPhoto(photo.id)
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title3)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .black.opacity(0.5))
                                        }
                                        .buttonStyle(TruffloPressStyle())
                                        .accessibilityLabel("Retirer la photo")
                                        .padding(4)
                                    }
                            }
                            PhotosPicker(selection: $picked, maxSelectionCount: 10, matching: .images) {
                                Group {
                                    if importing > 0 {
                                        ProgressView().tint(Color.truffloForest)
                                    } else {
                                        Image(systemName: "plus").font(.title2)
                                    }
                                }
                                .foregroundStyle(Color.truffloForest)
                                .frame(width: 100, height: 100)
                                .background(Color(red: 0.95, green: 0.97, blue: 0.95),
                                            in: RoundedRectangle(cornerRadius: TruffloTheme.Radius.medium, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: TruffloTheme.Radius.medium, style: .continuous)
                                    .strokeBorder(Color.truffloForest.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                            }
                            .disabled(importing > 0)
                            .accessibilityLabel("Ajouter des photos")
                        }
                        .animation(.snappy, value: photos.count)
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
            .scrollDismissesKeyboard(.interactively)
            .truffloAura()
            .background(Color.truffloSand.ignoresSafeArea())
            .navigationTitle("Modifier la balade")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.truffloForest)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                // The head says the title; the bar does not repeat it, truncated.
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.truffloSlate)
            content()
        }
        .truffloBoardCard(padding: 14)
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        importing = items.count
        defer { importing = 0 }
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let prepared = PhotoImport.prepare(data) {
                withAnimation(.snappy) {
                    _ = try? JournalRepository(context: context).addWalkPhoto(walk.id, data: prepared)
                }
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
