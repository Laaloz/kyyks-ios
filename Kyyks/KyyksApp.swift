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
                    TabView {
                        TodayView(auth: auth, userId: userId)
                            .tabItem { Label("Tänään", systemImage: "sun.max") }
                        WorkoutsListView(auth: auth, userId: userId)
                            .tabItem { Label("Treeni", systemImage: "dumbbell") }
                        NutritionView(auth: auth)
                            .tabItem { Label("Ravinto", systemImage: "fork.knife") }
                        BodyView(auth: auth)
                            .tabItem { Label("Keho", systemImage: "figure") }
                    }
                }
            }
            .task { auth.bootstrap() }
        }
    }
}
