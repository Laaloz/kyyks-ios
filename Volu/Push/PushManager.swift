import Foundation
import OSLog
import UIKit
import UserNotifications

/// Push-ilmoitusten lupa ja laitetunnisteen välitys palvelimelle.
///
/// Työnjako: iOS antaa tunnisteen, palvelin päättää milloin ja mitä
/// lähetetään. Tunniste lähetetään joka käynnistyksessä, koska Apple voi
/// vaihtaa sen ilman varoitusta (uudelleenasennus, palautus varmuuskopiosta,
/// iOS-päivitys) eikä laite saa tietoa siitä että vanha tunniste on kuollut.
@Observable
@MainActor
final class PushManager: NSObject {
    enum Authorization {
        case notDetermined
        case authorized
        case denied
    }

    private(set) var authorization: Authorization = .notDetermined

    private var api: APIClient?
    /// Viimeksi palvelimelle lähetetty tunniste. Estää saman tunnisteen
    /// lähettämisen uudelleen samassa ajossa; käynnistyksessä se lähetetään
    /// aina, koska palvelimen tila voi olla eri.
    private var sentToken: String?
    private static let log = Logger(subsystem: "fi.volu.app", category: "push")

    /// Sandbox vai tuotanto: väärä APNs-osoite palauttaa BadDeviceTokenin,
    /// jonka palvelin tulkitsee kuolleeksi tunnisteeksi ja poistaa rivin — eli
    /// väärä arvaus ei näy virheenä vaan ilmoitusten hiljaisena puuttumisena.
    ///
    /// Ainoa lähde joka tämän oikeasti tietää on paketin provisiointiprofiiliin
    /// leimattu `aps-environment`. Kuitista päättely olisi väärin: TestFlightin
    /// `sandboxReceipt` koskee StoreKitiä, ja TestFlight-asennukset käyttävät
    /// **tuotanto**-APNs:ää siinä missä App Store -asennuksetkin.
    private static let environment: String = {
        // Profiilia ei ole simulaattorissa, jossa APNs ei toimi muutenkaan.
        // Muualla lukemisen epäonnistuminen on tuntematon tilanne, ja
        // tuotanto on turvallisempi arvaus: se on oikea kaikille jaelluille
        // käännöksille, ja väärä vain kehittäjän omalla laitteella.
        guard let value = apsEnvironmentFromProfile() else {
            #if DEBUG
            return "sandbox"
            #else
            return "production"
            #endif
        }
        return value == "development" ? "sandbox" : "production"
    }()

    /// Lukee `aps-environment`-oikeuden paketin provisiointiprofiilista.
    ///
    /// Profiili on CMS-allekirjoitettu, eli plist on binäärikuoren sisällä.
    /// Allekirjoitusta ei tarvitse purkaa: iOS on jo validoinut profiilin
    /// asennuksessa, joten arvon voi etsiä tekstinä. Latin-1 siksi, että
    /// kuoressa on tavuja jotka eivät ole kelvollista UTF-8:aa — se ei muuta
    /// ASCII-osuutta, joka on ainoa mitä tästä luetaan.
    private static func apsEnvironmentFromProfile() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let key = text.range(of: "<key>aps-environment</key>"),
              let open = text.range(of: "<string>", range: key.upperBound..<text.endIndex),
              let close = text.range(of: "</string>", range: open.upperBound..<text.endIndex)
        else {
            return nil
        }
        return String(text[open.upperBound..<close.lowerBound])
    }

    func configure(auth: AuthManager) {
        if api == nil { api = APIClient(auth: auth) }
    }

    /// Kysyy luvan vain jos sitä ei ole vielä kysytty. iOS ei näytä kyselyä
    /// toista kertaa, joten kieltäneelle tämä on hiljainen no-op.
    func requestAuthorizationIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            authorization = granted ? .authorized : .denied
        case .denied:
            authorization = .denied
        default:
            authorization = .authorized
        }

        // Rekisteröinti vain kun lupa on: ilman sitä APNs ei anna tunnistetta.
        if authorization == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Kutsutaan AppDelegatesta kun APNs on antanut tunnisteen.
    func register(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard token != sentToken else { return }

        Task { [weak self] in
            guard let self, let api = self.api else { return }
            struct Body: Encodable {
                let token: String
                let environment: String
            }
            do {
                _ = try await api.post("/api/mobile/device-token", body: Body(
                    token: token,
                    environment: Self.environment
                ))
                self.sentToken = token
            } catch {
                // Epäonnistunut rekisteröinti ei ole käyttäjän ongelma eikä sitä
                // kerrota: seuraava käynnistys yrittää uudelleen.
                Self.log.warning("laitetunnisteen välitys epäonnistui: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Uloskirjautuminen: laite irrotetaan tilistä, jottei seuraava käyttäjä
    /// samalla laitteella saa edellisen muistutuksia.
    func unregister() async {
        guard let api, let token = sentToken else { return }
        struct Body: Encodable { let token: String }
        _ = try? await api.delete("/api/mobile/device-token", body: Body(token: token))
        sentToken = nil
    }
}
