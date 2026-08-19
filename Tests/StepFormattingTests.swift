import XCTest
@testable import Volu

final class StepFormattingTests: XCTestCase {
    func testGroupsThousandsWithNonBreakingSpace() {
        XCTAssertEqual(formatSteps(8432), "8\u{00A0}432")
        XCTAssertEqual(formatSteps(12345), "12\u{00A0}345")
        XCTAssertEqual(formatSteps(1000), "1\u{00A0}000")
    }

    func testLeavesShortNumbersAlone() {
        XCTAssertEqual(formatSteps(0), "0")
        XCTAssertEqual(formatSteps(999), "999")
    }
}

/// HealthManagerin muistilista: tuodun suorituksen tunniste ei saa kasvaa
/// rajatta, ja katon ylittyessä säilyy tuorein pää.
final class ImportedWorkoutIdsTests: XCTestCase {
    func testKeepsAllUnderLimit() {
        let ids: Set<String> = ["a", "b", "c"]
        XCTAssertEqual(HealthManager.trimmedIds(ids, keeping: ["a", "b", "c"], limit: 5), ids)
    }

    func testTrimsToMostRecentWhenOverLimit() {
        let ids: Set<String> = ["vanha1", "vanha2", "uusi1", "uusi2"]
        let trimmed = HealthManager.trimmedIds(ids, keeping: ["uusi1", "uusi2"], limit: 2)
        XCTAssertEqual(trimmed, ["uusi1", "uusi2"])
    }
}
