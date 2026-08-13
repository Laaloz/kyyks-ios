import SwiftUI

/// Oheisaktiviteetin kirjaus käsin. Kalorit laskee palvelin lajin MET-kertoimesta
/// ja painosta, ellei käyttäjä anna omaa lukemaa — sama logiikka kuin webissä.
struct AddActivitySheet: View {
    let auth: AuthManager
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var activityType: ExtraActivityType = .run
    @State private var durationText = "30"
    @State private var kcalText = ""
    @State private var occurredAt = Date.now
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

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

                    DatePicker("Ajankohta", selection: $occurredAt, in: ...Date.now)
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
            .navigationTitle("Lisää suoritus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peru") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tallenna") { Task { await save() } }
                        .disabled(isSaving || durationMinutes == nil)
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
        }

        do {
            _ = try await APIClient(auth: auth).post("/api/extra-activities", body: Body(
                activityType: activityType.rawValue,
                durationMinutes: minutes,
                manualKcal: Double(kcalText).flatMap { $0 > 0 ? $0 : nil },
                occurredAt: ISO8601DateFormatter().string(from: occurredAt),
                notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes
            ))
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
}
