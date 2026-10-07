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
    @State private var size: String
    @State private var weightText: String
    @State private var traits: [DogTrait]
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var showBreedPicker = false
    @State private var didSave = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        _size = State(initialValue: profile?.sizeRaw ?? "")
        _weightText = State(initialValue: profile?.weightKg.map {
            $0.formatted(.number.precision(.fractionLength(0...1)).locale(TruffloLocale.french))
        } ?? "")
        _traits = State(initialValue: profile?.traits ?? [])
    }

    private var isEditing: Bool { dogID != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // As in the 2026-10-07 mock-up: a title and one line, the face,
                    // then each field in its own white card.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isEditing ? "Modifier \(name.isEmpty ? "le chien" : name)" : "Ajouter un chien")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.truffloForest)
                            .accessibilityAddTraits(.isHeader)
                        Text("Parlez-nous un peu de votre compagnon.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.truffloSlate)
                    }
                    .padding(.bottom, TruffloTheme.Spacing.xSmall)

                    photoPicker
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, TruffloTheme.Spacing.xSmall)

                    field("Nom *") {
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
                        .buttonStyle(TruffloPressStyle())
                        .accessibilityLabel("Race : \(breedChoice.summary)")
                        .accessibilityHint("Ouvre la recherche de race")
                        .accessibilityIdentifier("dog.breed")
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: TruffloTheme.Spacing.small) {
                            ageField.frame(maxWidth: .infinity)
                            sexField.frame(maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: TruffloTheme.Spacing.small) {
                            ageField
                            sexField
                        }
                    }

                    field("Taille (au garrot)") {
                        TruffloChoice(options: DogSize.allCases.map { ($0.rawValue, $0.label) },
                                      selection: $size, clearsTo: "")
                            .accessibilityIdentifier("dog.size")
                    }

                    field("Poids (facultatif)") {
                        HStack {
                            TextField("Ex. 18 kg", text: $weightText)
                                .keyboardType(.decimalPad)
                                .accessibilityIdentifier("dog.weight")
                            Text("kg").foregroundStyle(Color.truffloSlate)
                        }
                        .modifier(FormFieldStyle())
                    }

                    field("Caractère (facultatif)") {
                        TraitChips(selection: $traits)
                    }

                    field("Préférences de balade") {
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
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.top, 0)
                .padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    HStack(spacing: TruffloTheme.Spacing.xSmall) {
                        if didSave {
                            Image(systemName: "checkmark")
                                .font(.headline)
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(didSave ? "Enregistré" : "Enregistrer")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .contentTransition(.opacity)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .overlay(alignment: .trailing) {
                        if !didSave { Image(systemName: "chevron.right").font(.headline) }
                    }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(Color.truffloForest)
                .disabled(didSave)
                .truffloTap()
                .accessibilityIdentifier("dog.save")
                .padding(.horizontal, TruffloTheme.Spacing.screen)
                .padding(.bottom, 4)
                .truffloBottomBarFade()
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
            // The title is drawn in the page, large; the bar keeps only the way back.
            .toolbar {
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "arrow.left") { dismiss() }
                }
            }
            .tint(Color.truffloForest)
            .background {
                TruffloDogAura(photoData: nil).frame(height: 360).frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
            }
        }
    }

    /// The face, with a camera badge, and while there is no photo a note that
    /// points at it (2026-10-07 mock-up). The initial shows once a name is typed,
    /// so the circle is never an empty hole.
    private var photoPicker: some View {
        HStack(alignment: .center, spacing: TruffloTheme.Spacing.small) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    if photoData != nil || !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        TruffloDogPortrait(name: name.isEmpty ? "?" : name, photoData: photoData, diameter: 112)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.7))
                            .overlay(Circle().strokeBorder(Color.truffloForest.opacity(0.3),
                                                           style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                            .frame(width: 112, height: 112)
                    }
                }
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.truffloForest)
                        .frame(width: 30, height: 30)
                        .background(Color.white, in: Circle())
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                }
            }
            .accessibilityLabel(photoData == nil ? "Choisir une photo" : "Changer la photo")
            if photoData == nil {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.truffloForest.opacity(0.5))
                    VStack(spacing: 4) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.truffloForest)
                        Text("Une photo\npour commencer !")
                            .font(.system(size: 12, design: .serif).italic())
                            .foregroundStyle(Color.truffloForest)
                            .multilineTextAlignment(.center)
                    }
                    .padding(10)
                    .background(Color(red: 0.86, green: 0.93, blue: 0.89).opacity(0.8),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityHidden(true)
            } else {
                Button("Retirer") {
                    photoData = nil
                    selectedPhotoItem = nil
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.truffloDanger)
                .truffloTap()
            }
        }
    }

    private var ageField: some View {
        field("Âge *") {
            TextField("Ex. 3 ans", text: $ageDescription)
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

    /// One field in its own white card, its label inside (2026-10-07 mock-up).
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.truffloSlate)
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                photoData: photoData,
                size: DogSize(rawValue: size),
                weightKg: parsedWeight,
                traits: traits
            )
            let repository = JournalRepository(context: context)
            if let dogID { try repository.updateDog(dogID, with: input) }
            else { try repository.addDog(input) }
            confirmAndDismiss()
        } catch DogError.invalidName {
            announce("Saisissez un nom de 1 à 80 caractères.")
        } catch DogError.invalidBreedLabel {
            announce("Renseignez la race ou sélectionnez « Race inconnue ».")
        } catch DogError.ageDescriptionTooLong {
            announce("L'âge doit contenir 50 caractères maximum.")
        } catch DogError.invalidWeight {
            announce("Le poids doit être compris entre 0,5 et 100 kg.")
        } catch DogError.preferencesNoteTooLong {
            announce("La note de comportement doit contenir 500 caractères maximum.")
        } catch JournalError.profileMissing {
            announce("Ce chien n'est plus sur cet iPhone. Fermez ce formulaire.")
        } catch {
            announce("Les changements n'ont pas été enregistrés. Réessayez sans fermer ce formulaire.")
        }
    }

    /// "18", "18,5" or "18.5"; empty means not given.
    private var parsedWeight: Double? {
        let clean = weightText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return clean.isEmpty ? nil : Double(clean) ?? -1
    }

    private func announce(_ message: String) {
        errorMessage = message
        AccessibilityNotification.Announcement(message).post()
    }

    /// The write already happened: this is not a wait for it to finish, only a
    /// beat long enough for "Enregistré" to register before the sheet closes,
    /// instead of vanishing the instant the write completes.
    private func confirmAndDismiss() {
        guard !reduceMotion else { dismiss(); return }
        withAnimation(TruffloTheme.Motion.selection(reduceMotion: reduceMotion)) { didSave = true }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            dismiss()
        }
    }
}

