import XCTest
@testable import Volu

/// Kesken olevan sarjakirjauksen säilyminen, kun palvelimen tila haetaan
/// ennen kuin tallennus on ehtinyt perille.
///
/// Ilman yhdistämistä vastaus on ruudulla olevaa tilaa vanhempi, ja kesken
/// treenin se tarkoittaa että juuri kirjattu sarja katoaa silmien edestä.
@MainActor
final class PendingSetMergeTests: XCTestCase {
    private func log(id: String, reps: Double?, load: Double?, done: Bool) -> WorkoutSetLog {
        WorkoutSetLog(
            id: id,
            templateExerciseId: "e1",
            setId: "set-\(id)",
            exerciseId: "ex",
            exerciseName: "Penkkipunnerrus",
            supersetGroup: nil,
            setLabel: "1",
            targetReps: 10,
            targetRepsMin: nil,
            targetRepsMax: nil,
            targetLoad: 60,
            targetRestSeconds: 90,
            actualReps: reps,
            actualLoad: load,
            done: done
        )
    }

    func testPendingSetSurvivesOlderServerResponse() {
        let model = WorkoutModel()
        model.setPendingForTesting(PendingSetPatch(logId: "1", actualReps: 8, actualLoad: 80, done: true))

        // Palvelin ei ole vielä nähnyt kirjausta.
        let fromServer = [log(id: "1", reps: nil, load: nil, done: false)]
        let merged = model.mergingPendingSets(into: fromServer)

        XCTAssertEqual(merged.first?.actualReps, 8)
        XCTAssertEqual(merged.first?.actualLoad, 80)
        XCTAssertTrue(merged.first?.done == true)
    }

    func testRowsWithoutPendingChangeComeFromServer() {
        let model = WorkoutModel()
        model.setPendingForTesting(PendingSetPatch(logId: "1", actualReps: 8, actualLoad: 80, done: true))

        // Toisen sarjan arvo tulee palvelimelta sellaisenaan — yhdistäminen ei
        // saa jäädyttää muita rivejä vanhaan tilaan.
        let fromServer = [
            log(id: "1", reps: nil, load: nil, done: false),
            log(id: "2", reps: 12, load: 40, done: true),
        ]
        let merged = model.mergingPendingSets(into: fromServer)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.last?.actualReps, 12)
        XCTAssertTrue(merged.last?.done == true)
    }

    func testWithoutPendingServerStateWins() {
        let model = WorkoutModel()
        let fromServer = [log(id: "1", reps: 5, load: 50, done: true)]

        XCTAssertEqual(model.mergingPendingSets(into: fromServer).first?.actualReps, 5)
    }
}

/// Lähettämättömien kirjausten säilyminen levyllä: sovellus voi sulkeutua
/// kesken treenin ennen kuin pyyntö on perillä.
final class PendingSetStoreTests: XCTestCase {
    func testPatchesSurviveReload() async {
        let store = PendingSetStore()
        let workoutId = "test-\(UUID().uuidString)"
        let patch = PendingSetPatch(logId: "log-1", actualReps: 10, actualLoad: 60, done: true)

        await store.save(workoutId: workoutId, patches: [patch.logId: patch])
        let loaded = await store.load(workoutId: workoutId)

        XCTAssertEqual(loaded[patch.logId], patch)
        await store.save(workoutId: workoutId, patches: [:])
    }

    func testSavingEmptyRemovesFile() async {
        let store = PendingSetStore()
        let workoutId = "test-\(UUID().uuidString)"
        let patch = PendingSetPatch(logId: "log-1", actualReps: 5, actualLoad: nil, done: false)

        await store.save(workoutId: workoutId, patches: [patch.logId: patch])
        // Tyhjä tarkoittaa "ei odottavia" — tiedosto ei saa jäädä levylle
        // kummittelemaan seuraavaan avaukseen.
        await store.save(workoutId: workoutId, patches: [:])

        let loaded = await store.load(workoutId: workoutId)
        XCTAssertTrue(loaded.isEmpty)
    }
}

/// Ohjelmaluonnoksen muutosten tunnistaminen: peruminen saa kysyä vain kun
/// työtä on oikeasti hukattavana.
final class ProgramDraftChangeTests: XCTestCase {
    /// Vertailu tehdään avattuun luonnokseen otettuun kopioon, ei uuteen
    /// `empty()`yn: treeneillä ja liikkeillä on omat UUID:t, joten kaksi
    /// erikseen luotua tyhjää eivät ole yhtä suuria — eikä tarvitsekaan olla.
    func testUntouchedDraftEqualsOriginal() {
        let original = ProgramDraft.empty()
        let untouched = original
        XCTAssertEqual(untouched, original)
    }

    func testRenamedTitleDiffersFromOriginal() {
        let original = ProgramDraft.empty()
        var edited = original
        edited.title = "Voimakausi"
        XCTAssertNotEqual(edited, original)
    }

    func testAddedExerciseDiffersFromOriginal() {
        let original = ProgramDraft.empty()
        var edited = original
        edited.workouts[0].exercises.append(
            ProgramDraft.DraftExercise(
                exerciseId: "ex-1",
                name: "Kyykky",
                setCount: 3,
                repsMin: 5,
                repsMax: 8,
                restSeconds: 120
            )
        )
        XCTAssertNotEqual(edited, original)
    }
}
