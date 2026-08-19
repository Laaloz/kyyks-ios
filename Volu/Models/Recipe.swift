import Foundation

/// Reseptikirjaston rivi. Makrot tulevat valmiiksi laskettuina palvelimelta:
/// laskenta on jaettua webin kanssa (`lib/nutrition`), eikä clientin tarvitse
/// ladata 4 331 rivin ainesosakatalogia niiden takia.
struct Recipe: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let mealTag: String
    let imageUrl: String?
    let defaultServings: Double
    let dietaryFlags: [String]
    let allergies: [String]
    let isOwn: Bool
    /// Pron sisältöä johon tällä käyttäjällä ei ole oikeutta. Kortti näkyy silti
    /// — makrot ja kuva kertovat mistä maksaisi — mutta ohje ja ainesosat eivät
    /// tule laitteelle lainkaan, joten lukko ei ole clientin varassa.
    let locked: Bool
    let macrosPerServing: RecipeMacros
    let instructionSteps: [String]?
    let ingredients: [RecipeIngredientLine]?

    var mealLabel: String { MealTag(rawValue: mealTag)?.label ?? "" }
}

struct RecipeMacros: Decodable, Hashable {
    let kcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    func scaled(by servings: Double) -> RecipeMacros {
        RecipeMacros(
            kcal: kcal * servings,
            proteinG: proteinG * servings,
            carbsG: carbsG * servings,
            fatG: fatG * servings
        )
    }
}

struct RecipeIngredientLine: Decodable, Hashable, Identifiable {
    let name: String
    let quantity: Double?
    let unit: String

    var id: String { "\(name)-\(quantity ?? 0)-\(unit)" }

    /// Määrä ja yksikkö luettavassa muodossa. Kokonaisluvusta jätetään desimaalit
    /// pois: "2 kpl" eikä "2,0 kpl".
    var amountText: String {
        guard let quantity else { return "" }
        let rounded = quantity.rounded()
        let number = abs(quantity - rounded) < 0.05
            ? String(Int(rounded))
            : String(format: "%.1f", quantity).replacingOccurrences(of: ".", with: ",")
        return "\(number) \(unitLabel)"
    }

    private var unitLabel: String {
        switch unit {
        case "g": "g"
        case "ml": "ml"
        case "dl": "dl"
        case "pcs": "kpl"
        case "tsp": "tl"
        case "tbsp": "rkl"
        default: unit
        }
    }
}
