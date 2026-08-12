import SwiftUI

/// Mittauksen kirjaus: paino ja vyötärö. Pituus on kertaluontoinen
/// profiilitieto eikä seurattava mitta, joten se ei ole täällä — toistuva
/// kirjaus tuotti vain historiarivejä joissa ei ollut mitään seurattavaa.
/// Kentät esitäytetään viimeisimmästä, koska mitat liikkuvat vähän.
struct AddMeasurementSheet: View {
    let auth: AuthManager
    let latest: BodyMeasurement?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weightText: String
    @State private var waistText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(auth: AuthManager, latest: BodyMeasurement?, onSaved: @escaping () -> Void) {
        self.auth = auth
        self.latest = latest
        self.onSaved = onSaved
        _weightText = State(initialValue: Self.format(latest?.weightKg))
        _waistText = State(initialValue: Self.format(latest?.waistCm))
    }

    private var hasAnyValue: Bool {
        [weightText, waistText].contains { Self.parse($0) != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Paino", text: $weightText, unit: "kg")
                    field("Vyötärö", text: $waistText, unit: "cm")
                } footer: {
                    Text("Tyhjäksi jätettyä mittaa ei kirjata. Paino päivittyy myös ravintolaskennan pohjaksi.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Kirjaa mittaus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peru") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tallenna") { Task { await save() } }
                        .disabled(isSaving || !hasAnyValue)
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        struct Body: Encodable {
            let weightKg: Double?
            let waistCm: Double?
        }

        do {
            _ = try await APIClient(auth: auth).post("/api/mobile/measurements", body: Body(
                weightKg: Self.parse(weightText),
                waistCm: Self.parse(waistText)
            ))
            onSaved()
            dismiss()
        } catch {
            errorMessage = "Mittauksen tallennus epäonnistui — yritä uudelleen."
        }
    }

    /// Hyväksyy sekä desimaalipilkun että -pisteen.
    private static func parse(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
