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
    var mealFilter: MealTag?

    var lockedCount: Int { recipes.filter(\.locked).count }

    /// Suodatettu lista. Lukitut pysyvät mukana: tyhjentyvä lista näyttäisi
    /// rikkinäiseltä sovellukselta eikä tarjoukselta.
    var visibleRecipes: [Recipe] {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        return recipes.filter { recipe in
            (mealFilter == nil || recipe.mealTag == mealFilter?.rawValue)
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
