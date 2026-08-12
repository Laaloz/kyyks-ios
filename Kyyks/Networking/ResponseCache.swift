import CryptoKit
import Foundation

/// Stale-while-revalidate-levyvälimuisti: viimeksi haettu vastaus näytetään
/// heti, tuore data haetaan taustalla. Käyttäjä ei koskaan tuijota tyhjää
/// ruutua datan takia, jonka hän on jo nähnyt.
actor ResponseCache {
    static let shared = ResponseCache()

    private let directory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appending(path: "api-cache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(name).json")
    }

    func read(_ key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    func write(_ key: String, data: Data) {
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    /// Kirjautumisen vaihtuessa vanhan käyttäjän data pois levyltä.
    func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
