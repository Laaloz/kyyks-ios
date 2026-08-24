import XCTest
@testable import Volu

/// Arvon kirjaamisen ja kuittauksen työnjako: kentät tallentavat vain arvot,
/// kuittaus merkitsee sarjan tehdyksi ja käynnistää levon. Aiemmin arvon
/// kirjaus kuittasi sarjan samalla, jolloin pelkkä luvun korjaaminen merkitsi
/// sarjan tehdyksi ja käynnisti lepoajastimen.
@MainActor
final class SetLoggingTests: XCTestCase {
    /// Toistohaarukka 8–10, jotta esitäytön nollautuminen alarajaan näkyisi:
    /// `targetReps` on haarukan alaraja.
    private func log(
        id: String,
        reps: Double? = nil,
        load: Double? = nil,
        done: Bool = false
    ) -> WorkoutSetLog {
        WorkoutSetLog(
            id: id,
            templateExerciseId: "e1",
            setId: "set-\(id)",
            exerciseId: "ex",
            exerciseName: "Pohkeet prässissä",
            supersetGroup: nil,
            setLabel: id,
            targetReps: 8,
            targetRepsMin: 8,
            targetRepsMax: 10,
            targetLoad: 160,
            targetRestSeconds: 90,
            actualReps: reps,
            actualLoad: load,
            done: done
        )
    }

    private func model(_ logs: [WorkoutSetLog]) -> WorkoutModel {
        let model = WorkoutModel()
        model.setLogsForTesting(logs)
        return model
    }

    func testUpdateSetDoesNotMarkDone() {
        let model = model([log(id: "1"), log(id: "2")])

        model.updateSet(logId: "1", reps: 9, load: 170)

        XCTAssertEqual(model.setLogs.first?.actualReps, 9)
        XCTAssertEqual(model.setLogs.first?.actualLoad, 170)
        XCTAssertFalse(model.setLogs.first?.isLogged ?? true)
    }

    /// Esitäytetty edellisen kerran tulos ei saa nollautua haarukan alarajaan
    /// kuittauksessa.
    func testToggleKeepsPrefilledValues() {
        let model = model([log(id: "1", reps: 10, load: 180), log(id: "2")])

        _ = model.toggleDone(logId: "1")

        XCTAssertTrue(model.setLogs.first?.isLogged ?? false)
        XCTAssertEqual(model.setLogs.first?.actualReps, 10)
        XCTAssertEqual(model.setLogs.first?.actualLoad, 180)
    }

    /// Kesken kirjoituksen tehty kuittaus: kentissä olevat vahvistamattomat
    /// arvot voittavat sekä esitäytön että tavoitteen.
    func testToggleUsesTypedValues() {
        let model = model([log(id: "1", reps: 10, load: 180), log(id: "2")])

        _ = model.toggleDone(logId: "1", reps: 12, load: 185)

        XCTAssertEqual(model.setLogs.first?.actualReps, 12)
        XCTAssertEqual(model.setLogs.first?.actualLoad, 185)
    }

    /// Ilman kirjoitettua tai esitäytettyä arvoa kuittaus kirjaa tavoitteen.
    func testToggleWithoutValuesFallsBackToTarget() {
        let model = model([log(id: "1"), log(id: "2")])

        _ = model.toggleDone(logId: "1")

        XCTAssertEqual(model.setLogs.first?.actualReps, 8)
        XCTAssertEqual(model.setLogs.first?.actualLoad, 160)
    }

    /// Kuittauksen peruminen jättää arvot paikalleen.
    func testUncheckKeepsValues() {
        let model = model([log(id: "1", reps: 10, load: 180), log(id: "2")])
        _ = model.toggleDone(logId: "1")

        _ = model.toggleDone(logId: "1")

        XCTAssertFalse(model.setLogs.first?.isLogged ?? true)
        XCTAssertEqual(model.setLogs.first?.actualReps, 10)
        XCTAssertEqual(model.setLogs.first?.actualLoad, 180)
    }
}
