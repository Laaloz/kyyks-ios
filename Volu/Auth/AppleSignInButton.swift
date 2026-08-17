import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

/// Sign in with Apple -painike ja sen nonce-käsittely.
///
/// Nonce estää toistohyökkäyksen: pyyntöön laitetaan satunnaisluvun SHA256, ja
/// Supabaselle lähetetään sama luku raakana. Apple sitoo tiivisteen tokeniin,
/// jolloin toisaalta kaapattua tokenia ei voi käyttää uudelleen ilman
/// alkuperäistä satunnaislukua. Ilman noncea Supabase hylkää tokenin.
struct AppleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let auth: AuthManager
    let onError: (String) -> Void

    @State private var currentNonce: String?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = Self.randomNonce()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            handle(result)
        }
        // Applen ohje: musta vaalealla, valkoinen tummalla. Lukittuna mustaksi
        // painike hukkuisi tummassa ulkoasussa taustaansa.
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                onError("Apple-kirjautuminen ei palauttanut tunnistetta.")
                return
            }

            // Nimi tulee vain ensimmäisellä kerralla, ja osissa. Yhdistetään
            // tässä, koska myöhemmin sitä ei ole enää saatavilla mistään.
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            Task {
                do {
                    try await auth.signInWithApple(
                        idToken: idToken,
                        nonce: nonce,
                        fullName: name.isEmpty ? nil : name
                    )
                } catch {
                    onError("Apple-kirjautuminen epäonnistui: \(error.localizedDescription)")
                }
            }

        case .failure(let error):
            // Käyttäjän oma peruutus ei ole virhe eikä siitä kerrota.
            if (error as? ASAuthorizationError)?.code != .canceled {
                onError("Apple-kirjautuminen epäonnistui.")
            }
        }
    }

    /// Kryptografisesti satunnainen nonce. `SecRandomCopyBytes` eikä
    /// `Int.random`: arvattava nonce tekisi koko suojauksesta näennäisen.
    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
