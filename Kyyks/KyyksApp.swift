import SwiftUI

@main
struct KyyksApp: App {
    @State private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            Group {
                switch auth.state {
                case .loading:
                    // Näkyy vain mikrosekunteja: bootstrap lukee Keychain-istunnon
                    // ilman verkkoa heti ensimmäisessä taskissa.
                    Color.clear
                case .signedOut:
                    LoginView(auth: auth)
                case .signedIn(let userId):
                    TodayView(auth: auth, userId: userId)
                }
            }
            .task { auth.bootstrap() }
        }
    }
}
