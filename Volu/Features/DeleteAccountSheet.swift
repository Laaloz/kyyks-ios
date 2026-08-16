import SwiftUI

/// Tilin poisto omana näkymänään: peruuttamaton toiminto kertoo mitä katoaa ja
/// vaatii sähköpostin kirjoittamisen — napautus ei ole riittävä tunniste.
struct DeleteAccountSheet: View {
    let auth: AuthManager
    let email: String
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var canDelete: Bool {
        confirmation.trimmingCharacters(in: .whitespaces).lowercased() == email.lowercased()
            && !email.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Tilin poisto on peruuttamaton. Treenit, sarjakirjaukset, mittaukset ja ravintokirjaukset poistetaan pysyvästi, eikä niitä voi palauttaa.")
                }

                Section {
                    TextField(email, text: $confirmation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                } header: {
                    Text("Vahvistus")
                } footer: {
                    Text("Kirjoita sähköpostiosoitteesi \(email) vahvistaaksesi poiston.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Poista tili")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peruuta") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await delete() }
                } label: {
                    Group {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Poista tili pysyvästi").font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!canDelete || isDeleting)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
        .interactiveDismissDisabled(isDeleting)
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await APIClient(auth: auth).delete("/api/mobile/account", body: DeleteAccountRequest(confirmEmail: email))
            dismiss()
            onDeleted()
        } catch {
            errorMessage = "Tilin poisto epäonnistui. Yritä uudelleen."
        }
    }
}

private struct DeleteAccountRequest: Encodable {
    let confirmEmail: String
}
