import XCTest
@testable import Volu

/// Sarjan suhde tavoitealueeseen. Sääntö on tiukka tarkoituksella: merkki
/// kuuluu vain poikkeukselle, ja väärä merkki on pahempi kuin puuttuva —
/// käyttäjä oppii nopeasti olemaan uskomatta merkkiä joka on usein väärässä.
final class SetOutcomeTests: XCTestCase {
    private func log(
        reps: Double?,
        load: Double? = 60,
        targetReps: Double = 8,
        min: Double? = 8,
        max: Double? = 10,
        targetLoad: Double? = 60
    ) -> WorkoutSetLog {
        WorkoutSetLog(
            id: "1",
            templateExerciseId: "e1",
            setId: "s1",
            exerciseId: "ex",
            exerciseName: "Penkkipunnerrus",
            supersetGroup: nil,
            setLabel: "1",
            targetReps: targetReps,
            targetRepsMin: min,
            targetRepsMax: max,
            targetLoad: targetLoad,
            targetRestSeconds: 90,
            actualReps: reps,
            actualLoad: load,
            done: reps != nil
        )
    }

    func testWithinRangeIsNotMarked() {
        XCTAssertEqual(log(reps: 9).outcome, .onTarget)
        XCTAssertEqual(log(reps: 8).outcome, .onTarget)
        XCTAssertEqual(log(reps: 10).outcome, .onTarget)
    }

    func testBelowRangeAtSameLoadIsMarked() {
        XCTAssertEqual(log(reps: 6).outcome, .below)
    }

    func testBelowRangeAtHeavierLoadIsNotMarked() {
        // Tavallinen vaihtokauppa, ei alisuoritus.
        XCTAssertEqual(log(reps: 6, load: 70).outcome, .onTarget)
    }

    func testBelowRangeAtLighterLoadIsMarked() {
        // Vähemmän toistoja kevyemmällä kuormalla on aidosti alle tavoitteen.
        XCTAssertEqual(log(reps: 6, load: 50).outcome, .below)
    }

    func testAboveRangeAtSameLoadIsMarked() {
        XCTAssertEqual(log(reps: 12).outcome, .above)
    }

    func testAboveRangeAtLighterLoadIsNotMarked() {
        XCTAssertEqual(log(reps: 12, load: 40).outcome, .onTarget)
    }

    func testUnloggedSetIsNotMarked() {
        XCTAssertEqual(log(reps: nil).outcome, .onTarget)
    }

    func testSingleTargetWithoutRange() {
        XCTAssertEqual(log(reps: 4, min: nil, max: nil, targetLoad: 100).outcome, .below)
        XCTAssertEqual(log(reps: 8, min: nil, max: nil, targetLoad: 100).outcome, .onTarget)
    }

    func testBodyweightExerciseComparesRepsAlone() {
        // Ei tavoitekuormaa: toistot ratkaisevat yksin, eikä puuttuva kuorma
        // saa estää merkkiä.
        XCTAssertEqual(log(reps: 5, load: nil, targetLoad: nil).outcome, .below)
    }
}

/// Kirjatun sarjan tunnistaminen. Vanhat rivit kantavat arvot ilman
/// kuittauslippua, eikä näkymä saa esittää niitä tyhjinä.
final class SetLoggedStateTests: XCTestCase {
    private func log(reps: Double?, load: Double?, done: Bool) -> WorkoutSetLog {
        WorkoutSetLog(
            id: "1", templateExerciseId: "e1", setId: "s1", exerciseId: "ex",
            exerciseName: "Soutu", supersetGroup: nil, setLabel: "1",
            targetReps: 8, targetRepsMin: 8, targetRepsMax: 10,
            targetLoad: 23, targetRestSeconds: 90,
            actualReps: reps, actualLoad: load, done: done
        )
    }

    func testValuesWithoutFlagCountAsLogged() {
        XCTAssertTrue(log(reps: 9, load: 23, done: false).isLogged)
    }

    func testFlagWithoutValuesCountsAsLogged() {
        XCTAssertTrue(log(reps: nil, load: nil, done: true).isLogged)
    }

    func testEmptySetIsNotLogged() {
        XCTAssertFalse(log(reps: nil, load: nil, done: false).isLogged)
    }

    func testLoadAloneCountsAsLogged() {
        XCTAssertTrue(log(reps: nil, load: 23, done: false).isLogged)
    }
}

/// Vanha välimuistivastaus levyllä ei sisällä uusia kenttiä. Jos dekoodaus
/// kaatuu niihin, näkymä jää tyhjäksi hiljaa — päivityksen jälkeen ensimmäinen
/// avaus lukee juuri sellaisen vastauksen.
final class WorkoutDetailDecodingTests: XCTestCase {
    private let withoutPreviousSets = """
    {
      "workout": {
        "id": "w1", "athleteId": "a1", "title": "Koko",
        "scheduledDate": "2026-08-14", "status": "completed"
      },
      "session": null,
      "note": null,
      "setLogs": []
    }
    """

    func testDecodesResponseWithoutPreviousSets() throws {
        let data = Data(withoutPreviousSets.utf8)
        let detail = try JSONDecoder().decode(WorkoutDetail.self, from: data)
        XCTAssertNil(detail.previousSets)
        XCTAssertEqual(detail.workout.title, "Koko")
    }
}
