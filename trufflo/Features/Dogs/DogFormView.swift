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
            Form {
                // MARK: - Photo Section
                Section("Photo de profil") {
                    HStack {
                        Spacer()
                        VStack(spacing: TruffloTheme.Spacing.small) {
                            if let photoData, let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.truffloForest, lineWidth: 2))
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(Color.truffloSand)
                                        .frame(width: 90, height: 90)
                                    Image(systemName: "pawprint.fill")
                                        .font(.largeTitle)
                                        .foregroundStyle(Color.truffloForest.opacity(0.6))
                                }
                            }

                            HStack(spacing: TruffloTheme.Spacing.medium) {
                                PhotosPicker(
                                    selection: $selectedPhotoItem,
                                    matching: .images,
                                    photoLibrary: .shared()
                                ) {
                                    Label(photoData == nil ? "Ajouter une photo" : "Changer", systemImage: "photo")
                                        .font(.truffloCaption)
                                        .foregroundStyle(Color.truffloForest)
                                }

                                if photoData != nil {
                                    Button(role: .destructive) {
                                        photoData = nil
                                        selectedPhotoItem = nil
                                    } label: {
                                        Label("Effacer", systemImage: "trash")
                                            .font(.truffloCaption)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, TruffloTheme.Spacing.xSmall)
                }

                // MARK: - General Identity
                Section("Identité") {
                    TextField("Nom", text: $name)
                        .font(.truffloBody)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("dog.name")

                    Picker("Sexe", selection: $gender) {
                        Text("Non renseigné").tag("unspecified")
                        Text("Mâle").tag("male")
                        Text("Femelle").tag("female")
                    }
                    .font(.truffloBody)

                    TextField("Âge ou date (ex: 2 ans, 6 mois)", text: $ageDescription)
                        .font(.truffloBody)
                        .accessibilityIdentifier("dog.age")

                    Picker("Race", selection: $breedKind) {
                        Text("Race inconnue").tag("unknown")
                        Text("Croisé").tag("mixed")
                        Text("Race connue").tag("known")
                    }
                    .font(.truffloBody)

                    if breedKind == "known" {
                        TextField("Nom de la race", text: $breedLabel)
                            .font(.truffloBody)
                            .accessibilityIdentifier("dog.breedLabel")
                    }
                }

                // MARK: - Preferences & Habits
                Section("Besoins & Comportement") {
                    TextField("Préférences de sortie, rythme, sociabilité...", text: $preferencesNote, axis: .vertical)
                        .font(.truffloBody)
                        .lineLimit(3...5)
                        .accessibilityIdentifier("dog.preferences")
                }

                Section {
                    Text("La race et l'âge sont déclaratifs et ne déclenchent aucune prescription vétérinaire automatique.")
                        .font(.truffloCaption)
                        .foregroundStyle(Color.truffloSlate)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.truffloCaption)
                            .foregroundStyle(Color.truffloDanger)
                            .accessibilityIdentifier("dog.error")
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            self.photoData = data
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Modifier le chien" : "Ajouter un chien")
            .truffloScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("dog.save")
                }
            }
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
