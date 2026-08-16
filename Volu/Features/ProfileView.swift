import StoreKit
import SwiftUI

/// Profiili ja tilin hallinta: makrolaskennan pohjatiedot (pituus, ikä,
/// sukupuoli), uloskirjautuminen ja tilin poisto. Pituus poistettiin aikanaan
/// mittauskirjauksesta kertaluontoisena profiilitietona, joten tämä on ainoa
/// paikka jossa sen voi asettaa.
struct ProfileView: View {
    let auth: AuthManager

    @State private var model = ProfileModel()
    @State private var heightText = ""
    @State private var birthDate = Date()
    /// Onko syntymäaika käyttäjän tai palvelimen asettama. Ilman tätä tyhjä
    /// profiili näyttäisi heti tallennettavalta valitsimen oletusarvolla.
    @State private var hasBirthDate = false
    @State private var ignoreNextBirthDateChange = false
    @State private var sex: String?
    @State private var showDelete = false
    @State private var showPaywall = false
    @State private var showManageSubscriptions = false
    @Environment(SubscriptionStore.self) private var subscriptions
    @FocusState private var focused: Field?

    private enum Field { case height }

    /// 13–100 v, sama haarukka kuin palvelimen validoinnissa.
    static var birthDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let oldest = calendar.date(byAdding: .year, value: -100, to: .now) ?? .distantPast
        let youngest = calendar.date(byAdding: .year, value: -13, to: .now) ?? .now
        return oldest ... youngest
    }

    private var hasChanges: Bool {
        guard let profile = model.profile else { return false }
        return heightText != format(profile.heightCm)
            || (hasBirthDate && Self.isoDay.string(from: birthDate) != (profile.birthDate ?? ""))
            || sex != profile.sex
    }

    var body: some View {
        List {
            if let error = model.errorMessage {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }

            if let profile = model.profile {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.fullName).font(.headline)
                        Text(profile.email)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    LabeledContent("Pituus") {
                        HStack(spacing: 4) {
                            TextField("—", text: $heightText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .focused($focused, equals: .height)
                            Text("cm").foregroundStyle(.secondary)
                        }
                    }
                    // Syntymäaika eikä ikä: ikä vanhenee itsestään, ja
                    // unohtunut päivitys vääristäisi makrolaskennan hiljaa.
                    if hasBirthDate {
                        DatePicker(
                            "Syntymäaika",
                            selection: $birthDate,
                            in: Self.birthDateRange,
                            displayedComponents: .date
                        )
                    } else {
                        // Tyhjä tila omana toimintonaan: pelkkä valitsin
                        // oletusarvolla ei kertoisi onko tieto kirjattu, eikä
                        // oletuspäivää saisi tallennettua (arvo ei muutu).
                        Button {
                            hasBirthDate = true
                        } label: {
                            Label("Lisää syntymäaika", systemImage: "calendar.badge.plus")
                        }
                    }
                    // Ikä vain kun se on johdettu syntymäajasta: ilman
                    // syntymäaikaa näkyvä luku olisi ristiriidassa valitsimen
                    // kanssa eikä kertoisi mistä se tulee.
                    if hasBirthDate, let age = profile.age {
                        LabeledContent("Ikä") {
                            Text("\(age) v")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Picker("Sukupuoli", selection: $sex) {
                        Text("—").tag(String?.none)
                        Text("Nainen").tag(String?.some("female"))
                        Text("Mies").tag(String?.some("male"))
                        Text("Muu").tag(String?.some("other"))
                    }
                } header: {
                    Text("Makrolaskennan tiedot")
                } footer: {
                    if !profile.missingForMacros.isEmpty {
                        Text(missingText(profile.missingForMacros))
                    } else {
                        Text("Perusaineenvaihdunta lasketaan näistä ja tuoreimmasta painosta.")
                    }
                }

                Section {
                    // iOS ei anna sovelluksen muuttaa eikä kysyä uudelleen
                    // Health-oikeuksia: kerran vastattu lupakysely ei toistu.
                    // Ilman tätä riviä käyttäjällä ei ollut mitään polkua
                    // perumiseen tai myöhempään sallimiseen.
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Apple Healthin oikeudet", systemImage: "heart.text.square")
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Askeleet, uni, paino ja muissa sovelluksissa tehdyt suoritukset luetaan Apple Healthista. Oikeudet myönnetään ja perutaan iOS:n asetuksista — sovellus ei voi muuttaa niitä.")
                }

                Section("Muistutukset") {
                    // Muistutus ilmestyy Tänään-välilehdelle pe klo 6 → su.
                    // Sen on oltava kytkettävissä pois samasta paikasta kuin
                    // muutkin omat asetukset.
                    Toggle("Viikoittainen mittausmuistutus", isOn: Binding(
                        get: { model.profile?.weeklyMeasurementReminders ?? true },
                        set: { newValue in Task { await model.setWeeklyReminders(newValue) } }
                    ))
                }

                Section {
                    Picker("Tavoite", selection: Binding(
                        get: { profile.goal ?? "maintain" },
                        set: { newValue in Task { await model.setGoal(newValue, activityLevel: nil) } }
                    )) {
                        Text("Pudota painoa").tag("lose")
                        Text("Pysy nykyisessä").tag("maintain")
                        Text("Kasvata lihasta").tag("gain")
                    }
                    Picker("Aktiivisuus", selection: Binding(
                        get: { profile.activityLevel ?? "moderate" },
                        set: { newValue in Task { await model.setGoal(nil, activityLevel: newValue) } }
                    )) {
                        Text("Kevyt").tag("low")
                        Text("Kohtalainen").tag("moderate")
                        Text("Aktiivinen").tag("high")
                    }
                } header: {
                    Text("Ravintotavoite")
                } footer: {
                    if let kcal = profile.targetKcal {
                        Text("Päivätavoite \(kcal) kcal. Se lasketaan uudelleen aina kun muutat näitä tai painosi muuttuu.")
                    } else {
                        Text("Tavoite lasketaan, kun makrolaskennan tiedot ovat täydelliset.")
                    }
                }

                Section {
                    LabeledContent("Taso") {
                        Text(levelLabel(profile.entitlement ?? .free))
                            .foregroundStyle(.secondary)
                    }
                    if let subscription = profile.subscription, let ends = subscription.expiresAt.flatMap(parseAPIDate) {
                        LabeledContent(subscription.isActive ? "Uusiutuu" : "Päättyi") {
                            Text(ends, format: .dateTime.day().month().year())
                                .foregroundStyle(.secondary)
                        }
                        // Hinnan ja peruutuksen omistaa App Store; sovellus ei
                        // voi eikä saa näyttää omaa peruutuspolkuaan.
                        Button("Hallitse tilausta") { showManageSubscriptions = true }
                    } else if profile.entitlement == .free {
                        Button("Tilaa Volu Pro") { showPaywall = true }
                    }
                } header: {
                    Text("Tilaus")
                } footer: {
                    if profile.entitlement == .coached {
                        Text("Valmentajasi sopimus kattaa Volun käytön — omaa tilausta ei tarvita.")
                    }
                }

                Section("Tili") {
                    Button("Kirjaudu ulos") {
                        Task { await signOut() }
                    }
                    Button("Poista tili", role: .destructive) {
                        showDelete = true
                    }
                }
            }
        }
        .navigationTitle("Profiili")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if model.isLoading && model.profile == nil { ProgressView() } }
        .safeAreaInset(edge: .bottom) {
            // Tallennus ilmestyy vasta kun on jotain tallennettavaa, jottei
            // muuttumaton näkymä näytä keskeneräiseltä.
            if hasChanges {
                Button {
                    focused = nil
                    Task { await save() }
                } label: {
                    Group {
                        if model.isSaving {
                            ProgressView()
                        } else {
                            Text("Tallenna").font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSaving)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
        .sheet(isPresented: $showPaywall, onDismiss: {
            // Osto muuttaa profiilin tason: haetaan se, ettei näkymä jää
            // näyttämään ilmaistasoa juuri ostaneelle.
            Task { await model.refreshAfterChange() }
        }) {
            PaywallView(store: subscriptions, reason: "Avaa AI-ruoka-arvio ja tue kehitystä.")
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .sheet(isPresented: $showDelete) {
            DeleteAccountSheet(auth: auth, email: model.profile?.email ?? "") {
                Task { await signOut() }
            }
        }
        .task {
            model.configure(auth: auth)
            await model.load()
            resetFields()
        }
        .onChange(of: model.profile?.email) { _, _ in resetFields() }
        .onChange(of: birthDate) { _, _ in
            // Ohjelmallinen palautus ei ole käyttäjän valinta.
            if ignoreNextBirthDateChange {
                ignoreNextBirthDateChange = false
            } else {
                hasBirthDate = true
            }
        }
    }

    private func resetFields() {
        guard let profile = model.profile else { return }
        heightText = format(profile.heightCm)
        sex = profile.sex

        let stored = profile.birthDate.flatMap { Self.isoDay.date(from: $0) }
        hasBirthDate = stored != nil
        // Ilman kirjattua syntymäaikaa valitsin avautuu tavanomaiseen
        // aikuisikään; haarukan pää (13 v) olisi lähes aina väärässä.
        let fallback = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
        if birthDate != (stored ?? fallback) {
            ignoreNextBirthDateChange = true
            birthDate = stored ?? fallback
        }
    }

    private func save() async {
        await model.save(
            heightCm: Double(heightText.replacingOccurrences(of: ",", with: ".")),
            birthDate: hasBirthDate ? Self.isoDay.string(from: birthDate) : nil,
            sex: sex
        )
        resetFields()
    }

    /// Päivämäärä ilman aikavyöhykesiirtymää: valitsin antaa paikallisen päivän,
    /// ja UTC-muunnos siirtäisi sen Suomessa edelliselle päivälle.
    static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func signOut() async {
        await ResponseCache.shared.clear()
        await auth.signOut()
    }

    private func levelLabel(_ entitlement: Entitlement) -> String {
        switch entitlement {
        case .free: "Ilmainen"
        case .pro: "Volu Pro"
        case .coached: "Valmennettava"
        }
    }

    private func missingText(_ missing: [String]) -> String {
        let names = missing.map { field in
            switch field {
            case "heightCm": "pituus"
            case "weightKg": "paino"
            case "age": "syntymäaika"
            case "sex": "sukupuoli"
            default: field
            }
        }
        let list = names.joined(separator: ", ")
        return missing == ["weightKg"]
            ? "Makrotavoite tarkentuu, kun kirjaat painon Keho-välilehdellä."
            : "Makrotavoitetta ei voi laskea ilman näitä: \(list)."
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Malli

struct MobileProfile: Decodable {
    let fullName: String
    let email: String
    let role: String
    let heightCm: Double?
    let weightKg: Double?
    let age: Int?
    let birthDate: String?
    let sex: String?
    let goal: String?
    let activityLevel: String?
    let targetKcal: Int?
    let weeklyMeasurementReminders: Bool?
    let missingForMacros: [String]
    let entitlement: Entitlement?
    let subscription: SubscriptionInfo?
}

private struct ProfilePatch: Encodable {
    let heightCm: Double?
    let birthDate: String?
    let sex: String?
}

private struct GoalPatch: Encodable {
    let goal: String?
    let activityLevel: String?
}

private struct ReminderPatch: Encodable {
    let weeklyMeasurementReminders: Bool
}

@Observable
@MainActor
final class ProfileModel: CachedModel {
    private(set) var profile: MobileProfile?
    var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?

    var api: APIClient?
    let cacheKey = "mobile-profile"
    let resourcePath = "/api/mobile/profile"
    let loadFailureMessage = "Profiilin haku epäonnistui."
    var hasContent: Bool { profile != nil }

    func save(heightCm: Double?, birthDate: String?, sex: String?) async {
        guard let api else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await api.patch("/api/mobile/profile", body: ProfilePatch(heightCm: heightCm, birthDate: birthDate, sex: sex))
            await refreshAfterChange()
            errorMessage = nil
        } catch {
            errorMessage = "Tallennus epäonnistui. Tarkista arvot ja yritä uudelleen."
        }
    }

    /// Tavoite ja aktiivisuus tallentuvat heti valinnasta, ja palvelin laskee
    /// makrotavoitteen uudelleen samassa pyynnössä. Erillinen tallennusnappi
    /// jättäisi tilan helposti puolitiehen.
    func setGoal(_ goal: String?, activityLevel: String?) async {
        guard let api else { return }
        do {
            _ = try await api.patch("/api/mobile/profile", body: GoalPatch(goal: goal, activityLevel: activityLevel))
            await refreshAfterChange()
            errorMessage = nil
        } catch {
            errorMessage = "Tavoitteen tallennus epäonnistui."
            await refreshAfterChange()
        }
    }

    /// Kytkin tallentuu heti: erillinen "tallenna" asetuksen päälle olisi
    /// ylimääräinen vaihe, jonka unohtaminen jättäisi asetuksen väärään tilaan.
    func setWeeklyReminders(_ isOn: Bool) async {
        guard let api else { return }
        do {
            _ = try await api.patch("/api/mobile/profile", body: ReminderPatch(weeklyMeasurementReminders: isOn))
            await refreshAfterChange()
            errorMessage = nil
        } catch {
            errorMessage = "Asetuksen tallennus epäonnistui."
            await refreshAfterChange()
        }
    }

    func apply(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(MobileProfile.self, from: data) else { return }
        profile = decoded
    }
}
