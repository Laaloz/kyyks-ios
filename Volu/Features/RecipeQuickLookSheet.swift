import SwiftUI

/// Reseptin katselu muualta kuin kirjastosta — käytännössä jo kirjatun
/// ateriarivin kautta.
///
/// Oma näkymänsä siksi, että kutsuja tuntee vain reseptin tunnisteen. Kirjasto
/// on levyvälimuistissa (`mobile-recipes`), joten avaus on yleensä välitön ja
/// verkkohaku on vain varautuminen tyhjään välimuistiin.
struct RecipeQuickLookSheet: View {
    let auth: AuthManager
    let recipeId: String

    @State private var model = RecipeLibraryModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let recipe = model.recipes.first(where: { $0.id == recipeId }) {
                RecipeDetailSheet(
                    recipe: recipe,
                    planDate: "",
                    onLog: { _, _ in .failed },
                    onLogged: {},
                    onPaywall: { _ in },
                    // Rivi on jo kirjattu: kirjausnappi tarjoaisi saman aterian
                    // toiseen kertaan.
                    showsLogAction: false
                )
            } else if model.isLoading {
                ProgressView()
            } else {
                // Resepti on voitu poistaa kirjastosta sen jälkeen kun ateria
                // kirjattiin. Rivi säilyy silti, joten tämä on kerrottava
                // eikä jätettävä tyhjäksi näkymäksi.
                VStack(spacing: 12) {
                    Text("Reseptiä ei löytynyt.").font(.headline)
                    Text("Se on voitu poistaa kirjastosta.").foregroundStyle(.secondary)
                    Button("Sulje") { dismiss() }
                }
                .padding()
            }
        }
        .task {
            model.configure(auth: auth)
            await model.load()
        }
    }
}

/// Reseptiviittaus sheet-kohteena.
struct RecipeReference: Identifiable {
    let id: String
}
