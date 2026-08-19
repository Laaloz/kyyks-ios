import Foundation
import Testing
@testable import Volu

/// Muutoksen jälkeisen päivityksen uusintasäännöt.
///
/// Ilmoitus "Muutos tallentui, mutta näkymä ei päivittynyt" tuli usein tilanteessa
/// jossa mikään ei ollut rikki. Nämä testit lukitsevat sen, mitkä virheet johtavat
/// ilmoitukseen ja mitkä eivät.
@MainActor
private final class TestModel: CachedModel {
    var api: APIClient?
    let cacheKey = "test"
    let resourcePath = "/test"
    let loadFailureMessage = "Haku epäonnistui."
    var hasContent = true
    var isLoading = false
    var errorMessage: String?
    func apply(_ data: Data) {}
}

@MainActor
struct RefreshRetryTests {
    // Näkymän sulkeutuminen peruu sen taskin. Käyttäjä on jo poissa siitä
    // näkymästä jota ilmoitus koskisi, joten ilmoitus on pelkkää häirintää.
    @Test func cancellationIsNotAFailure() {
        #expect(TestModel.isCancellation(URLError(.cancelled)))
        #expect(TestModel.isCancellation(CancellationError()))
        #expect(TestModel.isWorthRetrying(URLError(.cancelled)) == false)
    }

    // iOS uusiokäyttää yhteyttä jonka palvelin on jo sulkenut. Se osuu juuri
    // tähän kohtaan, koska muutos ja haku lähtevät peräkkäin — ja korjaantuu
    // yhdellä uudella yrityksellä.
    @Test func lostConnectionIsRetried() {
        #expect(TestModel.isWorthRetrying(URLError(.networkConnectionLost)))
        #expect(TestModel.isCancellation(URLError(.networkConnectionLost)) == false)
    }

    @Test func timeoutIsRetried() {
        #expect(TestModel.isWorthRetrying(URLError(.timedOut)))
    }

    // 4xx vastaa samoin sekunnin päästä: odotus vain viivyttäisi ilmoitusta.
    @Test func clientErrorsAreNotRetried() {
        #expect(TestModel.isWorthRetrying(APIError.status(401, nil)) == false)
        #expect(TestModel.isWorthRetrying(APIError.status(404, "Ei löytynyt")) == false)
        #expect(TestModel.isWorthRetrying(APIError.paymentRequired(nil)) == false)
    }

    // 5xx on palvelimen hetkellinen tila.
    @Test func serverErrorsAreRetried() {
        #expect(TestModel.isWorthRetrying(APIError.status(503, nil)))
        #expect(TestModel.isWorthRetrying(APIError.transport))
    }

    // Tuntematon virhe yritetään uudelleen: valkoinen lista jättäisi
    // ulkopuolelleen juuri sen koodin jota ei osattu odottaa.
    @Test func unknownErrorsAreRetried() {
        struct Odd: Error {}
        #expect(TestModel.isWorthRetrying(Odd()))
    }
}
