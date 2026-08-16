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
    /// joten palvelimen on tiedettävä kummasta rakennuksesta tunniste tuli.
    /// Debug-käännös ja TestFlight käyttävät sandboxia.
    private static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "sandbox" : "production"
        #endif
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
