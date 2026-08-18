import Foundation

/// Yhden API-reitin stale-while-revalidate-haku: välimuisti ruudulle heti,
/// tuore data verkosta taustalla.
///
/// Sama runko oli kirjoitettu seitsemään malliin erikseen. Erot olivat vain
/// reitti, vastauksen purku ja virheviesti — ne jäävät mallille, muu tulee
/// tästä. Mallit pitävät oman tilansa, joten `@Observable` toimii normaalisti
/// (periytyminen ei toimisi: alaluokan kentät jäisivät seuraamatta).
@MainActor
protocol CachedModel: AnyObject {
    var api: APIClient? { get set }
    /// Levyvälimuistin avain. Päiväkohtaisissa malleissa sisältää päivän.
    var cacheKey: String { get }
    var resourcePath: String { get }
    /// Onko ruudulla jo jotain näytettävää. Verkkovirhe kerrotaan vain jos ei
    /// ole: vanha data on käyttäjälle parempi kuin virheilmoitus.
    var hasContent: Bool { get }
    var loadFailureMessage: String { get }
    var isLoading: Bool { get set }
    var errorMessage: String? { get set }
    func apply(_ data: Data)
}

extension CachedModel {
    /// Näkymät kutsuvat tätä `.task`-lohkosta, siis joka avauksella. Clientti
    /// luodaan vain kerran: jokainen APIClient avaa oman URLSessionin, eikä
    /// niitä ole syytä kerätä taustalle.
    func configure(auth: AuthManager) {
        if api == nil { api = APIClient(auth: auth) }
    }

    func load() async {
        if let cached = await ResponseCache.shared.read(cacheKey) {
            apply(cached)
        } else {
            isLoading = true
        }
        await refresh()
        isLoading = false
    }

    /// Taustapäivitys. Epäonnistuminen on hiljainen jos ruudulla on jo dataa:
    /// vanha data on käyttäjälle parempi kuin virheilmoitus.
    ///
    /// Palauttaa onnistuiko haku. Käyttäjän tekemän muutoksen jälkeen käytä
    /// `refreshAfterChange()`ia — siellä hiljaisuus on väärä vastaus.
    @discardableResult
    func refresh() async -> Bool {
        await refreshCapturingError() == nil
    }

    /// Kuten `refresh()`, mutta palauttaa virheen sen sijaan että hukkaisi sen.
    ///
    /// Pelkkä Bool riitti niin kauan kuin epäonnistumiseen ei tarvinnut
    /// reagoida. Kun se alkoi näkyä käyttäjälle, jäljelle jäi ilmoitus joka ei
    /// kerro syytä — sama umpikuja johon treenin viimeistely ajautui.
    private func refreshCapturingError() async -> Error? {
        guard let api else { return APIError.transport }
        do {
            let data = try await api.get(resourcePath)
            await ResponseCache.shared.write(cacheKey, data: data)
            apply(data)
            errorMessage = nil
            return nil
        } catch {
            if !hasContent {
                errorMessage = loadFailureMessage
            }
            return error
        }
    }

    /// Päivitys heti käyttäjän muutoksen jälkeen.
    ///
    /// Ero taustapäivitykseen on olennainen: muutos on jo tallennettu
    /// palvelimelle, joten epäonnistunut haku jättää ruudulle tilan, josta
    /// puuttuu juuri se muutos jonka käyttäjä äsken teki — esimerkiksi kesken
    /// treenin lisätty liike. Hiljaisuus näyttää siltä kuin tallennus olisi
    /// epäonnistunut, ja ainoa keino saada liike näkyviin oli käynnistää
    /// sovellus uudelleen.
    ///
    /// Yksi uusintayritys ennen luovuttamista: tavallisin syy on hetkellinen
    /// katko, ja verkko on juuri äsken toiminut kun muutos meni läpi.
    func refreshAfterChange() async {
        if await refreshCapturingError() == nil { return }
        // Odotus oli 600 ms. Se riittää hetkelliseen katkoon, muttei siihen
        // että palvelin on hidas — jolloin molemmat yritykset osuvat samaan
        // ruuhkaan ja käyttäjä näkee virheen vaikka mikään ei ole rikki.
        try? await Task.sleep(for: .milliseconds(1500))
        guard let error = await refreshCapturingError() else { return }
        errorMessage = Self.refreshFailureText(for: error)
    }

    /// Syy mukaan ilmoitukseen: aikakatkaisu, palvelimen virhe ja kadonnut
    /// treeni näyttivät kaikki samalta, eikä niitä voinut erottaa raportista.
    private static func refreshFailureText(for error: Error) -> String {
        let base = "Muutos tallentui, mutta näkymä ei päivittynyt"
        if let serverMessage = (error as? APIError)?.serverMessage {
            return "\(base) — \(serverMessage)"
        }
        if case APIError.status(let code, _)? = error as? APIError {
            return "\(base) (virhe \(code)) — vedä alas päivittääksesi."
        }
        if (error as? URLError)?.code == .timedOut {
            return "\(base): palvelin ei ehtinyt vastata — vedä alas päivittääksesi."
        }
        return "\(base) — vedä alas päivittääksesi."
    }
}
