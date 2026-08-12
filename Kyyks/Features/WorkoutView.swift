import SwiftUI

/// Aktiivisen treenin näkymä: liikkeet sarjoineen, kuittaus yhdellä
/// napautuksella. Optimistinen päivitys: UI muuttuu heti ja synkka kulkee
/// taustalla — virheessä tila perutaan ja kerrotaan käyttäjälle.
struct WorkoutView: View {
    let auth: AuthManager
    let workoutId: String
    let workoutTitle: String

    @State private var model = WorkoutModel()
    @State private var editingLog: WorkoutSetLog?

    private var exerciseGroups: [(name: String, logs: [WorkoutSetLog])] {
        var order: [String] = []
        var grouped: [String: [WorkoutSetLog]] = [:]
        for log in model.setLogs {
            if grouped[log.templateExerciseId] == nil {
                order.append(log.templateExerciseId)
            }
            grouped[log.templateExerciseId, default: []].append(log)
        }
        return order.compactMap { key in
            guard let logs = grouped[key], let first = logs.first else { return nil }
            // Sarjat numerojärjestykseen labelin mukaan (kanta ei takaa järjestystä).
            let sorted = logs.sorted {
                (Int($0.setLabel) ?? 0, $0.setLabel) < (Int($1.setLabel) ?? 0, $1.setLabel)
            }
            return (name: first.exerciseName, logs: sorted)
        }
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

            ForEach(exerciseGroups, id: \.logs.first!.id) { group in
                Section {
                    ForEach(group.logs) { log in
                        SetRow(
                            log: log,
                            onToggle: { model.toggleDone(logId: log.id) },
                            onEdit: { editingLog = log }
                        )
                    }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text("\(group.logs.filter(\.done).count)/\(group.logs.count)")
                            .monospacedDigit()
                    }
                }
            }

            if model.setLogs.isEmpty && !model.isLoading {
                Section {
                    Text("Treenillä ei ole vielä sarjoja. Aloita treeni webissä, niin sarjat ilmestyvät tähän.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(workoutTitle)
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if model.isLoading && model.setLogs.isEmpty { ProgressView() } }
        .refreshable { await model.refresh() }
        .task {
            model.configure(auth: auth, workoutId: workoutId)
            await model.load()
        }
        .sheet(item: $editingLog) { log in
            SetEditSheet(log: log) { reps, load in
                model.updateSet(logId: log.id, reps: reps, load: load)
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
    }
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
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
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
    private(set) var isLoading = false
    private(set) var errorMessage: String?

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
    func toggleDone(logId: String) {
        guard let index = setLogs.firstIndex(where: { $0.id == logId }), let api else { return }
        let previous = setLogs[index]

        setLogs[index].done.toggle()
        if setLogs[index].done {
            if setLogs[index].actualReps == nil { setLogs[index].actualReps = previous.targetReps }
            if setLogs[index].actualLoad == nil { setLogs[index].actualLoad = previous.targetLoad }
        }
        sync(setLogs[index], revertTo: previous)
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
    }
}
