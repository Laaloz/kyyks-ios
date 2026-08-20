import OSLog
import SwiftUI
import UIKit
import UserNotifications

/// APNs-tunniste saapuu UIKitin delegaattimetodiin, jolle SwiftUI:ssa ei ole
/// vastinetta — siksi sovelluksella on delegaatti pelkästään tätä varten.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Asetetaan heti kun App-rakenne on pystyssä; delegaatti ei omista
    /// tilaa vaan välittää tunnisteen eteenpäin.
    static weak var push: PushManager?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Ilman tätä iOS vaimentaa ilmoituksen aina kun sovellus on edessä.
        // Viikkomuistutus tulee kerran viikossa eikä kilpaile mistään, joten
        // sen vaimentaminen tarkoittaisi käytännössä sen menettämistä.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in Self.push?.register(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Simulaattorissa ja ilman kehittäjätiliä tämä on odotettu tulos:
        // ilmoitukset eivät toimi, muu sovellus toimii normaalisti.
        Logger(subsystem: "fi.volu.app", category: "push")
            .warning("APNs-rekisteröinti epäonnistui: \(error.localizedDescription, privacy: .public)")
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Näytä muistutus myös edessä olevassa sovelluksessa. Ilman ääntä:
    /// käyttäjä katsoo jo ruutua, joten pelkkä palkki riittää.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    /// Napautus vie sinne mitä ilmoitus koski. Ilman tätä muistutus avaa vain
    /// viimeksi auki olleen välilehden, jolloin käyttäjä saa kehotuksen kirjata
    /// mittaus ja joutuu etsimään lomakkeen itse.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let target = response.notification.request.content.userInfo["target"] as? String
        await MainActor.run { NotificationRouter.shared.handle(target: target) }
    }
}

