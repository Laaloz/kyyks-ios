import Testing

@testable import Volu

/// Hakusanan prosenttikoodaus: & = + eivät saa päästä läpi, koska ne
/// katkaisisivat kyselyparametrin tai muuttuisivat välilyönniksi palvelimella.
/// `.urlQueryAllowed` päästi ne — siksi oma tiukka joukko.
struct QueryValueEncodingTests {
    @Test func koodaaParametrinKatkaisevatMerkit() {
        #expect(APIClient.queryValue("Clean & press") == "Clean%20%26%20press")
        #expect(APIClient.queryValue("Dips + lisäpaino") == "Dips%20%2B%20lis%C3%A4paino")
        #expect(APIClient.queryValue("a=b?c") == "a%3Db%3Fc")
    }

    @Test func eiKoskeTavallisiinKirjaimiin() {
        #expect(APIClient.queryValue("penkkipunnerrus") == "penkkipunnerrus")
        #expect(APIClient.queryValue("maastaveto-2.5") == "maastaveto-2.5")
    }
}
