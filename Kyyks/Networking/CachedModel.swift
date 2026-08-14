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
    var api: APIClient? { get }
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
    func load() async {
        if let cached = await ResponseCache.shared.read(cacheKey) {
            apply(cached)
        } else {
            isLoading = true
        }
        await refresh()
        isLoading = false
    }

    func refresh() async {
        guard let api else { return }
        do {
            let data = try await api.get(resourcePath)
            await ResponseCache.shared.write(cacheKey, data: data)
            apply(data)
            errorMessage = nil
        } catch {
            if !hasContent {
                errorMessage = loadFailureMessage
            }
        }
    }
}
