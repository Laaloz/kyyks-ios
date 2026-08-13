import XCTest
@testable import Kyyks

/// Yöunen keskiarvo: yöt tunnistetaan heräämispäivästä, ja päällekkäiset
/// jaksot yhdistetään — kello ja unisovellus kirjaavat usein saman unen
/// molemmat, jolloin summaaminen tuplaisi tunnit.
@MainActor
final class SleepAverageTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "Europe/Helsinki")
        return formatter.date(from: iso)!
    }

    private func interval(_ start: String, _ end: String) -> HealthManager.SleepInterval {
        HealthManager.SleepInterval(start: date(start), end: date(end))
    }

    func testMergesOverlappingSourcesInsteadOfSumming() {
        // Sama yö kahdesta lähteestä: 23–07 ja 23.30–06.30 = 8 h, ei 15 h.
        let total = HealthManager.mergedDuration(of: [
            interval("2026-08-10T23:00:00+03:00", "2026-08-11T07:00:00+03:00"),
            interval("2026-08-10T23:30:00+03:00", "2026-08-11T06:30:00+03:00"),
        ])

        XCTAssertEqual(total, 8 * 3600, accuracy: 1)
    }

    func testCountsSeparateStretchesOfSameNight() {
        // Herääminen kesken yön: 23–02 ja 03–07 = 7 h.
        let total = HealthManager.mergedDuration(of: [
            interval("2026-08-10T23:00:00+03:00", "2026-08-11T02:00:00+03:00"),
            interval("2026-08-11T03:00:00+03:00", "2026-08-11T07:00:00+03:00"),
        ])

        XCTAssertEqual(total, 7 * 3600, accuracy: 1)
    }

    func testAveragesPerNightNotPerSample() {
        // Yö 1: 8 h yhtenä jaksona. Yö 2: 6 h kahtena jaksona.
        // Keskiarvo on 7 h — ei kolmen näytteen keskiarvo.
        let average = HealthManager.averageNightlySleep(
            of: [
                interval("2026-08-10T23:00:00+03:00", "2026-08-11T07:00:00+03:00"),
                interval("2026-08-11T23:00:00+03:00", "2026-08-12T02:00:00+03:00"),
                interval("2026-08-12T03:00:00+03:00", "2026-08-12T06:00:00+03:00"),
            ],
            calendar: helsinkiCalendar
        )

        XCTAssertEqual(average ?? 0, 7 * 3600, accuracy: 1)
    }

    func testReturnsNilWithoutData() {
        XCTAssertNil(HealthManager.averageNightlySleep(of: []))
    }

    private var helsinkiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        return calendar
    }
}
