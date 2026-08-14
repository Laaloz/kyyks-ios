import SwiftUI

/// Ohjelman luonti apissa: valmis pohja tai tyhjä runko, jota muokataan.
/// Itsenäisellä treenaajalla ei ole valmentajaa, joten ilman tätä hänellä ei ole
/// mitään mitä seurata — ja koko treenin aloitus nojaa ohjelmaan.
struct CreateProgramView: View {
    let auth: AuthManager
    let userId: String
    /// Jaettu aloitusvalitsimen kanssa: nykyinen ohjelma on välimuistissa,
    /// joten se on ruudulla heti eikä vasta verkkokutsun jälkeen.
    let programs: ProgramsModel
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = CreateProgramModel()
    @State private var draft: ProgramDraft?
    /// Muokattavan ohjelman id. nil = uusi ohjelma.
    @State private var editingProgramId: String?
    @State private var pendingRemoval: Program?

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    ProgramDraftEditor(
                        auth: auth,
                        draft: Binding(get: { draft }, set: { self.draft = $0 }),
                        isSaving: model.isSaving,
                        errorMessage: model.errorMessage,
                        // Nykyistä ohjelmaa ei tarvitse ottaa käyttöön; muissa
                        // tapauksissa käyttöönotto on erillinen valinta.
                        isEditingActiveProgram: editingProgramId != nil && editingProgramId == programs.activeProgram?.id
                    ) { activate in
                        Task {
                            if await model.save(
                                draft: draft,
                                athleteId: userId,
                                programId: editingProgramId,
                                activate: activate
                            ) {
                                onCreated()
                                dismiss()
                            }
                        }
                    }
                } else {
                    templatePicker
                }
            }
            .navigationTitle(draft == nil ? "Oma ohjelma" : (editingProgramId == nil ? "Uusi ohjelma" : "Muokkaa ohjelmaa"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peru") {
                        // Pohjavalinnasta palataan taaksepäin, ei ulos: väärän
                        // pohjan valinta ei saa heittää alkuun asti.
                        if draft == nil {
                            dismiss()
                        } else {
                            draft = nil
                            editingProgramId = nil
                        }
                    }
                }
            }
        }
        .task {
            model.configure(auth: auth)
            programs.configure(auth: auth)
            await model.load()
        }
    }

    /// Arkistoidun rivin sisältö: nimi, päivä ja treenit. Päivä erottaa
    /// samannimiset versiot toisistaan.
    private func archivedRow(_ program: Program) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(program.title).font(.subheadline.weight(.medium))
            HStack(spacing: 4) {
                if let date = program.updatedDate {
                    Text(date, format: .dateTime.day().month().year())
                    Text("·")
                }
                Text(program.workoutNames).lineLimit(1)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var templatePicker: some View {
        List {
            if let error = model.errorMessage, draft == nil {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }

            // Nykyinen ohjelma ensin: useimmiten tänne tullaan muokkaamaan
            // olemassa olevaa, ei aloittamaan alusta.
            if let active = programs.activeProgram {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(active.title).font(.headline)
                        Text(active.workouts.map(\.name).joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)

                    Button {
                        editingProgramId = active.id
                        draft = .from(active)
                    } label: {
                        Label("Muokkaa ohjelmaa", systemImage: "pencil")
                    }
                } header: {
                    Text("Nykyinen ohjelma")
                } footer: {
                    // Luonnos kantaa yhden tavoitteen per liike, joten
                    // sarjakohtaiset erot tasoittuvat tallennuksessa. Parempi
                    // kertoa se etukäteen kuin antaa sen yllättää.
                    Text("Muokkaus säilyttää ohjelman ja tehdyt treenit. Kaikki liikkeen sarjat saavat saman tavoitteen, ja käynnissä olevaan treeniin muutokset eivät vaikuta.")
                }
            }

            if !programs.archivedPrograms.isEmpty {
                Section {
                    ForEach(programs.archivedPrograms) { program in
                        HStack {
                            Button {
                                editingProgramId = program.id
                                draft = .from(program)
                            } label: {
                                archivedRow(program)
                            }
                            .buttonStyle(.plain)

                            Menu {
                                Button {
                                    Task {
                                        if await programs.activate(program) { dismiss() }
                                    }
                                } label: {
                                    Label("Ota käyttöön", systemImage: "checkmark.circle")
                                }
                                Button {
                                    editingProgramId = program.id
                                    draft = .from(program)
                                } label: {
                                    Label("Muokkaa", systemImage: "pencil")
                                }
                                Button {
                                    editingProgramId = nil
                                    draft = .from(program)
                                } label: {
                                    Label("Käytä pohjana", systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) {
                                    pendingRemoval = program
                                } label: {
                                    Label("Poista", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .imageScale(.large)
                            }
                            .accessibilityLabel("Ohjelman \(program.title) toiminnot")
                        }
                    }
                } header: {
                    // Listassa on sekä käytöstä poistuneita että etukäteen
                    // valmisteltuja, joten "Aiemmat" olisi harhaanjohtava.
                    Text("Ei käytössä")
                } footer: {
                    Text("Tänne tallentuvat sekä etukäteen valmistellut ohjelmat että aiemmin käytössä olleet. Käyttöön otettu ohjelma korvaa nykyisen, ja nykyinen siirtyy tähän listaan. Tehdyt treenit säilyvät kaikissa tapauksissa.")
                }
            }

            Section {
                ForEach(model.templates) { template in
                    Button {
                        draft = .from(template)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(template.title).font(.headline)
                                Spacer()
                                Text("\(template.workouts.count) treeniä")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Text(template.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Valmis pohja")
            } footer: {
                Text("Pohjaa voi muokata vapaasti: liikkeitä voi vaihtaa, poistaa ja lisätä ennen tallennusta.")
            }

            Section {
                Button {
                    draft = .empty()
                } label: {
                    Label("Aloita tyhjästä", systemImage: "square.dashed")
                }
            }
        }
        .overlay { if model.isLoading && model.templates.isEmpty { ProgressView() } }
        .confirmationDialog(
            pendingRemoval.map { "Poistetaanko \($0.title)?" } ?? "",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Poista", role: .destructive) {
                if let program = pendingRemoval {
                    Task { _ = await programs.remove(program) }
                }
                pendingRemoval = nil
            }
            Button("Peruuta", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Ohjelma katoaa listalta pysyvästi. Sillä tehdyt treenit ja niiden sarjat säilyvät historiassa.")
        }
    }
}

@Observable
@MainActor
final class CreateProgramModel {
    private(set) var templates: [ProgramTemplate] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private var api: APIClient?
    private let cacheKey = "mobile-program-templates"

    func configure(auth: AuthManager) {
        if api == nil { api = APIClient(auth: auth) }
    }

    func load() async {
        guard let api else { return }
        if let cached = await ResponseCache.shared.read(cacheKey) {
            apply(cached)
        } else {
            isLoading = true
        }
        defer { isLoading = false }
        do {
            let data = try await api.get("/api/mobile/program-templates")
            await ResponseCache.shared.write(cacheKey, data: data)
            apply(data)
            errorMessage = nil
        } catch {
            if templates.isEmpty {
                errorMessage = "Ohjelmapohjien haku epäonnistui. Voit silti aloittaa tyhjästä."
            }
        }
    }

    /// Uusi ohjelma POST:lla, olemassa olevan muokkaus PATCH:lla — muokkaus ei
    /// saa arkistoida ohjelmaa eikä katkaista sen historiaa.
    /// Tallennus ja käyttöönotto ovat eri asioita: ohjelman voi valmistella
    /// etukäteen ja ottaa käyttöön vasta kun edellinen jakso on ajettu loppuun.
    func save(
        draft: ProgramDraft,
        athleteId: String,
        programId: String?,
        activate: Bool
    ) async -> Bool {
        guard let api else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            if let programId {
                // Muokkaus ei koske tilaan; käyttöönotto on oma pyyntönsä,
                // jotta arkistoidun muokkaus ei aktivoi sitä vahingossa.
                _ = try await api.patch(
                    "/api/programs/\(programId)",
                    body: CreateProgramRequest(draft: draft, athleteId: athleteId)
                )
                if activate {
                    struct StatusBody: Encodable { let status: String }
                    _ = try await api.post("/api/programs/\(programId)/status", body: StatusBody(status: "active"))
                }
            } else {
                _ = try await api.post(
                    "/api/programs",
                    body: CreateProgramRequest(
                        draft: draft,
                        athleteId: athleteId,
                        status: activate ? "active" : "archived"
                    )
                )
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Ohjelman tallennus epäonnistui — yritä uudelleen."
            return false
        }
    }

    private func apply(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(ProgramTemplatesResponse.self, from: data) else { return }
        templates = decoded.templates
    }
}
