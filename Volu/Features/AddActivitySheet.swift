import SwiftUI

/// Oheisaktiviteetin kirjaus käsin. Kalorit laskee palvelin lajin MET-kertoimesta
/// ja painosta, ellei käyttäjä anna omaa lukemaa — sama logiikka kuin webissä.
struct AddActivitySheet: View {
    let auth: AuthManager
    /// Muokattava suoritus, tai nil kun kirjataan uusi.
    var existing: ExtraActivity?
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var activityType: ExtraActivityType
    @State private var durationText: String
    @State private var kcalText: String
    @State private var distanceText: String
    @State private var occurredAt: Date
    @State private var notes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(auth: AuthManager, existing: ExtraActivity? = nil, onAdded: @escaping () -> Void) {
        self.auth = auth
        self.existing = existing
        self.onAdded = onAdded
        _activityType = State(initialValue: existing.flatMap { ExtraActivityType(rawValue: $0.activityType) } ?? .run)
        _durationText = State(initialValue: existing.map { String(Int($0.durationMinutes)) } ?? "30")
        // Kalorit esitäytetään kirjatulla arvolla: tyhjänä palvelin laskisi
        // arvion uudelleen ja korvaisi käyttäjän oman lukeman.
        _kcalText = State(initialValue: existing.map { String(Int($0.estimatedKcal)) } ?? "")
        // Kenttä näytetään lajin omassa yksikössä: uinti metreinä, muut
        // kilometreinä. Kantaan menee aina metrejä.
        let existingType = existing.flatMap { ExtraActivityType(rawValue: $0.activityType) }
        _distanceText = State(initialValue: {
            guard let meters = existing?.distanceMeters, meters > 0 else { return "" }
            if existingType?.distanceMode == .swim { return String(Int(meters.rounded())) }
            return String(format: "%.2f", meters / 1000)
                .replacingOccurrences(of: ".", with: ",")
        }())
        _occurredAt = State(initialValue: existing.flatMap { parseAPIDate($0.occurredAt) } ?? .now)
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private var distanceUnit: String {
        activityType.distanceMode == .swim ? "m" : "km"
    }

    /// Kenttä on lajin yksikössä, kanta metreissä — muunnos tehdään tässä,
    /// jotta se on yhdessä paikassa eikä tallennuksen ja esikatselun välillä
    /// voi syntyä eroa.
    private var distanceMeters: Double? {
        let value = Double(distanceText.replacingOccurrences(of: ",", with: "."))
        guard let value, value > 0 else { return nil }
        return activityType.distanceMode == .swim ? value : value * 1000
    }

    private var durationMinutes: Double? {
        let value = Double(durationText.replacingOccurrences(of: ",", with: "."))
        guard let value, value >= 1 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Laji", selection: $activityType) {
                        ForEach(ExtraActivityType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }

                    HStack {
                        Text("Kesto")
                        Spacer()
                        TextField("min", text: $durationText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 70)
                        Text("min").foregroundStyle(.secondary)
                    }

                    // Matka vain lajeille joille se on mielekäs: joogalle tai
                    // kamppailulle kenttä olisi pelkkää kohinaa.
                    if activityType.distanceMode != .none {
                        HStack {
                            Text("Matka")
                            Spacer()
                            TextField(distanceUnit, text: $distanceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(width: 80)
                            Text(distanceUnit).foregroundStyle(.secondary)
                        }
                    }

                    DatePicker("Ajankohta", selection: $occurredAt, in: ...Date.now)
                } footer: {
                    // Vauhti on matkan ja keston osamäärä, joten sitä ei
                    // kysytä erikseen — näytetään heti kun molemmat on annettu.
                    if let pace = ActivityMetrics.paceText(
                        meters: distanceMeters,
                        minutes: durationMinutes,
                        mode: activityType.distanceMode
                    ) {
                        Text("Vauhti \(pace)")
                            .monospacedDigit()
                    }
                }

                Section {
                    HStack {
                        Text("Kalorit")
                        Spacer()
                        TextField("Arvioidaan", text: $kcalText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 90)
                        Text("kcal").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Jätä tyhjäksi, niin kulutus arvioidaan lajin ja kestosi perusteella.")
                }

                Section("Muistiinpano") {
                    TextField("Vapaaehtoinen", text: $notes, axis: .vertical)
                        .lineLimit(1 ... 4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Lisää suoritus" : "Muokkaa suoritusta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peru") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SaveToolbarButton(isSaving: isSaving, isEnabled: durationMinutes != nil) {
                        Task { await save() }
                    }
                }
            }
        }
    }

