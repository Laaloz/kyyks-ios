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

    /// Mistä kohtaa sovellusta tapahtuma tuli. Palvelin hyväksyy vain nämä.
    enum Source: String {
        case nutrition
        case profile
        case aiEstimate = "ai_estimate"
        case recipes
    }
}

extension APIClient {
    private static let funnelLog = Logger(subsystem: "fi.volu.app", category: "funnel")

    /// Lähettää tapahtuman odottamatta vastausta.
    func log(_ event: FunnelEvent, source: FunnelEvent.Source? = nil) {
        struct Body: Encodable {
            let kind: String
            let source: String?
        }
        Task {
            do {
                _ = try await post("/api/mobile/events", body: Body(kind: event.rawValue, source: source?.rawValue))
            } catch {
                // Seurannan epäonnistuminen ei ole käyttäjän ongelma eikä saa näkyä missään
                // muualla kuin lokissa.
                Self.funnelLog.info("tapahtuman \(event.rawValue, privacy: .public) kirjaus ei mennyt läpi")
            }
        }
    }
}
