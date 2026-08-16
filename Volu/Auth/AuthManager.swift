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
