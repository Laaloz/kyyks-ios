import SwiftUI

@main
struct KyyksApp: App {
    @State private var auth = AuthManager()
    @State private var today = TodayModel()
    @State private var programs = ProgramsModel()
    @State private var subscriptions = SubscriptionStore()
    @State private var selectedTab = Tab.today

    private enum Tab { case today, workouts, nutrition, body }

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
                    // Tänään ja Treeni näyttävät samaa dataa samasta reitistä.
                    // Yhteinen malli: yksi haku kahden sijaan, ja toisessa
                    // välilehdessä tehty kirjaus näkyy heti toisessakin.
                    TabView(selection: $selectedTab) {
                        TodayView(auth: auth, userId: userId, model: today) {
                            selectedTab = .workouts
                        }
                        .tabItem { Label("Tänään", systemImage: "sun.max") }
                        .tag(Tab.today)
                        WorkoutsListView(auth: auth, userId: userId, model: today, programs: programs)
                            .tabItem { Label("Treeni", systemImage: "dumbbell") }
                            .tag(Tab.workouts)
                        NutritionView(auth: auth)
                            .tabItem { Label("Ravinto", systemImage: "fork.knife") }
                            .tag(Tab.nutrition)
                        BodyView(auth: auth)
                            .tabItem { Label("Keho", systemImage: "figure") }
                            .tag(Tab.body)
                    }
                    // Tilaustila haetaan kerran kirjautumisen jälkeen ja
                    // jaetaan ympäristönä: maksumuuri on Ravinnossa, tilauksen
                    // hallinta Profiilissa, eikä kumpikaan omista tilaa.
                    .environment(subscriptions)
                    .task(id: userId) {
                        subscriptions.configure(auth: auth)
                        await subscriptions.start()
                    }
                }
            }
            // Käyttöliittymä on suomeksi, joten päivämäärät ja viikonpäivät
            // muotoillaan suomeksi riippumatta laitteen kielestä — muuten
            // riveillä luki "Tuesday, Aug 11" suomenkielisen tekstin seassa.
            .environment(\.locale, Locale(identifier: "fi_FI"))
            .task { auth.bootstrap() }
        }
    }
}
