import XCTest
@testable import Volu

/// Ravintopäivän vaihto. Päivä vaihdetaan synkronisesti napin painalluksessa
/// ja vasta lataus jää taustalle — muuten siirtymä näytti satunnaisesti
/// jääneen väliin, kun main actor oli varattu edellisestä hausta.
@MainActor
final class NutritionDaySelectionTests: XCTestCase {
    func testMovingBackChangesDayImmediately() {
        let model = NutritionModel()
        let before = model.selectedDate

        XCTAssertTrue(model.selectDay(offsetBy: -1))

        let calendar = Calendar.current
        XCTAssertEqual(
            calendar.startOfDay(for: model.selectedDate),
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: before)!)
        )
        XCTAssertFalse(model.isToday)
        // Ilman spinneriä tyhjä päivä näyttäisi siltä kuin siirtymä ei olisi
        // tapahtunut lainkaan.
        XCTAssertTrue(model.isLoading)
    }

    func testCannotMovePastToday() {
        let model = NutritionModel()

        XCTAssertFalse(model.selectDay(offsetBy: 1))
        XCTAssertTrue(model.isToday)
        XCTAssertFalse(model.isLoading)
    }

    /// Eiliseen ja takaisin päätyy kuluvaan päivään myös silloin kun kello on
    /// vaihtumassa: vertailu tehdään päivinä, ei hetkinä.
    func testReturningForwardLandsOnToday() {
        let model = NutritionModel()

        XCTAssertTrue(model.selectDay(offsetBy: -1))
        XCTAssertTrue(model.selectDay(offsetBy: 1))
        XCTAssertTrue(model.isToday)
    }
}
