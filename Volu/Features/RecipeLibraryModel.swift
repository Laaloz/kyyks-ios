import Foundation
import Observation

/// Reseptikirjasto. SWR: välimuisti ruudulle heti, verkko taustalla.
///
/// Koko kirjasto haetaan kerralla (52 reseptiä) ja suodatus tehdään laitteessa.
/// Palvelinhaku per kirjain maksaisi ~280 ms kierrosta kohti eikä toisi mitään:
/// aineisto mahtuu muistiin moninkertaisesti.
@Observable
@MainActor
final class RecipeLibraryModel: CachedModel {
    private(set) var recipes: [Recipe] = []
    /// Onko käyttäjällä Pro. Näytetään vain lukittujen yhteydessä, jottei
    /// tilaajalle jää mitään muistutusta maksamisesta.
    private(set) var isPro = false
    var isLoading = false
    var errorMessage: String?

    var api: APIClient?
    let cacheKey = "mobile-recipes"
    let resourcePath = "/api/mobile/recipes"
    let loadFailureMessage = "Reseptien haku epäonnistui."
    var hasContent: Bool { !recipes.isEmpty }

    var query = ""
    /// Suodatus vaihtoryhmällä eikä yksittäisellä ateriapaikalla: aamupalaa ja iltapalaa
    /// syödään ristiin, samoin lounasta ja illallista. Tarkka ateriapaikka näkyy silti
    /// rivillä — se on reseptin ehdotus, ei rajoite.
    var mealFilter: MealSlotGroup?

    var lockedCount: Int { recipes.filter(\.locked).count }

    /// Kirjoituskentän ehdotukset. Vain avoimet reseptit: lukittu ehdotus kaatuisi
    /// palvelimen 402:een vasta napautuksen jälkeen.
    ///
    /// Ehdotus **ei** korvaa AI-arviota automaattisesti. "Banaanipannukakut" voi
    /// tarkoittaa sinun reseptiäsi tai jotain aivan muuta syötyä — arvaus näyttäisi
    /// oikealta myös silloin kun se on väärä, ja väärä makrorivi on pahempi kuin
    /// yksi napautus lisää.
    func suggestions(for text: String) -> [Recipe] {
        let term = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard term.count >= 3 else { return [] }
        return recipes
            .filter { !$0.locked && $0.name.lowercased().contains(term) }
            // Alusta täsmäävä ensin: "banaani" tarkoittaa todennäköisemmin
            // "Banaanipannukakut" kuin "Suklaa-banaanismoothie".
            .sorted { first, second in
                let firstPrefix = first.name.lowercased().hasPrefix(term)
                let secondPrefix = second.name.lowercased().hasPrefix(term)
                return firstPrefix == secondPrefix ? first.name < second.name : firstPrefix
            }
            .prefix(3)
            .map { $0 }
    }

    /// Suodatettu lista. Lukitut pysyvät mukana: tyhjentyvä lista näyttäisi
    /// rikkinäiseltä sovellukselta eikä tarjoukselta.
    var visibleRecipes: [Recipe] {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        return recipes.filter { recipe in
            (mealFilter == nil || recipe.slotGroup == mealFilter)
                && (term.isEmpty || recipe.name.lowercased().contains(term))
        }
    }

    func apply(_ data: Data) {
        guard let response = try? JSONDecoder().decode(RecipeLibraryResponse.self, from: data) else { return }
        recipes = response.recipes
        isPro = response.isPro
    }

    /// Merkitsee reseptin syödyksi valitulla annosmäärällä.
    ///
    /// Palauttaa `.paywall`, jos palvelin torjui lukitun reseptin — lukko on
    /// palvelimella, ja tämä on se hetki jolloin käyttäjä sen kohtaa.
    func logAsEaten(_ recipe: Recipe, servings: Double, planDate: String, mealTag: MealTag) async -> LogOutcome {
        guard let api else { return .failed }
        struct Body: Encodable {
            let planDate: String
            let mealTag: String
            let recipeId: String
            let servings: Double
            let source: String
            let eatenAt: String
        }
        do {
            _ = try await api.post("/api/day-meal-plans", body: Body(
                planDate: planDate,
                mealTag: mealTag.rawValue,
                recipeId: recipe.id,
                servings: servings,
                source: "added",
                // Kirjaus on kuittaus: rivi on syöty siinä hetkessä kun se kirjataan,
                // eikä erillistä "merkitse syödyksi" -vaihetta jätetä jälkeen.
                eatenAt: ISO8601DateFormatter().string(from: .now)
            ))
            return .logged
        } catch APIError.paymentRequired(let message) {
            return .paywall(message ?? "Tämä resepti kuuluu Volu Pro -tilaukseen.")
        } catch {
            return .failed
        }
    }

    enum LogOutcome {
        case logged
        case paywall(String)
        case failed
    }
}

private struct RecipeLibraryResponse: Decodable {
    let recipes: [Recipe]
    let isPro: Bool
}
