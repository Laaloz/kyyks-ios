import Foundation
import Testing
@testable import Volu

/// Ainesvaihtojen kaksi lukkoa:
///
/// 1. **Vanha välimuistivastaus dekoodautuu.** `macros` ja `alternatives` ovat uusia
///    kenttiä reseptivastauksessa, ja Swift heittää `keyNotFound` puuttuvasta avaimesta
///    ellei kenttä ole valinnainen. Levyllä oleva vanha `ResponseCache`-vastaus jäisi
///    silloin dekoodaamatta ja kirjasto tyhjäksi — hiljaa. (Sama vika todettu aiemmin
///    treenivastauksessa, ks. `TemplateExerciseDecodingTests`.)
///
/// 2. **Vaihdon vaikutus annoksen makroihin.** Erotus lasketaan palvelimen valmiiksi
///    laskemista rivi- ja vaihtoehtomakroista jaettuna annosmäärällä — sama sääntö on
///    palvelimella (`applyIngredientSwaps`, lib/nutrition.ts): jos muutat toista,
///    muuta molemmat.
struct RecipeSwapTests {
    @Test func oldCachedIngredientLineStillDecodes() throws {
        let json = Data("""
        {"name": "Kanan rintafilee", "quantity": 600, "unit": "g", "groupLabel": null, "scalingMode": "linear"}
        """.utf8)
        let line = try JSONDecoder().decode(RecipeIngredientLine.self, from: json)
        #expect(line.macros == nil)
        #expect(line.alternatives == nil)
    }

    @Test func ingredientLineWithAlternativesDecodes() throws {
        let json = Data("""
        {"name": "Naudan jauheliha 10%", "quantity": 520, "unit": "g", "groupLabel": null,
         "scalingMode": "linear",
         "macros": {"kcal": 915, "proteinG": 104, "carbsG": 0, "fatG": 52},
         "alternatives": [{"originalName": "Naudan jauheliha 10%", "ingredientId": "abc",
                           "name": "Kiinteä tofu", "grams": 600,
                           "macros": {"kcal": 924, "proteinG": 104, "carbsG": 3, "fatG": 52}}]}
        """.utf8)
        let line = try JSONDecoder().decode(RecipeIngredientLine.self, from: json)
        #expect(line.alternatives?.first?.name == "Kiinteä tofu")
        #expect(line.alternatives?.first?.grams == 600)
    }

    @Test func swapAdjustsPerServingMacrosByDeltaOverServings() throws {
        let json = Data("""
        {"id": "r1", "name": "VHH-ateria", "description": null, "mealTag": "lunch",
         "imageUrl": null, "defaultServings": 4, "dietaryFlags": [], "allergies": [],
         "isOwn": false, "locked": false,
         "macrosPerServing": {"kcal": 386, "proteinG": 44, "carbsG": 12, "fatG": 15},
         "instructionSteps": [],
         "ingredients": [{"name": "Naudan jauheliha 10%", "quantity": 520, "unit": "g",
                          "groupLabel": null, "scalingMode": "linear",
                          "macros": {"kcal": 915, "proteinG": 104, "carbsG": 0, "fatG": 52},
                          "alternatives": [{"originalName": "Naudan jauheliha 10%",
                                            "ingredientId": "tofu-id", "name": "Kiinteä tofu",
                                            "grams": 600,
                                            "macros": {"kcal": 924, "proteinG": 103.8,
                                                       "carbsG": 3, "fatG": 52.2}}]}]}
        """.utf8)
        let recipe = try JSONDecoder().decode(Recipe.self, from: json)
        let option = try #require(recipe.ingredients?.first?.alternatives?.first)

        let adjusted = recipe.macrosPerServing(applying: ["Naudan jauheliha 10%": option])
        // Δkcal = (924 − 915) / 4 = +2,25; Δhh = 3 / 4 = +0,75.
        #expect(abs(adjusted.kcal - 388.25) < 0.001)
        #expect(abs(adjusted.carbsG - 12.75) < 0.001)
        // Proteiiniankkurointi: annoksen proteiini ei käytännössä muutu.
        #expect(abs(adjusted.proteinG - 43.95) < 0.001)

        // Tyhjä valinta palauttaa reseptin omat makrot sellaisenaan.
        #expect(recipe.macrosPerServing(applying: [:]) == recipe.macrosPerServing)
    }

    @Test func swapOptionAmountScalesLinearlyWithServings() {
        let option = RecipeIngredientSwapOption(
            originalName: "Kanan rintafilee",
            ingredientId: "x",
            name: "Nyhtökaura",
            grams: 460,
            macros: RecipeMacros(kcal: 925, proteinG: 138, carbsG: 37, fatG: 20)
        )
        #expect(option.amountText(servings: 4, defaultServings: 4) == "460 g")
        #expect(option.amountText(servings: 1, defaultServings: 4) == "115 g")
        #expect(option.amountText(servings: 8, defaultServings: 4) == "920 g")
    }
}
