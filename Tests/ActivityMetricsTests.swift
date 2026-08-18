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


/// Listarivin lukemat. Rivillä oli viisi lukua väliviivoin, eikä kokonaiskuvaa
/// hahmottanut vilkaisulla; loput siirtyivät avattuun näkymään.
final class ActivityRowPartsTests: XCTestCase {
    func testDistanceSportShowsDistanceAndDuration() {
        XCTAssertEqual(
            ActivityMetrics.rowParts(meters: 12000, minutes: 85, kcal: 811, mode: .pace),
            ["12,0 km", "1 h 25 min"]
        )
    }

    func testDurationUsesHoursEverywhere() {
        // "85 min" on luku jonka lukija joutuu jakamaan päässään.
        XCTAssertEqual(formatDuration(minutes: 85), "1 h 25 min")
        XCTAssertEqual(formatDuration(minutes: 45), "45 min")
        // Tasatunti ilman turhaa nollaa.
        XCTAssertEqual(formatDuration(minutes: 120), "2 h")
        // Sekuntipohjainen muoto on sama laskenta, ei toinen sääntö.
        XCTAssertEqual(formatDuration(seconds: 85 * 60), "1 h 25 min")
    }

    func testSwimDistanceStaysInMetres() {
        XCTAssertEqual(
            ActivityMetrics.rowParts(meters: 1500, minutes: 40, kcal: 400, mode: .swim),
            ["1500 m", "40 min"]
        )
    }

    func testWithoutDistanceShowsDurationAndKcal() {
        // Joogassa kesto on ainoa mittaus, joten sen pariksi tulee kalorit.
        XCTAssertEqual(
            ActivityMetrics.rowParts(meters: nil, minutes: 60, kcal: 180, mode: .none),
            ["1 h", "180 kcal"]
        )
    }

    func testDistanceSportWithoutMeasuredDistance() {
        // Ennen 17.8. tuoduilla juoksuilla matka puuttui: rivin on silti
        // kerrottava jotain eikä jäätävä tyhjäksi.
        XCTAssertEqual(
            ActivityMetrics.rowParts(meters: nil, minutes: 85, kcal: 811, mode: .pace),
            ["1 h 25 min", "811 kcal"]
        )
    }

    func testRowNeverShowsMoreThanTwoValues() {
        // Koko korjauksen syy: rivi pysyy kahdessa luvussa lajista riippumatta.
        for mode in [ActivityDistanceMode.none, .pace, .speed, .swim] {
            XCTAssertEqual(
                ActivityMetrics.rowParts(meters: 12000, minutes: 85, kcal: 811, mode: mode).count,
                2
            )
        }
    }
}
