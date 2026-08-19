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
    /// Lukujen alkuperä: "recipe", "ai", "fineli", "own" tai puuttuva. Erottaa
    /// mitatut luvut arvatuista.
    let foodSource: String?
    let grams: Double?
    let aiStatus: String?
    let macros: MacroValues

    var isEaten: Bool { eatenAt != nil }
    var origin: EntryOrigin { EntryOrigin(foodSource: foodSource) }
    var isPendingEstimate: Bool { aiStatus == "pending" }
    var isFailedEstimate: Bool { aiStatus == "failed" }
}

/// Ateriarivin alkuperä sellaisena kuin se kannattaa näyttää.
///
/// Merkitään vain kaksi: resepti ja AI-arvio. Haulla lisätty katalogirivi on
/// normaalitila eikä ansaitse kuvaketta — merkki kuuluu poikkeukselle.
///
/// Ero on käyttäjälle olennainen eikä kosmeettinen: reseptin ja katalogin luvut
/// ovat mitattuja, AI:n arvattuja. Kun päivän summa näyttää oudolta, ensimmäinen
/// kysymys on mikä rivi on arvio.
enum EntryOrigin {
    case recipe
    case aiEstimate
    case plain

    init(foodSource: String?) {
        switch foodSource {
        case "recipe": self = .recipe
        case "ai": self = .aiEstimate
        default: self = .plain
        }
    }

    var symbol: String? {
        switch self {
        case .recipe: "book"
        case .aiEstimate: "sparkles"
        case .plain: nil
        }
    }

    /// Ruudunlukijalle sama tieto sanoina: kuvake yksin ei kerro mitään.
    var accessibilityLabel: String? {
        switch self {
        case .recipe: "Reseptistä"
        case .aiEstimate: "Tekoälyn arvio"
        case .plain: nil
        }
    }
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
