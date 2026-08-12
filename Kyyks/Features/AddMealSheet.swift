import PhotosUI
import SwiftUI

/// AI-kameralisäys: kuvaa ateria → Gemini arvioi ruoan ja makrot → käyttäjä
/// tarkistaa annoskoon ja ateriapaikan → rivi tallentuu syödyksi merkittynä.
struct AddMealSheet: View {
    let auth: AuthManager
    let planDate: String
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = AddMealModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            Form {
                if let estimate = model.estimate {
                    estimateSection(estimate)
                } else {
                    captureSection
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
                        Button("Tallenna") {
                            Task {
                                if await model.save() {
                                    onAdded()
                                    dismiss()
                                }
                            }
                        }
                        .disabled(model.isSaving)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await model.estimate(from: image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await model.estimate(from: image)
                    }
                    pickerItem = nil
                }
            }
        }
        .task {
            model.configure(auth: auth, planDate: planDate)
            // Lämmityskutsu: serverless-funktio herää käyttäjän kuvatessa,
            // jolloin varsinainen arvio osuu lämpimään instanssiin.
            await model.warmUp()
        }
    }

    @ViewBuilder
    private var captureSection: some View {
        if model.isEstimating {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(model.estimatingLabel)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            // Kuva ja teksti ovat tasavertaiset tavat: kuva on nopein lautasesta,
            // teksti toimii jälkikäteen kirjatessa tai kun ruokaa ei enää ole.
            Section("Kuvaa") {
                Button {
                    showCamera = true
                } label: {
                    Label("Kuvaa ateria", systemImage: "camera.fill")
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Valitse kuva", systemImage: "photo.on.rectangle")
                }
            }

            Section {
                HStack(spacing: 8) {
                    TextField("Esim. kaurapuuro ja banaani", text: $model.query)
                        .submitLabel(.search)
                        .onSubmit { Task { await model.estimateFromText() } }
                    Button {
                        Task { await model.estimateFromText() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.query.trimmingCharacters(in: .whitespaces).count < 2)
                }
            } header: {
                Text("Tai kirjoita")
            } footer: {
                Text("AI arvioi makrot kuvasta tai kuvauksesta. Voit korjata annoskoon ennen tallennusta.")
            }
        }
    }

    private func estimateSection(_ estimate: AiFoodEstimate) -> some View {
        Group {
            Section("Tunnistettu") {
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
                Button("Arvioi uudelleen") { model.reset() }
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
    var grams: Double = 0
    var mealTag: MealTag = .suggestion()
    var query = ""
    private(set) var estimatingLabel = "Tunnistetaan ateriaa…"

    private var api: APIClient?
    private var planDate = ""

    func configure(auth: AuthManager, planDate: String) {
        api = APIClient(auth: auth)
        self.planDate = planDate
    }

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

        isEstimating = true
        estimatingLabel = "Arvioidaan makroja…"
        errorMessage = nil
        defer { isEstimating = false }

        do {
            struct Body: Encodable { let query: String }
            let data = try await api.post("/api/nutrition/ai-estimate", body: Body(query: term), timeout: 60)
            let response = try JSONDecoder().decode(AiEstimateResponse.self, from: data)
            estimate = response.estimate
            grams = response.estimate.grams
        } catch {
            errorMessage = "Arviota ei saatu — tarkenna kuvausta tai kokeile kuvaa."
        }
    }

    func estimate(from image: UIImage) async {
        guard let api else { return }
        isEstimating = true
        estimatingLabel = "Tunnistetaan ateriaa…"
        errorMessage = nil
        defer { isEstimating = false }

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
            estimate = response.estimate
            grams = response.estimate.grams
        } catch {
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
            errorMessage = "Tallennus epäonnistui — yritä uudelleen."
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

/// UIKit-kamera SwiftUI-kääreessä (SwiftUI:ssa ei ole natiivia kamerakomponenttia).
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let dismiss: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onCapture = onCapture
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
            dismiss()
        }
    }
}
