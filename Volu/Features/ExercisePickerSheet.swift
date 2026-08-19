import SwiftUI

/// Liikevalitsin vaihtoon ja lisäykseen: hakukenttä + tulokset
/// /api/exercises/search-endpointista (sama haku kuin webin ohjelmaeditorissa).
struct ExercisePickerSheet: View {
    let auth: AuthManager
    let mode: ExercisePickerMode
    let onSelect: (ExerciseSearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [ExerciseSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty && searchText.count >= 2 && !isSearching {
                    Text("Ei osumia haulla ”\(searchText)”")
                        .foregroundStyle(.secondary)
                } else if searchText.count < 2 {
                    Text("Hae liikettä nimellä (vähintään 2 merkkiä)")
                        .foregroundStyle(.secondary)
                }
                ForEach(results) { exercise in
                    Button {
                        onSelect(exercise)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .foregroundStyle(.primary)
                            if let detail = detailText(exercise) {
                                Text(detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Hae liikettä")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Peru") { dismiss() }
                }
            }
            .overlay(alignment: .top) { if isSearching { ProgressView().padding() } }
            .onChange(of: searchText) { _, term in
                search(term)
            }
        }
    }

    /// Kevyt debounce: edellinen haku perutaan, uusi lähtee 250 ms hiljaisuuden jälkeen.
    private func search(_ term: String) {
        searchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let data = try await APIClient(auth: auth).get("/api/exercises/search?q=\(APIClient.queryValue(trimmed))")
                guard !Task.isCancelled else { return }
                results = (try? JSONDecoder().decode(ExerciseSearchResponse.self, from: data))?.exercises ?? []
            } catch {
                guard !Task.isCancelled else { return }
                results = []
            }
        }
    }

    private func detailText(_ exercise: ExerciseSearchResult) -> String? {
        let parts = [exercise.category, exercise.equipment].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
