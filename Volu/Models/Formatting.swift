import Foundation

// MARK: - Päivämäärät
//
// API palauttaa aikaleimat kolmessa muodossa (murto-osasekunnit, tavallinen
// ISO 8601, pelkkä päivä). Muotoilijat ovat kalliita luoda, joten ne ovat
// jaettuja vakioita — ja kaikki samassa paikassa, ettei kolmatta muunnosta
// keksitä uudestaan seuraavassa näkymässä.

extension ISO8601DateFormatter {
    /// Postgres-aikaleimoissa on murto-osasekunnit, joita oletusmuotoilija ei syö.
    ///
    /// **Tämä osaa vain murto-osasekunnilliset leimat.** Käytä aina
    /// `parseAPIDate`ia — sama API palauttaa myös leimoja ilman desimaaleja
    /// (esim. Healthista tuodut mittaukset), ja niiden jäsennys epäonnistuu
    /// tällä hiljaa. Muotoilija hiljeni aiemmin nimellä `flexible`, mikä
    /// houkutteli käyttämään sitä suoraan.
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Pelkkä päivä ilman kellonaikaa (`plan_date`, `scheduled_date`).
    static let dateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}

/// API:n aikaleima Dateksi muodosta riippumatta.
func parseAPIDate(_ value: String) -> Date? {
    ISO8601DateFormatter.withFractionalSeconds.date(from: value)
        ?? ISO8601DateFormatter().date(from: value)
        ?? ISO8601DateFormatter.dateOnly.date(from: String(value.prefix(10)))
}

// MARK: - Lukujen muotoilu

/// Kilot ilman turhaa desimaalia; pilkku desimaalierottimena kuten muualla apissa.
func formatKg(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    return rounded.truncatingRemainder(dividingBy: 1) == 0
        ? String(Int(rounded))
        : String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
}

func formatReps(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
}

/// Suunta merkkinä, ei värinä: nousu ei ole aina hyvä eikä lasku aina huono.
func formatPercent(_ value: Double) -> String {
    let sign = value >= 0 ? "+" : "−"
    return "\(sign)\(String(format: "%.1f", abs(value)).replacingOccurrences(of: ".", with: ",")) %"
}

/// "7 h 12 min" — tunnit ja minuutit, ei sekunteja.
///
/// Kesto näytetään aina tässä muodossa: "85 min" on luku jonka lukija joutuu
/// jakamaan päässään, eikä treenin tai lenkin pituus ole koskaan niin tarkka
/// asia että minuuttiluku olisi sinänsä kiinnostava.
func formatDuration(minutes totalMinutes: Int) -> String {
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours == 0 { return "\(minutes) min" }
    // Tasatunti ilman nollaa: "2 h" eikä "2 h 0 min".
    return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
}

func formatDuration(seconds: Double) -> String {
    formatDuration(minutes: Int((seconds / 60).rounded()))
}
