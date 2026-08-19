import Foundation

/// Yksi lähettämätön sarjakirjaus.
///
/// Vain ne kentät jotka palvelimelle lähetetään — koko sarjariviä ei
/// tallenneta, koska tavoitteet ja liikkeen nimi tulevat aina palvelimelta
/// eikä niistä saa syntyä toista totuutta levylle.
struct PendingSetPatch: Codable, Equatable {
    let logId: String
    let actualReps: Double?
    let actualLoad: Double?
    let done: Bool
}

/// Lähettämättömät sarjakirjaukset levyllä, treeneittäin.
///
/// Miksi tämä ei ole `ResponseCache`ssa: se elää `.cachesDirectory`ssä, jonka
/// käyttöjärjestelmä saa tyhjentää milloin tahansa. Palvelimen vastaus on
/// haettavissa uudelleen, mutta käyttäjän kirjaama sarja ei ole missään
/// muualla ennen kuin se on lähetetty — se on dataa, ei välimuistia, ja
/// kuuluu Application Supportiin.
///
/// Tarve on konkreettinen: sarjan tallennus lähtee taustatehtävänä, ja jos
/// sovellus suljetaan tai kaatuu ennen kuin pyyntö on perillä, kirjaus katosi
/// jäljettömiin kesken treenin.
actor PendingSetStore {
    static let shared = PendingSetStore()

    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appending(path: "pending-sets", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(workoutId: String) -> URL {
        // Treenitunniste on UUID, joten se kelpaa tiedostonimeksi sellaisenaan.
        directory.appending(path: "\(workoutId).json")
    }

    func load(workoutId: String) -> [String: PendingSetPatch] {
        guard let data = try? Data(contentsOf: fileURL(workoutId: workoutId)) else { return [:] }
        return (try? JSONDecoder().decode([String: PendingSetPatch].self, from: data)) ?? [:]
    }

    func save(workoutId: String, patches: [String: PendingSetPatch]) {
        let url = fileURL(workoutId: workoutId)
        guard !patches.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(patches) else { return }
        // Sama suojaus kuin ResponseCachessa: kirjaukset ovat terveysdataa.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    /// Uloskirjautuminen: toisen käyttäjän kirjaukset eivät saa jäädä laitteelle.
    func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
