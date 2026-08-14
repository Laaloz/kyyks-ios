import StoreKit
import SwiftUI

/// Tilausnäkymä. Avataan siitä kohdasta jossa lukko tuli vastaan, jotta
/// käyttäjä näkee mitä oli tekemässä — ei erillisenä mainoksena.
struct PaywallView: View {
    let store: SubscriptionStore
    /// Mikä toiminto törmäsi lukkoon; kerrotaan otsikon alla.
    var reason = "AI-ruoka-arvio kuuluu Pro-tilaukseen."

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Product?

    /// Applen vakioehdot: tilaussovelluksen on linkitettävä käyttöehtoihin.
    private static let eulaURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kyyks Pro").font(.title2.bold())
                        Text(reason).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Pro sisältää") {
                    benefit("Ruoka-arvio kuvasta", "camera.viewfinder")
                    benefit("Makrot ruoan nimestä", "sparkles")
                    benefit("Kaikki muu Kyyks jatkuu ennallaan", "checkmark.circle")
                }

                if store.products.isEmpty {
                    Section {
                        if store.didLoadProducts {
                            // Tuotteet puuttuvat App Storesta (tai .storekit-
                            // konfiguraatiota ei ole ladattu kehityksessä).
                            Text("Tilausvaihtoehtoja ei juuri nyt saatu App Storesta. Yritä hetken kuluttua uudelleen.")
                                .foregroundStyle(.secondary)
                        } else {
                            HStack {
                                ProgressView()
                                Text("Haetaan vaihtoehtoja…").foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Section("Valitse tilaus") {
                        ForEach(store.products, id: \.id) { product in
                            Button {
                                selected = product
                            } label: {
                                LabeledContent {
                                    Text(product.displayPrice).monospacedDigit()
                                } label: {
                                    // Jakso on kerrottava hinnan vierellä: pelkkä
                                    // summa ei kerro onko se kuukausi vai vuosi.
                                    Text(periodLabel(product))
                                }
                            }
                            .tint(.primary)
                            // Merkki vain valitulle riville, ei kaikille.
                            .listRowBackground(product.id == selected?.id ? Color.accentColor.opacity(0.12) : nil)
                        }
                    }
                }

                Section {
                    Button("Palauta ostot") {
                        Task { await store.restore() }
                    }
                    Link("Käyttöehdot", destination: Self.eulaURL)
                } footer: {
                    Text("Tilaus uusiutuu automaattisesti, ellei sitä peruta vähintään vuorokautta ennen jakson päättymistä. Hallinta ja peruutus tapahtuvat App Storen tilausasetuksissa.")
                }

                if let error = store.errorMessage {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Tilaus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sulje") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let product = selected {
                    Button {
                        Task {
                            await store.purchase(product)
                            if store.unlocksPaidFeatures { dismiss() }
                        }
                    } label: {
                        Group {
                            if store.isPurchasing {
                                ProgressView()
                            } else {
                                Text("Tilaa \(product.displayPrice)").font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isPurchasing)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .background(.bar)
                }
            }
            .task {
                await store.loadProducts()
                // Halvin vaihtoehto valmiiksi valituksi: näkymä ei jää
                // toimettomaksi, mutta valinta on silti käyttäjän.
                if selected == nil { selected = store.products.first }
            }
        }
    }

    private func benefit(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
    }

    private func periodLabel(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayName }
        let count = period.value
        switch period.unit {
        case .month: return count == 1 ? "Kuukausi" : "\(count) kk"
        case .year: return count == 1 ? "Vuosi" : "\(count) v"
        case .week: return count == 1 ? "Viikko" : "\(count) vk"
        case .day: return count == 1 ? "Päivä" : "\(count) pv"
        @unknown default: return product.displayName
        }
    }
}