/// A plain white field on sand, the same in both forms.
struct FormFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 14))
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(Color(red: 0.99, green: 0.985, blue: 0.97),
                        in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(Color.black.opacity(0.1), lineWidth: 1))
    }
}

/// A row of choices that reads like a segmented control but wraps its labels
/// at large text sizes instead of truncating them.
struct TruffloChoice: View {
    let options: [(String, String)]
    @Binding var selection: String
    var clearsTo: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.0) { option in
                let isOn = selection == option.0
                Button {
                    if isOn, let clearsTo { selection = clearsTo } else { selection = option.0 }
                } label: {
                    Text(option.1)
                        .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(isOn ? Color.truffloForest : Color.truffloCharcoal)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(isOn ? Color(red: 0.86, green: 0.93, blue: 0.89) : Color.black.opacity(0.03),
                                    in: Capsule())
                }
                .buttonStyle(TruffloPressStyle())
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// Traits of character as chips, several at once, each with its symbol
/// (2026-10-07 mock-up). Declared by the person, never inferred.
struct TraitChips: View {
    @Binding var selection: [DogTrait]

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(DogTrait.allCases, id: \.self) { trait in
                let isOn = selection.contains(trait)
                Button {
                    if isOn { selection.removeAll { $0 == trait } } else { selection.append(trait) }
                } label: {
                    Label(trait.label, systemImage: trait.systemImage)
                        .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color.truffloForest : Color.truffloCharcoal)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 30)
                        .background(isOn ? Color(red: 0.86, green: 0.93, blue: 0.89) : Color.black.opacity(0.03),
                                    in: Capsule())
                        .overlay(Capsule().strokeBorder(isOn ? Color.truffloForest.opacity(0.4) : .clear, lineWidth: 1))
                }
                .buttonStyle(TruffloPressStyle())
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .accessibilityIdentifier("dog.traits")
    }
}

/// Lays children out in rows, wrapping to the next row when one is full.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
