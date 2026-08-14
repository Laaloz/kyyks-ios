import Foundation

/// Käyttöoikeustaso. Palvelin johtaa arvon roolista ja tilausrivistä
/// (lib/entitlements.ts) — laite ei päättele sitä itse, jottei sama sääntö ole
/// kahdessa paikassa erikseen ylläpidettävänä.
enum Entitlement: String, Decodable {
    /// Ilmaiskäyttö: maksulliset ominaisuudet lukossa.
    case free
    /// Oma tilaus voimassa.
    case pro
    /// Valmentajan sopimus kattaa käytön — sama pääsy kuin prolla, mutta
    /// tilausta ei osteta eikä hallita sovelluksesta.
    case coached

    /// Tuntematon arvo palvelimelta (uusi taso vanhalle sovellukselle) ei saa
    /// avata maksumuuria — `free` on turvallinen oletus, ja palvelin on joka
    /// tapauksessa oikea portti.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Entitlement(rawValue: raw) ?? .free
    }

    var unlocksPaidFeatures: Bool { self != .free }
}

/// Oman tilauksen tiedot profiilinäkymää varten. Puuttuu valmennettavalta ja
/// valmentajalta, joiden oikeus tulee roolista.
struct SubscriptionInfo: Decodable {
    let status: String
    let productId: String
    let expiresAt: String?

    var isActive: Bool { status == "active" }
}
