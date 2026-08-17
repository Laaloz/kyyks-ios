import Foundation

/// Tietosuojaselosteen ja käyttöehtojen osoitteet yhdessä paikassa.
///
/// Applen sääntö 5.1.1(i) vaatii, että tietosuojaselosteeseen pääsee
/// sovelluksen sisältä helposti — ei vain App Storen sivulta. Siksi linkki on
/// kolmessa paikassa: rekisteröitymisessä (ennen kuin tietoja luovutetaan),
/// asetuksissa (kirjautuneelle käyttäjälle) ja tilausnäkymässä (jossa sääntö
/// 3.1.2 vaatii lisäksi käyttöehdot).
///
/// Osoite johdetaan API:n osoitteesta, koska seloste on samalla palvelimella.
/// Kovakoodattu domain oli aiemmin kahdessa paikassa eri muodossa, jolloin
/// kehityskäännös osoitti tuotantoon eikä eroa huomannut mistään.
enum LegalLinks {
    static var privacy: URL {
        AppConfig.apiBaseURL.appending(path: "privacy")
    }

    /// Applen vakioehdot. Sovelluksella ei ole omia käyttöehtoja, ja Apple
    /// hyväksyy tämän nimenomaisesti tilaussovelluksen ehdoiksi.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Salasanan palautus tehdään verkossa: "Unohditko salasanasi?" on
    /// kirjautumissivulla näkyvissä ilman navigointia, ja pyyntöreittiä suojaa
    /// hCaptcha jota sovelluksessa ei ole.
    static var passwordReset: URL {
        AppConfig.apiBaseURL
    }
}
