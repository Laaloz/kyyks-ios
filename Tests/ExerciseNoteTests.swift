import XCTest
@testable import Volu

/// Liikkeen muistiinpano: vastauksen purku ja polun koodaus.
final class ExerciseNoteTests: XCTestCase {
    func testDetailDecodesExerciseNotes() throws {
        let json = #"""
        {"workout":{"id":"w1","athleteId":"a1","title":"Vetävät","scheduledDate":"2026-10-13T08:00:00.000Z","status":"in_progress","updatedAt":"2026-10-13T08:00:00.000Z"},
         "session":null,"setLogs":[],
         "exerciseNotes":[{"exerciseId":"pull-up","body":"keltainen nauha","updatedAt":"2026-10-12T10:00:00Z"}]}
        """#
        let detail = try JSONDecoder().decode(WorkoutDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.exerciseNotes?.first?.exerciseId, "pull-up")
        XCTAssertEqual(detail.exerciseNotes?.first?.body, "keltainen nauha")
    }

    /// Vanha välimuistivastaus ei sisällä kenttää eikä saa kaataa purkua.
    func testDetailWithoutExerciseNotesStillDecodes() throws {
        let json = #"""
        {"workout":{"id":"w1","athleteId":"a1","title":"T","scheduledDate":"2026-10-13T08:00:00.000Z","status":"in_progress","updatedAt":"2026-10-13T08:00:00.000Z"},
         "session":null,"setLogs":[],"note":{"body":"vanha","updatedAt":"x"}}
        """#
        let detail = try JSONDecoder().decode(WorkoutDetail.self, from: Data(json.utf8))
        XCTAssertNil(detail.exerciseNotes)
    }

    func testTemplateExerciseDecodesNote() throws {
        let json = #"{"exerciseId":"pull-up","exerciseName":"Leuat","setCount":3,"note":"keltainen nauha"}"#
        let exercise = try JSONDecoder().decode(ProgramTemplate.TemplateExercise.self, from: Data(json.utf8))
        XCTAssertEqual(exercise.note, "keltainen nauha")
    }

    func testPathComponentEscapesSlashAndSpace() {
        XCTAssertEqual(WorkoutModel.pathComponent("a/b c"), "a%2Fb%20c")
        XCTAssertEqual(WorkoutModel.pathComponent("pull-up_2"), "pull-up_2")
    }
}
