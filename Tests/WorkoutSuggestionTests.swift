import XCTest
@testable import Volu

/// Seuraavan treenin ehdotus ja kuorman nostokehotus.
final class NextWorkoutTests: XCTestCase {
    private func summary(_ id: String, _ name: String) -> ProgramWorkoutSummary {
        let json = #"{"id":"\#(id)","name":"\#(name)","exerciseCount":3}"#
        return try! JSONDecoder().decode(ProgramWorkoutSummary.self, from: Data(json.utf8))
    }

    private func program(_ workouts: [ProgramWorkoutSummary]) -> Program {
        let list = workouts.map { #"{"id":"\#($0.id)","name":"\#($0.name)","exerciseCount":3}"# }.joined(separator: ",")
        let json = #"{"id":"p1","title":"Ohjelma","status":"active","workouts":[\#(list)]}"#
        return try! JSONDecoder().decode(Program.self, from: Data(json.utf8))
    }

    private func done(_ title: String, workoutId: String?, at isoDate: String, status: String = "completed") -> ScheduledWorkout {
        let json = """
        {"id":"s-\(title)-\(isoDate)","athleteId":"a","title":"\(title)","scheduledDate":"\(isoDate)",
         "status":"\(status)","completedAt":"\(isoDate)T10:00:00Z"
         \(workoutId.map { #","programWorkoutId":"\#($0)""# } ?? "")}
        """
        return try! JSONDecoder().decode(ScheduledWorkout.self, from: Data(json.utf8))
    }

    private var abc: Program {
        program([summary("a", "Ylä"), summary("b", "Ala"), summary("c", "Koko")])
    }

    func testStartsFromFirstWhenNothingIsDone() {
        XCTAssertEqual(NextWorkout.pick(in: abc, completed: [])?.id, "a")
    }

    func testContinuesAfterMostRecentlyCompleted() {
        let completed = [
            done("Ylä", workoutId: "a", at: "2026-10-05"),
            done("Ala", workoutId: "b", at: "2026-10-08"),
        ]
        XCTAssertEqual(NextWorkout.pick(in: abc, completed: completed)?.id, "c")
    }

    func testWrapsAroundAfterLast() {
        XCTAssertEqual(NextWorkout.pick(in: abc, completed: [done("Koko", workoutId: "c", at: "2026-10-08")])?.id, "a")
    }

    func testIgnoresUnfinishedWorkouts() {
        let completed = [
            done("Ala", workoutId: "b", at: "2026-10-08", status: "cancelled"),
            done("Ylä", workoutId: "a", at: "2026-10-05"),
        ]
        XCTAssertEqual(NextWorkout.pick(in: abc, completed: completed)?.id, "b")
    }

    func testFallsBackToTitleWhenIdIsMissingFromOldCache() {
        XCTAssertEqual(NextWorkout.pick(in: abc, completed: [done("Ylä", workoutId: nil, at: "2026-10-05")])?.id, "b")
    }

    func testEmptyProgramHasNoSuggestion() {
        XCTAssertNil(NextWorkout.pick(in: program([]), completed: []))
    }

    func testLastDoneIsNilWhenUnknown() {
        XCTAssertNil(NextWorkout.lastDone(of: summary("a", "Ylä"), in: []))
    }

    func testDaysAgoText() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        let now = ISO8601DateFormatter().date(from: "2026-10-12T12:00:00Z")!
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: -offset, to: now)! }
        XCTAssertEqual(NextWorkout.daysAgoText(day(0), now: now, calendar: calendar), "tänään")
        XCTAssertEqual(NextWorkout.daysAgoText(day(1), now: now, calendar: calendar), "eilen")
        XCTAssertEqual(NextWorkout.daysAgoText(day(5), now: now, calendar: calendar), "5 pv sitten")
    }
}

