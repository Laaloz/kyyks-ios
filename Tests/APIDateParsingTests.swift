import XCTest
@testable import Volu

/// API palauttaa aikaleimoja kolmessa muodossa, ja kaikkien on jäsennyttävä.
///
/// Keho-näkymä käytti muotoilijaa joka osaa vain murto-osasekunnilliset leimat,
/// ja epäonnistuneelle jäsennykselle annettiin oletukseksi `.now`. Healthista
/// tuoduilla mittauksilla ei ole desimaaleja, joten ne kaikki näyttivät
/// tämän päivän mittauksilta: historia oli väärässä järjestyksessä ja samalle
/// päivälle kertyi rivejä, joita kannassa ei ollut.
final class APIDateParsingTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ date: Date?) -> String? {
        guard let date else { return nil }
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year!)-\(parts.month!)-\(parts.day!)"
    }

    func testParsesTimestampWithFractionalSeconds() {
        XCTAssertEqual(day(parseAPIDate("2026-08-07T13:35:35.094+00:00")), "2026-8-7")
    }

    /// Healthista tuodut mittaukset — tämä muoto rikkoi historian.
    func testParsesTimestampWithoutFractionalSeconds() {
        XCTAssertEqual(day(parseAPIDate("2026-08-16T08:14:17+00:00")), "2026-8-16")
        XCTAssertEqual(day(parseAPIDate("2026-08-16T08:14:17Z")), "2026-8-16")
    }

    func testParsesDateOnly() {
        XCTAssertEqual(day(parseAPIDate("2026-08-14")), "2026-8-14")
    }

    func testReturnsNilForGarbage() {
        XCTAssertNil(parseAPIDate("ei ole päivämäärä"))
    }

    /// Kaksi eri muodossa tullutta leimaa on saatava oikeaan järjestykseen.
    /// Juuri tämä meni pieleen: desimaaliton leima ei jäsentynyt, sai
    /// oletukseksi nykyhetken ja nousi listan kärkeen.
    func testMixedFormatsSortChronologically() throws {
        let older = try XCTUnwrap(parseAPIDate("2026-08-07T13:35:35.094+00:00"))
        let newer = try XCTUnwrap(parseAPIDate("2026-08-16T08:14:17+00:00"))
        XCTAssertLessThan(older, newer)
    }
}
