import SwiftUI

/// Aloituskysely: kerätään kerralla se mitä makrotavoite tarvitsee.
///
/// Ilman tätä itse rekisteröitynyt käyttäjä tippui suoraan Tänään-välilehdelle,
/// jossa Ravinto-puoli oli hiljaa rikki — makrotavoitetta ei voinut laskea eikä
/// tavoitetta (pudota/pysy/kasvata) valita mistään.
///
/// Yksi vieritettävä lomake eikä monivaiheinen velho: kysymyksiä on kuusi,
/// ja vaiheistus tekisi lyhyestä täytöstä pidemmän tuntuisen.
struct OnboardingView: View {
    let auth: AuthManager
    let onFinished: () -> Void

    @State private var goal = "maintain"
    @State private var activityLevel = "moderate"
    @State private var sex: String?
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    private enum Field { case height, weight }

    private var canSubmit: Bool {
        sex != nil && parsed(heightText) != nil && parsed(weightText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Näillä lasketaan päivittäinen kalori- ja makrotavoitteesi. Voit muuttaa niitä myöhemmin profiilista.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Tavoite") {
                    Picker("Tavoite", selection: $goal) {
                        Text("Pudota painoa").tag("lose")
                        Text("Pysy nykyisessä").tag("maintain")
                        Text("Kasvata lihasta").tag("gain")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    HStack(spacing: 4) {
                        Text("Pituus")
                        TextField("—", text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($focused, equals: .height)
                        Text("cm").foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("Paino")
                        TextField("—", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($focused, equals: .weight)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    DatePicker(
                        "Syntymäaika",
                        selection: $birthDate,
                        in: ProfileView.birthDateRange,
                        displayedComponents: .date
                    )
                    Picker("Sukupuoli", selection: $sex) {
                        Text("Valitse").tag(String?.none)
                        Text("Nainen").tag(String?.some("female"))
                        Text("Mies").tag(String?.some("male"))
                        Text("Muu").tag(String?.some("other"))
                    }
                } header: {
                    Text("Perustiedot")
                } footer: {
                    // Sukupuoli vaikuttaa perusaineenvaihdunnan kaavaan, joten
                    // sen kysyminen on syytä perustella.
                    Text("Sukupuolta käytetään vain perusaineenvaihdunnan laskentaan.")
                }

                Section {
                    Picker("Aktiivisuus", selection: $activityLevel) {
                        Text("Kevyt").tag("low")
                        Text("Kohtalainen").tag("moderate")
                        Text("Aktiivinen").tag("high")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Arki treenien ulkopuolella")
                } footer: {
                    Text(activityDescription)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Aloitetaan")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: submit) {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Laske tavoitteeni").font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || !canSubmit)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
        .interactiveDismissDisabled()
    }

    private var activityDescription: String {
        switch activityLevel {
        case "low": "Istumatyö ja vähän liikkumista päivän aikana."
        case "high": "Liikkuva työ tai paljon arkiaktiivisuutta."
        default: "Jonkin verran kävelyä ja arkiliikuntaa."
        }
    }

    private func parsed(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func submit() {
        guard !isSaving, canSubmit else { return }
        focused = nil
        isSaving = true
        errorMessage = nil

        struct Body: Encodable {
            let heightCm: Double
            let weightKg: Double
            let birthDate: String
            let sex: String
            let goal: String
            let activityLevel: String
        }

        Task {
            do {
                _ = try await APIClient(auth: auth).post("/api/mobile/onboarding", body: Body(
                    heightCm: parsed(heightText) ?? 0,
                    weightKg: parsed(weightText) ?? 0,
                    birthDate: ProfileView.isoDay.string(from: birthDate),
                    sex: sex ?? "other",
                    goal: goal,
                    activityLevel: activityLevel
                ))
                onFinished()
            } catch {
                // "Tarkista arvot" on huono neuvo kun vika ei ole arvoissa.
                // Palvelin nimeää puuttuvan tiedon, joten sen viesti kertoo
                // käyttäjälle mitä oikeasti pitää korjata.
                errorMessage = (error as? APIError)?.serverMessage
                    ?? "Tallennus epäonnistui. Tarkista arvot ja yritä uudelleen."
            }
            isSaving = false
        }
    }
}
