import SwiftUI

/// Sovelluksen ulkoasu: järjestelmän mukaan, vaalea tai tumma.
///
/// iOS:ssä on jo järjestelmätason valinta, joten oletus seuraa sitä — mutta
/// salilla halutaan usein tumma vaikka puhelin olisi muuten vaalealla, ja
/// erillinen valinta on ainoa tapa saada se ilman että koko puhelimen ulkoasu
/// vaihtuu.
///
/// Tallennetaan `UserDefaults`iin, koska asetus koskee laitetta eikä tiliä:
/// sama käyttäjä voi haluta eri ulkoasun puhelimeen ja tablettiin.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// Avain on jaettu asetusnäkymän ja sovelluksen juuren kesken; kahtena
    /// merkkijonona kirjoitusvirhe jäisi huomaamatta.
    static let storageKey = "appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Järjestelmä"
        case .light: "Vaalea"
        case .dark: "Tumma"
        }
    }

    /// `nil` tarkoittaa "älä pakota" eli järjestelmän valinta.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
