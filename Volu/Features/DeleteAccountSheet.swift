import SwiftUI

/// Tilin poisto omana näkymänään: peruuttamaton toiminto kertoo mitä katoaa ja
/// vaatii kirjoitetun vahvistuksen — napautus ei ole riittävä tunniste.
///
/// Vahvistus on kiinteä sana eikä käyttäjän sähköposti. Apple-kirjautuja saa
/// halutessaan piilotetun osoitteen (`…@privaterelay.appleid.com`), joka on
/// satunnaismerkkijono jota hän ei ole koskaan nähnyt — sen jäljentäminen
/// merkki kerrallaan ruudulta ei tee poistosta harkittua vaan hankalaa, ja
/// Applen oma ohje vaatii että poiston saa vietyä loppuun vaivatta. Osoite
/// näytetään silti, jotta käyttäjä näkee minkä tilin on poistamassa.
struct DeleteAccountSheet: View {
    let auth: AuthManager
    let email: String
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    /// Kiinteä vahvistussana. Vertailu on kirjainkoosta riippumaton ja sietää
    /// välilyönnit: tarkoitus on estää vahinko, ei tavata oikein.
    private static let confirmWord = "POISTA"

    private var canDelete: Bool {
        // Sähköposti on yhä ehto, vaikkei sitä enää kirjoiteta: pyyntö lähettää
        // sen palvelimelle, ja tyhjänä poisto kaatuisi 400:aan näkymässä joka
        // kertoisi vain "yritä uudelleen". Tyhjä tarkoittaa että profiili on
        // vielä latautumatta.
        !email.isEmpty
            && confirmation.trimmingCharacters(in: .whitespaces)
                .caseInsensitiveCompare(Self.confirmWord) == .orderedSame
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Tilin poisto on peruuttamaton. Treenit, sarjakirjaukset, mittaukset ja ravintokirjaukset poistetaan pysyvästi, eikä niitä voi palauttaa.")
                } footer: {
                    // Kerrotaan mikä tili on kyseessä: Apple-kirjautujalla
                    // osoite voi olla piilotettu eikä hänen omansa.
                    if !email.isEmpty {
                        Text("Poistettava tili: \(email)")
                    }
                }

                Section {
                    TextField(Self.confirmWord, text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Vahvistus")
                } footer: {
                    Text("Kirjoita \(Self.confirmWord) vahvistaaksesi poiston.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Poista tili")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peruuta") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await delete() }
                } label: {
                    Group {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Poista tili pysyvästi").font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .prominentButtonLabel()
                .tint(.red)
                .disabled(!canDelete || isDeleting)
                .padding(.horizontal, 16)
                // Väli myös ylös, kuten Ravinnossa: ilman sitä tausta alkaa
                // napin reunasta ja näyttää irralliselta kaistaleelta.
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
        .interactiveDismissDisabled(isDeleting)
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await APIClient(auth: auth).delete("/api/mobile/account", body: DeleteAccountRequest(confirmEmail: email))
            dismiss()
            onDeleted()
        } catch {
            errorMessage = "Tilin poisto epäonnistui. Yritä uudelleen."
        }
    }
}

private struct DeleteAccountRequest: Encodable {
    let confirmEmail: String
}
