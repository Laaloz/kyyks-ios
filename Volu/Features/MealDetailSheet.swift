import SwiftUI

/// Yksittäisen ateriarivin esikatselu: koko nimi (listalla se on katkaistu),
/// makrot eriteltynä sekä annoskoon ja ateriapaikan korjaus. Poisto on täällä
/// ja listalla pyyhkäisynä.
struct MealDetailSheet: View {
    let entry: NutritionEntry
    /// Palauttaa virheviestin tai `nil` kun tallennus onnistui.
    let onSave: (_ grams: Double?, _ servings: Double?, _ mealTag: MealTag) async -> String?
    let onDelete: () -> Void
    /// Reseptistä kirjatun rivin polku takaisin ohjeeseen. Näkymä sulkeutuu ensin
    /// ja kutsuja avaa reseptin: sheetin päälle avattu sheet jäi tässä koodikannassa
    /// luotettavasti avautumatta.
    var onOpenRecipe: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var mealTag: MealTag
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false

    private var isFood: Bool { entry.kind == "food" }

    init(
        entry: NutritionEntry,
        onSave: @escaping (_ grams: Double?, _ servings: Double?, _ mealTag: MealTag) async -> String?,
        onDelete: @escaping () -> Void,
        onOpenRecipe: ((String) -> Void)? = nil
    ) {
        self.entry = entry
        self.onSave = onSave
        self.onDelete = onDelete
        self.onOpenRecipe = onOpenRecipe
        let amount = entry.kind == "food" ? (entry.grams ?? 0) : entry.servings
        _amountText = State(initialValue: Self.format(amount))
        _mealTag = State(initialValue: MealTag(rawValue: entry.mealTag) ?? .snack)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Ylimmäksi kuten muissakin näkymissä: virhe koskee juuri
                // tehtyä tallennusyritystä, ja arvot ovat yhä muokattavina alla.
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text(entry.name)
                        .font(.headline)
                        .padding(.vertical, 2)
                }

                if let recipeId = entry.recipeId, let onOpenRecipe {
                    Section {
                        Button {
                            dismiss()
                            onOpenRecipe(recipeId)
                        } label: {
                            Label("Näytä resepti", systemImage: "book")
                        }
                    }
                }

                Section("Makrot") {
                    macroRow("Energia", entry.macros.kcal, "kcal")
                    macroRow("Proteiini", entry.macros.proteinG, "g")
                    macroRow("Hiilihydraatit", entry.macros.carbsG, "g")
                    macroRow("Rasva", entry.macros.fatG, "g")
                }

                Section("Annos") {
                    HStack {
                        Text(isFood ? "Määrä" : "Annoksia")
                        Spacer()
                        TextField(isFood ? "g" : "kpl", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 80)
                        if isFood {
                            Text("g").foregroundStyle(.secondary)
                        }
                    }
                    Picker("Ateriapaikka", selection: $mealTag) {
                        ForEach(MealTag.allCases) { tag in
                            Text(tag.label).tag(tag)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Poista ateria", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Ateria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sulje") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tallenna") {
                        Task {
                            isSaving = true
                            errorMessage = nil
                            let amount = Self.parse(amountText)
                            let failure = await onSave(isFood ? amount : nil, isFood ? nil : amount, mealTag)
                            isSaving = false
                            // Suljetaan vain onnistuessa: epäonnistuneen
                            // tallennuksen jälkeen sulkeutuva näkymä näyttää
                            // onnistumiselta ja vie mukanaan syötetyt arvot.
                            if let failure {
                                errorMessage = failure
                            } else {
                                dismiss()
                            }
                        }
                    }
                    .disabled(isSaving || !hasChanges)
                }
            }
            .confirmationDialog(
                "Poistetaanko ateria?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Poista", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Peru", role: .cancel) {}
            } message: {
                Text("\(entry.name) poistetaan päiväkirjasta.")
            }
        }
    }

    private var hasChanges: Bool {
        let original = isFood ? (entry.grams ?? 0) : entry.servings
        let current = Self.parse(amountText) ?? 0
        return current != original || mealTag.rawValue != entry.mealTag
    }

    private func macroRow(_ title: String, _ value: Double, _ unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(Int(value.rounded())) \(unit)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// Hyväksyy sekä desimaalipilkun että -pisteen.
    private static func parse(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private static func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
