import Foundation
import Observation

@Observable
@MainActor
final class WorkoutModel: CachedModel {
    private(set) var setLogs: [WorkoutSetLog] = []
    private(set) var workout: ScheduledWorkout?
    var isLoading = false
    var errorMessage: String?
    private(set) var savedNoteBody = ""
    private(set) var isStructureSyncing = false
    private(set) var isCompleting = false
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

    private(set) var api: APIClient?
    private var workoutId = ""
    var cacheKey: String { "workout-\(workoutId)" }
    var resourcePath: String { "/api/mobile/workouts/\(workoutId)" }
    let loadFailureMessage = "Treenin haku epäonnistui."
    var hasContent: Bool { !setLogs.isEmpty }

    func configure(auth: AuthManager, workoutId: String) {
        api = APIClient(auth: auth)
        self.workoutId = workoutId
    }

    /// Vain testeille: lokien asetus ilman verkkoa.
    func setLogsForTesting(_ logs: [WorkoutSetLog]) {
        setLogs = logs
    }

    /// Toteuman kirjaaminen merkitsee sarjan tehdyksi: jos toistot tai kuorma on
    /// syötetty, sarja on tehty. Erillinen kuittaus jäi kannassa tekemättä 84
    /// kertaa valmiiksi merkityissä treeneissä (mm. maastaveto 4 × 120 kg), eli
    /// se oli pelkkä virhelähde. Kuittausruutu jää nopeaksi poluksi tavoitteen
    /// mukaiselle sarjalle ja kuittauksen perumiseen.
    /// Palauttaa lepoajan, jos sarja siirtyi tehdyksi.
    @discardableResult
    func updateSet(logId: String, reps: Double?, load: Double?) -> (restSeconds: Int, exerciseName: String)? {
        guard let index = setLogs.firstIndex(where: { $0.id == logId }) else { return nil }
        let previous = setLogs[index]
        setLogs[index].actualReps = reps
        setLogs[index].actualLoad = load

        let becameDone = (reps != nil || load != nil) && !previous.done
        if becameDone {
            setLogs[index].done = true
        }
        sync(setLogs[index], revertTo: previous)

        // Sama sääntö kuin kuittauksessa: viimeisestä sarjasta ei lepoa.
        guard becameDone, !setLogs.allSatisfy(\.done) else { return nil }
        let rest = Int(previous.targetRestSeconds ?? 90)
        return (restSeconds: rest > 0 ? rest : 90, exerciseName: previous.exerciseName)
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
        // Viimeisen sarjan jälkeen lepoa ei tarvita — treeni on ohi.
        // Muuten ajastin käynnistyy aina; treenin päättäminen sammuttaa sen.
        guard !setLogs.allSatisfy(\.done) else { return nil }
        let rest = Int(previous.targetRestSeconds ?? 90)
        return (restSeconds: rest > 0 ? rest : 90, exerciseName: previous.exerciseName)
    }

    func completeWorkout() async {
        guard let api, let updatedAt = workout?.updatedAt else { return }
        isCompleting = true
        defer { isCompleting = false }
        do {
            struct Body: Encodable { let expectedUpdatedAt: String }
            _ = try await api.post("/api/workouts/\(workoutId)/complete", body: Body(expectedUpdatedAt: updatedAt))
            await refresh()
        } catch {
            errorMessage = "Valmiiksi merkintä epäonnistui — päivitä näkymä ja yritä uudelleen."
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
        isStructureSyncing = true
        Task {
            defer { isStructureSyncing = false }
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

    func apply(_ data: Data) {
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
