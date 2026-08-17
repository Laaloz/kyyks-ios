import SwiftUI

/// Salasanan palautuksen pyyntö.
///
/// Pyyntö tehdään sovelluksessa eikä selaimessa: aiempi versio avasi webin
/// kirjautumissivun, jolloin käyttäjä joutui painamaan "Unohditko salasanasi?"
/// uudelleen toisessa näkymässä. Se näyttää siltä kuin jotain olisi mennyt
/// pieleen.
///
/// Uuden salasanan asettaminen tapahtuu edelleen sähköpostin linkistä
/// selaimessa — se on mobiilissa vakiintunut työnjako, ja vain pyyntö kuuluu
/// sovellukseen.
struct PasswordResetSheet: View {
    let auth: AuthManager
    /// Kirjautumisnäkymään kirjoitettu osoite; harvoin kannattaa kysyä
    /// uudelleen jotain minkä käyttäjä juuri kirjoitti.
    var prefilledEmail: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isSending = false
    @State private var sentMessage: String?
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.count >= 5
    }

    var body: some View {
        NavigationStack {
            Form {
                if let sentMessage {
                    Section {
                        Label(sentMessage, systemImage: "envelope.badge")
                            .font(.subheadline)
                    } footer: {
                        Text("Linkki vanhenee tunnin kuluttua. Tarkista myös roskapostikansio.")
                    }
                } else {
                    Section {
                        TextField("Sähköposti", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isFocused)
                    } footer: {
                        Text("Lähetämme osoitteeseen linkin, jolla voit asettaa uuden salasanan.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Salasanan palautus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sentMessage == nil ? "Peru" : "Valmis") { dismiss() }
                }
                if sentMessage == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        SaveToolbarButton("Lähetä", isSaving: isSending, isEnabled: canSend) {
                            Task { await send() }
                        }
                    }
                }
            }
            .task {
                email = prefilledEmail
                // Kohdistus vain kun kenttä on tyhjä: valmiiksi täytetyn
                // kentän päälle avautuva näppäimistö peittää vahvistustekstin.
                if email.isEmpty { isFocused = true }
            }
        }
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        struct Body: Encodable { let email: String }
        do {
            // Ilman istuntoa: käyttäjä on kirjautumisnäkymässä eikä tokenia ole.
            _ = try await APIClient(auth: auth).postWithoutSession(
                "/api/mobile/password-reset",
                body: Body(email: email.trimmingCharacters(in: .whitespaces))
            )
            // Palvelin vastaa saman viestin riippumatta siitä onko tiliä
            // olemassa, joten näkymä ei voi paljastaa sitä vahingossakaan.
            sentMessage = "Jos osoitteella on tili, lähetimme sinne palautuslinkin."
        } catch {
            errorMessage = (error as? APIError)?.serverMessage
                ?? "Lähetys epäonnistui — yritä uudelleen."
        }
    }
}
