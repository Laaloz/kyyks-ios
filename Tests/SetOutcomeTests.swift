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

    func testFlagWithoutValuesCountsAsLogged() {
        XCTAssertTrue(log(reps: nil, load: nil, done: true).isLogged)
    }

    func testEmptySetIsNotLogged() {
        XCTAssertFalse(log(reps: nil, load: nil, done: false).isLogged)
    }

    /// Palvelin esitäyttää toistot ja kuorman edellisen kerran tuloksilla heti
    /// treenin alkaessa. Ne ovat ehdotus, eivät suoritus.
    ///
    /// Kun tässä hyväksyttiin myös esitäytetty arvo, koko treeni näytti
    /// kuitatulta ensimmäisestä sekunnista: kuittausnappi poisti kirjauksen
    /// sen sijaan että olisi tehnyt sen, eikä lepoajastin käynnistynyt
    /// kertaakaan.
    func testPrefilledValuesAreNotLoggedWithoutFlag() {
        XCTAssertFalse(log(reps: 9, load: 23, done: false).isLogged)
        XCTAssertFalse(log(reps: nil, load: 23, done: false).isLogged)
        XCTAssertFalse(log(reps: 9, load: nil, done: false).isLogged)
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

/// Kehotus kuorman nostoon. Sääntö on tiukka tarkoituksella: väärä kehotus
/// johtaa epäonnistuneeseen sarjaan seuraavalla kerralla.
final class LoadProgressionTests: XCTestCase {
    private func log(_ label: String, reps: Double?, load: Double?, max: Double? = 10) -> WorkoutSetLog {
        WorkoutSetLog(
            id: "s\(label)", templateExerciseId: "e1", setId: "set\(label)", exerciseId: "ex",
            exerciseName: "Penkkipunnerrus", supersetGroup: nil, setLabel: label,
            targetReps: 8, targetRepsMin: 8, targetRepsMax: max,
            targetLoad: 60, targetRestSeconds: 90,
            actualReps: reps, actualLoad: load, done: reps != nil
        )
    }

    private func group(_ logs: [WorkoutSetLog]) -> ExerciseGroup {
        ExerciseGroup(id: "e1", name: "Penkkipunnerrus", logs: logs)
    }

    func testAllSetsAtCeilingSuggestsHeavierLoad() {
        let sets = group([log("1", reps: 10, load: 60), log("2", reps: 10, load: 60)])
        XCTAssertTrue(sets.isReadyForHeavierLoad)
    }

    func testOneSetShortDoesNotSuggest() {
        let sets = group([log("1", reps: 10, load: 60), log("2", reps: 9, load: 60)])
        XCTAssertFalse(sets.isReadyForHeavierLoad)
    }

    func testUnloggedSetDoesNotSuggest() {
        let sets = group([log("1", reps: 10, load: 60), log("2", reps: nil, load: nil)])
        XCTAssertFalse(sets.isReadyForHeavierLoad)
    }

    func testCeilingReachedAtLighterLoadDoesNotSuggest() {
        // Täydet toistot kevyemmällä painolla eivät kerro että paino on kevyt.
        let sets = group([log("1", reps: 10, load: 50), log("2", reps: 10, load: 50)])
        XCTAssertFalse(sets.isReadyForHeavierLoad)
    }

    func testExceedingCeilingAlsoSuggests() {
        let sets = group([log("1", reps: 12, load: 60), log("2", reps: 11, load: 60)])
        XCTAssertTrue(sets.isReadyForHeavierLoad)
    }

    func testSuggestsWithoutTargetLoad() {
        // Ohjelmassa ei aina ole painoja; kuorman vaatiminen tarkoittaisi
        // ettei kehotus laukeaisi sellaisella ohjelmalla koskaan.
        let noTarget = { (label: String, reps: Double) in
            WorkoutSetLog(
                id: "s\(label)", templateExerciseId: "e1", setId: "set\(label)", exerciseId: "ex",
                exerciseName: "Jalkaprässi", supersetGroup: nil, setLabel: label,
                targetReps: 8, targetRepsMin: 8, targetRepsMax: 10,
                targetLoad: nil, targetRestSeconds: 90,
                actualReps: reps, actualLoad: nil, done: true
            )
        }
        let sets = group([noTarget("1", 10), noTarget("2", 10)])
        XCTAssertTrue(sets.isReadyForHeavierLoad)
    }

    func testWithoutRepRangeDoesNotSuggest() {
        // Ilman ylärajaa ei ole mitään mihin yltää.
        let sets = group([log("1", reps: 10, load: 60, max: nil), log("2", reps: 10, load: 60, max: nil)])
        XCTAssertFalse(sets.isReadyForHeavierLoad)
    }
}

/// Treenin kesto. Sama sääntö kuin webissä: kahtena toteutuksena sama treeni
/// voisi näkyä eri pituisena.
final class SessionDurationTests: XCTestCase {
    private func session(started: String, completed: String? = nil, paused: String? = nil, pausedSeconds: Double? = nil, updated: String? = nil) -> WorkoutSession {
        WorkoutSession(
            id: "s1", startedAt: started, completedAt: completed,
            pausedAt: paused, pausedDurationSeconds: pausedSeconds, updatedAt: updated
        )
    }

    func testCompletedSessionUsesCompletionTime() {
        let s = session(started: "2026-08-17T10:00:00Z", completed: "2026-08-17T11:00:00Z")
        XCTAssertEqual(s.durationSeconds(), 3600)
    }

    func testPausedSecondsAreSubtracted() {
        let s = session(started: "2026-08-17T10:00:00Z", completed: "2026-08-17T11:00:00Z", pausedSeconds: 600)
        XCTAssertEqual(s.durationSeconds(), 3000)
    }

    func testRunningSessionGrowsWithNow() {
        let s = session(started: "2026-08-17T10:00:00Z")
        let now = ISO8601DateFormatter().date(from: "2026-08-17T10:30:00Z")!
        XCTAssertEqual(s.durationSeconds(now: now), 1800)
    }

    func testPausedSessionStopsAtPauseTime() {
        let s = session(started: "2026-08-17T10:00:00Z", paused: "2026-08-17T10:20:00Z")
        let now = ISO8601DateFormatter().date(from: "2026-08-17T11:00:00Z")!
        XCTAssertEqual(s.durationSeconds(now: now), 1200)
    }

    func testNegativeRangeIsZero() {
        let s = session(started: "2026-08-17T11:00:00Z", completed: "2026-08-17T10:00:00Z")
        XCTAssertEqual(s.durationSeconds(), 0)
    }
}

/// Lepoajastin näytön ollessa suljettuna.
///
/// Ajastin ei saa perustua tikittävään laskuriin: taustalla ja lukitulla
/// näytöllä ajastimet eivät aja, joten jäljellä oleva aika on laskettava
/// seinäkellosta joka kerta uudelleen.
final class RestTimerPersistenceTests: XCTestCase {
    private let keys = ["restTimerEndsAt", "restTimerTotal", "restTimerName"]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    @MainActor
    func testRemainingComesFromWallClockNotTicks() {
        let timer = RestTimerManager()
        timer.start(seconds: 90, exerciseName: "Penkkipunnerrus")

        // Kello siirtyy eteenpäin ilman että mikään on "tikittänyt".
        let later = Date.now.addingTimeInterval(30)
        XCTAssertEqual(timer.remainingSeconds(at: later), 60)
    }

    @MainActor
    func testTimerSurvivesAppRestart() {
        let timer = RestTimerManager()
        timer.start(seconds: 120, exerciseName: "Kyykky")

        // Uusi ilmentymä = sovellus käynnistetty uudelleen.
        let restored = RestTimerManager()
        XCTAssertTrue(restored.isActive)
        XCTAssertEqual(restored.exerciseName, "Kyykky")
        XCTAssertEqual(restored.totalSeconds, 120)
    }

    @MainActor
    func testExpiredTimerDoesNotComeBack() {
        let timer = RestTimerManager()
        timer.start(seconds: 1, exerciseName: "Soutu")
        // Vanhentunut ajastin ei saa palata ruudulle käynnistyksessä.
        UserDefaults.standard.set(Date.now.addingTimeInterval(-5).timeIntervalSince1970, forKey: "restTimerEndsAt")

        XCTAssertFalse(RestTimerManager().isActive)
    }

    @MainActor
    func testStoppedTimerLeavesNothingBehind() {
        let timer = RestTimerManager()
        timer.start(seconds: 60, exerciseName: "Maastaveto")
        timer.stop()

        XCTAssertFalse(RestTimerManager().isActive)
    }
}

/// Kehon "Viimeisin"-osion arvot. Rivi kantaa vain sen mitä silloin
/// kirjattiin, joten kunkin mitan tuorein arvo on haettava erikseen.
@MainActor
final class LatestMeasurementTests: XCTestCase {
    private func rows(_ json: String) -> [BodyMeasurement] {
        try! JSONDecoder().decode([BodyMeasurement].self, from: Data(json.utf8))
    }

    func testEachMetricUsesItsOwnLatestValue() {
        let model = BodyModel()
        // Uusin rivi on Healthista tuotu paino ilman vyötäröä.
        model.setMeasurementsForTesting(rows("""
        [
          {"id":"1","weightKg":78.3,"waistCm":null,"measuredAt":"2026-08-16T08:14:17Z"},
          {"id":"2","weightKg":79.5,"waistCm":85.5,"measuredAt":"2026-08-07T13:35:35Z"}
        ]
        """))

        XCTAssertEqual(model.latestWeight, 78.3)
        XCTAssertEqual(model.latestWaist, 85.5)
    }

    func testMissingMetricStaysNil() {
        let model = BodyModel()
        model.setMeasurementsForTesting(rows("""
        [{"id":"1","weightKg":80,"waistCm":null,"measuredAt":"2026-08-16T08:14:17Z"}]
        """))

        XCTAssertEqual(model.latestWeight, 80)
        XCTAssertNil(model.latestWaist)
    }
}
