import Foundation
import SwiftUI
import SwiftData
import PhotosUI

/// Creation and edit share one form: the rules are identical, only the title and
/// the target of the write differ. The profile is copied into state at init so
/// an edit never holds a reference that a concurrent delete could invalidate.
@MainActor
struct DogFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let dogID: UUID?

    @State private var name: String
    @State private var breedKind: String
    @State private var breedLabel: String
    @State private var ageDescription: String
    @State private var gender: String
    @State private var preferencesNote: String
    @State private var photoData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var showBreedPicker = false

    private var breedChoice: BreedChoice { BreedChoice(kind: breedKind, label: breedLabel) }

    init(profile: DogRecord? = nil) {
        self.dogID = profile?.id
        _name = State(initialValue: profile?.name ?? "")
        _breedKind = State(initialValue: profile?.breedKind ?? "unknown")
        _breedLabel = State(initialValue: profile?.breedLabel ?? "")
        _ageDescription = State(initialValue: profile?.ageDescription ?? "")
        _gender = State(initialValue: profile?.gender ?? "unspecified")
        _preferencesNote = State(initialValue: profile?.preferencesNote ?? "")
        _photoData = State(initialValue: profile?.photoData)
    }

    private var isEditing: Bool { dogID != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                    photoPicker
                        .frame(maxWidth: .infinity)

                    field("Nom") {
                        TextField("Nom de votre chien", text: $name)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("dog.name")
                            .modifier(FormFieldStyle())
                    }

                    field("Race") {
                        Button { showBreedPicker = true } label: {
                            HStack {
                                Text(breedChoice.summary)
                                    .foregroundStyle(breedChoice.kind == "unknown" ? Color.truffloSlate : Color.truffloCharcoal)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.truffloSlate)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                            .modifier(FormFieldStyle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Race : \(breedChoice.summary)")
                        .accessibilityHint("Ouvre la recherche de race")
                        .accessibilityIdentifier("dog.breed")
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: TruffloTheme.Spacing.small) {
                            ageField.frame(maxWidth: .infinity)
                            sexField.frame(maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.large) {
                            ageField
                            sexField
                        }
                    }

                    field("Préférences de sortie") {
                        TextField("Rythme, rencontres, ce qu'il aime ou évite", text: $preferencesNote, axis: .vertical)
                            .lineLimit(3...6)
                            .accessibilityIdentifier("dog.preferences")
                            .modifier(FormFieldStyle())
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.truffloDanger)
                            .accessibilityIdentifier("dog.error")
                    }

                    Text("La race et l'âge sont déclaratifs et ne déclenchent aucune prescription vétérinaire automatique.")
                        .font(.footnote)
                        .foregroundStyle(Color.truffloSlate)
                }
                .padding(.horizontal, TruffloTheme.Spacing.large)
                .padding(.vertical, TruffloTheme.Spacing.medium)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text("Enregistrer")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.truffloForest)
                .accessibilityIdentifier("dog.save")
                .padding(.horizontal, TruffloTheme.Spacing.large)
                .padding(.bottom, TruffloTheme.Spacing.xSmall)
            }
            .background(Color.truffloSand.ignoresSafeArea())
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        // Resized and stripped of its location before it is kept.
                        // Unreadable, it is not kept at all: storing the original
                        // would keep the place the photo was taken.
                        if let prepared = PhotoImport.prepare(data) {
                            await MainActor.run { self.photoData = prepared }
                        }
                    }
                }
            }
            .sheet(isPresented: $showBreedPicker) {
                BreedPickerView(current: breedChoice) { choice in
                    breedKind = choice.kind
                    breedLabel = choice.label
                }
            }
            .navigationTitle(isEditing ? "Modifier le chien" : "Nouveau chien")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.truffloForest)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    /// The face first: the photo when chosen, otherwise the initial as soon as
    /// a name is typed, so the portrait is never an empty hole.
    private var photoPicker: some View {
        VStack(spacing: TruffloTheme.Spacing.xSmall) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    if photoData != nil || !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        TruffloDogPortrait(name: name.isEmpty ? "?" : name, photoData: photoData, diameter: 112)
                    } else {
                        Circle()
                            .strokeBorder(Color.truffloForest.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                            .frame(width: 112, height: 112)
                            .overlay(Image(systemName: "camera").font(.title2).foregroundStyle(Color.truffloForest))
                    }
                }
            }
            .accessibilityLabel(photoData == nil ? "Choisir une photo" : "Changer la photo")
            HStack(spacing: TruffloTheme.Spacing.medium) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Text(photoData == nil ? "Choisir une photo" : "Changer la photo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.truffloForest)
                        .frame(minHeight: 36)
                }
                if photoData != nil {
                    Button("Retirer") {
                        photoData = nil
                        selectedPhotoItem = nil
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.truffloDanger)
                }
            }
        }
    }

    private var ageField: some View {
        field("Âge") {
            TextField("Par exemple : 3 ans", text: $ageDescription)
                .accessibilityIdentifier("dog.age")
                .modifier(FormFieldStyle())
        }
    }

    /// Sex is optional: tapping the selected option again clears it.
    private var sexField: some View {
        field("Sexe") {
            TruffloChoice(options: [("male", "Mâle"), ("female", "Femelle")],
                          selection: $gender, clearsTo: "unspecified")
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.xSmall) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.truffloSlate)
            content()
        }
    }

    private func save() {
        do {
            let input = try DogInput(
                name: name,
                breedKind: breedKind,
                breedLabel: breedLabel,
                ageDescription: ageDescription,
                gender: gender,
                preferencesNote: preferencesNote,
                photoData: photoData
            )
            let repository = JournalRepository(context: context)
            if let dogID { try repository.updateDog(dogID, with: input) }
            else { try repository.addDog(input) }
            dismiss()
        } catch DogError.invalidName {
            announce("Saisissez un nom de 1 à 80 caractères.")
        } catch DogError.invalidBreedLabel {
            announce("Renseignez la race ou sélectionnez « Race inconnue ».")
        } catch DogError.ageDescriptionTooLong {
            announce("L'âge doit contenir 50 caractères maximum.")
        } catch DogError.preferencesNoteTooLong {
            announce("La note de comportement doit contenir 500 caractères maximum.")
        } catch JournalError.profileMissing {
            announce("Ce profil n'existe plus. Fermez ce formulaire.")
        } catch {
            announce("Le profil n'a pas été enregistré. Réessayez sans fermer ce formulaire.")
        }
    }

    private func announce(_ message: String) {
        errorMessage = message
        AccessibilityNotification.Announcement(message).post()
    }
}

/// A plain white field on sand, the same in both forms.
struct FormFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.truffloForest.opacity(0.1), lineWidth: 1))
    }
}

/// A row of choices that reads like a segmented control but wraps its labels
/// at large text sizes instead of truncating them.
struct TruffloChoice: View {
    let options: [(String, String)]
    @Binding var selection: String
    var clearsTo: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.0) { option in
                let isOn = selection == option.0
                Button {
                    if isOn, let clearsTo { selection = clearsTo } else { selection = option.0 }
                } label: {
                    Text(option.1)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(isOn ? Color.truffloForest : Color.truffloCharcoal)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(isOn ? Color.white : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .shadow(color: isOn ? Color.truffloForestDeep.opacity(0.12) : .clear, radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.truffloForest.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
