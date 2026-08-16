import Foundation

/// Konfiguraatio Info.plistista (arvot injektoidaan Config/Config.xcconfigista).
/// Kaatuu heti käynnistyksessä jos arvot puuttuvat — parempi kuin hiljainen 401-suo.
enum AppConfig {
    static let supabaseURL: URL = url(for: "SupabaseURL")
    static let supabaseAnonKey: String = string(for: "SupabaseAnonKey")
    static let apiBaseURL: URL = url(for: "APIBaseURL")

    private static func string(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            fatalError("Puuttuva konfiguraatioavain: \(key). Kopioi Config/Config.example.xcconfig → Config.xcconfig ja aja xcodegen uudelleen.")
        }
        return value
    }

    private static func url(for key: String) -> URL {
        guard let url = URL(string: string(for: key)) else {
            fatalError("Virheellinen URL konfiguraatioavaimessa \(key)")
        }
        return url
    }
}
