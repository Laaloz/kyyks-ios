import Foundation

/// /api/nutrition/ai-estimate -vastaus.
struct AiEstimateResponse: Decodable {
    let estimate: AiFoodEstimate
}

struct AiFoodEstimate: Decodable {
    let name: String
    var grams: Double
    let kcalPer100: Double
    let proteinPer100: Double
    let carbsPer100: Double
    let fatPer100: Double
    let confidence: Double?

    /// Makrot valitulle annoskoolle (arvot ovat per 100 g).
    func macros(forGrams grams: Double) -> (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        let factor = grams / 100
        return (kcalPer100 * factor, proteinPer100 * factor, carbsPer100 * factor, fatPer100 * factor)
    }
}

extension MealTag: Identifiable {
    public var id: String { rawValue }

    /// Kellonaika vain *ehdottaa* ateriapaikkaa — käyttäjä valitsee aina itse,
    /// koska koko päivän ateriat kirjataan usein kerralla illalla.
    static func suggestion(at date: Date = .now) -> MealTag {
        switch Calendar.current.component(.hour, from: date) {
        case 4 ..< 10: .breakfast
        case 10 ..< 14: .lunch
        case 14 ..< 16: .snack
        case 16 ..< 20: .dinner
        default: .evening_snack
        }
    }
}
