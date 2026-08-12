import SwiftUI

struct LoginView: View {
    let auth: AuthManager

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("rooki.fit")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(2)
                    .foregroundStyle(.tint)
                Text("Kirjaudu sisään")
                    .font(.largeTitle.bold())
            }

            VStack(spacing: 12) {
                TextField("Sähköposti", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                SecureField("Salasana", text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(action: submit) {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Kirjaudu")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSubmitting || email.isEmpty || password.isEmpty)

            Spacer()
        }
        .padding(24)
        .padding(.top, 48)
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await auth.signIn(email: email, password: password)
            } catch {
                // Jos Supabase vaatii captchan (attack protection), tämä epäonnistuu
                // selvällä virheellä → V0:ssa captcha pois päältä dev-ympäristössä
                // tai hCaptcha-SDK lisätään myöhemmin.
                errorMessage = "Kirjautuminen epäonnistui: \(error.localizedDescription)"
            }
            isSubmitting = false
        }
    }
}
