import SwiftUI

/// Kirjautuminen ja rekisteröityminen samassa näkymässä.
///
/// Kaksi erillistä näkymää olisi tarkoittanut, että käyttäjä joutuu ensin
/// päättämään kumpi hän on ja vasta sitten näkee kentät. Yhdellä näkymällä
/// kentät ovat aina näkyvissä ja tila vaihtuu yhdellä napautuksella — sama
/// malli kuin useimmissa nykysovelluksissa.
///
/// Rekisteröityminen on olemassa siksi, että ilman sitä App Storesta ladannut
/// käyttäjä törmää kirjautumisnäyttöön johon hänellä ei ole tunnuksia. Kutsu
/// on yhä valmennettavan polku, mutta se ei voi olla ainoa.
struct LoginView: View {
    let auth: AuthManager

    private enum Mode {
        case signIn
        case signUp

        var title: String { self == .signIn ? "Tervetuloa takaisin" : "Luo tili" }
        var action: String { self == .signIn ? "Kirjaudu" : "Luo tili" }
        var switchPrompt: String {
            self == .signIn ? "Etkö ole vielä käyttäjä?" : "Onko sinulla jo tili?"
        }
        var switchAction: String { self == .signIn ? "Luo tili" : "Kirjaudu" }
    }

    @State private var mode: Mode = .signIn
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @FocusState private var focused: Field?

    private enum Field { case name, email, password }

    private var canSubmit: Bool {
        guard !email.isEmpty, password.count >= 6 else { return false }
        return mode == .signIn || fullName.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        // Pystysuunnassa keskitetty, mutta vieritettävä: `minHeight` säiliön
        // korkeuteen keskittää sisällön kun se mahtuu, ja antaa sen kasvaa
        // yli kun näppäimistö nousee tai rekisteröinnin lisäkenttä ilmestyy.
        // Kiinteä korkeus leikkaisi sisällön juuri niissä tilanteissa.
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
                header

                VStack(spacing: 12) {
                    if mode == .signUp {
                        field("Nimi", text: $fullName, field: .name) {
                            $0.textContentType(.name)
                                .textInputAutocapitalization(.words)
                        }
                    }

                    field("Sähköposti", text: $email, field: .email) {
                        $0.textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    secureField
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }

                Button(action: submit) {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(mode.action).font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(isSubmitting || !canSubmit)

                switcher

                if mode == .signUp {
                    // Tilaus- ja tietosuojaehdot on kerrottava ennen tilin
                    // luontia, ei vasta sen jälkeen.
                    Text("Luomalla tilin hyväksyt tietojesi käsittelyn tietosuojaselosteen mukaisesti.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Tietosuojaseloste", destination: URL(string: "https://volu.fi/privacy")!)
                        .font(.caption.weight(.semibold))
                }
            }
        .padding(24)
        .animation(.snappy(duration: 0.25), value: mode)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VOLU")
                .font(.title3.weight(.heavy))
                .kerning(4)
                .foregroundStyle(.tint)
            Text(mode.title)
                .font(.largeTitle.bold())
                .contentTransition(.opacity)
            Text("Treenit, ravinto ja kehitys samassa paikassa.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var switcher: some View {
        HStack(spacing: 6) {
            Text(mode.switchPrompt)
                .foregroundStyle(.secondary)
            Button(mode.switchAction) {
                // Virheilmoitus kuuluu edelliseen yritykseen, ei uuteen tilaan.
                errorMessage = nil
                mode = mode == .signIn ? .signUp : .signIn
            }
            .font(.subheadline.weight(.semibold))
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
    }

    private var secureField: some View {
        SecureField("Salasana", text: $password)
            .textContentType(mode == .signIn ? .password : .newPassword)
            .focused($focused, equals: .password)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
            .onSubmit(submit)
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        field: Field,
        modifiers: (TextField<Text>) -> some View
    ) -> some View {
        modifiers(TextField(title, text: text))
            .focused($focused, equals: field)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func submit() {
        guard !isSubmitting, canSubmit else { return }
        focused = nil
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                switch mode {
                case .signIn:
                    try await auth.signIn(email: email, password: password)
                case .signUp:
                    try await auth.signUp(
                        email: email,
                        password: password,
                        fullName: fullName.trimmingCharacters(in: .whitespaces)
                    )
                }
            } catch {
                errorMessage = message(for: error)
            }
            isSubmitting = false
        }
    }

    /// Supabasen virheet ovat englanniksi ja teknisiä. Tavallisimmat
    /// käännetään; muut näytetään sellaisenaan, ettei todellinen syy katoa.
    private func message(for error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("invalid login") || raw.contains("invalid credentials") {
            return "Sähköposti tai salasana ei täsmää."
        }
        if raw.contains("already registered") || raw.contains("already been registered") {
            return "Tällä sähköpostilla on jo tili. Kirjaudu sisään."
        }
        if raw.contains("password") && raw.contains("6") {
            return "Salasanassa on oltava vähintään 6 merkkiä."
        }
        if raw.contains("captcha") {
            return "Kirjautuminen vaatii varmistuksen. Kokeile hetken kuluttua uudelleen."
        }
        return error.localizedDescription
    }
}
