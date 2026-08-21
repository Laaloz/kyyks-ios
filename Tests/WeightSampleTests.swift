import XCTest
@testable import Volu

/// Painon tuonti Healthista: historiaan viedään päivän viimeinen punnitus.
/// Älyvaaka ja käyttäjä voivat kirjata saman päivän monta kertaa, eikä
/// jokainen astuminen vaa'alle kerro kehityksestä mitään.
@MainActor
final class WeightSampleTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "Europe/Helsinki")
        return formatter.date(from: iso)!
    }

    private func sample(_ id: String, _ iso: String, _ kg: Double) -> HealthManager.WeightSample {
        HealthManager.WeightSample(id: id, date: date(iso), kilograms: kg)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return calendar
    }

    func testKeepsOnlyLastWeighingOfEachDay() {
        let samples = [
            sample("a", "2026-08-12T06:30:00+03:00", 80.4),
            sample("b", "2026-08-12T19:10:00+03:00", 81.2),
            sample("c", "2026-08-13T06:20:00+03:00", 80.1),
        ]

        let result = HealthManager.latestPerDay(samples, calendar: calendar)

        XCTAssertEqual(result.map(\.id), ["b", "c"])
    }

    func testResultIsOrderedOldestFirstRegardlessOfInputOrder() {
        let samples = [
            sample("uusi", "2026-08-13T06:20:00+03:00", 80.1),
            sample("vanha", "2026-08-11T06:20:00+03:00", 80.9),
        ]

        let result = HealthManager.latestPerDay(samples, calendar: calendar)

        XCTAssertEqual(result.map(\.id), ["vanha", "uusi"])
    }

    /// Vuorokausiraja on käyttäjän aikavyöhykkeessä: keskiyön jälkeinen
    /// punnitus kuuluu uudelle päivälle, ei edelliselle UTC-päivälle.
    func testDayBoundaryFollowsLocalTimeZone() {
        let samples = [
            sample("ilta", "2026-08-12T23:50:00+03:00", 81.0),
            sample("yö", "2026-08-13T00:30:00+03:00", 80.8),
        ]

        let result = HealthManager.latestPerDay(samples, calendar: calendar)

        XCTAssertEqual(result.count, 2)
    }

    func testEmptyInputProducesNothingToImport() {
        XCTAssertTrue(HealthManager.latestPerDay([], calendar: calendar).isEmpty)
    }
}

/// Mittojen näyttömuotoilu. Vyötärö katkaistiin aiemmin `Int()`-muunnoksella,
/// jolloin kirjattu 84,5 cm luki historiarivillä 84 cm.
final class FormatDecimalTests: XCTestCase {
    func testKeepsHalfCentimetre() {
        XCTAssertEqual(formatDecimal(84.5), "84,5")
        XCTAssertEqual(formatDecimal(81.5), "81,5")
    }

    func testDropsTrailingZero() {
        XCTAssertEqual(formatDecimal(84.0), "84")
        XCTAssertEqual(formatDecimal(71.0), "71")
    }

    func testRoundsBeforeIntegerCheck() {
        // Healthista tuotu paino on liukuluku: 69,99999 on "70", ei "70,0".
        XCTAssertEqual(formatDecimal(69.99999), "70")
        XCTAssertEqual(formatDecimal(70.04), "70")
        XCTAssertEqual(formatDecimal(70.06), "70,1")
    }
}
