import Foundation
import Testing

@testable import Volu

/// Levyvälimuistin pysyminen totuudessa kuittauksen jälkeen.
///
/// Vika jonka tämä estää: kuitattu sarja näkyi treeniin palatessa hetken
/// kuittaamattomana ja valitsi itsensä uudelleen vasta verkkohaun jälkeen.
/// Syy ei ollut kilpa-ajo vaan se, että välimuisti kertoi yhä kuittausta
/// edeltävää tilaa — ja juuri se näytetään ensin.
struct CachedSetLogPatchTests {
    private func response(done: Bool, reps: String = "null", load: String = "null") -> Data {
        Data("""
        {
          "workout": {"id": "w1", "title": "Työntävät"},
          "setLogs": [
            {"id": "s1", "done": \(done), "actualReps": \(reps), "actualLoad": \(load), "setLabel": "1"},
            {"id": "s2", "done": false, "actualReps": null, "actualLoad": null, "setLabel": "2"}
          ]
        }
        """.utf8)
    }

    private func rows(_ data: Data) -> [[String: Any]] {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return root?["setLogs"] as? [[String: Any]] ?? []
    }

    @Test func kirjoittaaKuittauksenValimuistiin() throws {
        let patch = PendingSetPatch(logId: "s1", actualReps: 8, actualLoad: 60, done: true)
        let updated = try #require(WorkoutModel.applyingPatch(patch, to: response(done: false)))

        let row = rows(updated).first { $0["id"] as? String == "s1" }
        #expect(row?["done"] as? Bool == true)
        #expect(row?["actualReps"] as? Double == 8)
        #expect(row?["actualLoad"] as? Double == 60)
    }

    @Test func eiKoskeMuihinSarjoihin() throws {
        let patch = PendingSetPatch(logId: "s1", actualReps: 8, actualLoad: nil, done: true)
        let updated = try #require(WorkoutModel.applyingPatch(patch, to: response(done: false)))

        let other = rows(updated).first { $0["id"] as? String == "s2" }
        #expect(other?["done"] as? Bool == false)
        #expect(other?["actualReps"] is NSNull)
    }

    @Test func sailyttaaMuunVastauksen() throws {
        // Välimuistiin kuuluu palvelimen vastaus sellaisenaan: jos muut kentät
        // katoaisivat, näkymä jäisi paluussa vajaaksi.
        let patch = PendingSetPatch(logId: "s1", actualReps: 8, actualLoad: nil, done: true)
        let updated = try #require(WorkoutModel.applyingPatch(patch, to: response(done: false)))

        let root = try #require((try? JSONSerialization.jsonObject(with: updated)) as? [String: Any])
        let workout = root["workout"] as? [String: Any]
        #expect(workout?["title"] as? String == "Työntävät")
        #expect(rows(updated).count == 2)
    }

    @Test func kuittauksenPerumineTallentuuMyos() throws {
        // Peruminen on yhtä lailla muutos: ilman tätä peruttu kuittaus palaisi
        // näkyviin välimuistista.
        let patch = PendingSetPatch(logId: "s1", actualReps: nil, actualLoad: nil, done: false)
        let updated = try #require(WorkoutModel.applyingPatch(patch, to: response(done: true, reps: "8", load: "60")))

        let row = rows(updated).first { $0["id"] as? String == "s1" }
        #expect(row?["done"] as? Bool == false)
        #expect(row?["actualReps"] is NSNull)
    }

    @Test func tuntematonRakenneJattaaValimuistinRauhaan() {
        let patch = PendingSetPatch(logId: "s1", actualReps: 8, actualLoad: nil, done: true)

        // Ei setLogs-taulukkoa, tuntematon sarja, ei JSONia lainkaan.
        #expect(WorkoutModel.applyingPatch(patch, to: Data(#"{"workout":{}}"#.utf8)) == nil)
        #expect(WorkoutModel.applyingPatch(
            PendingSetPatch(logId: "puuttuu", actualReps: nil, actualLoad: nil, done: true),
            to: response(done: false)
        ) == nil)
        #expect(WorkoutModel.applyingPatch(patch, to: Data("ei jsonia".utf8)) == nil)
    }
}