    private func save() async {
        guard let minutes = durationMinutes else { return }
        isSaving = true
        defer { isSaving = false }

        struct Body: Encodable {
            let activityType: String
            let durationMinutes: Double
            let manualKcal: Double?
            let occurredAt: String
            let notes: String?
            let distanceMeters: Double?
        }

        let client = APIClient(auth: auth)
        do {
            let body = Body(
                activityType: activityType.rawValue,
                durationMinutes: minutes,
                manualKcal: Double(kcalText).flatMap { $0 > 0 ? $0 : nil },
                occurredAt: ISO8601DateFormatter().string(from: occurredAt),
                notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes,
                // Palvelin nollaa matkan itse jos laji ei kulje matkaa, joten
                // lajin vaihto joogaksi ei jätä vanhaa kilometrilukemaa roikkumaan.
                distanceMeters: distanceMeters
            )
            if let existing {
                _ = try await client.patch("/api/extra-activities/\(existing.id)", body: body)
            } else {
                _ = try await client.post("/api/extra-activities", body: body)
            }
            onAdded()
            dismiss()
        } catch {
            errorMessage = "Suorituksen tallennus epäonnistui — yritä uudelleen."
        }
    }
}

/// Palvelimen lajikatalogi (lib/extra-activities.ts). MET-kertoimet ja
/// kalorilaskenta ovat palvelimella; täällä tarvitaan vain avaimet ja nimet.
enum ExtraActivityType: String, CaseIterable, Identifiable {
    /// Suomenkielinen nimi tallennetulle avaimelle. Palvelin palauttaa avaimen
    /// ("run"), jota ei näytetä käyttäjälle sellaisenaan.
    static func label(for rawValue: String) -> String {
        ExtraActivityType(rawValue: rawValue)?.label ?? rawValue
    }

    case run, walk, cycle, indoor_cycle, treadmill, stair_climber, elliptical
    case mtb, downhill_ski, disc_golf, skate, paddle, swim, climb, hike, row
    case ski, yoga, hiit, combat, dance, mobility, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .run: "Juoksu"
        case .walk: "Kävely"
        case .cycle: "Pyöräily"
        case .indoor_cycle: "Sisäpyöräily"
        case .treadmill: "Juoksumatto"
        case .stair_climber: "Porraslaite"
        case .elliptical: "Crosstrainer"
        case .mtb: "Maastopyöräily"
        case .downhill_ski: "Laskettelu"
        case .disc_golf: "Frisbeegolf"
        case .skate: "Luistelu"
        case .paddle: "Melonta"
        case .swim: "Uinti"
        case .climb: "Kiipeily"
        case .hike: "Vaellus"
        case .row: "Soutu"
        case .ski: "Hiihto"
        case .yoga: "Jooga"
        case .hiit: "HIIT"
        case .combat: "Kamppailulajit"
        case .dance: "Tanssi"
        case .mobility: "Liikkuvuus"
        case .other: "Muu"
        }
    }

    /// Sama jako kuin webin katalogissa (`lib/extra-activities.ts`).
    /// Crosstrainer ja porraslaite jäävät ilman matkaa: laitteen oma lukema ei
    /// päädy Healthiin, joten kenttä olisi lähes aina tyhjä.
    var distanceMode: ActivityDistanceMode {
        switch self {
        case .run, .walk, .treadmill, .hike, .ski: .pace
        case .cycle, .indoor_cycle, .mtb, .downhill_ski, .skate, .paddle, .row: .speed
        case .swim: .swim
        case .stair_climber, .elliptical, .disc_golf, .climb,
             .yoga, .hiit, .combat, .dance, .mobility, .other: .none
        }
    }

    static func distanceMode(for rawValue: String) -> ActivityDistanceMode {
        ExtraActivityType(rawValue: rawValue)?.distanceMode ?? .none
    }
}
