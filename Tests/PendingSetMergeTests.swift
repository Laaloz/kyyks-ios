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
        let pending = log(id: "1", reps: 8, load: 80, done: true)
        model.setPendingForTesting(pending)

        // Palvelin ei ole vielä nähnyt kirjausta.
        let fromServer = [log(id: "1", reps: nil, load: nil, done: false)]
        let merged = model.mergingPendingSets(into: fromServer)

        XCTAssertEqual(merged.first?.actualReps, 8)
        XCTAssertEqual(merged.first?.actualLoad, 80)
        XCTAssertTrue(merged.first?.done == true)
    }

    func testRowsWithoutPendingChangeComeFromServer() {
        let model = WorkoutModel()
        model.setPendingForTesting(log(id: "1", reps: 8, load: 80, done: true))

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