/// Kehotus kuorman nostoon. Sääntö on tiukka tarkoituksella: väärä kehotus
/// johtaa epäonnistuneeseen sarjaan seuraavalla kerralla.
final class ProgressionHintTests: XCTestCase {
    private func log(
        _ label: String, done: Bool = false, max: Double? = 10, targetLoad: Double? = 60
    ) -> WorkoutSetLog {
        WorkoutSetLog(
            id: "s\(label)", templateExerciseId: "e1", setId: "set\(label)", exerciseId: "ex",
            exerciseName: "Penkkipunnerrus", supersetGroup: nil, setLabel: label,
            targetReps: 8, targetRepsMin: 8, targetRepsMax: max,
            targetLoad: targetLoad, targetRestSeconds: 90,
            actualReps: nil, actualLoad: nil, done: done
        )
    }

    private func previous(_ reps: Double?, _ load: Double?, label: String) -> PreviousSet {
        let json = """
        {"exerciseId":"ex","setLabel":"\(label)","actualReps":\(reps.map { String($0) } ?? "null"),
         "actualLoad":\(load.map { String($0) } ?? "null"),"performedAt":"2026-10-08T10:00:00Z"}
        """
        return try! JSONDecoder().decode(PreviousSet.self, from: Data(json.utf8))
    }

    private func hint(
        logs: [WorkoutSetLog], results: [String: (Double?, Double?)]
    ) -> ProgressionHint? {
        ProgressionHint.make(
            for: ExerciseGroup(id: "e1", name: "Penkkipunnerrus", logs: logs),
            previous: { log in results[log.setLabel].map { previous($0.0, $0.1, label: log.setLabel) } }
        )
    }

    func testSuggestsConcreteLoadWhenAllSetsReachedCeiling() {
        let result = hint(logs: [log("1"), log("2")], results: ["1": (10, 60), "2": (10, 60)])
        XCTAssertEqual(result, ProgressionHint(previousLoad: 60, suggestedLoad: 62.5, reps: 10))
        XCTAssertEqual(result?.text, "Viimeksi 60 kg × 10 · kokeile 62,5 kg")
    }

    func testOneSetShortDoesNotSuggest() {
        XCTAssertNil(hint(logs: [log("1"), log("2")], results: ["1": (10, 60), "2": (9, 60)]))
    }

    func testExceedingCeilingAlsoSuggestsAndShowsLowestReps() {
        let result = hint(logs: [log("1"), log("2")], results: ["1": (12, 60), "2": (11, 60)])
        XCTAssertEqual(result?.reps, 11)
    }

    func testMissingPreviousSetDoesNotSuggest() {
        // Uusi sarja ilman vertailua ei kerro mitään.
        XCTAssertNil(hint(logs: [log("1"), log("2")], results: ["1": (10, 60)]))
    }

    func testCeilingAtLighterLoadThanTargetDoesNotSuggest() {
        // Täydet toistot kevyemmällä painolla eivät kerro että paino on kevyt.
        XCTAssertNil(hint(logs: [log("1"), log("2")], results: ["1": (10, 50), "2": (10, 50)]))
    }

    func testWithoutRepRangeDoesNotSuggest() {
        XCTAssertNil(hint(logs: [log("1", max: nil)], results: ["1": (10, 60)]))
    }

    func testNoTargetLoadStillSuggestsAndUsesPreviousLoad() {
        // Ohjelmassa ei aina ole painoja.
        let result = hint(
            logs: [log("1", targetLoad: nil), log("2", targetLoad: nil)],
            results: ["1": (10, 40), "2": (10, 40)]
        )
        XCTAssertEqual(result?.suggestedLoad, 42.5)
    }

    func testBodyweightGivesRepsWithoutLoad() {
        let result = hint(
            logs: [log("1", targetLoad: nil)], results: ["1": (10, nil)]
        )
        XCTAssertEqual(result, ProgressionHint(previousLoad: nil, suggestedLoad: nil, reps: 10))
        XCTAssertEqual(result?.text, "Viimeksi 10 toistoa · kokeile lisätä painoa")
    }

    func testDisappearsOnceAnySetIsLogged() {
        // Kesken treenin ei näytetä mitään: ensimmäisen sarjan kirjaus on
        // aloittanut liikkeen.
        XCTAssertNil(hint(logs: [log("1", done: true), log("2")], results: ["1": (10, 60), "2": (10, 60)]))
    }

    func testNeverShownOnCompletedExercise() {
        XCTAssertNil(hint(logs: [log("1", done: true), log("2", done: true)], results: ["1": (10, 60), "2": (10, 60)]))
    }
}
