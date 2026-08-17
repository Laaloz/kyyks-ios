import XCTest
@testable import Volu

/// Palvelimen selitys on usein ainoa tieto siitä mikä meni pieleen: pyyntö ei
/// palaa palvelimelle, joten jos viesti pudotetaan tässä, se on lopullisesti
/// mennyt. Testit lukitsevat sen että viesti kulkee näkymälle asti.
final class APIErrorMessageTests: XCTestCase {
    func testServerMessageIsCarriedFromStatusError() {
        let error = APIError.status(400, "Ohjelma on arkistoitu eikä siitä voi käynnistää uutta treeniä.")
        XCTAssertEqual(error.serverMessage, "Ohjelma on arkistoitu eikä siitä voi käynnistää uutta treeniä.")
    }

    func testPaymentRequiredMessageIsCarried() {
        XCTAssertEqual(APIError.paymentRequired("Kiintiö täynnä").serverMessage, "Kiintiö täynnä")
    }

    /// Verkkovirheestä ei ole palvelimen viestiä, joten näkymän on käytettävä
    /// omaa tekstiään — muuten käyttäjälle näytettäisiin tyhjä rivi.
    func testTransportErrorHasNoServerMessage() {
        XCTAssertNil(APIError.transport.serverMessage)
    }

    func testStatusWithoutBodyFallsBackToCode() {
        XCTAssertNil(APIError.status(500, nil).serverMessage)
        XCTAssertEqual(APIError.status(500, nil).errorDescription, "Palvelin vastasi virheellä (500)")
    }

    /// Kun palvelin selittää, selitys voittaa koodin: "(400)" ei kerro
    /// käyttäjälle mitään.
    func testServerMessageWinsOverStatusCodeInDescription() {
        XCTAssertEqual(APIError.status(400, "Ohjelmaa ei löytynyt.").errorDescription, "Ohjelmaa ei löytynyt.")
    }
}
