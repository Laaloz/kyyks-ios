import XCTest
@testable import Volu

/// Energia-arvio treenin viennissä: kaava ja se, milloin arviota ei tehdä.
final class HealthExportTests: XCTestCase {
    func testUsesMetFormula() {
        // 5 MET × 3,5 × 80 kg / 200 = 7 kcal/min → 60 min = 420 kcal.
        let energy = HealthManager.estimatedActiveEnergy(minutes: 60, bodyWeightKilograms: 80)
        XCTAssertEqual(try XCTUnwrap(energy), 420, accuracy: 0.001)
    }

    func testScalesWithDuration() {
        let half = try? XCTUnwrap(HealthManager.estimatedActiveEnergy(minutes: 30, bodyWeightKilograms: 80))
        XCTAssertEqual(try XCTUnwrap(half), 210, accuracy: 0.001)
    }

    /// Ilman painoa kaava olisi arvaus arvauksesta, jolloin treeni menee
    /// Healthiin ilman energiaa.
    func testNilWithoutWeight() {
        XCTAssertNil(HealthManager.estimatedActiveEnergy(minutes: 45, bodyWeightKilograms: nil))
        XCTAssertNil(HealthManager.estimatedActiveEnergy(minutes: 45, bodyWeightKilograms: 0))
    }

    func testNilForEmptyWorkout() {
        XCTAssertNil(HealthManager.estimatedActiveEnergy(minutes: 0, bodyWeightKilograms: 80))
    }
}
