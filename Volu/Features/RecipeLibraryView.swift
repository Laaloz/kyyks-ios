import SwiftUI

/// Reseptikirjasto: selaa, katso makrot ja ohje, merkitse syödyksi.
///
/// Sama sisältö kuin webin Reseptit-välilehdellä. Kirjasto on Pron sisältöä, ja
/// lukitut reseptit näkyvät listalla — kortilta näkee mistä maksaisi, mutta ohje
/// ja ainesosat eivät tule laitteelle lainkaan.
struct RecipeLibraryView: View {
    let auth: AuthManager
    /// Päivä johon kirjaus menee. Kirjasto avataan Ravinnosta, joten se on se
    /// päivä jota käyttäjä juuri katsoi.
    let planDate: String
    let onLogged: () -> Void

    @State private var model = RecipeLibraryModel()
    @State private var selected: Recipe?
    @State private var paywallReason: PaywallReason?
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let error = model.errorMessage {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }

            Section {
                Picker("Ateriapaikka", selection: $model.mealFilter) {
                    Text("Kaikki").tag(MealSlotGroup?.none)
                    ForEach(MealSlotGroup.allCases) { group in
                        Text(group.label).tag(MealSlotGroup?.some(group))
                    }
                }
                .pickerStyle(.menu)
                // Korostusväri kuuluu toiminnoille, ei arvoille.
                .tint(Color.secondary)
            }

            Section {
                ForEach(model.visibleRecipes) { recipe in
                    Button {
                        selected = recipe
                    } label: {
                        RecipeRow(recipe: recipe)
                    }
                    .buttonStyle(.plain)
                }

                if model.visibleRecipes.isEmpty, model.hasContent {
                    Text("Ei osumia haulla.").foregroundStyle(.secondary)
                }
            } footer: {
                // Alaviite on oikea paikka juuri tälle: tieto ei ole sellaista jota
                // etsitään, mutta se pitää olla kerrottuna.
                if model.hasContent {
                    Text("Reseptikuvat ovat tekoälyllä luotuja kuvituskuvia.")
                }
            }

            // Kelluvan välilehtipalkin alle jää tilaa, ettei viimeinen rivi jää sen alle.
            Section {
                Color.clear
                    .frame(height: 44)
                    .listRowBackground(Color.clear)
            }
            .listSectionSpacing(0)
        }
        .navigationTitle("Reseptit")
        .navigationBarTitleDisplayMode(.inline)
        // Aina näkyvissä: oletuksena hakukenttä piiloutuu vieritettäessä, ja 52
        // reseptin listassa se jäi löytymättä kun se ei ollut ruudulla silloin kun
        // sitä olisi tarvittu.
        .searchable(
            text: $model.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Hae reseptiä"
        )
        .overlay { if model.isLoading && !model.hasContent { ProgressView() } }
        .refreshable { await model.refresh() }
        .sheet(item: $selected) { recipe in
            RecipeDetailSheet(
                recipe: recipe,
                planDate: planDate,
                onLog: { servings, mealTag in
                    await model.logAsEaten(recipe, servings: servings, planDate: planDate, mealTag: mealTag)
                },
                onLogged: {
                    onLogged()
                    // Kirjaus on valmis toiminto, ei selailun välivaihe: käyttäjä haluaa nähdä
                    // rivin päivässään eikä jäädä listaan jossa ei ole enää mitään tekemistä.
                    dismiss()
                },
                onPaywall: { reason in
                    selected = nil
                    paywallReason = PaywallReason(text: reason)
                }
            )
        }
        .sheet(item: $paywallReason) { reason in
            PaywallView(store: subscriptions, reason: reason.text, source: .recipes)
        }
        .task {
            model.configure(auth: auth)
            await model.load()
        }
    }
}

/// Rivillä kaksi lukua, ei viittä: energia ja proteiini ovat ne joilla resepti
/// valitaan. Loput näkyvät avatussa näkymässä.
private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            RecipeThumbnail(url: recipe.imageUrl)

            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(recipe.mealLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(recipe.macrosPerServing.kcal.rounded())) kcal · \(Int(recipe.macrosPerServing.proteinG.rounded())) g proteiinia")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 4)

            // Merkki vain poikkeukselle: avoin resepti on normaalitila eikä
            // ansaitse omaa kuvakettaan.
            if recipe.locked {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Kuuluu Pro-tilaukseen")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RecipeThumbnail: View {
    let url: String?

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.12)
                }
            } else {
                Color.secondary.opacity(0.12)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Maksumuurin syy sheet-kohteena. Oma tyyppi eikä `String`: `Identifiable`in
/// lisääminen standardityyppiin näkyisi koko moduulissa.
struct PaywallReason: Identifiable {
    let text: String
    var id: String { text }
}
