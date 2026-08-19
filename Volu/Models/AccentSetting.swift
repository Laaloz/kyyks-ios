import SwiftUI
import UIKit

/// Korostusvärin valinta. Laitekohtainen asetus kuten [[AppearanceSetting]]:
/// sama käyttäjä voi haluta eri värin puhelimeen ja tablettiin.
///
/// **Jokaisella värillä on erikseen vaalean ja tumman teeman sävy.** Yksi sävy
/// ei riitä: vaalealla taustalla väri on luettava vasta tummana, ja tummalla
/// taustalla sama sävy sulautuu taustaan. Sama jako on jo brändivihreässä
/// (`AccentColor`-resurssi), ja tämä noudattaa sitä.
///
/// Sävyt on valittu laskien eikä silmällä: jokaisen kontrasti omaa taustaansa
/// vasten ylittää WCAG:n 4,5:1 rajan, mikä koskee sekä linkkitekstiä että
/// valkoista tekstiä korostetun napin päällä. Lukitseva testi:
/// `AccentContrastTests`.
enum AccentSetting: String, CaseIterable, Identifiable {
    case green
    case blue
    case purple
    case orange
    case red
    case teal
    case magenta

    /// Avain on jaettu asetusnäkymän ja sovelluksen juuren kesken; kahtena
    /// merkkijonona kirjoitusvirhe jäisi huomaamatta.
    static let storageKey = "accentColor"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .green: "Vihreä"
        case .blue: "Sininen"
        case .purple: "Violetti"
        case .orange: "Oranssi"
        case .red: "Punainen"
        case .teal: "Turkoosi"
        case .magenta: "Magenta"
        }
    }

    /// Sävy vaalealla taustalla. Tummempi kuin tumman teeman vastine.
    var lightHex: String {
        switch self {
        case .green: "008048"
        case .blue: "0A5FCC"
        case .purple: "6A3FBF"
        case .orange: "A64B00"
        case .red: "B3243C"
        case .teal: "006D77"
        case .magenta: "A32473"
        }
    }

    /// Sävy tummalla taustalla. Vaaleampi, jottei sulaudu taustaan.
    var darkHex: String {
        switch self {
        case .green: "54D795"
        case .blue: "6AAFFF"
        case .purple: "B79BFF"
        case .orange: "FFA24D"
        case .red: "FF8095"
        case .teal: "5FD3DE"
        case .magenta: "FF8FCB"
        }
    }

    /// Dynaaminen väri, joka ratkeaa vasta piirtohetkellä.
    ///
    /// `UIColor(dynamicProvider:)` lukee sen tyylin joka kyseisessä kohdassa on
    /// voimassa — myös silloin kun sovellus pakottaa teeman
    /// `preferredColorScheme`illä. `@Environment(\.colorScheme)` kertoisi vain
    /// yhden näkymän tilan, jolloin sheetit ja pakotettu teema jäisivät väärään
    /// sävyyn.
    var color: Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
        })
    }
}

extension UIColor {
    /// Kuusimerkkinen RRGGBB. Kelvoton arvo antaa magentan: näkyvä virhe on
    /// parempi kuin hiljainen musta, joka menisi läpi arvaamattomana.
    convenience init(hex: String) {
        var value: UInt64 = 0
        guard hex.count == 6, Scanner(string: hex).scanHexInt64(&value) else {
            self.init(red: 1, green: 0, blue: 1, alpha: 1)
            return
        }
        self.init(
            red: CGFloat((value & 0xFF0000) >> 16) / 255,
            green: CGFloat((value & 0x00FF00) >> 8) / 255,
            blue: CGFloat(value & 0x0000FF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// Korostusnapin (`.borderedProminent`) tekstiväri.
    ///
    /// Oletusarvoinen valkoinen teksti toimii vaaleassa tilassa, mutta tumman
    /// tilan aksentit ovat tarkoituksella vaaleita (jotta ne kantavat tekstinä
    /// mustaa taustaa vasten), ja valkoinen niiden päällä jää ~1,6–2,0:1
    /// kontrastiin. systemBackground on valkoinen vaaleassa ja musta tummassa
    /// tilassa — täsmälleen ne parit, jotka AccentContrastTests todentaa
    /// jokaiselle aksentille (≥ 4,5:1).
    func prominentButtonLabel() -> some View {
        foregroundStyle(Color(.systemBackground))
    }
}
