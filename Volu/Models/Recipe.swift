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
    var slotGroup: MealSlotGroup? { MealTag(rawValue: mealTag).map(MealSlotGroup.forTag) }
}

/// Ateriapaikkojen vaihtoryhmät. Aamupala ja iltapala ovat saman kokoisia ja niitä
/// syödään ristiin, samoin lounas ja illallinen — viiden erillisen suodattimen takana
/// puolet kirjastosta jäi löytymättä väärän otsikon alta. Sama jako on jo webin
/// laskennassa (`mealSlotGroups`); tämä on sen näkymäpuoli.
enum MealSlotGroup: String, CaseIterable, Identifiable {
    case morningEvening
    case main
    case snack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .morningEvening: "Aamu- ja iltapala"
        case .main: "Lounas ja illallinen"
        case .snack: "Välipalat"
        }
    }

    var tags: [MealTag] {
        switch self {
        case .morningEvening: [.breakfast, .evening_snack]
        case .main: [.lunch, .dinner]
        case .snack: [.snack]
        }
    }

    static func forTag(_ tag: MealTag) -> MealSlotGroup {
        allCases.first { $0.tags.contains(tag) } ?? .snack
    }
}

extension Recipe {
    /// Ainesosat ryhmittäin siinä järjestyksessä kuin ryhmät esiintyvät. Ryhmätön
    /// resepti palauttaa yhden nimettömän ryhmän, jolloin näkymä ei tarvitse
    /// kahta eri polkua.
    var ingredientGroups: [(label: String?, items: [RecipeIngredientLine])] {
        guard let ingredients, !ingredients.isEmpty else { return [] }
        var order: [String?] = []
        var byLabel: [String?: [RecipeIngredientLine]] = [:]
        for item in ingredients {
            if byLabel[item.groupLabel] == nil { order.append(item.groupLabel) }
            byLabel[item.groupLabel, default: []].append(item)
        }
        return order.map { ($0, byLabel[$0] ?? []) }
    }
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
    /// Reseptin osa johon aines kuuluu ("Kastike", "Pohja", "Päälle"). Ilman tätä
    /// monikomponenttireseptistä ei näe mitkä ainekset menevät mihinkin.
    let groupLabel: String?

    var id: String { "\(groupLabel ?? "")-\(name)-\(quantity ?? 0)-\(unit)" }

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
