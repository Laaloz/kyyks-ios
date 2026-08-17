import Foundation
import Observation

@Observable
@MainActor
final class WorkoutModel: CachedModel {
    private(set) var setLogs: [WorkoutSetLog] = []
    private(set) var workout: ScheduledWorkout?
    /// Istunto keston laskentaa varten: alku, tauot ja valmistuminen.
    private(set) var session: WorkoutSession?
    var isLoading = false
    var errorMessage: String?
    private(set) var savedNoteBody = ""
    private(set) var isStructureSyncing = false
    private(set) var isCompleting = false
    var noteDraft = ""
    private var noteUpdatedAt: String?

    var doneCount: Int { setLogs.filter(\.isLogged).count }
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

    var api: APIClient?
    private var workoutId = ""
    var cacheKey: String { "workout-\(workoutId)" }
    var resourcePath: String { "/api/mobile/workouts/\(workoutId)" }
    let loadFailureMessage = "Treenin haku epäonnistui."
    var hasContent: Bool { !setLogs.isEmpty }

    func configure(auth: AuthManager, workoutId: String) {
        configure(auth: auth)
        self.workoutId = workoutId
    }

    /// Vain testeille: lokien asetus ilman verkkoa.
    func setLogsForTesting(_ logs: [WorkoutSetLog]) {
        setLogs = logs
    }

    /// Lähettämättömät sarjakirjaukset. Kaksi eri ongelmaa, sama ratkaisu:
    /// palvelimen vastaus voi olla ruutua vanhempi (kirjaus vielä matkalla), ja
    /// sovellus voi sulkeutua ennen kuin pyyntö on perillä. Sama tila myös
    /// levyllä ([[PendingSetStore]]), jotta jälkimmäinenkään ei hävitä sarjaa.
    private var pendingSets: [String: PendingSetPatch] = [:]

    /// Palvelimen rivit, mutta lähettämättömät kirjaukset päälle. Testattavuuden
    /// vuoksi erillään `apply`sta, joka tarvitsee verkkovastauksen.
    func mergingPendingSets(into rows: [WorkoutSetLog]) -> [WorkoutSetLog] {
        guard !pendingSets.isEmpty else { return rows }
        return rows.map { row in
            guard let patch = pendingSets[row.id] else { return row }
            var merged = row
            merged.actualReps = patch.actualReps
            merged.actualLoad = patch.actualLoad
            merged.done = patch.done
            return merged
        }
    }

    /// Vain testeille: lähettämättömän kirjauksen asettaminen ilman verkkoa.
    func setPendingForTesting(_ patch: PendingSetPatch) {
        pendingSets[patch.logId] = patch
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
        guard becameDone, !setLogs.allSatisfy(\.isLogged) else { return nil }
        let rest = Int(previous.targetRestSeconds ?? 90)
        return (restSeconds: rest > 0 ? rest : 90, exerciseName: previous.exerciseName)
    }

    /// Optimistinen kirjaus: paikallinen tila heti, synkka taustalla,
    /// virheessä tila palautetaan. Kirjattaessa toteuma esitäytetään
    /// tavoitteesta, jos käyttäjä ei ole syöttänyt omaa.
    ///
    /// Napin tila luetaan `isLogged`istä eikä `done`sta, ja perutessa myös
    /// arvot tyhjennetään. Muuten nappi voisi olla eri mieltä kuin ruutu:
    /// arvolliseen mutta kuittaamattomaan riviin napautus olisi vaihtanut
    /// pelkän lipun eikä mikään olisi muuttunut näkyvästi.
    /// Palauttaa lepoajan, jos sarja siirtyi kirjatuksi (ajastimen käynnistys).
    @discardableResult
    func toggleDone(logId: String) -> (restSeconds: Int, exerciseName: String)? {
        guard let index = setLogs.firstIndex(where: { $0.id == logId }) else { return nil }
        let previous = setLogs[index]

        if previous.isLogged {
            setLogs[index].done = false
            setLogs[index].actualReps = nil
            setLogs[index].actualLoad = nil
        } else {
            setLogs[index].done = true
            setLogs[index].actualReps = previous.targetReps
            // Kuorma tavoitteesta, tai jos ohjelmassa ei ole painoja, siitä
            // mitä samalla sarjalla nostettiin viimeksi. Ilman tätä kuittaus
            // kirjaisi pelkät toistot, ja paino olisi haettava lomakkeelta
            // joka sarjalla erikseen.
            setLogs[index].actualLoad = previous.targetLoad ?? previousSet(for: previous)?.actualLoad
        }
        sync(setLogs[index], revertTo: previous)

        guard setLogs[index].isLogged else { return nil }
        // Viimeisen sarjan jälkeen lepoa ei tarvita — treeni on ohi.
        // Muuten ajastin käynnistyy aina; treenin päättäminen sammuttaa sen.
        guard !setLogs.allSatisfy(\.isLogged) else { return nil }
        let rest = Int(previous.targetRestSeconds ?? 90)
        return (restSeconds: rest > 0 ? rest : 90, exerciseName: previous.exerciseName)
    }

