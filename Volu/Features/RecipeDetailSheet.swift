import SwiftUI

/// Reseptin sisältö ja kirjaus syödyksi.
///
/// Lukitulla reseptillä näkyy sama kortti ja samat makrot mutta ei ohjetta eikä
/// ainesosia — palvelin ei lähetä niitä, joten näkymässä ei ole mitään
/// piilotettavaa. Alanappi vaihtuu kirjauksesta tilauksen avaukseksi.
struct RecipeDetailSheet: View {
    let recipe: Recipe
    let planDate: String
    let onLog: (Double, MealTag, [RecipeSwapSelection]) async -> RecipeLibraryModel.LogOutcome
    /// Async, jotta kutsuja voi hakea päivän ennen kuin näkymä sulkeutuu:
    /// kirjaus näytti muuten valmistuvan ennen kuin rivi oli listassa, ja
    /// väliin jäi hetki jossa mikään ei kertonut työn olevan kesken.
    let onLogged: () async -> Void
    let onPaywall: (String) -> Void
    /// Näytetäänkö kirjausnappi. Jo kirjatun rivin kautta avattu resepti on
    /// katselua: sama ateria kirjattaisiin toiseen kertaan, mitä kukaan ei
    /// tarkoita avatessaan "Näytä resepti".
    var showsLogAction = true

    @Environment(\.dismiss) private var dismiss
    @AppStorage(ScreenAwakeSetting.recipeKey) private var keepAwake = ScreenAwakeSetting.recipeDefault
    @State private var servings: Double
    @State private var mealTag: MealTag
    @State private var isLogging = false
    @State private var errorMessage: String?
    /// Riville valittu vaihtoehto avaimena rivin nimi; puuttuva avain = alkuperäinen.
    @State private var swapByLine: [String: RecipeIngredientSwapOption] = [:]

    init(
        recipe: Recipe,
        planDate: String,
        onLog: @escaping (Double, MealTag, [RecipeSwapSelection]) async -> RecipeLibraryModel.LogOutcome,
        onLogged: @escaping () async -> Void,
        onPaywall: @escaping (String) -> Void,
        showsLogAction: Bool = true
    ) {
        self.showsLogAction = showsLogAction
        self.recipe = recipe
        self.planDate = planDate
        self.onLog = onLog
        self.onLogged = onLogged
        self.onPaywall = onPaywall
        // Reseptin oma annosmäärä: lounaat ja illalliset tehdään pellillisinä (4 annosta),
        // ja ainesosalistan kuuluu avautua siihen määrään jolla ruokaa oikeasti tehdään.
        // Aiempi "aina 1" -oletus suojasi makrolukua, joka silloin skaalautui valitsimen
        // mukana — nykyään makrot ovat aina per annos, joten suojattavaa ei ole.
        // Kirjaus on silti aina yksi annos (ks. log()).
        _servings = State(initialValue: recipe.defaultServings > 0 ? recipe.defaultServings : 1)
        _mealTag = State(initialValue: MealTag(rawValue: recipe.mealTag) ?? .snack)
    }

