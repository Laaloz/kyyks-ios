import XCTest
@testable import Volu

/// Painokäyrän pisteet. Samalle päivälle voi kertyä useita punnituksia —
/// Healthista tuotu ja käsin kirjattu, tai kaksi punnitusta samana aamuna.
/// Kaaviossa ne näkyivät pystysuorana hyppynä, joka kertoo vaa'an heitosta
/// eikä painon kehityksestä.
@MainActor
final class WeightSeriesTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return calendar
    }()

    private func point(_ id: String, _ iso: String, _ value: Double) -> WeightPoint {
        WeightPoint(id: id, date: parseAPIDate(iso)!, value: value)
    }

    func testKeepsOnlyLatestMeasurementOfEachDay() {
        let series = BodyModel.dailySeries(
            [
                point("aamu", "2026-08-17T05:00:00Z", 80.0),
                point("ilta", "2026-08-17T16:00:00Z", 79.4),
                point("eilen", "2026-08-16T06:00:00Z", 80.6),
            ],
            calendar: calendar
        )

        XCTAssertEqual(series.map(\.id), ["eilen", "ilta"])
        XCTAssertEqual(series.map(\.value), [80.6, 79.4])
    }

    func testSortsChronologically() {
        let series = BodyModel.dailySeries(
            [
                point("c", "2026-08-17T06:00:00Z", 79.0),
                point("a", "2026-08-10T06:00:00Z", 81.0),
                point("b", "2026-08-14T06:00:00Z", 80.0),
            ],
            calendar: calendar
        )
        XCTAssertEqual(series.map(\.id), ["a", "b", "c"])
    }

    func testKeepsSeparateDaysApart() {
        let series = BodyModel.dailySeries(
            [
                point("ti", "2026-08-16T06:00:00Z", 80.0),
                point("ke", "2026-08-17T06:00:00Z", 79.5),
            ],
            calendar: calendar
        )
        XCTAssertEqual(series.count, 2)
    }

    func testEmptyInputProducesEmptySeries() {
        XCTAssertTrue(BodyModel.dailySeries([], calendar: calendar).isEmpty)
    }
}
