import Foundation
import OSLog

/// Maksupolun seurantatapahtumat.
///
/// Vastaa yhteen kysymykseen johon kannasta ei muuten saa vastausta: **missä kohtaa maksupolkua
/// käyttäjä putoaa.** Tilausrivi kertoo vain onnistuneet ostot ja palvelin näkee vain toteutuneet
/// AI-arviot; väliin jää se osa jossa 0 tilaajaa syntyy — löytyikö ominaisuus, osuttiinko muuriin,
/// nähtiinkö hinta, painettiinko Tilaa.
///
/// Lähetys on tarkoituksella vaikutukseton: virhe niellään, mitään ei odoteta eikä käyttäjälle
/// näytetä. Seuranta ei saa koskaan estää eikä hidastaa sitä toimintoa jota se mittaa.
enum FunnelEvent: String {
    /// AI-arviointinäkymä avattiin. Erottaa "ei löytänyt" tilanteesta "löysi muttei käyttänyt".
    case aiSheetOpened = "ai_sheet_opened"
    /// Tilausnäkymä avautui, eli käyttäjä näki hinnan.
    case paywallViewed = "paywall_viewed"
    /// Tilaa-nappia painettiin. Ero valmiiseen ostoon = Applen dialogissa putoaminen.
    case purchaseStarted = "purchase_started"
    /// Käyttäjä perui Applen dialogin.
    case purchaseCancelled = "purchase_cancelled"
    /// Muutoksen jälkeinen päivitys epäonnistui niin että käyttäjä näki ilmoituksen.
    case refreshFailed = "refresh_failed"
    /// Sama päivitys onnistui vasta uusintayrityksellä. Tämä on se luku joka kertoo
    /// toimivatko uusinnat: ilman sitä näkyisi vain jäljelle jäänyt osa eikä se,
    /// kuinka paljon korjaantuu jo nyt itsestään.
    case refreshRecovered = "refresh_recovered"

    /// Mistä kohtaa sovellusta tapahtuma tuli. Palvelin hyväksyy vain nämä.
    enum Source: String {
        case nutrition
        case profile
        case aiEstimate = "ai_estimate"
        case recipes
        case today
        case workout
        case programs
        case body
    }

    /// Virheen laji karkeasti. Kiinteä joukko, koska tästä ei saa tulla vapaan tekstin
    /// kanavaa: `URLError`in oma kuvaus voisi sisältää osoitteita ja laitteen tietoja.
    enum Reason: String {
        case cancelled
        case connectionLost = "connection_lost"
        case timeout
        case offline
        case serverError = "server_error"
        case clientError = "client_error"
        case unknown

        init(_ error: Error) {
            if let apiError = error as? APIError {
                switch apiError {
                case .transport: self = .unknown
                case .paymentRequired: self = .clientError
                case .status(let code, _): self = code >= 500 ? .serverError : .clientError
                }
                return
            }
            switch (error as? URLError)?.code {
            case .cancelled: self = .cancelled
            case .networkConnectionLost: self = .connectionLost
            case .timedOut: self = .timeout
            case .notConnectedToInternet, .dataNotAllowed: self = .offline
            case .none: self = .unknown
            default: self = .unknown
            }
        }
    }
}

extension APIClient {
    private static let funnelLog = Logger(subsystem: "fi.volu.app", category: "funnel")

    /// Lähettää tapahtuman odottamatta vastausta.
    func log(_ event: FunnelEvent, source: FunnelEvent.Source? = nil, reason: FunnelEvent.Reason? = nil) {
        struct Body: Encodable {
            let kind: String
            let source: String?
            let reason: String?
        }
        Task {
            do {
                _ = try await post("/api/mobile/events", body: Body(
                    kind: event.rawValue,
                    source: source?.rawValue,
                    reason: reason?.rawValue
                ))
            } catch {
                // Seurannan epäonnistuminen ei ole käyttäjän ongelma eikä saa näkyä missään
                // muualla kuin lokissa.
                Self.funnelLog.info("tapahtuman \(event.rawValue, privacy: .public) kirjaus ei mennyt läpi")
            }
        }
    }
}
