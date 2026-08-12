import SwiftUI

/// Aktiivisen treenin näkymä. Liikkeet ovat kokoontaittuvia kortteja, jotta
/// pitkäkin treeni pysyy yhdellä silmäyksellä hallittavana; supersetit
/// näytetään yhtenä ryhmänä. Kaikki kirjaukset optimistisesti.
struct WorkoutView: View {
    let auth: AuthManager
    let workoutId: String
    let workoutTitle: String

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

            if model.isEditable {
                Section {
                    Button {
                        pickerMode = .add
                    } label: {
                        Label("Lisää liike", systemImage: "plus.circle")
                    }
                }
            }

            noteSection

            if model.isEditable && !model.setLogs.isEmpty {
                Section {
                    Button {
                        confirmation = .complete
                    } label: {
                        Text("Merkitse valmiiksi")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
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
            await model.load()
            autoExpandFirstUnfinished()
        }
        .sheet(item: $editingLog) { log in
            SetEditSheet(log: log) { reps, load in
                model.updateSet(logId: log.id, reps: reps, load: load)
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
                    Task { await model.completeWorkout() }
                }
            case .cancel:
                Button("Keskeytä treeni", role: .destructive) {
                    Task {
                        if await model.cancelWorkout() { dismiss() }
                    }
                }
            case .delete:
                Button("Poista treeni", role: .destructive) {
                    Task {
                        if await model.deleteWorkout() { dismiss() }
                    }
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

enum ExercisePickerMode: Identifiable {
    case replace(templateExerciseId: String, currentName: String)
    case add

    var id: String {
        switch self {
        case .replace(let templateExerciseId, _): "replace-\(templateExerciseId)"
        case .add: "add"
        }
    }

    var title: String {
        switch self {
        case .replace(_, let currentName): "Vaihda: \(currentName)"
        case .add: "Lisää liike"
        }
    }
}

/// Yksi liike sarjoineen.
struct ExerciseGroup: Identifiable {
    let id: String
    let name: String
    let logs: [WorkoutSetLog]
}

/// Yksi kortti: joko yksittäinen liike tai supersetti (2+ liikettä).
struct ExerciseBlock: Identifiable {
    let id: String
    let isSuperset: Bool
    let exercises: [ExerciseGroup]

    var logs: [WorkoutSetLog] { exercises.flatMap(\.logs) }
    var doneCount: Int { logs.filter(\.done).count }
    var isComplete: Bool { !logs.isEmpty && doneCount == logs.count }
    var title: String { exercises.map(\.name).joined(separator: " + ") }
}

private struct SetRow: View {
    let log: WorkoutSetLog
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Kuittaus ja muokkaus ovat erilliset kosketusalueet: vasen puoli
            // kuittaa, oikean puolen lukema avaa toistojen/kuorman muokkauksen.
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: log.done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(log.done ? Color.green : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.setLabel)
                            .font(.subheadline.weight(.medium))
                        Text(targetText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sarja \(log.setLabel), tavoite \(targetText)")
            .accessibilityValue(log.done ? "Kuitattu" : "Kuittaamatta")
            .accessibilityHint(log.done ? "Poista kuittaus kaksoisnapauttamalla" : "Kuittaa sarja kaksoisnapauttamalla")

            Button(action: onEdit) {
                Group {
                    if let reps = log.actualReps {
                        Text("\(Int(reps)) × \(formatLoad(log.actualLoad))")
                            .foregroundStyle(log.done ? Color.primary : Color.secondary)
                    } else {
                        Text("Kirjaa")
                            .foregroundStyle(.tint)
                    }
                }
                .font(.subheadline)
                .monospacedDigit()
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                log.actualReps.map { "Toteuma \(Int($0)) toistoa, \(formatLoad(log.actualLoad))" }
                    ?? "Kirjaa toistot ja kuorma"
            )
            .accessibilityHint("Avaa toistojen ja kuorman muokkauksen")
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: log.done)
    }

    private var targetText: String {
        var parts = ["\(log.targetRepsLabel) toistoa"]
        if let load = log.targetLoad, load > 0 {
            parts.append("\(formatLoad(load))")
        }
        return parts.joined(separator: " · ")
    }

    private func formatLoad(_ load: Double?) -> String {
        guard let load, load > 0 else { return "—" }
        let text = load.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(load))
            : String(format: "%.1f", load).replacingOccurrences(of: ".", with: ",")
        return "\(text) kg"
    }
}

@Observable
@MainActor
final class WorkoutModel {
    private(set) var setLogs: [WorkoutSetLog] = []
    private(set) var workout: ScheduledWorkout?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var savedNoteBody = ""
    var noteDraft = ""
    private var noteUpdatedAt: String?

    var doneCount: Int { setLogs.filter(\.done).count }
    var isCompleted: Bool { workout?.status == "completed" }
    var isEditable: Bool { workout?.status == "in_progress" }

    var statusLabel: String {
        switch workout?.status {
        case "completed": "Tehty"
        case "cancelled": "Keskeytetty"
        case "in_progress": "Käynnissä"
        default: "Ohjelmoitu"
        }
    }

    /// Sarjalokeista kortit: ensin liikkeittäin, sitten supersetit yhteen.
    var blocks: [ExerciseBlock] {
        var order: [String] = []
        var grouped: [String: [WorkoutSetLog]] = [:]
        for log in setLogs {
            if grouped[log.templateExerciseId] == nil {
                order.append(log.templateExerciseId)
            }
            grouped[log.templateExerciseId, default: []].append(log)
        }

        let exercises: [ExerciseGroup] = order.compactMap { key in
            guard let logs = grouped[key], let first = logs.first else { return nil }
            // Sarjat numerojärjestykseen labelin mukaan (kanta ei takaa järjestystä).
            let sorted = logs.sorted {
                (Int($0.setLabel) ?? 0, $0.setLabel) < (Int($1.setLabel) ?? 0, $1.setLabel)
            }
            return ExerciseGroup(id: key, name: first.exerciseName, logs: sorted)
        }

        var blocks: [ExerciseBlock] = []
        var blockIndexByGroup: [String: Int] = [:]
        for exercise in exercises {
            let supersetGroup = exercise.logs.first?.supersetGroup
            if let supersetGroup, let existing = blockIndexByGroup[supersetGroup] {
                let merged = blocks[existing].exercises + [exercise]
                blocks[existing] = ExerciseBlock(id: "ss-\(supersetGroup)", isSuperset: true, exercises: merged)
            } else if let supersetGroup {
                blockIndexByGroup[supersetGroup] = blocks.count
                blocks.append(ExerciseBlock(id: "ss-\(supersetGroup)", isSuperset: false, exercises: [exercise]))
            } else {
                blocks.append(ExerciseBlock(id: exercise.id, isSuperset: false, exercises: [exercise]))
            }
        }
        return blocks
    }

    private var api: APIClient?
    private var workoutId = ""
    private var cacheKey: String { "workout-\(workoutId)" }

    func configure(auth: AuthManager, workoutId: String) {
        api = APIClient(auth: auth)
        self.workoutId = workoutId
    }

    func load() async {
        if let cached = await ResponseCache.shared.read(cacheKey) {
            apply(cached)
        } else {
            isLoading = true
        }
        await refresh()
        isLoading = false
    }

    func refresh() async {
        guard let api else { return }
        do {
            let data = try await api.get("/api/mobile/workouts/\(workoutId)")
            await ResponseCache.shared.write(cacheKey, data: data)
            apply(data)
            errorMessage = nil
        } catch {
            if setLogs.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Toistojen/kuorman tallennus: optimistinen kuten kuittaus.
    func updateSet(logId: String, reps: Double?, load: Double?) {
        guard let index = setLogs.firstIndex(where: { $0.id == logId }) else { return }
        let previous = setLogs[index]
        setLogs[index].actualReps = reps
        setLogs[index].actualLoad = load
        sync(setLogs[index], revertTo: previous)
    }

    /// Optimistinen kuittaus: paikallinen tila heti, synkka taustalla,
    /// virheessä tila palautetaan. Kuitattaessa toteuma esitäytetään
    /// tavoitteesta, jos käyttäjä ei ole syöttänyt omaa.
    /// Palauttaa lepoajan, jos sarja merkittiin tehdyksi (ajastimen käynnistys).
    @discardableResult
    func toggleDone(logId: String) -> (restSeconds: Int, exerciseName: String)? {
        guard let index = setLogs.firstIndex(where: { $0.id == logId }) else { return nil }
        let previous = setLogs[index]

        setLogs[index].done.toggle()
        if setLogs[index].done {
            if setLogs[index].actualReps == nil { setLogs[index].actualReps = previous.targetReps }
            if setLogs[index].actualLoad == nil { setLogs[index].actualLoad = previous.targetLoad }
        }
        sync(setLogs[index], revertTo: previous)

        guard setLogs[index].done else { return nil }
        // Viimeisen sarjan jälkeen lepoa ei tarvita.
        let isLastRemaining = setLogs.allSatisfy(\.done)
        guard !isLastRemaining else { return nil }
        let rest = Int(previous.targetRestSeconds ?? 90)
        return (restSeconds: rest > 0 ? rest : 90, exerciseName: previous.exerciseName)
    }

    func completeWorkout() async {
        guard let api, let updatedAt = workout?.updatedAt else { return }
        do {
            struct Body: Encodable { let expectedUpdatedAt: String }
            _ = try await api.post("/api/workouts/\(workoutId)/complete", body: Body(expectedUpdatedAt: updatedAt))
            await refresh()
        } catch {
            errorMessage = "Valmiiksi merkintä epäonnistui — päivitä näkymä ja yritä uudelleen."
        }
    }

    func cancelWorkout() async -> Bool {
        guard let api else { return false }
        do {
            _ = try await api.post("/api/workouts/\(workoutId)/cancel")
            await ResponseCache.shared.remove(cacheKey)
            return true
        } catch {
            errorMessage = "Treenin keskeytys epäonnistui."
            return false
        }
    }

    func deleteWorkout() async -> Bool {
        guard let api else { return false }
        do {
            _ = try await api.delete("/api/workouts/\(workoutId)")
            await ResponseCache.shared.remove(cacheKey)
            return true
        } catch {
            errorMessage = "Treenin poisto epäonnistui."
            return false
        }
    }

    func saveNote() async {
        guard let api else { return }
        let body = noteDraft
        do {
            struct Body: Encodable {
                let body: String
                let expectedUpdatedAt: String?
            }
            _ = try await api.put("/api/workouts/\(workoutId)/note", body: Body(body: body, expectedUpdatedAt: noteUpdatedAt))
            savedNoteBody = body
            await refresh()
        } catch {
            errorMessage = "Muistiinpanon tallennus epäonnistui."
        }
    }

    func replaceExercise(templateExerciseId: String, with exercise: ExerciseSearchResult) {
        structureAction([
            "type": "replace",
            "templateExerciseId": templateExerciseId,
            "exerciseId": exercise.id,
            "exerciseName": exercise.name,
        ])
    }

    func addExercise(_ exercise: ExerciseSearchResult) {
        structureAction([
            "type": "add_extra",
            "exerciseId": exercise.id,
            "exerciseName": exercise.name,
        ])
    }

    func removeExercise(templateExerciseId: String) {
        // Optimistinen poisto: liike katoaa heti, virheessä palautetaan.
        let previous = setLogs
        setLogs.removeAll { $0.templateExerciseId == templateExerciseId }
        structureAction(["type": "remove", "templateExerciseId": templateExerciseId], revertTo: previous)
    }

    private func structureAction(_ payload: [String: String], revertTo previous: [WorkoutSetLog]? = nil) {
        guard let api else { return }
        Task {
            do {
                _ = try await api.post("/api/workouts/\(workoutId)/exercise-structure", body: payload)
                await refresh()
            } catch {
                if let previous {
                    setLogs = previous
                }
                errorMessage = "Liikkeen muutos epäonnistui — yritä uudelleen."
            }
        }
    }

    private func sync(_ updated: WorkoutSetLog, revertTo previous: WorkoutSetLog) {
        guard let api else { return }
        Task {
            do {
                struct SetPatch: Encodable {
                    let logId: String
                    let actualReps: Double?
                    let actualLoad: Double?
                    let done: Bool
                }
                struct Body: Encodable { let sets: [SetPatch] }
                _ = try await api.patch(
                    "/api/workouts/\(workoutId)/sets",
                    body: Body(sets: [SetPatch(
                        logId: updated.id,
                        actualReps: updated.actualReps,
                        actualLoad: updated.actualLoad,
                        done: updated.done
                    )])
                )
            } catch {
                if let revertIndex = setLogs.firstIndex(where: { $0.id == updated.id }) {
                    setLogs[revertIndex] = previous
                }
                errorMessage = "Tallennus epäonnistui — yritä uudelleen."
            }
        }
    }

    private func apply(_ data: Data) {
        guard let detail = try? JSONDecoder().decode(WorkoutDetail.self, from: data) else { return }
        setLogs = detail.setLogs
        workout = detail.workout
        let previousSaved = savedNoteBody
        savedNoteBody = detail.note?.body ?? ""
        noteUpdatedAt = detail.note?.updatedAt
        // Luonnosta ei ylikirjoiteta, jos käyttäjä on ehtinyt kirjoittaa omaa.
        if noteDraft.isEmpty || noteDraft == previousSaved {
            noteDraft = savedNoteBody
        }
    }
}
