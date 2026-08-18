import XCTest
@testable import Volu

/// Aloitusnäkymän arvio ja esikatselu. Kestoarvion kaava on sama kuin webin
/// ohjelmaeditorissa (`estimatedMinutes`), joten testi kirjaa myös sen
/// sopimuksen: kaksi eri arviota samasta treenistä olisi ristiriita.
final class ProgramWorkoutSummaryTests: XCTestCase {
    private func exercise(name: String, sets: Int) -> ProgramTemplate.TemplateExercise {
        ProgramTemplate.TemplateExercise(
            exerciseId: "e-\(name)",
            exerciseName: name,
            setCount: sets,
            targetRepsMin: 8,
            targetRepsMax: 12,
            restSeconds: 90
        )
    }

    private func summary(_ exercises: [ProgramTemplate.TemplateExercise]?) -> ProgramWorkoutSummary {
        ProgramWorkoutSummary(
            id: "w1",
            name: "Yläkroppa",
            splitType: "custom",
            exerciseCount: exercises?.count ?? 0,
            exercises: exercises
        )
    }

    func testEstimateIsSetsTimesFourPlusWarmup() {
        // 5 liikettä × 3 sarjaa = 15 sarjaa → 15 × 4 + 8 = 68 min.
        let workout = summary((1...5).map { exercise(name: "Liike \($0)", sets: 3) })
        XCTAssertEqual(workout.estimatedMinutes, 68)
    }

    func testShortWorkoutGetsMinimumEstimate() {
        // 2 sarjaa → 16 min, mutta alaraja on 20 min.
        let workout = summary([exercise(name: "Penkki", sets: 2)])
        XCTAssertEqual(workout.estimatedMinutes, 20)
    }

    func testEstimateIsShownInHoursAndMinutes() {
        // 20 sarjaa → 88 min, joka luetaan tunteina.
        let workout = summary((1...5).map { exercise(name: "Liike \($0)", sets: 4) })
        XCTAssertEqual(workout.startSummary, "5 liikettä · noin 1 h 28 min")
    }

    func testMissingExercisesLeavesEstimateOut() {
        // Liikkeitä ei haettu: arvaus liikemäärästä olisi eri luku kuin
        // editorissa näkyvä, joten arviota ei näytetä lainkaan.
        let workout = ProgramWorkoutSummary(
            id: "w1",
            name: "Yläkroppa",
            splitType: "custom",
            exerciseCount: 6,
            exercises: nil
        )
        XCTAssertNil(workout.estimatedMinutes)
        XCTAssertEqual(workout.startSummary, "6 liikettä")
        XCTAssertNil(workout.previewText)
    }

    func testPreviewListsFirstThreeAndCountsRest() {
        let workout = summary([
            exercise(name: "Penkkipunnerrus", sets: 3),
            exercise(name: "Kulmasoutu", sets: 3),
            exercise(name: "Pystypunnerrus", sets: 3),
            exercise(name: "Hauiskääntö", sets: 3),
            exercise(name: "Ojentajapunnerrus", sets: 3),
        ])
        XCTAssertEqual(workout.previewText, "Penkkipunnerrus · Kulmasoutu · Pystypunnerrus +2")
    }

    func testPreviewWithoutOverflowHasNoCounter() {
        let workout = summary([
            exercise(name: "Penkkipunnerrus", sets: 3),
            exercise(name: "Kulmasoutu", sets: 3),
        ])
        XCTAssertEqual(workout.previewText, "Penkkipunnerrus · Kulmasoutu")
    }
}