    var body: some View {
        NavigationStack {
            List {
                if let url = recipe.imageUrl, let parsed = URL(string: url) {
                    Section {
                        // 4:3 kiinteän korkeuden sijaan: sama suhde joka reseptillä ja
                        // laitteen leveydestä riippumatta.
                        //
                        // Muoto tulee läpinäkyvästä taustasta eikä kuvasta: `aspectRatio`
                        // suoraan kuvalle jää vaikutuksetta, koska `scaledToFill` on jo
                        // sitonut suhteen kuvan omaan mittaan — lopputulos oli 1:1.
                        Color.clear
                            .aspectRatio(4 / 3, contentMode: .fit)
                            .overlay {
                                AsyncImage(url: parsed) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.secondary.opacity(0.12)
                                }
                            }
                            .clipped()
                            .listRowInsets(EdgeInsets())
                    } footer: {
                        Text("Kuva on tekoälyllä luotu kuvituskuva.")
                    }
                }

                // Makrot aina yhdelle annokselle. Ne ovat reseptin tunnusluku ja se luku
                // jolla reseptejä vertaillaan keskenään — annosmäärän mukana heiluva
                // energialukema ei vertaudu mihinkään. Ainesvaihdot lasketaan mukaan:
                // luku kertoo mitä ollaan kirjaamassa, ei mitä reseptissä lukee.
                Section {
                    MacroEnergySplit(macros: effectiveMacrosPerServing, caption: "kcal / annos")
                } footer: {
                    if !swapByLine.isEmpty {
                        Text("Makrot on laskettu valituilla vaihtoehdoilla.")
                    }
                }

                if recipe.ingredients?.isEmpty == false {
                    Section {
                        // Kokonaisia annoksia 1–12, sama kuin webissä. Puolikkaat olivat
                        // keksitty tarkkuus: annos on se yksikkö jolla ruoka on mitoitettu.
                        Stepper(value: $servings, in: 1 ... 12, step: 1) {
                            LabeledContent("Annoksia") {
                                Text(servingsText).monospacedDigit()
                            }
                        }
                    } header: {
                        // Osion otsikko kattaa sekä annosmäärän että sen alla olevat
                        // ainesosaryhmät, kuten webissä. Aiemmin "Ainesosat" oli
                        // liimattu ensimmäisen ryhmän otsikkoon ("Ainesosat · Bataatti"),
                        // mikä luki kuin ryhmän nimi olisi osa sanaa.
                        Text("Ainesosat")
                    } footer: {
                        Text("Ainesosien määrät seuraavat valintaa. Syödyksi merkitään aina yksi annos.")
                    }
                }

                // Ainesosat reseptin osittain: kastikkeen ainekset erillään pohjasta, koska
                // niitä myös käsitellään erillään. Määrät seuraavat annosvalitsinta kuten
                // webissä — sama valitsin kertoo sekä paljonko syötiin että paljonko tehdään.
                ForEach(Array(recipe.ingredientGroups.enumerated()), id: \.offset) { index, group in
                    Section {
                        ForEach(group.items) { item in
                            ingredientRow(item)
                        }
                    } header: {
                        // Pelkkä ryhmän nimi: "Ainesosat" on jo annosmäärän otsikkona,
                        // ja ryhmätön resepti ei tarvitse otsikkoa lainkaan.
                        if let label = group.label {
                            Text(label)
                        } else if index > 0 {
                            Text("Muut ainekset")
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
            // Resepti luetaan tekemisen lomassa: sammuva näyttö keskeyttää juuri sen
            // hetken jolloin kädet ovat täynnä.
            .keepScreenAwake(keepAwake)
        }
    }

    /// Ainesrivi. Rivi jolla on vaihtoehtoja on valikko: valinta vaihtaa nimen,
    /// määrän ja makrot. Valikko on arvon valintaa, joten se on neutraali kuten
    /// muutkin arvovalitsimet — korostusväri kuuluu toiminnoille.
    @ViewBuilder
    private func ingredientRow(_ item: RecipeIngredientLine) -> some View {
        if let alternatives = item.alternatives, !alternatives.isEmpty {
            Menu {
                Picker("Vaihtoehto", selection: swapBinding(for: item)) {
                    Text(originalOptionLabel(item)).tag(nil as RecipeIngredientSwapOption?)
                    ForEach(alternatives) { option in
                        Text("\(option.name) · \(option.amountText(servings: servings, defaultServings: recipe.defaultServings))")
                            .tag(option as RecipeIngredientSwapOption?)
                    }
                }
            } label: {
                LabeledContent {
                    HStack(spacing: 6) {
                        if let selected = swapByLine[item.name] {
                            Text(selected.amountText(servings: servings, defaultServings: recipe.defaultServings))
                                .monospacedDigit()
                        } else {
                            Text(item.amountText(servings: servings, defaultServings: recipe.defaultServings))
                                .monospacedDigit()
                        }
                        // Merkki vain poikkeavalle kyvylle: tämä rivi on vaihdettavissa.
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                } label: {
                    Text(swapByLine[item.name]?.name ?? item.name)
                        .foregroundStyle(Color.primary)
                }
            }
            .tint(Color.secondary)
        } else {
            LabeledContent(item.name) {
                Text(item.amountText(servings: servings, defaultServings: recipe.defaultServings))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func swapBinding(for item: RecipeIngredientLine) -> Binding<RecipeIngredientSwapOption?> {
        Binding(
            get: { swapByLine[item.name] },
            set: { newValue in swapByLine[item.name] = newValue }
        )
    }

    /// Alkuperäisen rivin nimi valikossa määrineen — samassa muodossa kuin vaihtoehdot,
    /// jotta vertailu on suoraa.
    private func originalOptionLabel(_ item: RecipeIngredientLine) -> String {
        let amount = item.amountText(servings: servings, defaultServings: recipe.defaultServings)
        return amount.isEmpty ? item.name : "\(item.name) · \(amount)"
    }

    /// Annoksen makrot valituilla vaihdoilla. Laskenta on mallissa
    /// (`Recipe.macrosPerServing(applying:)`), jotta se on testattavissa.
    private var effectiveMacrosPerServing: RecipeMacros {
        recipe.macrosPerServing(applying: swapByLine)
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
                    // Ei "(1 annos)": annosmäärä lukee jo ylempänä, ja napissa toistettuna
                    // se näytti siltä kuin nappi kirjaisi eri määrän kuin valitsin näyttää.
                    Text(recipe.locked ? "Avaa Volu Prolla" : "Merkitse syödyksi").font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .prominentButtonLabel()
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

        // Aina yksi annos: valitsin kertoo paljonko tehdään, ei paljonko syötiin.
        // Määrää voi korjata riviltä jälkikäteen.
        let swaps = swapByLine.map { RecipeSwapSelection(originalName: $0.key, ingredientId: $0.value.ingredientId) }
        switch await onLog(1, mealTag, swaps) {
        case .logged:
            // Päivä haetaan ennen sulkemista, jotta "Kirjataan…" kattaa koko
            // operaation. Näkymä suljetaan vain onnistuneen tallennuksen
            // jälkeen: sulkeutuminen on käyttäjälle kuittaus onnistumisesta.
            await onLogged()
            dismiss()
        case .paywall(let message):
            onPaywall(message)
        case .failed:
            errorMessage = "Kirjaus ei onnistunut. Yritä uudelleen."
        }
    }

    /// Puolikkaat näytetään, kokonaiset ilman desimaalia.
    private var servingsText: String {
        servings == servings.rounded()
            ? String(Int(servings))
            : String(format: "%.1f", servings).replacingOccurrences(of: ".", with: ",")
    }

}
