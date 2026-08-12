import XCTest
@testable import Kyyks

/// WorkoutModel.blocks: liikkeiden ryhmittely korteiksi ja supersetin
/// yhdistäminen yhdeksi lohkoksi.
@MainActor
final class WorkoutBlocksTests: XCTestCase {
    private func log(
        id: String,
        exercise: String,
        name: String,
        set label: String,
        superset: String? = nil,
        done: Bool = false
    ) -> WorkoutSetLog {
        WorkoutSetLog(
            id: id,
            templateExerciseId: exercise,
            setId: "set-\(id)",
            exerciseId: "ex",
            exerciseName: name,
            supersetGroup: superset,
            setLabel: label,
            targetReps: 10,
            targetRepsMin: nil,
            targetRepsMax: nil,
            targetLoad: 20,
            targetRestSeconds: 90,
            actualReps: nil,
            actualLoad: nil,
            done: done
        )
    }

    private func model(with logs: [WorkoutSetLog]) -> WorkoutModel {
        let model = WorkoutModel()
        model.setLogsForTesting(logs)
        return model
    }

    func testSupersetMergesIntoSingleBlock() {
        let model = model(with: [
            log(id: "1", exercise: "e1", name: "Ojentajapunnerrus", set: "1", superset: "A"),
            log(id: "2", exercise: "e2", name: "Hauiskääntö", set: "1", superset: "A"),
            log(id: "3", exercise: "e1", name: "Ojentajapunnerrus", set: "2", superset: "A"),
            log(id: "4", exercise: "e3", name: "Penkkipunnerrus", set: "1"),
        ])

        let blocks = model.blocks
        XCTAssertEqual(blocks.count, 2)

        let superset = blocks[0]
        XCTAssertTrue(superset.isSuperset)
        XCTAssertEqual(superset.exercises.map(\.name), ["Ojentajapunnerrus", "Hauiskääntö"])
        XCTAssertEqual(superset.title, "Ojentajapunnerrus + Hauiskääntö")
        XCTAssertEqual(superset.logs.count, 3)

        XCTAssertFalse(blocks[1].isSuperset)
        XCTAssertEqual(blocks[1].title, "Penkkipunnerrus")
    }

    func testSingleExerciseInSupersetGroupIsNotLabeledSuperset() {
        let model = model(with: [
            log(id: "1", exercise: "e1", name: "Kyykky", set: "1", superset: "B"),
            log(id: "2", exercise: "e1", name: "Kyykky", set: "2", superset: "B"),
        ])

        let blocks = model.blocks
        XCTAssertEqual(blocks.count, 1)
        XCTAssertFalse(blocks[0].isSuperset)
    }

    func testSetsSortNumericallyByLabel() {
        let model = model(with: [
            log(id: "1", exercise: "e1", name: "Kyykky", set: "3"),
            log(id: "2", exercise: "e1", name: "Kyykky", set: "1"),
            log(id: "3", exercise: "e1", name: "Kyykky", set: "10"),
            log(id: "4", exercise: "e1", name: "Kyykky", set: "2"),
        ])

        XCTAssertEqual(model.blocks[0].exercises[0].logs.map(\.setLabel), ["1", "2", "3", "10"])
    }

    func testBlockCompletionCounts() {
        let model = model(with: [
            log(id: "1", exercise: "e1", name: "Kyykky", set: "1", done: true),
            log(id: "2", exercise: "e1", name: "Kyykky", set: "2"),
        ])

        let block = model.blocks[0]
        XCTAssertEqual(block.doneCount, 1)
        XCTAssertFalse(block.isComplete)
    }
}
