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
    /// Miten määrä muuttuu annosmäärän mukana: "linear", "gentle", "fixed" tai
    /// "text_only".
    let scalingMode: String?
    /// Rivin osuus koko reseptin makroista. Tulee palvelimelta vain riveille joilla
    /// on vaihtoehtoja — vaihdon vaikutus laskee erotuksena tästä. Valinnainen,
    /// jotta vanha levyvälimuistin vastaus dekoodautuu (ks. RecipeSwapTests).
    let macros: RecipeMacros?
    /// Rivin vaihtoehdot valmiiksi laskettuine makroineen. Appi ei lataa
    /// ainesosakatalogia, joten makrot on saatava palvelimelta.
    let alternatives: [RecipeIngredientSwapOption]?

    var id: String { "\(groupLabel ?? "")-\(name)-\(quantity ?? 0)-\(unit)" }

    /// Määrä annetulle annosmäärälle.
    ///
    /// **Sama sääntö kuin webin `getIngredientScalingRatio`** (`lib/nutrition.ts`).
    /// Se on toistettu tässä, koska annosvalitsin muuttuu napautuksella eikä
    /// palvelinkierros per napautus ole vaihtoehto — mutta se on toisto:
    /// **jos muutat toista, muuta molemmat.** `RecipeScalingTests` lukitsee
    /// nämä neljä tapausta.
    func scaledQuantity(servings: Double, defaultServings: Double) -> Double? {
        guard let quantity else { return nil }
        let base = defaultServings > 0 ? defaultServings : 1
        let ratio = servings > 0 ? servings / base : 1
        switch scalingMode {
        case "linear":
            return quantity * ratio
        // Mausteet ja vastaavat eivät kaksinkertaistu annosten mukana: puolella
        // nopeudella kasvava määrä osuu lähemmäs kuin suora kerroin.
        case "gentle":
            return quantity * (ratio >= 1 ? 1 + (ratio - 1) * 0.5 : ratio)
        default:
            return quantity
        }
    }

    /// Määrä ja yksikkö luettavassa muodossa. Kokonaisluvusta jätetään desimaalit
    /// pois: "2 kpl" eikä "2,0 kpl".
    func amountText(servings: Double, defaultServings: Double) -> String {
        guard let scaled = scaledQuantity(servings: servings, defaultServings: defaultServings) else { return "" }
        return Self.formattedAmount(quantity: scaled, unit: unitLabel)
    }

    static func formattedAmount(quantity: Double, unit: String) -> String {
        let rounded = quantity.rounded()
        let number = abs(quantity - rounded) < 0.05
            ? String(Int(rounded))
            : String(format: "%.1f", quantity).replacingOccurrences(of: ".", with: ",")
        return "\(number) \(unit)"
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

extension Recipe {
    /// Annoksen makrot valituilla ainesvaihdoilla: reseptin makrot + vaihtojen
    /// erotus jaettuna annosmäärällä. Erotus lasketaan palvelimen valmiiksi
    /// laskemista rivi- ja vaihtoehtomakroista — appi ei tunne ainesosakatalogia.
    /// Avain on rivin nimi; puuttuva avain = alkuperäinen aines.
    func macrosPerServing(applying swaps: [String: RecipeIngredientSwapOption]) -> RecipeMacros {
        guard !swaps.isEmpty, let ingredients else { return macrosPerServing }
        let base = defaultServings > 0 ? defaultServings : 1
        var kcal = macrosPerServing.kcal
        var protein = macrosPerServing.proteinG
        var carbs = macrosPerServing.carbsG
        var fat = macrosPerServing.fatG
        for item in ingredients {
            guard let selected = swaps[item.name], let lineMacros = item.macros else { continue }
            kcal += (selected.macros.kcal - lineMacros.kcal) / base
            protein += (selected.macros.proteinG - lineMacros.proteinG) / base
            carbs += (selected.macros.carbsG - lineMacros.carbsG) / base
            fat += (selected.macros.fatG - lineMacros.fatG) / base
        }
        return RecipeMacros(kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat)
    }
}

/// Ainesrivin vaihtoehto: sama rivi eri raaka-aineella ja omalla grammamäärällä.
/// Makrot ovat koko reseptin mittakaavassa (vaihtoehdon grammamäärälle), samoin
/// kuin rivin omat `macros` — vaihdon vaikutus annokseen on niiden erotus jaettuna
/// reseptin annosmäärällä.
struct RecipeIngredientSwapOption: Decodable, Hashable, Identifiable {
    let originalName: String
    let ingredientId: String
    let name: String
    let grams: Double
    let macros: RecipeMacros

    var id: String { ingredientId }

    /// Grammamäärä annosvalinnalle. Vaihtoehdot skaalautuvat aina lineaarisesti:
    /// ne ovat pääraaka-aineita, eivät mausteita.
    func amountText(servings: Double, defaultServings: Double) -> String {
        let base = defaultServings > 0 ? defaultServings : 1
        let ratio = servings > 0 ? servings / base : 1
        return RecipeIngredientLine.formattedAmount(quantity: grams * ratio, unit: "g")
    }
}

/// Kirjaukseen lähtevä valinta. Palvelin hakee grammat ja makrot itse reseptin
/// vaihtoehdoista ja katalogista — client kertoo vain mitä valittiin.
struct RecipeSwapSelection: Encodable, Hashable {
    let originalName: String
    let ingredientId: String
}
