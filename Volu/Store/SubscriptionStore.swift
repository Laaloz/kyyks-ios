import Foundation
import OSLog
import StoreKit

/// Tilaukset ja käyttöoikeus yhdessä paikassa.
///
/// Työnjako: **StoreKit hoitaa ostamisen, palvelin päättää oikeudesta.** Laite
/// lähettää jokaisen Applen allekirjoittaman transaktion palvelimelle, joka
/// varmentaa sen ja johtaa käyttöoikeuden. Tässä pidetty `entitlement` on siis
/// vain käyttöliittymän lukko — todellinen portti on API:n 402-vastaus, joten
/// vanhentunut paikallinen arvo ei voi vuotaa maksullista sisältöä.
@Observable
@MainActor
final class SubscriptionStore {
    /// App Store Connectiin luotavat tuotteet. Nämä on toistaiseksi vain
    /// Config/Volu.storekit-tiedostossa paikallista testausta varten.
    static let productIDs = ["fi.volu.app.pro.monthly", "fi.volu.app.pro.yearly"]

    private(set) var entitlement: Entitlement = .free
    private(set) var subscription: SubscriptionInfo?
    private(set) var products: [Product] = []
    /// Erikseen tyhjästä listasta: `Product.products` palauttaa tuntemattomista
    /// tuotetunnisteista tyhjän listan heittämättä virhettä, joten ilman tätä
    /// näkymä jäisi pyörittämään latausta ikuisesti.
    private(set) var didLoadProducts = false
    /// Oston vaihe. Pelkkä totuusarvo ei riittänyt: oston jälkeen seuraa vielä
    /// palvelimen varmennus, joka kestää oman sekuntinsa, ja siinä välissä
    /// näkymä näytti pysähtyneeltä — käyttäjä ei tiennyt meniko osto läpi.
    enum PurchasePhase: Equatable {
        case idle
        /// StoreKit avaa Applen vahvistusdialogin.
        case purchasing
        /// Osto on tehty, palvelin varmentaa allekirjoituksen ja kirjaa oikeuden.
        case verifying

        var label: String? {
            switch self {
            case .idle: nil
            case .purchasing: "Avataan App Store…"
            case .verifying: "Vahvistetaan tilausta…"
            }
        }
    }

    private(set) var phase: PurchasePhase = .idle
    var isPurchasing: Bool { phase != .idle }
    private(set) var errorMessage: String?

    private var api: APIClient?
    /// Volu-tilin tunniste liitetään ostoon `appAccountToken`ina. Apple
    /// välittää sen takaisin transaktiossa ja ilmoituksissa, jolloin osto on
    /// yhdistettävissä tiliin myös silloin kun laitteen kuittaus ei ole tullut
    /// perille — ja hyvityskiistoissa on näyttöä siitä kuka osti.
    private var accountToken: UUID?
    private var updatesTask: Task<Void, Never>?
    private static let log = Logger(subsystem: "fi.volu.app", category: "store")

    var unlocksPaidFeatures: Bool { entitlement.unlocksPaidFeatures }