    func completeWorkout() async {
        guard let api, let updatedAt = workout?.updatedAt else { return }
        isCompleting = true
        defer { isCompleting = false }
        // Odottavat kirjaukset ensin: valmiiksi merkitty treeni ilman viimeisiä
        // sarjoja on huonompi lopputulos kuin hetken odotus.
        await flushPendingWrites()
        do {
            struct Body: Encodable { let expectedUpdatedAt: String }
            _ = try await api.post("/api/workouts/\(workoutId)/complete", body: Body(expectedUpdatedAt: updatedAt))
            await refreshAfterChange()
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
            await refreshAfterChange()
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
                await refreshAfterChange()
            } catch {
                if let previous {
                    setLogs = previous
                }
                errorMessage = "Liikkeen muutos epäonnistui — yritä uudelleen."
            }
        }
    }

    private func sync(_ updated: WorkoutSetLog, revertTo previous: WorkoutSetLog) {
        let patch = PendingSetPatch(
            logId: updated.id,
            actualReps: updated.actualReps,
            actualLoad: updated.actualLoad,
            done: updated.done
        )
        pendingSets[patch.logId] = patch
        let snapshot = pendingSets
        Task { await PendingSetStore.shared.save(workoutId: workoutId, patches: snapshot) }
        Task { await send(patch, revertTo: previous) }
    }

    /// Yhden kirjauksen lähetys.
    ///
    /// Virheen laji ratkaisee, mitä käyttäjän syötteelle tapahtuu. Katko tai
    /// palvelimen häiriö ei ole syy hylätä kirjausta: se jää odottamaan ja
    /// lähtee uudelleen kun treeni seuraavan kerran avataan. Vain palvelimen
    /// selvä hylkäys (4xx) tarkoittaa, ettei kirjaus koskaan kelpaa — vasta
    /// silloin arvo palautetaan ja käyttäjälle kerrotaan.
    private func send(_ patch: PendingSetPatch, revertTo previous: WorkoutSetLog?) async {
        guard let api else { return }
        do {
            struct Body: Encodable { let sets: [PendingSetPatch] }
            _ = try await api.patch("/api/workouts/\(workoutId)/sets", body: Body(sets: [patch]))
            // Vain jos tämä oli viimeisin muutos tälle sarjalle: nopea
            // peräkkäinen kirjaus ehtii korvata arvon kesken pyynnön, eikä
            // vanhentunut vastaus saa poistaa uudempaa odottavaa arvoa.
            if pendingSets[patch.logId] == patch {
                pendingSets.removeValue(forKey: patch.logId)
                let snapshot = pendingSets
                await PendingSetStore.shared.save(workoutId: workoutId, patches: snapshot)
            }
            // Onnistunut lähetys on todiste siitä että verkko toimii juuri nyt.
            // Salin huonossa kentässä aiemmat kirjaukset ovat jääneet
            // odottamaan, eikä niiden pidä odottaa näkymästä poistumista.
            await flushPendingWrites()
        } catch APIError.status(let code) where (400 ..< 500).contains(code) {
            pendingSets.removeValue(forKey: patch.logId)
            let snapshot = pendingSets
            await PendingSetStore.shared.save(workoutId: workoutId, patches: snapshot)
            if let previous, let index = setLogs.firstIndex(where: { $0.id == patch.logId }) {
                setLogs[index] = previous
            }
            errorMessage = "Tallennus epäonnistui — yritä uudelleen."
        } catch {
            // Jää odottamaan. Arvoa ei palauteta: se on ruudulla ja levyllä,
            // ja se lähtee uudelleen kun treeni avataan seuraavan kerran.
        }
    }

    /// Levyllä odottavat kirjaukset käyttöön ja uudelleen matkaan.
    ///
    /// Kutsutaan treeniä avattaessa ennen hakua, jotta edellisellä kerralla
    /// lähettämättä jäänyt sarja näkyy heti eikä vasta onnistuneen lähetyksen
    /// jälkeen.
    func restorePendingWrites() async {
        let stored = await PendingSetStore.shared.load(workoutId: workoutId)
        guard !stored.isEmpty else { return }
        pendingSets = stored.merging(pendingSets) { _, newer in newer }
        setLogs = mergingPendingSets(into: setLogs)
    }

    /// Odottavien uudelleenlähetys. Aiempi arvo ei ole tiedossa, joten
    /// hylkäyksessä ei ole mitään mihin palata — palvelimen tila haetaan
    /// tuolloin joka tapauksessa.
    ///
    /// Lippu katkaisee rekursion: `send` kutsuu tätä onnistuessaan.
    func flushPendingWrites() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        for patch in pendingSets.values {
            await send(patch, revertTo: nil)
        }
    }

    private var isFlushing = false

    /// Edellisen kerran tulos liikkeen ja sarjan numeron mukaan.
    private(set) var previousSets: [String: PreviousSet] = [:]

    /// Edellinen tulos tälle sarjalle, jos se on tiedossa.
    func previousSet(for log: WorkoutSetLog) -> PreviousSet? {
        previousSets["\(log.exerciseId)#\(log.setLabel)"]
    }

    func apply(_ data: Data) {
        guard let detail = try? JSONDecoder().decode(WorkoutDetail.self, from: data) else { return }
        setLogs = mergingPendingSets(into: detail.setLogs)
        previousSets = Dictionary(
            (detail.previousSets ?? []).map { ("\($0.exerciseId)#\($0.setLabel)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        workout = detail.workout
        session = detail.session
        let previousSaved = savedNoteBody
        savedNoteBody = detail.note?.body ?? ""
        noteUpdatedAt = detail.note?.updatedAt
        // Luonnosta ei ylikirjoiteta, jos käyttäjä on ehtinyt kirjoittaa omaa.
        if noteDraft.isEmpty || noteDraft == previousSaved {
            noteDraft = savedNoteBody
        }
    }
}
