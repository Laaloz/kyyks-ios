import Foundation
import Observation

/// Ravintopäivän tila: SWR-haku päiväkohtaisella välimuistiavaimella ja
/// optimistiset kirjaukset. Palvelin laskee makrot valmiiksi.
@Observable
@MainActor
final class NutritionModel: CachedModel {
    private(set) var day: NutritionDay?
    var isLoading = false
    var errorMessage: String?
    private(set) var selectedDate = Date.now

    private(set) var api: APIClient?

    var totals: MacroValues { day?.totals ?? MacroValues(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0) }

    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    var dateLabel: String {
        if Calendar.current.isDateInToday(selectedDate) { return "Tänään" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Eilen" }
        return selectedDate.formatted(.dateTime.weekday(.abbreviated).day().month())
    }

    var remainingKcal: Int? {
        guard let target = day?.target else { return nil }
        return Int((target.kcal - totals.kcal).rounded())
    }

    var dateKey: String {
        // Paikallinen päiväavain — sama muoto kuin webin plan_date.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        return formatter.string(from: selectedDate)
    }

    var cacheKey: String { "nutrition-\(dateKey)" }
    var resourcePath: String { "/api/mobile/nutrition?date=\(dateKey)" }
    let loadFailureMessage = "Ravintotietojen haku epäonnistui."
    var hasContent: Bool { day != nil }

    func configure(auth: AuthManager) {
        api = APIClient(auth: auth)
    }

    func entries(for tag: MealTag) -> [NutritionEntry] {
        (day?.entries ?? []).filter { $0.mealTag == tag.rawValue }.sorted { $0.position < $1.position }
    }

    func shiftDay(by days: Int) async {
        guard let shifted = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        if days > 0 && shifted > Date.now { return }
        selectedDate = shifted
        day = nil
        await load()
    }

    /// Optimistinen poisto: rivi katoaa heti ja päivän summat päivittyvät,
    /// pyyntö kulkee taustalla. Virheessä rivi palautuu ja syy kerrotaan.
    func deleteEntry(_ entry: NutritionEntry) {
        guard let api, let current = day else { return }
        let previous = current
        day = NutritionDay(
            date: current.date,
            target: current.target,
            entries: current.entries.filter { $0.id != entry.id },
            totals: current.totals
        )

        Task {
            do {
                _ = try await api.delete("/api/day-meal-plans/\(entry.id)")
                await refresh()
            } catch {
                day = previous
                errorMessage = "Aterian poisto epäonnistui — yritä uudelleen."
            }
        }
    }

    /// Annoskoon ja ateriapaikan korjaus. Makrot lasketaan palvelimella,
    /// joten tuore data haetaan tallennuksen jälkeen.
    func updateEntry(_ entry: NutritionEntry, grams: Double?, servings: Double?, mealTag: MealTag) async {
        guard let api else { return }
        struct Body: Encodable {
            let grams: Double?
            let servings: Double?
            let mealTag: String
        }
        do {
            _ = try await api.patch(
                "/api/day-meal-plans/\(entry.id)",
                body: Body(grams: grams, servings: servings, mealTag: mealTag.rawValue)
            )
            await refresh()
        } catch {
            errorMessage = "Muutoksen tallennus epäonnistui."
        }
    }

    /// Päivä voi ehtiä vaihtua kesken haun — vanhan päivän vastaus jätetään
    /// huomiotta, jottei se korvaa jo valittua päivää.
    func apply(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(NutritionDay.self, from: data), decoded.date == dateKey else { return }
        day = decoded
    }
}
