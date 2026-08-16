import SwiftUI

/// Aktiivisen treenin näkymä. Liikkeet ovat kokoontaittuvia kortteja, jotta
/// pitkäkin treeni pysyy yhdellä silmäyksellä hallittavana; supersetit
/// näytetään yhtenä ryhmänä. Kaikki kirjaukset optimistisesti.
struct WorkoutView: View {
    let auth: AuthManager
    let workoutId: String
    let workoutTitle: String
    /// Keskeytys ja poisto suoritetaan kutsujan mallissa, jotta pyyntö jatkuu
    /// vaikka näkymä suljetaan heti — ja lista voi poistaa rivin optimistisesti.
    var onFinished: ((WorkoutEndAction, String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var model = WorkoutModel()
    @State private var editingLog: WorkoutSetLog?
    @State private var pickerMode: ExercisePickerMode?
    @State private var expanded: Set<String> = []
    @State private var didAutoExpand = false
    @State private var confirmation: Confirmation?
    @State private var restTimer = RestTimerManager()

    private enum Confirmation: Identifiable {
        case complete, cancel, delete
        var id: Int { hashValue }
    }

    var body: some View {
        List {
            if let error = model.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if !model.setLogs.isEmpty {
                progressSection
            }

            ForEach(model.blocks) { block in
                Section {
                    if expanded.contains(block.id) {
                        blockContent(block)
                    }
                } header: {
                    blockHeader(block)
                }
            }

            if model.setLogs.isEmpty && !model.isLoading {
                Section {
                    Text("Treenillä ei ole vielä sarjoja. Aloita treeni webissä, niin sarjat ilmestyvät tähän.")
                        .foregroundStyle(.secondary)
                }
            }

            if model.isStructureSyncing {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Päivitetään liikkeitä…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if model.isEditable {
                Section {
                    Button {
                        pickerMode = .add
                    } label: {
                        Label("Lisää liike", systemImage: "plus.circle")
                    }
                    .disabled(model.isStructureSyncing)
                }
            }

            noteSection

            if model.isEditable && !model.setLogs.isEmpty {
                Section {
                    Button {
                        confirmation = .complete
                    } label: {
                        Group {
                            if model.isCompleting {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.white)
                                    Text("Merkitään valmiiksi…")
                                }
                            } else {
                                Text("Merkitse valmiiksi")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .disabled(model.isCompleting)
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(workoutTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Treenin aikana koko ruutu on kirjaamista varten — välilehtipalkki pois.
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if model.isEditable {
                        Button(role: .destructive) {
                            confirmation = .cancel
                        } label: {
                            Label("Keskeytä treeni", systemImage: "xmark.circle")
                        }
                    }
                    Button(role: .destructive) {
                        confirmation = .delete
                    } label: {
                        Label("Poista treeni", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Treenin valinnat")
            }
        }
        .overlay { if model.isLoading && model.setLogs.isEmpty { ProgressView() } }
        .safeAreaInset(edge: .bottom) {
            if restTimer.isActive {
                RestTimerBar(timer: restTimer)
            }
        }
        .refreshable { await model.refresh() }
        .task {
            model.configure(auth: auth, workoutId: workoutId)
            // Ennen hakua: edellisellä kerralla lähettämättä jäänyt kirjaus
            // näkyy heti, eikä vasta jos uudelleenlähetys onnistuu.
            await model.restorePendingWrites()
            await model.load()
            await model.flushPendingWrites()
            autoExpandFirstUnfinished()
        }
        .sheet(item: $editingLog) { log in
            SetEditSheet(log: log) { reps, load in
                // Kirjaus merkitsee sarjan tehdyksi → lepoajastin käynnistyy
                // samoin kuin kuittauksesta.
                if let rest = model.updateSet(logId: log.id, reps: reps, load: load) {
                    withAnimation(.snappy) {
                        restTimer.start(seconds: rest.restSeconds, exerciseName: rest.exerciseName)
                    }
                }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $pickerMode) { mode in
            ExercisePickerSheet(auth: auth, mode: mode) { exercise in
                switch mode {
                case .replace(let templateExerciseId, _):
                    model.replaceExercise(templateExerciseId: templateExerciseId, with: exercise)
                case .add:
                    model.addExercise(exercise)
                }
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: confirmationBinding, titleVisibility: .visible) {
            switch confirmation {
            case .complete:
                Button("Merkitse valmiiksi") {
                    // Treeni päättyy — käynnissä oleva lepoajastin sammuu.
                    restTimer.stop()
                    Task { await model.completeWorkout() }
                }
            case .cancel:
                Button("Keskeytä treeni", role: .destructive) {
                    restTimer.stop()
                    onFinished?(.cancelled, workoutId)
                    dismiss()
                }
            case .delete:
                Button("Poista treeni", role: .destructive) {
                    restTimer.stop()
                    onFinished?(.deleted, workoutId)
                    dismiss()
                }
            case nil:
                EmptyView()
            }
            Button("Peru", role: .cancel) {}
        } message: {
            switch confirmation {
            case .complete:
                let remaining = model.setLogs.filter { !$0.done }.count
                Text(remaining > 0 ? "\(remaining) sarjaa on vielä kuittaamatta." : "Kaikki sarjat on kuitattu.")
            case .cancel:
                Text("Treeni merkitään keskeytetyksi. Kirjatut sarjat säilyvät.")
            case .delete:
                Text("Treeni ja sen kirjaukset poistetaan pysyvästi.")
            case nil:
                EmptyView()
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .complete: "Merkitäänkö treeni valmiiksi?"
        case .cancel: "Keskeytetäänkö treeni?"
        case .delete: "Poistetaanko treeni?"
        case nil: ""
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        )
    }

    @ViewBuilder
    private func blockHeader(_ block: ExerciseBlock) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { toggle(block.id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(expanded.contains(block.id) ? 90 : 0))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        if block.isSuperset {
                            Text("Supersetti")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tint)
                        }
                        Text(block.title)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)

                    Text("\(block.doneCount)/\(block.logs.count)")
                        .monospacedDigit()
                        .foregroundStyle(block.isComplete ? Color.green : Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(block.isSuperset ? "Supersetti: \(block.title)" : block.title)
            .accessibilityValue("\(block.doneCount) / \(block.logs.count) sarjaa kuitattu")
            .accessibilityHint(expanded.contains(block.id) ? "Sulje kaksoisnapauttamalla" : "Avaa kaksoisnapauttamalla")

            if model.isEditable {
                Menu {
                    ForEach(block.exercises) { exercise in
                        Section(block.isSuperset ? exercise.name : "") {
                            Button {
                                pickerMode = .replace(templateExerciseId: exercise.id, currentName: exercise.name)
                            } label: {
                                Label("Vaihda liike", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button(role: .destructive) {
                                model.removeExercise(templateExerciseId: exercise.id)
                            } label: {
                                Label("Poista liike", systemImage: "trash")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Liikkeen valinnat: \(block.title)")
            }
        }
    }

    @ViewBuilder
    private func blockContent(_ block: ExerciseBlock) -> some View {
        ForEach(block.exercises) { exercise in
            // Supersetissä liikkeet erotellaan omilla otsikoillaan, jotta
            // kierrot pysyvät luettavina saman kortin sisällä.
            if block.isSuperset {
                Text(exercise.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
            ForEach(exercise.logs) { log in
                SetRow(
                    log: log,
                    onToggle: {
                        if let rest = model.toggleDone(logId: log.id) {
                            withAnimation(.snappy) {
                                restTimer.start(seconds: rest.restSeconds, exerciseName: rest.exerciseName)
                            }
                        }
                    },
                    onEdit: { editingLog = log }
                )
            }
        }
    }

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.statusLabel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(model.isCompleted ? Color.green : Color.accentColor)
                    Spacer()
                    Text("\(model.doneCount)/\(model.setLogs.count) sarjaa")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: Double(model.doneCount), total: Double(max(model.setLogs.count, 1)))
                    .tint(model.isCompleted ? .green : .accentColor)
            }
            .padding(.vertical, 4)
        }
    }

    private var noteSection: some View {
        Section("Muistiinpano") {
            TextField("Miten treeni meni?", text: $model.noteDraft, axis: .vertical)
                .lineLimit(2 ... 6)
            if model.noteDraft != model.savedNoteBody {
                Button("Tallenna muistiinpano") {
                    Task { await model.saveNote() }
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    /// Salikäytössä oleellinen on seuraava kesken oleva liike — se avataan
    /// valmiiksi, loput pysyvät kiinni.
    private func autoExpandFirstUnfinished() {
        guard !didAutoExpand, !model.blocks.isEmpty else { return }
        didAutoExpand = true
        if let next = model.blocks.first(where: { !$0.isComplete }) {
            expanded.insert(next.id)
        } else if let first = model.blocks.first {
            expanded.insert(first.id)
        }
    }
}
