import SwiftUI

/// Liikkeen muistiinpanon muokkaus: "keltainen nauha", "leveä ote". Teksti
/// näytetään aina kun liike tulee vastaan, joten sen pitää olla lyhyt.
struct NoteEdit: Identifiable {
    let exerciseId: String
    let name: String
    let text: String
    var id: String { exerciseId }
}

struct ExerciseNoteSheet: View {
    let exerciseName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    /// Sama raja kuin palvelimella.
    private static let maxLength = 500

    init(exerciseName: String, initialText: String, onSave: @escaping (String) -> Void) {
        self.exerciseName = exerciseName
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Esim. keltainen nauha", text: $text, axis: .vertical)
                        .lineLimit(3 ... 8)
                        .focused($focused)
                        .onChange(of: text) {
                            if text.count > Self.maxLength { text = String(text.prefix(Self.maxLength)) }
                        }
                } footer: {
                    Text("Näkyy aina kun teet tämän liikkeen.")
                }
                if !text.isEmpty {
                    Section {
                        Button("Poista muistiinpano", role: .destructive) {
                            onSave("")
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peruuta") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tallenna") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
            .onAppear { focused = true }
        }
    }
}
