import SwiftUI

/// Reseptin sisältö ja kirjaus syödyksi.
///
/// Lukitulla reseptillä näkyy sama kortti ja samat makrot mutta ei ohjetta eikä
/// ainesosia — palvelin ei lähetä niitä, joten näkymässä ei ole mitään
/// piilotettavaa. Alanappi vaihtuu kirjauksesta tilauksen avaukseksi.
struct RecipeDetailSheet: View {
    let recipe: Recipe
    let planDate: String
    let onLog: (Double, MealTag) async -> RecipeLibraryModel.LogOutcome
    let onLogged: () -> Void
    let onPaywall: (String) -> Void
    /// Näytetäänkö kirjausnappi. Jo kirjatun rivin kautta avattu resepti on
    /// katselua: sama ateria kirjattaisiin toiseen kertaan, mitä kukaan ei
    /// tarkoita avatessaan "Näytä resepti".
    var showsLogAction = true

    @Environment(\.dismiss) private var dismiss
    @State private var servings: Double
    @State private var mealTag: MealTag
    @State private var isLogging = false
    @State private var errorMessage: String?

    init(
        recipe: Recipe,
        planDate: String,
        onLog: @escaping (Double, MealTag) async -> RecipeLibraryModel.LogOutcome,
        onLogged: @escaping () -> Void,
        onPaywall: @escaping (String) -> Void,
        showsLogAction: Bool = true
    ) {
        self.showsLogAction = showsLogAction
        self.recipe = recipe
        self.planDate = planDate
        self.onLog = onLog
        self.onLogged = onLogged
        self.onPaywall = onPaywall
        // Yksi annos, ei reseptin satoa. `defaultServings` kertoo montako annosta resepti antaa
        // (esim. 4), ja sillä avattuna näkymä näytti 2 088 kcal heti sen jälkeen kun käyttäjä
        // napautti korttia jossa luki 522 kcal. Kirjattava määrä on se mitä syödään.
        _servings = State(initialValue: 1)
        _mealTag = State(initialValue: MealTag(rawValue: recipe.mealTag) ?? .snack)
    }

    private var macros: RecipeMacros { recipe.macrosPerServing.scaled(by: servings) }

    var body: some View {
        NavigationStack {
            List {
                if let url = recipe.imageUrl, let parsed = URL(string: url) {
                    Section {
                        AsyncImage(url: parsed) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.12)
                        }
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .listRowInsets(EdgeInsets())
                    } footer: {
                        Text("Kuva on tekoälyllä luotu kuvituskuva.")
                    }
                }

                if let description = recipe.description, !description.isEmpty {
                    Section {
                        Text(description).foregroundStyle(.secondary)
                    }
                }

                Section {
                    // Annosmäärä ensin: se on se arvo joka muuttaa kaiken muun
                    // ruudulla, ja kirjaus tehdään sillä.
                    Stepper(value: $servings, in: 0.5 ... 10, step: 0.5) {
                        LabeledContent("Annoksia") {
                            Text(servingsText).monospacedDigit()
                        }
                    }
                    macroRow("Energia", macros.kcal, "kcal")
                    macroRow("Proteiini", macros.proteinG, "g")
                    macroRow("Hiilihydraatit", macros.carbsG, "g")
                    macroRow("Rasva", macros.fatG, "g")
                } header: {
                    Text("Makrot")
                }

                // Ainesosat reseptin osittain: kastikkeen ainekset erillään pohjasta, koska
                // niitä myös käsitellään erillään. Sato mukaan otsikkoon, sillä määrät ovat koko
                // reseptin eivätkä seuraa annosvalitsinta — resepti tehdään kerralla neljälle,
                // vaikka syödyksi merkitään yksi annos.
                ForEach(Array(recipe.ingredientGroups.enumerated()), id: \.offset) { index, group in
                    Section {
                        ForEach(group.items) { item in
                            LabeledContent(item.name) {
                                Text(item.amountText).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        if let label = group.label {
                            Text(index == 0 ? "\(ingredientsTitle) · \(label)" : label)
                        } else {
                            Text(index == 0 ? ingredientsTitle : "Muut ainekset")
                        }
                    }
                }

                if let steps = recipe.instructionSteps, !steps.isEmpty {
                    Section("Ohje") {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(index + 1).")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Text(step)
                            }
                        }
                    }
                }

                if recipe.locked {
                    Section {
                        Text("Ohje ja ainesosat kuuluvat Volu Pro -tilaukseen.")
                            .foregroundStyle(.secondary)
                    }
                }

                if !recipe.locked, showsLogAction {
                    Section("Kirjaus") {
                        Picker("Ateriapaikka", selection: $mealTag) {
                            ForEach(MealTag.allCases, id: \.self) { tag in
                                Text(tag.label).tag(tag)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section {
                    Color.clear.frame(height: 44).listRowBackground(Color.clear)
                }
                .listSectionSpacing(0)
            }
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sulje") { dismiss() }.disabled(isLogging)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if showsLogAction || recipe.locked {
                    bottomAction
                }
            }
        }
    }

    private var bottomAction: some View {
        Button {
            if recipe.locked {
                onPaywall("Tämä resepti kuuluu Volu Pro -tilaukseen.")
                return
            }
            Task { await log() }
        } label: {
            Group {
                if isLogging {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Kirjataan…").font(.headline)
                    }
                } else {
                    Text(recipe.locked ? "Avaa Volu Prolla" : "Merkitse syödyksi").font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLogging)
        .padding(.horizontal, 16)
        // Väli myös ylös: ilman sitä tausta alkaa napin reunasta ja näyttää
        // irralliselta kaistaleelta.
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func log() async {
        isLogging = true
        errorMessage = nil
        defer { isLogging = false }

        switch await onLog(servings, mealTag) {
        case .logged:
            // Näkymä suljetaan vain onnistuneen tallennuksen jälkeen: sulkeutuminen
            // on käyttäjälle kuittaus onnistumisesta.
            onLogged()
            dismiss()
        case .paywall(let message):
            onPaywall(message)
        case .failed:
            errorMessage = "Kirjaus ei onnistunut. Yritä uudelleen."
        }
    }

    /// Ainesosaotsikko: "Ainesosat (koko resepti, 4 annosta)". Yhden annoksen reseptillä
    /// tarkenne on pelkkää kohinaa — määrät eivät voi tarkoittaa mitään muuta.
    private var ingredientsTitle: String {
        let yieldServings = recipe.defaultServings > 0 ? recipe.defaultServings : 1
        guard yieldServings != 1 else { return "Ainesosat" }
        let count = yieldServings == yieldServings.rounded()
            ? String(Int(yieldServings))
            : String(format: "%.1f", yieldServings).replacingOccurrences(of: ".", with: ",")
        return "Ainesosat (koko resepti, \(count) annosta)"
    }

    /// Puolikkaat näytetään, kokonaiset ilman desimaalia.
    private var servingsText: String {
        servings == servings.rounded()
            ? String(Int(servings))
            : String(format: "%.1f", servings).replacingOccurrences(of: ".", with: ",")
    }

    private func macroRow(_ label: String, _ value: Double, _ unit: String) -> some View {
        LabeledContent(label) {
            Text("\(Int(value.rounded())) \(unit)").monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
