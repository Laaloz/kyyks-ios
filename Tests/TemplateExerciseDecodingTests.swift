import Foundation
import Testing

@testable import Volu

/// Ohjelman liikkeet tulevat JSONB-sarakkeesta jota palvelin ei validoi.
/// Yksi vajaa rivi ei saa kaataa koko vastauksen dekoodausta — se piilottaisi
/// kaikki ohjelmat ilman virheilmoitusta.
struct TemplateExerciseDecodingTests {
    @Test func puuttuvatAvaimetSaavatOletukset() throws {
        let json = Data(#"{"exerciseId":"abc"}"#.utf8)
        let exercise = try JSONDecoder().decode(ProgramTemplate.TemplateExercise.self, from: json)
        #expect(exercise.exerciseName == "Liike")
        #expect(exercise.restSeconds == 90)
        #expect(exercise.targetRepsMin == 8)
        #expect(exercise.targetRepsMax == 12)
        #expect(exercise.setCount == 0)
    }

    @Test func olemassaOlevatArvotSailyvat() throws {
        let json = Data(#"{"exerciseId":"abc","exerciseName":"Kyykky","setCount":3,"targetRepsMin":5,"targetRepsMax":7,"restSeconds":120}"#.utf8)
        let exercise = try JSONDecoder().decode(ProgramTemplate.TemplateExercise.self, from: json)
        #expect(exercise.exerciseName == "Kyykky")
        #expect(exercise.restSeconds == 120)
        #expect(exercise.targetRepsMax == 7)
    }

    @Test func repsMaxEiJaaAlleMinin() throws {
        // Vajaa rivi jossa vain min: max ei saa oletuksella pudota minin alle.
        let json = Data(#"{"exerciseId":"abc","targetRepsMin":15}"#.utf8)
        let exercise = try JSONDecoder().decode(ProgramTemplate.TemplateExercise.self, from: json)
        #expect(exercise.targetRepsMax == 15)
    }
}