    func configure(auth: AuthManager, userId: String) {
        guard api == nil else { return }
        api = APIClient(auth: auth)
        accountToken = UUID(uuidString: userId)

        // Uusiutuminen, palautus ja toisella laitteella tehty osto saapuvat
        // tätä kautta myös silloin kun ostonäkymä ei ole auki — kuuntelija
        // käynnistetään heti, ei vasta maksumuurilla.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    /// Käynnistyksen synkronointi: oikeus palvelimelta ja laitteen tuntemat
    /// voimassa olevat ostot palvelimelle.
    func start() async {
        await refreshEntitlement()
        await syncCurrentEntitlements()
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            // Halvin ensin: kuukausitilaus on matalampi kynnys, vuositilaus
            // esitetään sen rinnalla säästönä.
            products = loaded.sorted { $0.price < $1.price }
            didLoadProducts = true
        } catch {
            Self.log.warning("tuotteiden haku epäonnistui: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Tilausvaihtoehtoja ei saatu haettua. Yritä hetken kuluttua."
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        phase = .purchasing
        errorMessage = nil
        defer { phase = .idle }

        do {
            // Ilman tunnistetta ostoa ei estetä: se on jäljitettävyyttä, ei
            // ehto. Supabasen id on UUID, joten muunnos onnistuu normaalisti.
            let options: Set<Product.PurchaseOption> = accountToken.map { [.appAccountToken($0)] } ?? []
            switch try await product.purchase(options: options) {
            case .success(let verification):
                // Applen dialogi on kuitattu, mutta oikeus ei ole vielä
                // voimassa: se syntyy vasta kun palvelin on varmentanut
                // allekirjoituksen. Vaihe kerrotaan, ettei odotus ole mykkä.
                phase = .verifying
                await handle(verification)
            case .userCancelled:
                break
            case .pending:
                // Esim. Ask to Buy: osto valmistuu myöhemmin ja saapuu
                // Transaction.updates-kuuntelijaan.
                errorMessage = "Osto odottaa hyväksyntää. Pro avautuu, kun se on hyväksytty."
            @unknown default:
                break
            }
        } catch {
            Self.log.warning("osto epäonnistui: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Osto ei onnistunut. Yritä uudelleen."
        }
    }

    /// Palautus: App Store synkronoi ostot laitteelle, minkä jälkeen ne
    /// välitetään palvelimelle samaa polkua kuin uusi osto.
    func restore() async {
        do {
            try await AppStore.sync()
            await syncCurrentEntitlements(force: true)
            await refreshEntitlement()
        } catch {
            errorMessage = "Ostojen palautus ei onnistunut."
        }
    }

    func refreshEntitlement() async {
        guard let api else { return }
        do {
            let data = try await api.get("/api/mobile/profile")
            let response = try JSONDecoder().decode(EntitlementResponse.self, from: data)
            entitlement = response.entitlement ?? .free
            subscription = response.subscription
        } catch {
            // Oikeus on vain käyttöliittymän lukko: verkkovirheestä ei kerrota
            // erikseen, koska mitään ei ollut käyttäjän tekemässä.
            Self.log.info("oikeuden haku epäonnistui: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Käy läpi laitteen voimassa olevat oikeudet ja lähettää palvelimelle vain
    /// ne, joita se ei jo tunne — muuten joka käynnistys tekisi turhan POSTin.
    private func syncCurrentEntitlements(force: Bool = false) async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if force || needsSync(transaction) {
                await handle(result)
            }
        }
    }

    private func needsSync(_ transaction: Transaction) -> Bool {
        guard let stored = subscription, stored.isActive,
              let storedExpiry = stored.expiresAt.flatMap(parseAPIDate),
              let expiry = transaction.expirationDate
        else {
            return true
        }
        // Uusiutuminen siirtää päättymisaikaa eteenpäin → palvelin on jäljessä.
        return expiry > storedExpiry
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            // Laitteen oma varmennus ei mennyt läpi; palvelin hylkäisi saman
            // datan joka tapauksessa.
            Self.log.warning("varmentamaton transaktio ohitettiin")
            return
        }

        if await send(result.jwsRepresentation) {
            // Kuittaus vasta kun palvelin on tallentanut oikeuden: muuten
            // epäonnistunut synkronointi katoaisi jonosta lopullisesti.
            await transaction.finish()
        }
    }

    private func send(_ jws: String) async -> Bool {
        guard let api else { return false }
        struct Body: Encodable { let transaction: String }
        do {
            let data = try await api.post("/api/mobile/subscription", body: Body(transaction: jws))
            let response = try JSONDecoder().decode(EntitlementResponse.self, from: data)
            entitlement = response.entitlement ?? .free
            subscription = response.subscription
            return true
        } catch APIError.status(409) {
            errorMessage = "Tämä tilaus on jo liitetty toiseen Volu-tiliin."
            // Konflikti ei korjaannu yrittämällä uudelleen, joten transaktio
            // kuitataan käsitellyksi.
            return true
        } catch {
            Self.log.warning("tilauksen välitys epäonnistui: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Tilaus ostettiin, mutta sen vahvistus ei mennyt läpi. Kokeile Palauta ostot."
            return false
        }
    }
}

private struct EntitlementResponse: Decodable {
    let entitlement: Entitlement?
    let subscription: SubscriptionInfo?
}
