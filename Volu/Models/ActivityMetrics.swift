import Foundation

/// Miten lajin matka esitetään — ja samalla onko matka lajille lainkaan
/// mielekäs. Jooga ja kiipeily eivät kulje matkaa, joten niiltä ei kysytä
/// eikä niille näytetä kenttää.
///
/// `pace` on aika matkaa kohti (juoksijan kieli, min/km), `speed` matka aikaa
/// kohti (pyöräilijän kieli, km/h). Ero ei ole tyylivalinta: kumpikin laji
/// ilmaisee vauhtinsa vakiintuneesti vain toisella tavalla, ja väärä yksikkö
/// on treenaajalle yhtä hyödytön kuin puuttuva luku.
///
/// Peilaa webin `lib/extra-activities.ts`:ää — sama data, sama malli.
enum ActivityDistanceMode {
    case none, pace, speed, swim
}

/// Matkan ja vauhdin esitys. Vauhtia ei tallenneta kantaan, koska se on
/// matkan ja keston osamäärä: tallennettu johdannainen vanhenisi hiljaa heti
/// kun kestoa korjataan.
enum ActivityMetrics {
    /// Matka lukuna: uinti metreinä, muut kilometreinä.
    static func distanceText(meters: Double?, mode: ActivityDistanceMode) -> String? {
        guard mode != .none, let meters, meters > 0, meters.isFinite else { return nil }

        // Uintimatkat ovat satoja metrejä, ja altaassa mitataan metreissä —
        // "0,8 km" olisi uimarille luettavampi metreinä.
        if mode == .swim { return "\(Int(meters.rounded())) m" }

        let km = meters / 1000
        // Alle 100 km yhdellä desimaalilla: 42,2 km on merkityksellinen luku,
        // mutta 128,4 km:n desimaali on kohinaa.
        let text = km < 100 ? String(format: "%.1f", km) : String(Int(km.rounded()))
        return "\(text.replacingOccurrences(of: ".", with: ",")) km"
    }

    static func paceText(meters: Double?, minutes: Double?, mode: ActivityDistanceMode) -> String? {
        guard mode != .none,
              let meters, let minutes,
              meters > 0, minutes > 0,
              meters.isFinite, minutes.isFinite
        else { return nil }

        if mode == .speed {
            let kmh = (meters / 1000) / (minutes / 60)
            return String(format: "%.1f", kmh).replacingOccurrences(of: ".", with: ",") + " km/h"
        }

        // Uinnissa vauhti ilmaistaan sataa metriä kohti, juoksussa kilometriä.
        let unitMeters: Double = mode == .swim ? 100 : 1000
        let minutesPerUnit = minutes / (meters / unitMeters)
        let totalSeconds = Int((minutesPerUnit * 60).rounded())
        let suffix = mode == .swim ? "/100 m" : "/km"
        return String(format: "%d.%02d %@", totalSeconds / 60, totalSeconds % 60, suffix)
    }

    /// Rivin lisätiedot järjestyksessä matka, vauhti, syke. Tyhjät jätetään
    /// pois, jotta rivi ei täyty väliviivoista silloin kun mittauksia ei ole.
    static func detailParts(
        meters: Double?,
        minutes: Double?,
        heartRate: Double?,
        mode: ActivityDistanceMode
    ) -> [String] {
        var parts: [String] = []
        if let distance = distanceText(meters: meters, mode: mode) { parts.append(distance) }
        if let pace = paceText(meters: meters, minutes: minutes, mode: mode) { parts.append(pace) }
        if let heartRate, heartRate > 0 { parts.append("\(Int(heartRate.rounded())) bpm") }
        return parts
    }
}
