import XCTest
@testable import Volu

/// Vauhdin laskenta ja esitys. Säännöt ovat samat kuin webin
/// `lib/extra-activities.ts`:ssä, joten testit kirjaavat myös sen sopimuksen.
final class ActivityMetricsTests: XCTestCase {
    func testRunningPaceIsMinutesPerKilometre() {
        // 10 km / 50 min = 5.00 /km
        XCTAssertEqual(
            ActivityMetrics.paceText(meters: 10000, minutes: 50, mode: .pace),
            "5.00 /km"
        )
    }

    func testPaceSecondsArePaddedToTwoDigits() {
        // 5 km / 26 min = 5.12 /km — ei "5.2 /km".
        XCTAssertEqual(
            ActivityMetrics.paceText(meters: 5000, minutes: 26, mode: .pace),
            "5.12 /km"
        )
    }

    func testCyclingUsesSpeedNotPace() {
        // 30 km / 60 min = 30,0 km/h
        XCTAssertEqual(
            ActivityMetrics.paceText(meters: 30000, minutes: 60, mode: .speed),
            "30,0 km/h"
        )
    }

    func testSwimmingPaceIsPerHundredMetres() {
        // 1500 m / 30 min = 2.00 /100 m
        XCTAssertEqual(
            ActivityMetrics.paceText(meters: 1500, minutes: 30, mode: .swim),
            "2.00 /100 m"
        )
    }

    func testSwimmingDistanceStaysInMetres() {
        XCTAssertEqual(ActivityMetrics.distanceText(meters: 1500, mode: .swim), "1500 m")
    }

    func testDistanceUsesFinnishDecimalComma() {
        XCTAssertEqual(ActivityMetrics.distanceText(meters: 8400, mode: .pace), "8,4 km")
    }

    func testLongDistanceDropsTheDecimal() {
        // Sadan kilometrin jälkeen desimaali on kohinaa.
        XCTAssertEqual(ActivityMetrics.distanceText(meters: 128400, mode: .speed), "128 km")
    }

    /// Nolla ja puuttuva arvo tarkoittavat samaa: ei mitattu. Kumpikaan ei saa
    /// tuottaa "0,0 km" -riviä eikä nollalla jakoa.
    func testMissingOrZeroValuesProduceNothing() {
        XCTAssertNil(ActivityMetrics.distanceText(meters: nil, mode: .pace))
        XCTAssertNil(ActivityMetrics.distanceText(meters: 0, mode: .pace))
        XCTAssertNil(ActivityMetrics.paceText(meters: 5000, minutes: 0, mode: .pace))
        XCTAssertNil(ActivityMetrics.paceText(meters: 0, minutes: 30, mode: .pace))
        XCTAssertNil(ActivityMetrics.paceText(meters: nil, minutes: 30, mode: .pace))
    }

    /// Laji ilman matkaa ei näytä matkaa vaikka arvo olisi kannassa — esimerkiksi
    /// jos suorituksen laji on vaihdettu juoksusta joogaksi.
    func testActivityWithoutDistanceShowsNothing() {
        XCTAssertNil(ActivityMetrics.distanceText(meters: 5000, mode: .none))
        XCTAssertNil(ActivityMetrics.paceText(meters: 5000, minutes: 30, mode: .none))
    }

    func testDetailPartsKeepOrderAndSkipMissing() {
        XCTAssertEqual(
            ActivityMetrics.detailParts(meters: 10000, minutes: 50, heartRate: 148, mode: .pace),
            ["10,0 km", "5.00 /km", "148 bpm"]
        )
        XCTAssertEqual(
            ActivityMetrics.detailParts(meters: nil, minutes: 45, heartRate: nil, mode: .pace),
            []
        )
    }

    /// Lajin ja esitystavan sidos: pyöräily ei saa näyttää min/km eikä juoksu km/h.
    func testDistanceModeMatchesActivityType() {
        XCTAssertEqual(ExtraActivityType.distanceMode(for: "run"), .pace)
        XCTAssertEqual(ExtraActivityType.distanceMode(for: "cycle"), .speed)
        XCTAssertEqual(ExtraActivityType.distanceMode(for: "swim"), .swim)
        XCTAssertEqual(ExtraActivityType.distanceMode(for: "yoga"), .none)
        // Tuntematon avain ei saa kaataa esitystä.
        XCTAssertEqual(ExtraActivityType.distanceMode(for: "ei_ole"), .none)
    }
}
