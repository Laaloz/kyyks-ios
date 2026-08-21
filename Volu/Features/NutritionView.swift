import SwiftUI
import UIKit

/// Ravinto-välilehti: päivän makrotilanne tavoitteeseen verrattuna ja
/// ateriat ateriapaikoittain. Päivää voi selata eteen ja taakse.
struct NutritionView: View {
    let auth: AuthManager

    @State private var model = NutritionModel()
    @State private var showAddMeal = false
    @State private var selectedEntry: NutritionEntry?
    @State private var addMode: AddMealMode = .text
    @State private var quickQuery = ""
    @State private var pendingQuery = ""
    @State private var showPicker = false
    @State private var openedRecipe: RecipeReference?
    /// Kirjasto myös tässä näkymässä: sitä tarvitaan sekä kirjatun rivin
    /// resepti­linkkiin että kirjoituskentän ehdotukseen. Levyvälimuisti tekee
    /// avauksesta ilmaisen — verkkohaku ajetaan taustalla kuten muissakin
    /// näkymissä.
    @State private var recipes = RecipeLibraryModel()
    @State private var pickerSource: UIImagePickerController.SourceType = .camera
    @State private var capturedImage: UIImage?
    @FocusState private var isQuickFocused: Bool

    @Environment(RestTimerManager.self) private var restTimer

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    macroSummary
                }

                // Toissijainen toiminto listarivinä, ei yläpalkin kuvakkeena:
                // välilehden ensisijainen toiminto on kirjaus, ja se on alapalkissa.
                Section {
                    NavigationLink {
                        RecipeLibraryView(
                            auth: auth,
                            planDate: model.dateKey,
                            onLogged: { await model.refreshAfterChange() }
                        )
                    } label: {
                        Label("Reseptit", systemImage: "book")
                    }
                }


                // Ei erillisiä ateriaotsikoita: Listin rivikorkeus on vähintään
                // ~44 pt, joten kompaktikin otsikko söi sen verran ruutua jokaista
                // ateriaa kohden. Ateriapaikka on nyt rivin omalla tietorivillä,
                // ja rivit pysyvät ateriajärjestyksessä.
                Section {
                    ForEach(model.orderedEntries) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            NutritionRow(
                                entry: entry,
                                mealLabel: MealTag(rawValue: entry.mealTag)?.label ?? ""
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                model.deleteEntry(entry)
                            } label: {
                                Label("Poista", systemImage: "trash")
                            }
                        }
                    }
                }

                if model.day?.entries.isEmpty ?? false {
                    Section {
                        // Tyhjä päivä ohjaa suoraan lisäykseen — juuri silloin
                        // ohjaus on tarpeellisinta.
                        Button {
                            openPicker(.camera)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Ei kirjauksia tälle päivälle.")
                                    .foregroundStyle(.secondary)
                                Label("Lisää ensimmäinen ateria", systemImage: "camera.fill")
                                    .font(.subheadline.weight(.medium))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Alanapin alle jää tilaa, ettei viimeinen rivi jää sen alle.
                Section {
                    Color.clear
                        .frame(height: 44)
                        .listRowBackground(Color.clear)
                }
                .listSectionSpacing(0)
            }
            .navigationTitle("Ravinto")
            .navigationBarTitleDisplayMode(.inline)
            // Näppäimistö pois vierittämällä ja omalla napillaan. SwiftUI:n
            // listassa "napauta ulkopuolelta" ei ole luotettava ele, koska
            // rivit vievät kosketuksen — nämä kaksi toimivat aina.
            .scrollDismissesKeyboard(.interactively)
            .toolbar { dateToolbar }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Valmis") { isQuickFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Tabin tärkein toiminto peukalon ulottuville; samalla yläpalkin
                // "+" katosi päivänuolen vierestä, jossa se aiheutti vääriä osumia.
                // Kuvaaminen on oma nappinsa ja avaa kameran suoraan — se on
                // nopein polku pöydässä. Kirjoituskynä avaa saman näkymän ilman
                // kameraa, jolloin teksti ja kuvakirjasto ovat valittavissa.
                VStack(spacing: 8) {
                // Kaksi eri polkua tehdään näkyviksi riveinä sen sijaan että toinen
                // olisi piilossa nuolinapin takana. Kentästä ei muuten näe, että se
                // sekä hakee omista resepteistä että arvioi tekoälyllä mitä tahansa
                // syötyä — ja arvaus näyttää oikealta myös silloin kun se on väärä.
                if canSubmitQuickQuery {
                    let matches = recipes.suggestions(for: quickQuery)

                    if !matches.isEmpty {
                        // Otsikko kertoo mistä ehdotukset tulevat. Ilman sitä ne ovat
                        // vain nimiä, eikä ruudunlukija erota niitä kentän sisällöstä.
                        Text("Resepteistäsi")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                    }

                    ForEach(matches) { recipe in
                        Button {
                            logSuggested(recipe)
                        } label: {
                            suggestionLabel(
                                symbol: "book",
                                title: recipe.name,
                                detail: "\(Int(recipe.macrosPerServing.kcal.rounded())) kcal / annos"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(recipe.name), resepti, \(Int(recipe.macrosPerServing.kcal.rounded())) kilokaloria annos")
                        .accessibilityHint("Kirjaa yhden annoksen")
                    }

                    // AI-polku omana rivinään: se on ainoa tapa kirjata jotain jota
                    // kirjastossa ei ole, eikä sen pidä olla arvattavissa kuvakkeesta.
                    Button(action: submitQuickQuery) {
                        suggestionLabel(
                            symbol: "sparkles",
                            title: "Arvioi tekoälyllä",
                            detail: quickQuery.trimmingCharacters(in: .whitespaces)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Arvioi tekoälyllä: \(quickQuery)")
                }

                HStack(spacing: 8) {
                    // Kirjoituskenttä suoraan listan alla: yleisin kirjaus alkaa
                    // ilman navigointia — kirjoita ja lähetä. Kuvakkeet vievät
                    // muihin tapoihin yhdellä napautuksella.
                    TextField("Hae reseptiä tai kuvaile ateria", text: $quickQuery)
                        .focused($isQuickFocused)
                        .submitLabel(.send)
                        .onSubmit(submitQuickQuery)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(.fill.tertiary, in: Capsule())

                    if canSubmitQuickQuery {
                        Button(action: submitQuickQuery) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Arvioi kirjoitettu ateria")
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Button {
                            openPicker(.photoLibrary)
                        } label: {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title3)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Valitse kuva kirjastosta")

                        Button {
                            openPicker(.camera)
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(Color.accentColor, in: Circle())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Kuvaa ateria")
                    }
                }
                }
                .animation(.snappy(duration: 0.2), value: canSubmitQuickQuery)
                .padding(.horizontal, 16)
                // Väli myös ylös: ilman sitä tausta alkoi kentän reunasta ja
                // näytti irralliselta kaistaleelta, erityisesti tummassa.
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .restTimerBar(restTimer)
            .sheet(item: $selectedEntry) { entry in
                MealDetailSheet(
                    entry: entry,
                    onSave: { grams, servings, tag in
                        await model.updateEntry(entry, grams: grams, servings: servings, mealTag: tag)
                    },
                    onDelete: { model.deleteEntry(entry) },
                    onOpenRecipe: { openedRecipe = RecipeReference(id: $0) }
                )
            }
            .sheet(isPresented: $showAddMeal) {
                AddMealSheet(
                    auth: auth,
                    planDate: model.dateKey,
                    mode: addMode,
                    initialQuery: pendingQuery,
                    initialImage: capturedImage,
                    onRetry: {
                        showAddMeal = false
                        openPicker(pickerSource)
                    },
                    onAdded: { Task { await model.refreshAfterChange() } }
                )
            }
            // Valitsin esitetään listasta, ei vahvistusnäkymästä: sisäkkäinen
            // esitys jäi avautumatta, ja näin kamera aukeaa heti napautuksesta.
            .fullScreenCover(isPresented: $showPicker) {
                ImagePicker(
                    sourceType: pickerSource,
                    onCapture: { image in capturedImage = image },
                    onCancel: { capturedImage = nil }
                )
                .ignoresSafeArea()
            }
            .onChange(of: showPicker) { _, isShowing in
                // Vahvistusnäkymä avataan vasta kun valitsin on sulkeutunut,
                // jottei esitys osu kesken animaation.
                guard !isShowing, capturedImage != nil else { return }
                addMode = pickerSource == .camera ? .camera : .library
                pendingQuery = ""
                showAddMeal = true
            }
            .sheet(item: $openedRecipe) { reference in
                RecipeQuickLookSheet(auth: auth, recipeId: reference.id)
            }
            .overlay { if model.isLoading && model.day == nil { ProgressView() } }
            .refreshable { await model.refresh() }
        }
        .task {
            model.configure(auth: auth)
            await model.load()
        }
        .task {
            recipes.configure(auth: auth)
            await recipes.load()
        }
    }

    private var canSubmitQuickQuery: Bool {
        quickQuery.trimmingCharacters(in: .whitespaces).count >= 2
    }

    /// Kirjoitettu kuvaus siirtyy vahvistusnäkymään, joka käynnistää arvion
    /// heti — kenttä tyhjenee, jotta seuraavan voi kirjoittaa saman tien.
    // Ilmaiskäyttäjää ei pysäytetä tässä: hänellä on kuukausittainen kiintiö
    // AI-arvioita, ja vasta sen loppuminen avaa tilausnäkymän (AddMealSheet
    // palvelimen 402:sta). Paikallinen lukko estäisi myös ne arviot jotka
    // hänelle kuuluvat.
    private func openPicker(_ source: UIImagePickerController.SourceType) {
        capturedImage = nil
        pickerSource = source
        showPicker = true
    }

    private func suggestionLabel(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Ehdotuksen kirjaus: yksi annos reseptin omaan ateriapaikkaan. Sama oletus
    /// kuin kirjastosta kirjatessa — annosmäärää ja ateriapaikkaa voi korjata
    /// riviltä jälkikäteen.
    private func logSuggested(_ recipe: Recipe) {
        let tag = MealTag(rawValue: recipe.mealTag) ?? .suggestion()
        quickQuery = ""
        isQuickFocused = false
        Task {
            if case .logged = await recipes.logAsEaten(
                recipe,
                servings: 1,
                planDate: model.dateKey,
                mealTag: tag
            ) {
                await model.refreshAfterChange()
            }
        }
    }

    private func submitQuickQuery() {
        guard canSubmitQuickQuery else { return }
        capturedImage = nil
        pendingQuery = quickQuery.trimmingCharacters(in: .whitespaces)
        quickQuery = ""
        isQuickFocused = false
        addMode = .text
        showAddMeal = true
    }

    @ToolbarContentBuilder
    private var dateToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task { await model.shiftDay(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Edellinen päivä")
        }
        ToolbarItem(placement: .principal) {
            Text(model.dateLabel)
                .font(.headline)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await model.shiftDay(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(model.isToday)
            .accessibilityLabel("Seuraava päivä")
        }
    }

    private var macroSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(model.totals.kcal))")
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                if let target = model.day?.target {
                    Text("/ \(Int(target.kcal)) kcal")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("kcal").foregroundStyle(.secondary)
                }
                Spacer()
                if let remaining = model.remainingKcal {
                    Text(remaining >= 0 ? "\(remaining) jäljellä" : "\(-remaining) yli")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(remaining >= 0 ? Color.secondary : Color.orange)
                        .monospacedDigit()
                }
            }

            if let target = model.day?.target {
                ProgressView(value: min(model.totals.kcal, target.kcal), total: max(target.kcal, 1))
                    .tint(model.totals.kcal > target.kcal ? .orange : .accentColor)

                HStack(spacing: 12) {
                    macroBar("Proteiini", model.totals.proteinG, target.proteinG, .blue)
                    macroBar("Hiilihydraatit", model.totals.carbsG, target.carbsG, .green)
                    macroBar("Rasva", model.totals.fatG, target.fatG, .purple)
                }
            } else {
                Text("Aseta ravintotavoitteet webissä, niin näet edistymisen tässä.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func macroBar(_ title: String, _ value: Double, _ target: Double, _ color: Color) -> some View {
        // Tavoitteen ylitys näkyy samalla varoitusvärillä kuin kaloreissa,
        // jotta täysi palkki ei tarkoita kahta eri asiaa.
        let isOver = value > target
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ProgressView(value: min(value, target), total: max(target, 1))
                .tint(isOver ? Color.orange : color)
            Text("\(Int(value)) / \(Int(target)) g")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(isOver ? Color.orange : Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(Int(value)) grammaa tavoitteesta \(Int(target))\(isOver ? ", tavoite ylittyy" : "")")
    }
}

private struct NutritionRow: View {
    let entry: NutritionEntry
    let mealLabel: String

    var body: some View {
        HStack(spacing: 12) {
            // Lähdemerkki nimen edessä, ei perässä: silmä lukee rivin vasemmalta,
            // ja kuvake kertoo ennen nimeä mihin lukuun voi luottaa.
            if let symbol = entry.origin.symbol {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 1) {
                // Ei syöty-merkkiä: lisätty ateria on määritelmällisesti syöty
                // (myös illalla kirjattu koko päivä), joten merkki olisi kohinaa.
                // Nimi yhdelle riville: pitkä AI-nimi kasvatti rivin kolminkertaiseksi.
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(entry.isFailedEstimate ? .red : .secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if entry.isPendingEstimate {
                ProgressView()
            } else {
                Text("\(Int(entry.macros.kcal))")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
        }
        // Listin oletusmarginaali on ~11 pt ylä- ja alapuolella; rivi on kaksi
        // tiivistä tekstiriviä, joten puolet siitä riittää.
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .accessibilityElement(children: .combine)
        // Lähde myös sanoina: kuvake ei kerro ruudunlukijalle mitään.
        .accessibilityLabel([
            entry.origin.accessibilityLabel,
            entry.name,
            subtitle,
            "\(Int(entry.macros.kcal)) kilokaloria",
        ].compactMap { $0 }.joined(separator: ", "))
    }

    private var subtitle: String {
        if entry.isPendingEstimate { return "\(mealLabel) · Arvioidaan…" }
        if entry.isFailedEstimate { return "\(mealLabel) · Arvio ei onnistunut" }
        // Ateriapaikka ensin: se korvaa poistetun ryhmäotsikon.
        var parts: [String] = [mealLabel]
        if entry.kind == "food", let grams = entry.grams, grams > 0 {
            parts.append("\(Int(grams)) g")
        } else if entry.kind == "recipe", entry.servings != 1 {
            // Yksi annos on oletus eikä kerro mitään — näytetään vain poikkeus.
            let servings = entry.servings
            let text = servings.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(servings)) : String(format: "%.1f", servings)
            parts.append("\(text) annosta")
        }
        parts.append("P \(Int(entry.macros.proteinG)) · H \(Int(entry.macros.carbsG)) · R \(Int(entry.macros.fatG))")
        return parts.joined(separator: " · ")
    }
}
