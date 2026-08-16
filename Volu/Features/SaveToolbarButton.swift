import SwiftUI

/// Yläpalkin tallennusnappi, joka näyttää tallennuksen etenemisen.
///
/// Pelkkä lukittuminen ei kerro käyttäjälle mitään: hitaalla yhteydellä nappi
/// näyttää samalta kuin rikkinäinen. Sama komponentti kaikissa kirjaussheeteissä,
/// jotta palaute on samanlainen riippumatta siitä mitä tallennetaan.
struct SaveToolbarButton: View {
    let title: String
    let isSaving: Bool
    let isEnabled: Bool
    let action: () -> Void

    init(_ title: String = "Tallenna", isSaving: Bool, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isSaving = isSaving
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        if isSaving {
            ProgressView()
                .accessibilityLabel("Tallennetaan")
        } else {
            Button(title, action: action)
                .disabled(!isEnabled)
        }
    }
}
