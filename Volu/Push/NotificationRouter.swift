import Foundation
import Observation

/// Mihin ilmoituksen napautus vie. Palvelin kertoo kohteen hyötykuorman
/// `target`-kentässä.
///
/// Oma olionsa, koska kohteen asettaa UIKitin delegaatti ja lukee SwiftUI-
/// näkymä — kumpikaan ei voi omistaa toista. Kohde myös *kulutetaan*: ilman
/// sitä sama ilmoitus avaisi lomakkeen uudelleen joka kerta kun välilehti
/// tulee näkyviin.
@Observable
@MainActor
final class NotificationRouter {
    /// Jaettu ilmentymä eikä delegaatille annettu viite: kylmässä
    /// käynnistyksessä napautus välitetään ennen kuin näkymät ovat pystyssä,
    /// joten viitteen asettamiseen perustuva ratkaisu hukkaisi juuri sen
    /// napautuksen, joka sovelluksen avasi.
    static let shared = NotificationRouter()

    private(set) var target: String?

    func handle(target: String?) {
        guard let target, !target.isEmpty else { return }
        self.target = target
    }

    /// Ottaa kohteen käyttöön jos se on tämä. Palauttaa tiedon siitä avattiinko.
    func consume(_ value: String) -> Bool {
        guard target == value else { return false }
        target = nil
        return true
    }
}
