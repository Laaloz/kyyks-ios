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
    let onLogged: () async -> Void

    @State private var model = RecipeLibraryModel()
    @State private var selected: Recipe?
    @State private var paywallReason: PaywallReason?
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Kaksi saraketta, jotta selattavaa näkyy kerralla 6–8 eikä 2–3. Saavutettavuuden
    /// tekstiko'oilla yksi: kapeaan korttiin ei mahdu nimeä eikä lukuja.
    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = model.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }

                // Suodatin chipeinä: yksi napautus, ja kaikki vaihtoehdot näkyvät kerralla.
                // Valittu chip on neutraali — korostusväri kuuluu toiminnoille, ei arvoille.
                MealFilterChips(selection: $model.mealFilter)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(model.visibleRecipes) { recipe in
                        Button {
                            selected = recipe
                        } label: {
                            RecipeCard(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                if model.visibleRecipes.isEmpty, model.hasContent {
                    Text("Ei osumia haulla.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

                // Alaviite on oikea paikka juuri tälle: tieto ei ole sellaista jota
                // etsitään, mutta se pitää olla kerrottuna.
                if model.hasContent {
                    Text("Reseptikuvat ovat tekoälyllä luotuja kuvituskuvia.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 4)
            // Kelluvan välilehtipalkin alle jää tilaa, ettei viimeinen rivi jää sen alle.
            .padding(.bottom, 44)
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
                onLog: { servings, mealTag, swaps in
                    await model.logAsEaten(recipe, servings: servings, planDate: planDate, mealTag: mealTag, swaps: swaps)
                },
                onLogged: {
                    await onLogged()
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

/// Kuvakortti: ruoka valitaan katsomalla, joten kuva on kortin pääosa. Alla nimi ja
/// kaksi lukua — energia ja proteiini ovat ne joilla resepti valitaan, loput näkyvät
/// avatussa näkymässä. Ateriatyyppi ei mahdu kapeaan korttiin, ja suodatin kertoo sen.
private struct RecipeCard: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    if let url = recipe.imageUrl, let parsed = URL(string: url) {
                        AsyncImage(url: parsed) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.12)
                        }
                    } else {
                        Color.secondary.opacity(0.12)
                            .overlay {
                                Image(systemName: "fork.knife")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                // Merkki vain poikkeukselle: avoin resepti on normaalitila.
                .overlay(alignment: .topTrailing) {
                    if recipe.locked {
                        Image(systemName: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                            .accessibilityLabel("Kuuluu Pro-tilaukseen")
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(Int(recipe.macrosPerServing.kcal.rounded())) kcal · \(Int(recipe.macrosPerServing.proteinG.rounded())) g prot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .accessibilityLabel("\(Int(recipe.macrosPerServing.kcal.rounded())) kilokaloria, \(Int(recipe.macrosPerServing.proteinG.rounded())) grammaa proteiinia")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct MealFilterChips: View {
    @Binding var selection: MealSlotGroup?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Kaikki", isOn: selection == nil) { selection = nil }
                ForEach(MealSlotGroup.allCases) { group in
                    chip(group.label, isOn: selection == group) { selection = group }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isOn ? Color(.systemBackground) : Color.primary)
                .background(isOn ? Color.primary : Color.secondary.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Maksumuurin syy sheet-kohteena. Oma tyyppi eikä `String`: `Identifiable`in
/// lisääminen standardityyppiin näkyisi koko moduulissa.
struct PaywallReason: Identifiable {
    let text: String
    var id: String { text }
}
