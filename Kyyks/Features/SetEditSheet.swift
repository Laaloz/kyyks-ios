import SwiftUI

/// Sarjan toistojen ja kuorman muokkaus: numeronäppäimistö, pikasäätimet
/// (±1 toisto, ±2,5 kg) ja desimaalipilkun hyväksyntä. Esitäyttö toteumasta
/// tai tavoitteesta — salilla kirjaus on kahden napautuksen päässä.
struct SetEditSheet: View {
    let log: WorkoutSetLog
    let onSave: (_ reps: Double?, _ load: Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var repsText: String
    @State private var loadText: String
    @FocusState private var focusedField: Field?

    private enum Field { case reps, load }

    init(log: WorkoutSetLog, onSave: @escaping (_ reps: Double?, _ load: Double?) -> Void) {
        self.log = log
        self.onSave = onSave
        let reps = log.actualReps ?? log.targetReps
        let load = log.actualLoad ?? log.targetLoad
        _repsText = State(initialValue: reps > 0 ? Self.format(reps) : "")
        _loadText = State(initialValue: load.map(Self.format) ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    fieldColumn(title: "Toistot", text: $repsText, field: .reps, step: 1)
                    fieldColumn(title: "Kuorma (kg)", text: $loadText, field: .load, step: 2.5)
                }

                Button {
                    save()
                } label: {
                    Text("Tallenna")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(20)
            .navigationTitle("\(log.exerciseName) · sarja \(log.setLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peru") { dismiss() }
                }
            }
        }
        .onAppear { focusedField = .reps }
    }

    private func fieldColumn(title: String, text: Binding<String>, field: Field, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 12) {
                stepButton("minus") { adjust(text, by: -step) }
                stepButton("plus") { adjust(text, by: step) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func adjust(_ text: Binding<String>, by step: Double) {
        let current = Self.parse(text.wrappedValue) ?? 0
        let next = max(0, current + step)
        text.wrappedValue = Self.format(next)
    }

    private func save() {
        onSave(Self.parse(repsText), Self.parse(loadText))
        dismiss()
    }

    /// Hyväksyy sekä desimaalipilkun että -pisteen.
    private static func parse(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value >= 0 else { return nil }
        return value
    }

    private static func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
