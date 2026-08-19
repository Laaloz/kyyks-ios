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
