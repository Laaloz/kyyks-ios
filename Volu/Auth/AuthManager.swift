import Foundation
import Observation
import Supabase

/// Supabase Auth -istunto. supabase-swift säilöö istunnon Keychainiin
/// automaattisesti, joten kylmäkäynnistys ei vaadi verkkokutsua:
/// `bootstrap()` lukee paikallisen istunnon synkronisesti saataville
/// ja token-refresh tapahtuu taustalla vasta tarvittaessa.
@Observable
@MainActor
final class AuthManager {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(userId: String)
    }

    private(set) var state: State = .loading

    let client = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey
    )

    /// Nopea käynnistyspolku: paikallinen istunto Keychainista ilman verkkoa.
    /// currentSession palauttaa myös vanhentuneen istunnon — se riittää UI:n
    /// avaamiseen heti; APIClient hakee tuoreen tokenin (refresh) taustalla.
    func bootstrap() {
        if let session = client.auth.currentSession {
            state = .signedIn(userId: session.user.id.uuidString.lowercased())
        } else {
            state = .signedOut
        }
    }

    func signIn(email: String, password: String, captchaToken: String? = nil) async throws {
        let session = try await client.auth.signIn(
            email: email,
            password: password,
            captchaToken: captchaToken
        )
        state = .signedIn(userId: session.user.id.uuidString.lowercased())
    }

    /// Uusi tili sähköpostilla. Profiili syntyy kannassa triggerillä
    /// (migraatio 072): ilman kutsua rooliksi tulee itsenäinen treenaaja.
    ///
    /// Sähköpostin vahvistusta ei vaadita, joten istunto on käytettävissä
    /// heti. Jos vahvistus kytketään myöhemmin päälle Supabasesta, `session`
    /// on nil eikä käyttäjä pääse sisään ennen linkin klikkausta — siksi
    /// tilaa ei aseteta arvaamalla vaan vain kun istunto oikeasti saatiin.
    func signUp(email: String, password: String, fullName: String) async throws {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: ["full_name": .string(fullName)]
        )
        guard let session = response.session else {
            throw AuthError.confirmationRequired
        }
        state = .signedIn(userId: session.user.id.uuidString.lowercased())
    }

    /// Sign in with Apple. Laite on jo varmentanut käyttäjän, joten tänne tulee
    /// Applen allekirjoittama identiteettitoken — Supabase varmentaa sen Applen
    /// julkisilla avaimilla. Salaisuutta ei tarvita missään vaiheessa.
    ///
    /// `fullName` annetaan vain ensimmäisellä kirjautumisella: Apple palauttaa
    /// nimen kertaalleen valtuutusvastauksessa eikä koskaan enää, eikä se ole
    /// itse tokenissa. Jos sitä ei oteta talteen heti, profiiliin jää nimeksi
    /// sähköpostin alkuosa pysyvästi.
    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws {
        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        state = .signedIn(userId: session.user.id.uuidString.lowercased())
        pendingFullName = fullName
    }

    /// Google kulkee selainvuon kautta: natiivi SDK vaatisi oman riippuvuuden
    /// eikä toisi tähän mitään mitä ASWebAuthenticationSession ei tee.
    func signInWithGoogle() async throws {
        try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: URL(string: "fi.volu.app://login-callback")
        )
        // signInWithOAuth palauttaa vasta kun istunto on tallennettu, joten
        // tila luetaan clientilta eikä paluuarvosta.
        if let session = client.auth.currentSession {
            state = .signedIn(userId: session.user.id.uuidString.lowercased())
        }
    }

    /// Applelta saatu nimi odottamassa profiiliin kirjoitusta. Kirjoitus tehdään
    /// vasta kun istunto on pystyssä, koska se kulkee tavallisen API-kutsun
    /// kautta — ja vain kerran, jotta käyttäjän itse vaihtama nimi ei palaudu.
    private(set) var pendingFullName: String?

    func consumePendingFullName() -> String? {
        defer { pendingFullName = nil }
        return pendingFullName
    }

    enum AuthError: LocalizedError {
        case confirmationRequired

        var errorDescription: String? {
            switch self {
            case .confirmationRequired:
                "Vahvista sähköpostiosoitteesi lähettämästämme linkistä, niin pääset sisään."
            }
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
        state = .signedOut
    }

    /// Voimassa oleva access token API-kutsuihin. supabase-swift
    /// uusii tokenin automaattisesti jos se on vanhentunut.
    func accessToken() async throws -> String {
        try await client.auth.session.accessToken
    }
}
