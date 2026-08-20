import SwiftUI

/// Aterian vahvistusnäkymä: AI arvioi ruoan (kuvasta tai kuvauksesta),
/// käyttäjä tarkistaa annoskoon ja ateriapaikan, ja rivi tallentuu syödyksi
/// merkittynä. Syöte valitaan aina ennen tänne tuloa.
struct AddMealSheet: View {
    let auth: AuthManager
    let planDate: String
    /// Mistä syöte tulee. Kamera ja kuvakirjasto aukeavat suoraan, teksti
    /// arvioidaan initialQuerystä — näkymä itse ei kysy mitään, koska valinta
    /// on jo tehty listassa.
    var mode: AddMealMode = .text
    /// Listan kirjoituspalkista tullut kuvaus: arvio käynnistyy heti, eikä
    /// käyttäjän tarvitse kirjoittaa samaa uudelleen.
    var initialQuery = ""
    /// Kamerasta tai kuvakirjastosta valittu kuva. Valitsin esitetään
    /// listanäkymässä, ei täällä: sisäkkäinen esitys jäi luotettavasti
    /// avautumatta, ja suoraan avautuva kamera on myös nopeampi.
    var initialImage: UIImage?
    /// Uusi yritys: listanäkymä avaa saman lähteen uudelleen.
    var onRetry: (() -> Void)?
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionStore.self) private var subscriptions
    @State private var model = AddMealModel()

    var body: some View {
        NavigationStack {
            Form {
                if let estimate = model.estimate {
                    estimateSection(estimate)
                } else {
                    statusSection
                }

                if let error = model.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Lisää ateria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peru") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.estimate != nil {
                        SaveToolbarButton(isSaving: model.isSaving) {
                            Task {
                                if await model.save() {
                                    onAdded()
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $model.needsSubscription) {
            PaywallView(store: subscriptions, reason: model.paywallMessage, source: .aiEstimate)
        }
        .onChange(of: subscriptions.entitlement) { _, entitlement in
            // Onnistuneen oston jälkeen arvio jatkuu siitä mihin se jäi, ilman
            // että käyttäjän täytyy kuvata ateria uudelleen.
            guard entitlement.unlocksPaidFeatures, model.estimate == nil else { return }
            Task {
                if let initialImage {
                    await model.estimate(from: initialImage)
                } else if !model.query.isEmpty {
                    await model.estimateFromText()
                }
            }
        }
        .task {
            model.configure(auth: auth, planDate: planDate)
            if model.estimate == nil {
                if let initialImage {
                    await model.estimate(from: initialImage)
                } else if model.query.isEmpty, !initialQuery.isEmpty {
                    model.query = initialQuery
                    await model.estimateFromText()
                }
            }
            // Lämmityskutsu: serverless-funktio herää käyttäjän kuvatessa,
            // jolloin varsinainen arvio osuu lämpimään instanssiin.
            await model.warmUp()
        }
    }

    /// Näkymä on pelkkä arvion tila ja vahvistus: syöte tulee joko kamerasta,
    /// kuvakirjastosta tai listan kirjoituspalkista. Ilman omaa syötekenttää
    /// mikään ei myöskään ehdi välähtää ennen valitsimen avautumista.
    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(model.isEstimating ? model.estimatingLabel : "Valmistellaan…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func estimateSection(_ estimate: AiFoodEstimate) -> some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(estimate.name)
                        .font(.headline)
                    if let confidence = estimate.confidence {
                        Text("Varmuus \(Int(confidence * 100)) %")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                HStack {
                    Text("Annos")
                    Spacer()
                    TextField("g", value: $model.grams, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 80)
                    Text("g").foregroundStyle(.secondary)
                }
            } header: {
                Text("Tunnistettu")
            } footer: {
                // Vain ilmaistasolla: tilaajalla ei ole kiintiötä, joten
                // laskuri olisi hänelle pelkkää kohinaa.
                if let left = model.estimatesLeft {
                    Text(left > 0
                        ? "Ilmaisia AI-arvioita jäljellä \(left) tässä kuussa."
                        : "Tämä oli kuukauden viimeinen ilmainen AI-arvio.")
                }
            }

            Section("Makrot") {
                let m = estimate.macros(forGrams: model.grams)
                macroRow("Energia", value: m.kcal, unit: "kcal")
                macroRow("Proteiini", value: m.protein, unit: "g")
                macroRow("Hiilihydraatit", value: m.carbs, unit: "g")
                macroRow("Rasva", value: m.fat, unit: "g")
            }

            Section("Ateria") {
                // Valinta on aina käyttäjän — kellonaika antaa vain esivalinnan.
                Picker("Ateriapaikka", selection: $model.mealTag) {
                    ForEach(MealTag.allCases) { tag in
                        Text(tag.label).tag(tag)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                // Uusi yritys palaa samaan lähteeseen josta tultiin.
                switch mode {
                case .camera:
                    // Nollaus ennen paluuta valitsimeen: sheetin malli säilyy
                    // uudelleenesityksen yli, ja vanha virhe näkyi muuten
                    // "Valmistellaan…"-vaiheessa uuden kuvan alla.
                    Button("Kuvaa uudelleen") { model.reset(); onRetry?() }
                case .library:
                    Button("Valitse toinen kuva") { model.reset(); onRetry?() }
                case .text:
                    // Kuvausta muokataan listan kirjoituspalkissa, joka on
                    // näkyvissä heti sulkemisen jälkeen.
                    Button("Sulje ja kirjoita uudelleen") { dismiss() }
                }
            }
        }
    }

    private func macroRow(_ title: String, value: Double, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(Int(value.rounded())) \(unit)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

@Observable
@MainActor
final class AddMealModel {
    private(set) var estimate: AiFoodEstimate?
    private(set) var isEstimating = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    /// Palvelin vastasi maksumuurilla. Tämä on maksumuurin ainoa portti:
    /// ilmaiskäyttäjällä on kuukausikiintiö, jonka tilaa vain palvelin tietää,
    /// joten näkymä ei voi päättää lukosta etukäteen.
    var needsSubscription = false
    /// Palvelimen perustelu: kertoo loppuiko ilmainen kiintiö vai onko
    /// ominaisuus kokonaan maksullinen. Tilausnäkymä näyttää sen sellaisenaan.
    private(set) var paywallMessage = ""
    /// Ilmaiskäyttäjän jäljellä olevat arviot. Näytetään onnistuneen arvion
    /// yhteydessä, jottei kiintiön loppuminen tule yllätyksenä — muuri
    /// hyväksytään paremmin kun sen tulon on nähnyt etukäteen.
    private(set) var estimatesLeft: Int?
    var grams: Double = 0
    var mealTag: MealTag = .suggestion()
    var query = ""
    private(set) var estimatingLabel = "Tunnistetaan ateriaa…"

    private var api: APIClient?
    private var planDate = ""

    func configure(auth: AuthManager, planDate: String) {
        let client = APIClient(auth: auth)
        api = client
        self.planDate = planDate
        // Näkymän avaus kirjataan, koska pelkkä arvioiden määrä ei erota kahta hyvin erilaista
        // syytä nollakäytölle: ominaisuutta ei löydetä, vai löydetään muttei käytetä.
        client.log(.aiSheetOpened, source: .nutrition)
    }

    /// Käynnissä olevan yrityksen tunniste. Uusintakuvaus peruu edellisen
    /// yrityksen kesken 60 sekunnin arvion, ja peruutetun yrityksen catch voi
    /// ehtiä ajoon vasta uuden yrityksen onnistumisen jälkeen — ilman tätä
    /// vanha virhe kirjoittui tuoreen arvion viereen ("arvio + virhe yhtä
    /// aikaa"). Vain tuorein yritys saa kirjoittaa tilaan.
    private var attempt = 0

    func warmUp() async {
        _ = try? await api?.get("/api/nutrition/ai-estimate")
    }

    func reset() {
        estimate = nil
        errorMessage = nil
    }

    /// Tekstiarvio: sama endpoint, query-kenttä kuvan sijaan.
    func estimateFromText() async {
        guard let api else { return }
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { return }

        attempt += 1
        let current = attempt
        isEstimating = true
        estimatingLabel = "Arvioidaan makroja…"
        errorMessage = nil
        defer { if current == attempt { isEstimating = false } }

        do {
            struct Body: Encodable { let query: String }
            let data = try await api.post("/api/nutrition/ai-estimate", body: Body(query: term), timeout: 60)
            let response = try JSONDecoder().decode(AiEstimateResponse.self, from: data)
            guard current == attempt else { return }
            estimate = response.estimate
            grams = response.estimate.grams
            estimatesLeft = response.estimatesLeft
        } catch APIError.paymentRequired(let message) {
            guard current == attempt else { return }
            paywallMessage = message ?? "AI-ruoka-arvio kuuluu Pro-tilaukseen."
            needsSubscription = true
        } catch {
            guard current == attempt, !APIClient.isCancellation(error) else { return }
            errorMessage = "Arviota ei saatu — tarkenna kuvausta tai kokeile kuvaa."
        }
    }

    func estimate(from image: UIImage) async {
        guard let api else { return }
        attempt += 1
        let current = attempt
        isEstimating = true
        estimatingLabel = "Tunnistetaan ateriaa…"
        errorMessage = nil
        defer { if current == attempt { isEstimating = false } }

        // Pienennetään ennen lähetystä: pitkä sivu 1024 px riittää tunnistukseen
        // ja pitää latauksen nopeana myös mobiiliverkossa.
        guard let jpeg = image.resized(maxDimension: 1024).jpegData(compressionQuality: 0.7) else {
            errorMessage = "Kuvan käsittely epäonnistui."
            return
        }

        do {
            struct Body: Encodable {
                let imageBase64: String
                let mimeType: String
                let imageMode: String
            }
            // Gemini + mahdollinen Open Food Facts -varahaku vie kymmeniä sekunteja;
            // reitin oma katto on 60 s, joten clientin on odotettava vähintään yhtä kauan.
            let data = try await api.post("/api/nutrition/ai-estimate", body: Body(
                imageBase64: jpeg.base64EncodedString(),
                mimeType: "image/jpeg",
                imageMode: "photo"
            ), timeout: 60)
            let response = try JSONDecoder().decode(AiEstimateResponse.self, from: data)
            guard current == attempt else { return }
            estimate = response.estimate
            grams = response.estimate.grams
            estimatesLeft = response.estimatesLeft
        } catch APIError.paymentRequired(let message) {
            guard current == attempt else { return }
            paywallMessage = message ?? "AI-ruoka-arvio kuuluu Pro-tilaukseen."
            needsSubscription = true
        } catch {
            guard current == attempt, !APIClient.isCancellation(error) else { return }
            errorMessage = "Arvio epäonnistui — kokeile uudelleen tai valitse ruoka käsin."
        }
    }

    func save() async -> Bool {
        guard let api, let estimate, grams > 0 else { return false }
        isSaving = true
        defer { isSaving = false }

        struct Food: Encodable {
            let name: String
            let kcalPer100: Double
            let proteinPer100: Double
            let carbsPer100: Double
            let fatPer100: Double
            let source: String
        }
        struct Body: Encodable {
            let planDate: String
            let mealTag: String
            let grams: Double
            let food: Food
            let eatenAt: String
        }

        do {
            _ = try await api.post("/api/day-meal-plans", body: Body(
                planDate: planDate,
                mealTag: mealTag.rawValue,
                grams: grams,
                food: Food(
                    name: estimate.name,
                    kcalPer100: estimate.kcalPer100,
                    proteinPer100: estimate.proteinPer100,
                    carbsPer100: estimate.carbsPer100,
                    fatPer100: estimate.fatPer100,
                    source: "ai"
                ),
                // Itse lisätty ateria on määritelmällisesti syöty.
                eatenAt: ISO8601DateFormatter().string(from: .now)
            ))
            return true
        } catch {
            if !APIClient.isCancellation(error) {
                errorMessage = "Tallennus epäonnistui — yritä uudelleen."
            }
            return false
        }
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// UIKit-kuvavalitsin SwiftUI-kääreessä. Sekä kamera että kuvakirjasto kulkevat
/// tämän kautta: SwiftUI:n .photosPicker ei esittäydy luotettavasti toisen
/// esitetyn näkymän päältä, mutta fullScreenCover + UIImagePickerController kyllä.
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType = .camera
    let onCapture: (UIImage) -> Void
    var onCancel: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // Kameraa ei ole simulaattorissa eikä kaikilla laitteilla → kirjasto.
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onCancel: () -> Void
        private let dismiss: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
            dismiss()
        }
    }
}

/// Tapa lisätä ateria. Valinta tehdään ennen näkymän avaamista, jotta
/// vaihtoehdot eivät toistu sen sisällä.
enum AddMealMode {
    case camera, library, text
}
