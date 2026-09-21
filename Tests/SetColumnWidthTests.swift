import SwiftUI
import XCTest
@testable import Volu

/// Sarjarivin sarakeleveydet suhteessa tekstikokoon.
///
/// Kiinteä leveys katkaisi arvon suurilla tekstikoilla niin, että "67,5" näkyi
/// muodossa "6…" — kenttä ei kutista tekstiä vaan rajaa sen pois. Leveys
/// kasvaa siksi kertoimen mukana, mutta ei rajatta: rivi on jaettava
/// sarjanumeron ja kuittausnapin kanssa, joten katto on 1,5×.
final class SetColumnWidthTests: XCTestCase {
    func testDefaultTextSizeKeepsOriginalWidths() {
        XCTAssertEqual(SetColumnWidths.width(62, unit: 100), 62)
        XCTAssertEqual(SetColumnWidths.width(72, unit: 100), 72)
    }

    func testWidthGrowsWithTextSize() {
        XCTAssertEqual(SetColumnWidths.width(62, unit: 130), 81)
        XCTAssertEqual(SetColumnWidths.width(72, unit: 130), 94)
    }

    /// Saavutettavuuskoot vievät kertoimen kolmen yli; leveys pysähtyy 1,5:een.
    func testGrowthStopsAtOneAndAHalf() {
        XCTAssertEqual(SetColumnWidths.width(62, unit: 310), 93)
        XCTAssertEqual(SetColumnWidths.width(72, unit: 310), 108)
    }

    /// Pieni tekstikoko ei kavenna saraketta: kosketuskohde ei saa kutistua.
    func testSmallTextSizeDoesNotShrinkColumns() {
        XCTAssertEqual(SetColumnWidths.width(62, unit: 80), 62)
        XCTAssertEqual(SetColumnWidths.width(72, unit: 80), 72)
    }
}
