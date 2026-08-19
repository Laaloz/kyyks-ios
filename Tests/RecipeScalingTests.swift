import Testing
@testable import Volu

/// Ainesosan skaalaus annosmäärän mukana.
///
/// Sääntö on toistettu webistä (`lib/nutrition.ts`, `getIngredientScalingRatio`),
/// koska annosvalitsin muuttuu napautuksella eikä palvelinkierros per napautus ole
/// vaihtoehto. Toisto on hyväksytty riski vain jos se on lukittu testiin: nämä
/// neljä tapausta ovat se lukko.
struct RecipeScalingTests {
    private func line(_ mode: String?, quantity: Double? = 100) -> RecipeIngredientLine {
        RecipeIngredientLine(name: "Aines", quantity: quantity, unit: "g", groupLabel: nil, scalingMode: mode)
    }

    @Test func linearFollowsServingsDirectly() {
        let item = line("linear")
        #expect(item.scaledQuantity(servings: 2, defaultServings: 4) == 50)
        #expect(item.scaledQuantity(servings: 8, defaultServings: 4) == 200)
    }

    // Mauste ei kaksinkertaistu kun annokset kaksinkertaistuvat: puolella nopeudella
    // kasvava määrä osuu lähemmäs kuin suora kerroin.
    @Test func gentleGrowsAtHalfSpeedUpwards() {
        let item = line("gentle")
        #expect(item.scaledQuantity(servings: 8, defaultServings: 4) == 150)
    }

    // Alaspäin gentle käyttäytyy kuten linear — puolikas annos tarvitsee puolet
    // mausteesta, vaikka tupla ei tarvitse tuplaa.
    @Test func gentleShrinksLinearly() {
        let item = line("gentle")
        #expect(item.scaledQuantity(servings: 2, defaultServings: 4) == 50)
    }

    @Test func fixedAndUnknownStayPut() {
        #expect(line("fixed").scaledQuantity(servings: 8, defaultServings: 4) == 100)
        #expect(line("text_only").scaledQuantity(servings: 8, defaultServings: 4) == 100)
        #expect(line(nil).scaledQuantity(servings: 8, defaultServings: 4) == 100)
    }

    @Test func missingQuantityStaysMissing() {
        #expect(line("linear", quantity: nil).scaledQuantity(servings: 2, defaultServings: 4) == nil)
    }
}
