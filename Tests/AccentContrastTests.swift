import SwiftUI
import Testing
import UIKit

@testable import Volu

/// Korostusvärin lupaus on että se toimii **molemmissa** teemoissa. Se on
/// mitattava asia, ei makuasia: väri joka on luettava valkoisella taustalla on
/// usein tummalla mustaa vasten liian tumma, ja sama toisin päin.
///
/// Testi laskee WCAG-kontrastisuhteen jokaiselle sävylle omaa taustaansa vasten.
/// Sama luku pätee kahteen käyttöön: linkkitekstiin taustan päällä ja napin
/// tekstiin korostetun napin päällä — **kun** napin teksti on systemBackground
/// (valkoinen vaaleassa, musta tummassa), minkä `prominentButtonLabel()`
/// asettaa. Valkoinen teksti tumman tilan vaalealla aksentilla jäisi ~2:1
/// suhteeseen, eikä tämä testi sitä paria mittaa — älä poista modifieria
/// napeista siinä uskossa että testi kattaisi sen.
struct AccentContrastTests {
    /// WCAG 2.1: tavallisen tekstin alaraja.
    private let vaadittuSuhde = 4.5

    private func luminanssi(_ hex: String) -> Double {
        let color = UIColor(hex: hex)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func kanava(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * kanava(r) + 0.7152 * kanava(g) + 0.0722 * kanava(b)
    }

    private func suhde(_ a: String, _ b: String) -> Double {
        let (x, y) = (luminanssi(a), luminanssi(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test(arguments: AccentSetting.allCases)
    func vaaleaSavyEroaaValkoisestaTaustasta(_ option: AccentSetting) {
        let mitattu = suhde(option.lightHex, "FFFFFF")
        #expect(mitattu >= vaadittuSuhde, "\(option.label) vaalealla: \(mitattu)")
    }

    @Test(arguments: AccentSetting.allCases)
    func tummaSavyEroaaMustastaTaustasta(_ option: AccentSetting) {
        let mitattu = suhde(option.darkHex, "000000")
        #expect(mitattu >= vaadittuSuhde, "\(option.label) tummalla: \(mitattu)")
    }

    @Test(arguments: AccentSetting.allCases)
    func savytOvatEriVarit(_ option: AccentSetting) {
        // Jos vaalea ja tumma sävy olisivat sama, toinen teema jäisi
        // korjaamatta — juuri se vika jota tämä asetus välttää.
        #expect(option.lightHex != option.darkHex)
        #expect(luminanssi(option.darkHex) > luminanssi(option.lightHex))
    }

    @Test func oletusOnBrandivihrea() {
        // Oletus ei saa muuttua tämän asetuksen myötä: nykyisten käyttäjien
        // sovellus näyttää samalta kunnes he itse valitsevat toisin.
        #expect(AccentSetting.green.lightHex == "008048")
        #expect(AccentSetting.green.darkHex == "54D795")
    }

    @Test func kelvotonHexOnNakyvaVirhe() {
        // Hiljainen musta menisi läpi arvaamattomana; magenta ei.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: "ei-hexa").getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r == 1 && g == 0 && b == 1)
    }
}
