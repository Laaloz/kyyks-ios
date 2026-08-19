import Foundation

/// /api/mobile/nutrition?date=YYYY-MM-DD -vastaus. Makrot on laskettu
/// palvelimella, joten clientin ei tarvitse ainesosakatalogia.
struct NutritionDay: Decodable {
    let date: String
    let target: MacroValues?
    let entries: [NutritionEntry]
    let totals: MacroValues
}

struct MacroValues: Decodable {
    let kcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

struct NutritionEntry: Decodable, Identifiable {
    let id: String
    let mealTag: String
    let position: Int
    let servings: Double
    let eatenAt: String?
    let kind: String
    let name: String
    /// Reseptin tunniste, kun rivi on kirjattu kirjastosta. Reitti jättää sen
    /// pois ad hoc -riveiltä, joten `nil` erottaa ne ilman erillistä lippua.
    let recipeId: String?
    let grams: Double?
    let aiStatus: String?
    let macros: MacroValues

    var isEaten: Bool { eatenAt != nil }
    var isPendingEstimate: Bool { aiStatus == "pending" }
    var isFailedEstimate: Bool { aiStatus == "failed" }
}

enum MealTag: String, CaseIterable {
    case breakfast, lunch, snack, dinner, evening_snack

    var label: String {
        switch self {
        case .breakfast: "Aamupala"
        case .lunch: "Lounas"
        case .snack: "Välipala"
        case .dinner: "Illallinen"
        case .evening_snack: "Iltapala"
        }
    }
}