@main
struct VoluApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth = AuthManager()
    @State private var today = TodayModel()
    @State private var programs = ProgramsModel()
    @State private var subscriptions = SubscriptionStore()
    @State private var push = PushManager()
    /// Health kuuluu juureen kuten muutkin jaetut mallit: Tänään lukee siitä
    /// askeleet, Profiili omistaa vientiasetuksen ja Treeni kirjoittaa valmiin
    /// treenin. Kaksi erillistä `HKHealthStore`a näkisi lupatilan eri hetkinä.
    @State private var health = HealthManager()
    /// Lepoajastin kuuluu juureen eikä treeninäkymään: lepo jatkuu kun käyttäjä
    /// käy toisella välilehdellä, ja palkin on näyttävä siellä missä hän on —
    /// muuten ainoa jäljelle jäävä merkki levosta on ilmoitus, jota ei voi perua.
    @State private var restTimer = RestTimerManager()
    /// Puuttuvat makrotiedot = aloituskysely on tekemättä. Palvelin kertoo
    /// listan, joten sääntö on yhdessä paikassa eikä arvattuna kahdessa.
    @State private var needsOnboarding = false
    /// Kyselyn nimikentän esitäyttö — rekisteröinnin johtama nimi, jonka
    /// käyttäjä saa korjata (Applen relay-osoitteesta tulee satunnainen).
    @State private var onboardingName = ""
    @State private var selectedTab = Tab.today
    /// Ulkoasu pakotetaan sovelluksen juuressa, jotta se koskee myös
    /// sheettejä ja kirjautumisnäkymää — ei vain välilehtiä.
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.system
    /// Korostusväri samasta paikasta samasta syystä kuin ulkoasu: sheetit ja
    /// kirjautumisnäkymä ovat oman esityksensä juuria, eivätkä perisi sitä
    /// välilehdiltä.
    @AppStorage(AccentSetting.storageKey) private var accent = AccentSetting.green
    /// Onko juuren jaetuissa malleissa jonkun käyttäjän dataa. Uloskirjautuminen
    /// ei pura App-rakennetta, joten ilman nollausta saman ajon seuraava
    /// kirjautuja näkisi edellisen nimen, treenit ja suoritukset muistista
    /// (hasLoaded esti uudelleenlatauksenkin).
    @State private var modelsUserId: String?

    private enum Tab { case today, workouts, nutrition, body }

    /// Aloituskysely näytetään vain kun makrolaskennan tiedot puuttuvat.
    /// Verkkovirheessä sitä ei näytetä: kyselyn väläyttäminen olemassa
    /// olevalle käyttäjälle olisi pahempi haitta kuin sen viivästyminen.
    private func checkOnboarding() async {
        struct Profile: Decodable {
            let missingForMacros: [String]
            let fullName: String
        }
        guard let data = try? await APIClient(auth: auth).get("/api/mobile/profile"),
              let profile = try? JSONDecoder().decode(Profile.self, from: data)
        else { return }
        onboardingName = profile.fullName
        needsOnboarding = !profile.missingForMacros.isEmpty
    }

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
                        // Jaetut mallit nollataan täällä eikä kirjautumisessa:
                        // kirjautumisen puolella nollaus kilpailisi välilehtien
                        // omien .task-latausten kanssa (uusi malli voisi jäädä
                        // lataamatta, koska näkymän identiteetti ei vaihdu).
                        // Tässä TabView on jo purettu, joten järjestys on taattu.
                        .onAppear {
                            guard modelsUserId != nil else { return }
                            modelsUserId = nil
                            today = TodayModel()
                            programs = ProgramsModel()
                        }
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
                    // Identiteetti käyttäjästä: välilehtien omat @State-mallit
                    // (Ravinto, Keho, Profiili) luodaan uudelleen kun käyttäjä
                    // vaihtuu, eikä niiden tarvitse itse siivota mitään.
                    .id(userId)
                    .environment(subscriptions)
                    .environment(health)
                    .environment(restTimer)
                    .environment(push)
                    .environment(NotificationRouter.shared)
                    // Välilehden vaihto tässä, lomakkeen avaus Kehossa: näkymä
                    // omistaa oman sheettinsä, eikä sitä kannata ohjata ulkoa.
                    .onChange(of: NotificationRouter.shared.target) {
                        if NotificationRouter.shared.target == "measurement" { selectedTab = .body }
                    }
                    .task(id: userId) {
                        modelsUserId = userId
                        subscriptions.configure(auth: auth, userId: userId)
                        await subscriptions.start()
                    }
                    // Push-lupa kysytään vasta kirjautuneelta: ilmoitus koskee
                    // omia mittauksia, joten kysely ennen kirjautumista olisi
                    // vailla kontekstia.
                    .task(id: userId) {
                        AppDelegate.push = push
                        push.configure(auth: auth)
                        await push.requestAuthorizationIfNeeded()
                    }
                    .fullScreenCover(isPresented: $needsOnboarding) {
                        OnboardingView(auth: auth, initialName: onboardingName) {
                            needsOnboarding = false
                            Task {
                                await today.refreshAfterChange()
                            }
                        }
                    }
                    .task(id: userId) {
                        await checkOnboarding()
                    }
                    // Applen antama nimi talteen heti ensimmäisen kirjautumisen
                    // jälkeen: Apple ei palauta sitä toista kertaa, joten tämä
                    // on ainoa hetki jolloin profiiliin saa oikean nimen.
                    .task(id: userId) {
                        guard let name = auth.consumePendingFullName() else { return }
                        struct Patch: Encodable { let fullName: String }
                        _ = try? await APIClient(auth: auth)
                            .patch("/api/mobile/profile", body: Patch(fullName: name))
                        await today.refreshAfterChange()
                    }
                }
            }
            // Käyttöliittymä on suomeksi, joten päivämäärät ja viikonpäivät
            // muotoillaan suomeksi riippumatta laitteen kielestä — muuten
            // riveillä luki "Tuesday, Aug 11" suomenkielisen tekstin seassa.
            .environment(\.locale, Locale(identifier: "fi_FI"))
            // Ulkoasu juuressa: koskee myös sheettejä ja kirjautumisnäkymää.
            .preferredColorScheme(appearance.colorScheme)
            .tint(accent.color)
            .task { auth.bootstrap() }
        }
    }
}
