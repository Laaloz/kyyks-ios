import SwiftUI

/// Treenin keston korjaus.
///
/// Kesto mitataan aloituksesta valmistumiseen, joten päälle unohtunut treeni
/// kirjaa tuntikausia. Sitä ei voi päätellä puolesta — vain treenaaja tietää
/// milloin hän oikeasti lopetti — joten korjaus on käsin, ei automaattinen
/// arvaus.
struct DurationEditSheet: View {
    let currentSeconds: Int
    let onSave: (_ seconds: Int) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var minutesText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    init(currentSeconds: Int, onSave: @escaping (_ seconds: Int) async -> String?) {
        self.currentSeconds = currentSeconds
        self.onSave = onSave
        _minutesText = State(initialValue: String(max(1, currentSeconds / 60)))
    }

    private var minutes: Int? {
        guard let value = Int(minutesText.trimmingCharacters(in: .whitespaces)), value >= 1 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    // Pikasäätimet kuten sarjan muokkauksessa: salilla
                    // näppäimistö on hidas, ja korjaus on yleensä pyöreitä
                    // kymmeniä minuutteja.
                    stepButton("minus", step: -5)
                    TextField("Minuuttia", text: $minutesText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                        .focused($focused)
                        .frame(maxWidth: .infinity)
                    stepButton("plus", step: 5)
                }

                // Yksikkö kertoo mitä numero on; tuntimuoto kertoo mitä se
                // tarkoittaa. Jälkimmäinen vain kun se eroaa numerosta —
                // "45 min" kahdesti peräkkäin ei kanna tietoa.
                Text(minutes.map { $0 >= 60 ? formatDuration(minutes: $0) : "minuuttia" } ?? "minuuttia")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    save()
                } label: {
                    Group {
                        if isSaving {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("Tallennetaan…")
                            }
                        } else {
                            Text("Tallenna")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .prominentButtonLabel()
                .controlSize(.large)
                .disabled(minutes == nil || isSaving)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Treenin kesto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peru") { dismiss() }.disabled(isSaving)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func stepButton(_ symbol: String, step: Int) -> some View {
        Button {
            let current = minutes ?? max(1, currentSeconds / 60)
            minutesText = String(max(1, current + step))
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityLabel(step > 0 ? "Lisää viisi minuuttia" : "Vähennä viisi minuuttia")
    }

    private func save() {
        guard let minutes else { return }
        isSaving = true
        errorMessage = nil
        Task {
            let failure = await onSave(minutes * 60)
            isSaving = false
            if let failure {
                errorMessage = failure
            } else {
                dismiss()
            }
        }
    }
}
