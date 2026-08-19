import SwiftUI
import UIKit

/// Näytön sammumisen esto näkymäkohtaisesti.
///
/// Kaksi erillistä asetusta eikä yhtä, koska tilanteet ovat erilaiset: reseptiä
/// luetaan kädet taikinassa, jolloin näytön sammuminen keskeyttää tekemisen ja
/// puhelinta joutuu koskemaan likaisin käsin. Treenissä puhelin on useimmiten
/// taskussa sarjojen välillä, ja päälle jäävä näyttö syö akkua koko treenin ajan
/// — siksi oletukset ovat eri suuntiin.
///
/// Laitekohtainen (`@AppStorage`) kuten muutkin näyttöasetukset: sama käyttäjä voi
/// haluta eri käytöksen puhelimeen ja tablettiin.
enum ScreenAwakeSetting {
    /// Reseptinäkymä. Oletus päällä.
    static let recipeKey = "keepScreenAwakeRecipes"
    /// Treeninäkymä. Oletus pois.
    static let workoutKey = "keepScreenAwakeWorkout"

    static let recipeDefault = true
    static let workoutDefault = false
}

private struct KeepScreenAwake: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { apply(isEnabled) }
            .onDisappear { apply(false) }
            // Asetuksen vaihto vaikuttaa heti eikä vasta seuraavalla avauksella.
            .onChange(of: isEnabled) { _, newValue in apply(newValue) }
    }

    private func apply(_ disabled: Bool) {
        // Lippu on koko sovelluksen laajuinen, joten se on nollattava poistuttaessa.
        // Unohtunut `true` pitäisi näytön päällä kaikkialla, mikä näkyy käyttäjälle
        // vain akun kulumisena — vikamuoto jota ei yhdistetä mihinkään näkymään.
        UIApplication.shared.isIdleTimerDisabled = disabled
    }
}

extension View {
    /// Estää näytön sammumisen niin kauan kuin näkymä on esillä ja asetus on päällä.
    func keepScreenAwake(_ isEnabled: Bool) -> some View {
        modifier(KeepScreenAwake(isEnabled: isEnabled))
    }
}
