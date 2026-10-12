import XCTest
@testable import Volu

/// Aloitusvastauksen treenirunko välimuistiin: sama muoto kuin treenin haku.
final class StartResponseDetailTests: XCTestCase {
    func testExtractsDetailThatDecodesAsWorkoutDetail() throws {
        let response = #"""
        {"ok":true,"scheduledWorkoutId":"w1","detail":{
          "workout":{"id":"w1","athleteId":"a1","title":"Ylävartalo","scheduledDate":"2026-10-13T08:00:00.000Z","status":"in_progress","updatedAt":"2026-10-13T08:00:00.000Z"},
          "session":null,"note":null,
          "setLogs":[{"id":"l1","templateExerciseId":"t1","setId":"s1","exerciseId":"e1","exerciseName":"Penkki","setLabel":"1","targetReps":8,"actualReps":8,"actualLoad":60,"done":false}],
          "previousSets":[{"exerciseId":"e1","setLabel":"1","actualReps":8,"actualLoad":60,"performedAt":"2026-10-10T08:00:00.000Z"}]
        }}
        """#
        let detail = try XCTUnwrap(WorkoutStarter.detailData(from: Data(response.utf8)))
        let decoded = try JSONDecoder().decode(WorkoutDetail.self, from: detail)
        XCTAssertEqual(decoded.setLogs.map(\.id), ["l1"])
        XCTAssertEqual(decoded.previousSets?.count, 1)
    }

    /// Vanha palvelin ei palauta runkoa: treeni haetaan tavalliseen tapaan.
    func testMissingDetailIsNil() {
        let response = #"{"ok":true,"scheduledWorkoutId":"w1"}"#
        XCTAssertNil(WorkoutStarter.detailData(from: Data(response.utf8)))
    }
}
